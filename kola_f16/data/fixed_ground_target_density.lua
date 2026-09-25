-- How densely each coalition fills what it holds with fixed ground targets, and which
-- kinds go where. Plain data, no logic; stages/plan_fixed_ground_targets.lua applies it.
--
-- Zones: every zone a coalition holds that no SAM site uses is a candidate (mobile units
-- are planned separately and don't need zones kept free), except the classes in
-- FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES. A zone's echelon is measured
-- like a base's: distance to the nearest enemy-held base, CONFIG.ECHELON_*_KM.
--   zone_chance  chance a free zone of that echelon holds a target
--   zone_kinds   { kind, weight } per echelon; only kinds whose recipe fits the zone are
--                eligible, and each class in the recipe's `prefers` that the zone has
--                adds FIXED_GROUND_TARGET_PREFERENCE_BONUS to the weight
-- Airfields: every base a coalition holds is a candidate.
--   airfield_chance  { kind = { base class = chance } }: chance a base of that class
--                    holds the kind (0 or missing: never)
-- minimum      at least this many sites of a kind per coalition, placed before the random
--              passes in the best-fitting candidates; fewer (logged) if nothing fits
-- max_per_kind at most this many sites of a kind per coalition (kinds not listed: no cap)
--
-- Target feel (2026-09-24): an active conflict on both sides — a lived-in rear of
-- depots and headquarters, garrisons, armor and artillery along the front.

FIXED_GROUND_TARGET_DENSITY = {
    red = {
        zone_chance = { front = 0.9, mid = 0.8, rear = 0.6 },
        zone_kinds = {
            front = { { "garrison", 4 }, { "armor_assembly_area", 3 }, { "artillery_battery", 3 },
                      { "command_post", 1 }, { "communications_site", 1 } },
            mid   = { { "supply_depot", 3 }, { "fuel_depot", 2 }, { "command_post", 2 },
                      { "garrison", 2 }, { "communications_site", 1 } },
            rear  = { { "supply_depot", 3 }, { "fuel_depot", 3 }, { "communications_site", 2 },
                      { "command_post", 1 }, { "garrison", 1 } },
        },
        airfield_chance = {
            parked_aircraft       = { hub = 0.9, fighter = 0.9, bomber = 1.0, dispersal = 0.5, heli = 0.6, strip = 0.2 },
            airfield_fuel_storage = { hub = 0.8, fighter = 0.7, bomber = 0.8, dispersal = 0.3, heli = 0.3, strip = 0.1 },
        },
        minimum = { parked_aircraft = 2, fuel_depot = 1, supply_depot = 1, command_post = 1, garrison = 1 },
        max_per_kind = { command_post = 4, communications_site = 3 },
    },
    blue = {
        zone_chance = { front = 0.9, mid = 0.7, rear = 0.5 },
        zone_kinds = {
            front = { { "garrison", 4 }, { "armor_assembly_area", 3 }, { "artillery_battery", 3 },
                      { "command_post", 1 }, { "communications_site", 1 } },
            mid   = { { "supply_depot", 3 }, { "fuel_depot", 2 }, { "command_post", 2 },
                      { "garrison", 2 }, { "communications_site", 1 } },
            rear  = { { "supply_depot", 3 }, { "fuel_depot", 3 }, { "communications_site", 2 },
                      { "command_post", 1 }, { "garrison", 1 } },
        },
        airfield_chance = {
            parked_aircraft       = { hub = 0.8, fighter = 0.8, bomber = 0.7, dispersal = 0.5, heli = 0.5, strip = 0.1 },
            airfield_fuel_storage = { hub = 0.7, fighter = 0.6, bomber = 0.6, dispersal = 0.3, heli = 0.3, strip = 0.1 },
        },
        minimum = { parked_aircraft = 2, fuel_depot = 1, supply_depot = 1, command_post = 1, garrison = 1 },
        max_per_kind = { command_post = 4, communications_site = 3 },
    },
}

-- Zones with any of these classes never hold a fixed ground target, { class = { values } }.
-- The map's own SAM revetments are for SAM sites only: anything else placed there sits
-- oddly in the dug-in positions (John, 2026-09-24).
FIXED_GROUND_TARGET_EXCLUDED_ZONE_CLASSES = { prepared_sam_position = { "revetments" } }

-- Weight added to a zone kind for each `prefers` class the zone has (weight × (1 + n × bonus)).
FIXED_GROUND_TARGET_PREFERENCE_BONUS = 1

-- At most this many zone targets of one coalition in one area (the base a zone is named
-- after), so no quiet corner fills up with depots.
FIXED_GROUND_TARGET_MAX_PER_AREA = 2

-- No two zone targets of one coalition closer than this: overlapping zones hold one.
FIXED_GROUND_TARGET_MIN_SPACING_KM = 2

-- Parked aircraft take at most this share of an airfield's parking spots; the rest stay
-- free for AI flights (stage 5) and the players' dynamic-spawn slots.
FIXED_GROUND_TARGET_PARKING_SHARE_MAX = 0.3

-- Parked aircraft stand together: a base's group is one type, on the spots nearest its
-- seed spot and no farther than this from it (the seed is the spot with the most free
-- fitting spots within this reach).
FIXED_GROUND_TARGET_PARKED_AIRCRAFT_REACH_M = 300

-- DCS skill of target units (the few that are units: infantry, armor, artillery).
FIXED_GROUND_TARGET_SKILL = "Average"
