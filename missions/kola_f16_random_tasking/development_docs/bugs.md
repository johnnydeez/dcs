# Kola F-16 Random Tasking: bugs and fixes

Bugs found in runs, with what was seen and the fix proposed, to come back to. Each entry says where the evidence is. When one is fixed, it moves to `closed.md` (under *Bugs*, with its number and the fix), and any as-built facts go in `plan.md`. Numbers aren't reused.

---

## 3. Scrambles keep firing at patrols on their race-tracks

**Status:** open, accepted for now (John, 2026-10-01, after the run with bug 2 fixed: "a little annoying, but acceptable for now"). Seen again in `event_logs\2026-10-01_141412.log`: four Blue scrambles (MSN2901, 2903, 2904, 2905) at one Su-33 patrol, MSN5016_CAP, on its race-track over Red's own airspace, all stood down; MSN2903 7 s after spawning. With bug 2 fixed each jet goes back on alert, so it's only noise.

**Seen:** same log; grep `SCRAMBLE`, `STOOD_DOWN`, `stood down on the ramp`.
- Seven scrambles were decided against patrols and then stood down: Red MSN5901 and MSN5904 (both at Blue's F-15C patrol MSN2009_CAP), and Blue MSN2902, MSN2903, MSN2904 and MSN2906 (at Red patrols and a Red scramble going home).
- **The cycle:**
  1. one race-track leg points at an own asset for two picture rounds;
  2. the scramble is decided, and the jet spawns after its reaction delay;
  3. the patrol turns at the end of its leg and reads as "heading away";
  4. the jet is stood down.
- John agreed a scramble at a patrol that looks like a raid is fine (a defender can't know intentions). But the churn is noise, and with bug 2 every Red one cost a real alert jet.
- **Seen again** (`event_logs\2026-09-30_213757.log`; grep `MSN5009_CAP`): the Red Su-30 patrol MSN5009_CAP drew **four** Blue scrambles in 26 minutes (MSN2904, MSN2906, MSN2908, MSN2909). Each one read "10 min from TGT_BANA_command_post_1" or similar, and each ended "back over its own airspace, heading away". MSN5010_CAP drew a fifth (MSN2910). Red's MSN5902 went after Blue's F-15C patrol MSN2017_CAP and was stood down the same way.

**Proposed fix, once bug 2 is fixed** (decide with John whether it's still worth it then):
- Recognise an orbit from the picture: a contact whose heading has reversed within the last few minutes while staying in about the same area.
- Or require "inbound" for more rounds when the contact is still over its own or contested airspace.

---

## 4. A DEAD flight's weapon can't outrange its target

**Status:** waiting for the standoff work (John, 2026-10-01: it goes with the *Standoff attacks* backlog item and roadmap item 6).

**Seen:** same log; grep `MSN5023_DEAD`.
- MSN5023_DEAD, 2× Su-34 from Banak on `SAM_ENON_Roland_1`, carried Kh-29T, a TV-guided missile fired from about 9 km. The Roland reaches about 8 km.
- Both fired from 9 km at ~12,800 ft, and both were shot down by the Roland (08:21–08:22).
- The Roland lost one launcher.

**Cause:** DEAD loadouts are chosen per aircraft type (`aircraft_loadout_choices.json`), and the attack altitude is realistic for the weapon. Nothing compares the weapon's release range with the target's ring.

**Proposed fix:**
- Planning: only pick a DEAD target whose ring is shorter than the flight's weapon range, with a margin; or pick the loadout by target.
- Ties in with the *Standoff attacks* item in the `plan.md` backlog: which weapons the DCS AI really releases at range.

---

## 5. Event log: no GUNS line yet

**Status:** open, waiting for a run (the other event-log fixes, (a)–(f) and (h)–(k), are done: `closed.md`, bug 5).

**Seen:** no `GUNS` line in any run so far: either no AAA or gun came into range, or DCS doesn't send `S_EVENT_SHOOTING_START` for AI ground units.

**Also (checked 2026-10-02, all 12 event logs):** no base-defense group of a sleeping kind (towed or mobile guns, infrared missile launchers, MANPADS teams) has fired once, in any run, including the two 2026-09-30 runs from before sleeping existed. So "a woken base fights" is still unproven. Two bases woke with close passes and no shot (Kuusamo, 2026-10-01; Sodankylä, 2026-10-02, the MSN2027 Hornets at 1,200–3,600 ft), but a close pass is anything within 10 km of the base, beyond MANPADS (~5 km) and gun reach (~2–3 km), so that alone doesn't show a fault. The `radar_missile_launchers` (never asleep) do fire: the Vuojärvi Tor M2 at John, 2026-10-02.

**Next:** a test mission (a Red base's defenses put to sleep and woken the way `sleep_ground_units.lua` does, plus a control set never slept, and an AI jet flown low over each), or a run where jets fly low over a defended base. Nothing to fix until then.

---

## 6. Su-24M SEAD flights spawn with no weapons

**Status:** worked around 2026-10-01 (John: remove it from the roster for now, with a comment why). The Su-24M is out of Red's `suppression_of_air_defenses` roster (`data/coalition_rosters.lua`); finding the pylon DCS rejects is still open.

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN5024`; `dcs.log`: "MSN5024_SEAD_1 carries nothing — its loadout 'SEAD' lists 4 pylons" (both jets).
- MSN5024_SEAD (2× Su-24M from Alakurtti) was PKG5023's suppression flight for the Rovaniemi SA-10. It flew 75 km into the SA-10's ring with nothing to shoot, and both jets died there (the SA-10 and the F-15C patrol MSN2002).
- The same package's Su-24M OCA flight (RBK-250) spawned armed, so it's this one loadout, not the type.
- MSN5030_SEAD (Su-24M, suppressing the Kittilä Patriot) is planned with the same loadout later in the mission.

**Cause (suspected):** the loadout is Liberation's `SEAD` (Kh-58U on pylons 2 and 7, Kh-25MPU on 1 and 8, `data/aircraft_loadouts.lua`). Every CLSID passes our check against `aircraft_pylons.lua`, but DCS drops the whole payload at spawn. Most likely a CLSID or pylon DCS no longer accepts on the Su-24M (a module update), which the pylon file from pydcs doesn't know yet.

**Proposed fix:**
- Test in DCS: spawn one Su-24M with each pylon on its own (or load the payload in the ME) to find the pylon it rejects.
- Then pick another Su-24M SEAD loadout in `aircraft_loadout_choices.json` (`--list Su-24M`), or take the Su-24M out of Red's `suppression_of_air_defenses` roster.
- Also: a flight that "carries nothing" should be removed and logged at spawn rather than sent into a SAM ring unarmed. Its package's other flights are then flying without the suppression the plan counted on; decide with John whether the package still goes.

---

## 8. Scramble intercept points sit right at the kill-zone line

**Status:** open, waiting for John's decision (detail given 2026-10-01: keep the intercept point ~10 km outside the leash's line, or leave it; the scramble flies its own intercept from takeoff anyway, so the waypoint mostly pulls it toward the edge).

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN2902`: "WAYPOINT 2 of 3: intercept point … 7 km inside SAM_SODA_SA11_1" (11:15:45), then 19 s later "LEASH going home: inside the kill zone of SAM_SODA_SA11_1". The scramble was sent home the moment it reached the point it had been sent to.

**Cause:** `interceptPoint` walks out from the base in 5 km steps and keeps the last point outside enemy kill zones (85 % of a ring). The leash sends a jet home as soon as it's inside that same line. A point just outside the line, plus the AI's own intercept geometry, puts the jet over the line almost at once.

**Proposed fix:** keep the intercept point a margin outside the leash's line (e.g. an `AIR_DEFENSE.scramble_killzone_margin_km`, ~10–15 km); if that leaves no leg of `scramble_min_leg_km`, don't scramble.

---

## 13. Su-34s blow up on the ramp seconds after spawning

**Status:** worked around 2026-10-01 (John: open parking only for now). The Su-34's profile allows only terminal 104 (open-air) spots; the DCS test of spot size is still open.

**Seen:** `event_logs\2026-10-01_112448.log`, grep `MSN5024_SEAD`, `MSN5023_STRIKE`.
- MSN5024_SEAD (08:02:00) and MSN5023_STRIKE (08:06:07), each 2× Su-34 on the ramp at Afrikanda. 12–15 s after spawning, each flight read `ABORTED` twice, then both jets were `DESTROYED`, "no killer recorded", at 499 ft (field height), pilots ejected. All of PKG5023 was gone before takeoff.
- They spawned armed (`LOADOUT` lines), on terminal-72 spots 27 / 28 and 34 / 35 (plan dump). No parked-aircraft static or ground unit was near those spots (the nearest statics were the MiG-31s at spots 9–12 and 37, the base defenses at the runway end over 1 km away).
- Afrikanda is the forested field (`data/forested_airfields.lua`).
- Probably the same as session 11's "Su-34 takeoff crash" (`plan.md`, *Still to watch*): MSN5024_2 ejected at 161 ft 32 s after spawning at Poduzhemye.
- In the same run, a Su-27 (MSN5016_CAP, spot 4, terminal 104) took off from Afrikanda normally.
- **Seen again with the workaround in place** (`event_logs\2026-10-01_203147.log`, grep `MSN5009_CAP`): MSN5009_CAP_1, a Su-27 on Afrikanda spot 37 (terminal 104, open air), spawned 04:23:54 and was `DESTROYED` at 04:24:02, no killer recorded, 500 ft (field height), pilot ejected. The nearest parked-aircraft static (`TGT_AFRI_parked_aircraft_1`, spots 9 and 10) is 180 m away. So it isn't only the Su-34 or the terminal-72 spots: something about some Afrikanda spots (the forested field; trees are invisible to the API). Spot 37 is also where session 11's notes put a MiG-31 static.

**Cause (suspected, not proven):** `reserveParking` (`stages/plan_air_tasking.lua`) gives a flight any free spot whose terminal type its profile allows (Su-34: `{ 104, 72 }`), with no check on the spot's size. The Su-34 is a large jet (14.7 m span, 23 m long); on a small or tree-lined spot it may collide as it spawns or starts to taxi.

**Proposed fix:**
- First confirm in DCS: spawn a Su-34 on Afrikanda spots 27 and 34, and on a terminal-104 spot, and watch.
- If it's the spot size: limit the Su-34 (and other large types: Su-24M, Tu-22M3, A-50, E-3A, B-1B, F-15E?) to spots that fit. Options: terminal 104 only for them, or a per-airfield list of spots too small for large jets, surveyed once like the airbase footprints. DCS's `getParking` gives no spot size, so it has to come from the type or a survey.
- Also: a flight whose jets die on the ramp within a minute of spawning could be logged as a spawn failure (`dcs.log` `WARN`), so it isn't read as combat.

---

## 16. A scramble launched from the wrong base: a tail chase from Rovaniemi while Blue's northern bases held no alert

**Status:** open (found 2026-10-01, John).

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

## 18. Patrol handover: the old patrol stays on station after its relief arrives

**Status:** open, later fix (John, 2026-10-01: once the new patrol shows up, the old one can just go home).

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN2002_CAP`, `MSN2003_CAP`.
- Both fly station CAP_KIRU_front_1 from Kiruna. MSN2003 (F/A-18C) was on station at 07:00:24, 7 min ahead of its planned 07:07, because the station is ~1.5 min from Kiruna. MSN2002 (F-16C, on station since 06:10, also 7 min early) stays until ~07:17.
- From 07:02 both flew the same race-track, 26,247 ft, 440 kt, about one minute apart, like one stacked 2-ship.

**Cause:** rotations are planned to overlap (the next patrol arrives 10 min before the last leaves, `plan.md`, *Rotations*), and the outgoing patrol keeps its planned off-station time whatever happens. A short transit stretches the overlap further.

**Proposed fix:** when the relief reaches its station (its on-station `WAYPOINT`), send the outgoing patrol on that station home (`Controller:setTask` home, as the leash does). Keep the planned overlap as the latest handover time.

---

## 19. A flight that misses its landing flies off in a straight line until its fuel runs out

**Status:** open (John, 2026-10-01: to be fixed; give it a new landing order).

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN5025_SEAD_2`.
- MSN5025_SEAD (2× Su-34 from Vuojärvi) went cold at 06:23 and flew home. `_1` landed at Vuojärvi at 06:34:12; `_2` was beside the field at 06:33.
- From 06:34 to the end of the run (07:07) `_2` held heading 317, 303 kt, 4,445 ft: ~300 km in a straight line, out of its own airspace into contested airspace, fuel 52 % → 31 %.
- **Knock-on effect:** MSN5023_OCA was `DELAYED` twice ("waiting for MSN5025_SEAD, still in the air"), so the package's mission was held up by a jet that would never land.

**Cause (suspected):** `_2` missed its landing (most likely a go-around behind its lead) and, with no waypoints left after `Land`, the DCS AI flies on along its last heading. Nothing in the script notices a flight that should have landed.

**Proposed fix:**
- Watch every AI flight after its last waypoint (or once sent home): if it is overdue to land (e.g. 10 min past its planned landing, or its time home), or getting farther from its landing base for a few minutes in a row, give it a new landing order (`Controller:setTask`, as the leash and the go-cold rule do) at its base, or the nearest held base it can reach. Log it (`LEASH`-style line, e.g. `LANDING … lost after its landing, sent to land at <base>`).
- Packages in sequence stop waiting for a flight that is overdue: a suppression flight whose jets have all fired, gone home and are overdue counts as landed for `DELAYED`.

---

## 22. The low SEAD way out climbs through short-range SAMs the routing doesn't see

**Status:** open (found 2026-10-01, 22:23 run).

**Seen:** `event_logs\2026-10-01_222355.log`, grep `MSN5024_SEAD`, `SAM_BANA_SA8_2`.
- MSN5024_SEAD (2× Su-34 from Kilpyavr) fired its 8 Kh-31P at `SAM_BANA_IRISTSLM_1` from 41 km (03:55:35), went cold, went out low, and climbed through 6,000–11,000 ft in contested airspace (03:58–04:00).
- That put it within 13 km of `SAM_BANA_SA8_2` (an SA-8, ring 10 km). The SA-8 fired three missiles; MSN5024_SEAD_1 was shot down at 6,040 ft (04:00:09), `_2` got away.
- On the way in, the flight passed the same SA-8 at 26,000 ft, above its reach.

**Cause:** short-range SAM sites (SA-8, SA-15, Roland) aren't planned threats: `lib/threat_routing.lua` routes attack flights around medium and long-range rings only (+ base-defense Pantsirs / Tors). That was safe while flights stayed at ≥ 7,500 m; item 10's low ingress, low egress and climb-out now fly inside a short-range SAM's reach. This answers item 10's open question "short-range SAMs are deadly down low".

**Proposed fix:** route the SEAD flight's low legs and its climb-out (everything below the short-range systems' ceiling, ~5,000 m) around short-range SAM sites too, with a margin (SA-8 10 km, SA-15 12, Roland 8, + ~5 km). The launch-point clearance test could count them the same way.

---

## 23. A scramble refusal names the reason of the last alert base tried, not the best one

**Status:** open (found 2026-10-01, 22:23 run). Log wording; the decision itself may be right.

**Seen:** `event_logs\2026-10-01_222355.log`, grep `no scramble: FA-18C`: `RED CONTROL MSN2025_SEAD no scramble: FA-18C_hornet: can't reach the raid before it reaches SAM_KUUS_SA8_1 (26 min, raid 5 min)` (03:43:34). The raid was next to Kuusamo, a Red alert base with jets ready; 26 min is almost certainly the time from Alakurtti or Koshka Yavr. Why Kuusamo itself was refused doesn't show.

**Cause:** `pickBase` (`consumers/control_air_flights/scramble_fighters.lua`) overwrites `why` for every alert base it tries, so the logged reason is the last base in the posture list.

**Proposed fix:** keep each base's reason and log the nearest base's (or all of them, `Kuusamo: …; Alakurtti: …`).

---

## 26. The AWACS's enemy tracks don't reach the player's HSD

**Status:** open (found 2026-10-02 in the Caucasus datalink test; bug 25, friendly contacts and threat rings, is fixed and confirmed in Kola: `closed.md`).

**Seen:** `Saved Games\DCS\Missions\datalink_hsd_test.miz`: the E-3A (EPLRS on, listed as the player's Link 16 donor) showed on the HSD as a datalink contact, but the Red MiG-29S 250 km from it never did; John saw the MiG only on his own radar.

**Suspects:**
- The E-3A has no STN of its own in the test (the editor template gave it none), so the donor link may not work.
- Since 2026, air-track identity on the F-16 depends on the DTC's ROE tab, and the test's DTC was empty: hostile tracks may be filtered or never declared.
- The E-3A may not have detected the MiG (no way to tell from the test; the Kola event log's radar picture would show it).

**Next:** in a Kola run with bug 25's fix, check whether Red aircraft that Blue's picture holds (`CONTACT` lines, seen by `awacs`) show on the HSD. If not, a second test: the E-3A with an STN, the MiG in front of the AI F-16 team (fighter-to-fighter tracks), and a DTC saved from the editor with ROE set.

---

## 27. SEAD flights shot down at the pop-up: the sites reach far more than the low-altitude model says

**Status:** tuned 2026-10-02, not flown (John: "pop up and fire earlier, and go cold as soon as they loose the salvo"). The reach model itself goes with roadmap item 12.

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN2024_SEAD`, `MSN5024_SEAD`, `MSN5025_SEAD`. Every SEAD jet that reached its target died (6 of 6; MSN5031's two died earlier, to a scramble):
- MSN2024 (2× F-16 on `SAM_ALAK_SA11_1`): the profile as planned (cruise 24,600 ft, low leg 1,400–1,600 ft, pop-up), 8 HARMs from 33–44 km at ~10,000 ft; the SA-11 fired at 39 km and both jets died ~28 km from it. The search radar died to a HARM; the launchers (each with its own radar) kept shooting. The AI kept closing during the 33 s salvo (43 → 33 km) and the go-cold came 8 s after the first hit (the 30 s picture round).
- MSN5025 (2× Su-34 on `SAM_ROVA_Patriot_1`): Vuojärvi is ~58 km from the Patriot, so it popped up 80 s after takeoff; the Patriot fired at 50 km at 8,300 ft; it dived, never fired a Kh-31P, both died.
- MSN5024 (2× Su-34 on `SAM_KITT_SA10_1`): never above ~3,400 ft (bug 28; a 52 s pop-up leg); the SA-10 fired at 46 km; one jet fired 4 Kh-31P from 36–45 km and killed the 40B6M tracking radar; the SA-10 fired 8 missiles at the Kh-31Ps.

**Cause:** `lib/sam_reach.lua` lets a site reach only its low-altitude figure (SA-11 25 km, Patriot 30, SA-10 40) up to `killzone_low_altitude_m` (3,000 m), and the pop-up goes to exactly that altitude, 40 km out. At 3,000 m the sites see and reach nearly their full envelope; the low figure only holds near the ground (radar horizon, clutter).

**Done 2026-10-02:**
- `launch_km` 40 → 55 and `popup_km` 12 → 15 (`data/air_tasking.lua`). Re-planning the 00:57 roll over six seeds: SEAD flights 3–6 → 5–8 per coalition, AI attack missions 2–8 → 4–8 (a launch point farther out is clear of more sites).
- Go cold the moment the last anti-radiation missile leaves: the `suppression` directive runs on the fast check (5 s), and the controller runs it again 0.5 s after each anti-radiation missile a watched flight fires.
- The pop-up altitude is now held through the attack (bug 28).

**Still open:** the low-altitude reach should apply only close to the ground (a few hundred metres), not up to 3,000 m; roadmap item 12's launch points and layers rest on it. Watch in the next run: `SHOT` ranges of the salvo and of the sites back, `CONTROL.*go cold` seconds after the last missile, losses.

---

## 29. The AI retry of a player's SEAD tasking against a Tor went home without firing

**Status:** open (found 2026-10-02).

**Seen:** `event_logs\2026-10-02_005718.log`; grep `MSN2026_SEAD_AGAIN`. John flew the other tasking, so the controller flew MSN2026_SEAD (his unflown SEAD on the Vuojärvi Tor M2, `DEF_VUOJ_radar_missile_launchers_1`) as 2 AI F-16s (`retry`, 04:40). They reached the launch point 40 km out at 2,600 ft (04:46), fired nothing and landed at Rovaniemi (04:50). MSN2025_OCA was still waiting on it when the run ended.

**Suspects:** a HARM shot from 40 km at 2,600 ft at a point-defense Tor (12 km reach) may be out of the AI's launch range, and the Tor's radar may not have been on at that distance. The launch distance is set for long-range sites. After the attack waypoint the next one is the landing, so the AI just went home.

**Proposed fix (decide with John):** a launch distance by target (short-range and point-defense targets much closer, e.g. ~25 km, or a DEAD instead of a SEAD for them); and a flight that reaches its launch point and fires nothing within a few minutes is logged (`CONTROL … no shot`).
