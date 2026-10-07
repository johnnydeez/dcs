-- Loads the shared mission framework and the mission on it, in order
-- (shared_mission_framework\development_docs\plan.md, *Loading*):
--   config → lib → shared data → the mission's data (MISSION.data_files) → gather →
--   stages → consumers (→ the one-off surveys a CONFIG flag asks for) → the data checks
-- The mission's init.lua loads its mission_settings.lua (MISSION) first, then this, then
-- calls LoadFramework.run(); run_mission.lua then plays the run sequence.
--
-- The framework's files are in Saved Games\DCS\Scripts\<MISSION.framework_folder>\
-- (shared_mission_framework), the mission's in Scripts\<MISSION.scripts_folder>\ (Kola:
-- kola_f16). A file that fails to load stops everything, named in dcs.log and on screen.

LoadFramework = {}

-- The framework's own files, in load order (paths inside its folder).
local FRAMEWORK_FILES = {
    lib = {
        "lib\\util.lua", "lib\\logger.lua", "lib\\weather.lua", "lib\\placement.lua",
        "lib\\threat_routing.lua", "lib\\sam_reach.lua", "lib\\flight_callsigns.lua",
    },
    -- the shared data: facts about DCS, recipes, and the tuning every mission uses as is
    -- (a setting a mission needs its own value of lives in every mission's data instead)
    data = {
        "data\\cloud_presets.lua", "data\\unit_pool.lua",
        "data\\base_defense_levels.lua", "data\\base_defense_composition.lua", "data\\base_defense_placement.lua",
        "data\\sam_site_recipes.lua", "data\\sam_site_density.lua",
        "data\\fixed_ground_target_recipes.lua", "data\\fixed_ground_target_density.lua",
        "data\\convoy_recipes.lua", "data\\aircraft_profiles.lua", "data\\aircraft_loadouts.lua",
        "data\\air_tasking.lua", "data\\flight_callsigns.lua", "data\\airspace.lua",
        "data\\radar_picture.lua", "data\\air_picture_calls.lua", "data\\radio_calls.lua",
        "data\\air_control.lua", "data\\event_log.lua", "data\\ground_unit_sleep.lua",
    },
    stages = {
        "gather.lua",
        "stages\\roll_territory.lua", "stages\\plan_base_defenses.lua", "stages\\plan_sam_sites.lua",
        "stages\\divide_airspace.lua", "stages\\plan_fixed_ground_targets.lua", "stages\\plan_convoys.lua",
        "stages\\catalog_targets.lua", "stages\\plan_air_tasking.lua",
    },
    consumers = {
        "consumers\\write_event_log.lua", "consumers\\track_weapon_impacts.lua", "consumers\\territory.lua",
        "consumers\\draw_airspace.lua", "consumers\\spawn_ground_groups.lua", "consumers\\draw_base_defenses.lua",
        "consumers\\draw_sam_sites.lua", "consumers\\spawn_static_objects.lua",
        "consumers\\draw_fixed_ground_targets.lua", "consumers\\draw_convoys.lua",
        "consumers\\spawn_aircraft_groups.lua", "consumers\\preload_aircraft_types.lua",
        "consumers\\schedule_air_tasking_orders.lua", "consumers\\track_radar_picture.lua",
        "consumers\\control_air_flights\\assess_flight_situations.lua",
        "consumers\\control_air_flights\\directives_per_flight.lua",
        "consumers\\control_air_flights\\coordinate_flights.lua",
        "consumers\\control_air_flights\\give_orders.lua",
        "consumers\\control_air_flights\\track_alert_jets.lua",
        "consumers\\control_air_flights\\decide_launches.lua",
        "consumers\\control_air_flights\\scramble_fighters.lua",
        "consumers\\control_air_flights\\control_air_flights.lua",
        "consumers\\sleep_ground_units.lua", "consumers\\draw_air_tasking_orders.lua",
        "consumers\\brief_air_tasking.lua", "consumers\\call_air_picture.lua", "consumers\\send_radio_calls.lua",
        "consumers\\create_airfields_brief.lua", "consumers\\announce_flight_activity.lua",
        "consumers\\announce_controller_orders.lua", "consumers\\track_airfield_traffic.lua",
    },
}

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
    if not load(F, "config.lua") then return false end
    if not loadAll(F, FRAMEWORK_FILES.lib) then return false end

    Log.info("============================================")
    Log.info("  " .. MISSION.name .. " loading")
    Log.info("  " .. M)
    Log.info("============================================")

    if not loadAll(F, FRAMEWORK_FILES.data) then return false end
    if not loadAll(M, MISSION.data_files or {}) then return false end

    if not loadAll(F, FRAMEWORK_FILES.stages) then return false end
    if not loadAll(F, FRAMEWORK_FILES.consumers) then return false end
    if CONFIG.SURVEY_FOOTPRINTS and not load(F, "survey\\survey_airbase_footprints.lua") then return false end
    if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN and not load(F, "survey\\probe_parked_aircraft_spawn.lua") then return false end

    -- data files checked against each other and the unit pool before anything runs
    PlanBaseDefenses.checkData()
    PlanSamSites.checkData()
    PlanFixedGroundTargets.checkData()
    PlanConvoys.checkData()
    PlanAirTasking.checkData()
    return true
end
