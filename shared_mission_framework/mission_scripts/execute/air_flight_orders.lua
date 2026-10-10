-- Execute: the controller's orders to AI flights, turned into DCS orders. The only place
-- a flight's DCS controller is told anything; the controller calls it once it has written
-- its decision (rule 3), and only when a flight's intent changes, so a flight isn't
-- re-tasked every check.
--
-- Each order is handed a table carrying everything it needs (the flight's id and mission,
-- positions, the decision it carries out); Execute looks up only the group or units it
-- acts on, and writes what came of it to record\orders.lua (carried out, or failed and
-- why), which it also returns.
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
-- Still looked up here, not yet handed over (framework_design.md, rule 14): the landing
-- base's id and position, and the threat group's id.

ExecuteAirFlightOrders = {}

local ROE = { weapons_free = 0, open_fire = 2, return_fire = 3, weapons_hold = 4 }   -- AI.Option.Air.val.ROE
local OPTION_ROE = 0
local FIRST_RESUME_FLAG = 9100000   -- user flags this module sets to end a fight; nothing else uses them

local _nextFlag = FIRST_RESUME_FLAG

-- What came of order `o` (kind `order`): written to the Record and returned.
local function result(order, o, carriedOut, why, extra)
    local r = { order = order, flight = o.flight, coalition = o.mission and o.mission.coalition,
                carried_out = carriedOut, why = why, decision = o.decision }
    for k, v in pairs(extra or {}) do r[k] = v end
    return RecordOrders.write(r)
end

local function controllerOf(id, what)
    local g = Group.getByName(id)
    local ok, ctl = pcall(function() return g:getController() end)
    if not (ok and ctl) then
        Log.warn(string.format("%s: no DCS controller to %s", id, what))
        return nil
    end
    return ctl
end

local function setRules(ctl, rules)
    pcall(function() ctl:setOption(OPTION_ROE, ROE[rules]) end)
end

-- o = { flight, mission, pos (where the flight is: x, y altitude, z), decision }
function ExecuteAirFlightOrders.home(o)
    local m = o.mission
    local pos = o.pos
    local base = Airbase.getByName(m.landing_base)
    if not base then
        Log.warn(string.format("%s: landing base %s not found — left on its task", m.id, m.landing_base))
        return result("home", o, false, "landing base " .. m.landing_base .. " not found")
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
    local ctl = controllerOf(o.flight, "send home")
    if not ctl then return result("home", o, false, "no DCS controller") end
    local ok, err = pcall(function()
        ctl:setTask({ id = "Mission", params = { airborne = true, route = { points = points } } })
    end)
    if not ok then
        Log.warn(string.format("%s: sending it home failed: %s", m.id, tostring(err)))
        return result("home", o, false, tostring(err))
    end
    setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement)
    return result("home", o, true)
end

-- A flight lost on its way home (directive landing), or a jet still up after another of
-- its flight landed: a new mission from where it is straight to a landing at its base,
-- returning fire only. o = { flight, mission, units (its jets in the air: { name, pos }),
-- per_jet, decision }. With every live jet in the air (per_jet false) the order goes to the
-- group, from its first jet in the air; with one on the ground (landed, or not yet taken
-- off) it goes to each jet in the air on its own controller (DCS has unit controllers for
-- aircraft): the group's order went to the landed lead and the wingman never heard it
-- (bug 19). Carried out when any jet got it.
function ExecuteAirFlightOrders.land(o)
    local m = o.mission
    local base = Airbase.getByName(m.landing_base)
    if not base then
        Log.warn(string.format("%s: landing base %s not found — no landing order", m.id, m.landing_base))
        return result("land", o, false, "landing base " .. m.landing_base .. " not found")
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
    local up = o.units
    if #up == 0 then return result("land", o, false, "no jet in the air") end
    if not o.per_jet then
        local g = Group.getByName(o.flight)
        local ok, err = pcall(function() g:getController():setTask(mission(up[1].pos)) end)
        if not ok then
            Log.warn(string.format("%s: landing order failed: %s", m.id, tostring(err)))
            return result("land", o, false, tostring(err))
        end
        local ctl = controllerOf(o.flight, "land")
        if ctl then setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement) end
        return result("land", o, true)
    end
    local given = 0
    for _, j in ipairs(up) do
        local ok, err = pcall(function()
            local ctl = Unit.getByName(j.name):getController()
            ctl:setTask(mission(j.pos))
            setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement)
        end)
        if ok then
            given = given + 1
        else
            Log.warn(string.format("%s: landing order to %s failed: %s", m.id, tostring(j.name), tostring(err)))
        end
    end
    return result("land", o, given > 0, given == 0 and "no jet took the order" or nil)
end

-- o = { flight, mission, units (jet names), decision }: the jets removed from the world
-- where they are (an orphan in the air, bug 19).
function ExecuteAirFlightOrders.remove(o)
    for _, name in ipairs(o.units) do
        pcall(function()
            local u = Unit.getByName(name)
            if u and u:isExist() then u:destroy() end
        end)
    end
    return result("remove", o, true)
end

-- o = { flight, mission, decision }: the group removed (still on the ramp).
function ExecuteAirFlightOrders.standDown(o)
    pcall(function() Group.getByName(o.flight):destroy() end)
    return result("stand_down", o, true)
end

-- Engage the threat on top of the mission. o = { flight, mission, threat_group,
-- going_home, decision }. The result carries the fight, { group, since, flag }.
function ExecuteAirFlightOrders.defend(o)
    local m = o.mission
    local target = Group.getByName(o.threat_group)
    local ok, targetId = pcall(function() return target:getID() end)
    if not (ok and targetId) then return result("defend", o, false, o.threat_group .. " not found") end
    local ctl = controllerOf(o.flight, "defend")
    if not ctl then return result("defend", o, false, "no DCS controller") end
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
        Log.warn(string.format("%s: engaging %s failed: %s", m.id, o.threat_group, tostring(err)))
        return result("defend", o, false, tostring(err))
    end
    if o.going_home then setRules(ctl, "open_fire") end
    return result("defend", o, true, nil, { fight = { group = o.threat_group, since = timer.getTime(), flag = flag } })
end

-- End the fight. o = { flight, mission, fight (its { flag }), going_home, decision }.
function ExecuteAirFlightOrders.resume(o)
    local d = o.fight
    if d then pcall(function() trigger.action.setUserFlag(d.flag, true) end) end
    if o.going_home then
        local ctl = controllerOf(o.flight, "resume")
        if ctl then setRules(ctl, AIR_CONTROL.going_home_rules_of_engagement) end
    end
    return result("resume", o, true)
end
