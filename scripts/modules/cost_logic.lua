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
-- Value = { spent, destroyed, net }
CostTracker.playerScores = {}

-- Tracks which unit IDs have safely landed at a blue airfield.
-- Cleared when the unit is destroyed (one-time flag per sortie).
-- Key = unitID (number), Value = true
CostTracker.safeUnits = {}

-- Tracks which unit IDs have ejected — prevents safe-landing
-- credit even if the empty aircraft somehow touches down.
-- Key = unitID (number), Value = true
CostTracker.ejectedUnits = {}

-- Kill attribution via HIT→DEAD chain (fallback for multi-hit kills / statics).
-- Updated on S_EVENT_HIT, consumed on S_EVENT_DEAD.
-- Key = unit name (string) — more stable than getID() across event types.
CostTracker.lastHitBy = {}

-- Maps weapon object -> player name for HIT attribution when initiator is a weapon.
-- Key = weapon userdata object, Value = playerName (string)
CostTracker.weaponToPlayer = {}

-- Tracks units already credited via S_EVENT_KILL so S_EVENT_DEAD doesn't double-count.
-- Key = unit name (string), Value = true
CostTracker.killCredited = {}

-- ============================================================
--  INTERNAL HELPERS
-- ============================================================

-- Returns the player name for a unit, or nil if AI / invalid.
local function getPlayerName(unit)
    if not unit or not unit:isExist() then return nil end
    if unit:getCategory() ~= Object.Category.UNIT then return nil end
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
-- Only safe to call on live units (isExist() == true).
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
            destroyed = 0,
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
    s.net    = s.destroyed - s.spent
    env.info(string.format("[CostTracker] %s SPENT %.3fM | spent=%.3f destroyed=%.3f net=%.3f",
        playerName, amount, s.spent, s.destroyed, s.net))
end

-- Adds to 'destroyed' (enemy kills). Value should be positive.
local function addDestroyed(playerName, amount)
    if not playerName or amount <= 0 then return end
    ensurePlayer(playerName)
    local s = CostTracker.playerScores[playerName]
    s.destroyed = s.destroyed + amount
    s.net    = s.destroyed - s.spent
    env.info(string.format("[CostTracker] %s DESTROYED %.3fM | spent=%.3f destroyed=%.3f net=%.3f",
        playerName, amount, s.spent, s.destroyed, s.net))
end

-- Shows a brief kill confirmation on screen and logs the kill.
local function creditKill(playerName, unitType, source)
    local value = getKillValue(unitType)
    local isDefault = (COST_CONFIG.killValue[unitType] == nil)
    env.info(string.format("[CostTracker] KILL(%s) %s → %.3fM%s to %s",
        source, unitType, value, isDefault and " (DEFAULT)" or "", playerName))
    addDestroyed(playerName, value)
    local s = CostTracker.playerScores[playerName]
    local sign = s.net >= 0 and "+" or ""
    local msg = string.format("[Kill +%.2fM] %s  |  Net: %s%.2fM",
        value, unitType, sign, s.net)
    trigger.action.outTextForCoalition(coalition.side.BLUE, msg, 6, false)
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
            -- Cache weapon→player for HIT attribution fallback.
            -- In S_EVENT_HIT the initiator can be the weapon rather than the aircraft.
            CostTracker.weaponToPlayer[event.weapon] = playerName
        end

        local cost = getMunitionCost(weaponType)
        local isDefault = (COST_CONFIG.munitionCost[weaponType] == nil)
        env.info(string.format("[CostTracker] SHOT type='%s' cost=%.4fM%s by %s",
            weaponType, cost, isDefault and " (DEFAULT)" or "", playerName))
        if cost > 0 then
            addSpent(playerName, cost)
        end

    -- ── KILL: primary kill attribution ───────────────────────
    -- S_EVENT_KILL fires with event.initiator = killer unit and event.target =
    -- killed unit. This is more direct than HIT→DEAD and handles one-shot kills
    -- (e.g. Maverick direct hit) where DEAD fires before HIT can record lastHitBy.
    elseif event.id == world.event.S_EVENT_KILL then
        local playerName = getPlayerName(event.initiator)
        if not playerName then return end

        local target = event.target
        if not target then return end
        if type(target.getCoalition) ~= "function" then return end
        if target:getCoalition() ~= coalition.side.RED then return end
        if type(target.getCategory) ~= "function" then return end
        local cat = target:getCategory()
        if cat ~= Object.Category.UNIT and cat ~= Object.Category.STATIC then return end

        local unitName = target:getName()
        local unitType = target:getTypeName()
        CostTracker.killCredited[unitName] = true  -- suppress DEAD double-count
        creditKill(playerName, unitType, "KILL")

    -- ── HIT: record last player to hit each unit (fallback chain) ──
    -- Primary kills are handled via S_EVENT_KILL. HIT→lastHitBy feeds S_EVENT_DEAD
    -- as a fallback for multi-hit kills and statics (which don't trigger S_EVENT_KILL).
    elseif event.id == world.event.S_EVENT_HIT then
        local playerName, hitMethod
        -- Direct: initiator is the aircraft (cannon, unguided bombs in some cases)
        playerName = getPlayerName(event.initiator)
        if playerName then
            hitMethod = "direct"
        else
            -- If initiator is a Unit (has getPlayerName) but wasn't a player, it's AI — nothing to track.
            -- Only reach getLauncher for weapon objects (e.g. CBU submunitions where the
            -- initiator is the BLU-108 itself, not the launching aircraft).
            if event.initiator and type(event.initiator.getPlayerName) == "function" then return end
            local obj = event.weapon or event.initiator
            if obj and type(obj.getLauncher) == "function" then
                local ok, launcher = pcall(function() return obj:getLauncher() end)
                if ok and launcher then
                    playerName = getPlayerName(launcher)
                    if playerName then hitMethod = "getLauncher" end
                elseif not ok then
                    env.info("[CostTracker] HIT getLauncher failed: " .. tostring(launcher))
                end
            end
        end
        if not playerName then
            -- Last-resort: weapon object key (may fail if DCS re-wraps userdata)
            local weapon = event.weapon or event.initiator
            if weapon then
                playerName = CostTracker.weaponToPlayer[weapon]
                if playerName then hitMethod = "weaponCache" end
            end
        end
        local targetType = event.target and event.target:getTypeName() or "nil"
        env.info(string.format("[CostTracker] HIT target=%s by=%s via=%s",
            targetType, tostring(playerName), tostring(hitMethod)))
        if not playerName then return end

        local target = event.target
        if not target or not target:isExist() then return end
        local cat = target:getCategory()
        if cat ~= Object.Category.UNIT and cat ~= Object.Category.STATIC then return end
        -- Key by name: more stable than getID() which can differ between event types
        CostTracker.lastHitBy[target:getName()] = playerName

    -- ── DEAD: unit or static destroyed ───────────────────────
    elseif event.id == world.event.S_EVENT_DEAD then
        local deadUnit = event.initiator
        if not deadUnit then return end
        -- Weapon objects (missiles, bombs) lack getCategory entirely; skip them
        if type(deadUnit.getCategory) ~= "function" then return end
        local cat = deadUnit:getCategory()
        if cat ~= Object.Category.UNIT and cat ~= Object.Category.STATIC then return end

        local deadID   = deadUnit:getID()
        local deadType = deadUnit:getTypeName()
        local deadName = deadUnit:getName()

        -- Case 1: A player's aircraft was destroyed (units only — statics have no pilot)
        -- isExist() guard filters spurious DEAD events fired during player slot init
        if cat == Object.Category.UNIT then
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
        end

        -- Case 2: An enemy unit or static was destroyed — credit the killer.
        -- Do NOT use isEnemyUnit() here: isExist() returns false on dead units,
        -- so isEnemyUnit always returns false inside a DEAD handler.
        if deadUnit:getCoalition() == coalition.side.RED then
            if CostTracker.killCredited[deadName] then
                -- Already credited via S_EVENT_KILL; clean up and skip.
                CostTracker.killCredited[deadName] = nil
                CostTracker.lastHitBy[deadName]    = nil
                env.info(string.format("[CostTracker] DEAD RED %s — already credited via KILL", deadType))
            else
                -- S_EVENT_KILL didn't fire (multi-hit kill or static); use HIT→DEAD chain.
                local killer = CostTracker.lastHitBy[deadName]
                if killer then
                    CostTracker.lastHitBy[deadName] = nil
                    creditKill(killer, deadType, "DEAD")
                else
                    env.info(string.format("[CostTracker] DEAD RED %s — no killer attributed", deadType))
                end
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
        "  %-20s  Spent: %.2fM  |  Destroyed: %.2fM  |  Net: %s%.2fM",
        playerName, s.spent, s.destroyed, sign, s.net)
end

function CostTracker.getTeamTotals()
    local totalSpent  = 0
    local totalDestroyed = 0
    for _, s in pairs(CostTracker.playerScores) do
        totalSpent  = totalSpent  + s.spent
        totalDestroyed = totalDestroyed + s.destroyed
    end
    local totalNet = totalDestroyed - totalSpent
    local sign     = totalNet >= 0 and "+" or ""
    return totalSpent, totalDestroyed, totalNet,
        string.format(
            "  TEAM TOTAL  Spent: %.2fM  |  Destroyed: %.2fM  |  Net: %s%.2fM",
            totalSpent, totalDestroyed, sign, totalNet)
end

-- ============================================================
--  END OF cost_logic.lua
-- ============================================================
