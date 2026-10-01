# Kola F-16 Random Tasking — Roadmap

What's coming after session 10 (2026-09-30), when the mission became playable by humans. Each item says what it's for, what already exists, a proposed approach and the questions to settle before building. Details are decided with John as each item comes up, step by step, like the rest of the project.

`plan.md` stays the spec and the build log; this file is the list of where the mission is headed. When an item is built, its "as built" notes go into `plan.md`, and it gets marked done here.

Players fly Blue (the F-16C slots), so "own" below means Blue and "enemy" means Red unless it says otherwise.

**Order (John, 2026-09-30):** radar functions → scrambles → event log (built) → **performance in VR (top priority, added after John's first VR run; unnumbered so the item numbers cited elsewhere stay valid)** → AI behaviour logic → AWACS calls (text) → cruise missiles → AI radio calls (LLM / cloud) → Skynet IADS → fog of war. CAP visibility (making patrol routes and times easy to see) was cut on 2026-09-30: John can see the dotted station lines on the map fine for now. Fog of war is last on purpose: John is actively working on and debugging the mission and needs the full map. Four optional extras sit at the end, with no place in the order yet: radar jamming, helicopters, fun callsigns, and the threat picture on the map for players (after fog of war).

---

## 1. Radar functions: one shared radar picture

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

## 2. Fighter scrambles against enemy incursions

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

## 3. Event log: a readable file to watch during the mission

**Status: built (2026-09-30), not run in DCS yet.** As built, and how to watch it: `plan.md`, *Event log*.

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

## Top priority: performance in VR

**Status: first pass built (2026-10-01), not run in DCS yet.** John's test: the same `.miz` with no units still stuttered; lowering forest detail, scenery detail and LOD a little got Kola back to 45 fps, even low. So the mission's own load is what's left, and the first pass is lean (John): step 2 levers 1–3 (no security infantry; one towed-gun group and one MANPADS team per base; short-reach base defenses asleep until an enemy aircraft is within 30 km) and a lower cap (12 per coalition, 2 of it kept for scrambles, which no longer go over it). The "Mark bad frame rate" entry is out (John: stutters are too short to mark while flying). As built: `plan.md`, *Sleeping ground units*, *Stage 2* and *Airborne cap*. Next: John flies it in VR.

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

## 4. AI behaviour logic: conditional orders to flights in the air

**Goal:** fewer, more meaningful losses (air denial), by having the script give AI flights conditional orders while they fly, instead of only a plan at spawn. John (2026-09-30): "the only way we will reduce losses is to start using our AI logic to begin giving conditional in-game commands to flights." It won't be perfect, because the DCS AI is built to fight; the aim is the best scenario we can make.

**Why now:** the first scramble run (2026-09-30) lost 12 aircraft in 48 minutes (Blue 4, Red 8). Both Blue packages were caught by Red fighters and both Red packages were destroyed, mostly by aircraft that kept flying their route while being engaged.

**Where it stands:**
- `consumers/enforce_air_behaviour_rules.lua` exists, with one rule (the scramble leash). Every radar-picture round (30 s) it checks each watched flight and can send it home (`Controller:setTask`) or change its options (`setOption`).
- Each coalition's radar picture (item 1) says which enemy aircraft its radars see, where they are, and where they're heading.
- The rules collected so far (from the `plan.md` backlog, "AI behaviour rules, one place"): patrols leashed to own and contested airspace; strikes go home if their SEAD fails; no second wave into what killed the first (doctrine idea).

### 4a. The logic layer: conditional orders

**Approach (to design with John):**
- Every AI flight is watched, not only scrambles, each with the rules for its mission type.
- **The orders DCS offers a script:**
  - `Controller:setTask`: a new mission, e.g. go home;
  - `pushTask` / `popTask`: a task on top of the current one, then back to the mission (for "deal with this, then get back on task");
  - `setOption`: rules of engagement, reaction to threat, radar use, afterburner.
- Each rule is a check (from the radar picture, the flight's position, its package) plus an order, in one module, as the leash is.

### 4b. Attack flights defend themselves, then get back on task

**Goal:** strike, SEAD and DEAD flights that see a fighter coming for them fight back early, with the air-to-air missiles they carry, then carry on to the target. Today (John): "if a CAP goes after them they just keep flying to their target and wait to get shot at. They have AMRAAMs, so should self protect much earlier and then get back on task."

**Where it stands:**
- Attack flights fly `open_fire` with a single attack task, so they only react once fired upon (reaction to threat: evade fire).
- Many attack loadouts already carry air-to-air missiles. In the first run the DEAD F-16s had AIM-120C ×2 + AIM-9X ×2, and the Su-34s had R-73 ×2 + R-27R ×2.

**Approach (proposed):**
- **Trigger:** an enemy fighter in the coalition's radar picture that is closing on the flight within some range; or DCS's own detection by the flight (`getDetectedTargets` on the flight itself).
- **Order:** push an `EngageGroup` on that fighter (or open fire on air targets within a range) on top of the mission. When the fighter is dead, gone or turned away, pop it, so the flight resumes its route and attack.
- **Limits:** only flights whose loadout carries air-to-air missiles; don't chase past the leash; decide whether a flight that fought and lost its attack time still presses on or goes home.

### 4c. Found in the first event-log run (2026-09-30)

John asked for these to go into this item. The run's log is `event_logs\2026-09-30_201105.log`; grep `MSN2025_SEAD` and `MSN2026_SEAD` for issues 1–3. Bugs from the same run that aren't AI-logic work are in `bugs_and_fixes.md`.

**What happened:** PKG2023 was a human strike on `TGT_KOSH_communications_site_1`, escorted by three AI SEAD flights of 2× F-16C from Rovaniemi:
- MSN2024 → `SAM_KOSH_SA11_2`;
- MSN2025 → `SAM_MURM_SA10_1` + escort;
- MSN2026 → `SAM_KOSH_SA11_1`.

MSN2025 lost both jets:
- **`_1`:** a MiG-31 patrol (MSN5009_CAP_1) fired R-33s at it from 48 km, then from 22 km, while it flew its route. It dived to 1,400 ft and was killed (08:35:46). It never used its AIM-120C ×2 and AIM-9X ×2.
- **`_2`:**
  - at waypoint 7 (descent, 08:34:16) its `EngageGroup` on the SA-10 came on, 136 km from the site;
  - the AI left the route (which never comes closer than 105 km to the SA-10), went to afterburner at 580–690 kt and flew ~30 km into the SA-10's ring;
  - it fired both HARMs at the SA-10's search radars from 92–95 km;
  - on the way it crossed `SAM_KOSH_SA11_1`'s ring, and that SA-11 shot it down (08:37:05, 27,800 ft, pilot ejected).
- **MSN2026:** the flight assigned to that SA-11 was still ~2 min behind (TOT 08:41 against 08:39) and hadn't reached its own attack point.

**Three issues, for the rules in this item:**
1. **A SEAD / DEAD flight leaves its route once its attack task is live.** `EngageGroup` / `AttackGroup` let the DCS AI fly its own attack geometry, so the planned route's ring clearances don't hold. Needs a leash like the scrambles': don't go past a fraction of the target's ring, or into another enemy kill zone, to get a shot. Or an order that fires the HARMs from where the flight is, at longer range (research: can the AI be made to launch at max range, e.g. with an attack-range option, or a `FireAtPoint`-style task?).
2. **Suppression flights aren't sequenced by where their threat sits along the route.** Each is timed only by `suppression_lead_s` before the strike's TOT, so a flight going for a deeper site (the SA-10) can arrive before the flight suppressing a site on the way in (the SA-11). Fix in planning (earlier TOT for threats the route meets first), or with a rule (hold short until the nearer threat is suppressed or dead).
3. **Attack flights don't defend themselves** (4b): another case, with the air-to-air missiles aboard. Consider also going home or turning defensive when the picture shows an enemy fighter closing.

**More from the full review of the same run** (grep the flight names):
4. **The worst case of issue 1: MSN2028_SEAD,** 2× F/A-18C from Kemi Tornio escorting MSN2027_DEAD (a human DEAD on `SAM_KUUS_SA11_1`).
   - Its first ring comes soon after takeoff, so its `EngageGroup` tasks sat on waypoint 2 (departure), 145 km from the site.
   - From there the AI flew its own attack for the whole mission: 1,600–3,700 ft, never climbing to the planned 7,500 m, and pressed ~20 km inside the SA-11's ring.
   - It fired its 4 HARMs from 46–61 km, killing one launcher and damaging the radar.
   - Both jets were shot down by the SA-11 (08:22).
   - Whatever holds a flight to its route and altitude has to work from the moment the attack task is live, even when that's right after takeoff.
5. **Self-defence happens, but late** (data for 4b):
   - MSN2024_SEAD_2 fired an AIM-120C at the MiG-31 attacking it only at 7 km, a moment before being killed. The missile killed the MiG-31 anyway.
   - MSN2024_SEAD_1 killed the Su-27 patrol MSN5016 with an AIM-120C from 25 km, after being fired at, and died to that Su-27's R-27 in the exchange.
   - So the AI does shoot back once attacked; the rule should make it engage first, at the range the radar picture gives.
6. **Flights still go after targets that are already destroyed.**
   - `SAM_KOSH_SA11_2`'s radar (its one critical object) was destroyed at 08:38 (the event log's `TARGET` line, `MSN2035_DEAD … 1 of 1 critical`).
   - MSN2035_DEAD (TOT 12:52) and its two SEAD flights, MSN2036 and MSN2037, were still planned against it.
   - A rule for this layer: before a flight spawns (and while it flies), if its target already meets its success fraction, cancel it or send it home (or re-target it; decide with John).
   - The same goes for a SEAD flight whose threat is already dead.
7. **Related, already in the `plan.md` backlog** ("Unflown taskings' AI flights"): MSN2028 flew and died escorting a human tasking nobody took. Once the logic layer can cancel flights, cancel a human package's AI flights when no player takes the tasking.

**From the second event-log run, John flying** (`event_logs\2026-09-30_213757.log`, 65 min; losses Blue 5, Red 11). Bugs from it that aren't AI-logic work are in `bugs_and_fixes.md` (6–8, and the additions to 1–3 and 5).

8. **Issue 1 again, then a SEAD flight flying on with nothing left** (grep `MSN2026_SEAD`):
   - MSN2026 (2× F-16C from Rovaniemi) escorted MSN2025_STRIKE, the human tasking John didn't take (issue 7 again: 2 jets lost for a tasking nobody flew).
   - Its first threat, `SAM_SODA_SA11_1`, was near Rovaniemi, so its attack tasks went live at departure. It fired **all 4 HARMs** at that one SA-11 (11:01–11:03, 31–51 km), though the plan gave it 2 per threat and a second threat, `SAM_IVAL_SA11_1`.
   - It then flew its route into the Ivalo SA-11's ring with no HARMs left. Both jets were shot down there (11:10, 11:11, 16–23 km inside the ring).
   - **A new rule for this layer:** a suppression flight with no anti-radiation missiles left goes home (and an attack flight with no air-to-ground weapons left, after its attack). Research: can the AI be held to a number of missiles per group (`EngageGroup` with `weaponType` and an expend quantity per task)?
9. **The leash is too slow to save a jet already inside a kill zone** (grep `MSN2903_SCRAM`): its AIM-120s killed a Su-34 at 11:18:51, but the chase took it into the Sodankylä SA-11's kill zone. The leash fired at 11:19:34, the SA-11 launched at 11:19:42, and the jet died at 11:20:21. With a check every 30 s (one picture round), a jet moving at ~500 kt covers ~8 km between checks. Options: check watched flights more often than the picture (every 5–10 s, from their own position, which needs no radar); send home at a line short of the kill zone (e.g. the full ring instead of 85 %); or both.
10. **Suppression isn't timed to a late human flight** (grep `MSN2024_SEAD`, `Aerial-1-2`): John took off 10 min late and bombed at 11:40, 13 min after his TOT of 11:27. His SEAD, MSN2024, reached the target at 11:18, 5 min early against its own TOT of 11:23. It HARMed the Vuojärvi Tunguska and the Sodankylä SA-11 and lost one jet to the Vuojärvi SA-8. The SA-8 isn't on its suppression list, because short-range SAMs aren't planned threats. It worked out, because the SA-11 was dead by the time John arrived. Options: hold a human package's AI flights until the player takes off (goes with assignment tracking), or re-time them at the player's takeoff.
11. **Patrols kill packages, then die in the merge** (grep `MSN2016_CAP`, `MSN2002_CAP`):
    - The F-16 patrol MSN2016 killed four Su-34s of PKG5027 with AIM-120s. It then followed the last one down to 8,500 ft and died to its R-73 at 2 km.
    - The F-15C patrol MSN2002 killed four of PKG5023's jets, including a Su-24M from 5 km at 1,571 ft.
    - Blue's patrols are doing what they should. The merge at the end is where they die. A patrol leash rule could cover it: break off below an altitude, or when out of long-range missiles.
12. **Red's attacks on Rovaniemi fly into a full SAM umbrella:** PKG5023 (8 jets) was planned 44–90 km inside the Rovaniemi SA-10's ring, which is also covered by IRIS-T, NASAMS and a Tunguska. All 8 jets were lost; their Kh-31Ps killed the NASAMS radar and the IRIS-T search radar. With the suppression flight unarmed (`bugs_and_fixes.md` 6), the package had no chance. This is also a planning question: should a target deep under a long-range SAM be picked at all, and should a package go when one of its suppression flights is missing?

**Open (4a, 4b and 4c):**
- Which rules first, and in what order: attack-flight self-defence, strikes going home when their SEAD fails, the patrol leash?
- How far a self-defending flight may turn off its route, and for how long?
- Should a package's SEAD flight protect the strike flight, or only itself?

---

## 5. AWACS calls to the player (text)

**Goal:** the AWACS tells the player what it sees: enemy aircraft with bearing, distance, altitude and type, like a real controller's picture calls.

**Decided:** text messages to the player's group (`outTextForGroup`) for now. Long-term goal (John): AWACS calls become LLM / cloud audio like the AI pilots' calls (item 7), and the text version is the step before that. Build the calls so the delivery can be swapped: the facts (who, BRAA, type) are worked out in one place, and text is only one way of sending them.

**Where it stands:**
- One AWACS per coalition flies (session 8).
- Nothing reports to players. The brief still lacks AWACS frequency and callsign (`plan.md` backlog, playability follow-ups), and bullseye is 0,0.

**Approach (proposed):**
- **Source:** reads the radar picture (item 1). Only contacts own radars see; no calls once the AWACS is shot down, or say "picture degraded" and use ground radars only.
- **Picture on request:** comms menu `AWACS > Picture`, the nearest N contacts to the player.
- **Threat warning:** automatic, when a contact comes within N km of the player or points at them.
- **Format:** bearing / range / altitude / aspect from the player (BRAA), or from bullseye; plus type when the radar picture has it identified, else "unknown". For example: `DARKSTAR: group BRAA 045/32, 25 thousand, hot, Su-30`.
- AWACS callsign and frequency in the brief at the same time.

**Open:**
- BRAA from the player, or bullseye (which needs a real bullseye first)?
- Automatic threat warnings, or only on request?
- How often may it call unprompted, so it doesn't flood the screen?

---

## 6. Cruise missile attacks (ideally from the ground, else from the air)

**Goal:** long-range missile strikes on high-value targets, part of the Ukraine-war feel: missiles for deep strikes instead of risking airframes (a session 8 doctrine idea).

**Where it stands:**
- Nothing built.
- Overlaps "Standoff attacks" in the `plan.md` backlog (which standoff weapons the DCS AI actually releases at range).
- What the unit pool has (`data/unit_pool.lua`):
  - **Ground, Red:** `CHAP_9K720_HE` / `CHAP_9K720_Cluster`, Iskander (Currenthill). That's the ballistic Iskander-M, not the Iskander-K cruise missile; DCS has no ground-launched land-attack cruise missile.
  - **Ground, Blue:** `CHAP_M142_ATACMS_M48` / `_M39A1`, HIMARS ATACMS, also ballistic.
  - **Sea:** `TICONDEROG` (CG Ticonderoga) fires Tomahawks in DCS. It's a real cruise missile, and the Kola map has the sea for it.
  - **Air:** `B-52H` (AGM-86C), `Tu-95MS` / `Tu-160` (Kh-55 / Kh-65 / Kh-101 class). Whether the AI releases them at range, and which loadouts carry them, is the item-2 research.

**Approach (proposed):**
- **Research first, in DCS:**
  - Does a launcher fire at a map point (`FireAtPoint`) and hit it at range?
  - How often does a SAM intercept the missile?
  - Does the flight path matter (a cruise missile's low flight is the point)?
- **Then plan it like the other missions:** a launcher placed or stationed in the rear, targets picked from the target catalog (airfields, SAM sites, depots), launch times spread through the mission.
- **For the player:** an intel line or AWACS call ("cruise missile launch detected, heading W"), and air defences getting a chance to shoot them down.

**Open:**
- Is a ballistic missile (Iskander, ATACMS) acceptable for "from the ground", with ship-launched Tomahawk as Blue's cruise missile?
- Both coalitions, or Red only at first?
- Can players intercept them (a target for the F-16), or are they background only?

---

## 7. AI radio calls: flights announce their intentions (LLM / cloud)

**Goal:** AI flights say what they're doing, so the air war can be followed by ear: "Viper 2-1, airborne Rovaniemi, heading for the station", "Hornet 1-1, SEAD, pushing", "Eagle 3-1, bingo, RTB". The words come from an LLM, so calls sound natural and varied instead of canned.

**Long-term goal (John, 2026-09-30):** the AWACS and all AI pilots use LLM / cloud for **audio callouts only**, with no on-screen text once this works. **It's a goal with an unknown:** what's possible and what it costs hasn't been worked out yet. So this item starts with a feasibility and cost study, and nothing gets built until that's done.

**Feasibility and cost study (first step):**
- **Moving parts to price and test separately:**
  - **Phrasing:** an LLM turns each event into a radio call.
  - **Voice:** text-to-speech, cloud or local.
  - **Transmission:** SRS plays it on the right frequency.
- **Volume:** measure how many calls a real session would make. Count the scheduler's state changes and the AWACS calls from one logged mission, e.g. N calls × ~100 characters each. Every cost follows from that number.
- **Rough scale, to be checked with current prices:**
  - Phrasing a short call is a few hundred tokens. With a small, fast model that's likely cents per session, not dollars.
  - Cloud text-to-speech is priced per character. A few hundred short calls is tens of thousands of characters per session, likely well under a dollar.
  - A local voice (Windows speech, or a local neural voice) costs nothing but sounds flatter.
  - These are orders of magnitude only; the study replaces them with real numbers.
- **What to test:**
  - Latency: an LLM plus TTS round trip must be a couple of seconds at most, or "pushing" arrives after the push.
  - Does SRS's external audio tool (`DCS-SR-ExternalAudio.exe`) take the cloud voice we'd pick?
  - How the helper runs next to the DCS server.
  - What happens when the network drops.
- **Fallback to compare against:** fixed phrase templates plus the same text-to-speech, with no LLM. It's cheaper and predictable but repetitive; the study shows whether the LLM's variety is worth its cost and latency.

**Where it stands:**
- Nothing built.
- `consumers/schedule_air_tasking_orders.lua` already knows each flight's state changes (planned / airborne / landed / lost); the loss log line says who killed it and where.
- AI flights have no player-facing callsigns yet (`plan.md`, Design: callsign policy).

**Approach (proposed), in three parts:**
- **In the mission (Lua):**
  - Callsigns for every AI flight (the callsign policy in `plan.md`).
  - On each state change the scheduler sees (takeoff, on station, pushing, weapons away, RTB, lost), write a small structured event: flight, callsign, type, mission, state, position, and the bullseye / BRAA facts. The mission can't call the internet itself, so it hands events to a helper outside DCS: a file it appends to, or a local socket (the mission is de-sanitized, so `io` and possibly LuaSocket are available).
- **The helper (outside DCS, on the server machine):**
  - Reads the events and asks an LLM to phrase each one as a radio call, in brevity code, per callsign.
  - Speaks it on the right frequency through SRS text-to-speech (`DCS-SR-ExternalAudio.exe`), or sends the text back to the mission to show on screen.
- **Guard rails:**
  - The LLM only phrases facts it's given; it never invents contacts or positions.
  - Rate-limited, so up to 32 AI aircraft don't flood the channel.
  - Each coalition hears only its own flights.
  - If the helper or the cloud is down, the mission plays normally without calls.

**Open:**
- Which LLM and service: a cloud API (cost per session, latency of a second or two, an API key on the server) or a local model?
- Voice goes through SRS, so every player needs SRS running (decided: audio only).
- Which events are worth a call: all state changes, or only the ones that matter to a player (package pushing, station gaps, losses)?
- Everything to every Blue player, or only flights near the player or in their package?
- The AWACS calls (item 5) move to this voice channel once it works (John's goal); decide then whether the text version stays as a backup.

---

## 8. Skynet IADS: SAM networks that behave like real air defences

**Goal:** SAM sites that fight as a network instead of each radar on its own: early-warning radars share one picture, SAM sites stay dark until a target is close, and radars shut down when a HARM comes at them. That means ambushes, little RWR warning, and SEAD that actually has to work (John: "sounds really cool").

**Where it stands:** nothing built. What its README says (moved from the `plan.md` backlog):
- **Dependencies:** needs MIST; MOOSE is optional. Both would load unmodified alongside `kola_f16`.
- **Behaviour:**
  - early-warning radars share one picture;
  - SAM sites stay dark until a target is inside their go-live range;
  - radars within ~15° of a HARM's path, out to ~20 nm, shut down;
  - `addPointDefence` covers SHORAD guarding a site;
  - command centres and power sources can be destroyed, which leaves the sites working on their own.
- **Fit:** register each `plan.sam_sites.sites` entry by `layer` (`addSAMSite` / `addEarlyWarningRadar`; not by id prefix, since early-warning ids also start `SAM_`). Each `<id>_escort` → `addPointDefence`. One network per coalition.

**What it changes elsewhere:**
- **Radar picture (item 1):** dark SAM radars see nothing, so the picture then rests on early-warning radars, the AWACS and fighters. That's realistic, but check that scrambles still trigger. Also decide whether Skynet's own contact list and ours stay separate, or whether one feeds the other.
- **SEAD packages:** "whether suppression works doesn't need tracking" (John) may change once HARMs really make sites go dark.
- **Frag threats:** a site that stays dark is still listed as a threat. That fits the fidelity rule of fog of war (item 9).

**Approach (proposed):** test it first on script-spawned groups (the README covers groups placed in the ME). Prototype on one SA-11 and one early-warning radar, and fly a HARM at it. Then register the full networks.

**Open:**
- Command centres and power sources: add them as targets (new fixed-target kinds), or leave them out?
- Go-live range per system: Skynet's defaults, or tuned?
- Both coalitions, or Red only at first?
- SAMs in the map's revetments (`plan.md` backlog) could come in the same pass.

---

## 9. Fog of war: showing Red installations without revealing the whole map (last)

**Goal:** players see what Blue intelligence would plausibly know, not the planner's full picture. Enough to plan a mission, with real uncertainty left.

**Why last:** John is actively working on and debugging the mission and needs today's full-map drawings until the other items are done.

**Where it stands:**
- Everything is drawn for everyone: every `draw_*` consumer uses `…ToAll(-1, …)`. That shows both coalitions' territory, base defences, SAM sites with rings, fixed ground targets, convoys, airspace, and every air tasking line. It's the right view for debugging, and it gives the whole Red order of battle away to players.
- The design exists but isn't built: the threat-intel fidelity rule in `plan.md` (Design).
  - **CONFIRMED:** fixed strategic SAMs, with exact position and ring.
  - **PROBABLE:** mobile SAMs, with type and an operating area.
  - **POSSIBLE:** type and region only.
  - Some mobile systems not listed at all.
  - Base defences, AAA and MANPADS get a generic warning only.
  - Red's timeline is never disclosed; only station areas and base posture.

**Approach (proposed):**
- **Two views:**
  - **Developer view:** today's drawings, kept behind a config switch for debugging.
  - **Player view:** drawn per coalition. DCS map drawings take a coalition, so Blue and Red each see only their own view.
- **Blue player view:**
  - all of Blue's own assets;
  - Red per the fidelity rule: CONFIRMED rings, PROBABLE area circles, POSSIBLE in the comms-menu intel list only;
  - the airspace front line;
  - no Red flights, convoy routes, or base-defence labels.
- **Frag and targets:** a human tasking's own target is always shown (you were fragged against it), at the fidelity of its kind.
- **Live intel:** what the radar picture (item 1) or players detect appears as a timed "last seen" mark that goes stale.

**Open:**
- How much should players know of Red's base defences: nothing, a generic "defended" ring, or a level (light / heavy)?
- Unlisted mobile SAMs: what fraction?
- Should Red get a player view too, if Red slots come later?
- Live intel in the first version, or only the planned intel picture?

---

## Optional, later: radar jamming

**Goal:** jamming aircraft make the enemy's radar picture worse: a bearing without a range, contacts found later, and burn-through as they get closer. That gives escort jammers and self-protection pods a real effect on scrambles and AWACS calls.

**Where it stands:** nothing built, with no place in the order yet (John, 2026-09-30). The radar picture (item 1) takes DCS's detection result as it is, but it already keeps `range_known` per contact. So a jammed contact already shows up as a bearing-only strobe, if DCS reports it that way.

**Approach (proposed):**
- **Research first, in DCS:** does an AI jet with ECM on come back with `distance = false`? At what range does burn-through happen? Which AI types jam, and does the ECM option (`AI.Option.Air.id.ECM_USING`) change it?
- **If DCS models enough:** use it as it is, and make the consumers honour `range_known`. For example: no BRAA range in an AWACS call ("strobe, bearing 045"), and scrambles sent at a strobe with a search area instead of a point.
- **If it doesn't:** a small model of our own on top of the picture. Jammers carried by package flights reduce the detection range of radars that look toward them.

**Open:**
- Do dedicated jamming aircraft exist in DCS that the AI flies (EA-18G, Su-24MP), or only self-protection pods?
- Should Blue's F-16 players get to jam (the ALQ-184 pod)?

---

## Optional, later: helicopters

**Goal:** helicopters in the air war: attack helicopters working the front (Ka-52 / Mi-28 for Red, AH-64 for Blue), transport and utility flights behind it, and air defences and fighters that answer them.

**Where it stands:** nothing built (John, 2026-09-30: "we aren't doing helicopters yet"). The radar picture (item 1) already lists enemy helicopters as contacts. Scrambles (item 2) skip them for now.

**Open:**
- Which missions: close air support at the front, anti-armour, transport and insertion, search and rescue?
- Who answers enemy helicopters: SHORAD and MANPADS only, or also fighters (scrambles, patrols)?
- Low-flying helicopters are often masked by terrain from ground radars, so the picture will see them late or not at all. That's realistic, but decide whether it's enough.

---

## Optional, later: fun callsigns for human and AI flights

**Goal:** a generated data list of fun, flavourful callsigns ("Viper", "Reaper", "Moose", squadron-style names) that each flight gets, human and AI, so the air war has personality in the brief, the log and later on the radio (John, 2026-09-30).

**Where it stands:** nothing built. Flights have no callsign set, so DCS gives defaults, and several flights may share one. The callsign policy in `plan.md` (*Design, not built yet*) keeps the group name (`MSN2025_DEAD`) as the machine id, never spoken, with a separate radio callsign per flight.

**The catch to settle first:** DCS's own AI voices can only say callsigns from its fixed lists (Western aircraft: Enfield, Springfield, Uzi, Colt, Dodge, Ford, Chevy, Pontiac; AWACS: Overlord, Magic, Wizard, Focus, Darkstar; tankers: Texaco, Arco, Shell; Russian aircraft: numbers). A custom callsign can be printed in the brief, the comms menu and the log, but a DCS voice would still say the list name, so what's written and what's heard wouldn't match.
- **Once AI radio calls are built (item 7, LLM / text-to-speech),** our own voice can say any callsign, so fun callsigns work everywhere.
- **Until then:** fun callsigns in text only, or pick from DCS's list so voice and text agree.

**Approach (proposed):**
- **A data file** (`data/flight_callsigns.lua`, `FLIGHT_CALLSIGNS`), generated or hand-curated once, per coalition and role: fighters, attack, SEAD / DEAD, AWACS, tankers, human flights. Red could get Russian-flavoured names, or numbers as the real Russian air force uses.
- **Assigned at planning time,** one per flight, never two live flights with the same one, stored on the mission (`m.callsign`, e.g. "Reaper 2", units "Reaper 2-1", "Reaper 2-2").
- **Used by** the brief and frags, the comms menu, the event log (item 3), AWACS calls (item 5) and AI radio calls (item 7).
- **Human flights** get a reserved set, so a player's callsign stands out.

**Open:**
- Generate the list (e.g. from real squadron nicknames and brevity-friendly words) or hand-pick it?
- Text-only until item 7, or DCS list names for now?
- Themed per base or squadron (every Bodø flight is a "Viking"), or random from the role's list?

---

## Optional, later: the threat picture on the map for players

**Goal:** once fog of war (item 9) hides the full map, draw Blue's own radar picture (item 1) for Blue players, so they see the air threat the way their side's radars see it (John: "might be a really cool way to see the threat picture for the human players").

**Where it stands:** nothing built, on purpose. John doesn't want contacts drawn while debugging: the full map already shows every aircraft, and more marks would clutter it. It only makes sense after fog of war.

**Approach (proposed):**
- **A consumer of its own** (`consumers/draw_radar_picture.lua`) that listens to `TrackRadarPicture`'s events and redraws each coalition's contacts only for that coalition's players.
- **What a mark shows:** a symbol at the last known position with a heading line, the type if identified (else "unknown"), altitude, and the time last seen. A stale contact fades, then its mark is removed when the contact drops. A bearing-only contact is a line (strobe) from the radar, not a point.
- **Kept readable:** one mark per contact, updated in place every 30 s cycle; no trails.

**Open:**
- Every contact, or only those in own and contested airspace?
- Should it show which kind of sensor holds the contact (AWACS, ground radar)?
- Only while the AWACS is alive, or ground radars too?

---


**Also still open in `plan.md`, outside this roadmap:** front targets, playability follow-ups (spreading the two taskings, cancelling unflown packages, assignment and completion tracking), standoff attacks, escorts, and the AI behaviour rules in one place. Scrambles depend on that module's leash.
