# Shared Mission Framework — Design

> **What this is:** how the shared mission framework is designed and how it works: the shared tools, libraries and data used to create and run custom (multiplayer) DCS missions. The Lua that plans and runs a mission inside DCS, the radio calls outside it, the Python tools that build a map's data, the data that holds on any map, and the offline test harness. Kola (`missions\kola_f16_random_tasking\`), the Caucasus random tasking (`missions\caucasus_multiplayer_random_tasking\`) and later the Afghanistan campaign (`missions\afghanistan_campaign\`) run on it; a fix or a change made once applies to every mission. Syria shares nothing.
>
> **Where else to look:** status, what's next, what to check in the next run, how to pick work up, and the history (Kola's runs, the split step by step): the repository's one **`plan.md`**, at its root. Where things are headed: **`roadmap.md`**; bugs: **`bugs.md`**; finished items and fixed bugs: **`closed.md`** (all at the root, each item saying what it is for). Each mission's own map, scenario and settings: its **`mission_design.md`** (Kola: *Kola's map and scenario*). Until 2026-10-07 this file was `development_docs\as_built.md` (and before 2026-10-06 most of it was Kola's `plan.md`), so older notes and code comments say "plan.md, *The controller*" or "as_built.md": the section names are the same here.
>
> **Kola was the first mission on it,** so examples, numbers and run notes come from Kola runs. Bug and roadmap numbers are the repository's ("Kola bug 41": found in Kola). The numbers in shared settings hold for every mission; a setting individual to a mission lives only in each mission's own data, never as an override of the library (*Settings that differ by mission*).
>
> **Paths:** Lua files (`watch\…`, `record\…`, `execute\…`, `inform\…`, `logs\…`, `planner\…`, `controller\…`, `tools\…`, `data\…`) are in `shared_mission_framework\mission_scripts\`, except a mission's own data files (`data/clusters.lua`, `data/zones.lua`, `data/player_slots.lua`, `data/coalition_rosters.lua`, `data/airbase_*.lua`, `data/forested_airfields.lua`, `data/airfield_frequencies.lua`, `data/radio_channels.lua`, `data/awacs_orbit_distances.lua`: `MISSION.data_files`, in the mission's scripts folder). `radio_calls/`, `map_data_tools/` and `offline_test_harness/` are in `shared_mission_framework\`.
>
> **Since 2026-10-10 the scripts are in role folders** (*Roles and actors*). Older notes, `bugs.md`, `closed.md` and run notes name the files as they were then (`consumers\…`, `stages\…`, `lib\…`, `gather.lua`): *Where the old files went* maps each to its new place.
>
> **In this file:** *Direction* → *Decided* → *What the code showed* → *Layout* → *Settings that differ by mission* → *Loading* → *Architecture* (*Roles and actors*, *Where the old files went*, *Script layout*) → *As built* (the planner's stages, then the rest of the run, the tools, *DCS facts learned the hard way*, *Performance*) → *Reading a run* (what to grep) → *How the transfer is tested* (the offline test harness) → *Design, not built yet*.

---

## Direction

**Naming rule:** name things by what they are or what they do, in full words, folders included. No abbreviations in code names: `mobile_anti_aircraft_guns`, not `aaa_sp`; `shoulder_launched_missile_teams`, not `manpads_team`. Each name answers one question. Prose may still use common terms (AAA, SHORAD, MANPADS).

**Air denial** (since Kola's session 8, 2026-09-26). The air war was redesigned from air superiority to air denial, like Ukraine:
- jets stay under their own SAM umbrella;
- ground attack works the front;
- losses should be rare and meaningful;
- standoff weapons are coming.

Flight structures, weapons, tactics and strategy change step by step, with the details decided with John as they come up. Rules are judged by what real forces would do.

---

## Decided (John, 2026-10-06, when the framework was split out of Kola)

1. **No duplicated code.** Every piece of logic lives in one place, the framework, so a change or bug fix reaches every mission. **A setting that is individual to a mission lives only with that mission's files, never as an override of the library** (John, 2026-10-06, replacing the first design's shared default + mission override: "we don't want each custom mission overriding stuff from the library, that gets messy"; *Settings that differ by mission*).
2. **Map data stays with the mission** for now (zones, airbases, slots, frequencies…). It moves to a per-map folder only if two missions ever share a map.
3. **The name:** `shared_mission_framework`. Inside it, the folders say what they hold (*Layout*).
4. **Docs** (John, 2026-10-07): **one `plan.md`, `roadmap.md`, `bugs.md` (and `closed.md`) at the repository's root** for every mission and the framework, the one place to look for development (each roadmap item and bug saying which it is for); **this `framework_design.md`** for how the framework is designed and works (until 2026-10-07 `development_docs\as_built.md` and the design parts of the framework's own `plan.md`); **a `mission_design.md` in each mission's folder** for that mission's own design (its map, scenario and settings). Code comments that cite a Kola bug number say so: "Kola bug 41".
5. **When:** the whole rework plan first (the framework's plan, now the root `plan.md`'s *History*), then the steps; John flies Kola after the first few (steps 1–3), before anything is moved into the framework.

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
  framework_design.md                 this file: how the framework is designed and how it works
  mission_scripts\                    the Lua that runs inside DCS; copied to Saved Games\DCS\Scripts\shared_mission_framework\
    load_framework.lua                loads the framework, then the mission's data, in order (new)
    run_mission.lua                   the run sequence, today in Kola's init.lua (moved)
    data\                             shared data and shared defaults (below), config.lua (CONFIG) included
    tools\  logs\  record\  watch\  execute\  inform\           the roles (*Roles and actors*)
    planner\  controller\             the actors (commander\ when a mission has one)
    survey\                           the in-DCS surveys (zone terrain, airbase footprints, parked-aircraft probe)
  radio_calls\                        the radio player, helper, phrase banks, voices, radio sound, export script
  map_data_tools\                     the Python that builds data from DCS and a map (was kola_data_tools\)
  map_surveys\                        the Lua run by survey missions of a map's own (since 2026-10-07: the
                                      terrain probe, the spawn site survey, its viewer); copied to
                                      Saved Games\DCS\Scripts\map_surveys\, beside this PC's local_paths.lua
  map_data\<map>\                     a map's data for any mission on it (since 2026-10-08, Afghanistan's): survey_area.lua
                                      (the whole-map survey's rectangle, four GPS corners), spawn_sites_index.lua (the
                                      sites' index: rules, counts, tiles) and spawn_sites\tile_*.lua (the sites,
                                      one file per 100 km tile; a mission loads only the tiles it needs), written
                                      by find_spawn_sites.py; survey_measurements\<run>\ (the raw tiles,
                                      git-ignored; John backs them up)
  offline_test_harness\               stubbed DCS + replay tests, kept this time (*How the transfer is tested*)

missions\kola_f16_random_tasking\
  kola_f16\                           the mission's own scripts; copied to Saved Games\DCS\Scripts\kola_f16\
    init.lua                          names the mission and its folders, then hands over to load_framework.lua
    mission_settings.lua              identity and map facts: name, log tag, folders, UTC offset, magnetic variation, map edges
    data\                             map data, scenario data, and the settings each mission has its own values for (below)
  map_data_sources\                   kola_airbases.json and other inputs the map tools read for this map
  kola_f16_random_tasking.miz, mission_design.md, event_logs\

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
3. `load_framework.lua`, in order: `data\config.lua` → the framework's `data\*` (shared data) → the mission's `data\*` (map, scenario, its own settings) → `tools\` → `logs\` → `record\` → `watch\` → `execute\` → `planner\` → `controller\` → `inform\` → the data checks (`checkData`).
4. Then `run_mission.lua`: the run sequence that is in `init.lua` today, unchanged.
5. The mission tells the framework which of its data files to load (a list in `mission_settings.lua`), so a mission can't miss one silently and a missing file is named at load.

Globals don't clash between missions: only one mission runs at a time.

---

## Architecture

**Relationship to other code.** Every mission on the framework (Kola, the Caucasus random tasking, later the Afghanistan campaign) runs the same Lua, radio and tools; a fix made once reaches each. A mission holds only what is its own: its settings and map facts (`mission_settings.lua`, `MISSION`), its map and scenario data, and the settings each mission has its own values for (radio channels, AWACS orbit distances; *Settings that differ by mission*). The Syria mission is completely separate: no shared code, so it keeps working exactly as it does.

**The plan is one table.** The planner's stages build one accumulating plain-data Lua table; each stage reads earlier keys and adds its own.
- **Nothing spawns until planning is done**, so later stages (air tasking, brief) see the complete picture.
- **Stages may ask the terrain, never the live sim:** `land.getSurfaceType`, `land.getClosestPointOnRoads` and heights are fine during planning; reading DCS objects happens only in `watch\` (`watch\world_at_start.lua` before planning), creating them only in `execute\`.
- **Plain data only:** no DCS handles or functions. So the plan dumps to `Saved Games\DCS\<MISSION.plan_dump_file>` (Kola: `kola_last_plan.lua`) and can be replayed offline.
- **Complete entries:** each entry carries everything its spawner or reader needs (unit types, positions, headings, routes).
- **Immutable once built:** everything after the planner reads the plan and never writes to it.
- **Runtime state lives elsewhere:** what launched, what's dead, cooldowns, keyed by the same ids as the plan.

**From mission start to a finished plan:**
1. The mission editor trigger runs the mission's `init.lua`: its `mission_settings.lua`, then the framework's `load_framework.lua` loads everything (*Run order*).
2. Wait a few seconds (airbase queries return empty at T+0).
3. Read the world at start into `plan.world` (`watch\world_at_start.lua`).
4. Run the planner's stages back to back.
5. Dump the plan.
6. Spawn, draw, and start Watch, the controller and Inform (*Run order*).

**Execute and Inform own the DCS formats.** The `coalition.addGroup` tables, waypoint and task tables (Execute), `outText` strings, menus and map marks (Inform) are built from plan entries when used and thrown away. Going from an entry to an `addGroup` table is a translation, not a decision. One spawner per kind of DCS object (John), made flexible with optional entry fields, never a spawner per feature: `ExecuteSpawnStaticObjects`, `ExecuteSpawnGroundGroups` (optional `route`), `ExecuteSpawnAircraftGroups`.

### Roles and actors (John, 2026-10-09)

**Decided 2026-10-09** (worked out with John over the day, checked against four features traced function by function; **the deciders became actors the same evening**, John: `commander\evaluate_defenses` reads as what it is, `decide\commander\evaluate_defenses` backward). **The code moved to this layout on 2026-10-10**, in one set of work (*Where the old files went* below).

**Two kinds of top-level folder:**
- **Roles, named by verbs: the services** every part of the mission uses (`watch\`, `record\`, `execute\`, `inform\`, `logs\`, plus `data\` and `tools\`). Each is an API: a set of modules whose functions the actors call or which listen to the Record.
- **Actors, named by nouns: the deciders** (`commander\`, `planner\`, `controller\`): every decision about the war, and nothing else. They are the services' clients: they read the Record, ask Tools and Data, write their decisions to the Record, and call Execute.

A path reads as a sentence: the folder says what it does or who it is, the file says the subject or the act.
```
watch\radar_picture.lua                      -- watch the radar picture
record\flights.lua                           -- the record of flights
execute\spawn_aircraft_groups.lua            -- execute: spawn aircraft groups
commander\evaluate_defenses.lua              -- the commander evaluates defenses
planner\plan_air_tasking.lua                 -- the planner plans air tasking
controller\air_flights\scramble_fighters.lua -- the controller's air flights: scramble fighters
```
In a role folder, files are named by **subject** (`watch\radar_picture.lua`), except `execute\`, where the verb is the DCS operation itself (`execute\spawn_aircraft_groups.lua`). In an actor folder, files are named by **what the actor does** (`plan_sam_sites.lua`, `scramble_fighters.lua`); a subfolder groups one subject (`controller\air_flights\`, later `controller\ground_companies\`). An actor folder has no `decide\` inside: deciding is all it does.

**The roles:**

| Role (folder) | What it is for | It produces | It reads | It never |
|---|---|---|---|---|
| **Watch** (`watch\`) | the only place live DCS is read | **facts**: what is true now, and facts worked out from them ("contact inbound on Ivalo in 9 min", "inbound for 8 rounds", "company C stuck"), written to the Record | DCS, the Record | chooses, changes the sim, tells anyone |
| **Record** (`record\`) | the mission's one record of what is known and what has been decided: everything one part needs from another lives here | **entries**, each with exactly one writer, readable by all; publishes each change to whoever subscribed | | decides anything (it holds) |
| **Execute** (`execute\`) | the only place the sim is changed | **DCS calls**: spawn, `setTask` / `pushTask`, remove, a base's coalition, AI on / off; and **the result** of each order, written to `record\orders.lua` and returned to the actor (carried out, or failed and why; what DCS gave back: group id, unit types) | the decision it is handed by an actor, already in the Record, carrying every id and position the order needs | chooses: it acts the moment it is called, and the same decision always gives the same calls; looks up anything but the object it acts on |
| **Inform** (`inform\`) | the players, during the game | **what they see and hear**: screen text, radio calls, F10 map marks, comms menus, briefs | the Record, Data, Tools | changes the war; its choices are only how to tell (order, wording, when a call is worth making) |
| **Logs** (`logs\`) | us, after the game | **log files**: the event log (its event words unchanged: `CONTROL`, `CONTACT`, `RADIO_CALL` …), `dcs.log` | the Record (decisions, order results); and what anyone hands it: `Log` and `EventLog.add` may be called from anywhere for a fact line | feeds anything back |
| **Data** (`data\`) | everything fixed before the mission starts | **plain tables**, no code: settings, recipes, rosters, DCS facts, generated tables | | contains logic (the Record is its live counterpart) |
| **Tools** (`tools\`) | accessories for building and describing: not a step of the mission's flow, asked by anyone | **answers** to a question from its arguments ("how far does this SAM reach at 300 m?", "how does company C drive A → B?", "the next free callsign", "the magnetic bearing as the F-16 shows it") | its arguments, Data, the terrain | keeps state, changes the sim |

**The actors** (the command layers of the Afghanistan design, `missions\afghanistan_campaign\mission_design.md`, *Command layers*; each can be run by rules or, later, a language model):

| Actor (folder) | What it decides | It writes to the Record | It reads |
|---|---|---|---|
| **Commander** (`commander\`) | strategy, the JFC: objectives and their priority, how the air effort is split, what to defend, where the ground forces push, risk, where supply goes | **directives** | the Record (its own coalition's picture, never the truth), Data, Tools |
| **Planner** (`planner\`) | plans from the directives: the mission plan at start (territory, base defences, SAM sites, targets, convoys, the airspace, the air tasking orders); later the ground task forces' plans and the logistics flights and convoys | **the plan, air tasking orders** | the Record (directives), Data, Tools |
| **Controller** (`controller\`) | real time, the MOC: launches, scrambles, the bandit call, go cold, the leash, retries; sleeping ground units; later the ground companies' moves | **decisions** (with their reason) and **ledgers** (callsigns given out, jets committed, spots held) | the Record (the plan, the orders, Watch's facts), Data, Tools; **calls Execute** |

Kola and Caucasus have no commander: their priorities come from Data. An actor never reads DCS, changes it except through Execute, or tells the players anything; **an actor folder that grows its own `watch\` or `execute\` is the design breaking** (that was `control_air_flights\`).

**How it flows:**
```
DCS ──► WATCH ──► RECORD ◄──► COMMANDER ─► PLANNER ─► CONTROLLER   (each through the Record)
                    │                                    │
                    │                                    └──► EXECUTE ──► DCS
                    ├──► INFORM ──► the players (screen, radio, map, menus)
                    └──► LOGS ──► the event log, dcs.log
        DATA and TOOLS: read and asked by anyone
```

**The rules:**
1. **One way through.** DCS → Watch → Record → actors → Record → Execute → DCS. Inform and Logs listen to the Record; nothing reads from Inform or Logs.
2. **Everything one part needs from another is in the Record**, and **each entry has exactly one writer**: Watch writes facts, each actor its own decisions and ledgers. A part may keep private working state nobody else needs (the stuck detector's last few positions, which radio phrases were used lately).
3. **Record first, then Execute, then the result** (John, 2026-10-09: the controller runs Execute, reads the Record, and its decisions are logged and recorded; Execute reports back). In order:
   1. the actor writes its decision to the Record; Logs writes its CONTROL line;
   2. the actor calls Execute directly with it;
   3. Execute writes the result to `record\orders.lua` (carried out, or failed and why, plus what DCS gave back) and returns it; the actor updates its own state from it (a flight is "going home" only once the order was given);
   4. **Inform listens to the results, not the decisions:** Darkstar says an order only once it was given, never one that failed; Logs writes a line only for a failure.
   So the code reads as what happens next, every decision is in the Record (logged, saved, replayable whoever made it), and Execute never subscribes to anything.
4. **Actors talk to each other only through the Record:** commander → `record\directives.lua` → planner → `record\plan.lua`, `record\air_tasking_orders.lua` → controller. So any one layer can be run by rules or by a language model without the others knowing.
5. **If nothing is chosen, it's Watch.** Facts worked out from other facts, even counted over time ("inbound for 8 rounds", "hot for 2 checks"), are Watch's; the threshold that acts on them is an actor's.
6. **The actors own timing:** "launch in 85 s", and the look again before acting ("is the raid still there?"), are decisions. Execute acts at once.
7. **The mission plan is the Record's first entry:** what Watch read at start (`plan.world`) and the decisions the planner made at start (territory, defences, SAM sites, targets, the air tasking orders), never changed afterwards.
8. **What a player chooses is a fact.** Inform builds the comms menus; a player's choice (take a tasking, go on alert: roadmap item 14) is something Watch records, and an actor acts on it.
9. **Inform's choices are about telling, not the war:** which contact first, which words, whether a threat is worth a call now. A choice that changes what happens in the war is an actor's.
10. **Questions about the fixed world are allowed everywhere:** the terrain (`land.getHeight`, `getSurfaceType`, `getClosestPointOnRoads`, `findPathOnRoads`), the weather (`atmosphere.getWind`, …: DCS weather doesn't change during a mission) and the magnetic model (`require("magvar")`; `tools\bearings.lua` keeps the loaded module as a cache). Asking them is like reading Data. Reading live units and objects is Watch's alone.
11. **A Record entry may be worked out when it is read** (the flight situations are built only when a directive asks, as today; is group X alive; is SAM site Y out of the fight), by the Watch code that owns it; it is still a Watch fact. **Actors and Inform reach it only through its `record\` module** (`RecordGroups.alive(name)` calls `WatchGroups.alive(name)`), so no actor and no Inform file ever names a Watch module.
12. **Start-up is neither:** `load_framework.lua` and `run_mission.lua` stay at the top and only load and start things. Load order: data → tools → logs → record → watch → execute → commander → planner → controller → inform (Execute before the actors that call it); the run order stays in `run_mission.lua`.
13. **DCS events come in once** (John, 2026-10-09): `watch\dcs_events.lua` holds the only `world.addEventHandler`. It reads each event into a plain fact (names, types, coalitions, group, player, category, positions, place, weapon kind, target) and publishes it; everything that needs an event subscribes. A late read (a hit's damage a second on) is a follow-up fact from Watch.
14. **Execute is handed everything but the object it acts on** (John, 2026-10-09). A decision carries every id and position its order needs: airbase ids and elevations read once at start into `plan.world`, group ids from the spawn results in `record\orders.lua`. Execute looks up only the group or unit it acts on (a DCS object can't be kept in plain data, and goes stale), and reads back only the result of its own call.

**Which folder, for one function** (the test the move uses on every function):
1. Does it read live DCS? → **Watch**
2. Does it change DCS? → **Execute**
3. Does it choose what happens in the war? → **an actor**: strategy → **Commander**; a plan made ahead → **Planner**; the moment-to-moment call → **Controller**
4. Does it give players something to see or hear? → **Inform**
5. Does it write a log file? → **Logs**
6. Does it hold what others need to read? → **Record**
7. Does it only answer from its arguments? → **Tools**
8. Is it a plain table? → **Data**

A function that answers yes to two of these is two functions.

**The Record's mechanism** (`record\record.lua`): `Record.publish(subject, event)` and `Record.subscribe(subject, fn)`, one way for every change, replacing today's separate listeners (`RecordRadarPicture.on`, `RecordAirFlightDecisions.on`, the scheduler's record queries). Each `record\<subject>.lua` holds its entries, the functions to read them, and one write function, named in its header with its one writer. Inform's own bookkeeping of what it has said (`SendRadioCalls.onCall`: the pilots' answers hear Darkstar's orders as said) stays inside Inform.

**Module names** follow the file's path, in CamelCase, so every call shows its role or actor: `WatchRadarPicture`, `RecordRadarPicture`, `ExecuteSpawnAircraftGroups`, `InformRadioDarkstarPicture`, `InformMapSamSites`. **Actors:** the actor and the file, without the subject subfolder: `ControllerScrambleFighters`, `PlannerPlanSamSites`, `CommanderEvaluateDefenses`. Tools and Logs keep short names, because everyone calls them: `Util`, `Placement`, `SamReach`, `ThreatRouting`, `Weather`, `SpawnSites`, `Bearings`, `RadarCoverage`, `FlightCallsigns`, `GroundRoutes`; `Log` (dcs.log), `EventLog`. Data globals are unchanged (`CONFIG`, `AIR_CONTROL`, …).

**Outside DCS, by the same roles:** `radio_calls\` is Inform's other half (the radio helper words and voices calls, the radio player plays them; it also reads the jet's radios through the export script); `map_data_tools\` and `map_surveys\` are Tools (offline, building map data); `map_data\` and each mission's `data\` are Data; `offline_test_harness\` tests. The one-off measurement scripts in `mission_scripts\survey\` stay there: they run in their own missions, not as part of a mission's flow.

#### Two features, function by function

**Scrambles** (a raid is seen, a fighter launches, is leashed, lands back on alert):

| # | Role | File | What happens (today's function) |
|---|---|---|---|
| 1 | Data | `data\air_tasking.lua` (`AIR_DEFENSE`), `data\aircraft_profiles.lua`, `data\flight_callsigns.lua` | warning time, inbound rounds, reaction delay, turnaround; speeds; callsign names |
| 2 | Watch → Record | `watch\radar_picture.lua` → `record\radar_picture.lua` | the contacts and their derived facts (`poll`, `finishRound`, `threatOf`); how many rounds each has been inbound (today counted in `scramble_fighters.check`) |
| 3 | Watch → Record | `watch\airbases.lua` → `record\airbases.lua` | who holds each base, which ramp spots DCS reports free (today in `TrackAlertJets.canLaunch`, `freeSpot`) |
| 4 | Controller | `controller\air_flights\scramble_fighters.lua` | `check`: inbound long enough, no patrol covering it, not under enemy SAMs; `pickBase`, the intercept point, the airborne cap → **scramble MSN7901 from Kuusamo, launch in 85 s** |
| 5 | Tools | `tools\sam_reach.lua`, `tools\flight_callsigns.lua` | "in a kill zone?"; "the next free callsign is Rus 1" |
| 6 | Controller → Record | `controller\air_flights\assign_alert_jets.lua` → `record\alert_jets.lua`, `record\callsigns.lua`, `record\flights.lua` | the ledger (a jet committed, the cooldown, spot 7 held), the callsign in use, the new flight's entry |
| 7 | Controller | `controller\air_flights\scramble_fighters.lua` | 85 s later (`launch`): raid still there, a spot still free → **launch**, written to the Record, then Execute called |
| 8 | Execute | `execute\spawn_aircraft_groups.lua` | `buildGroup`, `spawn` (called by the controller) |
| 9 | Watch → Record | `watch\flights.lua` → `record\flights.lua` | takeoff, landing, losses |
| 10 | Controller | `controller\air_flights\apply_directives.lua` | the leash each picture round: raid heading away → **home** |
| 11 | Execute | `execute\air_flight_orders.lua` | `setTask` with a route home (today `GiveOrders.home`), called by the controller after it recorded the decision |
| 12 | Controller → Record | `controller\air_flights\assign_alert_jets.lua` | the jet landed → back on alert in 30 min |
| 13 | Inform | `inform\radio\darkstar_orders.lua`, `inform\radio\flight_calls.lua` | Darkstar's vector and "return to base"; "airborne", answers, check-out |
| 14 | Logs | `logs\event_log.lua` | `CONTROL scramble`, `no scramble`, `leash home`, `alert: landed…`; `SPAWNED`, `TAKEOFF`, `LAND` |

**The air picture for players** (the BRAA list every 2 min, and Darkstar speaking it):

| # | Role | File | What happens |
|---|---|---|---|
| 1 | Data | `data\air_picture_calls.lua`, `data\radio_calls.lua`; the mission's `data\radio_channels.lua` | period, time on screen, aspect bands, threat order; call kinds; each slot's Darkstar frequency |
| 2 | Watch → Record | `watch\radar_picture.lua` → `record\radar_picture.lua` | the contacts |
| 3 | Watch → Record | `watch\players.lua` → `record\players.lua` | which players are in which jets, where, airborne (today inside `callAll`) |
| 4 | Tools | `tools\bearings.lua` | the magnetic bearing as the F-16 shows it (`gridBearing`, `magvarAt`, `variation`); "is this player inside our radar coverage?" (`horizonM`, `groundDetectionM`, `covered`) stayed in `inform\screen\air_picture.lua` (a `tools\radar_coverage.lua` was planned) |
| 5 | Inform | `inform\screen\air_picture.lua` | per player, contacts near them, highest threat first, as BRAA lines (`pictureFor`, `describe`, `lineText`) |
| 6 | Inform | `inform\radio\radio_calls.lua` (`picture`, `threatRound`; a separate `darkstar_picture.lua` was planned) | the same picture as a spoken call to that jet, a threat call for a hot contact inside 40 nm; each call with its channel and frequency to the radio programs |
| 7 | Logs | `logs\event_log.lua`, `logs\dcs_log.lua` | `PICTURE_CALL`; `air picture: magvar +12.4° at Rovaniemi` |
| — | Actors, Execute | | none: telling players changes nothing in the war |

Also traced 2026-10-09: **the bandit call** (Watch: the picture, the flight situations, a missile fired at a flight → Controller: directives, one flight per threat, one intent → Record, then Execute: the pushed attack task → Watch: the flight seen following the order → Inform: Darkstar's engage and the pilot's answer → Logs: `CONTROL defend`) and **sleeping base defences** (Watch: enemy aircraft near each base, a sleeping unit hit → Controller: wake or sleep → Record: who is awake, then Execute: AI on / off → Logs: `UNIT_AWAKE`, the end table; nothing to Inform). Every function found one role; no role was empty or redundant. (Traced with a single Decide role; every Decide step there is the controller's.)

### Where the old files went (the move, 2026-10-10)

The whole move was one set of work (John, 2026-10-09; done 2026-10-10), every file sorted function by function with the test above. Plain moves used `git mv`, so history follows. Bug and run notes before 2026-10-10 use the old names; this table finds them.

| Before | Now |
|---|---|
| `gather.lua` (`Gather`) | `watch\world_at_start.lua` (`WatchWorldAtStart`: `plan.world`, and the airbase, group and weather dumps) |
| `config.lua` | `data\config.lua` |
| `stages\*` (`RollTerritory`, `PlanSamSites`, …) | `planner\*`, same file names (`PlannerRollTerritory`, `PlannerPlanSamSites`, …); the airspace lookups (`cell`, `classAt`, `kindFor`, `regionAt`, `nearestFront`, `facingRegion`) → `tools\airspace.lua` (`Airspace`) |
| `consumers\track_radar_picture.lua` | `watch\radar_picture.lua` → `record\radar_picture.lua` (`contacts`, `on`, …) |
| `consumers\track_weapon_impacts.lua` | `watch\weapon_impacts.lua` (`IMPACT` lines) |
| `consumers\announce_flight_activity.lua` | `watch\flight_activity.lua` → `record\flight_activity.lua`; `inform\radio\flight_calls.lua` (the calls) |
| `consumers\track_airfield_traffic.lua` | `watch\airfield_traffic.lua` → `record\airfield_traffic.lua` (the jets at each field); `inform\radio\airfield_calls.lua` (the phases and the calls) |
| `consumers\schedule_air_tasking_orders.lua` (`ScheduleAirTaskingOrders`) | `watch\flights.lua` (takeoffs, landings, losses, ramp losses, orphans) → `record\flights.lua`; `record\flight_launches.lua` (planned, launched, `statusOf`); `controller\air_flights\schedule_flights.lua` (the clock: due, late, launch, fly again, `track`) |
| `consumers\control_air_flights\control_air_flights.lua` (`ControlAirFlights`) | `controller\air_flights\direct_flights.lua` (`ControllerDirectFlights`: the checks, one intent, the watched flights → `record\watched_flights.lua`; decisions → `record\air_flight_decisions.lua`); missiles fired → `watch\shots.lua` → `record\shots.lua`; waypoints and the radar warning snapshot → `watch\flight_routes.lua` → `record\waypoints_reached.lua`; the ammo check → `watch\flight_loadouts.lua` → `record\flight_loadouts.lua` |
| `consumers\control_air_flights\assess_flight_situations.lua` | `watch\flight_situations.lua` → `record\flight_situations.lua` (worked out when read) |
| `directives_per_flight`, `coordinate_flights`, `decide_launches`, `scramble_fighters` | `controller\air_flights\apply_directives.lua`, `coordinate_flights`, `decide_launches`, `scramble_fighters` |
| `consumers\control_air_flights\track_alert_jets.lua` | `controller\air_flights\assign_alert_jets.lua` → `record\alert_jets.lua` (`ready`); free ramp spots → `watch\airbases.lua` → `record\airbases.lua` |
| `consumers\control_air_flights\give_orders.lua` (`GiveOrders`) | `execute\air_flight_orders.lua` (`ExecuteAirFlightOrders`; each result → `record\orders.lua`) |
| `consumers\sleep_ground_units.lua` (`SleepGroundUnits`) | `watch\enemy_aircraft_near_bases.lua` → `record\enemy_aircraft_near_bases.lua`; `controller\wake_ground_units.lua` → `record\ground_units_awake.lua`; `execute\ground_units_on_off.lua`; `logs\ground_units_awake.lua` (`UNIT_AWAKE`, the end table) |
| `consumers\spawn_aircraft_groups`, `spawn_ground_groups`, `spawn_static_objects`, `preload_aircraft_types` | `execute\`, same names (`ExecuteSpawnAircraftGroups`, …) |
| `consumers\territory.lua` (`Territory`) | `execute\base_coalitions.lua` (sets each base's coalition); `inform\map\territory.lua` (the circles) |
| `consumers\write_event_log.lua` (`WriteEventLog`) | `logs\event_log.lua` (`EventLog`); the `POSITION` lines' reads → `watch\aircraft_positions.lua` → `record\aircraft_positions.lua` |
| `lib\logger.lua` | `logs\dcs_log.lua` (`Log`) |
| `consumers\send_radio_calls.lua` (`SendRadioCalls`) | `inform\radio\radio_calls.lua` (`InformRadioRadioCalls`, Darkstar's picture and threat calls included) |
| `consumers\announce_controller_orders.lua` | `inform\radio\darkstar_orders.lua` (listens to `record\air_flight_decisions.lua` and `record\orders.lua`) |
| `consumers\call_air_picture.lua` | `inform\screen\air_picture.lua` (radar coverage included); bearings and the magnetic variation → `tools\bearings.lua` (`Bearings`); the players → `watch\players.lua` → `record\players.lua` |
| `consumers\brief_air_tasking`, `create_airfields_brief`; `lib\player_menus.lua` | `inform\screen\briefing.lua`, `airfield_info.lua`, `player_menus.lua`; the wind → `watch\wind.lua` → `record\wind.lua` |
| `consumers\draw_airspace`, `draw_base_defenses`, `draw_sam_sites`, `draw_fixed_ground_targets`, `draw_convoys`, `draw_air_tasking_orders` | `inform\map\airspace.lua`, `base_defenses`, `sam_sites`, `fixed_ground_targets`, `convoys`, `air_tasking_orders`; each one's `summaryText` → `logs\build_summary.lua` (`BuildSummary`) |
| `lib\flight_callsigns.lua` | `tools\flight_callsigns.lua` (`FlightCallsigns.assign` from the numbers it is handed); the numbers in use → `record\callsigns.lua` |
| `lib\util`, `placement`, `threat_routing`, `sam_reach`, `weather`, `spawn_sites` | `tools\`, same names |
| (new) | `watch\dcs_events.lua` (the one `world.addEventHandler`; rule 13) → `record\dcs_events.lua`; `watch\groups.lua`, `threats.lua`, `airborne_aircraft.lua` → their `record\` files; `record\record.lua` (`Record.publish` / `subscribe`) |
| `data\*`, `survey\`, `load_framework.lua`, `run_mission.lua` | unchanged |

**Not yet as the rules say** (left for later, each small):
- the airfield phases (taxi, departing, final …) are still worked out in `inform\radio\airfield_calls.lua`, not Watch; the airfield calls use `InformRadioFlightCalls.headingHome`;
- Execute still looks up an airbase's id and point and a threat group itself (rule 14): the harness's saved worlds have no airbase ids yet;
- `watch\flights.lua`, `watch\shots.lua` and `watch\weapon_impacts.lua` read the raw DCS event (`fact.raw`; allowed inside Watch);
- `logs\dcs_log.lua` (errors and warnings on screen) and `load_framework.lua`'s load error still call `outText`.

**How it was checked:** the offline harness, 11 runs per mission, byte-identical but for the load list and one intended reorder (a launch's retry and launch-early `CONTROL` lines now come before its `SPAWNED`); both baselines re-recorded; the data tools' outputs unchanged. The harness never fires a weapon, so a scripted fight (shots, hits with the life left, a kill, a player's static kill, an ejection, a crash, AI aborts, a landing, a SAM lost) was fired into the old code and the new on both missions: the same event log lines, radio calls and screen text. It found one bug (the follow-up `hit_life` fact crashed the subscribers that read the raw event), fixed.

**Next for Afghanistan, on this layout:** `tools\ground_routes.lua`, `data\ground_movement.lua`; with the ground war `watch\companies.lua`, `controller\ground_companies\`, `execute\ground_company_orders.lua`; with the campaign `commander\` (the JFC) and the planner's ground and logistics plans.

**Script layout.** Two folders under `Saved Games\DCS\Scripts\`, each a plain copy of its folder in the repository; a de-sanitized `MissionScripting.lua`; one mission editor trigger per mission, `ONCE → TIME MORE 1 → DO SCRIPT dofile(lfs.writedir() .. "Scripts\\<scripts folder>\\init.lua")`.
```
shared_mission_framework\mission_scripts\   → Scripts\shared_mission_framework\
  load_framework.lua             -- loads the framework and the mission on it, in order; a failure stops everything, named
  run_mission.lua                -- the run sequence (RunMission.start)
  data\                          -- plain tables: CONFIG and the shared data (facts about DCS, recipes, the tuning every mission uses as is)
    config.lua                   -- tunables and debug flags (CONFIG), the shared defaults
    base_defense_levels.lua  base_defense_composition.lua  base_defense_placement.lua
    sam_site_recipes.lua  sam_site_density.lua
    fixed_ground_target_recipes.lua  fixed_ground_target_density.lua
    convoy_recipes.lua
    air_tasking.lua              -- mission types, tasking, timing, SEAD (AIR_PACKAGE), AIR_DEFENSE, routing, HUMAN_TASKING
    airspace.lua                 -- airspace grid settings
    radar_picture.lua            -- radar picture settings: polling, stale / drop times, sensor kinds, inbound
    air_picture_calls.lua        -- the players' air picture: period, aspect bands, threat order, callsigns
    radio_calls.lua              -- the radio: on / off, channels and frequencies, call kinds (priority, expiry, folding), threat range, the watcher's and airfield calls' settings, calls file, start command
    flight_callsigns.lua         -- callsign names by mission type and aircraft type
    air_control.lua              -- the controller: directives per mission type, their settings, intent priorities
    event_log.lua                -- event log settings: write interval, hold and fold windows, positions
    ground_unit_sleep.lua        -- which base defenses sleep; wake and reach distances, check interval
    aircraft_profiles.lua        -- per aircraft type: runway, parking, reach, speeds, altitudes (hand)
    aircraft_loadouts.lua        -- one loadout per type × mission (aircraft_loadouts.py)
    aircraft_pylons.lua          -- pylon → CLSID, generated; offline validation only, not loaded
    unit_pool.lua                -- every spawnable DCS unit type (unit_pool.py)
    cloud_presets.lua            -- DCS cloud presets (cloud_presets.py)
  tools\                         -- answers from their arguments, asked by anyone
    util.lua                     -- RNG, picks, geometry, serialize, writeFile
    weather.lua                  -- weather + time/sun derivation
    placement.lua                -- isClear, findClear, ring/disc points, buildAnchors, pickAnchorPoint
    threat_routing.lua           -- threat map, routes around rings, priced by airspace
    sam_reach.lua                -- how far a SAM site reaches at an altitude; kill zones; the enemy airfields' Tors / Pantsirs (SamReach)
    airspace.lua                 -- which airspace a point is in, the nearest front, the region facing a point (Airspace)
    bearings.lua                 -- bearings, latitude / longitude, the magnetic variation as the F-16 shows it (Bearings)
    flight_callsigns.lua         -- the next free callsign from the numbers in use (FlightCallsigns)
    spawn_sites.lua              -- the map's surveyed spawn sites (SpawnSites)
  logs\                          -- for us, after the game
    dcs_log.lua                  -- dcs.log, tagged [MISSION.log_tag]; errors (and warnings with CONFIG.WARNINGS_ON_SCREEN) on screen (Log)
    event_log.lua                -- the event log: every event of the air war, unit by unit, one file per run (EventLog)
    ground_units_awake.lua       -- UNIT_AWAKE / UNIT_ASLEEP lines and the end table (GroundUnitsAwakeLog)
    build_summary.lua            -- the build summary in dcs.log (BuildSummary)
  record\                        -- what is known and decided; one writer per entry (Record.publish / subscribe in record.lua)
    record.lua  dcs_events.lua  flights.lua  flight_launches.lua  watched_flights.lua  air_flight_decisions.lua  orders.lua
    radar_picture.lua  flight_situations.lua  shots.lua  waypoints_reached.lua  flight_loadouts.lua  flight_activity.lua
    airbases.lua  groups.lua  threats.lua  airborne_aircraft.lua  alert_jets.lua  callsigns.lua  players.lua
    airfield_traffic.lua  enemy_aircraft_near_bases.lua  ground_units_awake.lua  aircraft_positions.lua  wind.lua
  watch\                         -- the only reads of live DCS
    world_at_start.lua           -- every read before planning → plan.world (airbases + player slots, zones, weather, time)
    dcs_events.lua               -- the one event handler: each DCS event as a plain fact (rule 13)
    flights.lua                  -- takeoffs, landings, losses, ramp losses, orphans; target progress
    radar_picture.lua            -- each coalition's radar picture: contacts, rounds, sensors
    flight_situations.lua        -- the facts about one flight at one check (worked out when read)
    shots.lua  flight_routes.lua  flight_loadouts.lua  weapon_impacts.lua   -- missiles fired, waypoints, ammo, where weapons land
    airbases.lua  groups.lua  threats.lua  airborne_aircraft.lua  players.lua  wind.lua
    flight_activity.lua  airfield_traffic.lua  enemy_aircraft_near_bases.lua  aircraft_positions.lua
  execute\                       -- the only changes to the sim
    spawn_static_objects.lua  spawn_ground_groups.lua  spawn_aircraft_groups.lua
    preload_aircraft_types.lua   -- first-spawn freeze fix
    air_flight_orders.lua        -- intent → DCS orders (setTask, pushTask, remove); results to record\orders.lua
    base_coalitions.lua          -- each planned base's coalition
    ground_units_on_off.lua      -- AI on / off for sleeping base defenses
  planner\                       -- the stages, named by verb; run order lives in run_mission.lua
    roll_territory.lua  plan_base_defenses.lua  plan_sam_sites.lua  divide_airspace.lua
    plan_fixed_ground_targets.lua  plan_convoys.lua  catalog_targets.lua  plan_air_tasking.lua
  controller\                    -- every run-time decision (event word CONTROL)
    wake_ground_units.lua        -- short-reach base defenses asleep (AI off) until an enemy aircraft is near
    air_flights\
      direct_flights.lua         --   watching flights, the checks, picking one intent (ControllerDirectFlights)
      schedule_flights.lua       --   the mission clock: each planned flight due, late, launched, flown again
      apply_directives.lua       --   leash, suppression (go cold), self_defence
      coordinate_flights.lua     --   across flights: who takes which threat
      decide_launches.lua        --   a due flight: launch, wait, fly its SEAD again, cancel; the SEAD rotation; the airborne cap
      scramble_fighters.lua      --   scrambles: trigger, refusals, raid, base, intercept point, launch
      assign_alert_jets.lua      --   the alert jets: ready, cooldown, back on alert (the ledger)
  inform\                        -- the players, during the game
    screen\
      briefing.lua               -- start text + comms menu
      airfield_info.lua          -- comms menu Airfield info: every Blue base's wind, runway in use, next flights, alert jets
      air_picture.lua            -- every 2 min the radar picture to each player: BRAA from them, highest threat first
      player_menus.lua           -- comms menus per player group
    radio\
      radio_calls.lua            -- every radio call as a JSON line for the radio helper outside DCS; Darkstar's picture and threat calls; starts the helper
      flight_calls.lua           -- AI flights' check-in / out and mission calls from what they do
      darkstar_orders.lua        -- Darkstar's orders to AI flights and the pilots' reports, from the order results
      airfield_calls.lua         -- AI traffic at Blue fields: taxi, departing, inbound, final, clear on the field's frequency
    map\
      territory.lua  airspace.lua  base_defenses.lua  sam_sites.lua  fixed_ground_targets.lua
      convoys.lua  air_tasking_orders.lua    -- F10 map marks (all ToAll(-1) until fog of war)
  survey\                        -- one-off in-sim measurements, behind CONFIG flags or in a zone drawing mission
    survey_airbase_footprints.lua  survey_zone_terrain.lua  probe_parked_aircraft_spawn.lua

missions\<mission>\<scripts folder>\   → Scripts\<scripts folder>\   (Kola: kola_f16)
  init.lua                       -- entry: mission_settings.lua, then load_framework.lua and run_mission.lua
  mission_settings.lua           -- MISSION: names, folders, files, map facts (UTC offset, magnetic variation, map edges), its data files (plain data)
  data\                          -- the mission's map and scenario (MISSION.data_files)
    clusters.lua                 -- cluster table, bases per cluster (hand)
    coalition_rosters.lua        -- the only file that knows red from blue (ground, SAM, targets, aircraft)
    zones.lua                    -- ground zones + classes (miz_zones.py)
    player_slots.lua             -- PLAYER_SLOTS[base] (miz_player_slots.py)
    airbase_classes.lua          -- AIRBASE_CLASS[name] + runway lengths (hand)
    airbase_codes.lua            -- 4-letter code per base (same codes as map_data_sources/<airbase reference file>)
    airbase_footprints.lua       -- surveyed aprons / buildings (in-sim survey)
    forested_airfields.lua       -- fields with only a cleared overrun (hand)
    airfield_frequencies.lua     -- each airfield's tower VHF / UHF by airbase id (airfield_frequencies.py)
    radio_channels.lua           -- RADIO_CHANNELS: AWACS, mission and airfield channels, clear of the map's towers
    awacs_orbit_distances.lua    -- AWACS_ORBIT_DISTANCES: how far AWACS orbits keep from enemy fighter bases and the front
  survey\survey_zone_terrain.lua -- loads mission_settings.lua, then the framework's zone survey (the zone drawing mission's trigger)
```
Outside DCS, in `shared_mission_framework\`: `radio_calls\` (the radio player, the helper, the phrase banks, the voices, and `export_cockpit_radios.lua`, which DCS's export system runs from there through one line in `Saved Games\DCS\Scripts\Export.lua`; Python, never copied to Scripts; *Radio calls*), `map_data_tools\` (*Offline tools and test harness*), `offline_test_harness\`. In each mission's folder: `map_data_sources\` (what the map tools read for its map: Kola's `kola_airbases.json`), `event_logs\`, its `.miz` and `development_docs\`.

Load order: `data\config.lua` → shared `data\*` → the mission's `data\*` → `tools\` → `logs\` → `record\` → `watch\` → `execute\` → `planner\` → `controller\` → `inform\` (→ the surveys a `CONFIG` flag asks for) → the data checks; then the run sequence (*Run order*).

**Naming and ids.** Every spawnable plan entry has a unique `id`, used verbatim as the DCS group name, so events map straight back to plan entries.

| Thing | Convention | Example |
|---|---|---|
| Zone (tool-generated) | `ZONE_<BASE>_<brg>_<km×10>` | `ZONE_KITT_100_012` |
| Base defense | `DEF_<CODE>_<component>_<n>`; units `<id>_<n>` | `DEF_OLEN_towed_anti_aircraft_guns_1` |
| SAM / EW site | `SAM_<CODE>_<system>_<n>`; escort `<id>_escort` | `SAM_SEV1_SA10_1` |
| Fixed ground target | `TGT_<CODE>_<kind>_<n>`; statics `<id>_static_<n>` | `TGT_IVAL_communications_site_1` |
| Convoy | `CONVOY_<FROM CODE>_supply_convoy_<n>` | |
| Flight | `MSN<n>_<tag>`: Blue 2001+, Red 7001+ (scrambles 2901+ / 7901+; Red was 5001+ / 5901+ until 2026-10-02, so older run notes and logs use those); units `<id>_<n>`. MSN = mission number, as in a real air tasking order. Tag = the mission type's `group_name_tag`: `STRIKE`, `OCA` (offensive counter-air: airfield strike), `SEAD`, `DEAD`, `CAP`, `AEW`, `SCRAM` (John, 2026-09-30) | `MSN2025_DEAD`, `MSN2901_SCRAM` |
| Patrol station / AWACS station | `CAP_<CODE>_<kind>_<n>` / `AEW_<CODE>_1` | |
| Player slot group | `f16_<base>` (placed by John) | `f16_rovaniemi` |

The player's flight has no pre-named group (dynamic spawn); it's matched by the player unit plus the frag's mission number.

---

## As built

### Run order (`run_mission.lua`)

The mission's `init.lua` (loaded by its mission editor trigger) loads its `mission_settings.lua` (`MISSION`), then `load_framework.lua` (`LoadFramework.run()`: config → shared data → the mission's data → tools, logs, record, watch, execute, planner, controller, inform → the data checks; *Loading*), then `run_mission.lua`, whose `RunMission.start()` runs the sequence `CONFIG.START_DELAY` in (airbase queries return empty at T+0):

`WatchWorldAtStart` (+ player slots) → `PlannerRollTerritory` → `PlannerPlanBaseDefenses` → `PlannerPlanSamSites` → `PlannerDivideAirspace` → `PlannerPlanFixedGroundTargets` → `PlannerPlanConvoys` → `PlannerCatalogTargets` → `PlannerPlanAirTasking` (defensive air → human flights → AI attack packages) → plan dump (`Saved Games\DCS\<MISSION.plan_dump_file>`; Kola: `kola_last_plan.lua`).

Then:
0. `EventLog.open` (this run's event log, with the plan at its top).
1. `InformMapAirspace.apply` (first, under every other mark).
2. `ExecuteBaseCoalitions.apply`, its bases drawn by `InformMapTerritory.apply`.
3. Spawns: **static objects first**, then base defenses, SAM sites, fixed-target units, convoys.
4. Draws.
5. `ExecutePreloadAircraftTypes`, then `WatchDcsEvents.start` (the one event handler) and `EventLog.start` (DCS events from here on, so the preload isn't in the story), `WatchWeaponImpacts.start`.
6. `RecordCallsigns.start` (run-time callsigns carry on from the plan's), `WatchFlights.start`, then `ControllerScheduleFlights.start` (the mission clock).
7. `WatchThreats.start`, `WatchFlightLoadouts.start`, `WatchRadarPicture.start` (before anything that reads the picture).
8. `WatchFlightSituations.start`, `ControllerDirectFlights.start` (the controller, scrambles included), `WatchFlightRoutes.start`, `WatchShots.start`; then `ControllerWakeGroundUnits.start` and `GroundUnitsAwakeLog.start`.
9. `InformMapAirTaskingOrders.apply`, then `InformScreenAirPicture.start` (the air picture) and `InformRadioRadioCalls.start` (the radio: empties the calls file, starts the radio player and helper).
10. `InformScreenAirfieldInfo.start`, `InformScreenBriefing.start` (comms menu), then `InformRadioFlightCalls.start`, `InformRadioAirfieldCalls.start` (the AI pilots' and airfield calls; after the airfield brief, whose runways they use) and `InformRadioDarkstarOrders.start`.
11. Build summary to `dcs.log` (`BuildSummary.text`).
12. `InformScreenBriefing.showStart` (start text, 3 min).


### Stage 1: territory (`planner\roll_territory.lua`, `data/clusters.lua`)

Syria-style clusters: some always Blue, some always Red, contested ones rolled. Two mechanics keep the roll plausible:
- **`p_red`** weights each contested cluster's roll.
- **`requires_red`** makes a deep cluster roll only if its border neighbour already fell (evaluated in file order), so Russia can't hold Alta while Kirkenes stays NATO.

The clusters (which bases, always Blue / always Red / contested, `p_red`, `requires_red`) are each mission's scenario data, `data/clusters.lua` in its scripts folder (Kola's: Kola's `mission_design.md`, *Kola's map and scenario*).

- **Echelon:** `front` ≤ `ECHELON_FRONT_KM` 100 km from the nearest enemy base, `mid` ≤ 200, else `rear`.
- **Zones:** each zone inherits its cluster's side.
- **After changing clusters:** re-run `miz_zones.py` (zones carry their cluster); no survey flight is needed if no zones moved.
- **Applied to the sim:** `ExecuteBaseCoalitions.apply` calls `setCoalition` + `autoCapture(false)` per base and draws a circle per base.

### Stage 2: base defenses (`planner\plan_base_defenses.lua`)

Every airbase gets a coalition-appropriate ground defense sized to how hard its owner holds it.

| Term | Question it answers | Values | Set where |
|---|---|---|---|
| **`class`** | What *is* this base? | `hub` / `fighter` / `bomber` / `dispersal` / `strip` / `heli` | `data/airbase_classes.lua` |
| **`echelon`** | Where does it sit relative to the enemy? | `front` / `mid` / `rear` | `PlannerRollTerritory` |
| **`defense_level`** | How heavily does its owner defend it? | `light` / `standard` / `heavy` | `BASE_DEFENSE_LEVEL[class][echelon]` |
| **component** | A kind of defensive element | `towed_anti_aircraft_guns`, `mobile_anti_aircraft_guns`, `infrared_missile_launchers`, `radar_missile_launchers`, `shoulder_launched_missile_teams`, `security_infantry` | `data/base_defense_placement.lua` |
| **composition** | How many groups of each component, per level | `{ component, min, max }` | `data/base_defense_composition.lua` |
| **placement** | Where a component's groups go | anchors spec, ring fallback, units per group, spread | `data/base_defense_placement.lua` |
| **anchor kind** | What open ground a group starts from | `infield`, `apron`, `parking`, `building`, `runway_side`, `runway_end`, `road` | `Placement.buildAnchors` |
| **role / roster** | Which types a coalition fields per role | weighted `{ type, weight }` | `data/coalition_rosters.lua` |

**Airbase classes are decided by runway length** (session 9; John: runway length is what decides; `data/airbase_classes.lua` lists each field's DCS runway):
- **`strip`:** too short for any jet (< `AIRBASE_CLASS_JET_RUNWAY_M`, 1,500 m).
- **`dispersal`:** any other field with no bigger role; a secondary field the air force flies fighters from in wartime (Finnish and Swedish dispersal doctrine).
- **Mismatches:** `PlannerPlanBaseDefenses` warns at start-up when a class disagrees with the runway.
- **Always heavy:** the bases a mission's `data/airbase_classes.lua` makes `hub` or `bomber` (Kola's: Kola's `mission_design.md`, *Kola's map and scenario*).

**Defense level.** What a base is matters more than where it sits: hubs and bomber bases are defended heavily anywhere, since long-range strikes reach the rear.
```
                 front      mid        rear
   hub           heavy      heavy      heavy
   bomber        heavy      heavy      heavy
   fighter       heavy      heavy      standard
   dispersal     heavy      standard   standard
   strip         standard   light      light
   heli          standard   light      light
```
Rough size: heavy 5 groups / ~10 units, standard 2–4 / ~7, light 2 / ~5 (before 2026-10-01: ~20 / ~13 / ~9). Skill: heavy `Good`, else `Average`. Standing ground units barely register on their own (John); what they cost is scanning the sky while aircraft fly, so the short-reach ones sleep (*Sleeping ground units*).

**Groups per level**, most important layer first (trimmed 2026-10-01 for performance in VR: security infantry is no longer fielded, its placement kept so it can come back; towed guns and MANPADS teams were 1–2):
```
                                   heavy   standard   light
   radar_missile_launchers          1        —         —
   infrared_missile_launchers       1        0–1       —
   mobile_anti_aircraft_guns        1        0–1       —
   towed_anti_aircraft_guns         1        1         1
   shoulder_launched_missile_teams  1        1         1
```

**Rosters.** Which types each coalition fields per role is the mission's scenario data (`COALITION_DEFENSE_ROSTER` and the rest of `data/coalition_rosters.lua`, in its scripts folder). Coverage and realism beat exact type (John); only single-vehicle systems here, multi-vehicle SAMs belong to the SAM site recipes. Kola's rosters and what was left out on purpose: Kola's `mission_design.md`, *Kola's map and scenario*.

**Placement.**
- **Trees are invisible to every DCS API** (proven by probe; don't re-investigate). So placement starts from ground that is open by construction, surveyed once into `data/airbase_footprints.lua`:
  - `infield`: grass between each runway's keep-clear edge and the first taxiway within 600 m;
  - `apron`: taxiway cells whose 4 neighbours are also taxiway;
  - `parking`, `building`;
  - `runway_side`: only at fields with no taxiway surface at all.
- **Forested fields** (`data/forested_airfields.lua`: Afrikanda) use only `runway_end`: the cleared overrun 80–380 m past each threshold, with units spread ≤ 30 m.
- **Anchors per component:** guns and vehicle launchers go infield first (0–40 m), then apron / parking 40–100 m, never buildings. Shoulder-launched missile teams and infantry spread wider, and buildings are allowed.
- **`Placement.isClear` for every group centre and unit:**
  - outside runway boxes (100 m beside the edge, 400 m past each end);
  - ≥ 60 m from parking spots;
  - no runway, taxiway or water in 9 surface samples;
  - flat ground (2026-10-08, John, from the Afghanistan spawn site viewer: an SA-10 needs flat ground): the spot and 8 points 8 m around it within 0.8 m (`Placement.unevenGround`, `CONFIG.CLEAR_FLAT_*`; reject reason `slope`). `isClearRoad`, the fallback, checks it too. **Never dropped for slope** (John: "it should jitter and try and place it somewhere flat inside the zone"): a SAM unit or target object with no flat spot in its part of the layout looks anywhere flat in the zone (only when slope turned it down, so a merely crowded site plans as before), and with none anywhere it takes the flattest spot that passes every other check (`findClear`'s third return; reject tally `placed_on_slope`); base-defense group centres and units and supply trucks the same. Convoy road points skip the check (`isClearRoad(…, true)`: they drive off). Harness: all baselines unchanged (its terrain is flat); with a hilly stub terrain, no unit dropped in Kola or Caucasus, at a worst-case cost of ~3–5 s of extra height samples at planning. Not seen in DCS yet.
- **Spacing:** group centres ≥ 150 m apart. Unit spacing by component: towed guns 25, mobile guns 30, missile launchers 40, missile teams 10, infantry 6 m.
- **Placement order:** most important layer first, so a cramped field loses towed guns, never its radar or infrared missile launchers.
- **Road fallback, instead of hand-drawn zones** (John: no manual placement work):
  - a group that finds no open ground in 80 tries goes onto one of the airfield's own roads (`anchor_kind = "road"`, within 800 m of a runway box);
  - a towed gun on a road becomes the truck-mounted Ural-375 ZU-23, facing along the road;
  - if the roads are full, the search widens to 2,000 m;
  - a unit that doesn't fit retries at half spacing, then a road within 300 m and then 1,000 m of its group;
  - only then is anything dropped (`DROPPED` warning, which shouldn't happen).

**Plan shape:**
- **Entry:** `plan.base_defenses = { groups = { { id, base, side, class, echelon, level, component, role, skill, anchor_kind, pos = { x, z, lat, lon }, units = { { type, x, z, heading_deg } } } }, bases = { [name] = { code, side, class, echelon, level, groups, units, anchors, rejects, dropped, on_roads } }, totals }`.
- **Names:** group id `DEF_<CODE>_<component>_<n>` is the DCS group name; units are `<id>_<n>`. Headings face outward from the field.
- **Not in the target catalog yet:** base defenses live in the plan, so they can become mission targets or brief information later.

**Load-time validation** (`PlannerPlanBaseDefenses.checkData`; fails loudly, nothing spawns):
- every roster type exists in `UNIT_POOL.ground`;
- every placement role has a roster for both sides;
- every composition component has a placement;
- every level has a skill, and every matrix cell a composition.

### Stage 3a: SAM sites (`planner\plan_sam_sites.lua`)

Target feel (John): **Ukraine-war density with mixed-age kit**, lived-in, built from what DCS has; coverage matters more than exact type. ~20–30 SAM sites per side per roll is judged about right. Don't change SAM spawning without being asked (John: "we just got that working the way we wanted"); later stages only consume `plan.sam_sites.zones_used`.

**How a site is decided** (`data/sam_site_density.lua`). Every held zone gets one role, first match wins:

| Role | Rule |
|---|---|
| `asset_ring` | ≤ 40 km from an own `heavy` base |
| `front_belt` | ≤ 100 km from an enemy base, or ≤ this roll's front gap + 60 km, whichever is farther |
| `rear_area` | anything else |

- **Chance by role:** asset 0.9, front **0.7** (lowered from 0.8 in session 9, to leave front zones for ground targets), rear 0.35.
- **Layer by weight:** asset: long 3 / medium 5 / short 2; front: medium 5 / short 4 / EW 1; rear: EW 3 / medium 2 / short 1.
- **System:** from `COALITION_SAM_SYSTEMS[side][layer]` that **fits the zone** (recipe `footprint_m` ≤ zone radius; else the next smaller layer).
- **Caps:** ≤ 75 % of a side's zones become SAM sites; ≤ 2 early-warning sites per side, and a pick over that cap becomes medium range.
- **Minimum per layer, placed first:** Red 3 long range + 2 early warning; Blue 1 long range + 2 early warning. Early warning goes rear-first; other layers go to the asset ring first, in clusters the side always holds, spread by area, with random tie-breaks so sites move between rolls.
- **Spreading:** ≤ 1 long-range site per area; ≤ 2 sites per base in the rear; no two sites of one side within 3 km.

**Systems** (`COALITION_SAM_SYSTEMS` in the mission's `data/coalition_rosters.lua`): per coalition and layer, weighted. Kola's: Kola's `mission_design.md`, *Kola's map and scenario*.

**How the systems perform in DCS** (researched 2026-09-23; engagement ranges high / low altitude):

| System | DCS | Behaviour, and what the recipe does |
|---|---|---|
| SA-10 | 5–120 / 5–40 km | Strongest SAM in DCS: 360° radars, 15 targets × 2 missiles, shoots down incoming missiles. |
| Patriot | 3–120 / **3–30 km** | Radar sees a fixed ~120° sector; wasted long shots. Recipe: **2 radars aimed 30° either side of the threat axis**, 6 launchers. |
| NASAMS | 0.7–57 / **0.7–14 km** | Limited by DCS's AMRAAM. Recipe: 2 search radars. |
| Hawk | 1.5–45 / 1.5–22 km | Needs its tracking radar to illuminate the target, so beaming defeats it. 2 tracking radars. |
| IRIS-T SLM | 40 km (mod data) | Currenthill mod; unverified. |
| SA-11 | 3.3–35 / 25 km | Radar on every launcher: robust. Weighted up for Blue. |
| SA-15 Tor | 1.5–12 km | Strong; very good at shooting down incoming missiles. |
| SA-8 Osa | 1.5–10.3 km | Decent; optical fallback if its radar is suppressed. |
| Roland | 0.5–8 km | Radar-only in DCS. |
| Rapier | 0.4–6.8 km, 3 km ceiling | Can't engage low flyers. Recipe kept, not rostered. |

Rings are drawn with ED's high-altitude figure; the low-altitude reach is much shorter (for the brief). Sources: ED forum threads on the Patriot and AIM-120, Airgoons DCS reference, DCS Liberation #1531.

**Recipes** (`data/sam_site_recipes.lua`):
- **Per system:** `layer`, `footprint_m`, `unit_spacing`, `parts = { type, min, max, place, aim }`, optional `escort_role`.
- **Places:** `centre` 0–35 % of the footprint (radars, command post), `launchers` 45–95 %, `edge` 60–100 % (support trucks).
- **Facing:** radars and launchers face the nearest enemy base; `aim` gives sector radars an exact heading.
- **Groups:** **one DCS group per site** (a system's radars and launchers must share a group); the point-defense escort is its own group `<id>_escort`.
- **On the F-16's HSD** (Kola bug 25, confirmed 2026-10-02): medium and long-range site groups spawn with `hiddenOnMFD = false` (`run_mission.lua` passes them to `ExecuteSpawnGroundGroups.run` as `show_on_mfd`), so their threat rings show; escorts, short-range and early-warning sites stay hidden (DCS's default for a script-spawned group). A coalition's SAM groups spawn as the country in `MISSION.sam_site_country` (Kola: Red as Russia), not CJTF Red (`options.country`). The DTC can't carry them: they spawn after the mission starts.

**Placement:** units stay inside their zone; `Placement.isClear` against the nearest airfield, then half spacing, then point-only. Base defenses keep 30 m outside every zone within 5 km of their base.

**Plan shape:** `plan.sam_sites = { sites = { { id, side, system, layer, role, zone, defends, pos, engage_m, detect_m, group_ids } }, groups, zones_used, summary }`. Group id `SAM_<CODE>_<system>_<n>` (e.g. `SAM_OLEN_SA10_1`), escort `<id>_escort`.

**Validation** (`PlannerPlanSamSites.checkData`): every recipe part is in the pool; every escort role has rosters; every system entry names a recipe of its layer.

**Known gaps:**
- A map whose zones are small fits only short- and medium-range systems there (Kola's core: Kola's `mission_design.md`, *Kola's map and scenario*).
- No alarm-state or ROE orders (DCS defaults engage).

### Stage 3b: fixed ground targets (`planner\plan_fixed_ground_targets.lua`)

Everything on the ground worth attacking that doesn't move and isn't a SAM site, for both coalitions (John: "an active conflict unfolding").
- **"Fixed"** = doesn't move; "mobile" = moves.
- **"Static"** is reserved for actual DCS static objects (`coalition.addStaticObject`, `form = "static_object"`, `UNIT_POOL.static`). A recipe part is a `unit` if it would shoot or drive, and a `static_object` for buildings and parked vehicles or aircraft.

**Data:**
- **`data/fixed_ground_target_recipes.lua`:**
  - `label`, `location` (`zone` / `parking_spot` / `airfield_ground`), `echelons`;
  - zone class `requires` / `prefers`;
  - `footprint_m`, `unit_spacing`;
  - `parts { role, min, max, place, form, critical, same_type, spacing_m }`;
  - `success = { critical_fraction }`, `mission_types`, `value`.
- **`data/fixed_ground_target_density.lua`:** per coalition, the zone chance and kinds per echelon, airfield chances by base class, minimums, caps.
- **`COALITION_FIXED_GROUND_TARGET_ROSTER`** in `data/coalition_rosters.lua`.

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
| airfield_fuel_storage | building / apron anchors | — | all |

**Roll per coalition:**
1. **Minimum pass:** each kind goes to its best-fitting place.
2. **Zone pass:** each free zone gets a chance by echelon, then a kind that fits (weighted up by matched preferences).
3. **Airfield pass:** each held base rolls each airfield kind by its class.

- **One roller** for every kind (John: separate rollers would get unwieldy).
- **Revetment zones** (`prepared_sam_position = "revetments"`) are for SAM sites only (John).

**Placement:**
- **Zone objects** stay inside the zone.
- **Airfield ground** uses the base-defense anchors, ≥ 40 m from base-defense units.
- **Parked aircraft** (John: scattered singles weren't realistic):
  - real parking spots, ≤ 30 % of a base's spots, and never a player slot;
  - large aircraft on terminal type 104, helicopters on 40/72/104;
  - nose toward the runway;
  - **one group per base, one type, parked together** around the spot with the most free neighbours within 300 m.

**Plan shape:** `plan.fixed_ground_targets = { sites, groups, static_objects, zones_used, parking_used, summary }`. Ids `TGT_<CODE>_<kind>_<n>` (DCS group name); units `<id>_<n>`; static objects `<id>_static_<n>`. A static object's category comes from the pool (structures from `UNIT_POOL.static`, `Planes` / `Helicopters`, or the vehicle's `cat`).

### Stage 3c: target catalog (`planner\catalog_targets.lua`)

`plan.target_catalog = { targets[id], list (by coalition, highest value first), summary[coalition].by_mission_type }`.
- **Entry:** `category`, `kind`, `label`, `coalition`, `cluster`, `location`, `zone` or `base`, `pos`, `value`, `mission_types`, `group_ids`, `static_object_ids`, `critical_names`, `success = { critical_fraction }`, `covered_by` (the owner's other SAM rings reaching it), `defended_base` (own base within 5 km), `description`.
- **SAM sites:** `suppression_of_air_defenses` + `destruction_of_air_defenses`; critical = radars, fraction 0.5: whether the site is out of the fight (the SEAD gate). **A DEAD flight has its own success** (John, 2026-10-03, not flown): `destruction = { critical_names, success }`, everything that sees, directs or shoots (pool roles `sam_sr`, `sam_tr`, `ewr`, `sam_cp`, `sam_ln`, `shorad`; not trucks or support vehicles) at 0.75 (`DESTRUCTION_FRACTION`): an SA-11 4 of its 5, an SA-6 3 of 4, an SA-8 both launchers. `commitFlight` gives a DEAD mission those as its `critical_names` / `success`, so its frag and `TARGET` lines count them. (Before, a HARM on the Banak SA-11's one search radar read "1 of 1 critical destroyed" for MSN2036_DEAD, due hours later; 19:29 run.)
- **Early-warning sites:** `strike` + `destruction_of_air_defenses`; fraction 1.
- **Convoys:** category `mobile_ground_target`, mission type `interdiction`, carrying their route and speed.
- **Rules:**
  - mission stages read only the catalog;
  - base defenses stay out;
  - the catalog is built before spawning; alive or dead is runtime state keyed by the same ids.

### Airspace (`planner\divide_airspace.lua`, `data/airspace.lua`)

`PlannerDivideAirspace` runs after `PlannerPlanSamSites` → `plan.airspace`.
- **Grid:** 10 km cells, each classified at its centre.
- **Held ground:** the coalition holding the nearest airbase. The front line is where it flips (marching squares, simplified).
- **Contested airspace:** within 30 km of the front line, or own ground under the enemy's medium or long-range SAM rings.
- **Encoding:** one string per row; `B` / `R` = own airspace, `b` / `r` = contested on Blue / Red ground.
- **Regions:** a region is a connected piece of one coalition's held ground; the largest is `main`, others are logged as `POCKET`. A front is a connected stretch of contested airspace.
- **Direction:** `Airspace.facingRegion` gives the own region nearest a target, and only bases in that region fly against it. A pocket fights only the front it faces (John stressed this).
- **Drawing:** `inform\map\airspace.lua` (mark ids 60000+) fills the areas as merged rectangles under every other mark, then draws the front line.

### Stage 4: convoys (`planner\plan_convoys.lua`, `data/convoy_recipes.lua`)

One Red supply convoy per mission (`CONVOYS_PER_COALITION`: Red 1, Blue 0).
- **Column:** 7–14 vehicles, with no infantry (it would slow the column to walking pace):
  - 1–2 armored personnel carriers at the ends;
  - 4–8 cargo trucks + 1–2 fuel trucks (critical);
  - 1–2 gun trucks mixed in;
  - 0–1 Shilka / Strela-10 at the tail.
- **Route:** a Red base pair 60–175 km apart, preferring rear or mid → front.
  - Start and parking are road points 2.5–5 km outside each airfield.
  - `land.findPathOnRoads` proves a road connects them (≤ 250 km); up to 8 pairs are tried.
  - Vehicles stand in a column 25 m apart; there's a waypoint every 20 km, "On Road" at ~50 km/h, and the convoy parks at the last one.
- **Ids:** `CONVOY_<FROM CODE>_supply_convoy_<n>`.
- **Map:** `inform\map\convoys.lua` (mark ids 40000+).

### Stages 5–6: air tasking (`planner\plan_air_tasking.lua`, `data/air_tasking.lua`)

**Order inside `PlannerPlanAirTasking`, per coalition:** defensive air (AWACS → CAP stations and rotations) → the SEAD order (which enemy sites, outside in) → human flights → the SEAD rotation → AI attack missions. Human flights come before the AI's so they get first pick of targets; the order comes before them so a player's SEAD can take a site it opens with.

**Airborne cap:** `max_airborne_aircraft` 12 per coalition (16 until 2026-10-01; cut 25 % for performance in VR, John: strike volume is all relative), counting every AI attack and SEAD flight, patrol, AWACS and scramble; human flights and players never count (John, 2026-10-01: the cap is for AI aircraft). The AI SEAD flights a player's mission needs do count, and are planned before the rotation and the AI's own missions. Planned flights fill it only up to `AIR_DEFENSE.scramble_reserve_aircraft` (2) below it (`plannedCap`), so strikes can't leave no room for a scramble; scrambles never go over it. Up to 24 aircraft airborne in total. In the harness on the 21:37 plan, planned peaks went from 13–16 to 7–10, and Red planned ~22–28 flights instead of ~30–36.

**Launch fields:** fighters and attack jets fly from any held field whose runway and parking fit them (John: in wartime every usable runway is used).
- F-16 / F/A-18 `min_runway_m` is 1,500 m (4,900 ft), so Alta (1,490 m) is just short and Kirkenes (1,795 m) qualifies.
- `base_classes` stays only on the heavies: Tu-22M3, B-1B, A-50, E-3A.
- Launch bases aren't tied to the parked-aircraft rosters (John: it would limit launch bases).

**Attack missions** (strike, airfield strike, DEAD; interdiction and close air support are stubbed with `built = false`):
- **Per mission:**
  1. mission type (weighted);
  2. aircraft from `COALITION_AIRCRAFT`;
  3. an enemy catalog target in reach (weighted by value, never hit twice);
  4. one of the 3 nearest fitting bases;
  5. a start time under the cap;
  6. free parking at that time;
  7. route and attack tasks.
- **Front only** (session 8): targets in the contested airspace or ≤ `AIR_TARGETING.max_km_past_contested` (40 km) beyond it. Launch bases come only from the own region facing the target.
- **Ids:** `MSN<n>` (Blue 2001+, Red 7001+; 5001+ before 2026-10-02) is the DCS group name.
- **Routes:**
  - **Cruise and descent:** ≥ 7,500 m (~25k ft) for every attack flight, above guns, MANPADS and short-range SAMs. Held until a descent point (5 km per km of drop, ≥ 10 km) before the ingress. The AI descends toward the next waypoint's altitude from the previous one, so attack altitude can't sit on the ingress point.
  - **Attack altitude** per aircraft and mission type, realistic for the payload whatever the threat (John): FAB-500 5,000 m, RBK 3,000 m, JDAM 7,000–9,000 m, Tu-22M3 carpet 8,000 m.
  - **Threat routing:** A* on a 10 km grid (`tools\threat_routing.lua`) around enemy medium and long-range SAM rings (+10 km) and Pantsir / Tor-M2 base-defense groups (+5 km). Every fixed enemy site is treated as known (John agreed).
  - **Airspace pricing:** own 1 / contested 3 / enemy 10 per km (`AIR_ROUTING.airspace_cost`). Smoothing refuses a shortcut that costs more than the path it replaces.
  - **Rejected routes:** a way around > 1.6× direct goes straight through; a route with more enemy-airspace km than the target's depth + 20 km isn't flown.
  - **Suppression flag:** a route still crossing a ring gets `needs_suppression` + `suppression_threats`.
  - **Way home:** the way out reversed. `return_when_out_of` is not used (DCS flies straight home off the route once the missiles are gone).
- **Making the AI attack** (researched from DCS Liberation's code and the ED forums; John: "the obvious choices don't actually work"):
  - one `Bombing` task per critical object at its position, on the ingress waypoint (search tasks never pick static objects);
  - every `Bombing` / `AttackGroup` task carries the planned attack altitude (`altitudeEnabled`; 2026-10-02, Kola bug 28: without it the AI picked its own once the attack started and flew it low, a JDAM strike dropping from 3,585 ft);
  - heavy bombers, and every flight with unguided bombs, get one `Bombing` at the centre with `expend = "All"` and one attack: the whole load in one pass, then out (2026-10-02, Kola bug 31: with a task per object and expend Auto, Su-34s dropped one FAB-500 a pass and circled the target);
  - rules of engagement `open_fire` (not weapons free, so the flight stays on its target);
  - evade fire, return at bingo, no jettisoning;
  - gun emptied (the AI otherwise strafes a Tor once the bombs are gone);
  - loadouts carry one kind of air-to-ground weapon each (the AI handles mixed weapons badly).
  - **standoff weapons, no overflying** (2026-10-02, John: air denial with standoff weapons): a strike carrying a weapon in `AIR_STANDOFF_WEAPONS` (Kh-59M 40 km, KAB-500S 8 km) has its "target" waypoint at a release point that far short of the target and turns home there; its weapons are spread over the critical objects, one attack each. Red's Su-34 strike flies the KAB-500S or the Kh-59M loadout at random (`AIRCRAFT_LOADOUT_OPTIONS`). Not flown yet (Kola bug 31 in `closed.md`).

  - **DEAD on a short-range site hits from out of its reach** (2026-10-02, Kola bug 4 in `closed.md`; not flown): the flight's weapon reaches the site's ring + 5 km, or it attacks from 1,000 m above the system's ceiling (`SAM_SITE_RECIPE` `ceiling_km`: SA-8 5, SA-15 6, Roland 5.5); `AIR_DEAD_WEAPONS`. The planner picks a DEAD loadout that does, and a target none does isn't taken by that aircraft. Red's Su-34 flies Kh-59M (release point 40 km) against short-range sites, either loadout on silenced medium sites; Blue's F-15E passes by height with JDAMs; AI F-16 / F/A-18 DEAD flights fly JSOW from a 20 km release point (AGM-154 added to `AIR_STANDOFF_WEAPONS`). Medium and long-range sites need no rule: the DEAD waits for SEAD. Human flights aren't held to it.

  Also: `EngageGroup` for anti-radiation missiles (it waits for the radar to emit), `AttackGroup` for SAM sites and convoys, and `BombingRunway` ignores laser-guided bombs. F-15E JDAMs do drop (confirmed session 8).
- **Loadouts** are generated, never hand-typed (John):
  - `map_data_tools/aircraft_loadouts.py` builds `data/aircraft_loadouts.lua` from ED's UnitPayloads, DCS Liberation's AI loadouts (reference clone `C:\Users\johnk\Git\dcs_liberation`) and Syria's proven CAS loadouts (`aircraft_loadouts_by_hand.json`);
  - the choice per type and mission type is in `aircraft_loadout_choices.json`;
  - every CLSID is checked against `aircraft_pylons.lua`; pylons carry weapon names;
  - `--list <type>` shows the options.
  - **Red flights carry their best long-range air-to-air missiles to protect themselves** (John, 2026-10-01): every Su-34 loadout is a hand loadout with 2× R-77 (`… R-77`: in place of the R-27Rs on pylons 5 and 8 for SEAD / DEAD / interdiction, in place of the R-73s on pylons 2 and 11 for strike and airfield strike). The fighters already carry their best (Su-30 R-77; Su-27 / Su-33 R-27ER, they can't take the R-77 in DCS; MiG-31 R-33). The Su-24M can carry nothing better than the R-60 and the Tu-22M3 nothing at all: they leave when a bandit comes (*The controller*).

**SEAD** (Kola roadmap item 12, built 2026-10-02, flown in every run since, closed 2026-10-05; John: "SEAD flights are the primary mission to open up everything else"; a flight that needs SEAD never flies without it, and an AI flight launches only once its SAMs are out of the fight):
- **One kind of SEAD flight:** a mission against one enemy air defense, its `target`: a medium / long-range SAM site (its point-defense escort saturated, not shot at) or a base-defense Pantsir / Tor group (a stand-in target built from the group; base defenses aren't in the catalog). "Escort" is gone (John, 2026-10-02: they don't escort anyone, they fly separately): no `escorts`, `suppresses`, `suppressed_by`, `cleared_by`, no packages (`PKG<n>`). SEAD loadouts carry 4 anti-radiation missiles per jet (F-16: 4 HARMs + centerline tank + an AMRAAM on each wingtip; F/A-18: 4 HARMs, Sidewinders and AMRAAMs, no tanks; both `hand:SEAD 4 HARM`, John's specs; Su-34 4 Kh-31P). `planned_as = "rotation"`.
- **One link, `requires_cleared`:** any flight lists the threats it needs out of the fight, in route order: a strike or DEAD the rings its route crosses; a SEAD flight the threats the site table already takes that its run-in goes through. **The site table** (`ctx.suppression`, in the plan `suppression_by_site`): each threat has at most one SEAD flight; every flight that needs it waits on that one.
- **The SEAD rotation** (`planSuppressionOrder`, `planSuppressionRotation`; John, 2026-10-02: "a 2 ship flight running pretty much the whole mission on both sides; one comes back and lands, despawns, the other spins up"), planned right after the human flights, so it has first call on the cap:
  - **Which sites, in what order:** every enemy medium / long-range site gets a step: 1 when it has a launch point clear of every other site's low-altitude reach (any bearing, tried from the nearest own base of the region facing it), n when one is clear once the sites of the steps before are out of the fight (the low map rebuilt without them, `lowMapWithout`), up to `max_order_steps` (3). First the sites whose full ring covers own or contested airspace (`ringCoverage`, 10 km samples), by step and then by coverage; a site of an earlier step whose low reach holds a later site's launch point goes before it; then the deeper sites, by step and nearest the front first. `dcs.log`: `SEAD order` (each site's place, step, coverage, what goes before it) and `not taken: …`.
  - **Back to back:** each 2-ship starts when the one before it is planned to land (touchdown; its takeoff is `taxi_s` later), and no earlier than 10 min after the salvo on what its run-in needs; from whichever base suits its site (a base with no parking free is left out and the next tried). A site the table already takes (a player's, or one a player's mission needs) is skipped. `SEAD rotation: … not taken (…)`, "the rotation fills the window before it" once the 6 hours are used.
  - **On the 10:38 roll** (six seeds): SEAD flights Red 0–4 → 9, Blue 0–2 → 10–11 (8–9 of them the rotation's); attack missions Red 2–3 (was 2–4), Blue 2–4 (was 1–3); AI peak 9–10 of the planned 10; the rotation is up all but ~2 h of the 6 (mostly the 10 min taxi at each handover). Blue's Kola-core sites are all step 1: with every bearing tried, each has a clear launch point from the far side.
- **SEAD an attack needs** (`draftNeededSuppression`): a mission whose route crosses a threat the table has no flight for gets one, from the mission's base when it can, else the nearest; flown alongside the rotation under the cap (John: option b). Not planned: `no SEAD flight: no launch point clear of other sites` / `too far for its fuel` / `too deep in enemy airspace` / `no base in reach`.
- **Timing (one rule):** a flight with `requires_cleared` starts no earlier than `strike_after_suppression_s` (10 min, for battle damage assessment) after the planned salvo (`tot_s`, the launch point) of each SEAD flight it waits on, not after its landing (real forces keep up the tempo; was landing + 10 min until 2026-10-02). Each flight is held under the cap only for its own time in the air.
- **Deeper targets where the way is cleared:** a target may lie up to `max_km_past_contested_when_cleared` (100 km) past the contested airspace when every ring over it already has a SEAD flight (a cheap filter in `reachableTargets`) and every ring its route crosses does too, at least one (`draftMission`: "too deep: its route's SAM sites aren't all taken by SEAD"). Otherwise targets stay within `max_km_past_contested` (40).
- **The SEAD profile: under the radar** (`suppressionRoute`, attack kind `harm_salvo`; Kola roadmap item 10, built 2026-10-01, John's profile after the 14:14 run, where the low run-in and pop-up killed the Sodankylä SA-10's radars). Numbers in `AIR_MISSION_TYPE.suppression_of_air_defenses`:
  - **Launch point** `launch_km` (45 since 2026-10-02, Kola bug 33: from 55 km the AI didn't fire, F-16s at ~10,600 ft pressing on to 44–48 km and a Su-34 at 5,000 ft never firing from 57 km; 55 before that, Kola bug 27: from 40 the sites fired back at the pop-up from 39–50 km and every SEAD jet that got there died; was 80 until the 13:07 run, where HARMs fired from 89–92 km were all shot down by the SA-10) from the site, or closer for a short-reaching target: its reach + `launch_past_reach_km` (15) when that is less (Kola bug 29, 2026-10-02: Tor M2 31 km, Pantsir 35, NASAMS 30, SA-6 40, Roland / Tunguska 23; the AI retry on the Vuojärvi Tor fired nothing from 40 km), on the side the flight comes from, **outside every other site's low-altitude reach** (`tools\sam_reach.lua`: SA-10 40 km, SA-11 25, … + 10 km; base-defense Pantsirs / Tors at full reach + 5; sites the table already takes left out) **and every short-range site's ring + `short_range_margin_km` (5)** (Kola bug 22): the bearing toward the base first, then every 15° either side.
  - **The way in** is routed around those low-altitude reaches and short-range rings (the low map without the table's threats; the way out is the same path, so the low egress and the climb-out keep clear of SA-8s, SA-15s and Rolands too: Kola bug 22, MSN5024_SEAD_1 lost to an SA-8 on its climb-out). Cruise in own airspace; a descent point so it is down `low_entry_margin_km` (10) before the route first enters any enemy ring (full reach + margin); **a base too close for the climb to cruise and the descent back** (the low entry under 2× the descent distance, ~77 km of route) **flies low from takeoff and never climbs**, way home included (Kola bug 33, John 2026-10-02: from Vuojärvi and Rovaniemi the cruise, descent and low leg crowded the climb-out); then **`low_altitude_m` (275, ~900 ft) above the ground** (`alt_type = "RADIO"`, the first non-sea-level altitudes in the mission) at `low_speed_mps` (270), a waypoint every `low_waypoint_km` (15) so the AI re-reads the ground; **pop up on afterburner** `popup_km` (8; was 15, and 12) before the launch point to `popup_altitude_m` (2,400, ~8,000 ft since Kola bug 36; 1,800 from Kola bug 33, John: "rocket themselves to 6k on afterburner, fire the entire salvo, then go cold", too low for the sites' radars to see the jets over the fells in the 16:03 run, so nothing was fired; 3,000 before that). A `popup_top` waypoint `popup_climb_km` (3) past the pop-up point is already at that altitude, so the AI is up before its launch point (Kola bug 40, 2026-10-02: with the altitude only on the launch point, DCS spread the climb over the leg and the F-16s passed their launch point at 2,825 ft). Up there the other sites reach farther than their low figure (Kola bug 27); the launch point is still cleared only of that low reach, and the short time up is accepted exposure (every SEAD jet lost at its pop-up so far fell to its own target). At the launch point an `AttackGroup` on the site's own group with every anti-radiation missile (`expend = "All"`, one attack), and from the top of the pop-up (`popup_top`; the pop-up until 2026-10-02 late, when the Su-34s fired low on the way up) an `EngageGroup` on it that fires the moment its radar is seen. **Pressing on for a radar ping** (Kola bug 36, John, 2026-10-02: "send the jets forward on that same track until they get a radar ping and can launch, then turn around and go home as planned"): a `press_on` waypoint on past the launch point, on the same track toward the site, at the pop-up altitude, up to `press_on_km` (20) closer (a short-reaching site whose launch point is outside its ring: no closer than its reach + 5 km; pulled back 1 km at a time out of other sites' low reach and short-range rings); nothing fired by there → home (go cold `no shot`). Built 2026-10-02, not flown.
  - **The way out:** straight back down and out low the way it came, afterburner allowed (option on the egress waypoint), afterburner off again at the low entry (`climb`), then back up to cruise and home. A route that enters no enemy ring at all (a short-reaching site, the launch point outside its own ring) has no low leg: down to 3,000 m, shoot, back.
  - **Fuel:** a low km counts `low_fuel_factor` (1.5) km of reach (`fuelLength`).
  - Waypoint kinds `low`, `popup`, `climb` (event log: "low level", "pop-up, climbing to the shot", "climb out, clear of the rings"). A long-range ring may reach past the launch point (SA-10, Patriot): it pops up, fires and turns away.
  - Strike and DEAD flights stay high (John): they launch only once their SAMs are out of the fight.
  - **Enemy airspace:** a SEAD flight may fly as deep into enemy airspace as its site lies (`siteFront`, searched to `facing_search_km`) + `enemy_airspace_slack_km`.
- **Go cold** (the controller's directive `suppression`, `AIR_CONTROL.suppression`): checked every fast check (5 s), and 0.5 s after each anti-radiation missile the flight fires, so it turns as the last one leaves (2026-10-02, John: no waiting once the salvo is away; it was the 30 s picture round); home once every anti-radiation missile is gone; `salvo_time_s` (20) after one jet of it fired its last (`salvo over`, Kola bug 40: a wingman firing one HARM a minute inside an SA-10's envelope died); at its press-on point with nothing fired (`no shot`, Kola bug 36); when it presses more than `press_km` (5) past its press-on point toward the site; inside the kill zone of another SAM site or an enemy airfield's Tor / Pantsir (Kola bug 41; at its height above the ground; not one its planned route passes through on purpose: `route_threats`; **not in its shot area while it has missiles**, from `popup_km` + 2 km before its launch point through the press-on leg, the plan's accepted exposure); or still on the attack `attack_time_s` (10 min) after it came within `arrival_km` (15) of its launch point (the clock starts on arrival, however late it took off: Kola bug 20, 2026-10-01). `CONTROL … go cold`. **Going home turns it around where it is** (John, 2026-10-01): before its launch point it flies its route out backwards from the nearest point behind it (low where it came in low); from the launch point on, its planned way back, starting after the press-on point, never on toward the site. (The first version always flew the planned way back, which starts near the launch point: MSN5026, sent home 15 s after takeoff, flew out to its target and turned there without firing.)
- **At run time** (the controller, `controller\air_flights\decide_launches.lua`, asked by the scheduler when a flight is due): a flight with `requires_cleared` launches only once those threats are out of the fight (a SAM site's critical radars to its success fraction; a base-defense group with no live unit). If not, per threat, its SEAD flight from the site table: still on its attack, or not launched yet → `wait` (10 min at a time, at most an hour on one that's on its attack); done (gone cold, sent home, landed or lost: no waiting out its planned landing) → `retry`, a copy `<id>_AGAIN` on parking free now, one per SEAD flight however many flights wait on it (looked at again 10 min after the copy's planned salvo); its second try spent → `cancel: … still in the fight after a second SEAD flight`; the SEAD flight itself cancelled → `cancel: <site>'s SEAD flight MSN… was cancelled`. A SEAD flight whose site is already out of the fight isn't sent (`cancel: not needed`). Nor a DEAD flight whose site already meets its own success (`cancel: not needed: SAM_BANA_SA11_1 already destroyed (4 of 5 critical)`; John, 2026-10-03: rare, HARMs mostly hit radars). A flight launched late flies a copy on parking free now, once there is room under the cap (checked every `wait_for_room_s`; `launch late`).
- **The rotation at run time:** one rotation flight in the air at a time per coalition (a rotation flight due while another is up looks again every `wait_for_room_s`). When a rotation flight is down (every jet landed, lost or removed: the scheduler tells the controller, `ControllerDirectFlights.flightDown`) or cancelled, the next one is pulled forward to now (`launch early`, a copy on spots free now once there is room). An earlier rotation flight that flew, is down and whose site is still in the fight gets its second try first, as the rotation's next flight, not an extra jet (`retry: … the rotation's next flight; MSN… waits`).
- **Players:** a player's strike or DEAD isn't held: the AI SEAD flights it needs (into the table like any) take off first thing (`first_start_s`; John: they make the player's tasking possible) and are over their sites at least `suppression_lead_s` (3–5 min) before the player is over the target (`scheduleHumanPackage`). **A player's SEAD** takes a step-1 site from the rotation's order (nothing to wait on) and is that site's SEAD flight in the table, so the rotation skips it; whatever waits on it gets the AI's second try if the site survives (two AI jets, `<id>_AGAIN`; Kola bug 17's rule), since a player's flight never counts as done for the AI. (The old form, the player taking the first threat on an AI mission's route, is gone; when no step-1 site fits, the player gets another mission type.)
- **Mission types:** `suppression_of_air_defenses` (anti-radiation missiles; the rotation and SEAD an attack needs). `destruction_of_air_defenses` is a primary (`AttackGroup` on each group; Red: Su-34 with 4 Kh-29T, attack altitude 4,000 m).
- **Scaling:** nothing is per-site; more zones → more rings → more SEAD flights, automatically.
- **Plan shape:** `plan.air_tasking_orders[c].suppression_by_site = { threat id → SEAD flight id }`, `suppression_rotation = { the rotation's SEAD flight ids, in order }`; missions carry `requires_cleared`; rotation flights `rotation = true`; summary `suppression_flights`, `rotation_flights`, `order_steps`, `sites_not_attacked`.

**Defensive air** (air-denial version, sessions 8–9; John: patrols deny own and as much contested airspace as possible and protect the coalition's installations near it; single ships, to watch them):
- **Front stations** (`planStations`):
  - the defended sites are the coalition's catalog targets (not convoys) in the contested airspace or ≤ `defended_depth_km` (60) behind it;
  - greedy: the uncovered site whose 60 km circle holds the most uncovered value, same region only, becomes a station;
  - up to `max_stations` (3), while it covers value ≥ `min_defended_value` (2).
- **Defended zone:** that circle around the covered sites' value-weighted centre, cut short of every enemy threat ring, never below `min_zone_radius_km` (20). Drawn dashed.
- **Orbit:** walked out from the nearest own base of that region toward the zone centre, as far as it stays on own held ground (all three points, per the airspace grid) and out of enemy kill zones. Legs run across the line to the nearest enemy base.
- **Kill zones** (John: SAMs don't fire to their full drawn range, so jets may work close to a ring or a little inside it, just not fly into the kill zone for no reason): patrols and the AWACS keep out of `AIR_DEFENSE.killzone_fraction` (0.85) of each ring, for routes, orbits and zones. Attack flights still route around the full ring + margin.
- **At run time the kill zone depends on altitude** (2026-10-01, `tools\sam_reach.lua`): a site reaches a low flyer much less far than its drawn ring (radar horizon, low envelope). Each medium / long-range recipe has `low_altitude_engage_km` (SA-10 40, Patriot 30, SA-11 25, Hawk 22, IRIS-T 20 (estimated), SA-6 15 (estimated), NASAMS 14); the zone is 85 % of that up to `killzone_low_altitude_m` (300 m above the ground), of the full ring from `killzone_high_altitude_m` (3,000 m), straight between (Kola bug 27, 2026-10-02: were 3,000 / 7,000 m above sea level; the low figure is the radar horizon, so it holds only close to the ground, and a jet 275 m over the Khibiny is over 1,000 m above sea level). Used by the leash, the SEAD rule, the bandit call's kill-zone check and the scrambles' "under enemy SAM cover" (the contact's altitude, made a height above the ground there). Found when the SEAD rule sent MSN5026 home 15 s after takeoff from Vuojärvi, 60 km from a Blue SA-10 whose 120 km ring called it deadly, though flights had used that base all mission unharmed.
- **No AI flight launches from a base inside an enemy site's low-altitude kill zone** (`launchBases`, `underEnemySam`; John: no flights up into instant death). The alert posture uses the same test (it used 85 % of the full ring).
- **Station flights** may fly at most `AIR_DEFENSE.station_enemy_airspace_km` (5) of enemy airspace to their station; otherwise that base doesn't fly it. A base whose route enters any enemy threat ring can't fly the station.
- **Patrol tasking:**
  - rules of engagement `open_fire`, with `EngageTargetsInZone` on the defended zone from the takeoff waypoint, so a patrol in transit defends too;
  - **not `weapons_free`:** in DCS that means engage anything the group detects, and with AWACS datalink patrols chased into enemy SAMs;
  - `may_jettison` is decoupled from rules of engagement, so fighters still drop tanks.
- **Commit circles:** each station also gets circles (`commit_*`: 40 km radius on a 50 km lattice, within 120 km of the orbit) over own and contested airspace, each shrunk until it holds no enemy airspace or kill zone. Patrols carry `EngageTargetsInZone` on each. An enemy jet over contested airspace near a patrol gets engaged; one in its own airspace doesn't. Drawn as faint dotted circles.
- **Rotations:** each patrol is on station 1 h; the next arrives 10 min before it leaves; the first spawns from T+2 min and is on station at ~T+17–24 min. Each rotation comes from the nearest base in its region with reach, free parking, and room under the cap.
- **AWACS, where its coalition fights** (A-50 / E-3A; reworked 2026-10-02 session 18, Kola bug 42 in `closed.md`, not flown: the old orbit, 200 km from every enemy base, put Blue's E-3A 460–550 km from John's Kola tasking in the 19:29 run):
  - **what it should see** (`earlyWarningPoints`, `early_warning_weights`): the contested airspace (sampled every 20 km, weight 1 each), the enemy targets the attacks can reach (× their value), the enemy fighter bases (3 each);
  - **where it may orbit** (`orbitCandidates`): own (not contested) airspace on own ground, every 20 km; at least `AWACS_ORBIT_DISTANCES.enemy_fighter_base_km` from every enemy fighter base and `contested_airspace_km` from the contested airspace (each mission's own, its `data/awacs_orbit_distances.lua`: Kola 250 / 120 since Kola bug 59, 150 / 80 before; Caucasus 120 / 40), the whole race-track `early_warning_map_margin_km` (60) inside the map's edges (`MISSION.map_bounds_m`); the whole race-track `early_warning_clearance_km` (30) outside enemy kill zones; legs across the line to the nearest enemy fighter base;
  - **the orbit:** the candidate that sees the most weight within `early_warning_coverage_km` (250); flown from the nearest base that can reach it (`draftStationFlight`), at T+5 s; a **second** one (`early_warning_max`: Blue 2, Red 1, Russia has few A-50s) where the first leaves more than 30 % unseen and the second would see at least 20 %; no candidate at all: the old orbit (`legacyEarlyWarning`). `dcs.log`: "sees n % of the fight (… unseen before, … after)";
  - **replay of the 19:29 plan:** Blue one E-3A from Evenes seeing 50 % (224 km from Alakurtti and Banak, 296 from Afrikanda; a second would add 18 %); Red one A-50 from Severomorsk-1 seeing 45 %; attack and SEAD flights planned unchanged;
  - feeds AI datalink;
  - **starts in the air on its station** (John, 2026-10-04: neither side would launch without AWACS coverage, so it's in place at mission start; not flown yet): `takeoff = "air"` (`AIR_MISSION_TYPE.airborne_early_warning`), spawned at T+5 s at the start of its race-track at station altitude (9,000 m) and cruise speed, heading down the first leg, with no way out (route: `station` (air start) → `station_end` → home → landing at its base); EPLRS, options, the `AWACS` task and the Orbit all on that first waypoint. Its base is still the one it lands at, chosen as before. Event log: `SPAWNED … in the air on its station, 29,528 ft`. (2026-10-02 to 10-04 it took off from the runway with the `AWACS` task on the takeoff waypoint, Kola bug 38: the E-3A took ~38 min to reach its station.)
- **Alert posture** (`AIR_DEFENSE.alert_posture_planned = true`, `planAlertPosture`): see *Scrambles and the leash*.
- **Mission types:** `combat_air_patrol`, `airborne_early_warning`, `interception`, with `planned_as` (mission / rotation / station / response), per-type `flight_size`, `rules_of_engagement`, `takeoff`, `keeps_gun`, `engage_range_km` (patrols).
- **Loadouts:**
  - Liberation `CAP` for the Russian fighters and F-15C;
  - `dcs:AIM-120C*4, AIM-9X*2, FUEL*3` for the F-16;
  - `liberation:Liberation BARCAP` for the F/A-18;
  - `hand:Clean` for the AWACS types.

**Human taskings** (session 10; `HUMAN_TASKING` in `data/air_tasking.lua`, `planHumanMissions`). John's decisions:
- the mission is also a sandbox: the brief lists the human taskings, and the player picks a base and spawns;
- no assignment or completion tracking yet (the design leaves room for both);
- always 2 human taskings, every mission type allowed; open to every player (2026-10-07, John, multiplayer with an F/A-18 friend: "just have human missions available that we can pick up", alone or together), nobody assigned;
- takeoff 10–20 min after mission start, TOT set by how far the target is.

How it's built:
- **Flight:** each human flight (`flown_by = "human"`, AI flights `"ai"`) is from a held base with a player slot whose aircraft type fits there, taking off `startup_s` (600–1200 s) after start. The player aircraft types are the types in the mission's `PLAYER_SLOTS` (`PlannerPlanAirTasking.playerAircraftTypes`, by name); the flight is planned (route, timing, loadout) for the first and starts at the base's first such slot; any player at the base flies it, in whichever jet (the frag lists every slot there and each type's loadout). `human_missions` lists their ids.
- **Mission types:**
  - strike / airfield strike / DEAD: planned like the AI's, with AI SEAD if the route needs it;
  - SEAD: a site the SEAD rotation opens with (step 1), the player being its SEAD flight in the site table;
  - CAP: the player flies one of the front stations for `on_station_s`.
- **Timing:** the AI SEAD flights a player's strike or DEAD needs are timed around the player (`scheduleHumanPackage`). SEAD that would push the player's takeoff past `startup_s[2]` + 1 min means the mission isn't planned for this player.
- **Fallbacks:** other mission types (types already used go last), then bases another human flight already uses.
- **Not spawned:** human flights aren't spawned or preloaded. Their routes are drawn dashed yellow with a `HUMAN` label.

**Scheduling and results** (`watch\flights.lua`):
- **Spawning:** each flight spawns on the mission clock and is removed 3 min after landing.
- **Logging:** the event log (see *Event log*) catches shots, hits, kills, losses, takeoffs and landings for every unit, and `POSITION` lines every minute; `watch\flights.lua` adds `TARGET` (a mission's target objects destroyed, n of m critical) and the spawner adds `SPAWNED`, `LOADOUT` (the ammo check 5 s after spawn) and `WAYPOINT` (a script command on every waypoint between takeoff and landing).
- **Status:** `RecordFlightLaunches.statusOf` gives planned / airborne / landed / lost for the brief.
- **Datalink** (Kola bug 25, confirmed 2026-10-02): every AI flight gets an explicit group id (700000+) and the EPLRS command as the first task of its first waypoint, as the mission editor does it (plus `setCommand` EPLRS right after the spawn); every AI unit its own Link 16 STN (`AddPropAircraft.STN_L16`, octal from 01000; the player slots use 00201–00211) and the editor's `datalinks.Link16` block. With all of it, friendly AI shows as datalink contacts on a player's HSD.

**Preload** (`execute\preload_aircraft_types.lua`): DCS loads a type's model, liveries and damage model on its first spawn, on the main thread, which froze the sim 2–25 s mid-mission (F-15E 25 s, Su-24M 7 s).
- **Fix:** for every coalition and aircraft type in the plan, spawn one real group 9 km above a base that type flies from, with one unit per distinct loadout (so weapon models load too), then destroy it at once.
- **Cost:** ~13 types in ~18 s at start-up (F-15C 13.7 s, F-15E 2.5 s). No mid-mission freeze since.

### Radar picture (`watch\radar_picture.lua`, `data/radar_picture.lua`)

Built 2026-09-30 (Kola roadmap item 1). Each coalition keeps a picture of the enemy aircraft its own radars report, so scrambles, AWACS calls and later fog of war act only on what the defenders could really know. The script uses it to decide things and gives the AI tasks; it can't add contacts to the AI's own awareness (DCS's built-in datalink already shares contacts between same-coalition AI). **The picture itself only watches and logs:** no orders, no spawns, nothing written to the plan; scrambles and the leash act on it. First DCS run: session 11.
- **Sensors:**
  - **Ground, found once at start:** SAM sites (`early_warning` by layer, otherwise `sam_search`, including each site's `<id>_escort`) and base-defense groups of the `radar_missile_launchers` component (`base_defense`), counted only when a unit carries a radar (`Unit:hasSensors`). Gun fire-control radars don't count (John).
  - **Flights, while airborne:** `awacs`, `patrol`, `scramble`, from the mission type (`RADAR_PICTURE.flight_sensor_kinds`). Attack flights and human flights aren't sensors. `WatchRadarPicture.addFlight` adds a flight spawned at run time (scrambles, item 2).
  - Dead groups drop out, so losing the AWACS thins the picture by itself.
  - On the 14:36 plan: Red 40 ground sensors, Blue 32 (3 Blue escorts without a radar skipped), 22 sensor flights each.
- **Polling:** every sensor once per `poll_interval_s` (30 s; John: plenty often, also for AWACS calls), spread over 10 steps 3 s apart. `Controller:getDetectedTargets(RADAR)` only, never `DLINK`.
- **Contacts:** one per enemy group, updated at the end of each round:
  - `group`, `category` (`airplane` / `helicopter`), `first_seen`, `last_seen`, `seen_by` (sensor kind → count), `state` (`tracked` / `stale`);
  - `pos`, `altitude_m`, `heading_deg`, `speed_mps` (`getPoint` / `getVelocity`);
  - `type_known` (this round), and `type` only once some sensor knew it (it stays after that);
  - `range_known` (false = bearing only);
  - `airspace` (`Airspace.kindFor`), `nearest_base` / `nearest_base_km` (own held base), `inside_own_sam_ring` (site id);
  - **`inbound`, `threat_asset`, `threat_minutes`:** the contact's heading line passes within `threat_pass_km` (30) of an own asset (a held base or a catalog target) ahead of it, at more than 50 m/s; the soonest such asset and the minutes to it. One definition for the scramble trigger and the leash's "heading away". (The first version used "heading within 60° of the nearest own base", which called a raid flying past that base toward Olenya "heading away": found in the scramble harness.)
- **Memory:** stale after 60 s unseen (two missed rounds), dropped after 300 s.
- **Events** (`RecordRadarPicture.on(coalition, event, fn)`), fired once per round, each listener run under `pcall`: `new_contact`, `airspace_changed` (extra = the airspace before), `contact_stale`, `contact_dropped`, then `picture_updated` once the round is complete (scrambles and the behaviour rules run on it).
- **Calls:** `contacts(coalition, filter)`, `contactsNear(coalition, pos, radius_m)`, `contact(coalition, group)`, `sensors(coalition)`. Contacts come back as kept: read them, never change them.
- **Test aids for the first DCS run** (`log_radar_tracking`, `count_missiles`): the first time a ground sensor's radar tracks each enemy group (`Unit:getRadar`), and the number of missiles the radars listed since the last summary.
- **What the first DCS run showed** (session 11, ~48 min): 32 Red / 34 Blue ground sensors, every sensor answering every round.
  - **Missiles are listed, but rarely:** 2 in one 5-min window while many were fired. Not reliable for air-to-air missiles; cruise missiles still to test (item 6).
  - **`getRadar()` works:** `SAM_ENON_SA11_1` tracking the Su-33, `SAM_ALTA_SA11_1` tracking the F-15C.
  - **Type known** for 6 of 16 new contacts.
  - **Bearing only** once: the F-15C, which carries an internal jammer in DCS. A good sign that DCS reports jammed contacts as range-unknown (optional jamming item).
  - **Low flyers:** the AWACS picked up aircraft at 1,100–4,500 ft from 160–210 km. Most first detections were 120–210 km out, which roughly fits the 15-min scramble warning.
  - **No flicker:** 0 "regained" lines; contacts went stale, then dropped.
  - A wreck can be seen once more after the kill (MSN5901_SCRAM), so a leash reason can read "heading away" instead of "destroyed". Wording only.
- **Offline harness:** `radar_picture_harness.lua` (session scratchpad; not kept) ran the module on the real 14:36 plan with stubbed radars: one Blue jet from Rovaniemi to Olenya, seen from T+60 to T+700. New at T+90, four airspace changes, stale at T+780, dropped at T+1020, a failing listener caught, missiles counted, the tracking line logged.

### Scrambles and the leash (the controller: `controller\air_flights\scramble_fighters.lua`, `controller\air_flights\assign_alert_jets.lua`, directive `leash`)

Rebuilt 2026-09-30 (Kola roadmap item 2; design agreed with John, recorded there). Moved under the controller on 2026-10-01 (Kola roadmap item 11), unchanged in what it decides: the decisions in `scramble_fighters.lua`, the alert jets' state (ready, cooldown, turnaround, which scramble came from which base, held spots) in `controller\air_flights\assign_alert_jets.lua`, bookkeeping only; `consumers/run_scrambles.lua` is gone. Its lines are `CONTROL` lines: `scramble`, `no scramble`, `stand down before launch`, `alert`, `leash home`, `leash stand down`. A scramble answers an immediate threat: it burns straight at the one raid it was sent after and chases it away or kills it, without flying head first into enemy airspace. First DCS run: session 11.

**Alert posture** (`planAlertPosture`, `AIR_DEFENSE`):
- **every** held base whose runway and parking fit an interception type (`COALITION_AIRCRAFT[c].interception`; John, 2026-10-02, Kola bug 16: until then the `alert_bases` (3) nearest the enemy plus the nearest of each other region, which left Finnmark with none). On the 10:38 roll: Blue 17, Red 11;
- **not a base inside an enemy kill zone** (found in the harness: Vuojarvi under a Blue ring had no way out that didn't start in the kill zone);
- **3 alert jets per base** (`alert_aircraft_per_base`), 15 min cooldown between launches. A jet that lands is back on alert `scramble_turnaround_s` (30 min) later; one shot down is gone for the mission (John, 2026-09-30: a base shouldn't run out if its jets came back; replaced the first version's fixed 3 launches, which ran Red dry ~1.5 h into the first run). `plan.air_tasking_orders[c].alert = { bases = { { base, code, region, aircraft, pos, enemy_km, alert_aircraft, cooldown_s, spots } }, max_airborne_aircraft, first_number }`.
- **Alert spots** (2026-10-01, Kola bug 7): the posture is planned before the patrols, and each alert base holds `alert_aircraft_per_base` ramp spots for the whole mission (`reserveAlertSpots`: free of statics, player slots and planned flights, a terminal type every interception type there fits, nearest a runway). No planned flight gets them; scrambles spawn only on them. A base that can't spare them isn't an alert base.
- Session 11's roll: Red Alakurtti, Koshka Yavr, Banak; Blue Kuusamo, Ivalo, Vuojarvi.

**Trigger** (every radar-picture round):
- a tracked contact with a known range, not a helicopter, that is over own airspace, or that the picture has inbound on an own asset it will reach within `scramble_warning_min` (15) minutes for `scramble_inbound_rounds` (2) rounds in a row, in whatever airspace it is now; a contact still over its own airspace needs `scramble_inbound_rounds_enemy_airspace` (8, 4 min, longer than a race-track leg; Kola bug 3, built 2026-10-06, not flown), and a turn away resets the count;
- **refused** (logged once per reason, checked again every round) when a live scramble is already after it, when an airborne patrol's defended zone or commit circle covers where it is, or **while it is inside an enemy kill zone** ("under enemy SAM cover": the leash would only bring the fighter home again; found in the harness, where a raid loitering under Blue SAMs burned 4 launches in 15 minutes).

**The raid:** the trigger plus the other contacts within `raid_radius_km` (20) on a heading within `raid_heading_deg` (45); one scramble takes them all, `EngageGroup` on each, in order.

**The base:** the nearest ready alert base in the region facing the raid (`Airspace.facingRegion`) whose intercept point is in reach and at least `scramble_min_leg_km` (10) out, that gets there before the raid reaches what it threatens (the mean reaction delay + `scramble_takeoff_s` 150 s + the dash, against the raid's `threat_minutes`; John, 2026-10-01), with a free alert spot; never over `max_airborne_aircraft`: the planner keeps `scramble_reserve_aircraft` (2) of it free (2026-10-01; it used to allow `scramble_over_cap`, 2 over). The intercept point is the raid pushed ahead along its heading by the scramble's flight time, pulled back in 5 km steps until it lies in own or contested airspace and `scramble_killzone_margin_km` (10) outside enemy kill zones (Kola bug 8, 2026-10-02: on the line itself, the leash sent MSN2902 home 19 s after it got there). **No tail chases** (Kola bug 16, 2026-10-02): a base the raid is flying away from (its heading more than `scramble_tail_chase_deg`, 100°, off the line from the raid to the base) doesn't answer. A refusal gives the reason of the ready base nearest the raid, `<base>: <why>` (Kola bug 23).

**The launch:**
- after `scramble_reaction_s` (60–120 s, cockpit alert), **hot on one of its base's alert spots, never the runway** (John: no spawning on top of jets lined up there): the first of the base's `spots` that `Airbase:getParking(true)` reports free. If the raid is gone by then, or no spot is free, the scramble is **stood down before launch** and its jet stays on alert. A jet the leash stands down on the ramp is back on alert at once (`ControllerAssignAlertJets.stoodDown`);
- **the session 7 fixes:** `EngageGroup` on the takeoff waypoint, so it's active from wheels-up and the AI flies its own intercept (it used to sit on waypoint 2, the intruder's position at launch, and DCS starts a waypoint's tasks only on arrival); waypoints at the profile's `dash_speed_mps` (F-16 / F/A-18 325, F-15C / Su-27 / Su-30 / Su-33 355, MiG-31 440 m/s) with afterburner explicitly allowed (option 16 false), instead of `speed_locked` at cruise speed; `open_fire`, no `EngageTargets` on everything; one-ship, `interception` loadout, gun kept, may jettison;
- then `ControllerScheduleFlights.track`, `WatchRadarPicture.addFlight` (its radar joins the picture) and `ControllerDirectFlights.watch(m, { targets })` (mission type `interception` gets the `leash` directive).
- Ids `MSN2901_SCRAM+` / `MSN7901_SCRAM+` (Red was `MSN5901+` until 2026-10-02).

**The leash** (`AIR_CONTROL.leash` in `data/air_control.lua`), checked every picture round per watched flight:
- **home** when every raid group is dead, dropped from the picture, or back over its own airspace **heading away** (not `inbound`; a raid that only dips over its own airspace on the way in is still a raid); or when the scramble itself is more than 5 km into enemy airspace (distance to the nearest contested cell) or inside an enemy kill zone (85 % of a live medium / long-range ring);
- **stood down** (the group removed) if the raid is gone before it leaves the ramp;
- going home: `Controller:setTask` with a new airborne mission (from where it is to a landing at its base, cruise speed) and rules of engagement "return fire". Once sent home it isn't watched any more; the scheduler removes it after landing. Fuel is DCS's (bingo).
- `RecordWatchedFlights.onTask(id)` tells scrambles whether a flight is still hunting.

**Offline harness** (`scramble_harness.lua`, session scratchpad; not kept): real 14:36 plan with air tasking re-planned, the real picture, rules, scrambles and aircraft spawner over stubbed DCS; one Blue jet Rovaniemi → Olenya. Checked: the spawned group (hot ramp start, `EngageGroup` on waypoint 1, afterburner option, dash speed and interception altitude on waypoint 2), the leash's `setTask` / return-fire option, stood down before launch, patrol cover, SAM cover, and the kill-zone leash when the scramble chases into Blue's rings.

**First DCS run** (session 11, ~48 min, watched): Red decided 6 scrambles, Blue 4.
- **Burning straight at the raid works:** John: MSN2901 and MSN5902 "did exactly what we wanted as a scramble", though MSN2901's path looked a little odd (its intercept point was 239 km out; once airborne the AI flies its own intercept geometry).
- **Kills:** scrambles scored 4 kills for 2 losses. MSN2901 (F-15C) killed a Su-33 patrol with an AIM-120 fired just before the kill-zone leash sent it home; MSN5901 (Su-30) killed both F-16s of a Blue DEAD; MSN5903 (Su-27) killed a SEAD F/A-18, then fell to a Blue patrol.
- **Every leash reason fired:** kill zone, target destroyed, target lost from the picture, heading away; plus stood down on the ramp (MSN2904) and stood down before launch (MSN5904, MSN5906).
- **`setTask` home lands them:** MSN2902 was sent home just after takeoff (its target was already gone), circled in the landing pattern and landed 5 min later (John agreed: going home is right when the target is gone). MSN2901 landed ~17 min after its leash.
- **Refusals:** "under enemy SAM cover" 7 times (mostly Blue patrols orbiting under Blue SAMs), "covered by patrol" twice. A scramble at an enemy patrol that looks like a raid is fine (John: Blue can't know a jet's intentions).
- **Budget:** the first version's 3 launches per base would have run Red dry ~1.5 h in → alert jets now return after landing (above).

### The controller (`controller\air_flights\`, `data/air_control.lua`)

Built 2026-10-01 (Kola roadmap items 4 and 11; design agreed with John the same day), not run in DCS with a fight yet. **Every decision after the plan is made and the mission has started about what AI flights do lives here** (John: no code all over the place serving that function): which flights launch when (`decide_launches.lua`: packages in sequence, waits, retries, cancels, late launches, and the airborne cap, one count for planned flights and scrambles alike), scrambles (`scramble_fighters.lua`, with the alert jets' bookkeeping in `controller\air_flights\assign_alert_jets.lua`), and what flights in the air are told (the directives). The plan says what should fly; the scheduler keeps the clock and the record and asks the controller when a flight is due (`ControllerDirectFlights.due`), then carries out what it decides (`launchNow`, `flyAgain`, `lookAgainAt`, `note`); the radar picture is what the controller knows. **One event word, `CONTROL`,** for every decision, the decision first (John: grep `CONTROL` to see what this layer is doing): `watching`, `defend`, `back on mission` / `back on way home`, `leave threat`, `go cold`, `leash home`, `leash stand down`, `scramble`, `no scramble`, `stand down before launch`, `alert`, `wait`, `retry`, `cancel`, `launch late`. **DCS AI is the pilot**: once it has a directive it flies, evades, shoots and goes home at bingo by itself. What it lacks is someone watching the whole picture and making the calls ("bandit, hot, commit", "go cold", "RTB"); the controller does that, one per coalition (John: controller-heavy, no separate pilot rules).
```
 what is known ──► situation per flight ──► directives ──► one intent ──► orders
 radar picture,     assess_flight_          directives_     coordinate_     give_orders
 the flight's own   situations              per_flight      flights         (only when the
 state, the plan                                            (who takes      intent changes)
                                                            which threat;
                                                            priority)
```
- **Watched flights:** every AI flight whose mission type has directives (`AIR_CONTROL.directives_by_mission_type`: strike, airfield strike and DEAD → `self_defence`; SEAD → `suppression` + `self_defence`; interception → `leash`; patrols → `handover`; every one of them, and the AWACS, also → `landing`), from spawn (`ControllerDirectFlights.watch`, called by the scheduler and the scrambles) until it lands or is lost.
- **Added 2026-10-02 (not flown):**
  - `handover` (Kola bug 18): a patrol goes home (`CONTROL … handover`) once a later patrol of its station is on task within 15 km of the race-track. Since Kola bug 62 (2026-10-06, not flown) the relief must also have reached its station waypoint (`w.on_station_at`; a patrol spawned in the air on its station counts from its spawn).
  - `landing` (Kola bug 19): a flight on its way home (sent home, a jet landed, or past its planned landing) whose jet gets 20 km farther from its base than its closest since, or still up 20 min past its planned landing, gets a landing order straight to its base (`CONTROL … land`, intent `land`, priority above `home`; at most 2; never while a jet of it is on the ramp). A jet still in the air 8 min after its flight's last landing (an orphaned wingman: about half of them never leave their hold and ignore landing orders, 19:29 run) is removed and counted as landed (`CONTROL … >>orphan<< removed`, intent `remove`, the highest priority; 2026-10-02, not flown). Bug 68 (2026-10-06, not flown): a jet deaf to its landing orders is removed the same way when, `orphan_remove_after_s` (8 min) after its last one, it is still `away_km` (20) farther from its base than its closest since that order; no landing in its flight needed.
  - `suppression` also says `no shot` once, 2 min after the launch point with every missile aboard (Kola bug 29).
  - `ControllerDirectFlights.unarmed` (Kola bug 6): jets that spawned with no weapons are removed on the ramp (`CONTROL … stand down`).
  - Packages: a suppression flight off its attack and past its planned landing counts as landed for the wait (Kola bug 19).
- **The situation** (`watch\flight_situations.lua`): facts about one flight at one check, worked out only when a directive asks: position and airborne, velocity, air-to-air missiles aboard (all, radar-guided, the longest-reaching radar missile), anti-radiation missiles aboard, threats (enemy airplanes the picture tracks within the 100 km warning range, plus whoever just fired at it at any range, with live range, aspect and closing speed), the last missile fired at it. Directives never ask DCS themselves.
- **Directives** (`controller\air_flights\apply_directives.lua`) each return an intent: `home`, `stand_down`, `defend`, `resume`. Each runs on a clock: the radar picture's round (30 s: `leash`, `suppression`) or the fast check (`AIR_CONTROL.check_every_s`, 5 s: `self_defence`). `leash` and `suppression` are the old rules, moved over unchanged; they stop once a flight is sent home (`on_task_only`), `self_defence` doesn't.
- **One intent per flight:** the highest of `AIR_CONTROL.intent_priority` (stand down > home > resume > defend). **Across flights** (`coordinate_flights.lua`): one enemy group is taken by one flight only, nearest first; a flight already fighting one keeps it.
- **Orders** (`execute\air_flight_orders.lua`), only when the intent changes: home = `setTask` with a route home (a SEAD flight turns around and goes back the way it came) and return fire; defend = `pushTask` of an `AttackGroup` on the threat inside a `ControlledTask` that stops after `max_engage_s` or when its own user flag is set (flags 9100000+); resume = set that flag. Never `popTask`: if DCS had already dropped the fight (target destroyed), it would pop the mission itself. A flight going home that defends gets open fire for the fight.
- **Reports:** a missile fired at a watched flight (`S_EVENT_SHOT`, its target in the flight) runs its coalition's fast check at once, and the shooter counts as a threat whatever its heading.
- **Self-defence: the bandit call** (rebuilt 2026-10-01 after the 20:31 run; John: "you would tell them immediately a fighter is inbound … if you know they have the weapons to engage, you tell them, if you know they don't, you tell them to leave"). The controller decides the moment the picture shows a **bandit**: an enemy airplane it tracks within `warning_range_km` (100) that is pointed at the flight (within `hot_aspect_deg` 45) and closing (≥ 50 m/s) on `hot_checks_before_call` (2) fast checks in a row (so a patrol's race-track leg swinging past doesn't count), or one that fired at the flight in the last 30 s **at any range** (the shot gives it away, picture or not).
  - **A SEAD flight with its anti-radiation missiles aboard isn't the air-to-air asset** (John, 2026-10-02, Kola bug 39: in the 17:15 run fights cost 6 SEAD jets, sent one SEAD flight home 82 s after takeoff and broke a salvo off after 3 of 8 missiles): it commits only when fired upon, or, outside its shot area, when the bandit is hot inside `sead_commit_km` (25); otherwise `CONTROL … press on: bandit …; staying low on its route` (or `finishing its salvo first`), once per bandit. After its salvo it's an ordinary flight.
  - **Can fight** (radar-guided air-to-air missiles aboard; infrared ones alone don't count, John): `defend` at once, an `AttackGroup` on the bandit; the DCS AI flies the intercept and shoots when its own missiles allow. After the fight it always carries on with its mission (John: "that's what they are there for after all").
  - **Can't fight** (infrared missiles only, or none: the Su-24M, the Tu-22M3): `leave`, sent home (John: the patrol isn't going anywhere, it stays on station and circles). A flight already going home isn't sent again.
  - The fight ends (`back on mission` / `back on way home`) when the bandit is destroyed, dropped from the picture (not while it fired at the flight in the last 30 s, Kola bug 30), beyond 100 km, turned cold (aspect > 110°), after 3 min, when the flight is out of radar missiles, or when the fight takes it into an enemy kill zone its route doesn't pass through on purpose (an enemy airfield's Tor / Pantsir included, Kola bug 41; a SEAD flight: any kill zone at its height outside its shot area, its own target's included, and none inside it); then it may engage again after 30 s, but not the bandit it broke off from while it is still inside a kill zone. `CONTROL` lines `defend`, `leave`, `back on mission` (or `back on way home`), `leave threat`.
  - **Why** (20:31 run, `event_logs\2026-10-01_203147.log`): the first version engaged only inside 0.6 × its own missile's range (21 km with the R-27R) and looked no farther than 1.5 × that, so the F-15C patrol MSN2002_CAP's AIM-120 shot at MSN5024_SEAD from 47 km went unanswered; `defend` came at 19 km, a second after the lead was hit, and both Su-34s died. Red's picture had held the F-15C the whole time.
- **Harness** (`controller_harness.lua`, session scratchpad, not kept; 40 checks after the bandit call): a MiG hot at 120 km ignored, at 90 km called on the second hot check and engaged at once, the farther strike leaving it to the nearer, cold → flag set, held 30 s, engages again, destroyed → back on mission; a crossing Su-27 ignored until it fires (wake at once); an infrared-only strike and a strike with no air-to-air missiles leave (once), a fighter hot for one check then turning across not called; a shot from 130 km by a group not in the picture engaged at once; a SEAD out of HARMs sent home, then defending with open fire; the leash's stand-down and home; a landed flight unwatched.
- **Item 11 checks** (same harness, with the real scheduler): a patrol due late launched on spots free now (`launch late`); a SEAD on time launched and watched; a SEAD whose site is already dead not sent; a strike waiting while its SEAD is up, its SEAD flown again when it is gone, the strike cancelled when that fails too; a scramble decided, launched and leashed; the last alert jet committed, stood down before launch and refunded, then spent on the next raid; "no alert base with a jet ready" said once; a landed scramble back on alert in 30 min. A smoke run on the 16:21 plan (`real_plan_harness.lua`): 2 h of mission clock, 23 flights launched, no errors.
- **To check in the next DCS run:** that `AttackGroup` pushed on top of a mission really engages an air group from ~100 km (the AI flies the intercept), and that the user flag ends it and the flight resumes its route and attack; that `leave` turns a bomber home before the fighter reaches it. (DCS does give `rangeMaxAltMax` for air-to-air missiles: 35 km for the R-27R, 20:31 run.)

### Air picture calls (`inform\screen\air_picture.lua`, `data/air_picture_calls.lua`)

Built 2026-10-02 (Kola roadmap item 5, text first; `closed.md`), first flown in the 00:57 run: the calls looked right and magvar works in the game. John's calls: no bullseye ("kind of a pain"), every bearing from the player's own position, no "bogey dope" to ask for; all known contacts in one list, highest threat to the player first; every 2 min, 14 s on screen (7 until John raised it the same day), short lines read at a glance (John's format, same day); only what the player's own coalition's radars see (`WatchRadarPicture`).
- **Who gets it:** every player in an aircraft (`coalition.getPlayers`), on the ground too (`on_the_ground`), one list per group from its first player; `outTextForGroup` for `show_s` (14) every `call_every_s` (120); other texts stay on screen.
- **The list:**
  ```
  DARKSTAR picture, 4 groups
  MiG-29S - 110/120nm, 10k, hot, 0s
  Su-30 - 255/?nm, low, flank SE, 0s
  MiG-31 - 343/60nm, 30k, beam E, 70s
  unknown - 027/40nm, 25k, drag NE, 0s
  ```
  Type (once any sensor identified it, else `unknown`) - magnetic bearing / range (`?` when no sensor knows it, e.g. a jammer), altitude in thousands (`low` under 1,000 ft), aspect from the contact's heading against the line to the player (hot ≤ 30°, flank ≤ 70°, beam ≤ 110°, else drag; flank, beam and drag carry the contact's track as N / NE / …; `slow` under 20 m/s), and how old the position is (seconds since a radar last saw it: under 30 while tracked, more once stale). At most `max_groups` (10) lines, then "+N more"; `clean` when the picture is empty. Header callsign per coalition (`DARKSTAR` / `OVERLORD`).
- **Threat order:** range × `threat_range_factor` by aspect (hot 1, flank 1.5, beam 2, drag 3), smallest first.
- **Coverage** (2026-10-02 session 18, Kola bug 42, not flown): a player outside every live sensor's reach gets `DARKSTAR: no radar coverage your area, picture unknown` (or `…, 3 groups; no radar coverage your area`) instead of a picture that only looks clean (`PICTURE_CALL … nothing; no radar coverage`). Reach at the player's height above the ground (`AIR_PICTURE_CALLS.coverage`): an AWACS 250 km, a patrol or scramble 80 km, a ground radar its type's `detection_m` (at most 300 km), each no farther than the radar horizon (4.12 × (√h₁ + √h₂) km, a ground antenna 10 m up). Tune from the `CONTACT` lines, which now say how far away the first sensor saw each contact ("seen by awacs MSN2001_AEW 212 km away").
- **Bearings:** magnetic as DCS works it out: the grid bearing (map x / z) minus the variation at the player (Kola bug 61, 2026-10-05: the F-16's HUD and the F10 ruler take grid north as true north; our earlier bearing from true north was off by the grid's convergence, ~1° at Kallax, ~6° near Ivalo, ~9° toward Murmansk). The contacts' tracks and the airfield brief's wind and runway numbers the same way. No per-map setting: the convergence only grows with distance from the map's central meridian. Variation from DCS's `magvar` module (`require "magvar"`, `get_mag_decl(lat_deg, lon_deg)` in radians, `init(month, year)`: what the mission editor and the DTC use). In `luae` it loads but answers 0, so a start-up self-test at the mission's check airbase (`MISSION.magnetic_variation_check_airbase`; Kola: Rovaniemi) drops it when it answers near 0 and uses the mission's approximate table by longitude (`MISSION.fallback_magnetic_variation`; Kola: Bodø +5° … Murmansk +16°). `dcs.log` (grep `air picture`) says which one is used, and both values at the check airbase.
- **Facts and text apart** (`describe` vs the text functions): `InformRadioRadioCalls` speaks the same facts (*Radio calls*); each call hands its groups to `InformRadioRadioCalls.picture`, and `InformScreenAirPicture.pictureFor(side, unit, quiet)` is open to it for threat calls.
- **Tracked contacts only, and their true age** (Kola bug 61, 2026-10-05): a stale track (no radar has seen it for `RADAR_PICTURE.stale_after_s`, 60 s) isn't called, on screen or on the radio (John: no reason to hear 5 min old contacts; they were often jets already shot down or landed). The age said runs from when a radar read the position (`pos_seen_at`), not from the round's end (it was ~27 s short).
- **Event log:** `PICTURE_CALL`, one line per player per call: the number of groups and the first one's line.
- **To check in the first run:** that magvar works in the game (`dcs.log`), bearings and ranges against the F-16's HSD, whether 14 s is long enough to read the list.

### Radio calls (`inform\radio\radio_calls.lua`, `data/radio_calls.lua`, `radio_calls/`)

Built and flown 2026-10-05 (Kola roadmap item 7's MVP; John: "working, and is awesome"). Darkstar speaks: the air picture's calls and immediate threat calls, phrased from a phrase bank, in a Windows voice, with a radio sound, played to Windows' default output. Blue only, each player called by their jet's callsign from the mission file (since 2026-10-07, John set one on every F-16 slot: `Unit:getCallsign()` "Python11" said "Python one one", `InformRadioRadioCalls.playerCallsign`; `RADIO_CALLS.player_callsign`, "Snake one one", when a jet has none; before that it was every player's). The AI pilots and the airfields joined later the same day, on their own channels (below, *AI pilots and airfields talk*); this first part describes Darkstar's calls and the programs as the MVP built them, with the changes noted there. The on-screen list is unchanged. How to start, watch and test it: the repo's `README.md`, *Mission radio calls*.

```
mission (Lua) --JSON line--> helper -----------> phrase bank --> Windows voice --> radio player ----> headphones
inform\radio\radio_calls.lua  mission_calls.jsonl  speak_mission_calls.py  (Zira, SSML)   127.0.0.1:47110
```

- **In the mission** (`InformRadioRadioCalls`):
  - **picture:** every on-screen picture (every 2 min, `InformScreenAirPicture`) is also written as a call: `picture` with up to 10 groups' facts (type, magnetic bearing, range nm, range known, altitude ft, aspect, track, seconds since seen), or `picture_clean`, or `no_coverage`;
  - **threat:** on each radar-picture round (30 s), per player, the highest-threat group that is hot with a known range inside `threat_nm` (40) is called at once; the same group to the same player again only after `threat_repeat_s` (180). Event log `PICTURE_CALL … threat: <type>, <brg>/<nm>nm, <ft> ft, hot`;
  - each call is one JSON line (`call`, `to`, `player_group`, `groups`, `mission_time_s`) in `RADIO_CALLS.calls_file` (`radio_calls/mission_calls.jsonl`, git-ignored), emptied at mission start; the mission never waits on anything outside DCS;
  - at start: `os.execute('start "" /min "…\radio_calls\start_radio_calls.cmd"')` (returns at once); `RADIO_CALLS.enabled = false` turns it all off.
- **The helper** (`speak_mission_calls.py`): reads new complete lines every 0.2 s (starts over when the file is emptied; a file untouched for 60 s at start is a past mission's and skipped); words each call (`phrase_bank_wording.py`), speaks it (`windows_voice.py`), sends it to the player. One copy at a time (holds port 47111); `--exit-with-dcs` closes it once `DCS.exe` is gone. Logs every call's words and wording / voice time to its window and `speak_mission_calls.log` (rewritten each start). Reads `awacs_phrases.json` once, at start.
- **The radio player** (`radio_player.py`): 127.0.0.1:47110; a call = one TCP connection, a JSON header line (`speaker`, `frequency`, `audio_bytes`, `sent_at`, `urgent`, `replaces`, `expires_s`) then the WAV. Plays one at a time with `winsound`. Threat calls are `urgent` (before anything waiting), a picture `replaces` the same player's older picture not yet played, `expires_s` drops old news (picture 90 s, threat 30 s). One copy at a time; `--exit-with-dcs`.
- **The radio sound** (`radio_sound.py`, every number in `radio_sound_settings.json`, read fresh per call): mono at 11,025 Hz, band-pass 300–3,000 Hz (2 stages), +4 dB at 1,800 Hz, soft-clip drive 3, hiss, a key-up click and squelch tail, volume 0.4 (0.8 until 2026-10-05 evening; John: a little too loud, halved). ~0.4 s for a 13 s call. John: "sounds great".
- **The voice** (`windows_voice.py`): PowerShell System.Speech → WAV, ~0.3–0.5 s a call; SSML, `{pause}` = 400 ms. Only David and Zira are open to System.Speech (Mark is a OneCore voice). Darkstar: Zira, rate 1 (`awacs_phrases.json`, `controller`).
- **The wording** (`phrase_bank_wording.py` + `awacs_phrases.json`):
  - **Fixed in code (brevity):** a group is always bearing, range, altitude, aspect, then who it is; bearings digit by digit with "niner" (000 is "three six zero"); ranges over 100 nm to the nearest 5; never "angels" for an enemy (thousands, or "low" under 1,000 ft); the first `groups_in_full` (3) groups in full, the rest summed up by count, direction and nearest range ("plus three more groups northeast, beyond one hundred", "scattered" when spread over 60°); direction labels ("northeast group") only when every group has its own direction, else numbers.
  - **From the data:** every flavour piece is a weighted list (openings, counts, labels, BRAA forms, aspect words, declarations, stale tracks, more groups, closings, clean, no coverage, threat openings and closings) with optional conditions (`one_group`, `several_groups`, `busy` 4+, `close_hot` the first group hot inside 40 nm, `type_known`, `type_unknown`, `stale` 60 s, `scattered`); styles chosen once per call so a call never mixes them (range "one twenty" / "one two zero" / "a hundred twenty", altitude "twenty-five thousand" / "two five thousand", NATO name / designation, direction / number labels); NATO names per DCS type (a type not listed is spoken from its name: Su → Sukhoi …); `pronounce` (BRAA → "brah").
  - **Repeats:** a phrase used last time keeps a quarter of its weight, the time before half; saying nothing is never held back (before the fix, recent phrases were barred, which flattened the weights: "that's all I have" came 17 % of the time, meant 6 %).
  - **Checked at load:** every placeholder and condition; a typo stops the helper at start, not mid-call.
- **Tests without DCS** (`radio_calls/`): `play_sample_awacs_calls.py` (seven made-up calls through Zira and the player; `--repeat`, `--only`, `--text-only`), `send_radio_call.py` (any text or WAV), `phrase_bank_wording.py` (checks the file, prints samples).
- **Multiplayer (not built):** over ZeroTier; the host words each player's calls, the friend's PC runs only the radio player (Kola roadmap item 7).

**AI pilots and airfields talk, on channels the jet tunes** (Kola roadmap item 7, steps 5–9; built 2026-10-05 late, harness-tested; first heard in the 21:02 test below, flown in the 2026-10-06 00:16 run). The design and John's decisions: Kola's `roadmap.md`, item 7, *Flights and airfields talk*.
- **Callsigns** (`tools\flight_callsigns.lua`, `data/flight_callsigns.lua`): every AI flight gets one when planned (`commitFlight`: `m.callsign`, `m.callsign_number`), a scramble when decided, a SEAD retry (`_AGAIN`, `_LATER`) when flown: the same name with a new number. Names by mission type (Blue SEAD "Weasel", AWACS "Darkstar") or aircraft type (Viper, Hornet, Eagle, Dude, Bone, Hawg; Red: Sokol, Berkut, Rubin …), numbers 1–9 per name then the next name; the numbers given are kept per coalition in `air_tasking_orders[c].callsign_numbers`, carried on at run time (`RecordCallsigns.start`). Shown with the id ("MSN2025_SEAD Weasel 1") in the brief, the air tasking order menus, the map labels, *Airfield info*, the event log's `SPAWNED` and plan lines, `dcs.log`'s flight list. Players have none (still "Snake one one").
- **Channels** (`RADIO_CHANNELS`, each mission's own `data/radio_channels.lua`, clear of its map's tower frequencies; Kola below, Caucasus UHF 272.000 / VHF 143.000): AWACS UHF 262.000 (Darkstar, check-in / out), mission VHF 140.000 (tactical calls), each Blue field its tower VHF from the map (`data/airfield_frequencies.lua`, generated by `map_data_tools/airfield_frequencies.py` from `Mods\terrains\<map>\radio.lua`, keyed by airbase id; 35 fields, the rest 122.800). Every call carries `channel`, `frequency_mhz`, `priority` and `expires_s` (`RADIO_CALLS.kinds`). Frequencies in the start text, the frag (`RADIO` line) and *Airfield info* ("Traffic calls: VHF 128.200").
- **The watcher** (`inform\radio\flight_calls.lua`, `InformRadioFlightCalls`): beside the controller, reads only. DCS events: takeoff → `airborne` (AWACS; a scramble's says its raid's type as `target_type`, worded as a NATO name or designation, "intercept on the Fullback", or "scramble, intercept" when unknown, Kola bug 65); shot → `fox` (1 / 2 / 3 by guidance: semi-active / IR / active), `magnum` (radar-passive), `rifle` (other air-to-ground missiles), `bombs`, folded per flight (`fold_s`); a missile fired at a jet → that jet `defending` (SAM or missile); kill of an aircraft → `splash`; a jet lost → `jet_down` by a jet still flying (`ejected`). Its waypoints: `pushing` (the ingress waypoint reached; a SEAD flight's first low-level or descent one). Every `watch_every_s` (5): `on_station` (a patrol at its station waypoint; by distance until Kola bug 62, 2026-10-06), `winchester` (no weapons left once it had some), `bingo` (fuel ≤ 15 % and ≥ 60 km from home; only flights the controller doesn't watch for fuel, i.e. not patrols and scrambles; both on AWACS since 2026-10-06, and neither once the pilot has reported it, step 15), `off_target` (mission) + `check_out` (AWACS) when seen heading home (within 35° of the bearing to its landing base, closing ≥ 0.5 km a look, ≥ 15 km nearer than its farthest point; a patrol only once it has left its station: sent home by the controller or at its off-station waypoint, then with no distance from its base needed, Kola bug 62; a scramble's has its own wording, "terminating" / "off intercept", not "off target", Kola bug 64). Players' and AWACS flights don't talk. Event log `RADIO_CALL`.
- **Airfield traffic** (`inform\radio\airfield_calls.lua`, `InformRadioAirfieldCalls`): AI flights at Blue fields, one call per flight per phase by its first jet: `taxi` (a jet born on the ramp moving ≥ 3 m/s; runway in use for the wind), `departing` (lined up on a runway, event log `LINE_UP`, at takeoff only when the line-up wasn't seen, Kola bug 67; the runway it is on, bound for its first leg), `inbound` (≥ 5 min after takeoff, coming back to land: seen heading home or ≤ 130 m/s and ≤ 1,500 m; heading for its landing base inside 10 nm), `final` (after inbound; inside 9 km, ≤ 700 m above the field, ≤ 110 m/s, within 20° of a runway end, the field ahead), `clear` (25 s after its first touchdown). Only with a player within `airfield_range_nm` (40) of the field. Runways from `InformScreenAirfieldInfo.runwayFor` / `runwayInUse` (grid − variation, as the F-16). A retry's or scramble's taxi isn't called (its record comes after its birth event). Event log `RADIO_CALL`.
- **The helper** routes each call: Darkstar's kinds to `phrase_bank_wording.py`; pilot and airfield kinds to `flight_phrase_wording.py` with `pilot_phrases.json` / `airfield_phrases.json` (each call kind a list of parts, each a weighted, conditional list; the placeholders and conditions per kind in `CALLS`, checked at load; callsigns digit by digit, runways "three two", SAM names "S A ten"). A pilot's voice from `pilot_phrases.json` `voices`, picked by the jet's callsign (`crc32`), never Darkstar's; System.Speech ignores SSML pitch, so each voice entry has a `pitch` the radio sound applies by playing it faster / slower (`radio_sound.make_radio_call(pitch=…)`). Voices from both Windows engines (`windows_voice.py` speaks each through whichever lists it: System.Speech for "… Desktop", the newer Windows.Media.SpeechSynthesis, "OneCore", through PowerShell's WinRT for Mark and others, ~0.7 s a call): four David and four Mark variants for now (2026-10-05). John installed Ryan, Andrew, Prabhat, Sonia and Guy too: those are Windows' "natural" voices, Narrator's only, and neither engine offers them. The helper sets `event_at` when it reads a call; several calls read at once go most urgent first.
- **The radio player:** waiting calls by priority (1 combat / threat, 2 airfield / Winchester / bingo, 3 routine), then arrival; over `MAX_BACKLOG_S` (20 s) of audio waiting, the lowest priority goes, oldest first; a call's age from `event_at`; never two at once. **The jet's radios:** `radio_calls/export_cockpit_radios.lua`, run by DCS's export system, sends the F-16's UHF (device 36, volume knob 430) and VHF (device 38, knob 431) frequency, on / off and volume twice a second over UDP 127.0.0.1:47112 (chained like SRS's `LuaExportActivityNextEvent`, so SRS keeps working); while reports are fresh (3 s) a call plays only on a radio on and tuned within 10 kHz, at that knob's volume; otherwise everything plays. Everything the player says goes to `radio_calls/radio_player.log` too (rewritten each start, git-ignored; Kola bug 69, 2026-10-06): the jet's radios as first heard and at each change, "no word from the jet's radios" when readings stop, each call heard (radio, volume), not heard (why) or dropped; the export script writes its `first reading of the jet's radios` to `dcs.log` once. Combat calls' lives (`RADIO_CALLS.kinds`, Kola bug 70): `splash` 40 s and `jet_down` 45 s, longer than a Darkstar picture they may wait behind; Fox / Magnum / defending 8 s. At start the player adds the one line loading it to `Saved Games\DCS\Scripts\Export.lua` (and `DCS.openbeta`) if missing (or corrects its path), touching nothing else; DCS needs one restart to load it. README *Your jet's radios* has the steps for John's friend.
- **Checked:** a luae harness with stubbed DCS ran one SEAD flight from taxi to clear (all 15 calls, folding, the jet-down speaker, no double call on ejection + crash), then the helper worded each; the player's queue, radio filter and the Export.lua edit (on a copy of John's file) in Python; the export script in luae with a stubbed cockpit (SRS's function still called every time); the brief, *Airfield info* and the air tasking order menu on a re-planned roll.
- **First test, 2026-10-05 21:02** (`event_logs\2026-10-05_210257.log`, John on the ramp at Rovaniemi, listening; John: "really good and really helps to know what is going on with all the flights"). 34 `RADIO_CALL`s; taxi, airborne, Magnum, Fox, splash, jet down (Weasel 1-1 for 1-2), off target, check-out, inbound and clear all matched what the flights did. **Every call was heard whatever the radios were set to:** expected the first time. The radio player added the Export.lua line when the mission started it (14:04 UTC), after DCS had read Export.lua at its own start (14:00), so the export script never ran (`dcs.log`: SRS's export line, no `KOLA-RADIOS`, the export script's tag then; `COCKPIT-RADIOS` since framework step 5); from the next DCS start it does. **The load is fine:** with every channel heard at once it wasn't too many calls (John). Fixed the same night (harness-checked, copied to DCS, not flown):
  - **"Pushing" one second after takeoff:** Rovaniemi lies in contested airspace, so "out of own airspace" was true on the runway. Now the flight reaching its ingress waypoint (a SEAD flight: its first low-level or descent waypoint), told by the waypoint's script command (`InformRadioFlightCalls.waypoint`, beside `EventLog.waypoint` and `ControllerDirectFlights.waypoint`).
  - **A false "final"** at Rovaniemi (Weasel 2 egressing low at ~450 kt past its own base, 5 min after takeoff), which used up the flight's final, so the real approach had none and "inbound" came after it. Now inbound only for a flight coming back to land (the watcher has seen it heading home, `InformRadioFlightCalls.headingHome`, or it is slow and low: ≤ 130 m/s, ≤ 1,500 m), and final only after that, at approach speed (≤ 110 m/s).
  - **"Splash" by a jet that had ejected** (Weasel 1-2's AIM-120 killed a Su-34 a second after 1-2 was shot down): a call from a jet already down is said by a jet of its flight still flying, or not at all.
- **Darkstar's orders to AI flights** (Kola roadmap item 7, step 14; designed with John and built 2026-10-05 night, harness-tested; flown 2026-10-06 00:16, each order matching its `CONTROL` line, `plan.md`, *History*, *Kola runs*). **A listener of the controller, not part of it** (John: "a watcher, not the controller directly"): `ControllerDirectFlights.say`, the one place every decision passes, also publishes it to listeners (`RecordAirFlightDecisions.on`, like `RecordRadarPicture.on`) as `{ coalition, subject, decision, text, details }`; details carry a `reason` word (every directive intent now has one: `salvo_complete`, `salvo_over`, `pressed_too_far`, `no_shot`, `attack_time_up`, `sam_threat`, `raid_destroyed`, `raid_turned_away`, `raid_lost`, `deep_in_enemy_airspace`, `relieved`, `bingo`, `no_air_to_air`, `wingman_landed`, `lost_on_way_home`, `overdue`; a fight's end: `bandit_destroyed`, `bandit_lost`, `bandit_far`, `bandit_cold`, `time_up`, `out_of_missiles`, `no_jets_up`), and `threat`, `relief`, `units`, `targets`. The controller knows nothing of the radio. `inform\radio\darkstar_orders.lua` (`InformRadioDarkstarOrders`) listens and speaks, on the AWACS channel in Darkstar's voice, to Blue AI flights with a callsign (not the AWACS):
  - `engage` (decision `defend`): the bandit's BRAA from the flight's lead, as the picture holds it (`InformScreenAirPicture.groupFrom`, grid-based magnetic like the picture calls; a bandit no radar holds, e.g. one that just fired: where it really is), type, "engage" / "commit". The same bandit to the same flight again within `RADIO_CALLS.orders.engage_fold_s` (90) isn't said (the break-off / re-engage cycle).
  - `resume` (`back on mission` / `back on way home`): only after an engage that was said, once; the reason ("good kill", "SAM threat, break off", "bandit cold") and "resume" or "continue RTB".
  - `return_to_base` (`go cold`, `leash home`, `handover` with the relief's callsign, `bingo`, `leave` with the bandit's BRAA at priority 1): the reason, then "RTB <base>".
  - `land_at` (`land`): to the one jet named (a wingman after its lead landed: "Weasel 1-2") or the flight, with the base's bearing and range.
  - `scramble_vector`: a scramble's decision is silent (its jet is still on the ground); `vector_after_takeoff_s` (4) after its first jet takes off, after the pilot's own airborne call: the vector to its raid (BRAA from the jet), angels to climb to, the raid's altitude, aspect and type.
  - **Not said:** launch decisions (`watching`, `wait`, `retry`, `cancel`, `launch late` / `early`, `come back`), `alert`, `no scramble`, ramp stand-downs, `press on` (John), `leave threat`, orphans, `no shot` without a go cold. Since step 15 (below) a go cold, bingo or fight end for a reason only the pilot would know is the pilot's report, not Darkstar's order.
  - Words: `radio_calls/awacs_order_phrases.json` through `flight_phrase_wording.py` (kinds and placeholders in its `CALLS`; `bra` said "brah"), voiced by the helper with Darkstar's voice. Event log `RADIO_CALL … <kind> on awacs by Darkstar to <callsign>, <reason or bandit>`.
  - **Checked:** a luae harness with stubbed DCS (the real controller's `say`, the air picture's BRAA, `InformRadioRadioCalls`): each decision said or not as above, folding, a scramble's vector after takeoff, a failing listener logged without stopping the controller; the calls worded by the helper's phrase bank. **Seen in the 2026-10-06 00:16 run:** each order matched its `CONTROL` line (2 engage, 1 resume, 5 RTB, a scramble's vector 4 s after its airborne call), heard in a sensible order with the pilots' own calls; Kola bug 63 (a resume then an RTB 5 s apart) came from it.
- **The pilots' reports and answers** (Kola roadmap item 7, step 15; designed with John and built 2026-10-06, harness-tested, copied to DCS, not flown).
  - **Who would know it says it:** a controller decision whose reason is in `RADIO_CALLS.orders.pilot_reasons` (`bingo`, `salvo_complete`, `salvo_over`, `no_shot`, `out_of_missiles`: fuel, weapons, whether the site's radar showed) is said by `inform\radio\darkstar_orders.lua` as the flight lead's `report` on AWACS, by the flight's callsign in the lead's voice ("Darkstar, Viper one, bingo, RTB Ivalo"; in a fight "Winchester, knocking it off, resuming"), then Darkstar's `acknowledge` ("Viper one, Darkstar, copy bingo"). No Darkstar order for those; the controller's order to DCS is unchanged. A fight-end report keeps the resume's rule (only after an engage that was said).
  - **Calls published:** every call written through `InformRadioRadioCalls.say` gets an `id` and goes to listeners (`InformRadioRadioCalls.onCall`), after it is written. Darkstar's orders carry the flight's `group`, an engage or a scramble's vector the bandit's `bandit` group.
  - **Answers** (`inform\radio\flight_calls.lua`): the watcher hears each order as said and waits for the flight to follow it, looked at every `RADIO_CALLS.answers.every_s` (2): `engage` the lead's nose within `toward_deg` (30) of the bandit and closing, or at once when the flight fires an air-to-air missile at it (the answer before the Fox); `scramble_vector` within 30° of the raid; `resume` within `route_deg` (45) of one of its next two waypoints (`last_waypoint` from the waypoints' script command), or toward home when it was "continue RTB"; `return_to_base` / `land_at` within `home_deg` (35) of its base `home_looks` (2) looks running. Then `answer` on AWACS by the flight's callsign (the one jet a landing order named: "Weasel 1-2"), in that jet's voice, at its order's priority, `answers` = the order's id: "Weasel one, committing", "copy, RTB", "copy vector, buster". Not seen within `within_s` (engage and resume 30, RTB and vector 45, land 60): no answer, event log `RADIO_CALL … no answer to <order> from <callsign>: not seen following it in n s`. A newer order replaces one still waiting; a report ends it.
  - **Check-out:** an RTB / continue-RTB / land answer, or a report going home, is the flight's check-out: no `check_out` after it (`off_target` on mission as before). A report also stands for the flight's bingo / Winchester.
  - **Helper and player:** each call's `call_id` and `answers` go in the header; the player remembers calls it dropped (expired, backlog, replaced, failed) for 120 s and drops an answer (or Darkstar's copy) to one of them, `dropped, the call it answers (n) was dropped`; the helper doesn't say an answer to a call it couldn't speak or send.
  - Words: `answer` and `report` in `pilot_phrases.json`, `acknowledge` in `awacs_order_phrases.json` (the pilot-only reasons' wording taken out of `return_to_base` and `resume`).
  - **Checked:** a luae harness with stubbed DCS (the real `InformRadioRadioCalls`, watcher and Darkstar's orders): an engage answered on turning in, and at once by a shot (before the Fox); a folded engage not answered; resume answered on turning back to the route; a salvo report and copy with no Darkstar RTB, then off target but no check-out; an ignored RTB logged as no answer after 45 s; a landing order answered by Weasel 1-2; a patrol's bingo as a report and no watcher bingo; a handover RTB answered, no check-out after. The player's drop of answers in Python; the phrase files by `flight_phrase_wording.py`. **To check in the first run:** each `RADIO_CALL … answer` after its order and matching what the flight did; `no answer` lines against the flight's track (an order the AI really ignored, or a test too strict); `report … bingo` / `salvo_complete` with no `return_to_base` for the same decision; no `check_out` after an answer or report; `radio_player.log` for `the call it answers … was dropped`.
- **To check in the first run** (after restarting DCS for the Export.lua line): the player's window "hearing the jet's radios from DCS: F-16C_50, UHF … VHF …"; calls heard only when tuned (AWACS UHF 262.000, mission VHF 140.000, the field's tower VHF); `RADIO_CALL` lines against what the flights did (a `pushing` at the ingress, `off_target` only on the way home, `final` only on a real approach); whether DCS's own ATC on the tower frequency talks over ours.

### Event log (`logs\event_log.lua`, `data/event_log.lua`)

Built 2026-09-30 (Kola roadmap item 3). A catalogue of everything that happened in the air war, in plain language, unit by unit (John: comb through it and see exactly how the mission unfolded per unit, step by step, without affecting game performance). First run in DCS on 2026-09-30.
- **File:** `<wall-clock date>_<time>.log` in the mission's `event_logs\` folder (`MISSION.event_log_folder`), a new one per run (John: timestamped files; in the repository, not the DCS game folder, and git-ignored). Old files stay, for comparing runs.
  - The folder is an absolute path (`MISSION.event_log_folder`), since the script runs from its copy under `Saved Games\DCS\Scripts`.
  - If that folder can't be written (another machine, the repository moved), the log goes to `Saved Games\DCS\<MISSION.event_log_fallback_folder>\` (Kola: `kola_event_logs`); if neither, to `dcs.log`.
- **Top:** the plan, to read the timeline against: territory, weather, SAM sites (id, system, layer, ring), alert bases, the air tasking order (spawn / takeoff / TOT or on station / end per flight; human flights marked), convoys.
- **Timeline:** one line per event, in fixed columns: local clock, time since start, coalition, event word, subject, details.
  - **Subject:** a unit name for unit events, a group name for flight events (spawn, waypoint, scramble), and the contact's group for radar-picture lines (whose coalition is the picture's owner).
  - **Details** always name the other party in full, so grepping a name finds both what it did and what was done to it.
  ```
  08:11:50  T+00:11:50  RED   SHOT         MSN5901_SCRAM_1             Su-30 fired P_77 at MSN2025_2 (F-16C_50), 103 km, from 29,528 ft
  08:12:00  T+00:12:00  BLUE  HIT          MSN2025_2                   F-16C_50 hit by ZU_23_shell (5 hits) from DEF_OLEN_towed_anti_aircraft_guns_1_2 (ZU-23 Emplacement), 22,966 ft, …
  08:12:31  T+00:12:31  BLUE  DESTROYED    MSN2025_2                   F-16C_50 by MSN5901_SCRAM_1 (Su-30) with R-77, 22,966 ft, own airspace, 135 km outside SAM_ALTA_SA11_1
  ```
- **End:** on `S_EVENT_MISSION_END`, a summary:
  - flights launched;
  - aircraft lost by cause (aircraft / SAM sites / base defenses / other ground units / no killer recorded);
  - ground units and objects destroyed;
  - each flight's outcome (`RecordFlightLaunches.statusOf`).

  If DCS crashes, the file ends at the last write.
- **Events caught here for every unit** (one DCS event handler):
  - `SHOT`: the weapon, the target and range when `Weapon:getTarget` knows it, and the shooter's altitude;
  - `GUNS` (`S_EVENT_SHOOTING_START`) and `HIT`;
  - `DESTROYED` (units and static objects, never scenery), `CRASHED`, `EJECTED`, `PILOT_DEAD`, `PARACHUTE`;
  - `TAKEOFF`, `LAND`, `PLAYER_IN` / `PLAYER_OUT`;
  - `ABORTED` (`S_EVENT_AI_ABORT_MISSION`, if this DCS version has it).
- **Events handed over by other modules** (`EventLog.add`):
  - the spawner: `SPAWNED`, `LOADOUT`, `WAYPOINT`;
  - `watch\flights.lua`: `TARGET`;
  - the radar picture: `CONTACT`, `TRACKING`, `PICTURE`;
  - the controller: `CONTROL` (every decision about flights: launches, scrambles, alert jets, directives).
- **`POSITION`:** every airborne aircraft, AI and players, each `position_every_s` (60): type, speed, heading, fuel, altitude, airspace, nearest enemy ring, and km from station centre for patrols. It replaces the old `track:` lines (patrols and the AWACS every 2 min).
- **`WAYPOINT`:** a `WrappedAction` `Script` command, first on every waypoint between takeoff and landing, calls `EventLog.waypoint(id, index)` when the flight gets there, so there's no polling. The line names:
  - the waypoint's kind: ingress (pushing, attack tasks active), target (with the planned TOT and minutes late or early), on / off station;
  - the lead's altitude, airspace and ring;
  - the aircraft left.
- **Folding** (John: gun hits collapsed so they don't spam the log): each line is held `hold_s` (10 s) before it's written. A repeat within the fold window of the last one adds to that line's count instead of making a new line:
  - hits by the same shooter on the same target with the same weapon, within 5 s: "(5 hits)";
  - shots of the same weapon at the same target, within 5 s: "fired 4x FAB-500";
  - a gun opening up again, within 10 s: "(3 bursts)".

  A death is reported once, from whichever DCS event comes first (kill, dead, unit lost). A kill that arrives while the line is still held fills in who did it.
- **Performance:**
  - a DCS event only builds a line in memory;
  - lines are written every `write_every_s` (5 s), in one `write` + `flush`;
  - the only polling is `POSITION`: ~32 `getPoint` calls a minute at the airborne cap;
  - if the file can't be opened, the lines go to `dcs.log` (`event:`).
- **Watching it live:** these follow the newest file, so start them after the mission has loaded (each run makes a new file).
  - PowerShell: `Get-Content (Get-ChildItem "$env:USERPROFILE\Git\dcs\missions\kola_f16_random_tasking\event_logs\*.log" | Sort-Object LastWriteTime | Select-Object -Last 1) -Wait -Tail 40`. Without the positions, add `| Where-Object { $_ -notmatch 'POSITION' }`.
  - Git Bash: `tail -n 40 -f "$(ls -t ~/Git/dcs/missions/kola_f16_random_tasking/event_logs/*.log | head -1)"`. Without the positions, add `| grep --line-buffered -v POSITION`.
- **Offline harness** (`event_log_harness.lua`, session scratchpad; not kept): the real spawner, scheduler and event log on the last plan, with stubbed DCS. It checked:
  - the spawner's waypoint commands and task numbering;
  - folding of bombs, gun bursts and hits;
  - a kill arriving after the dead event, and a scenery kill ignored;
  - lines in time order, and nothing after the mission end;
  - the plan header and the summary.

### Sleeping ground units (`controller\wake_ground_units.lua`, `data/ground_unit_sleep.lua`)

Built 2026-10-01 (the performance-in-VR item, now in `closed.md`); run once in 2D the same day, where one base woke and slept as designed. A sleeping group has its AI off (`Controller:setOnOff(false)`), so it doesn't scan the sky. Standing units cost little by themselves; ~500 of them checking every aircraft and missile is what multiplies.
- **What sleeps:** base-defense groups of `GROUND_UNIT_SLEEP.components`: towed and mobile guns, infrared missile launchers, MANPADS teams (and security infantry if it comes back). **Never:** SAM sites (the air denial) and `radar_missile_launchers` (they reach ~20 km and feed the radar picture).
- **Per base, every 10 s:** all its sleeping groups wake together when an enemy aircraft (plane or helicopter, AI or player) is within `wake_km` (30) of the base, with alarm state red. They sleep again once no enemy has been within 30 km, and the base hasn't fired, for `sleep_after_s` (180), so a base never sleeps mid-fight or flaps. Everything starts asleep.
- **Watching for problems** (John: see problems without spamming the log):
  - `UNIT_AWAKE` / `UNIT_ASLEEP`, one line per base per switch, subject `DEF_<CODE>`; the asleep line sums that wake: close passes, shots, hits, kills.
  - `LATE_WAKE`: an enemy within `reach_km` (10) of a base that was asleep. Never expected; it means the wake-up missed an aircraft.
  - `(asleep)` at the end of a `HIT` or `DESTROYED` line of a sleeping unit.
  - `AWAKE_COUNT` every 5 min per coalition: bases and units awake.
  - **End summary:** per base that woke: wakes, minutes awake, close passes (enemies within 10 km while awake), shots, hits, kills, late wakes; `CHECK` on a base with 2+ close passes and no shot (DCS may not have woken it properly).
- **Off switch:** `CONFIG.SLEEP_GROUND_UNITS = false` keeps everything awake, to compare a run.
- **Harness** (`sleep_harness.lua`, session scratchpad, not kept): the 21:37 plan's 174 sleeping groups off at start; a Blue jet woke Vuojärvi at 30 km, a gun burst kept it awake, and it slept 3 min after the jet died; a jet appearing 8 km from Alakurtti gave `LATE_WAKE`; a hit on a sleeping MANPADS team read `(asleep)`.

### Player slots (`data/player_slots.lua`)

- **Templates:** John places dynamic-spawn templates (group `f16_<base>`; in Caucasus also `f18_<base>`, an FA-18C beside each F-16C, 2026-10-07) in the mission's flyable `.miz` (`MISSION.flyable_mission_file`); DCS spawns the player on the template's exact spot. In the ME, the always-Blue / always-Red bases have their coalition set; contested ones are neutral and the script sets them.
- **Data file:** `map_data_tools/miz_player_slots.py <mission folder>` → the mission's `data/player_slots.lua` (`PLAYER_SLOTS[base]` = terminal index, spot name, group, type, position). Re-run it after moving or adding slots (not after renaming units: it keeps group names only).
- **Unit names** match their group (`f16_rovaniemi-1-1`; John renamed them 2026-10-02: the templates were copies of Kallax's, Kola bug 24).
- **Datalink in the templates:** country CJTF Blue (the AI's country; USA until 2026-10-02), each slot its own Link 16 STN (00201–00211), a team of itself only, no donors and an empty DTC. That is enough: AI flights show as datalink contacts without being in the team (the Caucasus test). A human 2-ship would list each other's STNs as team members; an AWACS donor would need the E-3A spawned with a fixed unit id (Kola bug 26).
- **Kept clear:** `watch\world_at_start.lua` attaches `player_slots` to each airbase and warns when a slot's spot is missing or has moved. Parked-aircraft statics and AI parking skip those spots; ground units already keep clear of every parking spot.

### Brief (`inform\screen\briefing.lua`)

- **Start text** (3 min, `START_MESSAGE_S` 180): the weather plus one line per human tasking (base, slot, takeoff, TOT, what). Nothing else on screen at start (John).
- **Comms menu** for each Blue player group (`\` > F10. Other...; John: call it the comms menu, F10 means the map). Since 2026-10-07 (multiplayer) every group with a player in it gets its own menu (`inform\screen\player_menus.lua`: built when a player is first seen in the group, checked every 5 s and at birth / entering a unit; removed when no player is left), and a text goes to that group only (`outTextForGroup`), so one player's frag or steerpoints don't cover another's screen:
  - `Human taskings > <MSN> > Frag / Steerpoints`, and `All human taskings`;
  - `Air tasking order > Attack missions / SEAD flights / Patrols and AWACS / All flights`, each flight with its state; an attack mission's menu entry is tagged with the SEAD flights it waits on ("09:41 STRIKE MSN2031 (after MSN2024, MSN2026 SEAD)"), a SEAD flight's text says which missions wait on it.

  Texts stay 60 s; the frag 180 s and the steerpoints 300 s (John, 2026-10-01). `Hide text` at the top of the comms menu clears the screen.
- **Frag contents:**
  - times (local);
  - target: description, degrees and decimal minutes (F-16) + MGRS + elevation, aim points, success as "destroy at least n of its m critical objects";
  - the loadout planned for an AI jet;
  - threats: enemy SAM rings the route crosses or passes within 20 km of, with the SEAD flight for each;
  - "Needs down: <site> (<SEAD flight>, <its state now>)", one line per site the mission waits on (John, 2026-10-02: which SEAD flight had to succeed for it to run); the frag is built again each time it's opened, so the states are live;
  - **SEAD frags** say to fire every anti-radiation missile from the LAUNCH steerpoint and list the missions waiting on it ("OPENING THE WAY FOR"); **CAP frags** add the orbit, the defended zone and the other patrols.

  Every frag and steerpoint list also goes to `dcs.log` (`HUMAN TASKING`).
- **Steerpoints** (2026-10-01, Kola bugs 10 and 11): the route out to `TGT` (or `CAP B`), then `LAND`; no egress or way home. `TGT` and each aim point (`AIM 1`, `AIM 2`, …) give the spot on the ground with its elevation, for fire-and-forget weapons; route points give the flight altitude.
- **Static kills** (2026-10-01, Kola bug 9): a player who destroys a static object the mission spawned gets a 15 s popup (DCS's kill list doesn't show static objects), with the human tasking's critical progress and "target destroyed: success" when its target is reached. Credited through the weapon if the player is gone by impact.
- **Airfield info** (`inform\screen\airfield_info.lua`, Kola roadmap item 13, built 2026-10-02, working, closed 2026-10-05): `Airfield info > <base>` for every Blue base, alphabetical by DCS name, paged by name range ("Alta–Evenes"); at the top of the comms menu, above `Human taskings`. Each text is built when it's opened:
  ```
  BANAK (BANA): Blue, mid, dispersal field, elevation 394 ft
  Wind 020° 11 kt → runway 34 in use (headwind 9 kt, crosswind 7 kt from the right)
  Runway 16/34, 2,462 m (8,077 ft)
  Next out: 04:12 MSN2016 CAP, 1x F-16C_50 (planned)
  Next in:  10:36 MSN2001 AWACS, 1x E-3A (airborne)
  Alert: 2 of 3 jets ready, 1 turning around (next in 12 min)
  ```
  - **Wind:** `atmosphere.getWind` 10 m above the field (the start text's ground wind if that fails), magnetic, the direction it blows from. Under 3 kt: "calm → either runway".
  - **Runway in use:** the runway end with the most headwind (the longer runway on a tie). DCS has no call that says which runway its ATC uses, so this is our pick from the wind. Runway numbers come from the runway's grid heading (`gather.lua`), turned to true (grid convergence from `coord.LOtoLL`) and then magnetic with the air picture's variation (`Bearings.variation`, so `InformScreenAirPicture.start` runs before the menus).
  - **Next out:** the AI flight from this base with the earliest takeoff that hasn't taken off (planned, delayed, or spawned with no jet in the air: "on the ramp"); its time is its takeoff time. **Next in:** the AI flight in the air whose planned landing here is soonest; its time is that planned landing. `_AGAIN` copies count ("MSN2025 again"); cancelled, not needed, stood down and down flights don't; human flights and scrambles aren't listed. The state is the air tasking order's (`statusOf`).
  - **Alert:** `RecordAlertJets.ready`: jets ready of the base's `alert_aircraft`, and jets turning around; "not an alert base" otherwise.
- **Not built yet:** tanker and AWACS frequencies and callsigns, threat fidelity (every SAM ring is listed as known; see *Design*), fuel, ROE, in-flight updates.
- **Warnings stay off screen** (`CONFIG.WARNINGS_ON_SCREEN = false`); errors still show.

### Zones: the ground-unit dataset (`data/zones.lua`)

Every ground unit except base defenses spawns inside a surveyed zone.
- **What a zone is:** exactly one thing, a clearing where ground units can realistically be placed. It has no side, no role and no substance (John): the planner assigns everything at run time from size, distance to bases and the front, and road access.
- **Where zones come from:**
  - drawn as ME trigger zones (circle or quad) in a zone drawing mission that is only flown for the survey: `Saved Games\DCS\Missions\<MISSION.zone_drawing_mission_file>` (Kola: `khola_ground_zones.miz`);
  - `map_data_tools/miz_zones.py <mission folder>` parses it into the mission's committed `data/zones.lua`, the **only** source the plan reads;
  - the flyable mission contains no zones.
- **Names are generated, never typed** (John): `ZONE_<BASE>_<brg>_<km×10>` from the nearest airbase (e.g. `ZONE_KITT_100_012`: 1.2 km on bearing 100° from Kittilä). Each entry keeps the ME's `zone_id`, which is stable while the zone exists, as the key.
- **Coordinates:** projected metres, `x` north and `z` east. Lat/lon are computed in-sim with `coord.LOtoLL`. The tool's own transverse-Mercator (`map_data_tools/map_projection.py`, the map's parameters) is verified to ~10 m on Kola.
- **Side:** each zone carries its nearest base's `cluster` and inherits that cluster's rolled side.
- **Classes** (precomputed offline, one question each; John rejected an in-mission classifier): `size`, `airfield_distance`, `ground`, `terrain`, `road_access`, `railway_access`, `water`, `radar_view`, `settlement`, `prepared_sam_position`, plus `surveyed` and `measured`. Thresholds (`CLASS_THRESHOLDS`, `OBJECT_CATEGORIES`) live in the tool.

**Workflow after drawing or moving zones** (John, 2026-09-27: the survey is part of the sequence, every time):
1. Save the zone drawing mission.
2. Fly it once. Its trigger loads the mission's `survey\survey_zone_terrain.lua`, which loads the mission's `mission_settings.lua` and then the framework's `survey/survey_zone_terrain.lua`; that measures the terrain around every zone and writes `Saved Games\DCS\<MISSION.zone_terrain_survey_file>` (Kola: `kola_zone_terrain.lua`).
3. At the end of that flight, the survey script calls `map_data_tools/update_zone_data.cmd`, which runs `miz_zones.py` on the mission folder and copies the mission's scripts folder to Scripts. The result shows on screen and in `Saved Games\DCS\<MISSION.zone_update_log_file>` (Kola: `kola_zone_update.log`).

Never regenerate `zones.lua` without the survey (unsurveyed zones get `unknown` classes). By hand: `shared_mission_framework\map_data_tools\update_zone_data.cmd "<mission folder>" "<Saved Games\DCS>" <scripts folder> <log file>`, or just `miz_zones.py <mission folder>`.

### Unit pool (`data/unit_pool.lua`)

What DCS needs to spawn a unit is one type string; an unknown string silently becomes a Leopard-2 (`woCar: … replaced with Leopard-2`).
- **Contents:** every AI-operable unit in base DCS, including the CoreMods packs (Currenthill `CHAP_*`, ColdWar, Massun92, HeavyMetal) but nothing from `Saved Games\Mods`. Generated by `map_data_tools/unit_pool.py` from pydcs's source text.
- **Agnostic by design** (John): no side, country or era. Blue may field Russian SAMs; which coalition uses what lives only in `data/coalition_rosters.lua`.
- **Per entry:** `type`, `name`, `cat`, `role`, `system`, ED's `detection_m` / `threat_m` / `air_weapon_m`; for aircraft also `tasks`, `task_default`, `fuel_max`, `chaff` / `flare`, `pylons`, `flyable`, `large_parking`, `tacan`.
- **Static objects:** `static` holds every structure and cargo type with `category` + `shape_name`.
- **Roles:** from name heuristics plus `map_data_tools/unit_role_overrides.json`; the tool reports anything unclassified.
- **Pylons:** `data/aircraft_pylons.lua` (pylon → allowed CLSIDs, 1.1 MB) is generated for offline validation only and never loaded at runtime.

### Weather and time (`tools\weather.lua`)

The runtime can read the mission's weather, time and date, but can't change them. Gather reads them once into `plan.world.weather` / `plan.world.time`:
- **Clouds and visibility:** clouds (preset, METAR text, coverage, base, ceiling, precipitation), visibility (capped by fog and a rain preset's range) and flight rules (VFR / MVFR / IFR / LIFR).
- **Wind:** at ground, 2,000 and 8,000 m.
- **Air:** temperature, QNH (the .miz stores mmHg), turbulence, dust.
- **Time and sun:** time, date, season and sun (elevation, condition, sunrise / sunset, polar day and night) at the airbase centroid. The clock's offset from UTC is the mission's (`MISSION.utc_offset_h`; Kola +3).
- **Preset clouds:** a preset stores only `clouds.preset` + `clouds.base`. Coverage and layers come from `DCS World\Config\Effects\clouds.lua` via `map_data_tools/cloud_presets.py` → `data/cloud_presets.lua`; re-run after DCS updates.
- **Wind direction:** the .miz stores the direction the wind blows *to*; the ME shows *from*.

### Offline tools and test harness

`shared_mission_framework\map_data_tools\` (stdlib Python, 3.7-compatible; pydcs and Liberation are reference clones, never dependencies). A mission's tools take its folder and read its `mission_settings.lua` (`mission_folder.py`: the map, the file names); the others write the framework's shared data. From the repository root:

| Run | When |
|---|---|
| fly the mission's zone drawing mission (`MISSION.zone_drawing_mission_file`; it runs `update_zone_data.cmd` itself) | after drawing or moving zones |
| `python shared_mission_framework\map_data_tools\miz_zones.py missions\<mission>` | after changing the mission's `data/clusters.lua` |
| `python shared_mission_framework\map_data_tools\miz_player_slots.py missions\<mission>` | after moving or adding player slots |
| `python shared_mission_framework\map_data_tools\airfield_frequencies.py missions\<mission>` | after a map update |
| `python shared_mission_framework\map_data_tools\aircraft_loadouts.py` | after changing a loadout choice, re-running `unit_pool.py`, or updating the Liberation clone |
| `python shared_mission_framework\map_data_tools\unit_pool.py` | after a DCS update, once pydcs has caught up |
| `python shared_mission_framework\map_data_tools\cloud_presets.py` | after a DCS update |
| the footprint survey (`CONFIG.SURVEY_FOOTPRINTS`) | after a map update |
| fly `afghanistan_spawn_site_survey.miz`: with no trigger zone, the whole-map survey of `map_data\<map>\survey_area.lua` (resumes after a crash; at the end it runs `find_spawn_sites.cmd map-survey` itself); with trigger zones, test areas around them (then the viewer). By hand: `python shared_mission_framework\map_data_tools\find_spawn_sites.py map-survey` (whole map, newest finished run) or `… find_spawn_sites.py` (test areas) | spawn sites on a map with no drawn zones (Afghanistan; `missions\afghanistan_campaign\mission_design.md`, *Map data: the site survey*); the whole map again after a DCS map update (comms menu, *Survey the map again*) |
| `python shared_mission_framework\map_data_tools\find_spawn_sites.py make-missions` | writes the survey and viewer missions from John's `Afghanistan_survey_1.miz` (the survey mission isn't overwritten without `--force`) |
| `python desanitize_dcs.py` (repo root, admin shell) + full DCS restart | after every DCS update |
| `python shared_mission_framework\radio_calls\phrase_bank_wording.py`, then `play_sample_awacs_calls.py` (player running) | after changing `awacs_phrases.json` |

- **A new map:** its projection parameters in `map_projection.py`'s `MAPS` (from pydcs, `dcs/terrain/<map>/projection.py`); a map not there stops the tools that need it, naming the known ones. **A map pydcs doesn't have** (Afghanistan, 2026-10-07; its `terrain.cfg.lua` is encrypted too): its facts come from DCS itself, by a survey in `map_surveys\` (the terrain probe's `airbases.lua`), in DCS's own x / z, so the site survey and its tools need no projection.
- **Python versions:** `python` on PATH is a pyenv 3.7 shim; Python 3.10 is at `AppData\Local\Programs\Python\Python310` (the `.cmd` files use it when it's there).
- **Offline test harness** (`shared_mission_framework\offline_test_harness\`, kept since framework step 0): stubbed DCS (`stub_dcs.lua`, `stub_dcs_world.lua`, a simple flight model, sensors and a stand-in player) runs a mission's real `init.lua` on a frozen saved world. `python replay_and_compare.py kola` (tests A–C: the plan, a 2-hour mission standing still and flying, the files loaded) and `python rerun_data_tools.py kola` (test D: the map tools) compare with recorded baselines; how to use them: the root `plan.md`, *Picking this up in a new session*, and *How the transfer is tested* below. Run them before handing a change to John; a change meant to alter behaviour means re-recording the baselines after checking every difference.
- **Random seeds in luae:** luae's `math.random` is the C `rand()`, and the first values after `math.randomseed(1..N)` are nearly linear in the seed. Seed with `seed * 7919` and discard ~50 values.

### DCS facts learned the hard way

Moved 2026-10-07 to the repository's one list, **`dcs_scripting_gotchas.md`** at the root (John: one place every session can read). Add new ones there, not here.

### Performance

**Baseline** (John's F-16 flights, 2026-09-25, stages 1–3c, GPU-bound):

| | Everything spawned (~860 units + ~250 static objects, all `DRAW_*` on) | Empty map |
|---|---|---|
| Bodø, on the ground and low flyover | 45–60 fps, some stutter when panning | 48–65 fps |
| 25,000 ft | 70–75 fps | 70–75 fps |
| F10 map | 45 fps | 55 fps |

- **Reading:** standing ground units cost a few fps only close to a heavy base, and nothing at altitude. The F10 drop is most likely the ~600 debug marks. John tuned graphics settings; no mission changes.
- **To do:** re-test the same way now that AI flights and convoys run.
- **Rules of thumb:**
  - cost order: moving ground > AI aircraft > standing units with sensors > idle units / statics;
  - levers: `controller:setOnOff(false)` for far ground groups, statics for non-shooting targets, few infantry.

---

---

## Reading a run

The story is in the event log (`event_logs\<date>_<time>.log` in the mission's folder, git-ignored, one per run; see *Event log*). The examples are Kola's. Grep a unit or flight name for its whole life, or an event word:

| Grep the event log | Shows |
|---|---|
| a name (`MSN2025_DEAD`, `MSN2025_DEAD_2`, `SAM_OLEN_SA11_1`) | everything it did and everything done to it |
| `SPAWNED`, `LOADOUT`, `TAKEOFF`, `WAYPOINT`, `LAND` | each flight's life: spawn, what each jet carries, each waypoint reached (ingress = pushing; target with TOT late / early), landing |
| `POSITION` | every airborne aircraft each minute: type, speed, heading, fuel, altitude, airspace, nearest enemy ring, km from station |
| `SHOT`, `GUNS`, `HIT` | weapons fired (with target and range when DCS knows it), guns opening up, hits (with the life left a second later, `life now 92 %`); repeats folded into one line |
| `IMPACT` | where a bomb or air-to-ground missile from an aircraft came down (grid reference as the F10 map), the objects within 150 m with their life before → after (or destroyed), or "gone in the air" (bug 71) |
| `LINE_UP` | an AI jet at a Blue field lined up on a runway (its departing call is said then; bug 67) |
| `DESTROYED`, `CRASHED`, `EJECTED`, `PILOT_DEAD` | every unit and object destroyed, by whom and with what; aircraft with altitude, airspace and ring |
| `TARGET` | a mission's target objects destroyed ("3 of 6 critical") |
| `CONTACT`, `TRACKING`, `PICTURE` | each coalition's radar picture: new / regained / stale / dropped contacts (new and regained say how far away the first sensor saw it, "seen by awacs MSN2001_AEW 212 km away") and airspace changes, a SAM radar's first track of a group, the 5-min summary |
| `CONTROL` | **every controller decision**, in order, the decision first (2026-10-01; before that each had its own word: `SCRAMBLE`, `NO_SCRAMBLE`, `STOOD_DOWN`, `ALERT`, `LEASH`, `SUPPRESSION`, `DEFEND`, `DELAYED`, `RETRY`, `CANCELLED`). Grep `CONTROL.*<decision>` for one kind: |
| `CONTROL.*watching` | a flight the controller watches, and its directives (a scramble: `leash on <raid>`) |
| `CONTROL.*scramble`, `no scramble`, `stand down before launch`, `alert` | scramble decisions and refusals (once per reason), stood down before launch, jets back on alert |
| `CONTROL.*leash` | a scramble sent home (`leash home`) or stood down on the ramp (`leash stand down`) |
| `CONTROL.*go cold` | a SEAD flight sent home after its salvo, and why |
| `CONTROL.*defend`, `leave`, `back on`, `leave threat` | the bandit call: an attack flight engaging a bandit (range, aspect, closing speed, radar missiles aboard), or sent home with no radar missiles to fight it (`leave:`); back on its mission or way home (why, how long); leaving a bandit to another flight (`leave threat`) |
| `CONTROL.*wait`, `retry`, `cancel`, `launch late`, `launch early` | SEAD first: a flight waiting for the SEAD flight on a site it needs, a SEAD flight flying again (`<id>_AGAIN`; in the rotation, "the rotation's next flight"), a flight not launched and why (`not needed`, `… still in the fight after a second SEAD flight`, `<site>'s SEAD flight … was cancelled`), a flight launched late, a rotation flight pulled forward (`launch early`). Before 2026-10-02 they were about packages |
| `CONTROL.*no shot` | a SEAD flight that reached its press-on point with every anti-radiation missile still aboard, sent home (before bug 36: at its launch point for 2 min) |
| `CONTROL.*press on` | a SEAD flight with missiles aboard not turning to fight a bandit (too far, or finishing its salvo); it commits only when fired upon or inside 25 km (bug 39) |
| `CONTROL.*salvo over` | a SEAD flight sent home 20 s after one of its jets fired its last anti-radiation missile (bug 40) |
| `RADAR_WARNING` | a SEAD flight at its launch and press-on points: whether its site's radar is on its warning receivers, every radar that is, the lead's height above the ground (bug 36) |
| `CONTROL.*handover`, `land:` | a patrol relieved on station and sent home; a jet lost on its way home given a new landing order, or a jet still up once another of its flight landed (`… still in the air`, each jet on its own order, bug 52) |
| `CONTROL.*stand down:` | jets removed on the ramp because they spawned with no weapons |
| `RAMP_LOSS` | a jet destroyed on the ramp before takeoff, within 2 min of spawning: a spawn failure, with base and spot |
| `>>orphan<<` | bug 19's wingmen (`CONTROL` lines): `possibly orphaned` (still in the air when a jet of its flight landed), then how it ended: `not orphaned: landed … after`, `removed: by the controller` (8 min on, counted as landed; or, since bug 68, `… still flying away 8 min after its last landing order`, with no landing in its flight needed), or `lost`. Count them run to run to see whether it gets worse or better |
| `UNIT_AWAKE`, `UNIT_ASLEEP`, `LATE_WAKE`, `AWAKE_COUNT`, `(asleep)` | sleeping ground units: a base's short-reach defenses waking and sleeping, an enemy within 10 km of a sleeping base (never expected), the 5-min count; hits and deaths of a sleeping unit end in `(asleep)` |
| `PLAYER_IN`, `PLAYER_OUT` | players |
| `PICTURE_CALL` | the air picture shown to a player every 2 min: how many groups, and the first (highest threat) line; `no radar coverage` when no sensor of the coalition reaches the player; `threat: …` a spoken threat call (a hot group inside 40 nm, roadmap item 7). What was said: `radio_calls/speak_mission_calls.log` |
| `RADIO_CALL` | an AI pilot's radio call, or Darkstar's order to an AI flight (`… by Darkstar to Weasel 1`: `engage`, `resume`, `return_to_base`, `land_at`, `scramble_vector`; compare with that flight's `CONTROL` lines); since 2026-10-06 the pilot's `report` to Darkstar (bingo, salvo done, no emitter, Winchester) and Darkstar's `acknowledge`, the pilot's `answer` to an order (`… (n s after the order)`), and `no answer to <order> from <callsign>` when the flight wasn't seen following it: what (`airborne`, `pushing`, `fox`, `magnum`, `splash`, `defending`, `jet_down`, `off_target`, `check_out`, `taxi`, `departing`, `inbound`, `final`, `clear`, …), on which channel (with an airfield's frequency and runway), by which jet's callsign. Compare with the flight's own lines to see that each call matches what it did; the words: `radio_calls/speak_mission_calls.log`; heard or not (tuned, too old, dropped), at what volume, and the jet's radios as they changed: `radio_calls/radio_player.log` (since 2026-10-06; before, the player's window only) |
| `== Mission end` | the summary: flights launched, losses by cause, ground losses, each flight's outcome |

`dcs.log` keeps planning and debugging (grep the mission's log tag: `[KOLA]`, `[CAUCASUS]`):

| Grep `dcs.log` | Shows |
|---|---|
| `PRELOAD`, `the sim froze` | the start-up preload cost per type, and any spawn over 1 s |
| `HUMAN TASKING` | every frag and steerpoint list |
| `SEAD order`, `SEAD rotation` | which enemy sites the rotation takes, in order (step, coverage, what goes before each), and every site not taken and why |
| `Build summary:` | the roll's totals |
| `asked for` | a unit type DCS swapped (Leopard-2 substitution) |
| `carries no weapons` | a jet spawned without the weapons its loadout lists (removed on the ramp; `carries nothing` before 2026-10-02) |
| `destroyed on the ramp` | a `RAMP_LOSS` |
| `picture:`, `Scrambles:` | the radar sensors found and the alert bases, at start |
| `WARN`, `ERROR` | anything that went wrong, including a failed event-log line |
| `KOLA-RADIOS` (not `[KOLA]`) | the export script reading the jet's radios for the radio player ("sending the jet's radios to 127.0.0.1:47112"), its first reading of them (`first reading of the jet's radios: {…}`), the first failure to read or send, or why it couldn't load |
| `Radio calls:`, `Flight calls:`, `Airfield calls:` | the radio's start lines: channels and frequencies, the calls file |

---

## How the transfer is tested (the offline test harness)

Built for the split out of Kola (2026-10-06) and kept as the regression test for every change since: run it before and after each change (`plan.md`, *Picking this up in a new session*).

The move is only right if Kola behaves exactly as before, so most tests compare against the step 0 baseline rather than judging by eye.

**Test A. The same plan, byte for byte.** The harness stubs DCS, takes `plan.world` from saved plans (`kola_last_plan.lua` from a few recent runs: different territory rolls), seeds the random numbers the same way (seed × 7919, ~50 values discarded, as Kola's harness notes say), runs every stage and writes the plan. After each step the plans must be identical to the baseline. Any difference is a regression, or an intended change that is written down.

**Test B. The same mission, 2 hours of mission clock.** The real scheduler, controller, radar picture, scrambles, event log and the radio's Inform files over stubbed DCS on a saved plan (Kola's `real_plan_harness.lua` did this for item 11: 23 flights launched, no errors). Compared with the baseline: no errors; the same counts per event word (`SPAWNED`, `CONTROL` by decision, `RADIO_CALL` by kind, `CONTACT`…); the same `calls_file` lines.

**Test C. Every file loaded once, from the right place.** The list of files loaded (logged by `load_framework.lua`) compared with today's `init.lua` list: none missing, none twice, none from the old folder. Every override line in `dcs.log` as expected (none for Kola).

**Test D. The Python tools give the same data.** From their new place, with Kola's folder as the argument: `miz_zones.py` (needs `Saved Games\DCS\kola_zone_terrain.lua`), `miz_player_slots.py`, `airfield_frequencies.py`, `unit_pool.py`, `cloud_presets.py`, `aircraft_loadouts.py`; each output identical to the committed file. Radio: `phrase_bank_wording.py` and `flight_phrase_wording.py` check their files; `play_sample_awacs_calls.py` plays through the player; the `Export.lua` edit tried on a copy of John's file (the old Kola line replaced, SRS's line untouched).

**Test E. John flies Kola** (after step 3, and after steps 4 and 5). In `dcs.log`: no `FATAL` / load errors; the loading lines (framework folder, mission folder, files loaded, overrides: none); `Build summary:` like a normal roll; the plan written to `kola_last_plan.lua`; the export script's `first reading of the jet's radios` (after step 5: from the framework's path, after one DCS restart). In the event log: a new file in `missions\kola_f16_random_tasking\event_logs\`, its header, `SPAWNED`, `CONTROL`, `RADIO_CALL` lines as in any run. By ear: Darkstar's picture, pilots' calls and airfield traffic heard, only when tuned. On the map: the usual drawings. Nothing else in the run should differ from a normal Kola run; anything that does is a bug of the move.

---

## Design, not built yet

**Threat-intel fidelity rule** (for the brief and fog of war, Kola roadmap item 9). Fidelity follows the threat's real-world nature, not a difficulty setting:

| Threat class | In the brief as | Map |
|---|---|---|
| Fixed strategic SAM (SA-10 class, long range) | **CONFIRMED**: type, exact coordinates, status, engagement ring | Ring drawn |
| Mobile SAM (SA-6/8/11/15) | **PROBABLE**: type + "operating vicinity <area>"; or **POSSIBLE**: type and region only; a fraction **unlisted** | Area circle (±5–10 nm) or nothing |
| Point defense (AAA, MANPADS) | Generic: "expect AAA / MANPADS in target area" | None |
| Air | Per-base types, assessed CAP station *area*, QRA timing | Station area |
| Target itself | Exact | Mark |

Roll it per mobile SAM each session. Surprise threats then have a realistic justification: the RWR is the last line of intel.

**What a pilot would realistically be told**, and what we'd give:
- **Frag** (mission number, callsign, target + coordinates + elevation, TOT, package) → built.
- **SPINS / comm-nav** (ROE, tanker track / TACAN / frequency, AWACS frequency, divert fields, sunrise / sunset) → divert = nearest 2 held bases; sun data is already in `plan.world.time`.
- **Mission data card** (steerpoints, joker / bingo) → steerpoints built; fuel estimate not built.
- **Air order of battle** → from each side's standing posture (stations, base types), never its timeline.

**No side reads the other side's plan.** Neither planner predicts the other's behaviour. Each side plans from the static picture (territory, the front, fixed sites, its own assets); responsiveness comes from a runtime reaction loop (scrambles) and native DCS AI. Red defends what Red values, with no knowledge of which target is the player's.

**Callsign policy: the radio callsign isn't the group name.**
- **Two identities:** the DCS group name is the machine id (`MSN2041`) and is never spoken. The radio callsign is a separate field drawn from DCS's built-in callsign enum, which drives the AI voiceovers *and* is what the brief prints, so what's written matches what's heard.
- **Blue pools per role:** fighters `{Springfield, Colt, Dodge, Ford, Chevy, Uzi, Enfield, Pontiac}`, tankers `{Texaco, Arco, Shell}`, AWACS `{Magic, Overlord, Wizard, Darkstar}`. The player gets a reserved fighter callsign by role (SEAD → Springfield, strike → Colt, CAP → Dodge…).
- **Audible but not overwhelming:** enum callsigns go to player-relevant Blue air (own flight, package-mates, covering CAP, tanker, AWACS); the airborne cap limits simultaneous transmitters.
- Roadmap item 7 (AI radio calls) builds on this.

**Weather as a planner input** (reading works; the planner doesn't use it yet):

| Weather fact | Planner consequence |
|---|---|
| Low ceiling / thick cloud | Down-weight laser-guided and visual weapons; favour JDAM / HARM (GPS works through cloud) |
| Poor visibility / fog / precipitation | Suppress visual recon and CAS; widen mobile-SAM assessed areas |
| Night / polar night | TGP- and night-appropriate loads; may suppress visual CAS |
| Wind aloft | Orient tanker and CAP tracks into wind |
| Temperature + QNH + field elevation | Density-altitude check on short fields; correct altimeter in the brief |
| Ceiling + visibility | VFR / IFR per base: recovery and divert choice |

**Weather and time variety** can't be done in Lua at runtime. Options:
1. fixed ME weather (now);
2. several `.miz` variants;
3. **pydcs pre-generation:** a Python step writes weather, time and date into the `.miz` before launch. The most powerful option, since Python already runs on the server box. Open: now, later or never.

**Later, from the original concept:**
- **Objective tracking:** a per-mission handler counting kills against the target's critical objects → success or fail, reported to the player. Open: binary, or a score tied to a cost tracker like Syria's?
- **Session history** (`Saved Games\DCS\kola_f16_history.lua`): mission type, target, base, outcome, to down-weight repeats. Plus `FORCE_MISSION_TYPE` / `FORCE_TARGET` overrides for testing.
- **Tankers** on tracks behind the front, with TACAN and frequency in the frag (range: Bodø → Murmansk is ~700 km; an F-16 with 2 bags and a strike load is tight past ~300 nm radius).
- **Other mission types:** naval strike on moored ships in Kola Bay (ship-spawn research needed), recon of a mobile target in a search box, CAS from Syria's `cas_mission.lua`.

**Sources** (general; each map's own in its mission's plan):
- [Skynet IADS](https://github.com/walder/Skynet-IADS)
- [pydcs](https://github.com/pydcs/dcs)
- [Airgoons DCS air-defence reference](https://www.airgoons.com/w/DCS_Reference/Air_Defences/Western)
