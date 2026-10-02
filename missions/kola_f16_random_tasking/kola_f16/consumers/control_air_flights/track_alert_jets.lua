-- Consumer part of the controller (control_air_flights.lua): the alert jets — each
-- coalition's quick-reaction fighters on the ground, the asset scrambles spend. Book-
-- keeping only: it counts jets and holds spots, and decides nothing (scramble_fighters.lua
-- decides when and from where; roadmap.md item 11).
--
-- Starts from the plan's alert posture (plan.air_tasking_orders[coalition].alert: the
-- alert bases, jets per base, cooldown, the ramp spots held for them). Per alert base:
--   ready      jets on alert now
--   returning  times jets back from a scramble are on alert again (scramble_turnaround_s
--              after landing; John, 2026-09-30: a base shouldn't run out if its jets come back)
--   ready_s    when the next launch is allowed (cooldown_s after the last)
-- plus which scramble came from which base (its jet returns there) and the alert spots a
-- launch is spawning on right now. A jet shot down never comes back; one stood down on the
-- ramp is back on alert at once (closed.md, bug 2).
--
-- Event log lines (word CONTROL, consumers/write_event_log.lua):
--   CONTROL  RED  MSN7901_SCRAM  "alert: landed; its jet is back on alert at Monchegorsk in 30 min; Monchegorsk has …"
--   CONTROL  RED  MSN7901_SCRAM  "alert: stood down on the ramp; its jet is back on alert at Monchegorsk; …"
-- Reads the plan; writes nothing back to it.

TrackAlertJets = {}

local SIDE = { red = 1, blue = 2 }

local _state = {}   -- coalition → { posture, bases = { [base] = { ready, returning, ready_s } }, flights, held }

local function jets(c, base)
    local st = _state[c]
    return st and st.bases[base]
end

-- Jets back from a scramble return to alert once their turnaround is over.
local function readyJets(s, now)
    for i = #s.returning, 1, -1 do
        if s.returning[i] <= now then
            s.ready = s.ready + 1
            table.remove(s.returning, i)
        end
    end
    return s.ready
end

-- ── what the controller asks ────────────────────────────────────

-- The coalition's alert posture from the plan (bases, max_airborne_aircraft,
-- first_number), or nil when it has no alert bases.
function TrackAlertJets.posture(c)
    return _state[c] and _state[c].posture
end

-- True when alert base `base` (a posture entry's name) has a jet on alert and is off
-- cooldown, and the base is still held by the coalition.
function TrackAlertJets.canLaunch(c, base, now)
    local s = jets(c, base)
    if not s or readyJets(s, now) == 0 or now < s.ready_s then return false end
    local ab = Airbase.getByName(base)
    local ok, side = pcall(function() return ab and ab:getCoalition() end)
    return ok and side == SIDE[c]
end

-- "2 alert jet(s) ready, 1 turning around (next in 12 min)"
function TrackAlertJets.jetsText(c, base, now)
    local s = jets(c, base)
    if not s then return "no alert jets" end
    local text = string.format("%d alert jet(s) ready", readyJets(s, now))
    if #s.returning > 0 then
        local soonest = math.huge
        for _, t in ipairs(s.returning) do soonest = math.min(soonest, t) end
        text = text .. string.format(", %d turning around (next in %d min)", #s.returning, math.ceil((soonest - now) / 60))
    end
    return text
end

-- Alert base `base` now: jets ready, jets turning around, and seconds until the first of
-- those is back on alert (nil when none is). nil when it isn't an alert base.
function TrackAlertJets.ready(c, base, now)
    local s = jets(c, base)
    if not s then return nil end
    local soonest
    for _, t in ipairs(s.returning) do soonest = math.min(soonest or t, t) end
    return readyJets(s, now), #s.returning, soonest and soonest - now
end

-- A free ramp spot for an alert jet at alert base b (a posture entry): one of the spots
-- the plan holds for its alert jets (b.spots, nearest the runway first) that DCS reports
-- free now and no other scramble is spawning on. { terminal_index, x, z } or nil.
function TrackAlertJets.freeSpot(c, b)
    local ab = Airbase.getByName(b.base)
    if not ab then return nil end
    local held = _state[c] and _state[c].held[b.base] or {}
    local ok, spots = pcall(function() return ab:getParking(true) end)
    if not ok or type(spots) ~= "table" then return nil end
    local free = {}
    for _, s in ipairs(spots) do free[s.Term_Index] = true end
    for _, s in ipairs(b.spots or {}) do
        if free[s.terminal_index] and not held[s.terminal_index] then return s end
    end
    return nil
end

-- ── what the controller tells it ────────────────────────────────

-- A jet is committed to a scramble (it starts its cockpit alert): one fewer on alert, the
-- cooldown starts. Returns what to give back if the scramble is stood down before launch.
function TrackAlertJets.commit(c, base, now, cooldown_s)
    local s = jets(c, base)
    local refund = { ready_s = s.ready_s }
    s.ready, s.ready_s = s.ready - 1, now + cooldown_s
    return refund
end

-- The scramble was stood down before launch: its jet is on alert again, the cooldown as before.
function TrackAlertJets.refund(c, base, refund)
    local s = jets(c, base)
    s.ready, s.ready_s = s.ready + 1, refund.ready_s
end

-- A spot taken while a scramble spawns on it, and freed again.
function TrackAlertJets.hold(c, base, terminal_index)
    local held = _state[c].held
    held[base] = held[base] or {}
    held[base][terminal_index] = true
end

function TrackAlertJets.release(c, base, terminal_index)
    local held = _state[c].held[base]
    if held then held[terminal_index] = nil end
end

-- Scramble `id` launched from `base`: its jet returns there after landing.
function TrackAlertJets.launched(c, base, id)
    _state[c].flights[id] = base
end

-- A scramble stood down on the ramp (it never flew): its jet is back on alert at once.
function TrackAlertJets.stoodDown(id)
    for c, st in pairs(_state) do
        local base = st.flights[id]
        if base then
            st.flights[id] = nil
            local s = st.bases[base]
            s.ready = s.ready + 1
            ControlAirFlights.say(c, id, "alert", string.format("stood down on the ramp; its jet is back on alert at %s; %s has %s",
                base, base, TrackAlertJets.jetsText(c, base, timer.getTime())))
        end
    end
end

-- A scramble's jet that lands goes back on alert at its base after the turnaround.
local landingHandler = {}
function landingHandler:onEvent(e)
    if e.id ~= world.event.S_EVENT_LAND or not e.initiator then return end
    local ok, name = pcall(function() return e.initiator:getGroup():getName() end)
    if not ok or not name then return end
    for c, st in pairs(_state) do
        local base = st.flights[name]
        if base then
            st.flights[name] = nil
            local now = timer.getTime()
            table.insert(st.bases[base].returning, now + AIR_DEFENSE.scramble_turnaround_s)
            ControlAirFlights.say(c, name, "alert", string.format("landed; its jet is back on alert at %s in %d min; %s has %s",
                base, math.floor(AIR_DEFENSE.scramble_turnaround_s / 60), base, TrackAlertJets.jetsText(c, base, now)))
        end
    end
end

-- The coalitions that have alert bases, as "RED from Alakurtti, Banak" lines for dcs.log.
function TrackAlertJets.start(plan)
    local ato = plan.air_tasking_orders
    local started = {}
    for _, c in ipairs({ "red", "blue" }) do
        local posture = ato and ato[c] and ato[c].alert
        if posture and #posture.bases > 0 then
            local st = { posture = posture, bases = {}, flights = {}, held = {} }
            for _, b in ipairs(posture.bases) do
                st.bases[b.base] = { ready = b.alert_aircraft, returning = {}, ready_s = 0 }
            end
            _state[c] = st
            local names = {}
            for _, b in ipairs(posture.bases) do names[#names + 1] = b.base end
            started[#started + 1] = string.format("%s from %s", c:upper(), table.concat(names, ", "))
        end
    end
    if #started > 0 then world.addEventHandler(landingHandler) end
    return started
end
