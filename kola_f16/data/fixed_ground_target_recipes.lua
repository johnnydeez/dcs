-- What each kind of fixed ground target contains, where it may go and what counts as
-- destroying it. "Fixed" = it doesn't move (mobile targets come later, separately).
-- Coalition-agnostic: parts name a role, and COALITION_FIXED_GROUND_TARGET_ROSTER
-- (data/coalition_rosters.lua) picks the type per coalition. Plain data, no logic.
--
--   label          what the target is called in logs, marks and briefs
--   location       zone             a free surveyed zone (not used by a SAM site)
--                  parking_spot     aircraft parked on an airfield's parking spots
--                  airfield_ground  open ground at an airfield (footprint anchors)
--   echelons       front / mid / rear: how far from the enemy it may be
--   requires       zone only: zone classes (data/zones.lua, tools/miz_zones.py) the zone
--                  must have, { class = { allowed values } }
--   prefers        zone only: classes that make a zone a better fit (more likely picked)
--   footprint_m    radius the target is laid out in (a bigger zone still gets this)
--   unit_spacing   m between any two objects; a part may override it with spacing_m
--   parts          { role, min, max, place, form, critical, same_type, spacing_m }
--                    place      centre / middle / outer, see FIXED_GROUND_TARGET_PLACE
--                    form       unit (in the target's DCS group) or static_object
--                    critical   counts toward destroying the target
--                    same_type  every object of this part is the same type (a battery)
--   anchors        airfield_ground only: { anchor kind = { weight, min_m, max_m } } as in
--                  data/base_defense_placement.lua
--   aircraft       parking_spot only: { min, max } aircraft, and
--   aircraft_roles_by_base_class  { base class = { { roster role, weight } } }; a class
--                  not listed gets no parked aircraft. A base's group is ONE role and
--                  ONE type, parked side by side (FIXED_GROUND_TARGET_PARKED_AIRCRAFT_REACH_M)
--   success        { critical_fraction }: share of the critical objects to destroy
--   mission_types  what the target catalog offers it for
--   value          how much its owner cares: 1 low … 3 high
--
-- Rule of thumb for form: whatever would shoot or drive is a unit, everything else
-- (buildings, tanks, parked vehicles and aircraft) is a static object.

-- Rings of the footprint each place fills, as fractions of footprint_m.
FIXED_GROUND_TARGET_PLACE = {
    centre = { 0,    0.35 },
    middle = { 0.3,  0.7  },
    outer  = { 0.6,  1.0  },
}

local ROAD = { "road_in_zone", "road_nearby" }

FIXED_GROUND_TARGET_RECIPE = {
    -- ── zones ───────────────────────────────────────────────────
    garrison = {
        label = "garrison", location = "zone", echelons = { "front", "mid", "rear" },
        requires = { size = { "medium", "large" }, road_access = ROAD },
        prefers  = { ground = { "flat" }, settlement = { "village", "town" } },
        footprint_m = 110, unit_spacing = 20,
        parts = {
            { "barracks",         1, 3, "centre", form = "static_object", critical = true, spacing_m = 30 },
            { "command_building", 0, 1, "centre", form = "static_object", spacing_m = 30 },
            { "infantry_carrier", 2, 4, "middle", form = "unit", critical = true },
            { "infantry",         4, 8, "outer",  form = "unit", spacing_m = 6 },
            { "supply_truck",     1, 3, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.5 },
        mission_types = { "strike", "close_air_support" },
        value = 1,
    },
    armor_assembly_area = {
        label = "armor assembly area", location = "zone", echelons = { "front" },
        requires = { size = { "large" }, road_access = ROAD },
        prefers  = { ground = { "flat" } },
        footprint_m = 140, unit_spacing = 25,
        parts = {
            { "main_battle_tank", 3, 6, "middle", form = "unit", critical = true },
            { "infantry_carrier", 2, 4, "outer",  form = "unit", critical = true },
            { "fuel_truck",       1, 2, "centre", form = "static_object" },
            { "supply_truck",     1, 2, "centre", form = "static_object" },
        },
        success = { critical_fraction = 0.5 },
        mission_types = { "close_air_support", "strike" },
        value = 2,
    },
    artillery_battery = {
        label = "artillery battery", location = "zone", echelons = { "front" },
        requires = { size = { "medium", "large" }, ground = { "flat", "uneven" } },
        prefers  = { road_access = ROAD },
        footprint_m = 120, unit_spacing = 30,
        parts = {
            { "artillery_piece",  3, 4, "middle", form = "unit", critical = true, same_type = true },
            { "command_vehicle",  1, 1, "centre", form = "static_object" },
            { "supply_truck",     1, 2, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.5 },
        mission_types = { "strike", "close_air_support" },
        value = 2,
    },
    command_post = {
        label = "command post", location = "zone", echelons = { "front", "mid", "rear" },
        requires = { road_access = ROAD },
        prefers  = { settlement = { "village", "town" } },
        footprint_m = 70, unit_spacing = 20,
        parts = {
            { "command_building",     1, 1, "centre", form = "static_object", critical = true },
            { "command_vehicle",      2, 3, "middle", form = "static_object", critical = true },
            { "communications_tower", 0, 1, "outer",  form = "static_object" },
            { "generator",            1, 1, "middle", form = "static_object" },
            { "infantry",             2, 4, "outer",  form = "unit", spacing_m = 6 },
        },
        success = { critical_fraction = 0.6 },
        mission_types = { "strike" },
        value = 3,
    },
    supply_depot = {
        label = "supply depot", location = "zone", echelons = { "mid", "rear" },
        requires = { size = { "large" }, road_access = ROAD },
        prefers  = { railway_access = { "railway_nearby" }, ground = { "flat" } },
        footprint_m = 140, unit_spacing = 25,
        parts = {
            { "warehouse",          2, 3, "centre", form = "static_object", critical = true, spacing_m = 40 },
            { "ammunition_storage", 1, 2, "middle", form = "static_object", critical = true, spacing_m = 40 },
            { "supply_containers",  3, 6, "middle", form = "static_object", spacing_m = 12 },
            { "supply_truck",       3, 5, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.6 },
        mission_types = { "strike" },
        value = 2,
    },
    fuel_depot = {
        label = "fuel depot", location = "zone", echelons = { "mid", "rear" },
        requires = { size = { "large" }, road_access = ROAD },
        prefers  = { railway_access = { "railway_nearby" }, water = { "waterside", "near_water" } },
        footprint_m = 130, unit_spacing = 25,
        parts = {
            { "fuel_storage_tank", 3, 5, "centre", form = "static_object", critical = true, spacing_m = 40 },
            { "fuel_truck",        2, 4, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.6 },
        mission_types = { "strike" },
        value = 2,
    },
    communications_site = {
        label = "communications site", location = "zone", echelons = { "front", "mid", "rear" },
        requires = {},
        prefers  = { terrain = { "high_ground" }, radar_view = { "open", "partial" } },
        footprint_m = 60, unit_spacing = 25,
        parts = {
            { "communications_tower", 1, 2, "centre", form = "static_object", critical = true, spacing_m = 30 },
            { "command_vehicle",      1, 1, "middle", form = "static_object", critical = true },
            { "generator",            1, 1, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.5 },
        mission_types = { "strike" },
        value = 2,
    },

    -- ── airfields ───────────────────────────────────────────────
    parked_aircraft = {
        label = "parked aircraft", location = "parking_spot", echelons = { "front", "mid", "rear" },
        aircraft = { 2, 6 },
        aircraft_roles_by_base_class = {
            hub       = { { "parked_fighter", 2 }, { "parked_strike_aircraft", 1 }, { "parked_transport", 1 } },
            fighter   = { { "parked_fighter", 3 }, { "parked_strike_aircraft", 1 } },
            bomber    = { { "parked_bomber", 3 }, { "parked_strike_aircraft", 1 } },
            dispersal = { { "parked_fighter", 1 } },
            heli      = { { "parked_helicopter", 1 } },
            strip     = { { "parked_transport", 1 }, { "parked_helicopter", 1 } },
        },
        success = { critical_fraction = 0.5 },
        mission_types = { "airfield_strike" },
        value = 3,
    },
    airfield_fuel_storage = {
        label = "airfield fuel storage", location = "airfield_ground", echelons = { "front", "mid", "rear" },
        anchors = { building = { 3, 60, 150 }, apron = { 1, 80, 160 } },
        footprint_m = 60, unit_spacing = 25,
        parts = {
            { "fuel_storage_tank", 2, 4, "centre", form = "static_object", critical = true, spacing_m = 35 },
            { "fuel_truck",        1, 3, "outer",  form = "static_object" },
        },
        success = { critical_fraction = 0.6 },
        mission_types = { "airfield_strike", "strike" },
        value = 2,
    },
}
