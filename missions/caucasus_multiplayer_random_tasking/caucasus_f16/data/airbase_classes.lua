-- What kind of base each airfield is in wartime — a static fact about the field,
-- independent of who owns it this session. Plain data, no logic.
--
--   hub      major main operating base, large ramp
--   fighter  fighter / interceptor base
--   bomber   long-range aviation, maritime patrol, other large aircraft
--   heli     helicopter base
--   dispersal  any other field whose runway takes jets (at least
--            AIRBASE_CLASS_JET_RUNWAY_M): the air force flies from it in wartime
--   strip    runway too short for any jet we fly (under AIRBASE_CLASS_JET_RUNWAY_M)
--
-- The class sets how a field is defended and what stands on it (stages 2 and 3b), and
-- which fields the heavies (bombers, AWACS) fly from: Red's Tu-22M3 needs a bomber field
-- with 2,500 m of runway (Mineralnye Vody), the A-50 and B-1B a hub or bomber field with
-- 2,500 m, the E-3A one with 2,300 m (Tbilisi-Lochini; no Blue field reaches 2,500 m in DCS,
-- so Blue has no B-1B here). Fighters and attack jets fly from any held
-- field whose runway and parking fit them (data/aircraft_profiles.lua). Runway length is
-- what decides strip vs dispersal; PlannerPlanBaseDefenses warns when a class disagrees with the
-- runway DCS reports.
--
-- Caucasus (agreed with John, 2026-10-06). Lengths in the comments are DCS's longest runway
-- (gather, first run 2026-10-06 21:27).

AIRBASE_CLASS_JET_RUNWAY_M = 1500   -- the shortest min_runway_m of a jet profile (F-16 / F/A-18)

AIRBASE_CLASS = {
    -- Georgia
    ["Tbilisi-Lochini"]      = "hub",        -- 2,345 m; Georgia's main field
    ["Vaziani"]              = "fighter",    -- 2,391 m; former Soviet fighter base, NATO exercises
    ["Soganlug"]             = "heli",       -- 2,399 m; Georgian helicopters
    ["Batumi"]               = "dispersal",  -- 2,070 m
    ["Kobuleti"]             = "dispersal",  -- 2,258 m; former naval aviation field
    ["Kutaisi"]              = "hub",        -- 2,419 m; Georgia's western hub
    ["Senaki-Kolkhi"]        = "dispersal",  -- 2,212 m

    -- Abkhazia
    ["Sukhumi-Babushara"]    = "dispersal",  -- 3,419 m
    ["Gudauta"]              = "heli",       -- 2,390 m; Russian base, helicopters

    -- Russia
    ["Mozdok"]               = "fighter",    -- 2,357 m; long-range aviation in reality, but DCS's runway is short of the Tu-22M3's 2,500 m
    ["Mineralnye Vody"]      = "bomber",     -- 3,754 m; the region's biggest runway: the Tu-22M3s and the A-50 (John, 2026-10-06)
    ["Krymsk"]               = "fighter",    -- 2,052 m; Su-27 / Su-30 regiment
    ["Krasnodar-Center"]     = "fighter",    -- 2,335 m
    ["Maykop-Khanskaya"]     = "fighter",    -- 3,108 m
    ["Krasnodar-Pashkovsky"] = "dispersal",  -- 2,968 m
    ["Anapa-Vityazevo"]      = "dispersal",  -- 2,629 m
    ["Sochi-Adler"]          = "dispersal",  -- 2,952 m
    ["Beslan"]               = "dispersal",  -- 2,843 m
    ["Nalchik"]              = "dispersal",  -- 2,048 m
    ["Novorossiysk"]         = "dispersal",  -- 1,719 m
    ["Gelendzhik"]           = "dispersal",  -- 1,662 m
}
