# Kola F-16 Random Tasking: bugs and fixes

Bugs found in runs, with what was seen and the fix proposed, to come back to. Each entry says where the evidence is. When one is fixed, it moves to `closed.md` (under *Bugs*, with its number and the fix), and any as-built facts go in the framework's `as_built.md`. Numbers aren't reused.

**Since 2026-10-06 Kola runs on the shared mission framework** (`shared_mission_framework\`): most of the code these bugs name is shared now (`shared_mission_framework\mission_scripts\`, `radio_calls\`, `map_data_tools\`; `kola_data_tools\` is now `map_data_tools\`), so a fix there reaches every mission on it. A `plan.md` section named here that isn't in Kola's `plan.md` any more (*The controller*, *Radio calls*, *Stages 5–6* …) is in `shared_mission_framework\development_docs\as_built.md`, under the same name. A fix that changes behaviour means re-recording the offline harness's baselines right after it (framework `plan.md`, *Picking this up*).

---

## 3. Scrambles keep firing at patrols on their race-tracks

**Status:** open, accepted for now (John, 2026-10-01, after the run with bug 2 fixed: "a little annoying, but acceptable for now"). Seen again in `event_logs\2026-10-01_141412.log`: four Blue scrambles (MSN2901, 2903, 2904, 2905) at one Su-33 patrol, MSN5016_CAP, on its race-track over Red's own airspace, all stood down; MSN2903 7 s after spawning. With bug 2 fixed each jet goes back on alert, so it's only noise.

**Seen again, more of it, now every fitting base is an alert base** (bug 16; `event_logs\2026-10-02_145532.log`, 50 min): three Blue scrambles at one MiG-31 patrol, MSN7016_CAP, on its race-track over Red's airspace, all stood down on the ramp with "back over its own airspace, heading away": MSN2901 (Enontekio, intercept 35 km out), MSN2902 (Banak, **125 km** out), MSN2903 (Enontekio, **159 km** out). Red's MSN7902 was stood down the same way at Blue's F-16 patrol MSN2009_CAP, and MSN7901 before launch at MSN2002_CAP. 5 of 7 scrambles in the run were this churn. Tune with bug 32 (the same "inbound / heading away" test, read the other way).

**Change built 2026-10-06, not flown** (John asked whether three inbound checks would do; a race-track leg is 50 km, ~3.5 min, ~7 picture rounds pointing the same way, so three wouldn't): a contact still over its own airspace must be inbound `scramble_inbound_rounds_enemy_airspace` (8) rounds in a row, 4 min, longer than a leg; a turn away resets the count. In contested and own airspace it stays 2. Seen in the 00:16 run: 6 of 7 scrambles were this churn (Blue MSN2901, 2902, 2904 at Red patrols; Red MSN7901, 7902, 7903 stood down before launch). **Check:** fewer `scramble` lines that end in `stand down`; whether a real raid from deep in its own airspace is now answered too late (`can't reach the raid before it reaches …`).

**Worse on the 2026-10-04 22:39 roll** (`event_logs\2026-10-04_223922.log`): about 14 of ~30 Red scrambles stood down on the ramp, 7 of them at Blue's Alakurtti patrols (MSN2016_CAP, MSN2017_CAP: Alakurtti is the Blue pocket inside Red, so each race-track leg reads as inbound); Blue 5 of 11. See bug 50 too.

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

## 6. Su-24M SEAD flights spawn with no weapons

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

**Status:** worked around 2026-10-01 (John: open parking only for now). The Su-34's profile allows only terminal 104 (open-air) spots; the DCS test of spot size is still open.

**The same spot twice** (`event_logs\2026-10-04_223922.log`, grep `RAMP_LOSS`): Su-27 scrambles MSN7917 (04:44:54) and MSN7937 (06:00:58), both at **Afrikanda spot 22**, both 13 s after spawning, no killer. Points at the spot, not the type: taking spot 22 (and 37, 2026-10-01) out of use at Afrikanda would be the cheap fix (not built; decide with John).

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

**Status:** open (found 2026-10-02, review of the 14:55 run).

**Seen:** `event_logs\2026-10-02_145532.log`; grep `retry`. Both rotations retried at once, as the rotation's next flight, with the same base, route and profile: MSN7023_SEAD_AGAIN spawned at 04:11:59, 1 s after MSN7023's last jet died, and MSN2025_SEAD_AGAIN at 04:13:09, 1 s after MSN2025's. Both retries were lost like the first (bug 33). 4 jets per side against one site in ~15 min. John, after the 00:57 run: losing some SEAD is fine, losing most isn't.

**Seen again** in the 16:50 run (`event_logs\2026-10-02_165055.log`): MSN2025_SEAD_AGAIN spawned at 04:15:56, 1 s after the SA-10 killed both F-16s of MSN2025 (bug 40), same base and route.

**Cause:** the rule (roadmap item 12, point 8): a site still in the fight after its SEAD flight gets one more try, and the rotation flies it next. It doesn't ask whether the first flight fired its salvo and came back, or was shot down. A flight shot down before or at its salvo is exactly the case where a second identical try is most likely to die too.

**Proposed (decide with John):**
- A flight **lost** at its target: no immediate retry. Move on down the queue and come back to the site later (or never: mark it "too hot" for this roll, log why), "no second wave into what killed the first" (doctrine idea in `plan.md`).
- A flight that **fired and came home** but the site survived: retry as now.
- Or space the retry (e.g. ≥ 30 min) and send it from another base / bearing.

---

## 36. A low SEAD flight reached its launch point, fired nothing and flew home

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

## 38. Blue's AWACS adds nothing to the picture until it reaches its station, ~26 min into the mission

**Status:** open (John, 2026-10-02, 16:03 run: "it has a radar, it's flying at altitude"). **The first fix is built, not flown; copied to DCS 2026-10-02 with bug 36's fix** (John, 2026-10-02): the `AWACS` task moved from the station waypoint to the takeoff waypoint (`spawn_aircraft_groups.lua`), so it runs from wheels-up; the orbit stays on the station waypoint. The next run shows whether cause 2 was it: `seen by awacs` lines while the E-3A is still on its way out. Cause 1 (far base, far station) is untouched. **Seen working in the 17:15 run** (`event_logs\2026-10-02_171553.log`): the E-3A (takeoff 04:01:27 from Bodo) gave Blue its first `seen by awacs` contact at 04:09:04 (MSN7016_CAP, 132 km from Rovaniemi), 12 min before it reached its station at 04:21:36. So cause 2 was real and is fixed; move to `closed.md` once John agrees. **Cause 1 settled too, 2026-10-04** (John: neither side would launch without AWACS coverage): both AWACS now start in the air on their station at mission start (`takeoff = "air"`; `plan.md`, *Defensive air*), not flown yet.

**Seen:** `event_logs\2026-10-02_160358.log`; grep `MSN2001_AEW`, `seen by awacs`. The E-3A took off from Bodø at 04:01:27 (the held base farthest from the enemy, by design), was at ~29,300 ft by 04:12, and reached its station at 04:27:22. Its first contact (`seen by awacs`) was at 04:26:04, a minute before the station. Until then Blue's picture held 0–1 contacts, all from ground radars or a patrol (`PICTURE` 04:05 / 04:10 / 04:15 / 04:20: 0, 1, 1, 2 contacts). Red's A-50 behaved the same way: on station at 04:06:32 (it launched much nearer the front), first contact 04:05:04.

**Causes (two, the second not proven):**
1. **Far and slow to get there:** it launches from the base farthest from the enemy and flies ~26 min to an orbit ~200 km behind the front (`AIR_DEFENSE`: 200 km from every enemy base). At 04:12 it was ~420 km from Banak, likely beyond its reach for fighters over Finnmark, some of them low.
2. **Its radar may only work once the AWACS task starts:** the spawner puts the `AWACS` task on the **station** waypoint (`spawn_aircraft_groups.lua`, `early_warning_on_station`), and DCS starts a waypoint's tasks only on arrival. If the DCS AI's AWACS radar (and so `getDetectedTargets`) only runs under that task, it's blind all the way out. Both AWACS's first contacts came just before their station waypoints, which fits, but the distance alone could explain it too.

**Proposed fix (decide with John):**
- Put the `AWACS` task on the takeoff waypoint (as patrols already get their zone engage tasks there), so it works the whole way out; the orbit stays on the station waypoint. Cheap, and it settles cause 2.
- Launch it from a base nearer its station, or bring the station closer to the front (it's 200 km from every enemy base now), so it is on station sooner.

---

## 39. A SEAD flight that fights at its pop-up passes its launch point during the fight and goes home with every missile

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
- Proposed with the rest of bug 39: while a SEAD flight is on its low run-in, a bandit call either keeps the fight low (no way to tell DCS that, as far as known) or breaks off as soon as the flight climbs above the low altitude inside any ring, its own target's included.

---

## 40. A SEAD flight reaches its launch point a third of the way up its pop-up, and the SA-10 kills it there before it fires

**Status:** part fixed 2026-10-02, not flown (copied to DCS). Found in the 16:50 run, the first with bug 36's fix (pop-up to 2,400 m, press-on leg). **Built** (John: get the fixes in): a `popup_top` waypoint `popup_climb_km` (3) past the pop-up point, already at the pop-up altitude, so the AI climbs hard there and is up before its launch point (steerpoint `TOP`; the `EngageGroup` stays on the pop-up waypoint). The launch distance is unchanged (John: the salvo gets through from close in). **Still open:** suspect 3, the SA-10 not on the RWR list (watch `RADAR_WARNING` in the next run; the test mission if it shows again).

**Seen:** `event_logs\2026-10-02_165055.log`; grep `MSN2025_SEAD`, `SAM_KOSH_SA10_1`. 2× F-16C (4 HARMs each) from Kirkenes on the Koshka Yavr SA-10, step 1 of Blue's rotation, flying low from takeoff (Kirkenes is close).
- The lead took off at 04:07:34 and circled near Kirkenes at 200–860 ft until its wingman took off at **04:12:33, 5 min later**. The wingman caught up at 740 kt.
- 04:14:34 pop-up waypoint at **1,249 ft**. 04:15:12 launch point waypoint (46 km from the site) at **2,825 ft (2,334 ft above the ground)**, not the planned 2,400 m (7,874 ft). The `POSITION` at 04:15:04: both jets ~2,810 ft, 410 / 503 kt, the lead's external tanks already gone (fuel read 102 % with tanks at 04:14, 100 % without at 04:15).
- **The SA-10 tracked and fired first:** 04:15:07 `TRACKING`, and 4 SA5B55 at the two F-16s from 45–49 km between 04:15:07 and 04:15:21, at ~2,800 ft. Both F-16s were destroyed at 04:15:55 (1,270 ft and 3,994 ft), 43 s after the launch point. **No HARM fired.** The press-on point was never reached.
- **`RADAR_WARNING` at the launch point (04:15:12): the SA-10's radar "not seen"**, 5 s after the SA-10 fired its first missile at the flight. On the warning receivers instead: the A-50 (`MSN7001_AEW`), the Su-27 patrol `MSN7002_CAP`, and the Luostari SA-8 (`SAM_LUOS_SA8_1`). So the AI's warning receivers do list ground radars, but not this SA-10 while it was engaging.

**Suspects (not proven):**
1. **The climb comes too late.** DCS spreads the climb over the leg to the next waypoint (*DCS facts*: "an AI descends toward the next waypoint's altitude from the previous one", climbs too), and it counts the pop-up and launch waypoints as reached a few km early. So the jets were only ~1,600 ft higher at the launch point than at the pop-up. They spent the whole 8 km leg low-ish and slow, inside the SA-10's reach.
2. **The SA-10 reaches farther low than the plan assumes:** `lib/sam_reach.lua` gives it 40 km low (85 % of that as the kill zone). It fired from 45–49 km at ~2,800 ft (~2,300 ft above the ground). The 00:57 run had the Kittilä SA-10 firing at 46 km at ~3,000 ft too. So a 46 km launch point against an SA-10 is inside its envelope from ~2,000 ft above the ground up.
3. **The SA-10's radar not on the RWR list:** either the `getDetectedTargets(RWR)` list doesn't hold a radar the AI only "hears" while it is locked, or the SA-10's radars really didn't register. If the AI can't see the SA-10 on its RWR, neither the `EngageGroup` nor the `AttackGroup` can fire a HARM at it, whatever the altitude. Worth a second look at `RADAR_WARNING` lines against other sites in this run.

**Proposed (decide with John):**
- Climb before the launch point, not across the leg to it: put the pop-up altitude on the pop-up waypoint itself (the AI then climbs on the low leg before it), or a climb waypoint 2–3 km after the pop-up at full pop-up altitude.
- Against an SA-10 (and the Patriot, 50 km at 8,300 ft in the 00:57 run), a launch point farther out or the low run-in to a closer point and a shorter, steeper pop-up. Your call on which way: real SEAD pilots time the pop to give the site as little look as possible.
- Find out whether the AI's RWR shows an SA-10 at all: a test mission with one AI F-16 with HARMs flying at an SA-10 at 8,000 ft from 60 km, logging `getDetectedTargets(RWR)` every 5 s.
- The wingman 5 min behind its lead (taxi queue at Kirkenes) is DCS's; noted only because the lead burned fuel circling low.

**17:15 run, with the pop-up top** (`event_logs\2026-10-02_171553.log`; grep `MSN2024_SEAD`, `SAM_SODA_SA10_1`): **the first full salvo since bug 36.** MSN2024 (2× F/A-18C, a player's AI SEAD from Rovaniemi) on the Sodankyla SA-10:
- Pop-up 04:12:55 at 1,548 ft; `TOP` reached 04:13:10 at 3,682 ft; launch point 04:13:17 at 3,779 ft. So DCS still counts both waypoints reached early and the jets are at about half the pop-up altitude at the launch point, but this time they kept climbing: the first HARMs left 22 s later at 8,907 ft.
- **8 HARMs from 39–47 km at 6,100–8,900 ft** at the SA-10's 40B6M tracking radar, 40B6MD and 64H6E search radars. MSN2024_SEAD_1 fired its 4 in 9 s (04:13:39–04:13:48); MSN2024_SEAD_2 spread 3 over a minute (04:14:04, 04:14:58, 04:15:04, from 44 down to 39 km) and was killed by the SA-10 at 04:15:27 with its 4th aboard. The SA-10 fired ~11 SA5B55 at the HARMs from 13–27 km, and the Pantsir escort more. Results: see below once in.
- **`RADAR_WARNING` at the launch point again said "not seen"** (04:13:17), yet the SA-10 fired at the flight 20 s later and the HARMs went at its radars. So the line is only a snapshot: the SA-10's radars weren't on the flight yet at the launch point. Suspect 3 above (the AI can't see an SA-10 at all) looks wrong; the 16:50 F-16s were simply killed before the SA-10's radar showed or before they could shoot.
- **New, not yet a bug (decide with John): the go cold waits for the whole flight.** The lead was empty 04:13:48, but the flight stayed on the attack while the wingman fired one HARM at a time for another 76 s inside the SA-10's envelope, which killed it. The `go cold` came only when the wingman died (04:15:29, "every anti-radiation missile fired"). A flight is one DCS group, so the controller can't send one jet home alone. Option: once one jet's missiles are gone, give the rest `salvo_time_s` (e.g. 20 s) and then go cold with whatever is left. **17:48 run (`event_logs\2026-10-02_174852.log`): it works.** MSN2024 (2× F-16) on the Sodankyla SA-10 reached `TOP` at 7,404 ft and fired all 8 HARMs within 13 s from 45–48 km at 6,500–8,240 ft; go cold at once. The SA-10 fired 6 interceptors at them, and at 04:14:29 the HARMs hit: **64H6E search radar and 40B6M tracking radar destroyed** (`TARGET … 2 of 3 critical`), the command post, the 40B6MD search radar and two launchers hit. Red's MSN7023 fired all 8 Kh-31P at the Rovaniemi SA-10 within 24 s from 43–49 km at 1,500–3,300 ft; that SA-10 fired 12 interceptors and nothing got through. Both F-16s were lost after the shot (the SA-10, and a base Tor during a fight: bug 41). Move to `closed.md` once John agrees. **Then built 2026-10-02, not flown (John agreed):** the "fire at first ping" `EngageGroup` moved from the pop-up waypoint to the pop-up top, so the Su-34s fire from altitude like the F-16s, not at 1,500–3,300 ft on the way up (0 of 24 Kh-31Ps through against SA-10s and Patriots so far).

**Built 2026-10-02, not flown (John agreed):** `salvo_time_s` 20; `CONTROL … go cold: salvo over: <jet> fired its last 20 s ago, n anti-radiation missiles left aboard`.

---

## 41. The controller's kill zones don't know the base-defense Tors and Pantsirs

**Status:** fix built 2026-10-02, not flown (John agreed after the behaviour was laid out; copied to DCS). `SamReach.baseDefenses` lists the enemy base-defense radar SAMs (`AIR_ROUTING.base_defense_roles`) with their longest unit's reach, as the planner sizes them; `AssessFlightSituations.enemyKillZone` and the scrambles' `enemyKillZone` check them after the SAM sites, at 85 % of that reach at any height, live groups only, and the `except` sets (route threats, a SEAD flight's own target) apply. So the fight's break-off, the go cold, the leash, the scrambles' "under enemy SAM cover" and the intercept point's 10 km margin all see them. Expected: fewer jets lost chasing or fighting into an airfield's Tor or Pantsir; a few bandits and raids escape there; slightly fewer scrambles. Checked in a luae harness. Found 2026-10-02, 17:48 run, watched by Claude.

**Seen:** `event_logs\2026-10-02_174852.log`; grep `MSN2024_SEAD_1`, `DEF_VUOJ_radar_missile_launchers_1`. After its salvo (which killed the Sodankyla SA-10's search and tracking radars, bug 40), MSN2024_SEAD_1 (F-16C) took the Red SEAD Su-34s that came hot at it (`defend` 04:12:54, 31 km, allowed: its HARMs were gone). The fight took it to 8,800–12,700 ft and east toward Vuojarvi. 04:13:56 the Vuojarvi base Tor M2 (`DEF_VUOJ_radar_missile_launchers_1_1`) fired at it from 13 km; 04:13:59 `back on way home: breaking off: inside the kill zone of SAM_SODA_SA10_1`; 04:14:14 destroyed by the Tor.

**Cause:** `AssessFlightSituations.enemyKillZone` walks only `plan.sam_sites`. The base-defense `radar_missile_launchers` groups (Tor M2, Pantsir; Blue's Roland / Tor) aren't in it, though the planner's routing keeps clear of them (`lib/threat_routing.lua`: + 5 km) and the radar picture counts them as sensors. So no controller rule sees them: the fight's break-off, the go cold's "inside another site's kill zone", the leash and the scrambles' "under enemy SAM cover". A fight or a chase can run straight into a defended base's Tor.

**Proposed fix (decide with John):** `enemyKillZone` also walks the live base-defense `radar_missile_launchers` groups of the other coalition, with their reach from `lib/sam_reach.lua` (the planner already has them: full reach, no low figure; ~12–20 km), so every rule above sees them. Log names them by group (`DEF_VUOJ_radar_missile_launchers_1`).

---

## 43. Kill zones still counted a SAM site whose radars were dead

**Status:** fix built 2026-10-04, not flown (John agreed; copied to DCS; checked in a luae harness). Found in the AI-only run `event_logs\2026-10-03_141509.log` (69 min).

**Seen:** both Kittila Patriot tracking radars were destroyed at 04:31:50 (MSN7023_SEAD_AGAIN). After that, MSN7035_DEAD broke off 4 fights in 5 s each "inside the kill zone of SAM_KITT_Patriot_1" (04:49-04:56), and Red refused scrambles at 05:04 and 05:06 "under enemy SAM cover" of the same Patriot. The launch gate had already launched MSN7035 *because* the Patriot was out of the fight.

**Fix:** the controller's and the scrambles' kill zones skip a site out of the fight, by the gate's own test (`DecideLaunches.outOfTheFight`: its radars destroyed to its success fraction). That covers the fight's break-off, the leash, the scrambles' "under enemy SAM cover" and the intercept point. **SEAD flights keep counting every live site** (John: don't change SEAD attack behavior): their go cold and their fight's break-off pass `countSilenced`.

---

## 44. A fight was timed out in the middle of the missile exchange

**Status:** fix built 2026-10-04, not flown (copied to DCS; harness-checked).

**Seen:** same run; both SEAD duels ended `back on way home: 3 min on …, time is up` the moment the missiles were in the air (04:20:56, 04:36:54), and the jets were hit 1-33 s later. A defend called at 80-95 km and closing takes about `max_engage_s` (3 min) to reach shot range.

**Fix:** time is up only when no air-to-air missile of the flight is still flying (the controller keeps each one the flight fires, from `S_EVENT_SHOT`) and it hasn't been fired upon in the last `shot_memory_s` (30 s).

---

## 45. SEAD flights fought each other after their salvoes

**Status:** fix built 2026-10-04, not flown (John: option (a); copied to DCS; harness-checked). The SEAD attack itself is unchanged.

**Seen:** same run. 12 of the 15 losses were air-to-air, 10 of them SEAD jets fighting after their salvoes. Blue's rotation (Rovaniemi → the Vuojarvi SA-10) and Red's (Vuojarvi → the Kittila Patriot) fly the same corridor head-on, on the same clock (both spawn at 04:02, the retries around 04:30); after the salvo each committed at 72-99 km, then defend / break off / defend. MSN2026 ↔ MSN7023: all 4 jets lost; MSN2026_AGAIN ↔ MSN7023_AGAIN: 3; MSN2028_AGAIN ↔ MSN7034_AGAIN: 3. MSN2028_AGAIN_2 committed on a MiG-31 with 1 radar missile aboard; the fight climbed it into the Koshka Yavr SA-11.

**Fix:** a SEAD flight whose salvo is away commits only when fired upon, or to a bandit hot inside `sead_commit_km` (25); otherwise `CONTROL … press on: bandit …; salvo away, staying on its way home`, once per bandit. Before the salvo nothing changed.

**Not done (option (b)):** offsetting the two rotations' start times.

---

## 46. A SEAD site that survived both tries blocked a coalition's attacks for the rest of the run

**Status:** fix built 2026-10-04, not flown (copied to DCS; harness-checked). Also the "come back later" half of bug 35.

**Seen:** same run. Every Blue attack mission (MSN2037, 2038, 2039, 2040, 2042) waited on `SAM_VUOJ_SA10_1`. After MSN2026 and MSN2026_SEAD_AGAIN left 1 of its 3 radars dead (it needs 2), MSN2037 was cancelled at 04:44:59 and the rest would follow; the rotation never came back to it. The Koshka Yavr SA-10 did the same to MSN2029 and MSN2030 (cancelled 04:49:56).

**Fix:** a rotation site still in the fight once its SEAD flight's second try is down comes back into the rotation once more, `AIR_PACKAGE.come_back_after_s` (60 min) later, as `<id>_LATER` (the same plan flown again: the plan is fixed, so same base and route), ahead of the rotation's next flight, and only if it would be back before the window ends. Flights waiting on the site wait for it instead of being cancelled; the rotation goes on past a rotation flight that waits for it. After a third failed try they're cancelled ("after three SEAD flights"). Lines: `CONTROL … come back: … it comes back into the rotation at 05:51`, `retry: … comes back as …_LATER, the rotation's next flight`, `wait: waiting for <site>'s SEAD flight to come back (…_LATER, at 05:51)`.

**To check in the next run:** grep `come back`, `_LATER`. Note the SA-10's own reload (plan.md, *DCS facts*): 2 h, so after 60 min a site may be partly rearmed.

---

## 50. The radar picture's first-detection ranges are far beyond the 250 km the coverage call assumes

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

**Status:** fix built 2026-10-05, not flown (John: "a dumb retry after 5 minutes and look at the target state again"; copied to DCS).

**Seen:** `event_logs\2026-10-05_103126.log`, grep `MSN2029_SEAD`. MSN2029's last jet died at 04:45:25; `MSN2029_SEAD_AGAIN` spawned at 04:45:26. MSN2029's HARMs destroyed the SA-11's search radar (its only critical radar) at 04:46:17, so the site was out of the fight 51 s later, but the copy flew the whole sortie and went home `no shot`. Every retry this run came 1 s after the flight before it was down (MSN2026, MSN7023).

**Fix:** a SEAD flight done (sent home, landed or lost) with its site still in the fight is flown again no sooner than `AIR_PACKAGE.retry_after_s` (300) after it came off its task, and the site is looked at again first (`ControlAirFlights.offTaskSince`; `decide_launches.lua`: the rotation's owed retry and the gate's retry). The come-back decision after a second try waits the same 5 min. New line: `CONTROL … wait: SAM_KOSH_SA11_2 still in the fight after MSN2029_SEAD; looking at it again at 04:50 before a second try`. Check: that line, then either a `retry` or the rotation's next flight launching because the site is out.

---

## 58. Red SEAD flights went cold 10 s into their salvo, the lead with all 4 aboard

**Status:** fix built 2026-10-05, not flown (copied to DCS; checked with stubbed situations).

**Seen:** same log, grep `MSN7024_SEAD`. Both tries on the Kirkenes IRIS-T: the wingman fired 1 Kh-31P at 49 km, then 3 at 43 km; 10 s later `go cold: 5 km past its launch point toward SAM_KIRK_IRISTSLM_1` (and `6 km past` on the retry). The lead never fired either time.

**Cause:** that site's flights have no press-on point (no point on the track clear of the other sites), so the "pressed too far" limit is the launch point + `press_km` (5). After the pop-up the `EngageGroup` flies the Su-34s on toward the site, past that limit in about 20 s.

**Fix:** pressing past the limit doesn't send the flight home within `AIR_CONTROL.suppression.press_after_shot_s` (30) of any anti-radiation missile it fires; `salvo over` (20 s after one jet is empty) still ends it. Whether the lead then fires is up to the DCS AI (only one jet fired in several salvoes on both sides: the optional Wild Weasel item).

---

## 59. Kuusamo scrambled six times at Blue's E-3A

**Status:** fix built 2026-10-05, not flown (John: "an AWAC that vulnerable would be scrambled and shot down, it's probably too close to the front. fix it."; copied to DCS).

**Seen:** same log, grep `MSN2001_AEW`. MSN7901, 7903, 7905, 7906, 7907, 7908, every ~17 min: "scramble: … after MSN2001_AEW (E-3A), enemy airspace, 14 min from SAM_ALAK_SA6_1; intercept 60 km out", each stood down on the ramp 3 min later, "back over its own airspace, heading away". The E-3A's race-track (centre 191 km from Alakurtti, 210 km from Koshka Yavr and Luostari, 254 km from Kuusamo) had a leg pointing at Alakurtti.

**Cause:** the orbit is chosen as far forward as the standoffs allow (`early_warning_near_best`), and the standoffs (150 km from every enemy fighter base, 80 km from the contested airspace) were checked at the race-track's centre only.

**Fix:** `early_warning_fighter_base_km` 250, `early_warning_front_km` 120, held for the centre and both ends (`orbitCandidates`). On this roll's airspace (a rough check, not the planner): Blue still has ~1,190 orbit cells, the best seeing ~35 % of the contested airspace within the 250 km planning reach (was ~46 %), so Blue's second E-3A (`early_warning_max` 2) is now more likely to be planned; Red's A-50 ~32 % (was ~58 %). Not checked: whether Red still scrambles at it (its trigger is "inbound on an asset within 15 min"). Check `dcs.log` "sees n % of the fight" and grep `after MSN2001_AEW` in the next run.

---

## 60. A MiG-31 patrol fought on low on fuel and went down with empty tanks

**Status:** fix built 2026-10-05, not flown (John: "add a fuel watch to the controller"; copied to DCS; checked with stubbed situations).

**Seen:** same log, grep `MSN7016_CAP`. About 1 % a minute on station; 19 % at 04:43, when it took on MSN2029_SEAD (killed both Hornets, R-33 and R-40R down to 1,850 ft); 9 % at 04:45, 1 % from 04:50, `DESTROYED … no killer recorded, 1,847 ft` at 04:54. DCS's own return at bingo didn't bring it home.

**Fix:** a new directive `fuel` for patrols, scrambles and the AWACS (`AIR_CONTROL.fuel`): home (`CONTROL … bingo: bingo fuel: MSN7016_CAP at 16 %, 100 km from Koshka Yavr (needs 17 %)`) when a jet's fuel is down to `reserve_fraction` (0.10) + km straight home / its combat radius × `home_fraction_per_radius` (0.5); the jet with the least to spare decides for the flight. A flight already going home that is fighting breaks the fight off (`back on way home: bingo fuel …`). Not attack flights for now: they are planned out to their combat radius, so the same rule could turn a strike back short of its target.

---

## 56. SA-10 rings missing from the F-16's HSD, inconsistently

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

**Status:** fix built 2026-10-06, not flown (copied to DCS; checked in a luae harness with stubbed DCS).

**Seen:** Viper 1 (Ivalo), Viper 5 and Viper 6 (Alakurtti) and Hornet 1 (Ivalo) said "on station" 1–5 s after "airborne": their race-tracks lie within 20 km of their bases, and the watcher counted a patrol within `on_station_km` (20) of its race-track as on station. The controller had the same test for a handover: `handover: relieved by MSN2017_CAP, on station (3 km from the race-track)` 16 s after Viper 6's takeoff, so Viper 5 was sent home at once. The other way round, Viper 5 never said off station or checked out: that needed it 40 km from its station, and it landed 2 km from it.

**Fix:**
- A patrol says "on station" at its station waypoint (the waypoint's script command), not by distance.
- It has left its station once the controller sends it home (handover, bingo, leash home, go cold, leave, land: a listener of the controller's decisions) or at its off-station waypoint (its orbit over); then "off station" and the check-out come when it is seen heading home (pointing at its base and closing), however close its station is to its base. An order the AI ignores still gets no call.
- The controller counts a relief as on station only once it has reached its station waypoint (`w.on_station_at`; a patrol spawned in the air on its station counts from its spawn), and within `handover.on_station_km` as before.

**Check:** `RADIO_CALL.*on_station` after the flight's `WAYPOINT … on station` line, never seconds after `airborne`; `handover:` only after the relief's on-station waypoint; an `off_target` / `check_out` for every relieved patrol.

## 63. Darkstar told Weasel 4 "back to your tasking", then "RTB" 5 s later

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

**Status:** fix built 2026-10-06, not flown. Ragin 3 (MSN2903_SCRAM), leashed home without a fight, said "Ragin three, off target, RTB". Interceptors now have their own condition (`intercept`) in `pilot_phrases.json`: "terminating" / "off intercept", then RTB.

## 65. A scramble's check-in spoke the DCS type name

**Status:** fix built 2026-10-06, not flown. "Darkstar, Ragin three, airborne Alakurtti, intercept on Su-34 at Ivalo": the watcher passed the raid's DCS type as a place-style target. Now the raid's type goes as `target_type`, worded by the helper like the Fox and splash calls (NATO name or designation): "intercept on the Fullback"; "scramble, intercept" when the type isn't known.

## 66. The flight-call listener failed on destroyed buildings

**Status:** fix built 2026-10-06, not flown. `dcs.log`: `flight calls: event 8 failed: … announce_flight_activity.lua:240: attempt to index local 'unitName' (a number value)`, 3×, from John's GBU-38s at Kalevala: a map object's name is a number. `nameOf` in the watcher now returns text names only.

## 67. "Departing" was said after the jet had taken off

**Status:** fix built 2026-10-06, not flown (luae harness: taxi, a runway crossing and a parallel taxiway not counted, lined up counted once, no second call at takeoff). John: backwards for airfield traffic.

**Fix:** the airfield tracker (every 3 s) sees a taxiing jet inside a runway's strip (`lineup_margin_m` 15 beyond its edges and ends; the runways from `Gather`) with its nose within `lineup_aligned_deg` (20) of one of its directions: lined up. New event word `LINE_UP` ("lined up on runway 21 at Ivalo, 2 kt"), and the departing call then, on the runway it is on. At takeoff only if the line-up wasn't seen. A new phrase: "lining up runway two one for departure".

## 68. A lone wingman ignored its landing orders and flew on until the mission ended

**Status:** fix built 2026-10-06, not flown (luae harness: removed 8 min after its last order while flying away; a jet closing on its base after two orders never removed).

**Seen:** `MSN7024_SEAD_2` (Su-34), its lead shot down: heading 050 at 26,000 ft for 13 min, straight past Koshka Yavr; `land: … lost after its landing` at 05:02:04 and 05:04:04 (`max_orders` 2), still flying at mission end. The orphan removal needed a landing in its flight, and there was none.

**Fix:** after its last landing order, a jet still getting farther from its base (`away_km` past its closest since that order) `orphan_remove_after_s` (8 min) later is removed and counted as landed: `>>orphan<< removed: by the controller: MSN7024_SEAD_2 171 km from Koshka Yavr (it was 66 km away) still flying away 8 min after its last landing order; counted as landed (…)`.

## 69. The F-16's COMM 1 / COMM 2 volume knobs did nothing

**Status:** open; logging built 2026-10-06 to find out why (the code reads the same knobs as SRS, arguments 430 / 431, and the player applies them: both checked offline, the export script in luae with a stubbed cockpit, the player with UDP readings).

**Seen:** John, 00:16 run: turning the COMM 1 / COMM 2 knobs didn't change the calls' volume. `dcs.log` shows our export script loaded (`KOLA-RADIOS … sending the jet's radios`), but nothing recorded whether a reading ever reached the radio player: it printed to its window only. With no fresh reading it plays every call at full volume, which would look exactly like this.

**Built:** the radio player writes everything it says to `radio_calls\radio_player.log` (rewritten at each start, git-ignored): the jet's radios as first heard and at every change (volume in 0.05 steps), "no word from the jet's radios … every call plays at full volume" when the readings stop, and each call heard (on which radio, at what volume), not heard (why) or dropped. The export script writes `KOLA-RADIOS … first reading of the jet's radios: {…}` to `dcs.log` once, and the first failure to read or send.

**Check after the next flight:** `dcs.log` for `first reading`; `radio_player.log` for `hearing the jet's radios`, the volume lines as the knobs turn, and `at volume` on each call.

**2026-10-06 17:47 run** (`event_logs\2026-10-06_174721.log`): the readings arrive: `dcs.log` `first reading of the jet's radios` (UHF 305.000 and VHF 127.000, both off, the cold jet), and `radio_player.log` logs each change, John's retuning to 262.000 / 140.000, and the UHF volume going down 1.00 → 0.00 in 0.05 steps and back up (bug 72). Every call heard was played `at volume 1.00`, so whether a call at a lower knob setting sounds quieter wasn't heard.

## 70. Both jet-down calls went unheard

**Status:** fix built 2026-10-06, not flown; the cause is likely, not proven (no player log in that run).

**Seen:** John heard no "jet down". Both were sent (`speak_mission_calls.log` 00:34:56 "Weasel one, Weasel one one's hit", 01:10:57 "Weasel four one, lost Weasel four two"), each 8 s after a 4–5 group Darkstar picture (~25 s of audio) started. Calls never overlap, so each waited behind the picture, and `jet_down` expired after 20 s.

**Fix:** `jet_down` lives 45 s and `splash` 40 s (`RADIO_CALLS.kinds`), longer than a picture. Fox / Magnum / defending stay at 8 s (no news that late). Bug 69's player log shows each `dropped` from now on. If it still happens: a combat call could cut in on a routine call playing on the other radio, or the pictures get shorter (roadmap item 7 step 12, "a short summary when nothing changed"), which would help more than longer lives.

## 71. Hits and bomb impacts said nothing about where a weapon landed or how much damage it did

**Status:** built 2026-10-06, not flown (luae harness with stubbed DCS). John, after the 00:16 run: his GBU-38s at Kalevala were logged as `HIT` on the Mi-8 static and two ZU-23s, twice, but nothing said how close they fell or how hurt the Mi-8 was (he thought he saw 8 % damage), so a miss and a weak hit couldn't be told apart.

**Built:**
- `IMPACT` (new, `consumers/track_weapon_impacts.lua`): every bomb and air-to-ground missile from an aircraft is followed (every 0.1 s) to where it comes down; one line with its grid reference (MGRS, as the F10 map), the objects within 150 m (distance and direction from each, life before → after, or destroyed), or the nearest one when none is that close; "gone in the air … (shot down, or burst)" when it vanished more than 50 m up. The life before is read on its way down (DCS applies the damage in the frame the weapon goes). Settings `EVENT_LOG.impact_*`.
- `HIT` lines end with the life the target has left a second after the hit (`life now 92 %`, or `destroyed`).

## 72. The radio went silent for the last ~5 minutes, though the calls were being sent

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
