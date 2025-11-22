# ABM Maritime Accident Impact on Fisheries Community
For Class of Ecological Challenges as a part of EPOG-JM Master's Degree (cohort 2024-2026)

# Version: v0.1 - Proof-of-Concept Draft - Actors & Mechanics are there but dynamics doesn't work yet :(

   ## Model Description:
      - Under usual condition fisherman pay money, go out to fish, and at least fish until he/she is satisfied
      - then come back to sell. If they are profitable, they do it again
      - When they have enough money (financial freedom), they exit happy_end
      - If they run out of money, they exit bad_end.
      - We will compare the happy_end / bad_end ratio

   ## Hypothesis:
      - When pollutant pollute the water, reproduction rate is hit, fish pop. go down
      - Fisherman have a hard time finding fish -> they go bankrupt

   ## What to do in the next version?
      - **IMPROVE PROCEDURE**
         - setup            ;; Fish spawned have to be more realistic (should spawned in school not randomly)
                            ;; Also, right now there are too many fishes available for fisherman
         - fish-reproduce      ;; - Fish reproduction mechanics have to be limited by i.) prior pop. amount, ii.) pollution amount [e.g. see logictical growth, pollution effect]
                               ;; - there are too many fishes for fisherman even though fish_reproduction_rate is set = 0;
                               ;; - pollution only decrease reproduction rate, but doesn't kill fish
         ***- fisherman-behavior  ;; Fisherman pay once but can keep finding fish forever until they reach the desired amount
                                  ;; Fix by either:
                                  ;; - remove the movement (everything happen in a tick, we use the model to calculate); we will not see nice animation though :(
                                  ;; - keep the movement; but we have to introduce fuel / limit to how much fisherman can travel per expedition_cost; once that is reached they have to return regardless of desired_fish_amount
         - pollution-spread    ;; right now when you press pollute, pollution keep expanding with no end when pollution_decay_rate > 20
      - **IMPROVE VARIABLES**   (to be true to real life)
         - max_fish_pop                ;; fish can't just keep growing
         - fish_reproduction_rate      ;; rate must be true to real life
         - ...
      - **INTRODUCE INVESTMENT/EQUIPMENT**
         - radar: always go to patch with highest fish
         - engine: increase move speed / reduce expedition cost (better fuel efficiency)
         - trawler: reduce fishing time
         - fuel tank: bigger fuel tank = more max_travel_distance
      - **INTRODUCE MARKET DYNAMICS**
         - fish_supply         ;; how much fish is in the market
         - fish_demand_static  ;; how many fish is consume/tick
         - fish_price          ;; have to be dynamics depends on current fish_supply: if oversupply => fish price drop, and vice-versa
      - **INTRODUCE JOB MARKET**
         - People can consider becoming fisherman / go to factory ??
      - **INTRODUCE HEALTH ASPECT??**
