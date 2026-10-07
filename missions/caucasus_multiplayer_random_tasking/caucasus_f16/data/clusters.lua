-- Caucasus base clusters: which airbases move together when territory is rolled.
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
-- Airbase name strings must match DCS exactly — verify with Log.dumpAirbases().
--
-- The scenario (first draft, 2026-10-06): Georgia with NATO behind it against Russia from the
-- north. The Greater Caucasus is the wall between them in the east; the fight is in the west,
-- where Russia pushes down the coast from Abkhazia toward Senaki and Kutaisi.

CLUSTERS = {

    -- ── Always Blue ──────────────────────────────────────────
    {
        id    = "GEORGIA_EAST",
        name  = "Eastern Georgia (Tbilisi)",
        fixed = "blue",
        bases = { "Tbilisi-Lochini", "Soganlug", "Vaziani" },
    },
    {
        id    = "ADJARA",
        name  = "Adjara coast (Batumi, Kobuleti)",
        fixed = "blue",
        bases = { "Batumi", "Kobuleti" },
    },

    -- ── Contested: border tier ───────────────────────────────
    {
        id    = "ABKHAZIA",
        name  = "Abkhazia (Gudauta, Sukhumi)",
        fixed = nil,
        p_red = 0.7,                        -- Russian-held in reality; Blue here = a Georgian counter-offensive
        bases = { "Gudauta", "Sukhumi-Babushara" },
    },

    -- ── Contested: deep tier (only if the border tier fell) ──
    {
        id           = "SAMEGRELO",
        name         = "Samegrelo (Senaki)",
        fixed        = nil,
        p_red        = 0.5,                 -- ~60 km down the coast from Sukhumi
        requires_red = "ABKHAZIA",
        bases        = { "Senaki-Kolkhi" },
    },
    {
        id           = "IMERETI",
        name         = "Imereti (Kutaisi)",
        fixed        = nil,
        p_red        = 0.4,                 -- deepest Russian push; keep it the rarer one
        requires_red = "SAMEGRELO",
        bases        = { "Kutaisi" },
    },

    -- ── Always Red ───────────────────────────────────────────
    {
        id    = "SOCHI",
        name  = "Sochi",
        fixed = "red",                      -- behind Abkhazia; a NATO Sochi with Abkhazia Russian would be a lone pocket
        bases = { "Sochi-Adler" },
    },
    {
        id    = "KUBAN",
        name  = "Krasnodar region and the Black Sea coast",
        fixed = "red",
        bases = { "Krasnodar-Center", "Krasnodar-Pashkovsky", "Maykop-Khanskaya", "Krymsk",
                  "Anapa-Vityazevo", "Novorossiysk", "Gelendzhik" },
    },
    {
        id    = "NORTH_CAUCASUS",
        name  = "North Caucasus (Mineralnye Vody to Beslan)",
        fixed = "red",
        bases = { "Mineralnye Vody", "Nalchik", "Mozdok", "Beslan" },
    },
}
