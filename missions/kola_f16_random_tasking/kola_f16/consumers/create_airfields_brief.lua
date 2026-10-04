-- Consumer: a short brief for every Blue airfield in Blue's comms menu (\ > F10. Other...),
-- so a player can land and turn around at any base, not only the one they spawned at
-- (roadmap.md item 13, John, 2026-10-02):
--   Airfield info > <base>      one text per base, built when it's opened:
--
--   BANAK (BANA): Blue, front, dispersal field, elevation 25 ft
--   Wind 240° 12 kt → runway 34 in use (headwind 6 kt, crosswind 10 kt from the left)
--   Runway 16/34, 2,462 m (8,077 ft)
--   Next out: 09:40 MSN2025 SEAD, 2x F-16C_50 (planned)
--   Next in:  09:55 MSN2009 CAP, 1x F-15C (airborne)
--   Alert: 2 of 3 jets ready
--
-- Bases are listed in alphabetical order by their DCS name, paged as the other menus.
-- Wind: measured at the base (atmosphere.getWind 10 m above the field), the direction it
-- blows from. Wind and runway numbers are magnetic (the variation as the air picture gets
-- it, CallAirPicture.magneticVariation). The runway in use is the runway end with the most
-- headwind (the longer runway on a tie); under CALM_KTS it's "calm". DCS has no call
-- that says which runway its ATC uses, so this is our pick from the wind.
-- Next out: the AI flight from this base whose takeoff comes next and that hasn't taken off
-- yet (planned, delayed, or on the ramp); next in: the AI flight in the air that is due
-- back here soonest (its planned landing time). Human flights and scrambles aren't listed;
-- the alert line covers the scrambles. A line with no flight is left out.
-- Reads the plan; writes nothing back to it.

CreateAirfieldsBrief = {}

local MESSAGE_S      = 60    -- how long the text stays on screen
local MENU_PAGE      = 9     -- entries per comms submenu (the menu shows 10 at most)
local CALM_KTS       = 3     -- under this, no runway is favoured by the wind
local WIND_HEIGHT_M  = 10    -- the wind is measured this high above the field
local FEET_PER_METRE = 3.28084
local MPS_TO_KTS     = 1.94384
local COALITION      = "blue"

local CLASS_NAME = {
    hub = "main base", fighter = "fighter base", bomber = "bomber base", heli = "helicopter base",
    dispersal = "dispersal field", strip = "short strip",
}

local _plan

-- ── formatting ──────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

local function norm(deg) return (deg % 360 + 360) % 360 end

-- 8077 → "8,077"
local function thousands(n)
    local s = tostring(round(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function at(t) return Weather.hhmm(_plan.world.time.start_local + t) end

-- ── directions ──────────────────────────────────────────────────

-- How far true north is from grid north at pos, degrees: a grid heading + this = true.
-- (The map's grid north is off true north by several degrees toward its edges.)
local function gridToTrue(pos)
    local lat1, lon1 = coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
    local lat2, lon2 = coord.LOtoLL({ x = pos.x + 1000, y = 0, z = pos.z })
    local p1, p2 = math.rad(lat1), math.rad(lat2)
    local dl = math.rad(lon2 - lon1)
    local y = math.sin(dl) * math.cos(p2)
    local x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.deg(math.atan2(y, x))
end

-- A grid heading at the base → magnetic, degrees 0–360.
local function magnetic(gridDeg, field)
    return norm(gridDeg + field.grid_to_true - field.variation)
end

-- A magnetic heading → its runway number, 1–36.
local function runwayNumber(magDeg)
    local n = round(magDeg / 10) % 36
    return n == 0 and 36 or n
end

-- ── what the base is ────────────────────────────────────────────

-- The fixed facts of a base, worked out once at start.
local function fieldFacts(name)
    local ab = _plan.world.airbases[name]
    local pos = ab.anchor or ab.pos
    local lat, lon = coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
    local field = {
        name = name, pos = pos,
        code = AIRBASE_CODE and AIRBASE_CODE[name],
        class = AIRBASE_CLASS[name],
        echelon = _plan.territory.bases[name] and _plan.territory.bases[name].echelon,
        elevation_m = land.getHeight({ x = pos.x, y = pos.z }),
        grid_to_true = gridToTrue(pos),
        variation = CallAirPicture.magneticVariation(lat, lon),
        runways = {},
    }
    for _, rw in ipairs(ab.runways or {}) do
        -- each runway's two ends, as headings a jet lands on
        local a, b = rw.heading_deg, norm(rw.heading_deg + 180)
        local na, nb = runwayNumber(magnetic(a, field)), runwayNumber(magnetic(b, field))
        if nb < na then a, b, na, nb = b, a, nb, na end
        field.runways[#field.runways + 1] = { length = rw.length, ends = { { heading = a, number = na }, { heading = b, number = nb } } }
    end
    return field
end

-- The wind at the base now: { from_grid, kts }. From the mission's weather if the
-- measurement fails.
local function windAt(field)
    local p = { x = field.pos.x, y = field.elevation_m + WIND_HEIGHT_M, z = field.pos.z }
    local ok, v = pcall(atmosphere.getWind, p)
    if ok and v then
        local mps = math.sqrt(v.x * v.x + v.z * v.z)
        return { from_grid = norm(math.deg(math.atan2(v.z, v.x)) + 180), kts = mps * MPS_TO_KTS }
    end
    local w = _plan.world.weather.wind.ground
    return { from_grid = w.from_deg, kts = w.kts }
end

-- "Wind 240° 12 kt → runway 34 in use (headwind 6 kt, crosswind 10 kt from the left)"
local function windLine(field)
    local wind = windAt(field)
    if wind.kts < CALM_KTS then
        return string.format("Wind calm (%d kt) → %s", round(wind.kts), #field.runways > 1 and "any runway" or "either runway")
    end
    local text = string.format("Wind %03d° %d kt", round(magnetic(wind.from_grid, field)) % 360, round(wind.kts))
    local best
    for _, rw in ipairs(field.runways) do
        for _, e in ipairs(rw.ends) do
            local off = math.rad(wind.from_grid - e.heading)
            local head, cross = wind.kts * math.cos(off), wind.kts * math.sin(off)
            if not best or head > best.head + 0.5 or (math.abs(head - best.head) <= 0.5 and rw.length > best.length) then
                best = { number = e.number, head = head, cross = cross, length = rw.length }
            end
        end
    end
    if not best then return text end
    local crossText = round(math.abs(best.cross)) == 0 and "no crosswind"
        or string.format("crosswind %d kt from the %s", round(math.abs(best.cross)), best.cross > 0 and "right" or "left")
    return string.format("%s → runway %02d in use (headwind %d kt, %s)", text, best.number, round(best.head), crossText)
end

-- ── the flights ─────────────────────────────────────────────────

-- How many jets of flight `id` are in the air now, and how many exist.
local function jetsUp(id)
    local g = Group.getByName(id)
    if not g then return 0, 0 end
    local ok, units = pcall(function() return g:getUnits() end)
    if not ok or not units then return 0, 0 end
    local up, alive = 0, 0
    for _, u in ipairs(units) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then up = up + 1 end
        local okLive, live = pcall(function() return u:isExist() end)
        if okLive and live then alive = alive + 1 end
    end
    return up, alive
end

-- Every AI flight of the coalition as { id, mission (as flown), record }: the planned ones
-- and their second and third tries (<id>_AGAIN, <id>_LATER).
local function flights()
    local out = {}
    local ato = _plan.air_tasking_orders[COALITION]
    for _, m in ipairs(ato and ato.missions or {}) do
        local f = ScheduleAirTaskingOrders.record(m.id)
        if f and m.flown_by ~= "human" then
            out[#out + 1] = { id = m.id, mission = f.mission_flown or f.mission, record = f }
        end
        for _, copyId in ipairs({ f and f.again or false, f and f.later or false }) do
            local copy = copyId and ScheduleAirTaskingOrders.record(copyId)
            if copy then out[#out + 1] = { id = copyId, mission = copy.mission, record = copy } end
        end
    end
    return out
end

-- The next flight out of and the next one into the base: { flight, state } each, or nil.
local function nextFlights(name)
    local out, into
    for _, fl in ipairs(flights()) do
        local m, f = fl.mission, fl.record
        local gone = f.down or f.stood_down or f.note == "cancelled" or f.note == "not needed"
        if not gone then
            local up, alive = 0, 0
            if f.spawned then up, alive = jetsUp(fl.id) end
            local onRamp = f.spawned and up == 0 and alive > 0 and f.landed == 0
            if m.launch_base == name and (not f.spawned or onRamp) then
                if not out or m.takeoff_s < out.mission.takeoff_s then
                    out = { id = fl.id, mission = m, state = onRamp and "on the ramp" or ScheduleAirTaskingOrders.statusOf(fl.id) }
                end
            elseif m.landing_base == name and f.spawned and up > 0 then
                if not into or m.end_s < into.mission.end_s then
                    into = { id = fl.id, mission = m, state = ScheduleAirTaskingOrders.statusOf(fl.id) }
                end
            end
        end
    end
    return out, into
end

-- "09:40 MSN2025 SEAD, 2x F-16C_50 (planned)"
local function flightText(fl, t)
    local m = fl.mission
    local number = fl.id:match("^MSN%d+") or fl.id
    if fl.id:match("_AGAIN$") then number = number .. " again" end
    if fl.id:match("_LATER$") then number = number .. " later" end
    return string.format("%s %s %s, %dx %s (%s)", at(t), number, BriefAirTasking.missionName(m.mission_type),
        m.count, m.aircraft_type, fl.state)
end

-- "Alert: 2 of 3 jets ready, 1 turning around (next in 12 min)" or "not an alert base".
local function alertLine(name)
    local posture = TrackAlertJets.posture(COALITION)
    for _, b in ipairs(posture and posture.bases or {}) do
        if b.base == name then
            local ready, returning, backIn = TrackAlertJets.ready(COALITION, name, timer.getTime())
            local text = string.format("Alert: %d of %d jets ready", ready or 0, b.alert_aircraft)
            if returning and returning > 0 then
                text = text .. string.format(", %d turning around (next in %d min)", returning, math.ceil(backIn / 60))
            end
            return text
        end
    end
    return "Alert: not an alert base"
end

-- ── the text ────────────────────────────────────────────────────

local function fieldText(field)
    local lines = {
        string.format("%s%s: Blue, %s, %s, elevation %s ft", field.name:upper(),
            field.code and (" (" .. field.code .. ")") or "", field.echelon or "?",
            CLASS_NAME[field.class] or field.class or "field", thousands(field.elevation_m * FEET_PER_METRE)),
        windLine(field),
    }
    for _, rw in ipairs(field.runways) do
        lines[#lines + 1] = string.format("Runway %02d/%02d, %s m (%s ft)", rw.ends[1].number, rw.ends[2].number,
            thousands(rw.length), thousands(rw.length * FEET_PER_METRE))
    end
    if #field.runways == 0 then lines[#lines + 1] = "No runway data" end
    local out, into = nextFlights(field.name)
    if out then lines[#lines + 1] = "Next out: " .. flightText(out, out.mission.takeoff_s) end
    if into then lines[#lines + 1] = "Next in:  " .. flightText(into, into.mission.end_s) end
    if not out and not into then lines[#lines + 1] = "No AI flights due out or in" end
    lines[#lines + 1] = alertLine(field.name)
    return table.concat(lines, "\n")
end

local function show(side, text)
    trigger.action.outTextForCoalition(side, text, MESSAGE_S, true)
end

-- The Airfield info menu: every Blue base, alphabetical, MENU_PAGE per submenu.
function CreateAirfieldsBrief.start(plan)
    _plan = plan
    local ato = plan.air_tasking_orders
    if not ato or ato.problems or not ato[COALITION] then return end
    local side = coalition.side.BLUE
    local fields = {}
    for _, name in ipairs(plan.world.airbase_list) do   -- sorted by DCS name
        local b = plan.territory.bases[name]
        if b and b.side == COALITION then
            local ok, field = pcall(fieldFacts, name)
            if ok then fields[#fields + 1] = field
            else Log.warn(string.format("airfield brief: %s left out: %s", name, tostring(field))) end
        end
    end
    if #fields == 0 then return end
    local menu = missionCommands.addSubMenuForCoalition(side, "Airfield info")
    local pages = math.ceil(#fields / MENU_PAGE)
    for p = 1, pages do
        local sub = menu
        if pages > 1 then
            sub = missionCommands.addSubMenuForCoalition(side, string.format("%s–%s",
                fields[(p - 1) * MENU_PAGE + 1].name, fields[math.min(p * MENU_PAGE, #fields)].name), menu)
        end
        for i = (p - 1) * MENU_PAGE + 1, math.min(p * MENU_PAGE, #fields) do
            local field = fields[i]
            missionCommands.addCommandForCoalition(side, field.name, sub, function()
                local ok, text = pcall(fieldText, field)
                if ok then show(side, text)
                else Log.warn(string.format("airfield brief: %s: %s", field.name, tostring(text))) end
            end)
        end
    end
    Log.info(string.format("--- Airfield info: %d Blue bases in the comms menu ---", #fields))
end
