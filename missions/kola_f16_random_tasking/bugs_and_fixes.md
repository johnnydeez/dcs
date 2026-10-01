# Kola F-16 Random Tasking: bugs and fixes

Bugs found in runs, with what was seen and the fix proposed, to come back to. Each entry says where the evidence is. When one is fixed, mark it fixed with the date, and put any as-built facts in `plan.md`.

---

## 1. Scrambles accept intercepts they can never make in time

**Status:** open (found 2026-09-30).

**Seen:** event log `event_logs\2026-09-30_201105.log`; grep `MSN5905`, `MSN5906`.
- **MSN5905_SCRAM:** a Su-27 from Kuusamo sent after MSN2024_SEAD + MSN2025_SEAD, which were "8 min from Kirkenes", with the intercept **629 km out**. That's ~30 min at dash speed, and far more afterburner than a fighter has fuel for.
- **MSN5906_SCRAM:** a Su-30 from Alakurtti, with the intercept **462 km out**.
- **Blue too:** MSN2901_SCRAM (F-15C from Ivalo) at **205 km**, sent after Su-34s 9 min from their target; it was airborne at 08:19, and the raid was dead by 08:22. MSN2905_SCRAM (F-16C from Rovaniemi) at **226 km**.
- **Why Kuusamo:** it was the only alert base with a jet ready. Koshka Yavr's last jet had gone to MSN5904 in the same round, and Alakurtti was on cooldown. That part is by the rules; it's also made worse by bug 2.
- **Seen again** (`event_logs\2026-09-30_213757.log`; grep `MSN2906`, `MSN2909`, `MSN2910`): three Blue F/A-18 scrambles from Hosio and Rovaniemi at Red patrols (MSN5009_CAP, MSN5010_CAP), with intercepts **534, 424 and 420 km out**. All pass the F/A-18's 550 km `combat_radius_km`. The patrol's race-track leg pointed at Banak, so the raid was pushed far ahead along it. The walk back from the base stops only at enemy airspace, and the whole way lay over Blue's own airspace.

**Cause** (`consumers/run_scrambles.lua`):
- `interceptPoint` pushes the raid ahead along its heading by the scramble's flight time. A raid flying away from the base becomes a long tail chase.
- `pickBase` then checks only three things:
  - the leg is at least `scramble_min_leg_km`;
  - it's within the type's `combat_radius_km` (Su-27: 700 km);
  - there's a free ramp spot.
- Nothing asks whether the scramble arrives before the raid reaches the asset it threatens.

**Proposed fix:**
- Refuse the pick (`NO_SCRAMBLE`, e.g. "can't reach the raid before it reaches Kirkenes") when the scramble's time to the intercept point, including its reaction delay and taxi, is later than the raid's `threat_minutes` plus a margin.
- Possibly also a maximum scramble leg (`AIR_DEFENSE.scramble_max_leg_km`, ~250–300 km).
- **Decide with John:** the time test only, or also the maximum leg, and the numbers.

---

## 2. A jet stood down on the ramp never returns to alert

**Status:** open (found 2026-09-30).

**Seen:** same log; grep `stood down on the ramp` and the `alert jet(s) ready` counts in the `SCRAMBLE` lines.
- **Jets lost without flying:** MSN5901 and MSN5904 (Koshka Yavr) and MSN5902 (Kuusamo) were stood down on the ramp and never came back. Koshka Yavr went from 3 jets to 1, and Kuusamo from 3 to 2, with none of them flying.
- **Two of the three were raised against MSN2009_CAP,** a Blue F-15C patrol on its race-track:
  1. one leg reads as inbound for two picture rounds, so Red scrambles;
  2. the jet spawns;
  3. the patrol turns, reads as "heading away", and the jet is stood down.

  John agreed a scramble at a patrol that looks like a raid is fine; with this bug, each such cycle costs a real alert jet.
- **Seen again** (`event_logs\2026-09-30_213757.log`; the `alert jet(s) ready` counts): MSN2904 (Kittila) and MSN2905 (Rovaniemi) were stood down on the ramp and never came back. Kittila was at "0 ready, 1 turning around" by MSN2907, and Rovaniemi the same by MSN2908. The jets that landed did come back (`ALERT` lines), so only the stand-down path is broken.

**Cause:** the leash's stand-down (`consumers/enforce_air_behaviour_rules.lua`) deletes the group with `g:destroy()`. An alert jet only goes back on alert from `RunScrambles`' `S_EVENT_LAND` handler, and a deleted jet never lands. Only a stand-down *before launch* (in `launch`, the `refund` path) gives the jet back.

**Proposed fix:**
- A jet stood down on the ramp goes back on alert at its base at once, or after a short delay (the crew climbing back out), the same way a stand-down before launch does.
- For example, `EnforceAirBehaviourRules` tells `RunScrambles` (a callback, or `RunScrambles.stoodDown(id)`), which moves the jet from `st.flights` back to `ready`.
- The `LEASH` line can then show the base's ready jets.

---

## 3. Scrambles keep firing at patrols on their race-tracks

**Status:** open (found 2026-09-30).

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

**Status:** open (found 2026-09-30).

**Seen:** same log; grep `MSN5023_DEAD`.
- MSN5023_DEAD, 2× Su-34 from Banak on `SAM_ENON_Roland_1`, carried Kh-29T, a TV-guided missile fired from about 9 km. The Roland reaches about 8 km.
- Both fired from 9 km at ~12,800 ft, and both were shot down by the Roland (08:21–08:22).
- The Roland lost one launcher.

**Cause:** DEAD loadouts are chosen per aircraft type (`aircraft_loadout_choices.json`), and the attack altitude is realistic for the weapon. Nothing compares the weapon's release range with the target's ring.

**Proposed fix:**
- Planning: only pick a DEAD target whose ring is shorter than the flight's weapon range, with a margin; or pick the loadout by target.
- Ties in with the *Standoff attacks* item in the `plan.md` backlog: which weapons the DCS AI really releases at range.

---

## 5. Event log: small fixes

**Status:** open (found 2026-09-30). All in `consumers/write_event_log.lua`, except (d).

**Seen:** same log.
- **(a) A dead shooter shows as `? (?)`.**
  - HARMs from MSN2028_SEAD hit `SAM_KUUS_SA11_2` at 08:23:51, after both Hornets had died: "hit by AGM_88 from ? (?)".
  - The MiG-31 MSN5009_CAP_1 was "DESTROYED … by ? (?) with AIM_120C" at 08:39:13: the F-16 that fired had died first.
  - Because of that, the end summary files the MiG-31 under "other ground units" instead of "aircraft".
  - **Fix:** remember each weapon's launcher (name, type, whether it's an aircraft) at `SHOT`, keyed by the weapon; or ask `Weapon:getLauncher()`. Use that when the initiator can't answer any more.
- **(b) Shots at missiles read badly:** "S-300PS 5P85D ln fired SA5B55 at  (AGM_88), 26 km". That's the SA-10 shooting at HARMs.
  - **Fix:** a weapon target reads "at an incoming AGM_88".
- **(c) Secondary explosions read like weapons:** "Osa 9A33 ln hit by Dog Ear radar from SAM_LUOS_SA8_1_1 (Dog Ear radar)"; the same at the Roland and SA-11 sites. The "weapon" is an exploding unit.
  - **Fix:** when the weapon object is a unit, write "caught in the explosion of SAM_LUOS_SA8_1_1 (Dog Ear radar)".
- **(d) The end summary's status is wrong for scrambles stood down on the ramp:** MSN5901, MSN5902, MSN5904 and MSN2904 show "airborne" but never flew.
  - **Fix:** in `ScheduleAirTaskingOrders.statusOf`, a flight that was removed without taking off reads "stood down" (the leash can tell the scheduler).
- **(e) `PARACHUTE` lines don't say whose pilot it was:** the subject is the generic parachute object (`pilot_su27_parachute`, also used for Su-34 pilots).
  - **Fix:** at `S_EVENT_EJECTION`, remember the ejected pilot object (`e.target`, if this DCS version gives it) against the aircraft; name that aircraft on landing.
- **(f) `ABORTED` repeats:** DCS fires "AI abort mission" on hits, sometimes twice in the same second for one flight.
  - **Fix:** fold per flight, like hits.
- **(g) No `GUNS` line all run:** either no AAA or gun came into range, or DCS doesn't send `S_EVENT_SHOOTING_START` for AI ground units.
  - **Next:** check in a run where jets fly low over a defended base (or a quick test mission). Nothing to fix until then.
  - Still no `GUNS` line in the second run (`2026-09-30_213757.log`), but nobody flew low over a defended base there either.

**Seen again in `event_logs\2026-09-30_213757.log`:**
- (a): "SAM_SODA_SA11_1_3 … by ? (?) with AGM_88" (11:23:37), after MSN2024_SEAD_2 had died.
- (b): the Rovaniemi SA-10, IRIS-T and NASAMS firing at Kh-31Ps: "fired SA5B55 at  (X_31P)".
- (c): "NASAMS_Command_Post hit by NASAMS_Radar_MPQ64F1 from SAM_ROVA_NASAMS_1_2", and the same at the IRIS-T site.
- (d): MSN2904, MSN2905, MSN2909 and MSN2910 show "airborne" in the end summary; all four were stood down on the ramp.
- (e): every Red parachute is `pilot_su27_parachute`, and the Blue one is `pilot_f15_parachute`.
- (f): 23 `ABORTED` lines, each at a hit or a death, usually in pairs. They add nothing a `HIT` or `DESTROYED` line doesn't already say. **Fix:** fold, or drop the event entirely.

**New in the same log:**
- **(h) Hits with no weapon and no shooter read "hit by gun from unknown":**
  - at the player's GBU-31 impacts on Vuojärvi: "MiG-29S hit by gun (2 hits) from unknown" (11:40:52, 11:46:41);
  - at a FAB-500 impact on the Banak command post: "GeneratorF hit by gun from unknown" (11:40:53).
  
  These are blast or secondary-explosion hits for which DCS gives neither weapon nor initiator. `weaponName` falls back to "gun" and `who` to "unknown". **Fix:** with no weapon and no initiator, write "damaged by a nearby explosion".
- **(i) Fuel over 100 %:** the player's `POSITION` lines read "fuel 183 %" after takeoff. `Unit:getFuel()` counts external tanks on top of internal fuel. **Fix:** write it as a fraction of internal fuel with a note ("fuel 183 % (with tanks)"), or convert to pounds or kilograms with the profile's `fuel_max`.
- **(j) The nearest-ring column counts dead SAM sites:** from 11:23 the player's lines put them "33 km inside SAM_SODA_SA11_1", but by then that site had lost its search radar and all four launchers. **Fix:** skip a site once no unit that can fire (or no radar) is left, in the ring column and in the `WAYPOINT` lines. The leash's kill-zone test already uses "live" rings; use the same test here.
- **(k) The player isn't linked to their tasking:** `PLAYER_IN` reads "New callsign in a F-16C_50 at Kallax", and nothing ties it to MSN2023_OCA. **Fix:** once a player takes off, name the human tasking that starts from that base (if only one does), e.g. "flying MSN2023_OCA?". Goes with *Assignment and completion tracking* in the `plan.md` backlog.
- **(l) Kills of static objects:** moved to bug 9 (a player-facing popup, not an event-log fix).

---

## 6. Su-24M SEAD flights spawn with no weapons

**Status:** open (found 2026-09-30).

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

## 7. An alert base can have no ramp spot for its alert jets

**Status:** open (found 2026-09-30).

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN5901`: "STOOD_DOWN MSN5901_SCRAM before launch: no free ramp spot at Ivalo" (11:45:39). That was Red's only scramble of the run to get as far as launching.

**Cause:** `planAlertPosture` picks alert bases by runway and parking fit, but nothing reserves ramp spots for the alert jets. At launch, `freeSpot` looks for a free ramp spot, and patrol rotations spawning at the same base (MSN5010_CAP spawned at Ivalo at 11:45:12, 27 s earlier) or the parked-aircraft statics may hold them all.

**Proposed fix:** reserve `alert_aircraft_per_base` ramp spots per alert base at planning time, like player slots: parked-aircraft statics and AI parking skip them, and scrambles use only those. If a base can't spare them, it isn't an alert base.

---

## 8. Scramble intercept points sit right at the kill-zone line

**Status:** open (found 2026-09-30).

**Seen:** `event_logs\2026-09-30_213757.log`, grep `MSN2902`: "WAYPOINT 2 of 3: intercept point … 7 km inside SAM_SODA_SA11_1" (11:15:45), then 19 s later "LEASH going home: inside the kill zone of SAM_SODA_SA11_1". The scramble was sent home the moment it reached the point it had been sent to.

**Cause:** `interceptPoint` walks out from the base in 5 km steps and keeps the last point outside enemy kill zones (85 % of a ring). The leash sends a jet home as soon as it's inside that same line. A point just outside the line, plus the AI's own intercept geometry, puts the jet over the line almost at once.

**Proposed fix:** keep the intercept point a margin outside the leash's line (e.g. an `AIR_DEFENSE.scramble_killzone_margin_km`, ~10–15 km); if that leaves no leg of `scramble_min_leg_km`, don't scramble.

---

## 9. The player never learns they destroyed static targets

**Status:** open (found 2026-09-30). John: we need an on-screen popup for these.

**Seen:** `event_logs\2026-09-30_213757.log`, grep `Aerial-1-2`. John's GBU-31s destroyed two of the three parked MiG-29s at Vuojärvi (`DESTROYED TGT_VUOJ_parked_aircraft_1_static_1` at 11:40:52, `_static_2` at 11:46:41, each followed by `TARGET MSN2023_OCA … n of 3 critical`). Neither kill showed in DCS's own kill list, so in the cockpit John thought the attack had failed.

**Cause:** parked aircraft, and many other fixed-target parts (buildings, parked vehicles), are DCS static objects (`coalition.addStaticObject`). DCS's kill messages and kill list don't show static objects the way they show units. The mission knows about each kill (`WriteEventLog` and the scheduler's `TARGET` line already catch it), but tells only the log.

**Proposed fix** (John, 2026-09-30: every spawned static object a human player destroys gets the message):
- **When:** a player destroys any static object the mission spawned (`plan.fixed_ground_targets.static_objects`, spawned by `SpawnStaticObjects`), whatever it belongs to. Map scenery (buildings that are part of the terrain) gets no popup. Units get none either, since DCS already shows those.
- **What:** a popup to that player's group (`trigger.action.outTextForGroup`, ~10–15 s) naming the object and the target it belongs to. For example: `Destroyed: Hummer (command post, Banak)`.
- **Tasking progress:** when the object is part of a human tasking's target (a mission with `flown_by = "human"`; its catalog target's `static_object_ids`), add the progress from the target catalog (`critical_names`, `success.critical_fraction`), as in the `TARGET` line. For example: `Destroyed: MiG-29S (parked aircraft, Vuojarvi): 2 of 3 critical for MSN2023_OCA`. When the success fraction is reached: `MSN2023_OCA target destroyed: success`.
- **Who killed it:** the kill event's initiator is the player's unit (`Unit:getPlayerName()`). If the initiator is gone (the player was killed or ejected before the bomb landed), use the launcher remembered at `SHOT` (as in 5 (a)).
- **Where:** the scheduler's target progress (`consumers/schedule_air_tasking_orders.lua`, which already writes the `TARGET` line) or the event log's kill handler (`consumers/write_event_log.lua`), calling a small player-message function in `consumers/brief_air_tasking.lua`, the module that already talks to players. The comms-menu wording rule applies to the text.
- Goes with *Assignment and completion tracking* in the `plan.md` backlog, and later with the objective tracking in *Design, not built yet*.

---

## 10. The target steerpoint carries the attack altitude, not the target's elevation

**Status:** open (found 2026-10-01, John).

**Seen:** the human tasking's `Steerpoints` list in the comms menu. The `TGT` steerpoint gives the planned attack altitude (e.g. 25,000 ft), not the ground elevation at the target. Entered like that, the F-16's steerpoint sits in the air above the target. Fire-and-forget weapons (JDAM, JSOW) need the exact spot on the ground, including its elevation. With a flight altitude on the steerpoint, John has to hunt for the target with the targeting pod when he gets there.

**Cause** (`consumers/brief_air_tasking.lua`, `steerpointText`): every steerpoint except takeoff and landing prints `feet(r.alt_m)`, the route's flight altitude. The frag's `TARGET` block already gives the elevation (`where()` → `land.getHeight`), but the steerpoint list doesn't, and a player types the steerpoint list into the jet.

**Proposed fix:**
- The `TGT` steerpoint prints the ground elevation at the target (`land.getHeight`), marked as elevation (e.g. `elev 420 ft`), not the attack altitude. The attack altitude can stay on the frag (or on the `IP` line).
- When the target has aim points (`m.attack.points`), list each one as its own steerpoint after `TGT`, each with its coordinates and elevation, so each weapon can be given its own spot.
- Check that the coordinates are precise enough for a JDAM (decimal minutes to 3 places is ~2 m, which is fine).
- Also for SEAD frags: the threats "YOURS to suppress" could get steerpoints with elevation too (decide with John).

---

## 11. Human taskings don't need egress or return steerpoints

**Status:** open (found 2026-10-01, John).

**Seen:** the human tasking's `Steerpoints` list continues past the target with `EGR` and the whole route home (the way in reversed, then `LAND`). John: a player can follow the path back out; the extra points only make more to type in.

**Cause** (`consumers/brief_air_tasking.lua`, `steerpointText`): it lists every point of `m.route`, which is planned the same way as an AI flight's (the way out reversed for the way home).

**Proposed fix:**
- The steerpoint list stops at the target (or after the aim points from bug 10), then gives only the landing base as the last steerpoint.
- For CAP taskings, stop after the station's two points (`CAP A`, `CAP B`), then the landing base.
- This replaces the *Steerpoints* item in the `plan.md` backlog ("a return leg that repeats many transit points could be shortened").
- The route itself stays in the plan (the map drawing and the frag's threat check use it); only the list the player types in gets shorter.

---

## 12. The steerpoint list leaves the screen before it's typed in

**Status:** open (found 2026-10-01, John).

**Seen:** `Comms menu > Other > Human taskings > <MSN> > Steerpoints`. The list disappears while John is still entering it into the F-16's computer, which takes several minutes.

**Cause** (`consumers/brief_air_tasking.lua`): every comms-menu text goes through `show()` with `MESSAGE_S` = 60 s, the frag and steerpoints included.

**Proposed fix:**
- The steerpoint list stays **5 minutes** (a `STEERPOINT_MESSAGE_S` 300) and the frag **3 minutes** (`FRAG_MESSAGE_S` 180) (John, 2026-10-01). Other menu texts keep 60 s.
- Add a `Hide text` entry to the comms menu. It clears the screen (a short empty message with `clearview`), so a long-lasting list isn't in the way once it's entered.
- Picking `Steerpoints` again shows it again from the start, as now.
