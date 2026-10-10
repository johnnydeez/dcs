-- What kind of base each airfield is in wartime — a static fact about the field,
-- independent of who owns it this session. Plain data, no logic.
--
--   hub      major main operating base, large ramp
--   fighter  fighter / interceptor base
--   bomber   long-range aviation, maritime patrol, other large aircraft
--   heli     helicopter base
--   dispersal  any other field whose runway takes jets (at least
--            AIRBASE_CLASS_JET_RUNWAY_M): the air force flies from it in wartime (Finnish
--            and Swedish dispersal doctrine), so it gets an Army air-defense detachment
--   strip    runway too short for any jet we fly (under AIRBASE_CLASS_JET_RUNWAY_M)
--
-- The class sets how a field is defended and what stands on it (stages 2 and 3b), and
-- which fields the heavies (bombers, AWACS) fly from. Fighters and attack jets fly from
-- any held field whose runway and parking fit them (data/aircraft_profiles.lua): in
-- wartime every usable runway is used (John, 2026-09-27). Runway length is what decides
-- strip vs dispersal (John, 2026-09-27); PlannerPlanBaseDefenses warns when a class disagrees
-- with the runway DCS reports. Lengths in the comments are DCS's (gather, 2026-09-27).

AIRBASE_CLASS_JET_RUNWAY_M = 1500   -- the shortest min_runway_m of a jet profile (F-16 / F/A-18)

AIRBASE_CLASS = {
    -- Norway
    ["Bodo"]                   = "hub",        -- 2,627 m
    ["Evenes"]                 = "bomber",     -- 2,525 m; P-8 maritime patrol since 2023, plus F-35 alert
    ["Andoya"]                 = "dispersal",  -- 2,332 m; air station (maritime patrol moved to Evenes in 2023)
    ["Bardufoss"]              = "heli",       -- 1,957 m; helicopter wing
    ["Tromso"]                 = "dispersal",  -- 1,881 m
    ["Banak"]                  = "dispersal",  -- 2,462 m; military air station
    ["Alta"]                   = "strip",      -- 1,490 m
    ["Kirkenes"]               = "dispersal",  -- 1,795 m; on the Russian border

    -- Sweden
    ["Kallax"]                 = "fighter",    -- 3,233 m; F 21
    ["Vidsel"]                 = "dispersal",  -- 2,111 m
    ["Kiruna"]                 = "dispersal",  -- 2,266 m
    ["Jokkmokk"]               = "dispersal",  -- 1,922 m
    ["Kalixfors"]              = "strip",      -- 1,097 m
    ["Arvidsjaur"]             = "dispersal",  -- 2,344 m
    ["Hemavan"]                = "strip",      -- 1,405 m
    ["Boden Heli Base"]        = "heli",       --   299 m

    -- Finland
    ["Rovaniemi"]              = "fighter",    -- 2,773 m; Lapland Air Command
    ["Kemi Tornio"]            = "dispersal",  -- 2,397 m
    ["Kuusamo"]                = "dispersal",  -- 2,226 m
    ["Ivalo"]                  = "dispersal",  -- 2,074 m
    ["Kittila"]                = "dispersal",  -- 2,200 m
    ["Enontekio"]              = "dispersal",  -- 1,814 m
    ["Sodankyla"]              = "strip",      -- 1,368 m
    ["Hosio"]                  = "dispersal",  -- 1,724 m
    ["Vuojarvi"]               = "dispersal",  -- 2,353 m

    -- Russia
    ["Murmansk International"] = "hub",        -- 2,416 m
    ["Severomorsk-1"]          = "bomber",     -- 2,769 m; naval aviation
    ["Severomorsk-3"]          = "fighter",    -- 2,307 m
    ["Olenya"]                 = "bomber",     -- 3,311 m; long-range aviation
    ["Monchegorsk"]            = "fighter",    -- 2,289 m
    ["Kilpyavr"]               = "fighter",    -- 2,205 m
    ["Luostari Pechenga"]      = "heli",       -- 1,216 m
    ["Afrikanda"]              = "dispersal",  -- 2,324 m; former military air base
    ["Koshka Yavr"]            = "dispersal",  -- 2,799 m; disused military field
    ["Alakurtti"]              = "dispersal",  -- 2,068 m; former military air base
    ["Kalevala"]               = "strip",      --   568 m
    ["Poduzhemye"]             = "dispersal",  -- 2,240 m; former military field
}
