-- Inform: AI flights at Blue airfields announce themselves on the field's own frequency,
-- the way traffic at an uncontrolled field does (roadmap.md item 7, "Flights and airfields
-- talk"; John, 2026-10-05: "Kallax traffic, Viper 1-2 on final, runway three one").
--
-- Each phase is seen, not planned: what the jets actually do (record\airfield_traffic.lua),
-- checked every RADIO_CALLS.airfield_every_s for flights departing or arriving, and DCS's
-- takeoff and landing events (record\dcs_events.lua). One call per flight per phase, by its lead (the first jet that does it):
--   taxi       a hot-spawned jet on the ramp starts to move     "taxiing to runway 31" (the runway in use for the wind)
--   departing  its first jet lines up on a runway: on the       the runway it is on, bound for its first leg
--              runway, nose along it (event log LINE_UP; bug 67:
--              it was said at takeoff, after the jet was gone);
--              at takeoff if the line-up wasn't seen
--   inbound    back toward its landing base, inside inbound_nm  where it is from the field; the runway in use
--   final      lined up with a runway end, close in and low     that runway
--   clear      clear_after_landing_s after its first touchdown  the runway it landed on
-- The runway numbers are magnetic as the F-16 shows them (InformScreenAirfieldInfo, grid minus
-- variation). A field's calls are made only with a player within airfield_range_nm of it
-- (a tower frequency's reach near the ground); the radio player then plays them only when
-- a radio is on that field's frequency (InformRadioRadioCalls.airfieldFrequency).
-- Players' flights don't call (John: maybe later, with an LLM-based ATC).
-- The phases are kept here; the comms menu's traffic list (roadmap.md item 15) will want
-- them as Watch facts. Event log: RADIO_CALL, and LINE_UP for a jet seen lined up.

InformRadioAirfieldCalls = {}

local _plan
local _departing = {}   -- group → { m, base, phase = "parked" | "taxi" }
local _flying = {}      -- group → { m, base (landing), airborne_at, said = { kind → true } }

local COMPASS_POINTS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function norm(deg) return (deg % 360 + 360) % 360 end

local function compass(deg)
    return COMPASS_POINTS[math.floor(norm(deg) / 45 + 0.5) % 8 + 1]
end


local function missionOf(groupName)
    return RecordFlightLaunches.missionFlown(groupName)
end

local function talks(m)
    return m and m.flown_by ~= "human" and m.callsign and InformRadioRadioCalls.on(m.coalition)
        and _plan.territory.bases[m.launch_base] and _plan.territory.bases[m.launch_base].side == m.coalition
end

local function basePos(name)
    local ab = _plan.world.airbases[name]
    return ab and (ab.anchor or ab.pos)
end

-- A jet's grid heading from its velocity (record\airfield_traffic.lua).
local function headingOf(jet)
    local v = jet.velocity
    return norm(math.deg(math.atan2(v.z, v.x)))
end

-- True when a player of `side` is within airfield_range_nm of base `name`.
local function heard(side, name)
    local pos = basePos(name)
    if not pos then return false end
    local reach = RADIO_CALLS.airfield_range_nm * 1852
    for _, player in ipairs(RecordPlayers.list(side == "blue" and coalition.side.BLUE or coalition.side.RED)) do
        local p = player.point
        if p and Util.dist({ x = p.x, z = p.z }, pos) <= reach then return true end
    end
    return false
end

local function say(m, kind, base, unitName, facts)
    if not heard(m.coalition, base) then return end
    local n = tonumber((unitName or ""):match("_(%d+)$") or "1") or 1
    facts.callsign = FlightCallsigns.jet(m, n)
    facts.flight = FlightCallsigns.text(m)
    facts.voice_key = facts.callsign
    facts.field = base
    InformRadioRadioCalls.say(m.coalition, kind, "airfield", facts, base)
    EventLog.add(m.coalition, "RADIO_CALL", unitName or m.id, string.format("%s on %s traffic (%s) by %s%s",
        kind, base, InformRadioRadioCalls.channelText("airfield", base), facts.callsign,
        facts.runway and (", runway " .. string.format("%02d", facts.runway)) or ""))
end

local function flagList(t)
    local out = {}
    for k, v in pairs(t) do if v then out[#out + 1] = k end end
    return out
end

-- ── DCS events ──────────────────────────────────────────────────

-- `unit` below: an event's object (record\dcs_events.lua) or a jet (record\airfield_traffic.lua),
-- both with name and nose_deg.
local function onBirth(unit)
    local group = unit.group
    if not group or _departing[group] or _flying[group] then return end
    local m = missionOf(group)
    if not talks(m) or m.takeoff == "air" then return end
    _departing[group] = { m = m, base = m.launch_base, phase = "parked" }
end

-- "departing" by jet `unit` of flight m from `base` on `runway`: bound for its first leg,
-- the route's next point from the field.
local function sayDeparting(m, base, unit, runway)
    local from, to = basePos(base), m.route and m.route[2]
    local direction = (from and to) and compass(math.deg(math.atan2(to.z - from.z, to.x - from.x))) or compass(unit.nose_deg)
    say(m, "departing", base, unit.name, { runway = runway, direction = direction,
        flags = flagList({ single = m.count == 1, two_ship = m.count >= 2 }) })
end

local function onTakeoff(unit)
    local group = unit.group
    local d = group and _departing[group]
    local m = d and d.m or missionOf(group)
    if not talks(m) or _flying[group] then return end
    _departing[group] = nil
    local base = m.launch_base
    _flying[group] = { m = m, base = m.landing_base, airborne_at = timer.getTime(), said = {} }
    -- said at its line-up; only a line-up the look missed is said now
    if d and d.lined_up then return end
    sayDeparting(m, base, unit, InformScreenAirfieldInfo.runwayFor(base, unit.nose_deg))
end

local function onLand(unit)
    local group = unit.group
    local f = group and _flying[group]
    if not f or f.said.clear then return end
    f.said.clear = true
    local base = f.base
    local runway = InformScreenAirfieldInfo.runwayFor(base, unit.nose_deg)
    local unitName = unit.name
    timer.scheduleFunction(function()
        local ok, err = pcall(say, f.m, "clear", base, unitName, { runway = runway,
            flags = flagList({ runway_known = runway ~= nil }) })
        if not ok then Log.warn("airfield calls: clear: " .. tostring(err)) end
    end, nil, timer.getTime() + RADIO_CALLS.clear_after_landing_s)
end

-- A DCS event (record\dcs_events.lua).
local function onEvent(e)
    if not e.initiator then return end
    local ok, err = pcall(function()
        if e.id == world.event.S_EVENT_BIRTH then onBirth(e.initiator)
        elseif e.id == world.event.S_EVENT_TAKEOFF then onTakeoff(e.initiator)
        elseif e.id == world.event.S_EVENT_LAND then onLand(e.initiator)
        end
    end)
    if not ok then Log.warn("airfield calls: event " .. tostring(e.id) .. " failed: " .. tostring(err)) end
end

-- ── the look every airfield_every_s ─────────────────────────────

local function units(group)
    return RecordAirfieldTraffic.jets(group)
end

-- The runway at `base` a jet at `p` with its nose on grid heading `nose` is lined up on:
-- inside the runway's strip (lineup_margin_m beyond its ends and edges) with its nose
-- within lineup_aligned_deg of one of its directions (so a jet crossing it isn't);
-- the runway end's number (magnetic, as the F-16 shows it), or nil.
local function runwayLinedUp(base, p, nose)
    local R = RADIO_CALLS
    local ab = _plan.world.airbases[base]
    for _, rw in ipairs(ab and ab.runways or {}) do
        local h = math.rad(rw.heading_deg)
        local dx, dz = p.x - rw.x, p.z - rw.z
        local along = dx * math.cos(h) + dz * math.sin(h)
        local across = -dx * math.sin(h) + dz * math.cos(h)
        local off = math.abs((nose - rw.heading_deg + 180) % 360 - 180)
        if math.abs(along) <= rw.length / 2 + R.lineup_margin_m and math.abs(across) <= rw.width / 2 + R.lineup_margin_m
           and (off <= R.lineup_aligned_deg or off >= 180 - R.lineup_aligned_deg) then
            return InformScreenAirfieldInfo.runwayFor(base, nose)
        end
    end
    return nil
end

local function lookDeparting(group, d)
    if d.lined_up then return end
    for _, u in ipairs(units(group)) do
        local ok, p, speed = pcall(function()
            if not u.exists or u.airborne then return nil end
            local v = u.velocity
            return u.point, math.sqrt(v.x * v.x + v.z * v.z)
        end)
        if ok and p then
            if d.phase == "parked" and speed >= RADIO_CALLS.taxi_speed_mps then
                d.phase = "taxi"
                local runway = InformScreenAirfieldInfo.runwayInUse(d.base)
                say(d.m, "taxi", d.base, u.name, { runway = runway,
                    flags = flagList({ runway_known = runway ~= nil, single = d.m.count == 1, two_ship = d.m.count >= 2 }) })
            end
            -- lined up: the first jet of the flight on a runway, nose along it
            local runway = d.phase == "taxi" and runwayLinedUp(d.base, p, u.nose_deg)
            if runway then
                d.lined_up = true
                EventLog.add(d.m.coalition, "LINE_UP", u.name or group, string.format("lined up on runway %02d at %s, %.0f kt",
                    runway, d.base, speed * 1.94384))
                sayDeparting(d.m, d.base, u, runway)
                return
            end
        end
    end
end

local function lookFlying(group, f)
    local R = RADIO_CALLS
    local field = basePos(f.base)
    if not field or timer.getTime() - f.airborne_at < 300 then return end   -- not on its way out
    for _, u in ipairs(units(group)) do
        if u.airborne then
            local p = u.point
            local pos = { x = p.x, z = p.z }
            local d = Util.dist(pos, field)
            local heading = headingOf(u)
            local toField = norm(math.deg(math.atan2(field.z - pos.z, field.x - pos.x)))
            local towards = math.abs((heading - toField + 180) % 360 - 180) <= 45
            local v = u.velocity
            local speed = math.sqrt(v.x * v.x + v.z * v.z)
            local okH, ground = pcall(land.getHeight, { x = p.x, y = p.z })
            local height = p.y - (okH and ground or 0)
            -- coming back to land: seen heading home by the watcher, or already slow and low
            -- (21:02 run: a SEAD flight egressing low past its own base read as on final)
            local returning = InformRadioFlightCalls.headingHome(group)
                or (speed <= R.inbound_max_mps and height <= R.inbound_height_m)
            -- inbound: heading for the field, inside inbound_nm
            if not f.said.inbound and returning and towards and d <= R.inbound_nm * 1852 and d > R.final_km * 1000 then
                f.said.inbound = true
                local runway = InformScreenAirfieldInfo.runwayInUse(f.base)
                say(f.m, "inbound", f.base, u.name, { runway = runway, distance_nm = d / 1852,
                    direction = compass(norm(toField + 180)), flags = flagList({ runway_known = runway ~= nil }) })
            end
            -- final: after inbound, lined up with a runway end, close in, low and at approach
            -- speed, the field ahead (an inbound call is made first, even when it came in fast)
            if not f.said.final and d <= R.final_km * 1000 and (f.said.inbound or returning) then
                local runway, off = InformScreenAirfieldInfo.runwayFor(f.base, heading)
                if runway and off and off <= R.final_aligned_deg and height <= R.final_height_m and towards
                        and speed <= R.final_max_mps then
                    f.said.final = true
                    say(f.m, "final", f.base, u.name, { runway = runway })
                end
            end
        end
    end
end

local function lookAll()
    for group, d in pairs(_departing) do
        local r, l = RecordFlights.facts(group), RecordFlightLaunches.launch(group)
        if not r or r.down or l.stood_down then _departing[group] = nil
        else
            local ok, err = pcall(lookDeparting, group, d)
            if not ok then Log.warn(string.format("airfield calls: %s: %s", group, tostring(err))) end
        end
    end
    for group, f in pairs(_flying) do
        local r = RecordFlights.facts(group)
        if not r or r.down or f.said.clear then _flying[group] = nil
        else
            local ok, err = pcall(lookFlying, group, f)
            if not ok then Log.warn(string.format("airfield calls: %s: %s", group, tostring(err))) end
        end
    end
end

function InformRadioAirfieldCalls.start(plan)
    _plan = plan
    local any = false
    for side in pairs(RADIO_CALLS.coalitions) do any = any or InformRadioRadioCalls.on(side) end
    if not any then return end
    RecordDcsEvents.on(onEvent)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(lookAll)
        if not ok then Log.error("airfield calls: round failed: " .. tostring(err)) end
        return now + RADIO_CALLS.airfield_every_s
    end, nil, timer.getTime() + RADIO_CALLS.airfield_every_s)
    Log.info(string.format("--- Airfield calls: AI traffic at Blue fields on each field's frequency, heard within %d nm ---",
        RADIO_CALLS.airfield_range_nm))
end
