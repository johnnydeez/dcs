-- What kind of base each airfield is — a static fact about the field, independent of
-- who owns it this session. Plain data, no logic.
--
--   hub      major main operating base, large ramp
--   fighter  fighter / interceptor base
--   bomber   long-range aviation, maritime patrol, other large aircraft
--   heli     helicopter base
--   dispersal  secondary field the air force flies fighters from in wartime (Finnish
--            and Swedish dispersal doctrine): gets an Army air-defense detachment
--   strip    civil or disused field with no wartime flying role
--
-- DRAFT (2026-09-23): first pass from each field's real-world role; re-classify freely.

AIRBASE_CLASS = {
    -- Norway
    ["Bodo"]                   = "hub",
    ["Evenes"]                 = "bomber",    -- P-8 maritime patrol base since 2023, plus F-35 alert
    ["Andoya"]                 = "strip",     -- maritime patrol moved to Evenes in 2023
    ["Bardufoss"]              = "heli",
    ["Tromso"]                 = "strip",
    ["Banak"]                  = "strip",
    ["Alta"]                   = "strip",
    ["Kirkenes"]               = "strip",

    -- Sweden
    ["Kallax"]                 = "fighter",
    ["Vidsel"]                 = "dispersal",
    ["Kiruna"]                 = "strip",
    ["Jokkmokk"]               = "dispersal",
    ["Kalixfors"]              = "dispersal",
    ["Arvidsjaur"]             = "strip",
    ["Hemavan"]                = "strip",
    ["Boden Heli Base"]        = "heli",

    -- Finland
    ["Rovaniemi"]              = "fighter",
    ["Kemi Tornio"]            = "strip",
    ["Kuusamo"]                = "dispersal",
    ["Ivalo"]                  = "dispersal",
    ["Kittila"]                = "dispersal",
    ["Enontekio"]              = "dispersal",
    ["Sodankyla"]              = "dispersal",
    ["Hosio"]                  = "strip",
    ["Vuojarvi"]               = "strip",

    -- Russia
    ["Murmansk International"] = "hub",
    ["Severomorsk-1"]          = "bomber",
    ["Severomorsk-3"]          = "fighter",
    ["Olenya"]                 = "bomber",
    ["Monchegorsk"]            = "fighter",
    ["Kilpyavr"]               = "fighter",
    ["Luostari Pechenga"]      = "heli",
    ["Afrikanda"]              = "strip",
    ["Koshka Yavr"]            = "strip",
    ["Alakurtti"]              = "strip",
    ["Kalevala"]               = "strip",
    ["Poduzhemye"]             = "strip",
}
