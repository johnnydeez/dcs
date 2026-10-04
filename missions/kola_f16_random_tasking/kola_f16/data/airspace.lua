-- How the airspace is divided each roll (stages/divide_airspace.lua). Plain data, no logic.
--
-- Held ground: every point belongs to the coalition holding its nearest airbase, so every
-- base stands in its own coalition's ground; the front line is where that flips.
-- A point on one coalition's ground is contested when it lies within front_band_km of
-- the front line, or inside the other coalition's SAM reach (the engagement ring of a
-- site in sam_layers, times sam_reach_fraction). Everything else is that coalition's
-- own airspace.

AIRSPACE = {
    cell_km            = 10,    -- grid resolution: each cell is classified at its centre
    margin_km          = 150,   -- grid extends this far beyond the outermost airbases
    front_band_km      = 30,    -- contested either side of the front line, SAMs or not
    sam_layers         = { long_range = true, medium_range = true },
    sam_reach_fraction = 1.0,   -- 1 = the full (high-altitude) engagement ring as drawn
    simplify_km        = 2,     -- front line drawn with points dropped within this of the line
    -- the Kola map's own edges, m (DCS World\Mods\terrains\Kola\MissionGenerator\nodesMap.lua,
    -- nodesMapBorders); the grid above reaches past them, the map doesn't
    map_bounds_m       = { min_x = -285184, min_z = -557056, max_x = 393216, max_z = 884736 },
}
