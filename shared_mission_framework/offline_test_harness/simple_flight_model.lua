-- Offline test harness, test B level 2: AI aircraft fly their planned routes, simply
-- (shared_mission_framework framework_design.md, *How the transfer is tested*). Loaded after
-- stub_dcs_world.lua; SimpleFlightModel.install() before the mission's init.lua runs.
--
-- Not a flight model, only enough movement for the mission's in-air code to run:
--   ramp       a group spawned on parking sits still, starts taxiing (ground speed, no
--              movement) TAXI_START_S after its spawn, and takes off TAKEOFF_S after it
--              (a runway start: RUNWAY_TAKEOFF_S); every jet's takeoff event fires then
--   air start  in the air from its spawn, on its first waypoint
--   route      the lead flies each leg in a straight line at the waypoint's speed, its
--              altitude moving evenly to the next waypoint's (a RADIO altitude: above the
--              stand-in ground); wingmen trail it WINGMAN_SPACING_M apart
--   waypoint   on arrival, its tasks as DCS starts them: script commands run (the mission's
--              WAYPOINT / ControllerDirectFlights.waypoint calls), an Orbit (a ControlledTask's,
--              until its stop time) flown as a race-track between its two points
--   landing    at the Land waypoint every jet lands (landing events) and stops on the runway
--   fuel       falls evenly in the air: full to empty in FUEL_ENDURANCE_S
--   orders     a controller's new mission (setTask, a route: sent home, a landing order)
--              replaces the route, flown from its first point; an AttackGroup pushed on top
--              (pushTask, inside a ControlledTask: the bandit call) turns the flight at that
--              group's lead at ATTACK_SPEED_MPS until its time is up, its user flag is set or
--              the group is gone, then back to the route where it left it. A landing order
--              to one jet moves the whole flight (flights here always move as one)
-- Everything moves every STEP_S of mission time, groups in name order, so a run repeats.

SimpleFlightModel = {}

local STEP_S = 2
local TAXI_START_S = 180
local TAKEOFF_S = 120
local RUNWAY_TAKEOFF_S = 60
local TAXI_SPEED_MPS = 8
local WINGMAN_SPACING_M = 600
local FUEL_ENDURANCE_S = 4 * 3600
local DEFAULT_SPEED_MPS = 200
local ATTACK_SPEED_MPS = 300

local W = StubDcsWorld
local flights = {}   -- by group name: { group, phase, points, index, ... }

local function airbaseById(id)
    for _, ab in ipairs(world.getAirbases()) do
        if ab:getID() == id then return ab end
    end
    return nil
end

local function groundHeight() return land.getHeight({}) end

local function pointAltitude(p)
    if p.alt_type == "RADIO" then return groundHeight() + (p.alt or 0) end
    return p.alt or groundHeight()
end

local function tasksOf(point)
    local t = point and point.task
    if t and t.id == "ComboTask" then return t.params and t.params.tasks or {} end
    return t and { t } or {}
end

-- The tasks a waypoint starts: script commands run now; an Orbit (bare, or a ControlledTask's,
-- with its stop time) returned for the flight to fly.
local function startWaypointTasks(f, point)
    local orbit
    for _, task in ipairs(tasksOf(point)) do
        local action = task.id == "WrappedAction" and task.params and task.params.action
        if action and action.id == "Script" then
            local chunk, err = loadstring(action.params.command)
            local ok, runErr = false, err
            if chunk then ok, runErr = pcall(chunk) end
            if not ok then env.error(f.group.name .. " waypoint script failed: " .. tostring(runErr)) end
        elseif task.id == "ControlledTask" and task.params.task and task.params.task.id == "Orbit" then
            orbit = { params = task.params.task.params, until_s = task.params.stopCondition and task.params.stopCondition.time }
        elseif task.id == "Orbit" then
            orbit = { params = task.params }
        end
    end
    return orbit
end

-- Puts every live jet of the flight at the lead's place (wingmen trailing it), with the
-- lead's heading and speed.
local function placeJets(f, x, z, alt, heading, speed)
    for i, u in ipairs(f.group.unit_list) do
        local back = (i - 1) * WINGMAN_SPACING_M
        u.pos.x, u.pos.z = x - back * math.cos(heading), z - back * math.sin(heading)
        u.pos.y, u.heading, u.speed = alt, heading, speed
    end
end

local function fireForEachJet(f, eventId, place)
    for _, u in ipairs(f.group:getUnits()) do
        W.fireEvent({ id = eventId, initiator = u, place = place })
    end
end

local function takeOff(f)
    f.phase, f.airborne_at = "airborne", StubDcs.now
    for _, u in ipairs(f.group.unit_list) do u.in_air = true end
    local first = f.points[1]
    placeJets(f, first.x, first.y, groundHeight() + 50, f.group.unit_list[1].heading, DEFAULT_SPEED_MPS)
    f.index = 2
    fireForEachJet(f, world.event.S_EVENT_TAKEOFF, f.launch_base)
end

local function land_(f, point)
    f.phase = "landed"
    for _, u in ipairs(f.group.unit_list) do u.in_air, u.speed = false, 0 end
    placeJets(f, point.x, point.y, groundHeight(), f.group.unit_list[1].heading, 0)
    fireForEachJet(f, world.event.S_EVENT_LAND, point.airdromeId and airbaseById(point.airdromeId))
end

local function groupById(id)
    for _, g in pairs(W.groups) do
        if g.id == id then return g end
    end
    return nil
end

-- An attack pushed on top still running: its stop condition not met, its target alive.
local function attackGoesOn(a, now)
    if a.until_s and now >= a.until_s then return false end
    if a.flag and trigger.misc.getUserFlag(a.flag) == (a.flag_value and 1 or 0) then return false end
    return a.target.alive and #a.target.unit_list > 0
end

-- One step of a flight in the air: at the group it attacks, on along its orbit, or toward
-- its next waypoint.
local function fly(f, now)
    local lead = f.group.unit_list[1]
    for _, u in ipairs(f.group.unit_list) do
        u.fuel = math.max(0, 1 - (now - f.airborne_at) / FUEL_ENDURANCE_S)
    end
    if f.attack then
        if attackGoesOn(f.attack, now) then
            local t = f.attack.target.unit_list[1].pos
            local dx, dz = t.x - lead.pos.x, t.z - lead.pos.z
            local d = math.max(1, math.sqrt(dx * dx + dz * dz))
            local step = math.min(d, ATTACK_SPEED_MPS * STEP_S)
            placeJets(f, lead.pos.x + dx / d * step, lead.pos.z + dz / d * step, lead.pos.y, math.atan2(dz, dx),
                ATTACK_SPEED_MPS)
            return
        end
        f.attack = nil
    end
    if f.orbit then
        local o = f.orbit
        if o.until_s and now >= o.until_s then
            f.orbit = nil
        else
            -- a race-track: back and forth between its two points
            local a, b = o.params.point, o.params.point2 or o.params.point
            local target = f.orbit_toward_second and b or a
            local dx, dz = target.x - lead.pos.x, target.y - lead.pos.z
            local d = math.sqrt(dx * dx + dz * dz)
            local speed = o.params.speed or DEFAULT_SPEED_MPS
            local alt = o.params.altitude or lead.pos.y
            if d <= speed * STEP_S then
                f.orbit_toward_second = not f.orbit_toward_second
                placeJets(f, target.x, target.y, alt, lead.heading, speed)
            else
                local h = math.atan2(dz, dx)
                placeJets(f, lead.pos.x + dx / d * speed * STEP_S, lead.pos.z + dz / d * speed * STEP_S, alt, h, speed)
            end
            return
        end
    end
    local point = f.points[f.index]
    if not point then return end
    local dx, dz = point.x - lead.pos.x, point.y - lead.pos.z
    local d = math.sqrt(dx * dx + dz * dz)
    local speed = (point.speed and point.speed > 0) and point.speed or DEFAULT_SPEED_MPS
    local step = speed * STEP_S
    local targetAlt = pointAltitude(point)
    if d <= step then
        if point.type == "Land" then
            land_(f, point)
            return
        end
        placeJets(f, point.x, point.y, targetAlt, lead.heading, speed)
        f.index = f.index + 1
        f.orbit = startWaypointTasks(f, point)
        f.orbit_toward_second = true
        return
    end
    -- the altitude moves evenly over the leg toward the waypoint's
    local alt = lead.pos.y + (targetAlt - lead.pos.y) * math.min(1, step / d)
    local h = math.atan2(dz, dx)
    placeJets(f, lead.pos.x + dx / d * step, lead.pos.z + dz / d * step, alt, h, speed)
end

local function stepAll()
    local now = StubDcs.now
    local names = {}
    for name, f in pairs(flights) do
        if f.group.alive then names[#names + 1] = name else flights[name] = nil end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local f = flights[name]
        if f.phase == "ramp" then
            if now >= f.taxi_at and not f.taxiing then
                f.taxiing = true
                for _, u in ipairs(f.group.unit_list) do u.speed = TAXI_SPEED_MPS end
            end
            if now >= f.takeoff_at then takeOff(f) end
        elseif f.phase == "airborne" then
            fly(f, now)
        end
    end
    return now + STEP_S
end

-- A new mission: its route replaces the flight's, flown from its first point.
local function onSetTask(group, task)
    local f = flights[group.name]
    if not (f and f.phase == "airborne" and task and task.id == "Mission") then return end
    local points = task.params and task.params.route and task.params.route.points
    if not points or #points == 0 then return end
    f.points, f.index, f.orbit, f.attack = points, 1, nil, nil
end

-- An AttackGroup pushed on top of the mission, bare or inside a ControlledTask.
local function onPushTask(group, task)
    local f = flights[group.name]
    if not (f and f.phase == "airborne" and task) then return end
    local inner, stop = task, nil
    if task.id == "ControlledTask" then inner, stop = task.params.task, task.params.stopCondition end
    if not (inner and inner.id == "AttackGroup") then return end
    local target = groupById(inner.params.groupId)
    if not target then return end
    f.attack = { target = target, until_s = stop and stop.duration and (StubDcs.now + stop.duration),
                 flag = stop and stop.userFlag, flag_value = stop and stop.userFlagValue }
end

function SimpleFlightModel.install()
    W.onSetTask, W.onPushTask = onSetTask, onPushTask
    local addGroup = coalition.addGroup
    coalition.addGroup = function(countryId, category, data)
        local g = addGroup(countryId, category, data)
        if category == Group.Category.AIRPLANE or category == Group.Category.HELICOPTER then
            local points = data.route and data.route.points or {}
            local first = points[1] or {}
            local f = { group = g, points = points, index = 1 }
            if type(first.type) == "string" and first.type:find("^TakeOff") then
                local runway = first.type == "TakeOff"
                f.phase = "ramp"
                f.launch_base = first.airdromeId and airbaseById(first.airdromeId)
                f.taxi_at = StubDcs.now + (runway and 0 or TAXI_START_S)
                f.takeoff_at = f.taxi_at + (runway and RUNWAY_TAKEOFF_S or TAKEOFF_S)
            else
                -- an air start: on its first waypoint already, its tasks started
                f.phase, f.airborne_at, f.index = "airborne", StubDcs.now, 2
                f.orbit = startWaypointTasks(f, first)
                f.orbit_toward_second = true
            end
            flights[g.name] = f
        end
        return g
    end
    timer.scheduleFunction(stepAll, nil, 1)
end
