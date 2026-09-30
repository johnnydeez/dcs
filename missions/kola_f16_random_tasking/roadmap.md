# Kola F-16 Random Tasking — Roadmap

What's coming after session 10 (2026-09-30), when the mission became playable by humans. Each item says what it's for, what already exists, a proposed approach and the questions to settle before building. Details are decided with John as each item comes up, step by step, like the rest of the project.

`plan.md` stays the spec and the build log; this file is the list of where the mission is headed. When an item is built, its "as built" notes go into `plan.md`, and it gets marked done here.

Players fly Blue (the F-16C slots), so "own" below means Blue and "enemy" means Red unless it says otherwise.

**Order (John, 2026-09-30):** radar functions → scrambles → CAP visibility → AWACS calls (text) → cruise missiles → AI radio calls (LLM / cloud) → Skynet IADS → fog of war. Fog of war is last on purpose: John is actively working on and debugging the mission and needs the full map. Two optional extras sit at the end, with no place in the order yet: radar jamming, and the threat picture on the map for players (after fog of war).

---

## 1. Radar functions: one shared radar picture

**Status: built 2026-09-30, tested offline; waiting for its first DCS run (watch and log only).** As built: `plan.md`, *Radar picture*.

**Goal:** each coalition builds its own threat picture from what its radars actually report, and keeps it as the mission runs. Scrambles (2), AWACS calls (4), live intel for fog of war (8) and any later AI behaviour rule all read it. So it's built once, and those features act only on what the defenders could really know.

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
- **A radar that's switched off sees nothing:** alarm state green, or a site that Skynet (item 7) keeps dark.

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

**What it leaves alone:** `run_scrambles.lua` stays off, with its old poll, until item 2. There it gets reworked to listen for `airspace_changed`, and its `radarPicture()` is deleted.

**Testing:**
1. **luae harness:** a stubbed `Controller` returns scripted detections. It checks the round robin, merging, going stale, events and airspace tags.
2. **The first DCS run only watches and logs,** so the mission plays exactly as before. Compare the `picture` lines with the `track:` lines and flight paths. The same run covers the DCS checks:
   - terrain masking: a low flyer against a ground radar;
   - a missile in flight: is it listed?
   - `getRadar()` on a SAM site tracking a jet;
   - whether the `type` and `distance` flags behave as described.

---

## 2. Fighter scrambles against enemy incursions

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
- The constrained redesign below was agreed in direction in session 9; the details are still open.

**Approach:**
- **Trigger:** an intruder in the radar picture over own airspace, or over contested airspace near an alert base. This replaces the defended-air-zone circles.
- **Tasking:** `open_fire`, `EngageGroup` on that one intruder, plus engage circles over own and contested airspace kept out of enemy kill zones, like the patrols' commit circles. No `EngageTargets` on everything.
- **Leash:** the 30 s scramble loop sends the scramble home when the intruder goes back to its own airspace, or when the scramble's path would enter an enemy kill zone. This is the first runtime behaviour rule. Build it once, in the one place for AI behaviour rules (`plan.md` backlog, "AI behaviour rules, one place"), so patrols can use it too.
- **Budget:** launches per alert base and cooldowns, within the shared airborne cap.

**To switch on:**
- `AIR_DEFENSE.alert_posture_planned = true` (alert bases, radars);
- un-comment `RunScrambles.start` in `init.lua`;
- rework `planAlertPosture` (the trigger area) and `consumers/run_scrambles.lua` (tasking, leash);
- `interception` loses `weapons_free` in `data/air_tasking.lua`.

**Open:**
- What counts as an "incursion": any contact over own airspace, only fighters, or only contacts heading inward?
- Response size: single ship (as now, to watch them) or pairs?
- Alert bases: re-check the hub / fighter pick against the session 9 runway reclassification.
- Session 9's order put scrambles after front targets (`plan.md` backlog), so there's more traffic to judge them by. Decide whether that still holds.

---

## 3. AI CAP routes easy to see: where and when

**Goal:** a player can see at a glance where own patrols will fly and when they'll be on station: to plan around them, join up, or know who covers what.

**Where it stands:**
- `consumers/draw_air_tasking_orders.lua` draws each station's race-track with one label listing its flights, plus commit circles.
- The comms menu `Air tasking order > Patrols and AWACS` lists each flight and its state (planned / airborne / landed / lost).
- Missing: times on the map (takeoff, on station, off station), the transit route to and from each station, and anything showing the current state on the map.

**Approach (proposed):**
- **Station labels:** each rotation's on-station window (`08:40–09:40 F-15C ×1 from Rovaniemi`), in mission time like the frag.
- **Routes:** a thin line from base to station for each rotation, in the same style as attack routes.
- **Live state:** update the label as flights launch, arrive and leave. DCS map marks can be removed and redrawn, so labels can change.
- **Comms menu:** `Patrols and AWACS` lists stations with coverage windows and gaps ("no cover 09:40–09:55").

**Open:**
- Live-updating labels, or planned times only?
- Once fog of war exists: own patrols only.

---

## 4. AWACS calls to the player (text)

**Goal:** the AWACS tells the player what it sees: enemy aircraft with bearing, distance, altitude and type, like a real controller's picture calls.

**Decided:** text messages to the player's group (`outTextForGroup`) for now. Long-term goal (John): AWACS calls become LLM / cloud audio like the AI pilots' calls (item 6), and the text version is the step before that. Build the calls so the delivery can be swapped: the facts (who, BRAA, type) are worked out in one place, and text is only one way of sending them.

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

## 5. Cruise missile attacks (ideally from the ground, else from the air)

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

## 6. AI radio calls: flights announce their intentions (LLM / cloud)

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
- The AWACS calls (item 4) move to this voice channel once it works (John's goal); decide then whether the text version stays as a backup.

---

## 7. Skynet IADS: SAM networks that behave like real air defences

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
- **Frag threats:** a site that stays dark is still listed as a threat. That fits the fidelity rule of fog of war (item 8).

**Approach (proposed):** test it first on script-spawned groups (the README covers groups placed in the ME). Prototype on one SA-11 and one early-warning radar, and fly a HARM at it. Then register the full networks.

**Open:**
- Command centres and power sources: add them as targets (new fixed-target kinds), or leave them out?
- Go-live range per system: Skynet's defaults, or tuned?
- Both coalitions, or Red only at first?
- SAMs in the map's revetments (`plan.md` backlog) could come in the same pass.

---

## 8. Fog of war: showing Red installations without revealing the whole map (last)

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

## Optional, later: the threat picture on the map for players

**Goal:** once fog of war (item 8) hides the full map, draw Blue's own radar picture (item 1) for Blue players, so they see the air threat the way their side's radars see it (John: "might be a really cool way to see the threat picture for the human players").

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
