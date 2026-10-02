-- Consumer part of the controller (control_air_flights.lua): whether a planned flight that
-- is due launches now, waits, has a SEAD flight flown again first, or is cancelled; and
-- the airborne cap, the one count of AI aircraft in the air for planned flights and
-- scrambles alike (roadmap.md item 11: every run-time decision about flights under the
-- controller). The scheduler (consumers/schedule_air_tasking_orders.lua) keeps the clock
-- and the record and does what this decides: it calls ControlAirFlights.due(id) when a
-- flight is due, and this answers with its execution calls (launchNow, flyAgain,
-- lookAgainAt, note).
--
-- SEAD first (roadmap item 12, John, 2026-10-02). Any flight may list the threats it
-- needs out of the fight (requires_cleared); the plan's site table
-- (suppression_by_site) says which SEAD flight takes each. A flight launches only once
-- those are out of the fight (a SAM site's radars destroyed to its success fraction, a
-- base-defense group with no live unit). If they aren't when it's due: while that
-- site's SEAD flight is still on its attack (or hasn't launched yet), it waits; once the
-- SEAD flight is done (gone cold, sent home, landed or lost: no waiting out its planned
-- landing) it flies once more (a copy, id <id>_AGAIN, one per SEAD flight however many
-- flights wait on it; a player's SEAD tasking is flown again by two AI jets) and the
-- flight waits for it; if that fails too, or the site's SEAD flight was cancelled, the
-- flight is cancelled. A SEAD flight whose site is already out of the fight isn't sent,
-- nor a DEAD flight whose site already meets its own success (radars, command post and
-- launchers: catalog_targets.lua; John, 2026-10-03).
--
-- The SEAD rotation (suppression_rotation): one rotation flight in the air at a time per
-- coalition. A rotation flight due while another is up waits for it; when one is down
-- (landed, lost, removed) or cancelled, the next is pulled forward to now ("one comes
-- back and lands, despawns, the other spins up"). An earlier rotation flight that flew,
-- is down and whose site is still in the fight gets its second try first, as the
-- rotation's next flight, not an extra jet.
--
-- A flight launched late (it waited, or the clock passed its start) or early (pulled
-- forward) flies a copy on spots free now, once there is room under the cap, while the
-- mission window lasts.
--
-- Event log lines (word CONTROL):
--   "wait: waiting for MSN2030_SEAD, still on its attack; looking again at 10:42"
--   "retry: SAM_KOSH_SA10_1 still in the fight: MSN2030_SEAD flies again as MSN2030_SEAD_AGAIN; waiting until 11:25"
--   "retry: SAM_KOSH_SA10_1 still in the fight after MSN2030_SEAD: it flies again as MSN2030_SEAD_AGAIN, the rotation's next flight"
--   "cancel: SAM_KOSH_SA10_1 still in the fight after a second SEAD flight"
--   "cancel: SAM_KOSH_SA10_1's SEAD flight MSN2030_SEAD was cancelled"
--   "cancel: not needed: SAM_KOSH_SA10_1 already out of the fight"
--   "cancel: not needed: SAM_BANA_SA11_1 already destroyed (4 of 5 critical)"
--   "cancel: too late: it would not be back before the mission window ends"
--   "launch late: 23 min after its planned start, on spots free now"
--   "launch early: 14 min before its planned start (the rotation's flight before it is down), on spots free now"
-- Reads the plan; writes nothing back to it.

DecideLaunches = {}

local SIDE = { red = 1, blue = 2 }
local MAX_WAITS = 6   -- looks while a SEAD flight is still on its attack: an hour at strike_after_suppression_s
local SUPPRESSION = "suppression_of_air_defenses"
local DESTRUCTION = "destruction_of_air_defenses"

local _plan
local _catalog = {}      -- catalog target id → target
local _waits = {}        -- flight id → looks so far while waiting for a SEAD flight
local _bySite = {}       -- coalition → threat id → the SEAD flight that takes it
local _rotation = {}     -- coalition → the rotation's SEAD flight ids, in order
local _rotationUp = {}   -- coalition → the rotation flight (or its second try) in the air

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

-- Whether `names` are destroyed to `success`'s fraction (rounded up, at least one); and
-- how many are, of how many.
local function destroyedTo(names, success)
    local dead = 0
    for _, name in ipairs(names) do
        if ScheduleAirTaskingOrders.isGone(name) or not liveUnit(name) then dead = dead + 1 end
    end
    local frac = success and success.critical_fraction or 1
    return dead >= math.max(1, math.ceil(frac * #names - 1e-9)), dead, #names
end

-- Whether a threat is out of the fight: a SAM site (a catalog target) whose critical
-- objects (its radars) are destroyed to its success fraction; a group (a base-defense
-- radar missile launcher) with no live unit.
local function threatCleared(id)
    local t = _catalog[id]
    if t and t.critical_names and #t.critical_names > 0 then
        return (destroyedTo(t.critical_names, t.success))
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

-- ── flights' states ─────────────────────────────────────────────

-- A SEAD flight still on its attack: in the air and not yet sent home (gone cold, sent
-- home, leaving a bandit). Once it is done there's no point waiting for it to land
-- (John, 2026-10-02).
local function stillOnAttack(id)
    return liveGroup(id) and ControlAirFlights.onTask(id)
end

-- A launched flight with every jet landed, lost or removed on the ramp (or its group gone).
local function isDown(id)
    local rec = ScheduleAirTaskingOrders.record(id)
    if not (rec and rec.spawned) then return false end
    local m = rec.mission_flown or rec.mission
    return rec.lost + rec.landed + (rec.removed or 0) >= m.count or not liveGroup(id)
end

-- A planned flight no longer waiting to fly: launched, or cancelled / not needed.
local function settled(rec)
    return rec.spawned or rec.note == "cancelled" or rec.note == "not needed"
end

local function say(m, id, decision, text) ControlAirFlights.say(m.coalition, id, decision, text) end

-- ── the rotation ────────────────────────────────────────────────

-- The rotation flight the copy `id` (<id>_AGAIN) or the flight itself stands for.
local function rotationId(id)
    return (id:gsub("_AGAIN$", ""))
end

-- The rotation's next flight after `id` still waiting to fly, asked about now.
local function pullForward(c, id)
    local S = ScheduleAirTaskingOrders
    local list, after = _rotation[c] or {}, false
    for _, rid in ipairs(list) do
        if after then
            local rec = S.record(rid)
            if rec and not settled(rec) then
                S.lookAgainAt(rid, timer.getTime() + 1)
                return
            end
        elseif rid == id then
            after = true
        end
    end
end

local function cancel(plan, id, text)
    ScheduleAirTaskingOrders.note(id, "cancelled")
    say(plan, id, "cancel", text)
    if plan.rotation then pullForward(plan.coalition, id) end
end

-- A copy of SEAD flight `by` flying again now (its second try); nil when no spots are free.
local function flyAgain(by)
    local copy = ScheduleAirTaskingOrders.flyAgain(by)
    if not copy then return nil end
    ControlAirFlights.watch(copy)
    if copy.rotation then _rotationUp[copy.coalition] = copy.id end
    return copy
end

-- The rotation's owed second try, before rotation flight `id` (plan `plan`) flies: the
-- first earlier rotation flight that flew, is down, has had no second try, and whose
-- site is still in the fight. Flies it now; returns true when it did.
local function owedRetry(plan, id)
    local S = ScheduleAirTaskingOrders
    for _, rid in ipairs(_rotation[plan.coalition] or {}) do
        if rid == id then return false end
        local rec = S.record(rid)
        local earlier = S.planned(rid)
        if rec and rec.spawned and not rec.again and isDown(rid) and not threatCleared(earlier.target) then
            local copy = flyAgain(rid)
            if copy then
                say(earlier, rid, "retry", string.format("%s still in the fight after %s: it flies again as %s, the rotation's next flight; %s waits",
                    earlier.target, rid, copy.id, id))
                S.note(id, "delayed")
                S.lookAgainAt(id, copy.end_s - AIR_TASKING_TIMING.landing_s)
                return true
            end
        end
    end
    return false
end

-- ── a flight is due ─────────────────────────────────────────────

-- Launch planned flight `id` now: on time, or a copy shifted to now on spots free now
-- once there's room under the cap (late: it waited, or the clock passed its start;
-- early: a rotation flight pulled forward), while the window lasts.
local function launch(plan, id, now)
    local S = ScheduleAirTaskingOrders
    local delay = now - plan.start_s
    if delay > 60 and plan.end_s + delay > AIR_TASKING_TIMING.window_s + 1800 then
        cancel(plan, id, "too late: it would not be back before the mission window ends")
        return
    end
    local m
    if math.abs(delay) <= 60 then
        m = S.launchNow(id, 0)
    else
        local room = DecideLaunches.airborneAircraft(plan.coalition) + plan.count <= DecideLaunches.cap(plan.coalition)
        m = room and S.launchNow(id, delay)
        if not m then
            S.note(id, "delayed")
            S.lookAgainAt(id, now + AIR_PACKAGE.wait_for_room_s)
            return
        end
        if delay > 0 then
            say(plan, id, "launch late", string.format("%d min after its planned start, on spots free now", math.floor(delay / 60)))
        else
            say(plan, id, "launch early", string.format("%d min before its planned start (the rotation's flight before it is down), on spots free now",
                math.floor(-delay / 60)))
        end
    end
    if m then
        ControlAirFlights.watch(m)
        if plan.rotation then _rotationUp[plan.coalition] = id end
    end
end

-- Planned flight `id` is due (at its start, when this asked to look again, or pulled
-- forward in the rotation).
function DecideLaunches.due(id)
    local S = ScheduleAirTaskingOrders
    local plan = S.planned(id)
    local rec = S.record(id)
    local now = timer.getTime()
    local c = plan.coalition
    if not rec or settled(rec) then return end   -- asked twice (pulled forward, and its own time)
    -- a SEAD flight whose site is already out of the fight isn't sent
    if plan.mission_type == SUPPRESSION and plan.target and threatCleared(plan.target) then
        S.note(id, "not needed")
        say(plan, id, "cancel", string.format("not needed: %s already out of the fight", plan.target))
        if plan.rotation then pullForward(c, id) end
        return
    end
    -- nor a DEAD flight whose site already meets its own success (its mission's critical
    -- objects: radars, command post, launchers)
    if plan.mission_type == DESTRUCTION and plan.critical_names and #plan.critical_names > 0 then
        local done, dead, of = destroyedTo(plan.critical_names, plan.success)
        if done then
            S.note(id, "not needed")
            say(plan, id, "cancel", string.format("not needed: %s already destroyed (%d of %d critical)", plan.target, dead, of))
            return
        end
    end
    if plan.rotation then
        -- one rotation flight in the air at a time
        local up = _rotationUp[c]
        if up and up ~= id and not isDown(up) then
            S.note(id, "delayed")
            S.lookAgainAt(id, now + AIR_PACKAGE.wait_for_room_s)
            return
        end
        if owedRetry(plan, id) then return end
    end
    local open = openThreats(plan.requires_cleared)
    if #open > 0 then
        -- per threat still in the fight, its SEAD flight: on its attack or not launched
        -- yet (wait for it), its second try spent, cancelled (so is this), or done (fly it
        -- once more; a player's SEAD tasking, flown or not, is flown again by the AI)
        local waitFor, send, cancelled = nil, {}, nil
        for _, t in ipairs(open) do
            local by = (_bySite[c] or {})[t]
            local sf = by and S.record(by)
            if not sf then
                cancelled = cancelled or string.format("%s has no SEAD flight", t)
            elseif sf.again then
                if stillOnAttack(sf.again) then waitFor = sf.again end
            elseif sf.note == "cancelled" then
                cancelled = cancelled or string.format("%s's SEAD flight %s was cancelled", t, by)
            elseif sf.mission.flown_by == "human" then
                send[by] = true
            elseif not sf.spawned then
                waitFor = waitFor or by
            elseif stillOnAttack(by) then
                waitFor = by
            elseif sf.mission.rotation and _rotationUp[c] and not isDown(_rotationUp[c]) then
                -- the rotation flies one at a time: its second try waits for the one up
                waitFor = _rotationUp[c]
            else
                send[by] = true
            end
        end
        if cancelled then
            cancel(plan, id, cancelled)
            return
        end
        -- at most an hour of waiting on a flight that's still on its attack
        _waits[id] = (_waits[id] or 0) + 1
        if waitFor and (_waits[id] <= MAX_WAITS or not S.record(waitFor).spawned) and now < AIR_TASKING_TIMING.window_s then
            local at = now + AIR_PACKAGE.strike_after_suppression_s
            S.note(id, "delayed")
            say(plan, id, "wait", string.format("waiting for %s, %s; looking again at %s", waitFor,
                S.record(waitFor).spawned and "still on its attack" or "not launched yet", clockText(at)))
            S.lookAgainAt(id, at)
            return
        end
        local names, back = {}, now
        local bys = {}
        for by in pairs(send) do bys[#bys + 1] = by end
        table.sort(bys)
        for _, by in ipairs(bys) do
            local copy = flyAgain(by)
            if copy then
                names[#names + 1] = string.format("%s flies again as %s", by, copy.id)
                -- looked at again after its planned salvo; it waits on while the copy is
                -- still on its attack
                back = math.max(back, copy.tot_s)
            end
        end
        if #names == 0 then
            cancel(plan, id, string.format("%s still in the fight after a second SEAD flight", table.concat(open, ", ")))
            return
        end
        local at = back + AIR_PACKAGE.strike_after_suppression_s
        S.note(id, "delayed")
        _waits[id] = 0
        say(plan, id, "retry", string.format("%s still in the fight: %s; waiting until %s",
            table.concat(open, ", "), table.concat(names, ", "), clockText(at)))
        S.lookAgainAt(id, at)
        return
    end
    launch(plan, id, now)
end

-- Every jet of flight `id` is down (landed, lost or removed on the ramp): a rotation
-- flight's place goes to the next one, now.
function DecideLaunches.flightDown(id)
    local S = ScheduleAirTaskingOrders
    local rec = S.record(id)
    local m = rec and (rec.mission_flown or rec.mission)
    if not (m and m.rotation) then return end
    if _rotationUp[m.coalition] == id then _rotationUp[m.coalition] = nil end
    pullForward(m.coalition, rotationId(id))
end

function DecideLaunches.start(plan)
    _plan = plan
    _catalog = plan.target_catalog and plan.target_catalog.targets or {}
    for _, c in ipairs({ "red", "blue" }) do
        local ato = plan.air_tasking_orders and plan.air_tasking_orders[c]
        _bySite[c] = ato and ato.suppression_by_site or {}
        _rotation[c] = ato and ato.suppression_rotation or {}
    end
end
