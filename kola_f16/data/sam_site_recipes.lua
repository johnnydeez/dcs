-- What a SAM or early-warning site of each system contains and how it is laid out.
-- Side-agnostic: which coalition fields which system is in data/coalition_rosters.lua
-- (COALITION_SAM_SYSTEMS). Plain data, no logic.
--
--   layer        long_range | medium_range | short_range | early_warning
--   footprint_m  radius the site is laid out in; a site only goes in a zone at least
--                this big, and a bigger zone still gets the compact layout
--   unit_spacing m between any two units of the site
--   parts        { type, min, max, place, aim = { deg, ... } }: `min`-`max` units of that
--                type (every type must exist in UNIT_POOL.ground). Optional `aim`: exact
--                heading of unit i, in degrees off the threat axis — for radars that only
--                see a fixed sector (Patriot). place:
--                  centre     radars and command post, inner 35 % of the footprint
--                  launchers  45-95 % of the footprint, around the radars
--                  edge       support vehicles, outer 60-100 %
--   escort_role  optional: a point-defense group next to the site, types from
--                COALITION_ROSTER[side][escort_role] (the base-defense rosters)
--
-- One DCS group per site: a system's radars and launchers must share a group to work
-- together. Engagement and detection radii come from UNIT_POOL (ED's data), not here.

SAM_SITE_RECIPE = {
    -- ── long range ──────────────────────────────────────────────
    ["SA-10"] = {
        layer = "long_range", footprint_m = 150, unit_spacing = 25,
        parts = {
            { "S-300PS 64H6E sr",   1, 1, "centre" },     -- Big Bird search radar
            { "S-300PS 40B6MD sr",  1, 1, "centre" },     -- Clam Shell low-level search
            { "S-300PS 40B6M tr",   1, 1, "centre" },     -- Flap Lid engagement radar
            { "S-300PS 54K6 cp",    1, 1, "centre" },
            { "S-300PS 5P85C ln",   2, 2, "launchers" },
            { "S-300PS 5P85D ln",   2, 4, "launchers" },
            { "Ural-375",           1, 2, "edge" },
            { "ZIL-131 KUNG",       1, 1, "edge" },
        },
        escort_role = "radar_missile_launcher",           -- Pantsir / Tor next to every S-300
    },
    -- DCS Patriot: its radar sees a fixed ~120° sector, so two radars aimed 30° either
    -- side of the threat axis cover ~180°; one radar turned off-axis left sites blind.
    ["Patriot"] = {
        layer = "long_range", footprint_m = 150, unit_spacing = 25,
        parts = {
            { "Patriot str",        2, 2, "centre", aim = { -30, 30 } },
            { "Patriot ECS",        1, 1, "centre" },
            { "Patriot cp",         1, 1, "centre" },
            { "Patriot EPP",        1, 1, "centre" },
            { "Patriot AMG",        1, 1, "centre" },
            { "Patriot ln",         6, 6, "launchers" },
            { "M 818",              1, 2, "edge" },
        },
        escort_role = "infrared_missile_launcher",        -- Avenger alongside
    },

    -- ── medium range ────────────────────────────────────────────
    ["SA-11"] = {
        layer = "medium_range", footprint_m = 120, unit_spacing = 25,
        parts = {
            { "SA-11 Buk SR 9S18M1",  1, 1, "centre" },
            { "SA-11 Buk CC 9S470M1", 1, 1, "centre" },
            { "SA-11 Buk LN 9A310M1", 3, 4, "launchers" },
            { "Ural-375",             1, 2, "edge" },
        },
    },
    ["SA-6"] = {
        layer = "medium_range", footprint_m = 100, unit_spacing = 25,
        parts = {
            { "Kub 1S91 str",       1, 1, "centre" },
            { "Kub 2P25 ln",        3, 4, "launchers" },
            { "Ural-375",           1, 1, "edge" },
        },
    },
    ["NASAMS"] = {
        layer = "medium_range", footprint_m = 100, unit_spacing = 25,
        parts = {
            { "NASAMS_Radar_MPQ64F1", 2, 2, "centre" },   -- DCS wants several for coverage
            { "NASAMS_Command_Post",  1, 1, "centre" },
            { "NASAMS_LN_C",          2, 3, "launchers" },
            { "CHAP_M1083",           1, 1, "edge" },
        },
    },
    ["IRIS-T SLM"] = {
        layer = "medium_range", footprint_m = 100, unit_spacing = 25,
        parts = {
            { "CHAP_IRISTSLM_STR",  1, 1, "centre" },
            { "CHAP_IRISTSLM_CP",   1, 1, "centre" },
            { "CHAP_IRISTSLM_LN",   2, 3, "launchers" },
            { "CHAP_M1083",         1, 1, "edge" },
        },
    },
    ["Hawk"] = {
        layer = "medium_range", footprint_m = 120, unit_spacing = 25,
        parts = {
            { "Hawk sr",            1, 1, "centre" },
            { "Hawk tr",            2, 2, "centre" },     -- ED's template: two trackers
            { "Hawk pcp",           1, 1, "centre" },
            { "Hawk cwar",          0, 1, "centre" },
            { "Hawk ln",            3, 3, "launchers" },
            { "M 818",              1, 1, "edge" },
        },
    },

    -- ── short range (field units, away from airbases) ───────────
    ["SA-8"] = {
        layer = "short_range", footprint_m = 60, unit_spacing = 20,
        parts = {
            { "Osa 9A33 ln",        2, 3, "launchers" },
            { "Dog Ear radar",      0, 1, "centre" },
            { "GAZ-66",             1, 1, "edge" },
        },
    },
    ["SA-15"] = {
        layer = "short_range", footprint_m = 50, unit_spacing = 20,
        parts = {
            { "Tor 9A331",          2, 2, "launchers" },
            { "GAZ-66",             1, 1, "edge" },
        },
    },
    ["Roland"] = {
        layer = "short_range", footprint_m = 50, unit_spacing = 20,
        parts = {
            { "Roland ADS",         2, 2, "launchers" },
            { "Roland Radar",       0, 1, "centre" },
            { "Hummer",             1, 1, "edge" },
        },
    },
    -- Not rostered: in DCS Rapier can't engage low flyers without hitting the ground.
    ["Rapier"] = {
        layer = "short_range", footprint_m = 60, unit_spacing = 20,
        parts = {
            { "rapier_fsa_blindfire_radar",      1, 1, "centre" },
            { "rapier_fsa_optical_tracker_unit", 1, 1, "centre" },
            { "rapier_fsa_launcher",             2, 3, "launchers" },
            { "Land_Rover_101_FC",               1, 1, "edge" },
        },
    },

    -- ── early warning ───────────────────────────────────────────
    ["1L13"] = {
        layer = "early_warning", footprint_m = 40, unit_spacing = 20,
        parts = {
            { "1L13 EWR",           1, 1, "centre" },
            { "Ural-375",           1, 1, "edge" },
        },
    },
    ["55G6"] = {
        layer = "early_warning", footprint_m = 40, unit_spacing = 20,
        parts = {
            { "55G6 EWR",           1, 1, "centre" },
            { "Ural-375",           1, 1, "edge" },
        },
    },
    ["FPS-117"] = {
        layer = "early_warning", footprint_m = 40, unit_spacing = 20,
        parts = {
            { "FPS-117",            1, 1, "centre" },
            { "FPS-117 ECS",        1, 1, "centre" },
            { "Hummer",             1, 1, "edge" },
        },
    },
}

-- Where each `place` puts a part, as fractions of the footprint radius.
SAM_SITE_PLACE = {
    centre    = { 0,    0.35 },
    launchers = { 0.45, 0.95 },
    edge      = { 0.6,  1.0  },
}
