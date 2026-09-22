-- Ground zones parsed from khola_ground_zones.miz by tools/miz_zones.py — do not hand-edit;
-- redraw in the survey .miz and re-run the tool. Plain data, no logic.
--
-- A zone is a clearing where ground units can realistically be placed. No side,
-- no role: the planner assigns both at run time.
--
--   name     ZONE_<BASE>_<brg>_<km*10> from the nearest airbase (suffix letter on collision)
--   zone_id  ME internal id — stable while the zone exists; key catalog entries on this
--   cluster  nearest base's cluster (or ME property `cluster`); zone inherits its rolled side
--   base/brg/km  nearest airbase, bearing from it, distance — for briefs and logs
--   x, z     DCS projected metres (x = north, z = east); lat/lon derived in-sim
--   type     "circle" (radius) | "quad" (verts = { {x, z}, ... })

ZONES = {
    -- N67°37'21"  E032°42'02"
    {
        name    = "ZONE_AFRI_338_188",
        zone_id = 281,
        cluster = "KOLA_SOUTH",
        base    = "Afrikanda",
        brg     = 338,
        km      = 18.8,
        type    = "circle",
        x       = 4068.163,
        z       = 431942.487,
        radius  = 152.4,
    },
    -- N70°17'54"  E026°09'33"
    {
        name    = "ZONE_BANA_056_517",
        zone_id = 211,
        cluster = "FINNMARK_WEST",
        base    = "Banak",
        brg     = 56,
        km      = 51.7,
        type    = "circle",
        x       = 263759.293,
        z       = 131214.379,
        radius  = 152.4,
    },
    -- N67°17'41"  E015°11'22"
    {
        name    = "ZONE_BODO_091_357",
        zone_id = 562,
        cluster = "NORWAY_REAR",
        base    = "Bodo",
        brg     = 91,
        km      = 35.7,
        type    = "circle",
        x       = -67675.943,
        z       = -312675.779,
        radius  = 152.4,
    },
    -- N65°57'35"  E016°13'08"
    {
        name    = "ZONE_HEMA_076_546",
        zone_id = 352,
        cluster = "SWEDEN",
        base    = "Hemavan",
        brg     = 76,
        km      = 54.6,
        type    = "circle",
        x       = -219892.727,
        z       = -279863.177,
        radius  = 152.4,
    },
    -- N66°49'18"  E020°32'58"
    {
        name    = "ZONE_JOKK_027_404",
        zone_id = 632,
        cluster = "SWEDEN",
        base    = "Jokkmokk",
        brg     = 27,
        km      = 40.4,
        type    = "circle",
        x       = -132033.794,
        z       = -82479.688,
        radius  = 152.4,
    },
    -- N65°28'56"  E021°55'44"
    {
        name    = "ZONE_KALL_232_112",
        zone_id = 351,
        cluster = "SWEDEN",
        base    = "Kallax",
        brg     = 232,
        km      = 11.2,
        type    = "circle",
        x       = -281092.468,
        z       = -19686.206,
        radius  = 152.4,
    },
    -- N67°41'54"  E024°52'25"
    {
        name    = "ZONE_KITT_100_012",
        zone_id = 70,
        cluster = "LAPLAND_WEST",
        base    = "Kittila",
        brg     = 100,
        km      = 1.2,
        type    = "circle",
        x       = -29241.250,
        z       = 101252.343,
        radius  = 152.4,
    },
    -- N69°39'14"  E031°14'31"
    {
        name    = "ZONE_LUOS_010_298",
        zone_id = 422,
        cluster = "KOLA_CORE",
        base    = "Luostari Pechenga",
        brg     = 10,
        km      = 29.8,
        type    = "circle",
        x       = 216957.583,
        z       = 333111.746,
        radius  = 152.4,
    },
    -- N64°56'10"  E034°08'38"
    {
        name    = "ZONE_PODU_277_060",
        zone_id = 633,
        cluster = "KARELIA",
        base    = "Poduzhemye",
        brg     = 277,
        km      = 6.0,
        type    = "circle",
        x       = -277702.986,
        z       = 555084.439,
        radius  = 152.4,
    },
    -- N69°06'58"  E033°23'26"
    {
        name    = "ZONE_SEV1_341_097",
        zone_id = 492,
        cluster = "KOLA_CORE",
        base    = "Severomorsk-1",
        brg     = 341,
        km      = 9.7,
        type    = "circle",
        x       = 173461.588,
        z       = 427362.776,
        radius  = 152.4,
    },
    -- N69°42'17"  E019°00'01"
    {
        name    = "ZONE_TROM_053_041",
        zone_id = 140,
        cluster = "NORWAY_REAR",
        base    = "Tromso",
        brg     = 53,
        km      = 4.1,
        type    = "circle",
        x       = 190598.568,
        z       = -140091.092,
        radius  = 45.7,
    },
    -- N69°39'28"  E018°54'25"
    {
        name    = "ZONE_TROM_191_027",
        zone_id = 210,
        cluster = "NORWAY_REAR",
        base    = "Tromso",
        brg     = 191,
        km      = 2.7,
        type    = "circle",
        x       = 185495.756,
        z       = -143889.191,
        radius  = 27.4,
    },
}
