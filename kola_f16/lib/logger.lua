-- Logger: writes to dcs.log (under "SCRIPTING") and, for warnings and errors, to screen.
-- Every line is prefixed [KOLA] for grepping.
-- Usage: Log.info("message"), Log.warn("..."), Log.error("..."), Log.debug("...")

Log = {}

local LEVEL = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local LEVEL_NAME = { [0] = "DEBUG", [1] = "INFO", [2] = "WARN", [3] = "ERROR" }

Log.currentLevel = LEVEL.DEBUG

local function write(level, msg)
    if level < Log.currentLevel then return end
    local t = timer and timer.getTime() or 0
    local line = string.format("[KOLA] [%s] [T+%.1fs] %s", LEVEL_NAME[level], t, msg)
    env.info(line)
    if level >= LEVEL.WARN then
        trigger.action.outText(line, 20)
    end
end

function Log.debug(msg) write(LEVEL.DEBUG, msg) end
function Log.info(msg)  write(LEVEL.INFO,  msg) end
function Log.warn(msg)  write(LEVEL.WARN,  msg) end
function Log.error(msg) write(LEVEL.ERROR, msg) end

-- ── Dumps: run once on a new .miz to pin down what DCS actually reports ──

-- Every airbase the map knows about, with category and current coalition.
function Log.dumpAirbases()
    Log.info("=== AIRBASE DUMP START ===")
    local all = world.getAirbases()
    local cats  = { [0] = "AIRDROME", [1] = "HELIPAD", [2] = "SHIP" }
    local sides = { [0] = "NEUTRAL",  [1] = "RED",     [2] = "BLUE" }
    local count = 0
    for _, ab in ipairs(all or {}) do
        count = count + 1
        local p = ab:getPoint()
        Log.info(string.format("  %-28s cat=%-8s coa=%-7s x=%.0f z=%.0f",
            ab:getName(), cats[ab:getDesc().category] or "?", sides[ab:getCoalition()] or "?", p.x, p.z))
    end
    if count == 0 then
        Log.warn("world.getAirbases() returned nothing — call later via timer")
    end
    Log.info("=== AIRBASE DUMP END (" .. count .. ") ===")
end

-- Every group name by coalition.
function Log.dumpGroups()
    Log.info("=== GROUP DUMP START ===")
    local sides = { [0] = "NEUTRAL", [1] = "RED", [2] = "BLUE" }
    for _, side in ipairs({ coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL }) do
        for _, grp in ipairs(coalition.getGroups(side) or {}) do
            Log.info(string.format("  %-50s coa=%s", grp:getName(), sides[side]))
        end
    end
    Log.info("=== GROUP DUMP END ===")
end

-- Activates each named late-activation group and logs its units' type strings.
function Log.dumpLateGroupUnits(names)
    Log.info("=== LATE GROUP UNIT DUMP START ===")
    for _, name in ipairs(names) do
        local grp = Group.getByName(name)
        if grp then
            grp:activate()
            local units = grp:getUnits() or {}
            Log.info(string.format("  Group '%s' (%d units):", name, #units))
            for _, u in ipairs(units) do
                Log.info(string.format("    unit '%s'  type='%s'", u:getName(), u:getTypeName()))
            end
        else
            Log.warn("dumpLateGroupUnits: group '" .. name .. "' not found")
        end
    end
    Log.info("=== LATE GROUP UNIT DUMP END ===")
end

-- The mission's weather/date/time tables as DCS exposes them at runtime. Run once to
-- pin the real field names before the planner relies on them (DCS 2.9 changed fog and
-- cloud presets).
function Log.dumpWeather()
    Log.info("=== WEATHER DUMP START ===")
    local m = env.mission
    Log.info("  date        " .. Util.serialize(m.date, "", true))
    Log.info("  start_time  " .. tostring(m.start_time) .. "  (abs now " .. tostring(timer.getAbsTime()) .. ")")
    Log.info("  weather:\n" .. Util.serialize(m.weather, "    "))
    Log.info("=== WEATHER DUMP END ===")
end
