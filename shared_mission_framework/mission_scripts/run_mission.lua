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
    -- this run's event log (MISSION.event_log_folder): the plan at its top, then
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
    -- where each bomb and air-to-ground missile from an aircraft came down, and what it did
    -- to what was there (event log: IMPACT)
    TrackWeaponImpacts.start()
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
    -- Darkstar's orders to the AI flights: a listener of the controller's decisions (the
    -- controller itself knows nothing of the radio)
    AnnounceControllerOrders.start()
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

function RunMission.start()
    timer.scheduleFunction(function()
        local ok, err = pcall(run)
        if not ok then
            Log.error("run() failed: " .. tostring(err))
        end
    end, nil, timer.getTime() + CONFIG.START_DELAY)
end
