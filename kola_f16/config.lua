-- Kola F-16 generator: tunables and debug flags. Plain data, no logic.
-- Loaded first so every later file can read CONFIG.

CONFIG = {
    -- Seconds to wait after script load before gathering inputs. Airbase queries
    -- return an empty table at T+0.
    START_DELAY      = 3,

    -- Write the finished plan to Saved Games\DCS\<PLAN_DUMP_FILE> for offline reading.
    PLAN_DUMP        = true,
    PLAN_DUMP_FILE   = "kola_last_plan.lua",

    -- Mission clock offset from UTC for the Kola map (pydcs terrain/kola: +3 h). Needed
    -- to place the sun; DCS start_time is local time.
    UTC_OFFSET_H     = 3,

    -- TEMP: print the derived weather/time block on screen at init so the reads can be
    -- checked against the ME. Remove once the brief owns this.
    SHOW_WEATHER_DEBUG = true,

    -- Stage 1: a base is "frontline" if an enemy base is within this range; two
    -- opposing clusters are "adjacent" if any base pair is within it.
    FRONT_RANGE_KM   = 200,

    -- Force a contested cluster to a side for testing: { LAPLAND_NORTH = "red" }.
    FORCE_CLUSTER    = {},

    -- Map drawing (debug view of the plan).
    DRAW_BASE_RADIUS = 10000,   -- m, territory circle at each base
    DRAW_ZONE_RADIUS = 3000,    -- m, zones are 30-150 m wide and invisible at map scale
    DRAW_ZONE_LABELS = true,
}
