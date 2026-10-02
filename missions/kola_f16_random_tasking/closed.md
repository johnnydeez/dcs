# Kola F-16 Random Tasking — Closed issues

Roadmap items and fixed bugs that are done, moved here from `roadmap.md` and `bugs.md` so those files only hold open work. Each keeps its original number and text, as it stood when it was closed, with the discussion that led to it. What was actually built, and how it behaves, is in `plan.md` (*As built*).

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

**Status: done (2026-09-30).** Built and run in DCS twice the same day (the second flown by John), then in every run since; its small fixes are bug 5 in `bugs.md`. As built, and how to watch it: `plan.md`, *Event log*.

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

### Bug 5. Event log: small fixes

**Status:** fixed 2026-10-01 except (g), not run in DCS yet. (a) the launcher is kept per weapon at `SHOT` (and `Weapon:getLauncher()` as a fallback); (b) "fired SA5B55 at an incoming AGM_88"; (c) "caught in the explosion of SAM_LUOS_SA8_1_1 (Dog Ear radar)"; (d) `statusOf` reads "stood down on the ramp"; (e) the parachute line names the aircraft the pilot left, when the ejection event names the pilot; (f) `ABORTED` folded per flight within 10 s, "(2x)"; (h) "damaged by a nearby explosion"; (i) "fuel 183 % (with external tanks)"; (j) the ring column skips SAM sites with no live unit (checked at most every 30 s); (k) a player's `TAKEOFF` adds "flying MSN2023_OCA?" when one human tasking starts at that base. (g) still waits for a run with jets low over a defended base.

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

### Bug 20. The SEAD go-cold timer counts from the planned time, so a late flight is sent home before it attacks

**Status:** fixed 2026-10-01 with roadmap item 10, not flown yet (found 2026-10-01). Late takeoffs are DCS AI taxiing and aren't a bug (John: a flight 6 min late or early is fine; the goal is that every mission gets flown and things go smoothly). This one is a bug because the lateness makes the mission fail.

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN5026_SEAD`. Six Su-34s of three SEAD flights spawned at Vuojärvi at 06:02 with the same planned takeoff (06:12); they left between 06:06 and 06:30. MSN5026's lead took off at 06:24 and its wingman at 06:30. At 06:31:34 the go-cold rule sent it home, "still on the attack 10 min after its time at the launch point", while it was at its departure waypoint (06:30:12), nowhere near the site. It never attacked; the Kuusamo IRIS-T it was meant for stayed untouched.

**Cause:** `attack_time_s` (10 min) in the `suppression` rule is measured from the flight's *planned* time at the launch point.

**Proposed fix:** start the clock when the flight reaches its launch point (its `target` waypoint), or from the planned time shifted by how late the flight took off. Optional, with it: some limited planning for taxi time, e.g. stagger flights spawning at the same field by a few minutes per 2-ship.

**Fix:** the clock starts when the flight comes within `AIR_CONTROL.suppression.arrival_km` (15) of its launch point, however late it took off (`directives_per_flight.lua`, `suppression`); the line now reads "still on the attack 10 min after it reached its launch point". No taxi-time planning added.

---

### Bug 24. The player appears under two names in the event log

**Status:** fixed 2026-10-02 by John in the Mission Editor (found 2026-10-01, 22:23 run).

**Seen:** `event_logs\2026-10-01_222355.log`: `PLAYER_IN`, `TAKEOFF`, `SHOT`, `POSITION`, `HIT`, `DESTROYED` say `f16_kallax-1-5` (the unit, spawned at Rovaniemi), while the radar picture's `CONTACT`, `TRACKING` and `CONTROL` lines say `f16_rovaniemi` (the group). Grepping one name misses half the player's story.

**Cause (found 2026-10-02, in the `.miz`):** the slot templates were copied from Kallax, so their units kept Kallax names: group `f16_rovaniemi` holds unit `f16_kallax-1-5`, `f16_kiruna` holds `f16_kallax-1-1`, `f16_banak` `f16_kallax-1-3`, `f16_tromso` `f16_kallax-1-4` (only `f16_rovaniemi-1-1` in `f16_kemi_tornio` is different, and also wrong). Unit events log the unit name, the radar picture the group name.

**Proposed fix:** rename each template's unit in the Mission Editor to match its group (`f16_rovaniemi-1-1`, …), then re-run `kola_data_tools/miz_player_slots.py`. Optionally also log the group name on player lines.

**Fix:** John renamed each slot template's unit to match its group (2026-10-02). `miz_player_slots.py` needed no re-run: `data/player_slots.lua` keeps group names only.

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
