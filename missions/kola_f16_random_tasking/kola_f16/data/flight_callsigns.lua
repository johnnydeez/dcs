-- Radio callsigns for AI flights (lib/flight_callsigns.lua; roadmap.md item 7, design 6).
-- Plain data, no logic.
--
-- Each AI flight gets one callsign when it is planned (a scramble when it is decided) and
-- keeps it until it lands: a name and a number, "Weasel 3", its jets "Weasel 3-1",
-- "Weasel 3-2". The same everywhere: radio, brief, air tasking order, map, event log. The
-- group name (MSN2023_SEAD) stays the machine id and is never spoken. A retry of a SEAD
-- flight (_AGAIN, _LATER) is a new sortie: the same name with a new number.
-- Numbers run 1–9 per name, then the next name in the list (a flight number never has two
-- digits, so "Viper one two" is always flight 1, jet 2). Realistic names for now (John,
-- 2026-10-05); flavour names can come later in the same place.
-- Human flights get none: the player's own callsign is RADIO_CALLS.player_callsign.

FLIGHT_CALLSIGNS = {
    -- a mission type that names its flights whatever they fly
    by_mission_type = {
        blue = {
            suppression_of_air_defenses = { "Weasel", "Wild", "Venom" },
            airborne_early_warning      = { "Darkstar", "Magic" },
        },
        red = {
            airborne_early_warning      = { "Overlord", "Wizard" },
        },
    },
    -- otherwise by aircraft type
    by_aircraft_type = {
        -- Blue
        ["F-16C_50"]      = { "Viper", "Cobra", "Falcon" },
        ["FA-18C_hornet"] = { "Hornet", "Ragin", "Knight" },
        ["F-15C"]         = { "Eagle", "Dragon", "Pistol" },
        ["F-15ESE"]       = { "Dude", "Rocco", "Mad Dog" },
        ["B-1B"]          = { "Bone", "Dark" },
        ["A-10C_2"]       = { "Hawg", "Tusk" },
        ["E-3A"]          = { "Darkstar", "Magic" },
        -- Red (never heard on Blue's radio; shown on the map and in the event log)
        ["Su-34"]         = { "Sokol", "Grach" },
        ["Su-24M"]        = { "Kobra", "Shtorm" },
        ["Tu-22M3"]       = { "Grom", "Burya" },
        ["Su-27"]         = { "Berkut", "Rus" },
        ["Su-30"]         = { "Strizh", "Vityaz" },
        ["Su-33"]         = { "Korshun", "Morskoy" },
        ["MiG-31"]        = { "Rubin", "Almaz" },
        ["A-50"]          = { "Overlord", "Wizard" },
    },
    -- a type not listed
    default = { blue = { "Falcon", "Raven", "Lancer" }, red = { "Orel", "Yastreb" } },
    max_number = 9,
}
