# Kola F-16 Random Tasking — Plan

> **What this is:** the spec and build state of the Kola F-16C mission generator. When the mission loads, a script rolls the battlefield (who holds which airfield), fills it with ground defenses, SAM networks and targets, plans both coalitions' air war for a ~6-hour window, and briefs human players on their taskings.
>
> **Where to look:** *Where we are* (pick up here) → *Backlog* → *Kola's map and scenario* → *Reference*. **How the code works** (*As built* by stage, *Architecture*, *DCS facts learned the hard way*, *Design, not built yet*, and every other section this file used to have) is in the shared mission framework's `shared_mission_framework\development_docs\as_built.md` since 2026-10-06, under the same names: a section named here or in `roadmap.md`, `bugs.md`, `closed.md` that isn't in this file is there. Features coming next, in John's order, are in the repository's one **`roadmap.md`** (at its root); bugs found in runs, to come back to, are in the repository's one **`bugs.md`** (at its root, every mission's and the framework's, since 2026-10-07); finished roadmap items (1–3, 5, 10–13, 16 and parts 4a / 4b so far) and fixed bugs move to the repository's one **`closed.md`** (at its root), keeping their numbers. Session-by-session history (run logs, before/after numbers) was cut on 2026-09-30; it's in git (`notes/kola_f16_generator_plan.md` in commits up to `4c49af9`).
>
> **Paths** are relative to this mission folder (`missions/kola_f16_random_tasking/`, one up from `development_docs/`, where this file lives; the roadmap, bugs and closed items are in the repository's one `roadmap.md`, `bugs.md` and `closed.md`, at its root, since 2026-10-07) unless they say otherwise. Kola runs on the shared mission framework (`shared_mission_framework\`: its Lua in `mission_scripts\`, the radio in `radio_calls\`, the map tools in `map_data_tools\`); Kola's own scripts in `kola_f16\` are its settings (`mission_settings.lua`), its map and scenario data, and its entry `init.lua`. Companion: the Syria mission (`missions/syria_a2g/notes.md`); no shared code.
>
> **Naming rule:** name things by what they are or what they do, in full words. No abbreviations in code names: `mobile_anti_aircraft_guns`, not `aaa_sp`; `shoulder_launched_missile_teams`, not `manpads_team`. Each name answers one question. Prose may still use common terms (AAA, SHORAD, MANPADS).
>
> **Direction: air denial** (since session 8, 2026-09-26). The air war was redesigned from air superiority to air denial, like Ukraine:
> - jets stay under their own SAM umbrella;
> - ground attack works the front;
> - losses should be rare and meaningful;
> - standoff weapons are coming.
>
> Flight structures, weapons, tactics and strategy change step by step, with the details decided with John as they come up.
>
> **Working rules:**
> - Commits are always done by John, on his own schedule; never ask about or perform a commit.
> - After any edit under `kola_f16\` or `shared_mission_framework\mission_scripts\`, copy that tree to `Saved Games\DCS\Scripts\kola_f16\` / `Saved Games\DCS\Scripts\shared_mission_framework\` immediately (not during a run John is flying). DCS is the only real test; the offline test harness (`shared_mission_framework\offline_test_harness\`: `python replay_and_compare.py kola`, `python rerun_data_tools.py kola`) comes first.
> - When zones are drawn or moved, John flies `khola_ground_zones.miz` once (see *Zones*).
> - **No wildcard deletes** (John, 2026-10-02): never `rm *` / `rm -rf *` or any delete by pattern. A delete names its exact path, so John can read in the command what goes. For scratch work, unpack into a new folder instead of emptying an old one.

---

## Where we are — pick up here  *(2026-10-05, late: the radio talks — Darkstar, AI pilots and airfields, on channels the jet tunes)*

> **Since 2026-10-06 Kola runs on the shared mission framework** (`shared_mission_framework\`; the split: its `development_docs\plan.md`, steps 0–6 done, each flown by John; next its step 7, the Caucasus random tasking). Kola's behaviour didn't change in the split: an offline test harness compared every step with recorded runs. **Kola bug fixes can go in again;** a fix that changes behaviour means re-recording the harness baselines right after it (framework `plan.md`, *Picking this up*). How the code works: `shared_mission_framework\development_docs\as_built.md`.

**Status:** the whole pipeline runs in DCS and the mission is playable by one human player.
- **Stage 1:** territory roll, 37 airfields.
- **Stage 2:** base defenses (trimmed for performance on 2026-10-01: no security infantry, one towed-gun group and one MANPADS team per base).
- **Stage 3:** SAM networks (127 surveyed zones), fixed ground targets, and the target catalog.
- **Stage 4:** one Red supply convoy.
- **Airspace map:** own / contested / enemy, with regions and pockets.
- **Air tasking for both coalitions:** a standing SEAD rotation against the enemy air defenses; front-only strike, airfield strike and DEAD (deeper where the way is cleared), each launching only once the SAM sites it needs are out of the fight (else one more SEAD, then cancelled); front CAP stations with commit circles; one AWACS each (see *Stages 5–6*).
- **SEAD against the air defenses** (roadmap item 12, built 2026-10-02 session 15, flown in the 14:55–17:48 runs the same day; *Stages 5–6*, SEAD): one kind of SEAD flight, a mission against one site; `requires_cleared` the only link, a site table (one SEAD flight per site); a standing 2-ship rotation per coalition down an outside-in order of the enemy sites, back to back for the whole window; extra SEAD only when an attack's route needs a site the table doesn't have; a waiting flight starts 10 min after the salvo, not the landing; packages and "escort" gone. On the 10:38 roll: SEAD flights Red 0–4 → 9, Blue 0–2 → 10–11.
- **SEAD doctrine: under the radar** (roadmap item 10, built 2026-10-01, reworked 2026-10-02 session 16: bugs 33, 36, 39, 40, 41; *Stages 5–6*, SEAD): one SAM site per 2-ship; cruise, down to 900 ft above the ground before the first enemy ring (from a base close to its target: low from takeoff), low and fast around the other sites' low-altitude reach, pop up on afterburner 8 km before a launch point 45 km from the site (a short-reaching site: its reach + 15 km), to 2,400 m (~8,000 ft) at a `popup_top` waypoint 3 km on; from the top an `EngageGroup` fires every anti-radiation missile the moment the site's radar is seen; with no ping yet it presses on along the same track up to 20 km closer (`press_on`), then home with `no shot`. Go cold: as the last missile leaves, or 20 s after one jet is empty (`salvo over`). While it has missiles it fights a bandit only when fired upon, or inside 25 km outside its shot area (`press on` otherwise). **First radar kills of the new profile, 17:48 run:** the Sodankylä SA-10's search and tracking radars, the Kuusamo SA-11's search radar.
- **Players:** F-16C dynamic-spawn slots, two human taskings per roll, frag (3 min) and steerpoints (5 min, target and aim points with ground elevation, no egress) in the comms menu, `Hide text`, a popup for every static object a player destroys.
- **Radar picture, scrambles and the leash, event log** (roadmap items 1–3, done; `closed.md`). Scrambles are refused when they can't arrive in time, spawn only on ramp spots held for alert jets, and a jet stood down on the ramp goes back on alert.
- **Airborne cap:** 12 AI aircraft per coalition (players never count), 2 of it kept for scrambles.
- **The controller** (session 13, `consumers/control_air_flights/`, *The controller*): every run-time decision about AI flights in one place (launches in sequence, scrambles and alert jets, the cap, the leash, go cold, and the bandit call: an attack flight is told the moment a fighter comes hot within 100 km, and commits if it has radar missiles or goes home if not; a SEAD flight with missiles aboard only when fired upon or inside 25 km), one event word `CONTROL`. Its kill zones include the enemy airfields' Tors and Pantsirs since 2026-10-02 (bug 41, not flown). All of it has flown (22:23 and 00:57 runs); items 4a / 4b and 11 are in `closed.md`.
- **Red's attack jets carry R-77s** (2026-10-01): every Su-34 loadout has 2× R-77 (*Stages 5–6*, Loadouts).
- **Kill zones depend on height above the ground** (`lib/sam_reach.lua`): the low-altitude reach up to 300 m, the full ring from 3,000 m (bug 27, fixed 2026-10-02: was 3,000 / 7,000 m above sea level; at the 00:57 run's pop-ups the sites reached nearly their full envelope); no AI flight launches from a base inside an enemy SAM's low-altitude kill zone. The SEAD launch point stays cleared of the other sites' low reach only; the pop-up and the press-on leg are accepted exposure: go cold and a fight's break-off ignore every ring there while missiles are aboard. Outside it a SEAD flight's fight is broken off for any kill zone at its height, its own target's included. Enemy airfield Tors / Pantsirs / Rolands count at 85 % of their full reach at any height (bug 41, 2026-10-02, not flown).
- **Air picture for players** (roadmap item 5, built 2026-10-02, flown in the 00:57 run; `closed.md`): every 2 min, for 14 s, each player gets their coalition's radar picture as a BRAA list from their own position (magnetic), highest threat first (*Air picture calls*).
- **The radio** (roadmap item 7; *Radio calls*): Darkstar's picture and threat calls (MVP, flown 2026-10-05), and since 2026-10-05 late the AI pilots too: every AI flight has a callsign for the whole mission; flights check in and out with Darkstar and make their mission calls (pushing, Fox, Magnum, Splash, defending, off target) from what they actually do (a watcher beside the controller); AI traffic at Blue fields calls taxi, departing, inbound, final and clear on the field's tower frequency. Channels: AWACS UHF 262.000, mission VHF 140.000, each field its tower VHF; our export script reads the F-16's two radios (one line in `Export.lua`, as SRS does), so a call is heard only when tuned. Spoken in Windows voices (Darkstar Zira; pilots David and Mark variants) by our own player and helper in `radio_calls/`, which the mission starts itself. John's first test, 2026-10-05 late: "insanely cool so far, probably needs a few fixes". Since 2026-10-05 night Darkstar also gives the AI flights the controller's orders (engage, resume, RTB, land, a scramble's vector), from a listener of the controller's decisions; flown 2026-10-06 00:16. Since 2026-10-06 the pilots answer them once the flight is seen following the order (no answer when it isn't), and a decision only the pilot could make (bingo, Magnum complete, no emitter, Winchester) is the pilot's report with Darkstar's "copy" (step 15; not flown). Bearings grid-based magnetic as the F-16 shows them, stale tracks no longer called (bug 61, fixed 2026-10-05).
- **The player's HSD** (bug 25, confirmed in Kola 2026-10-02): friendly AI flights show as datalink contacts and the medium and long-range SAM rings show (the recipe: *DCS facts learned the hard way*). The AWACS's enemy tracks reach it too, as yellow (unknown) contacts (bug 26, closed after the test mission, 2026-10-02).
- **SEAD retuned after the 00:57 run** (2026-10-02; bugs 27, 28, 30; its launch point and pop-up numbers were changed again since, see the doctrine line above): go cold the moment the last anti-radiation missile leaves; attack tasks hold the planned altitude (the AI flew its attacks low); the bandit call keeps a fighter that just fired at the flight.
- **Bug round 2026-10-02 (session 15, not flown; each fix in `closed.md`, the guards for 6 and 13 in `bugs.md`):**
  - **Scrambles:** every base with a fitting runway is an alert base (16); no tail chases (16); the intercept point stays 10 km outside the leash's line (8); a refusal names the nearest base's reason (23).
  - **SEAD:** a short-reaching target gets a closer launch point, its reach + 15 km (29); a "no shot" line; SEAD routes keep 5 km outside short-range SAM rings (22).
  - **Controller:** patrol handover when the relief is on station (18); a new landing order for a jet lost on its way home, and packages stop waiting on an overdue SEAD flight (19).
  - **Guards:** an unarmed jet is removed on the ramp (6); a jet lost on the ramp is a `RAMP_LOSS` line (13).
- **Red flight numbers** (bug 21, 2026-10-02): Red flights are `MSN7001+`, Red scrambles `MSN7901+` (were 5001+ / 5901+; older logs and run notes use those). Blue unchanged.
- **Performance in VR, first pass** (closed for now, `closed.md`): John's terrain settings got Kola back to 45 fps; short-reach base defenses sleep until an enemy aircraft is within 30 km (*Sleeping ground units*).

**Last DCS runs:**
- **Session 11, first radar picture + scramble run, ~48 min, watched:** scrambles worked; losses high (Blue 4, Red 8) → roadmap item 4.
- **2026-09-30, two event-log runs** (`event_logs\2026-09-30_201105.log`; `2026-09-30_213757.log`, John flying MSN2023_OCA, losses Blue 5 / Red 11) → `bugs.md` 1–12 and roadmap 4c.
- **2026-10-01, 11:24 run (2D, 35 min, no player):** sleeping, waking and the cap worked; a woken base fighting still unseen. Found bugs 13 (Su-34s blowing up on Afrikanda's small spots) and 14 (the cap counted human flights).
- **2026-10-01, 13:07 run:** the first SEAD salvo worked as built (MSN2025: 8 HARMs from 89–92 km, then cold) but the Sodankylä SA-10 shot all 8 down → launch point moved from 80 to 40 km. MSN5026 was sent home 15 s after takeoff by the old kill-zone test and flew out to its target before turning → altitude-aware kill zones and turning around on the spot (bug 15).
- **2026-10-01, 13:49 run** (`event_logs\2026-10-01_134933.log`): found bugs 16 (a scramble from the wrong base, a tail chase) and 17 (an AI DEAD behind a player SEAD nobody flew; fixed).
- **2026-10-01, 14:14 run (67 min, no player; `event_logs\2026-10-01_141412.log`):** losses Blue 2 / Red 0; on the ground the Sodankylä SA-10 lost both search radars.
  - **SEAD:** every SEAD flight ran in low (~2,500–3,000 ft) instead of at 30,000 ft, then popped up. MSN2024 (2× F-16) died to the SA-10 before firing; its repeat, MSN2024_SEAD_AGAIN, fired 8 HARMs from 35–41 km at 16–18k ft, killed both search radars, and the SA-10 never fired → John: low ingress and pop-up becomes the SEAD doctrine (backlog, *SEAD follow-ups*). Red's MSN5024 fired 8 Kh-31P at the Rovaniemi Patriot from 40–42 km at ~8,000 ft; the Patriot shot all of them down (12 MIM-104). MSN5025 never fired at the Alakurtti IRIS-T (3,000 ft, cold 15 km past its launch point).
  - **Worked:** `RETRY` / `_AGAIN`, `DELAYED`, every go-cold reason, scrambles refused when they can't arrive (bug 1), jets back on alert after a ramp stand-down (bug 2).
  - **Found:** bug 18 (patrol handover overlap), 19 (a wingman missed its landing and flew straight on for 300 km, holding up MSN5023_OCA), 20 (go-cold timer from the planned time sent the late MSN5026 home before it attacked). Six Su-34s spawned at Vuojärvi together took off between 06:06 and 06:30 (John: taxi times are DCS; only limited planning around it). Bug 3's churn seen again (accepted for now). Red planned 3 of 5 missions, Blue 4 of 6; most unplanned ones: "no suppression flight in reach" (no clear launch point).
  - **Not a bug:** Red's MiG-31 patrol didn't go after the SEAD flights working under the Rovaniemi Patriot's kill zone, low on fuel (John: realistic; a pop shot from the edge of the ring is an idea for roadmap item 4).
- **2026-10-01, 16:21 run (33 min, no player; `event_logs\2026-10-01_162135.log`):** first run with the controller (self-defence; before item 11). Loaded and ran cleanly; no armed attack flight was threatened, so no fight yet. MSN5023_OCA (2× Su-24M, RBK-250 only) died to the Kuusamo SA-8 and the F-16 patrol MSN2016_CAP; Blue first saw it only 26 km from Kuusamo (its E-3A not yet on station); no scramble, "covered by patrol" (right). Led to roadmap item 11 (built), the abort directive for defenceless flights and radar-missiles-only self-defence (roadmap item 4), bug 21 (Red MSN7xxx).

- **2026-10-01, 20:31 run (35 min, no player; `event_logs\2026-10-01_203147.log`):** losses Blue 0 / Red 3. The first `defend` in DCS came too late: Blue's F-15C patrol MSN2002_CAP fired an AIM-120C at MSN5024_SEAD (2× Su-34, R-27R) from 47 km; the controller only called `defend` at 19 km, a second after the lead was hit; both died → the bandit call and R-77s for the Su-34 (both built the same evening). MSN5009_CAP_1 (Su-27, Afrikanda spot 37, terminal 104) destroyed 8 s after spawning, no killer, at field height: bug 13 again, with another type on an open-air spot. No `wait` / `retry` / `cancel` / `launch late` yet. Frame spikes at T+21:06, 21:14, 26:21, 32:01 and 33:24 (John's FPS overlay `T:` = seconds since mission start): nothing of ours near any of them in the event log; `dcs.log` only shows DCS's own long-frame warnings (most suppressed as duplicates) and a 120 ms terrain cleanup at another moment.

- **2026-10-02, Caucasus datalink test** (not Kola; `Saved Games\DCS\Missions\datalink_hsd_test.miz`, built by script, John flew it): editor-placed AI and a script F-16 pair with EPLRS + STNs showed on the HSD, a script pair spawned like Kola's did not; a script SA-11 with `hiddenOnMFD = false` showed its ring, an editor-placed one (empty DTC) did not; the E-3A showed but none of its enemy tracks → bug 25 (fixed), bug 26 (open). Details: `closed.md`, bug 25.
- **2026-10-01, 21:30 run** (`event_logs\2026-10-01_213052.log`, with the bandit call and the Su-34 R-77s, before item 10): Blue planned 1 of 6 AI attack missions (MSN2025_OCA, a route crossing no ring) and no SEAD flight; every other mission "no suppression flight in reach". Cause: no Red medium / long-range site but one had a SEAD launch point clear of the others' full rings (Kola's sites cover each other) → item 10 built the same evening; re-planning this roll with it gave Red 3–6 missions (was 3) but Blue still 0 SEAD flights, its targets behind sites blocked even at low level → roadmap item 12 (rolling back outside-in), top priority.

- **2026-10-01, 22:23 run** (`event_logs\2026-10-01_222355.log`, 50 min, John flying MSN2024_DEAD; the first run with the bandit call, the Su-34 R-77s and the low SEAD profile): losses Blue 1 (the player) / Red 2.
  - **The bandit call worked:** MSN2025_SEAD (2× F/A-18C, low on its run-in) called `defend` the moment Blue's picture first held the MiG-31 patrol MSN5009_CAP (34 km, hot); the MiG's R-33s missed, the Hornets' AIM-120Cs from 25 km killed it, `back on mission` 45 s later.
  - **Blue's low SEAD worked as designed:** low leg ~1,500–1,900 ft (about 900 ft above the ground there; not checked against terrain), pop-up, 8 HARMs from 38–45 km, `go cold` on the last missile, out low, landed. The Kuusamo SA-11 lost its search radar, its command post was badly hit, and it never fired.
  - **Red's low SEAD flew the profile but achieved nothing:** 8 Kh-31P at the Banak IRIS-T from 41 km at ~9,400 ft; the IRIS-T fired 8 and lost nothing (with the 14:14 Patriot: 0 of 16 Kh-31P through). The low leg was ~30 s: the descent from 26,000 ft wasn't finished before the pop-up. On the climb-out an SA-8 the routing doesn't see shot down MSN5024_SEAD_1 → bug 22.
  - **Found:** bugs 22 (short-range SAMs on the low way out), 23 (a scramble refusal names the wrong base's reason), 24 (the player under two names). Bug 3's churn once more (a Su-27 scrambled at MSN2025 as it turned home; stood down on the ramp).
  - **Not seen yet:** `wait`, `retry`, `launch late`, `leave`; no base woke. Blue again planned few attack missions (4 AI packages, SEAD against only 3 sites) → the SEAD planning rework (John: "SEAD flights are the primary mission to open up everything else").

- **2026-10-02, 00:57 run** (`event_logs\2026-10-02_005718.log`, 66 min, John flying MSN2023_DEAD; the first with the datalink fix and the air picture calls): losses Blue 5 / Red 6; `dcs.log` clean.
  - **SEAD:** every SEAD jet that reached its target died (bug 27): the Alakurtti SA-11 fired at MSN2024 at 39 km at 10,500 ft, the Rovaniemi Patriot at MSN5025 at 50 km at 8,300 ft, the Kittilä SA-10 at MSN5024 at 46 km at ~3,000 ft. Results: the SA-11's search radar (HARM) and the SA-10's 40B6M tracking radar (Kh-31P). MSN5031's Su-34s died to the scramble MSN2904 (AIM-120s from 47–49 km at 36,000 ft).
  - **Strike:** MSN2027 (2× F/A-18) flew at 2,400–3,600 ft though planned at 7,500 m and died to the Sodankylä SA-8 (bug 28: attack tasks carried no altitude).
  - **Retry:** the first `retry` in DCS: MSN2026_SEAD_AGAIN flew John's unflown SEAD on the Vuojärvi Tor, fired nothing and landed (bug 29).
  - **Bandit call:** worked but let go of the F-15C that had fired at MSN5024 after 4 s (bug 30); the Su-34's R-77 killed the F-15C anyway.
  - **Player:** the SA-11's radar was dead before John arrived (`TARGET` 1 of 1 at 04:27); he hit a launcher and a Ural with GBU-38s; the Vuojärvi Tor M2 fired at him from 16 km and missed.
  - **Air picture:** calls every 2 min looked right; magvar works in the game (+12.4° at Rovaniemi, table +11.9°). John: 7 s too short, now 14 s.
  - **HSD:** still no rings or friendly contacts (bug 25 reopened; fixed for the 10:38 run).
  - **Seen again:** bug 3 (three scrambles at Red patrols), a wingman taking off 4 min late; Sodankylä `CHECK` (close passes, no shot; bug 5).

- **2026-10-02, 14:55 and 16:03 runs** (`event_logs\2026-10-02_145532.log`, `…_160358.log`; the first with roadmap item 12): both rotations opened on the other's long-range site. 14:55: salvoes from 44–61 km, the SA-10 and the Patriot shot everything down, 8 SEAD airframes lost in 15 min → bugs 33–35 (34 removed: John, one salvo gets through from close in). 16:03, with bug 33's 6,000 ft pop-up: **no anti-radiation missile fired all run** → bugs 36 (no radar ping at the launch point), 38 (the AWACS blind until on station), 39 (a fight at the pop-up).
- **2026-10-02, 16:50 run** (`…_165055.log`, 22 min, watched by Claude; bug 36's press-on and 2,400 m pop-up): the F-16s passed their launch point at 2,825 ft (DCS spreads a climb over the leg) and the Koshka Yavr SA-10 killed both before a shot; a fight climbed Red's Su-34s into the Patriot they were sent against → bug 40, the `popup_top` waypoint and the SEAD break-off rule.
- **2026-10-02, 17:15 run** (`…_171553.log`, ~25 min, watched by Claude): **the first full salvo since bug 36** (MSN2024, 8 HARMs at the Sodankylä SA-10 from 39–47 km at 6,100–8,900 ft), all shot down; the wingman fired one at a time for 76 s and died; fights cost 6 SEAD jets and sent one SEAD flight home 82 s after takeoff; the AWACS saw contacts 12 min before its station (bug 38 fixed) → `press on` and `salvo over` (bugs 39, 40).
- **2026-10-02, 17:48 run** (`…_174852.log`, 18 min, watched by Claude and John): **SEAD works.** `press on` twice (bandits at 46 and 92 km; the flights stayed low and flew their attacks). MSN2024 (2× F-16) reached `TOP` at 7,404 ft, 8 HARMs within 13 s from 45–48 km: the **Sodankylä SA-10's 64H6E search and 40B6M tracking radars destroyed**, its command post, second search radar and two launchers hit. MSN2025 (2× F-16): 3 HARMs at 46 km, a fight when fired upon (killed the Su-27), 5 more at 37 km: **the Kuusamo SA-11's search radar destroyed**, its command post and launchers hit. Red's MSN7023: 8 Kh-31P within 24 s from 43–49 km at 1,500–3,300 ft; the Rovaniemi SA-10 shot all down with 12 interceptors (0 of 24 Kh-31P through against SA-10s / Patriots so far) → their first-ping attack moved to the pop-up top. Losses after the shots: 3 of 4 Blue SEAD jets (the SA-10, the SA-11, and the Vuojärvi base Tor during a fight → bug 41). John: some losses are unavoidable; the SEAD flights now do what was intended.
- **2026-10-02, 10:38 run** (`event_logs\2026-10-02_103843.log`, ~9 min, John at Rovaniemi; an HSD check, with the SEAD retune in but no SEAD flown yet): **threat rings and friendly datalink contacts showed on the HSD** (bug 25 fixed: the editor's EPLRS-on-waypoint-1 recipe, Red SAMs as Russia, slots as CJTF Blue; `closed.md`). The player still logs under two names: unit `f16_human_1_3` (`PLAYER_IN`, `TAKEOFF`, `POSITION`) and group `f16_rovaniemi` (`PICTURE_CALL`, and in longer runs the radar picture and `CONTROL` lines). John is renaming each slot's pilot to start with its group name (`f16_rovaniemi_1`), so grepping the group name finds both; check it in the next log, then note it under bug 24 in `closed.md`. "New callsign" in `PLAYER_IN` is John's DCS Logbook pilot name, not the mission's.

- **2026-10-02, 19:29 run** (`event_logs\2026-10-02_192901.log`, 55 min, John flying MSN2023_SEAD from Ivalo on the Afrikanda SA-6; reviewed in session 18): losses Blue 1 (John) / Red 4.
  - **SEAD:** Blue's two SEAD flights each destroyed an SA-11 search radar (MSN2026 on Koshka Yavr #2: `RADAR_WARNING` "not seen" at the launch point, "SEEN" at the press-on point, 4 HARMs from 33 km; MSN2025 on Banak: 7 HARMs from 41–45 km); Red fired 8 Kh-31P from the pop-up top (~7,800 ft, 44–48 km) at the Ivalo SA-11, all shot down (0 of 32 so far). `press on` ×6, `salvo over`, the rotation's retry and `launch late` all ran. In 3 of 4 salvoes only the lead fired (to log).
  - **Wingmen orphaned after their lead landed** in all 4 two-ship SEAD flights (bug 19 again; fixed the same evening: `closed.md`).
  - **John:** killed the Su-27 scramble MSN7901 (AIM-120s from 32 km), two SA-6 launchers with GBU-38s; shot down by the MiG-31 scramble MSN7903 (R-40R from 2 km, 863 ft). **Blue's picture never held either scramble:** its E-3A orbited 460–550 km away off Bodø (the old 200 km-from-every-enemy-base rule) and Darkstar read "clean" → the AWACS placement and the coverage call (bug 42, `closed.md`); no enemy contact on his HSD at 120 / 240 nm either (bug 26, test mission built).
  - **Also:** bug 24 confirmed (every line `f16_ivalo`); bug 4 again (Kh-29T at the Ivalo Roland from 7–9 km; fixed the same evening); the E-3A spawns with no callsign, so DCS's own AWACS voice calls fail ("Callname -1 not found", 15× in `dcs.log`).

- **2026-10-04, 22:39 run** (`event_logs\2026-10-04_223922.log`, 2 h 09 min, John flying MSN2024_DEAD from Kemi-Tornio, then f16_kiruna; reviewed 2026-10-05): losses Blue 7 / Red 12.
  - **Worked:** bugs 44, 45 and 46 (no fight timed out with a missile in the air; ~8 `salvo away, staying on its way home`; the Monchegorsk SA-10's `come back` and `_LATER`). Red's Kh-31Ps got through for the first time: MSN7023_SEAD_AGAIN destroyed both Hosio Patriot search / track radars, the ECS and the EPP. Blue SEAD destroyed the search radars of the Kuusamo SA-11 (a DEAD then took it, 4 of 5), Ivalo SA-11 #1 and #3, and the Rovaniemi SA-10's 64H6E. John found the JSOW (bug 51) and hit the Kuusamo SA-8 with 4, then killed a Su-30, a Su-34 and a Su-27 with AIM-120s.
  - **Found:** bugs 52 (wingmen orphaned in 9 of 11 two-ships), 53 (the controller looked at the lead only; a strike wingman died inside an SA-11 ring), 54 (no come-back for a site the rotation needs that a non-rotation flight takes), 55 (wording); bug 49 again (two Su-34 SEAD flights on Hosio's Roland, no shot); bug 13 twice at Afrikanda spot 22; bug 50's ranges up to 536 km; bug 3's churn at Alakurtti's patrols.

- **2026-10-05, 10:31 run** (`event_logs\2026-10-05_103126.log`, 1 h 46 min; John spawned at Kallax and didn't fly): losses Blue 9 / Red 8.
  - **Worked:** `come back` / `_LATER` on both sides; bug 52's per-jet landing order (2 of 4 possibly orphaned wingmen landed, 2 circled near their base and were removed; 9 of 11 orphaned the run before); the Kh-59M standoff strike on the Kirkenes command post (1 of 4); MSN2024's HARMs killed the Alakurtti SA-6's radar, MSN2029's the Koshka Yavr SA-11 #2 search radar; one Kh-31P killed a Rovaniemi SA-10 search radar.
  - **Found and fixed the same day (not flown):** bugs 57 (a SEAD retry 1 s after the first flight was down, its HARMs still in the air), 58 (Red SEAD went cold 10 s into its salvo), 59 (the E-3A too far forward, six Red scrambles at it), 60 (a MiG-31 patrol ran out of fuel: the controller's fuel watch).
  - **Roadmap item 16** (new; closed 2026-10-05, not needed, John: "we have it on the radio now"): three Blue tries at the Koshka Yavr SA-10 cost 6 Hornets and no radar, half of them to Red fighters in the Kirkenes corridor.
  - **Anti-radiation missiles so far** (every log from 2026-10-02 on, units destroyed / missiles fired): HARM vs SA-10 6 / 98, vs SA-11 14 / 75; Kh-31P vs SA-10 2 / 21, vs SA-11 4 / 32, vs Patriot 8 / 63, vs NASAMS and IRIS-T 1 / 20. Per missile the Kh-31P does as well as the HARM against the same system; Red's targets are the harder ones (*Still to watch*).
  - Also bug 24: the Kallax slot logs as `f16_human_1_1`.

- **2026-10-06, 00:16 run** (`event_logs\2026-10-06_001615.log`, 66 min, John flying MSN2023_OCA from Ivalo on the Kalevala parked aircraft; the first with Darkstar's orders): losses Blue 5 / Red 4.
  - **Worked:** Darkstar's orders, each matching its `CONTROL` line (2 engage, 1 resume, 5 RTB, a scramble's vector 4 s after its airborne call), heard in a sensible order with the pilots' calls; bugs 52, 53, 57, 58, 59, 60 as built; Red's SEAD destroyed the Kirkenes Hawk's search and tracking radars and the Ivalo IRIS-T's radar. John killed the Su-30 MSN7016_CAP with AIM-120s from 55–19 km and hit the Mi-8 static and two ZU-23s with GBU-38s.
  - **Found:** bugs 62–71 (`bugs.md`); bug 3's churn again (6 of 7 scrambles). The Koshka Yavr SA-10, Blue's first rotation site, killed 3 F-16s and shot down all 7 HARMs (it fires from 45–49 km at ~3,500 ft, the launch point; bug 40's suspect 2), John: no change now.

**Next (2026-10-06, after the 00:16 run):** built today, copied to DCS, not flown: bugs 62, 64–68, 70, 71 and bug 3's longer inbound count over enemy airspace; bug 69's logging; bug 63 parked (John: option (a), a recovery time before the go cold after a SAM break-off, when SEAD is opened up again; no SEAD changes now); the pilots' reports and answers to Darkstar (roadmap item 7 step 15, *Radio calls*). Check: `RADIO_CALL … answer` after each order and matching what the flight did, `no answer` lines against the flight's track, `report` for bingo / salvo with no Darkstar `return_to_base` for it, no `check_out` after an answer or report (step 15); `on_station` after the station `WAYPOINT`, `handover` only after the relief's (62); `LINE_UP` then `departing` before `TAKEOFF` (67); `>>orphan<< removed: … still flying away` (68); `IMPACT` lines and `life now` on `HIT` lines (71); fewer stood-down scrambles (3). After the flight: `radio_player.log` and `dcs.log` `first reading` for the volume knobs (69), and whether jet-down calls were heard or `dropped` (70).

**Next (2026-10-05, after the 10:31 run):** bugs 57–60 built, copied to DCS, not flown. Check: `wait: … looking at it again at … before a second try` and what follows (57); no SEAD salvo cut by `… km past its launch point` mid-salvo (58); `dcs.log` "sees n % of the fight" for each AWACS, a second Blue E-3A, no scrambles `after MSN2001_AEW` (59); `bingo` lines, and no patrol lost with "no killer recorded" (60). Still to see from before: bug 53 (a wingman named in a break-off), bug 49 (DEAD from out of reach).

**Next (2026-10-05, morning):** built today, none flown, all copied to DCS, all in `closed.md` (John closed them before a run; bug 51 too): bugs 48, 49 (DEAD from out of reach instead of SEAD on a target whose radar can't see the press-on point), 52, 53, 54, 55. John flies Kola again. Check: `>>orphan<<` endings and `land: … still in the air` (bug 52); `breaking off:` / `go cold:` / `leash home:` lines naming a wingman (bug 53); `come back` for a site a non-rotation flight takes (bug 54); in `dcs.log` `DEAD from out of its reach`, and that DEAD's `SHOT` (Kh-59M range) and the waiting attack (bug 49); `landed` / `down` in leash lines (bug 55); where both AWACS orbit (`dcs.log`: "… km inside the map's edge", bug 47, also built 2026-10-05).

**Also 2026-10-05: Darkstar speaks (roadmap item 7 MVP; *Radio calls*).** Flown the same afternoon, John on the ramp: "working, and is awesome". Found: bug 61 (bearings a few degrees off against the F10 map; parked, its `dcs.log` check line on), and "that's all I have" far too often (the repeat avoidance flattened the weights; fixed, not heard yet). Still to see: a threat call (`PICTURE_CALL.*threat`) and how late it comes; whether the start-up `os.execute` causes any stutter. Next steps: `roadmap.md`, item 7.

**Radio calls, next iteration built 2026-10-05 late** (roadmap item 7, steps 5–9; *Radio calls*): callsigns for every AI flight, a reworked queue, channels with real frequencies, our export script reading the F-16's radios (one line in `Export.lua`, added by the radio player: **restart DCS once**), AI flights' mission calls from a watcher beside the controller, airfield traffic calls. Harness-tested, copied to DCS, not flown.

**Bug 61 closed 2026-10-05 evening** (`event_logs\2026-10-05_185934.log`, John's test flight on HUD 050 from Kallax): DCS's magnetic is grid minus variation, so Darkstar's bearings were off by the grid's convergence. Fixed (grid-based bearings, tracks and airfield brief; the true age; stale tracks not called; the DEBUG and bearing-check lines removed), copied to DCS, not flown; `closed.md`. Check in the next run: Darkstar's bearings against the HSD east of Rovaniemi, and no call of a contact that's gone.

**Next (2026-10-02 late, after session 18):** built in session 18, none flown: the orphaned-wingman removal (`>>orphan<<`, bug 19), DEAD from out of a short-range site's reach (Kh-59M / JSOW, bug 4), the AWACS placed where its coalition fights and Darkstar's "no radar coverage your area" (bug 42), contact ranges in `CONTACT` lines.
1. ~~John flies `awacs_hsd_test.miz`~~ (done 2026-10-02: the AWACS's tracks reach the HSD with Kola's spawn as it is, as yellow / unknown; bug 26 closed, `closed.md`).
2. **John flies Kola again.** Check: `>>orphan<<` lines (how many possibly orphaned, how they ended); Red DEAD on short-range sites with Kh-59M from ~40 km (`SHOT` ranges, losses) and Blue's JSOW release ranges; DEAD `TARGET` lines now counting launchers and command posts, and `cancel: not needed … already destroyed`; where the AWACS orbits (`dcs.log`: "sees n % of the fight") and Darkstar's coverage line where Blue has no radar; `CONTACT … seen by awacs … km away` to tune the 250 km coverage figure. Still to see from before: `breaking off`, `go cold` or `leash home` naming a `DEF_` group (bug 41); a SEAD flight against a base Tor or Pantsir firing at all.
3. **Docs, John's call:** bugs 38 (AWACS from takeoff, confirmed) and 40 (pop-up top, salvo, confirmed) to `closed.md`; ~~roadmap item 12 to `closed.md`~~ (done 2026-10-05, John: "item 12 is fine").
4. **Open SEAD bugs:** 35 (an immediate retry into the site that just shot the first flight down; parked by John), 39's second half (a flight that fought past its launch point isn't sent back for its shot), 36's open question (the 17:15 run suggests the AI does see SA-10s on its warning receivers; close it if the next run agrees).
5. ~~DEAD success~~ (built 2026-10-03, not flown: a DEAD counts radars, command post and launchers at 75 %, and isn't sent when its site already meets that; *Stage 3c*). Only the lead fired in 3 of 4 salvoes of the 19:29 run: John wants SEAD left alone now; logged as an optional roadmap item, the wingman flying Wild Weasel.
6. Then the rest of roadmap item 4 (AI behaviour logic).

**Still to watch in runs:**
- **Red SEAD against modern Blue SAMs** (2026-10-05): Kh-31Ps do as well per missile as HARMs on the same system, but Red's rotation opens on the hardest targets (most coverage first: Blue's SA-10, Patriot, IRIS-T, NASAMS), and those shoot anti-radiation missiles down well in DCS (the Kirkenes NASAMS fired 12 AIM-120s at one 8-missile salvo and stopped all 8). If Red SEAD keeps achieving little: two flights at once on one site (John said no on 2026-10-02 for SA-10s), or the rotation taking softer sites first.
- **The AWACS and low flyers** (bug 26's test, 2026-10-02): the E-3A never saw a Su-25T at ~2,000 ft 80 km away, but saw a MiG-29S at 25,000 ft at 162 km. Grep `CONTACT.*seen by awacs` for the "km away" and the contact's height; if low flyers are only seen close in, give Darkstar's coverage call (`AIR_PICTURE_CALLS.coverage`) a shorter AWACS reach for low threats, or say "coverage high only".
- **HSD threat limit:** a forum report says the F-16's HSD shows ~16 threats at most since the 12 May 2026 update; Red fields ~11 medium / long-range sites per roll. If rings are missing on a roll with more, that's why.
- **SEAD (the low profile, reworked 2026-10-02):** whether the AI holds ~900 ft above the ground on the low legs (`POSITION`), above all over the Khibiny and the fells; the height at `TOP` (DCS counts waypoints reached early: 3,682–7,404 ft so far, planned 7,874); `SHOT` ranges (45–48 km at the launch point, closer on the press-on leg) and how many missiles the site shoots down; whether SA-10s and Patriots fall to one tight salvo again (one of two so far); fuel on the long low legs (planned at 1.5× per km).
- **The `expend` limits:** whether the AI honours one salvo (`AttackGroup`, expend All, one attack).
- **Gun groups firing:** a woken base fights (2026-10-04, `event_logs\2026-10-04_200249.log`: Kuusamo's Igla-S team woke and shot John down; bug 5 closed, `closed.md`), but no `GUNS` line has ever appeared. If a run has a jet low over a woken base's guns and still no `GUNS` / `SHOT` from them, reopen it.
- **Lone F-15E crash:** an F-15E of a Banak DEAD crashed alone in Blue airspace ~30 min after bombing (1,237 ft, no hit recorded). Watch for a repeat.
- **Endurance:** does the AWACS stay on station the whole 6 hours (A-50 fuel)?
- **F-16 SEAD fuel:** the 4-HARM loadout has only the centerline tank; the planner still uses a 550 km reach.
- **MiG-29S:** left out of the Red rosters, because its loadouts carry CLSIDs `aircraft_pylons.lua` doesn't know.
- **Wingmen taking off late:** MSN5026_SEAD_2 took off 6 min after its lead (DCS taxi queue?).
- **Scramble trigger misses dog-legs** (session 11, not changed): "inbound" follows the current heading, so a raid on a leg around SAM rings reads as heading elsewhere. Possible addition: a contact in contested airspace within a few minutes' flight of any own asset counts, whatever its heading.

**Reading a run:** the story is in the event log (`event_logs\<date>_<time>.log` in this folder, git-ignored, one per run; see *Event log*). Grep a unit or flight name for its whole life, or an event word:

| Grep the event log | Shows |
|---|---|
| a name (`MSN2025_DEAD`, `MSN2025_DEAD_2`, `SAM_OLEN_SA11_1`) | everything it did and everything done to it |
| `SPAWNED`, `LOADOUT`, `TAKEOFF`, `WAYPOINT`, `LAND` | each flight's life: spawn, what each jet carries, each waypoint reached (ingress = pushing; target with TOT late / early), landing |
| `POSITION` | every airborne aircraft each minute: type, speed, heading, fuel, altitude, airspace, nearest enemy ring, km from station |
| `SHOT`, `GUNS`, `HIT` | weapons fired (with target and range when DCS knows it), guns opening up, hits (with the life left a second later, `life now 92 %`); repeats folded into one line |
| `IMPACT` | where a bomb or air-to-ground missile from an aircraft came down (grid reference as the F10 map), the objects within 150 m with their life before → after (or destroyed), or "gone in the air" (bug 71) |
| `LINE_UP` | an AI jet at a Blue field lined up on a runway (its departing call is said then; bug 67) |
| `DESTROYED`, `CRASHED`, `EJECTED`, `PILOT_DEAD` | every unit and object destroyed, by whom and with what; aircraft with altitude, airspace and ring |
| `TARGET` | a mission's target objects destroyed ("3 of 6 critical") |
| `CONTACT`, `TRACKING`, `PICTURE` | each coalition's radar picture: new / regained / stale / dropped contacts (new and regained say how far away the first sensor saw it, "seen by awacs MSN2001_AEW 212 km away") and airspace changes, a SAM radar's first track of a group, the 5-min summary |
| `CONTROL` | **every controller decision**, in order, the decision first (2026-10-01; before that each had its own word: `SCRAMBLE`, `NO_SCRAMBLE`, `STOOD_DOWN`, `ALERT`, `LEASH`, `SUPPRESSION`, `DEFEND`, `DELAYED`, `RETRY`, `CANCELLED`). Grep `CONTROL.*<decision>` for one kind: |
| `CONTROL.*watching` | a flight the controller watches, and its directives (a scramble: `leash on <raid>`) |
| `CONTROL.*scramble`, `no scramble`, `stand down before launch`, `alert` | scramble decisions and refusals (once per reason), stood down before launch, jets back on alert |
| `CONTROL.*leash` | a scramble sent home (`leash home`) or stood down on the ramp (`leash stand down`) |
| `CONTROL.*go cold` | a SEAD flight sent home after its salvo, and why |
| `CONTROL.*defend`, `leave`, `back on`, `leave threat` | the bandit call: an attack flight engaging a bandit (range, aspect, closing speed, radar missiles aboard), or sent home with no radar missiles to fight it (`leave:`); back on its mission or way home (why, how long); leaving a bandit to another flight (`leave threat`) |
| `CONTROL.*wait`, `retry`, `cancel`, `launch late`, `launch early` | SEAD first: a flight waiting for the SEAD flight on a site it needs, a SEAD flight flying again (`<id>_AGAIN`; in the rotation, "the rotation's next flight"), a flight not launched and why (`not needed`, `… still in the fight after a second SEAD flight`, `<site>'s SEAD flight … was cancelled`), a flight launched late, a rotation flight pulled forward (`launch early`). Before 2026-10-02 they were about packages |
| `CONTROL.*no shot` | a SEAD flight that reached its press-on point with every anti-radiation missile still aboard, sent home (before bug 36: at its launch point for 2 min) |
| `CONTROL.*press on` | a SEAD flight with missiles aboard not turning to fight a bandit (too far, or finishing its salvo); it commits only when fired upon or inside 25 km (bug 39) |
| `CONTROL.*salvo over` | a SEAD flight sent home 20 s after one of its jets fired its last anti-radiation missile (bug 40) |
| `RADAR_WARNING` | a SEAD flight at its launch and press-on points: whether its site's radar is on its warning receivers, every radar that is, the lead's height above the ground (bug 36) |
| `CONTROL.*handover`, `land:` | a patrol relieved on station and sent home; a jet lost on its way home given a new landing order, or a jet still up once another of its flight landed (`… still in the air`, each jet on its own order, bug 52) |
| `CONTROL.*stand down:` | jets removed on the ramp because they spawned with no weapons |
| `RAMP_LOSS` | a jet destroyed on the ramp before takeoff, within 2 min of spawning: a spawn failure, with base and spot |
| `>>orphan<<` | bug 19's wingmen (`CONTROL` lines): `possibly orphaned` (still in the air when a jet of its flight landed), then how it ended: `not orphaned: landed … after`, `removed: by the controller` (8 min on, counted as landed; or, since bug 68, `… still flying away 8 min after its last landing order`, with no landing in its flight needed), or `lost`. Count them run to run to see whether it gets worse or better |
| `UNIT_AWAKE`, `UNIT_ASLEEP`, `LATE_WAKE`, `AWAKE_COUNT`, `(asleep)` | sleeping ground units: a base's short-reach defenses waking and sleeping, an enemy within 10 km of a sleeping base (never expected), the 5-min count; hits and deaths of a sleeping unit end in `(asleep)` |
| `PLAYER_IN`, `PLAYER_OUT` | players |
| `PICTURE_CALL` | the air picture shown to a player every 2 min: how many groups, and the first (highest threat) line; `no radar coverage` when no sensor of the coalition reaches the player; `threat: …` a spoken threat call (a hot group inside 40 nm, roadmap item 7). What was said: `radio_calls/speak_mission_calls.log` |
| `RADIO_CALL` | an AI pilot's radio call, or Darkstar's order to an AI flight (`… by Darkstar to Weasel 1`: `engage`, `resume`, `return_to_base`, `land_at`, `scramble_vector`; compare with that flight's `CONTROL` lines); since 2026-10-06 the pilot's `report` to Darkstar (bingo, salvo done, no emitter, Winchester) and Darkstar's `acknowledge`, the pilot's `answer` to an order (`… (n s after the order)`), and `no answer to <order> from <callsign>` when the flight wasn't seen following it: what (`airborne`, `pushing`, `fox`, `magnum`, `splash`, `defending`, `jet_down`, `off_target`, `check_out`, `taxi`, `departing`, `inbound`, `final`, `clear`, …), on which channel (with an airfield's frequency and runway), by which jet's callsign. Compare with the flight's own lines to see that each call matches what it did; the words: `radio_calls/speak_mission_calls.log`; heard or not (tuned, too old, dropped), at what volume, and the jet's radios as they changed: `radio_calls/radio_player.log` (since 2026-10-06; before, the player's window only) |
| `== Mission end` | the summary: flights launched, losses by cause, ground losses, each flight's outcome |

`dcs.log` keeps planning and debugging (grep `[KOLA]`):

| Grep `dcs.log` | Shows |
|---|---|
| `PRELOAD`, `the sim froze` | the start-up preload cost per type, and any spawn over 1 s |
| `HUMAN TASKING` | every frag and steerpoint list |
| `SEAD order`, `SEAD rotation` | which enemy sites the rotation takes, in order (step, coverage, what goes before each), and every site not taken and why |
| `Build summary:` | the roll's totals |
| `asked for` | a unit type DCS swapped (Leopard-2 substitution) |
| `carries no weapons` | a jet spawned without the weapons its loadout lists (removed on the ramp; `carries nothing` before 2026-10-02) |
| `destroyed on the ramp` | a `RAMP_LOSS` |
| `picture:`, `Scrambles:` | the radar sensors found and the alert bases, at start |
| `WARN`, `ERROR` | anything that went wrong, including a failed event-log line |
| `KOLA-RADIOS` (not `[KOLA]`) | the export script reading the jet's radios for the radio player ("sending the jet's radios to 127.0.0.1:47112"), its first reading of them (`first reading of the jet's radios: {…}`), the first failure to read or send, or why it couldn't load |
| `Radio calls:`, `Flight calls:`, `Airfield calls:` | the radio's start lines: channels and frequencies, the calls file |

---

## Backlog (not on the roadmap)

Decide with John, step by step. Roadmap items are in the root's `roadmap.md`.

**Playability follow-ups** (session 10, none built):
- **Spread the two taskings:** require the second human tasking's target ≥ ~75 km from the first, falling back to any target. On the 12:18 roll both went to Rovaniemi.
- **Unflown taskings' AI flights:** the AI SEAD flights a player's mission needs fly even when nobody takes that tasking (part of the airborne cap; John, 2026-10-01: those SEAD flights fly first thing, ahead of other AI tasking, since they make the player's tasking possible). The human flight itself no longer counts against the cap. Still open, with picking a tasking: once a player takes one, cancel the other's AI flights.
- **Assignment and completion tracking** (John: later; the design leaves room): take a tasking from the comms menu, bind by slot (`player_slot.group`) or by the player's base at birth; report the target result; "take another tasking" after landing.
- **DEAD frag:** replace the "Groups: SAM_…" line with what the site holds (radars, launchers).
- **Brief items:** AWACS and tanker frequencies and callsigns (callsign policy below), bullseye (currently 0,0), divert fields.
- **More players:** more slots per base (the tool and planner already take several per base; the planner uses the first one that exists); 2-ship human flights.
- **Steerpoints:** done 2026-10-01 (`closed.md`, bugs 10 and 11: target elevation and aim points, no egress or return points).

**Front targets.** The fixed-target "front" echelon is still "≤ 100 km from an enemy base":
- **The gap:** on rolls where the sides sit far apart, nothing counts as front, so armor assembly areas and artillery never roll. Blue leaves ~3.5 missions per roll unplanned ("no target near the front in reach"), and human taskings fall back to DEAD / SEAD / CAP.
- **Offered, not built:** measure "front" from the airspace front line (`DivideAirspace` already runs before `PlanFixedGroundTargets`).
- **Optional:** John can nudge the no-road border zones onto a road (≤ 500 m) and fly the survey again.
- **Offered, not wanted for now:** reserving front zones for ground targets (John chose SAM front-belt chance 0.7 instead).
- **Also:** convoys and other mobile targets for Blue.

**Standoff attacks:** plan a release point short of the target, so jets attack from the contested airspace instead of overflying the target. First research which standoff weapons the DCS AI actually releases at range and which loadouts carry them:
- Blue: JSOW, SLAM-ER, AGM-86C;
- Red: Kh-29 / KAB, bomber cruise missiles.

Overlaps roadmap item 6 (cruise missiles).

**AI behaviour rules, one place** (John, session 8): collect the list first, then build it as one module instead of per-flight hacks:
- leash to own and contested airspace;
- strikes go home if their SEAD fails;
- scrambles that identify one jet and kill it only in certain airspace.

Built: the controller, `consumers/control_air_flights/` (see *The controller*), with the scramble leash, the SEAD go-cold directive `suppression` and attack flights defending themselves (`self_defence`, 2026-10-01). "Strikes go home if their SEAD fails" is handled before launch: a mission doesn't launch until its SAMs are out of the fight (packages in sequence). The rest is roadmap item 4 (AI behaviour logic).

**SEAD follow-ups** (offered 2026-10-01, not built):
- **Low ingress and pop-up becomes the SEAD doctrine** (John, 2026-10-01, after the 14:14 run: "my instinct to go high was wrong"): built 2026-10-01 as roadmap item 10 (*Packages*, "The SEAD profile: under the radar"), not flown yet.
- **Rolling back outside-in:** now roadmap item 12 (the standing SEAD rotation, designed 2026-10-02).

**Air picture follow-ups** (left open when roadmap item 5 closed, 2026-10-02):
- **AWACS tracks show yellow (unknown) on the HSD, not red** (bug 26's test, 2026-10-02): Link 16 identity, likely the F-16 DTC's ROE page; whether the mission can make them hostile.
- **Callsigns for AI flights from DCS's lists:** no effect on the datalink (bug 26's test), but DCS's own AWACS voice calls fail without one ("Callname -1 not found for MSN2001_AEW_1", 15× in the 19:29 run's `dcs.log`); with the callsign policy (*Design, not built yet*).
- is 14 s on screen enough to read up to 10 lines?
- a separate automatic THREAT call (a hot group inside ~35 nm, at once rather than at the next list)?
- when the AWACS is shot down: carry on from the ground radars (now: yes, the list is the whole picture), or say "picture degraded"?
- group size ("2 contacts", "heavy"): the picture keeps one contact per DCS group and doesn't count the aircraft;
- AWACS callsign and frequency in the brief (with *Brief items* above).

**Hunting an enemy patrol** (John, 2026-10-01, idea for later): if an enemy patrol keeps drawing scrambles or guards a viable target, task a sweep to go after it and eliminate it, the way a real air force would.

**Escorts:** fighter escorts for attack packages; on hold since the session 8 change of direction.
- **Hook:** a package gets one more member, like its SEAD flights.
- **Decide:** when a package gets one, and how it flies: the package route ahead of the strike with `EngageTargets` (air), or DCS's `Escort` task.
- **Research first:** check DCS Liberation's escort / sweep code (John: research what actually works for DCS AI).

**Spread the targets:** Red keeps hitting whatever sits inside the contested airspace; on one roll that was Rovaniemi, 4 of 5 packages.

**Tune the airspace:**
- the band width (30 km), maybe scaled to the gap between the sides' bases;
- stopping the front line at the coast or map edge;
- the routing multipliers (own 1 / contested 3 / enemy 10).

**Doctrine ideas** (session 8 discussion, nothing decided):
- finite squadrons with a loss budget, and no second wave into what killed the first;
- pulsed tempo instead of filling the cap;
- mobile SAM ambushes;
- escorts only where needed.

First step suggested: a loss summary per run, so later changes have a before and after.

**Rest of stage 4, mobile units:** Blue convoys, reinforcements, missile-launcher deployments, contacts.
- They need their own zones or corridors, since fixed targets use all free zones.
- They join the catalog through an adapter in `stages/catalog_targets.lua`; any static objects spawn before units.
- Interdiction (convoy `AttackGroup`) and close air support flights: `engage_in_zone` isn't built in `SpawnAircraftGroups`.

**SAMs on the map's revetments** (`prepared_sam_position = "revetments"`, 7 zones): John wants SAMs in those dug-in positions later. It's a SAM-stage change, so ask first.

**Smaller items:**
- **Base defenses:**
  - a ±1 level nudge at ~20 %;
  - logistics / fuel components as statics;
  - `security_armor` / `apc_patrol` components;
  - Tor / Tunguska at heavy Red bases.
- **Fixed targets:**
  - a second parked-aircraft group at hubs if ramps look empty;
  - real liveries per coalition for parked aircraft (CJTF with no `livery_id` logs "livery not found");
  - `settlement` still counts airfield buildings;
  - Red's supply-depot minimum fails about half the time (its large free zones mostly have no road).
- **Air tasking:** Red Su-34s sometimes fly at the edge of their reach (677 of 700 km); lower `combat_radius_km` if they run dry.
- **Housekeeping:**
  - rename `consumers/territory.lua` → `apply_territory.lua` (`ApplyTerritory`);
  - drop `SHOW_WEATHER_DEBUG`;
  - a per-run unit census log line.
- **Proximity spawning** (unlikely to be needed): spawn a base's defenses when a player gets within ~150 km. The plan already holds every unit, so briefs stay truthful.
- **Weather and time variety:** only possible outside the sim; see *Design*.

---

## Kola's map and scenario

Kola's own data on the shared framework: its names, folders and map facts in `kola_f16\mission_settings.lua` (`MISSION`: UTC +3, the magnetic-variation table Bodø +5° … Murmansk +16° with its self-test at Rovaniemi, Red's SAMs spawned as Russia, the map's edges, its files), its map and scenario data in `kola_f16\data\` (`MISSION.data_files`), and the settings each mission has its own values for, since 2026-10-06 (`radio_channels.lua`: AWACS UHF 262.000, mission VHF 140.000; `awacs_orbit_distances.lua`: 250 km from enemy fighter bases, 120 km from the contested airspace; framework `plan.md`, *Settings that differ by mission*). How each piece is used: the framework's `as_built.md`, the section named in each heading.

### Territory: the clusters (`data/clusters.lua`; *Stage 1: territory*)

| Cluster | Type | Bases |
|---|---|---|
| NORWAY_REAR | always Blue | Bodø, Evenes, Andøya, Bardufoss, Tromsø |
| SWEDEN | always Blue | Kallax, Vidsel, Kiruna, Jokkmokk, Kalixfors, Arvidsjaur, Hemavan, Boden |
| FINLAND_SOUTH | always Blue | Kemi-Tornio |
| FINNMARK_EAST | contested, p_red 0.7 | Kirkenes (56 km from Luostari, first to fall) |
| LAPLAND_EAST | contested, p_red 0.5 | Ivalo, Sodankylä, Vuojärvi |
| FINLAND_EAST | contested, p_red 0.5 | Kuusamo |
| KOLA_SOUTH | contested, p_red 0.75 | Alakurtti (Blue = a rare NATO pocket) |
| FINNMARK_WEST | contested, requires FINNMARK_EAST | Banak, Alta |
| LAPLAND_WEST | contested, requires LAPLAND_EAST | Kittilä, Enontekiö |
| ROVANIEMI | contested, requires LAPLAND_EAST, p_red 0.5 | Rovaniemi (Red ~25 % of rolls) |
| HOSIO | contested, requires ROVANIEMI, p_red 0.5 | Hosio (Red ~12 %) |
| KOLA_CORE | always Red | Murmansk Intl, Severomorsk-1, Severomorsk-3, Olenya, Monchegorsk, Kilpyavr, Koshka Yavr, Luostari Pechenga |
| AFRIKANDA | always Red | Afrikanda |
| KARELIA | always Red | Kalevala, Poduzhemye |

### Base defenses (*Stage 2: base defenses*)

- **Always heavy:** Murmansk, Olenya, Severomorsk-1 (Red); Bodø, Evenes (Blue).

**Rosters.** Coverage and realism beat exact type (John): Blue uses Russian or Chinese stand-ins where they match the real Nordic system better. Only single-vehicle systems here; multi-vehicle SAMs belong to the SAM site recipes.

| Role | Red: modern Russian Northern Fleet | Blue: Nordic, closest DCS stand-ins |
|---|---|---|
| towed_anti_aircraft_gun | ZU-23 Emplacement (3), Closed (2) | ZU-23 Emplacement (3), Closed (1): Finland's 23 ItK 61 is a ZU-23-2 |
| mobile_anti_aircraft_gun | ZSU-23-4 Shilka (2), Ural-375 ZU-23 (1) | Gepard (3), Vulcan (1) |
| infrared_missile_launcher | Strela-10M3 | M1097 Avenger (2), M6 Linebacker (1) |
| radar_missile_launcher | Pantsir-S1 (3), Tor M2 (2), Tor (1), Tunguska (1) | Roland ADS (2) for Crotale NG; Tor M2 (1) for IRIS-T SLS |
| shoulder_launched_missile | SA-18 Igla-S (3), Igla (1) | Stinger (3), Igla-S (1) |
| infantry | Soldier AK (2), Infantry AK ver2 (1), ver3 (1), Soldier RPG (1) | Soldier M4 (3), Soldier M249 (1) |

**Left out on purpose:**
- Strela-1, Chaparral, Osa, S-60 and the WWII Bofors;
- HQ-7B: its launcher has no search radar of its own in DCS, so it's unreliable alone.

### SAM sites (*Stage 3a: SAM sites*)

**Systems** (`COALITION_SAM_SYSTEMS` in `data/coalition_rosters.lua`):

| Layer | Red: Russian, layered, mixed age | Blue: western + Soviet-made, like Ukraine |
|---|---|---|
| long_range | SA-10 + Pantsir/Tor escort | Patriot (2) + Avenger escort, SA-10 (1) + Roland/Tor escort |
| medium_range | SA-11 (3), SA-6 (1) | NASAMS (3), IRIS-T SLM (2), SA-11 (2), Hawk (1) |
| short_range | SA-8 (2), SA-15 (1) | SA-8 (2), SA-15 (1), Roland (1) |
| early_warning | 1L13, 55G6 | FPS-117 |

- **Left out:** SA-2/3/5 (Russia doesn't field them).
- **Blue fields Soviet-made systems on purpose** (John): Ukraine fights with S-300, Buk, Osa and Tor, and NATO's Greece, Bulgaria and Slovakia have operated them.

**Known gap:**
- Kola-core zones are mostly 84–122 m, which only fits short- and medium-range systems.

### Player slots (*Player slots*)

- **Now 8 slots:** Banak, Bodø, Ivalo, Kallax, Kemi-Tornio, Kiruna, Rovaniemi, Tromsø.

### Zones (*Zones: the ground-unit dataset*)

- **127 zones**, all surveyed. The 15 border zones without a road can't hold garrisons, armor or depots, only SAMs, communications sites, and artillery where not steep.
- Drawn in `Saved Games\DCS\Missions\khola_ground_zones.miz` (`MISSION.zone_drawing_mission_file`); its trigger loads `kola_f16\survey\survey_zone_terrain.lua`, which writes `Saved Games\DCS\kola_zone_terrain.lua` and logs the tool run to `kola_zone_update.log`.
- The airbase codes in zone names come from `map_data_sources\kola_airbases.json` (same codes as `kola_f16\data\airbase_codes.lua`; keep the two in sync).

---

## Reference

**Kola airbases: exact DCS name strings** (verified in-sim; gather warns on any name that stops resolving after a map update):

| Country | Bases |
|---|---|
| Norway | `Bodo`, `Bardufoss`, `Evenes`, `Andoya`, `Tromso`, `Banak`, `Alta`, `Kirkenes` |
| Sweden | `Kallax`, `Vidsel`, `Kiruna`, `Jokkmokk`, `Kalixfors`, `Arvidsjaur`, `Hemavan`, `Boden Heli Base` |
| Finland | `Rovaniemi`, `Kemi Tornio`, `Kuusamo`, `Ivalo`, `Kittila`, `Enontekio`, `Sodankyla`, `Hosio`, `Vuojarvi` |
| Russia | `Murmansk International`, `Severomorsk-1`, `Severomorsk-3`, `Olenya`, `Monchegorsk`, `Afrikanda`, `Kilpyavr`, `Koshka Yavr`, `Luostari Pechenga`, `Alakurtti`, `Kalevala`, `Poduzhemye` |

- **Map:** ~1,400 km E-W × ~1,000 km N-S. Taiga and tundra, thousands of lakes, sparse roads, fjords. Polar night in winter, midnight sun in summer.
- **Kalevala** is a real 568 m helicopter strip.
- **Hosio** has no parking, taxiway or objects in DCS.

**Sources:**
- [DCS: Kola, ED product page](https://www.digitalcombatsimulator.com/en/products/terrains/kola_terrain/)
- [MOOSE `AIRBASE.Kola` names](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Wrapper.Airbase.html)
- [Skynet IADS](https://github.com/walder/Skynet-IADS)
- [pydcs](https://github.com/pydcs/dcs)
- [Airgoons DCS air-defence reference](https://www.airgoons.com/w/DCS_Reference/Air_Defences/Western)
