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
--
--  Rules:
--    Spent      munitions (per weapon released, gun per round fired) and lost
--               aircraft (crash, ejection, pilot killed, destroyed), charged once
--               per sortie. No charge after landing at a Blue airfield, and none
--               for leaving the slot or disconnecting.
--    Destroyed  Red units and statics a player killed. If Blue AI finishes off a
--               unit, the last player who hit it within HIT_CREDIT_SECONDS gets it.
--               Every victim is credited at most once.
--
--  Why it works from remembered facts instead of the event objects: by the time
--  DCS sends a loss or kill event, the player's aircraft may no longer exist, and
--  calling methods on a dead object fails. So who flies what is recorded when the
--  aircraft is born, and who fired what when it is fired.
-- ============================================================

CostTracker = {}

-- Per-player running totals.
-- Key   = player name
-- Value = { spent, destroyed, net }
CostTracker.playerScores = {}

local HIT_CREDIT_SECONDS    = 300   -- a player's hit earns an AI-finished kill for this long
local WEAPON_MEMORY_SECONDS = 600   -- how long a fired weapon is remembered for attribution
local CLEANUP_INTERVAL      = 120

-- Sorties of human-flown aircraft, by unit name and by DCS object id.
-- { playerName, typeName, groupId, landedSafe, lossCharged, ended, shellsAtTriggerPull }
local sortieByUnitName = {}
local sortieByObjectId = {}

-- Weapon object id → { playerName, time } for weapons fired by players.
local shooterOfWeapon = {}

-- Victim unit/static name → { playerName, time } of the last player hit.
local lastPlayerHit = {}

-- Victim names already settled (credited, or killed by AI with no player hit).
local settledVictims = {}

-- ============================================================
--  SAFE OBJECT ACCESS
--  Methods on a dead or despawned DCS object raise errors; these return nil instead.
-- ============================================================

local function call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then return nil end
    local ok, result = pcall(object[method], object, ...)
    if ok then return result end
    return nil
end

local function categoryOf(object)
    if object == nil then return nil end
    local ok, category = pcall(Object.getCategory, object)
    if ok then return category end
    return nil
end

local function objectIdOf(object)
    if type(object) == "table" then return object.id_ end
    return nil
end

local function isUnitOrStatic(object)
    local category = categoryOf(object)
    return category == Object.Category.UNIT or category == Object.Category.STATIC
end

-- ============================================================
--  LOOKUPS
-- ============================================================

local function lookup(tbl, key)
    if key ~= nil and tbl[key] ~= nil then
        return tbl[key]
    end
    return tbl["default"] or 0
end

local function getMunitionCost(typeName)  return lookup(COST_CONFIG.munitionCost, typeName) end
local function getKillValue(typeName)     return lookup(COST_CONFIG.killValue, typeName)    end
local function getAircraftCost(typeName)  return lookup(COST_CONFIG.aircraftCost, typeName) end
local function getGunRoundCost(typeName)  return lookup(COST_CONFIG.gunRoundCost, typeName) end

local function findSortie(unit)
    if unit == nil then return nil end
    local name = call(unit, "getName")
    if name and sortieByUnitName[name] then return sortieByUnitName[name] end
    local objectId = objectIdOf(unit)
    if objectId then return sortieByObjectId[objectId] end
    return nil
end

-- The player behind a unit: asked live while it exists, else from its sortie record.
local function playerOfUnit(unit)
    if categoryOf(unit) ~= Object.Category.UNIT then return nil end
    local playerName = call(unit, "getPlayerName")
    if playerName then return playerName end
    local sortie = findSortie(unit)
    return sortie and sortie.playerName or nil
end

-- The player behind a weapon: remembered from its SHOT event, else its launcher.
local function playerOfWeapon(weapon)
    if weapon == nil then return nil end
    local objectId = objectIdOf(weapon)
    local fired = objectId and shooterOfWeapon[objectId]
    if fired then return fired.playerName end
    return playerOfUnit(call(weapon, "getLauncher"))
end

-- The player responsible for an event: its initiator (a unit, or a weapon such as a
-- cluster submunition), then the event's weapon.
local function playerOfEvent(event)
    local initiator = event.initiator
    if categoryOf(initiator) == Object.Category.WEAPON then
        local playerName = playerOfWeapon(initiator)
        if playerName then return playerName end
    else
        local playerName = playerOfUnit(initiator)
        if playerName then return playerName end
    end
    return playerOfWeapon(event.weapon)
end

-- ============================================================
--  SCORE MANAGEMENT
-- ============================================================

local function ensurePlayer(playerName)
    if not CostTracker.playerScores[playerName] then
        CostTracker.playerScores[playerName] = { spent = 0, destroyed = 0, net = 0 }
    end
    return CostTracker.playerScores[playerName]
end

-- Adds to 'spent' (munitions, lost aircraft). Value should be positive.
local function addSpent(playerName, amount, what)
    if not playerName or amount <= 0 then return end
    local s = ensurePlayer(playerName)
    s.spent = s.spent + amount
    s.net   = s.destroyed - s.spent
    env.info(string.format("[CostTracker] %s SPENT %.4fM (%s) | spent=%.3f destroyed=%.3f net=%.3f",
        playerName, amount, what, s.spent, s.destroyed, s.net))
end

-- Credits a kill once per victim and shows a confirmation to Blue.
local function creditKill(playerName, victimName, victimType, source)
    settledVictims[victimName] = true
    lastPlayerHit[victimName]  = nil

    local value     = getKillValue(victimType)
    local isDefault = (COST_CONFIG.killValue[victimType] == nil)
    local s = ensurePlayer(playerName)
    s.destroyed = s.destroyed + value
    s.net       = s.destroyed - s.spent
    env.info(string.format("[CostTracker] KILL(%s) %s '%s' → %.3fM%s to %s | spent=%.3f destroyed=%.3f net=%.3f",
        source, victimType, victimName, value, isDefault and " (DEFAULT)" or "", playerName,
        s.spent, s.destroyed, s.net))

    local sign = s.net >= 0 and "+" or ""
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        string.format("[Kill +%.2fM] %s by %s  |  Net: %s%.2fM", value, victimType, playerName, sign, s.net),
        6, false)
end

local function tellSortie(sortie, message)
    if sortie.groupId then
        trigger.action.outTextForGroup(sortie.groupId, message, 8, false)
    else
        trigger.action.outTextForCoalition(coalition.side.BLUE, message, 8, false)
    end
end

-- Charges a lost aircraft once per sortie, unless it landed at a Blue airfield
-- or the player already left it.
local function chargeLoss(unit, reason)
    local sortie = findSortie(unit)
    if not sortie then return end
    if sortie.lossCharged or sortie.ended then return end
    if sortie.landedSafe then
        env.info(string.format("[CostTracker] %s %s after a safe landing — no charge", sortie.playerName, reason))
        return
    end
    sortie.lossCharged = true
    local cost = getAircraftCost(sortie.typeName)
    addSpent(sortie.playerName, cost, reason .. " " .. tostring(sortie.typeName))
    tellSortie(sortie, string.format("Aircraft lost (%s): -%.2fM charged to %s", reason, cost, sortie.playerName))
end

-- Red victims only; returns name and type, or nil.
local function redVictim(object)
    if not isUnitOrStatic(object) then return nil end
    if call(object, "getCoalition") ~= coalition.side.RED then return nil end
    local name = call(object, "getName")
    if not name then return nil end
    return name, call(object, "getTypeName") or "unknown"
end

-- Credits a victim to the last player who hit it, if that hit is recent enough.
local function creditLastHit(victimName, victimType, source)
    local hit = lastPlayerHit[victimName]
    if hit and timer.getTime() - hit.time <= HIT_CREDIT_SECONDS then
        creditKill(hit.playerName, victimName, victimType, source)
        return true
    end
    return false
end

local function shellCount(unit)
    local total = 0
    for _, ammo in ipairs(call(unit, "getAmmo") or {}) do
        if ammo.desc and ammo.desc.category == Weapon.Category.SHELL then
            total = total + (ammo.count or 0)
        end
    end
    return total
end

-- ============================================================
--  EVENT HANDLERS
-- ============================================================

local handlers = {}

-- A human takes an aircraft: start a sortie record.
local function startSortie(event)
    local unit = event.initiator
    if categoryOf(unit) ~= Object.Category.UNIT then return end
    local playerName = call(unit, "getPlayerName")
    if not playerName then return end
    local name = call(unit, "getName")
    if not name then return end
    local existing = sortieByUnitName[name]
    if existing and existing.playerName == playerName and not existing.ended then return end

    local sortie = {
        playerName = playerName,
        typeName   = call(unit, "getTypeName"),
        groupId    = call(call(unit, "getGroup"), "getID"),
        landedSafe = false,
    }
    sortieByUnitName[name] = sortie
    local objectId = objectIdOf(unit)
    if objectId then sortieByObjectId[objectId] = sortie end
    ensurePlayer(playerName)
    env.info(string.format("[CostTracker] sortie start: %s in %s (%s)", playerName, name, tostring(sortie.typeName)))
end

handlers[world.event.S_EVENT_BIRTH]             = startSortie
handlers[world.event.S_EVENT_PLAYER_ENTER_UNIT] = startSortie

-- Leaving the slot or disconnecting ends the sortie without a charge.
handlers[world.event.S_EVENT_PLAYER_LEAVE_UNIT] = function(event)
    local sortie = findSortie(event.initiator)
    if sortie and not sortie.ended then
        sortie.ended = true
        env.info(string.format("[CostTracker] sortie end: %s left the aircraft", sortie.playerName))
    end
end

handlers[world.event.S_EVENT_TAKEOFF] = function(event)
    local sortie = findSortie(event.initiator)
    if sortie then sortie.landedSafe = false end
end

-- Landing at a Blue airfield waives the aircraft cost until the next takeoff.
handlers[world.event.S_EVENT_LAND] = function(event)
    local sortie = findSortie(event.initiator)
    if not sortie or sortie.lossCharged then return end
    local place = event.place
    if place and call(place, "getCoalition") == coalition.side.BLUE then
        sortie.landedSafe = true
        env.info(string.format("[CostTracker] %s landed safely at %s — aircraft cost waived",
            sortie.playerName, tostring(call(place, "getName"))))
    end
end

-- Losses: whichever of these arrives first charges the aircraft, once.
handlers[world.event.S_EVENT_EJECTION]   = function(event) chargeLoss(event.initiator, "ejection")     end
handlers[world.event.S_EVENT_PILOT_DEAD] = function(event) chargeLoss(event.initiator, "pilot killed") end
handlers[world.event.S_EVENT_CRASH]      = function(event) chargeLoss(event.initiator, "crash")        end

-- Munitions: one SHOT per missile, bomb or rocket.
handlers[world.event.S_EVENT_SHOT] = function(event)
    local playerName = playerOfUnit(event.initiator)
    if not playerName then return end

    local weaponType = call(event.weapon, "getTypeName") or "default"
    local objectId   = objectIdOf(event.weapon)
    if objectId then
        shooterOfWeapon[objectId] = { playerName = playerName, time = timer.getTime() }
    end

    local cost = getMunitionCost(weaponType)
    local isDefault = (COST_CONFIG.munitionCost[weaponType] == nil)
    addSpent(playerName, cost, weaponType .. (isDefault and " (DEFAULT)" or ""))
end

-- Guns: DCS reports a trigger pull as SHOOTING_START / SHOOTING_END. The rounds
-- fired are the shell count difference between the two.
handlers[world.event.S_EVENT_SHOOTING_START] = function(event)
    local sortie = findSortie(event.initiator)
    if sortie then sortie.shellsAtTriggerPull = shellCount(event.initiator) end
end

handlers[world.event.S_EVENT_SHOOTING_END] = function(event)
    local sortie = findSortie(event.initiator)
    if not sortie or not sortie.shellsAtTriggerPull then return end
    local rounds = sortie.shellsAtTriggerPull - shellCount(event.initiator)
    sortie.shellsAtTriggerPull = nil
    if rounds > 0 then
        addSpent(sortie.playerName, rounds * getGunRoundCost(sortie.typeName),
            string.format("%d gun rounds", rounds))
    end
end

-- Hits: remember the last player to damage each Red unit.
handlers[world.event.S_EVENT_HIT] = function(event)
    local victimName = redVictim(event.target)
    if not victimName or settledVictims[victimName] then return end
    local playerName = playerOfEvent(event)
    if playerName then
        lastPlayerHit[victimName] = { playerName = playerName, time = timer.getTime() }
    end
end

-- Kills: the killer is in the event. A player killer is credited; an AI killer
-- passes the credit to a recent player hit, if any.
handlers[world.event.S_EVENT_KILL] = function(event)
    local victimName, victimType = redVictim(event.target)
    if not victimName or settledVictims[victimName] then return end

    local playerName = playerOfEvent(event)
    if playerName then
        creditKill(playerName, victimName, victimType, "KILL")
    elseif not creditLastHit(victimName, victimType, "KILL, finished by AI") then
        settledVictims[victimName] = true
        env.info(string.format("[CostTracker] KILL(AI) %s '%s' — no player credit", victimType, victimName))
    end
end

-- Deaths: player aircraft lost, or a Red unit / static gone without a KILL event
-- (statics, some multi-hit kills).
local function onDeath(event)
    local object = event.initiator
    if categoryOf(object) == Object.Category.WEAPON then return end

    if findSortie(object) then
        chargeLoss(object, "aircraft destroyed")
        return
    end

    local victimName, victimType = redVictim(object)
    if not victimName or settledVictims[victimName] then return end
    if not creditLastHit(victimName, victimType, "DEAD") then
        settledVictims[victimName] = true
        env.info(string.format("[CostTracker] DEAD %s '%s' — no player hit on record", victimType, victimName))
    end
end

handlers[world.event.S_EVENT_DEAD] = onDeath
if world.event.S_EVENT_UNIT_LOST then
    handlers[world.event.S_EVENT_UNIT_LOST] = onDeath
end

-- ============================================================
--  REGISTER THE EVENT HANDLER WITH DCS WORLD
-- ============================================================

Log.addEventHandler("CostTracker events", function(event)
    local handler = handlers[event.id]
    if handler then handler(event) end
end)

-- Forget old weapons and stale hits so the tables don't grow all session.
Log.repeating("CostTracker cleanup", function(time)
    for objectId, fired in pairs(shooterOfWeapon) do
        if time - fired.time > WEAPON_MEMORY_SECONDS then shooterOfWeapon[objectId] = nil end
    end
    for victimName, hit in pairs(lastPlayerHit) do
        if time - hit.time > HIT_CREDIT_SECONDS then lastPlayerHit[victimName] = nil end
    end
end, timer.getTime() + CLEANUP_INTERVAL, CLEANUP_INTERVAL)

-- ============================================================
--  PUBLIC API  (used by cost_ui.lua)
-- ============================================================

-- True if the unit is a human-flown aircraft this tracker has a sortie for.
function CostTracker.isPlayerUnit(unit)
    return findSortie(unit) ~= nil
end

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
