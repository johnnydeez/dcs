# Shared Mission Framework — Plan

> **What this is:** the shared tools, libraries, files and data used to create and run custom (multiplayer) DCS missions: the Lua that plans and runs a mission inside DCS, the radio calls outside it, the Python tools that build a map's data, and the data that holds on any map. It is taken out of the Kola mission (`missions/kola_f16_random_tasking/`) so that a new **Caucasus random tasking** mission, and later the **Afghanistan campaign** (`missions/afghanistan_campaign/`), run on the same code. A fix or a change made once applies to every mission.
>
> **State (2026-10-06):** plan done; **step 0 done** (the offline test harness and its baselines); **step 1 done** (Kola's names and map facts in `kola_f16\mission_settings.lua`); **step 2 done** (the override merge; retired in step 7, *Settings that differ by mission*); **step 3 done** (Kola's `init.lua` split: `load_framework.lua`, `run_mission.lua`). All tested and copied to DCS; **John's checkpoint flight passed** (2026-10-06 17:47, *Progress*). **Step 4 done** (the move: the framework's Lua in `shared_mission_framework\mission_scripts\`, Kola loads it from there; tested, copied to DCS; John's flight after it passed, 18:53). **Step 5 done** (the radio and the map tools in the framework; the tools take a mission folder and read its `mission_settings.lua`; tested, copied to DCS; John's flight after it passed, 20:04). **Step 6 done** (the docs: how the code works in `as_built.md`, Kola's `plan.md` keeps its status and its map and scenario). **Step 7 under way: the Caucasus random tasking, the same style as Kola on a different map** (John, 2026-10-06; *The Caucasus mission*; progress at the end of *Progress*): the mission folder, map data, zone and footprint surveys, slots, a first start in DCS, the harness's `caucasus` entry, and settings individual to a mission moved into the missions' data (the override files retired).
>
> **Running the tests** (from `shared_mission_framework\offline_test_harness\`): `python replay_and_compare.py kola` (tests A, B and C: 11 runs, ~2 min) and `python rerun_data_tools.py kola` (test D, seconds). Both end with one line: all the same as the baseline, or what differs.
>
> **Paths** are relative to the repository root (`C:\Users\johnk\Git\dcs\`) unless they say otherwise.
>
> **Working rules** (carried over from Kola):
> - Commits are always done by John, on his own schedule; never ask about or perform a commit.
> - Name things by what they are or do, in full words, folders included; no abbreviations in code names.
> - Decide with John step by step; present proposals before building.
> - No wildcard deletes: a delete names its exact path.
> - After any edit to the Lua, copy the tree to `Saved Games\DCS\Scripts\` at once (both trees, once the split is made), except during a run John is flying.
> - **Kola keeps working all the way through.** It is still in active development, with fixes built and not yet flown (Kola `plan.md`, *Next (2026-10-06)*).
> - **Syria stays completely separate** (`missions/syria_a2g/`): no shared code, as Kola's plan has always said.

---

## Decided (John, 2026-10-06)

1. **No duplicated code.** Every piece of logic lives in one place, the framework, so a change or bug fix reaches every mission. **A setting that is individual to a mission lives only with that mission's files, never as an override of the library** (John, 2026-10-06, replacing the first design's shared default + mission override: "we don't want each custom mission overriding stuff from the library, that gets messy"; *Settings that differ by mission*).
2. **Map data stays with the mission** for now (zones, airbases, slots, frequencies…). It moves to a per-map folder only if two missions ever share a map.
3. **The name:** `shared_mission_framework`. Inside it, the folders say what they hold (*Layout*).
4. **Docs:** the framework has its own `development_docs/` (this `plan.md`, `as_built.md`); each mission keeps its own plan. **The roadmap, bugs and closed items: one `roadmap.md`, `bugs.md` and `closed.md` at the repository's root for every mission and the framework** (John, 2026-10-07), each item and bug saying which it is for. Kola's *As built* and *Architecture* sections move here (step 6: `as_built.md`); Kola's run notes, bug list and mission-specific tuning stay in Kola. Code comments that cite a Kola bug number say so: "Kola bug 41".
5. **When:** the whole rework plan first (this file), then the steps; John flies Kola after the first few (steps 1–3), before anything is moved into the framework.

---

## What the code showed (2026-10-06)

Read before planning, so the split follows what the files actually hold:
- **The logic barely knows it's on Kola.** In `lib/`, `stages/` and `consumers/`, Kola base and map names appear almost only in comments. The one real hard-coded spot is the magnetic-variation self-test at Rovaniemi (`kola_f16/consumers/call_air_picture.lua`, `plan.world.airbases["Rovaniemi"]`).
- **The map lives in data and in the Python tools:** `zones`, `clusters`, `airbase_codes`, `airbase_classes`, `airbase_footprints`, `forested_airfields`, `player_slots`, `airfield_frequencies`, the magnetic-variation fallback table (`AIR_PICTURE_CALLS.fallback_magnetic_variation`), the UTC offset (`CONFIG.UTC_OFFSET_H`), the projection (`kola_data_tools/kola_proj.py`) and `kola_data_tools/kola_airbases.json`.
- **Kola's identity is written into a few places:** `SCRIPT_DIR = Scripts\kola_f16\` (`init.lua`), the `[KOLA]` log tag (`lib/logger.lua`, `init.lua`), `kola_last_plan.lua` (`CONFIG.PLAN_DUMP_FILE`), the event log's folder and `kola_event_logs` fallback (`data/event_log.lua`) and its header line, the radio's `calls_file` and `start_command` (absolute paths into the Kola folder, `data/radio_calls.lua`), the `KOLA-RADIOS` tag (`radio_calls/export_cockpit_radios.lua`), the window titles in `radio_calls/start_radio_calls.cmd`, the zone survey's `MISSION_DIR`, `kola_zone_terrain.lua` and `kola_zone_update.log` (`survey/survey_zone_terrain.lua`), and Red's SAMs spawned as country Russia (`init.lua`).
- **Blue is assumed in ~69 places** (`side.BLUE`, `"blue"`, 34 files): players, the radio, *Airfield info*, the brief. Fine for Caucasus (players fly Blue). The Afghanistan plan needs every player feature on both coalitions; that is its own later step (*Later*), not part of the split.
- **Size:** ~56,000 lines in all, most of it generated data (`aircraft_pylons` 15,678, `airbase_footprints` 9,985, `zones` 3,209). The logic is ~17,000 lines of Lua and ~2,600 of Python.

---

## Layout

```
shared_mission_framework\             (repository root, beside missions\)
  development_docs\                   this plan
  mission_scripts\                    the Lua that runs inside DCS; copied to Saved Games\DCS\Scripts\shared_mission_framework\
    load_framework.lua                loads the framework, then the mission's data, in order (new)
    run_mission.lua                   the run sequence, today in Kola's init.lua (moved)
    config.lua                        CONFIG defaults (mission identity and map facts come from the mission)
    gather.lua
    lib\                              util, logger, weather, placement, threat_routing, sam_reach, flight_callsigns
    data\                             shared data and shared defaults (below)
    stages\                           every stage
    consumers\                        every consumer, control_air_flights\ included
    survey\                           the in-DCS surveys (zone terrain, airbase footprints, parked-aircraft probe)
  radio_calls\                        the radio player, helper, phrase banks, voices, radio sound, export script
  map_data_tools\                     the Python that builds data from DCS and a map (today kola_data_tools\)
  offline_test_harness\               stubbed DCS + replay tests, kept this time (*How the transfer is tested*)

missions\kola_f16_random_tasking\
  kola_f16\                           the mission's own scripts; copied to Saved Games\DCS\Scripts\kola_f16\
    init.lua                          names the mission and its folders, then hands over to load_framework.lua
    mission_settings.lua              identity and map facts: name, log tag, folders, UTC offset, magnetic variation, map edges
    data\                             map data, scenario data, and the settings each mission has its own values for (below)
  map_data_sources\                   kola_airbases.json and other inputs the map tools read for this map
  kola_f16_random_tasking.miz, development_docs\, event_logs\

missions\caucasus_multiplayer_random_tasking\   the same shape (scripts folder caucasus_f16)
```

### Which file goes where

**Framework, shared as is** (facts about DCS, true on every map):

| File | Why |
|---|---|
| `unit_pool`, `aircraft_pylons` (offline only), `aircraft_loadouts` (+ `AIRCRAFT_LOADOUT_OPTIONS`), `aircraft_profiles`, `cloud_presets` | Generated from the DCS install or about aircraft types, not maps |
| `sam_site_recipes`, `base_defense_placement`, `fixed_ground_target_recipes`, `convoy_recipes` | How a system or a target is built and placed |

**Framework, shared tuning** (every mission uses it as is; a setting found to differ by mission moves out of these into every mission's data, *Settings that differ by mission*):

| File | Holds |
|---|---|
| `config` | `CONFIG` (debug flags, placement clearances, drawing switches; identity and map facts move to `mission_settings.lua`) |
| `air_tasking` | `AIR_MISSION_TYPE`, `AIR_STANDOFF_WEAPONS`, `AIR_DEAD_WEAPONS`, `AIR_WEAPON_TYPE`, `AIR_TASKING_PER_COALITION`, `AIR_TARGETING`, `AIR_TASKING_TIMING`, `AIR_TASKING_SKILL`, `AIR_PACKAGE`, `HUMAN_TASKING`, `AIR_DEFENSE`, `AIR_ROUTING` |
| `air_control`, `radar_picture`, `air_picture_calls`, `radio_calls`, `event_log`, `ground_unit_sleep`, `airspace` | The controller, the picture, the calls, the radio's channels and kinds, the event log, sleeping units, the airspace grid |
| `base_defense_levels`, `base_defense_composition`, `sam_site_density`, `fixed_ground_target_density`, `flight_callsigns` | How much of everything per roll; callsign names |

The distances in these were set on Kola's ~1,400 × 1,000 km map (100 km fronts, a 30 km contested band, 250 km AWACS reach); a smaller map like Caucasus needs some of them different, and each one that does moves into the missions' data.

**Mission, map data:** `zones`, `airbase_codes`, `airbase_classes`, `airbase_footprints`, `forested_airfields`, `player_slots`, `airfield_frequencies`; in `mission_settings.lua`: the UTC offset, the magnetic-variation fallback table and the airbase its start-up self-test reads, the map's edges (`map_bounds_m`).

**Mission, its own settings** (moved out of the shared files, 2026-10-06): `radio_channels` (`RADIO_CHANNELS`: the AWACS, mission and airfield channels, clear of the map's tower frequencies), `awacs_orbit_distances` (`AWACS_ORBIT_DISTANCES`: how far AWACS orbits keep from enemy fighter bases and the contested airspace).

**Mission, scenario data:** `clusters` (who holds what, how the roll goes), `coalition_rosters` (who fields which ground units, SAMs, aircraft, targets), and the country each coalition's SAMs spawn as (Red as Russia on Kola: from `init.lua` into data). Scenario data isn't code: a new mission may start from a copy of Kola's rosters and change them freely.

**Python:**
- `radio_calls\` moves whole into the framework (only one mission runs at a time, so one radio player and helper serve whichever runs; ports 47110–47112 stay). The phrase banks are shared; the test samples in `flight_phrase_wording.py` keep their Kola names (they're only examples).
- `kola_data_tools\` becomes `map_data_tools\`: `dcslua.py`, `unit_pool.py`, `unit_role_overrides.json`, `cloud_presets.py`, `aircraft_loadouts.py` (+ its two JSON files) write into the framework's `data\`; `miz_zones.py`, `miz_player_slots.py`, `airfield_frequencies.py`, `update_zone_data.cmd` take the mission folder (and its map) as an argument and write into that mission's `data\`. `kola_proj.py` becomes a projection module with the parameters per map, taken from pydcs's `dcs/terrain/<map>/projection.py` as Kola's were.
- `desanitize_dcs.py` stays at the repository root (it serves Syria too).

---

## Settings that differ by mission

John, 2026-10-06 (decision 1): a parameter individual to a mission goes with the mission's files; no mission overrides the library. (The first design, built in step 2, was a shared default plus override files merged over it; it was retired the same day, before any mission but Caucasus used it: `lib\mission_overrides.lua`, `MISSION.overrides` and the harness's `test_mission_overrides.lua` are gone.)
- **The rule:** when a setting turns out to need a different value on some mission, it leaves the shared data file completely and goes into **every** mission's own data (a file in its `data\`, listed in `MISSION.data_files`; a map fact in `mission_settings.lua`), Kola's included with Kola's value. The framework holds no value for it, so there is never a question of which one wins. Kola's harness proves the move changed nothing for Kola.
- **What stays shared:** facts about DCS and aircraft (`aircraft_profiles`, the recipes, the unit pool) and tuning every mission uses as it is. A shared fact that was simply wrong is fixed in the framework (the E-3A's runway, 2026-10-06).
- **Fails loudly:** a mission missing one of these files stops at load (`FATAL: could not load data\…`); a missing value is named by the data checks (`PlanAirTasking.checkData`).
- **Moved so far** (2026-10-06): `RADIO_CHANNELS` (was `RADIO_CALLS.channels`), `AWACS_ORBIT_DISTANCES` (was `AIR_DEFENSE.early_warning_fighter_base_km` / `early_warning_front_km`), `MISSION.map_bounds_m` (was `AIRSPACE.map_bounds_m`). Next candidates, each when Caucasus shows it needs its own: the echelon and front distances, the contested band, SAM density, CAP stations, the airborne cap.
- `CONFIG` likewise: shared in the framework's `config.lua`; the mission's identity and map facts live in `mission_settings.lua` (`MISSION.name`, `MISSION.log_tag`, `MISSION.scripts_folder`, `MISSION.repository_folder`, `MISSION.utc_offset_h`, …). A one-off survey flag (`CONFIG.SURVEY_FOOTPRINTS`) is set in `config.lua` for the one start that needs it and set back.

## Loading

Kola's `init.lua` today loads ~70 files from `Scripts\kola_f16\` in a fixed order, then runs the sequence. After the split:
1. The mission editor trigger is unchanged (`dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")`), so the `.miz` isn't touched.
2. The mission's `init.lua` loads its `mission_settings.lua`, then `Scripts\shared_mission_framework\load_framework.lua`.
3. `load_framework.lua`, in order: framework `config` → `lib\*` → framework `data\*` (shared data) → the mission's `data\*` (map, scenario, its own settings) → `gather` → `stages\*` → `consumers\*` → the data checks (`checkData`).
4. Then `run_mission.lua`: the run sequence that is in `init.lua` today, unchanged.
5. The mission tells the framework which of its data files to load (a list in `mission_settings.lua`), so a mission can't miss one silently and a missing file is named at load.

Globals don't clash between missions: only one mission runs at a time.

---

## Order of work

Each step leaves Kola working; each ends with its tests (*How the transfer is tested*). Steps 1–3 happen inside Kola's own tree, before anything moves, so a problem found then is a plain Kola change.

**Step 0. Baseline and kept test harness** (no change to Kola).
- Build `offline_test_harness\` (stubbed DCS; earlier harnesses lived in a session scratchpad and weren't kept; this one is the regression test for the whole move, so it stays).
- Record the baselines: the replayed plans (test A), the 2-hour mission-clock run (test B), and every generated data file from the Python tools (test D).
- Check the replay is repeatable: two replays of unchanged code must give the same plan. If they don't, find the cause first (table iteration order, time-based values) and pin it in the harness.

**Step 1. Kola map-neutral in place.** Move every name and fact tied to Kola out of the logic into `mission_settings.lua`: script folder, log tag, plan dump file, event log folder and header, radio calls file and start command, survey file names and mission folder, UTC offset, magnetic-variation fallback and self-test base, Red's SAM country. Behaviour unchanged. Tests A, B, C.

**Step 2. The override mechanism, in Kola's tree.** `load_framework.lua`'s merge, with Kola's `overrides\` empty; plus a test override to see the merge, the `dcs.log` line and the loud failure on a bad key (then removed). Tests A, B.

**Step 3. Kola's `init.lua` split into loading and running** (`load_framework.lua`, `run_mission.lua`, still inside `kola_f16\`). Tests A, B, C. **John flies Kola** (*Test E*); this run also flies the Kola fixes still waiting (bugs 62–71, roadmap item 7 step 15), so the checklists are read together.

**Step 4. The move.** Create `shared_mission_framework\mission_scripts\` and move the framework's files into it (plain moves; git detects renames when John commits). Kola's `init.lua` points at the framework. Copy both trees to `Saved Games\DCS\Scripts\`; in `Scripts\kola_f16\`, the files that moved are deleted by exact path, from a list John can read (no wildcard delete). Tests A, B, C. John flies Kola again (*Test E*).

**Step 5. The Python moves.** `radio_calls\` and `map_data_tools\` into the framework; the tools take the mission folder and map as arguments; `start_radio_calls.cmd` and the radio's paths updated. The radio player already corrects its line in `Export.lua` when the path changes (one DCS restart). Tests D and the radio checks in E. The repository `README.md`'s *Kola radio calls* and *Your jet's radios* sections become the framework's (the steps for John's friend change: the `Export.lua` line's path).

**Step 6. Docs.** Kola's *As built*, *DCS facts learned the hard way*, *Offline tools*, *Architecture* and *Reference* (the parts that aren't Kola's map) move here; Kola's `plan.md` keeps its status, run notes, Kola tuning and map, and points here. Kola's roadmap items that are framework work (most of them) are marked as such. The Afghanistan plan's open question 9 (*The shared library*) is answered by this file. The working rule "copy to DCS after edits" covers both trees.

**Step 7. Caucasus random tasking** on the framework (*The Caucasus mission*).

---

## Picking this up in a new session

- **Where it stands:** the *State* line at the top, then *Progress* (newest last). John flew (or is flying) the checkpoint run after step 3 (2026-10-06).
- **Reviewing John's checkpoint flight:** his event log (`missions\kola_f16_random_tasking\event_logs\`, newest) and `dcs.log` (`Saved Games\DCS\Logs\dcs.log`; it is lost on the next DCS start, so read it before he restarts). Check two lists: *Flight after step 3* below (what the migration changed), and Kola's own waiting checks, Kola `plan.md` *Next (2026-10-06, after the 00:16 run)* (bugs 62–71, roadmap item 7 step 15: answers, reports, no answer). Anything odd goes into the repository's `bugs.md` (Kola's until 2026-10-07); no fixes until after step 4 (or re-record the baselines right after one).
- **Before every change and after it:** `python replay_and_compare.py kola` and `python rerun_data_tools.py kola` from `offline_test_harness\`, and the same with `caucasus`; each must end "same as the baseline". An intended difference: check every differing line is the intended one (tally them: the differing file names and `+` / `-` lines across all runs), then remove that mission's 11 recorded runs by exact path (`baselines\<mission>\plan_seed_1` … `flying_seed_3`, never a wildcard) and `--record-baseline`. Caucasus's frozen world: `baselines\caucasus\saved_world_from_2026-10-06_2127_run.lua` (its first start); its test D runs only the mission's own tools (the shared ones are Kola's run).
- **Copying to DCS:** `cp -r <tree>/. "Saved Games/DCS/Scripts/<name>/"` then `diff -rq` the two (identical). Two trees: `shared_mission_framework\mission_scripts\` → `Scripts\shared_mission_framework\`, `missions\kola_f16_random_tasking\kola_f16\` → `Scripts\kola_f16\`.
- **Running a map tool by hand:** `python shared_mission_framework\map_data_tools\<tool>.py missions\<mission>` (the mission tools); `unit_pool.py`, `aircraft_loadouts.py`, `cloud_presets.py` take no mission. The `.cmd` files (the radio's start, `update_zone_data.cmd`) use Python 3.10 (`%LOCALAPPDATA%\Programs\Python\Python310\python.exe`) when it's there; the tools also run on the 3.7 `python` on PATH (test D does).
- **Traps:** `python` on PATH is a pyenv 3.7 shim (a batch file): `python -c "…"` gets mangled, so write a script into the session scratchpad and run that. `sed` with Windows paths and Lua's doubled backslashes fails quietly (the match count tells): use the editor or a script file. Temporary edits to Kola for a test are made with the editor and undone with it, then `git status` on `kola_f16\` and a full test run confirm it's back.

## Progress

**Step 0, test A: built 2026-10-06** (`offline_test_harness\`, in Git; its `output\` folder git-ignored).
- `stub_dcs.lua`: the DCS stand-ins (flat terrain, a straight road between any two points, a flat lat / lon projection around the saved world's first airbase, a mission clock with the timer queue, a fixed-seed random generator, every file write kept inside the output folder, `os.execute` recorded and never run).
- `replay_mission.lua`: runs a mission's real `init.lua` (its files read from the repository instead of `Saved Games\DCS\Scripts\`), hands the stages the saved `plan.world` in place of `gather.lua`, and stops once the plan is written (`run() failed: OFFLINE HARNESS: stopped after planning` in its log is the expected end).
- `replay_and_compare.py kola [--record-baseline] [--test plan|mission]`: runs both tests and compares every file each run wrote with `baselines\kola\<test>_seed_<n>\`, line for line. It never overwrites a baseline: an old one is removed by hand first. ~40 s for both.
- **Input frozen, in Git:** `baselines\kola\saved_world_from_2026-10-06_0016_run.lua`, a copy of the plan from John's 2026-10-06 00:16 run (`Saved Games\DCS\kola_last_plan.lua` is overwritten by every DCS run). The recorded runs (`baselines\*\*_seed_*\`) are git-ignored (John, 2026-10-06): re-recorded from the frozen world in under a minute.
- **Checked:** the same seed gives the same plan and log every time; the five seeds give five different missions (~330–380 log lines, Blue ~38 flights on seed 1); nothing written outside the output folder, no command run; a one-number change (`SAM_SITE_MIN_SPACING_KM` 3 → 4) made every seed differ (~42,000–52,000 plan lines), and with it put back all five matched again. ~2 s a seed.

**Step 0, test B level 1 (everything stands still): built 2026-10-06.**
- `stub_dcs_world.lua`: groups, units, static objects, airbases (from the saved world; parking free unless an aircraft on the ground or a static object is within 15 m), controllers (every order counted, none acted on), events (birth on spawn, the mission's end), the comms menu (every item kept), map drawings and texts (counted), user flags, the DCS enums. A jet's ammo comes from its pylons' weapon names in the loadout data (`AIM-120C … Active Radar AAM` → a radar-guided air-to-air missile, `… ARM …` / anti-radiation → passive radar, bombs, tanks and pods left out), so the controller sees armed jets. The wall clock is the mission clock from 1 January 2026, 08:00, so file names and dates repeat.
- `replay_mission.lua` mode `mission:<seconds>`: the whole `init.lua`, the clock run 2 hours (7,203 s), every comms menu command opened once (frags, steerpoints, *Airfield info*: 49 on seed 1), then the mission's end event. Writes also the event log and radio calls file (in `redirected\`), `menu_items.txt`, `drawings.txt`, `orders.txt`. ~9 s a seed; seeds 1–3.
- **What it runs (seed 1):** 25 flights spawned and watched, 16 `wait`, 1 `cancel`, loadouts logged, the radar picture every round, 116 ground groups put to sleep, every map drawing, 62 menu items; event log 696 lines. **What it can't run:** anything in the air (no takeoffs, no contacts, no player): the radio calls file stays empty. That is level 2.
- **Checked:** two runs identical in every file; a runtime-only change (`EVENT_LOG.position_every_s` 60 → 61) passed test A unseen and made all three mission runs differ in the event log; put back, all 8 runs matched.

**Step 0, test B level 2 (simple flying): items 1–2 built 2026-10-06** (takeoff, routes, waypoints, orbits, landing).
- `simple_flight_model.lua`, mode `flying:<seconds>`: a ramp spawn taxis 3 min after spawning and takes off 2 min later (a runway start 1 min); the lead flies each leg straight at the waypoint's speed, the altitude moving evenly to the next waypoint's, wingmen trailing 600 m; on arrival a waypoint's script commands run (the mission's own `WAYPOINT` / controller / watcher calls) and an Orbit is flown as a race-track until its stop time; at the Land waypoint every jet lands; fuel falls from full to empty over 4 h in the air. Takeoff and landing events fire per jet.
- **What it runs (seed 1, 2 h):** 58 takeoffs, 44 landings, 312 waypoints; the controller's in-air decisions (`go cold` 18, `handover` 12, `land` 12, `retry` 10, `come back` 7, `launch late` / `early` 3 each); 97 `RADIO_CALL`s (airborne, pushing, on station, off target, check-out, Darkstar's RTB and landing orders, the pilots' reports and Darkstar's copy); `RADAR_WARNING` at SEAD launch and press-on points; bases waking and sleeping. The same run twice: identical in every file.

**Step 0, test B level 2, items 3–5 built 2026-10-06** (radar, a stand-in player, orders followed); `replay_and_compare.py` runs it as test `flying` (seeds 1–3, ~20 s each; all 11 runs of the three tests match their baselines).
- `simple_sensors.lua`: a group's radar sees every enemy aircraft in the air within reach (a ground unit its `UNIT_POOL` `detection_m`, an AWACS type 350 km, any other aircraft 100 km), type and range known; a jet's RWR holds every enemy ground radar whose detection range reaches it. No terrain, jamming or look-down.
- `stand_in_player.lua`: at T+60 s a Blue F-16C with a player ("Harness Pilot") in the slot group of the Blue slot base nearest an enemy airbase (seed 1: `f16_rovaniemi`), circling it 30 km out at 6,000 m; never fires or lands.
- `simple_flight_model.lua`, orders: a new mission (`setTask`, a route: sent home, a landing order) replaces the route; an `AttackGroup` pushed on top (the bandit call's `ControlledTask`) turns the flight at the target's lead at 300 m/s until its time is up, its user flag is set or the target is gone, then back to the route. A landing order to one jet moves the whole flight.
- **What it runs (seed 1, 2 h):** 173 contacts; 14 scrambles, 67 `no scramble`, leash home / stand down, 6 `defend`, 2 `leave`, `back on mission` / `way home`, 17 `press on`, 18 `go cold`, 12 `handover`; 156 `RADIO_CALL`s, among them Darkstar's engage, resume, RTB and scramble vectors, 19 pilots' answers (5 `no answer`), reports and copies, airfield taxi / departing / inbound / clear at Rovaniemi; 61 `PICTURE_CALL`s to the player, threat calls; 212 lines in the radio calls file.
- **Still never run:** anything that needs a weapon fired, a hit or a death (Fox, Magnum, splash, jet down, `salvo over`, `TARGET`, kills in the event log, `IMPACT`), a `final` call (approach geometry), the radar `TRACKING` test aid, orphaned wingmen (flights move as one).

**Step 0, test B level 2, item 6 (line coverage): built 2026-10-06.** `measure_coverage.lua`; `replay_mission.lua … coverage` writes `coverage.txt` (code lines run per file, an estimate: Lua 5.1 can't list a file's active lines). Slow (a few minutes for a 2-hour flying run), so never part of the comparison; run it when wanting to know what the harness reaches.
- **Seed 1, flying, 2 h:** the logic files (`init`, `gather`, `lib`, `stages`, `consumers`) **83 %** of their code lines (7,933 of 9,580); every data file loaded but `aircraft_pylons.lua` (offline only, as meant). Most consumers 75–100 %.
- **Low, and why** (these parts are checked only by John's flights): `gather.lua` 1 % and `lib/weather.lua` 22 % (the harness hands over a saved world instead of reading DCS); `track_weapon_impacts.lua` 14 %, `write_event_log.lua` 65 %, `schedule_air_tasking_orders.lua` 64 % (shots, hits, kills, losses, target progress); `give_orders.lua` 55 % (per-jet landing orders, orphans); `lib/logger.lua` 33 % (the one-off dump functions); `survey\*` 0 % (not part of a mission run).

**Step 0, test C (the load list): built 2026-10-06.** Every replay writes `loaded_files.txt`: each file the mission loads, in order, as it named it (`Scripts\kola_f16\lib\util.lua`), then every `.lua` file in the scripts folder never loaded; a file loaded twice fails the run (`OFFLINE HARNESS: loaded twice`). Compared in all three tests. Kola today: 79 files loaded; never loaded: `data\aircraft_pylons.lua` (offline only) and the three `survey\` scripts. Checked: a second `load("data\\airspace.lua")` added to `init.lua` failed all five plan runs naming the file; taken out, all 11 runs matched.

**Step 0, test D (the Python data tools): built 2026-10-06.** `rerun_data_tools.py kola [--record-baseline]` copies `kola_data_tools\` and the data files the tools read (`clusters`, `unit_pool`, `aircraft_pylons`) into `output\kola\data_tools\latest\`, laid out as the mission folder, and runs there, in order: `unit_pool.py`, `aircraft_loadouts.py`, `cloud_presets.py`, `airfield_frequencies.py`, `miz_player_slots.py` (on `Saved Games\DCS\Missions\kola_f16_random_tasking.miz`), `miz_zones.py` (on `khola_ground_zones.miz` and `Saved Games\DCS\kola_zone_terrain.lua`). The seven data files they write and everything they print are compared with `baselines\kola\data_tools\` (git-ignored); each data file also with Kola's committed one, as information. Today all seven are the same as the committed files, and a second run is the same as the baseline. The tools never write into the repository here (`aircraft_loadouts.py` has no `--out`, so the copy is what keeps Kola's data safe). Inputs outside the repository (the `.miz` files, the zone survey, the DCS install, the pydcs and Liberation checkouts): if one of them changes, re-record.

**Step 0 done.** Before step 1, all baselines recorded on Kola as it is (2026-10-06, after the 00:16 run's fixes): `replay_and_compare.py kola` all 11 runs the same, `rerun_data_tools.py kola` every output the same. A Kola bug fix from here on means re-recording the baselines right after it (John holds fixes during steps 1–4, or says when one goes in).

**Step 1 done 2026-10-06: Kola map-neutral in place.** New `kola_f16\mission_settings.lua` (global `MISSION`), loaded first by `init.lua`: `name`, `display_name`, `log_tag`, `plan_dump_file`, `airbase_footprints_survey_file`, `event_log_folder`, `event_log_fallback_folder`, `utc_offset_h`, `fallback_magnetic_variation`, `magnetic_variation_check_airbase`, `sam_site_country`. Read instead of the old literals by `init.lua` (the banner, load errors, the plan dump, Red's SAM country), `lib/logger.lua` (the tag), `lib/weather.lua` (UTC), `consumers/brief_air_tasking.lua` (start text), `territory.lua` (summary), `write_event_log.lua` (header, folders), `call_air_picture.lua` (fallback table, self-test), `survey/survey_airbase_footprints.lua`; taken out of `config.lua` (`PLAN_DUMP_FILE`, `UTC_OFFSET_H`), `data/event_log.lua` (`folder`, `fallback_folder`), `data/air_picture_calls.lua` (`fallback_magnetic_variation`).
- **Tests, in three batches:** batch 1 (name, display name, tag) changed exactly two things in all 11 runs, both intended: `mission_settings.lua` loaded first, and `dcs.log`'s banner now "Kola F-16 random tasking loading" (was "Kola F-16 generator loading"); re-recorded. Batch 2 (plan dump, footprint survey, UTC, event log folders) and batch 3 (magnetic variation, SAM country): all 11 runs identical. Test D unchanged.
- **Harness addition:** `spawned_countries.txt` (groups and static objects spawned, by country), compared in tests B; it showed 32 ground groups spawned as Russia on seed 1 = Red's 32 SAM groups in that plan. Baselines re-recorded with it.
- **Not seen by the harness, for John's flight:** the UTC offset (only `gather` uses it: the event log header should still say UTC+3) and the footprint survey (only with `CONFIG.SURVEY_FOOTPRINTS`).
- **Left on purpose:** `init.lua`'s own `Scripts\kola_f16\` (how Kola finds its settings; `init.lua` stays Kola's entry file); `kola_data_tools/…` in three warning texts and the radio's paths and `KOLA-RADIOS` tag (step 5); the standalone zone survey (its settings will come from the zone mission's trigger: with the tools).
- Copied to `Saved Games\DCS\Scripts\kola_f16\` (identical to the repository).

**Step 2 done 2026-10-06: the override merge** (retired later the same day in step 7, John: no mission overrides the library; *Settings that differ by mission*) (rules as proposed in *Settings: shared defaults, mission overrides*, confirmed by John the same day). `kola_f16\lib\mission_overrides.lua` (`MissionOverrides.apply(folder, fileNames)`); `init.lua` runs it right after the last data file (before gather and the data checks), from `overrides\` in the mission's scripts folder, files listed by name in `MISSION.overrides` (a mission names the files it loads, so a missing one is reported, and the harness's load list shows them; Kola: `{}`). An override file is run with globals of its own (it reads the shared ones), then merged: keyed tables key by key, lists replaced whole, values replaced; an unknown global or key stops the mission (`FATAL: mission overrides: …` in `dcs.log` and on screen); every change logged (`override: AIR_CONTROL.suppression.killzone_fraction 0.85 → 0.9 (air_control.lua)`).
- **Tests:** with Kola's empty list, exactly two intended differences in all 11 runs (the new lib file loaded; `--- Mission overrides: none ---` in `dcs.log`); re-recorded. `test_mission_overrides.lua` (kept: `luae.exe test_mission_overrides.lua <mission_overrides.lua> <scratch folder\>`) checks the rules on made-up settings: 13 cases pass (merge one value, neighbours kept, logged; deep merge; lists and weighted rosters replaced whole; a plain value; unknown key and unknown global stop the load and change nothing; an override reading the shared settings; a missing listed file). In Kola, a temporary `overrides\air_control.lua` was loaded and logged in all 11 runs, and with a typo (`suppresion`) stopped every run before planning, naming it; taken out again (file and folder), all runs match the baseline.
- **Harness:** `loadfile` now reads from the repository too (as `dofile`), and files read with it are in the load list; `replay_and_compare.py` prints UTF-8 (the `→` of an override line crashed it on Windows' console encoding).
- Copied to `Saved Games\DCS\Scripts\kola_f16\` (identical to the repository).

**Step 3 done 2026-10-06: Kola's `init.lua` split into loading and running** (still all in `kola_f16\`).
- `load_framework.lua` (`LoadFramework.run()`): the framework's own file lists in load order (config, lib, the 21 shared data files, gather and the stages, the consumers), from `Scripts\<MISSION.framework_folder>\`; the mission's data files from `Scripts\<MISSION.scripts_folder>\` (`MISSION.data_files`, Kola's 9: clusters, zones, airbase codes / classes / footprints, forested airfields, player slots, coalition rosters, airfield frequencies); then the overrides; the surveys a `CONFIG` flag asks for; the data checks. A failure stops everything, named in `dcs.log` and on screen.
- `run_mission.lua` (`RunMission.start()`): the run sequence moved over line for line by script (119 lines), scheduled `CONFIG.START_DELAY` in as before.
- `init.lua`: 26 lines, Kola's entry point: loads `mission_settings.lua`, then `load_framework.lua` and `run_mission.lua` from `MISSION.framework_folder` (`kola_f16` until step 4).
- **Order changed on purpose:** shared data first, then the mission's (before, the two were interleaved). No data file reads another while loading (checked: the only mentions are in comments), so no value can differ.
- **Tests:** in all 11 runs only `loaded_files.txt` differed: the same 81 files plus `load_framework.lua` and `run_mission.lua`, the data in the new order, the same four never loaded; every plan, log, event log, radio calls file, screen text, order and spawn count byte-identical; re-recorded. A misspelled mission data file (`data\\zone.lua`) stopped the run: `FATAL: could not load data\zone.lua`. Test D and the 13 override cases pass.
- Kola's own `plan.md` *Run order (init.lua)* and *Architecture* now describe the old `init.lua`; they move here in step 6.
- Copied to `Saved Games\DCS\Scripts\kola_f16\` (identical to the repository).

### Flight after step 3 (John's checkpoint)

What steps 1–3 changed, and what the harness can't see. Fly Kola as usual (a long run with a player tasking is best: it also flies the Kola fixes still waiting, Kola `plan.md` *Next (2026-10-06)*). No DCS restart needed for these steps.
- **`dcs.log` (grep `[KOLA]`):** `Kola F-16 random tasking loading`; `--- Mission overrides: none`; no `FATAL` or `SCRIPT LOAD ERROR`; `Build summary:` (proves `gather` read the real world, which the harness never runs); `Plan written to …kola_last_plan.lua`; `air picture: magvar +…° at Rovaniemi` (the self-test now reads its airbase from `MISSION`); `Init complete.`
- **Screen at start:** `KOLA — <date>, mission start …`.
- **Event log:** a new file in `missions\kola_f16_random_tasking\event_logs\`; its first line `Kola F-16 random tasking: event log` and `(UTC+3)` in the second (the UTC offset, read only by `gather`).
- **HSD:** the Red medium / long-range SAM rings still show (they spawn as Russia through `MISSION.sam_site_country`).
- **What the harness never runs** (shots and kills): `SHOT`, `HIT` (with `life now`), `DESTROYED`, `IMPACT`, `TARGET` lines in the event log; a Fox, Magnum or splash call heard on the radio.
- **The radio:** the player and helper start, Darkstar talks, calls are heard when tuned.
- **Afterwards:** the event log and `dcs.log` to Claude; anything odd goes in Kola's `bugs.md` (no fixes until after step 4, or the baselines are re-recorded right after one).

**Checkpoint flight after step 3: passed** (2026-10-06 17:47, ~34 min, John in `f16_ivalo` on MSN2024_SEAD; `event_logs\2026-10-06_174721.log`; the `dcs.log` copied to the session scratchpad as `dcs_2026-10-06_1747.log`).
- **Every migration check passed:** `dcs.log`: `Kola F-16 random tasking loading`, the scripts folder, `Mission overrides: none`, no `FATAL` or load error, `Plan written to …kola_last_plan.lua`, `air picture: magvar +12.4° at Rovaniemi (approximate table: +11.9°)`, `Build summary:`, `Init complete.`; event log header `Kola F-16 random tasking: event log`, `(UTC+3)`; `KOLA-RADIOS` export script reading the jet's radios.
- **What the harness never runs, seen working:** 19 `SHOT`, 32 `HIT` (with `life now 91 %`), 18 `IMPACT` (hits on the ground with what was there, missiles gone in the air), 7 `DESTROYED`, an ejection and crash; radio calls Magnum, rifle, defending, jet down (heard on VHF 140.000), Darkstar's engage and resume, the pilots' answers (`… (1 s after the order)`), a report and Darkstar's acknowledge.
- **The 18 Lua tracebacks in `dcs.log`** are all DCS's own AWACS voice ("Callname -1 not found for MSN2001_AEW_1"), known since the 19:29 run (the E-3A spawns with no DCS callsign); nothing from Kola's code errored.
- Not checked by John: the HSD rings (he didn't say); the spawn count by country passed in the harness.

**Step 4 done 2026-10-06: the move.**
- **Harness first** (before anything moved, all 11 runs and test D unchanged): `replay_mission.lua` takes any number of extra `<name>=<folder>` scripts folders after the output folder; `replay_and_compare.py` passes `shared_mission_framework=<repository>\shared_mission_framework\mission_scripts\` once that folder exists; the never-loaded listing and the coverage look in every folder (a heading, or a name prefix, each once there are several). `rerun_data_tools.py` copies and compares each data file from where it is committed: the mission's `data\` if it has it, else the framework's.
- **Moved** (75 files; `git mv`, plain `mv` for the three not yet in Git: `lib\mission_overrides.lua`, `load_framework.lua`, `run_mission.lua`) into `shared_mission_framework\mission_scripts\`: `config`, `gather`, `load_framework`, `run_mission`, all of `lib\`, `stages\`, `consumers\`, the 21 shared data files and `aircraft_pylons.lua`, the footprint survey and the parked-aircraft probe. **Stay in `kola_f16\`** (12): `init.lua`, `mission_settings.lua` (`framework_folder = "shared_mission_framework"`), the 9 map and scenario data files, and `survey\survey_zone_terrain.lua` until step 5 (`khola_ground_zones.miz`'s trigger loads it from `Scripts\kola_f16\survey\`, and it runs `kola_data_tools\update_zone_data.cmd`).
- **Comments only:** `config.lua`'s header, two `(init.lua)` order notes now `(run_mission.lua)`, `load_framework.lua`'s folder note; the footprint survey's "copy to" line names `MISSION.scripts_folder`'s `data\`.
- **Until step 5 (John, 2026-10-06):** `unit_pool.py`, `aircraft_loadouts.py` and `cloud_presets.py` still write into `kola_f16\data\`, where those files no longer are; they aren't run until step 5 gives the tools their arguments (John: next run on Caucasus). The other tools write Kola's own data as before.
- **Tests:** in all 11 runs only `loaded_files.txt` differed: the same 83 files in the same order, Kola's 11 from `Scripts\kola_f16\`, the other 72 from `Scripts\shared_mission_framework\`, the same four never loaded (`survey_zone_terrain` in Kola's folder; `aircraft_pylons`, the probe and the footprint survey in the framework's); checked by script over every run. Re-recorded; test D and the 13 override cases pass.
- **Copied to DCS:** `Scripts\shared_mission_framework\` (identical to the repository) and `Scripts\kola_f16\`; the 75 old copies in `Scripts\kola_f16\` deleted by exact path (the list shown to John first), then its emptied `lib`, `stages`, `consumers\control_air_flights`, `consumers` folders.

### Flight after step 4 (John's)

The same checks as after step 3 (*Flight after step 3*), plus what the move changed. No DCS restart needed.
- **`dcs.log`:** `Kola F-16 random tasking loading`, then the scripts folder line `…Scripts\kola_f16\`; no `FATAL` or `SCRIPT LOAD ERROR` (a file the framework couldn't find would be named there); `Mission overrides: none`; `Build summary:`; `Plan written to …kola_last_plan.lua`; `air picture: magvar …at Rovaniemi`; `Init complete.`
- **Everything else as any Kola run:** the start text, the map drawings, the comms menu, the event log (new file, header), Darkstar and the radio, the AI flying, shots and kills logged.

**Flight after step 4: passed** (2026-10-06 18:53, ~8 min, AI only, no player; `event_logs\2026-10-06_185348.log`). `dcs.log`: `Kola F-16 random tasking loading`, `…Scripts\kola_f16\`, `Mission overrides: none`, `Plan written to …kola_last_plan.lua`, `air picture: magvar +12.4° at Rovaniemi`, `Build summary:`, `Init complete.`; no `FATAL`, load error, `[ERROR]` or Lua traceback (not even DCS's AWACS callsign one this time). Event log: header and `(UTC+3)` as before; 12 flights spawned, 7 takeoffs, `CONTROL`, `CONTACT`, `PICTURE`, `RADIO_CALL` (airborne), `LOADOUT`, `WAYPOINT`, positions; the mission-end summary written. Too short for shots or kills; those code paths didn't change in the move (same files, only their folder), and the step 3 flight saw them working.

**Step 5 done 2026-10-06: the Python moves** (as proposed, confirmed by John the same day: the tools read a mission's facts from its `mission_settings.lua`; `COCKPIT-RADIOS`, "Radio player", "Radio helper"; a Kola loader file for the zone survey, so no `.miz` changes).
- **Moved** (`git mv`): Kola's `radio_calls\` (16 files) → `shared_mission_framework\radio_calls\`; `kola_data_tools\` → `shared_mission_framework\map_data_tools\` (11 files; `kola_proj.py` → `map_projection.py`); `kola_airbases.json` → `missions\kola_f16_random_tasking\map_data_sources\`; `kola_f16\survey\survey_zone_terrain.lua` → `mission_scripts\survey\`. The radio's run files (git-ignored: `mission_calls.jsonl`, two logs) and both `__pycache__\` deleted by exact path; `.gitignore` names the new radio folder.
- **The radio:** `RADIO_CALLS.calls_file` and `start_command` (shared `data\radio_calls.lua`) point into `shared_mission_framework\radio_calls\`; `dcs.log` tag `KOLA-RADIOS` → `COCKPIT-RADIOS`; window titles "Radio player", "Radio helper"; the `Export.lua` line's comment "mission radio calls". The player rewrites the old line's path by itself on its first start (tried on a copy of John's `Export.lua`: only that line changed, SRS's untouched, a second start changes nothing); DCS loads it from the next start.
- **The tools:** `mission_folder.py` (new) finds a mission's `mission_settings.lua` (the one `<scripts folder>\mission_settings.lua` in the mission folder) and reads `MISSION` with `dcslua.py`. `airfield_frequencies.py`, `miz_player_slots.py`, `miz_zones.py` take the mission folder as their first argument and write its `data\`; `unit_pool.py`, `aircraft_loadouts.py`, `cloud_presets.py` take none and write the framework's `mission_scripts\data\`. `map_projection.py`: `for_map("Kola")`, parameters per map in `MAPS` (Kola only; an unknown map stops the tool naming the known ones). `miz_zones.py --saved-games` for `DCS.openbeta`. New in Kola's `MISSION`: `map`, `repository_folder`, `flyable_mission_file`, `zone_drawing_mission_file`, `zone_terrain_survey_file`, `zone_update_log_file`, `airbase_reference_file`.
- **The zone survey:** the framework's reads its names from `MISSION`; Kola's `survey\survey_zone_terrain.lua` (same path, so `khola_ground_zones.miz` is unchanged) loads Kola's `mission_settings.lua`, then the framework's survey. `update_zone_data.cmd "<mission folder>" "<Saved Games\DCS>" <scripts folder> <log file>` (212 characters from the survey, under DCS's ~260 limit; built and checked with `luae.exe`).
- **Text:** `kola_data_tools/` → `map_data_tools/` in the generated data files' headers (comments; as the tools now write them), two `gather.lua` warnings, a `plan_air_tasking.lua` check message, comments. The README's layout, *Mission radio calls* (was *Kola radio calls*) and *Your jet's radios* (the `Export.lua` line for a friend).
- **Test D rebuilt:** `rerun_data_tools.py` copies, laid out as the repository, the framework's tools and the data they read, and Kola's `mission_settings.lua`, `map_data_sources\` and `clusters.lua`; the mission's tools run on the copied mission folder. Against the old baseline: in all seven data files only the header lines (`kola_data_tools/` → `map_data_tools/`); in what the tools print only the paths written to; plus one new line from `aircraft_loadouts.py`, `skipped (can't parse) …\CoreMods\aircraft\Mirage-F1\UnitPayloads\Mirage-F1C.lua: unexpected identifier 'Intercept'`: that file in the DCS install was rewritten 2026-10-06 18:48 (after the baseline, likely a loadout saved in the mission editor); the Mirage is in no loadout choice, the output is unchanged (15 types, 46 loadouts). Every data file the same as the committed one. Re-recorded.
- **Tests A, B, C:** the radio paths in `dcs.log`'s *Radio calls* line, `commands.txt` and `redirected_writes.txt` (mission runs), and the framework's `survey\survey_zone_terrain.lua` listed as never loaded (Kola's loader too, as before); everything else byte-identical. Re-recorded. `phrase_bank_wording.py` and `flight_phrase_wording.py` pass.
- **Copied to DCS:** both trees, identical to the repository.

### Flight after step 5 (John's)

- **Before the flight:** start DCS and Kola as usual. The radio starts from its new folder (two minimised windows, now "Radio player" and "Radio helper"); the player's window says `corrected the path in …Export.lua: restart DCS once`. That session plays every call without the radio filter. **Quit DCS and start it again once**, then fly.
- **`dcs.log`:** everything in *Flight after step 4*, plus `--- Radio calls: … C:\Users\johnk\Git\dcs\shared_mission_framework\radio_calls\mission_calls.jsonl ---` and `COCKPIT-RADIOS … sending the jet's radios` / `first reading of the jet's radios` (from the new path).
- **By ear (in a jet, a player slot):** Darkstar's picture on UHF 262.000, AI calls on VHF 140.000, only when tuned; a radio turned off silences its channel.
- **The windows:** both close by themselves after DCS quits.
- **Not flown here:** the zone survey (only when zones change; its next run is the Caucasus zones, step 7).

**Flight after step 5: passed** (2026-10-06 20:04, ~32 min, John in an F-16; `event_logs\2026-10-06_200418.log`; two short starts before it, 19:53 and 19:58, the DCS restart for the `Export.lua` line).
- **`Export.lua`:** the radio line now loads `…\shared_mission_framework\radio_calls\export_cockpit_radios.lua` ("mission radio calls"); SRS's lines as before.
- **`dcs.log`:** `COCKPIT-RADIOS … mission radio calls: sending the jet's radios to 127.0.0.1:47112` and `first reading of the jet's radios` (F-16C_50, UHF and VHF); `--- Radio calls: … C:\Users\johnk\Git\dcs\shared_mission_framework\radio_calls\mission_calls.jsonl`; the step 4 lines (loading banner, `Scripts\kola_f16\`, `Mission overrides: none`, plan written, magvar +12.4° at Rovaniemi, `Build summary:`, `Init complete.`); no `FATAL`, load error or `[ERROR]`. The 8 Lua tracebacks are all DCS's AWACS voice (`Callname -1 not found for MSN2001_AEW_1`).
- **The radio** (`shared_mission_framework\radio_calls\`: its logs and calls file written there): the helper read the new calls file and sent 34 calls; the player heard the jet's radios and played only what was tuned (Darkstar's first picture `not heard, no radio tuned to 262.000` while UHF was on 305.000; from UHF 262.000 every Darkstar and pilot call on UHF; VHF 140.000 calls on VHF), at the knob's volume (UHF turned down to 0.65, calls at 0.67); both windows closed after DCS quit (20:39).
- **Event log:** header and `(UTC+3)`; 11 flights spawned, 12 takeoffs, 13 `SHOT`, 8 `HIT`, 7 `DESTROYED`, 6 `EJECTED`, 18 `RADIO_CALL`, 16 `PICTURE_CALL`, `PLAYER_IN`, `RADAR_WARNING`, `TRACKING`; the mission-end summary (Blue 4 flights, 2 aircraft lost; Red 7 flights, 5 lost).

**Step 6 done 2026-10-06: the docs.**
- **New `development_docs\as_built.md`:** how the framework works, moved from Kola's `plan.md` under the same section names (so "plan.md, *The controller*" in Kola's docs and code comments lands there): *Architecture* (rewritten for the two folders: the relationship to Kola, Caucasus, Afghanistan and Syria; mission start; the script layout of `mission_scripts\` and a mission's scripts folder; the load order), *As built* (every stage and consumer; *Run order* now `run_mission.lua`; *Offline tools and test harness* rewritten for `map_data_tools\` and `offline_test_harness\`), *DCS facts learned the hard way*, *Performance*, *Design, not built yet*. Moved word for word otherwise (checked by script: of Kola's 1,308 lines, 1,201 carried over unchanged, 51 with only "bug n" → "Kola bug n", "roadmap item n" → "Kola roadmap item n", "`closed.md`" → "Kola's `closed.md`", and the 56 others the intended edits: paths, `MISSION.…` names for what a mission sets, the layout).
- **Kola's `plan.md`** (393 lines, was 1,308): its header (where things are now, the copy rule for both trees, the harness), *Where we are* (the split done, bug fixes can go in again, re-record the baselines after one), *Backlog*, a new *Kola's map and scenario* (its clusters, base-defense rosters and always-heavy bases, SAM systems, the Kola-core zone gap, its 8 player slots, its 127 zones and their files, its map facts), *Reference* (Kola's airbases, map, sources).
- **Kola's `roadmap.md`, `bugs.md`, `closed.md`:** a note at the top: the sections about how the code works are in `as_built.md`; the shared code's new folders; every roadmap item is framework work.
- **The Afghanistan plan's open question 9** (*The shared library*) answered, but for the controller's name and the per-coalition player features (*Later*).
- **The working rule** "copy to DCS after edits" covers both trees (Kola's `plan.md`, this file's *Working rules*).
- The README's layout (step 5) already shows the framework.
- **Decided at the end of the day (John):** the Caucasus mission is the same style as Kola, a different map (*The Caucasus mission*); started next session.

**Step 7, first part done 2026-10-06: the Caucasus mission's skeleton** (names agreed with John the same day; not copied to DCS yet).
- **Names:** `missions\caucasus_multiplayer_random_tasking\` (after John's `.miz`), scripts folder `caucasus_f16`, log tag `CAUCASUS`; John's two missions in `Saved Games\DCS\Missions\`: `caucasus_multiplayer_random_tasking.miz` (flyable; empty so far) and `caucasus_multiplayer_rt_zones.miz` (zone drawing; 91 zones, all 274 m circles, so every SAM and target kind fits).
- **New:** `caucasus_f16\init.lua`, `mission_settings.lua` (from Kola's: map `Caucasus`, UTC +4 from pydcs, magnetic-variation fallback ~+6.5 to +7° with its self-test at Kutaisi, Red SAMs as Russia, no overrides), `survey\survey_zone_terrain.lua` (the loader the zone mission's trigger runs), `data\clusters.lua` (first draft of the scenario: Georgia + NATO against Russia; always Blue Tbilisi / Soganlug / Vaziani and Batumi / Kobuleti; contested Abkhazia (Gudauta, Sukhumi, p_red 0.7), then Senaki (requires Abkhazia Red), then Kutaisi (requires Senaki Red); always Red Sochi, the Krasnodar region and the North Caucasus fields), `data\airbase_codes.lua`, `map_data_sources\caucasus_airbases.json` (21 airbases from pydcs, same names as DCS's `Radio.lua`; lat / lon within 80–320 m of the published airport points, the difference being where DCS puts its reference point); `map_projection.py` knows `Caucasus` (pydcs's parameters); `.gitignore` the Caucasus event logs.
- **Checked:** `miz_zones.py missions\caucasus_multiplayer_random_tasking --report-only` reads John's 91 zones, names them (`ZONE_SENA_216_060` …) and gives each a cluster; terrain "no terrain file" until the survey is flown. Kola's test D unchanged.
- **Zone survey flown** (John, 2026-10-06 21:06): 91 zones measured, `zones.lua` written and copied by the survey itself. All large; 66 have no road within 500 m (26 farther than 2 km), so garrisons, command posts, assembly areas and depots fit only the other 25; John will add zones later.
- **The rest of the data** (2026-10-06, copied to DCS): `airfield_frequencies.lua` (the tool: 21 fields, VHF 121–141, UHF 250–270); the mission's first override (since replaced by its `data\radio_channels.lua`, below), `overrides\radio_calls.lua` (Vaziani's tower is VHF 140.000 and Kobuleti's UHF 262.000, the shared mission and AWACS channels: moved to VHF 143.000 and UHF 272.000 for Caucasus); `airbase_classes.lua` (John OK'd: hubs Tbilisi-Lochini, Kutaisi, Mineralnye Vody; bomber Mozdok; fighters Vaziani, Krymsk, Krasnodar-Center, Maykop; heli Soganlug, Gudauta; the rest dispersal; runway lengths approximate until gather reports DCS's); `forested_airfields.lua` (none); `coalition_rosters.lua` (Kola's, copied unchanged, John: Blue = Georgia with US / NATO support); `airbase_footprints.lua` and `player_slots.lua` empty placeholders; `overrides\config.lua` turns on `CONFIG.SURVEY_FOOTPRINTS` for the first starts (load order: overrides before the surveys).
- **Flyable `.miz`** (John, 2026-10-06): 5 slots (Batumi, Kobuleti, Tbilisi-Lochini, Gudauta, Sukhumi-Babushara; CJTF Blue, STNs 00201–00205), the init trigger, airbase coalitions; `player_slots.lua` generated.
- **First start, 2026-10-06 21:27** (56 s, `event_logs\2026-10-06_212706.log`, `dcs.log` copied to the session scratchpad as `dcs_caucasus_first.log`): loaded cleanly, no `FATAL`, no Lua error; both overrides logged; footprints surveyed at all 21 fields; the roll (Abkhazia Red, Senaki and Kutaisi Blue), 201 base-defense units, SAMs Red 23 / Blue 34 (Blue at its 75 % zone cap), targets Red 23 / Blue 12, one Red convoy Sochi → Sukhumi, 55 flights (Red 33: 1 of 4 attack missions, 10 SEAD, 21 patrols, an A-50; Blue 24: 5 of 6, 10 SEAD, 7 patrols, 2 human taskings), magvar +6.6° at Kutaisi (table +6.7°: kept), plan written, `Init complete.` Footprints copied into `data\airbase_footprints.lua`, `overrides\config.lua` removed; DCS's runway lengths put in `airbase_classes.lua`.
- **Found:** **Blue has no AWACS.** No Blue field has the heavies' 2,500 m `min_runway_m` in DCS (Tbilisi-Lochini 2,345 m, Kutaisi 2,419), and no orbit meets the standoffs (`early_warning_fighter_base_km` 250, `early_warning_front_km` 120: all of Georgia is within ~180 km of a Red base). Mozdok (2,357 m) can't take the Tu-22M3 either.
- **Settings individual to a mission move into the missions' data, overrides retired** (John, 2026-10-06: no mission overrides the library; *Settings that differ by mission*). `lib\mission_overrides.lua`, `MISSION.overrides`, Caucasus's `overrides\` (the radio channels) and the harness's `test_mission_overrides.lua` deleted (and their copies in `Saved Games\DCS\Scripts`, by exact path). New in both missions' data: `radio_channels.lua` (`RADIO_CHANNELS`; Kola 262.000 / 140.000, Caucasus 272.000 / 143.000) and `awacs_orbit_distances.lua` (`AWACS_ORBIT_DISTANCES`; Kola 250 / 120 km, Caucasus 120 / 40 km); in both `mission_settings.lua`: `map_bounds_m`. The map edges were found on the way: `AIRSPACE.map_bounds_m` held DCS's `MissionGenerator\nodesMap.lua` numbers, which are the same in the Kola and Caucasus folders and leave Batumi, Kobuleti and Tbilisi outside the "map", so no Caucasus orbit could pass; Kola keeps them, Caucasus takes pydcs's bounds (x −600 to 380 km, z −560 to 1,130 km). Checks for the new globals in `PlanAirTasking.checkData`. **Kola's harness:** exactly 4 differing lines in all 11 runs (the two new data files loaded, `mission_overrides.lua` not, no `Mission overrides: none` line), every plan, event log and radio file identical; re-recorded; identical again after the map-edge move and the E-3A change; test D unchanged.
- **Shared fact fixed:** the E-3A's `min_runway_m` 2,500 → 2,300 (John: it can leave from Tbilisi-Lochini); it starts in the air, so this is where it lands. Kola: no change.
- **Caucasus classes:** Mineralnye Vody `bomber` (Tu-22M3 and A-50), Mozdok `fighter` (DCS's runway too short for a bomber). Blue has no field of 2,500 m, so no B-1B here.
- **Caucasus rolls after it** (harness, 5 seeds): Blue's E-3A now flies every roll, over western Georgia near Zugdidi from Kutaisi (42.4° N 42.0° E, seeing ~44 % of the fight) when Abkhazia is Blue, over north-east Turkey ~80 km south of Batumi from Tbilisi (40.9° N 41.0° E, 59 %) when Abkhazia, Senaki and Kutaisi are Red; Red's A-50 from Mineralnye Vody north of the mountains (42–47 %). Caucasus baselines re-recorded; all three trees copied to DCS.
- **John's first Caucasus flight** (2026-10-06 22:43, `missions\caucasus_multiplayer_random_tasking\event_logs6-10-06_224344.log`, reviewed 2026-10-07): loaded and ran with no script errors; every radio call heard on 272.000 / 143.000, the volume knobs working (Kola bug 69 closed). Found: bugs 73 and 74 (SA-10 SEAD), in the repository's one `bugs.md` (moved to the root with `closed.md` the same day, John). **Players called by their own callsign** (2026-10-07, John set a callsign on every F-16 slot): Darkstar's picture and threat calls say the jet's callsign from the mission file (`SendRadioCalls.playerCallsign`: `Unit:getCallsign()` "Python11" → "Python one one"; `RADIO_CALLS.player_callsign` when a jet has none). Harness: the start-up `Radio calls:` line the only difference (6 runs per mission), both missions re-recorded, then identical; copied to DCS. Not flown.

## How the transfer is tested

The move is only right if Kola behaves exactly as before, so most tests compare against the step 0 baseline rather than judging by eye.

**Test A. The same plan, byte for byte.** The harness stubs DCS, takes `plan.world` from saved plans (`kola_last_plan.lua` from a few recent runs: different territory rolls), seeds the random numbers the same way (seed × 7919, ~50 values discarded, as Kola's harness notes say), runs every stage and writes the plan. After each step the plans must be identical to the baseline. Any difference is a regression, or an intended change that is written down.

**Test B. The same mission, 2 hours of mission clock.** The real scheduler, controller, radar picture, scrambles, event log and radio consumers over stubbed DCS on a saved plan (Kola's `real_plan_harness.lua` did this for item 11: 23 flights launched, no errors). Compared with the baseline: no errors; the same counts per event word (`SPAWNED`, `CONTROL` by decision, `RADIO_CALL` by kind, `CONTACT`…); the same `calls_file` lines.

**Test C. Every file loaded once, from the right place.** The list of files loaded (logged by `load_framework.lua`) compared with today's `init.lua` list: none missing, none twice, none from the old folder. Every override line in `dcs.log` as expected (none for Kola).

**Test D. The Python tools give the same data.** From their new place, with Kola's folder as the argument: `miz_zones.py` (needs `Saved Games\DCS\kola_zone_terrain.lua`), `miz_player_slots.py`, `airfield_frequencies.py`, `unit_pool.py`, `cloud_presets.py`, `aircraft_loadouts.py`; each output identical to the committed file. Radio: `phrase_bank_wording.py` and `flight_phrase_wording.py` check their files; `play_sample_awacs_calls.py` plays through the player; the `Export.lua` edit tried on a copy of John's file (the old Kola line replaced, SRS's line untouched).

**Test E. John flies Kola** (after step 3, and after steps 4 and 5). In `dcs.log`: no `FATAL` / load errors; the loading lines (framework folder, mission folder, files loaded, overrides: none); `Build summary:` like a normal roll; the plan written to `kola_last_plan.lua`; the export script's `first reading of the jet's radios` (after step 5: from the framework's path, after one DCS restart). In the event log: a new file in `missions\kola_f16_random_tasking\event_logs\`, its header, `SPAWNED`, `CONTROL`, `RADIO_CALL` lines as in any run. By ear: Darkstar's picture, pilots' calls and airfield traffic heard, only when tuned. On the map: the usual drawings. Nothing else in the run should differ from a normal Kola run; anything that does is a bug of the move.

---

## The Caucasus mission (step 7)

What it needs that the framework doesn't give (the work is mostly John's map work and decisions):
- **Name and folder:** `missions\caucasus_random_tasking\` and its scripts folder name (to settle; Kola's is `kola_f16`, as the F-16 is its player aircraft).
- **Scenario:** who fights whom (Georgia and NATO against Russia from the north? Abkhazia and South Ossetia as Red ground?), clusters and the territory roll, rosters per coalition.
- **Zones:** John draws them in a Caucasus survey `.miz` (as `khola_ground_zones.miz` for Kola) and flies it once; the survey and `update_zone_data.cmd` produce the mission's `zones.lua`.
- **Airfields:** the footprint survey flown once (`CONFIG.SURVEY_FOOTPRINTS`), airbase codes, classes by runway length, forested fields, frequencies from Caucasus's `radio.lua`.
- **Player slots:** F-16C dynamic-spawn templates in the mission's `.miz`, then `miz_player_slots.py`.
- **Map facts:** projection (pydcs's Caucasus parameters), UTC offset (+4 per pydcs; to check), magnetic-variation fallback table and self-test base.
- **Tuning for a smaller map, in the missions' data** (*Settings that differ by mission*): front and echelon distances, the contested band, AWACS placement and reach, SAM density, CAP stations, the airborne cap. Decided with John on the first rolls, from the harness and a first flight.
- **The shape (John, 2026-10-06): the same style as Kola, a different map.** An F-16C random tasking: the roll of who holds which field, ground defenses, SAM networks and targets, both air wars planned for the window, players picking a human tasking from the comms menu, the radio. So the Caucasus mission is mostly data (settings, map data, scenario) on the framework as it is; new code only where the map needs it (the projection's parameters, anything Kola never met), built in the framework.
- **Starting it** (next session): settle the names; the mission folder and its `mission_settings.lua` from Kola's as a template (every `MISSION` entry: the map `Caucasus`, its files); the scenario with John (sides, clusters, rosters); the `.miz` files John makes (the flyable one with slots, the zone drawing one); then the map data as Kola's was built (*Picking this up*, *Running a map tool by hand*), the harness taught a second mission (`replay_and_compare.py`, `rerun_data_tools.py`: a `caucasus` entry), first rolls, overrides for the smaller map.
- **The sea:** the Black Sea is next to the fight; ships are not in the framework yet (Kola's *Design*: naval strike needs research).

## Later

- **Both coalitions playable** and **map data in a per-map folder:** moved to the root `roadmap.md` (items 17, 18), 2026-10-07.
- The Afghanistan campaign's own needs (saved state, ground war, logistics) are built in the framework where they're shared, in the campaign where they're not.

## Open

- ~~The Caucasus mission's folder and scripts folder names~~ (settled 2026-10-06: `caucasus_multiplayer_random_tasking`, `caucasus_f16`).
- ~~The override mechanism~~ (built in step 2, retired 2026-10-06: settings individual to a mission live in its data).
- ~~Whether the framework gets its own `roadmap.md`~~ (settled 2026-10-07, John: one `roadmap.md` at the repository's root, Kola's moved there and this plan's *Later* into it as items 17–18, each item's `**For:**` line saying which; multiplayer Darkstar added as item 19). ~~Its own `bugs.md`~~ (settled 2026-10-07, John: one `bugs.md` at the repository's root for every mission and the framework, Kola's moved there, each bug's `**For:**` line saying which; Caucasus's first flight logged as bugs 73–74).
