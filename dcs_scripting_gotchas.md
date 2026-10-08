# DCS scripting gotchas

**The one list of DCS facts learned the hard way, for the whole repository** (John, 2026-10-07: in the repository, at the root, so every session can read it). Read it before writing a DCS script, above all a standalone one (a survey, a probe, a test mission), and add to it whenever DCS surprises us. Grouped by subject; each entry says where it was found when that helps.

Moved here 2026-10-07 from `shared_mission_framework\framework_design.md` (*DCS facts learned the hard way*) and from Claude's own notes, so there is one place.

---

## The mission scripting environment

- **De-sanitize `MissionScripting.lua`** (`DCS World\Scripts\MissionScripting.lua`: comment out the `sanitizeModule('os')`, `('io')`, `('lfs')` lines) for anything that writes files, times itself or runs a program. **DCS must be restarted** after editing it; a running DCS keeps the old one.
- **`math.randomseed` doesn't exist** in the mission environment (2026-10-07: the terrain probe's first run failed on it). Use a small generator of our own with a fixed seed (`map_surveys\probe_terrain_survey_costs.lua`, `random()`), which also makes runs repeatable.
- **`lfs.dir` returns an iterator and a state object** (2026-10-07: `show_spawn_sites.lua` failed with "bad argument #1 to '(for generator)'"). Never `pcall(lfs.dir, …)` and loop over the first result. Check the folder with `lfs.attributes(path).mode == "directory"`, then `for name in lfs.dir(path) do`. An offline stand-in for `lfs.dir` must demand the state too, or it hides this.
- **`string.gsub` returns two values** (the string and a count): `f(s:gsub(…))` passes the count as `f`'s next argument. Wrap it, `f((s:gsub(…)))`. (2026-10-07: `lfs.attributes(path:gsub(…))` read the count as its attribute name and answered nil, so the viewer said a folder that existed didn't.)
- **`os.execute` silently runs nothing past ~260 characters:** put the steps in a `.cmd` and call that. It waits for the command; `start "" /min "<cmd>"` returns at once (the radio calls start their programs that way).
- **`os.clock` is wall time on Windows,** so it counts DCS loading files, not only our CPU. `timer.getTime()` doesn't move within one frame: use `os.clock` to time work inside a frame.
- **Coroutines work;** yielding across a `pcall` doesn't (Lua 5.1). Long jobs (the surveys) run in a coroutine resumed by `timer.scheduleFunction` and yield between pieces of work, never from inside a `pcall`.
- **DCS ships Lua 5.1** (`DCS World\bin\luae.exe` runs scripts offline): no `goto`, no integer division operator.
- **`env.info()` lines appear under `SCRIPTING`** in `dcs.log`, not `INFO`: grep `SCRIPTING` (or our own tag, `[KOLA]`, `[TERRAIN PROBE]` …).
- **Thousands of ground units cost frame rate even with their AI off** (`setOnOff(false)`, "Ground Nothing"; 2026-10-08: the spawn site viewer's 11,533 trucks and ~3,400 map drawings put the F10 map at 9 fps, and `dcs.log` said `ModelTimeQuantizer: ANTIFREEZE ENABLED` right after the spawn). A viewer keeps units few, and `hidden = true` on the group keeps them off the F10 map (whether F7 still cycles hidden groups: to confirm).
- **`dcs.log` is overwritten when DCS restarts;** `dcs.log.old` holds only the session before. Anything needed to review a run belongs in the per-run event log; read `dcs.log` before DCS is started again.

## Triggers and the mission file

- **Use ONCE + TIME MORE 1, not MISSION START,** for the trigger that runs a script: a MISSION START trigger with any condition is silently dropped at t = 0.
- **Building a `.miz` by script:** start from one of John's missions on the same map and change only what's needed (`map_data_tools\find_spawn_sites.py make-missions` swaps the script in the trigger's text, in both places the editor keeps it: `trig` and `trigrules`). Lock the first waypoint's time (`ETA_locked`) on any group you add, or the editor refuses to save.
- **`mission.coalitions` lists every country on a side even with no units;** `mission.coalition.<side>.country` lists only countries that have units. A script can spawn for any country in `coalitions` (the survey missions spawn statics as CJTF Blue, id 80, into an empty mission).
- **Dynamic slots follow `Airbase:setCoalition()`:** enable Dynamic Spawn per airbase in the editor; slots appear and disappear with the base's owner, no hook needed. `onPlayerTryChangeSlot` doesn't fire for dynamic slots (ED bug).
- **`trigger.action.setAirbaseOwner()` doesn't exist** (a community myth): the call is `Airbase:setCoalition()`.

## Map drawings and text

- **Colours are positional tables** `{ r, g, b, a }`: named keys (`{ r = 1, … }`) draw invisible shapes.
- **`outText` is plain text:** no colour or markup; only ASCII symbols to set lines apart.

## The world and the terrain

- **Trees are invisible** to every API: `world.searchObjects` finds nothing in forest, `land.isVisible` is terrain-only. Nothing a script measures can tell forest from open ground (proven by probes, 2026-09-23). Taxiways and aprons read as `RUNWAY` in `land.getSurfaceType`; airfield buildings are visible as scenery.
- **`Airbase:getPoint()` is the runway threshold, not the middle of the field:** rings and offsets around it sit lopsided; the framework uses the mean runway midpoint.
- **The sign of a runway's `course` is inconsistently documented:** both are probed against the runway surface (`gather.lua`, `gatherRunways`).
- **Airbase queries return empty at T+0:** read them a few seconds in.
- **DCS's magnetic is grid-based** (Kola bug 61, 2026-10-05): the F-16's HUD heading (and the F10 ruler's M) = the map's grid heading minus the magvar module's variation; grid north is treated as true north. A direction worked out from true north (lat / lon) is off by the grid's convergence (Kola: ~1° at 22° E, ~6° near Ivalo). Anything a player compares with the jet's instruments: grid direction − variation. Every map.
- **Terrain call costs** (Afghanistan, measured by the terrain probe 2026-10-07, wall time): `land.getHeight` ~65 µs; `land.getSurfaceType` ~24 µs; `land.getClosestPointOnRoads("roads")` ~0.16 ms; **`"railroads"` ~0.2 s a call** on a map with no railways (Afghanistan): never call it there; `world.searchObjects` (scenery) ~5–6 µs per object found, so a 10 km sphere over Kabul (752,000 objects) is a 2 s stall in one call: search small tiles; `land.isVisible` ~0.18 ms; `land.findPathOnRoads` over 10 km ~0.16 s.
- **Afghanistan's map:** dense scenery (~1.5 million objects in 60 × 60 km around Kabul, mostly `PARTHOUSEAFGHANISTAN_*`); heliports report as category AIRDROME; three "airdromes" (FOB Camp Dubs, FOB Clark, FOB Thunder) are placeholders far off the map (x −3,759,657, z −9,428,368) with no runways or parking: skip them. pydcs has no Afghanistan terrain and the map's `terrain.cfg.lua` is encrypted: its facts come from DCS itself (the probe's `airbases.lua`).

## Spawning

- **Static objects must spawn before any AI units.** After ~800 units, `coalition.addStaticObject` took ~3 s per parked aircraft (a 3-minute start-up stall); spawned first, 250 objects take 0.5 s. `run_mission.lua`'s spawn block keeps this order ("KEEP THIS ORDER"). When a spawn is slow, time it per category and type, in an empty world and a full one, before guessing.
- **A player aircraft in the world slows every spawn:** 227 static objects took 71 s instead of 0.5 s with a Client F-16 on the ramp. So players come in by dynamic spawn after init.
- **First spawn of each aircraft type freezes the sim** (fixed by the preload).
- **An unknown unit type becomes a Leopard-2,** with only `woCar: Unit X is unknown, replaced with Leopard-2` in `dcs.log`: grep `replaced with` after adding unit types. An unknown static type isn't there at all, with no error: look it up by name after spawning and compare `getTypeName()` (`spawn_static_objects.lua` does).
- **Script-spawned units on the F-16's HSD** (Kola bug 25, `closed.md`; confirmed 2026-10-02): what works, all together (several things changed in one run, so keep every part): AI aircraft with an explicit group id, EPLRS as the first task of the first waypoint (`WrappedAction` `EPLRS` naming that group id), a Link 16 STN and the editor's `datalinks.Link16` block per unit; SAM groups with `hiddenOnMFD = false`, Red's as country Russia; player slots as CJTF Blue with their own STNs. STN + `setCommand` EPLRS after a ramp spawn, with CJTF SAMs, showed nothing.

## Events

- **`S_EVENT_DEAD` and `S_EVENT_HIT` fire for non-unit objects:** the initiator or target can be a weapon, a scenery object or terrain. Scenery objects exist but have no `getID`, `getTypeName` or `getGroup`, and a map object's name can be a number (Kola bug 66). Check `getCategory()` before calling unit methods; `getPlayerName()` too.

## The AI

- **`weapons_free` means engage anything detected;** with an AWACS's datalink that's a lot (a patrol left its route from takeoff and died in an SA-11 ring). Use `open_fire` + zone engage tasks for planned patrols.
- **An AI descends toward the next waypoint's altitude from the previous one.**
- **It climbs the same way, and counts a waypoint reached a few km early.** A pop-up with its altitude only on the launch point was a third of the way up there (Kola bug 40); a waypoint at full altitude right after the climb's start makes it climb hard.
- **The AI fires an anti-radiation missile only at a radar it detects** (`getDetectedTargets(RWR)`): no ping, no shot, whatever its orders (Kola bug 36). A site's radar may not be on the flight yet at the launch point; an `EngageGroup` fires the moment it is.
- **SAMs reload, slowly, and only from a supply truck** (checked 2026-10-04): a launcher rearms from a supply truck within ~600 ft (~183 m; John measured the circle in the mission editor, 2026-10-04): a unit with `GT.warehouse = true`, drawn with a supply circle in the mission editor; only some truck variants are (John). The ones that reload: **"Truck Ural-4320"** for Red (type string `Ural-375`, as our SA-10, SA-11 and SA-6 recipes carry) and **"Truck M939 Heavy"** for Blue (type `M 818`, as our Patriot and Hawk recipes). Not to be confused with the `Ural-4320-31` ("Arm'd") or `Ural-4320T` ED's own templates also use. Reload times from DCS's own unit files: S-300PS launchers (HeavyMetal) 7,200 s, so 2 h; Currenthill Pantsir 900/12 s and Tor M2 900/16 s, IRIS-T SLM 1,800/8 s, TechWeaponPack NASAMS 300 s per missile (`reload_time` is per package, so the per-missile reading of the Currenthill numbers isn't certain). The Patriot's, SA-11's and other base-DCS times are in the encrypted database. Coalition, not nationality, decides which truck rearms whom (forum). **Since 2026-10-04 every SAM gets supply trucks** (`SAM_SITE_SUPPLY`, `Placement.supplyTruckPoints`): each SAM site (not early warning) gets its coalition's `supply_truck` placed last, where every launcher and its escort are within 165 m (183 − an 18 m margin), a second truck only if one can't reach all; each base-defense SAM group (radar and infrared missile launchers, MANPADS teams: `supply_truck = true` in `BASE_DEFENSE_PLACEMENT`) gets one in a group of its own, `<id>_supply` (so a live truck never keeps a dead SAM group alive; not slept, not a sensor, no map mark of its own). The NASAMS, IRIS-T, SA-8 and SA-15 recipes and the base-defense Tors / Pantsirs have no truck and never reload. In the 2026-10-03 14:15 run both SA-10s emptied all 20 interceptors on the first salvo and fired none at the second, 15–21 min later.
- **DCS's own AWACS voice fails without a callsign:** "Callname -1 not found for MSN2001_AEW_1" tracebacks in `dcs.log` (harmless; the E-3A spawns with none).
- **AI wingmen follow their lead in the landing,** and once the lead has parked they may hold or go around (Kola bug 75, open; the landing-option fix `setOption(36, 1)` is to try).

## Harmless log noise

- "livery not found" (CJTF with no `livery_id`); missing wreck models (`Ural-375_p_1`, `MOBILE_GENERATOR_CRASH`); DCS's own AWACS "Callname -1" tracebacks.
