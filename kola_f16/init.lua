-- Kola F-16 generator: entry point.
-- Loaded by one ME trigger:  ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- Load order: config → lib → data → gather → stages → consumers, then after a short
-- delay: gather inputs → stages 1..7 → plan dump → hand the plan to each consumer.

local SCRIPT_DIR = lfs.writedir() .. "Scripts\\kola_f16\\"

local function load(rel)
    local ok, err = pcall(dofile, SCRIPT_DIR .. rel)
    if not ok then
        env.info("[KOLA] FATAL: could not load " .. rel .. ": " .. tostring(err))
        trigger.action.outText("KOLA SCRIPT LOAD ERROR — " .. rel .. "\n" .. tostring(err), 60)
    end
    return ok
end

if not load("config.lua")                  then return end
if not load("lib\\util.lua")               then return end
if not load("lib\\logger.lua")             then return end
if not load("lib\\weather.lua")            then return end
if not load("lib\\placement.lua")          then return end

Log.info("============================================")
Log.info("  Kola F-16 generator loading")
Log.info("  " .. SCRIPT_DIR)
Log.info("============================================")

if not load("data\\clusters.lua")          then return end
if not load("data\\zones.lua")             then return end
if not load("data\\cloud_presets.lua")     then return end
if not load("data\\unit_pool.lua")         then return end
if not load("data\\airbase_codes.lua")     then return end
if not load("data\\airbase_classes.lua")   then return end
if not load("data\\base_defense_levels.lua")      then return end
if not load("data\\base_defense_composition.lua") then return end
if not load("data\\base_defense_placement.lua")   then return end
if not load("data\\coalition_rosters.lua")        then return end
if not load("data\\airbase_footprints.lua")       then return end
if not load("data\\forested_airfields.lua")       then return end
if not load("data\\sam_site_recipes.lua")         then return end
if not load("data\\sam_site_density.lua")         then return end
if not load("data\\fixed_ground_target_recipes.lua") then return end
if not load("data\\fixed_ground_target_density.lua") then return end
if not load("data\\convoy_recipes.lua")           then return end
if not load("gather.lua")                  then return end
if not load("stages\\roll_territory.lua")  then return end
if not load("stages\\plan_base_defenses.lua")     then return end
if not load("stages\\plan_sam_sites.lua")         then return end
if not load("stages\\plan_fixed_ground_targets.lua") then return end
if not load("stages\\plan_convoys.lua")           then return end
if not load("stages\\catalog_targets.lua")        then return end
if not load("consumers\\territory.lua")    then return end
if not load("consumers\\spawn_ground_groups.lua") then return end
if not load("consumers\\draw_base_defenses.lua")  then return end
if not load("consumers\\draw_sam_sites.lua")      then return end
if not load("consumers\\spawn_static_objects.lua") then return end
if not load("consumers\\draw_fixed_ground_targets.lua") then return end
if not load("consumers\\draw_convoys.lua")        then return end
if CONFIG.SURVEY_FOOTPRINTS and not load("survey\\survey_airbase_footprints.lua") then return end
if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN and not load("survey\\probe_parked_aircraft_spawn.lua") then return end

-- Data files checked against each other and the unit pool before anything runs.
PlanBaseDefenses.checkData()
PlanSamSites.checkData()
PlanFixedGroundTargets.checkData()
PlanConvoys.checkData()

-- ── Run sequence ────────────────────────────────────────────────

local function dumpPlan(plan)
    if not CONFIG.PLAN_DUMP then return end
    local path = Util.writeFile(CONFIG.PLAN_DUMP_FILE, "plan = " .. Util.serialize(plan) .. "\n")
    if path then Log.info("Plan written to " .. path) end
end

local function run()
    if CONFIG.SHOW_WEATHER_DEBUG then Log.dumpWeather() end

    local plan = { world = Gather.run() }
    if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN then
        ProbeParkedAircraftSpawn.run(plan.world)
        return
    end
    if CONFIG.SURVEY_FOOTPRINTS then SurveyAirbaseFootprints.run(plan.world) end
    RollTerritory.run(plan)
    PlanBaseDefenses.run(plan)
    PlanSamSites.run(plan)
    PlanFixedGroundTargets.run(plan)
    PlanConvoys.run(plan)
    CatalogTargets.run(plan)   -- after every stage that plans targets
    -- stages 5..7 go here

    dumpPlan(plan)

    Territory.apply(plan)
    -- KEEP THIS ORDER: every static object before any AI unit. Spawned after ~800 AI
    -- units, each parked aircraft took ~3 s inside addStaticObject (a 3-minute stall at
    -- start); spawned first, 247 objects took 7.4 s and the units were no slower
    -- (2026-09-24). New stages that spawn static objects add them here, above the groups.
    SpawnStaticObjects.run(plan.fixed_ground_targets.static_objects, "fixed ground target objects")
    SpawnGroundGroups.run(plan.base_defenses.groups, "base defenses")
    SpawnGroundGroups.run(plan.sam_sites.groups, "SAM sites")
    SpawnGroundGroups.run(plan.fixed_ground_targets.groups, "fixed ground target units")
    SpawnGroundGroups.run(plan.convoys.groups, "convoys")
    DrawBaseDefenses.apply(plan)
    DrawSamSites.apply(plan)
    DrawFixedGroundTargets.apply(plan)
    DrawConvoys.apply(plan)
    local text = Territory.summaryText(plan) .. "\n" .. DrawBaseDefenses.summaryText(plan)
        .. "\n" .. DrawSamSites.summaryText(plan) .. "\n" .. DrawFixedGroundTargets.summaryText(plan)
        .. "\n" .. DrawConvoys.summaryText(plan)
    if CONFIG.SHOW_WEATHER_DEBUG then
        text = text .. "\n\n" .. Weather.summaryText(plan.world)
    end
    trigger.action.outText(text, 120)
    Log.info("Init complete.")
end

timer.scheduleFunction(function()
    local ok, err = pcall(run)
    if not ok then
        Log.error("run() failed: " .. tostring(err))
    end
end, nil, timer.getTime() + CONFIG.START_DELAY)
