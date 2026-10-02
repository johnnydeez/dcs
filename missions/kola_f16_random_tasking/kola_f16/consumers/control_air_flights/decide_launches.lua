-- Consumer part of the controller (control_air_flights.lua): whether a planned flight that
-- is due launches now, waits, has its suppression flown again, or is cancelled; and the
-- airborne cap, the one count of AI aircraft in the air for planned flights and scrambles
-- alike (roadmap.md item 11: every run-time decision about flights under the controller).
-- The scheduler (consumers/schedule_air_tasking_orders.lua) keeps the clock and the record
-- and does what this decides: it calls ControlAirFlights.due(id) when a flight is due, and
-- this answers with its execution calls (launchNow, flyAgain, lookAgainAt, note).
--
-- AI packages fly in sequence (plan: requires_cleared, cleared_by; John, 2026-10-01): a
-- mission that needs its route's threats out of the fight launches only once they are
-- (a SAM site's radars destroyed to its success fraction, a base-defense group with no
-- live unit). If they aren't when it's due: while one of its suppression flights is still
-- in the air it waits for it (at most an hour); otherwise those suppression flights fly
-- once more (a copy, id <id>_AGAIN; a player's SEAD tasking is flown again by two AI jets)
-- and the mission waits for them to land; if that fails too, it is cancelled. A
-- suppression flight whose threats are already out of the fight isn't sent. A flight
-- launched late (it waited, or the clock passed its start) flies a copy on spots free now,
-- once there is room under the cap, while the mission window lasts.
--
-- Event log lines (word CONTROL):
--   "wait: waiting for MSN2030_SEAD, still in the air; looking again at 10:42"
--   "retry: SAM_KOSH_SA10_1 still in the fight: suppression flies again as MSN2030_SEAD_AGAIN; the mission waits until 11:25"
--   "cancel: SAM_KOSH_SA10_1 still in the fight after a second suppression flight"
--   "cancel: not needed: SAM_KOSH_SA10_1 already out of the fight"
--   "cancel: too late: it would not be back before the mission window ends"
--   "launch late: 23 min after its planned start, on spots free now"
-- Reads the plan; writes nothing back to it.

DecideLaunches = {}

local SIDE = { red = 1, blue = 2 }
local MAX_WAITS = 6   -- looks while a suppression flight is still up: an hour at strike_after_suppression_s

local _plan
local _catalog = {}   -- catalog target id → target
local _waits = {}     -- mission id → looks so far while waiting for a suppression flight

local function liveUnit(name)
    local o = Unit.getByName(name) or StaticObject.getByName(name)
    local ok, live = pcall(function() return o and o:isExist() and o:getLife() >= 1 end)
    return ok and live == true
end

local function liveGroup(name)
    return AssessFlightSituations.liveGroup(name) ~= nil
end

local function clockText(t) return Weather.hhmm(_plan.world.time.start_local + t) end

-- ── the airborne cap ────────────────────────────────────────────

-- AI aircraft of the coalition in the air: players don't count (John, 2026-10-01: the
-- cap is for AI aircraft).
function DecideLaunches.airborneAircraft(c)
    local n = 0
    for _, g in ipairs(coalition.getGroups(SIDE[c], Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            local ok, air = pcall(function() return u:inAir() and not u:getPlayerName() end)
            if ok and air then n = n + 1 end
        end
    end
    return n
end

-- The coalition's cap: max_airborne_aircraft; planned flights may fill it only up to
-- scramble_reserve_aircraft below it, the rest is the scrambles'.
function DecideLaunches.cap(c, forScramble)
    local cap = AIR_TASKING_PER_COALITION[c].max_airborne_aircraft
    if not forScramble and AIR_DEFENSE.planned and AIR_DEFENSE.alert_posture_planned then
        cap = cap - AIR_DEFENSE.scramble_reserve_aircraft
    end
    return cap
end

-- ── threats out of the fight ────────────────────────────────────

-- Whether a threat is out of the fight: a SAM site (a catalog target) whose critical
-- objects (its radars) are destroyed to its success fraction; a group (a base-defense
-- radar missile launcher) with no live unit.
local function threatCleared(id)
    local t = _catalog[id]
    if t and t.critical_names and #t.critical_names > 0 then
        local dead = 0
        for _, name in ipairs(t.critical_names) do
            if ScheduleAirTaskingOrders.isGone(name) or not liveUnit(name) then dead = dead + 1 end
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

-- ── a flight is due ─────────────────────────────────────────────

local function say(m, id, decision, text) ControlAirFlights.say(m.coalition, id, decision, text) end

-- Planned flight `id` is due (at its start, or when this asked to look again).
function DecideLaunches.due(id)
    local S = ScheduleAirTaskingOrders
    local plan = S.planned(id)
    local now = timer.getTime()
    -- a suppression flight whose threats are already out of the fight isn't sent
    if plan.escorts and #(plan.suppresses or {}) > 0 and #openThreats(plan.suppresses) == 0 then
        S.note(id, "not needed")
        say(plan, id, "cancel", string.format("not needed: %s already out of the fight", table.concat(plan.suppresses, ", ")))
        return
    end
    local open = openThreats(plan.requires_cleared)
    if #open > 0 then
        -- per suppression flight still owed: in the air (wait for it), flown once more
        -- already (its second try is spent), or to fly again now. A suppression flight
        -- flies again at most once, whichever missions rely on it (one may clear the way
        -- for several), and they all wait for that one
        local flying, send = nil, {}
        for _, t in ipairs(open) do
            local by = plan.cleared_by and plan.cleared_by[t]
            local sf = by and S.record(by)
            if sf then
                if sf.again then
                    if liveGroup(sf.again) then flying = sf.again end
                elseif sf.spawned and liveGroup(by) then
                    flying = by
                else
                    -- a player's SEAD tasking (flown or not) is flown again by the AI
                    send[by] = true
                end
            end
        end
        -- at most an hour of waiting: a flight still up by then is no longer coming back
        -- with the job done
        _waits[id] = (_waits[id] or 0) + 1
        if flying and _waits[id] <= MAX_WAITS then
            local at = now + AIR_PACKAGE.strike_after_suppression_s
            S.note(id, "delayed")
            say(plan, id, "wait", string.format("waiting for %s, still in the air; looking again at %s", flying, clockText(at)))
            S.lookAgainAt(id, at)
            return
        end
        local names, back = {}, now
        local bys = {}
        for by in pairs(send) do bys[#bys + 1] = by end
        table.sort(bys)
        for _, by in ipairs(bys) do
            local copy = S.flyAgain(by)
            if copy then
                ControlAirFlights.watch(copy)
                names[#names + 1] = copy.id
                back = math.max(back, copy.end_s)
            end
        end
        if #names == 0 then
            S.note(id, "cancelled")
            say(plan, id, "cancel", string.format("%s still in the fight after a second suppression flight", table.concat(open, ", ")))
            return
        end
        local at = back + AIR_PACKAGE.strike_after_suppression_s
        S.note(id, "delayed")
        _waits[id] = 0
        say(plan, id, "retry", string.format("%s still in the fight: suppression flies again as %s; the mission waits until %s",
            table.concat(open, ", "), table.concat(names, ", "), clockText(at)))
        S.lookAgainAt(id, at)
        return
    end
    -- late (it waited, or the clock passed its start): a copy on spots free now, once
    -- there's room under the cap, while the window lasts
    local delay = now - plan.start_s
    if delay > 60 then
        if plan.end_s + delay > AIR_TASKING_TIMING.window_s + 1800 then
            S.note(id, "cancelled")
            say(plan, id, "cancel", "too late: it would not be back before the mission window ends")
            return
        end
        local room = DecideLaunches.airborneAircraft(plan.coalition) + plan.count <= DecideLaunches.cap(plan.coalition)
        local m = room and S.launchNow(id, delay)
        if not m then
            S.note(id, "delayed")
            S.lookAgainAt(id, now + AIR_PACKAGE.wait_for_room_s)
            return
        end
        say(plan, id, "launch late", string.format("%d min after its planned start, on spots free now", math.floor(delay / 60)))
        ControlAirFlights.watch(m)
        return
    end
    local m = S.launchNow(id, 0)
    if m then ControlAirFlights.watch(m) end
end

function DecideLaunches.start(plan)
    _plan = plan
    _catalog = plan.target_catalog and plan.target_catalog.targets or {}
end
