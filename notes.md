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

## Current Status — Session 4 Complete

At mission start, the script:
1. Randomizes which contested clusters go Red vs Blue
2. Calls `Airbase:setCoalition()` on every base in each cluster
3. Draws colored circles on the F10 map (blue = Blue territory, red = Red territory)
4. Prints a territory summary on screen for 60 seconds
5. Spawns randomized ground defenses at every Red base
6. Activates fixed SA-2 / SA-6 SAM sites based on territory and probability
7. Dynamically spawns roaming SA-9 / SA-13 units at Red bases and in Red territory
8. Prints a SAM summary on screen (type, site name, GPS coordinates) for 60 seconds

**Spawn slots:** DCS Dynamic Spawn (enabled per-airbase in the Mission Editor) correctly shows/hides player slots based on `setCoalition()`. No scripting required.

**Ground defenses:** Each Red base gets randomized counts of AK infantry, RPG infantry, SA-18 Igla MANPADS, BTR-80, Ural trucks, and ZU-23 AAA. Each unit spawns at an independent random position 800–2000m from the airbase threshold.

**SAM sites:** Fixed SA-2/SA-6 sites pre-placed in ME as late-activation groups. Roaming SA-9/SA-13 dynamically spawned via `coalition.addGroup()`. All active SAMs print GPS coords on screen at mission start.

---

## Script Architecture

### File Locations
- **Git repo:** `C:\Users\johnk\Git\dcs\scripts\`
- **DCS runtime:** `C:\Users\johnk\Saved Games\DCS\Scripts\a2a_dynamic_syria\`
- Files must be manually copied from repo to DCS after edits (or use PowerShell Copy-Item)

### File Structure
```
scripts/
    init.lua                        ← entry point, loaded by mission trigger
    lib/
        logger.lua                  ← global Log table (Log.info/warn/error/debug)
        spawner.lua                 ← position helpers + coalition.addGroup wrapper
    modules/
        coalition_setup.lua         ← cluster definitions + CoalitionSetup.assign()
        defense_setup.lua           ← ground unit definitions + DefenseSetup.spawn()
        sam_setup.lua               ← SAM activation + spawning (SA-2/6/9/13)
    slotblock.lua                   ← hook script (inactive, kept for reference)
```

### Module API
- `CoalitionSetup.assign()` → returns `assignments` (list of `{name, side}`), `clusterSides` (cluster id → coalition.side)
- `DefenseSetup.spawn(assignments)` → spawns ground defenses at all Red bases
- `SamSetup.spawn(clusterSides, assignments)` → activates/spawns all SAM systems

### Mission Editor Trigger
- **Type:** ONCE
- **Condition:** TIME MORE, 1 second
- **Action:** DO SCRIPT
- **Text:** `dofile(lfs.writedir() .. "Scripts\\a2a_dynamic_syria\\init.lua")`

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

---

## Cluster Definitions (coalition_setup.lua)

| Cluster | ID | Type | Bases |
|---|---|---|---|
| Southern Cyprus | CYPRUS_SOUTH | Always Blue | Akrotiri, Larnaca, Paphos, Kingsfield, Lakatamia |
| At Tanf | AT_TANF | Always Blue | At Tanf |
| Russian Core (Latakia) | RED_CORE | Always Red | Bassel Al-Assad, Hama, Taftanaz, Minakh, Wujah Al Hajar |
| NATO Northern Arc | TURKEY | Contested | Incirlik, Adana Sakirpasa, Hatay, Gaziantep, Gazipasa, Sanliurfa, Pinarbashi, Gecitkale |
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
- Unit type strings unconfirmed — check log for Leopard-2 replacements (`woCar: Unit X is unknown`)

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
- Confirmed correct type strings: `Soldier AK`, `Soldier RPG`, `BTR-80`, `SA-18 Igla manpad`, `Ural-375 ZU-23`, `Ural-4320-31`
- DCS replaces unknown unit types with Leopard-2 (not a crash, easy to miss without checking the log)

### Late-Activation Groups
- Place group in ME, right-click → set to Late Activation
- Activate at runtime with `Group.getByName("name"):activate()`
- Group must exist in the mission file — `Group.getByName()` returns nil if name doesn't match exactly

### Coordinate Conversion
- `coord.LOtoLL(vec3)` converts a DCS Vec3 to decimal lat/lon
- `Group:getUnit(1):getPoint()` returns a Vec3 suitable for passing to `coord.LOtoLL()`

### world.getAirbases() Dump
- `world.getAirbases()` returns a numerically-indexed table — use `ipairs`, not `pairs`
- Currently returns empty at T+0.3s on Syria map (timing issue suspected); dump not yet useful for name verification
- Workaround: check airbase name mismatches from WARN log lines at mission start

---

## Open Questions / Next Steps

- [x] Research and test DCS Dynamic Spawn system with `setCoalition()` — works correctly
- [x] Spawn defensive ground units at Red-controlled bases
- [x] SA-2 and SA-6 fixed sites with cluster-based territory check
- [x] SA-9 and SA-13 roaming SAMs with probabilistic spawning
- [x] Expand cluster coverage to all Syria map airbases
- [ ] Confirm SA-9 (`Strela-1 9P31`) and SA-13 (`Strela-10M3`) unit type strings in DCS
- [ ] Confirm correct DCS name for Ghabagheb airbase (currently commented out of DAMASCUS cluster)
- [ ] Fix `world.getAirbases()` dump — returns empty at mission start, may need timer delay
- [ ] Add more SA-2/SA-6 fixed sites (up to 8 planned)
- [ ] F10 menu for mission info / admin commands
- [ ] Randomized individual strike missions
- [ ] Investigate why airfield icons don't change color in singleplayer

---

## Research Files

- [Scripting Architecture](research_scripting_architecture.md) — Lua environments, frameworks, file organization, F10 menu API
- [Airbase API](research_airbase_api.md) — setCoalition, autoCapture, airbase methods, workarounds
- [Syria Airbases](research_syria_airbases.md) — complete airbase inventory with coordinates and cluster suggestions
