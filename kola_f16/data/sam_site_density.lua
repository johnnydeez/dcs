-- How densely each coalition fills the zones it holds with SAM and early-warning sites,
-- and which layer a site in each kind of zone is. Plain data, no logic.
--
-- Every zone a coalition holds this roll gets one role, first match wins:
--   asset_ring  within ASSET_RING_KM of one of its own bases whose defense level is in
--               SAM_DEFENDED_BASE_LEVELS: the network around what it values most
--   front_belt  within FRONT_BELT_KM of an enemy-held base: the belt along the front
--   rear_area   anything else: early warning, the odd medium site
-- A zone of that role becomes a site with probability `chance`; its layer is a weighted
-- pick from `layers`, then the system from COALITION_SAM_SYSTEMS[side][layer]. A zone too
-- small for the pick tries the next smaller layer (short range, then early warning).
--
-- Target feel (2026-09-23): Ukraine-war density — most suitable zones hold something —
-- while SAM_SITE_MAX_ZONE_SHARE keeps some of each side's zones for garrisons and targets.

SAM_ZONE_ROLE_KM = {
    ASSET_RING_KM = 40,
    FRONT_BELT_KM = 100,
}

SAM_DEFENDED_BASE_LEVELS = { heavy = true }

SAM_SITE_DENSITY = {
    asset_ring = { chance = 0.9, layers = { { "long_range", 3 }, { "medium_range", 5 }, { "short_range", 2 } } },
    front_belt = { chance = 0.8, layers = { { "medium_range", 5 }, { "short_range", 4 }, { "early_warning", 1 } } },
    rear_area  = { chance = 0.6, layers = { { "early_warning", 3 }, { "medium_range", 2 }, { "short_range", 1 } } },
}

-- Order zones are filled in (the share cap bites on the last).
SAM_ZONE_ROLE_ORDER = { "asset_ring", "front_belt", "rear_area" }

-- At most this share of the zones a coalition holds become SAM sites.
SAM_SITE_MAX_ZONE_SHARE = 0.75

-- At most this many sites of a layer per coalition (layers not listed: no cap). A pick
-- over its cap falls to the next smaller layer; early warning has none, so the zone is
-- left for later stages.
SAM_SITE_MAX_PER_LAYER = { early_warning = 2 }

-- DCS skill for every SAM site crew.
SAM_SITE_SKILL = "Good"
