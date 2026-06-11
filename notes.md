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

## Current Status — Session 3 Complete

At mission start, the script:
1. Randomizes which contested clusters go Red vs Blue
2. Calls `Airbase:setCoalition()` on every base in each cluster
3. Draws colored circles on the F10 map (blue = Blue territory, red = Red territory)
4. Prints a territory summary on screen for 60 seconds
5. Spawns randomized ground defenses at every Red base

**Spawn slots:** DCS Dynamic Spawn (enabled per-airbase in the Mission Editor) correctly shows/hides player slots based on `setCoalition()`. No scripting required.

**Ground defenses:** Each Red base gets randomized counts of AK infantry, RPG infantry, SA-18 Igla MANPADS, BTR-80, Ural trucks, and ZU-23 AAA. Each unit spawns at an independent random position 800–2000m from the airbase threshold, spread around the full perimeter.

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
    slotblock.lua                   ← hook script (inactive, kept for reference)
```

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

---

## Cluster Definitions (coalition_setup.lua)

| Cluster | Type | Bases |
|---|---|---|
| Southern Cyprus | Always Blue | Akrotiri, Larnaca, Paphos, Kingsfield, Lakatamia |
| NATO Northern Arc | Always Blue | Incirlik, Adana Sakirpasa, Hatay, Gaziantep, Gazipasa |
| Israel & Jordan | Always Blue | Ramat David, Ben Gurion, Haifa, Tel Nof, Hatzor, King Abdullah II, Muwaffaq Salti, Marka |
| Russian Core (Latakia) | Always Red | Bassel Al-Assad, Hama, Taftanaz, Minakh |
| Damascus Basin | Always Red | Damascus, Mezzeh, Al-Dumayr, Marj as Sultan N/S, Khalkhalah, Marj Ruhayyil, Tha'lah |
| Aleppo Region | **Contested** | Aleppo, Kuweires, Jirah, Abu al-Duhur |
| Central Syria (T4) | **Contested** | Shayrat, Tiyas, Palmyra, Al Qusayr, Sayqal |
| Lebanon | **Contested** | Beirut-Rafic Hariri, Rayak, Rene Mouawad |

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

---

## Open Questions / Next Steps

- [x] Research and test DCS Dynamic Spawn system with `setCoalition()` — works correctly, slots appear/disappear based on coalition
- [x] Spawn defensive ground units at Red-controlled bases
- [ ] Randomize location spawn in RED country of one SA-13 Gopher (80% of missions), One SA-8 Gecko (25% of missions), one Shilka (70% of the missions)
- [ ] F10 menu for mission info / admin commands
- [ ] Randomized individual missions
- [ ] Investigate why airfield icons don't change color in singleplayer (only coalition shown when clicked)

---

## Research Files

- [Scripting Architecture](research_scripting_architecture.md) — Lua environments, frameworks, file organization, F10 menu API
- [Airbase API](research_airbase_api.md) — setCoalition, autoCapture, airbase methods, workarounds
- [Syria Airbases](research_syria_airbases.md) — complete airbase inventory with coordinates and cluster suggestions
