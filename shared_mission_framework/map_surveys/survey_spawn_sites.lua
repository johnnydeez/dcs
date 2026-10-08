-- Spawn site survey: measures a map's terrain so map_data_tools\find_spawn_sites.py can find
-- the clear, flat places where anything fits (a group of ground units, a large SAM site, a
-- target; missions\afghanistan_campaign\mission_design.md, *Map data: the site survey*).
-- Runs in a survey mission of its own, started by hand, never in a flyable mission.
-- Standalone: loads nothing from the framework; works on any map (env.mission.theatre).
--
-- For now it surveys test areas only, to try the site rules before the whole map (John,
-- 2026-10-07): a square SURVEY_AREA_SIZE_M wide around each airbase in TEST_AREAS_AROUND,
-- one after the other in one run, skipping an area already surveyed (its file exists:
-- delete it to survey it again). A trigger zone in the survey mission, if there is one, is
-- surveyed instead (its name names the area).
-- Hands-off (John: "I just want you to populate the map"): when the areas are done it runs
-- map_data_tools\find_spawn_sites.cmd itself, then show_spawn_sites.lua, so the sites appear
-- on the F10 map at the end of the same run. Where the repository is comes from
-- Saved Games\DCS\Scripts\map_surveys\local_paths.lua (MAP_SURVEY_PATHS.repository_folder),
-- a file beside the copied scripts, never in the repository (bug 76: no Windows user paths
-- in it); without it the run ends with the command to type.
-- The survey mission (find_spawn_sites.py make-missions writes it): one trigger
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\survey_spawn_sites.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io / os).
--
-- Per area, a little at a time on a timer so DCS keeps running:
--   pass 1  every PASS_1_CELL_M cell: PASS_1_POINTS² heights and surface types;
--   pass 2  the cells within PASS_2_MAX_RISE_M rise and dry (loose on purpose): heights and
--           surface types every PASS_2_STEP_M, edges included, and the nearest road;
--   objects the map's scenery objects (buildings, walls, rubbish, containers …), one search
--           per OBJECT_TILE_M tile: a count per cell, and on pass 2 cells a count per
--           PASS_2_STEP_M square and a tally by type.
-- Writes raw measurements only, one file per area: Saved Games\DCS\map_surveys\<map>\
-- area_<name>.lua (SURVEYED_AREA). Which places are sites is decided in Python, so its
-- rules can change without flying this again. Trees are invisible to every DCS API (Kola
-- probes, 2026-09-23): nothing here sees them.
-- What the probe (probe_terrain_survey_costs.lua, 2026-10-07) taught: no railway lookups
-- (~0.2 s a call on Afghanistan, which has no railways); object searches on 5 km tiles (one
-- 10 km tile over Kabul held 752,000 objects, a 2 s stall); objects stored as counts, not
-- one by one (54 MB for one 60 km test area); DCS has no math.randomseed.

local SURVEY_AREA_SIZE_M    = 30000
-- an area around each (DCS's airbase names). The two test areas after Bagram / Kabul (from the
-- probe), chosen 2026-10-08 for the terrain it didn't have: Kandahar, the south's open desert
-- and dunes; Jalalabad, a narrow green river valley between mountains (slopes and water).
-- Other candidates: "Camp Bastion" (Helmand's green zone), "Herat" (the west's plains),
-- "Maymana Zahiraddin Faryabi" (the north)
local TEST_AREAS_AROUND     = { "Kandahar", "Jalalabad" }
local PASS_1_CELL_M         = 1000
local PASS_1_POINTS         = 3                       -- per side, at the centre and ±PASS_1_SPREAD_M
local PASS_1_SPREAD_M       = 400
local PASS_2_MAX_RISE_M     = 60                      -- pass 1's highest − lowest point
local PASS_2_STEP_M         = 100
local OBJECT_TILE_M         = 5000
local TICK_S                = 0.05
local BUDGET_S              = 0.04                    -- wall time of work per tick
local PROGRESS_EVERY_S      = 10

local MAP     = (env.mission and env.mission.theatre) or "unknown_map"
local OUT_DIR = lfs.writedir() .. "map_surveys\\" .. MAP .. "\\"

local function log(msg) env.info("[SPAWN SITE SURVEY] " .. msg) end
local function say(msg, s) trigger.action.outText("SPAWN SITE SURVEY: " .. msg, s or 15) end
local function round(v) return math.floor(v + 0.5) end
local function clock() return os.clock() end

-- ── DCS calls ───────────────────────────────────────────────────

local SURFACE_LETTER = {}   -- L land, R road, W water, S shallow water, U runway
for name, v in pairs(land.SurfaceType) do
    SURFACE_LETTER[v] = ({ LAND = "L", ROAD = "R", WATER = "W", SHALLOW_WATER = "S", RUNWAY = "U" })[name] or "?"
end

local function height(x, z) return land.getHeight({ x = x, y = z }) end
local function surface(x, z) return SURFACE_LETTER[land.getSurfaceType({ x = x, y = z })] or "?" end

local function distanceToRoad(x, z)
    local ok, px, pz = pcall(land.getClosestPointOnRoads, "roads", x, z)
    if not ok or not px then return nil end
    return round(math.sqrt((px - x) ^ 2 + (pz - z) ^ 2))
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

-- ── work on a timer ─────────────────────────────────────────────

local tickStarted = 0
local function pause()
    if clock() - tickStarted >= BUDGET_S then coroutine.yield() end
end

-- ── the areas ───────────────────────────────────────────────────

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

local function areasToSurvey()
    local areas = {}
    local zones = env.mission and env.mission.triggers and env.mission.triggers.zones or {}
    for _, z in ipairs(zones) do
        -- the mission editor calls east `y`
        areas[#areas + 1] = squareAround(z.name or ("zone_" .. tostring(z.zoneId)), z.x, z.y, "around the trigger zone " .. tostring(z.name))
    end
    if #areas > 0 then return areas end
    local byName = {}
    for _, ab in ipairs(world.getAirbases() or {}) do byName[ab:getName()] = ab end
    for _, name in ipairs(TEST_AREAS_AROUND) do
        local ab = byName[name]
        if ab then
            local p = ab:getPoint()
            areas[#areas + 1] = squareAround(name, p.x, p.z, "around " .. name)
        else
            log("no airbase named " .. name .. " on this map: its area is left out")
        end
    end
    return areas
end

local function alreadySurveyed(area)
    local f = io.open(OUT_DIR .. area.file, "r")
    if f then f:close() end
    return f ~= nil
end

-- map_data_tools\find_spawn_sites.cmd, then the viewer script, so the sites show on the
-- F10 map. Returns nil, or what went wrong.
local function findAndShowSites()
    MAP_SURVEY_PATHS = nil
    pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\local_paths.lua")
    local repo = MAP_SURVEY_PATHS and MAP_SURVEY_PATHS.repository_folder
    if not repo then
        return "sites not found yet: no Scripts\\map_surveys\\local_paths.lua, so the tool's place isn't known. "
            .. "Run: python shared_mission_framework\\map_data_tools\\find_spawn_sites.py"
    end
    local logFile = OUT_DIR .. "find_spawn_sites.log"
    -- DCS's Lua runs nothing from os.execute past ~260 characters, so the steps live in the
    -- .cmd; cmd /c needs the whole line quoted once more
    local cmd = string.format('""%s\\shared_mission_framework\\map_data_tools\\find_spawn_sites.cmd" "%s""', repo, logFile)
    log("running: " .. cmd)
    if #cmd > 250 then
        return string.format("sites not found yet: the command is %d characters, too long for DCS's os.execute (~260). "
            .. "Run: python shared_mission_framework\\map_data_tools\\find_spawn_sites.py", #cmd)
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
    if not ((rc == 0 or rc == true) and (lines[#lines] or ""):match("^done")) then
        return "find_spawn_sites.py FAILED: see " .. logFile
    end
    local okShow, err = pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\show_spawn_sites.lua")
    if not okShow then return "sites found, but showing them failed: " .. tostring(err) end
    return nil
end

-- ── the passes ──────────────────────────────────────────────────

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
-- row from the south-west corner (rows go north, x; points within a row go east, z).
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
    return { points_per_side = n + 1, h = heights, s = table.concat(letters),
             road_m = distanceToRoad(x0 + PASS_1_CELL_M / 2, z0 + PASS_1_CELL_M / 2) }
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

    local tileRadius = OBJECT_TILE_M * math.sqrt(2) / 2 + 1
    for tx = area.x_min, area.x_max - 1, OBJECT_TILE_M do
        for tz = area.z_min, area.z_max - 1, OBJECT_TILE_M do
            local t0 = clock()
            local centre = { x = tx + OBJECT_TILE_M / 2, z = tz + OBJECT_TILE_M / 2 }
            local volume = { id = world.VolumeType.SPHERE,
                             params = { point = { x = centre.x, y = height(centre.x, centre.z), z = centre.z }, radius = tileRadius } }
            local ok, err = pcall(world.searchObjects, Object.Category.SCENERY, volume, function(obj)
                local okP, p = pcall(obj.getPoint, obj)
                if okP and p and p.x >= tx and p.x < tx + OBJECT_TILE_M and p.z >= tz and p.z < tz + OBJECT_TILE_M
                   and p.x < area.x_max and p.z < area.z_max then
                    local row = math.floor((p.x - area.x_min) / PASS_1_CELL_M)
                    local col = math.floor((p.z - area.z_min) / PASS_1_CELL_M)
                    local cell = cells[cellKey(row, col)]
                    if cell then
                        cell.objects = cell.objects + 1
                        timing.objects = timing.objects + 1
                        local two = cell.pass_2
                        if two then
                            local i = math.min(squaresPerSide - 1, math.floor((p.x - cell.x) / PASS_2_STEP_M))
                            local j = math.min(squaresPerSide - 1, math.floor((p.z - cell.z) / PASS_2_STEP_M))
                            two.squares = two.squares or {}
                            local k = i * squaresPerSide + j + 1
                            two.squares[k] = (two.squares[k] or 0) + 1
                            local okT, tn = pcall(obj.getTypeName, obj)
                            tn = okT and tn or "?"
                            two.types = two.types or {}
                            two.types[tn] = (two.types[tn] or 0) + 1
                        end
                    end
                end
                return true
            end)
            if not ok then log("searchObjects failed: " .. tostring(err)) end
            local s = clock() - t0
            timing.objects_s = timing.objects_s + s
            timing.longest_search_s = math.max(timing.longest_search_s, s)
            timing.tiles = timing.tiles + 1
            progress.text = string.format("area %d of %d (%s): map objects, tile %d", index, count, area.name, timing.tiles)
            coroutine.yield()   -- one tile per tick: a single search can't be split
        end
    end
    -- the squares as a full list of counts (row by row, as the points), so the file is plain
    for _, cell in ipairs(list) do
        local two = cell.pass_2
        if two then
            local full = {}
            for k = 1, squaresPerSide * squaresPerSide do full[k] = (two.squares and two.squares[k]) or 0 end
            two.squares = full
            two.squares_per_side = squaresPerSide
        end
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
        "-- centre, squares (map objects per step_m square, row by row), types (objects by type name).",
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

-- ── run ─────────────────────────────────────────────────────────

local function work(progress)
    local areas = areasToSurvey()
    if #areas == 0 then
        say("nothing to survey: no trigger zone in the mission and no airbase named " .. table.concat(TEST_AREAS_AROUND, " / "), 60)
        return
    end
    local report = {}
    for i, area in ipairs(areas) do
        if alreadySurveyed(area) then
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
    timer.scheduleFunction(tick, nil, timer.getTime() + 1)
end

start()
