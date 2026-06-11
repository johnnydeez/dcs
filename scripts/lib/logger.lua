-- Logger: writes to DCS log (Saved Games\DCS\Logs\dcs.log) and optionally to screen.
-- All entries are prefixed with [DCS-MISSION] for easy grep.
-- Usage: Log.info("message"), Log.warn("..."), Log.error("..."), Log.debug("...")

Log = {}

local LEVEL = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local LEVEL_NAME = { [0] = "DEBUG", [1] = "INFO", [2] = "WARN", [3] = "ERROR" }

-- Set to LEVEL.INFO in production, LEVEL.DEBUG when diagnosing issues.
Log.currentLevel = LEVEL.DEBUG

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

-- Dumps every airbase name the map knows about to the log.
-- Run this once on a fresh mission to verify/correct airbase name strings.
function Log.dumpAirbases()
    Log.info("=== AIRBASE DUMP START ===")
    local all = world.getAirbases()
    local cats = { [0] = "AIRDROME", [1] = "HELIPAD", [2] = "SHIP" }
    local sides = { [0] = "NEUTRAL", [1] = "RED", [2] = "BLUE" }
    for _, ab in pairs(all) do
        local cat  = ab:getDesc().category
        local coa  = ab:getCoalition()
        local name = ab:getName()
        Log.info(string.format("  %-40s  cat=%-8s  coa=%s", name, cats[cat] or "?", sides[coa] or "?"))
    end
    Log.info("=== AIRBASE DUMP END ===")
end
