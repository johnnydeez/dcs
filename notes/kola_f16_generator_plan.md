# Kola F-16 Randomized Mission Generator — Planning Doc

> **Status:** v1 — stages 1–2 (territory + base defenses at all 37 airfields) + stage 3a (SAM network, 100 zones) + world inputs running in DCS (2026-09-23); zone classes in `data/zones.lua`, stage 3b (fixed ground targets) and 3c (target catalog) running in DCS for both coalitions, full start-up spawn ~7 s (2026-09-24); stage 4 first part (one Red supply convoy) and stages 5–6 first pass (strike and airfield strike air tasking for both coalitions, threat-aware routing) running in DCS (2026-09-25). Planning sections §1–10 are the concept; §11, "Where we are" and the "as built" sections are the spec.
> Companion to the Syria project (`notes/notes.md`). Open questions are marked **[Q]** — answer them inline and the doc becomes the spec.
>
> **Layout:** *Where we are* (pick up here) → *Next session* candidates → *Base defenses / SAM sites / Fixed ground targets — as built* → *Plan* (§1–10, concept and research) → *Architecture* (§11, code structure decisions).
>
> **Naming rule:** name things by what they are or what they do, in full words. No abbreviations in code names: `mobile_anti_aircraft_guns`, not `aaa_sp`; `shoulder_launched_missile_teams`, not `manpads_team`. Each name answers one question. Prose may still use common terms (AAA, SHORAD, MANPADS).
>
> **Working rules:** commits are always done by John, on his own schedule — never ask about or perform a commit. After any edit under `kola_f16\`, copy the tree to `Saved Games\DCS\Scripts\kola_f16\` immediately; DCS is the only test environment.

---

## Where we are — pick up here  *(2026-09-25, end of session 6 — convoy and ground attack air tasking running in DCS)*

**Status: stages 1–6 (first passes) run in DCS.**
- **Run order:** Boot → gather → `RollTerritory` → `PlanBaseDefenses` → `PlanSamSites` → `PlanFixedGroundTargets` → `PlanConvoys` → `CatalogTargets` → `PlanAirTasking` → plan dump → `Territory.apply` → spawn (**static objects first**, then base defenses, SAM sites, fixed-target units, convoys) → `ScheduleAirTaskingOrders` (flights spawn on the mission clock) → draw + on-screen summary.
- **Last DCS runs (John: "looks good"):**
  - start-up spawn ~7 s (212 static objects in 0.5 s; ~830 units);
  - 12 missions planned in 0.6 s, all routed; flights spawn on time with 0 type mismatches;
  - Su-24Ms dropped their bombs, not very accurately.
- **Not yet seen in a log:** flights landing and being removed. No logged run lasted past the first return (~1 h 17 min); grep `landed — removing it`.
- **Development setting:** no player slot in the mission. A player aircraft in the world slows every spawn (see §1.1 "Execution timing"); the final design is dynamic spawn after "Init complete".
- **Spawners, one per kind of DCS object (John):** `SpawnStaticObjects`, `SpawnGroundGroups` (optional fields such as `route`), `SpawnAircraftGroups`.

### Session 6 details (2026-09-25)

- **Performance flights** (John, F-16): baseline under "Unit budget" below. Result: no mission changes, graphics settings only; re-test once AI flights and moving units land.
- **Stage 4, first part: one Red supply convoy per mission** (`stages/plan_convoys.lua`, `PlanConvoys` → `plan.convoys`). Ported from the Syria `convoy_setup.lua`, split into the pipeline:
  - **Data:** `data/convoy_recipes.lua` holds `CONVOY_RECIPE.supply_convoy` and `CONVOYS_PER_COALITION` (Red 1, Blue 0). The column is 1–2 armored personnel carriers at the ends, 4–8 cargo trucks + 1–2 fuel trucks (critical), 1–2 gun trucks mixed in, and 0–1 Shilka/Strela-10 at the tail: 7–14 vehicles. No infantry (it would slow the column to walking pace). New Red roles in `COALITION_ROSTER`: `cargo_truck`, `fuel_truck`, `armored_personnel_carrier`, `mobile_air_defense_vehicle`.
  - **Route:** a Red base pair 60–175 km apart. It prefers rear/mid → front, then any base → one closer to the enemy, shuffled. Start and parking are road points 2.5–5 km outside each airfield, clear of runways, zones and anything planned. `land.findPathOnRoads` proves a road connects them and measures it (≤ 250 km); a pair without one is skipped (up to 8 tried). Vehicles stand in a column along the first stretch of the road path, 25 m apart. There is a waypoint every 20 km, "On Road" at ~50 km/h, and the convoy parks at the last one.
  - **Ids:** `CONVOY_<FROM CODE>_supply_convoy_<n>`.
  - **One ground spawner** (John: spawners split by static / ground / air; no per-feature spawners): `SpawnGroundGroups` takes an optional `route` field. Offline, the other 215 groups produce byte-identical `addGroup` tables.
  - **Catalog:** category `mobile_ground_target`, mission type `interdiction` (new); the trucks are critical, fraction 0.5. The entry carries `from_base`, `to_base`, `waypoints`, `speed_mps`, `travel_minutes`, so tasking can work out where the convoy is at a given time. `CatalogTargets` now runs after stage 4.
  - **Map:** `consumers/draw_convoys.lua` (`CONFIG.DRAW_CONVOYS`, mark ids 40000+) draws a dashed route line plus start and parking labels.
- **Offline** (100 rolls, road calls stubbed): a convoy every roll, 0 check failures; 24 % of routes go to a base closer to the enemy rather than a `front` one. Each roll logs "BLUE has no targets for: interdiction" (true until Blue gets convoys).
- **Verified in DCS (John):** the convoy works. Spawn times had grown because a player F-16 slot was in the mission (see §1.1 "Execution timing"); the slot is removed during development.
- **Stages 5–6, first pass: ground attack air tasking orders for both coalitions** (`stages/plan_air_tasking.lua`, `PlanAirTasking` → `plan.air_tasking_orders[coalition].missions`). Offline only so far.
  - **Built:** `strike` and `airfield_strike`, one flight per mission, no escorts or suppression packages (next).
  - **Stubbed:** `suppression_of_air_defenses`, `destruction_of_air_defenses`, `interdiction`, `close_air_support` (`built = false` in `data/air_tasking.lua`). Their attack method, rosters and loadouts are already in the data.
  - **Volume (John):** Red 4–6 and Blue 6–8 missions per 6-hour window, at most 3 flights per coalition airborne at once. Each coalition's first flight starts at T+2 min, so there's something to watch early.
  - **Per mission:** mission type (weighted) → aircraft from `COALITION_AIRCRAFT` → an enemy catalog target within its combat radius from a base it can launch from (weighted by value, never hit twice) → one of the 3 nearest fitting bases → a start time under the airborne cap → parking spots free at that time (not on parked-aircraft statics) → route (takeoff, departure, ingress, target, egress, landing) and attack tasks.
  - **Not tied to the parked-aircraft rosters** (John: it would limit launch bases and make tasking harder).
  - **Ids:** `MSN<number>` (Blue 2001+, Red 5001+) is the DCS group name.
  - **Making the AI attack** (researched from DCS Liberation's code and the ED forums):
    - one `Bombing` task per critical object at its position, on the ingress waypoint (search tasks never pick static objects); drop everything when there is a single point;
    - heavy bombers (Tu-22M3) get one `Bombing` at the centre, bombs only;
    - on the first waypoint: rules of engagement open fire (not weapons free, so the flight stays on its target), evade fire, return at bingo fuel, no jettisoning, gun emptied (the AI otherwise strafes a Tor once the bombs are gone);
    - loadouts carry one kind of air-to-ground weapon each;
    - recorded for later: `EngageGroup` for anti-radiation missiles (waits for the radar to emit), `AttackGroup` for SAM sites and convoys, `BombingRunway` ignores laser-guided bombs.
  - **Loadouts:** `tools/aircraft_loadouts.py` generates `data/aircraft_loadouts.lua` from ED's UnitPayloads, DCS Liberation's AI loadouts (local reference clone at `C:\Users\johnk\Git\dcs_liberation`, like pydcs) and Syria's three proven CAS loadouts (`tools/aircraft_loadouts_by_hand.json`). The choice per type and mission type is in `tools/aircraft_loadout_choices.json`; every CLSID is checked against `aircraft_pylons.lua`. `--list <type>` shows the options with weapon names.
  - **Consumers:**
    - `consumers/spawn_aircraft_groups.lua` (`SpawnAircraftGroups`): the third and last spawner, one per kind of DCS object;
    - `consumers/schedule_air_tasking_orders.lua`: spawns each flight at its start time and removes aircraft 3 min after they land;
    - `consumers/draw_air_tasking_orders.lua`: route lines and target labels, behind `DRAW_AIR_TASKING_ORDERS`.
  - **Offline** (100 rolls): Red 4.8 and Blue 7.0 missions per roll, 0 unplanned; 0 flights beyond reach, over the airborne cap, on a clashing or static-occupied spot, or sent to a target twice.
  - **To verify in DCS:**
    - that flights start hot from their parking spots;
    - that they actually drop on static objects;
    - how the Tu-22M3 carpet run looks;
    - whether they land and get removed.

    Grep `MSN` in `dcs.log`.
  - **First DCS run (John): works "pretty well".** Su-24Ms dropped their bombs, not very accurately. Two problems:
    - flights overflew easily avoidable enemy SAMs;
    - Su-24Ms crossed the map at 9,800 ft. Cause: the attack altitude sat on the ingress waypoint, and the AI descends toward the next waypoint's altitude from the previous one, so the whole transit sank toward attack height.
  - **Fixed: altitudes and threat routing** (`lib/threat_routing.lua`, `AIR_ROUTING` in `data/air_tasking.lua`).
    - **Cruise ≥ 7,500 m (~25k ft) for every attack flight:** above guns, shoulder-launched missiles and short-range SAMs (SA-8, SA-15, Roland reach ~5–6 km). Cruise altitude is held until a descent point (5 km per km of drop, ≥ 10 km) before the ingress.
    - **Attack altitude per aircraft and mission type** (`attack_altitude_m` in the profiles), realistic for the payload whatever the threat (John): unguided FAB-500 5,000 m, RBK cluster 3,000 m, JDAMs 7,000–9,000 m, Tu-22M3 carpet 8,000 m.
    - **Routed around what can't be overflown:** enemy medium- and long-range SAM rings (+10 km) and enemy Pantsir / Tor-M2 base-defense groups (+5 km). Every fixed enemy site is treated as known (John agreed).
    - **Method:** A* on a 10 km grid, where cells inside rings cost 25× per ring but aren't forbidden, then smoothed to a few waypoints. If the way around is > 1.6× direct or out of reach, the flight goes straight through (John agreed).
    - **Still crossing a ring** → `needs_suppression = true`, with the ids in `suppression_threats`: the hook for SEAD/DEAD escorts. Shown on the F10 label.
  - **Offline, 60 rolls:**
    - 86 % of direct routes would cross a ring and 72 % of flown routes still do. About 4 in 10 flagged missions cross only the rings around the target itself. The rest are mostly the front belt of SA-11 / NASAMS rings (a continuous wall at 45 km radius) and the stacked rings of the Kola core; 8 % of ways around were rejected as too long.
    - 0 transit waypoints below 7,500 m, 0 unflagged crossings, ~0.7 s per roll to plan.
    - **Takeaway:** most attack missions need suppression, which is what SEAD/DEAD packages are for, next.

## Where we were — end of session 5  *(2026-09-24 — zone classes, fixed ground targets and the target catalog running in DCS)*

**Status: stages 1–3c run in DCS.** Boot → gather → `RollTerritory` → `PlanBaseDefenses` → `PlanSamSites` → `PlanFixedGroundTargets` → `CatalogTargets` → plan dump → `Territory.apply` → spawn: **static objects first**, then base defenses, SAM sites, fixed-target units → draw (base defenses, SAM sites, fixed ground targets) + on-screen summary.
- **Last DCS run:** 250 static objects in 0.5 s, then ~860 units in ~5 s. 0 failed, 0 type mismatches.
- **Catalog:** 107 targets. It holds every SAM / early-warning site and every fixed ground target site of the roll, none missing, each with critical names, mission types, `covered_by` and `defended_base`.
- **John's verdict** on the parked-aircraft groups: "looks pretty good". The session ends at a good stopping point.

**Session 5 (2026-09-24):**
- **Zone classes (offline, part of the zone workflow).** `kola_f16/survey/survey_zone_terrain.lua` runs only in `khola_ground_zones.miz` (trigger: ONCE → TIME MORE 1 → DO SCRIPT `dofile(lfs.writedir() .. "Scripts\\kola_f16\\survey\\survey_zone_terrain.lua")`). It measures the DCS terrain around every zone and writes `Saved Games\DCS\kola_zone_terrain.lua`. `python tools/miz_zones.py "<khola_ground_zones.miz>"` then writes the classes into each `data/zones.lua` entry: `size`, `airfield_distance`, `ground`, `terrain`, `road_access`, `railway_access`, `water`, `radar_view`, `settlement`, `prepared_sam_position`. It also writes `surveyed`, a `measured` line, and reports prepared SAM positions and every map object type found. Thresholds and object categories (`CLASS_THRESHOLDS`, `OBJECT_CATEGORIES`) live in the tool. Workflow after drawing zones: save the .miz → fly it once → run the tool. Real data 2026-09-24: 7 zones on the map's own SAM revetments (the Kilpyavr zones, the Ivalo pair, `ZONE_ALAK_074_013` just outside); `settlement` still counts airfield buildings (18 of 29 airfield zones read "town") — accepted for now. SAM results verified byte-identical with the new `zones.lua` (30 seeds) and in a DCS run.
- **SAM spawning left untouched on purpose** (John: "we just got that working the way we wanted"). Later stages only consume what SAM leaves (`plan.sam_sites.zones_used`). SAM + base-defense output was verified byte-identical offline (30 seeds) after every related change.
- **Fixed ground targets (stage 3b) and the target catalog (stage 3c)**: spec in "Fixed ground targets — as built" below.
  - **One roller** for every kind of fixed target (John: separate rollers per target type would get unwieldy). Nine kinds, both coalitions ("an active conflict unfolding").
  - **Offline** (luae, 100 seeds, real zones): Red ≈ 22 sites / 17 units / 102 static objects per roll, Blue ≈ 31 / 42 / 159; all placement checks clean.
  - **In DCS:** Red 18–20 sites, Blue 29–33.
- **Renamed "static" → "fixed"** (John): "static" is reserved for actual DCS static objects; things that don't move are "fixed", things that move will be "mobile". The stage, data files, globals, plan key, config flag and mark text all say fixed.
- **Revetment zones are SAM-only** (John: anything else "would spawn weirdly there"). Rule: `FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES = { prepared_sam_position = { "revetments" } }`. Offline 30 seeds: 0 fixed targets in the 7 revetment zones.
- **Start-up stall found and fixed: static objects must spawn before any AI units.**
  - **Symptom:** the first runs spent ~2–3 min in `coalition.addStaticObject`, ~3 s per parked aircraft.
  - **Probe** (`survey/probe_parked_aircraft_spawn.lua`, `CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN`, off): livery and country (CJTF vs real) made no difference; every variant took ~0.00 s into an empty world.
  - **Fix:** spawning static objects first → 247 objects in 7.4 s, then 250 in 0.5 s; units no slower. The reason inside DCS is unknown and doesn't matter (John).
  - **Recorded** in the `init.lua` spawn block ("KEEP THIS ORDER"), both spawner headers, §1.1 "Execution timing", §11.3 step 6, the §11.4 consumers table and the fixed-targets as-built section. Temporary timing lines were removed after the fix was confirmed.
- **Parked aircraft stand together:** one group per base, one role, one type, on neighbouring spots (John: singles scattered over the field weren't realistic; more aircraft aren't needed). Offline: 0 mixed-type groups in 489, median spread 95 m. In DCS: "looks pretty good".
- **Prerequisites done:**
  - `tools/unit_pool.py` now fills `UNIT_POOL.static`: 259 structure / cargo types with category + shape_name from pydcs `statics.py`. The rest of the pool regenerates identically.
  - Gather keeps each parking spot's terminal type and index (`{ x, z, terminal_type, terminal_index }`). Kola fields have types 104 (large), 72 (open), 40 (helicopter), 16 (runway), and no hardened shelters (68).
  - Parked vehicles as static objects use the pool's `cat` as their category (e.g. `Unarmed`); verified in DCS.
- **Known gaps:**
  - **Front targets are starved.** Only ~4 zones per coalition are within 100 km of an enemy base, and the SAM front belt takes ~90% of them. So armor assembly areas and artillery batteries almost never appear, and Red often has just 1 close-air-support target.
  - **Red's supply-depot minimum** fails about half the time: its large free zones mostly have `no_road`.
  - **Fix:** zones near the front (John, later) or a front-target rule; SAM stays untouched.
- **Cosmetic, harmless:**
  - With CJTF countries and no `livery_id`, DCS logs "livery not found" and uses its standard livery. Real liveries per coalition would make parked jets look right.
  - Some wreck models are missing (`Ural-375_p_1`, `MOBILE_GENERATOR_CRASH`, …).

## Where we were — end of session 4  *(2026-09-23 — SAM network done for now; 100 zones)*

**Status: stages 1–2 run in DCS and are verified at all 37 airfields; stage 3a (SAM sites) ran in DCS five times with 90–100 zones and was tuned between runs (below); John called it done for now ("perfection isn't necessary").** Boot → gather (airbases incl. runways/parking/anchor, zones, weather + time) → `RollTerritory` (territory, front, echelon) → `PlanBaseDefenses` (every base, both coalitions) → `PlanSamSites` (SAM + early-warning network in the zones) → plan dump → `Territory.apply` (coalitions + circles) → `SpawnGroundGroups` (base defenses, then SAM sites) → `DrawBaseDefenses` + `DrawSamSites` (debug marks) + on-screen summary. The user's all-bases run looked right; placements at the cramped fields were acceptable. FPS is not a concern for standing ground units (John).

**Done in session 4 (2026-09-23):**
- **First DCS run of the SAM network** (90 zones): 0 failed groups, 0 type swaps; 47 SAM groups / 239 units on top of 167 / 494 base-defense ones. The spawn stalls DCS ~30 s at start (both spawns together). Found: Red had no long-range site (only 3 core zones ≥ 150 m, each ~30 % to roll long); 16 rear zones left empty because an early-warning pick over its cap had nowhere to go; Blue's Patriots all land in the rear (Bodø/Evenes), and **Rovaniemi has no zones**.
- **Second DCS run** (100 zones; 10 new, 150 m+, in the Kola core, at Rovaniemi, Ivalo, Vuojärvi and Kallax): 0 failed, 0 swaps; 76 SAM groups / 437 units. Minimum rule put SA-10s in three new core zones (Olenya, Murmansk, Severomorsk-1); Rovaniemi got a Patriot + SA-11. But the sides sat ≥ 159 km apart, so almost no zone was `front_belt`, and the early-warning → medium fallback crowded the rear (6 sites at Banak, 4 at Jokkmokk). **Fixed:** front belt measured from this roll's front gap (+ 60 km), rear chance 0.6 → 0.35, rear cap of 2 sites per base. Offline on that territory, 300 rolls: Red ≈ 28 sites (asset 10.2, front 16.2, rear 1.9; long 4.1), Blue ≈ 33 (asset 7.3, front 16.9, rear 8.8; long 1.6). Front-line areas can still stack up to 6 (Ivalo, Banak) — not capped, by design for now.
- **Third DCS run** (Kola South fell to Blue; front gap 59 km → belt 119 km): 0 failed, 0 swaps, spawn ~5 s total. Front belts and the rear cap worked; SA-10s at Monchegorsk / Murmansk / Olenya. But **Red had no early warning** (rear too sparse now) and Blue's long range was only at Evenes. **Fixed:** minimums extended (above), random tie-break instead of biggest zone, early warning placed rear-first. Offline on that territory, 300 rolls: Red ≈ 26 sites (long 4.6, EW 2 every roll: Kilpyavr, Luostari, Koshka Yavr, Karelia), Blue ≈ 25 (long 2.5: Evenes 1.2, Rovaniemi 0.9, Bodø 0.4; EW 2 spread over Norway/Sweden).
- **Fourth DCS run** (Blue held both Finnmark and both Lapland clusters): Patriots at Bodø, Rovaniemi and Evenes; early warning in the rear. But **6 SA-10s in the core, 3 guarding Olenya**, and both Red early-warning radars in neighbouring Kilpyavr zones a few hundred metres apart. **Fixed:** area cap, 3 km spacing, minimum pass spreads by area (see "Spreading"). Offline on that territory, 300 rolls: Red ≈ 20 sites (long 3.4, one each at Murmansk, Severomorsk-1, Severomorsk-3 and Olenya's area; EW 2 at Kilpyavr / Kalevala / Poduzhemye), Blue ≈ 28 (long 1.8, EW 2 spread over Norway/Sweden); 0 warnings.
- **Fifth DCS run** (Red took Finnmark East, Lapland East, Kuusamo, Kola South): 0 failed, 0 swaps, spawn ~5 s. Red 21 sites (SA-10s at Olenya, Murmansk, Severomorsk-1 — one each; EW at Kilpyavr and Poduzhemye), Blue 27 (SA-10 Evenes, SA-10 Rovaniemi, Patriot Kittilä; EW Jokkmokk, Bardufoss); spacing left the extra Kilpyavr/Bardufoss zones free. Blue has more rear (13) than front (4) sites because it holds many rear bases — accepted.
- **Scale check (John's target: Ukraine-war scale, substantial but not WWIII):** ~20–30 SAM sites per side per roll (~300 SAM units + ~470 base-defense units) is judged about right. Blue is denser than today's Nordic inventories — read as allied reinforcement; one-line change (rear chance) if it should be sparser. What will add more Ukraine feel than more sites: emissions behaviour (Skynet: go dark, relocate, ambush), SHORAD travelling with ground units (stages 3b/4), and PROBABLE/POSSIBLE threat intel in the brief (§1.5).
- **Offline test harness note:** luae's `math.random` is the C `rand()`; after `math.randomseed(1..N)` the first values are nearly linear in the seed, which skewed earlier per-zone shares (totals were fine). Seed with `seed * 7919` and discard ~50 values.
- **Fixed after the first run:** `SAM_SITE_MIN_PER_LAYER` (Red: 3 long-range sites every roll, placed before the random pass in asset-ring zones of clusters the side always holds, one per base, biggest zone first); `SAM_SITE_OVER_CAP_LAYER` (an early-warning pick over its cap becomes medium range); the "left free" log line now says why. John is drawing more zones: 150 m+ in the Murmansk–Severomorsk–Olenya–Monchegorsk triangle, and around Rovaniemi.
- **Base defenses refined in DCS:** unit spacing; six fully named components (naming rule at the top of this doc); level matrix by base value; `dispersal` class; placement order most-important-first; road fallback so nothing is dropped; truck-mounted guns and along-road headings on roads; forested fields (Afrikanda) use runway ends. Details in "Base defenses — as built".
- **SAM network (stage 3a)**: spec in "SAM sites — as built". Survey grew from 12 to 100 zones this session.
- **Researched DCS SAM performance** (table in "SAM sites — as built"). Blue re-balanced: Patriot sites get 2 radars aimed around the threat axis; SA-10 added to Blue long range; NASAMS 2 radars, Hawk 2 trackers; Blue short range is Osa / Tor / Roland (Rapier dropped).
- ~~Next, John: test the SAM network in DCS and draw more zones~~ — done (100 zones, five runs).
- **Removed** the no-op RNG seeding (`rng advanced 93` every launch): DCS varies `math.random` between launches on its own.

**Done in session 3 (2026-09-23):**
- **Base defenses end to end** (spec below, "Base defenses — as built"): airbase classes + codes, level matrix + skill, composition, placement, coalition rosters, load-time data validation, planning stage, generic ground spawner with a per-unit type check (catches the Leopard-2 swap), debug drawing.
- **Rename:** `stages/s1_territory.lua` → `stages/roll_territory.lua` (`RollTerritory`); adds `echelon` (front ≤ `ECHELON_FRONT_KM` 100 · mid ≤ `ECHELON_MID_KM` 200 · rear).
- **Trees solved without seeing trees.** Probes at Monchegorsk / Rovaniemi / Ivalo / Kalevala proved what the API can and can't see:
  - **Trees: invisible to every API.** `world.searchObjects` returns nothing in forest; `land.isVisible` matched a terrain-only line of sight 16/16 at all four bases. Don't re-investigate.
  - **Taxiways + aprons: visible** — `land.getSurfaceType` reports them as `RUNWAY`.
  - **Buildings: visible** — `searchObjects(SCENERY)`; within 250 m of the taxiway/parking/runway footprint = the airfield's own; towns sit farther out. No statics on these fields.
  - So placement starts from ground that is open by construction: the **infield** (grass between the runway keep-clear edge and the first taxiway), apron interiors, parking, buildings.
- **One-off footprint survey** (`survey/survey_airbase_footprints.lua`, `CONFIG.SURVEY_FOOTPRINTS`) run for all 37 airdromes → `data/airbase_footprints.lua` (4,680 taxiway cells, 4,851 buildings). Raw facts only; anchors are derived at startup so placement tunes without re-surveying. Re-run only after a Kola map update.
- **Offline test harness:** DCS ships Lua 5.1 as `DCS World\bin\luae.exe`. Stubbing the mission API and running the real `init.lua` (or one stage on real geometry from a plan dump) catches load errors and logic bugs before a DCS run.

**What exists (deployed to `Saved Games\DCS\Scripts\kola_f16\`):**
```
kola_f16/
  init.lua                   load order + run sequence (above); checkData() at load
  config.lua                 START_DELAY, PLAN_DUMP, UTC_OFFSET_H=3, SHOW_WEATHER_DEBUG, FRONT_RANGE_KM, FORCE_CLUSTER,
                             ECHELON_*_KM, DEFENSE_TEST_BASES ({} = all), CLEAR_* margins, DRAW_*, SURVEY_FOOTPRINTS=false
  lib/util.lua               pick/weightedPick/shuffle, dist/bearing, toVec3, withLatLon, formatLL, serialize, writeFile
  lib/logger.lua             Log.* + dumpAirbases/dumpGroups/dumpLateGroupUnits/dumpWeather
  lib/weather.lua            Weather.derive / deriveTime (§1.11), sun, flight rules, summaryText (TEMP debug)
  lib/placement.lua          isClear (runway boxes, parking, surface ring), findClear, ringPoint/discPoint,
                             buildAnchors (infield/apron/parking/building/runway_side), pickAnchorPoint
  data/clusters.lua          11 clusters (§3)            data/zones.lua  100 zones + classes, generated (§1.12)
  data/cloud_presets.lua     34 presets, generated        data/unit_pool.lua  every AI-operable unit + static object type, generated (§1.13)
  data/aircraft_pylons.lua   generated, NOT loaded        data/airbase_codes.lua  4-letter code per base
  data/airbase_classes.lua   hub/fighter/bomber/heli/strip (DRAFT)
  data/base_defense_levels.lua  BASE_DEFENSE_LEVEL[class][echelon] + BASE_DEFENSE_SKILL[level]
  data/base_defense_composition.lua  groups per component per level
  data/base_defense_placement.lua    role, anchors spec, ring fallback, units, spread, mixed_types; group spacing
  data/coalition_rosters.lua  COALITION_ROSTER[side][role] (DRAFT) — the only file that knows red from blue
  data/airbase_footprints.lua surveyed taxiway grid + airfield buildings, all 37 fields, generated in-sim
  data/forested_airfields.lua  fields whose infield is forest (Afrikanda): runway ends + roads only
  data/sam_site_recipes.lua  what each SAM / EW system's site contains + layout (SAM_SITE_RECIPE, SAM_SITE_PLACE)
  data/sam_site_density.lua  zone roles, chance + layer weights per role, zone share and per-layer caps
  data/fixed_ground_target_recipes.lua  what each fixed ground target kind contains, where it goes, success
  data/fixed_ground_target_density.lua  per coalition: zone chance + kinds per echelon, airfield chances, minimums, caps
  gather.lua                 plan.world: airbases{pos, anchor, runways, parking{x, z, terminal type, index}, me_side}, zones, time, weather, checks
  stages/roll_territory.lua  plan.territory: clusters, bases{side, cluster, echelon}, zones, front, summary
  stages/plan_base_defenses.lua  plan.base_defenses: groups, bases (per-base summary), totals
  stages/plan_sam_sites.lua  plan.sam_sites: sites, groups, zones_used, summary
  stages/plan_fixed_ground_targets.lua  plan.fixed_ground_targets: sites, groups, static_objects, zones_used, parking_used
  stages/catalog_targets.lua  plan.target_catalog: every SAM site + fixed ground target, by id
  consumers/territory.lua    setCoalition + autoCapture(false); base/zone circles; summaryText
  consumers/spawn_ground_groups.lua  plan entries → coalition.addGroup + type check (generic: zones will reuse it)
  consumers/draw_base_defenses.lua   level ring per base, label per group, optional anchor dots; summaryText
  consumers/draw_sam_sites.lua       label + engagement / detection ring per SAM site; summaryText
  consumers/spawn_static_objects.lua coalition.addStaticObject + per-object type check
  consumers/draw_fixed_ground_targets.lua  label + ring per fixed ground target site; summaryText
  data/convoy_recipes.lua    what each convoy kind contains, how it drives; convoys per coalition
  stages/plan_convoys.lua    plan.convoys: convoys, groups (with route), summary (stage 4, first part)
  consumers/draw_convoys.lua route line + start / parking labels per convoy; summaryText
  lib/threat_routing.lua      grid path search around threat circles, smoothing, crossed-ring check (pure logic)
  data/aircraft_profiles.lua  per aircraft type: launch base classes, runway, parking, reach, speeds, altitudes
  data/aircraft_loadouts.lua  one loadout per aircraft type and mission type, generated (tools/aircraft_loadouts.py)
  data/air_tasking.lua        air mission types (built or stub, how they attack), missions per coalition, timing
  stages/plan_air_tasking.lua plan.air_tasking_orders: each coalition's missions (stages 5–6, first pass)
  consumers/spawn_aircraft_groups.lua        one planned flight → coalition.addGroup + type check
  consumers/schedule_air_tasking_orders.lua  spawns flights at their start times; removes them after landing
  consumers/draw_air_tasking_orders.lua      route line + target label per flight; summaryText
  survey/survey_airbase_footprints.lua  one-off survey (off)
  survey/survey_zone_terrain.lua      zone terrain survey; runs only in khola_ground_zones.miz
  survey/probe_parked_aircraft_spawn.lua  one-off timing probe (off; CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN)
tools/                       miz_zones.py, cloud_presets.py, unit_pool.py (+ overrides), dcslua.py, kola_proj.py, kola_airbases.json,
                             aircraft_loadouts.py (+ aircraft_loadout_choices.json, aircraft_loadouts_by_hand.json)
kola_f16_random_tasking.miz  flyable mission (ONCE + TIME MORE 1 → DO SCRIPT dofile(lfs.writedir().."Scripts\\kola_f16\\init.lua"))
```
Plan dump: `Saved Games\DCS\kola_last_plan.lua` every run. Re-run `python tools/miz_zones.py "<survey .miz>"` after drawing zones; `python tools/unit_pool.py` after a DCS update once pydcs has caught up; `python tools/aircraft_loadouts.py` after changing a loadout choice, re-running unit_pool.py, or updating the Liberation clone (`C:\Users\johnk\Git\dcs_liberation`, sparse: resources/customized_payloads); the footprint survey after a map update. DCS updates re-sanitize `MissionScripting.lua` → `python desanitize_dcs.py` from an admin shell + full DCS restart.

---

## NEXT SESSION — candidates  *(pick one with John)*

**Build order (chosen 2026-09-23): linearly, stage by stage.** Stages 1–3 are done; stage 4 and stages 5–6 have first passes running in DCS (2026-09-25). Mission stages read only `plan.target_catalog`. John isn't in a rush to fly; a thin "fly one SEAD mission first" slice was offered and declined.

**Agreed next (John, 2026-09-25): packages — ordering plus SEAD/DEAD escorts.**
- **The hook is there:** each mission with `needs_suppression` lists its `suppression_threats` (SAM site ids, plus `DEF_…_radar_missile_launchers_*` groups). That's about 72 % of missions offline.
- **Build first:** the stubbed `suppression_of_air_defenses` (`EngageGroup`, anti-radiation missiles) and `destruction_of_air_defenses` (`AttackGroup`) mission types. Their rosters, loadouts, attack altitudes and attack method are already in the data (`built = false`).
- **Then packages:** a suppression line whose time on target is 3–5 min before the strike's, on the sites the strike crosses (§1.9 rule 3).
- **Decide:** how the package shares one start and time-on-target plan; whether a flagged strike without an available suppression flight is dropped or flies anyway; and how the airborne cap counts package members.

**Also wanted:** CAP and scrambles (§1.10), interdiction (convoy `AttackGroup`) and close air support flights, then the brief (stage 7).

1. **Front targets** (the known gap above): John draws zones near the front, or a front-target rule. For example, measure "front" for targets from this roll's front gap like the SAM front belt does, or allow armor / artillery at `mid`. Also Red supply depots with no road access.
2. **Rest of stage 4: mobile units.** One Red supply convoy is done (session 6). Still to do: Blue convoys, reinforcements, missile-launcher deployments, contacts. They need their own zones or corridors, since fixed targets use all free zones. Add them to the catalog through an adapter in `stages/catalog_targets.lua`; spawn any static objects before units.
   - **Air tasking polish:**
     - Red Su-34s sometimes fly at the edge of their reach (677 km of 700); lower `combat_radius_km` if they run dry;
     - mid-mission spawns while a player flies: batch them across frames if they freeze the sim;
     - `SpawnAircraftGroups` only builds `bomb_critical_objects` attacks so far.
3. **SAM sites on the map's revetments** (`prepared_sam_position = "revetments"`, 7 zones): John wants SAMs spawned in those dug-in positions later. It's a SAM-stage change, so ask first.
4. ~~First DCS run of the SAM network and tuning~~, done 2026-09-23. Still open: fly against it and check the Patriot's two-radar layout engages; optionally a Blue rear-density tweak.
5. ~~Rest of stage 3~~, done 2026-09-24 (fixed ground targets + catalog). Deferred from it:
   - ~~consolidate spawning~~: settled in session 6 as one spawner per kind of DCS object;
   - a second parked-aircraft group at hubs if ramps look empty;
   - real liveries per coalition for parked aircraft;
   - `settlement` still counts airfield buildings.
6. **Base-defense polish** (deferred list): ±1 level nudge at ~20 %; logistics/fuel components as statics (cheap, targetable); `security_armor` / `apc_patrol` components; re-classify `airbase_classes.lua` and grow `coalition_rosters.lua` (Tor / Tunguska at heavy Red bases, etc.).
7. **Housekeeping:** rename `consumers/territory.lua` → `apply_territory.lua` (`ApplyTerritory`); drop `SHOW_WEATHER_DEBUG` once the brief exists.
8. **Proximity spawning** (unlikely to be needed: standing ground units barely affect FPS): spawn a base's defenses when a player gets within ~150 km — the plan already holds every unit, so briefs and targets stay truthful.

**Unit budget (researched 2026-09-23, rules of thumb, not measured):** standing ground units ~1,000–1,500 total (2026-09-24: ~860 units + ~250 static objects per roll; all spawn in ~6 s); moving ground groups ~10–20 at once, short on-road routes (stage 4 is the risk); AI aircraft 12–20 alive. Cost order: moving ground > AI aircraft > standing units with sensors > idle units / statics. Levers: `controller:setOnOff(false)` for far ground groups, statics for non-shooting targets, few infantry, wreck cleanup, proximity spawning. Check with RCtrl+Pause FPS over the Kola core; a per-run unit census log line was offered.

**Performance baseline (John's F-16 flights, 2026-09-25, stages 1–3c; GPU-bound both times):**

| | Everything spawned (~860 units + ~250 static objects, all `DRAW_*` on) | Empty map |
|---|---|---|
| Bodø, on the ground and low flyover | 45–60 fps, some stutter and frametime drops when panning | 48–65 fps, smoother |
| 25,000 ft | 70–75 fps | 70–75 fps |
| F10 map | 45 fps | 55 fps |

Reading: standing ground units cost a few fps only close to a heavy base, nothing at altitude. The F10 drop is most likely the ~600 debug marks, not the units. John's response: lower the LOD distance and tune graphics settings; no mission changes. **Re-test the same way once tasked AI flights, CAP and moving ground units land**, since those are the expensive items in the cost order above.

**Open decision, settled for now:** base-defense units live in the plan (`plan.base_defenses`, ids = DCS group names) so they can later be mission targets or brief info, but they are **not** in the target catalog yet.

**Decide as we hit them:** runtime state table shape (§11.2; the ATO scheduler keeps a first `_flights` table keyed by mission id); scramble loop (§1.10); success model (§9); later phases: Skynet, pydcs pre-gen, naval.

---

## Base defenses — as built  *(2026-09-23)*

Every airbase gets a coalition-appropriate ground defense sized to how hard its owner holds it. First thing in the project that spawns units.

### Taxonomy (one question per term)

| Term | Question it answers | Values | Set where |
|---|---|---|---|
| **`class`** | What *is* this base? | `hub` / `fighter` / `bomber` / `dispersal` / `strip` / `heli` | `data/airbase_classes.lua` (draft) |
| **`echelon`** | Where does it sit relative to the enemy? | `front` ≤ 100 km · `mid` ≤ 200 km · `rear` | `RollTerritory`, from `nearest_enemy.km` |
| **`defense_level`** | How heavily does its owner defend it? | `light` / `standard` / `heavy` | `BASE_DEFENSE_LEVEL[class][echelon]` (nudge not built) |
| **component** | A kind of defensive element | `towed_anti_aircraft_guns`, `mobile_anti_aircraft_guns`, `infrared_missile_launchers`, `radar_missile_launchers`, `shoulder_launched_missile_teams`, `security_infantry` | `data/base_defense_placement.lua` |
| **composition** | How many groups of each component, per level | `{ component, min, max }` | `data/base_defense_composition.lua` |
| **placement** | Where a component's groups go | anchors spec, ring fallback, units per group, spread | `data/base_defense_placement.lua` |
| **anchor kind** | What open ground a group starts from | `infield`, `apron`, `parking`, `building`, `runway_side` | `Placement.buildAnchors` |
| **role** | Which roster list types come from | `towed_anti_aircraft_gun`, `mobile_anti_aircraft_gun`, `infrared_missile_launcher`, `radar_missile_launcher`, `shoulder_launched_missile`, `infantry` | placement `role` |
| **roster** | Which types a coalition fields per role | weighted `{ type, weight }` | `data/coalition_rosters.lua` |

`defense_level` matrix. What a base is matters more than where it sits: hubs and bomber bases are strategic and defended heavily anywhere (long-range strikes reach the rear), fighter bases ease off only deep in the rear, small fields scale with the front.
```
                 front      mid        rear
   hub           heavy      heavy      heavy
   bomber        heavy      heavy      heavy
   fighter       heavy      heavy      standard
   dispersal     heavy      standard   standard
   strip         standard   light      light
   heli          standard   light      light
```
`dispersal` = a secondary field the air force flies fighters from in wartime (Finnish and Swedish dispersal doctrine), so it gets an Army air-defense detachment: Kittilä, Ivalo, Sodankylä, Kuusamo, Enontekiö, Jokkmokk, Vidsel, Kalixfors. `strip` is now only civil or disused fields with no wartime flying role. Always heavy: Murmansk, Olenya, Severomorsk-1 (Red); Bodø, Evenes (Blue). Class changes 2026-09-23: Andøya bomber → strip (maritime patrol left in 2023), Evenes fighter → bomber (P-8 base since 2023, plus F-35 alert). Offline over 1,000 territory rolls: Red averages 4.2 heavy bases per roll (never 0), Blue 2.8. Monchegorsk heavy in 24 % of rolls, Kilpyavr and Severomorsk-3 in 47 %, Rovaniemi in 75 %. Kallax (always rear) stays standard. The old matrix left Red with no heavy base in 52 % of rolls.
Rough size: heavy 6–9 groups / ~20 units, standard 3–6 / ~13, light 2–3 / ~9. About 430 units per mission. FPS is not a concern: standing ground units barely register (John, 2026-09-23). Skill: heavy `Good`, else `Average`.

Groups per level (`data/base_defense_composition.lua`). Layered by how much the owner values the base:
```
                                   heavy   standard   light
   towed_anti_aircraft_guns         1–2      1–2       1
   mobile_anti_aircraft_guns        1        0–1       —
   infrared_missile_launchers       1        0–1       —
   radar_missile_launchers          1        —         —
   shoulder_launched_missile_teams  1–2      1         1
   security_infantry                1–2      1         0–1
   (light towed_anti_aircraft_guns is 1, not 0–1: no used field is left with a lone MANPADS pair)
```

Rosters (`data/coalition_rosters.lua`, weights in brackets). Coverage and realism beat exact type: Blue uses Russian or Chinese stand-ins where they match the real Nordic system better. Only single-vehicle systems; multi-vehicle SAM sites (NASAMS, IRIS-T SLM, Rapier) belong to stage 3's site recipes.

| Role | Red: modern Russian Northern Fleet | Blue: Nordic, closest DCS stand-ins |
|---|---|---|
| towed_anti_aircraft_gun | ZU-23 Emplacement (3), ZU-23 Emplacement Closed (2) | ZU-23 Emplacement (3), Closed (1): Finland's 23 ItK 61 is a ZU-23-2 |
| mobile_anti_aircraft_gun | ZSU-23-4 Shilka (2), Ural-375 ZU-23 (1) | Gepard (3), Vulcan (1): for Sweden's CV90 AA and Finland's 35 mm Skyguard guns |
| infrared_missile_launcher | Strela-10M3 | M1097 Avenger (2), M6 Linebacker (1): for ASRAD-R and vehicle RBS 70 |
| radar_missile_launcher | Pantsir-S1 (3), Tor M2 (2), Tor (1), Tunguska (1) | Roland ADS (2) for Finland's Crotale NG; Tor M2 (1) for IRIS-T SLS. HQ-7B left out: in DCS its launcher has no search radar of its own and is unreliable without the separate HQ-7 search radar vehicle. It comes back as a two-vehicle group with stage 3's site recipes. |
| shoulder_launched_missile | SA-18 Igla-S (3), SA-18 Igla (1) | Stinger (3), Igla-S (1): RBS 70 isn't in DCS; Finland fielded Igla |
| infantry | Soldier AK (2), Infantry AK ver2 (1), ver3 (1), Soldier RPG (1) | Soldier M4 (3), Soldier M249 (1) |

Left out on purpose: Strela-1 and Chaparral (retired), Osa (older army system), S-60, the WWII-era Bofors model. Vulcan is retired too but stays at low weight, since Blue has few gun options.

### Placement rules
- **Anchors** (derived at startup from `data/airbase_footprints.lua` + live runways/parking):
  - `infield`: grass between each runway's keep-clear edge and the first taxiway within 600 m.
  - `apron`: taxiway cells whose 4 neighbours are also taxiway. Thin taxiway lines can cross forest, so they are exclusions only.
  - `parking`, `building`.
  - `runway_side`: only at fields with no taxiway surface at all. Elsewhere the sides without taxiways are the tree lines.
  - `runway_end`: only at **forested fields** (`data/forested_airfields.lua`, read off the F10 map: Afrikanda). Their infield, aprons and parking edges are forest, so this is their only anchor kind: the cleared overrun beside each runway end, 80–380 m past the threshold and 50–70 m off the centreline. There, only the approach lane (runway width + `CLEAR_APPROACH_LANE_M` 15 either side) is kept clear past the ends, and units spread at most `FORESTED_SPREAD_M` 30 m.
- **Per component** `anchors = { kind = { weight, min_m, max_m } }`:
  - Guns and vehicle-mounted missile launchers: infield first (0–40 m), apron/parking 40–100 m, **never buildings** (they can stand in forest).
  - Shoulder-launched missile teams and infantry: wider, and buildings are allowed.
- **Checks:** every group centre and every unit must pass `Placement.isClear`: outside runway boxes (`CLEAR_RUNWAY_SIDE_M` 100 beside the edge, `CLEAR_RUNWAY_END_M` 400 past each end), ≥ `CLEAR_PARKING_M` 60 from parking spots, and no runway/taxiway/water in 9 surface samples (`CLEAR_SAMPLE_M` 40 ring). Group centres keep ≥ `BASE_DEFENSE_GROUP_SPACING_M` 150 apart. Units in a group keep ≥ `unit_spacing` apart (towed guns 25, mobile guns 30, infrared and radar missile launchers 40, shoulder-launched missile teams 10, infantry 6 m) inside the same `spread` disc. A unit that can't fit in 30 tries is dropped, not pushed outward toward the trees (offline, 20 seeds: ~2 units per run).
- **Placement order:** the composition lists the most important layer first (radar missiles → infrared → mobile guns → towed guns → MANPADS → infantry). Groups claim ground in that order, so a cramped field loses towed guns, never its radar or infrared missile launchers.
- **Road fallback:** a group that finds no clear open ground in 80 tries goes onto one of the airfield's own roads instead (`anchor_kind = "road"`): a spot within `ROAD_FALLBACK_RUNWAY_M` 800 of a runway's box, snapped with `land.getClosestPointOnRoads`, checked off runway boxes, parking, runway/taxiway and water (no 40 m surface ring, so a road may run beside a taxiway or lake). Its units snap along the road inside `spread`. Roads are open by construction, and vehicles on a road are normal. Hand-drawn zones for base defenses were rejected: no manual work (John, 2026-09-23). The per-base log shows `N on roads`.
- **Road units:** a towed-gun unit that ends up on a road becomes its truck-mounted version (`road_role = "truck_mounted_anti_aircraft_gun"`: Ural-375 ZU-23, both sides) — a dug-in emplacement on a road looks wrong. Road units face along the road (`Placement.roadHeading`), either way round.
- **Nothing is dropped:** if the airfield roads are full, a group widens its road search to 2,000 m from the runways. A unit that can't fit in its group's circle retries at **half** unit spacing (keeps the group compact; offline ~2 % of towed-gun pairs end up 12–25 m apart, none under 5 m), then goes onto a road within 300 m, and only then 1,000 m, of its group centre. Only if all of that fails is a group dropped, logged as a `DROPPED` warning (it shouldn't happen). Offline, 20 runs: 0 dropped groups, 0 dropped units, about 7 road groups per mission, all at the cramped fields. Cramped fields (Alta, Boden, Enontekio, Hemavan, Ivalo, Kalevala, Kiruna, Kittila, Kuusamo, Sodankyla, Tromso) lose 1–3 gun groups at HEAVY. Hosio has no parking/taxiway/objects in DCS (runway_side only). Kalevala is a real 568 m helo strip.

### Plan shape and naming
`plan.base_defenses = { groups = { { id, base, side, class, echelon, level, component, role, skill, anchor_kind, pos = { x, z, lat, lon }, units = { { type, x, z, heading_deg } } } }, bases = { [name] = { code, side, class, echelon, level, groups, units, anchors, rejects, dropped, on_roads } }, totals }`. Group id `DEF_<CODE>_<component>_<n>` (e.g. `DEF_OLEN_towed_anti_aircraft_guns_1`) is the DCS group name; units are `<id>_<n>`. Headings face outward from the field.

### Load-time validation (`PlanBaseDefenses.checkData`, fails loudly, nothing spawns)
Every roster type exists in `UNIT_POOL.ground` with a positive weight; every placement role has a roster for both sides; every placement has `anchors` (`{ weight, min, max }`) + `ring`; every composition component has a placement; every level has a skill and every matrix cell a composition; every `AIRBASE_CLASS` value is in the matrix. At run time, classes naming unknown airdromes warn.

### Verify in DCS
Per-base log line: `Olenya RED bomber/front → HEAVY 8 groups 22 units (anchors: …; rejects: …; no room for: …)`, then a total. Spawner line: `spawned N groups / M units; 0 failed; 0 type mismatches`. Grep `asked for` for type swaps. F10: level ring per base + a label per group; `DRAW_ANCHORS = true` adds anchor dots (use with `DEFENSE_TEST_BASES` set to a few bases — tens of thousands of marks otherwise).

---

## SAM sites — as built  *(2026-09-23, stage 3a, run in DCS five times; done for now)*

Both coalitions get a SAM and early-warning network sized to what they hold. Target feel (John): **Ukraine-war density with mixed-age kit**. It should feel lived-in, not 1985 and not pure SA-10, built from what DCS has; coverage matters more than exact type. All scripted; the only manual input is the survey zones.

### How a site is decided
Every zone a coalition holds this roll (it inherits its cluster's side) gets one **role**, first match wins (`data/sam_site_density.lua`):

| Role | Question it answers | Rule |
|---|---|---|
| `asset_ring` | Is it guarding something the owner values? | ≤ 40 km from an own base whose defense level is `heavy` (stage 2) |
| `front_belt` | Is it on the front? | ≤ 100 km from an enemy-held base, or ≤ this roll's front gap (shortest distance between opposing bases) + 60 km, whichever is farther |
| `rear_area` | Anything else | early warning, the odd medium site; none once 2 sites stand in zones named after the same base (`SAM_REAR_SITES_PER_BASE_MAX`) |

Then: `chance` (asset 0.9 · front 0.8 · rear 0.35) → a **layer** picked by weight (asset: long 3 / medium 5 / short 2 · front: medium 5 / short 4 / EW 1 · rear: EW 3 / medium 2 / short 1) → a **system** of that layer from `COALITION_SAM_SYSTEMS[side][layer]` that **fits the zone** (recipe `footprint_m` ≤ zone radius; else the next smaller layer) → the site laid out inside the zone. Caps: at most 75 % of a side's zones become SAM sites (the rest stay for garrisons and targets); at most 2 early-warning sites per side — a pick over that cap becomes medium range (`SAM_SITE_OVER_CAP_LAYER`). Asset-ring zones fill first.

**Minimum per layer** (`SAM_SITE_MIN_PER_LAYER`: Red 3 long range + 2 early warning, Blue 1 long range + 2 early warning): placed before the random pass, largest layer first. Candidates are ranked by role order (`SAM_SITE_MIN_ROLE_ORDER`: early warning goes rear → front → asset ring, since its radars see 300 km+ and shouldn't take a SAM battery's zone; other layers use asset ring first), then zones in a cluster the side always holds (so the Kola core, not a captured Finnish base), then an area without a site of this layer yet, then at random, so sites move between rolls.

**Spreading** (after the fourth run): a zone's **area** is the heavy base it guards (asset ring), otherwise the base its zone is named after. At most 1 long-range site per area (`SAM_SITE_MAX_PER_AREA`; a second long-range pick drops to medium), at most 2 sites per area in the rear (`SAM_REAR_SITES_PER_BASE_MAX`), and no two sites of one side within 3 km (`SAM_SITE_MIN_SPACING_KM`), so overlapping zones (the three at Kilpyavr, the Ivalo pair) hold one site between them. The minimum pass skips zones that break either rule. If too few zones fit the layer's systems, it logs a warning and places fewer.

### Systems (`COALITION_SAM_SYSTEMS` in `data/coalition_rosters.lua`)

| Layer | Red: Russian, layered, mixed age | Blue: western + Soviet-made, like Ukraine |
|---|---|---|
| long_range | SA-10 (for S-300/S-400) + Pantsir/Tor escort | Patriot (2) + Avenger escort, SA-10 (1) + Roland/Tor escort |
| medium_range | SA-11 Buk (3), SA-6 Kub (1, old stock) | NASAMS (3), IRIS-T SLM (2), SA-11 (2, Finland's former ITO 96, Ukraine's Buks), Hawk (1, reserve) |
| short_range | SA-8 Osa (2), SA-15 Tor (1) | SA-8 Osa (2), SA-15 Tor (1): Greece (NATO) and Ukraine field both; Roland (1) |
| early_warning | 1L13, 55G6 | FPS-117 |

SA-2/3/5 left out (Russia doesn't field them); one roster line brings an S-200 back if wanted. Blue fields Soviet-made systems on purpose (John: coverage and realism over exact type): Ukraine fights with S-300, Buk, Osa and Tor, and NATO's Greece, Bulgaria and Slovakia have operated S-300, Osa or Tor.

### How the systems perform in DCS (researched 2026-09-23)
Real-world figures vs DCS (Airgoons DCS reference; ED forum reports). Engagement ranges are high altitude / low altitude.

| System | Real (vs aircraft) | DCS | DCS behaviour, and what the recipe does about it |
|---|---|---|---|
| SA-10 | ~75–90 km | 5–120 km / 5–40 km | Strongest SAM in DCS: remade with better guidance and missile flight, 360° radars, 15 targets × 2 missiles, shoots down incoming missiles. |
| Patriot | ~160 km | 3–120 km / **3–30 km** | Radar sees a **fixed ~120° sector**; fires at about twice the S-300's range (wasted long shots); tracking and anti-munition reliability complaints. Recipe: **2 radars aimed exactly 30° either side of the threat axis** (~180° covered; `aim` in the part), 6 launchers. Blue also gets SA-10 as a long-range option. |
| NASAMS | 40 km (60 km ER) | 0.7–57 km / **0.7–14 km** | Limited by DCS's AMRAAM. Recipe: 2 search radars (ED's template uses several). |
| Hawk | ~45 km | 1.5–45 km / 1.5–22 km | Solid, but depends on its tracking radar illuminating the target, so beaming defeats it. Recipe: 2 tracking radars (ED's template). |
| IRIS-T SLM | 40 km | mod data 40 km | Currenthill mod; no reliability reports found. Unverified. |
| SA-11 | ~35 km | 3.3–35 km / 25 km | Radar on every launcher: robust and well-regarded. Weighted up for Blue. |
| SA-15 Tor | 12 km | 1.5–12 km | Strong; very good at shooting down incoming missiles. |
| SA-8 Osa | 10 km | 1.5–10.3 km | Decent; optical fallback if its radar is suppressed. |
| Roland | 8 km | 0.5–8 km | Radar-only in DCS; short range. |
| Rapier | 6.8 km | 0.4–6.8 km, 3 km ceiling | **Can't engage low flyers without the missile hitting the ground.** Recipe kept, not rostered. |

**For the brief (stage 7):** rings drawn now use ED's high-altitude figure; the low-altitude reach is much shorter (Patriot 30 km, NASAMS 14 km, SA-10 40 km). The threat picture should give both.

Sources: [Patriot launch range](https://forum.dcs.world/topic/317951-patriot-has-grossly-overestimated-launch-range/), [Patriot STR](https://forum.dcs.world/topic/280250-patriot-str-doesnt-work-properly/), [Patriot vs munitions](https://forum.dcs.world/topic/313261-patriot-extremely-unreliable-at-intercepting-incoming-munitions/), [DCS Liberation #1531](https://github.com/dcs-liberation/dcs_liberation/issues/1531), [Airgoons Western](https://www.airgoons.com/w/DCS_Reference/Air_Defences/Western), [Airgoons Eastern](https://www.airgoons.com/w/DCS_Reference/Air_Defences/Eastern), [AIM-120 range](https://forum.dcs.world/topic/318993-aim-120-range/).

### Recipes (`data/sam_site_recipes.lua`)
Per system: `layer`, `footprint_m` (SA-10/Patriot 150, SA-11/Hawk 120, SA-6/NASAMS/IRIS-T 100, SA-8/Rapier 60, Tor/Roland 50, EW 40), `unit_spacing`, `parts = { type, min, max, place, aim }` and optional `escort_role`. `aim` (degrees off the threat axis, one per unit) gives a unit an exact heading. It exists for sector radars like the Patriot's. Places, as fractions of the footprint: `centre` 0–35 % (radars, command post), `launchers` 45–95 %, `edge` 60–100 % (support trucks, which make the site look occupied). Radars and launchers face the nearest enemy base; support vehicles face anywhere. **One DCS group per site** (a system's radars and launchers must share a group); the escort is its own group `<id>_escort`. Engagement and detection radii come from UNIT_POOL (ED's data).

### Placement
Units stay inside their zone (a quad uses its inscribed circle). Each unit passes `Placement.isClear` against the zone's nearest airfield (runways and parking stay clear), then retries at half spacing, then with only the point itself checked (the zone was surveyed as open). A site whose radar or command post can't be placed is dropped with a warning. **Zones are reserved for stage 3 onward:** base defenses keep 30 m outside every zone within 5 km of their base (`base.zones` in the placement view).

### Plan shape and naming
`plan.sam_sites = { sites = { { id, side, system, layer, role, zone, defends, pos, engage_m, detect_m, group_ids } }, groups = { spawn-ready, same shape as base defenses + purpose = "air_defense", site }, zones_used = { [zone] = site id }, summary = { [side] = { zones_held, sites, by_layer } } }`. Group id `SAM_<CODE>_<system>_<n>` (code of the zone's nearest base, system without punctuation: `SAM_OLEN_SA10_1`, `SAM_BODO_NASAMS_1`); escort `<id>_escort`. Spawned by the same `SpawnGroundGroups` after all planning.

### Load-time validation (`PlanSamSites.checkData`)
Every recipe part is in `UNIT_POOL.ground` with a known place; every escort role has a roster on both sides; every `COALITION_SAM_SYSTEMS` entry names a recipe of that layer with a positive weight; every density role lists known layers.

### Verify in DCS
Log: one line per site (`SAM_SEV1_SA10_1  RED  SA-10  long_range  asset_ring  Severomorsk-1  11 units + escort  engage 120 km (ZONE_SEV1_341_097)`), then per side `N sites in N of M zones held`. A zone that rolled a site but got none logs `left free (<radius>, <why>)`. F10: a label per site; engagement rings (solid, side colour) and early-warning detection rings (dashed), switched by `DRAW_SAM_SITES` and `DRAW_SAM_RINGS`. Offline (24 zones, 200 rolls): Red ≈ 7.5 sites/roll (SA-10 0.8, SA-11 2.0, SA-6 0.8, SA-8 1.7, Tor 1.0, EW 1.2), Blue ≈ 6 (NASAMS 0.9, SA-11 0.6, IRIS-T 0.6, Hawk 0.3, Patriot 0.2, SA-10 0.1, Osa 0.8, Tor 0.4, Roland 0.5, EW 1.8); no two site units under 10 m; no base-defense unit inside a zone. A Patriot site came out with radars at 80° and 140° (60° apart around the threat axis) and 6 launchers. Offline after the fixes (90 zones, the DCS run's territory, 300 rolls): Red ≈ 27 sites of 40 zones (long 3.3: Murmansk, Monchegorsk, Severomorsk-1 every roll, Sodankylä 26 %; medium 9.3, short 12.7, EW 2), Blue ≈ 31 of 50 (long 1.1, medium 19.4, short 8.6, EW 2); 0 warnings.

**Volume vs target (reviewed 2026-09-23, before the zone survey grew to 100 — now judged about right, see "Scale check" under Where we are):** about a quarter to a third of the Ukraine-like target. For scale, the Kola core realistically holds something like 6–10 long-range battalions, and an active 400–600 km front has a medium site every 30–50 km. The code scales with zones; the limit is zone count and size (only 152 m zones fit SA-10/Patriot). Needed: about 10–12 full-size zones ringing Severomorsk / Kola Bay / Murmansk / Olenya, 2–3 per contested cluster 20–60 km behind the border, and 3–4 each at Rovaniemi, Bodø and Evenes, so about 40–50 for SAMs and ~100 overall. Planned: a "minimum sites per layer" rule so the Kola core always gets several long-range sites, and short-range units attached to garrisons and ground forces (stage 3b/4) rather than taking zones.

**Known gaps:** no zones yet at Rovaniemi (Blue's front-line fighter base gets no SAM cover). Blue has no long-range minimum, and its long-range sites land at Bodø/Evenes in the rear. Kola-core zones are mostly 84–122 m, which only fits short- and medium-range systems. No alarm-state or ROE orders yet (DCS defaults engage); Skynet later keys on the group ids.

---

## Fixed ground targets — as built  *(2026-09-24, stage 3b + target catalog 3c; offline only so far)*

Everything on the ground worth attacking that doesn't move and isn't a SAM site, for both coalitions ("an active conflict unfolding" — John). **Naming (John, 2026-09-24): "fixed" = doesn't move** (fixed ground targets; mobile targets are a separate, later stage and don't need zones kept free). **"static" is reserved for actual DCS static objects** (`coalition.addStaticObject`, `form = "static_object"`, `SpawnStaticObjects`, `UNIT_POOL.static`). A recipe part says `form = "unit"` or `"static_object"` (rule of thumb: would shoot or drive → unit; buildings, parked vehicles and aircraft → static object).

**Run order:** `PlanSamSites` → `PlanFixedGroundTargets` → `CatalogTargets` → dump → spawn (base defenses, SAM, target units, target static objects) → draw. SAM is untouched; 3b only reads `plan.sam_sites.zones_used`.

**Data (plain, no logic):**
- `data/fixed_ground_target_recipes.lua`: `FIXED_GROUND_TARGET_RECIPE[kind]`. Fields:
  - `label`, `location` (`zone` / `parking_spot` / `airfield_ground`), `echelons`;
  - zone class `requires` / `prefers`;
  - `footprint_m`, `unit_spacing`;
  - `parts` `{ role, min, max, place, form, critical, same_type, spacing_m }`;
  - airfield `anchors`; parking `aircraft` + `aircraft_roles_by_base_class`;
  - `success = { critical_fraction }`, `mission_types`, `value`.

  Places: `centre` / `middle` / `outer` rings (`FIXED_GROUND_TARGET_PLACE`).
- `data/fixed_ground_target_density.lua`: per coalition `zone_chance` and `zone_kinds` per echelon, `airfield_chance[kind][base class]`, `minimum`, `max_per_kind`. Also the preference bonus, 2 zone targets per area, 2 km spacing, parking share 0.3, skill `Average`.
- `COALITION_FIXED_GROUND_TARGET_ROSTER` in `data/coalition_rosters.lua` (still the only file that knows red from blue). It's a separate table because `COALITION_ROSTER` is validated as ground units only.

**Kinds (first pass):**

| Kind | Location | Needs | Echelons |
|---|---|---|---|
| garrison | zone | medium+, road | all |
| armor_assembly_area | zone | large, road | front |
| artillery_battery | zone | medium+, not steep | front |
| command_post | zone | road | all |
| supply_depot | zone | large, road | mid, rear |
| fuel_depot | zone | large, road | mid, rear |
| communications_site | zone | prefers high ground / open radar view | all |
| parked_aircraft | parking spots | aircraft roles by base class | all |
| airfield_fuel_storage | building/apron anchors | — | all |

**Roll, per coalition (same shape as SAM):**
1. **Minimum pass.** Zone kinds go in the best-fitting zone: most preferred classes, then a new area, then chance. Airfield kinds go to the base with the highest chance.
2. **Zone pass.** Every free zone gets a chance by echelon, then a kind that fits it; the weight grows ×(1 + matched preferences).
3. **Airfield pass.** Each held base rolls each airfield kind by its class.

A zone's echelon is measured like a base's (nearest enemy base, 100 / 200 km). **Zones on the map's own SAM revetments (`prepared_sam_position = "revetments"`) are for SAM sites only** — anything else sits oddly in the dug-in positions (John, 2026-09-24); rule: `FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES`, and the summary line counts excluded zones.

**Placement:**
- **Zone objects** stay inside the zone. The same relaxations as SAM sites: half spacing, then point-only.
- **Airfield ground:**
  - uses the base-defense anchors (`Placement.buildAnchors`);
  - keeps ≥ 40 m from every base-defense unit, and a footprint + 40 m clearance for the site centre;
  - no relaxing beyond half spacing.
- **Parked aircraft:**
  - on real parking spots, at most 30% of a base's spots;
  - large aircraft only on terminal type 104, helicopters on 40/72/104, others on 68/72/104;
  - nose toward the nearest runway centreline;
  - **one group per base, one type, parked together** (John, 2026-09-24: scattered singles weren't realistic; more aircraft not needed). The role comes from the base-class weights, then one roster type. The seed is the fitting spot with the most free fitting spots within `FIXED_GROUND_TARGET_PARKED_AIRCRAFT_REACH_M` (300 m); the group fills the seed's nearest neighbours. Offline, 30 rolls on real spot types: 489 groups, 0 mixed-type, median spread 95 m (max 428 m), ~4% end up as a single aircraft (few fitting spots nearby, or a small base's 30% cap).

**Plan shape:** `plan.fixed_ground_targets = { sites, groups, static_objects, zones_used, parking_used, summary }`.
- **Ids:** `TGT_<CODE>_<kind>_<n>` is the DCS group name. Units are `<id>_<n>`, static objects `<id>_static_<n>`.
- **Static-object entry:** `{ id, coalition, type, category, shape_name, x, z, heading_deg, site }`.
- **Category comes from the pool:** structures from `UNIT_POOL.static`; `Planes` / `Helicopters` for aircraft; the pool's `cat` for vehicles (e.g. `Unarmed`). This is unverified in DCS.

**Target catalog (`stages/catalog_targets.lua`, `plan.target_catalog`):** `targets[id]`, `list` (by coalition, highest value first), `summary[coalition].by_mission_type`.
- **Entry fields:** `category` (`air_defense` / `ground_target`), `kind`, `label`, `coalition`, `cluster`, `location`, `zone` or `base`, `pos`, `value`, `mission_types`, `group_ids`, `static_object_ids`, `critical_names`, `success = { critical_fraction }`, `covered_by`, `defended_base`, `description`.
  - `covered_by` = the owner's other SAM rings reaching the target.
  - `defended_base` = an own base within 5 km that has defenses.
- **SAM sites:** mission types `suppression_of_air_defenses` + `destruction_of_air_defenses`. Critical = radars (pool roles sam_sr / sam_tr / ewr), else the whole site; fraction 0.5.
- **Early-warning sites:** mission types `strike` + `destruction_of_air_defenses`; fraction 1.
- **Mission-type names** are in full words: `suppression_of_air_defenses`, `destruction_of_air_defenses`, `strike`, `airfield_strike`, `close_air_support`.
- **Rules:** base defenses stay out of the catalog. Mission stages read only the catalog. The catalog is built before spawning; alive or dead is runtime state keyed by the same ids.

**Consumers:** `SpawnGroundGroups` (unchanged) for target units; `consumers/spawn_static_objects.lua` (`SpawnStaticObjects`) spawns static objects, looks each one up by name and compares its type; `consumers/draw_fixed_ground_targets.lua` (`CONFIG.DRAW_FIXED_GROUND_TARGETS`, mark ids 30000+).

**Spawn order rule — static objects before any AI units** (measured 2026-09-24).
- **Spawned after ~800 AI units:** 286 static objects took ~2–3 min inside `coalition.addStaticObject`. Planes cost ~3 s each (C-130 ~10 s), vehicles ~0.2 s, structures ~0.03 s.
- **What it isn't:** the probe (`survey/probe_parked_aircraft_spawn.lua`, `CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN`) ruled out livery and country. Every variant took ~0.00 s into an empty world.
- **Spawned first:** 247 objects took 7.4 s (45 planes 0.2 s), and the unit spawns didn't slow down. Init completes ~14 s after start.
- **Apply it to every later stage:** anything that spawns static objects spawns them before units.
- **Confirmed** on the next run: 250 objects in 0.5 s. The TEMP per-type `TIMING` lines were removed. The one-off ATZ-5 slowdown (6.6 s) was likely a first-time model load; if start-up ever slows again, the per-list timestamps in `dcs.log` show where.

**Load-time validation** (`PlanFixedGroundTargets.checkData`):
- every roster type exists in the right pool for its part's form, and parked-aircraft roles are aircraft;
- `requires` / `prefers` use real zone classes and values;
- each recipe has a critical part;
- density kinds and echelons agree with the recipes (it caught `garrison` listed for the rear while its recipe excluded it).

---

## 1. Concept
A mission generator for the **F-16C Block 50** on the **Kola map**. When the `.miz` loads, the script:

1. **Rolls the battlefield** — Syria-style cluster assignment: some clusters always Red, some always Blue, contested clusters randomized. Airbase ownership, F10 territory circles, dynamic-spawn slots all follow.
2. **Generates an ATO for a ~6-hour window** — a coherent set of Blue flights (CAP rotations, tanker tracks, AWACS, strike packages, SEAD, escort, CAS) *and* a Red ATO opposing it. **One Blue line is the player's flight**; every other line is flown by AI. The player does not know whether tonight is SEAD, CAS, airfield strike, CAP, etc. until the frag arrives. Everything must be *consistent with the roll*: targets in Red territory, launch bases Blue and in range, threats in between, TOTs deconflicted.
3. **Delivers the intel** — the player's frag with essentials on screen, the full ATO and intel sections in F10.
4. **Executes the ATO** — spawns AI flights on schedule, keeps the alive-aircraft count under a performance cap.
5. **Tracks the outcome** — knows when the player's objective is met or failed, reports it, feeds the cost tracker. Later: lets the player pick another ATO line after landing.

All F-16 role types in §4 are in scope. The Syria sandbox stays as-is; this is a sibling project, not a replacement.

See §1.9 for the ATO model — it's the organizing idea for the whole project.

Where the Syria project is a *sandbox* (everything spawns at T+0, players pick what to hit), this project is a *tasking generator*: the player gets a mission card, flies it, and the mission knows whether it succeeded.

**Players:** 1 for now, 2 F-16 slots (friend later). No AI in the player's flight.

### 1.1 The build order
The key architectural idea: **separate the plan from its execution.** `Planner.build()` is a pure function of (RNG, content catalog, config) that returns a plain Lua table. `Executor.run(plan)` spawns things. `Briefing.deliver(plan)` talks to the player. This lets us log the whole plan to a file, replay it, or dry-run the planner without spawning a single unit.

The plan is built in **stages**, each consuming the outputs of every stage before it and never reaching backward. Later stages can be *intelligent* because earlier stages have already fixed the facts they need.

```
 ┌────────────────────────────────┐
 │ 1. Base coalitions             │  cluster roll → base ownership
 │    + front geometry            │  + distance matrix, frontline bases,
 │                                │    cluster adjacency across the line
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 2. Base defenses (Red & Blue)  │  AAA / MANPADS / SHORAD at every base,
 │                                │  heavier at frontline bases
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 3. Fixed ground units          │  strategic IADS (ME late-activation),
 │    (Red & Blue)                │  strike targets (statics, depots, ships),
 │                                │  garrisons + Blue positions in ME zones
 │                                │  → THREAT MAP (SAM rings)
 │                                │  → TARGET CATALOG (what really exists)
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 4. Ground scheme of maneuver   │  moving units: Red pushes zone→zone,
 │    ("ground ATO", Red & Blue)  │  Blue reinforcements, convoys, TEL
 │                                │  deployments, recon targets
 │                                │  → CONTACTS (where/when sides meet)
 │                                │  → interdiction candidates
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 5. Red air ATO                 │  from stages 1–4 only. Clocked: CAP
 │                                │  stations/rotations, strike packages
 │                                │  vs Blue bases / ground units.
 │                                │  Standing posture: QRA per fighter base
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 6. Blue air ATO                │  from stages 1–4 only — does NOT read
 │    (AI + player)               │  the Red ATO. Support first (AWACS,
 │                                │  tankers); player line (type roll,
 │                                │  target, launch base, TOT T+60–90);
 │                                │  package by static rules (§1.10);
 │                                │  CAP rotations over the front; fill
 │                                │  under aircraft budget; routes + TOT
 │                                │  deconfliction; alert-CAP posture
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 7. Brief                       │  EOB from 3, GOB from 4, AOB from Red
 │                                │  standing posture (stations, base
 │                                │  types, QRA — no times), fidelity
 │                                │  rule applied; F10 tree; marks
 └───────────────┬────────────────┘
                 ▼
     plan table  →  Executor.run(plan)  →  Briefing.deliver(plan)
                →  Objectives.track(plan) → end state
```

#### Stage inputs → outputs

| Stage | Consumes | Produces |
|---|---|---|
| 1 Base coalitions | cluster table, RNG | `territory` (base → side), `clusterSides`, `front` (distances, frontline bases, adjacency) |
| 2 Base defenses | territory, front | defense groups per base (heavier on the front) |
| 3 Fixed ground | territory, front, content catalog (§1.2), ME zones | `threatMap` (SAM sites + rings), `targets` (instantiated catalog entries), garrisons/positions |
| 4 Ground maneuver | territory, front, zones, garrisons | `contacts` (Red/Blue meeting points + ETA), moving groups, interdiction candidates |
| 5 Red air ATO | stages 1–4 (territory, front, Red fighter bases, Blue-side targets) | Red ATO lines, Red standing posture (CAP stations, QRA per base) |
| 6 Blue air ATO | stages 1–4 + history file — **not** stage 5 | Blue ATO lines incl. the player's, routes, packages, Blue alert posture |
| 7 Brief | threatMap (3), contacts (4), Red standing posture (5), player line (6), fidelity rule | brief text, F10 menu tree, map marks |

#### Why this order
- **Defenses before fixed units:** fixed targets sit inside base defense umbrellas; the planner needs to know what's already there.
- **Fixed before moving:** moving units start from and go to fixed positions (garrisons, zones); contacts are only meaningful once both ends exist.
- **Ground before air:** CAS lines target *real* contacts with ETAs; interdiction lines target real convoys; the threat map is complete before any corridor is drawn.
- **Red air and Blue air are independent:** both are planned from stages 1–4 only. **No side reads the other side's plan.** Blue's packaging decisions are static lookups (SAM ring? fighter base nearby?), not predictions of Red's schedule. The order 5 → 6 is just so the brief can include Red's standing posture; nothing in 6 depends on 5. See §1.10.
- **Brief last, and derived:** generated from what was actually planned/spawned, so it can't lie; fidelity degradation is the only distortion. Red's *timeline* is never disclosed — only station areas and base posture.

#### Execution timing
Planning is pure data and fast. **Spawning** is the cost. Stages 1–4 spawn at T+0 (Syria does this in one frame; if the Kola ground layer is much bigger, spread spawns over a few seconds with `timer.scheduleFunction`). Stages 5–6 spawn on the ATO clock via the Executor's scheduler, under the alive-aircraft budget (§1.9).

**Spawn order at T+0 — static objects first, then AI units** (measured 2026-09-24).
- `coalition.addStaticObject` gets very slow once many AI units exist: ~3 s per parked aircraft after ~800 units, a 3-minute stall at start.
- Spawned before the units, the same objects take seconds, and the units are no slower.
- Every stage that adds static objects must spawn them ahead of all ground groups; `init.lua`'s spawn block is where this is kept.
- Details: "Fixed ground targets — as built".

**A player aircraft in the world slows every spawn** (found 2026-09-25).
- **Measured:** with a Client F-16 cold on the ramp at Bodø, 227 static objects took 71 s (~0.3 s each, spread evenly) instead of 0.5 s, even though they went first into an empty world. Base defenses took 16 s and SAM sites 11 s. The log shows "Control passed to the player" before the spawn began.
- **Decision (John):** remove the slot during development.
- **Final design:** the player comes in by dynamic spawn (§1.4) after "Init complete", so the T+0 world is built with no player aircraft present.
- **Still open for mid-mission spawns** (ATO flights, later convoys) while the player flies: spawn in small batches across frames (`timer.scheduleFunction`) so the sim doesn't freeze. Measure it when stage 5/6 lands.

### 1.2 Content catalog and the side-condition

Every piece of content declares where it lives and when it's valid:

```lua
{
    id        = "SAM_OLENYA_SA10",
    kind      = "sam_site",                 -- feeds mission types: sead, dead
    cluster   = "KOLA_CORE",
    valid_if  = "red",                      -- cluster must be Red
    me_groups = { "TGT_Olenya_SA10_SR", "TGT_Olenya_SA10_TR", "TGT_Olenya_SA10_LN" },
    pos       = ll(68.15, 33.46),
    success   = { kind = "destroy_any", of = { "TGT_Olenya_SA10_SR", "TGT_Olenya_SA10_TR" } },
    point_def = "by_threat",                -- spawn Syria-style tiered defenses
}
```

Contested clusters need **both** Red-side and Blue-side content pre-placed, because only one set gets activated:

| Content | Lives in | Valid when cluster is |
|---|---|---|
| SAM batteries, airfield statics, radar sites, depots | any Red-capable cluster | Red |
| "Attack X" CAS garrisons | contested / Red | Red |
| "Defend X" CAS positions (Blue ME groups) | contested | Blue — *and* an adjacent cluster is Red (attackers need somewhere to come from) |
| Ships in Kola Bay | KOLA_CORE | always Red |
| Dynamic templates (TEL hunt, convoy, recon box) | none — anchored on any Red base at runtime | — |

Rough ME content budget: **2–4 hand-placed target sites per Red-capable cluster**, plus one Defend + one Attack CAS site per contested cluster. Everything late-activation, named `TGT_<Base>_<Type>_<Part>` so the catalog and the ME stay in sync (same discipline as `RED_<Site>_SA2`).

> **Scope:** pre-placement applies only to **ME late-activation target groups** (SAM batteries, airfield statics, ships). All script-spawned ground — CAS garrisons, defend positions, armor — comes from **coalition-agnostic zones** (§1.12) assigned a side by the roll, which replace the "pre-place both sides" approach for those categories.

### 1.3 Feasibility matrix — what can be rolled given the territory

| Mission type | Needs | Guaranteed? |
|---|---|---|
| SEAD / DEAD | ≥1 `sam_site` in Red cluster within range | Yes — KOLA_CORE always Red and has several |
| Airfield strike | Red airfield with static templates | Yes |
| Infrastructure | `fixed_target` in Red cluster | Yes if KOLA_CORE has a few |
| Naval | Kola Bay ships | Yes |
| CAP / Sweep | Red fighter base within range | Yes |
| Escort | any strike target for the AI package | Yes |
| CAS Defend | contested cluster rolled Blue with a Red neighbor | **Not guaranteed** — skip type if none |
| CAS Attack | contested cluster rolled Red, or Red site | Usually |
| Recon | any Red base to anchor on | Yes |

Type weights are applied *after* filtering to feasible types, so a session never dead-ends. Recommend a **session history file** (we have `io`/`lfs` — de-sanitized) recording the last N mission types so the roller can down-weight repeats. Cheap, and it's the seed of campaign-style progression later.

### 1.4 Launch base
The planner **picks the launch base** and builds the whole flight plan from it (steerpoints, IP, TOT, fuel). The player reads the frag and spawns there via dynamic spawn. No enforcement, no personalized re-brief needed — the frag is the plan. Every Blue F-16-capable base needs dynamic spawn enabled in the ME since any of them can be chosen.

### 1.5 Briefing

One `outText` at T+0 with the **essentials only** — no chained/timed messages. F10 **Briefing** submenu holds the full sections for reading in the cockpit. Map marks carry the geometry.

**Essential (on-screen brief):**
- Tasking type, target name, target coords (DMS + MGRS + elev), desired effect
- TOT window
- Launch base, recovery base
- Steerpoints — coords only, one line each
- Tanker + AWACS: callsign, freq, TACAN
- Threats: CONFIRMED sites one line each; PROBABLE/POSSIBLE summarized as one line ("mobile SA-11 assessed vic. Kandalaksha; possible SA-15 at core bases")
- Recommended load

**Submenu only (F10 > Briefing >):**
- `ATO` — every line in the window (§1.9), player's line highlighted
- `Package` — who's flying with/ahead of the player, their TOTs and callsigns
- `Threats` — full EOB/AOB with confidence, rings, AOB per base
- `Target` — full description, composition, success criteria, attack axis
- `Support` — tanker track details, offload, AWACS, divert fields
- `Fuel & Times` — joker/bingo estimate, sunrise/sunset, TOT math
- `ROE / SPINS`
- `Re-show brief` — the essentials again

#### What's realistic for the pilot to know

Real-world briefing layers and what they'd contain here:

| Layer | Real-world content | Generator equivalent |
|---|---|---|
| **Frag** (from the ATO) | Mission #, callsign, # aircraft, mission type, target ID + DMPI coords + elevation, TOT, package (escort/SEAD/tanker), controlling agency | Mission type, target name/ID, exact coords (DMS + MGRS 10-digit + elev ft), TOT window, AI package callsigns, AWACS callsign |
| **SPINS / comm-nav** | ROE, IFF, tanker track/alt/TACAN/freq/offload, AWACS freq, divert fields, code words, sunrise/sunset | Tanker + AWACS data, divert = nearest 2 Blue bases, sunrise/sunset from mission time |
| **Mission data card** | Steerpoints w/ coords, altitudes, times; joker/bingo; freq presets | Steerpoints: launch base → (tanker) → push point → IP → target → egress → recovery. Coords for each. Estimated joker/bingo from distance. |
| **Intel — EOB** (electronic order of battle) | Fixed strategic SAMs: exact location, type, status. Mobile SAMs: "assessed" type + operating area, confidence probable/possible. AAA/MANPADS: generic warning only. | See fidelity rule below |
| **Intel — AOB** (air order of battle) | Types and numbers per base, CAP normally on station?, QRA reaction time | "Monchegorsk: Su-27/MiG-31 regiment. 2-ship CAP assessed on station vicinity X. QRA reaction ~10 min." |
| **Intel — GOB** (ground, for CAS) | FLOT, friendly unit + position, enemy unit type + axis, commander's intent, JTAC contact | Friendly group + smoke marker, enemy composition + attack radials (Syria CAS already does this), JTAC freq if using AI FAC |
| **Target materials** | Imagery, description, DMPI, desired effect, collateral limits, weaponeering, attack axis restrictions | Target description + composition, success criterion phrased as desired effect ("destroy the SA-10 engagement radar"), recommended loadout, attack axis suggestion from the IP geometry |

#### Threat-intel fidelity rule

Fidelity follows the threat's real-world nature, not a difficulty setting:

| Threat class | In brief as | Map |
|---|---|---|
| Fixed strategic SAM (SA-2/3/5/10) | **CONFIRMED** — type, exact coords, status, engagement ring | Ring drawn |
| Mobile SAM (SA-6/8/11/15/19) | **PROBABLE** — type + "operating vicinity <area>", or **POSSIBLE** — type only, region only; a fraction are **unlisted** | Area circle (±5–10 nm) or nothing |
| Point defense (AAA, MANPADS, ZSU) | Generic: "expect AAA/MANPADS in target area" | None |
| Air | Per-base type/number, CAP assessment, QRA timing | CAP station circle |
| Target itself | Exact — unless mission is CAS (JTAC-provided) or Recon (search box only) | Mark |

The per-session roll: for each mobile SAM the planner spawns, roll confirmed / probable / possible / unlisted with weights that can shift by mission "threat tier." Fixed sites are always confirmed. This gives surprise threats a realistic justification — the RWR is the last line of intel.

#### Brief template (draft)

```
=== FRAG ORDER — MSN 2041 — VIPER 1 (2x F-16CM) ===
TASKING:   SEAD / DEAD
TARGET:    SA-10 site OLENYA-SW  (TGT-KL-017)
           N68°07'12" E033°21'40"   35VNK 42815 61240   ELEV 610 ft
           Engagement radar (30N6) + 4 TELs. DESIRED EFFECT: radar destroyed.
TOT:       14:40–14:55Z
LAUNCH:    Rovaniemi (EFRO)  — 212 nm to target, bearing 041°
RECOVERY:  Rovaniemi. DIVERT: Ivalo, Kemi Tornio.

STEERPOINTS
 1 EFRO         N66°33'  E025°49'
 2 PUSH         N67°20'  E029°10'   FL250
 3 IP  "HAMMER" N67°58'  E032°40'   FL220  (18 nm SW of tgt)
 4 TGT          N68°07'  E033°21'
 5 EGRESS       N67°45'  E031°30'
 6 EFRO
FUEL:      JOKER 4.5  BINGO 3.2  (est., 2 bags)

PACKAGE / SUPPORT
 TEXACO 1   KC-135 MPRS  Track ALPHA  N67°00' E027°30'  FL220  251.0  TCN 51Y
 MAGIC      E-3A         264.0
 (no escort assigned)

THREATS — EOB
 CONFIRMED  SA-10  Olenya-SW      N68°07' E033°21'  (target)   ring 40 nm
 CONFIRMED  SA-3   Monchegorsk    N67°58' E032°52'             ring 13 nm
 PROBABLE   SA-11  battery operating vic. Kandalaksha–Alakurtti road
 POSSIBLE   SA-15  point defense reported Kola core bases
 Expect AAA / MANPADS at target.
THREATS — AOB
 Monchegorsk: Su-27 / MiG-31. 2-ship CAP assessed vic. N68°20' E032°00'. QRA ~10 min.

RECOMMENDED LOAD:  2x AGM-88C, 2x GBU-12, HTS, 2x AIM-120C, 2x AIM-9M, 2 bags, TGP
ROE:       Weapons free in Red territory east of the 029°E line. No strikes on civil airfields.
SUNSET:    15:12Z
=== F10 > Briefing to re-read any section ===
```

Sections map 1:1 to F10 **Briefing >** `Frag` / `Steerpoints` / `Support` / `Threats` / `Target` / `Full Brief`.

**Delivery caveats (DCS limits, to verify):**
- Script cannot push steerpoints into the player's jet; the pilot hand-jams from the brief or reads coords off the F10 marks. Realistic enough (pilots hand-jam all the time). DTC via ME is per-group and probably doesn't apply to dynamic-spawn slots — **[TODO test]**.
- Kneeboard pages are images and can't be generated by Lua at runtime. If we ever want a printable card, that's the pydcs/Python route (§7).
- `outText` has practical length limits and no scrolling; the full brief may need to be 2–3 chained messages or rely on the F10 sections for the long parts. **[TODO test]** the max readable length.

#### In-flight updates
Event-driven `outText`: "MAGIC: bandits airborne Monchegorsk, 2-ship, heading 270", "TEXACO on station", "Secondary: convoy sighted moving S on E105", objective met/failed, score delta. Result + "Roll next tasking" (phase 7) via F10 **Briefing > Status**.

### 1.6 Spawn timing
Target, point defense, and base defenses (both coalitions) spawn at T+0 (Syria pattern — proven). Red CAP and QRA are **event-driven** (timer after player takeoff, or player crossing the front line) so they aren't bingo before the player arrives.

### 1.7 Ground layer at T+0

The ATO (§1.9) covers the **air** picture. The **ground** picture is spawned at mission start, Syria-style, and is a first-class part of the battlefield:

1. **Airfield coalitions** — every base set per the cluster roll (`setCoalition`, `autoCapture(false)`, F10 circles, dynamic-spawn slots follow).
2. **Airfield defenses** — ground defenses at every base, both coalitions, sized by class × echelon and placed on surveyed open ground. **Built** — see "Base defenses — as built".
3. **Surveyed ground zones** — clearings drawn once in a survey `.miz` and committed as `data/zones.lua` (§1.12). A zone carries no side and no role; it inherits its cluster's rolled side in stage 1, and stages 3–4 decide what (if anything) to put in it this session from its size, its distance to bases and to the front, and road proximity. At T+0 the ground spawner places those units *inside their zones*. Zones can also be **movement corridors**: a unit group spawns in one zone and routes to another, giving Red armor pushing toward a Blue border town, Blue reinforcing a defensive line, convoys on real roads.

Why zones instead of Syria's ring-around-the-airbase random offsets: Kola is lakes, marsh, and forest the API can't see. Hand-placed zones in known clearings/along roads sidestep the whole terrain-validation problem (§6) and give the planner a real **GOB** to brief — "Red mechanized battalion assessed vic. Pechenga moving W" is true because a zone spawned it.

How the ground layer feeds the ATO:
- CAS lines (player or AI) target ground zones where opposing units are in contact.
- Strike/SEAD targets are still catalog entries (§1.2) — zones and targets share the same `cluster` + `valid_if` tagging.
- Secondaries (TEL hunt, convoy, recon box) are drawn from zone spawns.
- Rule of thumb still applies: nothing in the ground layer may be a juicier target than the player's frag, and roaming units stay clear of planned IPs/corridors.

Zone mechanics — generated naming, the survey-file pipeline, cluster-based side assignment, plan-side role assignment, and the `[side][role]` templates — are specified in **§1.12**. Still deferred to their own pass: force-level scaling (Syria `FORCE_LEVELS` pattern), how many zones per cluster, and whether opposing zones can be paired into "fronts" that fight each other without the player. **[LATER — own design pass]**

### 1.8 Session history
Write `Saved Games\DCS\kola_f16_history.lua` (or JSON-ish) after each plan: date, mission type, target id, launch base, outcome. Roller down-weights recent types. Controlled by a config flag: `HISTORY_ENABLED = true/false`, plus `FORCE_MISSION_TYPE = "sead"` / `FORCE_TARGET = "SAM_OLENYA_SA10"` overrides for testing.

### 1.9 The ATO model

Instead of planning one mission, the generator plans an **Air Tasking Order for a ~6-hour window** starting at mission time. Every line is a flight with a callsign, aircraft, mission type, target or station, and times. One Blue line is the player's; AI flies the rest. Red gets its own ATO.

#### ATO line structure
```lua
{
    msn       = "2041",              -- mission number
    side      = "blue",
    callsign  = "VIPER 1",
    ac_type   = "F-16C_50", count = 2,
    role      = "sead",              -- cap | sead | dead | strike | escort | cas | tanker | awacs | recce | airlift
    player    = true,                -- exactly one Blue line
    base      = "Rovaniemi",
    target    = "SAM_OLENYA_SA10",   -- catalog id, or station id for cap/tanker/awacs
    package   = "PKG-A",             -- lines sharing a package share a TOT window
    t_start   = 3600,                -- mission-relative seconds: spawn/startup time
    t_tot     = 5400,                -- time on target / on station
    t_end     = 7200,                -- off station / expected recovery
    tanker    = "TEXACO 1",
    control   = "MAGIC",
    route     = { ... },             -- steerpoints from §1.1 step 10
}
```

#### Coherence rules (what makes it feel like an ATO and not a spawn list)
1. **Support up first.** AWACS and tanker lines start before any package and stay up across the window (rotate tankers if > 3 h on station).
2. **CAP covers packages.** At least one Blue CAP line is on station over the corridor while any strike/SEAD package is inside Red territory. CAP rotations overlap by ~10 min.
3. **SEAD precedes strike.** If a package strikes a target inside a CONFIRMED SAM ring, a SEAD line has a TOT 3–5 min earlier on that ring's site.
4. **Escort by proximity.** If the target is within ~80 nm of a Red fighter base, the package gets an escort line (static rule — §1.10).
5. **TOT deconfliction.** No two packages have TOTs within 10 min of each other on targets < 30 nm apart; tanker rendezvous slots don't overlap.
6. **Reaction is one loop, not many triggers.** Red QRA and Blue alert CAP are spawned by the per-base scramble loop (§1.10), not by the ATO. CAP rotations and strikes are on the clock.
7. **Player's line lands at T+60–90 min TOT** so there's time to read the brief, plan, start up, and take off; earlier ATO lines are already airborne (CAP on station, tanker orbiting) when the player launches — the world is already in motion.

#### The player's place in it
- The player's role is rolled like before (§1.3 feasibility, history weighting); the ATO is built *around* that line, then filled out.
- Package missions (escort, SEAD-for-a-strike, strike-with-SEAD) fall out naturally: the player is one line, AI flies the others, the brief lists them under `Package`.
- After recovery, **F10 > Briefing > ATO** can offer "take line 2087" — the player picks another *not-yet-started* line in the window and gets a new brief. This is how a session chains 2–3 sorties.

#### Red ATO
Mirror structure, smaller: CAP rotations from Monchegorsk / Severomorsk-3 / Kilpyavr, QRA posture per base, 0–2 Red strike packages (Su-24/Su-34) against Blue border bases during the window. The intel **AOB** in the brief is derived from Red's *standing posture* (station areas, base types, QRA), degraded by the fidelity rule — never from Red's timeline. This also gives CAP/sweep player missions real customers.

#### Performance budget
DCS AI aircraft aren't free. Syria caps at 12 alive; here the target is **≤ ~20 alive at once** (tune by testing on the server box). The Executor enforces it: lines are spawned at `t_start`, despawned on RTB (Syria `S_EVENT_LAND` pattern), and the filler in step 8 of the pipeline is budget-aware — it only adds lines whose time windows fit under the cap. Rough shape of a 6-hour window: 1 AWACS, 1–2 tankers, 2 CAP rotations (2-ship each, 90-min cycles), 3–5 packages of 2–4 aircraft, plus Red's 2 CAP rotations + QRA + 1–2 packages ≈ 25–35 lines, 12–20 alive at any time.

#### Scope note — build it in layers
This is a big step up from "one tasking." Plan to build the *data model* fully from day one (an ATO is just a table, cheap) but execute it incrementally:
1. Player line + AWACS + tanker only.
2. + Blue CAP rotations (reuse `blue_air_support` pattern).
3. + Package lines around the player (SEAD/escort/second element).
4. + Red ATO (CAP, QRA, strikes).
5. + Filler packages, airlift/recce, "take another line" after landing.
At every layer the F10 `ATO` view shows only lines that actually execute — never fake lines.

### 1.10 Reaction model — keep it simple
**Hard rule: no side reads the other side's plan.** Neither planner predicts the other's behavior. Each side has objectives and planned missions built from the static picture; responsiveness comes from *one* cheap reaction loop per side plus DCS's native AI.

#### Plan-time: static facts only
Both ATOs are built from stages 1–4: territory, the front, the fixed ground picture (SAM sites, garrisons, bases), and each side's own assets. These are things both sides plausibly know — Red knows its own SAMs; Blue has imagery of fixed sites. Nobody knows the other side's schedule. Blue packaging is therefore a short table of **static lookups**, not a model of Red intent:

| Static fact | Blue packaging rule |
|---|---|
| Target inside a CONFIRMED fixed SAM ring | Add a SEAD line, TOT 3–5 min ahead of the strike |
| Target within ~80 nm of a Red fighter base | Add an escort line |
| Corridor crosses an assessed mobile-SAM *area* | Route around it, or HARMs on call |
| Distance to target > threshold | Assign a tanker line |
| Red fighter base within ~100 nm of a Blue base | Blue CAP rotation covers that sector |

Red uses the mirror of the same table for its own packages (Blue SHORAD at the target base → Red SEAD element, etc.), and places its CAP stations over its high-value areas.

#### What the brief says about Red air
Derived from Red's **standing posture** only — never its timeline: base → fighter types, assessed CAP station *area*, QRA reaction time. "Monchegorsk: Su-27/MiG-31. CAP station assessed vic. N68°20' E032°00' — expect contact if you enter that area. QRA ~10 min." That is the most Blue knows, and it's true because the same posture generated Red's actual CAP line. Fidelity rule applies (a station may be listed as POSSIBLE with a wider area, or omitted).

#### Execution-time: one reaction loop per side
One periodic check (every 30–60 s), one rule, mirrored for both sides:

```
for each fighter base of side S with alert fighters available and cooldown elapsed:
    if any enemy aircraft is within R nm of that base:
        scramble a 2-ship with an intercept task on the nearest enemy group
        decrement alert availability; start cooldown
```

- **Red:** this *is* QRA. Cheap to spawn, DCS AI intercepts well, no scripting of the fight itself.
- **Blue:** alert CAP scrambles the same way, plus an AWACS-style `outText` to the player ("MAGIC: bandits bullseye 045/60, 2-ship, hot").
- Caps and cooldowns per base keep it from spiraling and keep it under the aircraft budget (§1.9).
- Detection starts dumb (distance check over `coalition.getGroups`); can later be driven by a real Red EW radar's `getDetectedTargets()` without changing the shape.

#### Everything else is native DCS AI
- CAP flights on station with `EngageTargets` engage what enters their zone.
- SAMs engage on their own (Skynet, if adopted, adds HARM-aware behavior — §5.3).
- An AWACS unit in the mission feeds AI datalink awareness automatically.
- Strike packages with `REACTION_ON_THREAT` evade/abort on their own.

#### Why this feels authentic
The player gets what a pilot gets: fixed threats known, a CAP *area* to expect trouble in, a QRA warning. Push into the CAP area → the planned CAP is there. Get close to Monchegorsk → jets scramble. Cross a SAM ring → it shoots. No prediction on either side — posture plus a tripwire.

#### Red is not tuned to the player
Red defends what Red values, with no knowledge of which target is the player's. CAP stations and SAM density weight toward Red's high-value areas (Olenya, Severomorsk, the core) — which is where the good targets are, so coverage emerges without special-casing. Variance is accepted; the history-weighted type roll, per-target threat tiers, and "take another line" after landing handle quiet nights.

### 1.11 Weather as a planner input
The runtime **can read** the mission's weather, time, and date — only *changing* them is impossible (that's §7). So weather is a first-class input to the plan, read once in the gather-inputs step (§11.3 step 3) and stored on `plan.world.weather` / `plan.world.date`. Even fixed ME weather becomes something the planner adapts to instead of ignoring.

**Sources (all plain data, read at T+0)** — field names *pinned from a real 2.9 plan dump* (2026-09-22):
- `env.mission.weather`: `clouds{ base, thickness, density, iprecptns, preset }`, `wind{ atGround | at2000 | at8000 = { dir, speed } }`, `fog{ visibility, thickness }` + `enable_fog` (the legacy fields are what 2.9 still exposes — no `fog2` seen), `visibility{ distance }` (a table, not a number), `qnh` **in mmHg**, `season{ temperature }` °C, `dust_density` / `enable_dust`, `groundTurbulence`, `halo{ preset }`, `cyclones{}`, `atmosphere_type`, `type_weather`, `modifiedTime`, `name`.
- **Preset weather stores only `clouds.preset` + `clouds.base`.** Coverage, layers and precipitation live in `DCS World\Config\Effects\clouds.lua`; `tools/cloud_presets.py` extracts them to `kola_f16/data/cloud_presets.lua` (34 presets: id, ME short name, ED's METAR text, coverage word, `precipitationPower`, base range, layers). Re-run after DCS updates.
- **Wind `dir` convention:** the `.miz` stores the direction the wind blows *to*; the ME shows *from* (`dir + 180`). Gather also samples `atmosphere.getWind()` at the airbase centroid so the debug display can confirm this in-sim. **[verify on first run]**
- `env.mission.date` `{Year,Month,Day}` and `env.mission.start_time` (local seconds since midnight; Kola clock is **UTC+3**, from pydcs `terrain/kola`); `timer.getAbsTime()` for the running clock.
- Point queries: `atmosphere.getWind(pt)`, `atmosphere.getWindWithTurbulence(pt)`, `atmosphere.getTemperatureAndPressure(pt)` (returns K, Pa).

**What the plan holds** (`lib/weather.lua`, called from gather): `plan.world.weather = { clouds{ preset, name, metar, coverage, base_m/ft, ceiling_ft (only if BKN/OVC), precip }, visibility_m/sm (ME distance capped by fog and by a rain preset's stated VIS range), fog, flight_rules (VFR/MVFR/IFR/LIFR), wind{ ground/at2000/at8000 = { from_deg, to_deg, mps, kts }, measured_ground }, temp_c, qnh{ mmhg, hpa, inhg }, turbulence, dust, raw }` and `plan.world.time = { date, day_of_year, season, utc_offset_h, start_hhmm, start_utc_hhmm, abs_time, sun{ ref, elev_deg, condition (day / civil / nautical twilight / night), sunrise, sunset, civil_dawn, civil_dusk, polar ("midnight sun" / "polar night"), max/min_elev } }`. Sun is evaluated at the **airbase centroid** for now; per-base evaluation (launch/recovery light) is a stage-6/7 job using the same `Weather.sunElevation`.

**Why it drives what gets created** — weather is a filter/weight applied through stages 1–6 and a brief section in stage 7:

| Weather fact | Planner consequence |
|---|---|
| Low ceiling / thick cloud | Down-weight LGB / visual-TGP / visual CAS; favor **JDAM / HARM / radar-cued** (GPS-INS works through cloud). Shifts §1.3 feasibility + recommended load. |
| Poor visibility / fog / precip | Suppress Recon (visual confirm) and CAS visual ID; widen mobile-SAM "assessed area" fidelity (bad wx = vaguer intel, in-fiction). |
| Night / polar night (date + time + lat) | Force TGP/NVG-appropriate loads, bias IR/GPS weapons, may suppress visual CAS. The §3 polar-night concern as a live input. |
| Wind aloft (speed/dir) | Orient tanker track + CAP station into wind; pick launch base / runway favouring an into-wind heavy departure. |
| Temp + QNH + field elevation | Density-altitude check → exclude a short/hot/high base from the launch pool (§3 runway concern); correct altimeter in the brief. |
| Ceiling + visibility together | **VFR vs IFR** determination per base → whether visual takeoff/recovery is viable; drives divert/recovery choice and the SPINS card. |

Composes cleanly with the pydcs route (§7 option 3): **Python sets weather/time, Lua reads and reacts** — no coupling.

### 1.12 Zones — the ground-unit dataset  *(revised 2026-09-22)*
Implements the §1.7 ground layer. **Every ground unit except base defenses spawns inside a surveyed zone.** A zone is exactly one thing: **a clearing where ground units can realistically be placed.** The dataset is **locations and sizes, nothing more** — no side, no role, no substance, and nothing about the front, which doesn't exist until stage 1 has run. The other fields in an entry (`base`, `brg`, `km`, `cluster`) are derived from the position against the fixed airbase list and are static facts about the map; every session-dependent decision is made by the planner at run time.

**Survey `.miz`, not the mission `.miz`.** Zones are drawn as ME trigger zones in a dedicated survey file (`Saved Games\DCS\Missions\khola_ground_zones.miz`) that is never flown. `tools/miz_zones.py` parses `mission.triggers.zones` out of it into the committed `kola_f16/data/zones.lua`; that data file is the **only** source the plan reads. The real mission `.miz` contains none of these zones, so there is no `trigger.misc.getZone()` at runtime and no need to keep ME names in sync with anything. Target list: ~100 zones, drawn once. Map "Draw" objects live in `mission.drawings` and aren't parsed — use the trigger-zone tool.

**Circle or quad.** On disk each zone has `x` (North), `y` (East) in **projected metres**, plus `type`: `0` = circle (has `radius`), `2` = quad (has 4 `verticies`). Circles for small clearings; quads for larger irregular areas (assembly areas, recon search boxes) — draw the polygon around the actual clearing/road so units only ever spawn on good ground (§6). One helper — **"random valid point in zone"** (disc-sample for circle, polygon-sample for quad, keeping the `isOnLand` / `isFlatEnough` retry) — is the single primitive stages 3–4 use to place ground units.

**Coordinates: store projected, derive GPS in-sim.** The dataset keeps projected `x,z` (`z` = the file's `y`/East, renamed so it can't be confused with altitude); the spawner consumes those directly. **Lat/Lon → DMS/MGRS is computed in-sim** via `coord.LOtoLL` at brief time (stage 7). Matches the §11.5 `pos = { x, z, lat, lon }` shape. (The tool also computes lat/lon offline with its own transverse-Mercator implementation, `tools/kola_proj.py`, for the review comments — verified to ~10 m against published airport coordinates.)

**Names are generated, never typed.** `ZONE_<BASE>_<brg>_<km×10>` from the nearest airbase: `ZONE_KITT_100_012` is 1.2 km on bearing 100° from Kittilä; `ZONE_SEV1_341_097` is 9.7 km NNW of Severomorsk-1. `BASE` is a 4-letter code per airbase (`tools/kola_airbases.json`). Reads like a radio fix in logs and briefs, unique in practice; a genuine collision (same base, same degree, same 100 m ring) gets a `B`, `C`… suffix ordered by `zone_id`, and the tool reports it. Hand-typed ME names are ignored. Each entry also keeps the ME's internal **`zone_id`**, which is stable while the zone exists even if it's nudged (the name would change) — anything that must reference a specific zone (a catalog entry) keys on `zone_id`.

**Role is assigned by the plan, not the zone.** What goes in a zone on a given session is decided in stages 3–4 from things the planner already knows:

| Signal | Source | What it implies |
|---|---|---|
| Radius / area | the zone | what *fits*: a SAM battery ~50 m, a garrison ~150 m, an armor assembly area 300 m+, a recon box = big quad |
| Distance to nearest base (`km`) | the zone | close → base-adjacent (garrison, SHORAD); far → field site |
| Distance to the front | stage 1 | near → armor/mech assembly, contacts; deep → SAM, depot, convoy node |
| Road proximity | `land.getClosestPointOnRoads` in-sim | convoy node, corridor endpoint |
| Rolled side | stage 1 | which `[side][role]` template pool |

Role vocabulary (plan-side): `armor`, `mech`, `garrison`, `sam`, `recon`, `convoy_node`. **"Attack" / "Defend" is not a role** — it's relational, emerging at stage 4 where an owned zone is adjacent to an enemy-owned zone (`contacts`). Unit templates are keyed by `[side][role]` (the `INFANTRY_POOL` / `BLUE_INFANTRY_POOL` split from `cas_mission.lua`). A zone that *must* be a specific thing can carry an ME zone property `role=…` as an override; expected to be rare.

**Side anchor — option A (cluster tag).** Each zone carries a `cluster` and inherits that cluster's rolled side in stage 1 — the direct parallel to how bases are listed under clusters. Chosen over "nearest-owned-base" (B) because it keeps territory coherent and lets a zone be a **forward outpost** (the Syria `AT_TANF` pattern). The tool sets `cluster` from the nearest base's cluster in `data/clusters.lua`; an ME zone property `cluster=…` overrides it for the exceptions (zones 35–55 km from any base are where the guess is weakest).

**Movement corridors = zone pairs.** A Red push is a start zone → end zone pair (both in the same cluster); the moving group belongs to the **start zone's** side. Contacts fall out where the corridor meets enemy-owned ground.

**Pipeline:**
```
draw trigger zones in survey .miz ─save─▶ khola_ground_zones.miz
        │  python tools/miz_zones.py <miz>     (offline; stdlib only)
        ▼
  kola_f16/data/zones.lua    committed, pure data:
                             { name, zone_id, cluster, base, brg, km,
                               type, x, z, radius | verts }
        ├───────────────┐
        ▼               ▼
  data/catalog.lua   gather-inputs (T+0): read both, derive lat/lon,
  (hand-authored,    apply stage-1 side → plan.world.zones
   keyed by zone_id: stages 3–4 assign roles → plan.fixed / plan.ground
   per-site detail,
   success criteria)
```
Committed data over a live read so the dataset is reviewable/diffable in git; regenerated whenever the survey changes (rarely — the survey is drawn once). Rich per-site detail lives in the companion catalog keyed by `zone_id`; most zones need no catalog entry and are populated from the generic `[side][role]` template.

**Tooling (all under `tools/`, no external dependencies — pydcs is reference material only):** `dcslua.py` reads/writes DCS's Lua-table serialization; `kola_proj.py` is the Kola projection (WGS84 TM, CM 21°E, k₀ 0.9996, FE −62702, FN −7543625); `kola_airbases.json` holds the 37 Kola airbase positions + codes (extracted once from pydcs's airport data); `miz_zones.py` is the parser.

**Zone classes (added 2026-09-24):** static facts about each zone, one question each, written into `data/zones.lua` by `miz_zones.py`: `size`, `airfield_distance`, `ground`, `terrain`, `road_access`, `railway_access`, `water`, `radar_view`, `settlement`, `prepared_sam_position` + `surveyed` + `measured`. The terrain facts come from flying the zone drawing mission once; `kola_f16/survey/survey_zone_terrain.lua` writes `Saved Games\DCS\kola_zone_terrain.lua` and the tool merges it by zone id. Workflow after drawing or moving zones: save the .miz → fly it once → `python tools/miz_zones.py "<.miz>"`. Classification never runs in the flyable mission (John). Details in "Where we are", session 5.

### 1.13 Unit pool — every spawnable DCS unit  *(2026-09-22)*
**What DCS needs to spawn a unit is one string.** `coalition.addGroup(country, category, { units = { { type = "BTR-80", … } } })` — the `type` string is the unit's whole identity; everything else per unit is placement (position, heading, skill). Country is always `CJTF_RED` / `CJTF_BLUE` (the scripting API doesn't restrict types by nation), category is per group. Statics add `shape_name`, aircraft add a payload of pylon CLSIDs. An unknown string doesn't error — DCS substitutes a Leopard-2 and logs `woCar: … replaced with Leopard-2`.

**`data/unit_pool.lua`** — every AI-operable unit in base DCS (incl. the CoreMods packs: Currenthill `CHAP_*`, ColdWar, Massun92, HeavyMetal; nothing from `Saved Games\Mods`), generated by `tools/unit_pool.py` from pydcs's `vehicles.py` / `planes.py` / `helicopters.py` / `ships.py` (themselves generated from DCS's own database). Segmented `ground` / `plane` / `helicopter` / `ship`, keyed by exact type string. **Side-, country- and era-agnostic by design** — Blue may field Russian SAMs; which coalition uses what is a `coalition_rosters` decision, not a pool property. Per entry: `type`, `name`, `cat` (pydcs category), `role` (planner tag: `sam_sr / sam_tr / sam_ln / sam_cp / shorad / ewr / aaa / aaa_sp / manpads / mbt / ifv / apc / recon / atgm / arty_sp / mlrs / truck / fuel / c2 …`; air: `fighter / multirole / strike / awacs / tanker / transport / recon / attack`), `system` (SAM family for site recipes: `SA-10`, `Patriot`, `Hawk`, `SA-2/3/5` …), ED's `detection_m` / `threat_m` / `air_weapon_m` (the seed for CONFIRMED-ring radii, §1.5), and for aircraft `tasks` (DCS task names the AI can fly — the ATO's feasibility input), `task_default`, `fuel_max`, `chaff`/`flare`, `pylons`, `flyable`, `large_parking`, `tacan`. `static` (added 2026-09-24) holds every structure / cargo static-object type from pydcs `statics.py` with its `category` and `shape_name`; `weapons = {}` is still a stub. Roles come from name heuristics in the tool plus `tools/unit_role_overrides.json`; the tool reports anything unclassified. Re-run after a DCS update once pydcs has caught up.

**`data/aircraft_pylons.lua`** — per-aircraft pylon → allowed weapon CLSIDs (1.1 MB). Deliberately *not* in the pool and *not* loaded by `init.lua`; it exists so hand-authored loadouts (`data/loadouts.lua`, later) can be validated offline before DCS sees them. Verified: the Syria F-16 CAS loadout validates on all four pylons.

**Not in the pool:** side, nation, era, cost, loadouts, static-object flag (that's a spawn option — any vehicle/plane/ship type can be placed static), SAM site composition (→ `data/sam_site_recipes.lua`, later).

---

## 2. Why the F-16 changes the design

The A-10/F-16/F-18 Syria mission is really an A-10 mission with other slots. The F-16C Block 50 is a different animal and the generator should be built around what it's actually for:

| F-16 role | DCS loadout | Generator implication |
|---|---|---|
| **SEAD / DEAD** | AGM-88C HARM + HTS pod, GBU-12/38 for the kill | The Block 50's signature job. Needs a real, randomized IADS with emitting radars — not scattered SA-9s. |
| **Precision strike** | GBU-31/38 JDAM, GBU-12/10 LGB, AGM-65D/G/H, CBU-97/105 | Needs fixed, hard targets: bunkers, radars, fuel farms, parked aircraft, bridges, moored ships. JDAM on statics = coordinates matter → mission card must give precise DMS/MGRS. |
| **CAP / Sweep / Escort** | AIM-120C, AIM-9M/X | Needs Red AI fighters that actually launch: MiG-29/31, Su-27/33/34 from Kola bases. Syria has no air threat at all. |
| **CAS** | Maverick, GBU-12, CBU | Direct reuse of Syria `cas_mission.lua`. |
| **Anti-ship** | JDAM / LGB against moored ships, Maverick vs small craft (no Harpoon on DCS F-16) | Northern Fleet in Severomorsk / Polyarny / Kola Bay — moored statics are viable JDAM targets. |
| **Recon** | TGP, eyes | "Find and report" — locate a mobile target in a search box, confirm via F10. Cheap to build, good filler. |

**Range is the real constraint.** Bodø → Murmansk is ~700 km. Rovaniemi → Olenya ~450 km. The F-16 with 2 bags and a strike load is tight past ~300 nm radius. Every mission needs either a forward base or an AI tanker on station — the generator should pick the launch base *based on* target distance, or spawn a tanker track when it can't.

---

## 3. Kola map facts

### Size & geography
- ~1,400 km E-W × ~1,000 km N-S ([ED product page](https://www.digitalcombatsimulator.com/en/products/terrains/kola_terrain/)). Covers northern Norway, Sweden, Finland, and the Kola Peninsula / Murmansk oblast.
- Russian side: Northern Fleet home — Murmansk, Severomorsk, Polyarny sub bases; dense cluster of airfields and installations in the Kola–Karelia corridor.
- Terrain: taiga/tundra, huge numbers of lakes and marsh, sparse roads, fjords on the Norwegian coast. Deep snow much of the year. **Off-road ground spawning will be harder than Syria** — lakes read as `WATER`, forest is invisible to the API, and roads are few.
- Lighting: high latitude. Polar night in winter, midnight sun in summer. Time-of-day randomization matters more here than on Syria (see §7 — can't be done in Lua at runtime).

### Airbases — exact DCS name strings
Source: MOOSE `AIRBASE.Kola` enumeration ([Airbase.lua](https://github.com/FlightControl-Master/MOOSE/blob/master/Moose%20Development/Moose/Wrapper/Airbase.lua)). **Verified in-sim** (2026-09-23): all 37 names in `data/clusters.lua` resolve in gather, and the base-defense run covered every one. Gather warns on any name that stops resolving after a map update.

| Country | Bases (DCS string) | Notes |
|---|---|---|
| **Norway** | `Bodo`, `Bardufoss`, `Evenes`, `Andoya`, `Tromso`, `Banak`, `Alta`, `Kirkenes` | Bodø = premier Blue hub (long runway, far from threat). Banak/Kirkenes are right on the Russian border. |
| **Sweden** | `Kallax`, `Vidsel`, `Kiruna`, `Jokkmokk`, `Kalixfors`, `Arvidsjaur`, `Hemavan`, `Boden Heli Base` | Kallax (Luleå) = second Blue hub. Vidsel = test range. Jokkmokk/Kalixfors are Swedish dispersal strips — check runway length. |
| **Finland** | `Rovaniemi`, `Kemi Tornio`, `Kuusamo`, `Ivalo`, `Kittila`, `Enontekio`, `Sodankyla`, `Hosio`, `Vuojarvi` | Rovaniemi = Finnish AF fighter base, closest big Blue base to Kola. Ivalo/Sodankylä are within ~200 km of the border. |
| **Russia** | `Murmansk International`, `Severomorsk-1`, `Severomorsk-3`, `Olenya`, `Monchegorsk`, `Afrikanda`, `Kilpyavr`, `Koshka Yavr`, `Luostari Pechenga`, `Alakurtti`, `Kalevala`, `Poduzhemye` | Olenya = long-range aviation (Tu-22M/Tu-95 statics = great strike targets). Monchegorsk = fighters. Severomorsk-3 = naval aviation. Kalevala/Poduzhemye are far south in Karelia. |

High-detail airports per Orbx: Rovaniemi, Kemi-Tornio, Kuusamo, Ivalo, Severomorsk-1/-3, Murmansk, Bodø, Kirkenes, Banak, Kiruna, Jokkmokk, Luleå, Vidsel, Kalixfors ([Threshold preview](https://www.thresholdx.net/news/tekola)).

8 + 8 + 9 + 12 = 37 airdromes.

**[TODO]** F-16 launch-base viability. Runway lengths are no longer a research item: gather reads them live (`plan.world.airbases[name].runways[].length`). What's still missing is the rule that turns length into "can launch a loaded F-16" (Syria's `research_runway_lengths.md` uses 2,500 m+ / marginal / too short), applied when stage 6 picks a launch base. Suspect short: Jokkmokk, Kalixfors, Hemavan, Hosio, Enontekiö, Kalevala (568 m helo strip).

### Proposed clusters (Syria-style, for `coalition_setup`)

Finland and Sweden are NATO members as of 2023/2024, so "all Nordic = Blue" is the realistic baseline. The interesting contested zones are the border regions.

*(Revised 2026-09-22 — this is what `data/clusters.lua` holds.)*

| Cluster | Type | Bases | Notes |
|---|---|---|---|
| **NORWAY_REAR** | Always Blue | Bodø, Evenes, Andøya, Bardufoss, Tromsø | |
| **SWEDEN** | Always Blue | Kallax, Vidsel, Kiruna, Jokkmokk, Kalixfors, Arvidsjaur, Hemavan, Boden | |
| **FINLAND_SOUTH** | Always Blue | Rovaniemi, Kemi Tornio, Hosio | |
| **FINNMARK_EAST** | Contested, p_red 0.7 | Kirkenes | 56 km from Luostari — first to fall |
| **LAPLAND_EAST** | Contested, p_red 0.5 | Ivalo, Sodankylä, Vuojärvi | E75 corridor, ~170 km from Red |
| **FINLAND_EAST** | Contested, p_red 0.5 | Kuusamo | 121 km from both Alakurtti and Kalevala |
| **KOLA_SOUTH** | Contested, p_red 0.75 | Afrikanda, Alakurtti | Blue = NATO counter-offensive, kept rare |
| **FINNMARK_WEST** | Contested, requires FINNMARK_EAST Red | Banak, Alta | 250–300 km deep |
| **LAPLAND_WEST** | Contested, requires LAPLAND_EAST Red | Kittilä, Enontekiö | 250–330 km deep |
| **KOLA_CORE** | Always Red | Murmansk Intl, Severomorsk-1, Severomorsk-3, Olenya, Monchegorsk, Kilpyavr, Koshka Yavr, Luostari Pechenga | |
| **KARELIA** | Always Red | Kalevala, Poduzhemye | |

Six contested clusters → 64 possible maps. Two mechanics keep it plausible: **`p_red`** weights the roll per cluster, and **`requires_red`** makes a deep cluster roll only if its border-tier neighbour already fell (evaluated in file order), so Russia can't hold Alta while Kirkenes stays NATO. Kuusamo and KOLA_SOUTH border Red directly and roll independently. The IADS in KOLA_CORE can be hand-placed with real-world fidelity since that cluster is always Red.

---

## 4. Mission catalog (draft)

Each session rolls one **primary** from the weighted pool, then 0–2 **secondaries**. Every mission carries `{ type, target, threat_level, launch_base, support }`.

### 4.1 Primary mission types

| # | Type | Target | What gets spawned | Success condition |
|---|---|---|---|---|
| P1 | **SEAD** | One SAM battery (SA-2/3/6/11/10) | Late-activation ME battery + dynamic point defense (SA-15/Shilka/MANPADS) + optional decoy emitter | Search/track radar dead |
| P2 | **DEAD strike** | Full SAM site incl. launchers | As P1, plus ammo trucks/statics | ≥ N% of battery destroyed |
| P3 | **Airfield strike** | Parked aircraft / fuel farm / HAS at a Red base | Static aircraft (Tu-22M3, Su-24, MiG-31), fuel tanks, dynamic AAA | ≥ N statics destroyed |
| P4 | **Infrastructure strike** | Radar site / comms / bridge / depot | Statics + light defenses; bridge = map object (scenery destruction works via `destroy` on scenery? — **verify**) | Target destroyed |
| P5 | **Naval strike** | Moored ships in Kola Bay / Severomorsk | Ship units (stationary) + SA-N point defense; or statics | Ship(s) sunk |
| P6 | **CAP / Sweep** | Red air activity | Red fighter groups launched on a schedule toward Blue airspace | Survive N minutes / kill N bandits |
| P7 | **Escort** | Blue AI strike package | Blue AI F-16/F-18 strike + Red fighters vectored to intercept | Package survives to target |
| P8 | **CAS** | Ground battle | Direct port of Syria `cas_mission.lua` | Red attackers reduced below threshold |
| P9 | **Recon / Find** | Mobile target in a 20×20 km box (SS-26 TEL, S-300 relocation, convoy) | Dynamic ground group, no marker | Player confirms via F10 "Target sighted" within N km |

### 4.2 Secondary objectives (small, 1–3 units)
- Scud/Iskander TEL hunt (Syria S&D port)
- Convoy interdiction (Syria convoy port)
- EW radar site (single emitter, MANPADS)
- Helicopter FARP

### 4.3 Threat layers (independent rolls)
- **Air threat:** none / CAP on station / QRA scramble on detection / both. Red fighter pool: MiG-29A/S, MiG-31, Su-27, Su-33 (from Severomorsk-3), Su-34.
- **IADS density:** low / med / high — controls how many *extra* SAMs spawn along the ingress corridor beyond the target's own defenses.
- **Point defense:** as Syria threat tiers, plus SA-15 Tor and SA-19 Tunguska at high.

### 4.4 Support layers
- **Tanker:** KC-135 MPRS / KC-130 on a track ~150 nm behind the front. Spawn when target distance from launch base > X nm. Give freq/TACAN in the card.
- **AWACS:** E-3A on a racetrack over Norway/Sweden. Always-on is fine (cheap).
- **Blue CAP:** 2-ship AI F-16/F-18 for the CAP/Escort missions and as a comfort layer at low threat.
- **Blue SEAD escort:** optional AI 2-ship with HARMs when the primary is a strike into a high-IADS zone.

---

## 5. Architecture

### 5.1 Relationship to the Syria code

Kola is a **completely separate** script tree (`kola_f16\`) — nothing in the Syria tree is touched and there is no shared library; Kola keeps its own copies of whatever it borrows. Rationale, layout, and load order are in §11.1 / §11.6. What ports over cleanly and what's genuinely new are below.

### 5.2 What ports over cleanly
- `spawner.lua` — as-is (ring spawn, flatness, land check, routes, fireGroups). Add an MGRS formatter for the F-16 (`coord.LLtoMGRS`).
- `logger.lua` — as-is.
- `cost_*` — as-is; F-16C_50 cost already present. Add HARM (`AGM_88C` already there), add Red fighter kill values (mostly there).
- `coalition_setup.lua` pattern — new cluster table, same logic.
- `sam_setup.lua` pattern — new site table; extend for SA-3/SA-10/SA-11/SA-15.
- `blue_air_support.lua` — becomes the template for **all** AI air spawning (tanker, AWACS, CAP, strike package, Red fighters). Its Orbit + EngageTargets + WEAPON_FREE lessons are the hard-won part.
- `cas_mission.lua`, `convoy_setup.lua`, `sd_mission.lua` — port as P8 / secondaries, with Kola unit pools and terrain checks tightened.

### 5.3 New plumbing needed

1. **Mission catalog + roller** — weighted random selection, mutual-exclusion rules (no Escort + CAP together), secondary picker.
2. **Target templates** — a data-driven way to describe a target: `{ statics = {...}, units = {...}, defenses_by_threat = {...}, success = { kind="destroy_pct", pct=0.6 } }`. Hand-placed ME late-activation groups for real-world fidelity (SAM sites, airfield statics) + dynamic fill.
3. **Objective tracking** — a per-mission event handler counting kills against the target set → success/fail state, on-screen result, cost-tracker bonus. This is the one thing Syria genuinely lacks.
4. **Red air AI** — spawn-on-schedule and spawn-on-trigger (player crosses a line / a radar detects). Needs a decision on GCI logic: hand-rolled `EngageTargets` vectors vs. **Skynet IADS** for the SAM side (no dependencies, fits the no-MOOSE stance — [Skynet](https://github.com/walder/Skynet-IADS)). **[Q]** Willing to take Skynet as the one external dependency? It gives SAMs that go dark when HARMs fly, EW-radar-cued launches, and coordinated sectors — a big step up for SEAD gameplay.
5. **Launch base selection** — pick the Blue base by target distance and runway length; the whole flight plan is built from it and the player spawns there (§1.4). Requires F-16 dynamic spawn enabled at every candidate Blue base in the ME.
6. **Support package** — tanker/AWACS spawn helper with TACAN/freq via `ActivateBeacon` + `SetFrequency` commands; string these into the card.
7. **Mission card** — one `outText` + F10 "Briefing" entry + map marks. Contents: task, target desc, coordinates (DMS + MGRS), threat summary, recommended loadout, launch base, tanker/AWACS freqs, TOT window if any.
8. **Mission end** — success/fail detection → summary → optional "roll next mission" F10 command so a session can chain 2–3 taskings without a mission restart.

---

## 6. Kola-specific technical risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Ground spawns in lakes/marsh | Thousands of lakes; `nearPos` will hit water constantly | Keep `isOnLand` + retry; raise retry count; prefer road-snap and ME-placed anchors for anything that must be flat |
| Forest (invisible to API) | Vehicles spawn in trees, can't move, can't be seen | Prefer hand-placed anchor zones (trigger zones in ME at known clearings) for CAS/S&D; dynamic offsets only within those zones |
| Ground AI movement | Sparse roads, long distances → convoys stall | Shorter routes (cap ~100 km), on-road only, test early |
| Range / fuel | F-16 bingo on long legs | Tanker always available when distance > threshold; launch-base selection |
| Runway lengths | Several Nordic strips may be too short for a loaded F-16 | Research table (TODO above); exclude from launch-base pool |
| Airbase name strings | Same trap as Syria | `Log.dumpAirbases()` on a timer (the T+0 empty-table issue) |
| Red air AI competence | Su-27s with `EngageTargets` can be either lethal or useless | Start with ME-defined CAP templates activated by script; tune skill per threat level |
| Skynet + no-MOOSE stance | Skynet is standalone but ~200 KB and has its own conventions | Prototype it on one SA-6 site before committing |
| Polar night | Dark missions need TGP/NVG; players may not want them every time | Can't fix in Lua — see §7 |

---

## 7. Out-of-sim randomization (weather / time / statics)

Lua at runtime **cannot** change weather, time of day, or date. On Kola that's a real loss (polar night vs midnight sun, snowstorms). Options:

1. **Live with it** — fixed ME weather/time, all randomness in-sim. Simplest; what Syria does.
2. **Multiple `.miz` files** — 3–4 hand-made variants (summer day / winter twilight / storm), pick one at server start. Cheap, coarse.
3. **pydcs pre-generation** — a Python step (you already source CLSIDs from [pydcs](https://github.com/pydcs/dcs)) writes the `.miz` before launch: random weather, time, date, and can also place statics/SAM sites programmatically with validated type names. In-sim Lua then handles the dynamic parts. **Big upside:** pydcs knows every unit type string, so the Leopard-2 silent-replacement bug class goes away for anything it places.

Recommendation: **option 1 now** (fixed ME weather/time, all randomness in-sim) so the Lua side gets built first; **option 3 (pydcs pre-gen) as a later phase** (§8 phase 8) — the most powerful path, and `desanitize_dcs.py` already runs Python on the server box. Still open (§9).

---

## 8. Phased plan (proposal)

| Phase | Deliverable | Reuses | New |
|---|---|---|---|
| **0** | Kola `.miz` with dynamic-spawn F-16 slots at Blue bases, de-sanitize check, `dumpAirbases()` confirming all names, `dumpWeather()` pinning weather field names (§1.11), runway table; survey zones drawn + parsed into `data/zones.lua` (§1.12) — **done for the first 12** | Install flow, `dumpGroups`/`dumpLateGroupUnits` | Runway research, weather dump, zone parser |
| **1** | Kola `init.lua` + gather-inputs + stage 1 (territory/front); `coalition_setup` with clusters; F10 skeleton — **done** except the F10 skeleton | logger, spawner, cost_* | cluster table, stage pipeline |
| **1b** | Stage 2 base defenses at all 37 bases, both coalitions; footprint survey; generic ground spawner — **done 2026-09-23** | — | anchors placement, rosters, level matrix |
| **2** | **Strike primary (P3/P4)** against ME-placed statics at Red airfields + point defense; objective tracking; mission card | sam threat tiers | catalog roller, objective tracker, card |
| **3** | **SEAD/DEAD (P1/P2)** with 3–4 hand-placed batteries; Skynet prototype on one site | sam_setup pattern | Skynet integration, HARM scoring |
| **4** | Support package: tanker + AWACS with TACAN/freqs in the card | blue_air_support | beacon/freq commands |
| **5** | **Red air**: QRA scramble + CAP on station; P6/P7 missions | blue_air_support | Red fighter templates, trigger-on-detection |
| **6** | Ports: CAS (P8), convoy/TEL secondaries, Recon (P9) | cas/convoy/sd modules | Kola anchor zones |
| **7** | Mission chaining ("next tasking" without restart), session summary | cost_ui | end-state machine |
| **8** | (optional) pydcs pre-gen for weather/time | — | Python |

---

## 9. Open questions

**Concept**
1. ~~Cluster membership review~~ — settled 2026-09-22 (§3): 6 contested clusters with `p_red` + `requires_red`.
2. Should mission start time itself vary (dawn/dusk/night) per session? Only possible via the pydcs route *(§7)*.
3. `outText` length limits and DTC-on-dynamic-spawn behaviour — test items, not decisions *(§1.5 caveats)*.

**Architecture**
1. Skynet IADS as a dependency for SEAD? *(§5.3, §6)* — **open, leaning yes, later** (John, 2026-09-23: "sounds really cool"; if adopted, its code ships with the mission). Findings (README, 2026-09-23):
   - **Needs MIST** (not dependency-free as §5.3 says); MOOSE optional. Both would load unmodified alongside `kola_f16`.
   - Early-warning radars search and share one picture; SAM sites stay dark until a tracked target is inside their go-live range (`setGoLiveRangeInPercent`) → ambushes, little RWR warning. HARMs are detected by speed and path, and radars within ~15° of the path, out to ~20 nm, shut down. `addPointDefence` for SHORAD guarding a long-range site; `setActAsEW(true)` lets e.g. an SA-10 search for the network; command centres, power sources, connection nodes can be destroyed → sites go autonomous (dark or plain DCS AI).
   - Fit with our plan: register each `plan.sam_sites.sites` entry by id (`addSAMSite` / `addEarlyWarningRadar` by `layer` — not by prefix, since EW ids also start `SAM_`); each `<id>_escort` group → `addPointDefence`; one network per coalition.
   - To test first: the README covers only ME-placed groups; registering script-spawned groups right after `coalition.addGroup` should work but is unverified. Prototype on one SA-11 + one EW radar and fly a HARM at it.
2. Python (pydcs) pre-generation for weather/time — now, later, or never? *(§7)*
3. Naval strike — worth the ship-spawn research? *(§4.1 P5)*
4. Success criteria — binary pass/fail, or a score tied to the cost tracker? *(§5.3)*

**Deferred to their own design pass**
- Ground zones: force scaling, zones-per-cluster, paired Red/Blue fronts *(§1.7, §1.12)*.
- Ground ambient beyond zones: roaming SAMs, convoys, ship traffic, keep-clear rules around planned corridors *(§1.7)*.

---

## 10. Sources

- [DCS: Kola Map — ED product page](https://www.digitalcombatsimulator.com/en/products/terrains/kola_terrain/)
- [Kola Map announcement — ED news 2022-07-29](https://www.digitalcombatsimulator.com/en/news/2022-07-29/)
- [Threshold: Orbx Kola previews (high-detail airport list)](https://www.thresholdx.net/news/tekola)
- [Orbx Kola FAQ](https://orbxstudios.com/dcs-kola-map-faqs/)
- [MOOSE Wrapper.Airbase — `AIRBASE.Kola` string enumeration](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Wrapper.Airbase.html)
- [Skynet IADS](https://github.com/walder/Skynet-IADS)
- [pydcs](https://github.com/pydcs/dcs)

---

## 11. Architecture

### 11.1 Relationship to the Syria code
**Completely separate.** No shared `lib/`, no refactor of the Syria scripts, nothing in the Syria tree is touched. Kola is its own script directory with its own copies of whatever it borrows (logger, spawner, cost tracker patterns). The Syria mission must keep working exactly as it does today, and sharing code would put that at risk.

### 11.2 The plan is one table
The 7 stages of §1.1 build **one accumulating Lua table**. Stage 1 writes `plan.territory`; stage 2 reads it and writes `plan.base_defenses`; and so on. Each stage is one module that takes the table, reads the keys of earlier stages, and adds its own key. "Stage N only reads earlier stages" is a convention, not enforced.

- **Nothing spawns until all 7 stages are done.** Unlike Syria, where each module decides and spawns in the same function, here the stages only produce data. This is a much larger setup; deciding everything first and spawning afterwards is the only way the later stages (ATOs, brief) can see the complete picture. *v1 (2026-09-23):* only stages 1–2 exist, so the consumers run after stage 2. As later stages land they slot in before the consumers, and spawning stays last.
- **Stages may ask the terrain, never the live sim** (agreed 2026-09-23). Read-only questions about fixed map geometry (`land.getSurfaceType`, `land.getClosestPointOnRoads`, heights) are allowed during planning; reading or creating DCS objects is not (that's gather and the consumers). Offline replay of a stage stubs those calls.
- **Plain data only.** Strings, numbers, nested tables. No DCS object handles, no functions. Anything needed from the sim (airbase positions, ME zone positions, late-activation group names) is read into plain values as part of building the plan. Consequence: the plan can be written to a file (`Saved Games\DCS\kola_last_plan.lua`, behind a config flag) and read when debugging, instead of reconstructing what was planned from `dcs.log`.
- **Each entry carries everything its consumer needs.** Since spawning happens later, a defense entry holds unit types, positions, headings; an ATO line holds its route; an ME-placed target holds its late-activation group names. In Syria these live in locals right before the spawn call — here they go in the table.
- **Immutable once built** (not enforced). Consumers — spawner, mission reporter/briefing, ATO scheduler, objective tracker — all read the plan; none write to it.
- **Runtime state lives elsewhere.** What has launched, what's dead, objective status, scramble cooldowns: separate tracking structures owned by the executor/trackers, keyed by the same IDs the plan uses (mission number, target id, group name) so the two can always be joined.

### 11.3 From mission start to a finished plan
1. **ME trigger fires `init.lua`** at mission start. Loads the script files, nothing else.
2. **Wait a few seconds** (`timer.scheduleFunction`) — airbase queries return empty at T+0 (the Syria issue noted in §6).
3. **Gather inputs — one step, up front.** All DCS reads happen here and are converted to plain values: airbase list with positions and current coalition, trigger zones, late-activation group names and positions, mission time/date. Plus the static data files (cluster table, content catalog, unit pools) and the session history file. Every stage then works from the same snapshot; the stages never see a DCS object. Cost: what the stages need has to be known ahead of time — for airbases/zones/groups that's clear enough.
4. **Stages 1–7 run back-to-back** in one call. All data, milliseconds. (v1: stages 1–2 only; see §11.2.)
5. **Plan dump** to file if the config flag is set.
6. **Hand off** to spawner, briefing, ATO scheduler, objective tracker. The spawner adds **all static objects before any AI units** (§1.1 "Execution timing": the reverse order stalls DCS for minutes).

The gathered inputs are stored on the plan itself (`plan.world`) so the dump file is self-contained; it costs nothing and makes the dump complete.

### 11.4 Consumers of the plan
Who reads the plan and what they pull from it:

| Consumer | When | Reads | Needs per entry |
|---|---|---|---|
| **Ground spawner** | T+0 | `base_defenses`, `fixed` (targets, garrisons, IADS), `ground` (moving units) | ME late-activation group name to activate, *or* country + unit types + positions + headings (+ route if it moves). Doesn't care why anything is there. **Static objects are spawned before any AI units** (`SpawnStaticObjects`, then `SpawnGroundGroups`). |
| **ATO scheduler** | on the clock | `red.ato`, `blue.ato` (skips the player's line) | `t_start`, aircraft type + count, base, loadout, steerpoints, role → DCS task (CAP orbit / SEAD / bombing target / escort target / tanker track + TACAN + freq / AWACS orbit + freq), callsign. Alive-aircraft cap from config. |
| **Scramble loop** (per side) | periodic | posture: alert bases, fighter count/type, cooldown, detection radius | everything else is runtime state |
| **Briefing** | T+0, F10 on demand | player's line, support lines, `fixed.threat_map` + fidelity, `ground.contacts`, Red posture (AOB), full ATO for the F10 view | coordinates in DMS + MGRS — stored in the plan or converted on the way out |
| **Objective tracker** | event-driven | player's line → target → `success` criterion (group/unit names, fraction) | later: AI lines' success too, for the F10 ATO view |
| **History writer** | plan time + end | mission type, target id, launch base; outcome from the tracker | |
| **F10 ATO / "take another line"** (later) | after landing | full Blue ATO with times | not-yet-started lines only |

Two kinds of need show up: spawner and scheduler need **spawn-ready detail** (unit types, exact positions, routes); briefing/tracker/history need **mission-level meaning** (target name, TOT, threat type + confidence). Both are in the one table. Group names, mission numbers, and target ids are **assigned by the planner**, not invented at spawn time — the tracker has to match DCS event names back to plan entries.

### 11.5 One table — what's in it and what isn't
**The plan holds every decision, in our own vocabulary.** What, where, who, when, how it's named, what counts as success. Example, a stage-2 entry from `plan.base_defenses.groups` (as built):

```lua
{
    id          = "DEF_OLEN_infrared_missile_launchers_1",
    base        = "Olenya",
    side        = "red",
    class       = "bomber",
    echelon     = "front",
    level       = "heavy",
    component   = "infrared_missile_launchers",
    role        = "infrared_missile_launcher",
    skill       = "Good",
    anchor_kind = "infield",
    pos         = { x = 123456, z = 654321, lat = 68.15, lon = 33.46 },
    units       = {
        { type = "Strela-10M3", x = 123470, z = 654330, heading_deg = 90 },
        { type = "Strela-10M3", x = 123440, z = 654310, heading_deg = 95 },
    },
}
```
Each unit carries its own position, since placement already checked every unit against `Placement.isClear`. The spawner doesn't scatter them.

**Consumers own the DCS formats.** The `coalition.addGroup` table, waypoint + task tables, `outText` strings, F10 menu structures, map-mark calls — all built on the fly from plan entries at the moment they're used, and thrown away afterwards. Going from the entry above to an `addGroup` table is a *translation*, not a decision; nothing new is chosen, so nothing new is stored. There is no separate "spawn table" or "mission table" — the ATO lines and targets *are* the mission data, the defense and ground entries *are* the battlefield data; they're different keys of the same table, and the briefing can walk `plan.blue.ato[msn].target → plan.fixed.targets[id] → plan.fixed.threat_map` without crossing structures.

**State holds what happened.** Spawned group → plan id, alive/dead, launched, objective status, cooldowns. Written by consumers at runtime (§11.2).

Net effect: all the planning is pure logic over plain data — fast, and segmented from the sim. The spawner then reads the plan and creates units that already fit the missions the plan built.

### 11.6 Script layout and load order
Install path `Saved Games\DCS\Scripts\kola_f16\`, loaded by one ME trigger (`MISSION START → DO SCRIPT → dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")`), de-sanitized `MissionScripting.lua`, and a separate `Hooks\slotblock.lua` for the F-16 dynamic slots — the same install shape as Syria (§ INSTALL.md), fully separate tree (§11.1). This is the standard DCS pattern; there isn't a meaningfully different one.

Files marked *(later)* don't exist yet. The "What exists" tree at the top of this doc is the as-built list.

```
Saved Games\DCS\Scripts\kola_f16\
  init.lua                     -- entry: load order + run sequence
  lib\
    util.lua                   -- RNG, picks, geometry, serialize, writeFile
    logger.lua                 -- + dumpAirbases/Groups/Weather   (ported from Syria)
    weather.lua                -- weather + time/sun derivation (§1.11)
    placement.lua              -- isClear, findClear, ring/disc points, buildAnchors, pickAnchorPoint
                               --   (later: randomPointInZone for zones; LLtoMGRS goes with the brief)
  data\                        -- static plain-data tables, no logic; hand- or parse-authored
    clusters.lua               -- cluster table (§3), bases per cluster
    zones.lua                  -- parsed from the .miz (§1.12)
    statics.lua                -- (later) static templates (airfield targets, ships), parsed from the .miz
    catalog.lua                -- (later) content catalog (§1.2): targets, success criteria, per-site templates
    cloud_presets.lua          -- DCS cloud presets, generated (§1.11)
    unit_pool.lua              -- every spawnable DCS unit type, generated (§1.13)
    aircraft_pylons.lua        -- pylon → CLSID compatibility, generated; offline validation only
    coalition_rosters.lua      -- COALITION_ROSTER[side][role] weighted type picks (hand-authored; the only file that knows red from blue)
    airbase_classes.lua        -- AIRBASE_CLASS[name]: hub / fighter / bomber / strip / heli (hand)
    airbase_codes.lua          -- 4-letter code per base (group names, zone names)
    airbase_footprints.lua     -- surveyed taxiway grid + airfield buildings, generated in-sim
    base_defense_levels.lua    -- BASE_DEFENSE_LEVEL[class][echelon] → light / standard / heavy; BASE_DEFENSE_SKILL
    base_defense_composition.lua  -- BASE_DEFENSE_COMPOSITION[level]: components + count ranges
    base_defense_placement.lua -- BASE_DEFENSE_PLACEMENT[component]: role, anchors { kind = { weight, min_m, max_m } },
                               --   ring fallback, units per group, spread, mixed_types; group spacing
    sam_site_recipes.lua       -- SAM / early-warning site recipes per system
    sam_site_density.lua       -- zone roles, layer weights, caps
    callsigns.lua              -- (later) curated DCS enum pools per role (§11.7)
  gather.lua                   -- all DCS reads → plan.world
  stages\                      -- named by verb; run order lives in init.lua
    roll_territory.lua  plan_base_defenses.lua  plan_sam_sites.lua  …  (later) write_brief.lua
  consumers\
    territory.lua              -- to be renamed apply_territory.lua (housekeeping)
    spawn_ground_groups.lua    -- generic: plan entries → coalition.addGroup + per-unit type check
    draw_base_defenses.lua     -- debug F10 marks
    draw_sam_sites.lua         -- debug F10 marks + rings
    (later) schedule_ato.lua  deliver_brief.lua  track_objectives.lua  run_scramble.lua  write_history.lua
  survey\
    survey_airbase_footprints.lua  -- one-off, behind CONFIG.SURVEY_FOOTPRINTS
```

Load order in `init.lua`: `lib\*` → `data\*` → `stages\*` → `consumers\*`, then the run sequence (§11.3): gather inputs → stages 1–7 → optional plan dump → hand the finished plan to each consumer. Data files load before stages so a stage can reference a data global directly (Syria's global-module convention). **Statics and any hand-placed unit templates live in `data\` alongside zones** — all coordinate-driven and all parseable from the `.miz`, per the same offline-parse workflow (§1.12).

### 11.7 Naming and id convention
**Core rule:** every spawnable plan entry has a unique `id`; the spawner uses it **verbatim as the DCS group name**; the objective tracker maps `group:getName()` → plan entry. No unit-name suffix parsing (Syria's `^(BAS_%d+)_`) — the group name *is* the key.

**1. ME-authored** (must match the ME exactly; the planner references these):

| Thing | Convention | Example |
|---|---|---|
| Late-activation target groups | `TGT_<Base>_<Type>_<Part>` | `TGT_Olenya_SA10_TR` |
| Dynamic-spawn player slot groups | `<Base>_F16` | `Rovaniemi_F16` |
| Debug harvest groups | single letters | `A`–`E` |

**2. Planner-assigned logical ids** (live in the plan table):

| Thing | Convention | Example |
|---|---|---|
| Ground zone (tool-generated, §1.12) | `ZONE_<BASE>_<brg>_<km×10>` | `ZONE_KITT_100_012` |
| Catalog target id | `<KIND>_<Place>_<Type>` | `SAM_Olenya_SA10`, `SHIP_KolaBay_Kirov` |
| ATO mission number `msn` | numeric blocks | Blue 2000–2999 · Red 5000–5999 · support 0900–0999 |
| Package id | `PKG-<letter>` | `PKG-A` |
| Radio callsign | curated DCS enum (below) | `Springfield 1` |

**3. Spawner-assigned DCS names** (= the plan id verbatim):

| Spawned thing | Group name | Tracker mapping |
|---|---|---|
| ATO air line | `MSN<msn>` | `MSN2041` → `blue.ato[2041]` |
| Ground group from a zone | `<zonename>__<n>` | `ZONE_KITT_100_012__1` → that ground entry |
| Base defense | `DEF_<CODE>_<component>_<n>`; units `<id>_<n>` | `DEF_OLEN_towed_anti_aircraft_guns_1` → `base_defenses.groups` entry |
| SAM / EW site | `SAM_<CODE>_<system>_<n>`; escort `<id>_escort` | `SAM_SEV1_SA10_1` → `sam_sites.sites` entry |
| Activated ME target | its `TGT_…` name | directly |

The **player line** has no pre-named group (dynamic spawn) — its objective is keyed off the player unit (`getPlayerName()`) plus the frag's `msn`/target, the same way `cost_logic` attributes kills to a human.

#### Callsign policy — radio ≠ group name  *(revisitable)*

The DCS **group name** is the machine id above — never spoken. The **radio callsign** is a separate field drawn from DCS's built-in callsign **enum**, which drives the AI voiceovers *and* is what the brief prints — so what's written matches what's heard.

- Curated per-role enum pools (Blue): fighters `{Springfield, Colt, Dodge, Ford, Chevy, Uzi, Enfield, Pontiac}`, tankers `{Texaco, Arco, Shell}`, AWACS `{Magic, Overlord, Wizard, Darkstar}`. The player gets a reserved fighter callsign **by role** (SEAD→Springfield, strike→Colt, CAP→Dodge…), so the frag reads consistently session to session.
- Brief callsigns are these enum names (the §1.5 template is an illustrative draft); a display string that isn't a real enum name won't match the audio.
- **"Audible but not overwhelming":** enum callsigns are assigned to **player-relevant Blue air only** — own flight, package-mates, the CAP covering the player, tanker, AWACS — so their radio calls are recognizable and useful. Volume is held down by (a) the §1.9 alive-cap limiting simultaneous transmitters, (b) not over-spawning concurrent Blue flights, (c) TOT deconfliction spreading events out. Red air still transmits (unavoidable) but isn't surfaced in the brief and is less intrusive; keep Red numbers modest. Tune the concurrent-Blue count in testing if it's still busy.
