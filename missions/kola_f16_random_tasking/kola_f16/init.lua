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
if not load("lib\\threat_routing.lua")     then return end
if not load("lib\\sam_reach.lua")          then return end
if not load("lib\\flight_callsigns.lua")   then return end

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
if not load("data\\player_slots.lua")      then return end
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
if not load("data\\aircraft_profiles.lua")        then return end
if not load("data\\aircraft_loadouts.lua")        then return end
if not load("data\\air_tasking.lua")              then return end
if not load("data\\flight_callsigns.lua")         then return end
if not load("data\\airspace.lua")                 then return end
if not load("data\\radar_picture.lua")            then return end
if not load("data\\air_picture_calls.lua")        then return end
if not load("data\\radio_calls.lua")              then return end
if not load("data\\airfield_frequencies.lua")     then return end
if not load("data\\air_control.lua")              then return end
if not load("data\\event_log.lua")                then return end
if not load("data\\ground_unit_sleep.lua")        then return end
if not load("gather.lua")                  then return end
if not load("stages\\roll_territory.lua")  then return end
if not load("stages\\plan_base_defenses.lua")     then return end
if not load("stages\\plan_sam_sites.lua")         then return end
if not load("stages\\divide_airspace.lua")        then return end
if not load("stages\\plan_fixed_ground_targets.lua") then return end
if not load("stages\\plan_convoys.lua")           then return end
if not load("stages\\catalog_targets.lua")        then return end
if not load("stages\\plan_air_tasking.lua")       then return end
if not load("consumers\\write_event_log.lua") then return end
if not load("consumers\\territory.lua")    then return end
if not load("consumers\\draw_airspace.lua")       then return end
if not load("consumers\\spawn_ground_groups.lua") then return end
if not load("consumers\\draw_base_defenses.lua")  then return end
if not load("consumers\\draw_sam_sites.lua")      then return end
if not load("consumers\\spawn_static_objects.lua") then return end
if not load("consumers\\draw_fixed_ground_targets.lua") then return end
if not load("consumers\\draw_convoys.lua")        then return end
if not load("consumers\\spawn_aircraft_groups.lua") then return end
if not load("consumers\\preload_aircraft_types.lua") then return end
if not load("consumers\\schedule_air_tasking_orders.lua") then return end
if not load("consumers\\track_radar_picture.lua") then return end
if not load("consumers\\control_air_flights\\assess_flight_situations.lua") then return end
if not load("consumers\\control_air_flights\\directives_per_flight.lua")    then return end
if not load("consumers\\control_air_flights\\coordinate_flights.lua")       then return end
if not load("consumers\\control_air_flights\\give_orders.lua")              then return end
if not load("consumers\\control_air_flights\\track_alert_jets.lua")         then return end
if not load("consumers\\control_air_flights\\decide_launches.lua")          then return end
if not load("consumers\\control_air_flights\\scramble_fighters.lua")        then return end
if not load("consumers\\control_air_flights\\control_air_flights.lua")      then return end
if not load("consumers\\sleep_ground_units.lua")  then return end
if not load("consumers\\draw_air_tasking_orders.lua") then return end
if not load("consumers\\brief_air_tasking.lua")   then return end
if not load("consumers\\call_air_picture.lua")    then return end
if not load("consumers\\send_radio_calls.lua")    then return end
if not load("consumers\\create_airfields_brief.lua") then return end
if not load("consumers\\announce_flight_activity.lua") then return end
if not load("consumers\\track_airfield_traffic.lua") then return end
if CONFIG.SURVEY_FOOTPRINTS and not load("survey\\survey_airbase_footprints.lua") then return end
if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN and not load("survey\\probe_parked_aircraft_spawn.lua") then return end

-- Data files checked against each other and the unit pool before anything runs.
PlanBaseDefenses.checkData()
PlanSamSites.checkData()
PlanFixedGroundTargets.checkData()
PlanConvoys.checkData()
PlanAirTasking.checkData()

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
    DivideAirspace.run(plan)   -- Blue / Red / contested, from held ground + SAM reach
    PlanFixedGroundTargets.run(plan)
    PlanConvoys.run(plan)
    CatalogTargets.run(plan)   -- after every stage that plans targets
    PlanAirTasking.run(plan)   -- stages 5–6: reads only the catalog for targets
    -- stage 7 (brief) goes here

    dumpPlan(plan)
    -- this run's event log (Saved Games\DCS\kola_event_logs\): the plan at its top, then
    -- every event of the air war as it happens
    WriteEventLog.open(plan)

    DrawAirspace.apply(plan)   -- first, so the filled areas lie under every other mark
    Territory.apply(plan)
    -- KEEP THIS ORDER: every static object before any AI unit. Spawned after ~800 AI
    -- units, each parked aircraft took ~3 s inside addStaticObject (a 3-minute stall at
    -- start); spawned first, 247 objects took 7.4 s and the units were no slower
    -- (2026-09-24). New stages that spawn static objects add them here, above the groups.
    SpawnStaticObjects.run(plan.fixed_ground_targets.static_objects, "fixed ground target objects")
    SpawnGroundGroups.run(plan.base_defenses.groups, "base defenses")
    -- medium and long-range SAM sites (not their escorts) show their threat ring on the
    -- F-16's HSD; the HSD takes ~16 threats, Red fields ~11 such sites (2026-10-02)
    -- Red's SAM sites (every group, escorts too) spawn as Russia, not CJTF Red: the
    -- Caucasus test SA-11 whose ring showed was Russia (bug 25, 2026-10-02; every Red
    -- system is Russian-made)
    local samsOnMfd, samCountry = {}, {}
    for _, s in ipairs(plan.sam_sites.sites or {}) do
        if s.layer == "medium_range" or s.layer == "long_range" then samsOnMfd[s.id] = true end
        if s.side == "red" then
            for _, gid in ipairs(s.group_ids or { s.id }) do samCountry[gid] = "RUSSIA" end
        end
    end
    SpawnGroundGroups.run(plan.sam_sites.groups, "SAM sites", { show_on_mfd = samsOnMfd, country = samCountry })
    SpawnGroundGroups.run(plan.fixed_ground_targets.groups, "fixed ground target units")
    SpawnGroundGroups.run(plan.convoys.groups, "convoys")
    DrawBaseDefenses.apply(plan)
    DrawSamSites.apply(plan)
    DrawFixedGroundTargets.apply(plan)
    DrawConvoys.apply(plan)
    -- Every aircraft type the flights use is spawned once and removed now: a type's first
    -- spawn freezes the sim for seconds (F-15E ~25 s), so it happens here, during start-up,
    -- not mid-mission.
    PreloadAircraftTypes.run(plan)
    -- DCS events to the event log from here on: after the preload (its spawns aren't part
    -- of the story), before the first flight spawns
    WriteEventLog.start()
    -- callsigns given at run time (scrambles, SEAD retries) carry on from the plan's numbers
    FlightCallsigns.start(plan)
    -- the mission clock: each planned flight is due at its start time, and the controller
    -- decides then whether it launches
    ScheduleAirTaskingOrders.start(plan)
    -- each coalition's radar picture: what its radars report, kept as the mission runs
    -- (event log: CONTACT, PICTURE). Before the controller, which runs on it.
    TrackRadarPicture.start(plan)
    -- the controller: every run-time decision about AI flights — launches in sequence,
    -- scrambles (nothing scrambles unless AIR_DEFENSE.alert_posture_planned planned alert
    -- bases), the leash, SEAD going cold, attack flights defending themselves (event log: CONTROL)
    ControlAirFlights.start(plan)
    -- base defenses that reach under ~10 km sleep (AI off) until an enemy aircraft is near
    -- their base (event log: UNIT_AWAKE, UNIT_ASLEEP); CONFIG.SLEEP_GROUND_UNITS = false
    -- keeps every unit awake
    SleepGroundUnits.start(plan)
    DrawAirTaskingOrders.apply(plan)
    -- every 2 min each player gets their coalition's radar picture as a BRAA list from
    -- their own position, highest threat first (event log: PICTURE_CALL). Before the
    -- airfield brief, which reads the magnetic variation it loads.
    CallAirPicture.start(plan)
    -- the radio calls (roadmap item 7): Darkstar's picture and threat calls, and the AI
    -- pilots' calls below; started here with the radio player and helper outside DCS (radio_calls\)
    SendRadioCalls.start()
    -- comms menu, top first: Airfield info (every Blue base: wind, runway in use, next
    -- flights, alert jets), then the human taskings and the air tasking order
    CreateAirfieldsBrief.start(plan)
    BriefAirTasking.start(plan)
    -- the AI pilots talk (roadmap item 7): mission calls from what each flight actually does
    -- (a watcher beside the controller, never its orders), and airfield traffic calls at
    -- Blue fields on each field's frequency; after the airfield brief, whose runways they use
    AnnounceFlightActivity.start(plan)
    TrackAirfieldTraffic.start(plan)
    -- the build summary goes to dcs.log; the screen shows only the weather and the human
    -- taskings (John, session 10)
    local text = Territory.summaryText(plan) .. "\n" .. DrawAirspace.summaryText(plan)
        .. "\n" .. DrawBaseDefenses.summaryText(plan)
        .. "\n" .. DrawSamSites.summaryText(plan) .. "\n" .. DrawFixedGroundTargets.summaryText(plan)
        .. "\n" .. DrawConvoys.summaryText(plan) .. "\n" .. DrawAirTaskingOrders.summaryText(plan)
    if CONFIG.SHOW_WEATHER_DEBUG then
        text = text .. "\n\n" .. Weather.summaryText(plan.world)
    end
    Log.info("Build summary:\n" .. text)
    BriefAirTasking.showStart(plan)
    Log.info("Init complete.")
end

timer.scheduleFunction(function()
    local ok, err = pcall(run)
    if not ok then
        Log.error("run() failed: " .. tostring(err))
    end
end, nil, timer.getTime() + CONFIG.START_DELAY)
