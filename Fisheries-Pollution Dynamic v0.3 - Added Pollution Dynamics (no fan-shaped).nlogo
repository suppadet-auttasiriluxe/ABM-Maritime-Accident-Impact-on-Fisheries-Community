;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  ABM: Fishery–Pollution–Economy Interaction Prototype
;;  Version: v0.2 - Introducing Debt system, Removed turtles_dies, Overhaul fisherman-behavior (2 ticks/day)
;;
;;   Model Description:
;;      1. Under usual condition fisherman sell caught-fish, pay money [?WHAT AMOUNT?]
;;      2. then go out randomly to fish, and fish all [or RANDOMIZED?] from patch
;;      3. then go back home and start again from 1.
;;
;;   Hypothesis:
;;      - When pollutant pollute the water, reproduction rate is hit, fish pop. go down
;;      - Fisherman have a hard time finding fish -> they go more into debt
;;
;;   What to do in the next version?
;;      - IMPROVE PROCEDURE
;;         - setup            ;; - starting money should be [?HETEROGENOUS?]
;;         - fish-reproduce      ;; - Fish reproduction mechanics have to be limited by i.) prior pop. amount, ii.) pollution amount [e.g. see logictical growth, pollution effect]
;;         - pollute          ;; - how much should be the starting pollution?
;;         - pollution-spread ;; - should only run once every 2 ticks to simulate 1-day   ;; or not we could argue that they spread 2 per day
;;                               - for some reason the world edge is not really heavily pollute, I think we might have to account for when neighbor_count < 4
;;
;;      - IMPROVE VARIABLES   (to be true to real life)
;;         - max_fish_pop                ;; fish can't just keep growing
;;         - fish_reproduction_rate      ;; rate must be true to real life
;;         - ...
;;
;;      - INTRODUCE 3 ECON. POLICIES
;;         - ...
;;         - ...
;;         - ...
;;         - ...
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

patches-own [
  fish_population       ;; number of fish in this patch
  max_fish_pop          ;; maximum fish population in a patch
  pollution_amount      ;; pollution level (0–100)
  ;max_pollution         ;; maximum pollution value of a patch
  next_pollution        ;; technical: required for stable pollution spread dynamics
  is_land               ;; 1 = land, 0 = sea
]

turtles-own [
  ; --- Economic Variables ---
  ; [SHOULD MODIFY LATER: V2] rate_of_fishing       ;; max capacity to fish per attempt    ;; [now fish everything from a patch; or randomized 70-100% e.g.]
  ; [REMOVED] desired_fish_amount   ;; how many fish needed to be satisfied before going back home ;; [now fish everything from a patch]
  ; [REMOVED] fishing_time          ;; how long does it takes to fish      ;; [now fish instantly]
  expedition_cost       ;; cost per fishing trip (deduct upon departing)   ;; (fixed at 3)
  fish_caught           ;; fish already caught (on boat)
  money                 ;; current money available. minus indicate debt    ;; (starting at 100, same for everyone)
  last_profit                ;; profit from (fish_sold - expedition_cost) last trip

  ;; --- Spawn/Fish/Return Mechanism Variables ---
  home_patch            ;; the land patch where this fisherman spawned
  target_patch          ;; where the fisherman is currently moving towards
  current_state         ;; "at-home", "fishing"
]

; globals [
  ; --- Adjustable Global Sliders ---
  ; fisherman_population    ;; How many fisherman is spawned at setup
  ; pollution_decay_rate    ;; How many pollution is lost per tick
  ; fish_reproduction_rate  ;; How many fish is born/patch; if no pollution is present   ;; (default at 3.00)
  ; fish_price              ;; How much a fish can be sold for                           ;; (default at 0.35)
; ]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETUP
;;   Map detail:
;;   - origin = corner, bottom left
;;   - maxpx/py cor = 0,127
;;   - patch size = 4 pixels
;;   - World doesn't wrap horizontally nor vertically
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all

  setup-map
  recolor
  setup-fishermen

  set fish_price 0.35
  reset-ticks
end

to setup-map
  ask patches [
    ifelse pxcor > (max-pxcor - 16) [
      ;; rightmost 16 columns = land
      set is_land 1
      set pcolor yellow
      set fish_population 0
      set max_fish_pop 0
      set pollution_amount 0
    ]
    [
      ;; all other patches = sea
      set is_land 0
      set fish_population random 50
      set max_fish_pop 100
      set pollution_amount 0
    ]
  ]
end

to setup-fishermen
  create-turtles fisherman_population [
    set color black
    set size 1

    ;; 1. Spawn on random land patch & Set Home
    let spawn_patch one-of patches with [is_land = 1]
    if spawn_patch != nobody [
      move-to spawn_patch
      set home_patch spawn_patch
    ]

    ;; 2. Initialize Variables
    set expedition_cost 3
    set money 100
    set fish_caught 0

    ;; 3. Set at_home status to pay for expedition, and select target sea patch
    set current_state "at-home"
    set target_patch one-of patches with [is_land = 0]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAIN LOOP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if not any? turtles [ stop ]
  pollution-spread
  pollution-decay
  fish-reproduce
  fisherman-behavior
  recolor
  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECOLOGICAL DYNAMICS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to fish-reproduce
  ask patches with [is_land = 0] [
    let growth (fish_reproduction_rate * (1 - pollution_amount / 100))   ;; reproduction rate is the inverse of pollution amount
    set fish_population fish_population + growth
       if fish_population < 0 [ set fish_population 0 ]
       if fish_population > max_fish_pop [ set fish_population max_fish_pop ]  ;; if fish exceed capacity, then don't increase more than cap
  ]
end

to pollution-spread
;; pollution spread to neighbor4
;; imagine a single patch of 8
  ;; 100 pollution start at the middle
  ;; 100/5      = 20 pollution remains in the middle.
  ;; the rest     20*4 pollution spread to 4 patch on Nth-Est-Wst-Sth

  ;; 1. Initialize buffer, so we don't create new pollution out of thin air.
  ask patches [ set next_pollution 0 ]

  ;; 2. Calculate distribution
  ask patches with [pollution_amount > 0 and is_land = 0] [
    let total_pollution pollution_amount
    let share total_pollution / 5

    ;; A. Keep 1 share for myself
    set next_pollution next_pollution + share

    ;; B. Give 4 shares to neighbors
    ask neighbors4 [
      ifelse is_land = 0 [
        ;; If Sea: Neighbor takes the share
        set next_pollution next_pollution + share
      ]
      [
        ;; If Land: Pollution "bounces" back to me
        ask myself [
          set next_pollution next_pollution + share
        ]
      ]
    ]
    ;; C. Handle World Edges
    ;; If we are at the edge of the map, neighbor_count < 4.
    ;; The shares intended for the void should bounce back to me.
    ;if neighbor_count < 4 [
       ;let lost_shares (4 - neighbor_count)
       ;set next_pollution next_pollution + (share * lost_shares)
    ;]
   ;]
  ]

  ;; 3. Apply the calculated values
  ask patches with [is_land = 0] [
    set pollution_amount next_pollution
  ]
end

to pollution-decay
  ask patches with [pollution_amount > 0 and is_land = 0] [

    ;; Standard Decay
    let decay_amount pollution_decay_rate

    ;; BONUS: Fast Decay near Land (Coastal Cleanup / Dispersion)
    ;; Check if any neighbor is land
    if any? neighbors4 with [is_land = 1] [
      set decay_amount decay_amount * 3  ;; Decay 3x faster near coast
    ]

    set pollution_amount pollution_amount - decay_amount

    ;; Prevent negative pollution
    if pollution_amount < 0 [ set pollution_amount 0 ]
  ]
end

; to pollution-decay-land
;  ask patches with [pollution_amount > 0 and is_land = 0 and is_adjacent_to_land = 1 (or patch xycor = x,17) ] [      ;; FIX PSEUDOCODE ON THIS LINE TO MAKE POLLUTION DECAY FASTER FOR PATCH ADJACENT TO LAND
;    set pollution_amount pollution_amount - pollution_decay_rate
;    if pollution_amount < 0 [ set pollution_amount 0 ]
;   ]
; end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FISHERMAN BEHAVIOR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to fisherman-behavior
  ask turtles [
    ifelse current_state = "at_home"
    [
      ;; --- STATE 1: AT HOME ---

      ;; 1. MOVE TO HOME
      ;; Used is-patch? to prevent "Move-to 0" error if home_patch is not set
      if is-patch? home_patch [ move-to home_patch ]

      ;; 2. SELL FISH
      let fish_income (fish_caught * fish_price)
      set fish_caught 0

      ;; 3. CALCULATE PROFIT & UPDATE MONEY
      let profit (fish_income - expedition_cost)
      set money money + profit
      set last_profit profit

      ;; 4. VISUALIZE DEBT
      ifelse money < 0 [ set color red ] [ set color black ]

      ;; 5. START TRIP
      set target_patch one-of patches with [is_land = 0]

      ;; 6. Change state
      set current_state "fishing"
    ]
    [
      ;; --- STATE 2: FISHING ---

      ;; 1. Move to random target patch
      ;; Used is-patch? to prevent "Move-to 0" error
      if is-patch? target_patch [
        move-to target_patch

        ;; 2. Catch ALL fish in that patch
        let actual_catch 0
        ask patch-here [
          set actual_catch fish_population
          set fish_population 0
        ]

        ;; 3. Update inventory
        set fish_caught actual_catch
      ]

      ;; 4. RESTART CYCLE
      set current_state "at_home"
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SHOCK INDUCING (I.E. MARITIME ACCIDENT)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to pollute
  ask n-of 1 patches with [is_land = 0] [                       ;; pollute 200 patches (~1.22%) out of 128*128 = 16,384 patches
    set pollution_amount pollution_amount + pollution_per_pollute
    recolor
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VISUALIZATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to recolor
  ask patches with [is_land = 0] [

    ;; --- 1. BASE COLOR (White -> Blue based on Fish) ---
    ;; Fish Ratio: 0 = No Fish, 1 = Max Fish
    let fish_ratio (fish_population / max_fish_pop)

    ;; Calculate Base Channels
    ;; 0 Fish: (255, 255, 255) = White
    ;; Max Fish: (0, 0, 255) = Blue
    let base_val 255 * (1 - fish_ratio)

    let r base_val
    let g base_val
    let b 255

    ;; --- 2. APPLY DARKENING (Based on Pollution) ---
    ;; Pollution Ratio: 0 = Clean, 1 = Max Pollution
    let poll_ratio (pollution_amount / 100)
    ;let poll_ratio (pollution_amount / max_pollution)
    if poll_ratio > 1 [ set poll_ratio 1 ]

    ;; Darkness Multiplier:
    ;; If poll_ratio is 0, mult is 1 (Original Color)
    ;; If poll_ratio is 1, mult is 0 (Black)
    let darkness_mult (1 - poll_ratio)

    ;; Apply multiplier to all channels except green so that polluted patch have green tint
    set pcolor rgb (r * darkness_mult) g (b * darkness_mult)
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; END OF MODEL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
@#$#@#$#@
GRAPHICS-WINDOW
18
32
538
553
-1
-1
4.0
1
10
1
1
1
0
0
0
1
0
127
0
127
0
0
1
ticks
30.0

BUTTON
574
34
637
67
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
654
34
717
67
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
760
36
857
69
NIL
pollute
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
563
123
735
156
fisherman_population
fisherman_population
0
10000
3700.0
1
1
NIL
HORIZONTAL

SLIDER
563
164
735
197
pollution_decay_rate
pollution_decay_rate
0
0.1
0.01
0.01
1
NIL
HORIZONTAL

SLIDER
563
205
735
238
fish_reproduction_rate
fish_reproduction_rate
0
10
3.0
0.1
1
NIL
HORIZONTAL

PLOT
757
94
957
244
Total fish population
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [fish_population] of patches"

MONITOR
784
453
986
498
NIL
Total money/debt amount
17
1
11

MONITOR
567
451
763
496
Latest Average Profit per Trip
sum [last_profit] of turtles / count turtles
2
1
11

PLOT
565
291
765
441
Average Profit per Trip
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (sum [last_profit] of turtles) / count turtles"

PLOT
782
290
982
440
Total money/debt amount
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [money] of turtles"

SWITCH
1217
38
1369
71
Intervention_Policy
Intervention_Policy
1
1
-1000

PLOT
980
94
1372
244
Population of Profitable vs. In-debt Fisherman
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"profitable" 1.0 0 -16777216 true "" "plot count turtles with [money >= 0]"
"in-debt" 1.0 0 -2674135 true "" "plot count turtles with [money < 0]"

SLIDER
563
246
735
279
fish_price
fish_price
0
1
0.35
0.01
1
NIL
HORIZONTAL

BUTTON
563
81
735
114
Default Value
set fisherman_population 3700\nset pollution_decay_rate 0.01\nset fish_reproduction_rate 3.0\nset fish_price 0.35
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
866
35
1056
68
pollution_per_pollute
pollution_per_pollute
0
10000000
1.0E7
100000
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
