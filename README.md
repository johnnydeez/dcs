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
    radio_calls/              Darkstar's spoken calls: radio player and helper, run outside DCS (below)
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

## Kola radio calls (Darkstar on the radio)

Darkstar, Blue's AWACS, speaks its picture calls (every 2 min) and threat calls (a hot hostile inside 40 nm, at once) in a Windows voice with a radio sound, played to Windows' default sound output. Everything is in `missions/kola_f16_random_tasking/radio_calls/`, Python standard library only (3.7+; the scripts use Python 3.10 at `%LOCALAPPDATA%\Programs\Python\Python310` when it's there).

Two programs run outside DCS:

| Program | What it does |
|---|---|
| `radio_player.py` | listens on 127.0.0.1:47110, puts the radio sound on each call and plays them one at a time (threat calls first) |
| `speak_mission_calls.py` | the helper: reads the calls the mission writes to `mission_calls.jsonl`, words them from `awacs_phrases.json`, speaks them (Zira) and sends them to the player |

### Starting it

**Nothing to do in a normal run.** At mission start the mission runs `start_radio_calls.cmd`, which opens both programs in minimised windows ("Kola radio player", "Kola radio helper"). Both close themselves once DCS has quit. Starting one that is already running does nothing, so a second mission in the same DCS session reuses them.

By hand (to test, or if the mission didn't start them), double-click `radio_calls\start_radio_calls.cmd`, or start each in its own window from `radio_calls\`:

```bash
python radio_player.py            # Ctrl+C to stop
python speak_mission_calls.py     # Ctrl+C to stop
```

Started by hand without `--exit-with-dcs`, they keep running until stopped.

### While it runs

- **The helper's window** (and `radio_calls\speak_mission_calls.log`, rewritten each start) shows every call's words and how long wording and voice took, or why a call wasn't spoken ("NOT SENT: no radio player running").
- **The player's window** shows each call played, its length and delay, and calls replaced by a newer picture or dropped as too old.
- **The event log** has `PICTURE_CALL` lines for every picture, `PICTURE_CALL … threat:` for threat calls.
- **Changing phrases** (`awacs_phrases.json`): the helper reads them when it starts, so close the helper window (or start the next mission after it has closed with DCS).
- **Changing the sound** (`radio_sound_settings.json`): read fresh for every call, no restart.
- **Switched off** in the mission: `RADIO_CALLS.enabled = false` (`kola_f16/data/radio_calls.lua`), which also sets the player callsign ("Snake one one") and the threat call's range.

### Trying it without DCS

With the player running, from `radio_calls\`:

```bash
python play_sample_awacs_calls.py                        # seven sample calls in a row
python play_sample_awacs_calls.py --repeat 4 --only 3    # one call 4 times, to hear the variety
python play_sample_awacs_calls.py --text-only            # print the words only
python send_radio_call.py --voice "Microsoft Zira Desktop" --say "Snake one one, Darkstar, picture clean."
```

### If nothing plays

1. Is "Kola radio helper" open? If not, `os.execute` may be sanitized (see below) or Python wasn't found: start `start_radio_calls.cmd` by hand.
2. Does the helper's window show the calls? If not, check `dcs.log` for `Radio calls:` (the mission's start line, with the calls file it writes).
3. "NOT SENT": the player isn't running; start it.
4. Calls played but not heard: the player plays to Windows' default output device; check the volume mixer.

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
