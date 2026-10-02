-- Consumer: the controller — every decision, after the plan is made and the mission has
-- started, about what AI flights do (roadmap.md items 4 and 11; John, 2026-10-01). DCS AI
-- is the pilot: it flies, evades, shoots and goes home at bingo by itself once it has a
-- directive. What it lacks is someone watching the whole picture and making the calls
-- ("bandit, hot, commit", "go cold", "RTB", "scramble"); that is this folder. The plan
-- says what should fly; the scheduler keeps the clock and the record; the radar picture
-- is what the controller knows; the controller decides.
--
--   control_air_flights.lua      this file: watching flights, the checks, one intent per
--                                flight, the CONTROL lines; what other code calls
--   assess_flight_situations.lua the facts about one flight at one check
--   directives_per_flight.lua    leash, suppression (go cold), self_defence
--   coordinate_flights.lua       across flights: who takes which threat
--   give_orders.lua              intent → DCS orders, only when the intent changes
--   decide_launches.lua          a due flight: launch, wait, fly the suppression again,
--                                cancel; the airborne cap
--   scramble_fighters.lua        scrambles: trigger, refusals, raid, base, intercept point
--   track_alert_jets.lua         the alert jets: ready, cooldown, back on alert (bookkeeping)
--
--   what is known ──► situation per flight ──► directives ──► one intent ──► orders
--   radar picture     assess_flight_          directives_     coordinate_     give_orders.lua
--   own flight        situations.lua          per_flight.lua  flights.lua      (only when the
--   plan                                                       (who takes       intent changes)
--                                                              which threat;
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
--   RED  MSN5901_SCRAM   "leash home: MSN2014_DEAD back over its own airspace, heading away (…)"
--   RED  MSN5901_SCRAM   "leash stand down: MSN2014_DEAD destroyed"
--   BLUE MSN2024_SEAD    "go cold: every anti-radiation missile fired (…)"
--   BLUE MSN2023_STRIKE  "defend: engaging MSN5009_CAP (MiG-31), 95 km, hot, closing 980 kt; 4 radar missiles
--                         aboard, longest AIM-120C (F-16C_50 at 24,000 ft, contested airspace)"
--   BLUE MSN2023_STRIKE  "back on mission: MSN5009_CAP destroyed (1 min 40 s)"
--   RED  MSN5028_OCA     "leave: bandit MSN2002_CAP (F-15C), 92 km, hot, closing 950 kt; no air-to-air
--                         missiles aboard (Su-24M at 25,000 ft, contested airspace)"
--   BLUE MSN2027_OCA     "leave threat: MSN5009_CAP to MSN2023_STRIKE"
-- plus the launch decisions (decide_launches.lua), scrambles (scramble_fighters.lua) and
-- alert jets (track_alert_jets.lua).
-- Reads the plan; writes nothing back to it. Which flights are watched is runtime state.

ControlAirFlights = {}

local FEET_PER_METRE = 3.28084
-- the decision word of each directive's intent, first in its CONTROL line
local DECISION = {
    leash = { home = "leash home", stand_down = "leash stand down" },
    suppression = { home = "go cold" },
    self_defence = { defend = "defend", resume = "back on mission", home = "leave" },
}

local _plan
local _watched = {}        -- flight id → watch entry (below)
local _wakeScheduled = {}  -- coalition → true while a fast check is already on its way

local A = AssessFlightSituations

-- ── text ────────────────────────────────────────────────────────

local function where(w, pos)
    return string.format("%s at %s ft, %s airspace", w.mission.aircraft_type, Util.thousands(pos.y * FEET_PER_METRE),
        DivideAirspace.kindFor(_plan.airspace, { x = pos.x, z = pos.z }, w.mission.coalition))
end

local function duration(s)
    s = math.floor(s)
    if s < 60 then return s .. " s" end
    if s % 60 == 0 then return math.floor(s / 60) .. " min" end
    return string.format("%d min %d s", math.floor(s / 60), s % 60)
end

-- One CONTROL line: "<decision>: <text>", subject the flight (or contact) it is about.
function ControlAirFlights.say(coalition, subject, decision, text)
    WriteEventLog.add(coalition, "CONTROL", subject, decision .. ": " .. text)
end

local function log(w, intent, text)
    local words = DECISION[intent.directive] or {}
    ControlAirFlights.say(w.mission.coalition, w.mission.id, words[intent.kind] or (intent.directive .. " " .. intent.kind), text)
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

local function act(w, s, intent)
    local m, g, now = w.mission, s.group, timer.getTime()
    if intent.kind == "home" then
        if GiveOrders.home(w, g, s.pos) then
            log(w, intent, string.format("%s (%s)", intent.why, where(w, s.pos)))
            w.state, w.defending = "going_home", nil   -- setTask replaced any fight
        end
    elseif intent.kind == "stand_down" then
        GiveOrders.standDown(w, g)
        log(w, intent, intent.why)
        _watched[m.id] = nil
        -- it never flew: its jet goes back on alert, and the end summary says so
        TrackAlertJets.stoodDown(m.id)
        ScheduleAirTaskingOrders.stoodDown(m.id)
    elseif intent.kind == "defend" then
        local t = intent.threat
        local fight = GiveOrders.defend(w, g, t)
        if fight then
            w.defending = fight
            local aa = s.air_to_air
            log(w, intent, string.format("engaging %s, %s %s kt%s; %d radar missiles aboard, longest %s (%s)",
                DirectivesPerFlight.threatText(t), t.closing_mps >= 0 and "closing" or "opening",
                Util.thousands(math.abs(t.closing_mps) * 1.94384),
                t.fired and ", it fired at the flight" or "", aa.radar_count, aa.longest_radar or "?", where(w, s.pos)))
        end
    elseif intent.kind == "resume" then
        local d = w.defending
        GiveOrders.resume(w, g)
        ControlAirFlights.say(m.coalition, m.id, w.state == "going_home" and "back on way home" or "back on mission",
            string.format("%s (%s)", intent.why, duration(now - d.since)))
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
        local g = A.liveGroup(id)
        local s = g and A.build(w, g)
        if not g then
            _watched[id] = nil   -- shot down or gone: the scheduler has logged it
        elseif s then
            if s.airborne then w.airborne_once = true end
            if w.airborne_once and not s.airborne then
                _watched[id] = nil   -- landed
            else
                watched[#watched + 1] = w
                local intents = {}
                for _, name in ipairs(w.directives) do
                    local d = DirectivesPerFlight.get(name)
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
        CoordinateFlights.assignThreats(claims, watched)
        -- a flight that wanted a threat another flight has: said once per flight and threat
        for _, claim in ipairs(claims) do
            local left = claim.left
            local mem = claim.w.memo.self_defence
            if left and mem then
                mem.left = mem.left or {}
                if not mem.left[left.group] then
                    mem.left[left.group] = true
                    ControlAirFlights.say(coalition, claim.w.mission.id, "leave threat", string.format("%s to %s", left.group, left.to))
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

-- True for an anti-radiation missile (passive radar guidance).
local function isAntiRadiation(weapon)
    local d = weapon:getDesc()
    return d and d.category == Weapon.Category.MISSILE and d.guidance == Weapon.GuidanceType.RADAR_PASSIVE
end

local handler = {}
function handler:onEvent(e)
    if e.id ~= world.event.S_EVENT_SHOT or not e.weapon then return end
    pcall(function()
        -- a watched flight's own anti-radiation missile: the go-cold check runs at once,
        -- so a SEAD flight turns the moment its last missile is away
        local own = e.initiator and e.initiator.getGroup and e.initiator:getGroup()
        if own and _watched[own:getName()] and isAntiRadiation(e.weapon) then
            wake(_watched[own:getName()].mission.coalition)
        end
        local target = e.weapon:getTarget()
        local group = target and target.getGroup and target:getGroup()
        local w = group and _watched[group:getName()]
        if not w then return end
        local shooter = e.initiator
        local sg = shooter and shooter.getGroup and shooter:getGroup()
        local isAirplane = shooter and shooter.getDesc and shooter:getDesc().category == Unit.Category.AIRPLANE
        w.reports.shot_at = { time = timer.getTime(), shooter_group = isAirplane and sg and sg:getName() or nil,
                              weapon = e.weapon:getTypeName() }
        wake(w.mission.coalition)
    end)
end

-- ── calls for other code ────────────────────────────────────────

-- Watch a launched AI flight (a plan-shaped mission table) with the directives of its
-- mission type; params.targets are the enemy group names a scramble was sent after
-- (leash). A mission type without directives isn't watched.
function ControlAirFlights.watch(m, params)
    local names = AIR_CONTROL.directives_by_mission_type[m.mission_type]
    if not names or #names == 0 then return end
    local memo = {}
    for _, name in ipairs(names) do memo[name] = {} end
    local targets = params and params.targets or {}
    _watched[m.id] = { mission = m, directives = names, targets = targets,
                       state = "on_task", airborne_once = false, memo = memo, reports = {}, defending = nil }
    ControlAirFlights.say(m.coalition, m.id, "watching", table.concat(names, ", ")
        .. (#targets > 0 and (" on " .. table.concat(targets, ", ")) or ""))
end

-- Planned flight `id` is due (the scheduler asks at its start, or when told to look
-- again): decide_launches.lua decides and has the scheduler carry it out.
function ControlAirFlights.due(id)
    DecideLaunches.due(id)
end

-- True while the flight is watched and still on its task: launched and not yet sent
-- home, stood down, landed or lost (scrambles: is it still after its raid?).
function ControlAirFlights.onTask(id)
    local w = _watched[id]
    return w ~= nil and w.state == "on_task"
end

function ControlAirFlights.start(plan)
    _plan = plan
    AssessFlightSituations.start(plan)
    DecideLaunches.start(plan)
    DirectivesPerFlight.checkData()
    -- each picture round: the directives first (the leash may send a scramble home),
    -- then the scramble decisions
    for _, coalition in ipairs({ "red", "blue" }) do
        TrackRadarPicture.on(coalition, "picture_updated", function() check(coalition, "picture") end)
    end
    local scrambles = ScrambleFighters.start(plan)
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
    world.addEventHandler(handler)
    Log.info(string.format("--- Controller: directives on the radar picture's round and every %d s ---", AIR_CONTROL.check_every_s))
end
