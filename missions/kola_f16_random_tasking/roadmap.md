# Kola F-16 Random Tasking — Roadmap

What's coming after session 10 (2026-09-30), when the mission became playable by humans. Each item says what it's for, what already exists, a proposed approach and the questions to settle before building. Details are decided with John as each item comes up, step by step, like the rest of the project.

`plan.md` stays the spec and the build log; this file is the list of where the mission is headed. When an item is built, its "as built" notes go into `plan.md`, and it gets marked done here.

Players fly Blue (the F-16C slots), so "own" below means Blue and "enemy" means Red unless it says otherwise.

**Order (John, 2026-09-30):** radar functions → scrambles → CAP visibility → AWACS calls (text) → cruise missiles → AI radio calls (LLM / cloud) → fog of war. Fog of war is last on purpose: John is actively working on and debugging the mission and needs the full map.

---

## 1. Radar functions: one shared radar picture

**Goal:** one place that knows what each coalition's radars actually see: which enemy aircraft, where, how fast, and whether the type is identified. Scrambles (2), AWACS calls (4), and later live intel for fog of war (7) all read it, so it's built once and those features only report what the defenders could really know.

**Where it stands:**
- `consumers/run_scrambles.lua` (session 7, switched off) already polls every radar group with `Controller:getDetectedTargets(RADAR)` every 30 s. The polling works in DCS: `31 of 31 answered` (Red), `21 of 21` (Blue).
- Red's A-50 saw a Blue F/A-18 near Rovaniemi at T+9 min.
- The polling is inside the scramble consumer, not something others can read.

**Approach (proposed):**
- **Pull the polling out** of `run_scrambles.lua` into its own consumer that keeps a per-coalition picture. It runs whether or not scrambles are on.
- **Radars in the picture:** early-warning radars, SAM search radars, the AWACS (while alive). Optionally, fighters' own radars.
- **Per contact:** the enemy group, position, altitude, heading and speed (from two samples), which radar saw it, whether the type is known (DCS reports that), and first-seen / last-seen times.
- **Contacts go stale** after N seconds unseen, not instantly: a radar sweep can miss a target for a cycle.
- **Airspace per contact** (own / contested / enemy), from the existing airspace grid. That's the input scrambles need.
- **Logging:** a periodic `picture:` line per coalition (contact count, by airspace), like the `track:` lines, for debugging runs.

**Open:**
- Poll interval: 30 s as now, or faster for AWACS calls (a 30 s-old position is ~15 km off for a fast jet)?
- Include fighters' own radars, or ground radars and the AWACS only?
- Does jamming or terrain masking matter, or is DCS's detection result taken as-is?

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

## 7. Fog of war: showing Red installations without revealing the whole map (last)

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


**Also still open in `plan.md`, outside this roadmap:** front targets, playability follow-ups (spreading the two taskings, cancelling unflown packages, assignment and completion tracking), standoff attacks, escorts, and the AI behaviour rules in one place. Scrambles depend on that module's leash.
