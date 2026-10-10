-- How far Kola's AWACS orbits keep from the enemy (the framework's planner/plan_air_tasking.lua,
-- orbitCandidates; every other AWACS setting is shared, AIR_DEFENSE.early_warning_* in
-- data/air_tasking.lua). Each race-track, centre and both ends, stays at least this far
-- from every enemy fighter base and from the contested airspace. They depend on the map's
-- size, so each mission has its own. Plain data, no logic.
--
-- Kola bug 59 (2026-10-05): 150 / 80 km until then, checked at the centre only; the E-3A
-- orbited 191 km from Alakurtti and Kuusamo scrambled at it six times in 90 min (an AWACS
-- that close would be hunted and shot down).

AWACS_ORBIT_DISTANCES = {
    enemy_fighter_base_km = 250,
    contested_airspace_km = 120,
}
