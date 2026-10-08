-- Terrain survey probe: the first step of a map's site survey (Afghanistan first; missions\
-- afghanistan_campaign\mission_design.md, *Map data: the site survey*). Runs in a survey
-- mission of its own, started by hand, never in a flyable mission. Standalone: loads
-- nothing from the framework, and works on any map (the map's name is DCS's own,
-- env.mission.theatre).
--
-- The survey mission: an empty mission on the map, no units needed, with one trigger
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\probe_terrain_survey_costs.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io / os).
--
-- What it does, in order, a little at a time on a timer so DCS keeps running:
--   1. call costs: times every DCS call the survey would use (height, surface type,
--      nearest road / railway, map objects in a sphere, line of sight, a route on roads)
--      on random points in the test area;
--   2. airbases: every airbase, helipad and ship DCS lists, with its runways (heading
--      checked against the runway surface, as gather.lua does) and parking spots;
--   3. the test area (TEST_AREA_*: a square around the midpoint of TEST_AREA_AIRBASES):
--      pass 1 on a PASS_1_CELL_M lattice (PASS_1_POINTS × PASS_1_POINTS heights and
--      surface types per cell), pass 2 on the cells that pass a deliberately loose
--      filter (PASS_2_MAX_RISE_M, no water) at PASS_2_STEP_M (heights and surface types,
--      nearest road and railway), and the map objects (buildings and other scenery) of
--      the whole area, searched once per BUILDING_TILE_M tile and sorted into cells.
--
-- Writes raw measurements only, to Saved Games\DCS\map_surveys\<map>\:
--   probe_call_costs.lua   PROBE_CALL_COSTS: seconds per call, objects found per search
--   airbases.lua           MAP_AIRBASES: every airbase as DCS has it
--   probe_test_area.lua    PROBE_TEST_AREA: the settings, every cell's pass 1 (and pass 2)
--                          figures, the map objects per cell
--   probe_summary.txt      the figures above in words, and the time a whole-map survey
--                          would take at these costs
-- Which cells are sites is decided later, in Python (map_data_tools\), so the thresholds
-- can change without flying this again. Trees are invisible to every DCS API (Kola probes,
-- 2026-09-23): nothing here sees them.
-- Not resumable: it is a probe on one area. The full survey will be.

local TEST_AREA_AIRBASES = { "bagram", "kabul" }   -- the test area's centre: the midpoint of these (names contain)
local TEST_AREA_SIZE_M   = 60000                   -- a square this wide
local PASS_1_CELL_M      = 1000
local PASS_1_POINTS      = 3                       -- per side: 3 × 3 points, at the centre and ±PASS_1_SPREAD_M
local PASS_1_SPREAD_M    = 400
local PASS_2_MAX_RISE_M  = 60                      -- loose on purpose: highest − lowest of pass 1's points
local PASS_2_STEP_M      = 100                     -- 11 × 11 points across the cell, edges included
local BUILDING_TILE_M    = 10000
local TICK_S             = 0.05                    -- the timer's interval
local BUDGET_S           = 0.04                    -- wall time of work per tick before handing back to DCS
local PROGRESS_EVERY_S   = 10                      -- on-screen progress

local CALL_COUNTS = {   -- how many of each call the cost test makes
    height = 20000, surface = 20000, road = 1000, railway = 200,
    search_500_m = 20, search_2000_m = 10, search_tile = 3,
    line_of_sight = 2000, route_on_roads = 10,
}

local MAP     = (env.mission and env.mission.theatre) or "unknown_map"
local OUT_DIR = lfs.writedir() .. "map_surveys\\" .. MAP .. "\\"

local function log(msg) env.info("[TERRAIN PROBE] " .. msg) end
local function say(msg, s) trigger.action.outText("TERRAIN PROBE: " .. msg, s or 15) end
local function round(v) return math.floor(v + 0.5) end
local function clock() return os.clock() end

-- ── DCS calls, each the way the survey would use it ─────────────

local SURFACE_LETTER = {}   -- one letter per point in the output: L land, R road, W water, S shallow water, U runway
for name, v in pairs(land.SurfaceType) do
    SURFACE_LETTER[v] = ({ LAND = "L", ROAD = "R", WATER = "W", SHALLOW_WATER = "S", RUNWAY = "U" })[name] or "?"
end

local function height(x, z) return land.getHeight({ x = x, y = z }) end
local function surface(x, z) return SURFACE_LETTER[land.getSurfaceType({ x = x, y = z })] or "?" end

local function distanceToNetwork(kind, x, z)
    local ok, px, pz = pcall(land.getClosestPointOnRoads, kind, x, z)
    if not ok or not px then return nil end
    return round(math.sqrt((px - x) ^ 2 + (pz - z) ^ 2))
end

-- Map objects (scenery) in a sphere; calls `each(obj)` for every one. Returns how many.
local function searchScenery(x, z, radius, each)
    local found = 0
    local volume = { id = world.VolumeType.SPHERE,
                     params = { point = { x = x, y = height(x, z), z = z }, radius = radius } }
    local ok, err = pcall(world.searchObjects, Object.Category.SCENERY, volume, function(obj)
        found = found + 1
        if each then each(obj) end
        return true
    end)
    if not ok then log("searchObjects failed: " .. tostring(err)) end
    return found
end

-- ── output ──────────────────────────────────────────────────────

local function isIdent(k) return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil end

local function serialize(v, indent)
    indent = indent or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.6g", v)
    end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    if #keys == 0 then return "{}" end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    local isSeq, allScalar = #v == #keys, true
    for _, k in ipairs(keys) do if type(v[k]) == "table" then allScalar = false end end
    local parts, pad = {}, indent .. "    "
    if allScalar then
        for _, k in ipairs(keys) do
            local ks = isSeq and "" or ((isIdent(k) and k or ("[" .. serialize(k) .. "]")) .. " = ")
            parts[#parts + 1] = ks .. serialize(v[k])
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    for _, k in ipairs(keys) do
        local ks = isSeq and "" or ((isIdent(k) and k or ("[" .. serialize(k) .. "]")) .. " = ")
        parts[#parts + 1] = pad .. ks .. serialize(v[k], pad)
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

local function header(what)
    return table.concat({
        "-- " .. what,
        "-- Measured in DCS on the " .. MAP .. " map by shared_mission_framework/map_surveys/",
        "-- probe_terrain_survey_costs.lua on " .. os.date("%Y-%m-%d %H:%M") .. ". Raw measurements;",
        "-- do not hand-edit. Units: metres, seconds; x north, z east (DCS's own coordinates).",
        "", "" }, "\n")
end

local function writeFile(name, text)
    local path = OUT_DIR .. name
    local f, err = io.open(path, "w")
    if not f then
        log("cannot write " .. path .. ": " .. tostring(err))
        say("cannot write " .. path .. "\n" .. tostring(err), 60)
        return false
    end
    f:write(text)
    f:close()
    log("wrote " .. path)
    return true
end

-- ── work on a timer ─────────────────────────────────────────────

-- The work runs in a coroutine that hands back to DCS whenever it has used BUDGET_S of
-- wall time in this tick (pause() is called between small pieces of work).
local tickStarted = 0
local function pause()
    if clock() - tickStarted >= BUDGET_S then coroutine.yield() end
end

-- ── 1. call costs ───────────────────────────────────────────────

-- Our own random numbers in [0, 1): DCS's mission environment has no math.randomseed
-- (2026-10-07: the probe's first run failed on it), and a fixed seed gives the same test
-- points every run. A linear congruential generator (Numerical Recipes' constants),
-- exact in doubles.
local randomState = 1
local function random()
    randomState = (1664525 * randomState + 1013904223) % 4294967296
    return randomState / 4294967296
end

local function randomPoint(area)
    return area.x_min + random() * (area.x_max - area.x_min),
           area.z_min + random() * (area.z_max - area.z_min)
end

-- Times `count` calls of `fn` on random points in the area (the points made first, so
-- only the calls are timed). Returns { calls, seconds, per_call_s, extra }.
local function timeCalls(area, count, fn)
    local pts = {}
    for i = 1, count do
        local x, z = randomPoint(area)
        pts[i] = { x, z }
    end
    local extra = 0
    local t0 = clock()
    for i = 1, count do extra = extra + (fn(pts[i][1], pts[i][2]) or 0) end
    local s = clock() - t0
    return { calls = count, seconds = s, per_call_s = s / count, extra = extra }
end

local function measureCallCosts(area)
    local costs, n = {}, CALL_COUNTS
    local function one(name, count, fn, extraName)
        local r = timeCalls(area, count, fn)
        if extraName then r[extraName] = r.extra end
        r.extra = nil
        costs[name] = r
        log(string.format("cost %-16s %6d calls %8.3f s  %10.1f µs a call", name, count, r.seconds, r.per_call_s * 1e6))
        coroutine.yield()   -- one kind of call per tick at most
    end
    one("height", n.height, function(x, z) height(x, z) end)
    one("surface", n.surface, function(x, z) land.getSurfaceType({ x = x, y = z }) end)
    one("road", n.road, function(x, z) distanceToNetwork("roads", x, z) end)
    one("railway", n.railway, function(x, z) distanceToNetwork("railroads", x, z) end)
    one("search_500_m", n.search_500_m, function(x, z) return searchScenery(x, z, 500) end, "objects_found")
    one("search_2000_m", n.search_2000_m, function(x, z) return searchScenery(x, z, 2000) end, "objects_found")
    local tileRadius = BUILDING_TILE_M * math.sqrt(2) / 2
    one("search_tile", n.search_tile, function(x, z) return searchScenery(x, z, tileRadius) end, "objects_found")
    one("line_of_sight", n.line_of_sight, function(x, z)
        local x2, z2 = randomPoint(area)
        land.isVisible({ x = x, y = height(x, z) + 10, z = z }, { x = x2, y = height(x2, z2) + 100, z = z2 })
    end)
    one("route_on_roads", n.route_on_roads, function(x, z)
        local a = random() * 2 * math.pi
        local ok, path = pcall(land.findPathOnRoads, "roads", x, z, x + 10000 * math.cos(a), z + 10000 * math.sin(a))
        return ok and type(path) == "table" and #path or 0
    end, "route_points")
    costs.search_tile_radius_m = round(tileRadius)
    costs.route_on_roads_length_m = 10000
    return costs
end

-- ── 2. airbases ─────────────────────────────────────────────────

local CATEGORY_NAME = {}
for name, v in pairs(Airbase.Category) do CATEGORY_NAME[v] = name:lower() end
local COALITION_NAME = { [0] = "neutral", [1] = "red", [2] = "blue" }

local function runwayHits(x, z, headingRad, length)
    local hits = 0
    for _, f in ipairs({ -0.4, -0.2, 0.2, 0.4 }) do
        local px = x + f * length * math.cos(headingRad)
        local pz = z + f * length * math.sin(headingRad)
        if land.getSurfaceType({ x = px, y = pz }) == land.SurfaceType.RUNWAY then hits = hits + 1 end
    end
    return hits
end

-- Runways as gather.lua reads them: the sign of `course` is inconsistently documented, so
-- both are probed against the runway surface; `axis` says which won.
local function readRunways(ab)
    local ok, rws = pcall(ab.getRunways, ab)
    if not ok or type(rws) ~= "table" then return {} end
    local out = {}
    for _, rw in ipairs(rws) do
        if rw.position and rw.course and rw.length then
            local x, z = rw.position.x, rw.position.z
            local hitsPos = runwayHits(x, z, rw.course, rw.length)
            local hitsNeg = runwayHits(x, z, -rw.course, rw.length)
            local course, axis = -rw.course, "-course"
            if hitsPos > hitsNeg then course, axis = rw.course, "course" end
            if hitsPos == 0 and hitsNeg == 0 then axis = "unverified" end
            out[#out + 1] = { name = rw.Name and tostring(rw.Name) or nil, x = round(x), z = round(z),
                              heading_deg = round(math.deg(course)) % 360, length_m = round(rw.length),
                              width_m = round(rw.width or 0), axis = axis }
        end
    end
    return out
end

-- Parking spots as { x, z, terminal_type, terminal_index, distance_to_runway_m }.
local function readParking(ab)
    local ok, spots = pcall(ab.getParking, ab)
    if not ok or type(spots) ~= "table" then return {} end
    local out = {}
    for _, s in ipairs(spots) do
        local p = s.vTerminalPos
        if p then out[#out + 1] = { round(p.x), round(p.z), s.Term_Type or -1, s.Term_Index or -1, round(s.fDistToRW or -1) } end
    end
    return out
end

local function readAirbases()
    local out = {}
    for _, ab in ipairs(world.getAirbases() or {}) do
        local ok, entry = pcall(function()
            local desc = ab:getDesc() or {}
            local p = ab:getPoint()
            local okC, callsign = pcall(ab.getCallsign, ab)
            local okI, id = pcall(ab.getID, ab)
            return {
                name = ab:getName(),
                id = okI and id or nil,
                category = CATEGORY_NAME[desc.category] or tostring(desc.category),
                type_name = desc.typeName,
                callsign = okC and callsign or nil,
                coalition = COALITION_NAME[ab:getCoalition()] or "?",
                x = round(p.x), z = round(p.z), height_m = round(p.y),
                runways = readRunways(ab),
                parking = readParking(ab),
            }
        end)
        if ok then out[#out + 1] = entry else log("airbase failed: " .. tostring(entry)) end
        pause()
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ── 3. the test area ────────────────────────────────────────────

local function testArea(airbases)
    local found = {}
    for _, want in ipairs(TEST_AREA_AIRBASES) do
        for _, ab in ipairs(airbases) do
            if ab.category == "airdrome" and ab.name:lower():find(want, 1, true) then
                found[#found + 1] = ab
                break
            end
        end
    end
    local cx, cz, note
    if #found > 0 then
        local sx, sz, names = 0, 0, {}
        for _, ab in ipairs(found) do sx, sz, names[#names + 1] = sx + ab.x, sz + ab.z, ab.name end
        cx, cz = sx / #found, sz / #found
        note = "the midpoint of " .. table.concat(names, " and ")
    else
        -- none of them on this map: the middle of every airbase
        local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
        for _, ab in ipairs(airbases) do
            x0, x1, z0, z1 = math.min(x0, ab.x), math.max(x1, ab.x), math.min(z0, ab.z), math.max(z1, ab.z)
        end
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        note = "the middle of every airbase (none named " .. table.concat(TEST_AREA_AIRBASES, " / ") .. ")"
    end
    -- snapped to the lattice, so a later full survey's cells line up with these
    local half = TEST_AREA_SIZE_M / 2
    local x_min = math.floor((cx - half) / PASS_1_CELL_M) * PASS_1_CELL_M
    local z_min = math.floor((cz - half) / PASS_1_CELL_M) * PASS_1_CELL_M
    return { x_min = x_min, z_min = z_min, x_max = x_min + TEST_AREA_SIZE_M, z_max = z_min + TEST_AREA_SIZE_M,
             centre = note }
end

-- Pass 1 for the cell whose south-west corner is (x0, z0).
local function passOne(x0, z0)
    local cx, cz = x0 + PASS_1_CELL_M / 2, z0 + PASS_1_CELL_M / 2
    local heights, letters = {}, {}
    local lo, hi, water = math.huge, -math.huge, false
    local step = PASS_1_POINTS > 1 and (2 * PASS_1_SPREAD_M / (PASS_1_POINTS - 1)) or 0
    for i = 0, PASS_1_POINTS - 1 do
        for j = 0, PASS_1_POINTS - 1 do
            local x = cx - PASS_1_SPREAD_M + i * step
            local z = cz - PASS_1_SPREAD_M + j * step
            local h = height(x, z)
            local s = surface(x, z)
            heights[#heights + 1] = round(h)
            letters[#letters + 1] = s
            lo, hi = math.min(lo, h), math.max(hi, h)
            if s == "W" or s == "S" then water = true end
        end
    end
    return { h = heights, s = table.concat(letters) }, hi - lo, water
end

-- Pass 2 for the same cell: heights and surface letters on PASS_2_STEP_M across it (row
-- by row, south to north, west to east within a row), nearest road and railway.
local function passTwo(x0, z0)
    local heights, letters = {}, {}
    local n = math.floor(PASS_1_CELL_M / PASS_2_STEP_M)
    for i = 0, n do
        for j = 0, n do
            local x, z = x0 + i * PASS_2_STEP_M, z0 + j * PASS_2_STEP_M
            heights[#heights + 1] = round(height(x, z))
            letters[#letters + 1] = surface(x, z)
        end
        pause()
    end
    local cx, cz = x0 + PASS_1_CELL_M / 2, z0 + PASS_1_CELL_M / 2
    return { points_per_side = n + 1, h = heights, s = table.concat(letters),
             road_m = distanceToNetwork("roads", cx, cz), railway_m = distanceToNetwork("railroads", cx, cz) }
end

local function cellKey(col, row) return col .. "_" .. row end

local function surveyTestArea(area, progress)
    local cols = math.floor((area.z_max - area.z_min) / PASS_1_CELL_M)
    local rows = math.floor((area.x_max - area.x_min) / PASS_1_CELL_M)
    local cells, passed = {}, 0
    local timing = { pass_1_s = 0, pass_2_s = 0, buildings_s = 0, pass_1_cells = 0, pass_2_cells = 0, tiles = 0, objects = 0 }

    -- pass 1 (and pass 2 straight after on a cell that passes)
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x0, z0 = area.x_min + row * PASS_1_CELL_M, area.z_min + col * PASS_1_CELL_M
            local t0 = clock()
            local one, rise, water = passOne(x0, z0)
            timing.pass_1_s = timing.pass_1_s + (clock() - t0)
            timing.pass_1_cells = timing.pass_1_cells + 1
            local cell = { row = row, col = col, x = x0, z = z0, rise_m = round(rise), pass_1 = one }
            if rise <= PASS_2_MAX_RISE_M and not water then
                local t1 = clock()
                cell.pass_2 = passTwo(x0, z0)
                timing.pass_2_s = timing.pass_2_s + (clock() - t1)
                timing.pass_2_cells = timing.pass_2_cells + 1
                passed = passed + 1
            end
            cells[cellKey(col, row)] = cell
            progress.text = string.format("test area pass 1: %d of %d cells, %d through to pass 2",
                timing.pass_1_cells, rows * cols, passed)
            pause()
        end
    end

    -- map objects, one search per tile, each object sorted into its cell: a count per
    -- cell, and on pass 2 cells every object (x, z, index into `object_types`)
    local types, typeIndex = {}, {}
    local tileRadius = BUILDING_TILE_M * math.sqrt(2) / 2 + 1
    for tx = area.x_min, area.x_max - 1, BUILDING_TILE_M do
        for tz = area.z_min, area.z_max - 1, BUILDING_TILE_M do
            local t0 = clock()
            local found = searchScenery(tx + BUILDING_TILE_M / 2, tz + BUILDING_TILE_M / 2, tileRadius, function(obj)
                local okP, p = pcall(obj.getPoint, obj)
                if not (okP and p) then return end
                -- inside this tile only (the sphere reaches into the next ones)
                if p.x < tx or p.x >= tx + BUILDING_TILE_M or p.z < tz or p.z >= tz + BUILDING_TILE_M then return end
                if p.x >= area.x_max or p.z >= area.z_max then return end
                local col = math.floor((p.z - area.z_min) / PASS_1_CELL_M)
                local row = math.floor((p.x - area.x_min) / PASS_1_CELL_M)
                local cell = cells[cellKey(col, row)]
                if not cell then return end
                cell.objects = (cell.objects or 0) + 1
                timing.objects = timing.objects + 1
                if cell.pass_2 then
                    local okT, tn = pcall(obj.getTypeName, obj)
                    tn = okT and tn or "?"
                    local ti = typeIndex[tn]
                    if not ti then
                        types[#types + 1] = tn
                        ti = #types
                        typeIndex[tn] = ti
                    end
                    local list = cell.pass_2.objects or {}
                    list[#list + 1] = { round(p.x), round(p.z), ti }
                    cell.pass_2.objects = list
                end
            end)
            timing.buildings_s = timing.buildings_s + (clock() - t0)
            timing.tiles = timing.tiles + 1
            log(string.format("tile %d: %d objects found in %.2f s", timing.tiles, found, clock() - t0))
            progress.text = string.format("test area map objects: tile %d", timing.tiles)
            coroutine.yield()   -- one tile per tick: a single search can't be split
        end
    end
    return cells, types, timing, rows, cols
end

-- ── the summary ─────────────────────────────────────────────────

local function hoursFor(seconds) return seconds / 3600 end

local function summary(costs, airbases, area, timing, rows, cols, wall_s)
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    add("Terrain survey probe, %s map, %s", MAP, os.date("%Y-%m-%d %H:%M"))
    add("")
    add("Call costs (wall time, os.clock):")
    for _, name in ipairs({ "height", "surface", "road", "railway", "search_500_m", "search_2000_m", "search_tile",
                            "line_of_sight", "route_on_roads" }) do
        local c = costs[name]
        if c then
            add("  %-16s %6d calls  %8.3f s  %11.1f µs a call%s", name, c.calls, c.seconds, c.per_call_s * 1e6,
                c.objects_found and string.format("  (%d objects found in all)", c.objects_found)
                    or c.route_points and string.format("  (%d route points in all)", c.route_points) or "")
        end
    end
    add("")
    local counts = {}
    for _, ab in ipairs(airbases) do counts[ab.category] = (counts[ab.category] or 0) + 1 end
    local parts = {}
    for k, v in pairs(counts) do parts[#parts + 1] = v .. " " .. k end
    table.sort(parts)
    add("Airbases: %d (%s)", #airbases, table.concat(parts, ", "))
    local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
    for _, ab in ipairs(airbases) do
        x0, x1, z0, z1 = math.min(x0, ab.x), math.max(x1, ab.x), math.min(z0, ab.z), math.max(z1, ab.z)
    end
    if #airbases == 0 then x0, x1, z0, z1 = area.x_min, area.x_max, area.z_min, area.z_max end
    add("  spread: x %d to %d, z %d to %d (%.0f × %.0f km)", x0, x1, z0, z1, (x1 - x0) / 1000, (z1 - z0) / 1000)
    add("")
    add("Test area: %d × %d km around %s; x %d to %d, z %d to %d", TEST_AREA_SIZE_M / 1000, TEST_AREA_SIZE_M / 1000,
        area.centre, area.x_min, area.x_max, area.z_min, area.z_max)
    add("  pass 1: %d cells of %d m, %.2f s (%.2f ms a cell)", timing.pass_1_cells, PASS_1_CELL_M, timing.pass_1_s,
        timing.pass_1_cells > 0 and timing.pass_1_s / timing.pass_1_cells * 1000 or 0)
    add("  pass 2: %d cells (%.0f %%) within %d m rise and dry, %.2f s (%.1f ms a cell)", timing.pass_2_cells,
        timing.pass_1_cells > 0 and timing.pass_2_cells / timing.pass_1_cells * 100 or 0, PASS_2_MAX_RISE_M,
        timing.pass_2_s, timing.pass_2_cells > 0 and timing.pass_2_s / timing.pass_2_cells * 1000 or 0)
    add("  map objects: %d in %d tiles of %d km, %.2f s", timing.objects, timing.tiles, BUILDING_TILE_M / 1000, timing.buildings_s)
    add("  the whole probe took %.0f s of wall time (work and DCS's frames between)", wall_s)
    add("")
    -- the whole map at these costs: the airbases' spread plus 100 km all round stands in
    -- for the map's edges, which DCS doesn't tell a script
    local areaKm2 = ((x1 - x0) / 1000 + 200) * ((z1 - z0) / 1000 + 200)
    local cellsAll = areaKm2 * 1e6 / (PASS_1_CELL_M * PASS_1_CELL_M)
    local share = timing.pass_1_cells > 0 and timing.pass_2_cells / timing.pass_1_cells or 0
    local p1 = timing.pass_1_cells > 0 and timing.pass_1_s / timing.pass_1_cells or 0
    local p2 = timing.pass_2_cells > 0 and timing.pass_2_s / timing.pass_2_cells or 0
    local perTile = timing.tiles > 0 and timing.buildings_s / timing.tiles or 0
    local tilesAll = areaKm2 * 1e6 / (BUILDING_TILE_M * BUILDING_TILE_M)
    local work = cellsAll * p1 + cellsAll * share * p2 + tilesAll * perTile
    add("A whole-map survey at these costs (the airbases' spread + 100 km all round, %.0f km², stands in for the map):", areaKm2)
    add("  pass 1: %.0f cells, %.1f h of work", cellsAll, hoursFor(cellsAll * p1))
    add("  pass 2: ~%.0f cells (the test area's share), %.1f h", cellsAll * share, hoursFor(cellsAll * share * p2))
    add("  map objects: %.0f tiles, %.1f h", tilesAll, hoursFor(tilesAll * perTile))
    add("  in all %.1f h of work; at %d %% of each tick (BUDGET_S / TICK_S) about %.1f h of running",
        hoursFor(work), round(BUDGET_S / TICK_S * 100), hoursFor(work * TICK_S / BUDGET_S))
    add("  (the test area holds a city and a busy valley: the mountains' share of pass 2 and objects is far lower)")
    return table.concat(lines, "\n") .. "\n"
end

-- ── run ─────────────────────────────────────────────────────────

local function work(progress)
    local started = clock()
    progress.text = "airbases"
    local airbases = readAirbases()
    log(string.format("%d airbases", #airbases))
    local area = testArea(airbases)
    log(string.format("test area around %s: x %d to %d, z %d to %d", area.centre, area.x_min, area.x_max, area.z_min, area.z_max))
    progress.text = "call costs"
    local costs = measureCallCosts(area)
    local cells, types, timing, rows, cols = surveyTestArea(area, progress)

    progress.text = "writing files"
    lfs.mkdir(lfs.writedir() .. "map_surveys")
    lfs.mkdir(OUT_DIR)
    local ok = writeFile("probe_call_costs.lua", header("Call costs of the DCS terrain functions.")
        .. "PROBE_CALL_COSTS = " .. serialize(costs) .. "\n")
    ok = writeFile("airbases.lua", header("Every airbase, helipad and ship DCS lists: runways { name, x, z, heading_deg, "
        .. "length_m, width_m, axis }; parking { x, z, terminal_type, terminal_index, distance_to_runway_m }.")
        .. "MAP_AIRBASES = " .. serialize(airbases) .. "\n") and ok
    -- the cells written one per line, so a big area doesn't build one huge string
    local path = OUT_DIR .. "probe_test_area.lua"
    local f, err = io.open(path, "w")
    if f then
        f:write(header("The probe's test area: pass 1 per cell (h: heights, s: surface letters L land, R road, W water, "
            .. "S shallow water, U runway; row by row, south to north), pass 2 where the cell passed, map objects per "
            .. "cell (pass 2 cells: { x, z, index into object_types })."))
        f:write("PROBE_TEST_AREA = {\n")
        f:write("    map = " .. serialize(MAP) .. ",\n")
        f:write("    area = " .. serialize(area, "    ") .. ",\n")
        f:write("    settings = " .. serialize({ cell_m = PASS_1_CELL_M, pass_1_points = PASS_1_POINTS,
            pass_1_spread_m = PASS_1_SPREAD_M, pass_2_max_rise_m = PASS_2_MAX_RISE_M, pass_2_step_m = PASS_2_STEP_M,
            object_tile_m = BUILDING_TILE_M, rows = rows, cols = cols }, "    ") .. ",\n")
        f:write("    timing = " .. serialize(timing, "    ") .. ",\n")
        f:write("    object_types = " .. serialize(types, "    ") .. ",\n")
        f:write("    cells = {\n")
        local keys = {}
        for k in pairs(cells) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ca, cb = cells[a], cells[b]
            if ca.row ~= cb.row then return ca.row < cb.row end
            return ca.col < cb.col
        end)
        for _, k in ipairs(keys) do
            f:write("        [" .. string.format("%q", k) .. "] = " .. serialize(cells[k], "        ") .. ",\n")
            pause()
        end
        f:write("    },\n}\n")
        f:close()
        log("wrote " .. path)
    else
        ok = false
        log("cannot write " .. path .. ": " .. tostring(err))
    end
    local text = summary(costs, airbases, area, timing, rows, cols, clock() - started)
    ok = writeFile("probe_summary.txt", text) and ok
    for line in text:gmatch("[^\n]+") do log(line) end
    say((ok and "DONE. " or "DONE WITH ERRORS (see dcs.log). ") .. "Files in " .. OUT_DIR .. "\n\n" .. text, 120)
end

local function start()
    if not (lfs and io and os and os.clock) then
        say("needs a de-sanitized MissionScripting.lua (lfs, io, os).", 60)
        return
    end
    local progress = { text = "starting" }
    local job = coroutine.create(work)
    local lastSaid = 0
    local function tick(_, now)
        tickStarted = clock()
        local ok, err = coroutine.resume(job, progress)
        if not ok then
            log("failed: " .. tostring(err))
            say("FAILED: " .. tostring(err), 60)
            return nil
        end
        if coroutine.status(job) == "dead" then return nil end
        if now - lastSaid >= PROGRESS_EVERY_S then
            lastSaid = now
            say(progress.text, PROGRESS_EVERY_S)
        end
        return now + TICK_S
    end
    log("started on the " .. MAP .. " map")
    say("started on the " .. MAP .. " map; progress every " .. PROGRESS_EVERY_S .. " s", 10)
    timer.scheduleFunction(tick, nil, timer.getTime() + 1)
end

start()
