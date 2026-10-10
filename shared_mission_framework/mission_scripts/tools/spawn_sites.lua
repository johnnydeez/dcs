-- SpawnSites: reads a map's spawn sites and their home bases from its map data folder
-- (shared_mission_framework\map_data\<map>\: spawn_sites_index.lua with spawn_sites\, and
-- base_domains.lua with site_domains\; missions\afghanistan_campaign\mission_design.md,
-- *Map data*). No mission logic: which site gets what is the caller's.
--
-- Loads only what is asked for: the two indexes at open, a tile when one of its sites is
-- wanted (and keeps it). Never the whole map at once unless the caller walks every tile.
--   local map = SpawnSites.open(folder)          -- folder ends in a backslash
--   for _, t in ipairs(map:tilesOverlapping(xMin, xMax, zMin, zMax)) do
--       for _, s in ipairs(map:tile(t)) do ... end
--   end
-- A site: { number, x, z, latitude, longitude, height_m, rise_m, base_id, base_distance_m };
-- base_id / base_distance_m are nil when the map has no base domains yet.
-- Reads files with dofile, so it needs nothing but Lua (and works offline in luae.exe).

SpawnSites = {}
SpawnSites.__index = SpawnSites

-- Runs a data file and returns the global it sets, or nil and why. The global is cleared
-- first and after, so two tiles never mix.
local function loadGlobal(file, name)
    _G[name] = nil
    local ok, err = pcall(dofile, file)
    local value = _G[name]
    _G[name] = nil
    if not ok then return nil, tostring(err) end
    if type(value) ~= "table" then return nil, file .. " sets no " .. name end
    return value
end

-- The map's sites in `folder`, or nil and why. Base domains are optional.
function SpawnSites.open(folder)
    local index, err = loadGlobal(folder .. "spawn_sites_index.lua", "SPAWN_SITES")
    if not index then return nil, err end
    local map = setmetatable({ folder = folder, index = index, tiles = {}, domains = nil }, SpawnSites)
    local domains = loadGlobal(folder .. "base_domains.lua", "BASE_DOMAINS")
    if domains then
        map.domains = domains
        map.bases = {}
        for _, b in ipairs(domains.bases) do map.bases[b.id] = b end
    end
    return map
end

-- The index's tiles (each { name, file, x_min, x_max, z_min, z_max, sites, … }) whose square
-- overlaps the box.
function SpawnSites:tilesOverlapping(xMin, xMax, zMin, zMax)
    local list = {}
    for _, t in ipairs(self.index.tiles) do
        if t.x_max > xMin and t.x_min < xMax and t.z_max > zMin and t.z_min < zMax then list[#list + 1] = t end
    end
    return list
end

-- Every tile of the index.
function SpawnSites:everyTile()
    return self.index.tiles
end

-- A tile's sites (a tile entry from the index, or its name), loaded once and kept; or nil and why.
function SpawnSites:tile(tile)
    if type(tile) == "string" then
        for _, t in ipairs(self.index.tiles) do if t.name == tile then tile = t break end end
        if type(tile) == "string" then return nil, "no tile " .. tile end
    end
    if self.tiles[tile.name] then return self.tiles[tile.name] end
    local raw, err = loadGlobal(self.folder .. self.index.folder .. "\\" .. tile.file, "SPAWN_SITES_TILE")
    if not raw then return nil, err end
    local homes
    if self.domains then
        local d, why = loadGlobal(self.folder .. self.domains.folder .. "\\" .. tile.file, "SITE_DOMAINS_TILE")
        if not d then return nil, why end
        if #d.sites ~= #raw.sites then
            return nil, string.format("%s: %d sites, its domain file %d", tile.file, #raw.sites, #d.sites)
        end
        homes = d.sites
    end
    local sites = {}
    for k, r in ipairs(raw.sites) do
        local s = { number = r[1], x = r[2], z = r[3], latitude = r[4], longitude = r[5], height_m = r[6], rise_m = r[7] }
        if homes then
            if homes[k][1] ~= r[1] then
                return nil, string.format("%s: site %d is site %d in its domain file", tile.file, r[1], homes[k][1])
            end
            s.base_id, s.base_distance_m = homes[k][2], homes[k][3]
        end
        sites[k] = s
    end
    self.tiles[tile.name] = sites
    return sites
end

-- Drops a loaded tile (an index entry or its name), so walking the whole map doesn't keep it all.
function SpawnSites:forget(tile)
    self.tiles[type(tile) == "string" and tile or tile.name] = nil
end

-- A base with a domain, by DCS airbase id: { id, name, kind, x, z, helipads, outline, … }.
function SpawnSites:base(id)
    return self.bases and self.bases[id]
end

-- The ring (1, 2, …) a distance falls in, by rings as BASE_RINGS lays them out: the first
-- whose out_to_km reaches it; the last ring has no out_to_km.
function SpawnSites.ringOf(rings, distance_m)
    for _, r in ipairs(rings) do
        if not r.out_to_km or distance_m <= r.out_to_km * 1000 then return r.ring end
    end
    return rings[#rings].ring
end
