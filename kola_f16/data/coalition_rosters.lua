-- Which unit types each coalition fields per role: { type, weight } lists for a weighted
-- pick. The ONLY file that knows red from blue — Russian kit on Blue is just a line here.
-- Every type must exist in UNIT_POOL.ground (checked at load). The roster role is our
-- decision and need not match the pool's own role tag (Ural-375 ZU-23 is tagged
-- aaa_sp in the pool but serves the aaa component here). Plain data, no logic.
--
-- DRAFT (2026-09-23): small starting set, only the roles base defenses use.

COALITION_ROSTER = {
    red = {
        aaa      = { { "ZU-23 Emplacement", 3 }, { "Ural-375 ZU-23", 2 }, { "ZSU-23-4 Shilka", 1 } },
        shorad   = { { "Strela-10M3", 1 } },
        manpads  = { { "SA-18 Igla manpad", 1 } },
        infantry = { { "Soldier AK", 3 }, { "Soldier RPG", 1 } },
    },
    blue = {
        aaa      = { { "Vulcan", 2 }, { "Gepard", 1 } },
        shorad   = { { "M1097 Avenger", 1 } },
        manpads  = { { "Soldier stinger", 1 } },
        infantry = { { "Soldier M4", 3 }, { "Soldier M249", 1 } },
    },
}
