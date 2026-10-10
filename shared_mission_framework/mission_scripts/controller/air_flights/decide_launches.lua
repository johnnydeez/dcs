-- Controller, part of directing the air flights (direct_flights.lua): whether a planned flight that
-- is due launches now, waits, has a SEAD flight flown again first, or is cancelled; and
-- the airborne cap, the one count of AI aircraft in the air for planned flights and
-- scrambles alike (roadmap.md item 11: every run-time decision about flights under the
-- controller). The scheduler (watch/flights.lua) keeps the clock
-- and the record and does what this decides: it calls ControllerDirectFlights.due(id) when a
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
-- Coming back later (2026-10-04, after the 2026-10-03 14:15 run, where the Vuojarvi
-- SA-10 survived two tries and every Blue attack mission waited on it): a rotation site
-- still in the fight once its SEAD flight's second try is down comes back into the
-- rotation once more, AIR_PACKAGE.come_back_after_s later (<id>_LATER: the same plan
-- flown again; the plan is fixed, so the same base and route), ahead of the rotation's
-- next flight. Flights waiting on that site wait for it instead of being cancelled, and
-- the rotation goes on past a rotation flight that waits for it.
-- The same for a site the rotation needs that another flight of the site table takes (a
-- SEAD flight an attack or a player's tasking needed first; 2026-10-05, after the
-- 2026-10-04 22:39 run: the Rovaniemi SA-10 was MSN2025_SEAD's, a player DEAD's SEAD;
-- it survived both tries and every rotation flight behind it was cancelled): its flight
-- comes back into the rotation as <id>_LATER, and takes the rotation's place while it flies.
--
-- No second try straight away (2026-10-05, after the 10:31 run, where MSN2029_SEAD_AGAIN
-- spawned 1 s after MSN2029's last jet died, while its HARMs were still in the air; they
-- took the site's radar 51 s later and the copy flew a whole sortie for nothing): a SEAD
-- flight's site is looked at again AIR_PACKAGE.retry_after_s after the flight came off
-- its task (sent home, landed or lost), and only then flown again; the same wait before
-- deciding a site's come-back.
--
-- A flight launched late (it waited, or the clock passed its start) or early (pulled
-- forward) flies a copy on spots free now, once there is room under the cap, while the
-- mission window lasts.
--
-- Event log lines (word CONTROL):
--   "wait: waiting for MSN2030_SEAD, still on its attack; looking again at 10:42"
--   "wait: SAM_KOSH_SA11_2 still in the fight after MSN2029_SEAD; looking at it again at 04:50 before a second try"
--   "retry: SAM_KOSH_SA10_1 still in the fight: MSN2030_SEAD flies again as MSN2030_SEAD_AGAIN; waiting until 11:25"
--   "retry: SAM_KOSH_SA10_1 still in the fight after MSN2030_SEAD: it flies again as MSN2030_SEAD_AGAIN, the rotation's next flight"
--   "come back: SAM_VUOJ_SA10_1 still in the fight after MSN2026_SEAD and MSN2026_SEAD_AGAIN: it comes back into the rotation at 05:36"
--   "retry: SAM_VUOJ_SA10_1 still in the fight: MSN2026_SEAD comes back as MSN2026_SEAD_LATER, the rotation's next flight"
--   "wait: waiting for SAM_VUOJ_SA10_1's SEAD flight to come back (MSN2026_SEAD_LATER, at 05:36); looking again at 05:58"
--   "cancel: SAM_KOSH_SA10_1 still in the fight after a second SEAD flight" (or "after three SEAD flights")
--   "cancel: SAM_KOSH_SA10_1's SEAD flight MSN2030_SEAD was cancelled"
--   "cancel: not needed: SAM_KOSH_SA10_1 already out of the fight"
--   "cancel: not needed: SAM_BANA_SA11_1 already destroyed (4 of 5 critical)"
--   "cancel: too late: it would not be back before the mission window ends"
--   "launch late: 23 min after its planned start, on spots free now"
--   "launch early: 14 min before its planned start (the rotation's flight before it is down), on spots free now"
-- Reads the plan; writes nothing back to it.

ControllerDecideLaunches = {}

local SIDE = { red = 1, blue = 2 }
local MAX_WAITS = 6   -- looks while a SEAD flight is still on its attack: an hour at strike_after_suppression_s
local SUPPRESSION = "suppression_of_air_defenses"
local DESTRUCTION = "destruction_of_air_defenses"

local _plan
local _waits = {}        -- flight id → looks so far while waiting for a SEAD flight
local _bySite = {}       -- coalition → threat id → the SEAD flight that takes it
local _rotation = {}     -- coalition → the rotation's SEAD flight ids, in order
local _rotationUp = {}   -- coalition → the rotation flight (or its second try) in the air
local _comeBack = {}     -- flight id → { at, done } its third try: due at mission time `at`
local _comesBack = {}    -- coalition → the flights whose sites come back: the rotation's, then those of sites it needs
local _waitingForComeBack = {}   -- flight id → the come-back's time (or true, not set yet) while it waits for one (the rotation goes on past it)
local _seenDone = {}     -- SEAD flight id → mission time this first saw it done, when the controller didn't
local _retryWaitSaid = {}   -- SEAD flight id → true once its "looking at it again" line is written
local _comeBackPending = {} -- flight id → true while its come-back is still to be decided (retry_after_s after its second try is down)

local function liveGroup(name)
    return RecordGroups.alive(name)
end

local function clockText(t) return Weather.hhmm(_plan.world.time.start_local + t) end

-- ── the airborne cap ────────────────────────────────────────────

-- The coalition's cap: max_airborne_aircraft; planned flights may fill it only up to
-- scramble_reserve_aircraft below it, the rest is the scrambles'.
function ControllerDecideLaunches.cap(c, forScramble)
    local cap = AIR_TASKING_PER_COALITION[c].max_airborne_aircraft
    if not forScramble and AIR_DEFENSE.planned and AIR_DEFENSE.alert_posture_planned then
        cap = cap - AIR_DEFENSE.scramble_reserve_aircraft
    end
    return cap
end

-- ── threats out of the fight ────────────────────────────────────

-- Whether a threat is out of the fight: a SAM site (a catalog target) whose critical
-- objects (its radars) are destroyed to its success fraction; a group (a base-defense
-- radar missile launcher) with no live unit (record\threats.lua). The rest of the
-- controller asks the same: a site out of the fight no longer counts as a kill zone
-- (2026-10-04, after the 2026-10-03 14:15 run: with both Patriot tracking radars dead,
-- MSN7035_DEAD still broke off 4 fights for the Patriot's kill zone, and Red refused
-- scrambles "under enemy SAM cover" of it, while the gate had already launched MSN7035
-- because the Patriot was out of the fight).
local function threatCleared(id)
    return RecordThreats.outOfTheFight(id)
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
    return liveGroup(id) and RecordWatchedFlights.onTask(id)
end

-- A launched flight with every jet landed, lost or removed on the ramp (or its group gone).
local function isDown(id)
    local rec, facts = RecordFlightLaunches.launch(id), RecordFlights.facts(id)
    if not (rec and rec.spawned) then return false end
    local m = rec.mission_flown or rec.mission
    return facts.lost + facts.landed + (rec.removed or 0) >= m.count or not liveGroup(id)
end

-- The mission time SEAD flight `id` (done: off its attack or down) may be flown again:
-- retry_after_s after it came off its task, so missiles still in the air have landed
-- and the site's state is known.
local function retryAt(id)
    local since = RecordWatchedFlights.offTaskSince(id)
    if not since then
        _seenDone[id] = _seenDone[id] or timer.getTime()
        since = _seenDone[id]
    end
    return since + AIR_PACKAGE.retry_after_s
end

-- "wait: <site> still in the fight after <by>; looking at it again at …", once per SEAD flight.
local function sayRetryWait(plan, by, site, at)
    if _retryWaitSaid[by] then return end
    _retryWaitSaid[by] = true
    ControllerDirectFlights.say(plan.coalition, plan.id, "wait", string.format("%s still in the fight after %s; looking at it again at %s before a second try",
        site, by, clockText(at)))
end

-- A planned flight no longer waiting to fly: launched, or cancelled / not needed.
local function settled(rec)
    return rec.spawned or rec.note == "cancelled" or rec.note == "not needed"
end

local function say(m, id, decision, text) ControllerDirectFlights.say(m.coalition, id, decision, text) end

-- ── the rotation ────────────────────────────────────────────────

-- The rotation flight the copy `id` (<id>_AGAIN, <id>_LATER) or the flight itself stands for.
local function rotationId(id)
    return (id:gsub("_AGAIN$", ""):gsub("_LATER$", ""))
end

-- The rotation's next flight after `id` still waiting to fly, asked about now (its first
-- when `id` isn't a rotation flight: a come-back that held the rotation's place). One
-- that waits for a site's come-back is passed over: the rotation goes on meanwhile.
local function pullForward(c, id)
    local S = ControllerScheduleFlights
    local list, after = _rotation[c] or {}, true
    for _, rid in ipairs(list) do
        if rid == id then after = false end
    end
    for _, rid in ipairs(list) do
        if after then
            local rec = RecordFlightLaunches.launch(rid)
            if rec and not settled(rec) and not _waitingForComeBack[rid] then
                S.lookAgainAt(rid, timer.getTime() + 1)
                return
            end
        elseif rid == id then
            after = true
        end
    end
end

local function cancel(plan, id, text)
    _waitingForComeBack[id] = nil
    ControllerScheduleFlights.note(id, "cancelled")
    say(plan, id, "cancel", text)
    if plan.rotation then pullForward(plan.coalition, id) end
end

-- A copy of SEAD flight `by` to fly again now (its second try, or with `comeBack` its
-- third); nil when no spots are free. Rule 3: prepared, the decision written, then
-- flown (flyAgain).
local function prepareAgain(by, comeBack)
    return ControllerScheduleFlights.prepareAgain(by, comeBack)
end

-- Flies the prepared copy (a site's come-back holds the rotation's place while it flies);
-- nil when the spawn failed.
local function flyAgain(by, copy, comeBack)
    copy = ControllerScheduleFlights.launchAgain(by, copy, comeBack)
    if not copy then return nil end
    ControllerDirectFlights.watch(copy)
    if copy.rotation or comeBack then _rotationUp[copy.coalition] = copy.id end
    return copy
end

-- ── coming back later ───────────────────────────────────────────

-- The flights whose sites come back into the rotation (rotation order first, then the
-- other site-table flights on a site some rotation flight needs, by id), worked out once.
local function comesBack(c)
    if _comesBack[c] then return _comesBack[c] end
    local S = ControllerScheduleFlights
    local list, inList, needed = {}, {}, {}
    for _, rid in ipairs(_rotation[c] or {}) do
        list[#list + 1], inList[rid] = rid, true
        local p = RecordFlightLaunches.planned(rid)
        for _, t in ipairs(p and p.requires_cleared or {}) do needed[t] = true end
    end
    local others = {}
    for site, by in pairs(_bySite[c] or {}) do
        if needed[site] and not inList[by] then others[#others + 1] = by end
    end
    table.sort(others)
    for _, by in ipairs(others) do list[#list + 1] = by end
    _comesBack[c] = list
    return list
end

-- Whether flight `by`'s site comes back into the rotation after its second try.
local function siteComesBack(c, by)
    for _, id in ipairs(comesBack(c)) do
        if id == by then return true end
    end
    return false
end

-- Whether flight `rid`'s come-back would still be back before the window ends, flown
-- from mission time `at`.
local function comeBackFits(rid, at)
    local p = RecordFlightLaunches.planned(rid)
    return at + (p.end_s - p.start_s) <= AIR_TASKING_TIMING.window_s + 1800
end

-- Flight `rid`'s second try is down with its site still in the fight: when the site comes
-- back into the rotation (siteComesBack), its come-back is due come_back_after_s from now
-- (said once; "won't come back" when it would not be back before the window ends).
local function planComeBack(rid)
    local S = ControllerScheduleFlights
    local p = RecordFlightLaunches.planned(rid)
    local rec = RecordFlightLaunches.launch(rid)
    if not (p and rec) or _comeBack[rid] or rec.later or threatCleared(p.target) then return end
    if not siteComesBack(p.coalition, rid) then return end
    local at = timer.getTime() + AIR_PACKAGE.come_back_after_s
    if not comeBackFits(rid, at) then
        _comeBack[rid] = { at = at, done = true }
        say(p, rid, "come back", string.format("%s still in the fight after %s and %s; no come-back: it would not be back before the mission window ends",
            p.target, rid, rec.again))
        return
    end
    _comeBack[rid] = { at = at }
    say(p, rid, "come back", string.format("%s still in the fight after %s and %s: it comes back into the rotation at %s",
        p.target, rid, rec.again, clockText(at)))
    timer.scheduleFunction(function()
        local ok, err = pcall(ControllerDecideLaunches.comeBackNow, p.coalition)
        if not ok then Log.warn(string.format("%s: come-back failed: %s", rid, tostring(err))) end
    end, nil, at)
end

-- A come-back of the coalition that is due now flies, unless a rotation flight is up (it
-- goes when that one is down) or no spots are free (looked at again shortly). One at a
-- time; true when one flew.
function ControllerDecideLaunches.comeBackNow(c)
    local S = ControllerScheduleFlights
    local now = timer.getTime()
    for _, rid in ipairs(comesBack(c)) do
        local cb = _comeBack[rid]
        if cb and not cb.done and cb.at <= now then
            local p = RecordFlightLaunches.planned(rid)
            if threatCleared(p.target) then
                cb.done = true
                say(p, rid, "come back", string.format("not needed: %s out of the fight", p.target))
            else
                local up = _rotationUp[c]
                if up and not isDown(up) then return false end
                local copy = prepareAgain(rid, true)
                if not copy then
                    timer.scheduleFunction(function() pcall(ControllerDecideLaunches.comeBackNow, c) end, nil, now + AIR_PACKAGE.wait_for_room_s)
                    return false
                end
                cb.done = true
                say(p, rid, "retry", string.format("%s still in the fight: %s comes back as %s, the rotation's next flight",
                    p.target, rid, copy.id))
                flyAgain(rid, copy, true)
                return true
            end
        end
    end
    return false
end

-- Whether SEAD flight `by` (record `sf`) will still come back for its site: one whose
-- site comes back into the rotation, whose second try isn't down yet, or whose come-back
-- is still to fly in the window. Returns its come-back (or nil while not yet known) and
-- true; false otherwise.
local function comingBack(by, sf)
    if not (sf.again and siteComesBack(sf.mission.coalition, by)) or sf.later then return nil, false end
    local cb = _comeBack[by]
    if cb then return cb, not cb.done end
    if _comeBackPending[by] then return nil, true end
    return nil, not isDown(sf.again) and comeBackFits(by, timer.getTime() + AIR_PACKAGE.come_back_after_s)
end

-- The rotation's owed second try, before rotation flight `id` (plan `plan`) flies: the
-- first earlier rotation flight that flew, is down, has had no second try, and whose
-- site is still in the fight. Flies it now; returns true when it did.
local function owedRetry(plan, id)
    local S = ControllerScheduleFlights
    for _, rid in ipairs(_rotation[plan.coalition] or {}) do
        if rid == id then return false end
        local rec = RecordFlightLaunches.launch(rid)
        local earlier = RecordFlightLaunches.planned(rid)
        if rec and rec.spawned and not rec.again and isDown(rid) and not threatCleared(earlier.target) then
            local at = retryAt(rid)
            if timer.getTime() < at then
                sayRetryWait(plan, rid, earlier.target, at)
                S.note(id, "delayed")
                S.lookAgainAt(id, at + 1)
                return true
            end
            local copy = prepareAgain(rid)
            if copy then
                say(earlier, rid, "retry", string.format("%s still in the fight after %s: it flies again as %s, the rotation's next flight; %s waits",
                    earlier.target, rid, copy.id, id))
                flyAgain(rid, copy)
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
    local S = ControllerScheduleFlights
    local delay = now - plan.start_s
    if delay > 60 and plan.end_s + delay > AIR_TASKING_TIMING.window_s + 1800 then
        cancel(plan, id, "too late: it would not be back before the mission window ends")
        return
    end
    local m
    if math.abs(delay) <= 60 then
        m = S.launch(id, plan)
    else
        local room = RecordAirborneAircraft.count(plan.coalition) + plan.count <= ControllerDecideLaunches.cap(plan.coalition)
        local copy = room and S.prepareLate(id, delay)
        if not copy then
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
        m = S.launch(id, copy)
    end
    if m then
        _waitingForComeBack[id] = nil
        ControllerDirectFlights.watch(m)
        if plan.rotation then _rotationUp[plan.coalition] = id end
    end
end

-- Planned flight `id` is due (at its start, when this asked to look again, or pulled
-- forward in the rotation).
function ControllerDecideLaunches.due(id)
    local S = ControllerScheduleFlights
    local plan = RecordFlightLaunches.planned(id)
    local rec = RecordFlightLaunches.launch(id)
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
        local done, dead, of = RecordThreats.destroyedTo(plan.critical_names, plan.success)
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
        -- a site's come-back that is due goes first
        if ControllerDecideLaunches.comeBackNow(c) then
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
        local notBefore, notBeforeSite, notBeforeBy   -- a done SEAD flight's site, looked at again later
        local comeBack, thirdTry   -- a site's come-back to wait for; a site that had all three tries
        for _, t in ipairs(open) do
            local by = (_bySite[c] or {})[t]
            local sf = by and RecordFlightLaunches.launch(by)
            if not sf then
                cancelled = cancelled or string.format("%s has no SEAD flight", t)
            elseif sf.later then
                if stillOnAttack(sf.later) then waitFor = sf.later else thirdTry = true end
            elseif sf.again then
                local cb, coming = comingBack(by, sf)
                if stillOnAttack(sf.again) then
                    waitFor = sf.again
                elseif coming then
                    comeBack = comeBack or { site = t, by = by, at = cb and cb.at }
                end
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
                local at = retryAt(by)
                if now < at then
                    if not notBefore or at > notBefore then notBefore, notBeforeSite, notBeforeBy = at, t, by end
                else
                    send[by] = true
                end
            end
        end
        if cancelled then
            cancel(plan, id, cancelled)
            return
        end
        -- at most an hour of waiting on a flight that's still on its attack
        _waits[id] = (_waits[id] or 0) + 1
        if waitFor and (_waits[id] <= MAX_WAITS or not RecordFlightLaunches.launch(waitFor).spawned) and now < AIR_TASKING_TIMING.window_s then
            local at = now + AIR_PACKAGE.strike_after_suppression_s
            S.note(id, "delayed")
            say(plan, id, "wait", string.format("waiting for %s, %s; looking again at %s", waitFor,
                RecordFlightLaunches.launch(waitFor).spawned and "still on its attack" or "not launched yet", clockText(at)))
            S.lookAgainAt(id, at)
            return
        end
        -- a SEAD flight done but not yet retry_after_s ago: its site is looked at again then
        if not waitFor and notBefore and now < AIR_TASKING_TIMING.window_s then
            S.note(id, "delayed")
            sayRetryWait(plan, notBeforeBy, notBeforeSite, notBefore)
            S.lookAgainAt(id, notBefore + 1)
            return
        end
        -- a site coming back into the rotation: wait for it (looked at again after the
        -- come-back's planned salvo, or every strike_after_suppression_s until it is set)
        if not waitFor and comeBack and now < AIR_TASKING_TIMING.window_s then
            local sp = RecordFlightLaunches.planned(comeBack.by)
            local at = comeBack.at and math.max(now, comeBack.at) + (sp.tot_s - sp.start_s) + AIR_PACKAGE.strike_after_suppression_s
                or now + AIR_PACKAGE.strike_after_suppression_s
            -- said when it starts waiting, and again once the come-back's time is set
            local before = _waitingForComeBack[id]
            local first = not before
            S.note(id, "delayed")
            if before ~= (comeBack.at or true) then
                say(plan, id, "wait", string.format("waiting for %s's SEAD flight to come back (%s_LATER%s); looking again at %s",
                    comeBack.site, comeBack.by, comeBack.at and (", at " .. clockText(comeBack.at)) or "", clockText(at)))
            end
            _waitingForComeBack[id] = comeBack.at or true
            S.lookAgainAt(id, at)
            if plan.rotation and first then pullForward(c, id) end   -- the rotation goes on meanwhile
            return
        end
        local names, back, copies = {}, now, {}
        local bys = {}
        for by in pairs(send) do bys[#bys + 1] = by end
        table.sort(bys)
        for _, by in ipairs(bys) do
            local copy = prepareAgain(by)
            if copy then
                copies[#copies + 1] = { by = by, copy = copy }
                names[#names + 1] = string.format("%s flies again as %s", by, copy.id)
                -- looked at again after its planned salvo; it waits on while the copy is
                -- still on its attack
                back = math.max(back, copy.tot_s)
            end
        end
        if #names == 0 then
            cancel(plan, id, string.format("%s still in the fight after %s", table.concat(open, ", "),
                thirdTry and "three SEAD flights" or "a second SEAD flight"))
            return
        end
        local at = back + AIR_PACKAGE.strike_after_suppression_s
        S.note(id, "delayed")
        _waits[id] = 0
        say(plan, id, "retry", string.format("%s still in the fight: %s; waiting until %s",
            table.concat(open, ", "), table.concat(names, ", "), clockText(at)))
        for _, c in ipairs(copies) do flyAgain(c.by, c.copy) end
        S.lookAgainAt(id, at)
        return
    end
    launch(plan, id, now)
end

-- Every jet of flight `id` is down (landed, lost or removed on the ramp): a rotation
-- flight's place (or a come-back's, which held it) goes to the next one, now.
function ControllerDecideLaunches.flightDown(id)
    local S = ControllerScheduleFlights
    local rec = RecordFlightLaunches.launch(id)
    local m = rec and (rec.mission_flown or rec.mission)
    if not m then return end
    local c = m.coalition
    local heldPlace = _rotationUp[c] == id
    if heldPlace then _rotationUp[c] = nil end
    -- a second try down with its site still in the fight: the site comes back later (a
    -- rotation site, or one the rotation needs: planComeBack decides)
    if id:match("_AGAIN$") then
        local rid = rotationId(id)
        _comeBackPending[rid] = true
        timer.scheduleFunction(function()
            _comeBackPending[rid] = nil
            local ok, err = pcall(planComeBack, rid)
            if not ok then Log.warn(string.format("%s: come-back failed: %s", rid, tostring(err))) end
        end, nil, timer.getTime() + AIR_PACKAGE.retry_after_s)
    end
    if not (m.rotation or heldPlace) then return end
    -- a come-back that is due takes the place first
    if ControllerDecideLaunches.comeBackNow(c) then return end
    pullForward(c, rotationId(id))
end

function ControllerDecideLaunches.start(plan)
    _plan = plan
    for _, c in ipairs({ "red", "blue" }) do
        local ato = plan.air_tasking_orders and plan.air_tasking_orders[c]
        _bySite[c] = ato and ato.suppression_by_site or {}
        _rotation[c] = ato and ato.suppression_rotation or {}
    end
end
