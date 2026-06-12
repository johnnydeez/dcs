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

## Current Status — Session 8 Complete

At mission start, the script:
1. Randomizes which contested clusters go Red vs Blue
2. Calls `Airbase:setCoalition()` on every base in each cluster
3. Draws colored circles on the F10 map (blue = Blue territory, red = Red territory) — 10km radius
4. Prints a territory summary on screen for 180 seconds
5. Spawns randomized ground defenses at every Red base
6. Activates fixed SA-2 / SA-6 SAM sites based on territory and probability
7. Dynamically spawns roaming SA-9 / SA-13 units at Red bases and in Red territory
8. Prints a SAM summary on screen (type, site name, GPS coordinates) for 180 seconds
9. Spawns one supply convoy, one mechanized convoy, and one armor convoy — each on a different route between Red airbases
10. Draws a labeled green circle (27km radius) on the F10 map at each convoy's estimated 35-minute position
11. Prints a combined convoy summary on screen (route, heading, GPS per convoy) for 180 seconds
12. Generates 3 S&D strike missions (one per threat level: low/med/high), draws orange circles on F10 map, prints GPS + target + launch time on screen for 60 seconds
13. Arms each missile site with a randomized launch timer; at expiry each surviving Scud TEL fires at a randomly selected Blue airbase (staggered 4 seconds apart)

**Spawn slots:** DCS Dynamic Spawn (enabled per-airbase in the Mission Editor) correctly shows/hides player slots based on `setCoalition()`. No scripting required.

**Ground defenses:** Each Red base gets randomized counts of AK infantry, RPG infantry, SA-18 Igla MANPADS, BTR-80, Ural trucks, and ZU-23 AAA. Each unit spawns at an independent random position 800–2000m from the airbase threshold.

**SAM sites:** Fixed SA-2/SA-6 sites pre-placed in ME as late-activation groups. Roaming SA-9/SA-13 dynamically spawned via `coalition.addGroup()`. All active SAMs print GPS coords on screen at mission start.

**Convoys:** Three types spawn each session with randomized skill (Average/Good/High per convoy). Routes are capped at 175 km; if no base is within range the nearest is used. Island bases (Gecitkale, Ercan) only route to other Cyprus bases — no cross-water routes.

**Strike missions:** Three S&D missions generated each session — one per threat level (low/med/high), order shuffled. Each mission picks a random valid location type. Currently only the ballistic missile target type is implemented. Each missile site: 1–5 Scud-B TELs (each its own 1-unit group, 200m spread) + support infantry/vehicles (300m spread) + air defense group offset 400–900m from site center. Site positions are retried up to 10 times to avoid spawning in water. Launch timers currently set to 2–3 min for testing.

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
| `town` | At a named Syrian town coordinate (not valid for missile missions) |
| `road` | Road-snapped point 15–60 km from a Red base (not valid for missile missions) |

### S&D Target Types — Status

| Target | Status | Valid Locations | Units |
|---|---|---|---|
| Ballistic missile | ✅ Done | `airbase`, `country` | 1–5 Scud-B TELs + infantry/BTR-80 support + per-threat air defense |
| Troops | 🔲 Next | `airbase`, `town`, `road` | Infantry cluster + vehicles, no TELs |
| VIP | 🔲 Next | `road`, `country` | Single high-value command vehicle + small escort |

### S&D Air Defense Loadouts (per mission, spawned near target)
| Threat | Units |
|---|---|
| Low | 1–2 ZU-23 (`Ural-375 ZU-23`) + 1–2 MANPADS (`SA-18 Igla manpad`) |
| Med | 1 SA-9 (`Strela-1 9P31`) + 1 ZU-23 |
| High | 1 SA-13 (`Strela-10M3`) + 1–2 Shilka (`ZSU-23-4 Shilka`) |

Air defense group spawns 400–900m from site center (150m internal spread).

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
        spawner.lua                 ← position helpers, coalition.addGroup wrapper, fireGroups, isOnLand
    modules/
        coalition_setup.lua         ← cluster definitions + CoalitionSetup.assign()
        defense_setup.lua           ← ground unit definitions + DefenseSetup.spawn()
        sam_setup.lua               ← SAM activation + spawning (SA-2/6/9/13)
        convoy_setup.lua            ← supply/mechanized/armor convoy spawning
        mission_setup.lua           ← thin orchestrator: calls SdMission + CasMission
        sd_mission.lua              ← S&D missions (ballistic missile implemented; troops/VIP next)
        cas_mission.lua             ← CAS missions (stub only, not yet implemented)
    slotblock.lua                   ← hook script (inactive, kept for reference)
```

### Module API
- `CoalitionSetup.assign()` → returns `assignments` (list of `{name, side}`), `clusterSides` (cluster id → coalition.side)
- `DefenseSetup.spawn(assignments)` → spawns ground defenses at all Red bases
- `SamSetup.spawn(clusterSides, assignments)` → activates/spawns all SAM systems
- `ConvoySetup.spawn(clusterSides, assignments)` → spawns supply, mechanized, and armor convoys
- `MissionSetup.generate(assignments)` → orchestrates all mission types
- `SdMission.generate(assignments)` → spawns S&D missions (one per threat level)
- `CasMission.generate(assignments)` → stub, no-op

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

### Screen Output
Active SAMs are printed on screen for 60 seconds at mission start with GPS coordinates in DMS format.

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
- Confirmed correct type strings: `Soldier AK`, `Soldier RPG`, `BTR-80`, `SA-18 Igla manpad`, `Ural-375 ZU-23`, `Ural-4320-31`, `KAMAZ Truck`
- DCS replaces unknown unit types with Leopard-2 (not a crash, easy to miss without checking the log)

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

### Surface Type Check
- `land.getSurfaceType({x=north, y=east})` returns `land.SurfaceType.LAND`, `SHALLOW_WATER`, `WATER`, `ROAD`, or `RUNWAY`
- Use to reject water positions for mission spawns; retry up to N times before accepting the last candidate
- Only applied to S&D/CAS mission spawning — convoy/defense/SAM spawning is anchored close enough to airbases that water is not a practical issue

### DCS Timer and Screen Messages
- `timer.getAbsTime()` returns seconds since midnight of the mission day — use for displaying human-readable game clock times (format with `% 86400` then convert to HH:MM:SS)
- `outText` called every second with a short duration creates a live countdown display but will stomp on other active `outText` messages — use a static one-time `outText` instead and show the computed launch time in game clock format
- `timer.scheduleFunction(fn, arg, t)` requires `t` to be strictly in the future; scheduling at exactly `timer.getTime()` (delay=0) may be silently dropped — use a minimum offset of 2+ seconds

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
- [ ] Confirm `Scud_B` type string — appears correct (missiles fire), not yet explicitly verified via getTypeName()
- [ ] Confirm `GAZ-3308` unit type string (no woCar errors seen but not in debug groups yet)
- [ ] Increase Scud launch timers from 2–3 min (testing) to 10–25 min for real play
- [ ] Confirm correct DCS name for Ghabagheb airbase (currently commented out of DAMASCUS cluster)
- [ ] Fix `world.getAirbases()` dump — returns empty at mission start, may need timer delay
- [ ] Add more SA-2/SA-6 fixed sites (up to 8 planned)
- [ ] Remove `Log.dumpLateGroupUnits` call from init.lua and debug groups A/B/C/D from ME once no longer needed
- [ ] S&D: troops mission — infantry cluster + vehicles at airbase/town/road location
- [ ] S&D: VIP mission — single command vehicle + small escort at road/country location
- [ ] S&D: randomizer to mix target types across the 3 per-session missions (currently all missile)
- [ ] CAS: design pre-built ME group naming convention for targets and friendlies
- [ ] CAS: implement fuel depot / ammo dump target type
- [ ] F10 menu for mission info / admin commands
- [ ] Investigate why airfield icons don't change color in singleplayer

---

## Research Files

- [Scripting Architecture](research_scripting_architecture.md) — Lua environments, frameworks, file organization, F10 menu API
- [Airbase API](research_airbase_api.md) — setCoalition, autoCapture, airbase methods, workarounds
- [Syria Airbases](research_syria_airbases.md) — complete airbase inventory with coordinates and cluster suggestions
- [Runway Lengths](research_runway_lengths.md) — F-16 viability by base (2,500m+ / marginal / too short)
