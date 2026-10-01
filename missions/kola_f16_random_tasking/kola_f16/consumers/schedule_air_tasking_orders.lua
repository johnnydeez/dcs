-- Consumer: runs the air tasking orders on the mission clock. Each planned flight is
-- spawned by SpawnAircraftGroups at its start_s (mission time); a start already past is
-- spawned a second from now. Aircraft of planned flights are removed a few minutes after
-- they land, freeing their parking spots and the alive-aircraft budget (the Syria
-- S_EVENT_LAND pattern).
-- AI packages fly in sequence (plan: requires_cleared, cleared_by; John, 2026-10-01): a
-- mission that needs its route's threats out of the fight launches only once they are
-- (a SAM site's radars destroyed to its success fraction, a base-defense group with no
-- live unit). If they aren't when it's due: while one of its suppression flights is still
-- in the air it waits for it; otherwise those suppression flights fly once more (a copy,
-- id <id>_AGAIN; a player's SEAD tasking is flown again by two AI jets) and the mission
-- waits for them to land; if that fails too, it is cancelled. A suppression flight whose threats are already out of the fight isn't sent.
-- A mission launched late waits for room under the airborne cap.
-- What the flights did (shots, kills, losses, landings, positions) goes to the event
-- log (consumers/write_event_log.lua), which catches the DCS events for every unit; this
-- adds each mission's target progress and its launch decisions:
--   "TARGET     MSN2001_STRIKE  TGT_IVAL_command_post_1_static_2 destroyed: 3 of 6 critical"
--   "DELAYED    MSN2031_STRIKE  waiting for MSN2030_SEAD, still in the air; looking again at 10:42"
--   "RETRY      MSN2031_STRIKE  SAM_KOSH_SA10_1 still in the fight: MSN2030_SEAD flies again as
--                               MSN2030_SEAD_AGAIN; the strike waits until 11:25"
--   "CANCELLED  MSN2031_STRIKE  SAM_KOSH_SA10_1 still in the fight after a second suppression flight"
--   "CANCELLED  MSN2030_SEAD    not needed: SAM_KOSH_SA10_1 is already out of the fight"
-- Reads the plan; writes nothing back to it. What has launched, landed and been
-- destroyed is runtime state, kept here under the plan's mission ids.

ScheduleAirTaskingOrders = {}

local REMOVE_AFTER_LANDING_S = 180

local _plan
local _catalog = {}   -- catalog target id → target
local _byId = {}      -- mission id → planned mission
local _flights = {}   -- mission id → { mission, spawned, destroyed = n }
local _targets = {}   -- critical object name → mission id
local _gone    = {}   -- names already counted destroyed or lost

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
    _flights[name].landed = _flights[name].landed + 1
    timer.scheduleFunction(function()
        local u = Unit.getByName(unitName)
        if u and u:isExist() then u:destroy() end
    end, nil, timer.getTime() + REMOVE_AFTER_LANDING_S)
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
        _flights[flight].lost = _flights[flight].lost + 1
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
    if e.id == world.event.S_EVENT_LAND then
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

-- ── launching in sequence ───────────────────────────────────────

local SIDE = { red = 1, blue = 2 }

local function liveUnit(name)
    local o = Unit.getByName(name) or StaticObject.getByName(name)
    local ok, live = pcall(function() return o and o:isExist() and o:getLife() >= 1 end)
    return ok and live == true
end

local function liveGroup(name)
    local g = Group.getByName(name)
    local ok, live = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then return true end
        end
        return false
    end)
    return ok and live == true
end

-- Whether a threat is out of the fight: a SAM site (a catalog target) whose critical
-- objects (its radars) are destroyed to its success fraction; a group (a base-defense
-- radar missile launcher) with no live unit.
local function threatCleared(id)
    local t = _catalog[id]
    if t and t.critical_names and #t.critical_names > 0 then
        local dead = 0
        for _, name in ipairs(t.critical_names) do
            if _gone[name] or not liveUnit(name) then dead = dead + 1 end
        end
        local frac = t.success and t.success.critical_fraction or 1
        return dead >= math.max(1, math.ceil(frac * #t.critical_names - 1e-9))
    end
    return not liveGroup(id)
end

local function openThreats(ids)
    local open = {}
    for _, id in ipairs(ids or {}) do
        if not threatCleared(id) then open[#open + 1] = id end
    end
    return open
end

-- The coalition's AI aircraft in the air (players don't count), against what planned
-- flights may fill of the cap (the rest is the scrambles').
local function roomFor(m)
    local n = 0
    for _, g in ipairs(coalition.getGroups(SIDE[m.coalition], Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            local ok, air = pcall(function() return u:inAir() and not u:getPlayerName() end)
            if ok and air then n = n + 1 end
        end
    end
    local cap = AIR_TASKING_PER_COALITION[m.coalition].max_airborne_aircraft
    if AIR_DEFENSE.planned and AIR_DEFENSE.alert_posture_planned then cap = cap - AIR_DEFENSE.scramble_reserve_aircraft end
    return n + m.count <= cap
end

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

local function clockText(t) return Weather.hhmm(_plan.world.time.start_local + t) end

local function spawnNow(m, f)
    local grp = SpawnAircraftGroups.spawn(m)
    f.spawned = grp ~= nil
    -- a SEAD flight goes cold after its salvo (consumers/enforce_air_behaviour_rules.lua)
    if grp and m.attack and m.attack.kind == "harm_salvo" then EnforceAirBehaviourRules.watch(m, "suppression") end
    return grp
end

local launch

-- Launches a planned mission (or its late copy `m`) when it's due: in sequence, only
-- once its threats are out of the fight.
launch = function(id, m)
    local f = _flights[id]
    local plan = _byId[id]
    m = m or plan
    local now = timer.getTime()
    -- a suppression flight whose threats are already out of the fight isn't sent
    if plan.escorts and #(plan.suppresses or {}) > 0 and #openThreats(plan.suppresses) == 0 then
        f.note = "not needed"
        WriteEventLog.add(m.coalition, "CANCELLED", id, string.format("not needed: %s already out of the fight",
            table.concat(plan.suppresses, ", ")))
        return
    end
    local open = openThreats(plan.requires_cleared)
    if #open > 0 then
        -- per suppression flight still owed: in the air (wait for it), flown once more
        -- already (its second try is spent), or to fly again now. A suppression flight
        -- flies again at most once, whichever missions rely on it (one may clear the way
        -- for several), and they all wait for that one
        local flying, send, spent = nil, {}, {}
        for _, t in ipairs(open) do
            local by = plan.cleared_by and plan.cleared_by[t]
            local sf = by and _flights[by]
            if sf then
                if sf.again then
                    if liveGroup(sf.again) then flying = sf.again else spent[#spent + 1] = t end
                elseif sf.spawned and liveGroup(by) then
                    flying = by
                else
                    -- a player's SEAD tasking (flown or not) is flown again by the AI
                    send[by] = true
                end
            else
                spent[#spent + 1] = t
            end
        end
        -- at most an hour of waiting: a flight still up by then is no longer coming back
        -- with the job done
        f.waits = (f.waits or 0) + 1
        if flying and f.waits <= 6 then
            local at = now + AIR_PACKAGE.strike_after_suppression_s
            f.note = "delayed"
            WriteEventLog.add(m.coalition, "DELAYED", id, string.format("waiting for %s, still in the air; looking again at %s",
                flying, clockText(at)))
            timer.scheduleFunction(function() launch(id) end, nil, at)
            return
        end
        local names, back = {}, now
        for by in pairs(send) do
            local s = aiVersion(_byId[by])
            local copy = later(s, now + 1 - s.start_s, s.id .. "_AGAIN")
            if copy and spawnNow(copy, {}) then
                _flights[copy.id] = { mission = copy, spawned = true, destroyed = 0, lost = 0, landed = 0 }
                _flights[by].again = copy.id
                names[#names + 1] = copy.id
                back = math.max(back, copy.end_s)
            end
        end
        table.sort(names)
        if #names == 0 then
            f.note = "cancelled"
            WriteEventLog.add(m.coalition, "CANCELLED", id, string.format("%s still in the fight after a second suppression flight",
                table.concat(open, ", ")))
            return
        end
        local at = back + AIR_PACKAGE.strike_after_suppression_s
        f.note, f.waits = "delayed", 0
        WriteEventLog.add(m.coalition, "RETRY", id, string.format("%s still in the fight: suppression flies again as %s; the mission waits until %s",
            table.concat(open, ", "), table.concat(names, ", "), clockText(at)))
        timer.scheduleFunction(function() launch(id) end, nil, at)
        return
    end
    -- late (it waited, or the clock passed its start): a copy on spots free now, once
    -- there's room under the cap, while the window lasts
    local delay = now - plan.start_s
    if delay > 60 then
        if plan.end_s + delay > AIR_TASKING_TIMING.window_s + 1800 then
            f.note = "cancelled"
            WriteEventLog.add(m.coalition, "CANCELLED", id, "too late: it would not be back before the mission window ends")
            return
        end
        local copy = roomFor(plan) and later(plan, delay)
        if not copy then
            f.note = "delayed"
            timer.scheduleFunction(function() launch(id) end, nil, now + AIR_PACKAGE.wait_for_room_s)
            return
        end
        m = copy
        f.mission_flown = copy
    end
    f.note = nil
    spawnNow(m, f)
end

-- A flight spawned at run time (a scramble), tracked like a planned one: its losses
-- count and its aircraft are removed after landing.
function ScheduleAirTaskingOrders.track(m)
    _flights[m.id] = { mission = m, spawned = true, destroyed = 0, lost = 0, landed = 0 }
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
    elseif f.lost >= m.count then
        state = string.format("%d of %d lost", f.lost, m.count)
    elseif f.lost + f.landed >= m.count then
        state = f.lost > 0 and string.format("landed, %d lost", f.lost) or "landed"
    else
        state = f.lost > 0 and string.format("airborne, %d lost", f.lost) or "airborne"
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
    _catalog = plan.target_catalog and plan.target_catalog.targets or {}
    local now, count, first = timer.getTime(), 0, nil
    local human = 0
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            _flights[m.id] = { mission = m, spawned = false, destroyed = 0, lost = 0, landed = 0 }
            _byId[m.id] = m
            if not m.escorts then
                for _, name in ipairs(m.critical_names or {}) do _targets[name] = m.id end
            end
            -- human flights aren't spawned: the player spawns in on the slot (its target
            -- is still watched, above)
            if m.flown_by == "human" then
                human = human + 1
            else
                local at = math.max(m.start_s, now + 1)
                timer.scheduleFunction(function()
                    local ok, err = pcall(launch, m.id)
                    if not ok then Log.error(string.format("%s: launch failed: %s", m.id, tostring(err))) end
                end, nil, at)
                count = count + 1
                if not first or at < first then first = at end
            end
        end
    end
    world.addEventHandler(handler)
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s, %d human flights left to players ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or "", human))
end
