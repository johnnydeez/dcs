-- Player slots parsed from kola_f16_random_tasking.miz by kola_data_tools/miz_player_slots.py — do not hand-edit;
-- move or add slots in the mission editor and re-run the tool. Plain data, no logic.
--
-- DCS always spawns a dynamic-spawn player on the template's exact parking spot, so the
-- planner keeps AI aircraft (parked static aircraft, AI flights) off these spots.
--
--   PLAYER_SLOTS[airbase] = list of
--     terminal_index  DCS parking spot index (Airbase:getParking() Term_Index)
--     spot            the spot's name in the mission editor
--     group           the ME group name
--     type            aircraft type
--     x, z            DCS projected metres (x = north, z = east)

PLAYER_SLOTS = {
    ["Banak"] = {
        { terminal_index = 15, spot = "M04", group = "f16_banak", type = "F-16C_50", x = 233642, z = 88382 },
    },
    ["Bodo"] = {
        { terminal_index = 89, spot = "G08", group = "f16_bodo", type = "F-16C_50", x = -67342, z = -347096 },
    },
    ["Ivalo"] = {
        { terminal_index = 15, spot = "D09", group = "f16_ivalo", type = "F-16C_50", x = 80523, z = 198192 },
    },
    ["Kallax"] = {
        { terminal_index = 4, spot = "U01", group = "f16_kallax", type = "F-16C_50", x = -273989, z = -11814 },
    },
    ["Kemi Tornio"] = {
        { terminal_index = 4, spot = "B03", group = "f16_kemi_tornio", type = "F-16C_50", x = -243576, z = 100950 },
    },
    ["Kiruna"] = {
        { terminal_index = 4, spot = "F3", group = "f16_kiruna", type = "F-16C_50", x = -20269, z = -90795 },
    },
    ["Rovaniemi"] = {
        { terminal_index = 39, spot = "Q3", group = "f16_rovaniemi", type = "F-16C_50", x = -153727, z = 150994 },
    },
    ["Tromso"] = {
        { terminal_index = 2, spot = "14", group = "f16_tromso", type = "F-16C_50", x = 187537, z = -143769 },
    },
}
