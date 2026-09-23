-- Which components a base gets per defense level, and how many GROUPS of each:
-- { component, min, max }. Group size comes from data/base_defense_placement.lua.
-- Listed in spawn order. Plain data, no logic.
--
-- Rough totals: heavy 5-9 groups / ~21 units, standard 3-5 / ~13, light 1-3 / ~6.

BASE_DEFENSE_COMPOSITION = {
    heavy = {
        { "aaa",               2, 3 },
        { "shorad",            1, 2 },
        { "manpads_team",      1, 2 },
        { "security_infantry", 1, 2 },
    },
    standard = {
        { "aaa",               1, 2 },
        { "shorad",            0, 1 },
        { "manpads_team",      1, 1 },
        { "security_infantry", 1, 1 },
    },
    light = {
        { "aaa",               0, 1 },
        { "manpads_team",      1, 1 },
        { "security_infantry", 0, 1 },
    },
}
