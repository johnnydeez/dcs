-- ============================================================
--  cost_logic.lua
--  Mission Cost Counter – Event Handler & Score Engine
--
--  Requires: cost_config.lua (loaded first in mission)
--  Consumed by: cost_ui.lua (reads CostTracker.playerScores)
--
--  Load order in init.lua:
--    1. cost_config.lua
--    2. cost_logic.lua
--    3. cost_ui.lua
-- ============================================================

CostTracker = {}

-- ============================================================
--  STATE TABLES
-- ============================================================

-- Per-player running totals.
-- Key   = player name string (as returned by unit:getPlayerName())
-- Value = { spent, earned, net }
CostTracker.playerScores = {}

-- Tracks which unit IDs have safely landed at a blue airfield.
-- Cleared when the unit is destroyed (one-time flag per sortie).
-- Key = unitID (number), Value = true
CostTracker.safeUnits = {}

-- Tracks which unit IDs have ejected — prevents safe-landing
-- credit even if the empty aircraft somehow touches down.
-- Key = unitID (number), Value = true
CostTracker.ejectedUnits = {}

-- Kill attribution: maps dead unit ID -> player name who last hit it.
-- Updated on S_EVENT_HIT, consumed on S_EVENT_DEAD.
-- Key = unitID (number), Value = playerName (string)
CostTracker.lastHitBy = {}

-- ============================================================
--  INTERNAL HELPERS
-- ============================================================

-- Returns the player name for a unit, or nil if AI / invalid.
local function getPlayerName(unit)
    if not unit or not unit:isExist() then return nil end
    return unit:getPlayerName()  -- nil for AI units
end

-- Looks up a value in a config table with fallback to "default".
local function lookup(tbl, key)
    if tbl[key] ~= nil then
        return tbl[key]
    end
    return tbl["default"] or 0
end

local function getMunitionCost(typeName)
    return lookup(COST_CONFIG.munitionCost, typeName)
end

local function getKillValue(typeName)
    return lookup(COST_CONFIG.killValue, typeName)
end

local function getAircraftCost(typeName)
    return lookup(COST_CONFIG.aircraftCost, typeName)
end

-- Returns true if the unit belongs to the red coalition.
local function isEnemyUnit(unit)
    if not unit or not unit:isExist() then return false end
    return unit:getCoalition() == coalition.side.RED
end

-- ============================================================
--  SCORE MANAGEMENT
-- ============================================================

local function ensurePlayer(playerName)
    if not playerName then return end
    if not CostTracker.playerScores[playerName] then
        CostTracker.playerScores[playerName] = {
            spent  = 0,
            earned = 0,
            net    = 0,
        }
    end
end

-- Adds to 'spent' (munitions, lost aircraft). Value should be positive.
local function addSpent(playerName, amount)
    if not playerName or amount <= 0 then return end
    ensurePlayer(playerName)
    local s = CostTracker.playerScores[playerName]
    s.spent  = s.spent + amount
    s.net    = s.earned - s.spent
    env.info(string.format("[CostTracker] %s SPENT %.3fM | spent=%.3f earned=%.3f net=%.3f",
        playerName, amount, s.spent, s.earned, s.net))
end

-- Adds to 'earned' (enemy kills). Value should be positive.
local function addEarned(playerName, amount)
    if not playerName or amount <= 0 then return end
    ensurePlayer(playerName)
    local s = CostTracker.playerScores[playerName]
    s.earned = s.earned + amount
    s.net    = s.earned - s.spent
    env.info(string.format("[CostTracker] %s EARNED %.3fM | spent=%.3f earned=%.3f net=%.3f",
        playerName, amount, s.spent, s.earned, s.net))
end

-- ============================================================
--  EVENT HANDLER
-- ============================================================

local CostEventHandler = {}

function CostEventHandler:onEvent(event)

    -- ── SHOT: munition fired / released ─────────────────────
    if event.id == world.event.S_EVENT_SHOT then
        local playerName = getPlayerName(event.initiator)
        if not playerName then return end

        local weaponType = "default"
        if event.weapon and event.weapon:isExist() then
            weaponType = event.weapon:getTypeName()
        end

        local cost = getMunitionCost(weaponType)
        if cost > 0 then
            addSpent(playerName, cost)
        end

    -- ── HIT: track last player to hit each unit ──────────────
    elseif event.id == world.event.S_EVENT_HIT then
        local playerName = getPlayerName(event.initiator)
        if not playerName then return end

        local target = event.target
        if target and target:isExist() then
            CostTracker.lastHitBy[target:getID()] = playerName
        end

    -- ── DEAD: unit destroyed ─────────────────────────────────
    elseif event.id == world.event.S_EVENT_DEAD then
        local deadUnit = event.initiator
        if not deadUnit then return end
        -- S_EVENT_DEAD fires for weapons (missiles, bombs) too; skip non-unit objects
        if deadUnit:getCategory() ~= Object.Category.UNIT then return end

        local deadID   = deadUnit:getID()
        local deadType = deadUnit:getTypeName()

        -- Case 1: A player's aircraft was destroyed
        -- isExist() guard filters spurious DEAD events fired during player slot init
        local playerName = getPlayerName(deadUnit)
        if playerName and deadUnit:isExist() then
            if not CostTracker.safeUnits[deadID] then
                local cost = getAircraftCost(deadType)
                addSpent(playerName, cost)
                -- getGroup() can return nil when DEAD fires; fall back to coalition message
                local grp = deadUnit:getGroup()
                local msg = string.format("Aircraft lost: -%.2fM charged to %s", cost, playerName)
                if grp then
                    trigger.action.outTextForGroup(grp:getID(), msg, 8, false)
                else
                    trigger.action.outTextForCoalition(coalition.side.BLUE, msg, 8, false)
                end
            end
            CostTracker.safeUnits[deadID]   = nil
            CostTracker.ejectedUnits[deadID] = nil
        end

        -- Case 2: An enemy unit was destroyed — credit the killer
        if isEnemyUnit(deadUnit) then
            local killer = CostTracker.lastHitBy[deadID]
            if killer then
                local value = getKillValue(deadType)
                addEarned(killer, value)
                CostTracker.lastHitBy[deadID] = nil
            end
        end

    -- ── CRASH: aircraft hit the ground ───────────────────────
    elseif event.id == world.event.S_EVENT_CRASH then
        local unit = event.initiator
        if not unit then return end

        local playerName = getPlayerName(unit)
        if not playerName then return end

        local unitID = unit:getID()
        if not CostTracker.safeUnits[unitID] then
            local cost = getAircraftCost(unit:getTypeName())
            addSpent(playerName, cost)
            local grp = unit:getGroup()
            local msg = string.format("Aircraft crashed: -%.2fM charged to %s", cost, playerName)
            if grp then
                trigger.action.outTextForGroup(grp:getID(), msg, 8, false)
            else
                trigger.action.outTextForCoalition(coalition.side.BLUE, msg, 8, false)
            end
        end

        CostTracker.safeUnits[unitID]   = nil
        CostTracker.ejectedUnits[unitID] = nil

    -- ── EJECTION: pilot leaves the aircraft ──────────────────
    -- Charge aircraft cost immediately. Mark unit as ejected
    -- so a safe-landing flag cannot be applied afterward.
    elseif event.id == world.event.S_EVENT_EJECTION then
        local unit = event.initiator
        if not unit then return end

        local playerName = getPlayerName(unit)
        if not playerName then return end

        local unitID = unit:getID()

        -- Only charge once (DEAD event may follow)
        if not CostTracker.ejectedUnits[unitID] then
            CostTracker.ejectedUnits[unitID] = true
            CostTracker.safeUnits[unitID]    = nil

            local cost = getAircraftCost(unit:getTypeName())
            addSpent(playerName, cost)
            local grp = unit:getGroup()
            local msg = string.format("Ejection: -%.2fM charged to %s", cost, playerName)
            if grp then
                trigger.action.outTextForGroup(grp:getID(), msg, 8, false)
            else
                trigger.action.outTextForCoalition(coalition.side.BLUE, msg, 8, false)
            end
        end

    -- ── PILOT DEAD: killed in cockpit ────────────────────────
    elseif event.id == world.event.S_EVENT_PILOT_DEAD then
        local unit = event.initiator
        if not unit then return end

        local playerName = getPlayerName(unit)
        if not playerName then return end

        local unitID = unit:getID()
        if not CostTracker.ejectedUnits[unitID] then
            local cost = getAircraftCost(unit:getTypeName())
            addSpent(playerName, cost)
        end

    -- ── LAND: aircraft touches down ──────────────────────────
    -- If landing at a currently Blue-coalition airfield, mark unit as safe.
    -- Uses live coalition check so it respects session randomization.
    elseif event.id == world.event.S_EVENT_LAND then
        local unit = event.initiator
        if not unit then return end

        local playerName = getPlayerName(unit)
        if not playerName then return end

        local unitID = unit:getID()
        if CostTracker.ejectedUnits[unitID] then return end

        local airbase = event.place
        if airbase and airbase:getCoalition() == coalition.side.BLUE then
            CostTracker.safeUnits[unitID] = true
            env.info(string.format("[CostTracker] %s landed safely at %s — aircraft cost waived",
                playerName, airbase:getName()))
        end

    end  -- end event type dispatch
end  -- end onEvent

-- ============================================================
--  REGISTER THE EVENT HANDLER WITH DCS WORLD
-- ============================================================
world.addEventHandler(CostEventHandler)

-- ============================================================
--  PUBLIC API  (used by cost_ui.lua)
-- ============================================================

function CostTracker.getPlayerSummary(playerName)
    local s = CostTracker.playerScores[playerName]
    if not s then
        return string.format("  %s: no data", playerName)
    end
    local sign = s.net >= 0 and "+" or ""
    return string.format(
        "  %-20s  Spent: %.2fM  |  Earned: %.2fM  |  Net: %s%.2fM",
        playerName, s.spent, s.earned, sign, s.net)
end

function CostTracker.getTeamTotals()
    local totalSpent  = 0
    local totalEarned = 0
    for _, s in pairs(CostTracker.playerScores) do
        totalSpent  = totalSpent  + s.spent
        totalEarned = totalEarned + s.earned
    end
    local totalNet = totalEarned - totalSpent
    local sign     = totalNet >= 0 and "+" or ""
    return totalSpent, totalEarned, totalNet,
        string.format(
            "  TEAM TOTAL  Spent: %.2fM  |  Earned: %.2fM  |  Net: %s%.2fM",
            totalSpent, totalEarned, sign, totalNet)
end

-- ============================================================
--  END OF cost_logic.lua
-- ============================================================
