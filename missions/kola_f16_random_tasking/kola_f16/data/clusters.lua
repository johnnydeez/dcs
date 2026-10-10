-- Kola base clusters: which airbases move together when territory is rolled.
-- Plain data, no logic. Consumed by stage 1 (territory) and by map_data_tools/miz_zones.py
-- to suggest a cluster for each trigger zone.
--
--   fixed        = "blue" | "red"  → never rolled
--   fixed        = nil             → contested, rolled each session
--   p_red        = probability a contested cluster rolls Red (default 0.5)
--   requires_red = id of a shallower cluster; this one can only roll Red if that one
--                  already did, so the front stays contiguous. Clusters are evaluated
--                  in file order, so list the dependency first.
--
-- Airbase name strings must match DCS exactly — verify with WatchWorldAtStart.dumpAirbases().

CLUSTERS = {

    -- ── Always Blue ──────────────────────────────────────────
    {
        id    = "NORWAY_REAR",
        name  = "Northern Norway (NATO Rear)",
        fixed = "blue",
        bases = { "Bodo", "Evenes", "Andoya", "Bardufoss", "Tromso" },
    },
    {
        id    = "SWEDEN",
        name  = "Sweden",
        fixed = "blue",
        bases = { "Kallax", "Vidsel", "Kiruna", "Jokkmokk", "Kalixfors", "Arvidsjaur", "Hemavan", "Boden Heli Base" },
    },
    {
        id    = "FINLAND_SOUTH",
        name  = "Southern Finnish Lapland (Kemi-Tornio)",
        fixed = "blue",
        bases = { "Kemi Tornio" },         -- Rovaniemi and Hosio roll since session 10 (deep tier)
    },

    -- ── Contested: border tier (independent rolls) ───────────
    {
        id    = "FINNMARK_EAST",
        name  = "Eastern Finnmark (Kirkenes)",
        fixed = nil,
        p_red = 0.7,                        -- 56 km from Luostari; first to fall
        bases = { "Kirkenes" },
    },
    {
        id    = "LAPLAND_EAST",
        name  = "Eastern Finnish Lapland (Ivalo corridor)",
        fixed = nil,
        p_red = 0.5,
        bases = { "Ivalo", "Sodankyla", "Vuojarvi" },
    },
    {
        id    = "FINLAND_EAST",
        name  = "Kuusamo",
        fixed = nil,
        p_red = 0.5,                        -- 121 km from both Alakurtti and Kalevala
        bases = { "Kuusamo" },
    },
    {
        id    = "KOLA_SOUTH",
        name  = "Southern Kola (Alakurtti)",
        fixed = nil,
        p_red = 0.75,                       -- Blue here = NATO counter-offensive; keep it rare
        bases = { "Alakurtti" },            -- Afrikanda is always Red since session 10
    },

    -- ── Contested: deep tier (only if the border tier fell) ──
    {
        id           = "FINNMARK_WEST",
        name         = "Western Finnmark (Banak, Alta)",
        fixed        = nil,
        p_red        = 0.5,
        requires_red = "FINNMARK_EAST",
        bases        = { "Banak", "Alta" },
    },
    {
        id           = "LAPLAND_WEST",
        name         = "Western Finnish Lapland",
        fixed        = nil,
        p_red        = 0.5,
        requires_red = "LAPLAND_EAST",
        bases        = { "Kittila", "Enontekio" },
    },
    {
        id           = "ROVANIEMI",
        name         = "Rovaniemi",
        fixed        = nil,
        p_red        = 0.5,
        requires_red = "LAPLAND_EAST",      -- Red ~25% of rolls
        bases        = { "Rovaniemi" },
    },
    {
        id           = "HOSIO",
        name         = "Hosio (Oulu)",
        fixed        = nil,
        p_red        = 0.5,
        requires_red = "ROVANIEMI",         -- Red ~12% of rolls
        bases        = { "Hosio" },
    },

    -- ── Always Red ───────────────────────────────────────────
    {
        id    = "KOLA_CORE",
        name  = "Kola Core (Murmansk)",
        fixed = "red",
        bases = { "Murmansk International", "Severomorsk-1", "Severomorsk-3", "Olenya",
                  "Monchegorsk", "Kilpyavr", "Koshka Yavr", "Luostari Pechenga" },
    },
    {
        id    = "AFRIKANDA",
        name  = "Afrikanda (Kandalaksha)",
        fixed = "red",
        bases = { "Afrikanda" },
    },
    {
        id    = "KARELIA",
        name  = "Karelia",
        fixed = "red",
        bases = { "Kalevala", "Poduzhemye" },
    },
}
