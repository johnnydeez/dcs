# DCS missions: bugs and fixes

**The one bug list for the whole repository** (John, 2026-10-07: one file, not one per mission, so nothing is tracked in two places). Every mission and the shared mission framework log their bugs here.

**Every bug says what it is for**, on a `**For:**` line right under its heading: the mission (`Kola`, `Caucasus`, …) when the fault is in that mission's own files or data, or `framework` when it is in the shared code or data (`shared_mission_framework\`), which reaches every mission on it. Add where it was found when that differs (`framework (found in Caucasus)`).

Bugs found in runs, with what was seen, the cause and the fix proposed, to come back to. Each entry says where the evidence is; an `event_logs\…` path is in the mission folder of the mission it was found in (`missions\<mission>\event_logs\`). When one is fixed, it moves to the repository's one `closed.md`, next to this file (under *Bugs*, as `### Bug n.`, keeping its number and its `**For:**` line, with when and why it was closed), and any as-built facts go in the framework's `as_built.md`. Numbers run across every mission and aren't reused.

Bugs 3–72 were found in Kola and lived in Kola's `development_docs\bugs.md` until 2026-10-07. Most of the code they name is shared now (`shared_mission_framework\mission_scripts\`, `radio_calls\`, `map_data_tools\`; `kola_data_tools\` is now `map_data_tools\`). A `plan.md` section named in them is in the root's `plan.md` (*Still to watch*, the backlog, the history), or, about how the code works (*The controller*, *Radio calls*, *Stages 5–6*, *DCS facts* …), in `shared_mission_framework\framework_design.md`, under the same name; a mission's map and scenario in its `mission_design.md`. A fix that changes behaviour means re-recording the offline harness's baselines right after it (`plan.md`, *Picking this up in a new session*).

---

## 6. Su-24M SEAD flights spawn with no weapons

**For:** Kola and Caucasus (each mission's `data\coalition_rosters.lua`, Caucasus's copied from Kola's; found in Kola).

**Status:** worked around 2026-10-01 (John: remove it from the roster for now, with a comment why). The Su-24M is out of Red's `suppression_of_air_defenses` roster (`data/coalition_rosters.lua`); finding the pylon DCS rejects is still open.

**Guard built 2026-10-02, not flown:** the ammo check 5 s after spawn (`logAmmo`) hands any jet with no weapon aboard (its gun aside), while its loadout lists weapon pylons, to the controller (`ControlAirFlights.unarmed`), which removes it on the ramp: `CONTROL … stand down: … carry no weapons (its loadout 'SEAD' lists 4 weapon pylons); removed on the ramp; the flight isn't flying` (or `the rest of the flight flies`). The `dcs.log` warning now reads `carries no weapons`. Whatever waits on a removed SEAD flight's site sees it still in the fight, so the gate flies that SEAD flight once more (`_AGAIN`, likely unarmed again) and then cancels: no flight goes without the SEAD it needs.

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

## 13. Su-34s blow up on the ramp seconds after spawning

**For:** framework (found in Kola).

**Status:** worked around 2026-10-01 (John: open parking only for now). The Su-34's profile allows only terminal 104 (open-air) spots; the DCS test of spot size is still open.

**The same spot twice** (`event_logs\2026-10-04_223922.log`, grep `RAMP_LOSS`): Su-27 scrambles MSN7917 (04:44:54) and MSN7937 (06:00:58), both at **Afrikanda spot 22**, both 13 s after spawning, no killer. Points at the spot, not the type: taking spot 22 (and 37, 2026-10-01) out of use at Afrikanda would be the cheap fix (not built; decide with John).

**Again, a second spot twice in one run** (`event_logs\2026-10-07_200750.log`, grep `RAMP_LOSS`): Su-34s of Red's SEAD rotation on the Kallax Patriot, both at **Rovaniemi spot 2**, both destroyed 19 s after spawning, no killer, 622 ft (field height), pilot ejected: MSN7023_SEAD_1 (spawned 04:02:00) and MSN7023_SEAD_AGAIN_1 (04:24:59; the retry was given the same spot). Each flight went on as a single ship (both lost later, to an F-15C and an F-16 SEAD flight's AIM-120s). Rovaniemi isn't a forested field. The mission-end summary counts both as "no killer recorded". With Afrikanda 22, two spots now fail twice; a list of spots not to use (Afrikanda 22 and 37, Rovaniemi 2; and Afrikanda 31, a Su-27 8 s after spawning in the 2026-10-08 20:10 run, once so far) is the cheap fix (not built; John, 2026-10-07: log only for now).

**Logging built 2026-10-02, not flown:** a jet destroyed before it ever took off, within 2 min of spawning, is a `RAMP_LOSS` line in the event log (and a `dcs.log` warning) with its base and spot: "Su-27 destroyed on the ramp 8 s after spawning, before taking off, at Afrikanda spot 37: a spawn failure, not combat". Grep `RAMP_LOSS` after each run to collect the spots for the spot-size test.

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

## 32. The leash read a Red fighter flying straight at Blue as "heading away"

**For:** framework (found in Kola).

**Status:** open (found by John 2026-10-02, during the 14:55 run). **The decision was right, the reading was wrong** (John: CAP was covering that area, so standing the scramble down was fine; reading the Red fighter as going home was not). The right reason would have been "covered by patrol", and the leash doesn't look at patrol cover at all.

**Seen:** `event_logs\2026-10-02_145532.log`; grep `MSN7903_SCRAM`, `MSN2905_SCRAM`.
- 04:35 Red scrambled MSN7903 (Su-27, Ivalo) at the Blue F-16 patrol MSN2009_CAP. It took off at 04:41:37 and flew SW (heading 223–230) toward Kittilä.
- 04:42:04 Blue's picture: new contact (seen by the patrol MSN2002_CAP), enemy airspace, `inbound SAM_KITT_IRISTSLM_1 in 9 min`. 04:42:34 Blue scrambled MSN2905 (F-16, Hosio); it spawned on the ramp at 04:43:46. The contact was still over Red's airspace, outside every commit circle (they hold no enemy airspace), so "covered by patrol" didn't apply when the scramble was decided.
- **04:44:04** `leash stand down: MSN7903_SCRAM back over its own airspace, heading away`, 18 s after spawning. The Su-27's `POSITION` in that same second: 532 kt, heading 230, climbing through 19,900 ft, 42 km outside the Kittilä IRIS-T ring, still closing.
- 04:44:49 the Hornets of MSN2026_SEAD called `defend` on it: 98 km, hot, closing 437 kt. 04:45:34 the picture had it inbound again (`entered contested airspace … inbound SAM_KITT_IRISTSLM_1 in 3 min`); by 04:46 it was at 692 kt, 4 km outside the IRIS-T ring. The IRIS-T fired at it at 04:46:44, after Red's own leash had sent it home (`inside the kill zone of SAM_KITT_IRISTSLM_1`).
- 04:45:04 `no scramble: … under enemy SAM cover (the kill zone of SAM_IVAL_SA11_2)`.

**Cause (from the code, not proven for this round):** the leash (`directives_per_flight.lua`, `leash`) lets go once the raid is over its own airspace and **not `inbound`** at one radar-picture round. In `track_radar_picture.lua`, `inbound` means the contact's current heading line passes within `threat_pass_km` (30 km) of a specific own asset (a held base or a catalog target) ahead of it. So:
- **One round is enough to let go.** The scramble needs `scramble_inbound_rounds` (2) inbound rounds to launch, but the leash drops it on a single round that isn't inbound. The Su-27 was inbound at 04:42:04 and 04:45:34, so the 04:44:04 round most likely caught a heading a few degrees off (climbing and accelerating, heading 223 → 230). At ~80 km from the IRIS-T, 7° moves the heading line ~10 km, enough to cross the 30 km band.
- **"Not inbound on an asset" isn't "heading away".** A fighter coming hot toward Blue whose line misses every asset by more than 30 km reads the same as one going home. Nothing looks at whether the range to Blue is closing.
- **No patrol check in the leash.** The scramble trigger refuses a raid an airborne patrol's defended zone or commit circle covers, but once a scramble is launched the leash never asks again, so a raid flying into a patrol's area keeps its scramble (or loses it for an unrelated reason, as here).

**Proposed fix (decide with John):**
- "Heading away" = the raid is opening from Blue: its heading more than ~90° off the line to the nearest own asset, or the scramble, or the range to it growing. Not just "its line misses every asset".
- Let go only after 2 rounds in a row (as many as the trigger needs), or after a set time over its own airspace not closing.
- A new leash reason: stand down (on the ramp) or home (airborne) when the raid has come under an airborne patrol's defended zone or commit circle, "covered by patrol", the same test the trigger uses.
- Related: bug 3 (scrambles at race-tracking patrols); a looser "heading away" would add to that churn, so tune the two together.

---

## 35. A SEAD retry flies straight back into the site that just shot the first flight down

**For:** framework (found in Kola).

**Status:** open (found 2026-10-02, review of the 14:55 run).

**Seen:** `event_logs\2026-10-02_145532.log`; grep `retry`. Both rotations retried at once, as the rotation's next flight, with the same base, route and profile: MSN7023_SEAD_AGAIN spawned at 04:11:59, 1 s after MSN7023's last jet died, and MSN2025_SEAD_AGAIN at 04:13:09, 1 s after MSN2025's. Both retries were lost like the first (bug 33). 4 jets per side against one site in ~15 min. John, after the 00:57 run: losing some SEAD is fine, losing most isn't.

**Seen again** in the 16:50 run (`event_logs\2026-10-02_165055.log`): MSN2025_SEAD_AGAIN spawned at 04:15:56, 1 s after the SA-10 killed both F-16s of MSN2025 (bug 40), same base and route.

**Seen again, 2026-10-07 20:07 run** (`event_logs\2026-10-07_200750.log`, grep `MSN2028_SEAD`, `SAM_ROVA_SA10_1`): the Rovaniemi SA-10 cost Blue 4 F-16s and was never shot at. MSN2028_SEAD (Weasel 4, from Kallax) fought two bandits on its low run-in and went home without a shot (bug 77), losing its wingman to the SA-10 on the way out (04:51:11, 1,073 ft, 81 km inside the ring). Its retry MSN2028_SEAD_AGAIN (Wild 4) spawned at 05:16:28 with the same base, route and profile; a Su-33 (MSN7003_CAP) fired at it at its pop-up (05:33:08), the fight was broken off after 30 s for the SA-10's kill zone, it reached the top of the pop-up at 3,355 ft (05:34:21), and the SA-10 fired at it from 47–52 km and killed both jets (05:35:02, 05:35:21) before any HARM left. The retry came 26 min after the first try's go cold, not at once (bug 78), but from the same place into the same site.

**Cause:** the rule (roadmap item 12, point 8): a site still in the fight after its SEAD flight gets one more try, and the rotation flies it next. It doesn't ask whether the first flight fired its salvo and came back, or was shot down. A flight shot down before or at its salvo is exactly the case where a second identical try is most likely to die too.

**Proposed (decide with John):**
- A flight **lost** at its target: no immediate retry. Move on down the queue and come back to the site later (or never: mark it "too hot" for this roll, log why), "no second wave into what killed the first" (doctrine idea in `plan.md`).
- A flight that **fired and came home** but the site survived: retry as now.
- Or space the retry (e.g. ≥ 30 min) and send it from another base / bearing.

---

## 36. A low SEAD flight reached its launch point, fired nothing and flew home

**For:** framework (found in Kola).

**Status:** fix built 2026-10-02, not flown (copied to DCS). Found by John 2026-10-02 in the 16:03 run, the first with bug 33's profile: low from takeoff or low before the rings, pop-up to 1,800 m on afterburner 8 km before a launch point 45 km out. **No SEAD flight fired a missile all run:** MSN2025 (F-16s, Monchegorsk SA-10) was at its launch point at 4,941 ft for 40 s with no HARM before fighters jumped it. MSN2025_SEAD_AGAIN fought at its pop-up (bug 39).

**Fix (John, 2026-10-02: "increase the pop up altitude a bit and then send the jets forward on that same track until they get a radar ping and can launch, then turn around and go home as planned"):**
- Pop-up altitude 2,400 m (~8,000 ft; was 1,800).
- An `EngageGroup` on the site from the pop-up waypoint: it fires the moment the site's radar is seen (the `AttackGroup` at the launch point stays).
- A new `press_on` waypoint past the launch point, on the same track toward the site, at the pop-up altitude: up to `press_on_km` (20) closer. For a short-reaching site whose launch point is outside its ring, it stops at the site's reach + 5 km. It is pulled back 1 km at a time while it lies inside another site's low reach or short-range ring.
- Go cold: at the press-on point with nothing fired → home as planned (`CONTROL … go cold: no shot: pressed on to <n> km …`). Pressing more than `press_km` (now 5) past the press-on point → home. The other sites' rings are accepted exposure from the pop-up through the press-on leg. Going home after a salvo on the press-on leg starts after the press-on point, never on toward the site.
- New event word `RADAR_WARNING` at the launch and press-on points: whether the site's radar is on the flight's warning receivers, every radar that is, and the lead's height above the ground. The next run shows whether the cause below was it.
- The frag of a player's SEAD says how far to press on.

**Check in the next run:** `RADAR_WARNING`; `SHOT` ranges and altitudes of the salvoes (now anywhere from ~45 km in to the press-on point); `CONTROL.*no shot`; losses on the press-on leg.

**Seen:** `event_logs\2026-10-02_160358.log`; grep `MSN7023_SEAD`. 2× Su-34 (4 Kh-31P each) from Banak on `SAM_ENON_SA11_1` (SA-11, ring 50 km), step 1 of Red's rotation.
- The way in flew as planned: cruise up to 26,200 ft, descent at 04:13, low from 04:16 (2,700–3,600 ft above sea level), pop-up at 04:17:21, launch point at 04:17:43 at 5,870 ft (6 min ahead of its planned time).
- **No shot.** 46 s after the launch point it was at its egress waypoint (04:18:29) and flew the route home low. No `SHOT` from either jet. `CONTROL … no shot` came at 04:19:24, already 61 km from the site on the way out.
- **The SA-11 never fired at it and never tracked it:** no `SHOT` or `TRACKING` line from `SAM_ENON_SA11_1` all run. Blue's picture saw the flight only from the Ivalo IRIS-T. So the pop-up exposure was fine this time; the target may never have been painting them.

**Suspects (not proven):**
- **No emitter for the Kh-31P to home on:** the AI fires an anti-radiation missile only at a radar its aircraft detects. If the SA-11's search radar wasn't seeing them (terrain masking at 5,900 ft over the fells, or the radar not emitting), there was nothing to shoot at. Both earlier salvos that did fire were at sites already tracking or firing at the flight (14:55 run: the Patriot at MSN7023; the Hornets at the Ivalo SA-11, whose neighbour fired at them).
- **Too little time at the launch point:** with the `AttackGroup` on the launch-point waypoint and the egress 8 km beyond, the AI finished (or dropped) the attack and moved on within 46 s. With the old 3,000 m / 15 km pop-up, flights stayed and manoeuvred until they could fire (and sometimes died doing it).
- **The shot itself:** 45 km at ~1,800 m may be outside the AI's Kh-31P launch envelope at that height even with an emitter (earlier Su-34 shots: 45–61 km from ~10,000 ft).

**Proposed fix (decide with John):**
- Check in DCS whether the SA-11's search radar was on and could see the launch point (the radar horizon over the fells at 1,800 m), and whether an AI Su-34 fires a Kh-31P from 45 km at 6,000 ft at an emitting SA-11 (a test mission).
- Hold the flight at its launch point (an orbit at pop-up height) until it fires or a short time is up, instead of letting the route take it home within a minute.
- Or fire on the emitter as soon as it is seen: `EngageGroup` (waits for the radar to emit) active from the pop-up, with expend All, instead of an `AttackGroup` on the launch-point waypoint.
- `no shot` reads oddly 2 min after the pop-up when the flight is already heading home; say instead "flew on from its launch point with every missile aboard" at the egress waypoint.

---

## 39. A SEAD flight that fights at its pop-up passes its launch point during the fight and goes home with every missile

**For:** framework (found in Kola).

**Status:** open (found by John 2026-10-02, 16:03 run). No fix yet (log only). Different from bug 36: there the flight reached its launch point unbothered and flew on without a shot; here a fight at the pop-up made it miss the launch point altogether.

**Seen:** `event_logs\2026-10-02_160358.log`; grep `MSN2025_SEAD_AGAIN`, `MSN7902_SCRAM`. 2× F-16 (4 HARMs + 2 AIM-120C each) on the Monchegorsk SA-10, the retry of MSN2025.
- Low run-in as planned; a Red MiG-31 scramble (MSN7902) came after it. Blue's picture held the MiG-31 (through the patrol MSN2002_CAP) from 04:27:34.
- **04:27:39** pop-up waypoint, and in the same second `defend: engaging MSN7902_SCRAM (MiG-31), 33 km, hot, closing 1,189 kt`: the bandit call worked. Both F-16s fired an AIM-120C at 26–27 km; both hit, and the MiG-31 died at 04:28:26. Its R-33 hit MSN2025_SEAD_AGAIN_1, which survived.
- **04:27:54** (15 s in) `back on mission: breaking off: inside the kill zone of SAM_OLEN_SA10_1`: the fight's break-off counted the Olenya SA-10's ring, which the flight was in on purpose at its pop-up (go cold ignores other sites there; the fight's break-off doesn't).
- **04:28:23** launch point waypoint reached at **2,780 ft**: the jets had been manoeuvring (8,000–10,000 ft at 04:28, then down to ~2,400 ft), not climbing to the shot. No HARM.
- **04:29:25** egress waypoint; flown home low with all 8 HARMs (`no shot` at 04:29:39). Both jets alive at 04:31, heading home.

**Cause (suspected):** the pop-up and the launch point are 8 km apart (~25 s). A fight there takes the flight past the launch point before it can climb and shoot: the route moves on to the egress, and the launch point's `AttackGroup` either never ran (the pushed fight task was on top when the waypoint came) or ran from low and was dropped. "Back on mission" resumes the route, which by then points home. Two parts:
1. Nothing brings the flight back to its shot after a fight near its launch point: the controller's `resume` only ends the fight; it doesn't check whether the attack waypoint was passed.
2. The fight was broken off after 15 s for another site's ring the flight was in by plan (the same break-off as in the 2 s case earlier this run, MSN2025_SEAD at 04:15:44).

**Proposed fix (decide with John):**
- After a fight, a SEAD flight that still has every anti-radiation missile and has passed its launch point gets a new order from the controller: back to its launch point (or straight to an attack on the site from where it is, if in range) with the salvo, before going home.
- Give SEAD flights the go-cold exposure rule in the fight's break-off too: no break-off for other sites' rings from the pop-up until the salvo is away.
- Goes with bug 36's fix (hold at the launch point until the salvo is away, or fire on the emitter as soon as it's seen).

**Part fixed 2026-10-02, not flown (copied to DCS):** a SEAD flight's fight is broken off for a kill zone by height, with no ring accepted (its own target's neither) outside its shot area (the pop-up through the press-on leg), and for no ring inside it, as for the go cold. The second part of the fix (back to the shot after a fight past the launch point) isn't built. Watch for a defend / break-off / defend cycle every 30 s (`reengage_after_s`) on a low run-in with a fighter hot on it.

**A fight called in the middle of a salvo** (17:15 run, grep `MSN7023_SEAD`): 2× Su-34 from Vuojarvi on the Rovaniemi SA-11. MSN7023_SEAD_2 fired 3 Kh-31P at 52 km from 1,470 ft 15 s into its pop-up (04:08:46, the `EngageGroup` from the pop-up worked). 8 s later (04:08:54) `defend` on Blue's SEAD Hornets MSN2025, 42 km, hot. The lead never fired; the wingman never fired its 4th. The SA-11 shot the 3 Kh-31Ps down. All four jets (both Su-34s, both Hornets) died within 8 s of each other at 04:10. A real pilot with a bandit at 42 km would let the rest of the salvo go first (seconds) and then turn to the fight. Proposed: inside its shot area with missiles aboard, a SEAD flight commits to a bandit only inside a closer range (e.g. 25 km) or when fired upon.

**The fight ends the SEAD mission, and the defend / break-off cycle is real** (17:15 run, grep `MSN2025_SEAD_AGAIN`, `MSN2024_SEAD`): Blue's SEAD Hornets out of Rovaniemi, which sits inside the Sodankyla SA-10's full ring (its run-in stays under the SA-10's low reach on purpose).
- MSN2025_SEAD_AGAIN (on the Vuojarvi SA-11) took off 04:17:17 and called `defend` at 04:18:04 on Red's SEAD Su-34s (MSN7023_SEAD_AGAIN, 62 km, hot), who called `defend` on it 5 s later. The fight climbed the Hornets to 9,131 ft, and at **04:18:39 the go cold sent the flight home: "inside the kill zone of SAM_SODA_SA10_1"**, 82 s after takeoff, every HARM aboard. The SEAD mission was over before it began.
- Then the cycle: `defend` 04:18:49 (49 km) → `back on way home: breaking off: inside the kill zone of SAM_SODA_SA10_1 (5 s)` 04:18:54 → `defend` again 04:19:24 (41 km) → missiles exchanged at 18 km at 04:20:06.
- MSN2024_SEAD after its salvo: `defend` on a Su-30 at 98 km (04:15:24), again at 04:15:39, `back on way home` after 2 min 19 s for the SA-10's kill zone, `defend` again 04:18:29 at 14,923 ft (38 km), killed the Su-30 with an AIM-120C, `back on way home` 04:19:19 for the SA-10 again.
- Both sides' SEAD flights keep meeting: on this roll Red's flies from Vuojarvi to the Rovaniemi SA-11 and Blue's from Rovaniemi to the Vuojarvi SA-11, the same corridor in opposite directions, and each picture calls the other a bandit at ~60 km.

**Built 2026-10-02, not flown (John: "that sounds fine"):** a SEAD flight with anti-radiation missiles aboard commits only when fired upon, or outside its shot area when the bandit is hot inside `sead_commit_km` (25); otherwise `CONTROL … press on: bandit …; staying low on its route` (or `finishing its salvo first`), once per bandit. A bandit a fight was broken off from for a kill zone isn't engaged again while the flight is still inside a kill zone. Checked in a luae harness with stubbed DCS. The proposal as it was:

**Proposed (decide with John):** a SEAD flight with its anti-radiation missiles still aboard doesn't commit to a bandit at long range: only when fired upon, or inside a short range (e.g. 25 km, inside which it can't outrun the fight anyway); otherwise it stays low on its route (the DCS AI still evades missiles by itself). After its salvo it is an ordinary flight going home. And a fight's break-off for a kill zone could hold off re-engaging that bandit while the flight is still inside that ring, instead of 30 s (`reengage_after_s`).

**Seen again, Red, on the low run-in** (`event_logs\2026-10-02_165055.log`, grep `MSN7023_SEAD`): 2× Su-34 from Vuojarvi on the Kittila Patriot, low from takeoff (Vuojarvi sits on the edge of the Patriot's ring). At 04:12:54, 2 min after takeoff and still low (1,579 ft), `defend` on the Blue Hornet patrol MSN2009_CAP at 82 km. The fight climbed both Su-34s to 11,000–14,600 ft **inside the Patriot's ring (13–43 km inside)**. The Patriot fired 6 MIM-104 at them from 59–80 km. The Hornet's AIM-120C killed MSN7023_SEAD_1 at 04:15:54. The fight was never broken off for the Patriot's ring: the break-off skips the rings the route passes through on purpose, and the flight's own target is one of them. So a SEAD flight's self-defence pulls it up out of its low run-in into its target's full envelope, and nothing stops it.
**Seen again 2026-10-07 (20:07 run):** both Rovaniemi SA-10 tries fought at or near their pop-up; the first went home with all 8 HARMs because its shot waypoints were all counted as reached the moment the fight ended (bug 77, its own entry), the second was killed by the SA-10 after the fight's break-off (bug 35's note). The second part of this bug (back to the shot after a fight) is what both needed.

- Proposed with the rest of bug 39: while a SEAD flight is on its low run-in, a bandit call either keeps the fight low (no way to tell DCS that, as far as known) or breaks off as soon as the flight climbs above the low altitude inside any ring, its own target's included.

---

## 41. The controller's kill zones don't know the base-defense Tors and Pantsirs

**For:** framework (found in Kola).

**Status:** fix built 2026-10-02, not flown (John agreed after the behaviour was laid out; copied to DCS). `SamReach.baseDefenses` lists the enemy base-defense radar SAMs (`AIR_ROUTING.base_defense_roles`) with their longest unit's reach, as the planner sizes them; `AssessFlightSituations.enemyKillZone` and the scrambles' `enemyKillZone` check them after the SAM sites, at 85 % of that reach at any height, live groups only, and the `except` sets (route threats, a SEAD flight's own target) apply. So the fight's break-off, the go cold, the leash, the scrambles' "under enemy SAM cover" and the intercept point's 10 km margin all see them. Expected: fewer jets lost chasing or fighting into an airfield's Tor or Pantsir; a few bandits and raids escape there; slightly fewer scrambles. Checked in a luae harness. Found 2026-10-02, 17:48 run, watched by Claude.

**Seen:** `event_logs\2026-10-02_174852.log`; grep `MSN2024_SEAD_1`, `DEF_VUOJ_radar_missile_launchers_1`. After its salvo (which killed the Sodankyla SA-10's search and tracking radars, bug 40), MSN2024_SEAD_1 (F-16C) took the Red SEAD Su-34s that came hot at it (`defend` 04:12:54, 31 km, allowed: its HARMs were gone). The fight took it to 8,800–12,700 ft and east toward Vuojarvi. 04:13:56 the Vuojarvi base Tor M2 (`DEF_VUOJ_radar_missile_launchers_1_1`) fired at it from 13 km; 04:13:59 `back on way home: breaking off: inside the kill zone of SAM_SODA_SA10_1`; 04:14:14 destroyed by the Tor.

**Cause:** `AssessFlightSituations.enemyKillZone` walks only `plan.sam_sites`. The base-defense `radar_missile_launchers` groups (Tor M2, Pantsir; Blue's Roland / Tor) aren't in it, though the planner's routing keeps clear of them (`lib/threat_routing.lua`: + 5 km) and the radar picture counts them as sensors. So no controller rule sees them: the fight's break-off, the go cold's "inside another site's kill zone", the leash and the scrambles' "under enemy SAM cover". A fight or a chase can run straight into a defended base's Tor.

**Proposed fix (decide with John):** `enemyKillZone` also walks the live base-defense `radar_missile_launchers` groups of the other coalition, with their reach from `lib/sam_reach.lua` (the planner already has them: full reach, no low figure; ~12–20 km), so every rule above sees them. Log names them by group (`DEF_VUOJ_radar_missile_launchers_1`).

---

## 43. Kill zones still counted a SAM site whose radars were dead

**For:** framework (found in Kola).

**Status:** fix built 2026-10-04, not flown (John agreed; copied to DCS; checked in a luae harness). Found in the AI-only run `event_logs\2026-10-03_141509.log` (69 min).

**Seen:** both Kittila Patriot tracking radars were destroyed at 04:31:50 (MSN7023_SEAD_AGAIN). After that, MSN7035_DEAD broke off 4 fights in 5 s each "inside the kill zone of SAM_KITT_Patriot_1" (04:49-04:56), and Red refused scrambles at 05:04 and 05:06 "under enemy SAM cover" of the same Patriot. The launch gate had already launched MSN7035 *because* the Patriot was out of the fight.

**Fix:** the controller's and the scrambles' kill zones skip a site out of the fight, by the gate's own test (`DecideLaunches.outOfTheFight`: its radars destroyed to its success fraction). That covers the fight's break-off, the leash, the scrambles' "under enemy SAM cover" and the intercept point. **SEAD flights keep counting every live site** (John: don't change SEAD attack behavior): their go cold and their fight's break-off pass `countSilenced`.

---

## 44. A fight was timed out in the middle of the missile exchange

**For:** framework (found in Kola).

**Status:** fix built 2026-10-04, not flown (copied to DCS; harness-checked).

**Seen:** same run; both SEAD duels ended `back on way home: 3 min on …, time is up` the moment the missiles were in the air (04:20:56, 04:36:54), and the jets were hit 1-33 s later. A defend called at 80-95 km and closing takes about `max_engage_s` (3 min) to reach shot range.

**Fix:** time is up only when no air-to-air missile of the flight is still flying (the controller keeps each one the flight fires, from `S_EVENT_SHOT`) and it hasn't been fired upon in the last `shot_memory_s` (30 s).

---

## 45. SEAD flights fought each other after their salvoes

**For:** framework (found in Kola).

**Status:** fix built 2026-10-04, not flown (John: option (a); copied to DCS; harness-checked). The SEAD attack itself is unchanged.

**Seen:** same run. 12 of the 15 losses were air-to-air, 10 of them SEAD jets fighting after their salvoes. Blue's rotation (Rovaniemi → the Vuojarvi SA-10) and Red's (Vuojarvi → the Kittila Patriot) fly the same corridor head-on, on the same clock (both spawn at 04:02, the retries around 04:30); after the salvo each committed at 72-99 km, then defend / break off / defend. MSN2026 ↔ MSN7023: all 4 jets lost; MSN2026_AGAIN ↔ MSN7023_AGAIN: 3; MSN2028_AGAIN ↔ MSN7034_AGAIN: 3. MSN2028_AGAIN_2 committed on a MiG-31 with 1 radar missile aboard; the fight climbed it into the Koshka Yavr SA-11.

**Fix:** a SEAD flight whose salvo is away commits only when fired upon, or to a bandit hot inside `sead_commit_km` (25); otherwise `CONTROL … press on: bandit …; salvo away, staying on its way home`, once per bandit. Before the salvo nothing changed.

**Not done (option (b)):** offsetting the two rotations' start times.

---

## 46. A SEAD site that survived both tries blocked a coalition's attacks for the rest of the run

**For:** framework (found in Kola).

**Status:** fix built 2026-10-04, not flown (copied to DCS; harness-checked). Also the "come back later" half of bug 35.

**Seen:** same run. Every Blue attack mission (MSN2037, 2038, 2039, 2040, 2042) waited on `SAM_VUOJ_SA10_1`. After MSN2026 and MSN2026_SEAD_AGAIN left 1 of its 3 radars dead (it needs 2), MSN2037 was cancelled at 04:44:59 and the rest would follow; the rotation never came back to it. The Koshka Yavr SA-10 did the same to MSN2029 and MSN2030 (cancelled 04:49:56).

**Fix:** a rotation site still in the fight once its SEAD flight's second try is down comes back into the rotation once more, `AIR_PACKAGE.come_back_after_s` (60 min) later, as `<id>_LATER` (the same plan flown again: the plan is fixed, so same base and route), ahead of the rotation's next flight, and only if it would be back before the window ends. Flights waiting on the site wait for it instead of being cancelled; the rotation goes on past a rotation flight that waits for it. After a third failed try they're cancelled ("after three SEAD flights"). Lines: `CONTROL … come back: … it comes back into the rotation at 05:51`, `retry: … comes back as …_LATER, the rotation's next flight`, `wait: waiting for <site>'s SEAD flight to come back (…_LATER, at 05:51)`.

**To check in the next run:** grep `come back`, `_LATER`. Note the SA-10's own reload (plan.md, *DCS facts*): 2 h, so after 60 min a site may be partly rearmed.

---

## 50. The radar picture's first-detection ranges are far beyond the 250 km the coverage call assumes

**For:** framework (found in Kola).

**Status:** open (found 2026-10-04, same log). Log only, no fix yet. Goes with the "AWACS and low flyers" item in `plan.md` (*Still to watch*) and Darkstar's coverage call (bug 42).

**Seen:** `CONTACT … seen by … km away` lines:
- Blue's E-3A `MSN2001_AEW`: 374, 391, 396, 399 km, on its way out (bug 38's fix); one of them a Su-34 at **853 ft** at 374 km (`MSN7023_SEAD_AGAIN`, 04:24:04).
- Red's A-50 `MSN7001_AEW`: Blue's E-3A at **633 km** (04:07:34), Blue's patrol MSN2002_CAP at 703 ft at 384 km.
- The MiG-31 scramble `MSN7901_SCRAM`: John's F-16 at 3,315 ft at **387 km** (04:16:04).
- Meanwhile at 04:38:04 John's picture call read `no radar coverage` (he was at ~1,200 ft near Kuusamo, more than 250 km from the E-3A).

**Cause (unknown, two possibilities):**
1. DCS's AI radars really detect that far (a MiG-31 at 387 km and an A-50 at 633 km are well beyond the real systems), so `AIR_PICTURE_CALLS.coverage.awacs_km` (250) is far too short for what the picture actually holds.
2. `Controller:getDetectedTargets(RADAR)` also returns contacts shared over datalink with the coalition, so the "first sensor" and its distance aren't really who saw it. Then the picture is less "what our radars see" than intended, and the `km away` figures can't be used to tune coverage.

**Seen again, farther** (`event_logs\2026-10-04_223922.log`): an F/A-18C scramble (MSN2910) "saw" a contact at 536 km and a low one (2,327 ft) at 486 km; the Su-30 patrol MSN7004 at 433 km; the Su-30 patrol MSN7003 John's F-16 at 516 km, and Red scrambled MSN7927 on it. No fighter radar reaches that far, so cause 2 (contacts shared across the coalition) is now the likely one; it would also feed bug 3's churn (a near all-seeing picture).

**Proposed (decide with John):** a test mission: an AI E-3A / A-50 and a MiG-31 alone on the map (no other friendly sensors), a target flown out at several heights and ranges, logging `getDetectedTargets(RADAR)` with each entry's `distance` / `visible` / `type` flags every 10 s; then a second run with other friendly aircraft up, to see whether their contacts appear in the lone sensor's list. Then set the coverage figures (and, if 2 is true, filter shared contacts out of the picture).

---

## 57. A SEAD retry spawned 1 s after the first flight was down, with its HARMs still in the air

**For:** framework (found in Kola).

**Status:** fix built 2026-10-05, not flown (John: "a dumb retry after 5 minutes and look at the target state again"; copied to DCS).

**Seen:** `event_logs\2026-10-05_103126.log`, grep `MSN2029_SEAD`. MSN2029's last jet died at 04:45:25; `MSN2029_SEAD_AGAIN` spawned at 04:45:26. MSN2029's HARMs destroyed the SA-11's search radar (its only critical radar) at 04:46:17, so the site was out of the fight 51 s later, but the copy flew the whole sortie and went home `no shot`. Every retry this run came 1 s after the flight before it was down (MSN2026, MSN7023).

**Fix:** a SEAD flight done (sent home, landed or lost) with its site still in the fight is flown again no sooner than `AIR_PACKAGE.retry_after_s` (300) after it came off its task, and the site is looked at again first (`ControlAirFlights.offTaskSince`; `decide_launches.lua`: the rotation's owed retry and the gate's retry). The come-back decision after a second try waits the same 5 min. New line: `CONTROL … wait: SAM_KOSH_SA11_2 still in the fight after MSN2029_SEAD; looking at it again at 04:50 before a second try`. Check: that line, then either a `retry` or the rotation's next flight launching because the site is out.

---

## 58. Red SEAD flights went cold 10 s into their salvo, the lead with all 4 aboard

**For:** framework (found in Kola).

**Status:** fix built 2026-10-05, not flown (copied to DCS; checked with stubbed situations).

**Seen:** same log, grep `MSN7024_SEAD`. Both tries on the Kirkenes IRIS-T: the wingman fired 1 Kh-31P at 49 km, then 3 at 43 km; 10 s later `go cold: 5 km past its launch point toward SAM_KIRK_IRISTSLM_1` (and `6 km past` on the retry). The lead never fired either time.

**Cause:** that site's flights have no press-on point (no point on the track clear of the other sites), so the "pressed too far" limit is the launch point + `press_km` (5). After the pop-up the `EngageGroup` flies the Su-34s on toward the site, past that limit in about 20 s.

**Fix:** pressing past the limit doesn't send the flight home within `AIR_CONTROL.suppression.press_after_shot_s` (30) of any anti-radiation missile it fires; `salvo over` (20 s after one jet is empty) still ends it. Whether the lead then fires is up to the DCS AI (only one jet fired in several salvoes on both sides: the optional Wild Weasel item).

---

## 59. Kuusamo scrambled six times at Blue's E-3A

**For:** framework (found in Kola).

**Status:** fix built 2026-10-05, not flown (John: "an AWAC that vulnerable would be scrambled and shot down, it's probably too close to the front. fix it."; copied to DCS).

**Seen:** same log, grep `MSN2001_AEW`. MSN7901, 7903, 7905, 7906, 7907, 7908, every ~17 min: "scramble: … after MSN2001_AEW (E-3A), enemy airspace, 14 min from SAM_ALAK_SA6_1; intercept 60 km out", each stood down on the ramp 3 min later, "back over its own airspace, heading away". The E-3A's race-track (centre 191 km from Alakurtti, 210 km from Koshka Yavr and Luostari, 254 km from Kuusamo) had a leg pointing at Alakurtti.

**Cause:** the orbit is chosen as far forward as the standoffs allow (`early_warning_near_best`), and the standoffs (150 km from every enemy fighter base, 80 km from the contested airspace) were checked at the race-track's centre only.

**Fix:** `early_warning_fighter_base_km` 250, `early_warning_front_km` 120, held for the centre and both ends (`orbitCandidates`). On this roll's airspace (a rough check, not the planner): Blue still has ~1,190 orbit cells, the best seeing ~35 % of the contested airspace within the 250 km planning reach (was ~46 %), so Blue's second E-3A (`early_warning_max` 2) is now more likely to be planned; Red's A-50 ~32 % (was ~58 %). Not checked: whether Red still scrambles at it (its trigger is "inbound on an asset within 15 min"). Check `dcs.log` "sees n % of the fight" and grep `after MSN2001_AEW` in the next run.

---

## 60. A MiG-31 patrol fought on low on fuel and went down with empty tanks

**For:** framework (found in Kola).

**Status:** fix built 2026-10-05, not flown (John: "add a fuel watch to the controller"; copied to DCS; checked with stubbed situations).

**Seen:** same log, grep `MSN7016_CAP`. About 1 % a minute on station; 19 % at 04:43, when it took on MSN2029_SEAD (killed both Hornets, R-33 and R-40R down to 1,850 ft); 9 % at 04:45, 1 % from 04:50, `DESTROYED … no killer recorded, 1,847 ft` at 04:54. DCS's own return at bingo didn't bring it home.

**Fix:** a new directive `fuel` for patrols, scrambles and the AWACS (`AIR_CONTROL.fuel`): home (`CONTROL … bingo: bingo fuel: MSN7016_CAP at 16 %, 100 km from Koshka Yavr (needs 17 %)`) when a jet's fuel is down to `reserve_fraction` (0.10) + km straight home / its combat radius × `home_fraction_per_radius` (0.5); the jet with the least to spare decides for the flight. A flight already going home that is fighting breaks the fight off (`back on way home: bingo fuel …`). Not attack flights for now: they are planned out to their combat radius, so the same rule could turn a strike back short of its target.

---

## 56. SA-10 rings missing from the F-16's HSD, inconsistently

**For:** framework (found in Kola).

**Status:** open, parked (John, 2026-10-05: "a problem for another day"). Log only.

**Seen:** the 2026-10-04 22:39 run (`event_logs\2026-10-04_223922.log`): no SA-10 ring on John's HSD, though smaller rings (presumably SA-11 / SA-6) showed. John has seen SA-10 rings in earlier runs, "but not all of them. It seems very inconsistent."

**What the roll had:** 25 Red sites spawned with `hiddenOnMFD = false` (4 SA-10, 21 SA-11 / SA-6; `init.lua` → `SpawnGroundGroups.run`, `show_on_mfd`), against ~11 on the 2026-10-02 roll where rings first worked. Spawn order of the ring sites: Monchegorsk, Kilpyavr and Murmansk SA-10s 1st–3rd, Rovaniemi SA-10 11th of 25.

**Suspects (not proven):**
1. **The HSD's threat limit:** a forum report says the F-16's HSD shows ~16 threats at most since the 12 May 2026 update (`plan.md`, *Still to watch*). 25 is well over. But neither "first 16 spawned" nor "nearest 16" would have dropped the Rovaniemi SA-10, so the HSD would have to pick its 16 some other way (by type or ring size?).
2. **Something about the SA-10 group:** since 2026-10-04 every SAM group carries a supply truck (a Ural-375 last in each Red SA-10 group). The SA-11s got one too and their rings showed, so the truck alone doesn't explain it, but it changed since the runs where SA-10 rings showed.

**Proposed (decide with John):**
- A test mission (like the 2026-10-02 HSD tests, script-built, comms-menu steps): an SA-10 as Kola spawns it (with truck), one without the truck, an SA-11 as control, then a step adding 20 more SA-11s to see whether the limit exists and which rings drop past it.
- Whatever the cause: turn rings on for at most ~15 sites per coalition, chosen on purpose (long-range first, then those covering the front), so the HSD's limit never picks for us.

---

*Bugs 62–71: from the 2026-10-06 00:16 run (`event_logs\2026-10-06_001615.log`, 66 min, John flying MSN2023_OCA from Ivalo on the Kalevala parked aircraft; the first run with Darkstar's orders, roadmap item 7 step 14). Losses Blue 5 / Red 4. Reviewed with John 2026-10-06.*

## 62. Patrols "on station" at takeoff, and relieved by a jet still on its takeoff roll

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown (copied to DCS; checked in a luae harness with stubbed DCS).

**Seen:** Viper 1 (Ivalo), Viper 5 and Viper 6 (Alakurtti) and Hornet 1 (Ivalo) said "on station" 1–5 s after "airborne": their race-tracks lie within 20 km of their bases, and the watcher counted a patrol within `on_station_km` (20) of its race-track as on station. The controller had the same test for a handover: `handover: relieved by MSN2017_CAP, on station (3 km from the race-track)` 16 s after Viper 6's takeoff, so Viper 5 was sent home at once. The other way round, Viper 5 never said off station or checked out: that needed it 40 km from its station, and it landed 2 km from it.

**Fix:**
- A patrol says "on station" at its station waypoint (the waypoint's script command), not by distance.
- It has left its station once the controller sends it home (handover, bingo, leash home, go cold, leave, land: a listener of the controller's decisions) or at its off-station waypoint (its orbit over); then "off station" and the check-out come when it is seen heading home (pointing at its base and closing), however close its station is to its base. An order the AI ignores still gets no call.
- The controller counts a relief as on station only once it has reached its station waypoint (`w.on_station_at`; a patrol spawned in the air on its station counts from its spawn), and within `handover.on_station_km` as before.

**Check:** `RADIO_CALL.*on_station` after the flight's `WAYPOINT … on station` line, never seconds after `airborne`; `handover:` only after the relief's on-station waypoint; an `off_target` / `check_out` for every relieved patrol.

## 63. Darkstar told Weasel 4 "back to your tasking", then "RTB" 5 s later

**For:** framework (found in Kola).

**Status:** open, parked (John, 2026-10-06): option (a) below "sounds good", but SEAD is mostly working, so no SEAD behaviour changes for now. Build (a) when SEAD is opened up again.

**Seen:** `MSN2028_SEAD`, 04:51:34–04:51:49. Weasel 4 (2× F-16, on its low run-in to the Monchegorsk SA-10) took on the Su-30 MSN7009_CAP at 24 km (inside `sead_commit_km`, as designed). The fight climbed MSN2028_SEAD_2 to ~7,600 ft (12,500 ft by 04:52:11):
- 04:51:44 `back on mission: breaking off: MSN2028_SEAD_2 inside the kill zone of SAM_MONC_SA10_1` → Darkstar "you're in a SAM ring, break off, back to your tasking";
- 04:51:49 `go cold: MSN2028_SEAD_2 inside the kill zone of SAM_OLEN_SA10_1` → Darkstar "SAM threat, turn cold, RTB".

**Cause:** two rules, both on the 5 s check, each reacting to the same climb:
1. The fight's break-off (`self_defence`): a SEAD flight outside its shot area breaks a fight off inside *any* ring at its height, its own target's included (bug 39). Its answer is "back to the mission", which for a SEAD flight is the low run-in.
2. The go cold (`suppression`): any ring at its height *other than* its own target's and the rings its route was planned through sends it home for good. At 04:51:44 the wingman was inside Monchegorsk's envelope (its target) but not yet Olenya's; 5 s later, still climbing, it was inside Olenya's too.

So the controller never asks, when it ends the fight, whether the mission can still go on. Both orders were right by their own rule. The AIM-120s were still in the air at the break-off (they killed the Su-30 at 04:52:03); the break-off for a kill zone doesn't wait for missiles in flight, as `time_up` does (bug 44).

**Options (decide with John):**
- (a) A flight whose fight is broken off for a kill zone gets `recover_s` (e.g. 60 s) to get back down to its low run-in before the go cold's ring test applies; still inside a ring after that: go cold.
- (b) One decision instead of two: when the break-off fires and the go cold would send it home at the same height, say only the go cold ("break off, RTB").
- (c) Leave the controller as it is and let Darkstar hold a "resume" call a few seconds, dropping it when an RTB to the same flight follows.

**Since the pilots' answers (roadmap item 7 step 15, 2026-10-06, not flown):** both of Darkstar's calls are still said, but the pilot answers only the last one: a newer order replaces the resume still waiting for its answer, so Weasel 4 would answer "copy, RTB" once it turns home, not "resuming" too.

## 64. A scramble sent home said "off target"

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown. Ragin 3 (MSN2903_SCRAM), leashed home without a fight, said "Ragin three, off target, RTB". Interceptors now have their own condition (`intercept`) in `pilot_phrases.json`: "terminating" / "off intercept", then RTB.

## 65. A scramble's check-in spoke the DCS type name

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown. "Darkstar, Ragin three, airborne Alakurtti, intercept on Su-34 at Ivalo": the watcher passed the raid's DCS type as a place-style target. Now the raid's type goes as `target_type`, worded by the helper like the Fox and splash calls (NATO name or designation): "intercept on the Fullback"; "scramble, intercept" when the type isn't known.

## 66. The flight-call listener failed on destroyed buildings

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown. `dcs.log`: `flight calls: event 8 failed: … announce_flight_activity.lua:240: attempt to index local 'unitName' (a number value)`, 3×, from John's GBU-38s at Kalevala: a map object's name is a number. `nameOf` in the watcher now returns text names only.

## 67. "Departing" was said after the jet had taken off

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown (luae harness: taxi, a runway crossing and a parallel taxiway not counted, lined up counted once, no second call at takeoff). John: backwards for airfield traffic.

**Fix:** the airfield tracker (every 3 s) sees a taxiing jet inside a runway's strip (`lineup_margin_m` 15 beyond its edges and ends; the runways from `Gather`) with its nose within `lineup_aligned_deg` (20) of one of its directions: lined up. New event word `LINE_UP` ("lined up on runway 21 at Ivalo, 2 kt"), and the departing call then, on the runway it is on. At takeoff only if the line-up wasn't seen. A new phrase: "lining up runway two one for departure".

## 68. A lone wingman ignored its landing orders and flew on until the mission ended

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown (luae harness: removed 8 min after its last order while flying away; a jet closing on its base after two orders never removed).

**Seen:** `MSN7024_SEAD_2` (Su-34), its lead shot down: heading 050 at 26,000 ft for 13 min, straight past Koshka Yavr; `land: … lost after its landing` at 05:02:04 and 05:04:04 (`max_orders` 2), still flying at mission end. The orphan removal needed a landing in its flight, and there was none.

**Fix:** after its last landing order, a jet still getting farther from its base (`away_km` past its closest since that order) `orphan_remove_after_s` (8 min) later is removed and counted as landed: `>>orphan<< removed: by the controller: MSN7024_SEAD_2 171 km from Koshka Yavr (it was 66 km away) still flying away 8 min after its last landing order; counted as landed (…)`.

## 70. Both jet-down calls went unheard

**For:** framework (found in Kola).

**Status:** fix built 2026-10-06, not flown; the cause is likely, not proven (no player log in that run).

**Seen:** John heard no "jet down". Both were sent (`speak_mission_calls.log` 00:34:56 "Weasel one, Weasel one one's hit", 01:10:57 "Weasel four one, lost Weasel four two"), each 8 s after a 4–5 group Darkstar picture (~25 s of audio) started. Calls never overlap, so each waited behind the picture, and `jet_down` expired after 20 s.

**Fix:** `jet_down` lives 45 s and `splash` 40 s (`RADIO_CALLS.kinds`), longer than a picture. Fox / Magnum / defending stay at 8 s (no news that late). Bug 69's player log shows each `dropped` from now on. **2026-10-07 20:07 run** (`radio_calls\radio_player.log`, grep `dropped`): no jet-down call dropped (three said, at 04:19:30, 04:51:11, 05:35:02 mission time). 4 of ~100 calls on tuned frequencies were dropped, all short-lived ones in busy moments: Weasel 3-2 (mission, 11 s old, expires after 8 s), Weasel 4-1 and a Darkstar call to Weasel 4 (both 26 s old, during its fight around 04:50), and Wild 4-1 (8 s old). If it still happens: a combat call could cut in on a routine call playing on the other radio, or the pictures get shorter (roadmap item 7 step 12, "a short summary when nothing changed"), which would help more than longer lives.

## 71. Hits and bomb impacts said nothing about where a weapon landed or how much damage it did

**For:** framework (found in Kola).

**Status:** built 2026-10-06, not flown (luae harness with stubbed DCS). John, after the 00:16 run: his GBU-38s at Kalevala were logged as `HIT` on the Mi-8 static and two ZU-23s, twice, but nothing said how close they fell or how hurt the Mi-8 was (he thought he saw 8 % damage), so a miss and a weak hit couldn't be told apart.

**Built:**
- `IMPACT` (new, `consumers/track_weapon_impacts.lua`): every bomb and air-to-ground missile from an aircraft is followed (every 0.1 s) to where it comes down; one line with its grid reference (MGRS, as the F10 map), the objects within 150 m (distance and direction from each, life before → after, or destroyed), or the nearest one when none is that close; "gone in the air … (shot down, or burst)" when it vanished more than 50 m up. The life before is read on its way down (DCS applies the damage in the frame the weapon goes). Settings `EVENT_LOG.impact_*`.
- `HIT` lines end with the life the target has left a second after the hit (`life now 92 %`, or `destroyed`).

## 72. The radio went silent for the last ~5 minutes, though the calls were being sent

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-06 (John: "we can log that one"); not investigated further, no fix.

**Seen:** John, 2026-10-06 17:47 run (`event_logs\2026-10-06_174721.log`): no radio calls heard for about the last 5 minutes, while the Python window showed them coming through.

**What the logs show** (`radio_calls\speak_mission_calls.log`, `radio_calls\radio_player.log`; wall clock):
- The helper worded and sent every call (`… sent`), e.g. Darkstar's pictures at 18:17:24 and 18:19:24, Weasel 2-1's check-in 18:19:46, Darkstar's engage to Cobra 1 18:20:24 and Cobra 1's answer 18:20:26.
- The radio player got them but played none: each `not heard, no radio tuned to 262.000`.
- Just before, from 18:15:29, the export script reported the UHF volume going down, 1.00 → 0.00 in 0.05 steps over 9 s (as a knob turning), and the UHF radio `off` from 0.05 (18:15:38). VHF stayed on 140.000 at 1.00, but no mission-channel call came in that window.
- From 18:20:36 the UHF volume came back up, 0.05 → 1.00 over 8 s; the mission ended about a minute later, no call after it.
- So the player muted the calls because it was told the UHF radio was off. Before the drop, every call on 262.000 was heard at volume 1.00.

**John's account** (2026-10-06, after the run): he lowered his COMM 1 volume, but it had no effect; then the radio calls stopped, including calls on COMM 2; then he turned it back up, and they never came back.

**Set against the logs** (the mission started at ~17:49:20 wall clock: the helper's `mission 1866 s` was at 18:20:26; the mission ended at T+31:57, ~18:21:17):
- **"Lowering COMM 1 had no effect":** while the knob went down (18:15:29–18:15:38), the call playing was a Darkstar picture that had started at 18:15:25, 32 s of audio, at volume 1.00. The player sets a call's volume once, when it starts, so a knob turned during a call changes nothing until the next one. With 25–33 s pictures that is most of the time Darkstar talks. Very likely why the knob seemed dead (and part of bug 69's original report).
- **"The calls stopped, COMM 2 too":** after 18:15:38 every UHF call was muted as `off` (above). On COMM 2 (VHF 140.000) no call was sent in that window: the last mission-channel call was 18:15:10 (Hornet 7-2, rifle), so the logs don't show a COMM 2 call muted, only none to hear. Whether COMM 2 would have played isn't known.
- **"Turned back up, they never came back":** the UHF reading was back at 1.00 at 18:20:44, about 33 s before the mission ended. The helper sent no call after 18:20:26: the next picture was due at mission 1924 s, 7 s after the end (1917 s). So nothing was sent to play in that last half minute. That doesn't prove it would have come back.

**Open questions:**
- `off` from a volume of 0.05: does DCS's UHF report `is_on() == false` at the bottom of the knob, or does our export script / player treat a near-zero volume as off? Turning the volume down should make calls quieter, not switch the radio off.
- A knob turned during a call: apply it live (the player plays a call in one piece with `winsound`, which has no volume control while playing), or at least to the next call, and say so in the log.
- To prove the rest in one test: turn COMM 1 down to zero and back up, with both radios on, and listen for COMM 2 calls during it and UHF calls after it (a long enough run after turning it up).
- The wording `not heard, no radio tuned to 262.000` is misleading when a radio is tuned to it but off or at zero volume: it should say so ("UHF on 262.000 is off").

**2026-10-07 20:07 run, a data point for the first question** (`radio_calls\radio_player.log`, the jet's radios lines): John turned COMM 1 (UHF 262.000) down several times, at 20:54:28–20:54:31 from 0.50 to **0.05**, and the export script kept reporting it `on` (then 0.10, back up to 0.20–0.50 later); VHF went down to 0.30 and back the same way. Both radios read `off` only when DCS quit (21:49:26). So this time a near-zero knob did not read as off. 96 calls were heard through the run, following the tuning (UHF 305.000 until 20:34, then 262.000; VHF 127.000 → 128.200 → 140.000 → 128.200). Whether the 2026-10-06 `off` came from the knob's very bottom (0.00) is still open.

---

## 73. The Sukhumi SA-10 shot down all 16 HARMs of both SEAD tries, and blocks Blue's western attacks

**For:** framework (found in Caucasus).

**Status:** open, logged 2026-10-07. No fix chosen.

**Seen:** `missions\caucasus_multiplayer_random_tasking\event_logs\2026-10-06_224344.log` (John's first Caucasus flight), grep `SAM_SUKH_SA10_1`, `MSN2025_SEAD`.
- MSN2025_SEAD (Weasel 1, 2× FA-18C from Kobuleti), 09:11:53–09:12:03: 8 AGM-88 from 45–50 km, fired from 1,062–2,000 ft. The lead was at 1,999 ft at its "top of the pop-up" waypoint. The SA-10's launchers fired about 13 SA5B55 at the incoming HARMs, from 29 km down to 18 km. All 8 are `IMPACT … gone in the air`, 3–5 km above the ground and 14–21 km short of the site.
- MSN2025_SEAD_AGAIN (Wild 1), 09:36:54–09:37:06: 8 more from 44–50 km, fired from 1,085–2,045 ft. All gone in the air 5–6 km short, 1.2–1.6 km up. The SA-10 and its escort Tor (`SAM_SUKH_SA10_1_escort_1`, 8 SA9M338K) both fired at them.
- The site took no damage. MSN2028_SEAD waits on it (`waiting for SAM_SUKH_SA10_1's SEAD flight to come back (MSN2025_SEAD_LATER)`), and MSN2031, 2034, 2036, 2039 and 2040 list it in their `after`.

**Not specific to Caucasus** (John asked 2026-10-07 why Caucasus fires from farther out than Kola; it doesn't):
- `launch_km` 45 is shared (`data\air_tasking.lua`, `suppression_of_air_defenses`), and both missions fire from the same distances.
- Kola since 2026-10-02: HARMs at SA-10s fired from 35–54 km in 11 runs; an SA-10 part was hit in 4 of them (10-02 17:48, 10-03 14:15, 10-04 14:20, 10-04 22:39).
- The Kola kill from 35–41 km (2026-10-01 14:14 run) was before `launch_km` went to 45 (bug 33: the sites fired back at the pop-up from 39–50 km).
- **The pop-up isn't reached by Blue in either mission:** `popup_altitude_m` 2,400 (~7,900 ft), but Blue's "top of the pop-up" lines show 2,000–2,400 ft here and 2,300–4,600 ft in Kola. Red's Su-34s reached 7,800–7,900 ft here. A HARM fired from 1,000–2,000 ft has a long, low-energy flight, so the S-300 gets plenty of time to shoot it down.

**The low pop-up again in Kola** (`event_logs\2026-10-07_200750.log`, grep `top of the pop-up`): Blue's F-16 SEAD flights at the top of the pop-up at 3,730 ft (MSN2025), 4,303 ft (MSN2024), 4,406 ft (MSN2026) and 3,355 ft (MSN2028_SEAD_AGAIN), planned 7,874 ft; they kept climbing and fired from 4,900–9,800 ft at 39–47 km. Against SA-11s that was enough (three search radars destroyed); MSN2024_SEAD_2 was killed by its target SA-11 (fired at it from 38 km at ~6,700 ft). Red's Su-34s fired from 11,000–14,800 ft (MSN7024, MSN7025). So Blue's jets don't reach the pop-up altitude in either mission; Red's do.

**Cause:** not known yet. Likely factors: low launch altitude, a 45 km shot, and the SA-10's own defence against the missiles. A 2-ship salvo of 8 doesn't saturate 8+ launchers.

**Options (decide with John):**
- A pop-up that really reaches its altitude before the shot (why Blue's doesn't is a question of its own).
- A closer launch point for long-range sites only, accepting bug 33's return fire.
- Two SEAD flights at once on an SA-10, to saturate it.
- A DEAD follow-up while the site reloads.

## 74. A SEAD flight on the Mineralnye Vody SA-10 reached its launch point with the radar dark, pressed on and both jets died without a shot

**For:** framework (found in Caucasus).

**Status:** open, logged 2026-10-07. No fix chosen.

**Seen:** same log, grep `MSN2026_SEAD`.
- MSN2026_SEAD (Weasel 2, 2× FA-18C from Kobuleti) flew a 47-waypoint route across the main Caucasus ridge to `SAM_MINV_SA10_1`, a rear-area site guarding Mineralnye Vody. Its "low level" legs were at 8,000–14,000 ft above sea level over the mountains.
- At its launch point (09:20:48, 46 km out, 7,835 ft, 3,409 ft above the ground): `its radar not seen`. The jets' warning receivers held the Mineralnye Vody SA-11 and SA-8 but not the SA-10. The flight pressed on (bug 36's press-on).
- The SA-10 lit up and fired at 43 km (09:21:01 and 09:21:04; `TRACKING` 09:21:07), 4 SA5B55 in all. Both jets were destroyed at 09:21:35 and 09:21:39, and both pilots were killed.
- Not one HARM was fired, even after the site's radar was on them. The only reaction logged is Weasel 2-1's `defending` call.

**Also a planning question:** this deep rear-area SA-10 was attacked in the first wave, while both front SA-10s (Sukhumi, Gudauta) still stood. It is not in Blue's rotation. Most likely it was planned because the route of the player DEAD task on the Mineralnye Vody SA-8 (MSN2024, `after SAM_SUKH_SA10_1, SAM_MINV_SA10_1`) crosses it.

**Related:** Kola bugs 36, 39 and 40 (no shot at the launch point, a fight at the pop-up, the SA-10 killing the flight before it fires).

**Cause / fix:** to look into with John. Questions:
- A long-range site that is dark at the launch point: press on into its ring, or hold outside it?
- Why did the Hornets not fire once the site was tracking them?
- Should a deep SEAD on a rear site wait until the front sites are down?

---

## 75. AI wingmen don't land once their lead has landed (bug 19's cause, still open)

**For:** framework (found in Kola, seen again in Caucasus).

**Status:** open, logged 2026-10-07; researched, no fix built. Bug 19 (`closed.md`) put in the workaround: landing orders, and the controller removing a jet still up 8 min after its lead landed, counted as landed. That hides it but the cause is still there. **Fixes to try in this order** (John, 2026-10-07): 1, then 2, then 3, one per test flight, each judged on its `>>orphan<<` lines.

**Seen** (every `>>orphan<<` line in all Kola and Caucasus event logs, counted 2026-10-07):
- **Always a wingman (`_2`); every lead landed.** 27 times a wingman was still in the air when its lead touched down: 6 landed, 18 were removed by the controller or lost, 3 were still up at mission end.
- **Two shapes.** Kola: the wingman flies off in a straight line at its holding altitude (~4,200–4,450 ft, 300–315 kt), from about the lead's touchdown (bug 19). Caucasus (`missions\caucasus_multiplayer_random_tasking\event_logs\2026-10-06_224344.log`, grep `POSITION     MSN2025_SEAD_2`, `MSN2025_SEAD_AGAIN_2`, `MSN7016_SEAD_2`): all 3 orphaned; each flew the pattern at 6,240 ft, came down to ~1,000 ft at 140–180 kt (final), went around on afterburner (fuel 51 → 36 % in 2 min) and climbed back, until the controller removed it.
- **Our landing orders are ignored.** With a jet of the flight on the ground, `GiveOrders.land` gives each jet in the air its own order on its unit controller; the log always follows with `no answer to land_at …: not seen following it in 60 s`.

**Ruled out: parking or traffic at the base.** Checked each orphan against ramp spawns and takeoffs at the same base from 5 min before to 8 min after the lead's touchdown: most orphans had none, and several wingmen that did land had them.

**Cause (from DCS users' reports, matching what we see):** a DCS AI wingman follows its lead in the landing too. It waits for the lead to clear the runway, and once the lead has parked and shut down, there is nothing left to follow, so it either holds and flies on, or keeps going around ([forum: AI wingmen](https://forum.dcs.world/topic/7807-question-about-ai-wingmen/); [formation landings](https://forum.dcs.world/topic/230088-formation-takeoffs-and-landings-as-2)). Reportedly, single jets of a group can't be given a mission while another of the group is on the ground ([forum thread](https://forum.dcs.world/topic/277371-tasking-with-wingman-on-ground/); the forum refused a direct read, so not confirmed): that fits our ignored orders. Leads on their own land reliably.

**Fixes, in John's order:**
1. **Force a pair landing.** DCS has an AI option for this (found 2026-10-07 in `DCS World\MissionEditor\modules\me_action_db.lua`): `LANDING_OPTIONS`, option id **36**, values `0` straight-in (the default), `1` **force pair landing**, `2` restrict pair landing, `3` overhead break; in the mission editor "Landing Options" under Set Option, airplanes only (next to it, id 37 `ALLOW_LINE_UP_RW`, the formation takeoff). Set `Controller:setOption(36, 1)` in each AI 2-ship's start options (`spawn_aircraft_groups.lua`, with the other options at the first waypoint), and again with every order that sends a flight home or to land (`GiveOrders`), in case a new task resets it. Both jets then land together, so there is no lead to wait for. Check: whether DCS also honours it after a `setTask`, and whether both jets touch down (two `LAND` lines seconds apart, no `possibly orphaned`).
2. **Land the wingman first.** While both jets are still in the air on the way home (the `landing` directive, or the order that sends the flight home), send the wingman to land ahead of its lead, e.g. the lead given a short hold or a longer route in (an `Orbit` near the base for a minute or two) and the wingman the straight-in landing, so it never waits behind a landed lead. The reported players' workaround. Uncertain: DCS lands a group as a group, and a separate order to one jet of an airborne group may pull it out of formation in ways we don't control.
3. **Despawn and respawn the wingman as its own flight.** When its lead touches down and the wingman is still up: remove it and spawn the same jet (type, loadout, fuel, skill, callsign) as a 1-ship group at its position, altitude, heading and speed (an air start, as scrambles and the AWACS use), with one waypoint: land at its base. A lone jet leads its own group, and leads land. Watch: the flight's bookkeeping (the new group counted as the old wingman for the scheduler, the event log, the radio and the gate), and that the swap isn't visible (no weapons or fuel change).

**Check after each:** grep `>>orphan<<`: `not orphaned` should replace `removed`; and `LAND` for both jets of each 2-ship.

**2026-10-07 20:07 run, before any of the fixes** (`event_logs\2026-10-07_200750.log`, grep `>>orphan<<`): 5 wingmen still in the air when their lead landed; the first 4 landed 3 min 18 s to 4 min 55 s after their lead (`not orphaned`), and the 5th (MSN7025_SEAD_2) was still up when the mission ended 2 min later. None removed. MSN2025_SEAD_2 (Kallax), MSN2026_SEAD_2 (Kallax), MSN7036_STRIKE_2 (Tu-22M3, Severomorsk-1), MSN7024_SEAD_2 (Rovaniemi). Each was given the per-jet landing order; MSN2026_SEAD_2 still got `no answer to land_at … not seen following it in 60 s` and landed 4 min 21 s after the order. Each was at 3,774–4,320 ft, 6–17 km from its field when its lead touched down (their tracks in between not looked at). A run where the wingmen land anyway; it doesn't change the fix order, but the fixes should be judged on several runs.

---

## 76. Absolute Windows paths with the username are written into the repository

**For:** framework and every mission (repository-wide).

**Status:** open (John, 2026-10-07: use relative paths so my Windows paths aren't in the repo). Found while checking the repository before making it public again. Not a secret, but it puts the Windows username and folder layout in every copy, and the code only runs on a machine laid out the same way.

**Seen:** `git grep -nIiE 'C:[\/]+Users[\/]+johnk'`, 22 lines in 13 files (2026-10-07):
- **Settings the code reads** (these break on any other machine): `missions\kola_f16_random_tasking\kola_f16\mission_settings.lua` and Caucasus's (`event_log_folder`, `repository_folder`); `shared_mission_framework\mission_scripts\data\radio_calls.lua` (`calls_file`, `start_command`); `map_data_tools\aircraft_loadouts.py` (`DEFAULT_LIBERATION`), `map_data_tools\unit_pool.py` (`DEFAULT_PYDCS`).
- **Comments, usage lines and docs:** `map_data_tools\mission_folder.py`, `update_zone_data.cmd`, the generated headers of `mission_scripts\data\aircraft_pylons.lua` and `unit_pool.lua` (written by the tools, so fix the tools, not just the files), `missions\syria_a2g\offline_test_harness.lua` and `notes.md`, `plan.md`, `framework_design.md`.

**Proposed fix:**
- **Python tools:** paths from the script's own folder (`Path(__file__).resolve().parent`) or the repository root; sibling checkouts (pydcs, dcs_liberation) as `<repo>\..\pydcs`, overridable by the existing `--pydcs` / `--liberation` options or an environment variable. Generated file headers say `pydcs checkout` without the path.
- **Mission scripts (inside DCS):** a relative path in DCS's Lua resolves against the DCS install folder, not the repository, so they can't simply go relative. Options: build them from `lfs.writedir()` (the Saved Games folder) where they live there; or keep the machine's paths in one untracked file (e.g. `mission_settings.local.lua`, in `.gitignore`) read over the defaults, with a committed `mission_settings.local.example.lua` showing `C:\Users\<you>\...`.
- **Docs and comments:** `C:\Users\<you>\...` or `%USERPROFILE%\...` (several docs already use `<you>` / `<username>`).
- **Check:** the grep above returns nothing, and a run still writes its event log and plays radio calls.
- The paths stay in the old commits; only a history rewrite (`git filter-repo --replace-text`) would remove them there. Not planned: low risk.

---

*Bugs 77–83: from the 2026-10-07 20:07 run (`event_logs\2026-10-07_200750.log`, 1 h 39 min; John flying MSN2023_DEAD from Kallax on the Kittila SA-11 #2, then a second sortie with HARMs toward Hosio). Losses Blue 5 (SAM sites 4, aircraft 1) / Red 6 (aircraft 4, the two ramp losses of bug 13). `dcs.log` clean: no script error; the 17 Lua tracebacks are DCS's AWACS voice ("Callname -1"). Reviewed by Claude 2026-10-07; John: log everything, no code fixes yet.*

## 77. After a fight, a SEAD flight's pop-up, top, launch and press-on waypoints were all counted reached at once, and it went home with every HARM

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. No fix built. Goes with bug 39's unbuilt second part (back to the shot after a fight).

**Seen:** grep `MSN2028_SEAD` (Weasel 4, 2× F-16C from Kallax on the Rovaniemi SA-10, the rotation's first site).
- Low run-in as planned (900–1,200 ft, ~540 kt) to waypoint 12 at 04:49:03, 52 km inside the SA-10's ring.
- `press on` on the Su-30 MSN7002_CAP at 97 km (04:47:34). At 04:50:09 the Su-30 fired an R-77 at it from 22 km; `defend` 04:50:10 (it had already fired an AIM-120C at 25 km at 04:50:03); the Su-30 was killed at 04:50:34; `back on mission: MSN7002_CAP destroyed (29 s)` at 04:50:39. The SA-10 was tracking it from 04:50:13 and fired 2 SA5B55 at the wingman from 49 km at 04:50:26.
- **04:50:43, all in the same second:** waypoints 13 (pop-up), 14 (top of the pop-up), 15 (target, i.e. the launch point) and 16 (press-on point) reached, the lead at 10,480 ft (the fight had climbed it), 54 km from the site. The press-on point lies up to 20 km past the 45 km launch point, so the flight was nowhere near it.
- `RADAR_WARNING` at the launch point and at the press-on point, both 04:50:43: **"its radar SEEN"** (the SA-10 and the Rovaniemi SA-11s and SA-6 on the warning receivers).
- **04:50:44** `go cold: no shot: pressed on to 54 km from SAM_ROVA_SA10_1 with no radar to shoot at, all 8 anti-radiation missiles aboard`; Weasel 4's "no shot" report and Darkstar's copy. The `EngageGroup` put on at the top of the pop-up had 1 s.
- On the way home low the SA-10 killed MSN2028_SEAD_2 (04:51:11, 1,073 ft, 81 km inside the ring; pilot killed). The lead landed at Kallax 05:16:27 with 8 HARMs.

**Cause (suspected, not proven):**
1. **DCS ran the skipped waypoints' commands in one burst.** The resume (`GiveOrders.resume`) only sets the fight's stop flag; the DCS AI then goes back to its route. The fight had taken it about to the pop-up point, and DCS apparently counted waypoints 13–16 as passed and ran their script commands together (the `WAYPOINT` lines and the controller's waypoint calls, `control_air_flights.lua:356`, which sets `memo.suppression.pressed_on` at the press-on waypoint).
2. **The no-shot rule trusts that waypoint call** (`directives_per_flight.lua:152`): `pressed_on` and every missile aboard → home, whatever the flight's real distance to the press-on point and whether the site's radar is seen.

**Options (decide with John):**
- The no-shot go cold only when the flight is really at its press-on point (its closest jet within a few km of it, or as close to the site), and not while the site's radar is on its warning receivers; else let the `EngageGroup` fire.
- Or, after a fight ends inside the shot area with every missile aboard, give the flight a new attack from where it is (bug 39's second part), and ignore waypoint calls that arrive in a burst (several in the same second).
- First check in the harness or a test mission whether a pushed `AttackGroup` ended near later waypoints really makes DCS run their commands at once.

## 78. The SEAD rotation waits for a flight that has gone cold to land, and says it is "still on its attack"

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. No fix built.

**Seen:** grep `MSN2028_SEAD`, `MSN2040_DEAD`, `MSN2029_SEAD`.
- MSN2028_SEAD went cold at 04:50:44 (bug 77). Its retry, MSN2028_SEAD_AGAIN, spawned at **05:16:28, 1 s after its lead landed**, 26 min after the go cold (bug 57's fix meant 5 min after it came off its task).
- Meanwhile Blue's DEAD MSN2040 (waiting on the Rovaniemi SA-10) logged `wait: waiting for MSN2028_SEAD, still on its attack; looking again at 05:23` at 05:13:24, 23 min after the go cold, and again for MSN2028_SEAD_AGAIN (05:23:24, 05:33:24).
- The rotation's next flight, MSN2029_SEAD, spawned `launch late: 23 min after its planned start`, at 05:35:22, 1 s after MSN2028_SEAD_AGAIN's last jet died. Red's rotation shows the same rule from the other side: MSN7024_SEAD and MSN7025_SEAD each `launch early … (the rotation's flight before it is down)`, at the moment the one before it was down.

**Cause (from the code):** `decide_launches.lua`, in the gate's look at each open threat: a rotation flight whose site is still in the fight waits while the rotation's flight in the air isn't down (`isDown`: every jet landed, lost or removed), line ~504, and the wait line words every spawned flight waited for as `still on its attack` (line ~526). So a flight that has gone cold holds the rotation, and its own retry, until its last jet lands, and the log says it is still attacking. `stillOnAttack` itself (in the air and on its task) was right: MSN2028_SEAD was `going_home`.

**Options (decide with John):**
- A rotation flight that has gone cold (or been sent home) gives up its place at once, so the retry and the rotation's next flight come `retry_after_s` after the go cold, as bug 57 meant ("once it is done there's no point waiting for it to land", John, 2026-10-02).
- Or keep one rotation flight in the air at a time on purpose (no two SEAD flights near the same corridor), but then say so: `waiting for MSN2028_SEAD to land (gone cold at 04:50)`.

## 79. A relieved patrol checked out before it answered Darkstar's RTB

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. Radio wording only.

**Seen:** grep `MSN2002_CAP` (Hornet 1, F/A-18C patrol from Tromsø); `radio_calls\speak_mission_calls.log` 21:13:05–21:13:06.
- 05:03:04 `handover: relieved by MSN2003_CAP` → Darkstar "Hornet one, Darkstar, Viper one on station, you're relieved, return to base" (UHF).
- 05:03:04 (same second) "Hornet one one, off station, RTB Tromso" (VHF) and **"Darkstar, Hornet one one, checking out"** (UHF).
- 05:03:06 Hornet 1's answer to the RTB (2 s after the order).
- Step 15 says the answer to an RTB is the check-out: no `check_out` after it. Eagle 5's handover the same run came out right (05:01:04 RTB, answer 38 s later, then "off station", no check-out).

**Cause (suspected):** Hornet 1 was already pointing home when the order came, so the watcher saw it "heading home" in the same check and said off station and the check-out before the answer (which waits to see the order followed) could stand in for it. The suppression of the check-out only works when the answer comes first.

**Proposed:** once a controller order that the pilot answers is said to a flight, hold its check-out until that answer is said (or its wait is over), then drop it.

## 80. Kallax's "inbound" calls named runway 31, the AI jets landed on 13

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. Radio wording; the landing itself is DCS's.

**Seen:** grep `RADIO_CALL.*Kallax traffic`. Departures all called and seen lined up on runway 31 (`LINE_UP … runway 31`). Weasel 2-2 (04:23:43) and Weasel 4-1 (04:59:28) called "inbound … runway 31"; Weasel 2-1 (04:26:37) and Weasel 3-1 (04:45:07) called final and clear on **runway 13**. Wind from 257° at 8 kt: about 5 kt down runway 31's direction (headwind), 5 kt tailwind on 13; DCS landed them on 13 anyway.

**Cause (suspected):** the inbound call names the runway in use by the wind (the airfield brief's logic), while final and clear name the runway the jet is actually on. DCS picks its own landing runway.

**Options:** say no runway in the inbound call (it isn't known yet), or name the one DCS's AI is landing on if it can be read; or leave it, since final names the real one.

## 81. A MiG-31 scramble took 8½ minutes from its hot ramp spawn to takeoff

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. Log only.

**Seen:** grep `MSN7901_SCRAM`. `scramble: MiG-31 from Vuojarvi after MSN2036_DEAD … 7 min from SAM_SODA_SA8_1; intercept 88 km out; launching in 67 s` at 05:16:04; spawned hot on the ramp 05:17:11; **takeoff 05:25:38**, 8 min 27 s later. By then the DEAD flight had fired its JSOWs (05:19:37) and was on its way home; the MiG-31 reached its intercept point (05:32:31) and was leashed home (05:33:04, "back over its own airspace, heading away"). The scramble's own check reckons the reaction time (`scramble_reaction_s`, 60–120 s) plus the flight time, not a long taxi.

**Cause (unknown):** a long taxi from Vuojarvi's alert spot to the runway, a taxi queue, or the DCS AI's start-up. Not checked: which spot it had, and whether other Vuojarvi spawns this run were as slow.

**Proposed (decide with John):** look at the alert spots held at Vuojarvi (distance to the runway end), and how long hot spawns there take to get airborne in other logs; then either pick alert spots near the runway, or count a base's taxi time in the "can it get there in time" check.

## 82. The Kallax slot's player logs under the unit name f16_human_1_1 (bug 24 again, one slot)

**For:** Kola (its `.miz` slot template).

**Status:** open, logged 2026-10-07. Bug 24 (`closed.md`) was fixed by renaming each slot template's unit to match its group; the Kallax slot still logs as `f16_human_1_1` (noted in the 2026-10-05 10:31 run too).

**Seen:** `PLAYER_IN`, `TAKEOFF`, `POSITION`, `SHOT`, `IMPACT`, `LAND` say `f16_human_1_1`; the radar picture's `CONTROL … no scramble` lines say `f16_kallax`. "New callsign" in those lines is John's DCS logbook pilot name, not the mission's.

**Proposed fix:** rename the Kallax template's unit in the Mission Editor to `f16_kallax_1` (or whatever matches its group), as bug 24 did for the others; or log the group name on player lines too.

## 83. Event log wording: a dispenser opening reads as a weapon shot down, and a player's shots name no target

**For:** framework (found in Kola).

**Status:** open, logged 2026-10-07. Log wording only.

**Seen:**
- John's 4 AGM-154A (04:34:59, 25,701 ft) and MSN2036_DEAD's 4 (05:19:37–46): each `IMPACT … gone in the air … 517–537 m above the ground (shot down, or burst)`. A JSOW-A opens at about that height by design; its BLU-97s then hit (3 SA-11 launchers destroyed by John's, the SA-8's radar by MSN2036's). The line reads as if the weapons were shot down.
- John's `SHOT` lines have no target or range (`F-16C_50 fired 4x AGM_154A, from 25,701 ft`; `fired 2x AGM_88, from 5,939 ft`): DCS gives no target for them. His 4 HARMs at 05:21:57–05:22:13 then show `hit the ground … nothing within 150 m` (3) and one gone in the air 4 km up, so it can't be read what they were fired at.

**Proposed:** for cluster weapons (JSOW-A, CBUs, RBKs), "opened at 520 m above the ground, n m from <nearest object>", told apart from a shot-down weapon by the weapon type and height; for a player's anti-radiation missile with no target, name the nearest enemy radar ahead of the shot (as `RADAR_WARNING` lists them) as its likely target.
