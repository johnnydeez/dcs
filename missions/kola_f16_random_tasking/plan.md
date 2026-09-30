# Kola F-16 Random Tasking — Plan

> **What this is:** the spec and build state of the Kola F-16C mission generator. When the mission loads, a script rolls the battlefield (who holds which airfield), fills it with ground defenses, SAM networks and targets, plans both coalitions' air war for a ~6-hour window, and briefs human players on their taskings.
>
> **Where to look:** *Where we are* (pick up here) → *Backlog* → *As built* (the spec, by stage) → *Design, not built yet* → *Architecture* → *Reference*. Features coming next, in John's order, are in **`roadmap.md`**. Session-by-session history (run logs, before/after numbers) was cut on 2026-09-30; it's in git (`notes/kola_f16_generator_plan.md` in commits up to `4c49af9`).
>
> **Paths** are relative to this mission folder (`missions/kola_f16_random_tasking/`) unless they say otherwise. Companion: the Syria mission (`missions/syria_a2g/notes.md`); no shared code.
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

---

## Where we are — pick up here  *(2026-09-30, end of session 11)*

**Status:** the whole pipeline runs in DCS and the mission is playable by one human player.
- **Stage 1:** territory roll, 37 airfields.
- **Stage 2:** base defenses.
- **Stage 3:** SAM networks (127 surveyed zones), fixed ground targets, and the target catalog.
- **Stage 4:** one Red supply convoy.
- **Airspace map:** own / contested / enemy, with regions and pockets.
- **Air tasking for both coalitions:** front-only strike, airfield strike and DEAD, with SEAD packages; front CAP stations with commit circles; one AWACS each.
- **Players:** F-16C dynamic-spawn slots, two human taskings per roll, frag and steerpoints in the comms menu.
- **Radar picture** (roadmap item 1, done 2026-09-30): each coalition's picture of the enemy aircraft its radars report (see *Radar picture* under *As built*).
- **Scrambles and the leash** (roadmap item 2, done 2026-09-30): one-ship scrambles at raids the radar picture shows, burning straight at them from a hot ramp spot; the first AI behaviour rule (the leash) brings them home; alert jets go back on alert 30 min after landing (see *Scrambles and the leash*).
- **Flight ids carry the mission type:** `MSN2025_DEAD`, `MSN2901_SCRAM` (see *Naming and ids*).

**Last DCS runs:**
- **Session 9, fourth run, ~2 h:** the air-denial rules held (John: "It looked good to me and like it followed our rules"). 0 patrol or AWACS track samples in enemy airspace or inside an enemy ring.
- **Session 10, 12:18 roll:** the human taskings, frags and steerpoints read well (John: "looking good").
- **Session 11, first radar picture + scramble run, ~48 min, watched (not flown):** everything designed showed up and nothing errored (details under *Radar picture* and *Scrambles and the leash*). John: MSN2901 and MSN5902 "did exactly what we wanted as a scramble". **Losses were high: 12 aircraft (Blue 4, Red 8)**, both Blue packages caught by Red fighters and both Red packages destroyed, mostly by aircraft that kept flying their route while engaged → roadmap item 4 (AI behaviour logic). Since then: alert jets return after landing, and flight ids carry the mission type; neither run in DCS yet.

**Next:** `roadmap.md`, in John's order: radar picture → scrambles → event log → AI behaviour logic → CAP visibility → AWACS calls (text) → cruise missiles → AI radio calls (LLM / cloud) → Skynet IADS → fog of war (last: the full map is needed while debugging); radar jamming, helicopters, fun callsigns and a player map of the threat picture are optional, at the end. Radar picture and scrambles are done for now; **next: the event log (item 3), then AI behaviour logic (item 4, a later session).** The backlog below holds everything else.

**Still to watch in runs:**
- **Lone F-15E crash:** an F-15E of a Banak DEAD crashed alone in Blue airspace ~30 min after bombing (1,237 ft, no hit recorded). An AI approach crash or fuel? Watch for a repeat.
- **Late bombers:** Red's Rovaniemi bombers dropped ~8 min after their TOT, after their SEAD had died, and hit nothing.
- **Airborne cap:** Blue hits it on some territories because long-haul patrols overlap (Kallax / Rovaniemi → Banak, 450–570 km each way). Options: count only on-station time, or use nearer bases or fewer stations.
- **Endurance:** does the AWACS stay on station the whole 6 hours (A-50 fuel)?
- **Frame rate** with up to 32 AI aircraft airborne: not measured yet.
- **MiG-29S:** left out of the Red rosters, because its loadouts carry CLSIDs `aircraft_pylons.lua` doesn't know.
- **Su-34 takeoff crash** (session 11): MSN5024_2 ejected at 161 ft 32 s after spawning at Poduzhemye. Watch for a repeat at that field.
- **Alert jets back on alert:** built after the session 11 run; check the `landed — its jet is back on alert` lines and a second launch by the same jet.
- **Scramble trigger misses dog-legs** (session 11, not changed): "inbound" follows the current heading, so a raid on a leg around SAM rings reads as heading elsewhere. Red's Su-34s attacking `SAM_KUUS_SA11_1` read as 19 / 25 min from other assets and were never scrambled against (a Blue patrol got them). Possible addition: a contact in contested airspace within a few minutes' flight of any own asset counts, whatever its heading.

**Reading a run (grep `dcs.log`):**

| Grep | Shows |
|---|---|
| `MSN`, `PKG` | every flight and package, with its `fired` / `killed` / `target object … destroyed` / `lost (…)` lines |
| `track:` | each airborne patrol and AWACS every 2 min: altitude, airspace, nearest enemy ring, km from station |
| `lost (` | who killed it, at what altitude, in which airspace, how far inside or outside the nearest enemy ring |
| `carries` | each aircraft's actual weapons 5 s after spawn; a warning when it's empty but the loadout lists pylons |
| `PRELOAD`, `the sim froze` | the start-up preload cost per type, and any spawn over 1 s |
| `HUMAN TASKING` | every frag and steerpoint list |
| `Build summary:` | the roll's totals (moved off screen in session 10) |
| `asked for` | a unit type DCS swapped (Leopard-2 substitution) |
| `picture` | each coalition's radar picture: sensors at start, new / regained / stale / dropped contacts (with what they're inbound on), airspace changes, a summary every 5 min, the first time a ground radar tracks each enemy group |
| `scramble` | alert bases (at planning), each scramble decision (base, type, raid, why, intercept distance, delay, alert jets ready), refusals (once per reason), stood down before launch, landed and back on alert |
| `leash` | a scramble sent home or stood down on the ramp, and why |

---

## Backlog (not on the roadmap)

Decide with John, step by step. Roadmap items are in `roadmap.md`.

**Playability follow-ups** (session 10, none built):
- **Spread the two taskings:** require the second human tasking's target ≥ ~75 km from the first, falling back to any target. On the 12:18 roll both went to Rovaniemi.
- **Unflown taskings' AI flights:** the AI SEAD of a human package flies even when nobody takes that tasking (4–6 jets, part of the airborne cap). Goes with picking a tasking: once a player takes one, cancel the other's AI flights, or never spawn a package's AI flights before a player shows up.
- **Assignment and completion tracking** (John: later; the design leaves room): take a tasking from the comms menu, bind by slot (`player_slot.group`) or by the player's base at birth; report the target result; "take another tasking" after landing.
- **DEAD frag:** replace the "Groups: SAM_…" line with what the site holds (radars, launchers).
- **Brief items:** AWACS and tanker frequencies and callsigns (callsign policy below), bullseye (currently 0,0), divert fields.
- **More players:** more slots per base (the tool and planner already take several per base; the planner uses the first one that exists); 2-ship human flights.
- **Steerpoints:** a return leg that repeats many transit points could be shortened ("same as 3").

**Front targets.** The fixed-target "front" echelon is still "≤ 100 km from an enemy base":
- **The gap:** on rolls where the sides sit far apart, nothing counts as front, so armor assembly areas and artillery never roll. Blue leaves ~3.5 missions per roll unplanned ("no target near the front in reach"), and human taskings fall back to DEAD / SEAD / CAP.
- **Offered, not built:** measure "front" from the airspace front line (`DivideAirspace` already runs before `PlanFixedGroundTargets`).
- **Optional:** John can nudge the no-road border zones onto a road (≤ 500 m) and fly the survey again.
- **Offered, not wanted for now:** reserving front zones for ground targets (John chose SAM front-belt chance 0.7 instead).
- **Also:** convoys and other mobile targets for Blue.

**Standoff attacks:** plan a release point short of the target, so jets attack from the contested airspace instead of overflying the target. First research which standoff weapons the DCS AI actually releases at range and which loadouts carry them:
- Blue: JSOW, SLAM-ER, AGM-86C;
- Red: Kh-29 / KAB, bomber cruise missiles.

Overlaps roadmap item 7 (cruise missiles).

**AI behaviour rules, one place** (John, session 8): collect the list first, then build it as one module instead of per-flight hacks:
- leash to own and contested airspace;
- strikes go home if their SEAD fails;
- scrambles that identify one jet and kill it only in certain airspace.

Built: `consumers/enforce_air_behaviour_rules.lua`, with the scramble leash as its first rule (see *Scrambles and the leash*). The rest, plus attack flights defending themselves, is now roadmap item 4 (AI behaviour logic).

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
1. `DrawAirspace` (first, under every other mark).
2. `Territory.apply`.
3. Spawns: **static objects first**, then base defenses, SAM sites, fixed-target units, convoys.
4. Draws.
5. `PreloadAircraftTypes`.
6. `ScheduleAirTaskingOrders.start`.
7. `TrackRadarPicture.start` (after the scheduler, before anything that reads the picture).
8. `EnforceAirBehaviourRules.start`, then `RunScrambles.start`.
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
Rough size: heavy 6–9 groups / ~20 units, standard 3–6 / ~13, light 2–3 / ~9. Skill: heavy `Good`, else `Average`. FPS is not a concern: standing ground units barely register (John).

**Groups per level**, most important layer first:
```
                                   heavy   standard   light
   radar_missile_launchers          1        —         —
   infrared_missile_launchers       1        0–1       —
   mobile_anti_aircraft_guns        1        0–1       —
   towed_anti_aircraft_guns         1–2      1–2       1
   shoulder_launched_missile_teams  1–2      1         1
   security_infantry                1–2      1         0–1
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

**Airborne cap:** `max_airborne_aircraft` 16 per coalition, counting every package member, patrol and AWACS (John: don't reduce flight volume). Up to 32 AI aircraft airborne in total.

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
- **Ids:** `MSN<n>` (Blue 2001+, Red 5001+) is the DCS group name.
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

**Packages: SEAD / DEAD** (John: a mission that needs suppression never flies without it, and whether the suppression works doesn't need tracking; it's flavour):
- **Unsuppressed:** a mission whose route crosses rings gets suppression flights, or isn't planned and another target is tried.
- **Dividing the threats:** in the order the route meets them. Each suppression flight takes `count × anti_radiation_missiles / missiles_per_threat` of them (2 missiles per threat; F-16 / F/A-18 carry 2, Su-34 / Su-24M 4), at most `max_groups_per_flight` 2 groups.
- **Point-defense escorts:** a SAM site's `<id>_escort` is engaged together with its site.
- **Base and timing:** a suppression flight flies the package's route from the mission's own base when it can, else from the region's base nearest the target. It is over the target `AIR_PACKAGE.suppression_lead_s` (3–5 min) ahead, with its `EngageGroup` tasks on the waypoint before its first ring.
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
- **Logging:** `fired <weapon>`, `killed <name> (<type>)`, `target object … destroyed (n of m critical)`, `<unit> lost (…)` with killer and position, `track:` every 2 min for patrols and the AWACS, and the ammo check 5 s after spawn.
- **Status:** `ScheduleAirTaskingOrders.statusOf` gives planned / airborne / landed / lost for the brief.

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
  - **Missiles are listed, but rarely:** 2 in one 5-min window while many were fired. Not reliable for air-to-air missiles; cruise missiles still to test (item 7).
  - **`getRadar()` works:** `SAM_ENON_SA11_1` tracking the Su-33, `SAM_ALTA_SA11_1` tracking the F-15C.
  - **Type known** for 6 of 16 new contacts.
  - **Bearing only** once: the F-15C, which carries an internal jammer in DCS. A good sign that DCS reports jammed contacts as range-unknown (optional jamming item).
  - **Low flyers:** the AWACS picked up aircraft at 1,100–4,500 ft from 160–210 km. Most first detections were 120–210 km out, which roughly fits the 15-min scramble warning.
  - **No flicker:** 0 "regained" lines; contacts went stale, then dropped.
  - A wreck can be seen once more after the kill (MSN5901_SCRAM), so a leash reason can read "heading away" instead of "destroyed". Wording only.
- **Offline harness:** `radar_picture_harness.lua` (session scratchpad; not kept) ran the module on the real 14:36 plan with stubbed radars: one Blue jet from Rovaniemi to Olenya, seen from T+60 to T+700. New at T+90, four airspace changes, stale at T+780, dropped at T+1020, a failing listener caught, missiles counted, the tracking line logged.

### Scrambles and the leash (`consumers/run_scrambles.lua`, `consumers/enforce_air_behaviour_rules.lua`)

Rebuilt 2026-09-30 (roadmap item 2; design agreed with John, recorded there). A scramble answers an immediate threat: it burns straight at the one raid it was sent after and chases it away or kills it, without flying head first into enemy airspace. First DCS run: session 11.

**Alert posture** (`planAlertPosture`, `AIR_DEFENSE`):
- held bases whose runway and parking fit an interception type (`COALITION_AIRCRAFT[c].interception`), the `alert_bases` (3) nearest the enemy, plus the nearest of each other region, so a pocket answers for itself;
- **not a base inside an enemy kill zone** (found in the harness: Vuojarvi under a Blue ring had no way out that didn't start in the kill zone);
- **3 alert jets per base** (`alert_aircraft_per_base`), 15 min cooldown between launches. A jet that lands is back on alert `scramble_turnaround_s` (30 min) later; one shot down is gone for the mission (John, 2026-09-30: a base shouldn't run out if its jets came back; replaced the first version's fixed 3 launches, which ran Red dry ~1.5 h into the first run). `plan.air_tasking_orders[c].alert = { bases = { { base, code, region, aircraft, pos, enemy_km, alert_aircraft, cooldown_s } }, max_airborne_aircraft, first_number }`.
- Session 11's roll: Red Alakurtti, Koshka Yavr, Banak; Blue Kuusamo, Ivalo, Vuojarvi.

**Trigger** (every radar-picture round):
- a tracked contact with a known range, not a helicopter, that is over own airspace, or that the picture has inbound on an own asset it will reach within `scramble_warning_min` (15) minutes for `scramble_inbound_rounds` (2) rounds in a row, in whatever airspace it is now;
- **refused** (logged once per reason, checked again every round) when a live scramble is already after it, when an airborne patrol's defended zone or commit circle covers where it is, or **while it is inside an enemy kill zone** ("under enemy SAM cover": the leash would only bring the fighter home again; found in the harness, where a raid loitering under Blue SAMs burned 4 launches in 15 minutes).

**The raid:** the trigger plus the other contacts within `raid_radius_km` (20) on a heading within `raid_heading_deg` (45); one scramble takes them all, `EngageGroup` on each, in order.

**The base:** the nearest ready alert base in the region facing the raid (`DivideAirspace.facingRegion`) whose intercept point is in reach and at least `scramble_min_leg_km` (10) out, with a free ramp spot; the coalition may go up to `scramble_over_cap` (2) over `max_airborne_aircraft`. The intercept point is the raid pushed ahead along its heading by the scramble's flight time, pulled back in 5 km steps until it lies in own or contested airspace outside enemy kill zones.

**The launch:**
- after `scramble_reaction_s` (60–120 s, cockpit alert), **hot on a free ramp spot, never the runway** (John: no spawning on top of jets lined up there). The spot is chosen at spawn time from `Airbase:getParking(true)`, nearest the runway, not a player slot or a parked-aircraft static. If the raid is gone by then, or no spot is free, the scramble is **stood down before launch** and its jet stays on alert;
- **the session 7 fixes:** `EngageGroup` on the takeoff waypoint, so it's active from wheels-up and the AI flies its own intercept (it used to sit on waypoint 2, the intruder's position at launch, and DCS starts a waypoint's tasks only on arrival); waypoints at the profile's `dash_speed_mps` (F-16 / F/A-18 325, F-15C / Su-27 / Su-30 / Su-33 355, MiG-31 440 m/s) with afterburner explicitly allowed (option 16 false), instead of `speed_locked` at cruise speed; `open_fire`, no `EngageTargets` on everything; one-ship, `interception` loadout, gun kept, may jettison;
- then `ScheduleAirTaskingOrders.track`, `TrackRadarPicture.addFlight` (its radar joins the picture) and `EnforceAirBehaviourRules.watch(m, "leash", { targets })`.
- Ids `MSN2901_SCRAM+` / `MSN5901_SCRAM+`.

**The leash** (`data/air_behaviour_rules.lua`), checked every picture round per watched flight:
- **home** when every raid group is dead, dropped from the picture, or back over its own airspace **heading away** (not `inbound`; a raid that only dips over its own airspace on the way in is still a raid); or when the scramble itself is more than 5 km into enemy airspace (distance to the nearest contested cell) or inside an enemy kill zone (85 % of a live medium / long-range ring);
- **stood down** (the group removed) if the raid is gone before it leaves the ramp;
- going home: `Controller:setTask` with a new airborne mission (from where it is to a landing at its base, cruise speed) and rules of engagement "return fire". Once sent home it isn't watched any more; the scheduler removes it after landing. Fuel is DCS's (bingo).
- `EnforceAirBehaviourRules.watching(id)` tells scrambles whether a flight is still hunting.

**Offline harness** (`scramble_harness.lua`, session scratchpad; not kept): real 14:36 plan with air tasking re-planned, the real picture, rules, scrambles and aircraft spawner over stubbed DCS; one Blue jet Rovaniemi → Olenya. Checked: the spawned group (hot ramp start, `EngageGroup` on waypoint 1, afterburner option, dash speed and interception altitude on waypoint 2), the leash's `setTask` / return-fire option, stood down before launch, patrol cover, SAM cover, and the kill-zone leash when the scramble chases into Blue's rings.

**First DCS run** (session 11, ~48 min, watched): Red decided 6 scrambles, Blue 4.
- **Burning straight at the raid works:** John: MSN2901 and MSN5902 "did exactly what we wanted as a scramble", though MSN2901's path looked a little odd (its intercept point was 239 km out; once airborne the AI flies its own intercept geometry).
- **Kills:** scrambles scored 4 kills for 2 losses. MSN2901 (F-15C) killed a Su-33 patrol with an AIM-120 fired just before the kill-zone leash sent it home; MSN5901 (Su-30) killed both F-16s of a Blue DEAD; MSN5903 (Su-27) killed a SEAD F/A-18, then fell to a Blue patrol.
- **Every leash reason fired:** kill zone, target destroyed, target lost from the picture, heading away; plus stood down on the ramp (MSN2904) and stood down before launch (MSN5904, MSN5906).
- **`setTask` home lands them:** MSN2902 was sent home just after takeoff (its target was already gone), circled in the landing pattern and landed 5 min later (John agreed: going home is right when the target is gone). MSN2901 landed ~17 min after its leash.
- **Refusals:** "under enemy SAM cover" 7 times (mostly Blue patrols orbiting under Blue SAMs), "covered by patrol" twice. A scramble at an enemy patrol that looks like a raid is fine (John: Blue can't know a jet's intentions).
- **Budget:** the first version's 3 launches per base would have run Red dry ~1.5 h in → alert jets now return after landing (above).

### Player slots (`data/player_slots.lua`)

- **Templates:** John places F-16C dynamic-spawn templates (group `f16_<base>`, one per base) in `kola_f16_random_tasking.miz`; DCS spawns the player on the template's exact spot. In the ME, the always-Blue / always-Red bases have their coalition set; contested ones are neutral and the script sets them.
- **Now 8 slots:** Banak, Bodø, Ivalo, Kallax, Kemi-Tornio, Kiruna, Rovaniemi, Tromsø.
- **Data file:** `kola_data_tools/miz_player_slots.py` → `data/player_slots.lua` (`PLAYER_SLOTS[base]` = terminal index, spot name, group, type, position). Re-run it after moving or adding slots.
- **Kept clear:** `gather.lua` attaches `player_slots` to each airbase and warns when a slot's spot is missing or has moved. Parked-aircraft statics and AI parking skip those spots; ground units already keep clear of every parking spot.

### Brief (`consumers/brief_air_tasking.lua`)

- **Start text** (3 min, `START_MESSAGE_S` 180): the weather plus one line per human tasking (base, slot, takeoff, TOT, what). Nothing else on screen at start (John).
- **Comms menu** for Blue (`\` > F10. Other...; John: call it the comms menu, F10 means the map):
  - `Human taskings > <MSN> > Frag / Steerpoints`, and `All human taskings`;
  - `Air tasking order > Attack packages / Patrols and AWACS / All flights`, each flight with its state.

  Texts stay 60 s.
- **Frag contents:**
  - times (local);
  - target: description, degrees and decimal minutes (F-16) + MGRS + elevation, aim points, success as "destroy at least n of its m critical objects";
  - the loadout planned for an AI jet;
  - threats: enemy SAM rings the route crosses or passes within 20 km of, with who suppresses each;
  - the package;
  - **SEAD frags** add the escorted mission and "your" threats; **CAP frags** add the orbit, the defended zone and the other patrols.

  Every frag and steerpoint list also goes to `dcs.log` (`HUMAN TASKING`).
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

**Threat-intel fidelity rule** (for the brief and fog of war, roadmap item 10). Fidelity follows the threat's real-world nature, not a difficulty setting:

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
- Roadmap item 8 (AI radio calls) builds on this.

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
    air_behaviour_rules.lua      -- the rules enforced on AI flights after launch (the leash)
    aircraft_profiles.lua        -- per aircraft type: runway, parking, reach, speeds, altitudes (hand)
    aircraft_loadouts.lua        -- one loadout per type × mission (aircraft_loadouts.py)
    aircraft_pylons.lua          -- pylon → CLSID, generated; offline validation only, not loaded
    unit_pool.lua                -- every spawnable DCS unit type (unit_pool.py)
    cloud_presets.lua            -- DCS cloud presets (cloud_presets.py)
  stages\                        -- named by verb; run order lives in init.lua
    roll_territory.lua  plan_base_defenses.lua  plan_sam_sites.lua  divide_airspace.lua
    plan_fixed_ground_targets.lua  plan_convoys.lua  catalog_targets.lua  plan_air_tasking.lua
  consumers\
    territory.lua                -- apply the roll (to be renamed apply_territory.lua)
    spawn_static_objects.lua  spawn_ground_groups.lua  spawn_aircraft_groups.lua
    preload_aircraft_types.lua   -- first-spawn freeze fix
    schedule_air_tasking_orders.lua  -- spawns flights on the clock; logs shots, kills, losses; statusOf
    track_radar_picture.lua      -- each coalition's radar picture: contacts, events, queries
    enforce_air_behaviour_rules.lua  -- rules on AI flights after launch: the scramble leash
    run_scrambles.lua            -- one-ship scrambles at raids the radar picture shows
    brief_air_tasking.lua        -- start text + comms menu
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
| Flight | `MSN<n>_<tag>`: Blue 2001+, Red 5001+ (scrambles 2901+ / 5901+); units `<id>_<n>`. MSN = mission number, as in a real air tasking order. Tag = the mission type's `group_name_tag`: `STRIKE`, `OCA` (offensive counter-air: airfield strike), `SEAD`, `DEAD`, `CAP`, `AEW`, `SCRAM` (John, 2026-09-30) | `MSN2025_DEAD`, `MSN2901_SCRAM` |
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
