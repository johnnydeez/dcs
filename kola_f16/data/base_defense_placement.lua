-- Where and how each base-defense component is placed. Plain data, no logic.
--
--   role         roster role the unit types come from (data/coalition_rosters.lua)
--   road_role    optional: roster role for units that end up on a road (a dug-in gun
--                becomes its truck-mounted version)
--   anchors      { [kind] = { weight, min_m, max_m } } — which footprint anchors the
--                group centre starts from and how far from one it may land. Kinds (see
--                lib/placement.lua): infield, apron, parking, building, runway_side,
--                runway_end (forested fields only, where it is the only kind).
--                Trees are invisible to the API; open ground is found from the airfield
--                layout instead.
--   ring         { min_m, max_m } from the base anchor — fallback when a base has none
--                of the listed anchor kinds
--   units        { min, max } units in one group
--   spread       m, radius around the group centre its units scatter within
--   unit_spacing m, minimum distance between two units of the same group. A unit that
--                can't keep it inside `spread` is dropped, never pushed outward.
--   mixed_types  true = pick a type per unit (infantry squad); false = one type per
--                group (a gun battery is all the same gun)
--
-- Every group and every unit position must pass Placement.isClear (off runways,
-- taxiways, aprons, parking and water); margins are in CONFIG.

BASE_DEFENSE_PLACEMENT = {
    -- guns and vehicle-mounted missiles need open sky: the infield first, tight to
    -- aprons/parking after. No building anchors — airfield buildings can stand in forest.
    towed_anti_aircraft_guns = {
        role = "towed_anti_aircraft_gun", road_role = "truck_mounted_anti_aircraft_gun",
        anchors = { infield = { 6, 0, 40 }, apron = { 2, 40, 100 }, parking = { 1, 40, 100 },
                    runway_side = { 2, 0, 60 },
                    runway_end = { 1, 0, 10 } },
        ring = { 600, 1500 }, units = { 2, 4 }, spread = 60, unit_spacing = 25, mixed_types = false,
    },
    mobile_anti_aircraft_guns = {
        role = "mobile_anti_aircraft_gun",
        anchors = { infield = { 6, 0, 40 }, apron = { 2, 40, 100 }, parking = { 1, 40, 100 },
                    runway_side = { 2, 0, 60 },
                    runway_end = { 1, 0, 10 } },
        ring = { 600, 1500 }, units = { 2, 2 }, spread = 60, unit_spacing = 30, mixed_types = false,
    },
    infrared_missile_launchers = {
        role = "infrared_missile_launcher",
        anchors = { infield = { 6, 0, 40 }, apron = { 2, 40, 100 }, parking = { 1, 40, 100 },
                    runway_side = { 2, 0, 60 },
                    runway_end = { 1, 0, 10 } },
        ring = { 500, 1500 }, units = { 1, 2 }, spread = 80, unit_spacing = 40, mixed_types = false,
    },
    radar_missile_launchers = {
        role = "radar_missile_launcher",
        anchors = { infield = { 6, 0, 40 }, apron = { 2, 40, 100 }, parking = { 1, 40, 100 },
                    runway_side = { 2, 0, 60 },
                    runway_end = { 1, 0, 10 } },
        ring = { 500, 1500 }, units = { 1, 1 }, spread = 80, unit_spacing = 40, mixed_types = false,
    },
    -- infantry may sit at the forest edge: wider offsets, buildings allowed
    shoulder_launched_missile_teams = {
        role = "shoulder_launched_missile",
        anchors = { infield = { 1, 0, 60 }, apron = { 1, 100, 300 }, building = { 2, 80, 300 },
                    runway_side = { 2, 50, 250 },
                    runway_end = { 1, 0, 10 } },
        ring = { 800, 2000 }, units = { 2, 3 }, spread = 30, unit_spacing = 10, mixed_types = false,
    },
    security_infantry = {
        role = "infantry",
        anchors = { building = { 3, 30, 200 }, parking = { 2, 40, 200 }, apron = { 1, 40, 200 },
                    runway_side = { 1, 30, 200 },
                    runway_end = { 1, 0, 10 } },
        ring = { 400, 1200 }, units = { 4, 6 }, spread = 40, unit_spacing = 6, mixed_types = true,
    },
}

-- Minimum distance between two defense group centres at the same base, so groups
-- don't pile onto one spot.
BASE_DEFENSE_GROUP_SPACING_M = 150
