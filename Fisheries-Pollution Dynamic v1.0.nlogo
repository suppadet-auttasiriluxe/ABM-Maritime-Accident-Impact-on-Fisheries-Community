;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  ABM: Fishery–Pollution–Economy Interaction
;;  Version: v1.0
;;
;;   Model Description:
;;      1. Under usual condition fisherman sell caught-fish, pay money
;;      2. then go out randomly to fish, and fish all from patch
;;      3. then go back home and start again from 1.
;;
;;   Hypothesis:
;;      - When pollutant pollute the water, reproduction rate is hit, fish pop. go down
;;      - Fisherman have a hard time finding fish -> they go more into debt
;;      - There exist a timing that fisherman will start going into debt
;;      - There exist the best scenario of gov't intervention that alleviate the unprofitable situation of fisherman
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

patches-own [
  fish_population       ;; number of fish in this patch
  max_fish_pop          ;; maximum fish population in a patch
  pollution_amount      ;; pollution level (0–100)
  ;max_pollution        ;; maximum pollution value of a patch
  next_pollution        ;; technical: required for stable pollution spread dynamics
  is_land               ;; 1 = land, 0 = sea

  ;; Government Regulation Variables
  is_restricted            ;; 1 = fishing prohibited in this patch; 0 = not restricted, fisherman can fulfill his/her/their ✰fish desire✰
  is_restriction_boundary  ;; 1 = this patch is part of the visual violet boundary line; 0 = no line drawn even though the area is forbidden to aid visualisation
]

turtles-own [
  ; --- Economic Variables ---
  fish_caught           ;; fish already caught (on boat)
  money                 ;; current money available. minus indicate debt    ;; (starting at 100, same for everyone)
  last_profit           ;; profit from (fish_sold - expedition_cost) last trip

  ;; --- Spawn/Fish/Return Mechanism Variables ---
  home_patch            ;; the land patch where this fisherman spawned
  target_patch          ;; where the fisherman is currently moving towards
  current_state         ;; "at-home", "fishing"
]

globals [
  ; --- Adjustable Global Sliders ---
  ; fisherman_population    ;; How many fisherman is spawned at setup
  ; pollution_decay_rate    ;; How many pollution is lost per tick
  ; fish_reproduction_rate  ;; How many fish is born/patch; if no pollution is present
  ; fish_price              ;; How much a fish can be sold for
  ; expedition_cost         ;; cost per fishing trip (deduct upon departing)


  ; Directional Weighting
  dir_weights
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ENVIRONMENT SETUP
;;   Map detail:
;;   - origin = corner, bottom left
;;   - minpx to maxpx cor = 0 to 125
;;   - minpx to maxpy cor = 0 to 127
;;       - two right most column (x, 126 and x, 127) is set as beach
;;       - so that the rest of the patches on the left side (y =< 125)
;;           - in other words the sea span from 0,0 to 125,125 (square-shaped area of 126*126) with size of 15,876 patches
;;   - visualisation: size per each patch = 4 pixels
;;   - World doesn't wrap horizontally nor vertically (we assume this is a certain observed part of the sea that are connected to other unobserved part (but is there nonetheless))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all

  setup-map
  recolor
  setup-fishermen

  ;; For pollution movement due to wave and wind
  calculate-directional-weights
  ; print dir_weights   ;; for debugging purpose

  reset-ticks
end

to setup-map
  ask patches [
    ifelse pxcor > (max-pxcor - 2) [
      ;; rightmost 2 columns = land
      set is_land 1
      set pcolor yellow
      set fish_population 0
      set max_fish_pop 0
      set pollution_amount 0

      ;; initialising fishing restriction zone
      set is_restricted 0
      set is_restriction_boundary 0
    ]
    [
      ;; all other patches = sea
      set is_land 0
      set fish_population random 50
      set max_fish_pop 100
      set pollution_amount 0

      ;; initialising fishing restriction zone
      set is_restricted 0
      set is_restriction_boundary 0
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
    set money 50        ;; arbitrarily set starting amount based on the interview by how many days a fisherman could go by without having to fish
    set fish_caught 0

    ;; 3. Set at_home status to pay for expedition, and select target sea patch
    set current_state "at-home"
    set target_patch one-of patches with [is_land = 0]
  ]
end

;; For pollution movement due to wave and wind
; Report function calculates directional weights that sum to 1.0
; ns_drift: 10 -> more North, 1 -> more south, 5 -> Balanced
; ew_drift:  10 -> more East, 1 -> more West, 5 -> Balanced

to calculate-directional-weights
  ; Base weights for each direction before normalization
  let raw-n (ns_drift / 10)
  let raw-s (1 - raw-n)
  let raw-e (ew_drift / 10)
  let raw-w (1 - raw-e)

  ; Diagonal weights are geometric mean of their cardinal components, multiply by proportion of quadrant of a circle r=1 in a 1x1 square ~  0.7853981634 for better diffusion
  let raw-ne sqrt (raw-n * raw-e) * 0.7853981634
  let raw-se sqrt (raw-s * raw-e) * 0.7853981634
  let raw-sw sqrt (raw-s * raw-w) * 0.7853981634
  let raw-nw sqrt (raw-n * raw-w) * 0.7853981634

  ; Calculate total for normalization
  let total raw-n + raw-s + raw-e + raw-w + raw-ne + raw-se + raw-sw + raw-nw

  ; Normalize so all weights sum to 1.0 and put in global list
  set dir_weights (list (raw-n / total) (raw-s / total) (raw-e / total) (raw-w / total) (raw-ne / total) (raw-se / total) (raw-sw / total) (raw-nw / total))
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MAIN LOOP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if not any? turtles [ stop ]
  pollution-spread
  fish-reproduce
  fisherman-behavior
  diffuse fish_population 0.2   ;; to simulate fish movement in the sea and is set arbitrarily 0.2
  recolor
  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FISH POPULATION DYNAMICS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to fish-reproduce
  ask patches with [is_land = 0] [
    let growth (fish_reproduction_rate * (1 - pollution_amount / 100))   ;; reproduction rate is the inverse of pollution amount
    set fish_population fish_population + growth
       if fish_population < 0 [ set fish_population 0 ]
       if fish_population > max_fish_pop [ set fish_population max_fish_pop ]  ;; if fish exceed capacity, then don't increase more than cap
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; POLLUTION DYNAMICS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to pollution-spread
  ;; Define custom weights (must sum to 1.0)
  let center-w (1 - (pollution_spread / 100))
  ;; remaining spread must sum to
  let residual (pollution_spread / 100)

  ;; Pollution Calibration: assume that pollutant can travel from the left edge to the beach (18km) in 5 days such that there is sizable accumulation on the beach ~ 5,000,000 (about 100kg)?
  repeat 13 [

    ;; 1. Initialize buffer, so we don't create new pollution out of thin air.
    ask patches [set next_pollution 0]

    ;; 2. Calculate distribution
    ask patches with [pollution_amount > 0 AND is_land = 0] [
      let current_pollution pollution_amount

      ;; distribute spread directionally by weight
      if (pycor != max-pycor) [ask patch-at 0 1 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 0 dir_weights)]]      ; north
      if (pycor != min-pycor) [ask patch-at 0 -1 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 1 dir_weights)]]     ; south
      if (pxcor != max-pxcor) [ask patch-at 1 0 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 2 dir_weights)]]      ; east
      if (pxcor != min-pxcor) [ask patch-at -1 0 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 3 dir_weights)]]     ; west
      if (pycor != max-pycor AND pxcor != max-pxcor) [ask patch-at 1 1 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 4 dir_weights)]]     ; northeast
      if (pycor != min-pycor AND pxcor != max-pxcor) [ask patch-at 1 -1  [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 5 dir_weights)]]     ; southeast
      if (pycor != min-pycor AND pxcor != min-pxcor) [ask patch-at -1 -1 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 6 dir_weights)]]    ; southwest
      if (pycor != max-pycor AND pxcor != min-pxcor) [ask patch-at -1 1 [set next_pollution next_pollution + ([current_pollution] of myself * residual * item 7 dir_weights)]]     ; northwest

      set next_pollution (next_pollution + (current_pollution * center-w)) ; original patch
    ]

    ask patches with [next_pollution > 0 AND is_land = 0] [set pollution_amount next_pollution]
    ask patches with [is_land = 1] [set pollution_amount pollution_amount + next_pollution]
  ]

end

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

      ;; 3. CONSUME & CALCULATE PROFIT & UPDATE MONEY
      let profit (fish_income - expedition_cost)
      set money money + profit
      set last_profit profit

      ;; 4. VISUALIZE DEBT
      ifelse money < 0 [ set color red ] [ set color black ]

      ;; 5. START TRIP
      ;; Only target non-land patches that are NOT restricted
      set target_patch one-of patches with [is_land = 0 and is_restricted = 0]

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
  ask n-of 1 patches with [is_land = 0][
    set pollution_amount pollution_amount + pollution_per_pollute
    recolor
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VISUALIZATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to recolor
  ask patches with [is_land = 0] [

    ;; --- PROTECT OVERLAY ---
    ;; If this patch is a boundary line, do not recolor it.
    if is_restriction_boundary = 1 [ stop ]

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
    let pollution_ratio (pollution_amount / 100)
    ;let poll_ratio (pollution_amount / max_pollution)
    if pollution_ratio > 1 [ set pollution_ratio 1 ]

    ;; Darkness Multiplier:
    ;; If pollution_ratio is 0, multiplier is 1 (Original Color)
    ;; If pollution_ratio is 1, multiplier is 0 (Black)
    let darkness_multiplier (1 - pollution_ratio)

    ;; Apply multiplier to all channels except green so that polluted patch have green tint
    set pcolor rgb (r * darkness_multiplier) g (b * darkness_multiplier)
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GOVERNMENT RESTRICTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Button: "Impose Fishing Zone restriction"
to impose-restrictions
  ;; 1. Reset first to clean up any previous lines
  clear-restrictions-internal

  ;; 2. Identify all polluted sea patches; we only assume that nurdles presence start at 1 nurdle
  let polluted-patches patches with [is_land = 0 and pollution_amount > 1]

  if any? polluted-patches [
    ;; 3. Find the Boundaries
    let max-y max [pycor] of polluted-patches
    let min-y min [pycor] of polluted-patches

    ;; 4. Apply Restriction Zone
    ask patches with [is_land = 0 and pycor >= min-y and pycor <= max-y] [
      set is_restricted 1

      ;; 5. VISUALIZATION
      ;; Mark boundary lines and paint them violet
      if (pycor = max-y or pycor = min-y) [
        set is_restriction_boundary 1
        set pcolor violet
      ]
    ]
  ]
end

;; Button: "Clear Restriction"
to clear-restrictions
  clear-restrictions-internal
  recolor ;; Force immediate redraw to remove violet lines
end

;; Helper to avoid duplication
to clear-restrictions-internal
  ask patches [
    set is_restricted 0
    set is_restriction_boundary 0
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
545
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
125
1
1
1
ticks
30.0

BUTTON
764
23
849
91
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
856
59
929
92
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
553
428
742
461
NIL
Pollute
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
761
145
933
178
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
761
186
933
219
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
552
68
752
218
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
1162
491
1364
536
Total money/debt amount
sum [money] of turtles
2
1
11

MONITOR
949
489
1145
534
Latest Average Profit per Trip
sum [last_profit] of turtles / count turtles
2
1
11

PLOT
947
329
1147
479
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
1160
328
1360
478
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

PLOT
950
164
1357
314
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
761
227
933
260
fish_price
fish_price
0
1
0.63
0.01
1
NIL
HORIZONTAL

BUTTON
761
103
933
136
Default Value
set fisherman_population 3700\nset fish_reproduction_rate 3.0\nset fish_price 0.63\nset expedition_cost 11.26\nset pollution_per_pollute 1300000000\nset pollution_spread 66\nset ns_drift 5\nset ew_drift 7
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
552
471
742
504
pollution_per_pollute
pollution_per_pollute
0
1300000000
1.3E9
100000000
1
NIL
HORIZONTAL

SLIDER
762
429
913
462
ns_drift
ns_drift
0
10
5.0
1
1
North-ness
HORIZONTAL

SLIDER
762
470
914
503
ew_drift
ew_drift
0
10
7.0
1
1
East-ness
HORIZONTAL

SLIDER
553
512
743
545
pollution_spread
pollution_spread
0
100
66.0
1
1
%
HORIZONTAL

MONITOR
555
370
745
415
Total Pollution (unit: nurdles)
sum [pollution_amount] of patches
0
1
11

MONITOR
760
370
911
415
Pollution on Beach
round sum [pollution_amount] of patches with [is_land = 1]
0
1
11

BUTTON
762
513
915
546
Press to Confirm New Drift
calculate-directional-weights
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
856
23
928
56
NIL
go
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
761
269
933
302
expedition_cost
expedition_cost
0
50
11.26
0.1
1
NIL
HORIZONTAL

BUTTON
1013
119
1175
152
 Impose Fishing Zone Restriction
impose-restrictions
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
1183
119
1284
152
Remove Restriction
clear-restrictions
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
563
20
754
85
=========================\n===    ENVIRONMENT SETUP       ===\n=========================
10
0.0
1

TEXTBOX
597
322
941
358
======================================\n===     POLLUTION AMOUNT AND DRIFT CONTROL     ===\n======================================
10
0.0
1

TEXTBOX
1019
31
1298
67
======================================\n===  GOVERNMENT MONITOR AND ACTION CENTER   ===\n======================================
10
0.0
1

BUTTON
990
77
1118
110
Pay Compensation
ask turtles [set money money + compensation]
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
1133
76
1305
109
compensation
compensation
18
140
18.0
1
1
USD
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

1 km = 7 patch lengths
Total area is 128x126 patches 
The ocean is 126x126 patches (18km x 18km)
Coast is 2x126 patches (.28km x 18 km)

X-Press Pearl 26,000 kg of pellets (3 containers) ~ 1,300,000,000 pellets

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
