-- Logger: writes to dcs.log (under "SCRIPTING") and, for errors (and warnings with
-- CONFIG.WARNINGS_ON_SCREEN), to screen.
-- Every line is prefixed with the mission's log tag ([KOLA] on Kola, MISSION.log_tag) for grepping.
-- Usage: Log.info("message"), Log.warn("..."), Log.error("..."), Log.debug("...")

Log = {}

local LEVEL = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local LEVEL_NAME = { [0] = "DEBUG", [1] = "INFO", [2] = "WARN", [3] = "ERROR" }

Log.currentLevel = LEVEL.DEBUG

local function write(level, msg)
    if level < Log.currentLevel then return end
    local t = timer and timer.getTime() or 0
    local line = string.format("[%s] [%s] [T+%.1fs] %s", MISSION.log_tag, LEVEL_NAME[level], t, msg)
    env.info(line)
    if level >= LEVEL.ERROR or (level == LEVEL.WARN and CONFIG and CONFIG.WARNINGS_ON_SCREEN) then
        trigger.action.outText(line, 20)
    end
end

function Log.debug(msg) write(LEVEL.DEBUG, msg) end
function Log.info(msg)  write(LEVEL.INFO,  msg) end
function Log.warn(msg)  write(LEVEL.WARN,  msg) end
function Log.error(msg) write(LEVEL.ERROR, msg) end

