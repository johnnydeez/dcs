-- Caucasus F-16 random tasking: what makes this mission this mission. Plain data, no logic.
-- Loaded first (init.lua), before config.lua, so every later file can read MISSION.
--
-- The logic is the shared mission framework's (shared_mission_framework\mission_scripts\,
-- shared with Kola and later the Afghanistan campaign); anything that names this mission,
-- its map or its files lives here instead (shared_mission_framework\development_docs\plan.md,
-- step 7). Started from Kola's mission_settings.lua.

MISSION = {
    -- Where its scripts are, under Saved Games\DCS\Scripts\: its own (this file and its
    -- data) and the shared framework's.
    scripts_folder   = "caucasus_f16",
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
    name         = "Caucasus F-16 random tasking",   -- dcs.log's loading banner, the event log's first line
    display_name = "CAUCASUS",                       -- the start text, the territory summary
    log_tag      = "CAUCASUS",                       -- every dcs.log line starts [CAUCASUS]; grep it

    -- Its files in Saved Games\DCS\.
    plan_dump_file                 = "caucasus_last_plan.lua",            -- the finished plan, for offline reading
    airbase_footprints_survey_file = "caucasus_airbase_footprints.lua",   -- CONFIG.SURVEY_FOOTPRINTS's output

    -- Its event log: one file per run in event_log_folder (the repository, git-ignored); if that
    -- can't be written, in event_log_fallback_folder under Saved Games\DCS.
    event_log_folder          = "C:\\Users\\johnk\\Git\\dcs\\missions\\caucasus_multiplayer_random_tasking\\event_logs",
    event_log_fallback_folder = "caucasus_event_logs",

    -- Its folder in the repository (the zone survey runs the map tools on it) and its
    -- missions under Saved Games\DCS\Missions: the one players fly, and the zone drawing
    -- mission the zone survey is flown in (shared_mission_framework\map_data_tools read these too).
    repository_folder         = "C:\\Users\\johnk\\Git\\dcs\\missions\\caucasus_multiplayer_random_tasking",
    flyable_mission_file      = "caucasus_multiplayer_random_tasking.miz",
    zone_drawing_mission_file = "caucasus_multiplayer_rt_zones.miz",
    -- The zone survey's files in Saved Games\DCS: its measurements, and the log of the map
    -- tools it runs afterwards (survey\survey_zone_terrain.lua).
    zone_terrain_survey_file = "caucasus_zone_terrain.lua",
    zone_update_log_file     = "caucasus_zone_update.log",
    -- The map tools' input of this map's airbases (map_data_sources\): reference points and
    -- our own 4-letter codes.
    airbase_reference_file = "caucasus_airbases.json",

    -- The map.
    -- Its name as DCS has it (a .miz's theatre, Mods\terrains\<map>\): the map tools' projection,
    -- its airfield radios.
    map = "Caucasus",
    -- Mission clock offset from UTC (pydcs terrain/caucasus: +4 h, Georgia's time); places the
    -- sun. DCS start_time is local.
    utc_offset_h = 4,
    -- The map's edges, DCS metres (x north, z east); the airspace grid reaches past them, the
    -- map doesn't (AWACS orbits keep inside them, Kola bug 47). From pydcs (terrain/caucasus,
    -- bounds): DCS's own MissionGenerator\nodesMap.lua for Caucasus holds Kola's numbers, with
    -- Batumi, Kobuleti and Tbilisi outside them.
    map_bounds_m = { min_x = -600000, min_z = -560000, max_x = 380000, max_z = 1130000 },
    -- Magnetic variation, degrees east, by longitude, when DCS's magvar module can't be loaded
    -- in the mission or answers 0 (it does outside the game). Approximate: about +6 to +7°
    -- across the whole map (Anapa to Tbilisi); straight lines between, the ends held. The
    -- start-up self-test writes the module's value at the check airbase to dcs.log
    -- (grep "air picture"): correct this table from it after the first run.
    fallback_magnetic_variation = { { lon = 37, deg = 7 }, { lon = 45, deg = 6.5 } },
    -- The airbase the start-up self-test asks magvar about: the variation is +6° or more
    -- everywhere on this map, so an answer near 0 there means magvar isn't working.
    magnetic_variation_check_airbase = "Kutaisi",

    -- The scenario.
    -- The country each coalition's SAM sites spawn as, instead of its CJTF one (Kola bug 25: a
    -- Russian SA-11's ring showed on the F-16's HSD, a CJTF Red one's didn't). A coalition
    -- not listed spawns as its CJTF country.
    sam_site_country = { red = "RUSSIA" },
}
