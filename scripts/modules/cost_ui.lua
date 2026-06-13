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
            "[%s] %-18s\n   Spent: %.2fM  Earned: %.2fM\n   Net:   %s%.2fM",
            indicator, playerName, s.spent, s.earned, sign, s.net
        ))
        table.insert(lines, "----------------------------------")
        hasAny = true
    end

    if not hasAny then
        table.insert(lines, "  No score data yet.")
        table.insert(lines, "----------------------------------")
    end

    local totalSpent, totalEarned, totalNet, _ = CostTracker.getTeamTotals()
    local teamSign      = totalNet >= 0 and "+" or ""
    local teamIndicator = totalNet >= 0 and "+" or "-"
    table.insert(lines, string.format(
        "[%s] TEAM TOTAL\n   Spent: %.2fM  Earned: %.2fM\n   Net:   %s%.2fM",
        teamIndicator, totalSpent, totalEarned, teamSign, totalNet
    ))
    table.insert(lines, "==================================")

    return table.concat(lines, "\n")
end

-- ============================================================
--  INTERNAL: SEND SCORE TO ALL PLAYER GROUPS
-- ============================================================

local function broadcastScore()
    local msg      = buildScoreString()
    local duration = COST_CONFIG.display.displayDuration

    -- Per-player delivery via slot lookup
    for _, playerName in ipairs(net.get_player_list()) do
        local unitId = net.get_slot(playerName)
        if unitId then
            local unit = Unit.getById(unitId)  -- getById takes numeric ID; getByName takes string name
            if unit and unit:isExist() then
                local group = unit:getGroup()
                if group then
                    trigger.action.outTextForGroup(group:getID(), msg, duration, false)
                end
            end
        end
    end

    -- Coalition-wide fallback in case slot lookup returns nothing
    trigger.action.outTextForCoalition(coalition.side.BLUE, msg, duration, false)
end

-- ============================================================
--  F10 MENU: "Show Mission Score" per player group
--  Registered once per group; re-checked every 30s for late joiners.
-- ============================================================

local menuRegistered = {}

local function registerF10Menus()
    local menuName = COST_CONFIG.display.f10MenuName
    local groups   = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE)
    for _, group in ipairs(groups or {}) do
        local gid = group:getID()
        if not menuRegistered[gid] then
            for _, unit in ipairs(group:getUnits()) do
                if unit:getPlayerName() then
                    missionCommands.addCommandForGroup(
                        gid,
                        menuName,
                        nil,
                        function()
                            local msg = buildScoreString()
                            trigger.action.outTextForGroup(
                                gid, msg,
                                COST_CONFIG.display.displayDuration,
                                false
                            )
                        end
                    )
                    menuRegistered[gid] = true
                    env.info(string.format("[CostUI] F10 menu registered for group %d", gid))
                    break
                end
            end
        end
    end
end

-- ============================================================
--  SCHEDULER: PERIODIC AUTO-DISPLAY + MENU REFRESH
-- ============================================================

local autoDisplayInterval = COST_CONFIG.display.intervalSeconds
local menuRefreshInterval  = 30

local lastAutoDisplay = 0
local lastMenuRefresh = 0

local function onTick()
    local now = timer.getTime()

    if (now - lastAutoDisplay) >= autoDisplayInterval then
        lastAutoDisplay = now
        broadcastScore()
        env.info("[CostUI] Auto-display score broadcast sent")
    end

    if (now - lastMenuRefresh) >= menuRefreshInterval then
        lastMenuRefresh = now
        registerF10Menus()
    end

    return timer.getTime() + 5
end

-- ============================================================
--  INIT: deferred 2s after module load
-- ============================================================

timer.scheduleFunction(function()
    env.info("[CostUI] Initializing cost display system")
    registerF10Menus()
    lastAutoDisplay = timer.getTime()
    lastMenuRefresh = timer.getTime()
    timer.scheduleFunction(onTick, nil, timer.getTime() + 5)
    env.info("[CostUI] Cost display system ready")
    return nil
end, nil, timer.getTime() + 2)

-- ============================================================
--  END OF cost_ui.lua
-- ============================================================
