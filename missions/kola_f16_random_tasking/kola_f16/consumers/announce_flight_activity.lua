-- Consumer: AI flights say on the radio what they are doing (roadmap.md item 7, "Flights and
-- airfields talk"): checking in and out with the AWACS, and their mission calls (pushing,
-- Fox, Magnum, Splash, defending, off target) on the mission channel.
--
-- A watcher beside the controller, not part of it: every call comes from what a flight
-- actually does, seen in DCS's events (a shot, a kill, a takeoff, a jet lost) or in where
-- it is (its airspace, heading home, fuel, weapons left), never from the controller's
-- orders, which the DCS AI doesn't always follow (John, 2026-10-05). It reads, never
-- orders: nothing here changes a flight or the plan.
--
--   airborne     (AWACS)    a flight's first jet takes off: "Darkstar, Weasel three one, airborne Rovaniemi, SEAD"
--   on_station   (AWACS)    a patrol reaches its race-track
--   pushing      (mission)  an attack flight reaches its ingress waypoint (SEAD: its first low-level one)
--   fox / magnum / rifle / bombs (mission)  a jet fires (repeats folded: RADIO_CALLS.kinds fold_s)
--   splash       (mission)  a jet kills an aircraft
--   defending    (mission)  a missile is fired at a jet (the jet itself says it)
--   jet_down     (mission)  a jet of the flight is lost, said by another jet still flying
--   winchester / bingo (mission)  weapons gone / fuel low far from home
--   off_target   (mission) and check_out (AWACS)  the flight is seen heading home: pointing at
--                its landing base, closing on it, well nearer home than its farthest point
-- Who talks: each jet by its own callsign (lib/flight_callsigns.lua), so each has its own
-- voice. Players' and AWACS flights don't talk here; only coalitions RADIO_CALLS.coalitions.
-- Event log: RADIO_CALL, one line per call (what, on which channel, by whom).

AnnounceFlightActivity = {}

local _plan
local _flights = {}   -- mission id → { m, side, said = { kind → time }, once = { kind → true }, ... }
local _down = {}      -- unit names already called down

local MISSION_WORDS = {
    suppression_of_air_defenses = "SEAD", destruction_of_air_defenses = "DEAD", strike = "strike",
    airfield_strike = "OCA", interdiction = "interdiction", close_air_support = "CAS",
    combat_air_patrol = "CAP", interception = "intercept",
}

local function norm(deg) return (deg % 360 + 360) % 360 end

local function nameOf(obj)
    local ok, name = pcall(function() return obj:getName() end)
    return ok and name or nil
end

local function groupNameOf(unit)
    local ok, name = pcall(function() return unit:getGroup():getName() end)
    return ok and name or nil
end

-- The mission a group flies (as flown: a late launch or a retry has its own copy), or nil.
local function missionOf(groupName)
    local r = groupName and ScheduleAirTaskingOrders.record(groupName)
    return r and (r.mission_flown or r.mission) or nil
end

local function talks(m)
    return m and m.flown_by ~= "human" and m.callsign and m.mission_type ~= "airborne_early_warning"
        and SendRadioCalls.on(m.coalition)
end

-- Jet `unitName`'s callsign ("Weasel 3-2"), from its number in the group name.
local function jetCallsign(m, unitName)
    local n = tonumber((unitName or ""):match("_(%d+)$") or "1") or 1
    return FlightCallsigns.jet(m, n)
end

local function pos2(p) return { x = p.x, z = p.z } end

local function basePos(name)
    local ab = _plan.world.airbases[name]
    return ab and (ab.anchor or ab.pos)
end

-- The nearest airbase to `pos`: its name.
local function nearestBase(pos)
    local best, bestD
    for name, ab in pairs(_plan.world.airbases) do
        local d = Util.dist(pos, ab.anchor or ab.pos)
        if not bestD or d < bestD then best, bestD = name, d end
    end
    return best
end

-- What the pilot calls the target: "the Koshka Yavr SA-10", "parked aircraft at Vuojarvi".
local function targetWords(m)
    if m.station or not m.target_pos then return nil end
    local base = nearestBase(m.target_pos)
    local label = m.target_label or ""
    local system = label:match("^(.-) site$")
    if system then return string.format("the %s %s", base or "", system) end
    return string.format("%s at %s", label, base or "the target")
end

local function flags(list)
    local out = {}
    for k, v in pairs(list) do if v then out[#out + 1] = k end end
    return out
end

-- Say `kind` for flight `f` by jet `unitName` (nil: its lead), on `channel`, with `facts`;
-- folded when the same kind was said by this flight within its fold_s.
local jetsUp

local function say(f, kind, channel, unitName, facts)
    -- a jet already down doesn't talk (its missile can still kill after it ejected, the
    -- 21:02 run): a jet of its flight still flying says it, or nobody
    if unitName and _down[unitName] then
        unitName = nil
        for _, u in ipairs(jetsUp(f.m.id)) do
            local other = nameOf(u)
            if other and not _down[other] then unitName = other break end
        end
        if not unitName then return end
    end
    local now = timer.getTime()
    local fold = RADIO_CALLS.kinds[kind] and RADIO_CALLS.kinds[kind].fold_s
    if fold and f.said[kind] and now - f.said[kind] < fold then return end
    f.said[kind] = now
    local m = f.m
    facts = facts or {}
    facts.callsign = jetCallsign(m, unitName or (m.id .. "_1"))
    facts.flight = FlightCallsigns.text(m)
    facts.voice_key = facts.callsign
    SendRadioCalls.say(f.side, kind, channel, facts)
    WriteEventLog.add(f.side, "RADIO_CALL", unitName or m.id, string.format("%s on %s by %s%s", kind, channel,
        facts.callsign, facts.target and facts.target ~= "" and (", " .. facts.target)
        or facts.target_type and (", " .. facts.target_type) or facts.kill_type and (", " .. facts.kill_type) or ""))
end

local function sayOnce(f, kind, channel, unitName, facts)
    if f.once[kind] then return end
    f.once[kind] = true
    say(f, kind, channel, unitName, facts)
end

-- ── what a flight is ────────────────────────────────────────────

local function kindOfFlight(m)
    if m.station then return "patrol" end
    if m.mission_type == "suppression_of_air_defenses" then return "sead" end
    if m.mission_type == "interception" then return "intercept" end
    return "attack"
end

local function flightFor(groupName)
    local f = _flights[groupName]
    if f then return f end
    local m = missionOf(groupName)
    if not talks(m) then return nil end
    f = { m = m, side = m.coalition, said = {}, once = {}, kind = kindOfFlight(m) }
    _flights[groupName] = f
    return f
end

-- The flight's jets still alive and in the air, lead first.
jetsUp = function(groupName)
    local out = {}
    local g = Group.getByName(groupName)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okAir, air = pcall(function() return u:isExist() and u:inAir() end)
        if okAir and air then out[#out + 1] = u end
    end
    return out
end

-- ── DCS events ──────────────────────────────────────────────────

local function weaponCall(weapon)
    local ok, d = pcall(function() return weapon:getDesc() end)
    if not ok or not d then return nil end
    if d.category == Weapon.Category.MISSILE then
        if d.missileCategory == Weapon.MissileCategory.AAM then
            if d.guidance == Weapon.GuidanceType.IR then return "fox", 2 end
            if d.guidance == Weapon.GuidanceType.RADAR_SEMI_ACTIVE then return "fox", 1 end
            return "fox", 3
        end
        if d.guidance == Weapon.GuidanceType.RADAR_PASSIVE then return "magnum" end
        return "rifle"
    elseif d.category == Weapon.Category.BOMB then
        return "bombs"
    end
    return nil
end

local function onShot(e)
    if not e.weapon then return end
    local okT, target = pcall(function() return e.weapon:getTarget() end)
    -- a missile fired at one of our jets: that jet is defending
    if okT and target then
        local tGroup = groupNameOf(target)
        local tf = tGroup and flightFor(tGroup)
        local okC, shooterCategory = pcall(function() return e.initiator:getDesc().category end)
        if tf and okC and (shooterCategory == Unit.Category.GROUND_UNIT or shooterCategory == Unit.Category.SHIP
                or shooterCategory == Unit.Category.AIRPLANE or shooterCategory == Unit.Category.HELICOPTER) then
            local sam = shooterCategory == Unit.Category.GROUND_UNIT or shooterCategory == Unit.Category.SHIP
            local okW, weaponCategory = pcall(function() return e.weapon:getDesc().category end)
            if okW and weaponCategory == Weapon.Category.MISSILE then
                say(tf, "defending", "mission", nameOf(target), { threat = sam and "SAM" or "missile",
                    flags = flags({ sam = sam, air = not sam }) })
            end
        end
    end
    local group = groupNameOf(e.initiator)
    local f = group and flightFor(group)
    if not f then return end
    local kind, fox = weaponCall(e.weapon)
    if not kind then return end
    local facts = {}
    if kind == "fox" then
        facts.fox = fox
        local okType, typeName = pcall(function() return target and target:getTypeName() end)
        facts.target_type = okType and typeName or nil
        facts.flags = flags({ target_known = facts.target_type ~= nil, fox_one = fox == 1, fox_two = fox == 2,
                              fox_three = fox == 3 })
    else
        local words = (kind == "magnum") and f.m.target_label and f.m.target_label:match("^(.-) site$")
                      or targetWords(f.m)
        facts.target = words or ""
        facts.flags = flags({ has_target = words ~= nil })
    end
    say(f, kind, "mission", nameOf(e.initiator), facts)
end

local function onKill(e)
    if not e.initiator or not e.target then return end
    local group = groupNameOf(e.initiator)
    local f = group and flightFor(group)
    if not f then return end
    local okC, category = pcall(function() return e.target:getDesc().category end)
    if not okC or (category ~= Unit.Category.AIRPLANE and category ~= Unit.Category.HELICOPTER) then return end
    local okType, typeName = pcall(function() return e.target:getTypeName() end)
    say(f, "splash", "mission", nameOf(e.initiator), { kill_type = okType and typeName or nil,
        flags = flags({ type_known = okType and typeName ~= nil }) })
end

local function onLost(unit, ejected)
    local unitName = nameOf(unit)
    if not unitName or _down[unitName] then return end
    _down[unitName] = true
    local group = groupNameOf(unit) or unitName:match("^(.*)_%d+$")
    local f = group and _flights[group]
    if not f then return end
    for _, u in ipairs(jetsUp(group)) do
        local other = nameOf(u)
        if other and other ~= unitName then
            say(f, "jet_down", "mission", other, { down = jetCallsign(f.m, unitName), flags = flags({ ejected = ejected }) })
            return
        end
    end
end

local function onTakeoff(e)
    local group = groupNameOf(e.initiator)
    local f = group and flightFor(group)
    if not f or f.once.airborne then return end
    local m = f.m
    f.airborne_at = timer.getTime()
    local target = targetWords(m)
    sayOnce(f, "airborne", "awacs", nameOf(e.initiator), {
        base = m.launch_base, count = m.count, mission = MISSION_WORDS[m.mission_type] or "", target = target or "",
        flags = flags({ patrol = f.kind == "patrol", sead = f.kind == "sead", attack = f.kind == "attack",
                        single = m.count == 1, two_ship = m.count >= 2, has_target = target ~= nil }) })
end

local handler = {}
function handler:onEvent(e)
    local ok, err = pcall(function()
        if e.id == world.event.S_EVENT_SHOT then onShot(e)
        elseif e.id == world.event.S_EVENT_KILL then onKill(e)
        elseif e.id == world.event.S_EVENT_TAKEOFF and e.initiator then onTakeoff(e)
        elseif e.id == world.event.S_EVENT_EJECTION and e.initiator then onLost(e.initiator, true)
        elseif (e.id == world.event.S_EVENT_DEAD or e.id == world.event.S_EVENT_CRASH
                or e.id == world.event.S_EVENT_PILOT_DEAD) and e.initiator then onLost(e.initiator, false)
        end
    end)
    if not ok then Log.warn("flight calls: event " .. tostring(e.id) .. " failed: " .. tostring(err)) end
end

-- ── what the flights are doing, looked at every watch_every_s ───

local function distanceToSegment(p, a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local len2 = dx * dx + dz * dz
    local t = len2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / len2)) or 0
    return Util.dist(p, { x = a.x + t * dx, z = a.z + t * dz })
end

local function weaponsAboard(units)
    local n = 0
    for _, u in ipairs(units) do
        local ok, ammo = pcall(function() return u:getAmmo() end)
        for _, a in ipairs(ok and ammo or {}) do
            if a.desc and a.desc.category ~= Weapon.Category.SHELL then n = n + (a.count or 0) end
        end
    end
    return n
end

local function look(groupName, f)
    local R = RADIO_CALLS
    local jets = jetsUp(groupName)
    local lead = jets[1]
    if not lead then return end
    local leadName = nameOf(lead)
    local m = f.m
    local p = pos2(lead:getPoint())
    local v = lead:getVelocity()
    local heading = norm(math.deg(math.atan2(v.z, v.x)))
    local home = basePos(m.landing_base)

    -- on station: a patrol at its race-track
    local station = m.attack and m.attack.station
    local fromStation = station and distanceToSegment(p, { x = station[1], z = station[2] }, { x = station[3], z = station[4] })
    if f.kind == "patrol" and fromStation and fromStation <= R.on_station_km * 1000 then
        sayOnce(f, "on_station", "awacs", leadName, { station = "" })
        f.on_station_seen = true
    end

    -- weapons gone (only once it has had some)
    local aboard = weaponsAboard(jets)
    if aboard > 0 then f.had_weapons = true end
    if f.had_weapons and aboard == 0 then sayOnce(f, "winchester", "mission", leadName) end

    if not home then return end
    local homeKm = Util.dist(p, home) / 1000
    f.farthest_km = math.max(f.farthest_km or 0, homeKm)

    -- bingo: low on fuel, still far from home
    local okFuel, fuel = pcall(function() return lead:getFuel() end)
    if okFuel and fuel and fuel <= R.bingo_fuel and homeKm >= R.bingo_min_home_km then
        sayOnce(f, "bingo", "mission", leadName, { base = m.landing_base })
    end

    -- heading home: pointing at its landing base, closing on it, well back from its farthest point
    local toHome = norm(math.deg(math.atan2(home.z - p.z, home.x - p.x)))
    local off = math.abs((heading - toHome + 180) % 360 - 180)
    local closing = f.last_home_km and (f.last_home_km - homeKm) >= R.rtb_closing_km
    local leftStation = f.kind ~= "patrol" or (f.on_station_seen and fromStation and fromStation > 2 * R.on_station_km * 1000)
    if not f.once.off_target and off <= R.rtb_heading_deg and closing and leftStation
            and f.farthest_km - homeKm >= R.rtb_after_target_km then
        local fl = flags({ patrol = f.kind == "patrol", sead = f.kind == "sead", attack = f.kind == "attack" or f.kind == "intercept" })
        sayOnce(f, "off_target", "mission", leadName, { base = m.landing_base, flags = fl })
        sayOnce(f, "check_out", "awacs", leadName, { base = m.landing_base, flags = fl })
    end
    f.last_home_km = homeKm
end

-- Pushing: the flight has reached the waypoint where its attack run starts, its ingress
-- (a SEAD flight: the first low-level or descent waypoint, where it goes under the radar).
-- Called by the waypoint's script command (SpawnAircraftGroups), so it's where the flight
-- really is. (Until 2026-10-05 late: leaving own airspace, which a flight from a base in
-- contested airspace did on its takeoff roll.)
local PUSH_WAYPOINT = { ingress = true, low = true, descent = true }

function AnnounceFlightActivity.waypoint(groupName, index)
    local ok, err = pcall(function()
        local f = _flights[groupName]
        if not f or f.once.pushing or (f.kind ~= "attack" and f.kind ~= "sead") then return end
        local r = f.m.route and f.m.route[index]
        if not r or not PUSH_WAYPOINT[r.kind] then return end
        local lead = jetsUp(groupName)[1]
        local target = targetWords(f.m)
        sayOnce(f, "pushing", "mission", lead and nameOf(lead), { target = target or "",
            flags = flags({ sead = f.kind == "sead", has_target = target ~= nil }) })
    end)
    if not ok then Log.warn("flight calls: waypoint: " .. tostring(err)) end
end

-- True once flight `groupName` has been seen heading home (its off-target call), for the
-- airfield calls: a flight passing near its base on the way out isn't inbound.
function AnnounceFlightActivity.headingHome(groupName)
    local f = _flights[groupName]
    return f ~= nil and f.once.off_target == true
end

local function lookAll()
    for groupName, f in pairs(_flights) do
        local r = ScheduleAirTaskingOrders.record(groupName)
        if not r or r.down then
            _flights[groupName] = nil
        elseif f.once.airborne then
            local ok, err = pcall(look, groupName, f)
            if not ok then Log.warn(string.format("flight calls: %s: %s", groupName, tostring(err))) end
        end
    end
end

function AnnounceFlightActivity.start(plan)
    _plan = plan
    local any = false
    for side in pairs(RADIO_CALLS.coalitions) do any = any or SendRadioCalls.on(side) end
    if not any then return end
    world.addEventHandler(handler)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(lookAll)
        if not ok then Log.error("flight calls: round failed: " .. tostring(err)) end
        return now + RADIO_CALLS.watch_every_s
    end, nil, timer.getTime() + RADIO_CALLS.watch_every_s)
    Log.info(string.format("--- Flight calls: AI flights check in on %s, mission calls on %s ---",
        SendRadioCalls.channelText("awacs"), SendRadioCalls.channelText("mission")))
end
