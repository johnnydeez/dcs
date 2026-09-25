-- What each kind of convoy contains, how it drives and where it may run, plus how many
-- of each kind a coalition sends per mission. Coalition-agnostic: parts name a role, and
-- COALITION_ROSTER (data/coalition_rosters.lua) picks the type per coalition. Plain
-- data, no logic.
--
--   label           what the convoy is called in logs, marks and briefs
--   parts           { role, min, max, column, critical }
--                     column    where the vehicles drive in the column:
--                               head   at the front
--                               ends   first at the front, then at the back, alternating
--                               body   mixed together in the middle
--                               tail   at the back
--                     critical  counts toward destroying the convoy
--   unit_spacing_m  m between vehicles in the column at spawn
--   speed_mps       driving speed on the road
--   route_km        { min, max } straight-line distance between the two airbases
--   road_km_max     the road route may be at most this long
--   skills          one is picked per convoy
--   success         { critical_fraction }: share of the critical vehicles to destroy
--   mission_types   what the target catalog offers it for
--   value           how much its owner cares: 1 low … 3 high
--
-- A convoy drives from a rear or mid airbase to a front airbase of its coalition (any
-- two of its bases if it has no front), on roads the whole way, and parks on the road
-- outside the destination.

CONVOY_RECIPE = {
    -- Supplies to a front airbase. Mostly trucks; in an active war zone a column travels
    -- escorted: armored personnel carriers at both ends, gun trucks mixed in, and
    -- sometimes a mobile air-defense vehicle. No infantry: a vehicle group with
    -- soldiers in it drives at walking pace.
    supply_convoy = {
        label = "supply convoy",
        parts = {
            { role = "armored_personnel_carrier",       min = 1, max = 2, column = "ends" },
            { role = "cargo_truck",                     min = 4, max = 8, column = "body", critical = true },
            { role = "fuel_truck",                      min = 1, max = 2, column = "body", critical = true },
            { role = "truck_mounted_anti_aircraft_gun", min = 1, max = 2, column = "body" },
            { role = "mobile_air_defense_vehicle",      min = 0, max = 1, column = "tail" },
        },
        unit_spacing_m = 25,
        speed_mps      = 13.9,          -- ~50 km/h, as in the Syria convoys
        route_km       = { 60, 175 },
        road_km_max    = 250,           -- ~5 h at 50 km/h, inside the 6-hour ATO window
        skills         = { "Average", "Good" },
        success        = { critical_fraction = 0.5 },
        mission_types  = { "interdiction" },
        value          = 2,
    },
}

-- How many convoys of each kind a coalition sends per mission. Blue gets none for now.
CONVOYS_PER_COALITION = {
    red  = { supply_convoy = 1 },
    blue = {},
}
