-- The part of the Afghanistan map the spawn site survey measures (map_surveys\survey_spawn_sites.lua,
-- the whole-map survey; missions\afghanistan_campaign\mission_design.md, *Map data: the site survey*).
-- John drew the rectangle on the F10 map (2026-10-08) and read its corners off with the mouse
-- (degrees, decimal minutes, in the comments); the survey converts them with DCS's own coord.LLtoLO
-- and measures the smallest x / z box around all four, widened to the 1 km lattice.
-- To survey another map: draw its rectangle, read the four corners, put this file in
-- map_data\<map>\ (the map's name in lower case, as DCS's theatre name).

SURVEY_AREA = {
    note = "Afghanistan from Herat / Zaranj to Jalalabad / Khost, with edges of Turkmenistan, Iran and Pakistan (John, 2026-10-08)",
    corners = {
        north_west = { latitude = 37.037600, longitude = 60.623750 },   -- N37 02.256 E60 37.425
        north_east = { latitude = 36.662717, longitude = 72.510250 },   -- N36 39.763 E72 30.615
        south_west = { latitude = 30.477450, longitude = 60.789500 },   -- N30 28.647 E60 47.370
        south_east = { latitude = 30.172967, longitude = 71.851617 },   -- N30 10.378 E71 51.097
    },
}
