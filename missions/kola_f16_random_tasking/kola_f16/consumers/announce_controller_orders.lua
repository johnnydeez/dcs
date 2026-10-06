-- Consumer: Darkstar gives the AI flights their orders on the radio (roadmap.md item 7,
-- step 14; John, 2026-10-05 late: "the controller commands become Darkstar directive radio
-- callouts to the individual flights").
--
-- A watcher of the controller, not part of it: the controller publishes every decision
-- (ControlAirFlights.onDecision) and knows nothing of the radio; this listens and says the
-- ones that are orders to a flight in the air, on the AWACS channel, in Darkstar's voice.
-- Unlike the pilots' calls (announce_flight_activity.lua), which come from what a flight
-- actually does, these come from the decision itself: the order is what Darkstar said,
-- whether or not the DCS AI follows it. No pilot answers yet (John, 2026-10-05: next).
--
--   engage           defend: "Weasel 1, Darkstar, bandit zero niner zero, twenty-five, hot, engage"
--   resume           back on mission / way home, after an engage that was said: "… bandit
--                    destroyed, resume"
--   return_to_base   go cold, leash home, handover, bingo, leave (a bandit and nothing to
--                    fight it with): "Weasel 1, Darkstar, push cold, RTB Rovaniemi"
--   land_at          land (a jet lost on its way home, a wingman still up after its lead
--                    landed): "Weasel 1-2, Darkstar, Rovaniemi bears two one zero, fifteen, land"
--   scramble_vector  a scramble's jet airborne: the vector to its raid, a few seconds after
--                    the pilot's own airborne call. The scramble decision itself isn't said
--                    (the jet is still on the ground, 1-2 min from spawning).
-- Not said: launch decisions (wait, retry, cancel, launch late, come back), alert jets, no
-- scramble, ramp stand-downs, press on, leave threat, orphans.
-- Bearings and ranges are from the flight's lead to the bandit as the coalition's radar
-- picture holds it (grid-based magnetic, as Darkstar's picture calls), else to where the
-- bandit really is (a bandit that fired at the flight but no radar holds).
-- Folding: an engage on the same bandit to the same flight within orders.engage_fold_s is
-- said once; a resume only after an engage that was said, and once.
-- Event log: RADIO_CALL, like the pilots' calls ("engage on awacs by Darkstar to Weasel 1, …").

AnnounceControllerOrders = {}

local _flights = {}     -- flight id → { engaged = { bandit group → time said }, resumed = { bandit group → true } }
local _scrambles = {}   -- scramble id → its raid's group names, until its first jet takes off

local RETURN_DECISIONS = {
    ["go cold"] = true, ["leash home"] = true, ["handover"] = true, ["bingo"] = true, ["leave"] = true,
}

local FEET_PER_METRE = 3.28084

local function norm(deg) return (deg % 360 + 360) % 360 end

-- The mission a group flies (as flown: a late launch or a retry has its own copy), or nil.
local function missionOf(id)
    local r = id and ScheduleAirTaskingOrders.record(id)
    return r and (r.mission_flown or r.mission) or nil
end

-- Darkstar talks to AI flights with a callsign, of a coalition that talks; not to the AWACS.
local function talksTo(m)
    return m and m.flown_by ~= "human" and m.callsign and m.mission_type ~= "airborne_early_warning"
        and SendRadioCalls.on(m.coalition)
end

local function flight(id)
    _flights[id] = _flights[id] or { engaged = {}, resumed = {} }
    return _flights[id]
end

-- The flight's first jet in the air, or nil.
local function leadOf(groupName)
    local g = Group.getByName(groupName)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then return u end
    end
    return nil
end

-- The bandit as the picture holds it, or (not held) where it really is, shaped like a
-- picture contact for CallAirPicture.groupFrom; nil when it's gone.
local function banditContact(coalition, groupName)
    local c = TrackRadarPicture.contact(coalition, groupName)
    if c and c.pos and c.heading_deg then return c end
    local u = leadOf(groupName)
    if not u then return nil end
    local ok, facts = pcall(function()
        local p, v = u:getPoint(), u:getVelocity()
        return { group = groupName, pos = { x = p.x, z = p.z }, altitude_m = p.y,
                 heading_deg = norm(math.deg(math.atan2(v.z, v.x))), speed_mps = math.sqrt(v.x * v.x + v.z * v.z),
                 range_known = true, type = u:getTypeName(), category = "airplane", last_seen = timer.getTime() }
    end)
    return ok and facts or nil
end

-- BRAA facts of the bandit from the flight's lead: bearing (magnetic), range_nm,
-- altitude_ft, aspect, bandit_type; plus flags. Empty when either is gone.
local function braa(coalition, flightId, banditGroup)
    local lead = leadOf(flightId)
    local c = lead and banditGroup and banditContact(coalition, banditGroup)
    if not c then return {}, {} end
    local ok, g = pcall(CallAirPicture.groupFrom, lead, c)
    if not ok or not g then return {}, {} end
    local known = g.type and not g.type:match("^unknown")
    return { bearing = g.bearing, range_nm = math.floor(g.range_nm * 10 + 0.5) / 10,
             altitude_ft = math.floor(g.altitude_ft + 0.5), aspect = g.aspect, bandit_type = known and g.type or nil },
           { has_bandit = true, type_known = known and true or nil, type_unknown = (not known) or nil }
end

-- Bearing (magnetic) and range from jet `unit` to airbase `base`, or nil.
local function toBase(unit, base)
    local ab = Airbase.getByName(base)
    if not (unit and ab) then return nil end
    local ok, g = pcall(function()
        local p = ab:getPoint()
        return CallAirPicture.groupFrom(unit, { pos = { x = p.x, z = p.z }, altitude_m = p.y, heading_deg = 0,
            speed_mps = 0, range_known = true, last_seen = timer.getTime() })
    end)
    return ok and g or nil
end

local function flagList(set)
    local out = {}
    for k, v in pairs(set) do if v then out[#out + 1] = k end end
    table.sort(out)
    return out
end

-- Say `kind` to flight m (or to `addressee`, a jet's callsign), with `facts` and `flags`.
local function say(m, kind, facts, flags, addressee, why)
    facts.callsign = addressee or FlightCallsigns.text(m)
    facts.flight = FlightCallsigns.text(m)
    facts.flags = flagList(flags)
    SendRadioCalls.say(m.coalition, kind, "awacs", facts)
    WriteEventLog.add(m.coalition, "RADIO_CALL", m.id, string.format("%s on awacs by %s to %s%s", kind,
        RADIO_CALLS.awacs_callsign[m.coalition] or "AWACS", facts.callsign, why and (", " .. why) or ""))
end

-- ── the decisions ───────────────────────────────────────────────

local function engage(m, d)
    local bandit = d.details.threat
    if not bandit then return end
    local f = flight(m.id)
    local now = timer.getTime()
    if f.engaged[bandit] and now - f.engaged[bandit] < RADIO_CALLS.orders.engage_fold_s then return end
    local facts, flags = braa(m.coalition, m.id, bandit)
    if not facts.bearing then return end
    f.engaged[bandit], f.resumed[bandit] = now, nil
    say(m, "engage", facts, flags, nil, bandit)
end

local function resume(m, d)
    local det = d.details
    local f = _flights[m.id]
    local bandit = det.threat
    if not (f and bandit and f.engaged[bandit]) or f.resumed[bandit] or det.reason == "no_jets_up" then return end
    if not leadOf(m.id) then return end
    f.resumed[bandit] = true
    local flags = { on_way_home = d.decision == "back on way home", on_mission = d.decision ~= "back on way home" }
    if det.reason then flags[det.reason] = true end
    say(m, "resume", { base = m.landing_base }, flags, nil, det.reason)
end

local function returnToBase(m, d)
    local det = d.details
    if not leadOf(m.id) then return end
    local facts, flags = {}, {}
    if d.decision == "leave" then
        facts, flags = braa(m.coalition, m.id, det.threat)
    end
    facts.base = m.landing_base
    local relief = det.relief and missionOf(det.relief)
    facts.relief = relief and FlightCallsigns.text(relief) or ""
    flags.has_relief = relief and relief.callsign and true or nil
    flags[det.reason or "home"] = true
    -- a bandit and nothing to fight it with: urgent
    if d.decision == "leave" then facts.priority = 1 end
    say(m, "return_to_base", facts, flags, nil, det.reason)
end

local function landAt(m, d)
    local det = d.details
    local jets = {}
    for _, name in ipairs(det.units or {}) do
        local u = Unit.getByName(name)
        if u then jets[#jets + 1] = u end
    end
    if #jets == 0 then jets[1] = leadOf(m.id) end
    if not jets[1] then return end
    -- one jet named: that jet; else the flight
    local addressee
    if #jets == 1 and det.units and #det.units == 1 then
        local n = tonumber(det.units[1]:match("_(%d+)$") or "")
        addressee = n and FlightCallsigns.jet(m, n)
    end
    local g = toBase(jets[1], m.landing_base)
    local facts = { base = m.landing_base }
    if g then facts.bearing, facts.range_nm = g.bearing, math.floor(g.range_nm * 10 + 0.5) / 10 end
    local flags = { has_bearing = g ~= nil }
    flags[det.reason or "overdue"] = true
    say(m, "land_at", facts, flags, addressee, det.reason)
end

local function onDecision(d)
    local decision = d.decision
    if decision == "watching" then
        local m = missionOf(d.subject)
        if m and m.mission_type == "interception" and #(d.details.targets or {}) > 0 and talksTo(m) then
            _scrambles[m.id] = d.details.targets
        end
        return
    end
    local wanted = decision == "defend" or decision == "back on mission" or decision == "back on way home"
        or decision == "land" or RETURN_DECISIONS[decision]
    if not wanted then return end
    local m = missionOf(d.subject)
    if not talksTo(m) then return end
    if decision == "defend" then engage(m, d)
    elseif decision == "back on mission" or decision == "back on way home" then resume(m, d)
    elseif decision == "land" then landAt(m, d)
    else returnToBase(m, d) end
end

-- ── a scramble airborne: its vector ─────────────────────────────

local function vector(id, unitName)
    local m = missionOf(id)
    local raid = _scrambles[id]
    _scrambles[id] = nil
    if not (m and raid) then return end
    local u = Unit.getByName(unitName)
    if not u then return end
    for _, group in ipairs(raid) do
        local c = banditContact(m.coalition, group)
        if c then
            local ok, g = pcall(CallAirPicture.groupFrom, u, c)
            if ok and g then
                local known = g.type and not g.type:match("^unknown")
                local climb = m.route and m.route[2] and m.route[2].alt_m
                say(m, "scramble_vector", {
                    bearing = g.bearing, range_nm = math.floor(g.range_nm * 10 + 0.5) / 10,
                    altitude_ft = math.floor(g.altitude_ft + 0.5), aspect = g.aspect,
                    bandit_type = known and g.type or nil,
                    angels_ft = climb and math.floor(climb * FEET_PER_METRE + 0.5) or nil,
                }, { type_known = known and true or nil, type_unknown = (not known) or nil, has_angels = climb ~= nil },
                nil, group)
                return
            end
        end
    end
end

local handler = {}
function handler:onEvent(e)
    if e.id ~= world.event.S_EVENT_TAKEOFF or not e.initiator then return end
    local ok, err = pcall(function()
        local unitName = e.initiator:getName()
        local id = e.initiator:getGroup():getName()
        if not _scrambles[id] then return end
        -- after the pilot's own "airborne" call, which comes on the same event
        timer.scheduleFunction(function()
            local okV, errV = pcall(vector, id, unitName)
            if not okV then Log.warn("controller orders: vector for " .. id .. " failed: " .. tostring(errV)) end
            return nil
        end, nil, timer.getTime() + RADIO_CALLS.orders.vector_after_takeoff_s)
    end)
    if not ok then Log.warn("controller orders: takeoff event failed: " .. tostring(err)) end
end

function AnnounceControllerOrders.start()
    local any = false
    for side in pairs(RADIO_CALLS.coalitions) do any = any or SendRadioCalls.on(side) end
    if not any then return end
    ControlAirFlights.onDecision(onDecision)
    world.addEventHandler(handler)
    Log.info(string.format("--- Controller orders: Darkstar's orders to AI flights on %s ---", SendRadioCalls.channelText("awacs")))
end
