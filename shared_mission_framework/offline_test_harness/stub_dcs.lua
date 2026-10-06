-- Offline test harness: stand-ins for the DCS mission scripting API, so a mission's real
-- init.lua runs under luae.exe (DCS's own Lua 5.1, DCS World\bin\luae.exe) without DCS.
--
-- Not a simulation. Everything here is simple and fixed, so the same code with the same
-- seed always gives the same result: the harness compares a run before and after a
-- change, it doesn't judge whether a plan is realistic (shared_mission_framework plan.md,
-- *How the transfer is tested*).
--
-- What it stands in for:
--   terrain      flat ground at one height, land everywhere, the road next to a point is the
--                point itself, a road path is a straight line
--   coordinates  lat / lon from a flat projection around the saved world's first airbase
--   time         a mission clock the harness moves on itself (timer.scheduleFunction queue)
--   randomness   math.random from a fixed-seed generator (DCS seeds it differently each launch)
--   files        every write outside the output folder is sent into it; os.execute is only recorded
--
-- StubDcs.install(options) before loading anything:
--   output_folder     where every file goes (with a trailing backslash)
--   script_folders    { [name under Saved Games\DCS\Scripts] = folder on disk } (with trailing backslashes)
--   seed              the random generator's seed
--   world             the saved plan.world, for the coordinate stand-in

StubDcs = {
    log_lines = {},          -- every env.info / warning / error line, in order
    screen_texts = {},       -- every trigger.action.outText
    commands = {},           -- every os.execute command, never run
    redirected_writes = {},  -- { asked = path, written = path } for writes sent into the output folder
    scheduled = {},          -- the timer queue: { at, fn, arg, order }
    now = 0,                 -- mission time, seconds
}

local options

-- ── Random numbers ──────────────────────────────────────────────

-- Park and Miller's minimal standard generator: every product stays below 2^53, so Lua's
-- doubles hold it exactly and the sequence is the same on every machine (luae's own
-- math.random is the C rand(), whose first values after a seed are nearly linear in it).
local MODULUS, MULTIPLIER = 2147483647, 48271
local state = 1

local function seedRandom(seed)
    state = (seed * 7919) % MODULUS
    if state == 0 then state = 1 end
    for _ = 1, 50 do state = (state * MULTIPLIER) % MODULUS end
end

local function nextFraction()
    state = (state * MULTIPLIER) % MODULUS
    return (state - 1) / (MODULUS - 1)   -- [0, 1)
end

local function random(low, high)
    local f = nextFraction()
    if low == nil then return f end
    if high == nil then low, high = 1, low end
    return low + math.floor(f * (high - low + 1))
end

-- ── Paths ───────────────────────────────────────────────────────

local function normalised(path)
    return (path:gsub("/", "\\")):lower()
end

local function insideOutput(path)
    local out = normalised(options.output_folder)
    return normalised(path):sub(1, #out) == out
end

-- A Saved Games\DCS\Scripts\<name>\ path → the folder on disk it stands for, else nil.
local function scriptOnDisk(path)
    local scripts = normalised(options.output_folder .. "Scripts\\")
    local p = normalised(path)
    if p:sub(1, #scripts) ~= scripts then return nil end
    for name, folder in pairs(options.script_folders) do
        local prefix = scripts .. normalised(name) .. "\\"
        if p:sub(1, #prefix) == prefix then
            return folder .. path:gsub("/", "\\"):sub(#prefix + 1)
        end
    end
    return nil
end

-- Where on disk a path the mission loads really is (its Saved Games\DCS\Scripts\ path stands
-- for a folder in the repository).
function StubDcs.diskPathOf(path) return scriptOnDisk(path) or path end

-- A write outside the output folder lands in output\redirected\<file name> instead.
local function safeWritePath(path)
    if insideOutput(path) then return path end
    local fileName = path:gsub("/", "\\"):match("([^\\]+)$")
    local written = options.output_folder .. "redirected\\" .. fileName
    StubDcs.redirected_writes[#StubDcs.redirected_writes + 1] = { asked = path, written = written }
    return written
end

-- ── Install ─────────────────────────────────────────────────────

function StubDcs.install(opts)
    options = opts
    seedRandom(opts.seed)
    math.random = random
    math.randomseed = function() end

    -- the real dofile, io.open and os, kept for the harness itself
    StubDcs.realDofile = dofile
    StubDcs.realOpen = io.open
    local realExecute = os.execute

    os.execute("mkdir \"" .. opts.output_folder .. "redirected\" 2>nul")

    dofile = function(path)
        return StubDcs.realDofile(scriptOnDisk(path) or path)
    end
    StubDcs.realLoadfile = loadfile
    loadfile = function(path)
        return StubDcs.realLoadfile(scriptOnDisk(path) or path)
    end
    io.open = function(path, mode)
        mode = mode or "r"
        if mode:find("[wa+]") then path = safeWritePath(path) end
        return StubDcs.realOpen(path, mode)
    end
    os.execute = function(command)
        StubDcs.commands[#StubDcs.commands + 1] = command or ""
        return 0
    end
    os.remove = function(path)
        if insideOutput(path) then return true end
        StubDcs.commands[#StubDcs.commands + 1] = "os.remove " .. tostring(path) .. " (refused)"
        return nil, "refused by the harness"
    end
    os.rename = function(from, to)
        StubDcs.commands[#StubDcs.commands + 1] = "os.rename " .. tostring(from) .. " (refused)"
        return nil, "refused by the harness"
    end
    StubDcs.realExecute = realExecute

    -- the wall clock is the mission clock from a fixed date (1 January 2026, 08:00), so file
    -- names, dates and timings come out the same every run
    local realDate, realTime = os.date, os.time
    local FIXED_START = realTime({ year = 2026, month = 1, day = 1, hour = 8, min = 0, sec = 0 })
    os.date = function(format, at) return realDate(format, at or (FIXED_START + math.floor(StubDcs.now))) end
    os.time = function(fields) return fields and realTime(fields) or (FIXED_START + math.floor(StubDcs.now)) end
    os.clock = function() return StubDcs.now end

    lfs = {
        writedir = function() return opts.output_folder end,
        mkdir = function(path)
            if insideOutput(path) then realExecute("mkdir \"" .. path .. "\" 2>nul") end
            return true
        end,
        attributes = function(path) return nil end,
    }

    env = {
        info = function(text) StubDcs.log_lines[#StubDcs.log_lines + 1] = tostring(text) end,
        warning = function(text) StubDcs.log_lines[#StubDcs.log_lines + 1] = "WARNING " .. tostring(text) end,
        error = function(text) StubDcs.log_lines[#StubDcs.log_lines + 1] = "ERROR " .. tostring(text) end,
        mission = { date = { Year = 2026, Month = 1, Day = 1 }, start_time = 28800, weather = {} },
    }

    timer = {
        getTime = function() return StubDcs.now end,
        getAbsTime = function() return env.mission.start_time + StubDcs.now end,
        scheduleFunction = function(fn, arg, at)
            local entry = { at = at, fn = fn, arg = arg, order = #StubDcs.scheduled + 1 }
            StubDcs.scheduled[#StubDcs.scheduled + 1] = entry
            return entry
        end,
        removeFunction = function(entry)
            for i, e in ipairs(StubDcs.scheduled) do
                if e == entry then table.remove(StubDcs.scheduled, i) return end
            end
        end,
    }

    trigger = {
        action = {
            outText = function(text) StubDcs.screen_texts[#StubDcs.screen_texts + 1] = tostring(text) end,
        },
    }

    coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }

    land = {
        SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 },
        getHeight = function() return 100 end,
        getSurfaceType = function() return 1 end,
        getClosestPointOnRoads = function(_, x, y) return x, y end,
        findPathOnRoads = function(_, x1, y1, x2, y2) return { { x = x1, y = y1 }, { x = x2, y = y2 } } end,
    }

    -- lat / lon from a flat projection around the saved world's first airbase (sorted by
    -- name): any map, deterministic, close enough for anything that reads it offline
    local origin
    for _, name in ipairs(opts.world.airbase_list) do
        origin = opts.world.airbases[name].pos
        break
    end
    local METRES_PER_DEGREE = 111320
    local lonScale = METRES_PER_DEGREE * math.cos(math.rad(origin.lat))
    coord = {
        LOtoLL = function(p)
            return origin.lat + (p.x - origin.x) / METRES_PER_DEGREE,
                   origin.lon + (p.z - origin.z) / lonScale, p.y or 0
        end,
        LLtoLO = function(lat, lon)
            return { x = origin.x + (lat - origin.lat) * METRES_PER_DEGREE, y = 0,
                     z = origin.z + (lon - origin.lon) * lonScale }
        end,
        LLtoMGRS = function()
            return { UTMZone = "35W", MGRSDigraph = "NQ", Easting = 12345, Northing = 67890 }
        end,
    }

    atmosphere = {
        getWind = function() return { x = -3, y = 0, z = 2 } end,
        getTemperatureAndPressure = function() return 273.15, 101325 end,
    }
end

-- Runs the timer queue up to `until_s` of mission time, earliest first (ties in the order
-- scheduled). A function that returns a number is scheduled again at that time, as in DCS.
-- An error in one is logged as DCS does and the queue goes on.
function StubDcs.runClock(until_s)
    while true do
        table.sort(StubDcs.scheduled, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            return a.order < b.order
        end)
        local entry = StubDcs.scheduled[1]
        if not entry or entry.at > until_s then break end
        table.remove(StubDcs.scheduled, 1)
        StubDcs.now = math.max(StubDcs.now, entry.at)
        local ok, again = pcall(entry.fn, entry.arg, StubDcs.now)
        if not ok then
            env.error("scheduled function failed: " .. tostring(again))
        elseif type(again) == "number" then
            entry.at = again
            entry.order = #StubDcs.scheduled + 1000000 + entry.order
            StubDcs.scheduled[#StubDcs.scheduled + 1] = entry
        end
    end
    StubDcs.now = math.max(StubDcs.now, until_s)
end
