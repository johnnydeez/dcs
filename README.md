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

## Kola radio calls (Darkstar, AI pilots and airfields on the radio)

Blue's radio, spoken in Windows voices with a radio sound, played to Windows' default sound output. Everything is in `missions/kola_f16_random_tasking/radio_calls/`, Python standard library only (3.7+; the scripts use Python 3.10 at `%LOCALAPPDATA%\Programs\Python\Python310` when it's there).

**Who talks, on which channel.** You hear a channel only while one of your F-16's radios is on it (see *Your jet's radios* below):

| Channel | Frequency | What's on it |
|---|---|---|
| AWACS | UHF 262.000 | Darkstar's picture (every 2 min) and threat calls (a hot hostile inside 40 nm); AI flights checking in and out with Darkstar |
| Mission (tactical common) | VHF 140.000 | AI flights' tactical calls: pushing, Fox one / two / three, Magnum, rifle, bombs away, splash, defending, a wingman down, Winchester, bingo, off target |
| Each Blue airfield | its tower VHF (the map's own, shown in *Airfield info*; 122.800 where the map has none) | AI traffic, the way an uncontrolled field works: taxiing, departing, inbound, final, clear of the runway; heard within 40 nm of the field |

The AI pilots' calls come from what their flights actually do (a watcher beside the controller), never from the controller's orders. Each flight has a callsign for the whole mission ("Weasel 3", its jets "Weasel 3-1", "Weasel 3-2"), the same in the brief and the air tasking order. Frequencies and call kinds: `kola_f16/data/radio_calls.lua`.

Two programs run outside DCS:

| Program | What it does |
|---|---|
| `radio_player.py` | listens on 127.0.0.1:47110, puts the radio sound on each call and plays them one at a time, never overlapping (combat and threat calls first; when more than 20 s is waiting, routine calls are dropped); plays only what your radios are tuned to |
| `speak_mission_calls.py` | the helper: reads the calls the mission writes to `mission_calls.jsonl`, words them (Darkstar: `awacs_phrases.json`; pilots: `pilot_phrases.json`; airfields: `airfield_phrases.json`), speaks them (Darkstar: Zira; pilots: the other voices in `pilot_phrases.json`, each jet its own) and sends them to the player |

### Your jet's radios (one line in DCS's Export.lua)

The radio player plays a call only when one of your F-16's radios is on and tuned to that call's frequency, at that radio's volume knob, the way SRS does it. To read the radios it uses our own small script, `radio_calls\export_cockpit_radios.lua`, which DCS runs through its export system. It only reads the cockpit (UHF and VHF frequency, on / off, volume), twice a second, and sends that to the radio player on 127.0.0.1 (UDP 47112). It never changes anything in the jet. It keeps every other export script working, SRS included. It is not a mod and nothing in the DCS install folder changes.

**Setting it up (once per PC; for a friend too):**

1. **The line goes in** `C:\Users\<you>\Saved Games\DCS\Scripts\Export.lua` (`DCS.openbeta` instead of `DCS` on an open beta install). The radio player adds it by itself when it starts, at the end of the file, next to SRS's line if you have SRS, and says so in its window: "added a line to …Export.lua: restart DCS once". It never touches any other line.
2. **By hand instead:** open that file in Notepad (create it if it isn't there) and add this as a line of its own at the end, with the path to *your* copy of the repo:
   ```lua
   pcall(function() dofile([[C:\Users\<you>\Git\dcs\missions\kola_f16_random_tasking\radio_calls\export_cockpit_radios.lua]]) end, nil) -- Kola radio calls
   ```
3. **Restart DCS once.** DCS reads Export.lua only when it starts. The first time, the radio player adds the line when a mission starts it, so that whole DCS session still plays every call; the filtering works from the next DCS start on.
4. **Check it works:** start the radio player, sit in an F-16 cockpit. The player's window says "hearing the jet's radios from DCS: F-16C_50, UHF 262.000 on vol 0.60, VHF …". `dcs.log` has `KOLA-RADIOS … sending the jet's radios`.
5. **Taking it out:** delete that one line from Export.lua (and restart DCS). With it gone the player plays every call, as before.

Notes:
- **Until the line is loaded**, or in a type the script doesn't read yet (only the F-16C for now), or in a spectator slot, every call is played, as before.
- **To hear a channel:** tune your UHF (or VHF) to its frequency. The frag's `RADIO` line and the start text list them; each base's *Airfield info* shows its traffic frequency. Turn a radio's volume down or off to silence that channel.
- **Multiplayer (not built yet):** the friend's PC will run only the radio player and this export line. The host's mission will send it the calls over ZeroTier, and it plays what the friend's jet is tuned to. Until that's built, calls play on the host's PC only.

### Starting it

**Nothing to do in a normal run.** At mission start the mission runs `start_radio_calls.cmd`, which opens both programs in minimised windows ("Kola radio player", "Kola radio helper"). Both close themselves once DCS has quit. Starting one that is already running does nothing, so a second mission in the same DCS session reuses them.

By hand (to test, or if the mission didn't start them), double-click `radio_calls\start_radio_calls.cmd`, or start each in its own window from `radio_calls\`:

```bash
python radio_player.py            # Ctrl+C to stop
python speak_mission_calls.py     # Ctrl+C to stop
```

Started by hand without `--exit-with-dcs`, they keep running until stopped.

### While it runs

- **The helper's window** (and `radio_calls\speak_mission_calls.log`, rewritten each start) shows every call's words, channel and frequency, and how long wording and voice took, or why a call wasn't spoken ("NOT SENT: no radio player running").
- **The player's window** shows each call played (on which radio, how long after the event), and calls not heard ("no radio tuned to 140.000"), replaced by a newer picture, dropped as too old, or dropped because the radio fell more than 20 s behind.
- **The event log** has `PICTURE_CALL` lines for every picture, `PICTURE_CALL … threat:` for threat calls, and `RADIO_CALL` for every AI pilot's call (what, on which channel, by whom).
- **Changing phrases** (`awacs_phrases.json`, `pilot_phrases.json`, `airfield_phrases.json`; check them with `python flight_phrase_wording.py`, which also prints samples): the helper reads them when it starts, so close the helper window (or start the next mission after it has closed with DCS).
- **More voices** for the pilots: add them in Windows (Settings, Time & language, Speech, Add voices), then list them in `pilot_phrases.json` (`voices`); `python windows_voice.py --list` shows what the scripts can use (both Windows speech engines). A listed voice that isn't installed is skipped. Windows' "natural" voices (Ryan, Andrew, Sonia, Guy, Prabhat, …) don't show there: Windows keeps them for Narrator.
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
5. "not heard, no radio tuned to …" in the player's window: tune a radio to that frequency (or the radio is off or turned down).

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
