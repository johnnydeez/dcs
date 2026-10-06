-- Which components a base gets per defense level, and how many GROUPS of each:
-- { component, min, max }. Group size comes from data/base_defense_placement.lua.
-- Plain data, no logic.
--
-- Listed in placement order, most important first: groups claim open ground in this
-- order, so when a cramped field runs out of room it loses a gun battery or a MANPADS team,
-- never its radar or infrared missile launchers.
--
-- Layered by how much the owner values the base: heavy gets every layer (guns, infrared
-- and radar missiles, shoulder-launched missiles); standard gets guns and sometimes
-- infrared missiles; light always gets towed guns and shoulder-launched missiles, so no
-- used field is left with a lone MANPADS pair.
-- Trimmed for performance in VR (John, 2026-10-01): security_infantry is no longer
-- fielded (~195 units of near-pure scenery; its placement in base_defense_placement.lua
-- stays, so it can come back), and towed guns and shoulder-launched missile teams are
-- one group each at every level (were 1-2).
-- Rough totals: heavy 5 groups / ~10 units, standard 2-4 / ~7, light 2 / ~5.

BASE_DEFENSE_COMPOSITION = {
    heavy = {
        { "radar_missile_launchers",         1, 1 },
        { "infrared_missile_launchers",      1, 1 },
        { "mobile_anti_aircraft_guns",       1, 1 },
        { "towed_anti_aircraft_guns",        1, 1 },
        { "shoulder_launched_missile_teams", 1, 1 },
    },
    standard = {
        { "infrared_missile_launchers",      0, 1 },
        { "mobile_anti_aircraft_guns",       0, 1 },
        { "towed_anti_aircraft_guns",        1, 1 },
        { "shoulder_launched_missile_teams", 1, 1 },
    },
    light = {
        { "towed_anti_aircraft_guns",        1, 1 },
        { "shoulder_launched_missile_teams", 1, 1 },
    },
}
