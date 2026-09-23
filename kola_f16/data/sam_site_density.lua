-- How densely each coalition fills the zones it holds with SAM and early-warning sites,
-- and which layer a site in each kind of zone is. Plain data, no logic.
--
-- Every zone a coalition holds this roll gets one role, first match wins:
--   asset_ring  within ASSET_RING_KM of one of its own bases whose defense level is in
--               SAM_DEFENDED_BASE_LEVELS: the network around what it values most
--   front_belt  near the front: within FRONT_BELT_KM of an enemy-held base, or within
--               FRONT_BELT_DEPTH_KM of this roll's front gap (the shortest distance between
--               opposing bases), whichever reaches farther — so a roll whose sides sit
--               160 km apart still has a belt along the front
--   rear_area   anything else: early warning, the odd medium site; at most
--               SAM_REAR_SITES_PER_BASE_MAX sites around any one base
-- A zone of that role becomes a site with probability `chance`; its layer is a weighted
-- pick from `layers`, then the system from COALITION_SAM_SYSTEMS[side][layer]. A zone too
-- small for the pick tries the next smaller layer (short range, then early warning).
-- SAM_SITE_MIN_PER_LAYER sites are placed first, before any of this.
--
-- Target feel (2026-09-23): Ukraine-war density — most suitable zones hold something —
-- while SAM_SITE_MAX_ZONE_SHARE keeps some of each side's zones for garrisons and targets.

SAM_ZONE_ROLE_KM = {
    ASSET_RING_KM       = 40,
    FRONT_BELT_KM       = 100,
    FRONT_BELT_DEPTH_KM = 60,
}

SAM_DEFENDED_BASE_LEVELS = { heavy = true }

SAM_SITE_DENSITY = {
    asset_ring = { chance = 0.9, layers = { { "long_range", 3 }, { "medium_range", 5 }, { "short_range", 2 } } },
    front_belt = { chance = 0.8, layers = { { "medium_range", 5 }, { "short_range", 4 }, { "early_warning", 1 } } },
    rear_area  = { chance = 0.35, layers = { { "early_warning", 3 }, { "medium_range", 2 }, { "short_range", 1 } } },
}

-- Order zones are filled in (the share cap bites on the last).
SAM_ZONE_ROLE_ORDER = { "asset_ring", "front_belt", "rear_area" }

-- At most this share of the zones a coalition holds become SAM sites.
SAM_SITE_MAX_ZONE_SHARE = 0.75

-- A zone's area: the heavily defended base it guards (asset_ring), otherwise the base its
-- zone is named after. A rear-area zone gets no site once this many sites (of any role)
-- already stand in its area, so no quiet area stacks up a cluster of batteries. Rear
-- zones left free stay for garrisons and targets.
SAM_REAR_SITES_PER_BASE_MAX = 2

-- At most this many sites of a layer per area (layers not listed: no cap). A pick over
-- it falls to the next smaller layer: one S-300 or Patriot battalion per base.
SAM_SITE_MAX_PER_AREA = { long_range = 1 }

-- No two sites of one coalition closer than this: overlapping or neighbouring zones hold
-- one site between them, the rest stay free for later stages.
SAM_SITE_MIN_SPACING_KM = 3

-- At most this many sites of a layer per coalition (layers not listed: no cap). A pick
-- over its cap falls to SAM_SITE_OVER_CAP_LAYER[layer], or else the next smaller layer.
SAM_SITE_MAX_PER_LAYER = { early_warning = 2 }

-- Where a pick goes once its layer is at its cap: an early-warning pick in a rear zone
-- becomes a medium-range site (or smaller, if the zone is too small for one).
SAM_SITE_OVER_CAP_LAYER = { early_warning = "medium_range" }

-- At least this many sites of a layer per coalition, placed before the random pass in the
-- zones most worth it: zones guarding a heavily defended base first (role order), in a
-- cluster the side always holds, a different base for each site while there is a choice,
-- otherwise at random. Fewer if not enough zones are large enough for the layer's
-- systems (logged).
SAM_SITE_MIN_PER_LAYER = {
    red  = { long_range = 3, early_warning = 2 },  -- the S-300/S-400 umbrella over the Kola core
    blue = { long_range = 1, early_warning = 2 },  -- Patriot / SA-10 at Bodø, Evenes or Rovaniemi
}

-- Role order the minimum pass tries zones in, per layer (default SAM_ZONE_ROLE_ORDER).
-- Early-warning radars see 300 km+ and belong in the rear, not in the zones around a
-- heavily defended base that a SAM battery needs.
SAM_SITE_MIN_ROLE_ORDER = { early_warning = { "rear_area", "front_belt", "asset_ring" } }

-- DCS skill for every SAM site crew.
SAM_SITE_SKILL = "Good"
