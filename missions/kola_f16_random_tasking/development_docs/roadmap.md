# Kola F-16 Random Tasking — Roadmap

What's coming after session 10 (2026-09-30), when the mission became playable by humans. Each item says what it's for, what already exists, a proposed approach and the questions to settle before building. Details are decided with John as each item comes up, step by step, like the rest of the project.

`plan.md` stays the status and the build log; this file is the list of where the mission is headed. When an item is built and run, its "as built" notes go into the framework's `as_built.md`, and the item moves to `closed.md` (so this file doesn't grow forever). Item numbers stay as they are, so references elsewhere keep working: items 1–3, 5, 10–13, 16, the performance item and parts 4a / 4b of item 4 are in `closed.md`.

Players fly Blue (the F-16C slots), so "own" below means Blue and "enemy" means Red unless it says otherwise.

**Framework work (2026-10-06):** Kola now runs on the shared mission framework (`shared_mission_framework\`), and **every item on this roadmap is framework work**: each changes shared code (`mission_scripts\`, `radio_calls\`, `map_data_tools\`), so once built it reaches every mission on the framework (the Caucasus random tasking next), with Kola's values as the shared defaults. What would be Kola's alone (its map, its rosters, its slots) is noted in an item when it comes up. Items stay numbered and kept here for now; whether the framework gets its own `roadmap.md` is open (framework `plan.md`, *Open*). "`plan.md`, *As built*" and the other sections about how the code works: `shared_mission_framework\development_docs\as_built.md`.

**Order (John, 2026-09-30; items 10–12 added 2026-10-01; item 5 pulled forward and built 2026-10-02; item 13, airfield info, added and built 2026-10-02 outside the order; item 14, every mission type for players, and item 15, airfield traffic, added 2026-10-03 with no place in the order yet; item 7, AI radio calls, pulled forward 2026-10-05, its MVP (Darkstar spoken) built and flown the same day, and the AI pilots' and airfield calls built that night; item 16, SEAD that meets fighters, added 2026-10-05 and closed the same day, not needed; items 12 and 13 closed 2026-10-05):** ~~radar functions → scrambles → event log~~ → ~~performance in VR~~ (done for now, 2026-10-01) (all in `closed.md`) → ~~every run-time flight decision under the controller (item 11)~~ → ~~SEAD ingress doctrine (item 10)~~ → ~~SEAD against the air defenses: a standing rotation (item 12)~~ (all in `closed.md`) → **AI behaviour logic (item 4, the controller's further directives; next in the order)** → ~~AWACS calls (text)~~ (item 5, in `closed.md`) → cruise missiles → AI radio calls (MVP and pilots / airfields done; the rest) → Skynet IADS → fog of war. CAP visibility (making patrol routes and times easy to see) was cut on 2026-09-30: John can see the dotted station lines on the map fine for now. Fog of war is last on purpose: John is actively working on and debugging the mission and needs the full map. Five optional extras sit at the end, with no place in the order yet: radar jamming, helicopters, fun callsigns, the threat picture on the map for players (after fog of war), and a Wild Weasel wingman for SEAD flights (added 2026-10-02).

---

## 14. Players can fly every mission type, scrambles included (John, 2026-10-03)

**Goal:** a human player can take any mission type the AI flies. That includes the scramble: the player waits on alert, and when the controller decides a scramble from their base they get (n) seconds to take it; if they don't, it goes to the AI as now.

**Where it stands:**
- Human taskings (`HUMAN_TASKING.mission_types`) offer strike, airfield strike, DEAD, SEAD and CAP. Missing: **interception** (the scramble), and **interdiction** and **close air support** once those are built (`built = false` today).
- Scrambles are decided at run time by the controller (`consumers/control_air_flights/scramble_fighters.lua`): trigger, refusals, base, intercept point, then an AI jet spawned hot on one of the base's alert spots after `scramble_reaction_s` (60–120 s), watched by the leash.
- Players spawn by dynamic slots (`f16_<base>`); the controller has no way yet to tell a player in a slot apart from one on alert.

**Approach (proposed, decide with John):**
- **On alert:** a player says so from the comms menu ("On alert at Ivalo"), sitting in the cockpit on the ramp of an alert base (or, an open question below, airborne on a CAP station). The alert posture already knows each base's jets and spots.
- **The offer:** when the controller decides a scramble from that base (or one a player on alert could reach in time), the player gets it first: an on-screen call with the raid (BRAA from their base, type if known, what it is inbound on) and "accept within (n) s" from the comms menu. Accepted: the player is the scramble (no AI jet spawned; the base's alert jet count as now), with a frag (BRAA, the intercept point as a steerpoint, the leash's limits as advice). Not accepted in time, or the player isn't ready: the AI scramble launches as today, with no delay added beyond (n).
- **(n):** inside the reaction time the AI gets anyway (60–120 s), so handing it to the AI late doesn't cost the defence anything; e.g. 60 s.
- **Logged:** `CONTROL … scramble offered to <player>`, `… taken by <player>` / `… not taken in n s, AI launches`.
- **The other types:** interdiction and close air support become player taskings when they're built; anything else the AI flies gets a player version as it is added.

**Open:**
- "On station": waiting on the ramp (cockpit alert, like the AI's) or airborne on a CAP station (a CAP player could be offered an intercept instead of a scramble), or both?
- (n): one number, or by how far the raid is?
- Does a player who takes a scramble use up one of the base's alert jets (and its turnaround), as an AI scramble does?
- The leash for a player: advice only (a call when the raid is gone or the player is past the limits), since the controller can't order a human.

---

## 15. Airfield traffic in the comms menu (John, 2026-10-03)

**Goal:** what's moving at a base right now, in its `Airfield info` text (item 13): how many aircraft are taking off, landing and taxiing, and who. So a player knows before taxiing out or coming in what they'll share the runway and taxiways with.

**Where it stands:** item 13 (built 2026-10-02, not flown) gives each Blue base the wind, the runway in use, the runway numbers, the next AI flight out and in (from the air tasking order, planned times) and the alert jets. Nothing about what is physically moving there now.

**Approach (proposed, decide with John):** part of each base's existing `Airfield info` text (John, 2026-10-03), below the next out / next in lines, worked out when the text is opened, from the live aircraft of the base's coalition (AI and players), each counted once:
- **Taxiing:** on the ground at the base and moving (above a few knots), or spawned hot on the ramp and not yet airborne (an AI flight about to taxi);
- **Taking off:** airborne within a few km of the base, low and climbing, within a minute or two of its `TAKEOFF` event (the scheduler records takeoffs);
- **Landing:** airborne, landing here (an AI flight's `landing_base`, or a player close in), within ~20–30 km, low or descending, on its way home;
- each with a short line: flight, type, how many, and for landing the distance out ("MSN2025 SEAD, 2x F/A-18C, landing, 12 km out").

```
Traffic: 1 taking off, 2 landing, 3 taxiing
  Taking off: MSN2016 CAP, 1x F-15C
  Landing:    MSN2025 SEAD, 2x F/A-18C, 12 km out; f16_ivalo (player), 25 km out
  Taxiing:    MSN2027 SEAD, 2x F-16C; MSN2901 scramble, 1x F-16C
```

**Open:**
- Players listed by name, or counted only?
- Parked jets on the ramp, cold (statics, alert jets waiting) left out?
- The distances and speeds that count as "taking off" and "landing".

---

## 4. AI behaviour logic: conditional orders to flights in the air

**Goal:** fewer, more meaningful losses (air denial), by having the script give AI flights conditional orders while they fly, instead of only a plan at spawn. John (2026-09-30): "the only way we will reduce losses is to start using our AI logic to begin giving conditional in-game commands to flights." It won't be perfect, because the DCS AI is built to fight; the aim is the best scenario we can make.

**Why now:** the first scramble run (2026-09-30) lost 12 aircraft in 48 minutes (Blue 4, Red 8). Both Blue packages were caught by Red fighters and both Red packages were destroyed, mostly by aircraft that kept flying their route while being engaged.

**Where it stands:**
- **Built and moved to `closed.md` (2026-10-02):** 4a (the controller), 4b (attack flights defend themselves) and the bandit call with the abort of a defenceless flight; all have flown (the bandit call first worked in the 2026-10-01 22:23 run). What's left of this item is below.
- Left in this item: the rest of 4c below (8b out of weapons, 9 the slow leash, 11 the patrol merge, 6 targets already destroyed), and new directives from the 14:14 run: a pop shot from the edge of a ring (the landing order for a lost flight, bug 19, and patrol handover, bug 18, were built 2026-10-02).
- Each coalition's radar picture (item 1) says which enemy aircraft its radars see, where they are, and where they're heading.
- The rules collected so far (from the `plan.md` backlog, "AI behaviour rules, one place"): patrols leashed to own and contested airspace; strikes go home if their SEAD fails; no second wave into what killed the first (doctrine idea).

### 4c. Found in the first event-log run (2026-09-30)

John asked for these to go into this item. The run's log is `event_logs\2026-09-30_201105.log`; grep `MSN2025_SEAD` and `MSN2026_SEAD` for issues 1–3. Bugs from the same run that aren't AI-logic work are in `bugs.md`.

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
1. *(SEAD addressed 2026-10-01: one site per flight, the salvo ordered at a launch point, and the go-cold rule turns it around if it presses on; `plan.md`, Packages. DEAD flights still fly their own attack.)* **A SEAD / DEAD flight leaves its route once its attack task is live.** `EngageGroup` / `AttackGroup` let the DCS AI fly its own attack geometry, so the planned route's ring clearances don't hold. Needs a leash like the scrambles': don't go past a fraction of the target's ring, or into another enemy kill zone, to get a shot. Or an order that fires the HARMs from where the flight is, at longer range (research: can the AI be made to launch at max range, e.g. with an attack-range option, or a `FireAtPoint`-style task?).
2. *(Addressed 2026-10-01 for AI packages: they now fly in sequence, suppression first and home before the mission launches; `plan.md`, Packages.)* **Suppression flights aren't sequenced by where their threat sits along the route.** Each is timed only by `suppression_lead_s` before the strike's TOT, so a flight going for a deeper site (the SA-10) can arrive before the flight suppressing a site on the way in (the SA-11). Fix in planning (earlier TOT for threats the route meets first), or with a rule (hold short until the nearer threat is suppressed or dead).
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
6. *(Partly 2026-10-01: a suppression flight whose threats are already out of the fight isn't sent; a mission whose own target is already destroyed still is.)* **Flights still go after targets that are already destroyed.**
   - `SAM_KOSH_SA11_2`'s radar (its one critical object) was destroyed at 08:38 (the event log's `TARGET` line, `MSN2035_DEAD … 1 of 1 critical`).
   - MSN2035_DEAD (TOT 12:52) and its two SEAD flights, MSN2036 and MSN2037, were still planned against it.
   - A rule for this layer: before a flight spawns (and while it flies), if its target already meets its success fraction, cancel it or send it home (or re-target it; decide with John).
   - The same goes for a SEAD flight whose threat is already dead.
7. **Related, already in the `plan.md` backlog** ("Unflown taskings' AI flights"): MSN2028 flew and died escorting a human tasking nobody took. Once the logic layer can cancel flights, cancel a human package's AI flights when no player takes the tasking.

**From the second event-log run, John flying** (`event_logs\2026-09-30_213757.log`, 65 min; losses Blue 5, Red 11). Bugs from it that aren't AI-logic work are in `bugs.md` (6–8, and the additions to 1–3 and 5).

8. *(2026-10-01: `EngageGroup` now carries `expend = "One"` per aircraft per group, one attack; to be seen in DCS whether the AI keeps HARMs for its later groups.)* **Issue 1 again, then a SEAD flight flying on with nothing left** (grep `MSN2026_SEAD`):
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
12. **Red's attacks on Rovaniemi fly into a full SAM umbrella:** PKG5023 (8 jets) was planned 44–90 km inside the Rovaniemi SA-10's ring, which is also covered by IRIS-T, NASAMS and a Tunguska. All 8 jets were lost; their Kh-31Ps killed the NASAMS radar and the IRIS-T search radar. With the suppression flight unarmed (`bugs.md` 6), the package had no chance. This is also a planning question: should a target deep under a long-range SAM be picked at all, and should a package go when one of its suppression flights is missing?

### 4d. Commit patrols onto enemy fighters that are a threat (John, 2026-10-02)

**Goal:** the controller sends a combat air patrol after an enemy fighter (or attack flight) that is a threat. John: "It should be sending combat air patrols after enemy fighters if they are a threat, that's its purpose. 54 nm is pretty close." Today the controller never commits a patrol: a patrol fights only what DCS finds inside its defended zone and commit circles (`EngageTargetsInZone`, *Defensive air* in `plan.md`); its only directive is `handover`.

**Seen** (`event_logs\2026-10-02_160358.log`, ~04:23–04:25): Blue's F-15C patrol MSN2009_CAP (Ivalo station, 34,000 ft) was ~54 nm (100 km) from Red's MSN7031_DEAD (a Su-34 with R-77s, in contested airspace, which had just helped kill MSN2025_SEAD) and was never sent after it.
- Here Blue's picture never held MSN7031 at all (no `CONTACT` line all run; Blue's picture held 0–2 contacts, its E-3A only reached its station off Bodø at 04:23, ~200 km back), so control couldn't have called it. The F-15C is itself a picture sensor, and its radar didn't report the Su-34 at ~100 km (it was flying away, east). Worth checking whether that's DCS's detection range or something in how the picture polls patrols.

**Proposed (decide with John before building):** a new directive for patrols, `commit`, in `consumers/control_air_flights/`:
- **Trigger:** a contact in the coalition's picture that is an enemy airplane (fighter or attack), in own or contested airspace, and a threat: hot on the patrol or inbound on an own asset (the picture's `inbound`), within a commit range of the patrol (e.g. 100 km / 54 nm; John: 54 nm is close).
- **Who goes:** the nearest patrol with radar missiles that isn't already fighting; one patrol per contact (`coordinate_flights.lua`, as the bandit call does).
- **The order:** `AttackGroup` on the contact (pushed, like `defend`), so the patrol leaves its race-track and the DCS AI flies the intercept.
- **Limits:** the leash's rules (not into enemy airspace beyond its limit, not into enemy kill zones); back to the station when the contact is dead, gone from the picture, back over its own airspace heading away, out of range, or the patrol is out of radar missiles; then the station's race-track again.
- **Scrambles:** a contact a committed patrol takes needs no scramble (the trigger already refuses one "covered by patrol").
- `CONTROL … commit:` / `back on station:` lines.

**Open (4a, 4b and 4c):**
- Which rules first, and in what order: attack-flight self-defence, strikes going home when their SEAD fails, the patrol leash?
- How far a self-defending flight may turn off its route, and for how long?
- Should a package's SEAD flight protect the strike flight, or only itself?

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

## 7. AI radio calls: flights announce their intentions

**Status:** **MVP built and flown 2026-10-05** (John: "working, and is awesome"): Darkstar, Blue's AWACS, speaks its picture calls and immediate threat calls in a Windows voice through our own radio player. As built: `plan.md`, *Radio calls*. **The AI pilots and airfields talk** (designed with John 2026-10-05 evening, built the same night, steps 5–9 below; first tested by John 2026-10-05 late: "insanely cool so far, probably needs a few fixes"): AI flights' mission calls and airfield traffic calls, from a watcher beside the controller, on channels the jet's own radios tune (our export script, as SRS does), with callsigns and a reworked queue; *Flights and airfields talk* below. Darkstar's orders to the AI flights (step 14) built 2026-10-05 night, flown in the 2026-10-06 00:16 run (each order matched its `CONTROL` line); fixes from that run (bugs 62, 64–70) built 2026-10-06, not flown. The pilots' answers and reports (step 15) built 2026-10-06, not flown. Next: Azure voices (step 10). Pulled forward from its place in the order on 2026-10-05.

**Goal:** the air war can be followed by ear. The AWACS and AI pilots talk on the radio: "Darkstar, picture, two groups…", "Viper 2-1, airborne Rovaniemi, heading for the station", "Hornet 1-1, Magnum", each call phrased fresh rather than the same words every time (John, 2026-10-05: a kind of variety and immersion nothing in DCS has today).

**Long-term goal (John, 2026-09-30):** audio callouts only, with no on-screen text once it works.

### Decided (John, 2026-10-05)

- **Phrase bank, not an LLM, for now:** calls are put together from weighted, swappable phrases around the fixed technical facts, so they vary but always carry every fact. An LLM stays possible later as a second wording adapter (the API is billed apart from John's ChatGPT subscription, a few cents a session for wording; Codex signed in with the subscription is no way round that: OpenAI's terms forbid programmatic use outside the API, and each call would take seconds). A local LLM later on a stronger PC.
- **Windows voices, free:** Zira is Darkstar's one voice, so John can tell it apart once flights talk too. Cloud voices (Google, OpenAI) remain an option for more voices.
- **Darkstar:** the picture on the 2-min cycle of the on-screen list; **threat calls at once** (a hot contact inside 40 nm can't wait for the cycle). General picture calls to one player for now; per-jet BRAA for every player comes with multiplayer.
- **Blue only.** One frequency in the MVP; split into channels by the design below (2026-10-05 evening).
- **The on-screen text stays** for now; maybe removed later.
- **Latency doesn't need to be perfect** ("it's a game after all"), except threat calls.
- **Service-agnostic:** wording and voice are each one swappable piece (facts in, words out; words in, WAV out).
- **Kola-only for now.** Much of it moves to a shared folder once the Afghanistan mission starts (it will want radio calls too).
- **No mods or third-party code in DCS's game files, and no new dependencies** (John: mods bring dependencies, break on updates, can crash the game). Standard-library Python only. Nothing extra in John's start-up routine: the mission starts the programs itself.
- **Our own radio player, not SRS** (below).
- **Multiplayer: over ZeroTier** (John already plays with a friend on it). The mission runs on the host only, so the host words each player's calls (BRAA from that player's jet) and the friend's PC runs only the radio player, reached over the ZeroTier network; no public port. Every call already carries `to`.
- **Player callsign:** "Snake one one" for everyone until the slots carry their own (John, 2026-10-05: getting it right in the mission file has been a pain).

### Why not SRS or DCS's radio

- **DCS's radio** (`trigger.action.radioTransmission`) only plays sound files packed into the `.miz`, never audio made while the mission runs; DCS's voice chat has no scripting interface.
- **SRS** (its `DCS-SR-ExternalAudio.exe` sender) worked end to end, but its audio crackles, and it couldn't be fixed (2026-10-05): not the voice (clean when played locally), not John's SRS settings or effects, not CPU load, and the crackle is in SRS's own recording of what it received. Its sender is a fixed program, so there was nothing left to change. (A `flat` SRS settings profile with every effect off stays in John's SRS client for tests.)
- **Cockpit-aware:** decided 2026-10-05 evening, our own export script (below), the way SRS does it.

### Flights and airfields talk: the design (John, 2026-10-05 evening)

Two new kinds of talk: **AI flights calling what they do** (mission calls, "Fox 3", "pushing", "Splash"), so the fight can be followed by ear, and **airfield traffic calls the way an uncontrolled field works** ("Kallax traffic, Viper one two, final, runway three one, Kallax"). John: the mission channel is there to understand the fight, and can be turned off to focus on Darkstar and his flight; John and his friend talk on Discord, which is their inter-flight channel.

**How it works in real life (the basis):** frequencies are split by who a call is to. Each flight's own inter-flight frequency is private; the control frequency (AWACS / GCI) carries check-ins, check-outs and the tactical calls everyone needs ("Fox 3", "Magnum": a missile in the air, so nobody flies into it or mistakes it for a threat; "Splash": the picture changed); each field has its own tower / traffic frequency; guard for emergencies. Comm discipline keeps the calls short, so hearing everything on those frequencies is realistic.

**1. Calls come from what flights actually do, not from the controller.** The controller's decisions are orders the DCS AI sometimes doesn't follow, so speaking them would put things on the radio that never happened. A **watcher** sits beside the controller, not in it: it reads DCS's events and the same per-flight facts the controller uses (position, airspace, the flight's jets, weapons left; read only, no decisions), the way the event log watches without deciding. The controller stays orders only and knows nothing of the radio.

| Call | Seen as |
|---|---|
| airborne, checking in / out with Darkstar | `S_EVENT_TAKEOFF`; the flight's mission and target from the plan; landing / heading home |
| pushing / fence in | the flight's position crossing into contested airspace (not the ingress waypoint order) |
| Fox 1 / Fox 2 / Fox 3, Magnum, Rifle, bombs away | `S_EVENT_SHOT`, by the weapon (radar semi-active / infrared / active radar air-to-air; anti-radiation; air-to-ground missile; bombs); repeats from one flight within a few seconds folded into one call |
| Splash | `S_EVENT_KILL` / dead with our flight as the killer |
| defending / engaged | fired upon (a shot at it), or its own air-to-air shot |
| off target, RTB, bingo, Winchester | its attack done and heading home (seen, not ordered), fuel, weapons left (since step 15, a bingo or Winchester the controller decided is the pilot's report to Darkstar instead) |
| "Hornet 3-2 is down" | a jet of the flight destroyed or ejected |
| on station / off station (patrols) | reaching / leaving its race-track |

The controller's orders become **Darkstar's** voice later (below); the pilot's reply would still come from what the flight does, so an order the AI ignores is heard with no reply.

**2. Channels**, each its own frequency, like real ones:

| Channel | On it | Radio |
|---|---|---|
| AWACS | Darkstar's picture and threat calls (its orders since step 14), flights checking in and out with Darkstar (since step 15 also the pilots' answers and reports, bingo and Winchester) | UHF |
| Mission (tactical common) | the flights' tactical calls: pushing, Fox, Magnum, Splash, defending, off target, down | VHF |
| One per Blue airfield | that field's traffic calls | VHF |

- Frequencies in a data file (`data/radio_frequencies.lua`): the airfields' **real ones from the Kola map's own airfield radio data** (as the charts), AWACS and mission our own; shown in the brief and each base's *Airfield info*; set on the F-16 slots' preset channels in the mission file where that works (UHF 1 AWACS, UHF 2 mission…).
- Inter-flight isn't modelled (Discord).

**3. Hearing what the jet is tuned to: our own export script, as SRS does** (John, 2026-10-05: "if SRS does it I am fine with it"). Checked in SRS's own F-16 code (`Saved Games\DCS\Mods\Services\DCS-SRS\Scripts\DCS-SRS-Modules\F16C.lua`): UHF (AN/ARC-164) `GetDevice(36):get_frequency()`, volume cockpit argument 430; VHF (AN/ARC-222) `GetDevice(38):get_frequency()`, volume argument 431; `is_on()` per radio. The mission's own Lua can't read the cockpit; DCS's export system can.
- **Our export script** (in `radio_calls/`, never a mod or a game file) reads both radios' frequency, on / off and volume about once a second and sends them over UDP on 127.0.0.1 to the radio player.
- **The radio player plays only calls on a frequency one of the jet's radios is tuned to, at that radio's volume knob** (the radio sound's volume setting stays the overall level). With no word from the export script it plays everything, as now.
- **Installed by one line in `Saved Games\DCS\Scripts\Export.lua`,** next to SRS's line. The radio player checks for it at start and adds it if missing (never touching anything else in the file), and says once that DCS needs a restart; takes effect from the next DCS start.
- **Documented step by step in the repo's `README.md`** (John: so he can tell his friend how to set it up): what the line is, where it goes, how to add it by hand, how to check it works, how to take it out.
- **Multiplayer fits:** the export script runs on each pilot's own PC and talks to that PC's radio player; the host sends every call, tagged with its frequency, to every radio player (over ZeroTier); each plays what its own pilot is tuned to.

**4. Everything is heard** (John, 2026-10-05: "we don't have that many flights running"). From the 10:31 run (1 h 46 min, Blue: ~11 flights, 14 kills, ~20 air-launched salvoes): about 5 routine calls per flight plus the combat calls, ~80 calls, under one a minute, ~5 % airtime; the busiest minute ~2–3 calls once folded. The queue rules (5) are a safety net, not a filter.

**5. The queue, reworked for many calls.** Today: one call at a time, urgent (threat) first, a newer picture replaces an older one waiting, a call past its `expires_s` dropped when its turn comes. Missing for this load:
- **Its clock starts at the mission event,** not when the helper sends the finished audio (the helper's own wording / voice backlog is counted).
- **A priority on every call:** threat and combat calls (Fox, Magnum, Splash, defending, down) first, then airfield calls, then routine (airborne, checking in, RTB).
- **A backlog limit:** over ~20 s of audio waiting, the lowest priority calls go.
- **Short lives by kind:** a Fox call ~8 s, an airfield call ~20 s, a picture 90 s (as now).
- **Folding:** the same flight and kind within a few seconds is one call.
- **The frequency checked when a call's turn comes:** retuning drops calls waiting on the old one.
- **Calls never overlap** (John: two radios are fine as long as calls don't overlap): one playback lane for both radios.

**6. Callsigns** (John: realistic names for now): one per flight, from planning until it lands, **the same everywhere** (radio, brief, air tasking order, comms menu, event log): MSN2023_SEAD is "Hornet 3" for the whole mission, its jets "Hornet 3-1", "Hornet 3-2". Names by role and type from a data file (`data/flight_callsigns.lua`; e.g. Viper, Hornet, Eagle, Weasel for SEAD), numbered so no two live flights share one. **A retry (`_AGAIN`, `_LATER`) keeps the name with a new number** ("Hornet 5"), so two "Hornet 3"s are never on the radio at once. The group name stays the machine id, never spoken. Players stay "Snake 1-1" until the slots carry their own. This is the optional fun-callsigns item, built realistic; flavour names can come later from the same file.

**7. Airfield traffic, uncontrolled-field style.** "<Field> traffic, <callsign>, <where / what>, runway <n>, <field>" on that field's frequency, for Blue fields:
- taxiing (a hot-spawned AI jet starting to move), departing (takeoff, with its direction), inbound (~10 nm, heading for its planned landing base), final (~4–5 nm, lined up and descending), clear of the runway (landed and slowed);
- **the runway it actually uses,** from its heading against the field's runway numbers (grid-based magnetic, as the airfield brief);
- one tracker of these phases for AI jets near Blue fields, checked every few seconds and only for flights departing or arriving, **shared with roadmap item 15** (traffic in the comms menu);
- **no player calls** (John: maybe later, if it grows into an LLM-based ATC).

**8. Wording: phrase banks like Darkstar's,** for pilots and airfields both (John: so dozens more phrases can be added later): the facts fixed in code, every flavour piece a weighted, conditional list in a JSON file (`pilot_phrases.json`, `airfield_phrases.json` beside `awacs_phrases.json`), styles chosen once per call, recent phrases down-weighted, every placeholder and condition checked at load.

**9. Voices:** a voice per flight, never Zira (Darkstar's), from whatever voices are open to us; with System.Speech that's only David today, so flights also get a small pitch and rate offset of their own (SSML) to tell them apart. John adds more Windows voices later (Settings → Speech); reaching the newer Windows voices (Mark and the installed language packs) may need the WinRT speech engine through PowerShell, still standard Windows, checked when we get there.

**Darkstar gives orders** over the radio, to AI flights (the controller's decisions, in a controller's words; designed as step 14 below, John 2026-10-05 late) and later to human players (John, 2026-10-05: "at some point").

### Steps

1. ~~**The radio player**~~ (built 2026-10-05; John tuned nothing: "sounds great").
2. ~~**Phrase-bank wording and Windows voices**~~ (built 2026-10-05; 100+ combinations per call; recent phrases made less likely, never barred, after John heard "that's all I have" too often).
3. ~~**The MVP in Kola:** Darkstar's picture and threat calls, the helper and player started by the mission~~ (built and flown 2026-10-05).
4. ~~**Bug 61:** bearings a few degrees off against the F10 map~~ (fixed 2026-10-05: DCS's magnetic is grid-based; stale tracks no longer called; `closed.md`).
Steps 5–9 built 2026-10-05 late, harness-tested, first heard in the 21:02 test and flown in the 2026-10-06 00:16 run (as built: `plan.md`, *Radio calls*). Built a little differently: slot presets not set (John tunes the frequencies; they're in the start text, the frag and *Airfield info*); folding is done in the mission (per flight and kind, `fold_s`), not in the player; a pilot's voice is per jet, not per flight; with only David installed, the voices differ by speed and pitch (System.Speech ignores SSML pitch, so the radio sound plays the voice faster or slower).
5. ~~**Callsigns** (design 6)~~.
6. ~~**The queue rework** (design 5)~~.
7. ~~**Channels, frequencies and the export script** (designs 2, 3)~~.
8. ~~**The watcher's mission calls** (designs 1, 8, 9)~~.
9. ~~**Airfield traffic calls** (design 7)~~; the phase tracker (`track_airfield_traffic.lua`) is there for roadmap item 15 to read.
10. **More voices: Azure's cloud voices next** (John, 2026-10-05: "probably the next step"; not built). Windows gives scripts only David, Zira and Mark (Mark added 2026-10-05 through the newer OneCore engine). The voices John installed (Ryan, Andrew, Sonia, Guy, Prabhat) are Windows' "natural" voices, Narrator's only; the same voices are Microsoft's Azure neural voices (en-GB Ryan and Sonia, en-US Andrew and Guy, en-IN Prabhat, and many more accents). The plan:
    - **A third voice adapter** beside `windows_voice.py` (`azure_voice.py`): text in (SSML), WAV out, over Azure Speech's REST text-to-speech API with Python's standard library only (`urllib`), so no new dependency.
    - **Needs:** internet, an Azure account and a Speech resource's key and region, kept outside the repo (an environment variable or a git-ignored file), never committed. Its free tier covers far more than this mission speaks.
    - **One more voice option**, alongside the Windows ones: `pilot_phrases.json` voices get an engine (`windows` / `azure`); a call falls back to a Windows voice when Azure doesn't answer in time (no internet, no key, over the quota), so the radio never goes quiet. A voice per flight as now; Darkstar could get one too.
    - **To check when built:** the time per call (a network round trip on top of the ~0.4–0.7 s now; threat and Fox calls can't wait long), and caching calls that repeat word for word.
    - Not a third-party adapter that exposes the natural voices to Windows' engines (outside software installed into Windows).
11. **Player callsigns** from the slots, once John has them in the mission file.
12. **More Darkstar calls,** written for the ear like a real controller: new group / pop-up, faded, merged; a short summary when nothing changed instead of the full list every 2 min.
13. **Multiplayer:** each player's calls with BRAA from their own jet, sent to their radio player over ZeroTier (the player listening on the ZeroTier address too).
14. ~~**Darkstar's directives to the AI flights**~~ (John, 2026-10-05 late: "the controller commands become Darkstar directive radio callouts to the individual flights"; **built 2026-10-05 night without the pilots' answers**, flown 2026-10-06 00:16; as built: `plan.md`, *Radio calls*. Built a little differently: a listener of the controller's published decisions (John: "a watcher, not the controller directly"); `press on` not said; a scramble's decision silent, its vector said once its jet is airborne. The answers below are the next pass). The controller already plays the part a real AWACS / GCI controller does (it commits, sends home, hands over, vectors scrambles); its decisions become Darkstar's calls to that flight, by callsign, on the AWACS channel, so the orders can be heard as well as the flights' answers.
    - **Which decisions** (the controller's `CONTROL` decisions; the words are a phrase bank, `awacs_phrases.json` or its own file, as variable as the rest):

      | Decision | Darkstar says (e.g.) |
      |---|---|
      | `scramble` | "Viper 5, Darkstar, scramble, vector zero four zero, sixty miles, angels two five, group Flanker" |
      | `defend` (the bandit call) | "Weasel 1, Darkstar, bandit, zero niner zero for two five, hot, engage" |
      | `leave` (no radar missiles to fight it) | "Hornet 2, Darkstar, bandit hot two five miles, break off, RTB" |
      | `press on` (a SEAD flight keeps low) | "Weasel 1, Darkstar, bandit north four zero miles, press on" |
      | `back on mission` | "Weasel 1, Darkstar, bandit dead, resume" |
      | `go cold` / `no shot` / `salvo over` | "Weasel 1, Darkstar, push cold, RTB" (since step 15, a salvo done or no emitter is the pilot's report, "Darkstar, Weasel one, Magnum complete, egressing", and Darkstar's "copy"; a go cold for a SAM ring or pressing too far stays Darkstar's) |
      | `leash home` / `leash stand down` | "Viper 5, Darkstar, raid turned away, return to base" / "… scramble cancelled" |
      | `handover` | "Eagle 1, Darkstar, relief on station, cleared off, RTB" |
      | `bingo` | "Viper 2, Darkstar, bingo, RTB Ivalo" (since step 15 the pilot's report, "Darkstar, Viper two, bingo, RTB Ivalo", and Darkstar's "copy bingo") |
      | `land` (an orphaned wingman sent to land) | "Weasel 1-2, Darkstar, land Rovaniemi" |

      Not spoken: the launch decisions (`wait`, `retry`, `cancel`, `launch late`, `come back`, `alert`): planning on the ground, not an order to a flight in the air.
    - **The answer comes from what the flight does,** as decided for the pilots' calls: the watcher hears the order and looks for the flight to follow it (turning toward home, a Fox call, heading for the intercept point) within a short time; then the pilot answers ("Weasel 1, wilco" / "Weasel 1, copy, engaging"), and their own calls follow as now. An order the DCS AI ignores is heard with no answer, which is honest, and the event log's `RADIO_CALL` line can say "no answer".
    - **The controller doesn't know the radio:** it publishes each decision to listeners (as the radar picture publishes its events), and the radio subscribes; `ControlAirFlights.say` is the one place every decision already passes.
    - **Text and timing:** the facts each call needs are what the decision already works out (the bandit's bearing, range, aspect from the radar picture, measured from the flight; a scramble's vector to its intercept point; the base to land at). Priority as a threat call when a bandit is involved, routine for RTB and handover.
    - **Later, with multiplayer and player taskings:** the same directives to human players (John, 2026-10-05: "at some point"): a commit or an RTB call to a player's flight, which the player follows or not.
15. ~~**Pilot answers to Darkstar's orders**~~ (John, 2026-10-05 night: step 14 was built without them; **designed with John and built 2026-10-06**, harness-tested, copied to DCS, not flown; as built: `plan.md`, *Radio calls*). Decided with John 2026-10-06:
    - **Who would know it says it** (John: "the air controller can't see the individual pilot's jet fuel IRL"): a controller decision only the pilot could make, from what is inside the jet (`bingo`, a salvo done: `salvo_complete` / `salvo_over`, `no_shot`, `out_of_missiles`), is said as the flight lead's **report** ("Darkstar, Viper one, bingo, RTB Ivalo") and Darkstar's "copy"; the order to DCS stays the controller's. Everything from the radar picture stays Darkstar's order, answered by the pilot.
    - **The report or the RTB answer is the check-out** (no separate `check_out` after it); `off_target` stays on the mission channel.
    - **One bingo:** a flight the controller watches for fuel (patrols, scrambles) has only the report; attack flights (no controller fuel rule) keep the watcher's 15 % call. A Winchester already reported isn't said again.
    - **No "unable":** we can't tell "can't" from "the AI ignored it", so an order not followed gets silence and `RADIO_CALL … no answer`.
    - **The answers hear the orders as said**, not the controller's decisions (John: "tag the controller orders that are published as radio calls sent"): every call written is published (`SendRadioCalls.onCall`), so no hand-off between consumers and no listener order to depend on.
    - **Wait limits:** engage and resume 30 s, RTB and a scramble's vector 45 s, land 60 s.

    The design as it stood before building: the answer comes from what the flight does, as in step 14's design above (the order heard, then the flight seen following it: turning home, a Fox call, heading for its intercept point; an ignored order gets no answer, `RADIO_CALL … no answer`). **Channels, decided with John 2026-10-05 night: divided by who a call is to, not what it's about**, because an answer goes back on the frequency its order came on:
    - **AWACS, UHF 262.000: anything to or from Darkstar.** Darkstar's picture, threat calls and orders (as now); check-in, check-out, on station (as now); **the pilots' answers** ("Weasel one, wilco", "committing", "copy, RTB"); **`bingo` and `winchester` move here from the mission channel** (reports to the controller, often answered by Darkstar's RTB).
    - **Mission, VHF 140.000: flights talking for everyone in the fight, not to Darkstar:** pushing, Fox, Magnum, rifle, bombs away, splash, defending, jet down, off target.
    - **Tower VHF:** airfield traffic, unchanged.
    - Both radios on (the normal setup) hears everything; VHF off leaves the whole conversation with Darkstar, orders and answers, without the combat chatter. An engage then reads: UHF "Weasel one, Darkstar, bandit …, engage" → UHF "Weasel one, committing" → VHF "Weasel one one, Fox three" → VHF "Splash one Flanker" → UHF "Weasel one, Darkstar, good kill, resume".
    - **Splash stays on mission for now:** really it is often said on the control frequency so the controller can update the picture, but Darkstar's "good kill" comes from the controller's own decision, not from hearing it. Moving it is one line in `announce_flight_activity.lua`.
    - ~~To settle when building: the two bingo thresholds~~ (settled 2026-10-06 above: one bingo per flight).
16. **Later:** an LLM wording adapter to compare against the phrase bank; player calls / an LLM-based ATC.

### Open

- **The threat call's lateness:** up to one radar round (30 s) after a contact crosses 40 nm; fine, or faster?
- Red's voice (Russian?) once Red talks.
- **Which Kola fields carry radio data** in the map's files, and whether the F-16 slots' presets can be set by script (else John sets them once in the mission editor).

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

**Note (2026-10-01):** AI packages now launch a mission only once its SAMs are *destroyed* (radars dead), since DCS SAMs without Skynet rarely go dark and a HARM hit usually kills the radar. With Skynet, HARMs make sites go dark, so that check needs to become "suppressed or destroyed", and the SEAD salvo may suppress rather than kill.

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

## Optional, later: the SEAD wingman flies Wild Weasel (John, 2026-10-02)

**Goal:** give the second jet of a SEAD 2-ship a job of its own, since in most salvoes it does nothing. John: SEAD works now, so this waits; don't change the SEAD flights for it until it's picked up.

**Why:** in the 19:29 run (`event_logs\2026-10-02_192901.log`) only the lead fired in 3 of 4 salvoes: the wingmen of MSN2026, MSN7023 and MSN7023_SEAD_AGAIN fired nothing before `salvo over` sent the flight home 20 s after the lead's last missile, and flew home with 4 anti-radiation missiles each (in the 17:48 run both F-16s of MSN2024 fired all 8 within 13 s, so it isn't every time). Half of each salvo goes unused.

**The idea:** the lead flies the planned salvo at its site as now; the wingman flies Wild Weasel: it stays in the area (outside the target's kill zone) for a while and fires at any radar that comes up, the site's own if it comes back, a pop-up short-range SAM, an airfield Tor or Pantsir, or covers a strike flight going in behind the salvo.

**To settle when it comes up:**
- A DCS group has one task, so the wingman would have to be its own group: plan and spawn the SEAD flight as two single-ship groups (one id each, or `MSN2026_SEAD` and `MSN2026_WEASEL`), or split the wingman off after takeoff.
- What the Weasel is told: `EngageTargets` on SAM radars in a zone, `EngageGroup` on a list of nearby sites, or an orbit with the anti-radiation missiles free; how long it stays, how far it may go, and how the controller's go-cold and bandit rules treat it.
- Whether it pairs with strikes (Weasel cover timed to an attack flight's run) or stays with the SEAD rotation only.

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

**Status (2026-10-05 evening):** pulled into item 7 (*Flights and airfields talk*, design 6, step 5): realistic names first (John), one per flight for the whole mission, a retry the same name with a new number. Flavour names stay this item, from the same data file, later.

**Goal:** a generated data list of fun, flavourful callsigns ("Viper", "Reaper", "Moose", squadron-style names) that each flight gets, human and AI, so the air war has personality in the brief, the log and later on the radio (John, 2026-09-30).

**Where it stands:** nothing built. Flights have no callsign set, so DCS gives defaults, and several flights may share one. The callsign policy in `plan.md` (*Design, not built yet*) keeps the group name (`MSN2025_DEAD`) as the machine id, never spoken, with a separate radio callsign per flight.

**The catch to settle first:** DCS's own AI voices can only say callsigns from its fixed lists (Western aircraft: Enfield, Springfield, Uzi, Colt, Dodge, Ford, Chevy, Pontiac; AWACS: Overlord, Magic, Wizard, Focus, Darkstar; tankers: Texaco, Arco, Shell; Russian aircraft: numbers). A custom callsign can be printed in the brief, the comms menu and the log, but a DCS voice would still say the list name, so what's written and what's heard wouldn't match.
- **With our own radio voices (item 7; Darkstar speaks since 2026-10-05),** any callsign can be said, so fun callsigns work everywhere once AI flights talk.
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
