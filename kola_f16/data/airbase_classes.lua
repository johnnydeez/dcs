-- What kind of base each airfield is — a static fact about the field, independent of
-- who owns it this session. Plain data, no logic.
--
--   hub      major main operating base, large ramp
--   fighter  fighter / interceptor base
--   bomber   long-range aviation, maritime patrol, other large aircraft
--   heli     helicopter base
--   strip    secondary / civil / dispersal field
--
-- DRAFT (2026-09-23): first pass from each field's real-world role; re-classify freely.

AIRBASE_CLASS = {
    -- Norway
    ["Bodo"]                   = "hub",
    ["Evenes"]                 = "fighter",
    ["Andoya"]                 = "bomber",
    ["Bardufoss"]              = "heli",
    ["Tromso"]                 = "strip",
    ["Banak"]                  = "strip",
    ["Alta"]                   = "strip",
    ["Kirkenes"]               = "strip",

    -- Sweden
    ["Kallax"]                 = "fighter",
    ["Vidsel"]                 = "strip",
    ["Kiruna"]                 = "strip",
    ["Jokkmokk"]               = "strip",
    ["Kalixfors"]              = "strip",
    ["Arvidsjaur"]             = "strip",
    ["Hemavan"]                = "strip",
    ["Boden Heli Base"]        = "heli",

    -- Finland
    ["Rovaniemi"]              = "fighter",
    ["Kemi Tornio"]            = "strip",
    ["Kuusamo"]                = "strip",
    ["Ivalo"]                  = "strip",
    ["Kittila"]                = "strip",
    ["Enontekio"]              = "strip",
    ["Sodankyla"]              = "strip",
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
