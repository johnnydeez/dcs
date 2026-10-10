-- How far Caucasus's AWACS orbits keep from the enemy (the framework's
-- planner/plan_air_tasking.lua, orbitCandidates; every other AWACS setting is shared,
-- AIR_DEFENSE.early_warning_* in data/air_tasking.lua). Each race-track, centre and both
-- ends, stays at least this far from every enemy fighter base and from the contested
-- airspace. They depend on the map's size, so each mission has its own. Plain data, no logic.
--
-- The map is about half Kola's size: all of Georgia lies within ~180 km of a Red base, so
-- Kola's 250 / 120 km left Blue no orbit at all (first run, 2026-10-06 21:27). John agreed
-- smaller numbers for the smaller map (2026-10-06).

AWACS_ORBIT_DISTANCES = {
    enemy_fighter_base_km = 120,
    contested_airspace_km = 40,
}
