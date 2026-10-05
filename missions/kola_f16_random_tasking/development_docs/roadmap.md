# Kola F-16 Random Tasking — Roadmap

What's coming after session 10 (2026-09-30), when the mission became playable by humans. Each item says what it's for, what already exists, a proposed approach and the questions to settle before building. Details are decided with John as each item comes up, step by step, like the rest of the project.

`plan.md` stays the spec and the build log; this file is the list of where the mission is headed. When an item is built and run, its "as built" notes go into `plan.md`, and the item moves to `closed.md` (so this file doesn't grow forever). Item numbers stay as they are, so references elsewhere keep working: items 1–3, 5, 10, 11, the performance item and parts 4a / 4b of item 4 are in `closed.md`.

Players fly Blue (the F-16C slots), so "own" below means Blue and "enemy" means Red unless it says otherwise.

**Order (John, 2026-09-30; items 10–12 added 2026-10-01; item 5 pulled forward and built 2026-10-02; item 13, airfield info, added and built 2026-10-02 outside the order; item 14, every mission type for players, and item 15, airfield traffic, added 2026-10-03 with no place in the order yet; item 7, AI radio calls, pulled forward 2026-10-05 and its MVP (Darkstar spoken) built and flown the same day; item 16, SEAD that meets fighters, added 2026-10-05 with no place in the order yet):** ~~radar functions → scrambles → event log~~ → ~~performance in VR~~ (done for now, 2026-10-01) (all in `closed.md`) → ~~every run-time flight decision under the controller (item 11)~~ → ~~SEAD ingress doctrine (item 10)~~ (both in `closed.md`) → **SEAD against the air defenses: a standing rotation, rolling them back outside-in (item 12, top priority; designed 2026-10-01, reworked with John and built 2026-10-02, to fly)** → AI behaviour logic (item 4, the controller's further directives) → ~~AWACS calls (text)~~ (item 5, in `closed.md`) → cruise missiles → AI radio calls (MVP done; the rest) → Skynet IADS → fog of war. CAP visibility (making patrol routes and times easy to see) was cut on 2026-09-30: John can see the dotted station lines on the map fine for now. Fog of war is last on purpose: John is actively working on and debugging the mission and needs the full map. Five optional extras sit at the end, with no place in the order yet: radar jamming, helicopters, fun callsigns, the threat picture on the map for players (after fog of war), and a Wild Weasel wingman for SEAD flights (added 2026-10-02).

---

## 12. SEAD against the air defenses: a standing rotation, rolling them back outside-in (top priority, next)

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

## 13. Airfield info in the comms menu (John, 2026-10-02)

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

## 16. SEAD that meets fighters: clear the way, or go elsewhere (John, 2026-10-05)

**Goal:** a SEAD flight that keeps dying to enemy fighters in contested airspace gets help, or its effort moves somewhere less hot, instead of the same flight being sent down the same corridor again. John: "A SEAD fail to fighters in contested airspace should call in a CAP or SCRAM or send out a search and destroy mission from a base to clear the way. And rotating flights to other less hot regions also makes sense." A bigger change; a todo item, no place in the order yet.

**Seen** (`event_logs\2026-10-05_103126.log`, 1 h 46 min, no player flying): three tries at the Koshka Yavr SA-10 (MSN2026_SEAD, `_AGAIN`, `_LATER`, all 2x F/A-18C from Kirkenes on the same route) cost 6 Hornets and destroyed no radar. 3 of the 6 died to fighters: two to Red's Su-34 strike flights (R-77s) and one to a Su-27 patrol, all in the Kirkenes-Koshka Yavr corridor, which is also Red's busiest (strikes out of Koshka Yavr and Murmansk, the MiG-31 station). Two more died to the SA-10 and the Luostari SA-8. Blue's whole rotation waits behind that one site. Red lost 4 Su-34s the same way on the Rovaniemi SA-10 (one Kh-31P got through).

**Ideas (decide with John when it comes up):**
- **Clear the way:** a SEAD flight lost to fighters (or `press on` / `defend` calls on its run-in) marks its corridor as fighter-contested; the next try waits for a patrol commit there (item 4d), a scramble at the fighters seen, or a planned sweep ("search and destroy") from the nearest fighter base, timed ahead of it.
- **Go elsewhere:** the rotation moves on to sites in a quieter region (by the picture's fighter contacts or losses there) and comes back to the hot one later; goes with bug 35 (no immediate retry into what just killed the first flight) and the come-back (bug 46).
- **Not the lever** (John, 2026-10-05): tuning the SEAD flight's own fight (the 25 km commit). "Some jets are going to fly into a zone and kill other jets. It's DCS, not real life." The lever is not sending SEAD unsupported into a corridor full of enemy CAP.

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

**Status:** **MVP built and flown 2026-10-05** (John: "working, and is awesome"): Darkstar, Blue's AWACS, speaks its picture calls and immediate threat calls in a Windows voice through our own radio player. As built: `plan.md`, *Radio calls*. What's left of the item is the rest of the talking (more call types, AI pilots, callsigns, multiplayer), below. Pulled forward from its place in the order on 2026-10-05.

**Goal:** the air war can be followed by ear. The AWACS and AI pilots talk on the radio: "Darkstar, picture, two groups…", "Viper 2-1, airborne Rovaniemi, heading for the station", "Hornet 1-1, Magnum", each call phrased fresh rather than the same words every time (John, 2026-10-05: a kind of variety and immersion nothing in DCS has today).

**Long-term goal (John, 2026-09-30):** audio callouts only, with no on-screen text once it works.

### Decided (John, 2026-10-05)

- **Phrase bank, not an LLM, for now:** calls are put together from weighted, swappable phrases around the fixed technical facts, so they vary but always carry every fact. An LLM stays possible later as a second wording adapter (the API is billed apart from John's ChatGPT subscription, a few cents a session for wording; Codex signed in with the subscription is no way round that: OpenAI's terms forbid programmatic use outside the API, and each call would take seconds). A local LLM later on a stronger PC.
- **Windows voices, free:** Zira is Darkstar's one voice, so John can tell it apart once flights talk too. Cloud voices (Google, OpenAI) remain an option for more voices.
- **Darkstar:** the picture on the 2-min cycle of the on-screen list; **threat calls at once** (a hot contact inside 40 nm can't wait for the cycle). General picture calls to one player for now; per-jet BRAA for every player comes with multiplayer.
- **Blue only, one frequency** for now; split by role later (AWACS, strike, tower).
- **The on-screen text stays** for now; maybe removed later.
- **Wanted later, not yet:** AI jets announcing taxi, takeoff, approach, final and landing.
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
- **Cockpit-aware later, optional:** calls heard only when a radio is tuned to their frequency, at that radio's volume. SRS gets this from a script in DCS's export system (`Saved Games\DCS\Scripts\Export.lua`); ours would be our own code but would run inside DCS's export system: John's call when we get there.

### Steps

1. ~~**The radio player**~~ (built 2026-10-05; John tuned nothing: "sounds great").
2. ~~**Phrase-bank wording and Windows voices**~~ (built 2026-10-05; 100+ combinations per call; recent phrases made less likely, never barred, after John heard "that's all I have" too often).
3. ~~**The MVP in Kola:** Darkstar's picture and threat calls, the helper and player started by the mission~~ (built and flown 2026-10-05).
4. ~~**Bug 61:** bearings a few degrees off against the F10 map~~ (fixed 2026-10-05: DCS's magnetic is grid-based; stale tracks no longer called; `closed.md`).
5. **Player callsigns** from the slots, once John has them in the mission file.
6. **More Darkstar calls,** written for the ear like a real controller: new group / pop-up, faded, merged; a short summary when nothing changed instead of the full list every 2 min.
7. **Multiplayer:** each player's calls with BRAA from their own jet, sent to their radio player over ZeroTier (the player listening on the ZeroTier address too).
8. **AI flights talk:** airfield calls first (taxi, takeoff, approach, final, landing), then mission calls; a voice per flight (David, more Windows voices from Settings → Speech, or cloud voices), callsigns (the optional fun-callsigns item).
9. **Optional:** an LLM wording adapter to compare against the phrase bank.

### Open

- **The threat call's lateness:** up to one radar round (30 s) after a contact crosses 40 nm; fine, or faster?
- **Callsigns** for the AI flights, once they talk (`plan.md`, *Design*: callsign policy; the optional fun-callsigns item).
- Red's voice (Russian?) once Red talks; a split by frequency later.

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
