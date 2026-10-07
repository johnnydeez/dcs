# Kola F-16 Random Tasking — Mission design

> **What this is:** the Kola mission's own design: its scenario, its map and the settings it has its own values for. When the mission loads, the shared framework rolls the battlefield (who holds which airfield), fills it with ground defenses, SAM networks and targets, plans both coalitions' air war for a ~6-hour window, and briefs the human players on their taskings. How all of that works is the framework's: `shared_mission_framework\framework_design.md` (until 2026-10-06 it was in this mission's `plan.md`).
>
> **Where else to look:** status, what's next, what to check in the next run, Kola's run history and the backlog: the repository's one `plan.md` (*Kola*, *History*); where things are headed: `roadmap.md`; bugs: `bugs.md`; done: `closed.md` (all at the root). Session-by-session history before 2026-09-30 is in git (`notes/kola_f16_generator_plan.md` in commits up to `4c49af9`).
>
> **Paths** are relative to this folder (`missions\kola_f16_random_tasking\`) unless they say otherwise. Kola's own scripts in `kola_f16\` are its settings (`mission_settings.lua`), its map and scenario data, and its entry `init.lua`.

---

## Kola's map and scenario

Kola's own data on the shared framework: its names, folders and map facts in `kola_f16\mission_settings.lua` (`MISSION`: UTC +3, the magnetic-variation table Bodø +5° … Murmansk +16° with its self-test at Rovaniemi, Red's SAMs spawned as Russia, the map's edges, its files), its map and scenario data in `kola_f16\data\` (`MISSION.data_files`), and the settings each mission has its own values for, since 2026-10-06 (`radio_channels.lua`: AWACS UHF 262.000, mission VHF 140.000; `awacs_orbit_distances.lua`: 250 km from enemy fighter bases, 120 km from the contested airspace; `framework_design.md`, *Settings that differ by mission*). How each piece is used: `framework_design.md`, the section named in each heading.

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
