-- ============================================================
--  cost_ui.lua
--  Mission Cost Counter – Display & F10 Menu
--
--  Requires: cost_config.lua, cost_logic.lua (loaded first)
--
--  Handles:
--    - Periodic auto-display every N minutes to all players
--    - F10 radio menu "Show Mission Score" per player group
-- ============================================================

CostUI = {}

-- ============================================================
--  INTERNAL: BUILD DISPLAY STRING
-- ============================================================

local function buildScoreString()
    local lines = {}

    table.insert(lines, "==================================")
    table.insert(lines, "      MISSION COST REPORT         ")
    table.insert(lines, "==================================")

    local hasAny = false
    for playerName, _ in pairs(CostTracker.playerScores) do
        local s    = CostTracker.playerScores[playerName]
        local sign = s.net >= 0 and "+" or ""
        local indicator = s.net >= 0 and "+" or "-"

        table.insert(lines, string.format(
            "[%s] %-18s\n   Spent: %.2fM  Destroyed: %.2fM\n   Net:   %s%.2fM",
            indicator, playerName, s.spent, s.destroyed, sign, s.net
        ))
        table.insert(lines, "----------------------------------")
        hasAny = true
    end

    if not hasAny then
        table.insert(lines, "  No score data yet.")
        table.insert(lines, "----------------------------------")
    end

    local totalSpent, totalDestroyed, totalNet, _ = CostTracker.getTeamTotals()
    local teamSign      = totalNet >= 0 and "+" or ""
    local teamIndicator = totalNet >= 0 and "+" or "-"
    table.insert(lines, string.format(
        "[%s] TEAM TOTAL\n   Spent: %.2fM  Destroyed: %.2fM\n   Net:   %s%.2fM",
        teamIndicator, totalSpent, totalDestroyed, teamSign, totalNet
    ))
    table.insert(lines, "==================================")

    return table.concat(lines, "\n")
end

-- ============================================================
--  INTERNAL: SEND SCORE TO ALL PLAYER GROUPS
-- ============================================================

local function broadcastScore()
    local msg = buildScoreString()
    trigger.action.outTextForCoalition(coalition.side.BLUE, msg, COST_CONFIG.display.displayDuration, false)
end

-- ============================================================
--  F10 MENU: "Show Mission Score" per player group
--  Added when a player takes an aircraft (birth / enter events), with a periodic
--  scan as a backstop for anything the events missed.
-- ============================================================

local menuRegistered = {}

local function showScoreToGroup(groupId)
    trigger.action.outTextForGroup(groupId, buildScoreString(),
        COST_CONFIG.display.displayDuration, false)
end

local function registerMenuForGroup(group)
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    if menuRegistered[groupId] then return end
    missionCommands.addCommandForGroup(groupId, COST_CONFIG.display.f10MenuName, nil,
        Log.protect("CostUI score menu", showScoreToGroup), groupId)
    menuRegistered[groupId] = true
    env.info(string.format("[CostUI] F10 menu registered for group %d (%s)", groupId, group:getName()))
end

local function groupHasPlayer(group)
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit:isExist() and unit:getPlayerName() then return true end
    end
    return false
end

-- One group whose units are mid-despawn must not stop the scan of the rest.
local function registerMenusForPlayerGroups()
    for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        for _, group in ipairs(coalition.getGroups(coalition.side.BLUE, category) or {}) do
            local ok, hasPlayer = pcall(groupHasPlayer, group)
            if ok and hasPlayer then registerMenuForGroup(group) end
        end
    end
end

local function onPlayerTakesAircraft(event)
    if event.id ~= world.event.S_EVENT_BIRTH and event.id ~= world.event.S_EVENT_PLAYER_ENTER_UNIT then return end
    local unit = event.initiator
    if not unit or Object.getCategory(unit) ~= Object.Category.UNIT then return end
    if not unit:getPlayerName() or unit:getCoalition() ~= coalition.side.BLUE then return end
    registerMenuForGroup(unit:getGroup())
end

-- ============================================================
--  SCHEDULERS: PERIODIC AUTO-DISPLAY + MENU BACKSTOP
-- ============================================================

local autoDisplayInterval = COST_CONFIG.display.intervalSeconds
local menuRefreshInterval = 30

-- ============================================================
--  INIT: deferred 2s after module load
-- ============================================================

timer.scheduleFunction(Log.protect("CostUI init", function()
    env.info("[CostUI] Initializing cost display system")
    Log.addEventHandler("CostUI menus", onPlayerTakesAircraft)
    registerMenusForPlayerGroups()
    Log.repeating("CostUI menu scan", registerMenusForPlayerGroups,
        timer.getTime() + menuRefreshInterval, menuRefreshInterval)
    Log.repeating("CostUI score broadcast", function()
        broadcastScore()
        env.info("[CostUI] Auto-display score broadcast sent")
    end, timer.getTime() + autoDisplayInterval, autoDisplayInterval)
    env.info("[CostUI] Cost display system ready")
end), nil, timer.getTime() + 2)

-- ============================================================
--  END OF cost_ui.lua
-- ============================================================
