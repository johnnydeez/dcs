-- Loads the shared mission framework and the mission on it, in order
-- (shared_mission_framework\framework_design.md, *Roles and actors*, rule 12):
--   data (config, the shared data, the mission's data: MISSION.data_files) → tools → logs →
--   record → watch → execute → commander → planner → controller → inform
--   (→ the one-off surveys a CONFIG flag asks for) → the data checks
-- Execute loads before the actors that call it. No file uses another's module while it
-- loads, but for the controller's alias of watch\flight_situations.lua (watch loads first).
-- The mission's init.lua loads its mission_settings.lua (MISSION) first, then this, then
-- calls LoadFramework.run(); run_mission.lua then plays the run sequence.
--
-- The framework's files are in Saved Games\DCS\Scripts\<MISSION.framework_folder>\
-- (shared_mission_framework), the mission's in Scripts\<MISSION.scripts_folder>\ (Kola:
-- kola_f16). A file that fails to load stops everything, named in dcs.log and on screen.

LoadFramework = {}

-- The framework's own files, in load order (paths inside its folder).
local FRAMEWORK_FILES = {
    -- the shared data: facts about DCS, recipes, and the tuning every mission uses as is
    -- (a setting a mission needs its own value of lives in every mission's data instead)
    data = {
        "data\\config.lua",
        "data\\cloud_presets.lua", "data\\unit_pool.lua",
        "data\\base_defense_levels.lua", "data\\base_defense_composition.lua", "data\\base_defense_placement.lua",
        "data\\sam_site_recipes.lua", "data\\sam_site_density.lua",
        "data\\fixed_ground_target_recipes.lua", "data\\fixed_ground_target_density.lua",
        "data\\convoy_recipes.lua", "data\\aircraft_profiles.lua", "data\\aircraft_loadouts.lua",
        "data\\air_tasking.lua", "data\\flight_callsigns.lua", "data\\airspace.lua",
        "data\\radar_picture.lua", "data\\air_picture_calls.lua", "data\\radio_calls.lua",
        "data\\air_control.lua", "data\\event_log.lua", "data\\ground_unit_sleep.lua",
    },
    -- answers from arguments, asked by anyone
    tools = {
        "tools\\util.lua", "tools\\weather.lua", "tools\\placement.lua",
        "tools\\threat_routing.lua", "tools\\sam_reach.lua", "tools\\flight_callsigns.lua",
        "tools\\airspace.lua", "tools\\bearings.lua",
    },
    -- the log files: dcs.log and the event log
    logs = {
        "logs\\dcs_log.lua", "logs\\event_log.lua", "logs\\ground_units_awake.lua", "logs\\build_summary.lua",
    },
    -- everything one part needs from another; each entry has one writer
    record = {
        "record\\record.lua", "record\\radar_picture.lua", "record\\flight_launches.lua", "record\\flights.lua",
        "record\\airbases.lua", "record\\groups.lua", "record\\threats.lua", "record\\airborne_aircraft.lua",
        "record\\alert_jets.lua", "record\\watched_flights.lua", "record\\shots.lua",
        "record\\flight_situations.lua", "record\\callsigns.lua", "record\\air_flight_decisions.lua",
        "record\\orders.lua", "record\\flight_loadouts.lua", "record\\waypoints_reached.lua", "record\\dcs_events.lua",
        "record\\players.lua", "record\\flight_activity.lua", "record\\airfield_traffic.lua",
        "record\\ground_units_awake.lua", "record\\enemy_aircraft_near_bases.lua", "record\\aircraft_positions.lua", "record\\wind.lua",
    },
    -- the only place live DCS is read
    watch = {
        "watch\\dcs_events.lua", "watch\\world_at_start.lua", "watch\\weapon_impacts.lua", "watch\\flights.lua",
        "watch\\airbases.lua", "watch\\groups.lua", "watch\\threats.lua", "watch\\airborne_aircraft.lua",
        "watch\\radar_picture.lua", "watch\\shots.lua", "watch\\flight_loadouts.lua", "watch\\flight_routes.lua",
        "watch\\players.lua", "watch\\flight_activity.lua", "watch\\airfield_traffic.lua",
        "watch\\enemy_aircraft_near_bases.lua", "watch\\flight_situations.lua", "watch\\aircraft_positions.lua", "watch\\wind.lua",
    },
    -- the only place the sim is changed
    execute = {
        "execute\\base_coalitions.lua", "execute\\spawn_ground_groups.lua", "execute\\spawn_static_objects.lua",
        "execute\\spawn_aircraft_groups.lua", "execute\\preload_aircraft_types.lua",
        "execute\\air_flight_orders.lua", "execute\\ground_units_on_off.lua",
    },
    -- the mission plan at start: territory, defences, SAM sites, targets, the air tasking orders
    planner = {
        "planner\\roll_territory.lua", "planner\\plan_base_defenses.lua", "planner\\plan_sam_sites.lua",
        "planner\\divide_airspace.lua", "planner\\plan_fixed_ground_targets.lua", "planner\\plan_convoys.lua",
        "planner\\catalog_targets.lua", "planner\\plan_air_tasking.lua",
    },
    -- the run-time decisions: AI flights, sleeping ground units
    controller = {
        "controller\\air_flights\\schedule_flights.lua",
        "controller\\air_flights\\apply_directives.lua",
        "controller\\air_flights\\coordinate_flights.lua",
        "controller\\air_flights\\assign_alert_jets.lua",
        "controller\\air_flights\\decide_launches.lua",
        "controller\\air_flights\\scramble_fighters.lua",
        "controller\\air_flights\\direct_flights.lua",
        "controller\\wake_ground_units.lua",
    },
    -- the players: screen, radio, map, comms menus
    inform = {
        "inform\\map\\territory.lua", "inform\\map\\airspace.lua", "inform\\map\\base_defenses.lua", "inform\\map\\sam_sites.lua",
        "inform\\map\\fixed_ground_targets.lua", "inform\\map\\convoys.lua", "inform\\map\\air_tasking_orders.lua",
        "inform\\screen\\player_menus.lua", "inform\\screen\\briefing.lua", "inform\\screen\\air_picture.lua",
        "inform\\radio\\radio_calls.lua", "inform\\screen\\airfield_info.lua", "inform\\radio\\flight_calls.lua",
        "inform\\radio\\darkstar_orders.lua", "inform\\radio\\airfield_calls.lua",
    },
}
-- the roles and actors in load order (data comes first, with the mission's after the shared)
local LOAD_ORDER = { "tools", "logs", "record", "watch", "execute", "commander", "planner", "controller", "inform" }

LoadFramework.framework_folder = lfs.writedir() .. "Scripts\\" .. MISSION.framework_folder .. "\\"
LoadFramework.mission_folder   = lfs.writedir() .. "Scripts\\" .. MISSION.scripts_folder .. "\\"

local function fail(what, err)
    env.info("[" .. MISSION.log_tag .. "] FATAL: " .. what .. ": " .. tostring(err))
    trigger.action.outText(MISSION.log_tag .. " SCRIPT LOAD ERROR — " .. what .. "\n" .. tostring(err), 60)
end

local function load(folder, rel)
    local ok, err = pcall(dofile, folder .. rel)
    if not ok then fail("could not load " .. rel, err) end
    return ok
end

local function loadAll(folder, list)
    for _, rel in ipairs(list) do
        if not load(folder, rel) then return false end
    end
    return true
end

-- Loads everything. Returns true, or false once something failed (already reported).
function LoadFramework.run()
    local F, M = LoadFramework.framework_folder, LoadFramework.mission_folder
    if not loadAll(F, FRAMEWORK_FILES.data) then return false end
    if not loadAll(M, MISSION.data_files or {}) then return false end

    for _, role in ipairs(LOAD_ORDER) do
        if not loadAll(F, FRAMEWORK_FILES[role] or {}) then return false end
        if role == "logs" then
            -- nothing logs while data and tools load, so this is still dcs.log's first line
            Log.info("============================================")
            Log.info("  " .. MISSION.name .. " loading")
            Log.info("  " .. M)
            Log.info("============================================")
        end
    end
    if CONFIG.SURVEY_FOOTPRINTS and not load(F, "survey\\survey_airbase_footprints.lua") then return false end
    if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN and not load(F, "survey\\probe_parked_aircraft_spawn.lua") then return false end

    -- data files checked against each other and the unit pool before anything runs
    PlannerPlanBaseDefenses.checkData()
    PlannerPlanSamSites.checkData()
    PlannerPlanFixedGroundTargets.checkData()
    PlannerPlanConvoys.checkData()
    PlannerPlanAirTasking.checkData()
    return true
end
