-- The controller's mission clock: runs the air tasking orders. When a planned flight is
-- due (at its start_s, mission time; a start already past is due a second from now) the
-- controller decides (decide_launches.lua, through direct_flights.lua's `due`) and calls
-- back here to carry it out: launch now, look again later, fly a SEAD flight again, or
-- nothing (cancelled). Every launch goes into the ledger, record\flight_launches.lua (this
-- file and the other controller files its one writer), and to Execute for the spawn.
-- When every jet of a flight is down (record\flights.lua) the SEAD rotation's next flight
-- goes; a jet that landed is removed a few minutes later, freeing its parking spot and the
-- alive-aircraft budget (the Syria S_EVENT_LAND pattern).
-- Reads the plan; writes nothing back to it.

ControllerScheduleFlights = {}

local REMOVE_AFTER_LANDING_S = 180

local _plan
local _held = {}   -- base → terminal index → true: spots of copies prepared, not yet spawned

-- Parking for a flight launched later than planned: free spots of its types now, its
-- own planned spots first, never a player slot, a parked-aircraft static or an alert
-- jet's spot. { { terminal_index, x, z } } or nil.
local function spotsNow(m)
    local list = RecordAirbases.freeSpots(m.launch_base)
    if not list then return nil end
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
    -- a copy prepared to spawn there, not yet spawned (it will stand on them)
    for idx in pairs(_held[m.launch_base] or {}) do blocked[idx] = true end
    local free = {}
    for _, s in ipairs(list) do
        if terminals[s.terminal_type] and not blocked[s.terminal_index] then
            free[#free + 1] = { terminal_index = s.terminal_index, x = s.x, z = s.z,
                                order = planned[s.terminal_index] or 100 + (s.distance_to_runway_m or 0) }
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
    local c = {}
    for k, v in pairs(m) do c[k] = v end
    c.id = id or m.id
    c.start_s, c.takeoff_s, c.tot_s, c.end_s = m.start_s + delay, m.takeoff_s + delay, m.tot_s + delay, m.end_s + delay
    if m.takeoff == "air" then return c end   -- an air start needs no spot (the AWACS)
    local spots = spotsNow(m)
    if not spots then return nil end
    c.parking = spots
    c.route = {}
    for i, r in ipairs(m.route) do c.route[i] = r end
    local first = {}
    for k, v in pairs(m.route[1]) do first[k] = v end
    first.x, first.z = spots[1].x, spots[1].z
    c.route[1] = first
    return c
end

-- The spots of copy `c` held until it spawns (or not: released either way).
local function hold(c, held)
    if not c or c.takeoff == "air" then return end
    _held[c.launch_base] = _held[c.launch_base] or {}
    for _, s in ipairs(c.parking or {}) do _held[c.launch_base][s.terminal_index] = held or nil end
end

-- Spawns mission `m` (Execute); on success the ledger says so, then "launched" goes out
-- (the event log's SPAWNED line, the ammo check, a scramble's radar).
local function spawn(id, m, scramble)
    local grp = ExecuteSpawnAircraftGroups.spawn(m)
    hold(m, false)
    return grp
end

local function launched(id, m, scramble)
    RecordFlightLaunches.publish({ event = "launched", id = id, mission = m, scramble = scramble or nil })
end

local function due(id)
    local ok, err = pcall(ControllerDirectFlights.due, id)
    if not ok then Log.error(string.format("%s: launch decision failed: %s", id, tostring(err))) end
end

-- ── calls for the controller ────────────────────────────────────

-- Ask about flight `id` again at mission time `t`.
function ControllerScheduleFlights.lookAgainAt(id, t)
    timer.scheduleFunction(function() due(id) end, nil, t)
end

-- What the brief and the end summary say of a flight not flying (yet): "delayed",
-- "cancelled", "not needed".
function ControllerScheduleFlights.note(id, note)
    if RecordFlightLaunches.launch(id) then RecordFlightLaunches.write(id, { note = note }) end
end

-- What planned flight `id` flies when launched `delay` s off its planned start: late, a
-- copy shifted by `delay` on spots free now, held until it spawns (nil when no spots are
-- free); early (a rotation flight pulled forward), the plan itself, on its planned spots.
-- The decision comes next, then launch.
function ControllerScheduleFlights.prepareLate(id, delay)
    local m = RecordFlightLaunches.planned(id)
    if delay <= 0 then return m end
    m = later(m, delay)
    hold(m, true)
    return m
end

-- Spawn planned flight `id` now, as `m` (the plan, or a copy from prepareLate). Returns
-- the mission flown, or nil (the spawn failed).
function ControllerScheduleFlights.launch(id, m)
    if m ~= RecordFlightLaunches.planned(id) then RecordFlightLaunches.write(id, { mission_flown = m }) end
    RecordFlightLaunches.clear(id, "note")
    local grp = spawn(id, m)
    RecordFlightLaunches.write(id, { spawned = grp ~= nil, spawned_at = timer.getTime() })
    if grp then launched(id, m) end
    return grp and m or nil
end

-- A copy of SEAD flight `by` to fly once more now (a player's SEAD tasking by two AI
-- jets), as `<by>_AGAIN` on spots free now (held until it spawns); with `comeBack`, its
-- third try `<by>_LATER` (a rotation site still in the fight after both,
-- AIR_PACKAGE.come_back_after_s). nil when no spots are free. The decision comes next,
-- then launchAgain.
function ControllerScheduleFlights.prepareAgain(by, comeBack)
    local s = aiVersion(RecordFlightLaunches.planned(by))
    local copy = later(s, timer.getTime() + 1 - s.start_s, s.id .. (comeBack and "_LATER" or "_AGAIN"))
    if not copy then return nil end
    -- a new sortie: the same callsign name, a new number ("Weasel 3" flies again as "Weasel 5")
    FlightCallsigns.assign(RecordCallsigns.numbers(copy.coalition), copy, s.callsign)
    hold(copy, true)
    return copy
end

-- Spawn the copy of `by` from prepareAgain. Returns the copy, or nil (the spawn failed).
function ControllerScheduleFlights.launchAgain(by, copy, comeBack)
    if not spawn(copy.id, copy) then return nil end
    RecordFlightLaunches.add(copy.id, { mission = copy, spawned = true, spawned_at = timer.getTime() })
    RecordFlightLaunches.write(by, comeBack and { later = copy.id } or { again = copy.id })
    launched(copy.id, copy)
    return copy
end

-- A flight spawned at run time (a scramble), tracked like a planned one: its losses
-- count and its aircraft are removed after landing.
function ControllerScheduleFlights.track(m)
    RecordFlightLaunches.add(m.id, { mission = m, spawned = true, spawned_at = timer.getTime() })
    launched(m.id, m, true)
end

-- Jets of flight `id` the controller removed on the ramp (they carried no weapons): they
-- never fly, and the flight's state counts them out.
function ControllerScheduleFlights.removed(id, n)
    local l = RecordFlightLaunches.launch(id)
    if l then
        RecordFlightLaunches.write(id, { removed = (l.removed or 0) + n })
        RecordFlightLaunches.publish({ event = "removed", id = id })
    end
end

-- A flight removed on the ramp before it took off (a scramble the leash stood down).
function ControllerScheduleFlights.stoodDown(id)
    if RecordFlightLaunches.launch(id) then RecordFlightLaunches.write(id, { stood_down = true }) end
end

function ControllerScheduleFlights.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    _plan = plan
    -- a jet that landed is removed a few minutes later
    RecordFlights.on("landed", function(e)
        timer.scheduleFunction(function() ExecuteAirFlightOrders.remove({ flight = e.id, units = { e.unit } }) end, nil,
            timer.getTime() + REMOVE_AFTER_LANDING_S)
    end)
    -- every jet of a flight down: the SEAD rotation's next flight goes
    RecordFlights.on("down", function(e) ControllerDirectFlights.flightDown(e.id) end)
    local now, count, first = timer.getTime(), 0, nil
    local human = 0
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            RecordFlightLaunches.addPlanned(m)
            RecordFlightLaunches.add(m.id, { mission = m, spawned = false })
            -- human flights aren't spawned: the player spawns in on the slot (its target
            -- is still watched, watch\flights.lua)
            if m.flown_by == "human" then
                human = human + 1
            else
                local at = math.max(m.start_s, now + 1)
                ControllerScheduleFlights.lookAgainAt(m.id, at)
                count = count + 1
                if not first or at < first then first = at end
            end
        end
    end
    Log.info(string.format("--- Air tasking orders: %d flights scheduled%s, %d human flights left to players ---", count,
        first and string.format(", first at T+%d s", math.floor(first)) or "", human))
end
