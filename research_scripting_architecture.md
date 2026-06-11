# DCS Scripting Architecture — Research Notes

## Is It All Lua?

Yes. Everything inside a running mission is Lua. DCS exposes a "Simulator Scripting Engine" (SSE) running Lua 5.2. There is no other option for in-mission gameplay logic.

There is a separate Python-based tool (DCSServerBot) for Discord/admin integration, but that operates outside the mission itself via the Hooks environment.

---

## Two Separate Lua Environments

### Mission Scripting Environment (SSE)
- Runs inside the DCS server process, alongside the simulation
- Full access to the DCS World API: spawn units, control AI, manage coalitions, build the F10 menu
- **Sandboxed by default** — `os`, `io`, and `lfs` modules are disabled in `Scripts/MissionScripting.lua` in the DCS install folder
- De-sanitization (commenting out three lines in that file) is required to read/write files or use external paths
- Must be redone after every DCS update
- Scripts run synchronously on the simulation thread — a slow or hung script degrades or freezes the server
- Maximum recommended per-frame execution budget: ~22.5ms at 30 FPS

### Hooks / GUI Lua Environment
- Files placed in `Saved Games\DCS\Scripts\Hooks\*.lua` are loaded automatically at DCS startup
- Runs in a separate Lua state — the administrative/GUI layer
- Lifecycle callbacks: `onMissionLoadBegin`, `onSimulationStart`, `onPlayerConnect`, `onPlayerDisconnect`, etc.
- Access to `net` API (chat, player management, mission loading) and server admin functions
- **Cannot** access the full in-mission API — cannot spawn units from a hook
- Used by tools like DCSServerBot, SLmod (slot management), TacView integration

### Export Environment (not relevant here)
- Third separate Lua state for cockpit data export (DCS-BIOS, Helios, TacView)
- Uses `Export.*` functions — not useful for mission logic

---

## How Scripts Get Loaded Into a Mission

### DO SCRIPT
- Lua code typed or pasted directly into the Mission Editor trigger text box
- Embedded as raw text inside the `.miz` file
- Good for short snippets; no syntax highlighting, hard to edit

### DO SCRIPT FILE (embedded)
- Points to a `.lua` file that is embedded inside the `.miz` archive
- The `.miz` file is a standard ZIP archive — scripts are copied into it when added via the ME
- Subsequent edits to the file on disk are NOT automatically picked up; must re-add through the ME

### DO SCRIPT FILE (external, requires de-sanitization)
- After de-sanitizing, use `dofile()` inside a DO SCRIPT to load from anywhere on the filesystem
- `lfs.writedir()` → `C:\Users\<username>\Saved Games\DCS\`
- `lfs.currentdir()` → DCS installation directory
- Enables version control and normal editor workflows — scripts live outside the `.miz`

### Hooks Folder
- `Saved Games\DCS\Scripts\Hooks\*.lua` files are loaded automatically at DCS startup (alphabetical order)
- No trigger required; runs in the Hooks Lua state, not the mission state

### Script Execution Order
1. Initialization script (pre-spawn, earliest)
2. Group spawn conditions
3. Mission Start triggers (top-to-bottom)
4. Waypoint 1 scripts
5. Time-based triggers
6. Waypoint 2+ scripts

---

## How Scripts Are Typically Organized

### Standard Layered Pattern
```
MISSION START trigger  → DO SCRIPT FILE → mist.lua          (base library)
TIME MORE(1) trigger   → DO SCRIPT FILE → Moose_.lua         (framework, if used)
TIME MORE(2) trigger   → DO SCRIPT       → bootstrapper: dofile(...) loads external modules
```

### Common Patterns
- **Single-file** — one `init.lua` with all setup; fine for simple scenarios
- **Modular/multi-file** — separate files by domain: `ground_defense.lua`, `air_defense.lua`, `logistics.lua`, etc. Dominant pattern for anything serious
- **Dynamic loader** — scans a directory and loads all `.lua` files in alphabetical order; useful during development

---

## The F10 "Other" Menu

The `missionCommands` singleton is the only interactive UI channel available to scripts during a mission. No HUDs, pop-ups, or custom UI — only the F10 > Other menu and text overlays.

### Core API
```lua
-- Add a command for all players
missionCommands.addCommand(name, path, functionToCall, arg)

-- Create a submenu (returns a path table)
local sub = missionCommands.addSubMenu(name, parentPath)

-- Coalition-scoped (only Blue or Red players see it)
missionCommands.addCommandForCoalition(coalition.side.BLUE, name, path, func, arg)
missionCommands.addSubMenuForCoalition(coalition.side.RED, name, parentPath)

-- Group-scoped (only players in that group see it)
missionCommands.addCommandForGroup(groupId, name, path, func, arg)

-- Remove items
missionCommands.removeItem(path)
missionCommands.removeItemForCoalition(side, path)
missionCommands.removeItemForGroup(groupId, path)
```

### Notes
- Menu items persist for the life of the mission unless explicitly removed
- No native dynamic refresh — must remove and re-add to change items
- MOOSE wraps this API in `MENU_MISSION`, `MENU_COALITION`, `MENU_GROUP` classes with automatic path management

---

## Scripting Frameworks

### MIST (Mission Scripting Tools)
- GitHub: https://github.com/mrSkortch/MissionScriptingTools
- A foundational utility library — the community's standard library for DCS Lua
- Does not automate anything on its own; gives you better tools to write your own logic
- Provides:
  - Improved event handler system
  - Group management: spawn, respawn, teleport, task assignment, patrol routes
  - Zone/position utilities: random point in zone, line-of-sight checks, terrain validation
  - Coordinate conversion: MGRS, lat/lon, bearing/range, vector math
  - Unit conversion: meters↔NM, feet, etc.
  - Scheduling: `mist.scheduleFunction()` for time-delayed execution
  - Serialization and deep-copy utilities
- **Required** by many community scripts: CTLD, CSAR, Medevac, some SRS integrations
- **Best choice for a small private server** — low overhead, widely compatible

### MOOSE (Mission Object-Oriented Scripting Environment)
- GitHub: https://github.com/FlightControl-Master/MOOSE
- Docs: https://flightcontrol-master.github.io/MOOSE_DOCS/
- Large, opinionated OOP framework with hundreds of pre-built classes
- Pre-built systems include:
  - **RAT** — random AI air traffic
  - **AIRBOSS** — full carrier operations (Case I/II/III, LSO grading)
  - **GCICAP / AWACS** — automated GCI and AWACS management
  - **MANTIS / SEAD** — automated IADS and SEAD suppression
  - **SPAWN** — advanced group spawning with templates and scheduling
- Load `Moose_.lua` (combined minified build) via DO SCRIPT FILE at MISSION START
- Your scripts must load at TIME MORE(1) or later
- Heavy (~2-3 MB); load time is perceptible
- **Choose MOOSE when** you specifically want one of its pre-built high-level systems

### SSE / MSF (Mission Scripting Foundation)
- SSE is the underlying DCS scripting engine itself — the Lua API shipped with DCS
- MSF is ED's own lightweight official framework, documented on the Hoggit wiki
- Rarely used compared to MIST/MOOSE but represents the "official" layer
- Provides: `mission.model`, `mission.controller`, `mission.view`, `mission.utils`

### Framework Comparison

| | MIST | MOOSE | Bare SSE |
|---|---|---|---|
| Size | Medium | Very large | None (built-in) |
| Learning curve | Low | High | Medium |
| Style | Procedural utilities | Object-oriented classes | Procedural |
| Pre-built systems | None (tools only) | Many | Limited |
| Community script compatibility | Required by CTLD, CSAR, etc. | Self-contained | SSE-compatible |
| Suitable for small private server | **Yes — recommended** | Yes, if you need the features | Yes, for minimal setups |

### Notable Community Scripts
- **CTLD** (Combat Troops & Logistics Deployment) — helicopter logistics, crate spawning, FARP construction; requires MIST
- **CSAR** (Combat Search & Rescue) — downed pilot rescue; requires MIST
- **Skynet IADS** — coordinated air defense (SAMs share radar tracks, react to HARM, coordinate sectors); no dependencies — https://github.com/walder/Skynet-IADS
- **SkyEye** — AI GCI controller with voice recognition and neural TTS; requires SRS
- **Splash Damage** — realistic blast physics and secondary explosions; no dependencies
- **DCSServerBot** — Python-based Discord bot for server admin via hooks — https://github.com/Special-K-s-Flightsim-Bots/DCSServerBot

---

## Filesystem Layout

### Inside the .miz Archive
- The `.miz` is a standard ZIP file — open with 7-Zip or WinRAR
- Scripts added via DO SCRIPT FILE in the ME are copied into the archive root
- Self-contained; easier to share, harder to version-control and iterate on

### External Scripts (recommended for development)
```
Saved Games\DCS\                         ← lfs.writedir()
    Scripts\
        Hooks\                           ← Auto-loaded at DCS startup (hooks state)
            MyServerHook.lua
        MyMission\                       ← User-defined; loaded via dofile()
            init.lua
            module_air.lua
            module_ground.lua
            module_logistics.lua
            utils.lua
```

### DCS Installation Directory
- `lfs.currentdir()` → DCS install root
- `Scripts\MissionScripting.lua` here is the sandbox config to de-sanitize
- Do NOT put custom scripts here — DCS updates wipe it

### Hybrid Approach (common in production)
- Framework files (MIST, MOOSE) embedded in `.miz` — they change rarely
- Custom mission modules loaded externally via `dofile()` — enables version control

---

## Recommended Architecture for a Small Private Server

1. **De-sanitize** `MissionScripting.lua` (comment out `os`, `io`, `lfs` lines) — must redo after DCS updates
2. **Mission Editor triggers:**
   - `MISSION START` → `DO SCRIPT FILE` → `mist.lua` (embedded in .miz)
   - `TIME MORE(1)` → `DO SCRIPT` → `dofile(lfs.writedir() .. "Scripts\\MyMission\\init.lua")`
3. **On-disk layout** under `Saved Games\DCS\Scripts\MyMission\` (version-controlled in this repo):
   - `init.lua` — loads all modules in order, sets up F10 menu skeleton
   - `spawning.lua` — dynamic ground unit spawning logic
   - `air_defense.lua` — Skynet IADS or custom SAM logic
   - `logistics.lua` — CTLD/CSAR setup if desired
   - `admin.lua` — server admin F10 commands
   - `utils.lua` — shared utilities
4. **F10 menu** — built in `init.lua`, one submenu per module

---

## Sources

- [Simulator Scripting Engine Documentation — Hoggit Wiki](https://wiki.hoggitworld.com/view/Simulator_Scripting_Engine_Documentation)
- [Scripting Engine Introduction — Hoggit Wiki](https://wiki.hoggitworld.com/view/Scripting_Engine_Introduction)
- [Mission Scripting Foundation Documentation — Hoggit Wiki](https://wiki.hoggitworld.com/view/Mission_Scripting_Foundation_Documentation)
- [Mission Scripting Tools (MIST) — Hoggit Wiki](https://wiki.hoggitworld.com/view/Mission_Scripting_Tools_Documentation)
- [DCS singleton missionCommands — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_singleton_missionCommands)
- [DCS func addCommand — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_addCommand)
- [DCS server gameGUI — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_server_gameGUI)
- [Miz mission structure — Hoggit Wiki](https://wiki.hoggitworld.com/view/Miz_mission_structure)
- [Lua environment — DCS Official FAQ](https://www.digitalcombatsimulator.com/en/support/faq/1253/)
- [MOOSE GitHub](https://github.com/FlightControl-Master/MOOSE)
- [MOOSE Documentation](https://flightcontrol-master.github.io/MOOSE_DOCS/)
- [MOOSE Hello World Build Guide](https://flightcontrol-master.github.io/MOOSE/beginner/hello-world-build.html)
- [MOOSE De-Sanitize Guide](https://flightcontrol-master.github.io/MOOSE/advanced/desanitize-dcs.html)
- [MIST GitHub](https://github.com/mrSkortch/MissionScriptingTools)
- [DCS-gRPC GitHub](https://github.com/DCS-gRPC/rust-server)
- [DCSServerBot GitHub](https://github.com/Special-K-s-Flightsim-Bots/DCSServerBot)
- [Skynet IADS GitHub](https://github.com/walder/Skynet-IADS)
- [DCS World Scripting & Popular Scripts Beginners Guide — LetsFlyvfr](https://letsflyvfr.com/dcs-world-scripting-popular-scripts-beginners-guide/)
- [Mission Scripts — DCS Dev Index](https://it-dev-group-6.github.io/dcs-dev-index/mission-scripts.html)
- [LUA Scripting Radio Commands (F10) — ED Forums](https://forum.dcs.world/topic/90202-lua-scripting-radio-commands-f10/)
