# DCS missions

Scripted DCS World missions, one folder per mission. Nothing is shared in code between missions.

```
desanitize_dcs.py        shared setup: lets mission scripts load files (below)
research/                DCS research that isn't tied to one mission (API findings, map research)
missions/
  syria_a2g/                  dynamic air-to-ground sandbox on Syria (2 players, Blue)
    INSTALL.md                how to install and start it
    notes.md                  status and design: start here
    a2g_dynamic_syria.miz
    a2g_dynamic_syria/        scripts → Saved Games\DCS\Scripts\a2g_dynamic_syria\
    offline_test_harness.lua  runs the scripts outside DCS with luae.exe (usage in its header)
  kola_f16_random_tasking/    F-16 tasking generator on Kola (air denial, human strike missions)
    development_docs/
      plan.md                 status and design: start at "Where we are"
      roadmap.md              where the mission is headed next (features, open questions, order)
      bugs.md                 bugs found in runs, to come back to
      closed.md               finished roadmap items and fixed bugs, keeping their numbers
    event_logs/               one event log per mission run (git-ignored; see below)
    kola_f16_random_tasking.miz
    kola_f16/                 scripts → Saved Games\DCS\Scripts\kola_f16\
    kola_data_tools/          offline Python tools that generate kola_f16/data (stdlib only, 3.7+)
```

Each mission's script folder has the same name in the repo as in `Saved Games\DCS\Scripts\`, so deploying is a plain copy of that folder.

## Watching the Kola event log live

Each Kola mission run writes a new file to `missions/kola_f16_random_tasking/event_logs/`: every event of the air war in plain language, unit by unit. Start one of these once the mission has loaded; each follows the newest file.

PowerShell:

```powershell
Get-Content (Get-ChildItem "$env:USERPROFILE\Git\dcs\missions\kola_f16_random_tasking\event_logs\*.log" | Sort-Object LastWriteTime | Select-Object -Last 1) -Wait -Tail 40
```

Git Bash:

```bash
tail -n 40 -f "$(ls -t ~/Git/dcs/missions/kola_f16_random_tasking/event_logs/*.log | head -1)"
```

Without the once-a-minute position lines, add `| Where-Object { $_ -notmatch 'POSITION' }` (PowerShell) or `| grep --line-buffered -v POSITION` (Git Bash) to the end. What each line means, and what to grep for: `development_docs/plan.md`, *Event log* and *Reading a run*.

## De-sanitize MissionScripting.lua

Every mission here needs it.

1. Open a terminal as Administrator (right-click → "Run as administrator")
2. Run: `python desanitize_dcs.py`
3. Fully restart DCS (not just the mission)

**Re-run after every DCS update** — updates reset MissionScripting.lua, which breaks script loading with `attempt to index global 'lfs' (a nil value)`.

### Manual alternative

Edit `C:\Program Files\Eagle Dynamics\DCS World\Scripts\MissionScripting.lua` and comment out the 6 lines inside the `do...end` sanitize block:

```lua
do
    -- sanitizeModule('os')
    -- sanitizeModule('io')
    -- sanitizeModule('lfs')
    -- _G['require'] = nil
    -- _G['loadlib'] = nil
    -- _G['package'] = nil
end
```
