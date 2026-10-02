# Kola F-16 Random Tasking — Plan

> **What this is:** the spec and build state of the Kola F-16C mission generator. When the mission loads, a script rolls the battlefield (who holds which airfield), fills it with ground defenses, SAM networks and targets, plans both coalitions' air war for a ~6-hour window, and briefs human players on their taskings.
>
> **Where to look:** *Where we are* (pick up here) → *Backlog* → *As built* (the spec, by stage) → *Design, not built yet* → *Architecture* → *Reference*. Features coming next, in John's order, are in **`roadmap.md`**; bugs found in runs, to come back to, are in **`bugs.md`**; finished roadmap items (1–3, 5, 10, 11 and parts 4a / 4b so far) and fixed bugs move to **`closed.md`**, keeping their numbers. Session-by-session history (run logs, before/after numbers) was cut on 2026-09-30; it's in git (`notes/kola_f16_generator_plan.md` in commits up to `4c49af9`).
>
> **Paths** are relative to this mission folder (`missions/kola_f16_random_tasking/`, one up from `development_docs/`, where this file and `roadmap.md`, `bugs.md`, `closed.md` live) unless they say otherwise. Companion: the Syria mission (`missions/syria_a2g/notes.md`); no shared code.
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
> - After any edit under `kola_f16\`, copy the tree to `Saved Games\DCS\Scripts\kola_f16\` immediately. DCS is the only real test; the `luae.exe` harness (below) comes first.
> - When zones are drawn or moved, John flies `khola_ground_zones.miz` once (see *Zones*).
> - **No wildcard deletes** (John, 2026-10-02): never `rm *` / `rm -rf *` or any delete by pattern. A delete names its exact path, so John can read in the command what goes. For scratch work, unpack into a new folder instead of emptying an old one.

---

## Where we are — pick up here  *(2026-10-02, session 15)*

**Status:** the whole pipeline runs in DCS and the mission is playable by one human player.
- **Stage 1:** territory roll, 37 airfields.
- **Stage 2:** base defenses (trimmed for performance on 2026-10-01: no security infantry, one towed-gun group and one MANPADS team per base).
- **Stage 3:** SAM networks (127 surveyed zones), fixed ground targets, and the target catalog.
- **Stage 4:** one Red supply convoy.
- **Airspace map:** own / contested / enemy, with regions and pockets.
- **Air tasking for both coalitions:** front-only strike, airfield strike and DEAD; AI packages fly **in sequence** (SEAD first and home, the mission only once its SAMs are out of the fight, else one more SEAD, then cancelled), and later packages reuse an earlier SEAD flight's work; front CAP stations with commit circles; one AWACS each (see *Stages 5–6*).
- **SEAD doctrine: under the radar** (roadmap item 10, built 2026-10-01 late, flown in the 22:23 and 00:57 runs, retuned 2026-10-02; `closed.md`): one SAM site per 2-ship; cruise, down to 900 ft above the ground before the first enemy ring, low and fast around the other sites' low-altitude reach, pop up to 10,000 ft (the climb starts 15 km before the launch point), all anti-radiation missiles in one salvo 55 km from the site (40 until the 2026-10-02 retune), back down and out low on afterburner, then home. The controller sends it home if it presses on, strays into another kill zone, or is still on the attack 10 min after reaching its launch point (bug 20, fixed with it).
- **Players:** F-16C dynamic-spawn slots, two human taskings per roll, frag (3 min) and steerpoints (5 min, target and aim points with ground elevation, no egress) in the comms menu, `Hide text`, a popup for every static object a player destroys.
- **Radar picture, scrambles and the leash, event log** (roadmap items 1–3, done; `closed.md`). Scrambles are refused when they can't arrive in time, spawn only on ramp spots held for alert jets, and a jet stood down on the ramp goes back on alert.
- **Airborne cap:** 12 AI aircraft per coalition (players never count), 2 of it kept for scrambles.
- **The controller** (session 13, `consumers/control_air_flights/`, *The controller*): every run-time decision about AI flights in one place (launches in sequence, scrambles and alert jets, the cap, the leash, go cold, and the bandit call: an attack flight is told the moment a fighter comes hot within 100 km, and commits if it has radar missiles or goes home if not), one event word `CONTROL`. All of it has flown (22:23 and 00:57 runs); items 4a / 4b and 11 are in `closed.md`.
- **Red's attack jets carry R-77s** (2026-10-01): every Su-34 loadout has 2× R-77 (*Stages 5–6*, Loadouts).
- **Kill zones depend on altitude** (`lib/sam_reach.lua`): low-altitude reach near the ground, the full ring high up; no AI flight launches from a base inside an enemy SAM's low-altitude kill zone. **Known wrong** (bug 27, 00:57 run): the low reach holds up to 3,000 m in the model, but the sites reached nearly their full envelope at the 3,000 m pop-up; to fix first in roadmap item 12.
- **Air picture for players** (roadmap item 5, built 2026-10-02, flown in the 00:57 run; `closed.md`): every 2 min, for 14 s, each player gets their coalition's radar picture as a BRAA list from their own position (magnetic), highest threat first (*Air picture calls*).
- **The player's HSD** (bug 25, confirmed in Kola 2026-10-02): friendly AI flights show as datalink contacts and the medium and long-range SAM rings show (the recipe: *DCS facts learned the hard way*). The AWACS's enemy tracks: bug 26, still to check.
- **SEAD retuned after the 00:57 run** (2026-10-02, not flown; bugs 27, 28, 30): launch point 55 km (was 40), pop-up 15 km before it (was 12); go cold the moment the last anti-radiation missile leaves; attack tasks hold the planned altitude (the AI flew its attacks low); the bandit call keeps a fighter that just fired at the flight.
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

- **2026-10-02, 10:38 run** (`event_logs\2026-10-02_103843.log`, ~9 min, John at Rovaniemi; an HSD check, with the SEAD retune in but no SEAD flown yet): **threat rings and friendly datalink contacts showed on the HSD** (bug 25 fixed: the editor's EPLRS-on-waypoint-1 recipe, Red SAMs as Russia, slots as CJTF Blue; `closed.md`). The player still logs under two names: unit `f16_human_1_3` (`PLAYER_IN`, `TAKEOFF`, `POSITION`) and group `f16_rovaniemi` (`PICTURE_CALL`, and in longer runs the radar picture and `CONTROL` lines). John is renaming each slot's pilot to start with its group name (`f16_rovaniemi_1`), so grepping the group name finds both; check it in the next log, then note it under bug 24 in `closed.md`. "New callsign" in `PLAYER_IN` is John's DCS Logbook pilot name, not the mission's.

**Next (2026-10-02, for the next session):**
1. **John flies Kola with the SEAD retune** (launch 55 km, pop-up 15 km before it, go cold on the last missile, attack altitude held; bugs 27, 28, 30 in `closed.md` / `bugs.md`). Check: the salvo's `SHOT` ranges (~55 km) and the sites' return fire, `CONTROL.*go cold` within seconds of the last missile, `SHOT … from <ft>` at the planned attack altitudes (bombs at ~7,000 m, anti-radiation missiles at ~3,000 m), SEAD losses, `dcs.log` for `asked for group id` (the EPLRS task's group id) and `carries nothing`.
2. **Also in that run:** grep the player's group name (`f16_<base>`): it should now match every player line (bug 24); whether Red aircraft Blue's picture holds through the AWACS (`CONTACT` … `seen by awacs`) show on the HSD (bug 26); `CONTROL.*\(defend\|leave\|back on\)` for the bandit call, and whether a shooter stays the fight (bug 30).
3. **Roadmap item 12, the SEAD campaign** (top priority): first bug 27's reach model (the low reach only close to the ground), then the campaign as designed (SEAD planned first as missions of their own against every site covering the front, outside in by layers, strikes filling in behind; John: "SEAD flights are the primary mission to open up everything else"), with bug 22 (low legs around short-range SAMs), bug 19 (landing order), bug 29 (launch distance by target: a 40 km HARM shot at a Tor fired nothing), continuous tempo (discuss with John).
4. Then bug 8 (John's decision on the intercept margin) and the rest of roadmap item 4 (AI behaviour logic).

**Still to watch in runs:**
- **HSD threat limit:** a forum report says the F-16's HSD shows ~16 threats at most since the 12 May 2026 update; Red fields ~11 medium / long-range sites per roll. If rings are missing on a roll with more, that's why.
- **SEAD (the low profile, item 10, retuned 2026-10-02):** whether the AI holds ~900 ft above the ground on the low legs (`POSITION`), above all over the Khibiny and the fells; whether it pops up and fires near the 55 km launch point (`SHOT` range; the AI starts the attack ~12 km before it; at 55 km from 10,000 ft the AI may judge the target out of range and close in, and `press_km` sends it home 10 km past the point); how many missiles the target shoots down; whether `CONTROL … go cold` sends flights home for the right reasons; fuel on the long low legs (planned at 1.5× per km).
- **The `expend` limits:** whether the AI honours one salvo (`AttackGroup`, expend All, one attack).
- **A woken base fighting:** never seen in any of the 12 runs to 2026-10-02 (bug 5): a run where an enemy flies low over a defended base (`UNIT_AWAKE`, then `GUNS` / `SHOT` from `DEF_` groups; the end summary's `CHECK`), or a test mission.
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
| `SHOT`, `GUNS`, `HIT` | weapons fired (with target and range when DCS knows it), guns opening up, hits; repeats folded into one line |
| `DESTROYED`, `CRASHED`, `EJECTED`, `PILOT_DEAD` | every unit and object destroyed, by whom and with what; aircraft with altitude, airspace and ring |
| `TARGET` | a mission's target objects destroyed ("3 of 6 critical") |
| `CONTACT`, `TRACKING`, `PICTURE` | each coalition's radar picture: new / regained / stale / dropped contacts and airspace changes, a SAM radar's first track of a group, the 5-min summary |
| `CONTROL` | **every controller decision**, in order, the decision first (2026-10-01; before that each had its own word: `SCRAMBLE`, `NO_SCRAMBLE`, `STOOD_DOWN`, `ALERT`, `LEASH`, `SUPPRESSION`, `DEFEND`, `DELAYED`, `RETRY`, `CANCELLED`). Grep `CONTROL.*<decision>` for one kind: |
| `CONTROL.*watching` | a flight the controller watches, and its directives (a scramble: `leash on <raid>`) |
| `CONTROL.*scramble`, `no scramble`, `stand down before launch`, `alert` | scramble decisions and refusals (once per reason), stood down before launch, jets back on alert |
| `CONTROL.*leash` | a scramble sent home (`leash home`) or stood down on the ramp (`leash stand down`) |
| `CONTROL.*go cold` | a SEAD flight sent home after its salvo, and why |
| `CONTROL.*defend`, `leave`, `back on`, `leave threat` | the bandit call: an attack flight engaging a bandit (range, aspect, closing speed, radar missiles aboard), or sent home with no radar missiles to fight it (`leave:`); back on its mission or way home (why, how long); leaving a bandit to another flight (`leave threat`) |
| `CONTROL.*wait`, `retry`, `cancel`, `launch late` | packages in sequence: a mission waiting for its SEAD flight, a SEAD flight flying again (`<id>_AGAIN`), a mission or SEAD flight not launched and why, a flight launched late |
| `UNIT_AWAKE`, `UNIT_ASLEEP`, `LATE_WAKE`, `AWAKE_COUNT`, `(asleep)` | sleeping ground units: a base's short-reach defenses waking and sleeping, an enemy within 10 km of a sleeping base (never expected), the 5-min count; hits and deaths of a sleeping unit end in `(asleep)` |
| `PLAYER_IN`, `PLAYER_OUT` | players |
| `PICTURE_CALL` | the air picture shown to a player every 2 min: how many groups, and the first (highest threat) line |
| `== Mission end` | the summary: flights launched, losses by cause, ground losses, each flight's outcome |

`dcs.log` keeps planning and debugging (grep `[KOLA]`):

| Grep `dcs.log` | Shows |
|---|---|
| `PRELOAD`, `the sim froze` | the start-up preload cost per type, and any spawn over 1 s |
| `HUMAN TASKING` | every frag and steerpoint list |
| `Build summary:` | the roll's totals |
| `asked for` | a unit type DCS swapped (Leopard-2 substitution) |
| `carries nothing` | a jet spawned without the weapons its loadout lists |
| `picture:`, `Scrambles:` | the radar sensors found and the alert bases, at start |
| `WARN`, `ERROR` | anything that went wrong, including a failed event-log line |

---

## Backlog (not on the roadmap)

Decide with John, step by step. Roadmap items are in `roadmap.md`.

**Playability follow-ups** (session 10, none built):
- **Spread the two taskings:** require the second human tasking's target ≥ ~75 km from the first, falling back to any target. On the 12:18 roll both went to Rovaniemi.
- **Unflown taskings' AI flights:** the AI SEAD of a human package flies even when nobody takes that tasking (part of the airborne cap; John, 2026-10-01: those SEAD flights fly first thing, ahead of other AI tasking, since they make the player's tasking possible). The human flight itself no longer counts against the cap. Still open, with picking a tasking: once a player takes one, cancel the other's AI flights.
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
- **Rolling back outside-in** (now part of roadmap item 12, the SEAD campaign, top priority): a SAM site inside another's ring has no clear launch point, so it can't be attacked alone and targets behind such clusters aren't planned. Order the SEAD flights so the outer site goes first, and let the next site's launch point ignore sites already handled, each flight launching after the one before it lands and only if its site is dead.
- **Two flights at once for SA-10 / Patriot:** if one 8-HARM salvo still can't get through an SA-10 and its escort (the 13:07 run: all 8 shot down), send two SEAD flights to fire together (16 HARMs).

**Air picture follow-ups** (left open when roadmap item 5 closed, 2026-10-02):
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

## As built

### Run order (`init.lua`)

`Gather` (+ player slots) → `RollTerritory` → `PlanBaseDefenses` → `PlanSamSites` → `DivideAirspace` → `PlanFixedGroundTargets` → `PlanConvoys` → `CatalogTargets` → `PlanAirTasking` (defensive air → human flights → AI attack packages) → plan dump (`Saved Games\DCS\kola_last_plan.lua`).

Then:
0. `WriteEventLog.open` (this run's event log, with the plan at its top).
1. `DrawAirspace` (first, under every other mark).
2. `Territory.apply`.
3. Spawns: **static objects first**, then base defenses, SAM sites, fixed-target units, convoys.
4. Draws.
5. `PreloadAircraftTypes`, then `WriteEventLog.start` (DCS events from here on, so the preload isn't in the story).
6. `ScheduleAirTaskingOrders.start`.
7. `TrackRadarPicture.start` (after the scheduler, before anything that reads the picture).
8. `ControlAirFlights.start` (the controller, scrambles included), then `SleepGroundUnits.start`.
9. `DrawAirTaskingOrders`.
10. `BriefAirTasking.start` (comms menu).
11. Build summary to `dcs.log`.
12. `BriefAirTasking.showStart` (start text, 3 min).


### Stage 1: territory (`stages/roll_territory.lua`, `data/clusters.lua`)

Syria-style clusters: some always Blue, some always Red, contested ones rolled. Two mechanics keep the roll plausible:
- **`p_red`** weights each contested cluster's roll.
- **`requires_red`** makes a deep cluster roll only if its border neighbour already fell (evaluated in file order), so Russia can't hold Alta while Kirkenes stays NATO.

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

- **Echelon:** `front` ≤ `ECHELON_FRONT_KM` 100 km from the nearest enemy base, `mid` ≤ 200, else `rear`.
- **Zones:** each zone inherits its cluster's side.
- **After changing clusters:** re-run `miz_zones.py` (zones carry their cluster); no survey flight is needed if no zones moved.
- **Applied to the sim:** `Territory.apply` calls `setCoalition` + `autoCapture(false)` per base and draws a circle per base.

### Stage 2: base defenses (`stages/plan_base_defenses.lua`)

Every airbase gets a coalition-appropriate ground defense sized to how hard its owner holds it.

| Term | Question it answers | Values | Set where |
|---|---|---|---|
| **`class`** | What *is* this base? | `hub` / `fighter` / `bomber` / `dispersal` / `strip` / `heli` | `data/airbase_classes.lua` |
| **`echelon`** | Where does it sit relative to the enemy? | `front` / `mid` / `rear` | `RollTerritory` |
| **`defense_level`** | How heavily does its owner defend it? | `light` / `standard` / `heavy` | `BASE_DEFENSE_LEVEL[class][echelon]` |
| **component** | A kind of defensive element | `towed_anti_aircraft_guns`, `mobile_anti_aircraft_guns`, `infrared_missile_launchers`, `radar_missile_launchers`, `shoulder_launched_missile_teams`, `security_infantry` | `data/base_defense_placement.lua` |
| **composition** | How many groups of each component, per level | `{ component, min, max }` | `data/base_defense_composition.lua` |
| **placement** | Where a component's groups go | anchors spec, ring fallback, units per group, spread | `data/base_defense_placement.lua` |
| **anchor kind** | What open ground a group starts from | `infield`, `apron`, `parking`, `building`, `runway_side`, `runway_end`, `road` | `Placement.buildAnchors` |
| **role / roster** | Which types a coalition fields per role | weighted `{ type, weight }` | `data/coalition_rosters.lua` |

**Airbase classes are decided by runway length** (session 9; John: runway length is what decides; `data/airbase_classes.lua` lists each field's DCS runway):
- **`strip`:** too short for any jet (< `AIRBASE_CLASS_JET_RUNWAY_M`, 1,500 m).
- **`dispersal`:** any other field with no bigger role; a secondary field the air force flies fighters from in wartime (Finnish and Swedish dispersal doctrine).
- **Mismatches:** `PlanBaseDefenses` warns at start-up when a class disagrees with the runway.
- **Always heavy:** Murmansk, Olenya, Severomorsk-1 (Red); Bodø, Evenes (Blue).

**Defense level.** What a base is matters more than where it sits: hubs and bomber bases are defended heavily anywhere, since long-range strikes reach the rear.
```
                 front      mid        rear
   hub           heavy      heavy      heavy
   bomber        heavy      heavy      heavy
   fighter       heavy      heavy      standard
   dispersal     heavy      standard   standard
   strip         standard   light      light
   heli          standard   light      light
```
Rough size: heavy 5 groups / ~10 units, standard 2–4 / ~7, light 2 / ~5 (before 2026-10-01: ~20 / ~13 / ~9). Skill: heavy `Good`, else `Average`. Standing ground units barely register on their own (John); what they cost is scanning the sky while aircraft fly, so the short-reach ones sleep (*Sleeping ground units*).

**Groups per level**, most important layer first (trimmed 2026-10-01 for performance in VR: security infantry is no longer fielded, its placement kept so it can come back; towed guns and MANPADS teams were 1–2):
```
                                   heavy   standard   light
   radar_missile_launchers          1        —         —
   infrared_missile_launchers       1        0–1       —
   mobile_anti_aircraft_guns        1        0–1       —
   towed_anti_aircraft_guns         1        1         1
   shoulder_launched_missile_teams  1        1         1
```

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

**Placement.**
- **Trees are invisible to every DCS API** (proven by probe; don't re-investigate). So placement starts from ground that is open by construction, surveyed once into `data/airbase_footprints.lua`:
  - `infield`: grass between each runway's keep-clear edge and the first taxiway within 600 m;
  - `apron`: taxiway cells whose 4 neighbours are also taxiway;
  - `parking`, `building`;
  - `runway_side`: only at fields with no taxiway surface at all.
- **Forested fields** (`data/forested_airfields.lua`: Afrikanda) use only `runway_end`: the cleared overrun 80–380 m past each threshold, with units spread ≤ 30 m.
- **Anchors per component:** guns and vehicle launchers go infield first (0–40 m), then apron / parking 40–100 m, never buildings. Shoulder-launched missile teams and infantry spread wider, and buildings are allowed.
- **`Placement.isClear` for every group centre and unit:**
  - outside runway boxes (100 m beside the edge, 400 m past each end);
  - ≥ 60 m from parking spots;
  - no runway, taxiway or water in 9 surface samples.
- **Spacing:** group centres ≥ 150 m apart. Unit spacing by component: towed guns 25, mobile guns 30, missile launchers 40, missile teams 10, infantry 6 m.
- **Placement order:** most important layer first, so a cramped field loses towed guns, never its radar or infrared missile launchers.
- **Road fallback, instead of hand-drawn zones** (John: no manual placement work):
  - a group that finds no open ground in 80 tries goes onto one of the airfield's own roads (`anchor_kind = "road"`, within 800 m of a runway box);
  - a towed gun on a road becomes the truck-mounted Ural-375 ZU-23, facing along the road;
  - if the roads are full, the search widens to 2,000 m;
  - a unit that doesn't fit retries at half spacing, then a road within 300 m and then 1,000 m of its group;
  - only then is anything dropped (`DROPPED` warning, which shouldn't happen).

**Plan shape:**
- **Entry:** `plan.base_defenses = { groups = { { id, base, side, class, echelon, level, component, role, skill, anchor_kind, pos = { x, z, lat, lon }, units = { { type, x, z, heading_deg } } } }, bases = { [name] = { code, side, class, echelon, level, groups, units, anchors, rejects, dropped, on_roads } }, totals }`.
- **Names:** group id `DEF_<CODE>_<component>_<n>` is the DCS group name; units are `<id>_<n>`. Headings face outward from the field.
- **Not in the target catalog yet:** base defenses live in the plan, so they can become mission targets or brief information later.

**Load-time validation** (`PlanBaseDefenses.checkData`; fails loudly, nothing spawns):
- every roster type exists in `UNIT_POOL.ground`;
- every placement role has a roster for both sides;
- every composition component has a placement;
- every level has a skill, and every matrix cell a composition.

### Stage 3a: SAM sites (`stages/plan_sam_sites.lua`)

Target feel (John): **Ukraine-war density with mixed-age kit**, lived-in, built from what DCS has; coverage matters more than exact type. ~20–30 SAM sites per side per roll is judged about right. Don't change SAM spawning without being asked (John: "we just got that working the way we wanted"); later stages only consume `plan.sam_sites.zones_used`.

**How a site is decided** (`data/sam_site_density.lua`). Every held zone gets one role, first match wins:

| Role | Rule |
|---|---|
| `asset_ring` | ≤ 40 km from an own `heavy` base |
| `front_belt` | ≤ 100 km from an enemy base, or ≤ this roll's front gap + 60 km, whichever is farther |
| `rear_area` | anything else |

- **Chance by role:** asset 0.9, front **0.7** (lowered from 0.8 in session 9, to leave front zones for ground targets), rear 0.35.
- **Layer by weight:** asset: long 3 / medium 5 / short 2; front: medium 5 / short 4 / EW 1; rear: EW 3 / medium 2 / short 1.
- **System:** from `COALITION_SAM_SYSTEMS[side][layer]` that **fits the zone** (recipe `footprint_m` ≤ zone radius; else the next smaller layer).
- **Caps:** ≤ 75 % of a side's zones become SAM sites; ≤ 2 early-warning sites per side, and a pick over that cap becomes medium range.
- **Minimum per layer, placed first:** Red 3 long range + 2 early warning; Blue 1 long range + 2 early warning. Early warning goes rear-first; other layers go to the asset ring first, in clusters the side always holds, spread by area, with random tie-breaks so sites move between rolls.
- **Spreading:** ≤ 1 long-range site per area; ≤ 2 sites per base in the rear; no two sites of one side within 3 km.

**Systems** (`COALITION_SAM_SYSTEMS` in `data/coalition_rosters.lua`):

| Layer | Red: Russian, layered, mixed age | Blue: western + Soviet-made, like Ukraine |
|---|---|---|
| long_range | SA-10 + Pantsir/Tor escort | Patriot (2) + Avenger escort, SA-10 (1) + Roland/Tor escort |
| medium_range | SA-11 (3), SA-6 (1) | NASAMS (3), IRIS-T SLM (2), SA-11 (2), Hawk (1) |
| short_range | SA-8 (2), SA-15 (1) | SA-8 (2), SA-15 (1), Roland (1) |
| early_warning | 1L13, 55G6 | FPS-117 |

- **Left out:** SA-2/3/5 (Russia doesn't field them).
- **Blue fields Soviet-made systems on purpose** (John): Ukraine fights with S-300, Buk, Osa and Tor, and NATO's Greece, Bulgaria and Slovakia have operated them.

**How the systems perform in DCS** (researched 2026-09-23; engagement ranges high / low altitude):

| System | DCS | Behaviour, and what the recipe does |
|---|---|---|
| SA-10 | 5–120 / 5–40 km | Strongest SAM in DCS: 360° radars, 15 targets × 2 missiles, shoots down incoming missiles. |
| Patriot | 3–120 / **3–30 km** | Radar sees a fixed ~120° sector; wasted long shots. Recipe: **2 radars aimed 30° either side of the threat axis**, 6 launchers. |
| NASAMS | 0.7–57 / **0.7–14 km** | Limited by DCS's AMRAAM. Recipe: 2 search radars. |
| Hawk | 1.5–45 / 1.5–22 km | Needs its tracking radar to illuminate the target, so beaming defeats it. 2 tracking radars. |
| IRIS-T SLM | 40 km (mod data) | Currenthill mod; unverified. |
| SA-11 | 3.3–35 / 25 km | Radar on every launcher: robust. Weighted up for Blue. |
| SA-15 Tor | 1.5–12 km | Strong; very good at shooting down incoming missiles. |
| SA-8 Osa | 1.5–10.3 km | Decent; optical fallback if its radar is suppressed. |
| Roland | 0.5–8 km | Radar-only in DCS. |
| Rapier | 0.4–6.8 km, 3 km ceiling | Can't engage low flyers. Recipe kept, not rostered. |

Rings are drawn with ED's high-altitude figure; the low-altitude reach is much shorter (for the brief). Sources: ED forum threads on the Patriot and AIM-120, Airgoons DCS reference, DCS Liberation #1531.

**Recipes** (`data/sam_site_recipes.lua`):
- **Per system:** `layer`, `footprint_m`, `unit_spacing`, `parts = { type, min, max, place, aim }`, optional `escort_role`.
- **Places:** `centre` 0–35 % of the footprint (radars, command post), `launchers` 45–95 %, `edge` 60–100 % (support trucks).
- **Facing:** radars and launchers face the nearest enemy base; `aim` gives sector radars an exact heading.
- **Groups:** **one DCS group per site** (a system's radars and launchers must share a group); the point-defense escort is its own group `<id>_escort`.
- **On the F-16's HSD** (bug 25, confirmed 2026-10-02): medium and long-range site groups spawn with `hiddenOnMFD = false` (`init.lua` passes them to `SpawnGroundGroups.run` as `show_on_mfd`), so their threat rings show; escorts, short-range and early-warning sites stay hidden (DCS's default for a script-spawned group). Every Red SAM group spawns as country Russia (`options.country`), not CJTF Red. The DTC can't carry them: they spawn after the mission starts.

**Placement:** units stay inside their zone; `Placement.isClear` against the nearest airfield, then half spacing, then point-only. Base defenses keep 30 m outside every zone within 5 km of their base.

**Plan shape:** `plan.sam_sites = { sites = { { id, side, system, layer, role, zone, defends, pos, engage_m, detect_m, group_ids } }, groups, zones_used, summary }`. Group id `SAM_<CODE>_<system>_<n>` (e.g. `SAM_OLEN_SA10_1`), escort `<id>_escort`.

**Validation** (`PlanSamSites.checkData`): every recipe part is in the pool; every escort role has rosters; every system entry names a recipe of its layer.

**Known gaps:**
- Kola-core zones are mostly 84–122 m, which only fits short- and medium-range systems.
- No alarm-state or ROE orders (DCS defaults engage).

### Stage 3b: fixed ground targets (`stages/plan_fixed_ground_targets.lua`)

Everything on the ground worth attacking that doesn't move and isn't a SAM site, for both coalitions (John: "an active conflict unfolding").
- **"Fixed"** = doesn't move; "mobile" = moves.
- **"Static"** is reserved for actual DCS static objects (`coalition.addStaticObject`, `form = "static_object"`, `UNIT_POOL.static`). A recipe part is a `unit` if it would shoot or drive, and a `static_object` for buildings and parked vehicles or aircraft.

**Data:**
- **`data/fixed_ground_target_recipes.lua`:**
  - `label`, `location` (`zone` / `parking_spot` / `airfield_ground`), `echelons`;
  - zone class `requires` / `prefers`;
  - `footprint_m`, `unit_spacing`;
  - `parts { role, min, max, place, form, critical, same_type, spacing_m }`;
  - `success = { critical_fraction }`, `mission_types`, `value`.
- **`data/fixed_ground_target_density.lua`:** per coalition, the zone chance and kinds per echelon, airfield chances by base class, minimums, caps.
- **`COALITION_FIXED_GROUND_TARGET_ROSTER`** in `data/coalition_rosters.lua`.

| Kind | Location | Needs | Echelons |
|---|---|---|---|
| garrison | zone | medium+, road | all |
| armor_assembly_area | zone | large, road | front |
| artillery_battery | zone | medium+, not steep | front |
| command_post | zone | road | all |
| supply_depot | zone | large, road | mid, rear |
| fuel_depot | zone | large, road | mid, rear |
| communications_site | zone | prefers high ground / open radar view | all |
| parked_aircraft | parking spots | aircraft roles by base class | all |
| airfield_fuel_storage | building / apron anchors | — | all |

**Roll per coalition:**
1. **Minimum pass:** each kind goes to its best-fitting place.
2. **Zone pass:** each free zone gets a chance by echelon, then a kind that fits (weighted up by matched preferences).
3. **Airfield pass:** each held base rolls each airfield kind by its class.

- **One roller** for every kind (John: separate rollers would get unwieldy).
- **Revetment zones** (`prepared_sam_position = "revetments"`) are for SAM sites only (John).

**Placement:**
- **Zone objects** stay inside the zone.
- **Airfield ground** uses the base-defense anchors, ≥ 40 m from base-defense units.
- **Parked aircraft** (John: scattered singles weren't realistic):
  - real parking spots, ≤ 30 % of a base's spots, and never a player slot;
  - large aircraft on terminal type 104, helicopters on 40/72/104;
  - nose toward the runway;
  - **one group per base, one type, parked together** around the spot with the most free neighbours within 300 m.

**Plan shape:** `plan.fixed_ground_targets = { sites, groups, static_objects, zones_used, parking_used, summary }`. Ids `TGT_<CODE>_<kind>_<n>` (DCS group name); units `<id>_<n>`; static objects `<id>_static_<n>`. A static object's category comes from the pool (structures from `UNIT_POOL.static`, `Planes` / `Helicopters`, or the vehicle's `cat`).

### Stage 3c: target catalog (`stages/catalog_targets.lua`)

`plan.target_catalog = { targets[id], list (by coalition, highest value first), summary[coalition].by_mission_type }`.
- **Entry:** `category`, `kind`, `label`, `coalition`, `cluster`, `location`, `zone` or `base`, `pos`, `value`, `mission_types`, `group_ids`, `static_object_ids`, `critical_names`, `success = { critical_fraction }`, `covered_by` (the owner's other SAM rings reaching it), `defended_base` (own base within 5 km), `description`.
- **SAM sites:** `suppression_of_air_defenses` + `destruction_of_air_defenses`; critical = radars, fraction 0.5.
- **Early-warning sites:** `strike` + `destruction_of_air_defenses`; fraction 1.
- **Convoys:** category `mobile_ground_target`, mission type `interdiction`, carrying their route and speed.
- **Rules:**
  - mission stages read only the catalog;
  - base defenses stay out;
  - the catalog is built before spawning; alive or dead is runtime state keyed by the same ids.

### Airspace (`stages/divide_airspace.lua`, `data/airspace.lua`)

`DivideAirspace` runs after `PlanSamSites` → `plan.airspace`.
- **Grid:** 10 km cells, each classified at its centre.
- **Held ground:** the coalition holding the nearest airbase. The front line is where it flips (marching squares, simplified).
- **Contested airspace:** within 30 km of the front line, or own ground under the enemy's medium or long-range SAM rings.
- **Encoding:** one string per row; `B` / `R` = own airspace, `b` / `r` = contested on Blue / Red ground.
- **Regions:** a region is a connected piece of one coalition's held ground; the largest is `main`, others are logged as `POCKET`. A front is a connected stretch of contested airspace.
- **Direction:** `DivideAirspace.facingRegion` gives the own region nearest a target, and only bases in that region fly against it. A pocket fights only the front it faces (John stressed this).
- **Drawing:** `consumers/draw_airspace.lua` (mark ids 60000+) fills the areas as merged rectangles under every other mark, then draws the front line.

### Stage 4: convoys (`stages/plan_convoys.lua`, `data/convoy_recipes.lua`)

One Red supply convoy per mission (`CONVOYS_PER_COALITION`: Red 1, Blue 0).
- **Column:** 7–14 vehicles, with no infantry (it would slow the column to walking pace):
  - 1–2 armored personnel carriers at the ends;
  - 4–8 cargo trucks + 1–2 fuel trucks (critical);
  - 1–2 gun trucks mixed in;
  - 0–1 Shilka / Strela-10 at the tail.
- **Route:** a Red base pair 60–175 km apart, preferring rear or mid → front.
  - Start and parking are road points 2.5–5 km outside each airfield.
  - `land.findPathOnRoads` proves a road connects them (≤ 250 km); up to 8 pairs are tried.
  - Vehicles stand in a column 25 m apart; there's a waypoint every 20 km, "On Road" at ~50 km/h, and the convoy parks at the last one.
- **Ids:** `CONVOY_<FROM CODE>_supply_convoy_<n>`.
- **Map:** `consumers/draw_convoys.lua` (mark ids 40000+).

### Stages 5–6: air tasking (`stages/plan_air_tasking.lua`, `data/air_tasking.lua`)

**Order inside `PlanAirTasking`, per coalition:** defensive air (AWACS → CAP stations and rotations) → human flights → AI attack packages. Human flights come before the AI's so they get first pick of targets.

**Airborne cap:** `max_airborne_aircraft` 12 per coalition (16 until 2026-10-01; cut 25 % for performance in VR, John: strike volume is all relative), counting every AI package member, patrol, AWACS and scramble; human flights and players never count (John, 2026-10-01: the cap is for AI aircraft). A human package's AI escorts do count, and are planned before the AI's own packages. Planned flights fill it only up to `AIR_DEFENSE.scramble_reserve_aircraft` (2) below it (`plannedCap`), so strikes can't leave no room for a scramble; scrambles never go over it. Up to 24 aircraft airborne in total. In the harness on the 21:37 plan, planned peaks went from 13–16 to 7–10, and Red planned ~22–28 flights instead of ~30–36.

**Launch fields:** fighters and attack jets fly from any held field whose runway and parking fit them (John: in wartime every usable runway is used).
- F-16 / F/A-18 `min_runway_m` is 1,500 m (4,900 ft), so Alta (1,490 m) is just short and Kirkenes (1,795 m) qualifies.
- `base_classes` stays only on the heavies: Tu-22M3, B-1B, A-50, E-3A.
- Launch bases aren't tied to the parked-aircraft rosters (John: it would limit launch bases).

**Attack missions** (strike, airfield strike, DEAD; interdiction and close air support are stubbed with `built = false`):
- **Per mission:**
  1. mission type (weighted);
  2. aircraft from `COALITION_AIRCRAFT`;
  3. an enemy catalog target in reach (weighted by value, never hit twice);
  4. one of the 3 nearest fitting bases;
  5. a start time under the cap;
  6. free parking at that time;
  7. route and attack tasks.
- **Front only** (session 8): targets in the contested airspace or ≤ `AIR_TARGETING.max_km_past_contested` (40 km) beyond it. Launch bases come only from the own region facing the target.
- **Ids:** `MSN<n>` (Blue 2001+, Red 7001+; 5001+ before 2026-10-02) is the DCS group name.
- **Routes:**
  - **Cruise and descent:** ≥ 7,500 m (~25k ft) for every attack flight, above guns, MANPADS and short-range SAMs. Held until a descent point (5 km per km of drop, ≥ 10 km) before the ingress. The AI descends toward the next waypoint's altitude from the previous one, so attack altitude can't sit on the ingress point.
  - **Attack altitude** per aircraft and mission type, realistic for the payload whatever the threat (John): FAB-500 5,000 m, RBK 3,000 m, JDAM 7,000–9,000 m, Tu-22M3 carpet 8,000 m.
  - **Threat routing:** A* on a 10 km grid (`lib/threat_routing.lua`) around enemy medium and long-range SAM rings (+10 km) and Pantsir / Tor-M2 base-defense groups (+5 km). Every fixed enemy site is treated as known (John agreed).
  - **Airspace pricing:** own 1 / contested 3 / enemy 10 per km (`AIR_ROUTING.airspace_cost`). Smoothing refuses a shortcut that costs more than the path it replaces.
  - **Rejected routes:** a way around > 1.6× direct goes straight through; a route with more enemy-airspace km than the target's depth + 20 km isn't flown.
  - **Suppression flag:** a route still crossing a ring gets `needs_suppression` + `suppression_threats`.
  - **Way home:** the way out reversed. `return_when_out_of` is not used (DCS flies straight home off the route once the missiles are gone).
- **Making the AI attack** (researched from DCS Liberation's code and the ED forums; John: "the obvious choices don't actually work"):
  - one `Bombing` task per critical object at its position, on the ingress waypoint (search tasks never pick static objects);
  - every `Bombing` / `AttackGroup` task carries the planned attack altitude (`altitudeEnabled`; 2026-10-02, bug 28: without it the AI picked its own once the attack started and flew it low, a JDAM strike dropping from 3,585 ft);
  - heavy bombers get one `Bombing` at the centre;
  - rules of engagement `open_fire` (not weapons free, so the flight stays on its target);
  - evade fire, return at bingo, no jettisoning;
  - gun emptied (the AI otherwise strafes a Tor once the bombs are gone);
  - loadouts carry one kind of air-to-ground weapon each (the AI handles mixed weapons badly).

  Also: `EngageGroup` for anti-radiation missiles (it waits for the radar to emit), `AttackGroup` for SAM sites and convoys, and `BombingRunway` ignores laser-guided bombs. F-15E JDAMs do drop (confirmed session 8).
- **Loadouts** are generated, never hand-typed (John):
  - `kola_data_tools/aircraft_loadouts.py` builds `data/aircraft_loadouts.lua` from ED's UnitPayloads, DCS Liberation's AI loadouts (reference clone `C:\Users\johnk\Git\dcs_liberation`) and Syria's proven CAS loadouts (`aircraft_loadouts_by_hand.json`);
  - the choice per type and mission type is in `aircraft_loadout_choices.json`;
  - every CLSID is checked against `aircraft_pylons.lua`; pylons carry weapon names;
  - `--list <type>` shows the options.
  - **Red flights carry their best long-range air-to-air missiles to protect themselves** (John, 2026-10-01): every Su-34 loadout is a hand loadout with 2× R-77 (`… R-77`: in place of the R-27Rs on pylons 5 and 8 for SEAD / DEAD / interdiction, in place of the R-73s on pylons 2 and 11 for strike and airfield strike). The fighters already carry their best (Su-30 R-77; Su-27 / Su-33 R-27ER, they can't take the R-77 in DCS; MiG-31 R-33). The Su-24M can carry nothing better than the R-60 and the Tu-22M3 nothing at all: they leave when a bandit comes (*The controller*).

**Packages: SEAD / DEAD** (John: a mission that needs suppression never flies without it. Since 2026-10-01 whether it worked is tracked: an AI mission launches only once its SAMs are out of the fight):
- **Unsuppressed:** a mission whose route crosses rings gets suppression flights, or isn't planned and another target is tried.
- **Dividing the threats:** in the order the route meets them, **one SAM site per SEAD flight** (John, 2026-10-01: "fly high and fast and dump the HARMs at it at distance and then go cold"; the "high" part replaced by item 10's low run-in the same day; a second site gets its own flight). SEAD loadouts carry 4 anti-radiation missiles per jet (F-16: 4 HARMs + centerline tank + an AMRAAM on each wingtip; F/A-18: 4 HARMs, Sidewinders and AMRAAMs, no tanks; both `hand:SEAD 4 HARM`, John's specs; Su-34 4 Kh-31P).
- **The SEAD profile: under the radar** (`suppressionRoute`, attack kind `harm_salvo`; roadmap item 10, built 2026-10-01, John's profile after the 14:14 run, where the low run-in and pop-up killed the Sodankylä SA-10's radars). Numbers in `AIR_MISSION_TYPE.suppression_of_air_defenses`:
  - **Launch point** `launch_km` (55 since 2026-10-02, bug 27: from 40 the sites fired back at the pop-up from 39–50 km and every SEAD jet that got there died; was 80 until the 13:07 run, where HARMs fired from 89–92 km were all shot down by the SA-10) from the site, on the side the flight comes from, **outside every other site's low-altitude reach** (`lib/sam_reach.lua`: SA-10 40 km, SA-11 25, … + 10 km; base-defense Pantsirs / Tors at full reach + 5): the bearing toward the base first, then every 15° either side; none clear → the site can't be attacked alone (until rolling back outside-in). On the 21:30 roll this opened Red's planning from 3 of 6 missions / 2 SEAD flights to 3–6 / 3–6 over six seeds; Blue's targets there sit behind Kola's inner sites (an SA-11 beside its SA-10 is blocked even low) and still mostly aren't planned.
  - **The way in** is routed around those low-altitude reaches (`ctx.low_threats`). Cruise in own airspace; a descent point so it is down `low_entry_margin_km` (10) before the route first enters any enemy ring (full reach + margin); then **`low_altitude_m` (275, ~900 ft) above the ground** (`alt_type = "RADIO"`, the first non-sea-level altitudes in the mission) at `low_speed_mps` (270), a waypoint every `low_waypoint_km` (15) so the AI re-reads the ground; **pop up** `popup_km` (15; was 12) before the launch point to `popup_altitude_m` (3,000, ~10,000 ft; John: one number; must stay at or below `AIR_DEFENSE.killzone_low_altitude_m`, where the launch-point test's low reach holds); at the launch point an `AttackGroup` on the site's own group with every anti-radiation missile (`expend = "All"`, one attack).
  - **The way out:** straight back down and out low the way it came, afterburner allowed (option on the egress waypoint), afterburner off again at the low entry (`climb`), then back up to cruise and home. A route that enters no enemy ring at all (a short-reaching site, the launch point outside its own ring) has no low leg: down to 3,000 m, shoot, back.
  - **Fuel:** a low km counts `low_fuel_factor` (1.5) km of reach (`fuelLength`).
  - Waypoint kinds `low`, `popup`, `climb` (event log: "low level", "pop-up, climbing to the shot", "climb out, clear of the rings"). The point-defense escort gets no missiles of its own (the salvo saturates it). A long-range ring may reach past the launch point (SA-10, Patriot): it pops up, fires and turns away.
  - **Not planned** reasons now say why: `no suppression flight: no launch point clear of other sites` / `too far for its fuel` / `too deep in enemy airspace` / `no base in reach`.
  - Strike and DEAD flights stay high (John): they launch only once their SAMs are out of the fight.
- **Go cold** (the controller's directive `suppression`, `AIR_CONTROL.suppression`): checked every fast check (5 s), and 0.5 s after each anti-radiation missile the flight fires, so it turns as the last one leaves (2026-10-02, John: no waiting once the salvo is away; it was the 30 s picture round); home once every anti-radiation missile is gone, when it presses more than `press_km` (10) past its launch point toward the site, inside the kill zone of another SAM site (not one its planned route passes through on purpose: `route_threats`), or still on the attack `attack_time_s` (10 min) after it came within `arrival_km` (15) of its launch point (the clock starts on arrival, however late it took off: bug 20, 2026-10-01). Low on the run-in, "inside the kill zone" uses the site's low-altitude reach, and the rings the route passes on purpose are the low-altitude reaches it crosses. `CONTROL … go cold`. **Going home turns it around where it is** (John, 2026-10-01): before its launch point it flies its route out backwards from the nearest point behind it (low where it came in low); from the launch point on, its planned way back. (The first version always flew the planned way back, which starts near the launch point: MSN5026, sent home 15 s after takeoff, flew out to its target and turned there without firing.)
- **Base:** the mission's own base when it can, else the region's base nearest the target.
- **AI packages fly in sequence** (John, 2026-10-01: "we can still task and launch all these missions, they just can't all run at the same time"): the suppression flights first (spread over the window), then the mission `strike_after_suppression_s` (10 min) after the last of them is planned to land (`scheduleSequentialPackage`). Each flight is held under the cap only for its own time in the air, so a package needs room for one flight at a time. In the harness Blue went from 0–2 to 6–7 of 6–7 AI missions planned, Red 4–6 of 4–6, peaks still ≤ 10.
- **Rolling the air defenses back:** a threat an earlier AI suppression flight already takes (`ctx.cleared`) gets no new flight; the mission waits until that one has landed (+10 min). A player's suppression flight never counts for this (nobody may fly it). Plan fields: `cleared_by = { threat → flight }`, `requires_cleared = { threats }`.
- **At run time** (the controller, `control_air_flights/decide_launches.lua`, asked by the scheduler when a flight is due): a mission with `requires_cleared` launches only once those threats are out of the fight (a SAM site's critical radars to its success fraction; a base-defense group with no live unit). If not: it waits (`CONTROL … wait`, 10 min at a time, at most an hour) while one of its suppression flights is still up; otherwise those flights fly once more (`CONTROL … retry`, a copy `<id>_AGAIN` on parking free now; one repeat per suppression flight however many missions rely on it) and the mission waits for them; if the threats are still alive after that, it's cancelled (`CONTROL … cancel`; John: (b) then (a)). A suppression flight whose threats are already out of the fight isn't sent (`CONTROL … cancel: not needed`). A mission launched late flies a copy on parking free now, once there is room under the cap (checked every `wait_for_room_s`; `CONTROL … launch late`).
- **Packages with a human flight:** a player's own mission flies together with its AI suppression flights, which take off first thing (`first_start_s`; John: they make the player's tasking possible) and stay at least `suppression_lead_s` (3–5 min) ahead of the player over the target; human flights aren't gated. **A player's SEAD tasking in front of an AI mission** is the other way round (bug 17): the AI mission flies in sequence after it, `strike_after_suppression_s` after the player's planned landing (`scheduleHumanSeadPackage`), only once its threats are out of the fight; if not, two AI jets fly the player's tasking once (`<id>_AGAIN`), then it's cancelled. (Found when MSN2023_DEAD flew with JSOWs into a live SA-11 behind a player SEAD nobody flew, and lost both jets.)
- **Enemy airspace:** suppression flights obey the same enemy-airspace limit as their mission.
- **Mission types:** `suppression_of_air_defenses` is escort-only (anti-radiation missiles). `destruction_of_air_defenses` is a primary (`AttackGroup` on each group; Red: Su-34 with 4 Kh-29T, attack altitude 4,000 m).
- **Scaling:** nothing is per-site; more zones → more rings → more suppression flights, automatically.
- **Plan shape:** `plan.air_tasking_orders[c].packages = { { id = "PKG<n>", mission, suppression_flights, tot_s } }`; missions carry `package` / `suppressed_by`; suppression flights carry `escorts` / `suppresses`.

**Defensive air** (air-denial version, sessions 8–9; John: patrols deny own and as much contested airspace as possible and protect the coalition's installations near it; single ships, to watch them):
- **Front stations** (`planStations`):
  - the defended sites are the coalition's catalog targets (not convoys) in the contested airspace or ≤ `defended_depth_km` (60) behind it;
  - greedy: the uncovered site whose 60 km circle holds the most uncovered value, same region only, becomes a station;
  - up to `max_stations` (3), while it covers value ≥ `min_defended_value` (2).
- **Defended zone:** that circle around the covered sites' value-weighted centre, cut short of every enemy threat ring, never below `min_zone_radius_km` (20). Drawn dashed.
- **Orbit:** walked out from the nearest own base of that region toward the zone centre, as far as it stays on own held ground (all three points, per the airspace grid) and out of enemy kill zones. Legs run across the line to the nearest enemy base.
- **Kill zones** (John: SAMs don't fire to their full drawn range, so jets may work close to a ring or a little inside it, just not fly into the kill zone for no reason): patrols and the AWACS keep out of `AIR_DEFENSE.killzone_fraction` (0.85) of each ring, for routes, orbits and zones. Attack flights still route around the full ring + margin.
- **At run time the kill zone depends on altitude** (2026-10-01, `lib/sam_reach.lua`): a site reaches a low flyer much less far than its drawn ring (radar horizon, low envelope). Each medium / long-range recipe has `low_altitude_engage_km` (SA-10 40, Patriot 30, SA-11 25, Hawk 22, IRIS-T 20 (estimated), SA-6 15 (estimated), NASAMS 14); the zone is 85 % of that up to `killzone_low_altitude_m` (3,000 m), of the full ring from `killzone_high_altitude_m` (7,000 m), straight between. Used by the leash, the SEAD rule and the scrambles' "under enemy SAM cover" (the contact's altitude). Found when the SEAD rule sent MSN5026 home 15 s after takeoff from Vuojärvi, 60 km from a Blue SA-10 whose 120 km ring called it deadly, though flights had used that base all mission unharmed.
- **No AI flight launches from a base inside an enemy site's low-altitude kill zone** (`launchBases`, `underEnemySam`; John: no flights up into instant death). The alert posture uses the same test (it used 85 % of the full ring).
- **Station flights** may fly at most `AIR_DEFENSE.station_enemy_airspace_km` (5) of enemy airspace to their station; otherwise that base doesn't fly it. A base whose route enters any enemy threat ring can't fly the station.
- **Patrol tasking:**
  - rules of engagement `open_fire`, with `EngageTargetsInZone` on the defended zone from the takeoff waypoint, so a patrol in transit defends too;
  - **not `weapons_free`:** in DCS that means engage anything the group detects, and with AWACS datalink patrols chased into enemy SAMs;
  - `may_jettison` is decoupled from rules of engagement, so fighters still drop tanks.
- **Commit circles:** each station also gets circles (`commit_*`: 40 km radius on a 50 km lattice, within 120 km of the orbit) over own and contested airspace, each shrunk until it holds no enemy airspace or kill zone. Patrols carry `EngageTargetsInZone` on each. An enemy jet over contested airspace near a patrol gets engaged; one in its own airspace doesn't. Drawn as faint dotted circles.
- **Rotations:** each patrol is on station 1 h; the next arrives 10 min before it leaves; the first spawns from T+2 min and is on station at ~T+17–24 min. Each rotation comes from the nearest base in its region with reach, free parking, and room under the cap.
- **AWACS, one per coalition** (A-50 / E-3A):
  - off the runway of the held base farthest from the enemy, at T+5 s;
  - race-track orbit (80 km) toward the nearest enemy fighter base, 200 km from every enemy base;
  - orbit in own airspace, `early_warning_clearance_km` 30 outside enemy rings;
  - feeds AI datalink.
- **Alert posture** (`AIR_DEFENSE.alert_posture_planned = true`, `planAlertPosture`): see *Scrambles and the leash*.
- **Mission types:** `combat_air_patrol`, `airborne_early_warning`, `interception`, with `planned_as` (mission / escort / station / response), per-type `flight_size`, `rules_of_engagement`, `takeoff`, `keeps_gun`, `engage_range_km` (patrols).
- **Loadouts:**
  - Liberation `CAP` for the Russian fighters and F-15C;
  - `dcs:AIM-120C*4, AIM-9X*2, FUEL*3` for the F-16;
  - `liberation:Liberation BARCAP` for the F/A-18;
  - `hand:Clean` for the AWACS types.

**Human taskings** (session 10; `HUMAN_TASKING` in `data/air_tasking.lua`, `planHumanMissions`). John's decisions:
- the mission is also a sandbox: the brief lists the human taskings, and the player picks a base and spawns;
- no assignment or completion tracking yet (the design leaves room for both);
- 1 player for now, always 2 human taskings, every mission type allowed;
- takeoff 10–20 min after mission start, TOT set by how far the target is.

How it's built:
- **Flight:** each human flight is 1× F-16C (`flown_by = "human"`, AI flights `"ai"`) from a held slot base whose runway fits, taking off `startup_s` (600–1200 s) after start. `human_missions` lists their ids.
- **Mission types:**
  - strike / airfield strike / DEAD: planned like the AI's, with AI SEAD if the route needs it;
  - SEAD: the player escorts an AI mission and takes the first threats on its route;
  - CAP: the player flies one of the front stations for `on_station_s`.
- **Timing:** the package's AI flights are timed around the player (`scheduleHumanPackage`). A package that would push the player's takeoff past `startup_s[2]` + 1 min is dropped.
- **Fallbacks:** other mission types (types already used go last), then bases another human flight already uses.
- **Not spawned:** human flights aren't spawned or preloaded. Their routes are drawn dashed yellow with a `HUMAN` label.

**Scheduling and results** (`consumers/schedule_air_tasking_orders.lua`):
- **Spawning:** each flight spawns on the mission clock and is removed 3 min after landing.
- **Logging:** the event log (see *Event log*) catches shots, hits, kills, losses, takeoffs and landings for every unit, and `POSITION` lines every minute; the scheduler adds `TARGET` (a mission's target objects destroyed, n of m critical) and the spawner adds `SPAWNED`, `LOADOUT` (the ammo check 5 s after spawn) and `WAYPOINT` (a script command on every waypoint between takeoff and landing).
- **Status:** `ScheduleAirTaskingOrders.statusOf` gives planned / airborne / landed / lost for the brief.
- **Datalink** (bug 25, confirmed 2026-10-02): every AI flight gets an explicit group id (700000+) and the EPLRS command as the first task of its first waypoint, as the mission editor does it (plus `setCommand` EPLRS right after the spawn); every AI unit its own Link 16 STN (`AddPropAircraft.STN_L16`, octal from 01000; the player slots use 00201–00211) and the editor's `datalinks.Link16` block. With all of it, friendly AI shows as datalink contacts on a player's HSD.

**Preload** (`consumers/preload_aircraft_types.lua`): DCS loads a type's model, liveries and damage model on its first spawn, on the main thread, which froze the sim 2–25 s mid-mission (F-15E 25 s, Su-24M 7 s).
- **Fix:** for every coalition and aircraft type in the plan, spawn one real group 9 km above a base that type flies from, with one unit per distinct loadout (so weapon models load too), then destroy it at once.
- **Cost:** ~13 types in ~18 s at start-up (F-15C 13.7 s, F-15E 2.5 s). No mid-mission freeze since.

### Radar picture (`consumers/track_radar_picture.lua`, `data/radar_picture.lua`)

Built 2026-09-30 (roadmap item 1). Each coalition keeps a picture of the enemy aircraft its own radars report, so scrambles, AWACS calls and later fog of war act only on what the defenders could really know. The script uses it to decide things and gives the AI tasks; it can't add contacts to the AI's own awareness (DCS's built-in datalink already shares contacts between same-coalition AI). **The picture itself only watches and logs:** no orders, no spawns, nothing written to the plan; scrambles and the leash act on it. First DCS run: session 11.
- **Sensors:**
  - **Ground, found once at start:** SAM sites (`early_warning` by layer, otherwise `sam_search`, including each site's `<id>_escort`) and base-defense groups of the `radar_missile_launchers` component (`base_defense`), counted only when a unit carries a radar (`Unit:hasSensors`). Gun fire-control radars don't count (John).
  - **Flights, while airborne:** `awacs`, `patrol`, `scramble`, from the mission type (`RADAR_PICTURE.flight_sensor_kinds`). Attack flights and human flights aren't sensors. `TrackRadarPicture.addFlight` adds a flight spawned at run time (scrambles, item 2).
  - Dead groups drop out, so losing the AWACS thins the picture by itself.
  - On the 14:36 plan: Red 40 ground sensors, Blue 32 (3 Blue escorts without a radar skipped), 22 sensor flights each.
- **Polling:** every sensor once per `poll_interval_s` (30 s; John: plenty often, also for AWACS calls), spread over 10 steps 3 s apart. `Controller:getDetectedTargets(RADAR)` only, never `DLINK`.
- **Contacts:** one per enemy group, updated at the end of each round:
  - `group`, `category` (`airplane` / `helicopter`), `first_seen`, `last_seen`, `seen_by` (sensor kind → count), `state` (`tracked` / `stale`);
  - `pos`, `altitude_m`, `heading_deg`, `speed_mps` (`getPoint` / `getVelocity`);
  - `type_known` (this round), and `type` only once some sensor knew it (it stays after that);
  - `range_known` (false = bearing only);
  - `airspace` (`DivideAirspace.kindFor`), `nearest_base` / `nearest_base_km` (own held base), `inside_own_sam_ring` (site id);
  - **`inbound`, `threat_asset`, `threat_minutes`:** the contact's heading line passes within `threat_pass_km` (30) of an own asset (a held base or a catalog target) ahead of it, at more than 50 m/s; the soonest such asset and the minutes to it. One definition for the scramble trigger and the leash's "heading away". (The first version used "heading within 60° of the nearest own base", which called a raid flying past that base toward Olenya "heading away": found in the scramble harness.)
- **Memory:** stale after 60 s unseen (two missed rounds), dropped after 300 s.
- **Events** (`TrackRadarPicture.on(coalition, event, fn)`), fired once per round, each listener run under `pcall`: `new_contact`, `airspace_changed` (extra = the airspace before), `contact_stale`, `contact_dropped`, then `picture_updated` once the round is complete (scrambles and the behaviour rules run on it).
- **Calls:** `contacts(coalition, filter)`, `contactsNear(coalition, pos, radius_m)`, `contact(coalition, group)`, `sensors(coalition)`. Contacts come back as kept: read them, never change them.
- **Test aids for the first DCS run** (`log_radar_tracking`, `count_missiles`): the first time a ground sensor's radar tracks each enemy group (`Unit:getRadar`), and the number of missiles the radars listed since the last summary.
- **What the first DCS run showed** (session 11, ~48 min): 32 Red / 34 Blue ground sensors, every sensor answering every round.
  - **Missiles are listed, but rarely:** 2 in one 5-min window while many were fired. Not reliable for air-to-air missiles; cruise missiles still to test (item 6).
  - **`getRadar()` works:** `SAM_ENON_SA11_1` tracking the Su-33, `SAM_ALTA_SA11_1` tracking the F-15C.
  - **Type known** for 6 of 16 new contacts.
  - **Bearing only** once: the F-15C, which carries an internal jammer in DCS. A good sign that DCS reports jammed contacts as range-unknown (optional jamming item).
  - **Low flyers:** the AWACS picked up aircraft at 1,100–4,500 ft from 160–210 km. Most first detections were 120–210 km out, which roughly fits the 15-min scramble warning.
  - **No flicker:** 0 "regained" lines; contacts went stale, then dropped.
  - A wreck can be seen once more after the kill (MSN5901_SCRAM), so a leash reason can read "heading away" instead of "destroyed". Wording only.
- **Offline harness:** `radar_picture_harness.lua` (session scratchpad; not kept) ran the module on the real 14:36 plan with stubbed radars: one Blue jet from Rovaniemi to Olenya, seen from T+60 to T+700. New at T+90, four airspace changes, stale at T+780, dropped at T+1020, a failing listener caught, missiles counted, the tracking line logged.

### Scrambles and the leash (the controller: `control_air_flights/scramble_fighters.lua`, `track_alert_jets.lua`, directive `leash`)

Rebuilt 2026-09-30 (roadmap item 2; design agreed with John, recorded there). Moved under the controller on 2026-10-01 (roadmap item 11), unchanged in what it decides: the decisions in `scramble_fighters.lua`, the alert jets' state (ready, cooldown, turnaround, which scramble came from which base, held spots) in `track_alert_jets.lua`, bookkeeping only; `consumers/run_scrambles.lua` is gone. Its lines are `CONTROL` lines: `scramble`, `no scramble`, `stand down before launch`, `alert`, `leash home`, `leash stand down`. A scramble answers an immediate threat: it burns straight at the one raid it was sent after and chases it away or kills it, without flying head first into enemy airspace. First DCS run: session 11.

**Alert posture** (`planAlertPosture`, `AIR_DEFENSE`):
- held bases whose runway and parking fit an interception type (`COALITION_AIRCRAFT[c].interception`), the `alert_bases` (3) nearest the enemy, plus the nearest of each other region, so a pocket answers for itself;
- **not a base inside an enemy kill zone** (found in the harness: Vuojarvi under a Blue ring had no way out that didn't start in the kill zone);
- **3 alert jets per base** (`alert_aircraft_per_base`), 15 min cooldown between launches. A jet that lands is back on alert `scramble_turnaround_s` (30 min) later; one shot down is gone for the mission (John, 2026-09-30: a base shouldn't run out if its jets came back; replaced the first version's fixed 3 launches, which ran Red dry ~1.5 h into the first run). `plan.air_tasking_orders[c].alert = { bases = { { base, code, region, aircraft, pos, enemy_km, alert_aircraft, cooldown_s, spots } }, max_airborne_aircraft, first_number }`.
- **Alert spots** (2026-10-01, bug 7): the posture is planned before the patrols, and each alert base holds `alert_aircraft_per_base` ramp spots for the whole mission (`reserveAlertSpots`: free of statics, player slots and planned flights, a terminal type every interception type there fits, nearest a runway). No planned flight gets them; scrambles spawn only on them. A base that can't spare them isn't an alert base.
- Session 11's roll: Red Alakurtti, Koshka Yavr, Banak; Blue Kuusamo, Ivalo, Vuojarvi.

**Trigger** (every radar-picture round):
- a tracked contact with a known range, not a helicopter, that is over own airspace, or that the picture has inbound on an own asset it will reach within `scramble_warning_min` (15) minutes for `scramble_inbound_rounds` (2) rounds in a row, in whatever airspace it is now;
- **refused** (logged once per reason, checked again every round) when a live scramble is already after it, when an airborne patrol's defended zone or commit circle covers where it is, or **while it is inside an enemy kill zone** ("under enemy SAM cover": the leash would only bring the fighter home again; found in the harness, where a raid loitering under Blue SAMs burned 4 launches in 15 minutes).

**The raid:** the trigger plus the other contacts within `raid_radius_km` (20) on a heading within `raid_heading_deg` (45); one scramble takes them all, `EngageGroup` on each, in order.

**The base:** the nearest ready alert base in the region facing the raid (`DivideAirspace.facingRegion`) whose intercept point is in reach and at least `scramble_min_leg_km` (10) out, that gets there before the raid reaches what it threatens (the mean reaction delay + `scramble_takeoff_s` 150 s + the dash, against the raid's `threat_minutes`; John, 2026-10-01), with a free alert spot; never over `max_airborne_aircraft`: the planner keeps `scramble_reserve_aircraft` (2) of it free (2026-10-01; it used to allow `scramble_over_cap`, 2 over). The intercept point is the raid pushed ahead along its heading by the scramble's flight time, pulled back in 5 km steps until it lies in own or contested airspace outside enemy kill zones.

**The launch:**
- after `scramble_reaction_s` (60–120 s, cockpit alert), **hot on one of its base's alert spots, never the runway** (John: no spawning on top of jets lined up there): the first of the base's `spots` that `Airbase:getParking(true)` reports free. If the raid is gone by then, or no spot is free, the scramble is **stood down before launch** and its jet stays on alert. A jet the leash stands down on the ramp is back on alert at once (`TrackAlertJets.stoodDown`);
- **the session 7 fixes:** `EngageGroup` on the takeoff waypoint, so it's active from wheels-up and the AI flies its own intercept (it used to sit on waypoint 2, the intruder's position at launch, and DCS starts a waypoint's tasks only on arrival); waypoints at the profile's `dash_speed_mps` (F-16 / F/A-18 325, F-15C / Su-27 / Su-30 / Su-33 355, MiG-31 440 m/s) with afterburner explicitly allowed (option 16 false), instead of `speed_locked` at cruise speed; `open_fire`, no `EngageTargets` on everything; one-ship, `interception` loadout, gun kept, may jettison;
- then `ScheduleAirTaskingOrders.track`, `TrackRadarPicture.addFlight` (its radar joins the picture) and `ControlAirFlights.watch(m, { targets })` (mission type `interception` gets the `leash` directive).
- Ids `MSN2901_SCRAM+` / `MSN5901_SCRAM+`.

**The leash** (`AIR_CONTROL.leash` in `data/air_control.lua`), checked every picture round per watched flight:
- **home** when every raid group is dead, dropped from the picture, or back over its own airspace **heading away** (not `inbound`; a raid that only dips over its own airspace on the way in is still a raid); or when the scramble itself is more than 5 km into enemy airspace (distance to the nearest contested cell) or inside an enemy kill zone (85 % of a live medium / long-range ring);
- **stood down** (the group removed) if the raid is gone before it leaves the ramp;
- going home: `Controller:setTask` with a new airborne mission (from where it is to a landing at its base, cruise speed) and rules of engagement "return fire". Once sent home it isn't watched any more; the scheduler removes it after landing. Fuel is DCS's (bingo).
- `ControlAirFlights.onTask(id)` tells scrambles whether a flight is still hunting.

**Offline harness** (`scramble_harness.lua`, session scratchpad; not kept): real 14:36 plan with air tasking re-planned, the real picture, rules, scrambles and aircraft spawner over stubbed DCS; one Blue jet Rovaniemi → Olenya. Checked: the spawned group (hot ramp start, `EngageGroup` on waypoint 1, afterburner option, dash speed and interception altitude on waypoint 2), the leash's `setTask` / return-fire option, stood down before launch, patrol cover, SAM cover, and the kill-zone leash when the scramble chases into Blue's rings.

**First DCS run** (session 11, ~48 min, watched): Red decided 6 scrambles, Blue 4.
- **Burning straight at the raid works:** John: MSN2901 and MSN5902 "did exactly what we wanted as a scramble", though MSN2901's path looked a little odd (its intercept point was 239 km out; once airborne the AI flies its own intercept geometry).
- **Kills:** scrambles scored 4 kills for 2 losses. MSN2901 (F-15C) killed a Su-33 patrol with an AIM-120 fired just before the kill-zone leash sent it home; MSN5901 (Su-30) killed both F-16s of a Blue DEAD; MSN5903 (Su-27) killed a SEAD F/A-18, then fell to a Blue patrol.
- **Every leash reason fired:** kill zone, target destroyed, target lost from the picture, heading away; plus stood down on the ramp (MSN2904) and stood down before launch (MSN5904, MSN5906).
- **`setTask` home lands them:** MSN2902 was sent home just after takeoff (its target was already gone), circled in the landing pattern and landed 5 min later (John agreed: going home is right when the target is gone). MSN2901 landed ~17 min after its leash.
- **Refusals:** "under enemy SAM cover" 7 times (mostly Blue patrols orbiting under Blue SAMs), "covered by patrol" twice. A scramble at an enemy patrol that looks like a raid is fine (John: Blue can't know a jet's intentions).
- **Budget:** the first version's 3 launches per base would have run Red dry ~1.5 h in → alert jets now return after landing (above).

### The controller (`consumers/control_air_flights/`, `data/air_control.lua`)

Built 2026-10-01 (roadmap items 4 and 11; design agreed with John the same day), not run in DCS with a fight yet. **Every decision after the plan is made and the mission has started about what AI flights do lives here** (John: no code all over the place serving that function): which flights launch when (`decide_launches.lua`: packages in sequence, waits, retries, cancels, late launches, and the airborne cap, one count for planned flights and scrambles alike), scrambles (`scramble_fighters.lua`, with the alert jets' bookkeeping in `track_alert_jets.lua`), and what flights in the air are told (the directives). The plan says what should fly; the scheduler keeps the clock and the record and asks the controller when a flight is due (`ControlAirFlights.due`), then carries out what it decides (`launchNow`, `flyAgain`, `lookAgainAt`, `note`); the radar picture is what the controller knows. **One event word, `CONTROL`,** for every decision, the decision first (John: grep `CONTROL` to see what this layer is doing): `watching`, `defend`, `back on mission` / `back on way home`, `leave threat`, `go cold`, `leash home`, `leash stand down`, `scramble`, `no scramble`, `stand down before launch`, `alert`, `wait`, `retry`, `cancel`, `launch late`. **DCS AI is the pilot**: once it has a directive it flies, evades, shoots and goes home at bingo by itself. What it lacks is someone watching the whole picture and making the calls ("bandit, hot, commit", "go cold", "RTB"); the controller does that, one per coalition (John: controller-heavy, no separate pilot rules).
```
 what is known ──► situation per flight ──► directives ──► one intent ──► orders
 radar picture,     assess_flight_          directives_     coordinate_     give_orders
 the flight's own   situations              per_flight      flights         (only when the
 state, the plan                                            (who takes      intent changes)
                                                            which threat;
                                                            priority)
```
- **Watched flights:** every AI flight whose mission type has directives (`AIR_CONTROL.directives_by_mission_type`: strike, airfield strike and DEAD → `self_defence`; SEAD → `suppression` + `self_defence`; interception → `leash`), from spawn (`ControlAirFlights.watch`, called by the scheduler and the scrambles) until it lands or is lost. Patrols and the AWACS have none yet.
- **The situation** (`assess_flight_situations.lua`): facts about one flight at one check, worked out only when a directive asks: position and airborne, velocity, air-to-air missiles aboard (all, radar-guided, the longest-reaching radar missile), anti-radiation missiles aboard, threats (enemy airplanes the picture tracks within the 100 km warning range, plus whoever just fired at it at any range, with live range, aspect and closing speed), the last missile fired at it. Directives never ask DCS themselves.
- **Directives** (`directives_per_flight.lua`) each return an intent: `home`, `stand_down`, `defend`, `resume`. Each runs on a clock: the radar picture's round (30 s: `leash`, `suppression`) or the fast check (`AIR_CONTROL.check_every_s`, 5 s: `self_defence`). `leash` and `suppression` are the old rules, moved over unchanged; they stop once a flight is sent home (`on_task_only`), `self_defence` doesn't.
- **One intent per flight:** the highest of `AIR_CONTROL.intent_priority` (stand down > home > resume > defend). **Across flights** (`coordinate_flights.lua`): one enemy group is taken by one flight only, nearest first; a flight already fighting one keeps it.
- **Orders** (`give_orders.lua`), only when the intent changes: home = `setTask` with a route home (a SEAD flight turns around and goes back the way it came) and return fire; defend = `pushTask` of an `AttackGroup` on the threat inside a `ControlledTask` that stops after `max_engage_s` or when its own user flag is set (flags 9100000+); resume = set that flag. Never `popTask`: if DCS had already dropped the fight (target destroyed), it would pop the mission itself. A flight going home that defends gets open fire for the fight.
- **Reports:** a missile fired at a watched flight (`S_EVENT_SHOT`, its target in the flight) runs its coalition's fast check at once, and the shooter counts as a threat whatever its heading.
- **Self-defence: the bandit call** (rebuilt 2026-10-01 after the 20:31 run; John: "you would tell them immediately a fighter is inbound … if you know they have the weapons to engage, you tell them, if you know they don't, you tell them to leave"). The controller decides the moment the picture shows a **bandit**: an enemy airplane it tracks within `warning_range_km` (100) that is pointed at the flight (within `hot_aspect_deg` 45) and closing (≥ 50 m/s) on `hot_checks_before_call` (2) fast checks in a row (so a patrol's race-track leg swinging past doesn't count), or one that fired at the flight in the last 30 s **at any range** (the shot gives it away, picture or not).
  - **Can fight** (radar-guided air-to-air missiles aboard; infrared ones alone don't count, John): `defend` at once, an `AttackGroup` on the bandit; the DCS AI flies the intercept and shoots when its own missiles allow. After the fight it always carries on with its mission (John: "that's what they are there for after all").
  - **Can't fight** (infrared missiles only, or none: the Su-24M, the Tu-22M3): `leave`, sent home (John: the patrol isn't going anywhere, it stays on station and circles). A flight already going home isn't sent again.
  - The fight ends (`back on mission` / `back on way home`) when the bandit is destroyed, dropped from the picture (not while it fired at the flight in the last 30 s, bug 30), beyond 100 km, turned cold (aspect > 110°), after 3 min, when the flight is out of radar missiles, or when the fight takes it into an enemy kill zone its route doesn't pass through on purpose; then it may engage again after 30 s. `CONTROL` lines `defend`, `leave`, `back on mission` (or `back on way home`), `leave threat`.
  - **Why** (20:31 run, `event_logs\2026-10-01_203147.log`): the first version engaged only inside 0.6 × its own missile's range (21 km with the R-27R) and looked no farther than 1.5 × that, so the F-15C patrol MSN2002_CAP's AIM-120 shot at MSN5024_SEAD from 47 km went unanswered; `defend` came at 19 km, a second after the lead was hit, and both Su-34s died. Red's picture had held the F-15C the whole time.
- **Harness** (`controller_harness.lua`, session scratchpad, not kept; 40 checks after the bandit call): a MiG hot at 120 km ignored, at 90 km called on the second hot check and engaged at once, the farther strike leaving it to the nearer, cold → flag set, held 30 s, engages again, destroyed → back on mission; a crossing Su-27 ignored until it fires (wake at once); an infrared-only strike and a strike with no air-to-air missiles leave (once), a fighter hot for one check then turning across not called; a shot from 130 km by a group not in the picture engaged at once; a SEAD out of HARMs sent home, then defending with open fire; the leash's stand-down and home; a landed flight unwatched.
- **Item 11 checks** (same harness, with the real scheduler): a patrol due late launched on spots free now (`launch late`); a SEAD on time launched and watched; a SEAD whose site is already dead not sent; a strike waiting while its SEAD is up, its SEAD flown again when it is gone, the strike cancelled when that fails too; a scramble decided, launched and leashed; the last alert jet committed, stood down before launch and refunded, then spent on the next raid; "no alert base with a jet ready" said once; a landed scramble back on alert in 30 min. A smoke run on the 16:21 plan (`real_plan_harness.lua`): 2 h of mission clock, 23 flights launched, no errors.
- **To check in the next DCS run:** that `AttackGroup` pushed on top of a mission really engages an air group from ~100 km (the AI flies the intercept), and that the user flag ends it and the flight resumes its route and attack; that `leave` turns a bomber home before the fighter reaches it. (DCS does give `rangeMaxAltMax` for air-to-air missiles: 35 km for the R-27R, 20:31 run.)

### Air picture calls (`consumers/call_air_picture.lua`, `data/air_picture_calls.lua`)

Built 2026-10-02 (roadmap item 5, text first; `closed.md`), first flown in the 00:57 run: the calls looked right and magvar works in the game. John's calls: no bullseye ("kind of a pain"), every bearing from the player's own position, no "bogey dope" to ask for; all known contacts in one list, highest threat to the player first; every 2 min, 14 s on screen (7 until John raised it the same day), short lines read at a glance (John's format, same day); only what the player's own coalition's radars see (`TrackRadarPicture`).
- **Who gets it:** every player in an aircraft (`coalition.getPlayers`), on the ground too (`on_the_ground`), one list per group from its first player; `outTextForGroup` for `show_s` (14) every `call_every_s` (120); other texts stay on screen.
- **The list:**
  ```
  DARKSTAR picture, 4 groups
  MiG-29S - 110/120nm, 10k, hot, 0s
  Su-30 - 255/?nm, low, flank SE, 0s
  MiG-31 - 343/60nm, 30k, beam E, 70s
  unknown - 027/40nm, 25k, drag NE, 0s
  ```
  Type (once any sensor identified it, else `unknown`) - magnetic bearing / range (`?` when no sensor knows it, e.g. a jammer), altitude in thousands (`low` under 1,000 ft), aspect from the contact's heading against the line to the player (hot ≤ 30°, flank ≤ 70°, beam ≤ 110°, else drag; flank, beam and drag carry the contact's track as N / NE / …; `slow` under 20 m/s), and how old the position is (seconds since a radar last saw it: under 30 while tracked, more once stale). At most `max_groups` (10) lines, then "+N more"; `clean` when the picture is empty. Header callsign per coalition (`DARKSTAR` / `OVERLORD`).
- **Threat order:** range × `threat_range_factor` by aspect (hot 1, flank 1.5, beam 2, drag 3), smallest first.
- **Bearings:** true from the two positions' lat/lon (the map grid is skewed from true north toward its edges), then magnetic with DCS's `magvar` module (`require "magvar"`, `get_mag_decl(lat_deg, lon_deg)` in radians, `init(month, year)`: what the mission editor and the DTC use). In `luae` it loads but answers 0, so a start-up self-test at Rovaniemi drops it when it answers near 0 and uses the approximate table by longitude (`fallback_magnetic_variation`: Bodø +5° … Murmansk +16°). `dcs.log` (grep `air picture`) says which one is used, and both values at Rovaniemi.
- **Facts and text apart** (`describe` vs the text functions), so the AI radio calls (item 7) can speak the same facts later.
- **Event log:** `PICTURE_CALL`, one line per player per call: the number of groups and the first one's line.
- **To check in the first run:** that magvar works in the game (`dcs.log`), bearings and ranges against the F-16's HSD, whether 14 s is long enough to read the list.

### Event log (`consumers/write_event_log.lua`, `data/event_log.lua`)

Built 2026-09-30 (roadmap item 3). A catalogue of everything that happened in the air war, in plain language, unit by unit (John: comb through it and see exactly how the mission unfolded per unit, step by step, without affecting game performance). First run in DCS on 2026-09-30.
- **File:** `event_logs\<wall-clock date>_<time>.log` in this mission folder, a new one per run (John: timestamped files; in the repository, not the DCS game folder, and git-ignored). Old files stay, for comparing runs.
  - The folder is an absolute path in `EVENT_LOG.folder`, since the script runs from its copy under `Saved Games\DCS\Scripts`.
  - If that folder can't be written (another machine, the repository moved), the log goes to `Saved Games\DCS\kola_event_logs\` (`EVENT_LOG.fallback_folder`); if neither, to `dcs.log`.
- **Top:** the plan, to read the timeline against: territory, weather, SAM sites (id, system, layer, ring), alert bases, the air tasking order (spawn / takeoff / TOT or on station / end per flight; human flights marked), convoys.
- **Timeline:** one line per event, in fixed columns: local clock, time since start, coalition, event word, subject, details.
  - **Subject:** a unit name for unit events, a group name for flight events (spawn, waypoint, scramble), and the contact's group for radar-picture lines (whose coalition is the picture's owner).
  - **Details** always name the other party in full, so grepping a name finds both what it did and what was done to it.
  ```
  08:11:50  T+00:11:50  RED   SHOT         MSN5901_SCRAM_1             Su-30 fired P_77 at MSN2025_2 (F-16C_50), 103 km, from 29,528 ft
  08:12:00  T+00:12:00  BLUE  HIT          MSN2025_2                   F-16C_50 hit by ZU_23_shell (5 hits) from DEF_OLEN_towed_anti_aircraft_guns_1_2 (ZU-23 Emplacement), 22,966 ft, …
  08:12:31  T+00:12:31  BLUE  DESTROYED    MSN2025_2                   F-16C_50 by MSN5901_SCRAM_1 (Su-30) with R-77, 22,966 ft, own airspace, 135 km outside SAM_ALTA_SA11_1
  ```
- **End:** on `S_EVENT_MISSION_END`, a summary:
  - flights launched;
  - aircraft lost by cause (aircraft / SAM sites / base defenses / other ground units / no killer recorded);
  - ground units and objects destroyed;
  - each flight's outcome (`ScheduleAirTaskingOrders.statusOf`).

  If DCS crashes, the file ends at the last write.
- **Events caught here for every unit** (one DCS event handler):
  - `SHOT`: the weapon, the target and range when `Weapon:getTarget` knows it, and the shooter's altitude;
  - `GUNS` (`S_EVENT_SHOOTING_START`) and `HIT`;
  - `DESTROYED` (units and static objects, never scenery), `CRASHED`, `EJECTED`, `PILOT_DEAD`, `PARACHUTE`;
  - `TAKEOFF`, `LAND`, `PLAYER_IN` / `PLAYER_OUT`;
  - `ABORTED` (`S_EVENT_AI_ABORT_MISSION`, if this DCS version has it).
- **Events handed over by other modules** (`WriteEventLog.add`):
  - the spawner: `SPAWNED`, `LOADOUT`, `WAYPOINT`;
  - the scheduler: `TARGET`;
  - the radar picture: `CONTACT`, `TRACKING`, `PICTURE`;
  - the controller: `CONTROL` (every decision about flights: launches, scrambles, alert jets, directives).
- **`POSITION`:** every airborne aircraft, AI and players, each `position_every_s` (60): type, speed, heading, fuel, altitude, airspace, nearest enemy ring, and km from station centre for patrols. It replaces the old `track:` lines (patrols and the AWACS every 2 min).
- **`WAYPOINT`:** a `WrappedAction` `Script` command, first on every waypoint between takeoff and landing, calls `WriteEventLog.waypoint(id, index)` when the flight gets there, so there's no polling. The line names:
  - the waypoint's kind: ingress (pushing, attack tasks active), target (with the planned TOT and minutes late or early), on / off station;
  - the lead's altitude, airspace and ring;
  - the aircraft left.
- **Folding** (John: gun hits collapsed so they don't spam the log): each line is held `hold_s` (10 s) before it's written. A repeat within the fold window of the last one adds to that line's count instead of making a new line:
  - hits by the same shooter on the same target with the same weapon, within 5 s: "(5 hits)";
  - shots of the same weapon at the same target, within 5 s: "fired 4x FAB-500";
  - a gun opening up again, within 10 s: "(3 bursts)".

  A death is reported once, from whichever DCS event comes first (kill, dead, unit lost). A kill that arrives while the line is still held fills in who did it.
- **Performance:**
  - a DCS event only builds a line in memory;
  - lines are written every `write_every_s` (5 s), in one `write` + `flush`;
  - the only polling is `POSITION`: ~32 `getPoint` calls a minute at the airborne cap;
  - if the file can't be opened, the lines go to `dcs.log` (`event:`).
- **Watching it live:** these follow the newest file, so start them after the mission has loaded (each run makes a new file).
  - PowerShell: `Get-Content (Get-ChildItem "$env:USERPROFILE\Git\dcs\missions\kola_f16_random_tasking\event_logs\*.log" | Sort-Object LastWriteTime | Select-Object -Last 1) -Wait -Tail 40`. Without the positions, add `| Where-Object { $_ -notmatch 'POSITION' }`.
  - Git Bash: `tail -n 40 -f "$(ls -t ~/Git/dcs/missions/kola_f16_random_tasking/event_logs/*.log | head -1)"`. Without the positions, add `| grep --line-buffered -v POSITION`.
- **Offline harness** (`event_log_harness.lua`, session scratchpad; not kept): the real spawner, scheduler and event log on the last plan, with stubbed DCS. It checked:
  - the spawner's waypoint commands and task numbering;
  - folding of bombs, gun bursts and hits;
  - a kill arriving after the dead event, and a scenery kill ignored;
  - lines in time order, and nothing after the mission end;
  - the plan header and the summary.

### Sleeping ground units (`consumers/sleep_ground_units.lua`, `data/ground_unit_sleep.lua`)

Built 2026-10-01 (the performance-in-VR item, now in `closed.md`); run once in 2D the same day, where one base woke and slept as designed. A sleeping group has its AI off (`Controller:setOnOff(false)`), so it doesn't scan the sky. Standing units cost little by themselves; ~500 of them checking every aircraft and missile is what multiplies.
- **What sleeps:** base-defense groups of `GROUND_UNIT_SLEEP.components`: towed and mobile guns, infrared missile launchers, MANPADS teams (and security infantry if it comes back). **Never:** SAM sites (the air denial) and `radar_missile_launchers` (they reach ~20 km and feed the radar picture).
- **Per base, every 10 s:** all its sleeping groups wake together when an enemy aircraft (plane or helicopter, AI or player) is within `wake_km` (30) of the base, with alarm state red. They sleep again once no enemy has been within 30 km, and the base hasn't fired, for `sleep_after_s` (180), so a base never sleeps mid-fight or flaps. Everything starts asleep.
- **Watching for problems** (John: see problems without spamming the log):
  - `UNIT_AWAKE` / `UNIT_ASLEEP`, one line per base per switch, subject `DEF_<CODE>`; the asleep line sums that wake: close passes, shots, hits, kills.
  - `LATE_WAKE`: an enemy within `reach_km` (10) of a base that was asleep. Never expected; it means the wake-up missed an aircraft.
  - `(asleep)` at the end of a `HIT` or `DESTROYED` line of a sleeping unit.
  - `AWAKE_COUNT` every 5 min per coalition: bases and units awake.
  - **End summary:** per base that woke: wakes, minutes awake, close passes (enemies within 10 km while awake), shots, hits, kills, late wakes; `CHECK` on a base with 2+ close passes and no shot (DCS may not have woken it properly).
- **Off switch:** `CONFIG.SLEEP_GROUND_UNITS = false` keeps everything awake, to compare a run.
- **Harness** (`sleep_harness.lua`, session scratchpad, not kept): the 21:37 plan's 174 sleeping groups off at start; a Blue jet woke Vuojärvi at 30 km, a gun burst kept it awake, and it slept 3 min after the jet died; a jet appearing 8 km from Alakurtti gave `LATE_WAKE`; a hit on a sleeping MANPADS team read `(asleep)`.

### Player slots (`data/player_slots.lua`)

- **Templates:** John places F-16C dynamic-spawn templates (group `f16_<base>`, one per base) in `kola_f16_random_tasking.miz`; DCS spawns the player on the template's exact spot. In the ME, the always-Blue / always-Red bases have their coalition set; contested ones are neutral and the script sets them.
- **Now 8 slots:** Banak, Bodø, Ivalo, Kallax, Kemi-Tornio, Kiruna, Rovaniemi, Tromsø.
- **Data file:** `kola_data_tools/miz_player_slots.py` → `data/player_slots.lua` (`PLAYER_SLOTS[base]` = terminal index, spot name, group, type, position). Re-run it after moving or adding slots (not after renaming units: it keeps group names only).
- **Unit names** match their group (`f16_rovaniemi-1-1`; John renamed them 2026-10-02: the templates were copies of Kallax's, bug 24).
- **Datalink in the templates:** country CJTF Blue (the AI's country; USA until 2026-10-02), each slot its own Link 16 STN (00201–00211), a team of itself only, no donors and an empty DTC. That is enough: AI flights show as datalink contacts without being in the team (the Caucasus test). A human 2-ship would list each other's STNs as team members; an AWACS donor would need the E-3A spawned with a fixed unit id (bug 26).
- **Kept clear:** `gather.lua` attaches `player_slots` to each airbase and warns when a slot's spot is missing or has moved. Parked-aircraft statics and AI parking skip those spots; ground units already keep clear of every parking spot.

### Brief (`consumers/brief_air_tasking.lua`)

- **Start text** (3 min, `START_MESSAGE_S` 180): the weather plus one line per human tasking (base, slot, takeoff, TOT, what). Nothing else on screen at start (John).
- **Comms menu** for Blue (`\` > F10. Other...; John: call it the comms menu, F10 means the map):
  - `Human taskings > <MSN> > Frag / Steerpoints`, and `All human taskings`;
  - `Air tasking order > Attack packages / Patrols and AWACS / All flights`, each flight with its state.

  Texts stay 60 s; the frag 180 s and the steerpoints 300 s (John, 2026-10-01). `Hide text` at the top of the comms menu clears the screen.
- **Frag contents:**
  - times (local);
  - target: description, degrees and decimal minutes (F-16) + MGRS + elevation, aim points, success as "destroy at least n of its m critical objects";
  - the loadout planned for an AI jet;
  - threats: enemy SAM rings the route crosses or passes within 20 km of, with who suppresses each;
  - the package;
  - **SEAD frags** add the escorted mission and "your" threats; **CAP frags** add the orbit, the defended zone and the other patrols.

  Every frag and steerpoint list also goes to `dcs.log` (`HUMAN TASKING`).
- **Steerpoints** (2026-10-01, bugs 10 and 11): the route out to `TGT` (or `CAP B`), then `LAND`; no egress or way home. `TGT` and each aim point (`AIM 1`, `AIM 2`, …) give the spot on the ground with its elevation, for fire-and-forget weapons; route points give the flight altitude.
- **Static kills** (2026-10-01, bug 9): a player who destroys a static object the mission spawned gets a 15 s popup (DCS's kill list doesn't show static objects), with the human tasking's critical progress and "target destroyed: success" when its target is reached. Credited through the weapon if the player is gone by impact.
- **Not built yet:** tanker and AWACS frequencies and callsigns, threat fidelity (every SAM ring is listed as known; see *Design*), fuel, ROE, in-flight updates.
- **Warnings stay off screen** (`CONFIG.WARNINGS_ON_SCREEN = false`); errors still show.

### Zones: the ground-unit dataset (`data/zones.lua`)

Every ground unit except base defenses spawns inside a surveyed zone.
- **What a zone is:** exactly one thing, a clearing where ground units can realistically be placed. It has no side, no role and no substance (John): the planner assigns everything at run time from size, distance to bases and the front, and road access.
- **Where zones come from:**
  - drawn as ME trigger zones (circle or quad) in a survey file that is never flown: `Saved Games\DCS\Missions\khola_ground_zones.miz`;
  - `kola_data_tools/miz_zones.py` parses it into the committed `data/zones.lua`, the **only** source the plan reads;
  - the flyable mission contains no zones.
- **Names are generated, never typed** (John): `ZONE_<BASE>_<brg>_<km×10>` from the nearest airbase (e.g. `ZONE_KITT_100_012`: 1.2 km on bearing 100° from Kittilä). Each entry keeps the ME's `zone_id`, which is stable while the zone exists, as the key.
- **Coordinates:** projected metres, `x` north and `z` east. Lat/lon are computed in-sim with `coord.LOtoLL`. The tool's own transverse-Mercator (`kola_proj.py`) is verified to ~10 m.
- **Side:** each zone carries its nearest base's `cluster` and inherits that cluster's rolled side.
- **Classes** (precomputed offline, one question each; John rejected an in-mission classifier): `size`, `airfield_distance`, `ground`, `terrain`, `road_access`, `railway_access`, `water`, `radar_view`, `settlement`, `prepared_sam_position`, plus `surveyed` and `measured`. Thresholds (`CLASS_THRESHOLDS`, `OBJECT_CATEGORIES`) live in the tool.
- **127 zones**, all surveyed. The 15 border zones without a road can't hold garrisons, armor or depots, only SAMs, communications sites, and artillery where not steep.

**Workflow after drawing or moving zones** (John, 2026-09-27: the survey is part of the sequence, every time):
1. Save `khola_ground_zones.miz`.
2. Fly it once. `survey/survey_zone_terrain.lua` measures the terrain around every zone and writes `Saved Games\DCS\kola_zone_terrain.lua`.
3. At the end of that flight, the survey script calls `kola_data_tools/update_zone_data.cmd`, which runs `miz_zones.py` and copies the `kola_f16` tree to Scripts. The result shows on screen and in `Saved Games\DCS\kola_zone_update.log`.

Never regenerate `zones.lua` without the survey (unsurveyed zones get `unknown` classes). By hand: `kola_data_tools\update_zone_data.cmd "<.miz>" "<Saved Games\DCS>"`.

### Unit pool (`data/unit_pool.lua`)

What DCS needs to spawn a unit is one type string; an unknown string silently becomes a Leopard-2 (`woCar: … replaced with Leopard-2`).
- **Contents:** every AI-operable unit in base DCS, including the CoreMods packs (Currenthill `CHAP_*`, ColdWar, Massun92, HeavyMetal) but nothing from `Saved Games\Mods`. Generated by `kola_data_tools/unit_pool.py` from pydcs's source text.
- **Agnostic by design** (John): no side, country or era. Blue may field Russian SAMs; which coalition uses what lives only in `data/coalition_rosters.lua`.
- **Per entry:** `type`, `name`, `cat`, `role`, `system`, ED's `detection_m` / `threat_m` / `air_weapon_m`; for aircraft also `tasks`, `task_default`, `fuel_max`, `chaff` / `flare`, `pylons`, `flyable`, `large_parking`, `tacan`.
- **Static objects:** `static` holds every structure and cargo type with `category` + `shape_name`.
- **Roles:** from name heuristics plus `kola_data_tools/unit_role_overrides.json`; the tool reports anything unclassified.
- **Pylons:** `data/aircraft_pylons.lua` (pylon → allowed CLSIDs, 1.1 MB) is generated for offline validation only and never loaded at runtime.

### Weather and time (`lib/weather.lua`)

The runtime can read the mission's weather, time and date, but can't change them. Gather reads them once into `plan.world.weather` / `plan.world.time`:
- **Clouds and visibility:** clouds (preset, METAR text, coverage, base, ceiling, precipitation), visibility (capped by fog and a rain preset's range) and flight rules (VFR / MVFR / IFR / LIFR).
- **Wind:** at ground, 2,000 and 8,000 m.
- **Air:** temperature, QNH (the .miz stores mmHg), turbulence, dust.
- **Time and sun:** time, date, season and sun (elevation, condition, sunrise / sunset, polar day and night) at the airbase centroid. Kola clock is UTC+3.
- **Preset clouds:** a preset stores only `clouds.preset` + `clouds.base`. Coverage and layers come from `DCS World\Config\Effects\clouds.lua` via `kola_data_tools/cloud_presets.py` → `data/cloud_presets.lua`; re-run after DCS updates.
- **Wind direction:** the .miz stores the direction the wind blows *to*; the ME shows *from*.

### Offline tools and test harness

`kola_data_tools/` (stdlib Python, 3.7-compatible; pydcs and Liberation are reference clones, never dependencies):

| Run | When |
|---|---|
| fly `khola_ground_zones.miz` (runs `update_zone_data.cmd` itself) | after drawing or moving zones |
| `python kola_data_tools/miz_zones.py "<zones .miz>"` | after changing `data/clusters.lua` |
| `python kola_data_tools/miz_player_slots.py` | after moving or adding player slots |
| `python kola_data_tools/aircraft_loadouts.py` | after changing a loadout choice, re-running `unit_pool.py`, or updating the Liberation clone |
| `python kola_data_tools/unit_pool.py` | after a DCS update, once pydcs has caught up |
| `python kola_data_tools/cloud_presets.py` | after a DCS update |
| the footprint survey (`CONFIG.SURVEY_FOOTPRINTS`) | after a Kola map update |
| `python desanitize_dcs.py` (repo root, admin shell) + full DCS restart | after every DCS update |

- **Python versions:** `python` on PATH is a pyenv 3.7 shim; Python 3.10 is at `AppData\Local\Programs\Python\Python310`.
- **Offline test harness:** DCS ships Lua 5.1 as `DCS World\bin\luae.exe`. Stub the mission API and run the real `init.lua`, or one stage on real geometry from `kola_last_plan.lua`, before handing a change to John.
- **Random seeds in luae:** luae's `math.random` is the C `rand()`, and the first values after `math.randomseed(1..N)` are nearly linear in the seed. Seed with `seed * 7919` and discard ~50 values.

### DCS facts learned the hard way

- **Script-spawned units on the F-16's HSD** (bug 25, `closed.md`; confirmed 2026-10-02): what works, all together (several things changed in one run, so keep every part): AI aircraft with an explicit group id, EPLRS as the first task of the first waypoint (`WrappedAction` `EPLRS` naming that group id), a Link 16 STN and the editor's `datalinks.Link16` block per unit; SAM groups with `hiddenOnMFD = false`, Red's as country Russia; player slots as CJTF Blue with their own STNs. STN + `setCommand` EPLRS after a ramp spawn, with CJTF SAMs, showed nothing.
- **Static objects must spawn before any AI units.** After ~800 units, `coalition.addStaticObject` took ~3 s per parked aircraft (a 3-minute start-up stall); spawned first, 250 objects take 0.5 s. `init.lua`'s spawn block keeps this order ("KEEP THIS ORDER").
- **A player aircraft in the world slows every spawn:** 227 static objects took 71 s instead of 0.5 s with a Client F-16 on the ramp. So players come in by dynamic spawn after init.
- **First spawn of each aircraft type freezes the sim** (fixed by the preload).
- **Trees are invisible** to every API (`world.searchObjects` finds nothing in forest; `land.isVisible` is terrain-only). Taxiways and aprons read as `RUNWAY` in `land.getSurfaceType`; airfield buildings are visible as scenery.
- **`weapons_free` means engage anything detected;** with AWACS datalink that's a lot. Use `open_fire` + zone tasks.
- **An AI descends toward the next waypoint's altitude from the previous one.**
- **`os.execute` from DCS Lua silently runs nothing past ~260 characters:** use a `.cmd`.
- **Airbase queries return empty at T+0:** gather runs a few seconds in.
- **Harmless log noise:** "livery not found" (CJTF with no `livery_id`), missing wreck models (`Ural-375_p_1`, `MOBILE_GENERATOR_CRASH`).

### Performance

**Baseline** (John's F-16 flights, 2026-09-25, stages 1–3c, GPU-bound):

| | Everything spawned (~860 units + ~250 static objects, all `DRAW_*` on) | Empty map |
|---|---|---|
| Bodø, on the ground and low flyover | 45–60 fps, some stutter when panning | 48–65 fps |
| 25,000 ft | 70–75 fps | 70–75 fps |
| F10 map | 45 fps | 55 fps |

- **Reading:** standing ground units cost a few fps only close to a heavy base, and nothing at altitude. The F10 drop is most likely the ~600 debug marks. John tuned graphics settings; no mission changes.
- **To do:** re-test the same way now that AI flights and convoys run.
- **Rules of thumb:**
  - cost order: moving ground > AI aircraft > standing units with sensors > idle units / statics;
  - levers: `controller:setOnOff(false)` for far ground groups, statics for non-shooting targets, few infantry.

---

## Design, not built yet

**Threat-intel fidelity rule** (for the brief and fog of war, roadmap item 9). Fidelity follows the threat's real-world nature, not a difficulty setting:

| Threat class | In the brief as | Map |
|---|---|---|
| Fixed strategic SAM (SA-10 class, long range) | **CONFIRMED**: type, exact coordinates, status, engagement ring | Ring drawn |
| Mobile SAM (SA-6/8/11/15) | **PROBABLE**: type + "operating vicinity <area>"; or **POSSIBLE**: type and region only; a fraction **unlisted** | Area circle (±5–10 nm) or nothing |
| Point defense (AAA, MANPADS) | Generic: "expect AAA / MANPADS in target area" | None |
| Air | Per-base types, assessed CAP station *area*, QRA timing | Station area |
| Target itself | Exact | Mark |

Roll it per mobile SAM each session. Surprise threats then have a realistic justification: the RWR is the last line of intel.

**What a pilot would realistically be told**, and what we'd give:
- **Frag** (mission number, callsign, target + coordinates + elevation, TOT, package) → built.
- **SPINS / comm-nav** (ROE, tanker track / TACAN / frequency, AWACS frequency, divert fields, sunrise / sunset) → divert = nearest 2 held bases; sun data is already in `plan.world.time`.
- **Mission data card** (steerpoints, joker / bingo) → steerpoints built; fuel estimate not built.
- **Air order of battle** → from each side's standing posture (stations, base types), never its timeline.

**No side reads the other side's plan.** Neither planner predicts the other's behaviour. Each side plans from the static picture (territory, the front, fixed sites, its own assets); responsiveness comes from a runtime reaction loop (scrambles) and native DCS AI. Red defends what Red values, with no knowledge of which target is the player's.

**Callsign policy: the radio callsign isn't the group name.**
- **Two identities:** the DCS group name is the machine id (`MSN2041`) and is never spoken. The radio callsign is a separate field drawn from DCS's built-in callsign enum, which drives the AI voiceovers *and* is what the brief prints, so what's written matches what's heard.
- **Blue pools per role:** fighters `{Springfield, Colt, Dodge, Ford, Chevy, Uzi, Enfield, Pontiac}`, tankers `{Texaco, Arco, Shell}`, AWACS `{Magic, Overlord, Wizard, Darkstar}`. The player gets a reserved fighter callsign by role (SEAD → Springfield, strike → Colt, CAP → Dodge…).
- **Audible but not overwhelming:** enum callsigns go to player-relevant Blue air (own flight, package-mates, covering CAP, tanker, AWACS); the airborne cap limits simultaneous transmitters.
- Roadmap item 7 (AI radio calls) builds on this.

**Weather as a planner input** (reading works; the planner doesn't use it yet):

| Weather fact | Planner consequence |
|---|---|
| Low ceiling / thick cloud | Down-weight laser-guided and visual weapons; favour JDAM / HARM (GPS works through cloud) |
| Poor visibility / fog / precipitation | Suppress visual recon and CAS; widen mobile-SAM assessed areas |
| Night / polar night | TGP- and night-appropriate loads; may suppress visual CAS |
| Wind aloft | Orient tanker and CAP tracks into wind |
| Temperature + QNH + field elevation | Density-altitude check on short fields; correct altimeter in the brief |
| Ceiling + visibility | VFR / IFR per base: recovery and divert choice |

**Weather and time variety** can't be done in Lua at runtime. Options:
1. fixed ME weather (now);
2. several `.miz` variants;
3. **pydcs pre-generation:** a Python step writes weather, time and date into the `.miz` before launch. The most powerful option, since Python already runs on the server box. Open: now, later or never.

**Later, from the original concept:**
- **Objective tracking:** a per-mission handler counting kills against the target's critical objects → success or fail, reported to the player. Open: binary, or a score tied to a cost tracker like Syria's?
- **Session history** (`Saved Games\DCS\kola_f16_history.lua`): mission type, target, base, outcome, to down-weight repeats. Plus `FORCE_MISSION_TYPE` / `FORCE_TARGET` overrides for testing.
- **Tankers** on tracks behind the front, with TACAN and frequency in the frag (range: Bodø → Murmansk is ~700 km; an F-16 with 2 bags and a strike load is tight past ~300 nm radius).
- **Other mission types:** naval strike on moored ships in Kola Bay (ship-spawn research needed), recon of a mobile target in a search box, CAS from Syria's `cas_mission.lua`.

---

## Architecture

**Relationship to the Syria code: completely separate.** No shared library; Kola keeps its own copies of whatever it borrows. The Syria mission must keep working exactly as it does, and sharing code would put that at risk.

**The plan is one table.** The stages build one accumulating plain-data Lua table; each stage reads earlier keys and adds its own.
- **Nothing spawns until planning is done**, so later stages (air tasking, brief) see the complete picture.
- **Stages may ask the terrain, never the live sim:** `land.getSurfaceType`, `land.getClosestPointOnRoads` and heights are fine during planning; reading or creating DCS objects happens only in gather and the consumers.
- **Plain data only:** no DCS handles or functions. So the plan dumps to `Saved Games\DCS\kola_last_plan.lua` and can be replayed offline.
- **Complete entries:** each entry carries everything its consumer needs (unit types, positions, headings, routes).
- **Immutable once built:** consumers read the plan and never write to it.
- **Runtime state lives elsewhere:** what launched, what's dead, cooldowns, keyed by the same ids as the plan.

**From mission start to a finished plan:**
1. The ME trigger fires `init.lua`, which loads the files.
2. Wait a few seconds (airbase queries return empty at T+0).
3. Gather all DCS reads into `plan.world`.
4. Run the stages back to back.
5. Dump the plan.
6. Hand off to the consumers.

**Consumers own the DCS formats.** The `coalition.addGroup` tables, waypoint and task tables, `outText` strings, menus and map marks are built from plan entries when used and thrown away. Going from an entry to an `addGroup` table is a translation, not a decision. One spawner per kind of DCS object (John), made flexible with optional entry fields, never a spawner per feature: `SpawnStaticObjects`, `SpawnGroundGroups` (optional `route`), `SpawnAircraftGroups`.

**Script layout** (`Saved Games\DCS\Scripts\kola_f16\`; loaded by one ME trigger, `ONCE → TIME MORE 1 → DO SCRIPT dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")`, with a de-sanitized `MissionScripting.lua`):
```
kola_f16\
  init.lua                       -- entry: load order + run sequence
  config.lua                     -- tunables and debug flags (CONFIG)
  gather.lua                     -- all DCS reads → plan.world (airbases + player slots, zones, weather, time)
  lib\
    util.lua                     -- RNG, picks, geometry, serialize, writeFile
    logger.lua                   -- dcs.log; errors (and warnings with CONFIG.WARNINGS_ON_SCREEN) on screen
    weather.lua                  -- weather + time/sun derivation
    placement.lua                -- isClear, findClear, ring/disc points, buildAnchors, pickAnchorPoint
    threat_routing.lua           -- threat map, routes around rings, priced by airspace
    sam_reach.lua                -- how far a SAM site reaches at an altitude; kill zones (SamReach)
  data\                          -- plain data, no logic; hand-authored or generated
    clusters.lua                 -- cluster table, bases per cluster (hand)
    zones.lua                    -- ground zones + classes (miz_zones.py)
    player_slots.lua             -- PLAYER_SLOTS[base] (miz_player_slots.py)
    airbase_classes.lua          -- AIRBASE_CLASS[name] + runway lengths (hand)
    airbase_codes.lua            -- 4-letter code per base (same codes as kola_data_tools/kola_airbases.json)
    airbase_footprints.lua       -- surveyed aprons / buildings (in-sim survey)
    forested_airfields.lua       -- fields with only a cleared overrun (hand)
    base_defense_levels.lua  base_defense_composition.lua  base_defense_placement.lua
    sam_site_recipes.lua  sam_site_density.lua
    fixed_ground_target_recipes.lua  fixed_ground_target_density.lua
    convoy_recipes.lua
    coalition_rosters.lua        -- the only file that knows red from blue (ground, SAM, targets, aircraft)
    air_tasking.lua              -- mission types, tasking, timing, packages, AIR_DEFENSE, routing, HUMAN_TASKING
    airspace.lua                 -- airspace grid settings
    radar_picture.lua            -- radar picture settings: polling, stale / drop times, sensor kinds, inbound
    air_picture_calls.lua        -- the players' air picture: period, aspect bands, threat order, callsigns, magnetic variation
    air_control.lua              -- the controller: directives per mission type, their settings, intent priorities
    event_log.lua                -- event log settings: folder, write interval, hold and fold windows, positions
    ground_unit_sleep.lua        -- which base defenses sleep; wake and reach distances, check interval
    aircraft_profiles.lua        -- per aircraft type: runway, parking, reach, speeds, altitudes (hand)
    aircraft_loadouts.lua        -- one loadout per type × mission (aircraft_loadouts.py)
    aircraft_pylons.lua          -- pylon → CLSID, generated; offline validation only, not loaded
    unit_pool.lua                -- every spawnable DCS unit type (unit_pool.py)
    cloud_presets.lua            -- DCS cloud presets (cloud_presets.py)
  stages\                        -- named by verb; run order lives in init.lua
    roll_territory.lua  plan_base_defenses.lua  plan_sam_sites.lua  divide_airspace.lua
    plan_fixed_ground_targets.lua  plan_convoys.lua  catalog_targets.lua  plan_air_tasking.lua
  consumers\
    write_event_log.lua          -- the event log: every event of the air war, unit by unit, one file per run
    territory.lua                -- apply the roll (to be renamed apply_territory.lua)
    spawn_static_objects.lua  spawn_ground_groups.lua  spawn_aircraft_groups.lua
    preload_aircraft_types.lua   -- first-spawn freeze fix
    schedule_air_tasking_orders.lua  -- the mission clock and each flight's record; asks the controller when a flight is due; target progress; statusOf
    track_radar_picture.lua      -- each coalition's radar picture: contacts, events, queries
    control_air_flights\         -- the controller: every run-time decision about AI flights (event word CONTROL)
      control_air_flights.lua    --   watching flights, the checks, picking one intent, CONTROL lines (ControlAirFlights)
      assess_flight_situations.lua  -- facts per flight from the picture, its own state, the plan
      directives_per_flight.lua  --   leash, suppression (go cold), self_defence
      coordinate_flights.lua     --   across flights: who takes which threat
      give_orders.lua            --   intent → DCS orders (setTask, pushTask, user flags)
      decide_launches.lua        --   a due flight: launch, wait, fly the suppression again, cancel; the airborne cap
      scramble_fighters.lua      --   scrambles: trigger, refusals, raid, base, intercept point, launch
      track_alert_jets.lua       --   the alert jets: ready, cooldown, back on alert (bookkeeping only)
    sleep_ground_units.lua       -- short-reach base defenses asleep (AI off) until an enemy aircraft is near
    brief_air_tasking.lua        -- start text + comms menu
    call_air_picture.lua         -- every 2 min the radar picture to each player: BRAA from them, highest threat first
    draw_airspace.lua  draw_base_defenses.lua  draw_sam_sites.lua  draw_fixed_ground_targets.lua
    draw_convoys.lua  draw_air_tasking_orders.lua    -- F10 map marks (all ToAll(-1) until fog of war)
  survey\                        -- one-off in-sim measurements, behind CONFIG flags or in the zone mission
    survey_airbase_footprints.lua  survey_zone_terrain.lua  probe_parked_aircraft_spawn.lua
```
Load order: `lib\*` → `data\*` → `stages\*` → `consumers\*`, then the run sequence.

**Naming and ids.** Every spawnable plan entry has a unique `id`, used verbatim as the DCS group name, so events map straight back to plan entries.

| Thing | Convention | Example |
|---|---|---|
| Zone (tool-generated) | `ZONE_<BASE>_<brg>_<km×10>` | `ZONE_KITT_100_012` |
| Base defense | `DEF_<CODE>_<component>_<n>`; units `<id>_<n>` | `DEF_OLEN_towed_anti_aircraft_guns_1` |
| SAM / EW site | `SAM_<CODE>_<system>_<n>`; escort `<id>_escort` | `SAM_SEV1_SA10_1` |
| Fixed ground target | `TGT_<CODE>_<kind>_<n>`; statics `<id>_static_<n>` | `TGT_IVAL_communications_site_1` |
| Convoy | `CONVOY_<FROM CODE>_supply_convoy_<n>` | |
| Flight | `MSN<n>_<tag>`: Blue 2001+, Red 7001+ (scrambles 2901+ / 7901+; Red was 5001+ / 5901+ until 2026-10-02, so older run notes and logs use those); units `<id>_<n>`. MSN = mission number, as in a real air tasking order. Tag = the mission type's `group_name_tag`: `STRIKE`, `OCA` (offensive counter-air: airfield strike), `SEAD`, `DEAD`, `CAP`, `AEW`, `SCRAM` (John, 2026-09-30) | `MSN2025_DEAD`, `MSN2901_SCRAM` |
| Package | `PKG<n>`, n = the mission it escorts | |
| Patrol station / AWACS station | `CAP_<CODE>_<kind>_<n>` / `AEW_<CODE>_1` | |
| Player slot group | `f16_<base>` (placed by John) | `f16_rovaniemi` |

The player's flight has no pre-named group (dynamic spawn); it's matched by the player unit plus the frag's mission number.

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
