-- Spawn site survey: measures a map's terrain so map_data_tools\find_spawn_sites.py can find
-- the clear, flat places where anything fits (a group of ground units, a large SAM site, a
-- target; missions\afghanistan_campaign\mission_design.md, *Map data: the site survey*).
-- Runs in a survey mission of its own, started by hand, never in a flyable mission.
-- Standalone: loads nothing from the framework; works on any map (env.mission.theatre).
--
-- Two ways to run it, chosen by the survey mission:
--   test areas   a trigger zone in the survey mission: a square SURVEY_AREA_SIZE_M wide around
--                each zone (its name names the area), to try the site rules on a small piece
--                of a map. Raw files in Saved Games\DCS\map_surveys\<map>\area_<name>.lua; an
--                area already surveyed is skipped (delete its file to survey it again); at the
--                end map_data_tools\find_spawn_sites.cmd, then show_spawn_sites.lua draws the
--                sites, with units in them, on the F10 map.
--   whole map    no trigger zone (John, 2026-10-08): the rectangle in the framework's
--                map_data\<map>\survey_area.lua (four GPS corners John read off the F10 map,
--                converted with DCS's own coord.LLtoLO), in TILE_M tiles. Each run has its own
--                dated folder, map_data\<map>\survey_measurements\<date>_<time>\ (in the
--                repository, git-ignored; John backs it up). Each tile's file is written when
--                the tile is done (to a .tmp, then renamed), so a crash loses one tile at most:
--                flying the survey mission again carries on from the first missing tile. When
--                every tile is done: survey_complete.lua, then find_spawn_sites.cmd writes the
--                map's sites, map_data\<map>\spawn_sites_index.lua and spawn_sites\tile_*.lua
--                (the sites by tile, so a mission loads only what it needs), and the summary is
--                shown. Nothing is drawn (John: the data file is the point; drawing and test
--                spawns later). No road distances: a mission looks them up for the sites it uses.
--                Flown again after that, it says so and offers two comms menu commands:
--                "Survey the map again" (after a DCS map update) and "Find the sites again".
-- Where the repository is comes from Saved Games\DCS\Scripts\map_surveys\local_paths.lua
-- (MAP_SURVEY_PATHS.repository_folder), a file beside the copied scripts, never in the
-- repository (bug 76: no Windows user paths in it). The whole map needs it; test areas run
-- without it but then end with the command to type.
-- The survey mission (find_spawn_sites.py make-missions writes it): one trigger
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\survey_spawn_sites.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io / os).
--
-- Per area or tile, a little at a time on a timer so DCS keeps running:
--   pass 1  every PASS_1_CELL_M cell: PASS_1_POINTS² heights and surface types;
--   pass 2  the cells within PASS_2_MAX_RISE_M rise and dry (loose on purpose): heights and
--           surface types every PASS_2_STEP_M, edges included, and the nearest road;
--   objects the map's scenery objects (buildings, walls, rubbish, containers …), one search
--           per OBJECT_TILE_M square: a count per cell, and on pass 2 cells a count per
--           PASS_2_STEP_M square (and a tally by type).
-- Writes raw measurements only. Which places are sites is decided in Python, so its rules can
-- change without flying this again.
-- Trees are invisible to every DCS API (Kola probes, 2026-09-23): nothing here sees them. On
-- Afghanistan that only means orchards in the green zones; on forested maps (Kola, Caucasus)
-- sites may land in woods. Not solved yet (John, 2026-10-08: deal with it when porting there).
-- What the probe (probe_terrain_survey_costs.lua, 2026-10-07) taught: no railway lookups
-- (~0.2 s a call on Afghanistan, which has no railways); object searches on 5 km squares (one
-- 10 km square over Kabul held 752,000 objects, a 2 s stall); objects stored as counts, not
-- one by one (54 MB for one 60 km test area); DCS has no math.randomseed.

local SURVEY_AREA_SIZE_M    = 30000                   -- test areas: the square around each zone
local TILE_M                = 100000                  -- whole map: tiles on a lattice from x = 0, z = 0
local LATITUDE_GRID_M       = 10000                   -- whole map: GPS of the lattice points this far apart
local PASS_1_CELL_M         = 1000
local PASS_1_POINTS         = 3                       -- per side, at the centre and ±PASS_1_SPREAD_M
local PASS_1_SPREAD_M       = 400
local PASS_2_MAX_RISE_M     = 60                      -- pass 1's highest − lowest point
local PASS_2_STEP_M         = 100
local OBJECT_TILE_M         = 5000
-- How the work shares DCS (2026-10-08, the first whole-map flights): a slice of BUDGET_S of work,
-- then at least REST_S of rest, both by the wall clock. Timed by mission time instead (a tick
-- every 0.01 s, 0.2 then 0.05 s of work), DCS ran the tick again in each catch-up step after a
-- long frame, frames grew, and its anti-freeze held mission time still ("ModelTimeQuantizer:
-- ANTIFREEZE ENABLED / SAME MODEL TIME" in dcs.log): the escape menu wouldn't open at 0.2 s, and
-- at 0.05 s the survey ran at ~20 cells a second of the 1,000+ it can do (dcs_scripting_gotchas.md).
local TICK_S                = 0.05                    -- mission time between looks
local BUDGET_S              = 0.05                    -- wall time of work per slice
local REST_S                = 0.05                    -- wall time between slices, whatever DCS does
local PROGRESS_EVERY_S      = 10                      -- by the wall clock, not mission time (same reason)
local PROGRESS_SHOWN_S      = 5                       -- each progress line's time on screen

local MAP        = (env.mission and env.mission.theatre) or "unknown_map"
local MAP_FOLDER = MAP:lower()                        -- map_data\<map>\ in the framework
local OUT_DIR    = lfs.writedir() .. "map_surveys\\" .. MAP .. "\\"

local function log(msg) env.info("[SPAWN SITE SURVEY] " .. msg) end
-- replace: clear what's on screen first, so progress lines don't stack (John, 2026-10-08)
local function say(msg, s, replace) trigger.action.outText("SPAWN SITE SURVEY: " .. msg, s or 15, replace == true) end
local function round(v) return math.floor(v + 0.5) end
local function clock() return os.clock() end

-- ── DCS calls ───────────────────────────────────────────────────

local SURFACE_LETTER = {}   -- L land, R road, W water, S shallow water, U runway
for name, v in pairs(land.SurfaceType) do
    SURFACE_LETTER[v] = ({ LAND = "L", ROAD = "R", WATER = "W", SHALLOW_WATER = "S", RUNWAY = "U" })[name] or "?"
end

-- Time spent in each kind of DCS call, for the log line after each tile (2026-10-08: tile 5 of
-- the first whole-map flights took 528 s of work where tiles 1-4 took 2-15 s; this says which
-- call). os.clock ticks in milliseconds, so one call's time is rough; the totals over a tile
-- aren't.
local callTimes = {}
local function timed(name, started)
    local s = clock() - started
    local t = callTimes[name]
    if not t then
        t = { count = 0, s = 0, longest_s = 0 }
        callTimes[name] = t
    end
    t.count, t.s, t.longest_s = t.count + 1, t.s + s, math.max(t.longest_s, s)
end

-- "heights 1.2 M calls 30 s (longest 0.00 s), …", and from zero again
local function callTimesLine()
    local names, parts = {}, {}
    for name in pairs(callTimes) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local t = callTimes[name]
        parts[#parts + 1] = string.format("%s %d calls %.0f s (longest %.2f s)", name, t.count, t.s, t.longest_s)
    end
    callTimes = {}
    return #parts > 0 and table.concat(parts, ", ") or "no DCS calls"
end

local function height(x, z)
    local t0 = clock()
    local h = land.getHeight({ x = x, y = z })
    timed("heights", t0)
    return h
end

local function surface(x, z)
    local t0 = clock()
    local s = SURFACE_LETTER[land.getSurfaceType({ x = x, y = z })] or "?"
    timed("surfaces", t0)
    return s
end

local function distanceToRoad(x, z)
    local t0 = clock()
    local ok, px, pz = pcall(land.getClosestPointOnRoads, "roads", x, z)
    timed("road lookups", t0)
    if not ok or not px then return nil end
    return round(math.sqrt((px - x) ^ 2 + (pz - z) ^ 2))
end

-- ── files ───────────────────────────────────────────────────────

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

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

local function isFolder(path)
    local a = lfs.attributes(path)
    return a ~= nil and a.mode == "directory"
end

-- every folder of `path` below `base` (base ends in a backslash), made if missing
local function makeFolders(base, path)
    local at = base
    for part in path:gmatch("[^\\]+") do
        at = at .. part .. "\\"
        lfs.mkdir(at)
    end
    return at
end

-- the repository's folder on this PC, or nil
local function repositoryFolder()
    MAP_SURVEY_PATHS = nil
    pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\local_paths.lua")
    return MAP_SURVEY_PATHS and MAP_SURVEY_PATHS.repository_folder
end

-- Runs a .cmd (DCS's Lua runs nothing from os.execute past ~260 characters, so the steps live
-- in the .cmd; cmd /c needs the whole line quoted once more). Returns true if it succeeded
-- and its log's last line is "done", and the log's lines.
local function runCommand(cmd, logFile)
    log("running: " .. cmd)
    if #cmd > 250 then
        return false, { string.format("the command is %d characters, too long for DCS's os.execute (~260)", #cmd) }
    end
    local rc = os.execute(cmd)
    local lines = {}
    local f = io.open(logFile, "r")
    if f then
        for line in f:lines() do
            lines[#lines + 1] = line
            log("  | " .. line)
        end
        f:close()
    end
    return (rc == 0 or rc == true) and (lines[#lines] or ""):match("^done") ~= nil, lines
end

-- ── work on a timer ─────────────────────────────────────────────

local tickStarted = 0
local function pause()
    if clock() - tickStarted >= BUDGET_S then coroutine.yield() end
end

-- how the work has shared DCS, for the log line after each tile
local slices = { count = 0, work_s = 0, looks = 0 }

local busy = false

-- Runs work(progress) in a coroutine, BUDGET_S of it per tick, with progress.text (or what
-- progress.describe() returns, when set) on screen every PROGRESS_EVERY_S. One job at a time.
local function startJob(name, work)
    if busy then
        say("busy: the survey is still running", 10)
        return
    end
    if not (lfs and io and os and os.clock) then
        say("needs a de-sanitized MissionScripting.lua (lfs, io, os).", 60)
        return
    end
    busy = true
    local progress = { text = "starting" }
    local job = coroutine.create(work)
    local lastSaid = 0
    local lastSliceEnded = -math.huge
    local function tick(_, now)
        slices.looks = slices.looks + 1
        if clock() - lastSliceEnded < REST_S then return now + TICK_S end
        tickStarted = clock()
        local ok, err = coroutine.resume(job, progress)
        lastSliceEnded = clock()
        slices.count = slices.count + 1
        slices.work_s = slices.work_s + (lastSliceEnded - tickStarted)
        if not ok then
            busy = false
            log(name .. " failed: " .. tostring(err))
            say("FAILED: " .. tostring(err), 60)
            return nil
        end
        if coroutine.status(job) == "dead" then
            busy = false
            return nil
        end
        local wall = os.time()
        if wall - lastSaid >= PROGRESS_EVERY_S then
            lastSaid = wall
            -- on screen a few seconds, then gone until the next one replaces it
            say(progress.describe and progress.describe() or progress.text, PROGRESS_SHOWN_S, true)
        end
        return now + TICK_S
    end
    log(name .. " started on the " .. MAP .. " map")
    timer.scheduleFunction(tick, nil, timer.getTime() + 1)
end

-- ── measuring a cell ────────────────────────────────────────────

local function passOne(x0, z0)
    local cx, cz = x0 + PASS_1_CELL_M / 2, z0 + PASS_1_CELL_M / 2
    local heights, letters = {}, {}
    local lo, hi, water = math.huge, -math.huge, false
    local step = PASS_1_POINTS > 1 and (2 * PASS_1_SPREAD_M / (PASS_1_POINTS - 1)) or 0
    for i = 0, PASS_1_POINTS - 1 do
        for j = 0, PASS_1_POINTS - 1 do
            local x, z = cx - PASS_1_SPREAD_M + i * step, cz - PASS_1_SPREAD_M + j * step
            local h, s = height(x, z), surface(x, z)
            heights[#heights + 1] = round(h)
            letters[#letters + 1] = s
            lo, hi = math.min(lo, h), math.max(hi, h)
            if s == "W" or s == "S" then water = true end
        end
    end
    return { h = heights, s = table.concat(letters) }, hi - lo, water
end

-- Heights and surface letters every PASS_2_STEP_M across the cell, edges included, row by
-- row from the south-west corner (rows go north, x; points within a row go east, z); and,
-- unless skipRoad, the distance from the cell's centre to the nearest road. The whole map skips
-- it (2026-10-08: far from roads one lookup can take over 0.1 s; a mission looks up the road
-- distance of the sites it uses instead).
local function passTwo(x0, z0, skipRoad)
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
    return { points_per_side = n + 1, h = heights, s = table.concat(letters),
             road_m = (not skipRoad) and distanceToRoad(x0 + PASS_1_CELL_M / 2, z0 + PASS_1_CELL_M / 2) or nil }
end

-- Counts the scenery objects in the OBJECT_TILE_M squares of [x_min, x_max) × [z_min, z_max)
-- into the cells: cellAt(x, z) gives the cell a point is in (or nil), squareOf(cell, x, z)
-- its PASS_2_STEP_M square's 1-based index. Calls perSquare(done, total) after each search.
local function countObjects(x_min, x_max, z_min, z_max, cellAt, squaresPerSide, types, perSquare)
    local tileRadius = OBJECT_TILE_M * math.sqrt(2) / 2 + 1
    local total = math.ceil((x_max - x_min) / OBJECT_TILE_M) * math.ceil((z_max - z_min) / OBJECT_TILE_M)
    local done, found, longest = 0, 0, 0
    for tx = x_min, x_max - 1, OBJECT_TILE_M do
        for tz = z_min, z_max - 1, OBJECT_TILE_M do
            local t0 = clock()
            local centre = { x = tx + OBJECT_TILE_M / 2, z = tz + OBJECT_TILE_M / 2 }
            local volume = { id = world.VolumeType.SPHERE,
                             params = { point = { x = centre.x, y = height(centre.x, centre.z), z = centre.z }, radius = tileRadius } }
            local ok, err = pcall(world.searchObjects, Object.Category.SCENERY, volume, function(obj)
                local okP, p = pcall(obj.getPoint, obj)
                if okP and p and p.x >= tx and p.x < tx + OBJECT_TILE_M and p.z >= tz and p.z < tz + OBJECT_TILE_M
                   and p.x < x_max and p.z < z_max then
                    local cell = cellAt(p.x, p.z)
                    if cell then
                        cell.objects = cell.objects + 1
                        found = found + 1
                        if cell.pass_2 then
                            local i = math.min(squaresPerSide - 1, math.floor((p.x - cell.x) / PASS_2_STEP_M))
                            local j = math.min(squaresPerSide - 1, math.floor((p.z - cell.z) / PASS_2_STEP_M))
                            local k = i * squaresPerSide + j + 1
                            cell.squares = cell.squares or {}
                            cell.squares[k] = (cell.squares[k] or 0) + 1
                            local okT, tn = pcall(obj.getTypeName, obj)
                            tn = okT and tn or "?"
                            types[tn] = (types[tn] or 0) + 1
                        end
                    end
                end
                return true
            end)
            if not ok then log("searchObjects failed: " .. tostring(err)) end
            timed("object searches", t0)
            longest = math.max(longest, clock() - t0)
            done = done + 1
            perSquare(done, total)
            pause()   -- outside the pcall: a coroutine can't yield across one
        end
    end
    return found, longest
end

-- ── test areas (trigger zones) ──────────────────────────────────

local function fileName(name) return (name:gsub("[^%w_%-]", "_")) end

-- A square SURVEY_AREA_SIZE_M wide around (cx, cz), snapped to the PASS_1_CELL_M lattice so
-- every survey's cells line up.
local function squareAround(name, cx, cz, note)
    local half = SURVEY_AREA_SIZE_M / 2
    local x_min = math.floor((cx - half) / PASS_1_CELL_M) * PASS_1_CELL_M
    local z_min = math.floor((cz - half) / PASS_1_CELL_M) * PASS_1_CELL_M
    return { name = name, file = "area_" .. fileName(name) .. ".lua", note = note,
             x_min = x_min, z_min = z_min, x_max = x_min + SURVEY_AREA_SIZE_M, z_max = z_min + SURVEY_AREA_SIZE_M }
end

local function triggerZoneAreas()
    local areas = {}
    local zones = env.mission and env.mission.triggers and env.mission.triggers.zones or {}
    for _, z in ipairs(zones) do
        -- the mission editor calls east `y`
        areas[#areas + 1] = squareAround(z.name or ("zone_" .. tostring(z.zoneId)), z.x, z.y, "around the trigger zone " .. tostring(z.name))
    end
    return areas
end

-- map_data_tools\find_spawn_sites.cmd on the test areas, then the viewer script, so the sites
-- show on the F10 map. Returns nil, or what went wrong.
local function findAndShowSites()
    local repo = repositoryFolder()
    if not repo then
        return "sites not found yet: no Scripts\\map_surveys\\local_paths.lua, so the tool's place isn't known. "
            .. "Run: python shared_mission_framework\\map_data_tools\\find_spawn_sites.py"
    end
    local logFile = OUT_DIR .. "find_spawn_sites.log"
    local cmd = string.format('""%s\\shared_mission_framework\\map_data_tools\\find_spawn_sites.cmd" "%s""', repo, logFile)
    local ok, lines = runCommand(cmd, logFile)
    if not ok then return "find_spawn_sites.py FAILED: " .. (lines[1] and #lines == 1 and lines[1] or ("see " .. logFile)) end
    local okShow, err = pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\show_spawn_sites.lua")
    if not okShow then return "sites found, but showing them failed: " .. tostring(err) end
    return nil
end

local function cellKey(row, col) return row .. "_" .. col end

local function surveyArea(area, progress, index, count)
    local rows = math.floor((area.x_max - area.x_min) / PASS_1_CELL_M)
    local cols = math.floor((area.z_max - area.z_min) / PASS_1_CELL_M)
    local cells, list = {}, {}
    local timing = { pass_1_s = 0, pass_2_s = 0, objects_s = 0, pass_1_cells = 0, pass_2_cells = 0, tiles = 0,
                     objects = 0, longest_search_s = 0 }
    local squaresPerSide = math.floor(PASS_1_CELL_M / PASS_2_STEP_M)

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x0, z0 = area.x_min + row * PASS_1_CELL_M, area.z_min + col * PASS_1_CELL_M
            local t0 = clock()
            local one, rise, water = passOne(x0, z0)
            timing.pass_1_s = timing.pass_1_s + (clock() - t0)
            timing.pass_1_cells = timing.pass_1_cells + 1
            local cell = { row = row, col = col, x = x0, z = z0, rise_m = round(rise), pass_1 = one, objects = 0 }
            if rise <= PASS_2_MAX_RISE_M and not water then
                local t1 = clock()
                cell.pass_2 = passTwo(x0, z0)
                timing.pass_2_s = timing.pass_2_s + (clock() - t1)
                timing.pass_2_cells = timing.pass_2_cells + 1
            end
            cells[cellKey(row, col)] = cell
            list[#list + 1] = cell
            progress.text = string.format("area %d of %d (%s): pass 1 %d of %d cells, %d through to pass 2",
                index, count, area.name, timing.pass_1_cells, rows * cols, timing.pass_2_cells)
            pause()
        end
    end

    local types = {}
    local t0 = clock()
    timing.objects, timing.longest_search_s = countObjects(area.x_min, area.x_max, area.z_min, area.z_max,
        function(x, z)
            return cells[cellKey(math.floor((x - area.x_min) / PASS_1_CELL_M), math.floor((z - area.z_min) / PASS_1_CELL_M))]
        end,
        squaresPerSide, types,
        function(done, total)
            timing.tiles = done
            progress.text = string.format("area %d of %d (%s): map objects, square %d of %d", index, count, area.name, done, total)
        end)
    timing.objects_s = clock() - t0
    -- the squares as a full list of counts (row by row, as the points), so the file is plain
    for _, cell in ipairs(list) do
        local two = cell.pass_2
        if two then
            local full = {}
            for k = 1, squaresPerSide * squaresPerSide do full[k] = (cell.squares and cell.squares[k]) or 0 end
            two.squares = full
            two.squares_per_side = squaresPerSide
        end
        cell.squares = nil
    end
    return list, timing, rows, cols
end

local function writeArea(area, list, timing, rows, cols)
    lfs.mkdir(lfs.writedir() .. "map_surveys")
    lfs.mkdir(OUT_DIR)
    local path = OUT_DIR .. area.file
    local f, err = io.open(path, "w")
    if not f then
        log("cannot write " .. path .. ": " .. tostring(err))
        return false, path
    end
    f:write(table.concat({
        "-- One area of the spawn site survey, measured in DCS on the " .. MAP .. " map by",
        "-- shared_mission_framework/map_surveys/survey_spawn_sites.lua on " .. os.date("%Y-%m-%d %H:%M") .. ".",
        "-- Raw measurements, read by map_data_tools/find_spawn_sites.py; do not hand-edit.",
        "-- Metres, seconds; x north, z east (DCS's own). Per cell: pass_1 { h heights, s surface letters",
        "-- (L land, R road, W water, S shallow water, U runway) }, both row by row from the south-west",
        "-- corner; pass_2 where the cell passed: h / s every step_m with edges, road_m from the cell's",
        "-- centre, squares (map objects per step_m square, row by row).",
        "", "" }, "\n"))
    f:write("SURVEYED_AREA = {\n")
    f:write("    map = " .. serialize(MAP) .. ",\n")
    f:write("    name = " .. serialize(area.name) .. ",\n")
    f:write("    note = " .. serialize(area.note) .. ",\n")
    f:write("    x_min = " .. area.x_min .. ", x_max = " .. area.x_max .. ", z_min = " .. area.z_min .. ", z_max = " .. area.z_max .. ",\n")
    f:write("    settings = " .. serialize({ cell_m = PASS_1_CELL_M, pass_1_points = PASS_1_POINTS,
        pass_1_spread_m = PASS_1_SPREAD_M, pass_2_max_rise_m = PASS_2_MAX_RISE_M, step_m = PASS_2_STEP_M,
        object_tile_m = OBJECT_TILE_M, rows = rows, cols = cols }, "    ") .. ",\n")
    f:write("    timing = " .. serialize(timing, "    ") .. ",\n")
    f:write("    cells = {\n")
    for _, cell in ipairs(list) do
        f:write("        " .. serialize(cell, "        ") .. ",\n")
        pause()
    end
    f:write("    },\n}\n")
    f:close()
    log("wrote " .. path)
    return true, path
end

local function surveyTestAreas(progress, areas)
    local report = {}
    for i, area in ipairs(areas) do
        if fileExists(OUT_DIR .. area.file) then
            report[#report + 1] = area.name .. ": surveyed before (delete " .. area.file .. " to survey it again)"
            log(report[#report])
        else
            local started = clock()
            log(string.format("area %d of %d: %s, %s; x %d to %d, z %d to %d", i, #areas, area.name, area.note,
                area.x_min, area.x_max, area.z_min, area.z_max))
            local list, timing, rows, cols = surveyArea(area, progress, i, #areas)
            progress.text = string.format("area %d of %d (%s): writing", i, #areas, area.name)
            local ok, path = writeArea(area, list, timing, rows, cols)
            local line = string.format("%s: %d cells, %d to pass 2, %d map objects, %.0f s (longest object search %.2f s)%s",
                area.name, timing.pass_1_cells, timing.pass_2_cells, timing.objects, clock() - started,
                timing.longest_search_s, ok and "" or ("; COULD NOT WRITE " .. path))
            log(line)
            report[#report + 1] = line
        end
    end
    progress.text = "finding the sites (find_spawn_sites.py), then drawing them"
    say(progress.text, 20)
    coroutine.yield()   -- that line on screen before the tool blocks DCS for a few seconds
    local problem = findAndShowSites()
    say("SURVEY DONE.\n" .. table.concat(report, "\n") .. "\n"
        .. (problem or "Sites drawn on the F10 map: green circles, trucks in each.") .. "\nFiles in " .. OUT_DIR, 120)
end

-- ── the whole map ───────────────────────────────────────────────

local function measurementsFolder(repo)
    return repo .. "\\shared_mission_framework\\map_data\\" .. MAP_FOLDER .. "\\survey_measurements\\"
end

-- SURVEY_AREA from map_data\<map>\survey_area.lua, or nil and why not
local function readSurveyArea(repo)
    local path = repo .. "\\shared_mission_framework\\map_data\\" .. MAP_FOLDER .. "\\survey_area.lua"
    if not fileExists(path) then return nil, "no " .. path end
    SURVEY_AREA = nil
    local ok, err = pcall(dofile, path)
    if not ok then return nil, path .. ": " .. tostring(err) end
    local c = SURVEY_AREA and SURVEY_AREA.corners
    for _, name in ipairs({ "north_west", "north_east", "south_west", "south_east" }) do
        if not (c and c[name] and c[name].latitude and c[name].longitude) then
            return nil, path .. ": corners." .. name .. " needs latitude and longitude"
        end
    end
    return SURVEY_AREA
end

-- the smallest x / z box around the four corners, widened to the PASS_1_CELL_M lattice
local function boxAround(corners)
    local box = { x_min = math.huge, x_max = -math.huge, z_min = math.huge, z_max = -math.huge, corners = {} }
    for name, c in pairs(corners) do
        local p = coord.LLtoLO(c.latitude, c.longitude, 0)
        box.corners[name] = { x = round(p.x), z = round(p.z) }
        box.x_min, box.x_max = math.min(box.x_min, p.x), math.max(box.x_max, p.x)
        box.z_min, box.z_max = math.min(box.z_min, p.z), math.max(box.z_max, p.z)
    end
    box.x_min = math.floor(box.x_min / PASS_1_CELL_M) * PASS_1_CELL_M
    box.z_min = math.floor(box.z_min / PASS_1_CELL_M) * PASS_1_CELL_M
    box.x_max = math.ceil(box.x_max / PASS_1_CELL_M) * PASS_1_CELL_M
    box.z_max = math.ceil(box.z_max / PASS_1_CELL_M) * PASS_1_CELL_M
    return box
end

-- the box's tiles, on a TILE_M lattice from x = 0, z = 0 (so a tile is the same piece of the
-- map whatever the box), cut to the box; south to north, west to east
local function tilesOf(box)
    local tiles = {}
    for tx = math.floor(box.x_min / TILE_M) * TILE_M, box.x_max - 1, TILE_M do
        for tz = math.floor(box.z_min / TILE_M) * TILE_M, box.z_max - 1, TILE_M do
            local t = { x_min = math.max(tx, box.x_min), x_max = math.min(tx + TILE_M, box.x_max),
                        z_min = math.max(tz, box.z_min), z_max = math.min(tz + TILE_M, box.z_max) }
            if t.x_max > t.x_min and t.z_max > t.z_min then
                t.name = string.format("tile_x%+05d_z%+05d", tx / 1000, tz / 1000)
                t.file = t.name .. ".txt"
                t.cells = ((t.x_max - t.x_min) / PASS_1_CELL_M) * ((t.z_max - t.z_min) / PASS_1_CELL_M)
                tiles[#tiles + 1] = t
            end
        end
    end
    return tiles
end

-- the run folders' names, oldest first (they're dated, so names sort by time)
local function runNames(folder)
    local names = {}
    if isFolder(folder) then
        for name in lfs.dir(folder) do
            if name:match("^%d%d%d%d%-%d%d%-%d%d_%d%d%d%d$") and isFolder(folder .. name) then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

local function km(m) return string.format("%d", round(m / 1000)) end

local function duration(s)
    s = math.max(0, round(s))
    if s >= 3600 then return string.format("%d h %02d min", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
    return string.format("%d min", math.floor(s / 60))
end

-- GPS of every LATITUDE_GRID_M lattice point over the box, so find_spawn_sites.py can give each
-- site its latitude and longitude as DCS converts them (coord.LOtoLL)
local function writeLatitudeGrid(runFolder, box, progress)
    local path = runFolder .. "latitude_longitude_grid.txt"
    if fileExists(path) then return end
    local f = assert(io.open(path .. ".tmp", "w"))
    f:write("# DCS's coord.LOtoLL every " .. LATITUDE_GRID_M .. " m over the survey box, written by survey_spawn_sites.lua.\n")
    f:write("# Lines: <x> <z> <latitude> <longitude> (metres, degrees; x north, z east).\n")
    local g = LATITUDE_GRID_M
    for x = math.floor(box.x_min / g) * g, math.ceil(box.x_max / g) * g, g do
        for z = math.floor(box.z_min / g) * g, math.ceil(box.z_max / g) * g, g do
            local lat, lon = coord.LOtoLL({ x = x, y = 0, z = z })
            f:write(string.format("%d %d %.7f %.7f\n", x, z, lat, lon))
        end
        progress.text = "writing the GPS grid"
        pause()
    end
    f:close()
    os.rename(path .. ".tmp", path)
end

local function writeRunFile(runFolder, area, box, tiles)
    local path = runFolder .. "run.lua"
    if fileExists(path) then return end
    local f = assert(io.open(path, "w"))
    f:write("-- One run of the whole-map spawn site survey, written by survey_spawn_sites.lua when it started.\n")
    f:write("-- Metres; x north, z east (DCS's own).\n\n")
    f:write("SURVEY_RUN = " .. serialize({
        map = MAP, started = os.date("%Y-%m-%d %H:%M"), note = area.note,
        dcs_version = rawget(_G, "_APP_VERSION"),
        survey_area_corners = area.corners, corners_in_dcs = box.corners,
        x_min = box.x_min, x_max = box.x_max, z_min = box.z_min, z_max = box.z_max, tiles = #tiles,
        settings = { tile_m = TILE_M, cell_m = PASS_1_CELL_M, pass_1_points = PASS_1_POINTS,
                     pass_1_spread_m = PASS_1_SPREAD_M, pass_2_max_rise_m = PASS_2_MAX_RISE_M,
                     step_m = PASS_2_STEP_M, object_tile_m = OBJECT_TILE_M, latitude_grid_m = LATITUDE_GRID_M },
    }) .. "\n")
    f:close()
end

-- One tile: measured, then written to <file>.tmp and renamed, so a tile file is either whole
-- or not there. Lines as the header says (find_spawn_sites.py reads them).
local function surveyTile(tile, runFolder, status)
    local started = os.time()
    local rows = (tile.x_max - tile.x_min) / PASS_1_CELL_M
    local cols = (tile.z_max - tile.z_min) / PASS_1_CELL_M
    local cells, list = {}, {}
    local squaresPerSide = math.floor(PASS_1_CELL_M / PASS_2_STEP_M)
    local passTwoCells = 0
    status.phase = "measuring the first cells"
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local x0, z0 = tile.x_min + r * PASS_1_CELL_M, tile.z_min + c * PASS_1_CELL_M
            local one, rise, water = passOne(x0, z0)
            local cell = { row = round(x0 / PASS_1_CELL_M), col = round(z0 / PASS_1_CELL_M), x = x0, z = z0,
                           rise = round(rise), objects = 0,
                           pass_1 = table.concat(one.h, ",") .. " " .. one.s }
            if rise <= PASS_2_MAX_RISE_M and not water then
                local two = passTwo(x0, z0, true)
                local lowest = math.huge
                for _, h in ipairs(two.h) do lowest = math.min(lowest, h) end
                local above = {}
                for k, h in ipairs(two.h) do above[k] = h - lowest end
                local letters = two.s
                if letters == string.rep(letters:sub(1, 1), #letters) then letters = letters:sub(1, 1) end
                cell.pass_2 = "? " .. lowest .. " " .. table.concat(above, ",") .. " " .. letters
                passTwoCells = passTwoCells + 1
            end
            cells[cellKey(r, c)] = cell
            list[#list + 1] = cell
            status.cells_done = status.cells_done + 1
            status.session_cells = status.session_cells + 1
            status.phase = string.format("%d of %d cells measured, %d through to pass 2", r * cols + c + 1, rows * cols, passTwoCells)
            pause()
        end
    end
    local types = {}
    local objects = countObjects(tile.x_min, tile.x_max, tile.z_min, tile.z_max,
        function(x, z)
            return cells[cellKey(math.floor((x - tile.x_min) / PASS_1_CELL_M), math.floor((z - tile.z_min) / PASS_1_CELL_M))]
        end,
        squaresPerSide, types,
        function(done, total) status.phase = string.format("map objects, %d km square %d of %d", OBJECT_TILE_M / 1000, done, total) end)

    status.phase = "writing"
    local path = runFolder .. tile.file
    local f = assert(io.open(path .. ".tmp", "w"))
    f:write(table.concat({
        "# One tile of the whole-map spawn site survey of the " .. MAP .. " map, measured in DCS by",
        "# shared_mission_framework/map_surveys/survey_spawn_sites.lua on " .. os.date("%Y-%m-%d %H:%M") .. ".",
        "# Raw measurements, read by map_data_tools/find_spawn_sites.py; do not hand-edit. Metres; x north, z east.",
        "# Lines:",
        "#   tile <x_min> <x_max> <z_min> <z_max> <cell_m> <step_m> <pass_1_points>",
        "#   A <row> <col> <rise> <objects> <pass 1 heights> <pass 1 surfaces>     a cell measured in pass 1 only",
        "#   B <row> <col> <rise> <objects> <pass 1 heights> <pass 1 surfaces> <road_m> <lowest> <pass 2 heights> <pass 2 surfaces> <object squares>",
        "#   object <count> <type name>     objects by type, in the tile's pass 2 cells",
        "#   end <cells> <pass 2 cells> <objects> <seconds>",
        "# row = x / cell_m and col = z / cell_m of the cell's south-west corner; rise = pass 1's highest - lowest.",
        "# Pass 1: pass_1_points² points 400 m apart around the cell's centre; pass 2: every step_m, edges included,",
        "# heights above <lowest>; both row by row from the south-west (rows go north, points in a row go east).",
        "# Surfaces: L land, R road, W water, S shallow water, U runway; pass 2's is one letter when all are the same.",
        "# road_m: ? (not measured: a mission looks up the road distance of the sites it uses; tiles measured",
        "# before 2026-10-08 13:30 have the cell centre's, - for none). Object squares: - for none, else",
        "# <index>:<count>, index = row * " .. squaresPerSide .. " + column of the step_m square from the cell's south-west corner.",
        string.format("tile %d %d %d %d %d %d %d", tile.x_min, tile.x_max, tile.z_min, tile.z_max, PASS_1_CELL_M, PASS_2_STEP_M, PASS_1_POINTS),
        "" }, "\n"))
    for n, cell in ipairs(list) do
        local head = string.format("%s %d %d %d %d %s", cell.pass_2 and "B" or "A", cell.row, cell.col, cell.rise, cell.objects, cell.pass_1)
        if cell.pass_2 then
            local squares = {}
            if cell.squares then
                for k = 1, squaresPerSide * squaresPerSide do
                    if cell.squares[k] then squares[#squares + 1] = (k - 1) .. ":" .. cell.squares[k] end
                end
            end
            f:write(head, " ", cell.pass_2, " ", #squares > 0 and table.concat(squares, ",") or "-", "\n")
        else
            f:write(head, "\n")
        end
        if n % 200 == 0 then pause() end
    end
    local typeNames = {}
    for tn in pairs(types) do typeNames[#typeNames + 1] = tn end
    table.sort(typeNames)
    for _, tn in ipairs(typeNames) do f:write(string.format("object %d %s\n", types[tn], tn)) end
    f:write(string.format("end %d %d %d %d\n", #list, passTwoCells, objects, os.time() - started))
    f:close()
    os.remove(path)   -- none should be there; os.rename won't replace a file on Windows
    local ok, err = os.rename(path .. ".tmp", path)
    if not ok then error("cannot rename " .. path .. ".tmp: " .. tostring(err)) end
    return #list, passTwoCells, objects
end

-- find_spawn_sites.cmd on a finished run: the map's spawn_sites_index.lua and
-- spawn_sites\tile_*.lua (the sites by tile). On the whole map it takes
-- minutes, so it is started on its own ("start" returns at once) and its log read every
-- second, its last line on screen, until the .cmd writes "done" or "FAILED". Runs inside a
-- job's coroutine. Returns ok and the log's lines.
local function findSitesForMap(repo, runName, progress)
    local logFile = measurementsFolder(repo) .. runName .. "\\find_spawn_sites.log"
    os.remove(logFile)   -- so an old "done" isn't read as this one's
    -- cmd /c so its window closes when it ends (start on a .cmd alone leaves it open)
    local cmd = string.format('start "" /min cmd /c ""%s\\shared_mission_framework\\map_data_tools\\find_spawn_sites.cmd" map-survey %s %s"',
        repo, MAP_FOLDER, runName)
    log("running: " .. cmd)
    os.execute(cmd)
    local started = os.time()
    progress.text = "finding the sites (find_spawn_sites.py): starting"
    while true do
        local waitUntil = clock() + 1
        while clock() < waitUntil do coroutine.yield() end
        local lines = {}
        local f = io.open(logFile, "r")
        if f then
            for line in f:lines() do lines[#lines + 1] = line end
            f:close()
        end
        local last = lines[#lines]
        local finished = last and last:match("^done%s*$") ~= nil
        if finished or (last and last:match("FAILED")) then
            for _, line in ipairs(lines) do log("  | " .. line) end
            return finished, lines
        end
        progress.text = "finding the sites (find_spawn_sites.py), " .. duration(os.time() - started) .. ": " .. (last or "starting")
        if os.time() - started > 3600 then
            lines[#lines + 1] = "no end to " .. logFile .. " after an hour"
            return false, lines
        end
    end
end

-- the tool's summary, from its log: the lines after its "summary" line, before "done"
local function sitesSummary(ok, lines)
    if not ok then return "find_spawn_sites.py FAILED:\n" .. table.concat(lines, "\n", math.max(1, #lines - 8)) end
    local keep, on = {}, false
    for i = 1, #lines - 1 do
        if on then keep[#keep + 1] = lines[i] end
        if lines[i] == "summary" then on = true end
    end
    return table.concat(keep, "\n")
end

-- After every tile is measured (or from the comms menu): find the sites. Returns the text for
-- the screen. (Until 2026-10-08 it then looked up every site's road distance: ~250,000 sites on
-- Afghanistan, hours of lookups, and loading the then one 39 MB sites file hung DCS. John: a
-- mission looks up the road distance of the sites it uses.)
local function finishSites(repo, runName, progress)
    local ok, lines = findSitesForMap(repo, runName, progress)
    return sitesSummary(ok, lines)
end

local function findSitesAgain(repo, runName)
    startJob("finding the sites", function(progress)
        local text = finishSites(repo, runName, progress)
        say("SITES FOUND AGAIN from the survey of " .. runName .. ".\n" .. text, 120, true)
    end)
end

local function surveyWholeMap(repo, area, runName)
    startJob("whole-map survey", function(progress)
        local box = boxAround(area.corners)
        local tiles = tilesOf(box)
        local runFolder = makeFolders(repo .. "\\", "shared_mission_framework\\map_data\\" .. MAP_FOLDER .. "\\survey_measurements\\" .. runName)
        log(string.format("run %s: x %d to %d, z %d to %d (%s × %s km), %d tiles", runName, box.x_min, box.x_max,
            box.z_min, box.z_max, km(box.x_max - box.x_min), km(box.z_max - box.z_min), #tiles))
        writeRunFile(runFolder, area, box, tiles)
        writeLatitudeGrid(runFolder, box, progress)

        local status = { cells_done = 0, session_cells = 0, phase = "" }
        local totalCells, todo = 0, {}
        for _, t in ipairs(tiles) do
            totalCells = totalCells + t.cells
            os.remove(runFolder .. t.file .. ".tmp")   -- a tile a crash cut short starts again
            if fileExists(runFolder .. t.file) then status.cells_done = status.cells_done + t.cells else todo[#todo + 1] = t end
        end
        if #todo < #tiles then
            say(string.format("carrying on with the survey of %s: %d of %d tiles done before", runName, #tiles - #todo, #tiles), 20)
        end
        local sessionStarted = os.time()
        local tileNumber = #tiles - #todo
        local current, currentStarted
        local sessionWorkBefore = slices.work_s
        -- time left from this session's finished tiles (John, 2026-10-08: the estimate from cells
        -- measured so far climbed and climbed, since a tile's map objects take time but count no
        -- cells, and tiles differ): their seconds per cell × the cells of the tiles not finished,
        -- less the time already spent on the current one
        local finished = { seconds = 0, cells = 0, cells_left = 0 }
        for _, t in ipairs(todo) do finished.cells_left = finished.cells_left + t.cells end
        local function text()
            local elapsed = os.time() - sessionStarted
            local left = "time left known after this session's first tile"
            if finished.cells > 0 then
                local s = finished.seconds / finished.cells * finished.cells_left - (os.time() - currentStarted)
                left = "about " .. duration(math.max(60, s)) .. " left"
            end
            return string.format("tile %d of %d (%s, x %s to %s km, z %s to %s km): %s\nwhole map %d%%, %s this session, %s; the survey gets %d%% of the time",
                tileNumber, #tiles, current.name, km(current.x_min), km(current.x_max), km(current.z_min), km(current.z_max),
                status.phase, math.floor(100 * status.cells_done / totalCells), duration(elapsed), left,
                math.floor(100 * (slices.work_s - sessionWorkBefore) / math.max(1, elapsed)))
        end
        progress.describe = text   -- worked out each time it's shown
        for _, t in ipairs(todo) do
            current, currentStarted = t, os.time()
            tileNumber = tileNumber + 1
            local slicesBefore, workBefore, looksBefore = slices.count, slices.work_s, slices.looks
            callTimesLine()   -- from zero for this tile
            local cells, passTwoCells, objects = surveyTile(t, runFolder, status)
            local wall = math.max(1, os.time() - currentStarted)
            finished.seconds, finished.cells = finished.seconds + wall, finished.cells + t.cells
            finished.cells_left = finished.cells_left - t.cells
            log(string.format("%s done (%d of %d): %d cells, %d through to pass 2, %d map objects; whole map %d%%; "
                .. "%d s, %d slices (%.1f a second, %d looks), %.0f s of work (%d%% of the time); %s",
                t.name, tileNumber, #tiles, cells, passTwoCells, objects, math.floor(100 * status.cells_done / totalCells),
                wall, slices.count - slicesBefore, (slices.count - slicesBefore) / wall, slices.looks - looksBefore,
                slices.work_s - workBefore, 100 * (slices.work_s - workBefore) / wall, callTimesLine()))
        end
        progress.describe = nil

        local f = assert(io.open(runFolder .. "survey_complete.lua", "w"))
        f:write("-- Every tile of this run is measured (survey_spawn_sites.lua).\n\n")
        f:write("SURVEY_COMPLETE = " .. serialize({ finished = os.date("%Y-%m-%d %H:%M"), tiles = #tiles, cells = totalCells }) .. "\n")
        f:close()
        log("run " .. runName .. " complete")

        say("every tile measured; finding the sites (find_spawn_sites.py)", 20, true)
        local text = finishSites(repo, runName, progress)
        say("SURVEY DONE (" .. runName .. ", " .. #tiles .. " tiles).\n" .. text, 300, true)
    end)
end

-- ── start ───────────────────────────────────────────────────────

local function start()
    if not (lfs and io and os and os.clock) then
        say("needs a de-sanitized MissionScripting.lua (lfs, io, os).", 60)
        return
    end
    local areas = triggerZoneAreas()
    if #areas > 0 then
        startJob("test area survey", function(progress) surveyTestAreas(progress, areas) end)
        return
    end
    local repo = repositoryFolder()
    if not repo then
        say("the whole-map survey needs Saved Games\\DCS\\Scripts\\map_surveys\\local_paths.lua "
            .. "(MAP_SURVEY_PATHS.repository_folder), so it knows where to write.", 60)
        return
    end
    local area, why = readSurveyArea(repo)
    if not area then
        say("nothing to survey: no trigger zone in the mission, and " .. why
            .. "\n(draw the area on the F10 map and put its four GPS corners in that file, as Afghanistan's)", 60)
        return
    end
    local runs = runNames(measurementsFolder(repo))
    local newest = runs[#runs]
    local newestComplete = newest and fileExists(measurementsFolder(repo) .. newest .. "\\survey_complete.lua")

    local menu = missionCommands.addSubMenu("Spawn site survey")
    missionCommands.addCommand("Survey the map again", menu, function()
        surveyWholeMap(repo, area, os.date("%Y-%m-%d_%H%M"))
    end)
    missionCommands.addCommand("Find the sites again", menu, function()
        local names = runNames(measurementsFolder(repo))
        for i = #names, 1, -1 do
            if fileExists(measurementsFolder(repo) .. names[i] .. "\\survey_complete.lua") then
                findSitesAgain(repo, names[i])
                return
            end
        end
        say("no finished survey to find sites in yet", 15)
    end)

    if newest and not newestComplete then
        surveyWholeMap(repo, area, newest)
    elseif newestComplete then
        say("the " .. MAP .. " map was surveyed in run " .. newest .. "; its sites are in map_data\\" .. MAP_FOLDER
            .. "\\spawn_sites_index.lua and spawn_sites\\ (by tile).\nComms menu, Spawn site survey: \"Survey the map again\" (after a DCS map update) "
            .. "or \"Find the sites again\" (after a change to the site rules).", 120)
    else
        surveyWholeMap(repo, area, os.date("%Y-%m-%d_%H%M"))
    end
end

start()
