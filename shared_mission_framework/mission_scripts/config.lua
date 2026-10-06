-- Shared mission framework: tunables and debug flags, the shared defaults. Plain data, no logic.
-- Loaded first (after the mission's MISSION) so every later file can read CONFIG.

CONFIG = {
    -- Seconds to wait after script load before gathering inputs. Airbase queries
    -- return an empty table at T+0.
    START_DELAY      = 3,

    -- Write the finished plan to Saved Games\DCS\<MISSION.plan_dump_file> for offline reading.
    PLAN_DUMP        = true,

    -- (The mission clock's offset from UTC is the map's: MISSION.utc_offset_h.)

    -- Add the derived weather/time block (as read from the ME) to the build summary in
    -- dcs.log. The screen shows the brief's short weather (consumers/brief_air_tasking.lua).
    SHOW_WEATHER_DEBUG = true,

    -- Warnings also on screen (errors always are). Off since session 10: the screen is
    -- for the player's brief; warnings are in dcs.log.
    WARNINGS_ON_SCREEN = false,

    -- Stage 1: a base is "frontline" if an enemy base is within this range; two
    -- opposing clusters are "adjacent" if any base pair is within it.
    FRONT_RANGE_KM   = 200,

    -- Force a contested cluster to a side for testing: { LAPLAND_NORTH = "red" }.
    FORCE_CLUSTER    = {},

    -- Stage 1 echelon by distance to the nearest enemy base: front ≤ FRONT, mid ≤ MID,
    -- rear beyond.
    ECHELON_FRONT_KM = 100,
    ECHELON_MID_KM   = 200,

    -- Stage 2: plan base defenses only at these bases (testing). Empty = every base.
    DEFENSE_TEST_BASES = {},

    -- Placement exclusions (lib/placement.lua). A spawn point is rejected if it lies
    -- inside a runway box (runway + SIDE either side, + END past each end), within
    -- PARKING of any parking spot, or if any of 9 surface samples on a SAMPLE-radius
    -- ring around it is runway or water.
    CLEAR_RUNWAY_SIDE_M = 100,
    CLEAR_RUNWAY_END_M  = 400,
    CLEAR_PARKING_M     = 60,
    CLEAR_SAMPLE_M      = 40,
    -- Forested fields only (data/forested_airfields.lua): past each runway end, only the
    -- approach lane — runway width plus this either side — is kept clear; units spread
    -- at most FORESTED_SPREAD_M from their group centre (the cleared overrun is narrow).
    CLEAR_APPROACH_LANE_M = 15,
    FORESTED_SPREAD_M     = 30,
    -- Road fallback: a group that finds no clear open ground goes onto an airfield road
    -- instead — a road within this distance of a runway's box (the field's own
    -- perimeter and access roads). Roads are open by construction; trees aren't.
    ROAD_FALLBACK_RUNWAY_M = 800,

    -- Base defenses that reach under ~10 km sleep (AI off) until an enemy aircraft comes
    -- near their base (consumers/sleep_ground_units.lua, data/ground_unit_sleep.lua).
    -- false: every ground unit stays awake all mission, to compare a run without it.
    SLEEP_GROUND_UNITS = true,

    -- Map drawing (debug view of the plan).
    DRAW_BASE_RADIUS = 10000,   -- m, territory circle at each base
    DRAW_ZONE_RADIUS = 3000,    -- m, zones are 30-150 m wide and invisible at map scale
    DRAW_ZONE_LABELS = true,
    DRAW_DEFENSES    = true,    -- label every base-defense group + a level ring per base
    DRAW_ANCHORS     = false,   -- dot every placement anchor at defended bases (by kind)
    DRAW_SAM_SITES   = true,    -- label every SAM / early-warning site
    DRAW_SAM_RINGS   = true,    -- engagement ring per SAM site, detection ring per EW site
    DRAW_FIXED_GROUND_TARGETS = true,   -- label + ring per fixed ground target site
    DRAW_CONVOYS     = true,    -- planned route line + start and parking labels per convoy
    DRAW_AIR_TASKING_ORDERS = true,   -- planned route line + target label per flight
    DRAW_AIRSPACE    = true,    -- Blue / Red / contested airspace filled, plus the front line

    -- One-off: survey every airfield's footprint (aprons, airfield buildings) and write
    -- Saved Games\DCS\kola_airbase_footprints.lua; copy it to data\airbase_footprints.lua
    -- and set this back to false. See survey/survey_airbase_footprints.lua.
    SURVEY_FOOTPRINTS = false,

    -- One-off: time how long parked aircraft take to spawn as static objects under
    -- different countries / liveries (survey/probe_parked_aircraft_spawn.lua). When true,
    -- the mission runs only the probe — nothing else is planned or spawned.
    PROBE_PARKED_AIRCRAFT_SPAWN = false,
}
