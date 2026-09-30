-- Logger: writes to DCS log (Saved Games\DCS\Logs\dcs.log) and optionally to screen.
-- All entries are prefixed with [DCS-MISSION] for easy grep.
-- Usage: Log.info("message"), Log.warn("..."), Log.error("..."), Log.debug("...")

Log = {}

local LEVEL = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local LEVEL_NAME = { [0] = "DEBUG", [1] = "INFO", [2] = "WARN", [3] = "ERROR" }

-- Set to LEVEL.INFO in production, LEVEL.DEBUG when diagnosing issues.
Log.currentLevel = LEVEL.INFO

local function write(level, msg)
    if level < Log.currentLevel then return end

    local t = timer and timer.getTime() or 0
    local line = string.format("[DCS-MISSION] [%s] [T+%.1fs] %s", LEVEL_NAME[level], t, msg)
    env.info(line)

    -- Warnings and errors also appear briefly on screen.
    if level >= LEVEL.WARN then
        trigger.action.outText(line, 20)
    end
end

function Log.debug(msg) write(LEVEL.DEBUG, msg) end
function Log.info(msg)  write(LEVEL.INFO,  msg) end
function Log.warn(msg)  write(LEVEL.WARN,  msg) end
function Log.error(msg) write(LEVEL.ERROR, msg) end

-- ── Error protection ─────────────────────────────────────────────
-- An error inside a timer function, event handler or F10 menu callback makes DCS
-- show a script error box and, for timers, stops the loop for good. Every callback
-- goes through Log.protect / Log.run instead: the error and its stack trace go to
-- dcs.log, the first error per label also shows on screen once, and play goes on.

local errorCounts = {}

local function reportError(label, err)
    errorCounts[label] = (errorCounts[label] or 0) + 1
    local count = errorCounts[label]
    env.info(string.format("[DCS-MISSION] [ERROR] %s (error #%d): %s", label, count, tostring(err)))
    if count == 1 then
        trigger.action.outText("Mission script error in " .. label .. " (details in dcs.log, play continues)", 10)
    end
end

local function traceback(err)
    if debug and debug.traceback then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
end

-- Runs fn(...) protected. Returns ok, then fn's first result.
function Log.run(label, fn, ...)
    local args  = { ... }
    local count = select("#", ...)
    local ok, result = xpcall(function() return fn(unpack(args, 1, count)) end, traceback)
    if not ok then
        reportError(label, result)
        return false, nil
    end
    return true, result
end

-- Returns a protected version of fn, for timer.scheduleFunction, event handlers and
-- menu callbacks. A protected timer function that fails returns nil, so a repeating
-- timer must reschedule itself through Log.repeating instead.
function Log.protect(label, fn)
    return function(...)
        local _, result = Log.run(label, fn, ...)
        return result
    end
end

-- Schedules fn(time) every `interval` seconds, starting at firstTime. fn's errors are
-- logged and the loop keeps going. fn may return a different next time to override
-- the interval once.
function Log.repeating(label, fn, firstTime, interval)
    timer.scheduleFunction(function(_, time)
        local _, nextTime = Log.run(label, fn, time)
        return nextTime or (time + interval)
    end, nil, firstTime)
end

-- Registers a world event handler whose onEvent is protected.
function Log.addEventHandler(label, onEvent)
    local handler = {}
    function handler:onEvent(event)
        Log.run(label, onEvent, event)
    end
    world.addEventHandler(handler)
    return handler
end

-- Dumps every group name to the log.
-- Run this once to verify group name strings match BASE_GROUPS in coalition_setup.lua.
function Log.dumpGroups()
    Log.info("=== GROUP DUMP START ===")
    local sides = { [0] = "NEUTRAL", [1] = "RED", [2] = "BLUE" }
    for _, side in ipairs({ coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL }) do
        local groups = coalition.getGroups(side)
        for _, grp in ipairs(groups or {}) do
            Log.info(string.format("  %-50s  coa=%s", grp:getName(), sides[side] or "?"))
        end
    end
    Log.info("=== GROUP DUMP END ===")
end

-- Activates each named late-activation group and logs every unit's type string.
-- Run once to verify type strings for units placed in ME debug groups.
function Log.dumpLateGroupUnits(names)
    Log.info("=== LATE GROUP UNIT DUMP START ===")
    for _, name in ipairs(names) do
        local grp = Group.getByName(name)
        if grp then
            grp:activate()
            local units = grp:getUnits()
            Log.info(string.format("  Group '%s' (%d units):", name, #(units or {})))
            for _, u in ipairs(units or {}) do
                Log.info(string.format("    unit '%s'  type='%s'", u:getName(), u:getTypeName()))
            end
        else
            Log.warn("dumpLateGroupUnits: group '" .. name .. "' not found — check ME group name")
        end
    end
    Log.info("=== LATE GROUP UNIT DUMP END ===")
end

-- Dumps every airbase name the map knows about to the log.
-- Run this once on a fresh mission to verify/correct airbase name strings.
function Log.dumpAirbases()
    Log.info("=== AIRBASE DUMP START ===")
    local all = world.getAirbases()
    if not all then
        Log.warn("world.getAirbases() returned nil")
        Log.info("=== AIRBASE DUMP END ===")
        return
    end
    local cats  = { [0] = "AIRDROME", [1] = "HELIPAD", [2] = "SHIP" }
    local sides = { [0] = "NEUTRAL",  [1] = "RED",     [2] = "BLUE" }
    local count = 0
    -- DCS returns a numerically-indexed table; ipairs is correct here
    for _, ab in ipairs(all) do
        count = count + 1
        local cat  = ab:getDesc().category
        local coa  = ab:getCoalition()
        local name = ab:getName()
        Log.info(string.format("  %-40s  cat=%-8s  coa=%s", name, cats[cat] or "?", sides[coa] or "?"))
    end
    if count == 0 then
        Log.warn("world.getAirbases() returned empty table — try calling later via timer")
    end
    Log.info("=== AIRBASE DUMP END ===")
end
