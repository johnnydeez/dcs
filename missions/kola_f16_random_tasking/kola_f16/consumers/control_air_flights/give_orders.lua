-- Consumer part of the controller (control_air_flights.lua): an intent turned into DCS
-- orders. The only place the controller talks to a flight's DCS controller; the
-- controller calls it only when a flight's intent changes, so a flight isn't re-tasked
-- every check.
--
--   home        Controller:setTask, a new mission from where the flight is to a landing at
--               its base (a SEAD flight turns around and goes back the way it came), and
--               rules of engagement AIR_CONTROL.going_home_rules_of_engagement. Replaces
--               whatever it was doing, a fight included.
--   land        Controller:setTask, straight from where the flight is to a landing at its
--               base (a flight lost on its way home, or a jet still up after another of
--               its flight landed), and return fire; with a jet of the flight on the
--               ground, to each jet in the air on its own unit controller (bug 19)
--   remove      the jets named removed where they are (orphans in the air, bug 19)
--   stand_down  the group removed (still on the ramp)
--   defend      Controller:pushTask: AttackGroup on the threat, on top of the mission,
--               inside a ControlledTask that stops after self_defence.max_engage_s or when
--               its own user flag is set. DCS drops it by itself when the threat is
--               destroyed, and the flight carries on with the task underneath.
--   resume      sets that user flag, which stops the fight; never popTask, which would
--               pop the mission itself if DCS had already dropped the fight.
-- A flight going home that defends gets open fire for the fight and return fire back
-- after it.

GiveOrders = {}

local ROE = { weapons_free = 0, open_fire = 2, return_fire = 3, weapons_hold = 4 }   -- AI.Option.Air.val.ROE
local OPTION_ROE = 0
local FIRST_RESUME_FLAG = 9100000   -- user flags this module sets to end a fight; nothing else uses them

local _nextFlag = FIRST_RESUME_FLAG

local function controllerOf(g, m, what)
    local ok, ctl = pcall(function() return g:getController() end)
    if not (ok and ctl) then
        Log.warn(string.format("%s: no DCS controller to %s", m.id, what))
        return nil
    end
    return ctl
end

local function setRules(ctl, rules)
    pcall(function() ctl:setOption(OPTION_ROE, ROE[rules]) end)
end

function GiveOrders.home(w, g, pos)
    local m = w.mission
    local base = Airbase.getByName(m.landing_base)
    if not base then
        Log.warn(string.format("%s: landing base %s not found — left on its task", m.id, m.landing_base))
        return false
    end
    local bp = base:getPoint()
    local p = AIRCRAFT_PROFILE[m.aircraft_type]
    local speed = p and p.cruise_speed_mps or 230
    local function point(x, z, alt, v, altType)
        return { x = x, y = z, alt = alt, alt_type = altType or "BARO", speed = v or speed, speed_locked = true,
                 type = "Turning Point", action = "Turning Point", ETA = 0, ETA_locked = false,
                 task = { id = "ComboTask", params = { tasks = {} } } }
    end
    local points = { point(pos.x, pos.z, pos.y) }
    -- a SEAD flight turns around where it is and goes back the way it came (around the
    -- other SAMs, low where it came in low), not straight home: before its launch point,
    -- its route out flown backwards from the nearest point behind it; from the launch
    -- point on, its planned way back (never on toward the site: from the launch point or
    -- the press-on leg it starts at the first point after the press-on point, bug 36)
    if m.attack and m.attack.kind == "harm_salvo" and m.route then
        local route, launchAt, pressAt, nearest = m.route, nil, nil, nil
        for i, r in ipairs(route) do
            if r.kind == "target" then launchAt = i end
            if r.kind == "press_on" then pressAt = i end
            if i > 1 and i < #route and (not nearest or Util.dist(pos, r) < Util.dist(pos, route[nearest])) then nearest = i end
        end
        if nearest and launchAt and nearest >= launchAt then
            for i = math.max(nearest, pressAt or launchAt) + 1, #route - 1 do
                local r = route[i]
                points[#points + 1] = point(r.x, r.z, r.alt_m, r.speed_mps, r.alt_type)
            end
        elseif nearest then
            for i = nearest - 1, 2, -1 do
                local r = route[i]
                points[#points + 1] = point(r.x, r.z, r.alt_m, r.alt_type == "RADIO" and r.speed_mps or nil, r.alt_type)
            end
        end
    end
    points[#points + 1] = { x = bp.x, y = bp.z, alt = bp.y, alt_type = "BARO", speed = speed, speed_locked = true,
          type = "Land", action = "Landing", airdromeId = base:getID(), ETA = 0, ETA_locked = false,
          task = { id = "ComboTask", params = { tasks = {} } } }
    local ctl = controllerOf(g, m, "send home")
    if not ctl then return false end
    local ok, err = pcall(function()
        ctl:setTask({ id = "Mission", params = { airborne = true, route = { points = points } } })
    end)
    if not ok then
        Log.warn(string.format("%s: sending it home failed: %s", m.id, tostring(err)))
        return false
    end
    setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement)
    return true
end

-- A flight lost on its way home (directive landing), or a jet still up after another of
-- its flight landed: a new mission from where it is straight to a landing at its base,
-- returning fire only. With every live jet in the air the order goes to the group; with
-- one on the ground (landed, or not yet taken off) it goes to each jet in the air on its
-- own controller (DCS has unit controllers for aircraft): the group's order went to the
-- landed lead and the wingman never heard it (bug 19). Returns true when any jet got it.
function GiveOrders.land(w, g)
    local m = w.mission
    local base = Airbase.getByName(m.landing_base)
    if not base then
        Log.warn(string.format("%s: landing base %s not found — no landing order", m.id, m.landing_base))
        return false
    end
    local bp = base:getPoint()
    local p = AIRCRAFT_PROFILE[m.aircraft_type]
    local speed = p and p.cruise_speed_mps or 230
    local function mission(pos)
        return { id = "Mission", params = { airborne = true, route = { points = {
            { x = pos.x, y = pos.z, alt = pos.y, alt_type = "BARO", speed = speed, speed_locked = true,
              type = "Turning Point", action = "Turning Point", ETA = 0, ETA_locked = false,
              task = { id = "ComboTask", params = { tasks = {} } } },
            { x = bp.x, y = bp.z, alt = bp.y, alt_type = "BARO", speed = speed, speed_locked = true,
              type = "Land", action = "Landing", airdromeId = base:getID(), ETA = 0, ETA_locked = false,
              task = { id = "ComboTask", params = { tasks = {} } } },
        } } } }
    end
    local up, onGround = {}, false
    pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then
                if u:inAir() then up[#up + 1] = u else onGround = true end
            end
        end
    end)
    if #up == 0 then return false end
    local given = 0
    if not onGround then
        local ok, err = pcall(function() g:getController():setTask(mission(up[1]:getPoint())) end)
        if not ok then
            Log.warn(string.format("%s: landing order failed: %s", m.id, tostring(err)))
            return false
        end
        local ctl = controllerOf(g, m, "land")
        if ctl then setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement) end
        return true
    end
    for _, u in ipairs(up) do
        local ok, err = pcall(function()
            local ctl = u:getController()
            ctl:setTask(mission(u:getPoint()))
            setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement)
        end)
        if ok then
            given = given + 1
        else
            Log.warn(string.format("%s: landing order to %s failed: %s", m.id, tostring(u:getName()), tostring(err)))
        end
    end
    return given > 0, true
end

-- Jets `names` removed from the world where they are (an orphan in the air, bug 19).
function GiveOrders.remove(names)
    for _, name in ipairs(names) do
        pcall(function()
            local u = Unit.getByName(name)
            if u and u:isExist() then u:destroy() end
        end)
    end
    return true
end

function GiveOrders.standDown(w, g)
    pcall(function() g:destroy() end)
    return true
end

-- Engage `threat` (a situation threat: { group, … }) on top of the mission. Returns the
-- fight's record for w.defending, or nil.
function GiveOrders.defend(w, g, threat)
    local m = w.mission
    local target = Group.getByName(threat.group)
    local ok, targetId = pcall(function() return target:getID() end)
    if not (ok and targetId) then return nil end
    local ctl = controllerOf(g, m, "defend")
    if not ctl then return nil end
    local flag = _nextFlag
    _nextFlag = _nextFlag + 1
    pcall(function() trigger.action.setUserFlag(flag, false) end)
    local task = {
        id = "ControlledTask",
        params = {
            task = { id = "AttackGroup", params = {
                groupId = targetId, weaponType = AIR_WEAPON_TYPE.auto, expend = "Auto", groupAttack = true,
                attackQtyLimit = false, attackQty = 1, directionEnabled = false, direction = 0,
                altitudeEnabled = false, altitude = 0,
            } },
            stopCondition = { duration = AIR_CONTROL.self_defence.max_engage_s, userFlag = flag, userFlagValue = true },
        },
    }
    local pushed, err = pcall(function() ctl:pushTask(task) end)
    if not pushed then
        Log.warn(string.format("%s: engaging %s failed: %s", m.id, threat.group, tostring(err)))
        return nil
    end
    if w.state == "going_home" then setRules(ctl, "open_fire") end
    return { group = threat.group, since = timer.getTime(), flag = flag }
end

function GiveOrders.resume(w, g)
    local d = w.defending
    if d then pcall(function() trigger.action.setUserFlag(d.flag, true) end) end
    if w.state == "going_home" then
        local ctl = controllerOf(g, w.mission, "resume")
        if ctl then setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement) end
    end
    return true
end
