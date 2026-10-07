# DCS missions: closed issues

**The one closed list for the whole repository** (John, 2026-10-07: one `closed.md` at the root, as with `bugs.md`). Fixed bugs from `bugs.md` and finished roadmap items from any mission's or the framework's `roadmap.md` move here, so those files only hold open work. Each keeps its original number and text, as it stood when it was closed, with the discussion that led to it, and a line saying when and why it was closed.

**What each one is for:** a bug closed from 2026-10-07 on keeps its `**For:**` line from `bugs.md` (a mission, or `framework`). Everything closed before that was Kola's, from Kola's own `roadmap.md` and `bugs.md`, and carries no `**For:**` line; most of the code it names is shared framework code now.

Until 2026-10-07 this was Kola's `development_docs\closed.md`. What was actually built, and how it behaves, is in the shared mission framework's `shared_mission_framework\development_docs\as_built.md` (a `plan.md` section named below that isn't in Kola's `plan.md` is there, under the same name; `kola_data_tools\` is the framework's `map_data_tools\`). An `event_logs\…` path is in the mission folder of the mission it was found in (`missions\<mission>\event_logs\`); before 2026-10-07, always Kola's.

---

## Roadmap items

### 1. Radar functions: one shared radar picture

**Status: done for now (2026-09-30).** Built, run once in DCS (session 11) and used by scrambles and the leash. As built, and what the run showed: `plan.md`, *Radar picture*.

**Goal:** each coalition builds its own threat picture from what its radars actually report, and keeps it as the mission runs. Scrambles (2), AWACS calls (5), live intel for fog of war (9) and any later AI behaviour rule all read it. So it's built once, and those features act only on what the defenders could really know.

**What it's for:** the picture is for our script, not for the AI's own awareness. DCS already shares radar contacts between same-coalition AI over its built-in datalink, and a script can't add to that. The script uses the picture to decide things and passes the result to the AI as tasks: who scrambles, against which group (`EngageGroup`), when they go home (the leash), what the AWACS tells the player. It's runtime state kept in memory (like the scheduler's), not part of the plan. Planning stages never read it: frags are built before anything flies.

**What DCS offers** (discussed 2026-09-30):
- **`Controller:getDetectedTargets(detection types)`:** a group's detected objects, each with `visible` (line of sight), `type` (the type is known) and `distance` (the range is known; false = bearing only, e.g. jammed). Ask for `RADAR` only: `DLINK` would return contacts shared from other units, and everyone would echo everyone.
- **`Controller:isTargetDetected(object)`:** adds the last time seen, last position and last velocity.
- **Ground units answer only through their group's controller;** aircraft answer at group or unit level.
- **`Unit:hasSensors(RADAR)` / `getSensors()`:** which units carry a radar. **`Unit:getRadar()`:** whether the radar is on, and which object it's tracking (later: "spiked" warnings).
- **`Object:getPoint()` / `getVelocity()`:** exact position and speed once a radar has reported the object. That's fair: the radar measured them.
- **What DCS already simulates before a contact appears:**
  - each radar type's range;
  - line of sight and terrain masking, and the radar horizon;
  - the target's size, roughly;
  - fighter radars' forward search cone.
- **A radar that's switched off sees nothing:** alarm state green, or a site that Skynet (item 8) keeps dark.

**Where it stands:**
- `consumers/run_scrambles.lua` (session 7, switched off) already polls a planned list of radar groups with `Controller:getDetectedTargets(RADAR)` every 30 s. The polling works in DCS: `31 of 31 answered` (Red), `21 of 21` (Blue).
- Red's A-50 saw a Blue F/A-18 near Rovaniemi at T+9 min.
- The polling is inside the scramble consumer and nothing else can read it. It keeps only the group name, position, type and the first radar that saw it, with no memory between polls.

**Approach (agreed with John, 2026-09-30):**
- **Its own consumer,** running from mission start whether or not scrambles are on, with one picture per coalition.
- **Poll every 30 s** (John: plenty often, also for AWACS calls; MP servers' AWACS call about that often). Ask the sensors in turn across the interval, so there's no spike.
- **Sensors:** early-warning radars, SAM search radars, the AWACS while it's alive, and the patrols' own radars (datalinks really do merge fighter radars into the picture). Find them from the units (`hasSensors`) instead of a list planned in advance. From the base defenses, only the `radar_missile_launchers` component counts (Pantsir, Tor, Roland); gun fire-control radars (Shilka, Gepard, Vulcan) don't really report to a network (John agreed). Tag each sensor by kind, so a consumer can tell "the AWACS saw it" from "a SAM radar saw it" or ignore fighter radars.
- **A contact is a DCS group.** Merging groups that fly close together, the way a real controller would, can come later for the AWACS calls.
- **Per contact:**
  - position, altitude, heading and speed;
  - which sensors see it, first seen, last seen;
  - `type_known`, and the type only if some sensor knows it (otherwise "unknown");
  - `range_known` (false = a bearing-only strobe, not a position);
  - airspace (own / contested / enemy) from the existing grid;
  - nearest own base, whether it's inside an own SAM ring, inbound or outbound.
- **Memory:** a missed sweep doesn't drop a contact. It turns into "last seen N s ago" and is dropped after a few minutes.
- **What other code can ask:** contacts in an airspace, contacts within X km of a point, one group's contact. Events: new contact, entered own airspace, contact lost.
- **Detection is taken from DCS as it is:** no masking or range model of our own. Jamming is a later, optional item (see the end of this file).
- **Logging:** a periodic `picture:` line per coalition (contacts by airspace), plus first-seen and lost lines, like the `track:` lines.
- **Who reads it:**
  - **Scrambles:** launch triggers, the `EngageGroup` target, the leash.
  - **AWACS calls:** BRAA and type for contacts near the player.
  - **Human missions:** Red's picture of the player, so flying low through terrain really keeps Red from scrambling. Later also in-flight updates.
  - **Fog of war:** "last seen" marks.
  - **Cruise missiles:** launch calls, if radars report missiles.
  - **CAP:** patrols already engage through DCS's native datalink and their zone tasks. The picture could send them toward a contact later.
- **No map drawing of contacts** (John: it would clutter the map, and the full debug map already shows every aircraft). Drawing the picture for players is an optional item at the end of this file, for after fog of war.

**Structure (agreed with John, 2026-09-30):**

| File | Holds |
|---|---|
| `consumers/track_radar_picture.lua` → `TrackRadarPicture` | the module: finding sensors, polling, contacts, queries, events, logging |
| `data/radar_picture.lua` → `RADAR_PICTURE` | settings only: `poll_interval_s` 30, `stale_after_s`, `drop_after_s`, `log_every_s`, which sensor kinds count |

- **Start order:** in `init.lua`, `TrackRadarPicture.start(plan)` comes after `ScheduleAirTaskingOrders.start`, since it needs to know which flights are patrols and which is the AWACS. It comes before `RunScrambles` and the brief, which will read it.
- **Reads the plan, never writes it,** and gives no orders. Its state (sensors, contacts) is runtime state, keyed by the plan's group ids.

**Inside the module:**
```
 every ~3 s: poll the next 1/10 of the sensors       ← round robin, no spike
        │  getDetectedTargets(RADAR) per group
        ▼
 seen this cycle  { enemy group → sightings }
        │  at the end of each 30 s cycle
        ▼
 update contacts ─► derived facts ─► events ─► logging
 (new / refreshed / stale / dropped)
```
1. **Finding sensors.**
   - **Ground groups, once at start:** each coalition's groups with a radar (`hasSensors`), with the kind taken from the plan: `early_warning` (a SAM site with layer `early_warning`), `sam_search` (other SAM sites), `base_defense` (`DEF_…` groups of the `radar_missile_launchers` component only).
   - **Aircraft, every cycle:** `awacs`, `patrol` or `scramble`, from the flight's mission type in the plan. Attack flights aren't sensors (their radars are busy with ground work).
   - **Dead groups drop out,** so losing the AWACS thins the picture on its own.
2. **Polling:** round robin through the 30 s cycle. Keep only enemy aircraft that are airborne (planes and helicopters; missiles too if the DCS test shows radars list them).
3. **One contact per enemy group,** in each coalition's table:
   ```
   contact = {
     group, first_seen, last_seen, seen_by = { sensor kind → count },
     pos, altitude_m, heading_deg, speed_mps,     -- getPoint / getVelocity at the latest sighting
     type_known, type,                            -- type only if some sensor knew it
     range_known,                                 -- false = bearing-only strobe
     airspace,                                    -- own / contested / enemy
     nearest_base, inside_own_sam_ring, inbound,
     state,                                       -- "tracked" / "stale"
   }
   ```
   Heading and speed come from `getVelocity` in one sample. That's as honest as two samples, since a radar track gives them too.
4. **Derived facts** use the plan: airspace from `DivideAirspace.kindFor(plan.airspace, pos, coalition)`, rings from `plan.sam_sites` (`engage_m`), bases from `plan.world`.
5. **Events** fire once per cycle, after the update, each listener run with `pcall` so a broken consumer can't stop the picture:
   - `new_contact`;
   - `airspace_changed` (e.g. contested → own: the scramble trigger);
   - `contact_stale` (not seen this cycle);
   - `contact_dropped` (past `drop_after_s`).
6. **Calls for other code:**
   ```
   TrackRadarPicture.on(coalition, event, fn)
   TrackRadarPicture.contacts(coalition, filter)            -- e.g. { airspace = "own" }
   TrackRadarPicture.contactsNear(coalition, pos, radius_m)
   TrackRadarPicture.contact(coalition, groupName)
   TrackRadarPicture.sensors(coalition)
   ```
7. **Logging** (grep `picture`):
   - every `log_every_s`: `RED picture: 3 contacts (own 1, contested 2), 28 of 30 sensors answered`;
   - on each event: `RED picture: new MSN2014 (F-16C) seen by early_warning SAM_OLEN_55G6_1, contested, 62 km from Olenya`, and `… entered own airspace`, `… stale`, `… dropped`.

**What it leaves alone:** `run_scrambles.lua` stays off, with its old poll, until item 2. There it gets reworked onto the picture (the `picture_updated` event added then), and its `radarPicture()` is deleted.

**Testing:**
1. **luae harness:** a stubbed `Controller` returns scripted detections. It checks the round robin, merging, going stale, events and airspace tags.
2. **The first DCS run only watches and logs,** so the mission plays exactly as before. Compare the `picture` lines with the `track:` lines and flight paths. The same run covers the DCS checks:
   - terrain masking: a low flyer against a ground radar;
   - a missile in flight: is it listed?
   - `getRadar()` on a SAM site tracking a jet;
   - whether the `type` and `distance` flags behave as described.

---

### 2. Fighter scrambles against enemy incursions

**Status: done for now (2026-09-30).** Rebuilt, run once in DCS (session 11): scrambles burned straight at their raids and the leash brought them home. Afterwards, alert jets return 30 min after landing, and scramble ids read `MSN2901_SCRAM`. The high losses of that run lead into item 4 (AI behaviour logic). As built, and what the run showed: `plan.md`, *Scrambles and the leash*. Found while testing and built in (John's intent, not new direction): no alert at a base inside an enemy kill zone; no scramble at a raid under enemy SAM cover; the picture's `inbound` is the time-to-threat test, so the leash's "heading away" means the same as the trigger. Raids: one scramble per raid, `EngageGroup` on each group (John: my judgment; tune as we go). After the target is dead: home.

**Goal:** quick-reaction fighters launch when enemy aircraft come into own airspace, triggered by what own radars actually see (item 1), not by knowledge the defenders couldn't have.

**Where it stands:**
- **Built in session 7:**
  - `consumers/run_scrambles.lua` checks every 30 s, per coalition. An enemy aircraft group inside a "defended air zone" (100 km round heavy bases, each SAM ring + 20 km) with no live scramble after it draws one single ship from the nearest alert base with a launch left, off cooldown, in reach and under the cap.
  - The alert posture (`planAlertPosture`) is the 3 held hub / fighter bases nearest the enemy, 3 launches each, 15 min apart.
  - Scramble ids are `MSN2901+` / `MSN5901+`, tracked by the scheduler like other flights. A scramble is refused (logged) when the coalition is already at its airborne cap.
- **Switched off in session 8,** for three reasons:
  - the scrambles flew `weapons_free` with `EngageTargets` (air, 40 km), the setup that made patrols chase into enemy SAMs;
  - in session 7 they helped wipe out whole packages, the opposite of air denial's rare, meaningful losses;
  - they share the airborne cap with patrols and packages.
- **Why have them at all:** QRA is real (Finland, Norway, Russia). Session 9's fourth run showed the gap: a Red raid on Rovaniemi came in under Red's own Sodankylä SA-10, where no Blue commit circle may reach, and only the SAMs answered. A scramble from Rovaniemi or Kemi-Tornio against a raid over Blue's own airspace is what would really happen.
- **Why session 7's scrambles were slow and indirect** (John noticed; found in `consumers/spawn_aircraft_groups.lua`):
  - `EngageGroup` sat on waypoint 2, the intruder's position *at launch*, and DCS starts a waypoint's tasks only on arrival. So the fighter flew to an old, empty spot before hunting.
  - Every waypoint had `speed_locked` at `cruise_speed_mps` (230–250 m/s), so the AI never used afterburner.

**Design (agreed with John, 2026-09-30).** The idea (John): a scramble answers an immediate threat. It burns straight at that one intruder and either chases it away or kills it, without flying head first into enemy airspace.
- **Trigger: warning time, not distance,** from the radar picture (item 1), checked every picture round (30 s):
  - **Time to threat:** project each tracked contact's heading. If the line passes within ~30 km of an own asset (a held base, a SAM site, a catalog target of value), the time to arrive there is the distance ÷ speed. **Scramble when it's under `scramble_warning_min` (15 min),** whatever airspace the contact is in, including one still over its own airspace. 100 km was far too close (John: a jet at 60 nm can have weapons on the base in ~5 minutes).
  - **Any contact over own airspace** is answered, whatever its heading.
  - "Inbound" must hold for **two rounds in a row** (60 s), so a Red patrol turning on its race-track doesn't trigger one.
  - Only `tracked` contacts with a known range; **helicopters are skipped** (optional helicopters item at the end).
- **Skip when a patrol covers it:** no scramble if an airborne patrol's defended zone or commit circle covers where the contact is (John agreed).
- **One-ships** from the alert bases:
  - **Alert bases:** any held base whose runway fits an interception type, the 3 nearest the enemy, at least one per pocket (John agreed; replaces hub / fighter only).
  - **Budget:** 3 alert jets per base, 15 min cooldown; a jet that lands is back on alert 30 min later, one shot down is gone (John, after the first run).
  - **Pick:** the nearest alert base with a launch ready, in the region facing the contact, with the intercept point in reach, and a way there with ≤ 5 km of enemy airspace and no enemy kill zone.
- **Reaction delay:** 1–2 min (cockpit alert), then a hot runway start.
- **Airborne cap:** scrambles may go up to **2 over** `max_airborne_aircraft` (John agreed).
- **Flying it (the session 7 fixes):**
  - `EngageGroup` on the intruder goes on the **takeoff waypoint**, so it's active from wheels-up, and the AI flies its own intercept at the target;
  - `open_fire`, with no `EngageTargets` on everything;
  - **dash speed** (a new `dash_speed_mps` per fighter in `data/aircraft_profiles.lua`, Mach 1.1–1.5) with afterburner explicitly allowed;
  - the intercept point (the contact pushed ahead along its heading) is capped at own or contested airspace, outside enemy kill zones;
  - the scheduler tracks the flight; `TrackRadarPicture.addFlight` makes it a `scramble` sensor.
  - **To test in DCS:** does `EngageGroup` give the AI the target's position before its own radar finds it? If not, re-point its route every round from the picture.
- **The leash: the first AI behaviour rule,** in `consumers/enforce_air_behaviour_rules.lua` (`EnforceAirBehaviourRules`), with settings in `data/air_behaviour_rules.lua`:
  - modules register the flights they want watched (`watch(flight, rule, target)`); it checks them every picture round;
  - **a scramble goes home when:** its target is dead; the target is dropped from the picture; the target is back over its own airspace (John: break off, chase them away or kill them); the scramble goes > 5 km into enemy airspace; or it enters an enemy kill zone (85 % of a ring). While the target is only stale, it keeps going to the last known position;
  - **going home:** `Controller:setTask` with a route home from where the jet is, and rules of engagement "return fire". Once sent home, it stays sent home. Fuel is DCS's (bingo);
  - later rules (strikes go home if their SEAD dies, patrols' leash) are new checks in the same module.
- **Logging** (grep `scramble`, `leash`): each launch with base, type, target, reason and minutes to threat; each refusal (once per reason); each leash decision with its reason.

**What changes in existing files:**
- **`planAlertPosture`:** the new alert-base pick; the defended air zones and the radar list go.
- **`data/air_tasking.lua`:** `interception` → `open_fire`, loses `engage_range_km`. `AIR_DEFENSE` → `alert_posture_planned = true`, loses `detection` and the air-zone settings, gains the trigger settings.
- **`consumers/spawn_aircraft_groups.lua`:** the `intercept` attack kind loses `EngageTargets`; attack tasks can go on the takeoff waypoint; scrambles fly at dash speed.
- **`consumers/run_scrambles.lua`:** rewritten around the picture.
- **Radar picture:** one more event, `picture_updated`, at the end of each round.
- **`init.lua`:** start `EnforceAirBehaviourRules`; un-comment `RunScrambles.start`.

**Testing:** luae harness with fake picture contacts (trigger, pick, refusals, every leash reason); then in DCS, John flies into Red airspace high, then low.

---

### 3. Event log: a readable file to watch during the mission

**Status: done (2026-09-30).** Built and run in DCS twice the same day (the second flown by John), then in every run since; its small fixes are bug 5 below. As built, and how to watch it: `plan.md`, *Event log*.

What John decided (2026-09-30):
- **Scope:** a catalogue of every event from the run, so one can comb through it and see how the mission unfolded unit by unit, step by step, without affecting game performance.
- **Gun hits:** collapsed, so they don't spam the log.
- **Files:** a new timestamped file per run.
- **Moving lines:** the flight, radar-picture, scramble and leash lines move out of `dcs.log` into the event log (my call, as John asked).

Filled in without asking:
- both coalitions go in one file, with a coalition column;
- a `POSITION` line per airborne aircraft every minute, replacing the `track:` lines;
- AAA and MANPADS fire shows as one `GUNS` line per burst series, plus folded hits and kills;
- the plan goes at the top of the file and a summary at the end.

The proposal below is kept as it was discussed.

**Goal:** a plain-language log of what's happening in the air war, in a file of its own that John can tail and watch while the mission runs, without grepping `dcs.log` (John, 2026-09-30).

**Where it stands:** nothing built. Everything is in `dcs.log` today, mixed with DCS's own lines and written for grepping (`MSN…`, `track:`, `picture`, `scramble`).

**Approach (proposed):**
- **One file per mission,** e.g. `Saved Games\DCS\kola_events.log`, started fresh when the mission loads. Every line is flushed at once, so `Get-Content -Wait` (PowerShell) or `tail -f` shows it live.
- **Human-readable lines,** mission time (local clock) first, both coalitions:
  - `12:43 RED scramble: MiG-31 from Monchegorsk after MSN2014 (F-16C), 11 min from Olenya`
  - `12:47 BLUE MSN2014 (F-16C) shot down by MSN5901 (MiG-31), 20 km inside Red airspace`
  - `12:51 RED MSN5901 (MiG-31) heading home: target back in Blue airspace`
- **Events worth a line:** takeoffs and landings, packages pushing, weapons released on targets, target objects destroyed, aircraft lost (by what), scrambles and leash decisions, new radar contacts over own airspace. Not the every-2-minute `track:` lines.
- **One small module** (`consumers/write_event_log.lua`, `WriteEventLog`) that the scheduler, scrambles, the leash and the radar picture hand events to. The same structured events can later feed the AI radio calls (item 7).

**Open:**
- Which events: the list above, or fewer?
- Both coalitions in one file, or one file each?
- Keep old files (a file per mission start) or overwrite each time?

---

### Performance in VR (was the unnumbered top priority)

**Status: done for now (2026-10-01).** First pass built and checked in a 2D run (`event_logs\2026-10-01_112448.log`: sleeping, waking and the cap worked; VR frame rate not measured). If performance is still a problem, it comes back as a new roadmap item. John's test: the same `.miz` with no units still stuttered; lowering forest detail, scenery detail and LOD a little got Kola back to 45 fps, even low. So the mission's own load is what's left, and the first pass is lean (John): step 2 levers 1–3 (no security infantry; one towed-gun group and one MANPADS team per base; short-reach base defenses asleep until an enemy aircraft is within 30 km) and a lower cap (12 per coalition, 2 of it kept for scrambles, which no longer go over it). The "Mark bad frame rate" entry is out (John: stutters are too short to mark while flying). As built: `plan.md`, *Sleeping ground units*, *Stage 2* and *Airborne cap*. Next: John flies it in VR.

**Goal:** the mission holds John's standard VR frame rate of 45 fps, with no big frame-time spikes, including on takeoff and low around airfields. The Syria mission already does (John: it "ran fine"). John, 2026-09-30: "It is now the top priority."

**What John saw** (first VR run of this mission, 2026-09-30, `event_logs\2026-09-30_213757.log`):
- Smooth at times and very choppy at times, with huge frame-time spikes.
- **Takeoff was the worst:** Kallax at 11:16:46, down to about 12 fps for a while after leaving the runway.
- Worse close to the ground and around airfields.
- **At about 11:25 game time it suddenly got much smoother.**
- No fair comparison yet: it was the first VR run of this mission. The 2026-09-25 performance baseline in `plan.md` had no AI aircraft flying and may not have been in VR.

**What the event log shows at those moments** (airborne AI from the `POSITION` lines, per minute):

| Time | Airborne AI | Shots / hits | What was happening |
|---|---|---|---|
| 11:05–11:15 | 19–22 | 13 / 4 | Blue SEAD over Sodankylä, first losses |
| 11:16–11:23 (John's takeoff) | 18–21 | 33 / 39 | Red's Rovaniemi raid (PKG5023) meets the SA-10, IRIS-T, NASAMS and the F-15C patrol: SAM salvos at Kh-31Ps, AIM-120s, 22 hits in the minute 11:18 |
| 11:25 | 17 | 1 / 1, 5 destroyed | the package's last three jets die |
| 11:26–11:32 (smooth) | 14–15 | 0 / 0 | quiet |
| 11:33–11:40 | 10–15 | 8 / 18 | PKG5027 dies to the F-16 patrol; John bombs Vuojärvi |

- The smooth patch starts exactly when the Rovaniemi battle ends and four fewer AI aircraft are flying. John was also climbing through ~26,000 ft by then, so altitude is mixed in.
- **The takeoff drop wasn't local ground units:** Kallax is a standard-level rear field, with 16 base-defense units and 11 SAM units within 30 km, and 4 static objects within 10 km. The battle was ~200 km away. That points at work that grows with the whole air war (AI jets, missiles in flight, every radar and shooter checking what it sees), not at what was near the player.
- No spawn took over 1 s during the run (no "the sim froze" line in `dcs.log`), and the first-spawn preload held.

**The load this mission puts in the world** (the 21:37 plan):

| | Count |
|---|---|
| AI ground units | **~960**: base defenses 543 (195 security infantry, 167 towed ZU-23s, 111 MANPADS teams, 34 mobile guns, 28 IR launchers, 8 radar launchers), SAM sites 346 (59 sites), fixed targets 64, convoy 10 |
| Static objects | 319 |
| AI aircraft airborne | peak 22 in this run; the cap allows 16 per coalition + 2 scrambles each over it |
| Map marks | several hundred debug drawings (all `…ToAll(-1)`) |

Syria caps its AI aircraft at 12 alive and has far fewer ground units (count them for the comparison).

**Suspects, most likely first:**
1. **AI aircraft × everything that looks at them (CPU, main thread).** Every AI unit that can shoot or has a sensor keeps checking what it can see. With ~900 ground shooters and 20+ aircraft, the work multiplies, and each AI jet adds its own flight model, sensors and combat logic. VR at 45 fps leaves ~22 ms per frame, and DCS's AI shares the main thread.
2. **Missiles in flight and explosions.** Each missile is a full physics object: SA-10 salvos at Kh-31Ps, AIM-120s, and blasts hitting 7 units at once. This fits the 11:16–11:25 spikes.
3. **The Kola terrain itself, low in VR** (GPU): dense forest near the ground, which the Syria desert doesn't have. It isn't the mission's doing, but it adds to "worse close to the ground" and needs a baseline to separate it out.
4. **Our scripts:** radar-picture polling (~10 controller calls every 3 s), `POSITION` (~22 reads a minute), string building on every DCS event, the scheduler, scrambles, the rules. Probably small, but never measured. Scripts would show as regular hitches, not a steady low frame rate.
5. **Map marks:** probably only matter while the F10 map is open.

**John's tests first (2026-09-30), before any edits to the mission:**
- **The same flight with no AI units:** the Kallax takeoff and the route to Vuojärvi, in VR. No `CONFIG` switch turns the generator off yet. The simplest way is to disable the mission's one ME trigger (`DO SCRIPT dofile(... "Scripts\\kola_f16\\init.lua")`) in a copy of the `.miz`. Kallax is an always-Blue field, so its slot still works without the script. That gives the terrain's own cost on the same flight.
- **DCS system and graphics settings** that don't change how the mission looks or plays for John but may help a lot.
- **John's reading so far:** the AI flights and the fighting between aircraft and SAMs are most likely the biggest hit (not a surprise). His results decide what gets built below.

**Step 1: measure** (small, behind `CONFIG` switches, before cutting anything):
- **Empty-map baseline:** the same `.miz` with the generator switched off (a `CONFIG` flag), John taking off at Kallax in VR. That gives the terrain's own cost at the same spot.
- **Frame-time overlay:** John runs one with CPU vs GPU frame time (OpenXR Toolkit or fpsVR).
- **A comms-menu entry "Mark bad frame rate"** that writes a `PERF` line to the event log with the time, the player's position and altitude, and the current load. John doesn't have to remember the time of a stutter.
- **A per-minute `LOAD` line in the event log:** alive ground units (active / idle), airborne aircraft, missiles in flight if countable, so frame-rate notes can be matched to the load.
- **Script timing:** `os.clock` around each consumer's tick; any tick over ~2 ms goes to `dcs.log`, plus a per-minute total per consumer.
- **A/B switches for runs:** no base-defense infantry; airborne cap 8 per coalition; base-defense AI off away from aircraft.

**Step 2: the likely levers,** best payoff for least realism lost:
1. **Base-defense security infantry:** remove it, or make it static objects. That's 195 units that are almost pure scenery (and 37 more at fixed targets).
2. **Base defenses wake only when an enemy aircraft is near:** guns, MANPADS teams and short-range launchers reach under 10 km. Their AI stays off (`Controller:setOnOff(false)`) until an enemy aircraft is within ~25–30 km, checked every ~10 s. On most frames ~500 units would be idle instead of scanning the sky. SAM sites stay on: they are the air denial. (Related: *Proximity spawning* in the `plan.md` backlog.)
3. **Fewer MANPADS teams per base,** or the same wake-up rule for them.
4. **SAM radars:** alarm state or emission control for sites far from any aircraft. This overlaps Skynet (item 8), which keeps sites dark until a target is close.
5. **A lower airborne cap,** from 16 per coalition to ~10–12. John said not to cut flight volume (session 8), so this comes last and only if the rest isn't enough.
6. **Scripts:** whatever step 1 shows is over budget.

**Open:**
- Is the wake-up rule acceptable for base defenses, and at what distance?
- Is removing the security infantry fine, or should it stay as static objects for looks?
- What frame rate counts as done: 45 fps steady everywhere, or 45 fps with short dips in the worst moments?

---

### 4a and 4b. AI behaviour logic: the controller, attack flights defending themselves, the bandit call

**Closed 2026-10-02** (parts of roadmap item 4, which stays open in `roadmap.md` for 4c and the controller's further directives). Built 2026-10-01; the bandit call first worked in the 22:23 run and again in the 2026-10-02 00:57 run. As built: `plan.md`, *The controller*.

What item 4's *Where it stands* said about them when they moved:
- **4a and 4b built 2026-10-01, not flown yet:** the controller, `consumers/control_air_flights/` (`plan.md`, *The controller*). Design agreed with John: DCS AI is the pilot; the script is the controller that watches the whole picture and gives directives (no separate pilot rules). Situation per flight → directives → one intent (priority, threat assignment across flights) → orders only when the intent changes. Directives so far: the leash and go-cold (moved over unchanged) and self-defence (4b).
- **Built 2026-10-01 (after the 20:31 run), not flown yet: the bandit call** (`plan.md`, *The controller*). It replaces self-defence's wait-for-our-missile-range trigger and covers the abort item below: when the picture shows a fighter hot on an attack flight within 100 km (two checks in a row), or one fires at it from any range, the controller decides at once: radar missiles aboard → engage now; none (infrared only counts as none) → go home (John: "the CAP is just going to stay there and circle"). With it, every Su-34 loadout carries 2× R-77 (John: every Red flight carries its best long-range air-to-air missiles). The original request, kept for reference:
- **Abort a defenceless flight** (John, 2026-10-01, 16:21 run: MSN5023_OCA, 2× Su-24M with only RBK-250s, heading for Kuusamo where the F-16 patrol MSN2016_CAP works): if the coalition's radar picture shows an enemy fighter that threatens an attack flight that can't fight it (no air-to-air missiles, or only short-range infrared ones against a fighter beyond their reach), the controller sends the flight home. Its own directive, next to self-defence: self-defence for flights that can fight, abort for those that can't. To settle when building: what counts as "threatens" (the same hot-and-closing test, at what range: the fighter's missile range rather than ours), and whether the package's mission is then retried later or cancelled. John (same day): infrared missiles alone are effectively useless against a fighter, so no R-60s added to the Su-24M's airfield-strike loadout; and **self-defence should count only radar-guided missiles** when deciding whether a flight can fight (today any air-to-air missile counts, and an infrared-only flight would turn toward a fighter at the 10 km minimum engage range). Change it together with the abort directive.

#### 4a. The logic layer: conditional orders

**Built 2026-10-01** as the controller (`plan.md`, *The controller*). The proposal as it stood:

**Approach (to design with John):**
- Every AI flight is watched, not only scrambles, each with the rules for its mission type.
- **The orders DCS offers a script:**
  - `Controller:setTask`: a new mission, e.g. go home;
  - `pushTask` / `popTask`: a task on top of the current one, then back to the mission (for "deal with this, then get back on task");
  - `setOption`: rules of engagement, reaction to threat, radar use, afterburner.
- Each rule is a check (from the radar picture, the flight's position, its package) plus an order, in one module, as the leash is.

#### 4b. Attack flights defend themselves, then get back on task

**Built 2026-10-01** as the controller's `self_defence` directive (`plan.md`, *The controller*). John's calls: stay on the mission until a threat threatens the mission (pointed at the flight and closing, or firing at it); after the fight, always carry on with the mission. Engage range from the missiles aboard; one threat per flight across the coalition; `AttackGroup` pushed on top of the mission and ended by a user flag (never `popTask`). The proposal as it stood:

**Goal:** strike, SEAD and DEAD flights that see a fighter coming for them fight back early, with the air-to-air missiles they carry, then carry on to the target. Today (John): "if a CAP goes after them they just keep flying to their target and wait to get shot at. They have AMRAAMs, so should self protect much earlier and then get back on task."

**Where it stands:**
- Attack flights fly `open_fire` with a single attack task, so they only react once fired upon (reaction to threat: evade fire).
- Many attack loadouts already carry air-to-air missiles. In the first run the DEAD F-16s had AIM-120C ×2 + AIM-9X ×2, and the Su-34s had R-73 ×2 + R-27R ×2.

**Approach (proposed):**
- **Trigger:** an enemy fighter in the coalition's radar picture that is closing on the flight within some range; or DCS's own detection by the flight (`getDetectedTargets` on the flight itself).
- **Order:** push an `EngageGroup` on that fighter (or open fire on air targets within a range) on top of the mission. When the fighter is dead, gone or turned away, pop it, so the flight resumes its route and attack.
- **Limits:** only flights whose loadout carries air-to-air missiles; don't chase past the leash; decide whether a flight that fought and lost its attack time still presses on or goes home.

---

### 5. AWACS calls to the player (text)

**Closed 2026-10-02:** flown in the 00:57 run; the calls came every 2 min and looked right, and DCS's magvar works in the game (+12.4° at Rovaniemi against the table's +11.9°). John: 7 s on screen was too short, now 14 s. The open questions left below went to the `plan.md` backlog (*Air picture follow-ups*). As built: `plan.md`, *Air picture calls*.

**Built 2026-10-02, not flown yet** (`plan.md`, *Air picture calls*): every 2 min, for 14 s, each player gets every contact in their own coalition's radar picture as a short BRAA list from their own position, highest threat first (range weighted by aspect): `MiG-29S - 110/120nm, 10k, hot, 5s` (magnetic bearing / range, altitude, aspect, age of the position). John's calls: no bullseye ("kind of a pain"), all bearings from the player, no "bogey dope" to ask for, only what Blue's radars see. Moves to `closed.md` once a run confirms it.

**Goal:** the AWACS tells the player what it sees: enemy aircraft with bearing, distance, altitude and type, like a real controller's picture calls.

**Decided:** text messages to the player's group (`outTextForGroup`) for now. Long-term goal (John): AWACS calls become LLM / cloud audio like the AI pilots' calls (item 7), and the text version is the step before that. The facts per group (`describe`) are worked out apart from the text, so the delivery can be swapped.

**Still open, after a run:**
- Is 14 s enough to read up to 10 lines? (raised from 7 on 2026-10-02)
- Does DCS's `magvar` module work in the game (`dcs.log`, grep `air picture`), or does the approximate table stay?
- A separate automatic THREAT call (a hot group inside ~35 nm, at once rather than at the next list)?
- When the AWACS is shot down: carry on from the ground radars (now: yes, the list is the whole picture), or say "picture degraded"?
- Group size ("2 contacts", "heavy"): the picture keeps one contact per DCS group and doesn't count the aircraft its radars see.
- AWACS callsign and frequency in the brief.

---

### 10. SEAD ingress doctrine: high transit, low ingress, pop up, fire, low and fast out

**Closed 2026-10-02:** built 2026-10-01, flown in the 22:23 run (Blue's low SEAD killed the Kuusamo SA-11's radar; it never fired) and the 2026-10-02 00:57 run (every SEAD jet that got there died to sites firing back at the pop-up). Retuned the same day (launch 55 km, pop-up 15 km before it, go cold on the last missile, attack altitude held): `bugs.md` 27, `closed.md` bug 28. The reach model behind it goes with roadmap item 12. As built: `plan.md`, *Packages*.

**Built 2026-10-01, not flown yet** (`plan.md`, *Packages*, "The SEAD profile: under the radar"). John's calls on the open questions: 900 ft above the ground; one pop-up altitude, 10,000 ft (3,000 m, where the kill-zone model's low reach ends); every SEAD target (they are all medium / long range); strike and DEAD flights stay high; bug 20 fixed with it (the go-cold clock starts on arrival at the launch point); rolling back outside-in is its own step, after a run. Not tested in a DCS test mission first (John flies the full mission instead): watch whether the AI holds 900 ft over the Khibiny and the fells, and whether it pops up and fires at the launch point. Moves to `closed.md` once a run confirms it.

**Goal:** SEAD flights that beat long-range SAMs the way a real pilot does: under the radar, then a short pop-up to fire, then gone. John (2026-10-01): "going in low and popping up to launch radiation missiles at a long range SAM is a really good defeat tactic … my instinct to go high was wrong, I forgot that SA-10s struggle to target when you are low."

**Why now:** the 14:14 run (`event_logs\2026-10-01_141412.log`, `plan.md` *Last DCS runs*). Every SEAD flight ran in low by accident (~2,500–3,000 ft; the planned 30,000 ft run-in was never reached), and the result showed the tactic:
- MSN2024_SEAD_AGAIN (2× F-16) ingressed at ~2,700 ft, popped up to 16–18k ft, fired 8 HARMs from 35–41 km and killed both Sodankylä SA-10 search radars. The SA-10 never fired.
- The first MSN2024 flew the same profile and died before firing: the SA-10 saw the pop-up and fired at 43–49 km. The pop-up has to be short and the shots must come at once.
- MSN5025 (2× Su-34) stayed at 3,000 ft and never fired at the Alakurtti IRIS-T (most likely no line of sight or no range at that altitude), then went cold.

**Where it stood before the build** (`plan.md`, *Packages*): one SAM site per SEAD 2-ship; `suppressionRoute` flies around other threats to a launch point `launch_km` (40) from the site, the last `run_in_km` at 9,000 m and Mach 0.9; an `AttackGroup` with every anti-radiation missile at the launch point; the go-cold rule (`suppression`) turns it home. The launch point must be outside every other site's full ring.

**The profile (John's, 2026-10-01):**
1. **Takeoff and climb** to cruise, 16,000–25,000 ft (~5,000–7,500 m), in own airspace.
2. **Descend to the low ingress** at the edge of the SAM ring: before the route enters the first enemy ring on the way in (+ a margin, so it is down before the radar can see it).
3. **Low ingress** at ~900 ft above ground (John's default from flying it), fast.
4. **Pop up to 8,000–12,000 ft** short of the launch point and **fire at ~40 km** (today's launch distance: it worked, and the AI doesn't dodge SAMs well, so not closer). All missiles in one salvo.
5. **Back down low, afterburner, out cold**, the way it came, until out of the ring; then climb and cruise home.

**How low the DCS AI can fly (advice; to verify in DCS before building):**
- **Altitude above ground:** waypoints take `alt_type = "RADIO"` (above ground) instead of `"BARO"`. Today every waypoint is `BARO`, so a low leg at a fixed sea-level altitude would fly into rising ground.
- **900 ft (~275 m) above ground is a sound default.** From community experience the AI flies 150–300 m above ground over flat and rolling terrain without trouble; lower than ~100 m it starts to hit trees, hills and power lines, and it doesn't really terrain-follow between waypoints, it flies toward the next one. Kola is mostly flat to rolling (lakes, tundra, taiga), with real high ground in the Khibiny (Apatity / Monchegorsk), the Lapland fells and the Norwegian coast. Not measured by us yet.
- **Waypoints on the low leg every ~10–20 km**, so the AI re-reads the ground often. The planner can check ground height along the leg (`land.getHeight`) and keep the leg out of the high ground, or raise it there.
- **Climbs and descents take distance:** the AI changes altitude gradually toward the next waypoint (the 14:14 run: ~2,700 ft reached ~28 km after takeoff, against a planned 9,000 m). So the descent waypoint goes well before the ring edge, and the pop-up point ~10–15 km before the launch point. The AI also starts its attack ~12 km before the attack waypoint, which goes with the pop-up.
- **Afterburner out:** the option that allows it (`option 16 false`, as scrambles use) on the egress, and a dash speed on the egress waypoints.
- **Reaction to threat:** today `evade fire`. Whether `bypass and escape` (the AI's own terrain masking) helps on the low leg is something to test.
- **Fuel:** a long low leg at high speed burns much more; the planner's reach (`combat_radius_km`) should count the low part at a higher burn.

**What it changes elsewhere:**
- **Launch points:** a jet coming in low is only threatened by each other site's low-altitude reach (`lib/sam_reach.lua`: SA-10 40 km, Patriot 30, SA-11 25, NASAMS 14 …) rather than its full ring. The launch-point clearance test can use that reach for the low leg, and the pop-up zone needs only a short clear window. Many sites that today have no clear launch point (most of the "no suppression flight in reach" missions in the 14:14 run) would become attackable. Goes with rolling the defenses back outside-in (`plan.md` backlog, *SEAD follow-ups*).
- **The go-cold rule:** "inside another site's kill zone" should use the flight's altitude (it already does, through `SamReach`); the timer starts when the flight reaches its launch point (bug 20).
- **Human SEAD frags:** the same profile in the steerpoints (descent point, pop-up point, launch point) and the frag text.
- **Red's SEAD** (Su-34 with Kh-31P) flies the same profile.

**Testing:** in the luae harness first (the route: altitudes, `RADIO` legs, waypoint spacing, ground height on the low leg); then a DCS test of one F-16 2-ship and one Su-34 2-ship at 900 ft over flat ground and over the Khibiny, before a full run.

**Open:**
- 900 ft, or lower over flat ground if the test shows the AI holds it?
- Pop-up altitude: one number (e.g. 10,000 ft), or by system (higher against a Patriot, lower against an SA-10)?
- Does the low ingress apply to every SEAD target, or only medium and long-range SAMs (short-range SAMs are deadly down low)?
- Do strike and DEAD flights behind the SEAD also come in low near the front, or stay high once the threat is down?

---

### 11. One controller: every run-time decision about what flights do, in one place

**Closed 2026-10-02:** built 2026-10-01; ran cleanly in the 16:21, 20:31, 21:30 and 2026-10-02 00:57 runs (the first `retry` came in the 00:57 run). As built: `plan.md`, *The controller*.

**Built 2026-10-01; ran cleanly in the 16:21, 20:31 and 21:30 runs** (`watching`, `no scramble`, `cancel: not needed`, the first `defend`), though `wait`, `retry` and `launch late` haven't come up in a run yet (`plan.md`, *The controller*): `decide_launches.lua` (launches in sequence, waits, retries, cancels, late launches, the airborne cap), `scramble_fighters.lua` and `track_alert_jets.lua` in `consumers/control_air_flights/`; the scheduler keeps the clock and the record and asks the controller (`ControlAirFlights.due`); `consumers/run_scrambles.lua` is gone; every decision is a `CONTROL` line. Same decisions as before on the same inputs (harness), plus the new `watching`, `leave threat` and `launch late` lines. Moves to `closed.md` once a run confirms it.

**Goal:** all the logic that decides at run time what AI flights do, and which directives they get, lives under the controller (`consumers/control_air_flights/`), so it isn't spread over several modules that each do part of a controller's job. John (2026-10-01, 16:21 run, after the `NO_SCRAMBLE … covered by patrol MSN2016_CAP` decision turned out to live in the scramble module): "we should move all of the logic about what flights are supposed to do and what directives they receive under the controller now … so we don't have code all over the place that serves that function."

**The line to draw:**
- **Planning** (stages, before anything spawns) stays where it is: which missions, targets, routes, packages, patrol stations and alert bases are planned (`stages/plan_air_tasking.lua`, `planAlertPosture` included). The plan is what the controller works from.
- **Sensing** stays where it is: the radar picture (`consumers/track_radar_picture.lua`) is what the controller knows.
- **Execution** stays where it is: spawning a group (`consumers/spawn_aircraft_groups.lua`), the mission clock and the record of each flight (spawned, landed, lost, target progress, `statusOf`) in the scheduler, the event log.
- **Every run-time decision about flights moves to the controller:** whether a flight launches now, waits, flies again or is cancelled; whether to scramble, from where, at what; what a flight in the air is told to do.

**What did a controller's job outside the controller (before the move, 2026-10-01):**
| Decision | Where it is now | Event words |
|---|---|---|
| Scramble or not (trigger: inbound for two rounds, time to threat), refusals (covered by a patrol, under enemy SAM cover, no way there), the raid, the base pick (in time, in reach, facing region), the intercept point | `consumers/run_scrambles.lua` (`check`, `scramble`, `pickBase`, `raidOf`, `coveringPatrol`, `interceptPoint`, `refuse`) | `SCRAMBLE`, `NO_SCRAMBLE` |
| Stood down before launch (the raid is gone during the reaction delay) | `consumers/run_scrambles.lua` (`launch`) | `STOOD_DOWN` |
| Alert jets: ready, cooldown, back on alert after landing or a ramp stand-down | `consumers/run_scrambles.lua` (`readyJets`, landing handler, `stoodDown`) | `ALERT` |
| A mission launches only once its threats are out of the fight; waits for its suppression flight; the suppression flight flies again; cancelled; a suppression flight not needed; launched late when there is room under the cap | `consumers/schedule_air_tasking_orders.lua` (`launch`, `threatCleared`, `openThreats`, `roomFor`, `later`) | `DELAYED`, `RETRY`, `CANCELLED` |
| The airborne cap at run time (AI aircraft in the air per coalition) | `consumers/run_scrambles.lua` (`airborneAircraft`), the scheduler's `roomFor` | — |

**Approach (proposed, to settle with John):**
- **The scheduler keeps the clock, asks the controller.** When a flight is due, the scheduler asks the controller "launch, wait (until when), fly again, or cancel?" and does what it says (spawn, reschedule, record). The packages-in-sequence rules move into the controller as a launch decision (e.g. `control_air_flights/decide_launches.lua`).
- **Scrambles become a controller job** (e.g. `control_air_flights/scramble_fighters.lua`): the trigger, refusals, raid, base pick and intercept point, in the same pattern as the rest, with the scramble's leash already there. "Scramble, or leave it to the patrol" sits next to the patrols' own directives once those come.
- **Alert jets** (ready / cooldown / turnaround, the reserved spots) are the state of an asset the controller spends, like the airborne cap: kept in one small state module the controller reads and updates, not decided in it.
- **One cap check** for planned launches and scrambles alike.
- **Behaviour stays the same:** a move, not a redesign. The event words and lines stay as they are, so runs before and after compare one for one; the harness checks the same decisions come out on the same inputs.
- **Then** new controller jobs from item 4 (abort a defenceless flight, landing order, patrol handover and merge break-off, hunting an enemy patrol) all land in one place.

**Decided (John, 2026-10-01):**
- **One event word, `CONTROL`,** for every controller decision, with the decision named at the start of the text, so `grep CONTROL` shows what that layer is doing, in order (e.g. `CONTROL MSN5023_OCA no scramble: covered by patrol MSN2016_CAP`, `CONTROL MSN2023_STRIKE defend: engaging …`, `CONTROL MSN2027_OCA retry: …`). Replaces `LEASH`, `SUPPRESSION`, `DEFEND`, `SCRAMBLE`, `NO_SCRAMBLE`, `STOOD_DOWN`, `ALERT`, `DELAYED`, `RETRY`, `CANCELLED`; update the grep table in `plan.md`. With it, from the event-log idea of the same day: a line when a flight is first watched (its directives), and a line when coordination leaves a threat to another flight.
- **Later, the controller can send a patrol anywhere** (not only within its station's circles): after a raid instead of a scramble, to hunt an enemy patrol, to cover a package.

- **Alert jets:** their state moves to `consumers/control_air_flights/track_alert_jets.lua`, bookkeeping only (jets ready per base, turnaround and cooldown, which scramble came from which base, held spots, back on alert after landing or a ramp stand-down), no decisions; the controller asks it which bases have a jet ready and tells it when a jet launches, lands or is stood down.
- **`consumers/run_scrambles.lua` goes away** (John: in the new design it no longer runs scrambles): its decisions move into the controller, its alert-jet state into `track_alert_jets.lua`.

---

### 12. SEAD against the air defenses: a standing rotation, rolling them back outside-in (top priority, next)

**Closed 2026-10-05** (John: "item 12 is fine"): the rotation, the site table, the outside-in order, retries and the come-back have flown in every run since 2026-10-02. As built: `plan.md`, *Stages 5–6*, SEAD.

**Status:** built 2026-10-02 (session 15, late), every step of the build order below; harness-tested on the 10:38 plan (planning over six seeds: SEAD flights Red 0–4 → 9, Blue 0–2 → 10–11; the plan's timing rules; a gate harness for wait / retry / cancel chains / the rotation's retry and pull-forward; a 6 h smoke on the re-planned roll). **Flown 2026-10-02 in the 14:55, 16:03, 16:50, 17:15 and 17:48 runs**: the rotation, the site table, `retry … the rotation's next flight` and `wait` all ran; the SEAD profile was reworked along the way (bugs 33, 36, 39, 40, 41) until the 17:48 run killed the Sodankylä SA-10's and the Kuusamo SA-11's search radars. As-built notes: `plan.md`, *Stages 5–6*, SEAD; bug 27 in `closed.md`. Moves to `closed.md` once a run confirms it. Built a little differently from the design below:
- **Both "to confirm with John" points built as proposed, and John confirmed them** (2026-10-02: the bug 27 split, "probably fine"; a player's SEAD on a step-1 rotation site, "sounds good"; the rest of the deviations below too). The old player form (first threat of an AI mission's route) was dropped instead of kept as a fallback: when no step-1 site fits, the player simply gets another mission type, as for any type that doesn't fit.
- **The rotation goes on to deeper sites** once the sites reaching over the front are queued (by step, nearest the front first), so it runs the whole window; on the 10:38 roll only 6–7 sites per coalition reach over the front, which filled ~3 h.
- **Pulled forward on landing too,** not only on a cancel or a loss: the next rotation flight goes when the one before it is down ("one comes back and lands, despawns, the other spins up").
- **Deeper targets** need at least one ring on the route, every one with a SEAD flight (a target deep but under no ring isn't opened by this).
- **Heights above the ground** for the reach model (the low figure is the radar horizon).

**Goal:** SEAD is the primary mission that opens everything else (John, 2026-10-01, after the 22:23 run: "every run has almost no SEAD flights and SEAD flights are the primary mission to open up everything else"). Each coalition goes after the enemy's air defenses for their own sake, the way a real air force does, taking a dense, nested network like Kola's core apart from the outside in, with a SEAD 2-ship in the air pretty much the whole mission; strikes and DEAD use what it clears.

**Why:** today a SEAD flight exists only because a strike or DEAD mission needed it (`planMission`, `stages/plan_air_tasking.lua`): pick a target, route to it, plan one SEAD flight per ring the route crosses, all of them or the mission is dropped. That gives almost no SEAD in two ways, and recent rolls hit both:
- **No clear launch point** (the 21:30 run, `event_logs\2026-10-01_213052.log`): Blue planned 1 of 6 AI attack missions and no SEAD flight; every other mission "no suppression flight in reach". Red's sites cover each other: each SA-11 beside its SA-10 (`SAM_KOSH_SA11_1` under `SAM_KOSH_SA10_1`, `SAM_MONC_SA11_1` under `SAM_OLEN_SA10_1`) and the SA-11s in the Kola Bay cluster have no clear launch point even with item 10's low run-in. Re-planning that roll with item 10 over six seeds still gave Blue 0 SEAD flights.
- **No strike to go with** (the 22:23 run, `event_logs\2026-10-01_222355.log`; `dcs.log`): nearly every failure was "no target near the front in reach" (8 of 8 tries). Red planned 1 of 6 missions (1 SEAD flight), Blue 3 of 8 (SEAD against 3 sites), while the front was full of SAM sites nobody went after.

**Where it stands:** the pieces exist. Packages fly in sequence (SEAD first, the mission only once its SAMs are out of the fight, `requires_cleared`); a later package reuses an earlier SEAD flight's work (`ctx.cleared`); the run-time gate in `decide_launches.lua` already checks *sites*, not flights (wait, retry once as `<id>_AGAIN`, cancel; `cancel: not needed` when the site is already dead). The low SEAD profile (item 10) works: the 22:23 run's MSN2025 knocked out the Kuusamo SA-11 without it firing once.

**Design** (John, 2026-10-01: "choose the most realistic options"; reworked with John 2026-10-02: one kind of SEAD flight, no classifiers for chaining, and a standing rotation):

1. **One kind of SEAD flight.** A SEAD flight is a mission against one SAM site; its `target` is the site, like any other mission. It carries nothing about who it's for. "Escort" goes (John, 2026-10-02: they don't escort anyone, they fly separately): `planned_as = "escort"`, `escorts`, `suppresses` (→ `target`), `suppressed_by` and the per-mission `cleared_by` are removed; `suppression_of_air_defenses` becomes a mission type of its own.
2. **One link: `requires_cleared`.** Any flight may list the sites it needs out of the fight: a strike or DEAD the rings its route crosses; a SEAD flight against an inner site the outer sites in its way (outside-in falls out of this, no layer field). The planner keeps one table per coalition, **site → the SEAD flight planned against it** (at most one each; replaces `ctx.cleared`; kept in the plan for the gate and the brief). A site gets its SEAD flight for one of two reasons:
   - **the general assault** on the enemy air defenses (the rotation, below);
   - **an attack flight needs it:** its route crosses a site nobody takes yet, so a SEAD flight for that site is planned right then (John: "if a STRIKE or DEAD needs SEAD, it gets SEAD"). Same flight, same fields.
3. **Which sites the general assault takes:** every enemy medium and long-range site whose ring reaches the contested airspace or own ground (the sites that deny the air over the front), plus any deeper site that blocks one of those. Early-warning radars and short-range sites aren't on it (short-range ones are DEAD targets, as now; base-defense Pantsirs / Tors stay in the way at every step).
4. **The order, outside in:**
   - first the sites with a launch point and low route clear of every other site's low-altitude reach (today's `launchPoint` / `suppressionRoute`);
   - then the sites whose launch point and low route are clear once those are taken out (the low threat map rebuilt without them; the routing cache keyed by it); their `requires_cleared` = the earlier sites they need out of the way;
   - at most 3 steps deep; among sites of one step, the one whose ring covers the most own and contested airspace first;
   - sites still blocked aren't attacked, and the planning log says why ("blocked by …", "no base in reach"), one line per site.
5. **The rotation** (John, 2026-10-02: "a 2 ship flight running pretty much the whole mission on both sides; one comes back and lands, despawns, the other spins up"): the general assault is one queue per coalition, flown back to back by 2-ships, each starting when the one before it is planned to land, from whichever base suits its site; from `first_start_s` until the window or the queue runs out. ~60–90 min a sortie gives ~4–6 flights per coalition in 6 hours, against ~11 medium / long-range sites on Red's side. A site that survives its flight gets its second try (`_AGAIN`) as the next flight in the rotation, not as an extra jet. Planned first, after defensive air, so it has first call on the airborne cap.
6. **SEAD an attack needs flies extra** (John, 2026-10-02, option b): alongside the rotation, under the airborne cap. With the rotation planned first most strikes reuse its sites, so this should be rare. (Replaces the earlier "at most 2 campaign flights at once" setting.)
7. **One timing rule:** a flight with `requires_cleared` starts no earlier than `strike_after_suppression_s` (10 min, for battle damage assessment) after the planned salvo of each SEAD flight on those sites, not after its landing (real forces keep up the tempo once the site is assessed down). Same rule for strikes and for SEAD behind SEAD.
8. **One run-time rule** (the gate in `decide_launches.lua`, keyed on the site table): when a flight is due and a site it needs is still in the fight, wait while that site's SEAD flight is still on its attack (once it has gone cold it's done: don't wait out its planned landing); otherwise fly that SEAD flight once more (`_AGAIN`, one repeat per SEAD flight, shared by every flight waiting on it); if the site is still up after that, cancel. If the site's SEAD flight was itself cancelled, cancel too (`CONTROL … cancel: <site>'s SEAD flight MSN… was cancelled`; today the gate would fly a never-spawned flight as if it were an unflown player tasking). The plan is fixed once built: no re-planning at run time; the rest of the queue carries on.
9. **No gaps in the rotation:** when a rotation flight is cancelled or lost, the next one in the queue is pulled forward to now (the `launch late` mechanism), so the rotation doesn't sit empty until the next planned start.
10. **Strikes and DEAD fill in behind:** planned after the rotation; a route crossing only sites the table already covers needs no SEAD of its own and waits on them; a site it doesn't cover gets an extra SEAD flight (point 6), or the mission isn't planned.
11. **Deeper targets where the way is cleared:** a target may lie up to `max_km_past_contested` (40 km) past the contested airspace as now, or deeper (up to ~100 km, a new setting) when every ring its route crosses has a SEAD flight in the table. This also answers many "no target near the front in reach" failures.
12. **Players:**
    - **A player's strike / DEAD:** the AI SEAD flights on its sites are timed to fire before the player's time over the target (`suppression_lead_s`, first thing after takeoff as now); the player isn't gated.
    - **A player's SEAD** (John confirmed, 2026-10-02): the player is the SEAD flight on a site in the table, a first-step site from the rotation's queue (one with nothing in its `requires_cleared`). Anything waiting on it gets the AI retry if the site survives (bug 17's rule, unchanged), since a player's flight never counts as done for the AI. The old form (the player takes the first threat of an AI mission's route) is dropped: when no step-1 site fits, the player gets another mission type.
13. **The brief** (John, 2026-10-02: show which SEAD flight had to succeed for the mission to run; keep it simple): each frag gets one line per site the mission needs down, with the SEAD flight and its state; the comms menu's air tasking order tags a mission "after MSN2024 SEAD". A SEAD flight's own line says which missions wait on it ("opening the way for MSN2025, MSN2030"), worked out from the table. Packages (`PKG<n>`) stop being groups (a SEAD flight serves several missions): the attack-package menu lists missions by start time with these lines.
    ```
    Needs down: SAM_KUUS_SA11_1 (MSN2024_SEAD, airborne)
                SAM_SODA_SA10_1 (MSN2026_SEAD, planned 09:40)
    ```

**Build order:**
0. **Bug 27, the low-altitude reach** (found in the 2026-10-02 00:57 run; do this first): `lib/sam_reach.lua` lets a site reach only its low-altitude figure up to 3,000 m, but at the pop-up the SA-11 fired at 39 km at 3,200 m (model: 25), the Patriot at 50 km at 2,500 m (model: 30), the SA-10 at 46 km at ~900 m (model: 40). Proposed: the low figure only up to ~300 m, the full ring from ~3,000 m (all three shots fit). Split (John confirmed, 2026-10-02): the truer model for the leash, the scrambles and the kill zones; the launch-point test and the low routes keep the low figure, accepting the short pop-up as exposure (every SEAD jet that died at its pop-up died to its own target, never a neighbouring site; with the truer model a launch point would have to sit outside every other site's full ring, and Kola's core would go unattacked); go cold ignores other sites' rings from the pop-up until the salvo is away. See the retune's DCS run (launch 55 km, pop-up 15 km before it, go cold on the last missile) before building.
1. The rename and the one-kind model (points 1–2), with the gate keyed on the site table (point 8); everything still planned as today.
2. The general assault's site list and order (points 3–4), logged.
3. The rotation and the timing rule (points 5–7, 9).
4. Strikes behind it, extra SEAD, deeper targets (points 6, 10, 11).
5. Players and the brief (points 12–13); the event log, the map drawings and `logFlight` lose "escorts".

**Goes with it** (same work, or right after):
- ~~**Bug 22:** route the low legs and the climb-out around short-range SAM sites~~ (built 2026-10-02, not flown: `closed.md`, bug 22).
- ~~**Two flights at once against an SA-10 / Patriot / IRIS-T**~~ (not needed, John, 2026-10-02: one 8-missile salvo gets through from close enough in, which the low run-in and pop-up are for; the salvoes shot down were fired from far out).
- `plan.md` *Packages* gets the as-built notes; the summary line counts SEAD flights (rotation and extra), how deep the order went, and sites not attacked.

**Testing:** the luae harness on the 21:30, 22:23 and 00:57 plans (`kola_last_plan.lua` replays), six seeds each: SEAD flights per coalition, how deep the order reached, which Kola-core sites stay unattacked and why; the rotation's coverage (minutes with no SEAD flight up); peaks under the cap. The controller harness: a flight behind an inner site waiting, its blocker retried as `_AGAIN`, a cancel chaining down, a cancelled rotation flight pulling the next one forward. Then a DCS run.

---

### 13. Airfield info in the comms menu (John, 2026-10-02)

**Closed 2026-10-05** (John: "built and working"). As built: `plan.md`, *Brief*.

**Status:** built 2026-10-02 (session 17), harness-tested on the last plan dump, copied to DCS, not flown. As-built notes: `plan.md`, *Brief*. Moves to `closed.md` once a run confirms it.

**Goal:** a player can land and turn around at any Blue base, not only the one they spawned at, so each Blue base gets a short brief: `Airfield info > <base>`.

**Decided with John:**
- every Blue base, alphabetical by DCS name; Blue only;
- one text per base: header (code, echelon, class, elevation), wind and the runway in use (headwind and crosswind), each runway's numbers and length, the next AI takeoff and the next AI landing (one each, with the flight's live state, a line left out if none), one alert line ("2 of 3 jets ready");
- no TACAN, ILS or frequencies for now (they'd need a data file from the Kola terrain's beacon and radio files);
- the file is `consumers/create_airfields_brief.lua`.

**To check in the first run:**
- whether our runway in use matches DCS ATC's and the AI's takeoffs;
- whether the runway numbers match the airfield charts / F-16's;
- whether the wind matches the start text and ATC.

---

### 16. SEAD that meets fighters: clear the way, or go elsewhere (John, 2026-10-05)

**Closed 2026-10-05, not built** (John: "no longer needed, we have it on the radio now").

**Goal:** a SEAD flight that keeps dying to enemy fighters in contested airspace gets help, or its effort moves somewhere less hot, instead of the same flight being sent down the same corridor again. John: "A SEAD fail to fighters in contested airspace should call in a CAP or SCRAM or send out a search and destroy mission from a base to clear the way. And rotating flights to other less hot regions also makes sense." A bigger change; a todo item, no place in the order yet.

**Seen** (`event_logs\2026-10-05_103126.log`, 1 h 46 min, no player flying): three tries at the Koshka Yavr SA-10 (MSN2026_SEAD, `_AGAIN`, `_LATER`, all 2x F/A-18C from Kirkenes on the same route) cost 6 Hornets and destroyed no radar. 3 of the 6 died to fighters: two to Red's Su-34 strike flights (R-77s) and one to a Su-27 patrol, all in the Kirkenes-Koshka Yavr corridor, which is also Red's busiest (strikes out of Koshka Yavr and Murmansk, the MiG-31 station). Two more died to the SA-10 and the Luostari SA-8. Blue's whole rotation waits behind that one site. Red lost 4 Su-34s the same way on the Rovaniemi SA-10 (one Kh-31P got through).

**Ideas (decide with John when it comes up):**
- **Clear the way:** a SEAD flight lost to fighters (or `press on` / `defend` calls on its run-in) marks its corridor as fighter-contested; the next try waits for a patrol commit there (item 4d), a scramble at the fighters seen, or a planned sweep ("search and destroy") from the nearest fighter base, timed ahead of it.
- **Go elsewhere:** the rotation moves on to sites in a quieter region (by the picture's fighter contacts or losses there) and comes back to the hot one later; goes with bug 35 (no immediate retry into what just killed the first flight) and the come-back (bug 46).
- **Not the lever** (John, 2026-10-05): tuning the SEAD flight's own fight (the 25 km commit). "Some jets are going to fly into a zone and kill other jets. It's DCS, not real life." The lever is not sending SEAD unsupported into a corridor full of enemy CAP.

---

## Bugs

Fixed bugs from `bugs.md`, each as it stood when it was closed (status line: what was built). Moved 2026-10-01; fixed in session 12 and not all confirmed in a DCS run yet.

### Bug 1. Scrambles accept intercepts they can never make in time

**Status:** fixed 2026-10-01, not run in DCS yet. John: refuse a scramble that can't arrive in time (the time test only, no maximum leg). `pickBase` adds the reaction delay (mean), `AIR_DEFENSE.scramble_takeoff_s` (150 s, taxi and takeoff from a hot ramp spot) and the dash to the intercept point; when that's later than the raid's `threat_minutes`, the base is skipped: `NO_SCRAMBLE … can't reach the raid before it reaches <asset> (n min, raid m min)`.

**Seen:** event log `event_logs\2026-09-30_201105.log`; grep `MSN5905`, `MSN5906`.
- **MSN5905_SCRAM:** a Su-27 from Kuusamo sent after MSN2024_SEAD + MSN2025_SEAD, which were "8 min from Kirkenes", with the intercept **629 km out**. That's ~30 min at dash speed, and far more afterburner than a fighter has fuel for.
- **MSN5906_SCRAM:** a Su-30 from Alakurtti, with the intercept **462 km out**.
- **Blue too:** MSN2901_SCRAM (F-15C from Ivalo) at **205 km**, sent after Su-34s 9 min from their target; it was airborne at 08:19, and the raid was dead by 08:22. MSN2905_SCRAM (F-16C from Rovaniemi) at **226 km**.
- **Why Kuusamo:** it was the only alert base with a jet ready. Koshka Yavr's last jet had gone to MSN5904 in the same round, and Alakurtti was on cooldown. That part is by the rules; it's also made worse by bug 2.
- **Seen again** (`event_logs\2026-09-30_213757.log`; grep `MSN2906`, `MSN2909`, `MSN2910`): three Blue F/A-18 scrambles from Hosio and Rovaniemi at Red patrols (MSN5009_CAP, MSN5010_CAP), with intercepts **534, 424 and 420 km out**. All pass the F/A-18's 550 km `combat_radius_km`. The patrol's race-track leg pointed at Banak, so the raid was pushed far ahead along it. The walk back from the base stops only at enemy airspace, and the whole way lay over Blue's own airspace.

**Cause** (`consumers/run_scrambles.lua`):
- `interceptPoint` pushes the raid ahead along its heading by the scramble's flight time. A raid flying away from the base becomes a long tail chase.
- `pickBase` then checks only three things:
  - the leg is at least `scramble_min_leg_km`;
  - it's within the type's `combat_radius_km` (Su-27: 700 km);
  - there's a free ramp spot.
- Nothing asks whether the scramble arrives before the raid reaches the asset it threatens.

**Proposed fix:**
- Refuse the pick (`NO_SCRAMBLE`, e.g. "can't reach the raid before it reaches Kirkenes") when the scramble's time to the intercept point, including its reaction delay and taxi, is later than the raid's `threat_minutes` plus a margin.
- Possibly also a maximum scramble leg (`AIR_DEFENSE.scramble_max_leg_km`, ~250–300 km).
- **Decide with John:** the time test only, or also the maximum leg, and the numbers.

---

### Bug 2. A jet stood down on the ramp never returns to alert

**Status:** fixed 2026-10-01, not run in DCS yet. The leash's stand-down calls `RunScrambles.stoodDown(id)`: the jet is back on alert at once, with an `ALERT … stood down on the ramp; its jet is back on alert` line.

**Seen:** same log; grep `stood down on the ramp` and the `alert jet(s) ready` counts in the `SCRAMBLE` lines.
- **Jets lost without flying:** MSN5901 and MSN5904 (Koshka Yavr) and MSN5902 (Kuusamo) were stood down on the ramp and never came back. Koshka Yavr went from 3 jets to 1, and Kuusamo from 3 to 2, with none of them flying.
- **Two of the three were raised against MSN2009_CAP,** a Blue F-15C patrol on its race-track:
  1. one leg reads as inbound for two picture rounds, so Red scrambles;
  2. the jet spawns;
  3. the patrol turns, reads as "heading away", and the jet is stood down.

  John agreed a scramble at a patrol that looks like a raid is fine; with this bug, each such cycle costs a real alert jet.
- **Seen again** (`event_logs\2026-09-30_213757.log`; the `alert jet(s) ready` counts): MSN2904 (Kittila) and MSN2905 (Rovaniemi) were stood down on the ramp and never came back. Kittila was at "0 ready, 1 turning around" by MSN2907, and Rovaniemi the same by MSN2908. The jets that landed did come back (`ALERT` lines), so only the stand-down path is broken.

**Cause:** the leash's stand-down (`consumers/enforce_air_behaviour_rules.lua`) deletes the group with `g:destroy()`. An alert jet only goes back on alert from `RunScrambles`' `S_EVENT_LAND` handler, and a deleted jet never lands. Only a stand-down *before launch* (in `launch`, the `refund` path) gives the jet back.

**Proposed fix:**
- A jet stood down on the ramp goes back on alert at its base at once, or after a short delay (the crew climbing back out), the same way a stand-down before launch does.
- For example, `EnforceAirBehaviourRules` tells `RunScrambles` (a callback, or `RunScrambles.stoodDown(id)`), which moves the jet from `st.flights` back to `ready`.
- The `LEASH` line can then show the base's ready jets.

---

### Bug 4. A DEAD flight's weapon can't outrange its target

**Status:** fixed 2026-10-02, not flown (it had waited for the standoff work since 2026-10-01). Seen again in the 19:29 run (`event_logs\2026-10-02_192901.log`, grep `MSN7032_DEAD`): Kh-29Ts at the Ivalo Roland from 7–9 km; the site was destroyed (3 of 3) and one Su-34 lost.

**Seen:** same log; grep `MSN5023_DEAD`.
- MSN5023_DEAD, 2× Su-34 from Banak on `SAM_ENON_Roland_1`, carried Kh-29T, a TV-guided missile fired from about 9 km. The Roland reaches about 8 km.
- Both fired from 9 km at ~12,800 ft, and both were shot down by the Roland (08:21–08:22).
- The Roland lost one launcher.

**Cause:** DEAD loadouts are chosen per aircraft type (`aircraft_loadout_choices.json`), and the attack altitude is realistic for the weapon. Nothing compares the weapon's release range with the target's ring.

**Proposed fix:**
- Planning: only pick a DEAD target whose ring is shorter than the flight's weapon range, with a margin; or pick the loadout by target.
- Ties in with the *Standoff attacks* item in the `plan.md` backlog: which weapons the DCS AI really releases at range.

**Fix (John, 2026-10-02: build what completes missions and is realistic, watch it and re-evaluate):** a DEAD flight against a **short-range** site must hit it from out of its reach: its weapon reaches the site's ring + `AIR_DEAD_WEAPONS.reach_margin_km` (5), or it attacks from at least the system's ceiling + `ceiling_margin_m` (1,000 m) above the site's ground (`SAM_SITE_RECIPE` `ceiling_km`: SA-8 5, SA-15 6, Roland 5.5). Medium and long-range sites need no rule: a DEAD there already waits until SEAD has put the site out of the fight. Human flights aren't held to it.
- **Loadout by target** (`draftMission`, `deadLoadouts`): the planner picks a DEAD loadout of the aircraft that passes; a target none passes isn't taken by that aircraft (`no DEAD weapon hits its short-range targets from out of reach`). The Su-34 got a second DEAD loadout, `dcs:Kh-59M*2,R-73*2,R-77*2,ECM` (`aircraft_loadout_choices.json`), next to the Kh-29T one.
- **Weapon reach:** a standoff weapon's `release_km` (`AIR_STANDOFF_WEAPONS`: Kh-59M 40, AGM-154 JSOW 20, new), else `AIR_DEAD_WEAPONS.weapon_reach_km` (Kh-29T 9).
- **Standoff route for AI DEAD flights** carrying one: the "target" waypoint is the release point, as for strikes; the `AttackGroup` on the site stays (the AI can still close in if it can't fire from there).
- **Replay of the 19:29 plan, six seeds:** every Red Su-34 DEAD on a short-range site (SA-15, Roland) flew the Kh-59M from 40 km; on medium sites either loadout. Blue's F-15E JDAM passes by height (7,500 m over ceilings of 5–6 km); AI F-16 / F/A-18 DEAD flights fly JSOW from a 20 km release point; no DEAD was lost to the rule.
- **To watch:** whether the AI fires a Kh-59M at a SAM group from ~40 km (no Kh-59M has flown yet), and how far out it releases JSOW.

---

### Bug 5. Event log: small fixes

**Status:** fixed 2026-10-01 except (g), not run in DCS yet. (a) the launcher is kept per weapon at `SHOT` (and `Weapon:getLauncher()` as a fallback); (b) "fired SA5B55 at an incoming AGM_88"; (c) "caught in the explosion of SAM_LUOS_SA8_1_1 (Dog Ear radar)"; (d) `statusOf` reads "stood down on the ramp"; (e) the parachute line names the aircraft the pilot left, when the ejection event names the pilot; (f) `ABORTED` folded per flight within 10 s, "(2x)"; (h) "damaged by a nearby explosion"; (i) "fuel 183 % (with external tanks)"; (j) the ring column skips SAM sites with no live unit (checked at most every 30 s); (k) a player's `TAKEOFF` adds "flying MSN2023_OCA?" when one human tasking starts at that base. **(g) closed 2026-10-04 without a `GUNS` line** (John: if one kind of sleeping unit woke and fired, the rest likely will; revisit if that turns out not to be true): in `event_logs\2026-10-04_200249.log` Kuusamo's defenses, asleep all mission, woke with John 27 km out (`UNIT_AWAKE DEF_KUUS` 04:37:55), and 1 min 40 s later both soldiers of `DEF_KUUS_shoulder_launched_missile_teams_1` fired an Igla-S at him from 1–2 km at ~1,100 ft and killed him (04:39:48, 874 ft). The first shot from a base-defense group of a sleeping kind in any run; no `LATE_WAKE`. Still never seen: `GUNS` (no gun group has come into range), so whether DCS sends `S_EVENT_SHOOTING_START` for AI ground guns is unproven.

**Seen:** same log.
- **(a) A dead shooter shows as `? (?)`.**
  - HARMs from MSN2028_SEAD hit `SAM_KUUS_SA11_2` at 08:23:51, after both Hornets had died: "hit by AGM_88 from ? (?)".
  - The MiG-31 MSN5009_CAP_1 was "DESTROYED … by ? (?) with AIM_120C" at 08:39:13: the F-16 that fired had died first.
  - Because of that, the end summary files the MiG-31 under "other ground units" instead of "aircraft".
  - **Fix:** remember each weapon's launcher (name, type, whether it's an aircraft) at `SHOT`, keyed by the weapon; or ask `Weapon:getLauncher()`. Use that when the initiator can't answer any more.
- **(b) Shots at missiles read badly:** "S-300PS 5P85D ln fired SA5B55 at  (AGM_88), 26 km". That's the SA-10 shooting at HARMs.
  - **Fix:** a weapon target reads "at an incoming AGM_88".
- **(c) Secondary explosions read like weapons:** "Osa 9A33 ln hit by Dog Ear radar from SAM_LUOS_SA8_1_1 (Dog Ear radar)"; the same at the Roland and SA-11 sites. The "weapon" is an exploding unit.
  - **Fix:** when the weapon object is a unit, write "caught in the explosion of SAM_LUOS_SA8_1_1 (Dog Ear radar)".
- **(d) The end summary's status is wrong for scrambles stood down on the ramp:** MSN5901, MSN5902, MSN5904 and MSN2904 show "airborne" but never flew.
  - **Fix:** in `ScheduleAirTaskingOrders.statusOf`, a flight that was removed without taking off reads "stood down" (the leash can tell the scheduler).
- **(e) `PARACHUTE` lines don't say whose pilot it was:** the subject is the generic parachute object (`pilot_su27_parachute`, also used for Su-34 pilots).
  - **Fix:** at `S_EVENT_EJECTION`, remember the ejected pilot object (`e.target`, if this DCS version gives it) against the aircraft; name that aircraft on landing.
- **(f) `ABORTED` repeats:** DCS fires "AI abort mission" on hits, sometimes twice in the same second for one flight.
  - **Fix:** fold per flight, like hits.
- **(g) No `GUNS` line all run:** either no AAA or gun came into range, or DCS doesn't send `S_EVENT_SHOOTING_START` for AI ground units.
  - **Next:** check in a run where jets fly low over a defended base (or a quick test mission). Nothing to fix until then.
  - Still no `GUNS` line in the second run (`2026-09-30_213757.log`), but nobody flew low over a defended base there either.

**Seen again in `event_logs\2026-09-30_213757.log`:**
- (a): "SAM_SODA_SA11_1_3 … by ? (?) with AGM_88" (11:23:37), after MSN2024_SEAD_2 had died.
- (b): the Rovaniemi SA-10, IRIS-T and NASAMS firing at Kh-31Ps: "fired SA5B55 at  (X_31P)".
- (c): "NASAMS_Command_Post hit by NASAMS_Radar_MPQ64F1 from SAM_ROVA_NASAMS_1_2", and the same at the IRIS-T site.
- (d): MSN2904, MSN2905, MSN2909 and MSN2910 show "airborne" in the end summary; all four were stood down on the ramp.
- (e): every Red parachute is `pilot_su27_parachute`, and the Blue one is `pilot_f15_parachute`.
- (f): 23 `ABORTED` lines, each at a hit or a death, usually in pairs. They add nothing a `HIT` or `DESTROYED` line doesn't already say. **Fix:** fold, or drop the event entirely.

**New in the same log:**
- **(h) Hits with no weapon and no shooter read "hit by gun from unknown":**
  - at the player's GBU-31 impacts on Vuojärvi: "MiG-29S hit by gun (2 hits) from unknown" (11:40:52, 11:46:41);
  - at a FAB-500 impact on the Banak command post: "GeneratorF hit by gun from unknown" (11:40:53).
  
  These are blast or secondary-explosion hits for which DCS gives neither weapon nor initiator. `weaponName` falls back to "gun" and `who` to "unknown". **Fix:** with no weapon and no initiator, write "damaged by a nearby explosion".
- **(i) Fuel over 100 %:** the player's `POSITION` lines read "fuel 183 %" after takeoff. `Unit:getFuel()` counts external tanks on top of internal fuel. **Fix:** write it as a fraction of internal fuel with a note ("fuel 183 % (with tanks)"), or convert to pounds or kilograms with the profile's `fuel_max`.
- **(j) The nearest-ring column counts dead SAM sites:** from 11:23 the player's lines put them "33 km inside SAM_SODA_SA11_1", but by then that site had lost its search radar and all four launchers. **Fix:** skip a site once no unit that can fire (or no radar) is left, in the ring column and in the `WAYPOINT` lines. The leash's kill-zone test already uses "live" rings; use the same test here.
- **(k) The player isn't linked to their tasking:** `PLAYER_IN` reads "New callsign in a F-16C_50 at Kallax", and nothing ties it to MSN2023_OCA. **Fix:** once a player takes off, name the human tasking that starts from that base (if only one does), e.g. "flying MSN2023_OCA?". Goes with *Assignment and completion tracking* in the `plan.md` backlog.
- **(l) Kills of static objects:** moved to bug 9 (a player-facing popup, not an event-log fix).

---

### Bug 7. An alert base can have no ramp spot for its alert jets

**Status:** fixed 2026-10-01, not run in DCS yet. `planAlertPosture` runs before the patrols and holds `alert_aircraft_per_base` ramp spots per alert base for the whole mission (`reserveAlertSpots`: free of statics, player slots and planned flights, of a terminal type every interception type there fits, nearest a runway). No planned flight is given them; scrambles spawn only on them (`b.spots`). A base that can't spare them isn't an alert base (`WARN`, the next candidate is taken).

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN5901`: "STOOD_DOWN MSN5901_SCRAM before launch: no free ramp spot at Ivalo" (11:45:39). That was Red's only scramble of the run to get as far as launching.

**Cause:** `planAlertPosture` picks alert bases by runway and parking fit, but nothing reserves ramp spots for the alert jets. At launch, `freeSpot` looks for a free ramp spot, and patrol rotations spawning at the same base (MSN5010_CAP spawned at Ivalo at 11:45:12, 27 s earlier) or the parked-aircraft statics may hold them all.

**Proposed fix:** reserve `alert_aircraft_per_base` ramp spots per alert base at planning time, like player slots: parked-aircraft statics and AI parking skip them, and scrambles use only those. If a base can't spare them, it isn't an alert base.

---

### Bug 8. Scramble intercept points sit right at the kill-zone line

**Status:** fixed 2026-10-02, not flown (John: a 10 km margin). `interceptPoint` keeps the point `AIR_DEFENSE.scramble_killzone_margin_km` (10) outside the leash's line; a base left with less than `scramble_min_leg_km` doesn't answer ("no way to the raid outside enemy airspace and kill zones").

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN2902`: "WAYPOINT 2 of 3: intercept point … 7 km inside SAM_SODA_SA11_1" (11:15:45), then 19 s later "LEASH going home: inside the kill zone of SAM_SODA_SA11_1". The scramble was sent home the moment it reached the point it had been sent to.

**Cause:** `interceptPoint` walks out from the base in 5 km steps and keeps the last point outside enemy kill zones (85 % of a ring). The leash sends a jet home as soon as it's inside that same line. A point just outside the line, plus the AI's own intercept geometry, puts the jet over the line almost at once.

**Proposed fix:** keep the intercept point a margin outside the leash's line (e.g. an `AIR_DEFENSE.scramble_killzone_margin_km`, ~10–15 km); if that leaves no leg of `scramble_min_leg_km`, don't scramble.

---

### Bug 9. The player never learns they destroyed static targets

**Status:** fixed 2026-10-01, not run in DCS yet. `BriefAirTasking` watches kills: a static object the mission spawned, destroyed by a player (or by a weapon a player launched, if the player is gone), gives that player's group a 15 s popup, e.g. "Destroyed: MiG-29S (parked aircraft at Vuojarvi): 2 of 3 critical for MSN2023_OCA", then "MSN2023_OCA target destroyed: success" once the success fraction is reached. The scheduler now counts a kill whose shooter is gone, too.

**Seen:** `event_logs\2026-09-30_213757.log`, grep `Aerial-1-2`. John's GBU-31s destroyed two of the three parked MiG-29s at Vuojärvi (`DESTROYED TGT_VUOJ_parked_aircraft_1_static_1` at 11:40:52, `_static_2` at 11:46:41, each followed by `TARGET MSN2023_OCA … n of 3 critical`). Neither kill showed in DCS's own kill list, so in the cockpit John thought the attack had failed.

**Cause:** parked aircraft, and many other fixed-target parts (buildings, parked vehicles), are DCS static objects (`coalition.addStaticObject`). DCS's kill messages and kill list don't show static objects the way they show units. The mission knows about each kill (`WriteEventLog` and the scheduler's `TARGET` line already catch it), but tells only the log.

**Proposed fix** (John, 2026-09-30: every spawned static object a human player destroys gets the message):
- **When:** a player destroys any static object the mission spawned (`plan.fixed_ground_targets.static_objects`, spawned by `SpawnStaticObjects`), whatever it belongs to. Map scenery (buildings that are part of the terrain) gets no popup. Units get none either, since DCS already shows those.
- **What:** a popup to that player's group (`trigger.action.outTextForGroup`, ~10–15 s) naming the object and the target it belongs to. For example: `Destroyed: Hummer (command post, Banak)`.
- **Tasking progress:** when the object is part of a human tasking's target (a mission with `flown_by = "human"`; its catalog target's `static_object_ids`), add the progress from the target catalog (`critical_names`, `success.critical_fraction`), as in the `TARGET` line. For example: `Destroyed: MiG-29S (parked aircraft, Vuojarvi): 2 of 3 critical for MSN2023_OCA`. When the success fraction is reached: `MSN2023_OCA target destroyed: success`.
- **Who killed it:** the kill event's initiator is the player's unit (`Unit:getPlayerName()`). If the initiator is gone (the player was killed or ejected before the bomb landed), use the launcher remembered at `SHOT` (as in 5 (a)).
- **Where:** the scheduler's target progress (`consumers/schedule_air_tasking_orders.lua`, which already writes the `TARGET` line) or the event log's kill handler (`consumers/write_event_log.lua`), calling a small player-message function in `consumers/brief_air_tasking.lua`, the module that already talks to players. The comms-menu wording rule applies to the text.
- Goes with *Assignment and completion tracking* in the `plan.md` backlog, and later with the objective tracking in *Design, not built yet*.

---

### Bug 10. The target steerpoint carries the attack altitude, not the target's elevation

**Status:** fixed 2026-10-01, not run in DCS yet. `TGT` is the target's spot with its ground elevation ("elev 405 ft") and the TOT, followed by `AIM 1`, `AIM 2`, … the same way. Threat steerpoints for SEAD frags not added (open).

**Seen:** the human tasking's `Steerpoints` list in the comms menu. The `TGT` steerpoint gives the planned attack altitude (e.g. 25,000 ft), not the ground elevation at the target. Entered like that, the F-16's steerpoint sits in the air above the target. Fire-and-forget weapons (JDAM, JSOW) need the exact spot on the ground, including its elevation. With a flight altitude on the steerpoint, John has to hunt for the target with the targeting pod when he gets there.

**Cause** (`consumers/brief_air_tasking.lua`, `steerpointText`): every steerpoint except takeoff and landing prints `feet(r.alt_m)`, the route's flight altitude. The frag's `TARGET` block already gives the elevation (`where()` → `land.getHeight`), but the steerpoint list doesn't, and a player types the steerpoint list into the jet.

**Proposed fix:**
- The `TGT` steerpoint prints the ground elevation at the target (`land.getHeight`), marked as elevation (e.g. `elev 420 ft`), not the attack altitude. The attack altitude can stay on the frag (or on the `IP` line).
- When the target has aim points (`m.attack.points`), list each one as its own steerpoint after `TGT`, each with its coordinates and elevation, so each weapon can be given its own spot.
- Check that the coordinates are precise enough for a JDAM (decimal minutes to 3 places is ~2 m, which is fine).
- Also for SEAD frags: the threats "YOURS to suppress" could get steerpoints with elevation too (decide with John).

---

### Bug 11. Human taskings don't need egress or return steerpoints

**Status:** fixed 2026-10-01, not run in DCS yet. The list stops at `TGT` and its aim points (CAP: at `CAP B`), then one `LAND` point with the landing base's elevation and the time home.

**Seen:** the human tasking's `Steerpoints` list continues past the target with `EGR` and the whole route home (the way in reversed, then `LAND`). John: a player can follow the path back out; the extra points only make more to type in.

**Cause** (`consumers/brief_air_tasking.lua`, `steerpointText`): it lists every point of `m.route`, which is planned the same way as an AI flight's (the way out reversed for the way home).

**Proposed fix:**
- The steerpoint list stops at the target (or after the aim points from bug 10), then gives only the landing base as the last steerpoint.
- For CAP taskings, stop after the station's two points (`CAP A`, `CAP B`), then the landing base.
- This replaces the *Steerpoints* item in the `plan.md` backlog ("a return leg that repeats many transit points could be shortened").
- The route itself stays in the plan (the map drawing and the frag's threat check use it); only the list the player types in gets shorter.

---

### Bug 12. The steerpoint list leaves the screen before it's typed in

**Status:** fixed 2026-10-01, not run in DCS yet. Frag 180 s, steerpoints 300 s, other texts 60 s; `Hide text` at the top of the comms menu (Other) clears the screen.

**Seen:** `Comms menu > Other > Human taskings > <MSN> > Steerpoints`. The list disappears while John is still entering it into the F-16's computer, which takes several minutes.

**Cause** (`consumers/brief_air_tasking.lua`): every comms-menu text goes through `show()` with `MESSAGE_S` = 60 s, the frag and steerpoints included.

**Proposed fix:**
- The steerpoint list stays **5 minutes** (a `STEERPOINT_MESSAGE_S` 300) and the frag **3 minutes** (`FRAG_MESSAGE_S` 180) (John, 2026-10-01). Other menu texts keep 60 s.
- Add a `Hide text` entry to the comms menu. It clears the screen (a short empty message with `clearview`), so a long-lasting list isn't in the way once it's entered.
- Picking `Steerpoints` again shows it again from the start, as now.

---

### Bug 14. The airborne cap counts human flights, and flights nobody flies

**Status:** fixed 2026-10-01, not run in DCS yet. Human flights don't count in planning (`airborneAtMost`, the package spans and the patrol check), and players don't count at run time (`airborneAircraft`). Their AI escorts still count and are planned first (the order stays defensive air → human packages → AI packages).

**Seen:** `dcs.log` of the 2026-10-01 run: "BLUE: 2 human flights (MSN2023_OCA, MSN2026_CAP), 2 of 6 missions planned", with four Blue attack missions not planned "over the airborne cap". MSN2023_OCA (a human tasking) was never flown, but its slot was held all along. Its two AI SEAD flights (MSN2024, MSN2025) still flew without it, and all four jets died to the Koshka Yavr SA-10.

**Cause:**
- **Planning** (`stages/plan_air_tasking.lua`, `airborneAtMost`): every mission in `ctx.out.missions` counts against `planned_cap`, human flights (`flown_by = "human"`) included.
- **Run time** (`consumers/run_scrambles.lua`, `airborneAircraft`): counts every airborne aircraft of the coalition, players included.
- **AI escorts of an unflown human tasking** still spawn and fly (the *Unflown taskings' AI flights* item in the `plan.md` backlog), so they count, and die, for a tasking nobody took.

**Proposed fix:**
- `airborneAtMost` skips human flights; `airborneAircraft` skips units with a player in them (`Unit:getPlayerName()`).
- The AI flights of a human package spawn only once a player takes that tasking, or are cancelled when nobody has by the player's takeoff time (goes with the backlog's *Unflown taskings' AI flights* and *Assignment and completion tracking*; decide with John how a player "takes" a tasking). Until a flight spawns it isn't airborne, so it doesn't count at run time.
- Planning still has to fit those AI escorts under the cap in case the tasking is flown.

**Decided (John, 2026-10-01):** players don't take or decline taskings yet, so the AI flights that make a human tasking possible come first. Example (John): a human strike on an airfield whose route needs an AI SEAD flight; that SEAD flight is planned before any other AI tasking.
- **Order stays** defensive air → human packages → AI attack packages, so human taskings keep first pick of targets (session 10) and their AI escorts take their cap room before the AI's own packages.
- **The human flight itself never counts** against the cap (`airborneAtMost` skips `flown_by = "human"`; at run time `airborneAircraft` skips player units). Its AI escorts do count: they fly whether or not a player takes the tasking.
- Cancelling the escorts of a tasking nobody flies waits for *Assignment and completion tracking* (`plan.md` backlog).

---

### Bug 15. A SEAD flight sent home right after takeoff flew out to its target first

**Status:** fixed 2026-10-01, in the third run of the day.

**Seen:** `event_logs\2026-10-01_130749.log`, grep `MSN5026`. 15 s after takeoff from Vuojärvi, the SEAD go-cold rule sent MSN5026 home: "inside the kill zone of SAM_ROVA_SA10_1". Going home followed the planned way back, which starts at the egress point near the launch point, so the flight flew ~15 min out toward its target, climbing, and turned there without firing (its attack task was gone).

**Cause:**
- Kill zones used 85 % of a site's drawn ring, ED's high-altitude figure, at every altitude. Vuojärvi is 60 km from the Rovaniemi SA-10 (ring 120 km), and flights had used it all mission unharmed: an SA-10 reaches a low flyer at only ~40 km.
- "Home by the way back" didn't look at where the flight was.

**Fix:**
- Kill zones depend on altitude (`lib/sam_reach.lua`, `low_altitude_engage_km` per system), in the SEAD rule, the leash and the scrambles' SAM-cover refusal; no AI flight launches from a base inside an enemy site's low-altitude kill zone (John: no flights up into instant death).
- The SEAD rule ignores rings its planned route passes through on purpose (`route_threats`).
- Going home turns the flight around where it is: its route out backwards before the launch point, the planned way back after it (John: turn around at once, or don't fly at all).

---

### Bug 16. A scramble launched from the wrong base: a tail chase from Rovaniemi while Blue's northern bases held no alert

**Status:** fixed 2026-10-02, not flown. John: no tail chases, and every base with a fitting runway is an alert base.
- **Alert posture:** every held base whose runway and parking fit an interception type, outside enemy kill zones, holds `alert_aircraft_per_base` (3) jets (`alert_bases` is gone). On the 10:38 roll: Blue 17 alert bases (Enontekiö has no 3 free spots), Red 11; missions and patrols planned as before over six seeds.
- **No tail chases:** a base answers only a raid whose heading is within `AIR_DEFENSE.scramble_tail_chase_deg` (100°) of the line from the raid to the base; else that base refuses "flying away from it" and the next one is tried.

**Seen:** `event_logs\2026-10-01_134933.log`, grep `MSN2901`, `MSN5023_STRIKE`.
- MSN5023_STRIKE (2× Su-24M from Kittila) flew north toward `TGT_ALTA_communications_site_1`, heading 345–354, flying away from Rovaniemi (44 → 115 km from the Rovaniemi Patriot between 06:09 and 06:16).
- 06:14:04: `SCRAMBLE MSN2901_SCRAM FA-18C_hornet from Rovaniemi after MSN5023_STRIKE … 13 min from TGT_ALTA_communications_site_1; intercept 95 km out`. It spawned at 06:15:25: a tail chase behind a raid flying away from the base.
- Blue's alert bases this roll: Rovaniemi, Kuusamo, Hosio, all on the southern / eastern front. Blue also held Banak (and Alta, Tromsø, Bardufoss, Evenes, Andøya) in the north, where the raid was going, with no alert jets. (Alta's 1,490 m runway is just short for the F-16 / F/A-18; Banak fits.)

**Cause:**
- **Alert posture** (`planAlertPosture`, `stages/plan_air_tasking.lua`): the alert bases are the `alert_bases` (3) held bases nearest the enemy, plus the nearest of each other region. "Nearest the enemy" picks one stretch of the front, here Rovaniemi / Kuusamo / Hosio at 64–137 km, and leaves another stretch (Finnmark: Banak is farther from the nearest Red base) with nothing. Distance to the enemy says nothing about which own assets a base can defend.
- **Base pick** (`pickBase`, now `consumers/control_air_flights/scramble_fighters.lua`): the nearest ready alert base whose intercept point is in reach, at least `scramble_min_leg_km` out and reached in time (bug 1's test). Nothing looks at the geometry: a base behind a raid flying away from it passes when the raid is slow enough, and the jet chases it from behind toward someone else's sector.

**Proposed fix (decide with John):**
- **Alert bases by coverage, not by distance to the enemy:** pick alert bases so every own asset near the front (held bases and catalog targets in or near the contested airspace, the patrol stations' defended sites) is within a scramble radius (e.g. ~150 km) of one, greedily the base covering the most uncovered assets first, up to a maximum (e.g. 4–5). Finnmark would then get Banak.
- **No tail chases:** a base only answers a raid that is coming toward it or passing across it, not one flying away from it (e.g. the raid's heading points within ~100° of the bearing from the raid to the base, or the intercept point lies ahead of the raid and nearer the asset it threatens than the raid is). Otherwise `NO_SCRAMBLE … flying away from <base>`, and the next base is tried.
- Or prefer the alert base nearest the **asset the raid threatens** (`threat_asset`) rather than nearest the raid.

---

### Bug 17. A DEAD flight flew into a live SA-11 with glide bombs, behind a player SEAD tasking nobody flew

**Status:** fixed 2026-10-01 (found the same day, John: "attacking an SA-11 with glide bombs. That's never going to work"; then: "if the AI DEAD missions only fly after successful SEAD missions then the AI DEAD missions should also only fly after successful human SEAD missions"). An AI mission behind a player's SEAD tasking now flies in sequence: it starts `strike_after_suppression_s` after the player's planned landing (`scheduleHumanSeadPackage`) and launches only once its threats are out of the fight; if not, two AI jets fly the player's SEAD tasking once (`<id>_AGAIN`, the AI SEAD loadout, the same route), then the mission is cancelled. AI DEAD missions in AI packages already worked this way (their route enters their own target's ring, so it gets a SEAD flight and they wait for it). Standoff DEAD weapons stay with bug 4.

**Seen:** `event_logs\2026-10-01_134933.log`, grep `MSN2023_DEAD`, `MSN2024_SEAD`.
- PKG2023: MSN2023_DEAD, 2× F-16C from Banak with AGM-154A JSOW ×2 each (Liberation DEAD loadout), against `SAM_KIRK_SA11_1`; its suppression was **MSN2024_SEAD, a player tasking**. No player flew it (no `PLAYER_IN`).
- The DEAD flight flew its route into the live SA-11's ring: descent point 8 km inside it (06:17:51). The SA-11 fired from 39 km at 06:18:02, and both jets were shot down 19 km inside the ring (06:18:46, 06:18:58), before releasing anything.

**Cause:**
- **The suppression was a player's, and nobody flew it.** A package with a human flight flies together and isn't gated (only AI packages in sequence wait for their SAMs to be out of the fight), so the AI DEAD went in against a live radar. The same as the backlog's *Unflown taskings' AI flights*, the other way round: here the AI mission depends on the player.
- **DEAD flies its own attack into the ring** with a short-range glide weapon (bug 4 and roadmap 4c issue 1): ingress 30 km before the target, inside an SA-11's 35 km ring, so a live site always gets the first shot. A JSOW is a weapon for a site that is already blind, not for one still looking.

**Proposed fix (decide with John):**
- **DEAD only against a blind site:** a DEAD mission always gets a SEAD flight on its own target site first, and (like any AI mission in sequence) launches only once that site's radars are out of the fight; its glide bombs then finish the launchers and command post. Its route's other threats as before.
- **An AI mission behind a player's SEAD** waits for the player: it launches only once its threats are out of the fight (the same check as in sequence), waiting while the tasking could still be flown, else cancelled. Or the planner never puts an AI mission behind a player SEAD: the player's SEAD tasking escorts an AI package that has its own AI SEAD as well.
- Longer term: standoff DEAD weapons released outside the ring (the *Standoff attacks* backlog item, bug 4).

---

### Bug 18. Patrol handover: the old patrol stays on station after its relief arrives

**Status:** fixed 2026-10-02, not flown. Patrols are now watched by the controller with the directive `handover`: once a later patrol of the same station is on task and within `AIR_CONTROL.handover.on_station_km` (15) of the race-track, the old one goes home: `CONTROL … handover: relieved by MSN2003_CAP, on station (2 km from the race-track)`.

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN2002_CAP`, `MSN2003_CAP`.
- Both fly station CAP_KIRU_front_1 from Kiruna. MSN2003 (F/A-18C) was on station at 07:00:24, 7 min ahead of its planned 07:07, because the station is ~1.5 min from Kiruna. MSN2002 (F-16C, on station since 06:10, also 7 min early) stays until ~07:17.
- From 07:02 both flew the same race-track, 26,247 ft, 440 kt, about one minute apart, like one stacked 2-ship.

**Cause:** rotations are planned to overlap (the next patrol arrives 10 min before the last leaves, `plan.md`, *Rotations*), and the outgoing patrol keeps its planned off-station time whatever happens. A short transit stretches the overlap further.

**Proposed fix:** when the relief reaches its station (its on-station `WAYPOINT`), send the outgoing patrol on that station home (`Controller:setTask` home, as the leash does). Keep the planned overlap as the latest handover time.

---

### Bug 19. A flight that misses its landing flies off in a straight line until its fuel runs out

**Followed up 2026-10-07 as bug 75** (`bugs.md`): the cause researched (AI wingmen don't land once their lead has landed) and three fixes to try; the workaround below stays until one works.

**Status:** fixed 2026-10-02; the landing orders didn't hold in the 19:29 run, so orphaned wingmen are now removed 8 min after their flight's last landing (below; not flown). First fix: Every AI flight now has the directive `landing` (`AIR_CONTROL.landing`): once a flight is on its way home (sent home, a jet of it landed, or past its planned landing), a jet that gets `away_km` (20) farther from its landing base than its closest since, or a flight still up `overdue_s` (20 min) after its planned landing (or its last order), gets a new landing order straight to its base: `CONTROL … land: MSN7025_SEAD_2 lost after its landing: 45 km from Vuojarvi and getting farther (it was 2 km away); sent to land at Vuojarvi`. At most 2 orders, and never while a jet of the flight is on the ramp (a landed one is removed after 3 min; a late wingman not yet up), so no landed jet is sent up again. Packages: a suppression flight still in the air but off its attack and past its planned landing counts as landed for the wait (`decide_launches.lua`), so the mission retries or cancels instead of waiting on it.

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN5025_SEAD_2`.
- MSN5025_SEAD (2× Su-34 from Vuojärvi) went cold at 06:23 and flew home. `_1` landed at Vuojärvi at 06:34:12; `_2` was beside the field at 06:33.
- From 06:34 to the end of the run (07:07) `_2` held heading 317, 303 kt, 4,445 ft: ~300 km in a straight line, out of its own airspace into contested airspace, fuel 52 % → 31 %.
- **Knock-on effect:** MSN5023_OCA was `DELAYED` twice ("waiting for MSN5025_SEAD, still in the air"), so the package's mission was held up by a jet that would never land.

**Cause (suspected):** `_2` missed its landing (most likely a go-around behind its lead) and, with no waypoints left after `Land`, the DCS AI flies on along its last heading. Nothing in the script notices a flight that should have landed.

**Seen again with the fix in, 2026-10-02 (`event_logs\2026-10-02_192901.log`):** all 4 two-ship SEAD flights orphaned their wingman (MSN7023, MSN7023_SEAD_AGAIN, MSN2026, MSN2025). MSN7023_SEAD_2 flew back into the Ivalo SA-11 with 4 Kh-31P aboard and was shot down; MSN2026_SEAD_2 drifted into enemy airspace and drew a MiG-31 scramble. The `land` orders were given and mostly ignored: MSN7023_SEAD_2 and MSN7023_SEAD_AGAIN_2 ignored both of theirs; MSN2026_SEAD_2 turned home ~3 min after its second, maybe on its own.
- **All runs, every flight whose lead landed with a wingman alive in the air:** 6 landed normally (the wingman held at ~4,300 ft, circled and landed 0–7.5 min after its lead), 7 orphaned (a straight line at 300–315 kt and 4,200–4,450 ft, the same holding altitude). So it is roughly half the time, and it starts at the lead's touchdown (MSN7023_SEAD_2 was on its straight heading 30 s after), not at the landed lead's removal 3 min later.

**Fixed again 2026-10-02, not flown (John: despawn it after 8 min, the latest wingman that landed came down 7.5 min after its lead, and count it as landed in case another flight waits on it):** the `landing` directive removes any jet still in the air `AIR_CONTROL.landing.orphan_remove_after_s` (480) after its flight's last landing, fight or not, and the scheduler counts it as landed (`ScheduleAirTaskingOrders.removedInAir`), so the flight is down for the gate and the SEAD rotation. `CONTROL … >>orphan<< removed: by the controller 8 min 00 s after MSN7023_SEAD_1 landed, counted as landed (Su-34 at 4,232 ft, 64 km from Banak)`. The landing orders stay for the first 8 min. Checked in a luae harness with stubbed DCS.
- **Tracked in the event log** (John: so we don't lose track if it gets worse or better): `CONTROL` lines marked `>>orphan<<` (John: the controller runs them, so they're CONTROL; the marker makes them easy to find), one when a jet is still in the air as another of its flight lands (`>>orphan<< possibly orphaned: still in the air when <lead> landed (<type> at <height>, <km> from <base>)`), and one for how it ended: `>>orphan<< not orphaned: landed at <base> 4 min 40 s after <lead>`, `>>orphan<< removed: by the controller 8 min 00 s after <lead> landed, counted as landed`, or `>>orphan<< lost: 9 min 50 s after <lead> landed`. Grep `>>orphan<<`.

**Proposed fix:**
- Watch every AI flight after its last waypoint (or once sent home): if it is overdue to land (e.g. 10 min past its planned landing, or its time home), or getting farther from its landing base for a few minutes in a row, give it a new landing order (`Controller:setTask`, as the leash and the go-cold rule do) at its base, or the nearest held base it can reach. Log it (`LEASH`-style line, e.g. `LANDING … lost after its landing, sent to land at <base>`).
- Packages in sequence stop waiting for a flight that is overdue: a suppression flight whose jets have all fired, gone home and are overdue counts as landed for `DELAYED`.

---

### Bug 20. The SEAD go-cold timer counts from the planned time, so a late flight is sent home before it attacks

**Status:** fixed 2026-10-01 with roadmap item 10, not flown yet (found 2026-10-01). Late takeoffs are DCS AI taxiing and aren't a bug (John: a flight 6 min late or early is fine; the goal is that every mission gets flown and things go smoothly). This one is a bug because the lateness makes the mission fail.

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN5026_SEAD`. Six Su-34s of three SEAD flights spawned at Vuojärvi at 06:02 with the same planned takeoff (06:12); they left between 06:06 and 06:30. MSN5026's lead took off at 06:24 and its wingman at 06:30. At 06:31:34 the go-cold rule sent it home, "still on the attack 10 min after its time at the launch point", while it was at its departure waypoint (06:30:12), nowhere near the site. It never attacked; the Kuusamo IRIS-T it was meant for stayed untouched.

**Cause:** `attack_time_s` (10 min) in the `suppression` rule is measured from the flight's *planned* time at the launch point.

**Proposed fix:** start the clock when the flight reaches its launch point (its `target` waypoint), or from the planned time shifted by how late the flight took off. Optional, with it: some limited planning for taxi time, e.g. stagger flights spawning at the same field by a few minutes per 2-ship.

**Fix:** the clock starts when the flight comes within `AIR_CONTROL.suppression.arrival_km` (15) of its launch point, however late it took off (`directives_per_flight.lua`, `suppression`); the line now reads "still on the attack 10 min after it reached its launch point". No taxi-time planning added.

---

### Bug 21. Red flight numbers: MSN7xxx instead of MSN5xxx

**Status:** done 2026-10-02. `stages/plan_air_tasking.lua`: `FIRST_NUMBER.red` 5001 → 7001 (scrambles follow at 7901); the example comments in the controller, scramble, alert-jet, sleep and event-log modules now use 7xxx; comments citing real flights from past runs keep their 5xxx numbers. A re-plan of the 2026-10-02 roll gave MSN7001_AEW, MSN7023_STRIKE … and scrambles from 7901. `plan.md` *Naming and ids* updated.

**Was:** open, change requested (John, 2026-10-01).

**Now:** Blue flights are `MSN2001+` (scrambles `MSN2901+`), Red flights `MSN5001+` (scrambles `MSN5901+`).

**Change:** Red flights `MSN7001+`, Red scrambles `MSN7901+`; Blue unchanged. Packages follow their mission's number (`PKG7023`).

**Where:**
- `stages/plan_air_tasking.lua`: `FIRST_NUMBER = { blue = 2001, red = 5001 }` → `red = 7001` (scrambles are `first_number + 900`, so 7901 follows), and the comment above it (line ~119).
- Comments and examples naming 5xxx flights: `consumers/control_air_flights/scramble_fighters.lua` (header: "Blue 2901+, Red 5901+"), `consumers/control_air_flights/control_air_flights.lua`, `consumers/write_event_log.lua`, `data/air_tasking.lua`.
- `plan.md` *Naming and ids* (Flight row: "Red 5001+ (scrambles … 5901+)") and the event-log examples.
- Old event logs and the docs' run notes keep their 5xxx numbers (history).

---

### Bug 22. The low SEAD way out climbs through short-range SAMs the routing doesn't see

**Status:** fixed 2026-10-02, not flown. The SEAD low-threat map (`ctx.low_threats`, `threatCircles` kind "low") now also holds every enemy short-range SAM site's ring + `short_range_margin_km` (5): the whole way in and out, low legs and climb-out included, routes around them, and the launch point keeps clear of them. On the 10:38 roll every SEAD route kept ≥ 5 km outside every short-range ring; SEAD flights planned unchanged over six seeds.

**Seen:** `event_logs\2026-10-01_222355.log`, grep `MSN5024_SEAD`, `SAM_BANA_SA8_2`.
- MSN5024_SEAD (2× Su-34 from Kilpyavr) fired its 8 Kh-31P at `SAM_BANA_IRISTSLM_1` from 41 km (03:55:35), went cold, went out low, and climbed through 6,000–11,000 ft in contested airspace (03:58–04:00).
- That put it within 13 km of `SAM_BANA_SA8_2` (an SA-8, ring 10 km). The SA-8 fired three missiles; MSN5024_SEAD_1 was shot down at 6,040 ft (04:00:09), `_2` got away.
- On the way in, the flight passed the same SA-8 at 26,000 ft, above its reach.

**Cause:** short-range SAM sites (SA-8, SA-15, Roland) aren't planned threats: `lib/threat_routing.lua` routes attack flights around medium and long-range rings only (+ base-defense Pantsirs / Tors). That was safe while flights stayed at ≥ 7,500 m; item 10's low ingress, low egress and climb-out now fly inside a short-range SAM's reach. This answers item 10's open question "short-range SAMs are deadly down low".

**Proposed fix:** route the SEAD flight's low legs and its climb-out (everything below the short-range systems' ceiling, ~5,000 m) around short-range SAM sites too, with a margin (SA-8 10 km, SA-15 12, Roland 8, + ~5 km). The launch-point clearance test could count them the same way.

---

### Bug 23. A scramble refusal names the reason of the last alert base tried, not the best one

**Status:** fixed 2026-10-02, not flown. `pickBase` keeps each ready base's reason and gives the one nearest the raid: `no scramble: Su-24M: Rovaniemi: flying away from it (and 2 more alert bases refused)`.

**Seen:** `event_logs\2026-10-01_222355.log`, grep `no scramble: FA-18C`: `RED CONTROL MSN2025_SEAD no scramble: FA-18C_hornet: can't reach the raid before it reaches SAM_KUUS_SA8_1 (26 min, raid 5 min)` (03:43:34). The raid was next to Kuusamo, a Red alert base with jets ready; 26 min is almost certainly the time from Alakurtti or Koshka Yavr. Why Kuusamo itself was refused doesn't show.

**Cause:** `pickBase` (`consumers/control_air_flights/scramble_fighters.lua`) overwrites `why` for every alert base it tries, so the logged reason is the last base in the posture list.

**Proposed fix:** keep each base's reason and log the nearest base's (or all of them, `Kuusamo: …; Alakurtti: …`).

---

### Bug 24. The player appears under two names in the event log

**Status:** fixed 2026-10-02 by John in the Mission Editor (found 2026-10-01, 22:23 run).

**Seen:** `event_logs\2026-10-01_222355.log`: `PLAYER_IN`, `TAKEOFF`, `SHOT`, `POSITION`, `HIT`, `DESTROYED` say `f16_kallax-1-5` (the unit, spawned at Rovaniemi), while the radar picture's `CONTACT`, `TRACKING` and `CONTROL` lines say `f16_rovaniemi` (the group). Grepping one name misses half the player's story.

**Cause (found 2026-10-02, in the `.miz`):** the slot templates were copied from Kallax, so their units kept Kallax names: group `f16_rovaniemi` holds unit `f16_kallax-1-5`, `f16_kiruna` holds `f16_kallax-1-1`, `f16_banak` `f16_kallax-1-3`, `f16_tromso` `f16_kallax-1-4` (only `f16_rovaniemi-1-1` in `f16_kemi_tornio` is different, and also wrong). Unit events log the unit name, the radar picture the group name.

**Proposed fix:** rename each template's unit in the Mission Editor to match its group (`f16_rovaniemi-1-1`, …), then re-run `kola_data_tools/miz_player_slots.py`. Optionally also log the group name on player lines.

**Fix:** John renamed each slot template's unit to match its group (2026-10-02). `miz_player_slots.py` needed no re-run: `data/player_slots.lua` keeps group names only.

**Checked 2026-10-02 (`event_logs\2026-10-02_145532.log`):** `PLAYER_IN` and every `PICTURE_CALL` say `f16_tromso`, so grepping the group name finds the player's lines. The player didn't take off that run, so `TAKEOFF` / `POSITION` / `SHOT` weren't seen under the new name.

**Confirmed 2026-10-02 (`event_logs\2026-10-02_192901.log`, John flying MSN2023_SEAD from Ivalo):** every player line is `f16_ivalo`: `PLAYER_IN`, `TAKEOFF`, `POSITION`, `SHOT`, `HIT`, `DESTROYED`, `PICTURE_CALL`, and the radar picture's `CONTACT` and `CONTROL` lines. Closed.

---

### Bug 25. No friendly datalink tracks and no SAM threat rings on the player's HSD

**Status:** fixed and confirmed in Kola 2026-10-02 (the second fix; the first, below under *Fix*, wasn't enough). Found 2026-10-02 (John: both used to work; first flight after a few months of DCS updates). The AWACS's enemy tracks: bug 26.

**What works (confirmed in Kola, 2026-10-02, John: threat rings and datalink contacts on the HSD):** several suspects were changed in one run, so it isn't known which one mattered. **Keep all of them together:**
- **AI aircraft** (`consumers/spawn_aircraft_groups.lua`): an explicit group id (700000+); the EPLRS command (`WrappedAction` `EPLRS`, `value = true`, that `groupId`) as the **first task of the first waypoint**, as the mission editor does it (the `setCommand` EPLRS right after the spawn is kept too); per unit its own Link 16 STN (`AddPropAircraft.STN_L16`, octal from 01000) and the editor's `datalinks.Link16` block (`settings` flight lead / channels / power, `network` with empty `teamMembers` and `donors`). `dcs.log` warns if DCS doesn't take the group id.
- **SAM sites** (`consumers/spawn_ground_groups.lua`, `init.lua`): medium and long-range site groups spawn with `hiddenOnMFD = false`; every Red SAM group spawns as country **Russia**, not CJTF Red.
- **Player slots:** John's F-16 templates are country CJTF Blue (the AI's country; was USA), each with its own STN (00201–00211), a team of itself only, no donors, empty DTC.
- **Not enough on its own** (the 00:57 run): STN + `setCommand` EPLRS right after a ramp spawn, CJTF Red SAMs with `hiddenOnMFD = false`, player slots as USA: nothing showed. Country alone (slots to CJTF Blue): nothing.

**Seen:** in Kola, no datalink contacts and no threat rings on the F-16's HSD. A Caucasus test mission (`Saved Games\DCS\Missions\datalink_hsd_test.miz`, built by script; John flew it the same day) split it up:
- AI aircraft placed in the mission editor, and a script-spawned F-16 pair with the EPLRS command and STNs: all shown on the HSD (the editor team as his flight, the rest as datalink contacts).
- A script-spawned F-16 pair spawned the way Kola spawns its AI (no EPLRS, no STN): **not shown**.
- A script-spawned SA-11 with `hiddenOnMFD = false`: ring shown. An SA-11 placed in the editor (its F-16 had an empty DTC): no ring. Kola's SAMs, script-spawned without the field: no rings.

**Cause:** the mission editor gives every AI flight an EPLRS command (datalink on) on its first waypoint and each Link 16 aircraft an STN; Kola's spawner gave neither. Kola's ground spawner never set `hiddenOnMFD`, and DCS's default hides the group from the HSD.

**First fix (not enough on its own, 00:57 run):**
- `consumers/spawn_aircraft_groups.lua`: every AI unit gets its own STN (`AddPropAircraft.STN_L16`, octal from 01000; the player slots use 00201–00211), and every spawned flight gets `setCommand({ id = "EPLRS", value = true, groupId })` at once (scrambles and `_AGAIN` copies go through the same spawner).
- `consumers/spawn_ground_groups.lua`: `run(entries, label, { show_on_mfd = set })` spawns those groups with `hiddenOnMFD = false`; `init.lua` passes every medium and long-range SAM site (not escorts, not short-range or early warning). A forum report (since the 12 May 2026 update) says the HSD shows about 16 threats at most; Red fields ~11 such sites per roll. Fits the fog-of-war rule's "confirmed" strategic SAMs.
- Also found: the slot templates' unit names (bug 24).

---

### Bug 26. The AWACS's enemy tracks don't reach the player's HSD

**Status:** closed 2026-10-02 (session 18): not a bug in our spawn. The test mission showed the AWACS's tracks reach the player's HSD however it is put in the mission; Kola's E-3A as spawned today works. John: the improved AWACS coverage (bug 42) should solve what he saw.

**Seen:** `Saved Games\DCS\Missions\datalink_hsd_test.miz`: the E-3A (EPLRS on, listed as the player's Link 16 donor) showed on the HSD as a datalink contact, but the Red MiG-29S 250 km from it never did; John saw the MiG only on his own radar.

**Suspects:**
- The E-3A has no STN of its own in the test (the editor template gave it none), so the donor link may not work.
- Since 2026, air-track identity on the F-16 depends on the DTC's ROE tab, and the test's DTC was empty: hostile tracks may be filtered or never declared.
- The E-3A may not have detected the MiG (no way to tell from the test; the Kola event log's radar picture would show it).

**Seen in Kola, 19:29 run** (`event_logs\2026-10-02_192901.log`; John, flying MSN2023_SEAD with his HSD at 120 and 240 nm for long stretches): no enemy contact on the HSD all mission. Two of the Red jets after him were never in Blue's picture at all (the E-3A was 460–550 km away; bug 42), so nothing could have reached his HSD for those. But from 04:44 to 04:50 Darkstar called "unknown - 355/78nm, 30k, hot": the MiG-31 scramble MSN7902, which the E-3A was tracking (`CONTACT … seen by awacs MSN2001_AEW`). John can't say for sure that it wasn't on the HSD then; he'll check deliberately next time.
- The Kola E-3A spawns with an STN, the Link 16 block and EPLRS like every AI flight, but **no callsign** (DCS's own AWACS voice calls fail: "Callname -1 not found for MSN2001_AEW_1", 15× in `dcs.log`), and the player slots list **no donors** (a spawned unit can't be named in the .miz).

**Test mission built 2026-10-02 (session 18): `Saved Games\DCS\Missions\awacs_hsd_test.miz`** (Caucasus, from `Sep29CawkusPlay2.miz` like the bug 25 test; builder and script in the session-18 scratchpad, `hsd2\make_awacs_hsd_test.py` and `awacs_hsd_test.lua`). The player is set up like a Kola slot (CJTF Blue, STN 00201, a team of itself) plus one donor. Two Red jets on weapons hold that never react: a MiG-29S at 25,000 ft ~140 km from the AWACS orbit, a Su-25T at ~2,000 ft ~80 km from it. Everything lies ahead of the player, who starts over the Black Sea heading east (John, no HOTAS: autopilot and mouse only): at the start the AWACS orbit is ~120 nm ahead, the Su-25T ~165 nm, the MiG ~195 nm, all within 10° of the nose; after 20 min on autopilot the Red jets are still 45+ nm ahead. Comms menu > HSD test, one at a time (each removes the one before):
- **A:** an E-3A spawned exactly the Kola way (no callsign);
- **B:** the same with a callsign (Magic 1-1);
- **C:** an editor E-3A (late activation) that is the player's donor (Darkstar 1-1);
- **D:** an editor E-3A that isn't (Overlord 1-1);
- **E:** no AWACS, an AI F-16 pair spawned the Kola way facing the MiG (their own radars).

Every 10 s an on-screen line (and `dcs.log`, `[AWACS HSD TEST]`) says whether the active test's own radar sees each Red jet, so "the AWACS doesn't see it" and "the datalink doesn't pass it" can be told apart.

**Next:** John flies it. What the Kola fix is follows from which tests show the Red jets: A shows them → nothing to fix in the spawn (look at the 19:29 case again); only B → give every AI flight a callsign from DCS's lists; only C → an editor-placed late-activation AWACS in the Kola .miz, listed as every slot's donor, activated and routed by the script; none → DTC / ROE identity or a DCS limit, look further.

**Result (John flew `awacs_hsd_test.miz`, 2026-10-02):**

| Test | AWACS | HSD | The AWACS's own radar |
|---|---|---|---|
| A | spawned exactly the Kola way, no callsign | 2 yellow contacts + 1 friendly | MiG-29S SEEN (162 km), Su-25T not seen |
| B | A + callsign Magic 1-1 | same | same |
| C | editor E-3A, late activation, the player's donor | same | same |
| D | editor E-3A, not a donor | same | same |
| E | no AWACS: an AI F-16 pair spawned the Kola way | friendlies only | neither Red jet seen |

- **The datalink works with Kola's spawn as it is**: callsign, donor and editor placement make no difference. What John saw in the 19:29 run was coverage: the jets that attacked him were never in Blue's picture (bug 42, the AWACS placement, fixed).
- **AWACS tracks show yellow (unknown), not red (hostile):** easy to miss on a busy HSD, probably why the MiG-31 Darkstar called at 78 nm went unnoticed. Making them hostile (Link 16 identity, likely the DTC's ROE page) is in the `plan.md` backlog.
- **The E-3A never saw the Su-25T at ~2,000 ft, 80 km away**, while it saw the MiG-29S at 25,000 ft at 162 km: the DCS AWACS is weak against a low jet over land. Darkstar's coverage call (bug 42) uses 250 km whatever the threat's height, so it overstates coverage for low threats; tune from the `CONTACT` lines' "km away" (`plan.md`, *Still to watch*).
- Test E settles nothing on fighter-to-fighter tracks: the AI F-16s never detected the MiG (~87 km).
- A callsign doesn't matter for the datalink, but it would stop DCS's own AWACS voice calls failing ("Callname -1 not found"): a backlog item with the callsign policy.

---

### Bug 27. SEAD flights shot down at the pop-up: the sites reach far more than the low-altitude model said

**Status:** fixed 2026-10-02, not flown. Tuned first (John: "pop up and fire earlier, and go cold as soon as they loose the salvo"), then the reach model fixed as step 0 of roadmap item 12 (session 15, late).

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN2024_SEAD`, `MSN5024_SEAD`, `MSN5025_SEAD`. Every SEAD jet that reached its target died (6 of 6; MSN5031's two died earlier, to a scramble):
- MSN2024 (2× F-16 on `SAM_ALAK_SA11_1`): the profile as planned (cruise 24,600 ft, low leg 1,400–1,600 ft, pop-up), 8 HARMs from 33–44 km at ~10,000 ft; the SA-11 fired at 39 km and both jets died ~28 km from it. The search radar died to a HARM; the launchers (each with its own radar) kept shooting. The AI kept closing during the 33 s salvo (43 → 33 km) and the go-cold came 8 s after the first hit (the 30 s picture round).
- MSN5025 (2× Su-34 on `SAM_ROVA_Patriot_1`): Vuojärvi is ~58 km from the Patriot, so it popped up 80 s after takeoff; the Patriot fired at 50 km at 8,300 ft; it dived, never fired a Kh-31P, both died.
- MSN5024 (2× Su-34 on `SAM_KITT_SA10_1`): never above ~3,400 ft (bug 28; a 52 s pop-up leg); the SA-10 fired at 46 km; one jet fired 4 Kh-31P from 36–45 km and killed the 40B6M tracking radar; the SA-10 fired 8 missiles at the Kh-31Ps.

**Cause:** `lib/sam_reach.lua` lets a site reach only its low-altitude figure (SA-11 25 km, Patriot 30, SA-10 40) up to `killzone_low_altitude_m` (3,000 m), and the pop-up goes to exactly that altitude, 40 km out. At 3,000 m the sites see and reach nearly their full envelope; the low figure only holds near the ground (radar horizon, clutter).

**Done 2026-10-02:**
- `launch_km` 40 → 55 and `popup_km` 12 → 15 (`data/air_tasking.lua`). Re-planning the 00:57 roll over six seeds: SEAD flights 3–6 → 5–8 per coalition, AI attack missions 2–8 → 4–8 (a launch point farther out is clear of more sites).
- Go cold the moment the last anti-radiation missile leaves: the `suppression` directive runs on the fast check (5 s), and the controller runs it again 0.5 s after each anti-radiation missile a watched flight fires.
- The pop-up altitude is now held through the attack (bug 28).

**The reach model (roadmap item 12, step 0):** `lib/sam_reach.lua` now goes by height above the ground (`SamReach.aboveGround`): the low figure up to `killzone_low_altitude_m` (300 m), the full ring from `killzone_high_altitude_m` (3,000 m), straight between (were 3,000 / 7,000 m above sea level). All three shots fit (the Patriot reaches 50 km at 900 m above the ground). Used that way by the leash, the bandit call's kill-zone check, go cold and the scrambles' SAM cover (the contact's altitude made a height above the ground). Not used for the SEAD launch point and low route: they stay cleared of the other sites' low figure, the pop-up being accepted exposure (every SEAD jet lost at its pop-up fell to its own target; with the truer reach a launch point would have to sit outside every other site's full ring and Kola's core would go unattacked); to match, go cold ignores other sites' kill zones from the pop-up (within `popup_km` + 2 km of the launch point) until the salvo is away. The validation that the pop-up stays below `killzone_low_altitude_m` is gone. John confirmed the split (2026-10-02: "probably fine"); the next run will tell. Watch: `SHOT` ranges of the salvo and of the sites back, `CONTROL.*go cold` seconds after the last missile and none for another site during the pop-up, losses.

---

### Bug 28. Attack tasks carried no altitude: the AI flew its attack low

**Status:** fixed 2026-10-02, not flown.

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN2027_STRIKE`. 2× F/A-18C from Kittilä on `TGT_SODA_airfield_fuel_storage_1`, every waypoint planned at 7,000–7,500 m, flew the whole way at 2,400–3,600 ft and dropped GBU-31s from 3,585 ft; the Sodankylä SA-8 shot both down. MSN5024_SEAD fired from ~3,400 ft (pop-up planned at 3,000 m). MSN2026_SEAD_AGAIN reached its launch point at 2,600 ft (planned 3,000 m).

**Cause:** two DCS AI behaviours. (1) Every `Bombing` / `AttackGroup` task was sent with `altitudeEnabled = false`, so once the attack starts the AI picks its own altitude. (2) The lead holds low and slow until its wingman has taken off and joined (MSN2027's wingman took off 2.5 min after the lead; MSN2024's 4 min, its lead circled at ~2,000 ft for 8 min). On a short route the attack starts before the climb ever happens.

**Fix:** `consumers/spawn_aircraft_groups.lua`: `Bombing`, `AttackGroup` and the SEAD salvo carry the route's target-waypoint altitude (`altitudeEnabled = true`), so the AI attacks from the planned altitude. Watch `SHOT … from <ft>` on bombs and anti-radiation missiles. The wingman delay is DCS's (John: taxi times are DCS).

---

### Bug 29. The AI retry of a player's SEAD tasking against a Tor went home without firing

**Status:** fixed 2026-10-02, not flown (John: closer launch point). The launch distance is the target's reach + `launch_past_reach_km` (15), at most `launch_km` (55): Tor M2 31 km, Pantsir 35, NASAMS 30, SA-6 40, Roland / Tunguska 23; SA-11, IRIS-T, Hawk and the long-range sites stay at 55. A SEAD flight that has reached its launch point with every anti-radiation missile still aboard 2 min later gets one line: `CONTROL … no shot: 2 min after reaching its launch point, 31 km from DEF_VUOJ_…, all 8 anti-radiation missiles still aboard`.

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN2026_SEAD_AGAIN`. John flew the other tasking, so the controller flew MSN2026_SEAD (his unflown SEAD on the Vuojärvi Tor M2, `DEF_VUOJ_radar_missile_launchers_1`) as 2 AI F-16s (`retry`, 04:40). They reached the launch point 40 km out at 2,600 ft (04:46), fired nothing and landed at Rovaniemi (04:50). MSN2025_OCA was still waiting on it when the run ended.

**Suspects:** a HARM shot from 40 km at 2,600 ft at a point-defense Tor (12 km reach) may be out of the AI's launch range, and the Tor's radar may not have been on at that distance. The launch distance is set for long-range sites. After the attack waypoint the next one is the landing, so the AI just went home.

**Proposed fix (decide with John):** a launch distance by target (short-range and point-defense targets much closer, e.g. ~25 km, or a DEAD instead of a SEAD for them); and a flight that reaches its launch point and fires nothing within a few minutes is logged (`CONTROL … no shot`).

---

### Bug 30. The bandit call dropped a fighter that had just fired, because the picture didn't hold it

**Status:** fixed 2026-10-02, not flown.

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN5024_SEAD`. At 04:12:35 MSN5024 called `defend` on the F-15C patrol MSN2009_CAP that had just fired at it (24 km); 4 s later "back on way home: MSN2009_CAP lost from the radar picture": Red's picture never held the F-15C, only the shot gave it away. It engaged again only at 9 km, 30 s later (the re-engage hold). The surviving Su-34 still killed the F-15C with an R-77 as it died.

**Fix:** `directives_per_flight.lua` (`self_defence`): a bandit that fired at the flight within `shot_memory_s` (30 s) stays the fight whether the picture holds it or not.

---

### Bug 31. Dumb-bomb strikes dropped one bomb a pass and circled over the target

**Status:** fixed 2026-10-02, not flown.

**Seen:** `event_logs\2026-10-02_145532.log`; grep `MSN7037_STRIKE`, `MSN7033`. MSN7037 (2× Su-34, 8× FAB-500 each, on `TGT_BANA_supply_depot_1`) held its planned 5,000 m and dropped **one** FAB-500 per jet per pass, roughly every 2 min, from ~17,000 ft, coming back over the target again and again (04:36–04:43 and on), with 1 of 4 critical objects destroyed by 04:41. MSN7033 did the same. John: "not a good attack strategy": fly in, drop everything, get out fast, or use different weapons.

**Cause:** a `bomb_critical_objects` attack had one `Bombing` task per critical object (up to 4) with `expend = "Auto"` and no limit on the number of attacks. With unguided bombs, the DCS AI drops one bomb per task per pass and comes back around until they're gone. Every Red strike and airfield-strike loadout uses unguided bombs (Su-34 and Su-24M FAB-500 / RBK, Tu-22M3 FAB). Every Blue one uses JDAMs.

**Fix:** `stages/plan_air_tasking.lua` (`attackOf`, `dropsUnguidedBombs`): a flight whose loadout carries bombs and no guided weapon (by weapon name) gets one aim point, the centre of the critical objects, as carpet bombing already did, with weapon type bombs and `expend = "All"`. `consumers/spawn_aircraft_groups.lua`: a `Bombing` task with `expend = "All"` also sets `attackQtyLimit = true, attackQty = 1`, so the AI makes one attack and then flies on to its egress. Guided-bomb flights (Blue's JDAMs) are unchanged. Re-planning the 14:55 roll gives every Red strike / OCA 1 point, `All`, bombs. Watch for `SHOT … fired 8x FAB_500` in one line per jet, then the egress `WAYPOINT`.

**Bombing from too high (John, 2026-10-02):** "those RED flights were also bombing from too high, they didn't hit anything from 17k feet". The log shows MSN7037 (released at ~16,900–17,060 ft) did hit: 8 statics at once at 04:39:11 and the ammunition depot destroyed at 04:41:33 (1 of 4 critical), but one critical object in ~5 minutes of passes. Not changed yet. **John's direction (2026-10-02, logged only):** different weapons rather than a lower altitude: "we don't want to fly jets low enough to get attacked". So the fix to build is a Red strike loadout with guided or standoff weapons, flown from a safe altitude. **Best candidate: the KAB-500S**, Russia's GPS / GLONASS-guided 500 kg bomb, the JDAM equivalent (`{KAB_500S_LOADOUT}`, "KAB-500S - 500kg GPS Guided Bomb" in `data/aircraft_pylons.lua`): the Su-34 takes it on pylons 3–10 (up to 8, like today's FAB-500 load), and the Su-30 on 6 pylons; the Su-24M and Tu-22M3 can't. No existing loadout carries it, so it would be a hand loadout (`… R-77` like the others: KAB-500S on 3–10, R-77s, ECM pods). It would drop from altitude onto the critical objects' coordinates like Blue's JDAMs (one `Bombing` task per object, so bug 31's one-pass rule wouldn't apply). Untested in DCS: that the AI releases it from a `Bombing` task, and that this pydcs pylon data still matches the current Su-34. The Su-24M (FAB-500 / RBK) would still need a lower altitude or to come off strike. Other candidates from `--list Su-34`: `KAB-500*4` (KAB-500LG laser-guided; whether the AI can aim it without a pod is untested), `Kh-29T*4` / `Kh-29L*4` (TV / laser missiles, ~10 km), `Kh-59M*2` (standoff, inertial). This ties in with the *Standoff attacks* backlog item and bug 4. Test in DCS which of these the AI actually releases and hits with.

**Built 2026-10-02 (John: "try 2 different loadouts, one with the KAB-500S and one with the Kh-59M*2 for strikes. We are doing air denial with standoff weapons, no one should really be overflying targets"), harness only, not flown:**
- Su-34 strike flies one of two loadouts at random per flight: `hand:Strike KAB-500S R-77` (the Strike R-77 pylons with 8 KAB-500S on 3-10, `kola_data_tools/aircraft_loadouts_by_hand.json`) or `dcs:Kh-59M*2,R-73*2,R-77*2,ECM`. `aircraft_loadout_choices.json` takes a list of picks; `aircraft_loadouts.py` writes the first to `AIRCRAFT_LOADOUT` and all of them to `AIRCRAFT_LOADOUT_OPTIONS`; the planner picks per flight (`pickLoadout`) before it routes.
- **No overflying:** `AIR_STANDOFF_WEAPONS` (`data/air_tasking.lua`: Kh-59M `release_km` 40, KAB-500S 8). A strike whose loadout carries one gets its "target" waypoint at the release point that far short of the target, on the way in, and turns home from there (`buildRoute`); the route, and so its SEAD needs, end at the release point. Each jet's weapons are spread over at most as many critical objects as it carries, the same number at each (`expend` One / Two / Four), one attack per object (`attackQtyLimit`).
- Harness (the 16:03 roll, 3 seeds): Kh-59M flights 37-40 km short, 2 objects, One each; KAB-500S flights 8 km short, 2-3 objects, Two / Four each; none of them needed a SEAD flight.
- Unchanged: Su-34 / Su-24M airfield strike (RBK, one pass), Su-24M strike (FAB-500), Tu-22M3 (carpet), Blue's JDAM flights (over the target, as before).
- **Watch:** `LOADOUT` lines (both loadouts seen), `SHOT … X_59M` / `KAB_500S` with range and altitude, `HIT` / `TARGET` on the critical objects, and the flight's `POSITION` after the release point (turning home, not pressing on). The release distances are guesses: from the `Bombing` task the AI flies its own attack from the ingress and may release earlier or later.

**Still open (John):** the attack altitude (Su-34 strike 5,000 m, OCA 3,000 m) and whether Red should carry guided weapons instead (the Su-34 has `KAB-500*4` laser-guided, `Kh-29T/L*4` and `Kh-59M*2` loadouts in `--list Su-34`; whether the AI self-designates the KAB-500L is untested).

---

### Bug 33. SEAD flights from a base near their target climb into the kill zone instead of staying low

**Status:** fixed 2026-10-02, not flown (found in the review of the 14:55 run; John set what should happen the same day).

**What should happen** (John, 2026-10-02): a SEAD flight against a long-range SAM ingresses at **very low altitude** and stays there until it is within firing distance. Then it pops up **on afterburner to ~6,000 ft** (10,000 ft, today's `popup_altitude_m` 3,000 m, is too high), fires the entire salvo and goes cold. So:
- **Base close to the target:** the flight never climbs. Low from takeoff to the pop-up.
- **Target far away:** it climbs for the cruise over, then descends to low level before the rings (as today).

**Seen:** `event_logs\2026-10-02_145532.log`; grep `MSN7023_SEAD`, `MSN7024_SEAD`, `MSN2025_SEAD`. On this roll Vuojärvi (Red) and Rovaniemi (Blue) are ~90 km apart, each under the other's long-range SAM: Vuojärvi 30 km inside the Rovaniemi Patriot's ring, Rovaniemi 52 km inside the Vuojärvi SA-10's. Red's rotation flies 10 of 11 SEAD flights from Vuojärvi; Blue's SA-10 flight flies from Rovaniemi. The planned routes are short (`dcs.log`: MSN7023 36 km flown, MSN7024 43, MSN2025 24).
- **The flights climbed instead of staying low.** The low leg and the pop-up came within the first minutes, so the jets went more or less straight from the climb-out into the pop-up. They reached their launch point waypoint 1–2 min after takeoff at 2,500–5,000 ft: MSN7023 at 3,809 ft (04:08:20, takeoff 04:06), MSN7023_SEAD_AGAIN 4,119 ft, MSN7024 5,042 ft, MSN2025 2,491 ft, MSN2025_SEAD_AGAIN 2,863 ft. The Patriot fired at MSN7023 from 62 km at 3,800 ft, 2 min after takeoff.
- **Then they hung around under the target's full ring trying to get a shot.** At the launch point with `AttackGroup` on and the target out of the AI's reach at that height, the DCS AI manoeuvred in place: MSN7023 turned through 117°, 218°, 109°, 167° at 1,500–5,000 ft for 3 min, then climbed to ~10,400 ft and fired its 8 Kh-31P from 45–61 km (04:10:25–04:11:23); both jets died to the Patriot. MSN7023_SEAD_AGAIN did the same for 6 min and never fired a Kh-31P (it fought the Blue SEAD flight instead; both jets lost). MSN7024 at 5,000 ft never fired at the Rovaniemi SA-11 from 57 km and flew its egress. Blue's MSN2025 / _AGAIN climbed to ~10,600 ft and fired only at 44–54 km (bug 34).
- **No afterburner on the pop-up:** today the afterburner is allowed only on the egress. The climb to 3,000 m took the Su-34s minutes, not seconds.
- **`no shot` fires falsely:** its 2 min counts from coming within `arrival_km` (15) of the launch point, which here is at takeoff. MSN7023 got `no shot` at 04:08:06 and fired at 04:10:25.

**Cause (suspected):** `suppressionRoute` builds cruise → descent → low leg → pop-up → launch point and assumes the base is far enough for all of it. With a close base the waypoints still exist but crowd the climb-out, so the low leg is never really flown. The pop-up altitude (3,000 m) and the climb without afterburner put the jets up high, slowly, inside the target's full reach.

**Proposed fix (decide with John):**
- A SEAD flight whose base is inside the enemy rings, or too close for a cruise, takes off and stays low (275 m RADIO) all the way: no cruise, no descent.
- Pop-up to ~1,800 m (6,000 ft) with afterburner allowed from the pop-up waypoint, `AttackGroup` (expend All) at the launch point, go cold on the last missile (already built).
- **To check before trusting it:** the AI's launch range at 6,000 ft. At 10,000 ft the F-16s only fired at 44–48 km, and MSN7024 at 5,000 ft didn't fire at 57 km at all (the Hornets did fire from 59 km at 3,258 ft during their pop-up). The launch distance (55 km) may have to come in for a 6,000 ft shot, which means closer to the site.
- `no shot` and the 10 min attack timer start from the pop-up waypoint, not from coming within 15 km.

**Fix (built 2026-10-02, harness only):**
- `stages/plan_air_tasking.lua` (`suppressionRoute`): a flight whose low entry comes sooner than a climb to cruise and the descent back (`lowAt < 2 × descentM`, ~77 km of route with an 8,000 m cruise) goes low from takeoff and never climbs: the departure point, the way in and the way home all at `low_altitude_m` (RADIO). A far target still cruises high and descends before the rings (MSN2031 on the 14:55 roll). A base under an enemy ring was already low from takeoff, and still is.
- The pop-up waypoint allows the afterburner (from there through the egress; off again at the climb or the last low point home).
- `data/air_tasking.lua`: `popup_altitude_m` 3,000 → **1,800** (~6,000 ft), `popup_km` 15 → **8** (a short climb on afterburner), `launch_km` 55 → **45** (from 55 km the AI didn't fire: F-16s at ~10,600 ft pressed on and fired at 44–48 km, a Su-34 at 5,000 ft never fired from 57 km). Short-reaching targets keep reach + 15 km when that's less.
- `no shot` and the 10 min attack timer start at the pop-up waypoint (`ControlAirFlights.waypoint`, called by each waypoint's script command next to `WriteEventLog.waypoint`), or within 15 km of the launch point once the flight is at 80 % of the pop-up altitude, not at takeoff.
- Harness: the 14:55 roll re-planned. Every Vuojärvi / Rovaniemi SEAD flight is now takeoff → 900 ft legs → pop-up (afterburner) 8 km before a launch point 45 km out at 1,800 m → back low; SEAD flights per coalition unchanged (Red 11, Blue 9); a 6 h smoke run clean.
- **Watch in the next run:** `SHOT` ranges and altitudes of the salvo (does the AI fire from ~45 km at 6,000 ft, or press on to the 10 km `press_km` limit?); `POSITION` low after takeoff; the time from the `pop-up` `WAYPOINT` to the first `SHOT`; return fire at the pop-up; `no shot` only after the pop-up.

---

### Bug 42. Blue's radar never saw the two Red scrambles that killed the player; Darkstar read "clean"

**Status:** fixed 2026-10-02 (session 18), not flown. Found by John in the 19:29 run.

**Seen:** `event_logs\2026-10-02_192901.log`, grep `MSN7901_SCRAM`, `MSN7903_SCRAM`, `PICTURE_CALL`. John flew MSN2023_SEAD from Ivalo to the Afrikanda SA-6. Red scrambled a Su-27 from Alakurtti (he saw it on his own radar and killed it) and a MiG-31 from Koshka Yavr, which he only saw when it was behind him, cold for home; it killed him with an R-40R from 2 km. Neither ever had a `CONTACT` line in Blue's picture, so Darkstar had nothing to call ("clean" or other groups far away) and nothing could reach his HSD.

**Cause:** where the AWACS orbited. The old rule kept the orbit 200 km from every enemy base; with Kirkenes, Banak, Alta, Kuusamo and Alakurtti Red, the only place that met it was off Bodø, aimed at Banak. The E-3A was 470 km from Alakurtti, 460 from Koshka Yavr and 537–548 from Afrikanda and Monchegorsk; its first detections in our logs come at 120–210 km (session 11). Blue's nearest ground radars were 150–250 km away, mostly short-range, with low flyers under their horizon. Red's A-50, orbiting from Olenya near its own front, held John from takeoff. Not a DCS limit: a real planner wouldn't send a strike 250 km past Ivalo with no AWACS over it. And Darkstar's "clean" read the same wherever Blue had no radar at all.

**Fix (John: "great plan"):**
- **The AWACS is placed where its coalition fights** (`planEarlyWarning`, `plan.md` *Defensive air*): the orbit (own airspace, 150 km from enemy fighter bases, 80 km from the contested airspace, clear of kill zones) that sees the most of the front, the targets in reach and the enemy fighter bases within 250 km, from the nearest base that can fly it; a second one for Blue where its fronts are too far apart. Replay of the 19:29 plan: Blue's E-3A 224 km from Alakurtti and Banak, 296 from Afrikanda.
- **Darkstar says when the player is outside coverage** (`call_air_picture.lua`, `AIR_PICTURE_CALLS.coverage`): "DARKSTAR: no radar coverage your area, picture unknown".
- **`CONTACT` lines say how far away the first sensor saw each contact**, to tune the 250 km.
- The HSD part is bug 26 (test mission built).

---

### Bug 48. The controller stops watching a flight whose only airborne jet is shot down while its wingman is still on the ramp

**Status:** fix built 2026-10-05 with bug 53, not flown (John: "check every airborne jet … for all controller commands and also monitoring"; copied to DCS; harness-checked). A flight counts as landed only when no jet of it is in the air **and** none is still on the ground before its takeoff (`AssessFlightSituations.waitingToTakeOff`, from the scheduler's takeoff record, `ScheduleAirTaskingOrders.tookOff`); a fight whose flight has no jet left in the air ends (`back on mission: no jet of the flight left in the air`), so the next jet up starts clean.

**Seen:** grep `MSN2025_SEAD_AGAIN`. 2× F-16C from Kirkenes on the Kilpyavr SA-10 (the rotation's retry of MSN2025).
- The lead took off at 04:24:22; the wingman only at 04:29:20 (5 min later, the Kirkenes taxi queue again, as in MSN2025 and the 16:50 run).
- 04:26:44 `defend` on the Red strike MSN7030_STRIKE (24 km, hot) while the lead circled low near Kirkenes waiting; the lead was killed by an R-77 at 04:27:36. No `back on mission` line ever followed.
- From then on **no `CONTROL` line for the flight at all**: the wingman flew the whole SEAD alone, fired its 4 HARMs at 04:35:22-04:35:45 (all shot down), and got no `go cold` (it should have come 0.5 s after the last missile, `every anti-radiation missile fired`), no bandit call, no landing or orphan check. It went home only because its route did (egress waypoint 04:37:03).

**Cause (from the code):** `control_air_flights.lua`, `check`: once a flight has been airborne (`w.airborne_once`), a check that finds no jet of it in the air (`s.airborne`, any unit `inAir()`) takes it as landed and drops it from `_watched`. With the lead dead and the wingman still on the ramp, that's true, so the flight was unwatched before the wingman ever took off.

**Proposed fix (decide with John):** "landed" only when a jet of the flight has actually landed (the scheduler's `LAND` record, or `ControlAirFlights.flightDown`), or when no jet is in the air **and** none is left on the ramp that hasn't taken off yet; a flight with a jet still waiting to take off stays watched. Check the `defend` state too: a fight whose own jet is gone should end (`back on mission`) so the next jet starts clean.

---

### Bug 49. A SEAD flight against a Roland can never fire: its radar can't see out to the launch point

**Status:** fix built 2026-10-05, not flown (John chose the first option below; copied to DCS; checked by re-planning the 22:39 roll over six seeds). A threat whose radar sees less far than its reach + `short_range_margin_km` (where the press-on point stops) gets no SEAD flight (`seadGetsAShot`, `stages/plan_air_tasking.lua`): of today's types only the Roland ADS (and the Strela-1 / -10, which aren't threats the routing knows). An attack whose route crosses one gets a **DEAD flight from out of its reach** for it instead (`draftStandoffDestruction`): a DEAD aircraft with a loadout whose weapon reaches the threat's reach + `AIR_DEAD_WEAPONS.reach_margin_km` (the Su-34's Kh-59M from 28–40 km on the replays), `AttackGroup` on the group, routed to the release point like bug 4's DEAD. It goes into the site table in the SEAD flight's place, so the attack waits on it, and the gate retries it (`_AGAIN`) and cancels as for SEAD. `dcs.log`: `DEAD from out of its reach (no SEAD shot at it), first needed by …`; a mission that can't have one fails with `no shot for SEAD, no DEAD from out of its reach: …`. Its success is every unit of the group (the gate's test for a base-defense group). On the replays: seeds 1 and 3 planned it for `DEF_HOSI_radar_missile_launchers_1` (MSN7036 / MSN7034, 2× Su-34, Kh-59M), waited on by a strike and an airfield strike.

**Seen again** in `event_logs\2026-10-04_223922.log`: MSN7038_SEAD and MSN7038_SEAD_AGAIN (2× Su-34 each, Vuojärvi) on Hosio's Roland, `RADAR_WARNING` "not seen" at 24 and 17 km both times, `no shot`, 16 Kh-31P flown home; MSN7037_DEAD (on the Hosio Patriot, already 3 of 10 critical down) waited on it and was cancelled.

**Seen:** grep `MSN7028_SEAD`. 2× Su-34 (8 Kh-31P) from Severomorsk-1 on `DEF_KIRK_radar_missile_launchers_1`, Kirkenes's base-defense Roland ADS (a SEAD flight an attack needs: MSN7027_OCA's Tu-22M3s at 05:34 wait on it). `RADAR_WARNING` at the launch point (04:21:47, 24 km) and the press-on point (04:22:14, 18 km): "its radar not seen"; `go cold: no shot … all 8 anti-radiation missiles aboard`; landed 04:38. Meanwhile `SAM_KIRK_SA8_1` was tracking the flight (`TRACKING` 04:22:10) and its mobile guns were on the warning receivers.

**Cause:** the Roland's radar sees only 12 km (`UNIT_POOL` `detection_m` 12,000; `threat_m` 8,000). The launch point for a short-reaching target is its reach + `launch_past_reach_km` (15), here ~24 km, and the press-on leg stops at reach + 5 km (~13 km). Both lie outside 12 km, so the Roland never detects the flight, never shows on its warning receivers, and the AI has nothing to fire at (*DCS facts*: no ping, no shot). The same will hold for any target whose radar sees less than its reach + 5 km. Tor M2 (32 km) and Pantsir are fine; check the other short-range types' `detection_m`.

**Proposed (decide with John):**
- Don't plan SEAD on a target whose radar can't see the press-on point (detection range < its reach + 5 km); leave it to DEAD from out of its reach (bug 4's Kh-59M / JSOW), and let the waiting attack wait on that DEAD instead.
- Or bring the press-on point inside the radar's detection range for these targets, accepting the exposure (the Roland reaches 8 km; a press-on point at ~11 km stays outside it).

---

### Bug 51. John couldn't find the JSOW in the F-16C rearm screen for a DEAD frag that lists it

**Status:** resolved, no code change: in the 22:39 run the same night (`event_logs\2026-10-04_223922.log`) John flew MSN2024_DEAD with the JSOW and fired 4× AGM-154A from 29,000 ft at the Kuusamo SA-8 (Dog Ear radar and a Ural destroyed, all three launchers hit). Closed by John 2026-10-05. (Found by John 2026-10-04, `event_logs\2026-10-04_220508.log`.) (The first entry here said the player F-16C can't carry the JSOW at all; the game files show it can, below.)

**Seen:** John took the human tasking MSN2027_DEAD (1× F-16C on `SAM_KUUS_SA11_1`, the Kuusamo SA-11) and spawned at Rovaniemi. The frag's `LOADOUT (as planned for an AI jet)` line gave the AI F-16C's DEAD loadout, 2× AGM-154A JSOW (Liberation `DEAD`, `data/aircraft_loadouts.lua`). He found no JSOW in the rearm screen, stations 3 and 7 included.

**What the game files say** (DCS 2.9.29, files of 2026-09-21):
- **The F-16C carries it:** `CoreMods\aircraft\F-16C\F-16C.lua` lists `{AGM-154A}` and `{BRU57_2*AGM-154A}` in the `middle` launcher table that stations 3 and 7 use. No `AddPropAircraft` option restricts weapons.
- **It's filed under missiles, not bombs:** `CoreMods\aircraft\AircraftWeaponPack\glide_bombs.lua` declares the `{AGM-154A}` loadout with `category = CAT_MISSILES`. The rearm window groups each station's list by that category, and with two JSOW entries (single, BRU-57 ×2) they sit in a sub-menu of their own under it.
- **Not the mission:** all 37 airports in the `.miz` have `unlimitedMunitions = true`. No slot payload has a `restricted` list, which is the only per-station filter the in-game rearm window applies (`Scripts\UI\MissionResourcesDialog.lua`, `pass_ME_restricted`). Our scripts never touch warehouses.
- **A weapon the warehouse lacks shows, not hides:** it is listed as `NOT AVAILABLE : <name>`.

**Next:** John looks under station 3 or 7, in the missiles category. If it isn't there either:
- check the Mission Editor's payload page for an F-16C (station 3);
- then the rearm screen at an always-Blue base (Bodø), to rule out `setCoalition` on contested bases.

**Separately (decide with John):** the frag shows the AI's loadout. A player would be helped more by a loadout they can pick quickly and where to find it, or weapon advice instead.

---

### Bug 52. Wingmen leave their hold the moment their lead lands and fly a straight line (bug 19 again)

**Status:** fix built 2026-10-05, not flown (John: "yeah, we should try that"; copied to DCS; harness-checked). The removal after 8 min (bug 19, `closed.md`) stays as the safety net.

**Seen:** `event_logs\2026-10-04_223922.log`, grep `>>orphan<<`. In 9 of 11 two-ships one jet was still up when the other landed, and every one of them was removed after 8 min (`>>orphan<< removed`) or lost. Only MSN2025_SEAD_AGAIN and MSN7024_SEAD landed together. The pattern, MSN2029_SEAD_2 as the example: holding near Kittilä at ~4,300 ft while its lead came in, then from the moment the lead touched down (05:24:25) a fixed heading 246, 301 kt, 4,345 ft, away from the base, until removed at 05:32:34. The `land:` orders (05:27, 05:30) changed nothing. MSN2031_SEAD_2 flew off from Kittilä into the Rovaniemi SA-10 area and a Su-30 killed it at 06:03:32, 8 min 21 s after its lead landed.

**Cause (suspected):** the landing order was a group order (`Controller:setTask` on the group), and with the lead on the ground the group's controller is its landed lead: the jet in the air never got it. The directive also held the order back while a landed jet was on the ramp ("the order would send it up again").

**Fix:**
- As soon as a jet of the flight has landed and another is still up, each jet still up gets a landing order (once per landing): `land: MSN2029_SEAD_1 landed, MSN2029_SEAD_2 still in the air; sent to land at Kittila, each jet in the air on its own order (…)`.
- With any jet of the flight on the ground, `GiveOrders.land` gives the order to each airborne jet on **its own unit controller** (DCS has unit controllers for aircraft), straight to a landing at its base, return fire. With every jet in the air it stays one group order, as before. The old "not while a landed jet is on the ramp" hold is gone (the landed jet gets no order).

**Check in the next run:** `>>orphan<<` lines (how many `possibly orphaned` end `not orphaned: landed` now, against 0 of 9 in this run); the `land: … still in the air` lines; any wingman that takes the order and still flies off.

---

### Bug 53. The controller looked at the lead only: a wingman fought inside a SAM ring and was never broken off

**Status:** fix built 2026-10-05, not flown (John: "this seems to be a re-occurring problem for all CONTROLLER commands and also monitoring"; copied to DCS; harness-checked). Bug 48 is the same kind and was fixed with it.

**Seen:** `event_logs\2026-10-04_223922.log`, grep `MSN2043_STRIKE`. 2× F-16C from Kittilä on the Alta communications site (no `route_threats`, so no ring accepted). The wingman took off ~3 min after the lead. `defend` at 04:27:19 on the Su-27 patrol MSN7016_CAP (95 km, hot). The fight took the wingman up to 27,000 ft and 16 km inside the Ivalo SA-11 #3's ring; two SA-11s fired 4 missiles at it from 37–44 km and killed it at 04:30:00. The lead stayed ~5 km outside the ring at 14,000 ft. No break-off came: the controller's kill-zone test used the situation's position, the lead's. The lead later traded itself for a Su-30 scramble; the target was never attacked.

**Cause:** `AssessFlightSituations.build` takes the first live unit as the lead (even one still on the ramp) and its position is the flight's; the leash, the go cold, the fight's break-off and the bandit call's ranges all measured from it.

**Fix (`consumers/control_air_flights/`):**
- **The lead** is the first jet in the air (a lead still on the ramp, or landed, isn't where the flight is).
- **A new fact, `jets`:** every airborne jet with its position. `AssessFlightSituations.flightKillZone` asks each one and returns the site and the jet; the leash (kill zone, and enemy-airspace depth from the deepest jet), the go cold (other sites; a jet in its shot area with missiles aboard left alone) and the fight's break-off (SEAD: a jet in its shot area left alone) all use it. The line names the jet when more than one is up: `back on mission: breaking off: MSN2043_STRIKE_2 inside the kill zone of SAM_IVAL_SA11_3`.
- **The bandit call:** each enemy group is measured from the closest pair of its jets and ours (range, aspect, closing), and the picture is searched around every jet.
- **The go cold's "pressed past its press-on point":** the jet closest to the site counts. A SEAD flight is "in its shot area" (finishing its salvo first) when any jet is.
- **`RADAR_WARNING`:** the height is the first airborne jet's.
- **Not changed:** going home, the fight itself and the resume are still group orders (only the landing order goes to single jets, bug 52); `POSITION` lines already list every jet.

---

### Bug 54. A site the rotation needs, taken by a non-rotation SEAD flight, got no come-back

**Status:** fix built 2026-10-05, not flown (copied to DCS; harness-checked). Extends bug 46's come-back.

**Seen:** `event_logs\2026-10-04_223922.log`, grep `SAM_ROVA_SA10_1`. The Rovaniemi SA-10's SEAD flight was MSN2025_SEAD, planned for John's DEAD tasking (MSN2024), not a rotation flight. The first try killed nothing (its lead died after the salvo); MSN2025_SEAD_AGAIN destroyed the 64H6E only (the site needs 2 of 3 radars). Bug 46's come-back applies to rotation sites only, so at 05:02:38 the rotation's MSN2028 (on the Rovaniemi SA-11 #2, behind the SA-10) was cancelled "after a second SEAD flight", and MSN2030 with it (05:32:35). MSN2036, MSN2039 and MSN2040 wait on the same site: Blue's whole Rovaniemi branch was gone for the run.

**Fix (`decide_launches.lua`):** the come-back covers every site-table flight whose site a rotation flight needs (`requires_cleared`), not only the rotation's own. Its second try down with the site still in the fight: `come back: SAM_ROVA_SA10_1 still in the fight after MSN2025_SEAD and MSN2025_SEAD_AGAIN: it comes back into the rotation at …`. Then `<id>_LATER`, the same plan flown again, holds the rotation's place while it flies (the rotation's next flight waits for it, and is pulled forward when it is down). Flights waiting on the site wait for it instead of being cancelled. A site only an attack needs still gets no come-back.

---

### Bug 55. "destroyed" for a flight that had landed

**Status:** fixed 2026-10-05, not flown (copied to DCS; harness-checked). Wording only.

**Seen:** `event_logs\2026-10-04_223922.log`: `leash stand down: MSN2017_CAP destroyed` (MSN7934_SCRAM, 05:55:04), though the F-15C had landed at Alakurtti at 05:51:47; `leash home: MSN2025_SEAD destroyed` (MSN7912) for a flight that had landed. The leash, the bandit call's `back on mission` and the scrambles' `stand down before launch` said "destroyed" for any group no longer there.

**Fix:** `AssessFlightSituations.goneText`, from the scheduler's record: `… destroyed` (all lost), `… landed`, `… down (1 lost, 1 landed)`, or `… gone` (a group the scheduler doesn't keep: a player).

---

### Bug 47. Blue's second (southern) E-3A flies its race-track down to the edge of the map

**Status:** fixed 2026-10-05, not flown (John: "the AWACS are often spawning right on the map edge … using half their capacity to scan off the map"; copied to DCS). The airspace grid the orbits are sampled on reaches 150 km past the outermost bases, past the map's edges, and the score (fight seen within 250 km) didn't care how much of the circle was empty. Built (`orbitCandidates`, `rankOrbits`, `stages/plan_air_tasking.lua`):
- **Inside the map:** the whole race-track (centre and both ends) stays `early_warning_map_margin_km` (60) inside the Kola map's edges, `AIRSPACE.map_bounds_m` (from DCS's `Mods\terrains\Kola\MissionGenerator\nodesMap.lua`: x −285,184 … 393,216, z −557,056 … 884,736).
- **Forward:** among the orbits that see at least 90 % of the best one's share (`early_warning_near_best` 0.1), the one nearest the fight it sees (the weighted centre of the points in its coverage) wins, so an orbit far back or at the edge that sees about as much as a forward one loses to it.
- `dcs.log`'s AWACS line now gives "n km from the fight it sees, race-track n km inside the map's edge".
- **Replay of the 22:39 roll** (three seeds): Red's A-50 was planned off Olenya with its race-track **26 km off the map's south edge** (x −303 km); now off Severomorsk-1, 250 km inside the edge, 114 km from the fight it sees (30 % of the fight against 34 % before: what the old orbit saw more lay at the edge). Blue's E-3A (off Evenes, 264 km inside) unchanged.

**Seen:** the southern Blue AWACS's race-track runs down to the very southern edge of the map. It doesn't need to go that far south, and much of its radar coverage is wasted on empty space past the fight. Example, John's test roll of 2026-10-04 14:20 (`Saved Games\DCS\kola_last_plan.lua`): `MSN2002_AEW` on `AEW_EVEN_2`, race-track `{ -288144, -275, -239448, -11621 }` (x north, z east); the first E-3A, `MSN2001_AEW` on `AEW_BODO_1`, orbits far to the north (`{ 121343, -193604, 191788, -155690 }`).

**Cause (suspected, from the design, not checked in code):** the AWACS placement (bug 42, `orbitCandidates` / `earlyWarningPoints` in `stages/plan_air_tasking.lua`) picks the second orbit by how much of the fight the first leaves unseen within `early_warning_coverage_km` (250), from own-airspace candidates at least 150 km from every enemy fighter base and 80 km from the contested airspace, with the legs laid across the line to the nearest enemy fighter base. Nothing keeps the race-track away from the map edge, nothing prefers the end of the track that faces the fight, and the legs' direction can run the track north-south, away from what it should watch.

**Proposed (decide with John):**
- Lay the race-track's legs so the whole track stays on the side facing the fight: the far end no farther from the front than the near end plus a little, or legs parallel to the front.
- Keep the race-track a margin inside the map's edge.
- Score a candidate by the fight it sees from the race-track's far end too, not only its centre, so a track that drifts away loses.

---

### Bug 61. Darkstar's bearings are a few degrees off against the F10 map

**Status:** fixed 2026-10-05, not flown (John: "do the fixes then close the bug"; copied to DCS; checked in a luae harness). Cause: DCS's magnetic is grid-based (the test flight below). Built: the bearing said = grid bearing − the variation at the player; the contacts' tracks and the airfield brief's wind and runway numbers the same way; the age said from when a radar read the position (`pos_seen_at`), not the round's end; stale tracks (unseen for `RADAR_PICTURE.stale_after_s`, 60 s) are no longer called, on screen or on the radio (John: no reason to give 5 min old contacts). The bearing check line and the DEBUG blocks are removed. John asked whether it changes per map: no setting needed, the grid bearing comes from the map's own x / z, and the convergence that was the error is simply larger the farther a map reaches from its central meridian.

**Seen** (2026-10-05 afternoon run, John on the ramp, Ivalo area; screenshots on John's desktop `a1.png`, `a2.png`): "Snake one one, Darkstar, updated picture, one group. Zero three five for one four zero, thirty thousand, beaming southeast, hostile" (the Red A-50). Altitude, heading and speed matched. The F10 ruler at 035° M / 140 nm ended ~15 nm southeast of the A-50; the A-50 measured ~030° M. The ruler showed `018°M / 035°T` and `035°M / 053°T`: 17–18° between its true and magnetic, against DCS's magvar module's +12.4° at Rovaniemi (~+14° near Ivalo) that Darkstar uses.

**Not it:** delay (a contact's position is read off the aircraft when a radar sees it; the picture's round is 30 s, ~3 nm for an A-50, ~1° at 140 nm). Earlier the same day the whole ~14° was the F10 ruler being read as true; this is what's left with its magnetic reading.

**Suspects (not proven):**
1. **Variation:** DCS's magvar module (mission date, at the player's position) disagrees with what the F10 ruler (and maybe the F-16) uses. Ours is what the mission editor and DTC use (`call_air_picture.lua`, `loadMagvar`), but the F10 ruler's 17–18° doesn't fit it.
2. **True vs grid:** the Kola map's grid north is 6–9° off true north there (transverse Mercator, central meridian 21° E). We compute true from lat / lon; the F10 ruler's "T" may be grid. A slip between the two would show as a few degrees.
3. **Our maths** (less likely; the A-50 check earlier the same day matched true to the degree).

**15:33 run** (`event_logs\2026-10-05_153340.log`, John from Ivalo; `dcs.log` lost to a DCS restart, so no check lines; the calls' numbers are in `radio_calls/mission_calls.jsonl`). John: a low jet called at 313, his HSD cursor put it at 342; other calls 5–10° off. Found:
- **The positions called are up to ~30 s old, and the call says 0 s** (`track_radar_picture.lua`, `poll` / `finishRound`): a contact keeps the point and velocity of the *first* sensor that saw it in the round (the round spreads 10 steps over ~27 s), and `last_seen` is set to the round's end, so `age_s` reads 0. Calls run on the round. Checked against the shots: at 04:38:04 Darkstar called the Su-27 MSN7902_SCRAM at 26 nm (48 km); 7 s later John's AIM-120 went at it from 36 km, and with ~1,200 kt closing it should have been ~40 km at the call. ~8 km too far is ~25 s of the Su-27's own flight (595 kt). Seen from the side, the same delay moves the bearing: ~2 nm at 26 nm is ~4°, more when closer or when crossing faster.
- **313 vs 342 is most likely two different moments, not the maths:** the low "313 / 85 nm, 2k, hot" (04:32) was the Su-34 pair MSN7023_SEAD_AGAIN; "313 / 90 nm, 18k, hot" (04:34) was the Su-27 MSN7902 climbing out of Banak (2,750 ft at 04:33). Its bearing then swung with both jets closing: 321 (04:36), 336 (04:37:34 threat call), 344 (04:38). So the HSD's 342 fits the 04:38 moment.
- The remaining few degrees: the staleness above, plus the variation question (suspect 1).

**Proposed fix (decide with John):** keep the newest sighting in a round (point, velocity and its time), not the first; set `last_seen` to that time so the age said is true; and at the call, move each tracked contact forward along its velocity to the call's moment (a real AWACS's track does the same). Write the bearing check line to the event log too, so a DCS restart can't lose it.

**DEBUG lines built 2026-10-05, TEMPORARY (John: tag them DEBUG, remove later; copied to DCS, not flown):** `AIR_PICTURE_CALLS.debug_call_positions`. At every Darkstar call, picture and threat (`CallAirPicture.debugCall`), the event log gets a block numbered `call <n>`: the call (kind, groups said); the player (F-16-style and decimal lat / lon, x / z, altitude, heading magnetic / true / grid, speed, the variation used, the grid's convergence there); each group said (what was said, the picture's position for it and how long before the call that position was read: `pos_seen_at`, new in `track_radar_picture.lua`); and every airborne enemy airplane's true position and heading at that moment with its bearing and range from the player now (`said n`, `in the picture, not said` or `not in the picture`). Grep `DEBUG` or `call 12:`. To remove: the flag, `debugCall` in `call_air_picture.lua`, its two callers (`callAll`, `send_radio_calls.lua` `threatRound`), `pos_seen_at`.

**The test flight (agreed with John, 2026-10-05):** John flies ~15 min straight and level on one round heading (autopilot heading hold is fine), away from Red's rings and fighters, and tells Claude the HUD heading he held. Every picture call (~7, one per 2 min) and any threat call logs a DEBUG block. Then, from that run's event log alone:
- **Timing:** each `said n` line against the same jet's `true now` line in the same call (and the "read n s before the call" age).
- **Variation:** the HUD heading against the true heading in the `player` lines gives the F-16's own variation; compare with Darkstar's (DCS's magvar module, called as the mission editor does: `init(Month, Year)`, lat / lon in degrees; checked 2026-10-05; about +13–14° near Ivalo). Suspect: the F-16 uses ~4° more (the F10 ruler showed 17–18°), which would be the steady ~5°.
- **Maths:** the bearing recomputed offline from the logged positions.
Then patch what's real: fresh sightings and tracks moved forward to the call (above), and / or the variation.

**The test flight, flown 2026-10-05** (`event_logs\2026-10-05_185934.log`, John from Kallax, HUD heading 050 from takeoff to ~04:35, out past Kuusamo; 21 calls, 72 groups; checked offline with `bug61.py` in that session's scratchpad). **Cause found: DCS's magnetic is grid-based.**
- **Maths and timing are fine:** every bearing said is within 1° of the jet's true position at the call (rounding), ranges within ~0.8 nm; an offline great-circle bearing from the logged lat / lon matches the logged true bearing to 0.1°. Most positions are read 6 s before the call; a few 27 s (2.5–4 nm off, 1°).
- **The variation:** with the HUD steady on 050, our "magnetic" heading for John's jet drifted 051 → 057 as he flew east (our true heading 061 → 070). **Grid heading minus our variation stays 049–051 the whole leg** (grid 060 → 064, variation +10.3 → +13.5). So the F-16 (and the F10 ruler's M) shows magnetic = grid − variation: it treats the map's grid north as true north and ignores the grid's convergence. DCS's magvar figure itself matches the jet.
- **So Darkstar is off by the convergence:** ~1° at Kallax, ~6° near Kuusamo / Ivalo, ~9° toward Murmansk, always in the same direction (Darkstar's numbers too high east of 21° E). That fits the steady ~5° near Ivalo and the 5–10° of the 15:33 run.
- **Smaller, also seen:** the age said is the read age minus ~27 s (said 0 s for a 27 s position, 150 s for 177 s). A contact that is gone is still called while its track goes stale, up to ~5 min: MSN7016_CAP's Su-33 after it was shot down (04:15:36), MSN7023_SEAD's Su-34s after they landed at Alakurtti (04:25, 04:31).

**Proposed fix (decide with John):** the bearing said = grid bearing − variation at the player (and the same for the contacts' tracks, and for the airfield brief's wind and runway in use, which use the same variation); `age_s` from the time the position was read. The newest-sighting / move-forward fix above isn't needed for the bearing error.

**To fix (when picked up):** one run with the check line on. Note a call's time and group, put the HSD or radar cursor on that contact and read the bearing from the jet (the F-16's instruments are the reference Darkstar must match), and take an F10 ruler screenshot at the same moment. Then recompute the call from the logged positions offline (`kola_data_tools/kola_proj.py`) and compare all three.

### Bug 69. The F-16's COMM 1 / COMM 2 volume knobs did nothing

**For:** framework (found in Kola).

**Closed 2026-10-07** (John, after the Caucasus flight of 2026-10-06 22:43: the COMM 1 / COMM 2 volume knobs work; a change applies from the next call, not to a call already playing). **Status before closing:** open; logging built 2026-10-06 to find out why (the code reads the same knobs as SRS, arguments 430 / 431, and the player applies them: both checked offline, the export script in luae with a stubbed cockpit, the player with UDP readings).

**Seen:** John, 00:16 run: turning the COMM 1 / COMM 2 knobs didn't change the calls' volume. `dcs.log` shows our export script loaded (`KOLA-RADIOS … sending the jet's radios`), but nothing recorded whether a reading ever reached the radio player: it printed to its window only. With no fresh reading it plays every call at full volume, which would look exactly like this.

**Built:** the radio player writes everything it says to `radio_calls\radio_player.log` (rewritten at each start, git-ignored): the jet's radios as first heard and at every change (volume in 0.05 steps), "no word from the jet's radios … every call plays at full volume" when the readings stop, and each call heard (on which radio, at what volume), not heard (why) or dropped. The export script writes `KOLA-RADIOS … first reading of the jet's radios: {…}` to `dcs.log` once, and the first failure to read or send.

**Check after the next flight:** `dcs.log` for `first reading`; `radio_player.log` for `hearing the jet's radios`, the volume lines as the knobs turn, and `at volume` on each call.

**2026-10-06 17:47 run** (`event_logs\2026-10-06_174721.log`): the readings arrive: `dcs.log` `first reading of the jet's radios` (UHF 305.000 and VHF 127.000, both off, the cold jet), and `radio_player.log` logs each change, John's retuning to 262.000 / 140.000, and the UHF volume going down 1.00 → 0.00 in 0.05 steps and back up (bug 72). Every call heard was played `at volume 1.00`, so whether a call at a lower knob setting sounds quieter wasn't heard.
