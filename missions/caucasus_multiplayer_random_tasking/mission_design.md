# Caucasus Multiplayer Random Tasking — Mission design

> **What this is:** the Caucasus mission's own design: its scenario, its map and the settings it has its own values for. It is the same style as Kola on a different map (John, 2026-10-06): when the mission loads, the shared framework rolls who holds which field, fills the map with ground defenses, SAM networks and targets, plans both air wars for the window and briefs the players, here two of them in multiplayer (John in the F-16C, a friend in the F/A-18C, 2026-10-07). How all of that works is the framework's: `shared_mission_framework\framework_design.md`.
>
> **Where else to look:** status, what's next and what to check in a run: the repository's `plan.md` (*Where we are*, *Caucasus*); where things are headed: `roadmap.md` (items say `**For:** Caucasus` or `framework`); bugs: `bugs.md`; the history of how this mission was built: `plan.md`, *History*, *The framework split*, step 7.
>
> **Paths** are relative to this folder (`missions\caucasus_multiplayer_random_tasking\`) unless they say otherwise.

---

## Names and files

- **Folder** `missions\caucasus_multiplayer_random_tasking\` (after John's `.miz`), **scripts folder** `caucasus_f16\` (copied to `Saved Games\DCS\Scripts\caucasus_f16\`), **log tag** `CAUCASUS` (grep `[CAUCASUS]` in `dcs.log`).
- **John's missions** in `Saved Games\DCS\Missions\`: `caucasus_multiplayer_random_tasking.miz` (the one flown: player slots, the init trigger, airbase coalitions) and `caucasus_multiplayer_rt_zones.miz` (zone drawing, flown once to survey them).
- **Its own scripts:** `caucasus_f16\init.lua` (the entry the `.miz` trigger runs), `mission_settings.lua` (`MISSION`: names, files, map facts), `data\` (map, scenario and its own settings, `MISSION.data_files`), `survey\survey_zone_terrain.lua` (the loader the zone mission's trigger runs).
- **Map inputs:** `map_data_sources\caucasus_airbases.json` (21 airbases from pydcs, same names as DCS's `Radio.lua`, with our 4-letter codes).
- **Event logs:** `event_logs\` (git-ignored, one per run).

## Map facts (`caucasus_f16\mission_settings.lua`)

- **Map** `Caucasus`; projection from pydcs's Caucasus parameters (`map_data_tools\map_projection.py`).
- **UTC +4** (Georgia's time, pydcs).
- **Magnetic variation** fallback ~+6.5 to +7° across the map; the start-up self-test asks DCS's magvar at Kutaisi (first start: +6.6°, the table +6.7°).
- **Map edges** from pydcs (x −600 to 380 km, z −560 to 1,130 km). DCS's own `MissionGenerator\nodesMap.lua` for Caucasus holds Kola's numbers and leaves Batumi, Kobuleti and Tbilisi outside the map.
- **Red's SAMs spawn as Russia** (`sam_site_country`; the HSD shows a Russian SA-11's ring, not a CJTF Red one's).

## Scenario

**Georgia with US / NATO support (Blue) against Russia (Red).**

### Territory: the clusters (`data/clusters.lua`)

| Cluster | Type | Bases |
|---|---|---|
| GEORGIA_EAST | always Blue | Tbilisi-Lochini, Soganlug, Vaziani |
| ADJARA | always Blue | Batumi, Kobuleti |
| ABKHAZIA | contested, p_red 0.7 (Russian-held in reality; Blue = a Georgian counter-offensive) | Gudauta, Sukhumi-Babushara |
| SAMEGRELO | contested, p_red 0.5, requires ABKHAZIA Red | Senaki-Kolkhi |
| IMERETI | contested, p_red 0.4, requires SAMEGRELO Red (the deepest Russian push) | Kutaisi |
| SOCHI | always Red (a NATO Sochi with Abkhazia Russian would be a lone pocket; the roll can't say "Blue only if Abkhazia is Blue") | Sochi-Adler |
| KUBAN | always Red | Krasnodar-Center, Krasnodar-Pashkovsky, Maykop-Khanskaya, Krymsk, Anapa-Vityazevo, Novorossiysk, Gelendzhik |
| NORTH_CAUCASUS | always Red | Mineralnye Vody, Nalchik, Mozdok, Beslan |

### Airbase classes (`data/airbase_classes.lua`, John OK'd 2026-10-06; runway lengths DCS's)

- **Hubs:** Tbilisi-Lochini (2,345 m), Kutaisi (2,419 m), Mineralnye Vody as the bomber base (3,754 m: the Tu-22M3s and the A-50).
- **Fighter bases:** Vaziani, Krymsk, Krasnodar-Center, Maykop-Khanskaya, Mozdok (DCS's 2,357 m runway is too short for the Tu-22M3's 2,500 m).
- **Helicopter bases:** Soganlug, Gudauta. The rest are dispersal fields.
- No Blue field has 2,500 m, so no B-1B here; the E-3A (`min_runway_m` 2,300, shared) can leave from Tbilisi-Lochini.
- **Forested fields:** none.

### Rosters (`data/coalition_rosters.lua`)

- Copied unchanged from Kola's on 2026-10-06 to get the mission running; its comments still give Kola's reasons. **To rework** for Georgia, NATO and Russia's Southern Military District.

## The mission's own settings (framework_design.md, *Settings that differ by mission*)

- **Radio channels** (`data/radio_channels.lua`): AWACS (Darkstar) UHF 272.000, mission VHF 143.000; each field's real tower frequency (`data/airfield_frequencies.lua`: 21 fields, VHF 121–141, UHF 250–270), 122.800 where the map gives none. Kola's 262.000 / 140.000 would land on Kobuleti's and Vaziani's towers.
- **AWACS orbit distances** (`data/awacs_orbit_distances.lua`): 120 km from enemy fighter bases, 40 km from the contested airspace (Kola: 250 / 120; on this map all of Georgia is within ~180 km of a Red base). Blue's E-3A then orbits over western Georgia from Kutaisi when Abkhazia is Blue, over north-east Turkey from Tbilisi when it's Red; Red's A-50 from Mineralnye Vody north of the mountains.

## Players: multiplayer (2026-10-07)

- **Two players:** John in the F-16C, a friend in the F/A-18C, flying a human tasking together or apart; nobody is assigned one (John: "just have human missions available that we can pick up"). The mission runs on John's PC (the host); the friend joins it.
- **Slots** (`data/player_slots.lua`, from `map_data_tools\miz_player_slots.py`): an F-16C (`f16_<base>`) and an FA-18C (`f18_<base>`) dynamic-spawn slot at each of Batumi, Kobuleti, Tbilisi-Lochini, Gudauta and Sukhumi-Babushara. CJTF Blue, each its own Link 16 STN (F-16s 00201–00205, F/A-18s 00206–00212).
- **Callsigns** (Darkstar calls each player by the jet's callsign): the F-16s Python 1-1, the F/A-18s Snake 1-1; `f18_gudauta` is Enfield 1-1.
- **A human tasking is open to every slot at its base,** in either jet: its frag lists each slot and each type's loadout (framework_design.md, *Human taskings*, *Brief*). Each player's comms menu is their own (*Brief*).
- **The radio for the second player** isn't built yet: roadmap item 19 (a Darkstar frequency per slot, the calls sent to the friend's radio player over ZeroTier), and the F/A-18C's radios in the export script.

## Zones (`data/zones.lua`)

- **91 zones,** drawn in `caucasus_multiplayer_rt_zones.miz`, all 274 m circles (every SAM and target kind fits), surveyed 2026-10-06. 66 have no road within 500 m (26 farther than 2 km), so garrisons, command posts, assembly areas and depots fit only the other 25. John will add zones later; after drawing or moving any, fly the zone mission once.

## Still to design

- **Tuning for the smaller map,** each value moved into this mission's data when it's needed: front and echelon distances, the contested band, SAM density (Blue hits its 75 % zone cap), CAP stations, the airborne cap.
- **The sea:** the Black Sea is next to the fight; ships aren't in the framework yet (naval strike needs research).
