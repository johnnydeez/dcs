# Kola F-16 Random Tasking: bugs and fixes

Bugs found in runs, with what was seen and the fix proposed, to come back to. Each entry says where the evidence is. When one is fixed, it moves to `closed_issues.md` (under *Bugs*, with its number and the fix), and any as-built facts go in `plan.md`. Numbers aren't reused.

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

**Status:** open, waiting for a run (the other event-log fixes, (a)–(f) and (h)–(k), are done: `closed_issues.md`, bug 5).

**Seen:** no `GUNS` line in any run so far: either no AAA or gun came into range, or DCS doesn't send `S_EVENT_SHOOTING_START` for AI ground units.

**Next:** check in a run where jets fly low over a defended base (or a quick test mission). Nothing to fix until then.

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
- **Base pick** (`pickBase`, `consumers/run_scrambles.lua`): the nearest ready alert base whose intercept point is in reach, at least `scramble_min_leg_km` out and reached in time (bug 1's test). Nothing looks at the geometry: a base behind a raid flying away from it passes when the raid is slow enough, and the jet chases it from behind toward someone else's sector.

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

## 20. The SEAD go-cold timer counts from the planned time, so a late flight is sent home before it attacks

**Status:** open (found 2026-10-01). Late takeoffs are DCS AI taxiing and aren't a bug (John: a flight 6 min late or early is fine; the goal is that every mission gets flown and things go smoothly). This one is a bug because the lateness makes the mission fail.

**Seen:** `event_logs\2026-10-01_141412.log`, grep `MSN5026_SEAD`. Six Su-34s of three SEAD flights spawned at Vuojärvi at 06:02 with the same planned takeoff (06:12); they left between 06:06 and 06:30. MSN5026's lead took off at 06:24 and its wingman at 06:30. At 06:31:34 the go-cold rule sent it home, "still on the attack 10 min after its time at the launch point", while it was at its departure waypoint (06:30:12), nowhere near the site. It never attacked; the Kuusamo IRIS-T it was meant for stayed untouched.

**Cause:** `attack_time_s` (10 min) in the `suppression` rule is measured from the flight's *planned* time at the launch point.

**Proposed fix:** start the clock when the flight reaches its launch point (its `target` waypoint), or from the planned time shifted by how late the flight took off. Optional, with it: some limited planning for taxi time, e.g. stagger flights spawning at the same field by a few minutes per 2-ship.
