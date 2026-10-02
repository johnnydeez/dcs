-- Consumer: runs the air tasking orders on the mission clock, and keeps the record of each
-- flight. When a planned flight is due (at its start_s, mission time; a start already past
-- is due a second from now) the scheduler asks the controller (ControlAirFlights.due,
-- consumers/control_air_flights/decide_launches.lua) and carries out what it decides:
-- launch now, look again later, fly a SEAD flight again, or nothing (cancelled). When
-- every jet of a launched flight is down (landed, lost, removed on the ramp) it tells
-- the controller (ControlAirFlights.flightDown: the SEAD rotation's next flight goes).
-- The decisions are the controller's (roadmap.md item 11); this keeps the clock, spawns,
-- and records (John, 2026-10-01).
-- Aircraft of planned flights are removed a few minutes after they land, freeing their
-- parking spots and the alive-aircraft budget (the Syria S_EVENT_LAND pattern).
-- What the flights did (shots, kills, losses, landings, positions) goes to the event
-- log (consumers/write_event_log.lua), which catches the DCS events for every unit; this
-- adds each mission's target progress, and jets lost on the ramp before takeoff:
--   "TARGET     MSN2001_STRIKE  TGT_IVAL_command_post_1_static_2 destroyed: 3 of 6 critical"
--   "RAMP_LOSS  MSN7009_CAP_1  Su-27 destroyed on the ramp 8 s after spawning, before taking off, at Afrikanda spot 37: …"
-- Reads the plan; writes nothing back to it. What has launched, landed and been
-- destroyed is runtime state, kept here under the plan's mission ids.

ScheduleAirTaskingOrders = {}

local REMOVE_AFTER_LANDING_S = 180
local RAMP_LOSS_S = 120   -- a jet destroyed this soon after spawning, before takeoff, is a spawn failure

local _plan
local _byId = {}      -- mission id → planned mission
local _flights = {}   -- mission id → { mission, spawned, spawned_at, destroyed = n, lost, landed, removed, again, note, stood_down, down }
local _targets = {}   -- critical object name → mission id
local _gone    = {}   -- names already counted destroyed or lost
local _tookOff = {}   -- unit names of AI jets that have taken off

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

-- Tells the controller once, when every jet of flight `name` is down.
local function checkDown(name)
    local f = _flights[name]
    local m = f.mission_flown or f.mission
    if f.down or f.lost + f.landed + (f.removed or 0) < m.count then return end
    f.down = true
    local ok, err = pcall(ControlAirFlights.flightDown, name)
    if not ok then Log.warn(string.format("%s: flight down: %s", name, tostring(err))) end
end

local function landed(unit)
    local name = flightOf(unit)
    if not name then return end
    local unitName = unit:getName()
    _flights[name].landed = _flights[name].landed + 1
    checkDown(name)
    timer.scheduleFunction(function()
        local u = Unit.getByName(unitName)
        if u and u:isExist() then u:destroy() end
    end, nil, timer.getTime() + REMOVE_AFTER_LANDING_S)
end

-- A jet destroyed before it ever took off, within RAMP_LOSS_S of its spawn: a spawn
-- failure, not combat (bug 13: Su-34s and a Su-27 blew up on Afrikanda's ramp seconds
-- after spawning, no killer recorded). Said in dcs.log and the event log, with its spot.
local function rampLoss(f, unitName)
    if _tookOff[unitName] or not f.spawned_at then return end
    local after = timer.getTime() - f.spawned_at
    if after > RAMP_LOSS_S then return end
    local m = f.mission_flown or f.mission
    local n = tonumber(unitName:match("_(%d+)$") or "")
    local spot = n and m.parking and m.parking[n]
    local text = string.format("%s destroyed on the ramp %d s after spawning, before taking off, at %s spot %s: a spawn failure, not combat",
        m.aircraft_type, math.floor(after), m.launch_base, spot and tostring(spot.terminal_index) or "?")
    Log.warn(unitName .. ": " .. text)
    WriteEventLog.add(m.coalition, "RAMP_LOSS", unitName, text)
end

local function destroyed(object)
    local name = nameOf(object)
    if not name or _gone[name] then return end
    local target = _targets[name]
    if target then
        _gone[name] = true
        local f = _flights[target]
        f.destroyed = f.destroyed + 1
        WriteEventLog.add(f.mission.coalition, "TARGET", target, string.format("%s destroyed: %d of %d critical",
            name, f.destroyed, #f.mission.critical_names))
        return
    end
    local flight = flightOf(object)
    if flight then
        _gone[name] = true
        local f = _flights[flight]
        f.lost = f.lost + 1
        rampLoss(f, name)
        checkDown(flight)
    end
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

-- ── launching ───────────────────────────────────────────────────

-- Parking for a flight launched later than planned: free spots of its types now, its
-- own planned spots first, never a player slot, a parked-aircraft static or an alert
-- jet's spot. { { terminal_index, x, z } } or nil.
local function spotsNow(m)
    local ab = Airbase.getByName(m.launch_base)
    local ok, list = pcall(function() return ab:getParking(true) end)
    if not ok or type(list) ~= "table" then return nil end
    local terminals, planned, blocked = {}, {}, {}
    for _, t in ipairs(AIRCRAFT_PROFILE[m.aircraft_type].parking) do terminals[t] = true end
    for i, s in ipairs(m.parking or {}) do planned[s.terminal_index] = i end
    local world = _plan.world.airbases[m.launch_base]
    for idx in pairs(world and world.player_slots or {}) do blocked[idx] = true end
    for idx in pairs(_plan.fixed_ground_targets and _plan.fixed_ground_targets.parking_used[m.launch_base] or {}) do blocked[idx] = true end
    local alert = _plan.air_tasking_orders[m.coalition].alert
    for _, b in ipairs(alert and alert.bases or {}) do
        if b.base == m.launch_base then
            for _, s in ipairs(b.spots or {}) do blocked[s.terminal_index] = true end
        end
    end
    local free = {}
    for _, s in ipairs(list) do
        if terminals[s.Term_Type] and not blocked[s.Term_Index] then
            free[#free + 1] = { terminal_index = s.Term_Index, x = s.vTerminalPos.x, z = s.vTerminalPos.z,
                                order = planned[s.Term_Index] or 100 + (s.fDistToRW or 0) }
        end
    end
    if #free < m.count then return nil end
    table.sort(free, function(a, b) return a.order < b.order end)
    local spots = {}
    for i = 1, m.count do spots[i] = { terminal_index = free[i].terminal_index, x = free[i].x, z = free[i].z } end
    return spots
end

-- An AI flight flying a player's SEAD tasking (its retry: a player flight can't be
-- copied): two jets of the same type with the AI's SEAD loadout, on the same route.
local function aiVersion(s)
    if s.flown_by ~= "human" then return s end
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    c.flown_by, c.player_slot = "ai", nil
    c.count = AIRCRAFT_PROFILE[s.aircraft_type].flight_size[2]
    c.loadout = AIRCRAFT_LOADOUT[s.aircraft_type][s.mission_type]
    c.skill = Util.pick(AIR_TASKING_SKILL)
    return c
end

-- A copy of a planned mission launched `delay` seconds later than planned, under `id`,
-- on spots free now (the plan itself is never changed). nil when no spots are free.
local function later(m, delay, id)
    local spots = spotsNow(m)
    if not spots then return nil end
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    c.id = id or m.id
    c.start_s, c.takeoff_s, c.tot_s, c.end_s = m.start_s + delay, m.takeoff_s + delay, m.tot_s + delay, m.end_s + delay
    c.parking = spots
    c.route = {}
    for i, r in ipairs(m.route) do c.route[i] = r end
    local first = {}
    for k, v in pairs(m.route[1]) do first[k] = v end
    first.x, first.z = spots[1].x, spots[1].z
    c.route[1] = first
    return c
end

local function due(id)
    local ok, err = pcall(ControlAirFlights.due, id)
    if not ok then Log.error(string.format("%s: launch decision failed: %s", id, tostring(err))) end
end

-- ── calls for the controller ────────────────────────────────────

-- The planned mission `id` (never changed).
function ScheduleAirTaskingOrders.planned(id)
    return _byId[id]
end

-- The record of flight `id`: { mission, spawned, destroyed, lost, landed, again (the id
-- of its second try), note, stood_down }, or nil. Read it, never change it.
function ScheduleAirTaskingOrders.record(id)
    return _flights[id]
end

-- True once the object `name` has been counted destroyed or lost.
function ScheduleAirTaskingOrders.isGone(name)
    return _gone[name] == true
end

-- Ask the controller about flight `id` again at mission time `t`.
function ScheduleAirTaskingOrders.lookAgainAt(id, t)
    timer.scheduleFunction(function() due(id) end, nil, t)
end

-- What the brief and the end summary say of a flight not flying (yet): "delayed",
-- "cancelled", "not needed".
function ScheduleAirTaskingOrders.note(id, note)
    if _flights[id] then _flights[id].note = note end
end

-- Spawn planned flight `id` now; `delay` > 0: a copy `delay` s later than planned, on
-- spots free now. Returns the mission flown, or nil (no spots free, or the spawn failed).
function ScheduleAirTaskingOrders.launchNow(id, delay)
    local f, m = _flights[id], _byId[id]
    if delay > 0 then
        m = later(m, delay)
        if not m then return nil end
        f.mission_flown = m
    end
    f.note = nil
    local grp = SpawnAircraftGroups.spawn(m)
    f.spawned = grp ~= nil
    f.spawned_at = timer.getTime()
    return grp and m or nil
end

-- Fly SEAD flight `by` once more now (a player's SEAD tasking by two AI jets), as
-- `<by>_AGAIN` on spots free now. Returns the copy, or nil.
function ScheduleAirTaskingOrders.flyAgain(by)
    local s = aiVersion(_byId[by])
    local copy = later(s, timer.getTime() + 1 - s.start_s, s.id .. "_AGAIN")
    if not copy or not SpawnAircraftGroups.spawn(copy) then return nil end
    _flights[copy.id] = { mission = copy, spawned = true, spawned_at = timer.getTime(), destroyed = 0, lost = 0, landed = 0 }
    _flights[by].again = copy.id
    return copy
end

-- A flight spawned at run time (a scramble), tracked like a planned one: its losses
-- count and its aircraft are removed after landing.
function ScheduleAirTaskingOrders.track(m)
    _flights[m.id] = { mission = m, spawned = true, spawned_at = timer.getTime(), destroyed = 0, lost = 0, landed = 0 }
end

-- Jets of flight `id` the controller removed on the ramp (they carried no weapons): they
-- never fly, and the flight's state counts them out.
function ScheduleAirTaskingOrders.removed(id, n)
    local f = _flights[id]
    if f then
        f.removed = (f.removed or 0) + n
        checkDown(id)
    end
end

-- A mission's target progress: critical objects destroyed so far (anyone's hits count),
-- and how many it has.
function ScheduleAirTaskingOrders.targetProgress(id)
    local f = _flights[id]
    if not f then return 0, 0 end
    return f.destroyed, #(f.mission.critical_names or {})
end

-- A flight removed on the ramp before it took off (a scramble the leash stood down).
function ScheduleAirTaskingOrders.stoodDown(id)
    if _flights[id] then _flights[id].stood_down = true end
end

-- A planned flight's state now, in a few words: "planned", "airborne", "landed",
-- "2 of 2 lost", …, plus its target objects destroyed so far (anyone's hits count).
function ScheduleAirTaskingOrders.statusOf(id)
    local f = _flights[id]
    if not f then return "unknown" end
    local m = f.mission
    local state
    if m.flown_by == "human" then
        state = "for a player"
    elseif f.note == "not needed" or f.note == "cancelled" then
        state = f.note
    elseif f.stood_down then
        state = "stood down on the ramp"
    elseif not f.spawned then
        state = f.note == "delayed" and "delayed" or "planned"
    elseif (f.removed or 0) >= m.count then
        state = "removed on the ramp, unarmed"
    elseif f.lost >= m.count then
        state = string.format("%d of %d lost", f.lost, m.count)
    elseif f.lost + f.landed + (f.removed or 0) >= m.count then
        state = f.lost > 0 and string.format("landed, %d lost", f.lost) or "landed"
    else
        state = f.lost > 0 and string.format("airborne, %d lost", f.lost) or "airborne"
    end
    if (f.removed or 0) > 0 and f.removed < m.count then
        state = string.format("%s, %d removed unarmed", state, f.removed)
    end
    if f.destroyed > 0 then
        state = string.format("%s; target %d of %d critical destroyed", state, f.destroyed, #(m.critical_names or {}))
    end
    return state
end

function ScheduleAirTaskingOrders.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    _plan = plan
    local now, count, first = timer.getTime(), 0, nil
    local human = 0
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            _flights[m.id] = { mission = m, spawned = false, destroyed = 0, lost = 0, landed = 0 }
            _byId[m.id] = m
            -- a SEAD flight's target (its site) isn't counted for it: the gate looks at the
            -- site itself, and a DEAD on the same site keeps its own TARGET lines
            if m.mission_type ~= "suppression_of_air_defenses" then
                for _, name in ipairs(m.critical_names or {}) do _targets[name] = m.id end
            end
            -- human flights aren't spawned: the player spawns in on the slot (its target
            -- is still watched, above)
            if m.flown_by == "human" then
                human = human + 1
            else
                local at = math.max(m.start_s, now + 1)
                ScheduleAirTaskingOrders.lookAgainAt(m.id, at)
                count = count + 1
                if not first or at < first then first = at end
            end
        end
    end
    world.addEventHandler(handler)
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s, %d human flights left to players ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or "", human))
end
