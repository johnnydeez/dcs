-- The run sequence: once everything is loaded (load_framework.lua), a few seconds into the
-- mission (airbase queries return empty at T+0): gather → the stages → the plan dump → each
-- consumer, in this order. The mission's init.lua calls RunMission.start().

RunMission = {}

local function dumpPlan(plan)
    if not CONFIG.PLAN_DUMP then return end
    local path = Util.writeFile(MISSION.plan_dump_file, "plan = " .. Util.serialize(plan) .. "\n")
    if path then Log.info("Plan written to " .. path) end
end

local function run()
    if CONFIG.SHOW_WEATHER_DEBUG then WatchWorldAtStart.dumpWeather() end

    local plan = { world = WatchWorldAtStart.run() }
    if CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN then
        ProbeParkedAircraftSpawn.run(plan.world)
        return
    end
    if CONFIG.SURVEY_FOOTPRINTS then SurveyAirbaseFootprints.run(plan.world) end
    PlannerRollTerritory.run(plan)
    PlannerPlanBaseDefenses.run(plan)
    PlannerPlanSamSites.run(plan)
    PlannerDivideAirspace.run(plan)   -- Blue / Red / contested, from held ground + SAM reach
    PlannerPlanFixedGroundTargets.run(plan)
    PlannerPlanConvoys.run(plan)
    PlannerCatalogTargets.run(plan)   -- after every stage that plans targets
    PlannerPlanAirTasking.run(plan)   -- stages 5–6: reads only the catalog for targets
    -- stage 7 (brief) goes here

    dumpPlan(plan)
    -- this run's event log (MISSION.event_log_folder): the plan at its top, then
    -- every event of the air war as it happens
    EventLog.open(plan)

    InformMapAirspace.apply(plan)   -- first, so the filled areas lie under every other mark
    InformMapTerritory.apply(plan, ExecuteBaseCoalitions.apply(plan))
    -- KEEP THIS ORDER: every static object before any AI unit. Spawned after ~800 AI
    -- units, each parked aircraft took ~3 s inside addStaticObject (a 3-minute stall at
    -- start); spawned first, 247 objects took 7.4 s and the units were no slower
    -- (2026-09-24). New stages that spawn static objects add them here, above the groups.
    ExecuteSpawnStaticObjects.run(plan.fixed_ground_targets.static_objects, "fixed ground target objects")
    ExecuteSpawnGroundGroups.run(plan.base_defenses.groups, "base defenses")
    -- medium and long-range SAM sites (not their escorts) show their threat ring on the
    -- F-16's HSD; the HSD takes ~16 threats, Red fields ~11 such sites (2026-10-02)
    -- a coalition's SAM sites (every group, escorts too) spawn as the country the mission
    -- names (MISSION.sam_site_country; Kola: Red as Russia, not CJTF Red: the Caucasus test
    -- SA-11 whose ring showed was Russia, bug 25, 2026-10-02)
    local samsOnMfd, samCountry = {}, {}
    for _, s in ipairs(plan.sam_sites.sites or {}) do
        if s.layer == "medium_range" or s.layer == "long_range" then samsOnMfd[s.id] = true end
        local countryName = MISSION.sam_site_country and MISSION.sam_site_country[s.side]
        if countryName then
            for _, gid in ipairs(s.group_ids or { s.id }) do samCountry[gid] = countryName end
        end
    end
    ExecuteSpawnGroundGroups.run(plan.sam_sites.groups, "SAM sites", { show_on_mfd = samsOnMfd, country = samCountry })
    ExecuteSpawnGroundGroups.run(plan.fixed_ground_targets.groups, "fixed ground target units")
    ExecuteSpawnGroundGroups.run(plan.convoys.groups, "convoys")
    InformMapBaseDefenses.apply(plan)
    InformMapSamSites.apply(plan)
    InformMapFixedGroundTargets.apply(plan)
    InformMapConvoys.apply(plan)
    -- Every aircraft type the flights use is spawned once and removed now: a type's first
    -- spawn freezes the sim for seconds (F-15E ~25 s), so it happens here, during start-up,
    -- not mid-mission.
    ExecutePreloadAircraftTypes.run(plan)
    -- DCS's events, the one place they come in (watch\dcs_events.lua; rule 13), and to the
    -- event log from here on: after the preload (its spawns aren't part of the story),
    -- before the first flight spawns
    WatchDcsEvents.start()
    EventLog.start()
    -- where each bomb and air-to-ground missile from an aircraft came down, and what it did
    -- to what was there (event log: IMPACT)
    WatchWeaponImpacts.start()
    -- callsigns given at run time (scrambles, SEAD retries) carry on from the plan's numbers
    RecordCallsigns.start(plan)
    -- what happens to each flight (takeoffs, landings, losses, target progress), then the
    -- mission clock: each planned flight is due at its start time, and the controller
    -- decides then whether it launches
    WatchFlights.start(plan)
    ControllerScheduleFlights.start(plan)
    -- threats out of the fight (a SAM site's radars destroyed), for the launch gate and
    -- the kill zones
    WatchThreats.start(plan)
    -- what each launched jet carries, read a few seconds after its spawn (LOADOUT lines)
    WatchFlightLoadouts.start()
    -- each coalition's radar picture: what its radars report, kept as the mission runs
    -- (event log: CONTACT, PICTURE). Before the controller, which runs on it.
    WatchRadarPicture.start(plan)
    -- the controller: every run-time decision about AI flights — launches in sequence,
    -- scrambles (nothing scrambles unless AIR_DEFENSE.alert_posture_planned planned alert
    -- bases), the leash, SEAD going cold, attack flights defending themselves (event log: CONTROL)
    WatchFlightSituations.start(plan)
    ControllerDirectFlights.start(plan)
    -- a SEAD flight's radar warning snapshot at its launch and press-on points
    WatchFlightRoutes.start()
    -- missiles fired at and by the watched flights (after the controller, where its handler was)
    WatchShots.start()
    -- base defenses that reach under ~10 km sleep (AI off) until an enemy aircraft is near
    -- their base (event log: UNIT_AWAKE, UNIT_ASLEEP); CONFIG.SLEEP_GROUND_UNITS = false
    -- keeps every unit awake
    ControllerWakeGroundUnits.start(plan)
    GroundUnitsAwakeLog.start()
    InformMapAirTaskingOrders.apply(plan)
    -- every 2 min each player gets their coalition's radar picture as a BRAA list from
    -- their own position, highest threat first (event log: PICTURE_CALL). Before the
    -- airfield brief, which reads the magnetic variation it loads.
    InformScreenAirPicture.start(plan)
    -- the radio calls (roadmap item 7): Darkstar's picture and threat calls, and the AI
    -- pilots' calls below; started here with the radio player and helper outside DCS (radio_calls\)
    InformRadioRadioCalls.start()
    -- comms menu, top first: Airfield info (every Blue base: wind, runway in use, next
    -- flights, alert jets), then the human taskings and the air tasking order
    InformScreenAirfieldInfo.start(plan)
    InformScreenBriefing.start(plan)
    -- the AI pilots talk (roadmap item 7): mission calls from what each flight actually does
    -- (a watcher beside the controller, never its orders), and airfield traffic calls at
    -- Blue fields on each field's frequency; after the airfield brief, whose runways they use
    InformRadioFlightCalls.start(plan)
    InformRadioAirfieldCalls.start(plan)
    -- Darkstar's orders to the AI flights: a listener of the controller's decisions (the
    -- controller itself knows nothing of the radio)
    InformRadioDarkstarOrders.start()
    -- the build summary goes to dcs.log; the screen shows only the weather and the human
    -- taskings (John, session 10)
    local text = BuildSummary.text(plan)
    if CONFIG.SHOW_WEATHER_DEBUG then
        text = text .. "\n\n" .. Weather.summaryText(plan.world)
    end
    Log.info("Build summary:\n" .. text)
    InformScreenBriefing.showStart(plan)
    Log.info("Init complete.")
end

function RunMission.start()
    timer.scheduleFunction(function()
        local ok, err = pcall(run)
        if not ok then
            Log.error("run() failed: " .. tostring(err))
        end
    end, nil, timer.getTime() + CONFIG.START_DELAY)
end
