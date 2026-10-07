-- Kola F-16 random tasking: what makes this mission this mission. Plain data, no logic.
-- Loaded first (init.lua), before config.lua, so every later file can read MISSION.
--
-- The logic is the shared mission framework's (shared_mission_framework\mission_scripts\,
-- shared with the Caucasus random tasking and the Afghanistan campaign); anything that names
-- this mission, its map or its files lives here instead
-- (shared_mission_framework\development_docs\plan.md, step 1).

MISSION = {
    -- Where its scripts are, under Saved Games\DCS\Scripts\: its own (this file and its
    -- data) and the shared framework's.
    scripts_folder   = "kola_f16",
    framework_folder = "shared_mission_framework",

    -- Its own data files, in its scripts folder, loaded after the framework's shared data
    -- (load_framework.lua): the map, the scenario, and the settings each mission has its own
    -- values for (the framework holds no value for those).
    data_files = {
        "data\\clusters.lua", "data\\zones.lua", "data\\airbase_codes.lua", "data\\airbase_classes.lua",
        "data\\player_slots.lua", "data\\coalition_rosters.lua", "data\\airbase_footprints.lua",
        "data\\forested_airfields.lua", "data\\airfield_frequencies.lua",
        "data\\radio_channels.lua", "data\\awacs_orbit_distances.lua",
    },

    -- Who it is: dcs.log and the screen.
    name         = "Kola F-16 random tasking",   -- dcs.log's loading banner, the event log's first line
    display_name = "KOLA",                       -- the start text, the territory summary
    log_tag      = "KOLA",                       -- every dcs.log line starts [KOLA]; grep it

    -- Its files in Saved Games\DCS\.
    plan_dump_file                 = "kola_last_plan.lua",            -- the finished plan, for offline reading
    airbase_footprints_survey_file = "kola_airbase_footprints.lua",   -- CONFIG.SURVEY_FOOTPRINTS's output

    -- Its event log: one file per run in event_log_folder (the repository, git-ignored); if that
    -- can't be written, in event_log_fallback_folder under Saved Games\DCS.
    event_log_folder          = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking\\event_logs",
    event_log_fallback_folder = "kola_event_logs",

    -- Its folder in the repository (the zone survey runs the map tools on it) and its
    -- missions under Saved Games\DCS\Missions: the one players fly, and the zone drawing
    -- mission the zone survey is flown in (shared_mission_framework\map_data_tools read these too).
    repository_folder         = "C:\\Users\\johnk\\Git\\dcs\\missions\\kola_f16_random_tasking",
    flyable_mission_file      = "kola_f16_random_tasking.miz",
    zone_drawing_mission_file = "khola_ground_zones.miz",
    -- The zone survey's files in Saved Games\DCS: its measurements, and the log of the map
    -- tools it runs afterwards (survey\survey_zone_terrain.lua).
    zone_terrain_survey_file = "kola_zone_terrain.lua",
    zone_update_log_file     = "kola_zone_update.log",
    -- The map tools' input of this map's airbases (map_data_sources\): reference points and
    -- our own 4-letter codes.
    airbase_reference_file = "kola_airbases.json",

    -- The map.
    -- Its name as DCS has it (a .miz's theatre, Mods\terrains\<map>\): the map tools' projection,
    -- its airfield radios.
    map = "Kola",
    -- Mission clock offset from UTC (pydcs terrain/kola: +3 h); places the sun. DCS start_time is local.
    utc_offset_h = 3,
    -- The map's edges, DCS metres (x north, z east); the airspace grid reaches past them, the
    -- map doesn't (AWACS orbits keep inside them, Kola bug 47). From DCS World\Mods\terrains\
    -- Kola\MissionGenerator\nodesMap.lua (nodesMapBorders); Caucasus's file carries the very
    -- same numbers, so they may be ED's template rather than Kola's true edges (pydcs gives
    -- x -315 to 900 km, z -900 to 855.5 km). Kola's airbases all lie inside them.
    map_bounds_m = { min_x = -285184, min_z = -557056, max_x = 393216, max_z = 884736 },
    -- Magnetic variation, degrees east, by longitude, when DCS's magvar module (DCS
    -- World\bin, as the mission editor and the DTC use it) can't be loaded in the mission or
    -- answers 0 (it does outside the game). Approximate 2021 values across the map (Bodø,
    -- Tromsø, Rovaniemi, Murmansk); straight lines between, the ends held.
    fallback_magnetic_variation = { { lon = 14, deg = 5 }, { lon = 19, deg = 8 }, { lon = 26, deg = 12 }, { lon = 33, deg = 16 } },
    -- The airbase the start-up self-test asks magvar about: the variation is +5° or more
    -- everywhere on this map, so an answer near 0 there means magvar isn't working.
    magnetic_variation_check_airbase = "Rovaniemi",

    -- The scenario.
    -- The country each coalition's SAM sites spawn as, instead of its CJTF one (bug 25: a
    -- Russian SA-11's ring showed on the F-16's HSD, a CJTF Red one's didn't; every Red system
    -- here is Russian-made). A coalition not listed spawns as its CJTF country.
    sam_site_country = { red = "RUSSIA" },
}
