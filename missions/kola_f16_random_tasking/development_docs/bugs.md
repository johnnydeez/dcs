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

**Guard built 2026-10-02, not flown:** the ammo check 5 s after spawn (`logAmmo`) hands any jet with no weapon aboard (its gun aside), while its loadout lists weapon pylons, to the controller (`ControlAirFlights.unarmed`), which removes it on the ramp: `CONTROL … stand down: … carry no weapons (its loadout 'SEAD' lists 4 weapon pylons); removed on the ramp; the flight isn't flying` (or `the rest of the flight flies`). The `dcs.log` warning now reads `carries no weapons`. A package behind a removed SEAD flight sees its threats still in the fight, so the gate flies it once more (`_AGAIN`, likely unarmed again) and then cancels: the package doesn't go without its suppression.

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
