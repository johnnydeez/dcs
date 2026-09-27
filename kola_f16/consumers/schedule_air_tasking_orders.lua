-- Consumer: runs the air tasking orders on the mission clock. Each planned flight is
-- spawned by SpawnAircraftGroups at its start_s (mission time); a start already past is
-- spawned a second from now. Aircraft of planned flights are removed a few minutes after
-- they land, freeing their parking spots and the alive-aircraft budget (the Syria
-- S_EVENT_LAND pattern).
-- What the flights did goes to dcs.log, so a run can be judged without watching it
-- (grep the mission id):
--   "MSN2001: MSN2001_1 fired GBU_31_V_3B"                   every weapon a flight releases
--   "MSN2001: MSN2001_1 killed TGT_IVAL_command_post_1_static_2 (…)"   what it destroyed
--   "MSN2001: target object … destroyed (3 of 6 critical)"   a mission's target, by anyone
--   "MSN2001: MSN2001_2 lost (killed by SAM_VUOJ_SA10_1_1 (S-300PS 5P85C ln)) at 24600 ft,
--    contested airspace, 12 km inside SAM_VUOJ_SA10_1"       the flight's own losses, where
--   "MSN2002_1 track: 26100 ft, own airspace, 45 km outside SAM_…, 3 km from station centre"
--                                                            every PATROL_TRACK_INTERVAL_S,
--                                                            each airborne patrol and AWACS
-- Reads the plan; writes nothing back to it. What has launched, landed and been
-- destroyed is runtime state, kept here under the plan's mission ids.

ScheduleAirTaskingOrders = {}

local REMOVE_AFTER_LANDING_S = 180
local PATROL_TRACK_INTERVAL_S = 120
local FEET_PER_METRE = 3.28084

local _flights = {}   -- mission id → { mission, spawned, destroyed = n }
local _targets = {}   -- critical object name → mission id
local _gone    = {}   -- names already reported destroyed or lost
local _plan           -- for where a flight is: the airspace and the enemy SAM rings

local function nameOf(object)
    local ok, name = pcall(function() return object:getName() end)
    return ok and name or nil
end

-- The mission id of the planned flight this unit belongs to, or nil.
local function flightOf(unit)
    local ok, name = pcall(function() return unit:getGroup():getName() end)
    if ok and _flights[name] then return name end
    return nil
end

local function landed(unit)
    local name = flightOf(unit)
    if not name then return end
    local unitName = unit:getName()
    Log.info(string.format("%s: %s landed — removing it in %d s", name, unitName, REMOVE_AFTER_LANDING_S))
    timer.scheduleFunction(function()
        local u = Unit.getByName(unitName)
        if u and u:isExist() then u:destroy() end
    end, nil, timer.getTime() + REMOVE_AFTER_LANDING_S)
end

-- Where a unit of `coalition` is: altitude, airspace, and the enemy medium / long-range
-- SAM ring it is in, or the nearest one.
local function whereIs(unit, coalition)
    local ok, p = pcall(function() return unit:getPoint() end)
    if not ok or not p then return "position unknown" end
    local pos = { x = p.x, z = p.z }
    local nearest, edge
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalition and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0 then
            local d = Util.dist(pos, s.pos) - s.engage_m
            if not edge or d < edge then nearest, edge = s.id, d end
        end
    end
    local text = string.format("%.0f ft, %s airspace", p.y * FEET_PER_METRE,
        DivideAirspace.kindFor(_plan.airspace, pos, coalition))
    if nearest then
        text = text .. string.format(", %.0f km %s %s", math.abs(edge) / 1000, edge < 0 and "inside" or "outside", nearest)
    end
    return text
end

local function destroyed(object, how)
    local name = nameOf(object)
    if not name or _gone[name] then return end
    local target = _targets[name]
    if target then
        _gone[name] = true
        local f = _flights[target]
        f.destroyed = f.destroyed + 1
        Log.info(string.format("%s: target object %s destroyed (%d of %d critical)", target, name,
            f.destroyed, #f.mission.critical_names))
        return
    end
    local flight = flightOf(object)
    if flight then
        _gone[name] = true
        Log.info(string.format("%s: %s lost (%s) at %s", flight, name, how,
            whereIs(object, _flights[flight].mission.coalition)))
    end
end

local handler = {}
function handler:onEvent(e)
    if not e.initiator then return end
    if e.id == world.event.S_EVENT_LAND then
        local ok, category = pcall(function() return e.initiator:getCategory() end)
        if ok and category == Object.Category.UNIT then landed(e.initiator) end
    elseif e.id == world.event.S_EVENT_SHOT then
        local flight = flightOf(e.initiator)
        if flight then
            local ok, weapon = pcall(function() return e.weapon:getTypeName() end)
            Log.info(string.format("%s: %s fired %s", flight, nameOf(e.initiator) or "?", ok and weapon or "?"))
        end
    elseif e.id == world.event.S_EVENT_KILL then
        local flight = flightOf(e.initiator)
        if flight and e.target then
            local ok, kind = pcall(function() return e.target:getTypeName() end)
            Log.info(string.format("%s: %s killed %s (%s)", flight, nameOf(e.initiator) or "?",
                nameOf(e.target) or "?", ok and kind or "?"))
        end
        if e.target then
            local ok, kind = pcall(function() return e.initiator:getTypeName() end)
            destroyed(e.target, string.format("killed by %s (%s)", nameOf(e.initiator) or "?", ok and kind or "?"))
        end
    elseif e.id == world.event.S_EVENT_DEAD then
        destroyed(e.initiator, "dead")
    elseif e.id == world.event.S_EVENT_CRASH then
        destroyed(e.initiator, "crash")
    elseif e.id == world.event.S_EVENT_EJECTION then
        destroyed(e.initiator, "ejected")
    end
end

-- A flight spawned at run time (a scramble), tracked like a planned one: its weapons,
-- kills and losses are logged and its aircraft are removed after landing.
function ScheduleAirTaskingOrders.track(m)
    _flights[m.id] = { mission = m, spawned = true, destroyed = 0 }
end

-- Every PATROL_TRACK_INTERVAL_S: one line per airborne unit of a station flight (patrols,
-- the AWACS) — altitude, distance from its race-track's centre, airspace, enemy rings.
local function trackPatrols()
    local stations = {}
    for _, c in ipairs({ "red", "blue" }) do
        for _, st in ipairs(_plan.air_tasking_orders[c] and _plan.air_tasking_orders[c].stations or {}) do
            stations[st.id] = st
        end
    end
    for id, f in pairs(_flights) do
        local st = f.mission.station and stations[f.mission.station]
        local g = st and f.spawned and Group.getByName(id)
        if g and g:isExist() then
            for _, u in ipairs(g:getUnits() or {}) do
                local ok, air = pcall(function() return u:inAir() end)
                if ok and air then
                    local p = u:getPoint()
                    Log.info(string.format("%s track: %s, %.0f km from station centre", u:getName(),
                        whereIs(u, f.mission.coalition), Util.dist({ x = p.x, z = p.z }, st.centre) / 1000))
                end
            end
        end
    end
    return timer.getTime() + PATROL_TRACK_INTERVAL_S
end

function ScheduleAirTaskingOrders.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    _plan = plan
    timer.scheduleFunction(trackPatrols, nil, timer.getTime() + PATROL_TRACK_INTERVAL_S)
    local now, count, first = timer.getTime(), 0, nil
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            _flights[m.id] = { mission = m, spawned = false, destroyed = 0 }
            if not m.escorts then
                for _, name in ipairs(m.critical_names or {}) do _targets[name] = m.id end
            end
            local at = math.max(m.start_s, now + 1)
            timer.scheduleFunction(function()
                _flights[m.id].spawned = SpawnAircraftGroups.spawn(m) ~= nil
            end, nil, at)
            count = count + 1
            if not first or at < first then first = at end
        end
    end
    world.addEventHandler(handler)
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or ""))
end
