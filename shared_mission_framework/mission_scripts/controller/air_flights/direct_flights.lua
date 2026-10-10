-- Controller: directing the air flights — every decision, after the plan is made and the mission has
-- started, about what AI flights do (roadmap.md items 4 and 11; John, 2026-10-01). DCS AI
-- is the pilot: it flies, evades, shoots and goes home at bingo by itself once it has a
-- directive. What it lacks is someone watching the whole picture and making the calls
-- ("bandit, hot, commit", "go cold", "RTB", "scramble"); that is this folder. The plan
-- says what should fly; the scheduler keeps the clock and the record; the radar picture
-- is what the controller knows; the controller decides.
--
--   direct_flights.lua           this file: watching flights, the checks, one intent per
--                                flight, the CONTROL lines; what other code calls
--   apply_directives.lua         leash, suppression (go cold), self_defence
--   coordinate_flights.lua       across flights: who takes which threat
--   decide_launches.lua          a due flight: launch, wait, fly its SEAD again,
--                                cancel; the airborne cap
--   scramble_fighters.lua        scrambles: trigger, refusals, raid, base, intercept point
--   assign_alert_jets.lua        the alert jets: ready, cooldown, back on alert (bookkeeping)
-- and outside this folder: watch\flight_situations.lua (the facts about one flight at one
-- check) and execute\air_flight_orders.lua (intent → DCS orders, only when it changes).
--
--   what is known ──► situation per flight ──► directives ──► one intent ──► orders
--   radar picture     watch\flight_           apply_          coordinate_     execute\air_
--   own flight        situations.lua          directives.lua  flights.lua      flight_orders.lua
--   plan                                                       (who takes       (only when the
--                                                              which threat;    intent changes)
--                                                              priority)
--
-- Every AI flight whose mission type has directives (AIR_CONTROL.directives_by_mission_type)
-- is watched from spawn (watch, called when the controller launches it) until it lands
-- or is lost. Each directive runs on a clock: the radar picture's round (picture_updated,
-- 30 s) or the fast check (AIR_CONTROL.check_every_s); a missile fired at a watched flight
-- runs the fast check for its coalition at once (the flight's "missile launch" call), and
-- so does an anti-radiation missile a watched flight fires (go cold on the last one).
--
-- A flight's state:
--   on_task      flying its mission; every directive is asked
--   going_home   sent home: only directives that aren't on_task_only (self-defence) are
--                asked; it stays watched until it lands
--   w.defending  set while it fights a threat (on top of on_task or going_home)
--
-- Event log lines: one word, CONTROL, for every controller decision, the decision first
-- (John, 2026-10-01: grep CONTROL to see what this layer is doing):
--   BLUE MSN2023_STRIKE  "watching: self_defence"
--   RED  MSN7901_SCRAM   "leash home: MSN2014_DEAD back over its own airspace, heading away (…)"
--   RED  MSN7901_SCRAM   "leash stand down: MSN2014_DEAD destroyed"
--   BLUE MSN2024_SEAD    "go cold: every anti-radiation missile fired (…)"
--   BLUE MSN2023_STRIKE  "defend: engaging MSN7009_CAP (MiG-31), 95 km, hot, closing 980 kt; 4 radar missiles
--                         aboard, longest AIM-120C (F-16C_50 at 24,000 ft, contested airspace)"
--   BLUE MSN2023_STRIKE  "back on mission: MSN7009_CAP destroyed (1 min 40 s)"
--   RED  MSN7028_OCA     "leave: bandit MSN2002_CAP (F-15C), 92 km, hot, closing 950 kt; no air-to-air
--                         missiles aboard (Su-24M at 25,000 ft, contested airspace)"
--   BLUE MSN2027_OCA     "leave threat: MSN7009_CAP to MSN2023_STRIKE"
--   BLUE MSN2002_CAP     "handover: relieved by MSN2003_CAP, on station (2 km from the race-track) (…)"
--   RED  MSN7025_SEAD    "land: MSN7025_SEAD_2 lost after its landing: 45 km from Vuojarvi and getting farther
--                         (it was 2 km away); sent to land at Vuojarvi (…)"
--   RED  MSN7023_SEAD_2  ">>orphan<< removed: by the controller 8 min 00 s after MSN7023_SEAD_1 landed, counted
--                         as landed (Su-34 at 4,232 ft, 64 km from Banak)" (and the other >>orphan<< lines,
--                         watch\flights.lua)
--   BLUE MSN2026_SEAD    "no shot: 2 min after reaching its launch point, 31 km from DEF_VUOJ_…, all 8 … still aboard"
--   RED  MSN7024_SEAD    "stand down: MSN7024_SEAD_1, MSN7024_SEAD_2 carry no weapons (…); removed on the ramp; …"
-- plus the launch decisions (decide_launches.lua), scrambles (scramble_fighters.lua) and
-- alert jets (controller\air_flights\assign_alert_jets.lua).
-- Reads the plan; writes nothing back to it. Which flights are watched is runtime state.
--
-- Every decision is written to the Record first (record\air_flight_decisions.lua: { coalition,
-- subject, decision, text, details }), then the order goes to Execute, whose result is
-- record\orders.lua (rule 3).
-- details carry what a listener needs without reading the text: reason (one word per
-- why, e.g. "salvo_over", "bingo", "raid_turned_away"), threat (the bandit's group),
-- relief (a patrol's relief), units (the jets a landing order went to), targets (a
-- scramble's raid). The controller doesn't know who listens; Darkstar's radio calls
-- (inform\radio\darkstar_orders.lua) are one listener.

ControllerDirectFlights = {}

local FEET_PER_METRE = 3.28084
-- the decision word of each directive's intent, first in its CONTROL line
local DECISION = {
    leash = { home = "leash home", stand_down = "leash stand down" },
    suppression = { home = "go cold" },
    self_defence = { defend = "defend", resume = "back on mission", home = "leave" },
    handover = { home = "handover" },
    landing = { land = "land" },
    fuel = { home = "bingo" },
}

local _plan
local _watched = {}        -- flight id → watch entry (below)
local _wakeScheduled = {}  -- coalition → true while a fast check is already on its way
local _offTaskAt = {}      -- flight id → mission time it came off its task (sent home, landed, lost); kept after the watch ends
-- the watch entries and off-task times are the Record's (record\watched_flights.lua)
RecordWatchedFlights.writeTables(_watched, _offTaskAt)

local A = RecordFlightSituations

-- ── text ────────────────────────────────────────────────────────

local function where(w, pos)
    return string.format("%s at %s ft, %s airspace", w.mission.aircraft_type, Util.thousands(pos.y * FEET_PER_METRE),
        Airspace.kindFor(_plan.airspace, { x = pos.x, z = pos.z }, w.mission.coalition))
end

-- "8 min 00 s", as the >>orphan<< lines say it
local function duration2(s)
    s = math.floor(s)
    return string.format("%d min %02d s", math.floor(s / 60), s % 60)
end

local function duration(s)
    s = math.floor(s)
    if s < 60 then return s .. " s" end
    if s % 60 == 0 then return math.floor(s / 60) .. " min" end
    return string.format("%d min %d s", math.floor(s / 60), s % 60)
end

-- A decision, written to the Record (record\air_flight_decisions.lua): "<decision>: <text>",
-- subject the flight (or contact) it is about, with `details` (see the top of this file).
-- The event log writes its CONTROL line from there. Returns the decision, for the order
-- that carries it out.
function ControllerDirectFlights.say(coalition, subject, decision, text, details)
    return RecordAirFlightDecisions.write({ coalition = coalition, subject = subject, decision = decision,
                                            text = text, details = details or {} })
end

-- Jets of flight `id` the controller is removing in the air (`names`), said before they
-- go: wingmen still up long after their flight's last landing (bug 19). One >>orphan<<
-- removed line each; then they count as landed (watch\flights.lua hears it), so
-- whatever waits on the flight sees it down.
-- `why`: the reason in words when it isn't "its lead landed" (bug 68: deaf to its
-- landing orders).
local function removedInAir(id, names, why)
    local f = RecordFlights.facts(id)
    if not f then return end
    local m = RecordFlightLaunches.missionFlown(id)
    for _, name in ipairs(names) do
        local orphan = f.orphans and f.orphans[name]
        if why then
            ControllerDirectFlights.say(m.coalition, name, ">>orphan<< removed", string.format("by the controller: %s; counted as landed (%s)",
                why, RecordFlights.jetWhere(m, name)))
        else
            ControllerDirectFlights.say(m.coalition, name, ">>orphan<< removed", string.format("by the controller %s after %s landed, counted as landed (%s)",
                duration2(timer.getTime() - (orphan and orphan.since or f.last_landing_at or timer.getTime())),
                orphan and orphan.lead or f.last_landed or "its lead", RecordFlights.jetWhere(m, name)))
        end
    end
    RecordFlightLaunches.publish({ event = "removed_in_air", id = id, names = names })
end

local function log(w, intent, text)
    local words = DECISION[intent.directive] or {}
    return ControllerDirectFlights.say(w.mission.coalition, w.mission.id, words[intent.kind] or (intent.directive .. " " .. intent.kind), text,
        { reason = intent.reason, threat = intent.threat and intent.threat.group or intent.bandit,
          relief = intent.relief, units = intent.units })
end

-- ── one check ───────────────────────────────────────────────────

local PRIORITY = AIR_CONTROL.intent_priority

-- The one intent a flight acts on: the highest priority, the first directive asked on a tie.
local function pick(intents)
    local best
    for _, i in ipairs(intents) do
        if not best or PRIORITY[i.kind] > PRIORITY[best.kind] then best = i end
    end
    return best
end

-- Acting on the one intent (rule 3): the decision is written to the Record first, then
-- Execute is handed the order, then the flight's state follows from what came of it.
local function act(w, s, intent)
    local m, now = w.mission, timer.getTime()
    if intent.kind == "home" then
        local d = log(w, intent, string.format("%s (%s)", intent.why, where(w, s.pos)))
        local r = ExecuteAirFlightOrders.home({ flight = m.id, mission = m, pos = s.pos, decision = d })
        if r.carried_out then
            w.state, w.defending = "going_home", nil   -- setTask replaced any fight
            _offTaskAt[m.id] = _offTaskAt[m.id] or now
        end
    elseif intent.kind == "land" then
        local mem = w.memo.landing
        mem.orders, mem.ordered_at = (mem.orders or 0) + 1, now
        -- its jets in the air get the order; one jet each when another of the flight is on
        -- the ground (bug 19); none in the air: no order
        local up, onGround = {}, false
        for _, u in ipairs(s.units) do
            if u.airborne then up[#up + 1] = { name = u.name, pos = u.pos } else onGround = true end
        end
        if #up > 0 then
            local d = log(w, intent, string.format("%s; sent to land at %s%s (%s)", intent.why, m.landing_base,
                onGround and ", each jet in the air on its own order" or "", where(w, s.pos)))
            local r = ExecuteAirFlightOrders.land({ flight = m.id, mission = m, units = up, per_jet = onGround, decision = d })
            if r.carried_out then
                w.state, w.defending = "going_home", nil
                _offTaskAt[m.id] = _offTaskAt[m.id] or now
                mem.closest = nil   -- measured again from here
            end
        end
    elseif intent.kind == "remove" then
        -- its CONTROL lines are the ">>orphan<< removed" decisions, one per jet, written
        -- before they go, to read where they are
        _watched[m.id] = nil
        removedInAir(m.id, intent.units, intent.reason ~= "orphan" and intent.why or nil)
        ExecuteAirFlightOrders.remove({ flight = m.id, mission = m, units = intent.units })
    elseif intent.kind == "stand_down" then
        local d = log(w, intent, intent.why)
        ExecuteAirFlightOrders.standDown({ flight = m.id, mission = m, decision = d })
        _watched[m.id] = nil
        -- it never flew: its jet goes back on alert, and the end summary says so
        ControllerAssignAlertJets.stoodDown(m.id)
        ControllerScheduleFlights.stoodDown(m.id)
    elseif intent.kind == "defend" then
        local t = intent.threat
        local aa = s.air_to_air
        local d = log(w, intent, string.format("engaging %s, %s %s kt%s; %d radar missiles aboard, longest %s (%s)",
            ControllerApplyDirectives.threatText(t), t.closing_mps >= 0 and "closing" or "opening",
            Util.thousands(math.abs(t.closing_mps) * 1.94384),
            t.fired and ", it fired at the flight" or "", aa.radar_count, aa.longest_radar or "?", where(w, s.pos)))
        local r = ExecuteAirFlightOrders.defend({ flight = m.id, mission = m, threat_group = t.group,
                                                  going_home = w.state == "going_home", decision = d })
        if r.carried_out then w.defending = r.fight end
    elseif intent.kind == "resume" then
        local fight = w.defending
        local d = ControllerDirectFlights.say(m.coalition, m.id, w.state == "going_home" and "back on way home" or "back on mission",
            string.format("%s (%s)", intent.why, duration(now - fight.since)),
            { reason = intent.reason, threat = fight.group, fight_s = now - fight.since })
        ExecuteAirFlightOrders.resume({ flight = m.id, mission = m, fight = fight,
                                        going_home = w.state == "going_home", decision = d })
        w.defending = nil
        w.memo.self_defence.last_resume = now
    end
end

-- Runs the directives on `clock` for every watched flight of the coalition.
local function check(coalition, clock)
    local ids, watched = {}, {}
    for id, w in pairs(_watched) do
        if w.mission.coalition == coalition then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local decided, claims = {}, {}
    for _, id in ipairs(ids) do
        local w = _watched[id]
        local live = RecordGroups.alive(id)
        local s = live and A.build(w)
        if not live then
            _watched[id] = nil   -- shot down or gone: the scheduler has logged it
            _offTaskAt[id] = _offTaskAt[id] or timer.getTime()
        elseif s then
            if s.airborne then w.airborne_once = true end
            -- landed: none of it in the air any more, and none still waiting to take off
            -- (bug 48: a lead shot down while its wingman sat in the taxi queue ended the
            -- watch, and the wingman flew its whole SEAD with no go cold or bandit call)
            if w.airborne_once and not s.airborne and not A.waitingToTakeOff(s) then
                _watched[id] = nil
                _offTaskAt[id] = _offTaskAt[id] or timer.getTime()
            else
                watched[#watched + 1] = w
                local intents = {}
                for _, name in ipairs(w.directives) do
                    local d = ControllerApplyDirectives.get(name)
                    if d.clock == clock and not (d.on_task_only and w.state == "going_home") then
                        local ok, intent = pcall(d.check, w, s)
                        if not ok then
                            Log.warn(string.format("%s: directive %s failed: %s", id, name, tostring(intent)))
                        elseif intent then
                            intent.directive = name
                            intents[#intents + 1] = intent
                        end
                    end
                end
                local intent = pick(intents)
                if intent then
                    decided[#decided + 1] = { w = w, s = s, intent = intent }
                    if intent.kind == "defend" then claims[#claims + 1] = decided[#decided] end
                end
            end
        end
    end
    if #claims > 0 then
        ControllerCoordinateFlights.assignThreats(claims, watched)
        -- a flight that wanted a threat another flight has: said once per flight and threat
        for _, claim in ipairs(claims) do
            local left = claim.left
            local mem = claim.w.memo.self_defence
            if left and mem then
                mem.left = mem.left or {}
                if not mem.left[left.group] then
                    mem.left[left.group] = true
                    ControllerDirectFlights.say(coalition, claim.w.mission.id, "leave threat", string.format("%s to %s", left.group, left.to))
                end
            end
        end
    end
    for _, d in ipairs(decided) do
        if d.intent and _watched[d.w.mission.id] then
            local ok, err = pcall(act, d.w, d.s, d.intent)
            if not ok then Log.warn(string.format("%s: acting on %s failed: %s", d.w.mission.id, d.intent.kind, tostring(err))) end
        end
    end
end

-- ── reports: a missile fired at a watched flight ────────────────

local function wake(coalition)
    if _wakeScheduled[coalition] then return end
    _wakeScheduled[coalition] = true
    timer.scheduleFunction(function()
        _wakeScheduled[coalition] = nil
        check(coalition, "fast")
        return nil
    end, nil, timer.getTime() + 0.5)
end

-- A watched flight fired an anti-radiation missile (the go-cold check runs at once, so a
-- SEAD flight turns the moment its last missile is away), or a missile was fired at one
-- (record\shots.lua, from watch\shots.lua): its coalition's fast check runs now.
local function wakeFor(e)
    local w = _watched[e.flight]
    if w then wake(w.mission.coalition) end
end

-- ── calls for other code ────────────────────────────────────────

-- Watch a launched AI flight (a plan-shaped mission table) with the directives of its
-- mission type; params.targets are the enemy group names a scramble was sent after
-- (leash). A mission type without directives isn't watched.
function ControllerDirectFlights.watch(m, params)
    local names = AIR_CONTROL.directives_by_mission_type[m.mission_type]
    if not names or #names == 0 then return end
    local memo = {}
    for _, name in ipairs(names) do memo[name] = {} end
    local targets = params and params.targets or {}
    _watched[m.id] = { mission = m, directives = names, targets = targets,
                       state = "on_task", airborne_once = false, memo = memo, defending = nil,
                       -- spawned in the air on its station: no waypoint to reach first
                       on_station_at = m.takeoff == "air" and m.route[1] and m.route[1].kind == "station"
                           and timer.getTime() or nil }
    ControllerDirectFlights.say(m.coalition, m.id, "watching", table.concat(names, ", ")
        .. (#targets > 0 and (" on " .. table.concat(targets, ", ")) or ""), { targets = targets })
end

-- Flight `id` reached waypoint `index` of its route (record\waypoints_reached.lua): a SEAD
-- flight's attack clock starts at its pop-up (bug 33: counted from 15 km of the launch
-- point, it started at takeoff for a flight from a base that close).
-- At its press-on point (bug 36) the go cold sends it home if it has fired nothing.
function ControllerDirectFlights.waypoint(id, index)
    local w = _watched[id]
    local r = w and w.mission.route and w.mission.route[index]
    if not r then return end
    -- a patrol at its station waypoint is on station, the relief a handover waits for
    -- (bug 62: a station over its base counted the relief on station on its takeoff roll)
    if r.kind == "station" then w.on_station_at = w.on_station_at or timer.getTime() end
    if not w.memo.suppression then return end
    if (r.kind == "popup" or r.kind == "target") and not w.memo.suppression.arrived_s then
        w.memo.suppression.arrived_s = timer.getTime()
    end
    if r.kind == "press_on" then w.memo.suppression.pressed_on = true end
end

-- Planned flight `id` is due (the scheduler asks at its start, or when told to look
-- again): decide_launches.lua decides and has the scheduler carry it out.
function ControllerDirectFlights.due(id)
    ControllerDecideLaunches.due(id)
end

-- Every jet of flight `id` is down (the scheduler says so once): decide_launches.lua
-- moves the SEAD rotation on.
function ControllerDirectFlights.flightDown(id)
    ControllerDecideLaunches.flightDown(id)
end

-- A spawned flight's jets that carry no weapons although their loadout lists some
-- (record\flight_loadouts.lua, from watch\flight_loadouts.lua; bug 6: two Su-24Ms flew 75 km into an
-- SA-10's ring with nothing to shoot): removed on the ramp, never flown. A flight left
-- with no jet isn't flying; the gate (decide_launches.lua) then sees its threat still
-- in the fight for whatever waits on it, as if it had failed.
function ControllerDirectFlights.unarmed(m, unitNames, loadoutText)
    -- the jets still there go; the rest of the flight flies if any other jet of it is alive
    local existing, going = {}, {}
    for _, name in ipairs(unitNames) do
        if RecordGroups.unitExists(name) then
            existing[#existing + 1] = name
            going[name] = true
        end
    end
    if #existing == 0 then return end
    local left = false
    for _, name in ipairs(RecordGroups.liveUnitNames(m.id)) do
        if not going[name] then left = true end
    end
    local d = ControllerDirectFlights.say(m.coalition, m.id, "stand down", string.format("%s carr%s no weapons (its loadout %s); removed on the ramp%s",
        table.concat(unitNames, ", "), #unitNames == 1 and "ies" or "y", loadoutText,
        left and "; the rest of the flight flies" or "; the flight isn't flying"))
    ExecuteAirFlightOrders.remove({ flight = m.id, mission = m, units = existing, decision = d })
    ControllerScheduleFlights.removed(m.id, #existing)
    if not left then _watched[m.id] = nil end
end

function ControllerDirectFlights.start(plan)
    _plan = plan
    ControllerDecideLaunches.start(plan)
    ControllerApplyDirectives.checkData()
    -- each picture round: the directives first (the leash may send a scramble home),
    -- then the scramble decisions
    for _, coalition in ipairs({ "red", "blue" }) do
        RecordRadarPicture.on(coalition, "picture_updated", function() check(coalition, "picture") end)
    end
    local scrambles = ControllerScrambleFighters.start(plan)
    if #scrambles > 0 then
        Log.info(string.format("--- Scrambles: every radar-picture round; %s ---", table.concat(scrambles, "; ")))
    end
    timer.scheduleFunction(function(_, now)
        for _, coalition in ipairs({ "red", "blue" }) do
            local ok, err = pcall(check, coalition, "fast")
            if not ok then Log.warn("controller fast check failed: " .. tostring(err)) end
        end
        return now + AIR_CONTROL.check_every_s
    end, nil, timer.getTime() + AIR_CONTROL.check_every_s)
    RecordWaypointsReached.on(ControllerDirectFlights.waypoint)
    RecordFlightLoadouts.on("unarmed", function(e) ControllerDirectFlights.unarmed(e.mission, e.units, e.loadout_text) end)
    RecordShots.on("anti_radiation_fired", wakeFor)
    RecordShots.on("shot_at", wakeFor)
    Log.info(string.format("--- Controller: directives on the radar picture's round and every %d s ---", AIR_CONTROL.check_every_s))
end
