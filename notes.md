# DCS Dynamic Ground Spawning — Research & Planning Notes

## Project Overview

- **Map:** Syria
- **Server type:** Private, started on demand (2 players)
- **Goal:** Dynamic air-to-ground mission with randomized Red/Blue base setup at mission start
- **Players always Blue**, flying air-to-ground strikes against Red-controlled positions
- **DCS version:** 2.9.26.23303, Standalone (not Steam/OpenBeta), Windows 11

---

## Concept

Mission starts with a randomized layout of Red and Blue bases across the Syria map. Players fly air-to-ground strikes against Red-controlled positions. The system should feel different each session without manual mission editing. Future plans include spawning defensive ground units at Red bases, AI battles, and F10 menu functionality.

---

## Current Status — Session 11 In Progress

At mission start, the script:
1. Randomizes which contested clusters go Red vs Blue
2. Calls `Airbase:setCoalition()` on every base in each cluster
3. Draws colored circles on the F10 map (blue = Blue territory, red = Red territory) — 10km radius
4. Prints a territory summary on screen for 180 seconds
5. Spawns randomized ground defenses at every Red base
6. Activates fixed SA-2 / SA-6 SAM sites based on territory and probability
7. Dynamically spawns roaming SA-9 / SA-13 units at Red bases and in Red territory
8. Prints a SAM summary on screen for 300 seconds — GPS shown for SA-2/SA-6 fixed sites; location description only for SA-9/SA-13 roaming units
9. Spawns one supply convoy, one mechanized convoy, and one armor convoy — each on a different route between Red airbases
10. Draws a labeled green circle (27km radius) on the F10 map at each convoy's estimated 35-minute position
11. Prints a combined convoy summary on screen for 300 seconds
12. Generates 2 S&D strike missions per session — one ballistic missile (M1) and one VIP (M2), each with a randomly assigned threat level. Draws orange circles on F10 map, prints info on screen for 300 seconds
13. Arms each missile site with a randomized launch timer (10–120 minutes); at expiry each surviving Scud TEL fires at a randomly selected Blue airbase (staggered 4 seconds apart)
14. Populates two F10 menu submenus: **SAM Threats** (one entry per active SAM) and **Missions** (convoys + strike missions); each entry shows a 60-second info readout on click
15. Tracks per-player mission cost score throughout the session — munitions charged on `S_EVENT_SHOT`, aircraft losses charged on DEAD/CRASH/EJECTION (waived if pilot lands at a Blue airbase), kill credits attributed via HIT→DEAD chain
16. Displays score via **Show Mission Score** F10 command (per player group) and auto-broadcasts every 5 minutes
17. Implements CAS missions via `cas_mission.lua` — first mission: **Defend Kovanli** (Kovanlı, Oğuzeli/Gaziantep). Blue late-activation groups (infantry, Bradleys, APCs, Scorpions) defend against dynamically spawned Red attackers in 1–3 groups from random bearings, force level weak/adequate/strong/overwhelming scaled against Blue defender counts, arrival time 35–120 min. Air defense threat randomized independently (low/med/high). F10 menu: **Missions > CAS > Defend Kovanli [THREAT]**

**Spawn slots:** DCS Dynamic Spawn (enabled per-airbase in the Mission Editor) correctly shows/hides player slots based on `setCoalition()`. No scripting required.

**Ground defenses:** Each Red base gets randomized counts of AK infantry, RPG infantry, SA-18 Igla MANPADS, BTR-80, Ural trucks, and ZU-23 AAA. Each unit spawns at an independent random position 800–2000m from the airbase threshold.

**SAM sites:** Fixed SA-2/SA-6 sites pre-placed in ME as late-activation groups. Roaming SA-9/SA-13 dynamically spawned via `coalition.addGroup()`. Active SAMs print to screen for 300s; GPS shown for fixed sites only.

**Convoys:** Three types spawn each session with randomized skill (Average/Good/High per convoy). Routes are capped at 175 km; if no base is within range the nearest is used. Island bases (Gecitkale, Ercan) only route to other Cyprus bases — no cross-water routes.

**Strike missions:** 2 S&D missions per session — M1 (ballistic missile) and M2 (VIP), each assigned a random threat level from the shuffled pool. Spawn locations checked for land and terrain flatness before placement. Missile sites weighted 3:1 country:airbase. VIP sites use `{ country, country, road, airbase }` distribution with tighter flatness requirements.

---

## Strike Mission Design

### Two Mission Paths

**Search & Destroy (S&D)** — fully dynamic, all units spawned via `coalition.addGroup()`. No friendlies.
- Parameters: `location_type`, `target_type`, `threat_level` (low/med/high)
- Each mission module declares `VALID_LOCATIONS` — the location types valid for that target

**CAS (Close Air Support)** — requires pre-built ME late-activation groups for both targets and friendlies. Stubbed, not yet implemented.
- Parameters: `location_type`, `target_type`, `threat_level`, friendlies present

### S&D Location Types
| Type | Description |
|---|---|
| `airbase` | 800–2500m outside a Red airbase perimeter, off-road |
| `country` | Open terrain 15–60 km from a Red base anchor, no road snap |
| `town` | At a named Syrian town coordinate (not valid for missile or VIP missions) |
| `road` | Road-snapped point 15–60 km from a Red base |

### S&D Target Types — Status

| Target | Status | Valid Locations | Units |
|---|---|---|---|
| Ballistic missile | ✅ Done | `airbase`, `country` | 1–5 Scud-B TELs + infantry/BTR-80 support + per-threat air defense |
| VIP | ✅ Done | `airbase`, `country`, `road` | 5–8 infantry (AK/AKM), BTR-80, 2 Ural trucks, Mi-8MT static helo (type unconfirmed) + per-threat air defense |
| Troops | 🔲 Next | `airbase`, `town`, `road` | Infantry cluster + vehicles, no TELs |

### S&D Air Defense Loadouts (per mission, spawned near target)
| Threat | Units |
|---|---|
| Low | 1–2 ZU-23 (`Ural-375 ZU-23`) + 1–2 MANPADS (`SA-18 Igla manpad`) |
| Med | 1 SA-9 (`Strela-1 9P31`) + 1 ZU-23 |
| High | 1 SA-13 (`Strela-10M3`) + 1–2 Shilka (`ZSU-23-4 Shilka`) |

Air defense group spawns 400–900m from site center (150m internal spread).

### Terrain Flatness Check
All S&D mission spawn points are validated for flat terrain using `Spawner.isFlatEnough(pos, radius, maxDelta)` — samples 8 perimeter points + center, rejects if max-min height > maxDelta.

| Context | Radius | Max delta | Notes |
|---|---|---|---|
| Missile site anchor | 150m | 25m | `resolveSite` retry loop |
| Per-TEL position | 75m | 20m | Each TEL retried independently; needed because TEL spread (200m) exceeds site check radius |
| VIP site anchor | 100m | 15m | Tighter — must be viable helo LZ; VIP spread (30m) is within radius so no per-unit check needed |

---

## CAS Mission Design

### Mission Types
| Type | Description |
|---|---|
| `blue_defending` | Blue late-activation groups hold a fixed location; Red attackers spawn dynamically and advance |
| `red_defending` | Red holds a fixed position (late-activation or dynamic); Blue forces (if any) activate; players strike |

### Mission Definition Fields
Each entry in the `MISSIONS` table in `cas_mission.lua`:
- `name` — internal identifier, used as group name prefix (e.g. `CAS_KOVANLI_DEFENSE_red_1`)
- `label` — F10 display name (e.g. `"Defend Kovanli"`)
- `mtype` — `"blue_defending"` or `"red_defending"`
- `pos` — hardcoded Vec3 via `ll(lat, lon)` helper; town/site center for F10 circle and attack waypoint
- `blue.groups` / `red.groups` — ME late-activation group names; activated at mission start
- `blue.spawn_defs` + `blue.spawn_pos` / `red.spawn_defs` + `red.spawn_pos` — dynamic spawn fallback (optional)
- `defenders` — Blue force composition for Red scaling (`{infantry, light_armor, heavy_armor}`); required for `blue_defending`
- `airdef_anchor` — Red air defense spawn anchor for `red_defending` missions; not used for `blue_defending` (placed dynamically)

### Red Attacker Spawning (blue_defending)
- **Force level** (weak/adequate/strong/overwhelming): rolled independently per session; multipliers applied against `defenders` table to compute Red unit counts
- **Group count** (1–3): rolled independently of force level
- **Approach bearings**: evenly spaced with random overall rotation, so groups converge from different directions
- **Individual groups**: each unit is its own DCS group so they pathfind independently — prevents the column-marching behaviour that occurs when units share a group controller. ±15° bearing jitter + ±15% distance jitter per unit creates natural spread across the approach cone.
- **Spawn distance**: `attackMins × 60 × 3.1 m/s` — 3.1 m/s matches observed DCS infantry speed (~7 mph); `attackMins` = 30–120 min
- **Vehicles lead**: armor/APCs spawn at 85% of infantry spawn distance so they arrive first and lead the assault
- **Orbit behavior**: each unit's route ends in 3 loops of 12 waypoints around a 185m (~0.10 nm) ring centered on the town. Units engage defenders while orbiting rather than parking at a single point. Constants: `ORBIT_RADIUS = 185`, `ORBIT_STEPS = 12`, `ORBIT_LOOPS = 3`.
- **Arrival display**: shown in F10 info and screen text as game-clock time (`attackMins × 60 − 10 min` correction applied; vehicles move at ~11 mph regardless of route speed setting so they arrive ~10 min before the raw formula)
- **Air defense**: each AD unit is its own group; spawned within 500m of an anchor 1–2nm behind the assault force, then routes to a support position 1.5–2.5km from town on the approach bearing — within SA-13 (5km) and ZU-23 (2.5km) range of the final fight

### Red Force Level Multipliers
Multipliers are applied against the mission's `defenders` table values. Ranges randomized per session.
| Level | Infantry mult | Light armor mult | Heavy armor mult |
|---|---|---|---|
| weak | 0.45–0.75 | 0.45–0.75 | 0 |
| adequate | 1.05–1.65 | 0.9–1.35 | 0.15–0.45 |
| strong | 2.1–3.0 | 1.65–2.4 | 0.75–1.35 |
| overwhelming | 3.75–5.25 | 3.0–4.5 | 1.5–2.7 |

*(1.5× the original values — 2× was too strong; 1.0× was too weak)*

Attacking is harder than defending in DCS, so even "adequate" must slightly exceed Blue counts to be a real threat.

### Red Unit Pools
| Category | Types |
|---|---|
| Infantry | `Soldier AK` (×2 weight), `Infantry AK Ins`, `Soldier RPG` |
| Light armor | `BTR-70`, `BTR-80` (×2 weight), `BMP-1`, `BRDM-2` |
| Heavy armor | `T-55` (×2 weight), `T-72B` |

### CAS Mission Inventory
| Mission | Type | Location | Blue Groups | Status |
|---|---|---|---|---|
| Defend Kovanli | blue_defending | Kovanlı, Oğuzeli/Gaziantep (N36°48.672' E37°41.904') | Infantry×30, Bradley×3, AAVAPC7×5, Scorpion×2 | ✅ Implemented |

---

## Script Architecture

### File Locations
- **Git repo:** `C:\Users\johnk\Git\dcs\scripts\`
- **DCS runtime:** `C:\Users\johnk\Saved Games\DCS\Scripts\a2g_dynamic_syria\`
- Files must be manually copied from repo to DCS after edits (or use PowerShell Copy-Item)

### File Structure
```
scripts/
    init.lua                        ← entry point, loaded by mission trigger
    lib/
        logger.lua                  ← global Log table (Log.info/warn/error/debug)
        spawner.lua                 ← position helpers, coalition.addGroup wrapper, fireGroups, isOnLand, isFlatEnough
    modules/
        coalition_setup.lua         ← cluster definitions + CoalitionSetup.assign()
        defense_setup.lua           ← ground unit definitions + DefenseSetup.spawn()
        sam_setup.lua               ← SAM activation + spawning (SA-2/6/9/13)
        convoy_setup.lua            ← supply/mechanized/armor convoy spawning
        mission_setup.lua           ← thin orchestrator: calls SdMission + CasMission
        sd_mission.lua              ← S&D missions (ballistic missile + VIP implemented; troops next)
        cas_mission.lua             ← CAS missions (blue_defending / red_defending; fixed locations, mixed late-activation + dynamic spawns)
        cost_config.lua             ← cost tracker: aircraft/munition costs + enemy kill values
        cost_logic.lua              ← cost tracker: DCS event handler, per-player spent/earned state
        cost_ui.lua                 ← cost tracker: score display, F10 menu, 5-min auto-broadcast
    slotblock.lua                   ← hook script (inactive, kept for reference)
```

### Module API
- `CoalitionSetup.assign()` → returns `assignments` (list of `{name, side}`), `clusterSides` (cluster id → coalition.side)
- `DefenseSetup.spawn(assignments)` → spawns ground defenses at all Red bases
- `SamSetup.spawn(clusterSides, assignments, samMenu)` → activates/spawns all SAM systems; adds entries to samMenu
- `ConvoySetup.spawn(clusterSides, assignments, missionsMenu)` → spawns convoys; adds entries to missionsMenu
- `MissionSetup.generate(assignments, missionsMenu)` → orchestrates all mission types
- `SdMission.generate(assignments, missionsMenu)` → spawns S&D missions; adds entries to missionsMenu
- `CasMission.generate(assignments, casMenu)` → activates Blue groups, spawns Red attackers + air defense, draws F10 circles, adds entries to casMenu (Missions > CAS submenu)
- `CostTracker.playerScores` → per-player `{ spent, earned, net }` tables (read by cost_ui)
- `CostTracker.getPlayerSummary(name)` → formatted single-player score string
- `CostTracker.getTeamTotals()` → `totalSpent, totalEarned, totalNet, formattedString`
- cost_ui self-initializes via `timer.scheduleFunction` at load time; no explicit call needed from init.lua

### Mission Editor Trigger
- **Type:** ONCE
- **Condition:** TIME MORE, 1 second
- **Action:** DO SCRIPT
- **Text:** `dofile(lfs.writedir() .. "Scripts\\a2g_dynamic_syria\\init.lua")`

**Critical:** Trigger type must be ONCE, NOT "4 MISSION START". MISSION START type with any condition never fires — the condition is checked at t=0, fails, and the trigger is permanently discarded.

---

## Decisions Made

- **Framework:** No MIST/MOOSE — custom vanilla Lua modules only (lightweight, no dependencies)
- **Coalition system:** Geographic cluster approach — fixed clusters (always Blue/Red) + contested clusters randomized each session
- **Spawn slots:** DCS Dynamic Spawn system — enabled per-airbase in ME, respects `setCoalition()` automatically
- **Script loading:** External files via `dofile(lfs.writedir() ...)` — requires MissionScripting.lua de-sanitization
- **Map visualization:** `trigger.action.circleToAll()` with 5000m radius circles
- **SAM fixed sites:** Pre-placed in ME as late-activation groups, activated by script — gives precise real-world placement
- **SAM roaming units:** Dynamically spawned via `coalition.addGroup()` — SA-9/SA-13 are mobile, random placement fits
- **Scud TEL spawning:** One DCS group per TEL (not one group with N units) — required to get each launcher to fire independently via its group controller
- **VIP helo:** Spawned as static object via `coalition.addStaticObject()` — stays on the ground, not flyable AI

---

## Cluster Definitions (coalition_setup.lua)

| Cluster | ID | Type | Bases |
|---|---|---|---|
| Southern Cyprus | CYPRUS_SOUTH | Always Blue | Akrotiri, Larnaca, Paphos, Kingsfield, Lakatamia |
| At Tanf | AT_TANF | Always Blue | At Tanf |
| Russian Core (Latakia) | RED_CORE | Always Red | Bassel Al-Assad, Hama, Taftanaz, Minakh, Wujah Al Hajar |
| NATO Northern Arc | TURKEY | Contested | Incirlik, Adana Sakirpasa, Hatay, Gaziantep, Gazipasa, Sanliurfa, Pinarbashi, Gecitkale, Ercan |
| Israel & Jordan | BLUE_SOUTH | Contested | Ramat David, Ben Gurion, Haifa, Tel Nof, Hatzor, Kiryat Shmona, Megiddo, Palmachim, Herzliya, King Abdullah II, Muwaffaq Salti, Marka, Prince Hassan, King Hussein Air College, Ruwayshid |
| Damascus Basin | DAMASCUS | Contested | Damascus, Mezzeh, Al-Dumayr, Marj as Sultan N/S, Khalkhalah, Marj Ruhayyil, Tha'lah *(Ghabagheb — name unconfirmed)* |
| Aleppo Region | ALEPPO | Contested | Aleppo, Kuweires, Jirah, Abu al-Duhur |
| Central Syria (T4) | CENTRAL_SYRIA | Contested | Shayrat, Tiyas, Palmyra, Al Qusayr, Sayqal |
| Lebanon | LEBANON | Contested | Beirut-Rafic Hariri, Rayak, Rene Mouawad, An Nasiriyah |
| Euphrates / NE Syria | EUPHRATES | Contested | Kharab Ishk, Tal Siman, Tabqa, Deir ez-Zor |

---

## SAM System (sam_setup.lua)

### Fixed Sites — SA-2 and SA-6
Pre-placed in ME as late-activation groups. Groups named `RED_<Location>_SA2` / `RED_<Location>_SA6`.

| Site | Region / Cluster |
|---|---|
| RED_Sanliurfa | TURKEY (contested) |
| RED_BasselAlAssad | RED_CORE (always Red) |
| RED_Damascus | DAMASCUS (contested) |
| RED_Aleppo | ALEPPO (contested) |

Up to 8 sites planned total.

**Spawn rules:**
- SA-2: 10% global chance, **max one on the map at a time**, chosen from all Red-territory sites
- SA-6: 15% per Red site, independently rolled
- SA-2 and SA-6 are **never active at the same site**

### Roaming SAMs — SA-9 and SA-13
Dynamically spawned each session via `coalition.addGroup()`.

| Type | DCS unit string | Max count | Placement |
|---|---|---|---|
| SA-9 | `Strela-1 9P31` | 2 | 50% at Red airbase, 50% open terrain |
| SA-13 | `Strela-10M3` | 3 | 50% at Red airbase, 50% open terrain |

- At-airbase ring: 500–2000m from threshold
- Open terrain ring: 15,000–40,000m from a random Red airbase anchor
- Unit type strings confirmed: `Strela-1 9P31` (SA-9), `Strela-10M3` (SA-13)

### Screen Output / F10 Menu
- Active SAMs print to screen for 300 seconds at mission start
- SA-2/SA-6 fixed sites: label + GPS coordinates
- SA-9/SA-13 roaming: label + location description (e.g. "field near Hama") — no GPS
- F10 **SAM Threats** submenu: one entry per active SAM; click shows same info for 60 seconds

---

## Technical Lessons Learned

### De-sanitization
- Edit `C:\Program Files\Eagle Dynamics\DCS World\Scripts\MissionScripting.lua`
- Comment out the 6 lines inside the `do...end` sanitize block (lines 16–21)
- **Requires full DCS restart** — editing while DCS is running has no effect
- Must be redone after every DCS update

### DCS Airbase API
- Correct function: `Airbase:setCoalition(coalition.side.BLUE)` — added in DCS 2.8.8
- Always call `ab:autoCapture(false)` first or DCS ground presence can revert ownership
- `trigger.action.setAirbassOwner()` does NOT exist — community myth
- `env.info()` output appears in dcs.log under category `SCRIPTING`, not `INFO`
- **`Airbase:getPoint()` returns the runway threshold, not the geographic center** — use offsets of 800m+ for perimeter spawning or all units cluster at the terminal end

### DCS Map Drawing
- `trigger.action.circleToAll(-1, id, pos, radius, lineColor, fillColor, lineType, readOnly, message)`
- Color tables MUST use positional format: `{r, g, b, a}` not named keys `{r=x, g=y, ...}`
  - Named keys silently produce invisible/black shapes (DCS reads by numeric index)
- Values are 0–1 for all RGBA components
- `ab:getPoint()` returns a valid Vec3 usable directly as the center position

### math.randomseed
- `math.randomseed` is unavailable in DCS's mission Lua environment
- Workaround: advance RNG state manually using mission time steps: `for i=1, (t%97)+1 do math.random() end`

### Ground Unit Spawning
- Use `coalition.addGroup(countryId, Group.Category.GROUND, groupData)` to spawn ground units dynamically
- `land.getClosestPointOnRoads("roads", x, y)` returns two values `rx, ry` — NOT a table (indexing it causes a script error)
- Wrong unit type names are silently replaced with Leopard-2; check dcs.log for `woCar: Unit X is unknown`
- Confirmed correct type strings: `Soldier AK`, `Soldier RPG`, `BTR-80`, `SA-18 Igla manpad`, `Ural-375 ZU-23`, `Ural-4320-31`, `KAMAZ Truck`, `Infantry AK Ins` (AKM insurgent), `BMP-1`
- DCS replaces unknown unit types with Leopard-2 (not a crash, easy to miss without checking the log)

### Static Object Spawning
- Use `coalition.addStaticObject(countryId, { name, type, x, y, heading })` to place non-moving objects
- **`Group.getByName()` cannot find static objects** — they are not groups. `dumpLateGroupUnits` will always report "not found" for a static placed in ME
- To verify a static object's type string, you need a different approach (e.g. place it as a unit in a debug group, check type, then switch to static in ME)
- Mi-8MT static type string is currently `"Mi-8MT"` — **unconfirmed**, watch for woCar errors

### Terrain Flatness Check
- `land.getHeight({x, y})` returns ground elevation in metres (does NOT include trees/vegetation)
- Sample the center + 8 evenly-spaced perimeter points; reject if max-min height exceeds threshold
- DCS has **no vegetation/forest API** — trees are part of the terrain render layer, not queryable objects
- On Syria, most dense forest is in the western mountain ranges at higher elevations; an elevation cap (~550m) could serve as a rough proxy for avoiding forest spawns (not yet implemented)

### Late-Activation Groups
- Place group in ME, right-click → set to Late Activation
- Activate at runtime with `Group.getByName("name"):activate()`
- Group must exist in the mission file — `Group.getByName()` returns nil if name doesn't match exactly

### Convoy Unit Type Strings
- Confirmed: `ATZ-5`, `ATZ-10` (fuel trucks), `Ural-375 PBU` (command vehicle)
- Confirmed: `BTR-70`, `BTR-80`, `T-55`, `T-72B`, `BMP-2`, `BMP-3`, `ZSU-23-4 Shilka`
- `BTR-60PB` does NOT exist — silently spawns Leopard-2; correct DCS string unknown, omit for now
- Confirmed CH mod strings: `CHAP_T64BV` (T-64BV Type 2017), `CHAP_MATV` (M-ATV)
- `ATZ-5 civil` does NOT exist — silently spawns Leopard-2
- ME label "Ural-4320 MCC" maps to DCS type `Ural-375 PBU` — naming is inconsistent
- Use `Log.dumpLateGroupUnits({"A","B",...})` to activate debug groups and log `getTypeName()` for each unit

### Convoy Routing
- Routes capped at 175 km (`MAX_ROUTE_DIST`) — beyond that DCS road AI fails to navigate reliably
- `ISLAND_BASES` table in convoy_setup.lua lists bases that cannot road-route to the mainland (Gecitkale, Ercan); convoys only route within the same landmass
- Southern Cyprus bases (CYPRUS_SOUTH cluster) are fixed Blue and never need island handling
- `goto` is NOT supported in DCS's Lua environment — use `if/else` blocks for early-exit logic in loops

### Lua in DCS
- `goto` / `::label::` syntax is not supported — use nested `if/else` instead

### DCS Bearing Calculation
- In DCS, `Airbase:getPoint()` returns Vec3 where `.x` = North-South axis, `.z` = East-West axis
- Compass bearing formula: `math.atan2(east_diff, north_diff)` = `math.atan2(b.z - a.z, b.x - a.x)`
- Using `atan2(north, east)` instead gives wrong results (e.g., "N" when heading "E")

### Coordinate Conversion
- `coord.LOtoLL(vec3)` converts a DCS Vec3 to decimal lat/lon
- `Group:getUnit(1):getPoint()` returns a Vec3 suitable for passing to `coord.LOtoLL()`

### world.getAirbases() Dump
- `world.getAirbases()` returns a numerically-indexed table — use `ipairs`, not `pairs`
- Currently returns empty at T+0.3s on Syria map (timing issue suspected); dump not yet useful for name verification
- Workaround: check airbase name mismatches from WARN log lines at mission start

### Ballistic Missile (Scud-B) Firing
- `unit:getController():setTask({id="FireAtPoint",...})` does NOT work reliably for Scud-B — only one unit in the group responds regardless of how many are in it
- **Fix:** spawn each TEL as its own 1-unit group; command each group controller independently
- `group:getController():setTask({id="FireAtPoint", params={point={x=north,y=east}, expendQty=1, expendQtyEnabled=true}})` works correctly per group
- Stagger fire orders by scheduling each group's command via `timer.scheduleFunction` with a cumulative delay (e.g. 4s apart)
- Always look up the group by name at fire time (`Group.getByName(name)`) rather than storing unit/group references at spawn time — references from 2+ minutes earlier can behave unexpectedly

### DCS Event System — S_EVENT_DEAD
- `S_EVENT_DEAD` fires for **weapons** (missiles, bombs hitting the ground) as well as units and statics — always check `Object.Category.UNIT` before calling any Unit-specific method
- `event.initiator` for a weapon's DEAD event is a Weapon object; Weapon does not have `getID()`, `getGroup()`, `getTypeName()`, etc. — calling them throws "attempt to call method 'getID' (a nil value)"
- **Fix:** add `if type(deadUnit.getCategory) ~= "function" then return end` immediately after the nil check — Weapon objects don't have `getCategory` as a method at all, so calling it throws rather than returning a filterable category value
- `getGroup()` can also return nil when DEAD fires for a unit (the group is already gone by the time the event fires) — guard before chaining `:getID()`
- At mission init, `getPlayerName()` can briefly return a player name for phantom slot-initialization units; add `unit:isExist()` check before charging costs or sending messages

### Ground Unit AI Speed
- DCS ground AI ignores the `speed` field in route waypoints when it falls below the unit's minimum AI speed
- Observed speeds: vehicles ~11 mph (~4.9 m/s), infantry ~7 mph (~3.1 m/s)
- Setting `speed = 3.1` in waypoints successfully slows vehicles in some cases but not always — infantry speed (3.1 m/s) is the reliable baseline for timing estimates
- Use `GROUND_SPEED_MPS = 3.1` for spawn distance formula; subtract ~10 min from arrival estimates to account for vehicles running ahead of that pace
- `INFANTRY_TYPES` set in `cas_mission.lua` is used to detect non-infantry units and spawn them 15% closer (armor-leads-infantry formation)

### Moving Ground Units (Routes)
- `coalition.addGroup()` groupData accepts a `route` field with a `points` array to give ground units waypoints
- Route point format: `{ x=north, y=east, alt=height, type="Turning Point", action="Off Road", speed=m/s, ETA=0, ETA_locked=false }`
- With a route, `task = "Ground Nothing"` is sufficient — units follow waypoints and engage enemies automatically
- `Spawner.spawnGroundGroup` now accepts `options.route` and `options.task` and passes them through to `coalition.addGroup`
- Route point coordinates use the same `x=north, y=east` convention as the `pos` format (not Vec3); for Vec3 `{x,y,z}`: route point `x = vec3.x`, `y = vec3.z`

### Surface Type Check
- `land.getSurfaceType({x=north, y=east})` returns `land.SurfaceType.LAND`, `SHALLOW_WATER`, `WATER`, `ROAD`, or `RUNWAY`
- Use to reject water positions for mission spawns; retry up to N times before accepting the last candidate
- Only applied to S&D/CAS mission spawning — convoy/defense/SAM spawning is anchored close enough to airbases that water is not a practical issue

### DCS Timer and Screen Messages
- `timer.getAbsTime()` returns seconds since midnight of the mission day — use for displaying human-readable game clock times (format with `% 86400` then convert to HH:MM:SS)
- `outText` called every second with a short duration creates a live countdown display but will stomp on other active `outText` messages — use a static one-time `outText` instead and show the computed launch time in game clock format
- `timer.scheduleFunction(fn, arg, t)` requires `t` to be strictly in the future; scheduling at exactly `timer.getTime()` (delay=0) may be silently dropped — use a minimum offset of 2+ seconds

### init.lua Load Order
- Each module with side effects (SAM spawning, convoy spawning, etc.) must be called **once** — calling `SamSetup.spawn()` twice (once without the menu handle, once with) double-spawns all SAM groups silently
- Modules that self-initialize via `timer.scheduleFunction` at load time (e.g. cost_ui) need no explicit call in the startup sequence — loading the file is enough

### F10 Radio Menu
- `missionCommands.addSubMenuForCoalition(coa, title, parentMenu)` — creates a submenu; returns a handle used as parent for child items. Pass `nil` as parent for top-level.
- `missionCommands.addCommandForCoalition(coa, title, parentMenu, fn, args)` — adds a clickable item; `fn(args)` is called when selected
- Create the menu handle once (e.g. in `init.lua`) and pass it as a parameter to modules that need to add entries — avoids duplicate top-level menus if two modules both call `addSubMenuForCoalition` with the same title
- Menu is per-coalition; Blue players only see Blue menus

---

## Open Questions / Next Steps

- [x] Research and test DCS Dynamic Spawn system with `setCoalition()` — works correctly
- [x] Spawn defensive ground units at Red-controlled bases
- [x] SA-2 and SA-6 fixed sites with cluster-based territory check
- [x] SA-9 and SA-13 roaming SAMs with probabilistic spawning
- [x] Expand cluster coverage to all Syria map airbases
- [x] Spawn supply convoy traveling between Red airbases with F10 map circle and screen summary
- [x] Implement mechanized-convoy and armor-convoy types
- [x] S&D ballistic missile mission — Scud-B TELs, support group, per-threat air defense, F10 markers
- [x] Scud-B TELs fire at a random Blue base on a randomized launch timer; staggered salvo, survivors only
- [x] Confirm `KAMAZ Truck` unit type string — confirmed working
- [x] Confirm AKM insurgent type string — confirmed `"Infantry AK Ins"`
- [x] S&D VIP mission — infantry + vehicles + static helo, tight cluster, per-threat air defense
- [x] F10 menu for mission info — SAM Threats + Missions submenus implemented
- [x] Terrain flatness check for S&D spawn positions
- [ ] Confirm `Scud_B` type string — appears correct (missiles fire), not yet explicitly verified via getTypeName()
- [ ] Confirm `GAZ-3308` unit type string (no woCar errors seen but not in debug groups yet)
- [ ] Confirm Mi-8MT static type string — currently `"Mi-8MT"`, unverified; Group.getByName() can't find statics so needs alternate verification method
- [x] Increase Scud launch timers from 2–3 min (testing) to 10–25 min for real play — set to 10–120 min
- [ ] Confirm correct DCS name for Ghabagheb airbase (currently commented out of DAMASCUS cluster)
- [ ] Fix `world.getAirbases()` dump — returns empty at mission start, may need timer delay
- [ ] Add more SA-2/SA-6 fixed sites (up to 8 planned)
- [ ] Remove `Log.dumpLateGroupUnits` call from init.lua and debug groups from ME once type strings confirmed
- [ ] S&D: troops mission — infantry cluster + vehicles at airbase/town/road location
- [ ] S&D: randomizer to mix target types when more than 2 mission types are implemented
- [ ] VIP mission: forest/tree avoidance — no DCS vegetation API; elevation cap (~550m) as Syria-specific proxy considered, tabled for future visit
- [x] CAS: design pre-built ME group naming convention — `BLUE_CAS_<Mission>_<Type>` / `CAS_<NAME>_red_N` for dynamic
- [x] CAS: implement first mission (Defend Kovanli) — blue_defending type, 4 force levels, 1–3 groups, 35–120 min arrival
- [x] CAS: confirm Red attack groups move toward town — confirmed; units orbit at 185m ring rather than stopping at center
- [x] CAS: confirm `BRDM-2` type string — confirmed `"BRDM-2"` (ColdWarAssetsPack replaces model at startup but type string unchanged; added to LIGHT_ARMOR_POOL)
- [ ] CAS: implement red_defending mission type
- [ ] CAS: add more missions to the MISSIONS table
- [ ] Investigate why airfield icons don't change color in singleplayer

---

## Research Files

- [Scripting Architecture](research_scripting_architecture.md) — Lua environments, frameworks, file organization, F10 menu API
- [Airbase API](research_airbase_api.md) — setCoalition, autoCapture, airbase methods, workarounds
- [Syria Airbases](research_syria_airbases.md) — complete airbase inventory with coordinates and cluster suggestions
- [Runway Lengths](research_runway_lengths.md) — F-16 viability by base (2,500m+ / marginal / too short)
