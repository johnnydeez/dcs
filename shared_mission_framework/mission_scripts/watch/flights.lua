-- Watch: what happens to each flight once launched, from DCS's events: jets taking off,
-- landing and lost, its mission's target objects destroyed, wingmen possibly orphaned, and
-- when every jet of it is down. Written to record\flights.lua; the controller hears a
-- flight down there (the SEAD rotation's next flight goes) and a jet landed (removed a
-- few minutes later, freeing its parking spot and the alive-aircraft budget).
-- The flights themselves are the controller's ledger, record\flight_launches.lua: a facts
-- entry is opened for each flight that enters it.
--
-- Event log lines, for each mission's target progress and jets lost on the ramp before
-- takeoff:
--   "TARGET     MSN2001_STRIKE  TGT_IVAL_command_post_1_static_2 destroyed: 3 of 6 critical"
--   "RAMP_LOSS  MSN7009_CAP_1  Su-27 destroyed on the ramp 8 s after spawning, before taking off, at Afrikanda spot 37: …"
-- and wingmen that may be orphaned (bug 19), one line when it may be, one for how it ended
-- (under the word CONTROL, beside the controller's own >>orphan<< removed; John: >>orphan<<
-- to find them at a glance):
--   "CONTROL  MSN7023_SEAD_2  >>orphan<< possibly orphaned: still in the air when MSN7023_SEAD_1 landed (Su-34 at 4,232 ft, 7 km from Banak)"
--   "CONTROL  MSN7023_SEAD_2  >>orphan<< not orphaned: landed at Banak 4 min 40 s after MSN7023_SEAD_1"
--   "CONTROL  MSN7023_SEAD_2  >>orphan<< lost: 9 min 50 s after MSN7023_SEAD_1 landed"
-- Reads the plan; writes nothing back to it.

WatchFlights = {}

local RAMP_LOSS_S = 120   -- a jet destroyed this soon after spawning, before takeoff, is a spawn failure

local _flights = {}   -- flight id → facts (record\flights.lua)
local _targets = {}   -- critical object name → mission id
local _gone    = {}   -- names already counted destroyed or lost
local _tookOff = {}   -- unit names of AI jets that have taken off
RecordFlights.writeTables(_flights, _gone, _tookOff)

local function nameOf(object)
    local ok, name = pcall(function() return object:getName() end)
    return ok and name or nil
end

-- The mission id of the flight this unit belongs to, or nil.
local function flightOf(unit)
    local ok, name = pcall(function() return unit:getGroup():getName() end)
    if ok and _flights[name] then return name end
    return nil
end

local function flown(id)
    return RecordFlightLaunches.missionFlown(id)
end

-- Says once, when every jet of flight `name` is down (landed, lost, or removed by the
-- controller on the ramp).
local function checkDown(name)
    local f, l = _flights[name], RecordFlightLaunches.launch(name)
    local m = flown(name)
    if f.down or f.lost + f.landed + (l.removed or 0) < m.count then return end
    f.down = true
    RecordFlights.publish({ event = "down", id = name })
end

-- An >>orphan<< fact line, under the word CONTROL as the controller's are.
local function orphanLine(coalition, subject, decision, text)
    EventLog.add(coalition, "CONTROL", subject, decision .. ": " .. text)
end

local function minSec(s)
    s = math.floor(s)
    return string.format("%d min %02d s", math.floor(s / 60), s % 60)
end

-- Where jet `unitName` of mission `m` is, for an >>orphan<< line: "Su-34 at 4,232 ft, 7 km
-- from Banak".
function WatchFlights.jetWhere(m, unitName)
    local ok, text = pcall(function()
        local p = Unit.getByName(unitName):getPoint()
        local base = Airbase.getByName(m.landing_base):getPoint()
        return string.format("%s at %s ft, %.0f km from %s", m.aircraft_type, Util.thousands(p.y * 3.28084),
            Util.dist({ x = p.x, z = p.z }, { x = base.x, z = base.z }) / 1000, m.landing_base)
    end)
    return ok and text or m.aircraft_type
end

-- Orphaned wingmen (bug 19): a jet still in the air when another of its flight lands may
-- never come out of its hold. Each gets an >>orphan<< line then, and another when it lands
-- after all or the controller removes it, so the rate can be followed run to run.
local function watchOrphans(name, f, landedName)
    local m = flown(name)
    f.orphans = f.orphans or {}
    local ok, units = pcall(function() return Group.getByName(name):getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local uName = nameOf(u)
        local okUp, up = pcall(function() return u:isExist() and u:inAir() end)
        if uName and uName ~= landedName and okUp and up and not f.orphans[uName] then
            f.orphans[uName] = { since = timer.getTime(), lead = landedName }
            orphanLine(m.coalition, uName, ">>orphan<< possibly orphaned", string.format("still in the air when %s landed (%s)",
                landedName, WatchFlights.jetWhere(m, uName)))
        end
    end
end

local function landed(unit)
    local name = flightOf(unit)
    if not name then return end
    local unitName = unit:getName()
    local f = _flights[name]
    f.landed = f.landed + 1
    f.last_landing_at, f.last_landed = timer.getTime(), unitName   -- for the landing directive's orphans
    local orphan = f.orphans and f.orphans[unitName]
    if orphan and not orphan.closed then
        orphan.closed = true
        local m = flown(name)
        orphanLine(m.coalition, unitName, ">>orphan<< not orphaned", string.format("landed at %s %s after %s",
            m.landing_base, minSec(timer.getTime() - orphan.since), orphan.lead))
    end
    watchOrphans(name, f, unitName)
    checkDown(name)
    RecordFlights.publish({ event = "landed", id = name, unit = unitName })
end

-- A jet destroyed before it ever took off, within RAMP_LOSS_S of its spawn: a spawn
-- failure, not combat (bug 13: Su-34s and a Su-27 blew up on Afrikanda's ramp seconds
-- after spawning, no killer recorded). Said in dcs.log and the event log, with its spot.
local function rampLoss(id, unitName)
    local l = RecordFlightLaunches.launch(id)
    if _tookOff[unitName] or not l.spawned_at then return end
    local after = timer.getTime() - l.spawned_at
    if after > RAMP_LOSS_S then return end
    local m = flown(id)
    if m.takeoff == "air" then return end   -- spawned in the air: never on a ramp
    local n = tonumber(unitName:match("_(%d+)$") or "")
    local spot = n and m.parking and m.parking[n]
    local text = string.format("%s destroyed on the ramp %d s after spawning, before taking off, at %s spot %s: a spawn failure, not combat",
        m.aircraft_type, math.floor(after), m.launch_base, spot and tostring(spot.terminal_index) or "?")
    Log.warn(unitName .. ": " .. text)
    EventLog.add(m.coalition, "RAMP_LOSS", unitName, text)
end

local function destroyed(object)
    local name = nameOf(object)
    if not name or _gone[name] then return end
    local target = _targets[name]
    if target then
        _gone[name] = true
        local f, m = _flights[target], RecordFlightLaunches.launch(target).mission
        f.destroyed = f.destroyed + 1
        EventLog.add(m.coalition, "TARGET", target, string.format("%s destroyed: %d of %d critical",
            name, f.destroyed, #m.critical_names))
        return
    end
    local flight = flightOf(object)
    if flight then
        _gone[name] = true
        local f = _flights[flight]
        f.lost = f.lost + 1
        rampLoss(flight, name)
        local orphan = f.orphans and f.orphans[name]
        if orphan and not orphan.closed then
            orphan.closed = true
            local m = flown(flight)
            orphanLine(m.coalition, name, ">>orphan<< lost", string.format("%s after %s landed",
                minSec(timer.getTime() - orphan.since), orphan.lead))
        end
        checkDown(flight)
    end
end

-- Jets the controller removed in the air (wingmen still up long after their flight's
-- last landing, bug 19): they count as landed, so whatever waits on the flight sees it down.
local function removedInAir(id, names)
    local f = _flights[id]
    if not f then return end
    for _, name in ipairs(names) do
        _gone[name] = true   -- a stray dead event isn't a loss
        local orphan = f.orphans and f.orphans[name]
        if orphan then orphan.closed = true end
    end
    f.landed = f.landed + #names
    checkDown(id)
end

local handler = {}
function handler:onEvent(e)
    -- a kill counts even when its shooter is already gone (no initiator)
    if e.id == world.event.S_EVENT_KILL then
        if e.target then destroyed(e.target) end
        return
    end
    if not e.initiator then return end
    if e.id == world.event.S_EVENT_TAKEOFF then
        local name = nameOf(e.initiator)
        if name then _tookOff[name] = true end
    elseif e.id == world.event.S_EVENT_LAND then
        local ok, category = pcall(function() return e.initiator:getCategory() end)
        if ok and category == Object.Category.UNIT then landed(e.initiator) end
    elseif e.id == world.event.S_EVENT_DEAD then
        destroyed(e.initiator)
    elseif e.id == world.event.S_EVENT_CRASH then
        destroyed(e.initiator)
    elseif e.id == world.event.S_EVENT_EJECTION then
        destroyed(e.initiator)
    end
end

function WatchFlights.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    -- every flight that enters the controller's ledger gets its facts
    RecordFlightLaunches.on("added", function(e)
        _flights[e.id] = { destroyed = 0, lost = 0, landed = 0 }
    end)
    RecordFlightLaunches.on("removed", function(e)
        if _flights[e.id] then checkDown(e.id) end
    end)
    RecordFlightLaunches.on("removed_in_air", function(e) removedInAir(e.id, e.names) end)
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            -- a SEAD flight's target (its site) isn't counted for it: the gate looks at the
            -- site itself, and a DEAD on the same site keeps its own TARGET lines
            if m.mission_type ~= "suppression_of_air_defenses" then
                for _, name in ipairs(m.critical_names or {}) do _targets[name] = m.id end
            end
        end
    end
    RecordDcsEvents.on(function(fact) if fact.raw then handler:onEvent(fact.raw) end end)
end
