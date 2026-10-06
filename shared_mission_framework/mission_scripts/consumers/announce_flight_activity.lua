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
--   on_station   (AWACS)    a patrol reaches its station waypoint (bug 62: not by distance, as a
--                station over its own base was "reached" on the takeoff roll)
--   pushing      (mission)  an attack flight reaches its ingress waypoint (SEAD: its first low-level one)
--   fox / magnum / rifle / bombs (mission)  a jet fires (repeats folded: RADIO_CALLS.kinds fold_s)
--   splash       (mission)  a jet kills an aircraft
--   defending    (mission)  a missile is fired at a jet (the jet itself says it)
--   jet_down     (mission)  a jet of the flight is lost, said by another jet still flying
--   winchester / bingo (AWACS: reports to the controller)  weapons gone / fuel low far from
--                home; bingo only for flights the controller doesn't watch for fuel (its
--                bingo is the pilot's report, announce_controller_orders.lua), and neither
--                once the pilot has reported it
--   off_target   (mission) and check_out (AWACS)  the flight is seen heading home: pointing at
--                its landing base, closing on it, well nearer home than its farthest point;
--                a patrol once it has left its station (sent home by the controller, or its
--                orbit over: its off-station waypoint) and is seen heading home, however close
--                its station is to its base (bug 62). No check-out once the flight has
--                answered an RTB or reported going home: that was its check-out.
--   answer       (AWACS)  the flight's answer to Darkstar's order (roadmap item 7 step 15),
--                once it is seen following it (RADIO_CALLS.answers): an engage when it fires
--                at the bandit or turns toward it closing; resume when it turns back to its
--                route (or home); RTB / land when it points home two looks running; a
--                scramble's vector when it turns toward its raid. Not seen in time: no answer
--                (event log "no answer"); a newer order replaces one not yet answered. The
--                orders are heard as said (SendRadioCalls.onCall), never from the controller.
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

-- A unit's name, or nil. A map object (a building a bomb destroyed) is named by a number,
-- so only text counts (bug 66: "attempt to index local 'unitName' (a number value)").
local function nameOf(obj)
    local ok, name = pcall(function() return obj:getName() end)
    return ok and type(name) == "string" and name or nil
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

-- True when the controller watches the flight's fuel (patrols, scrambles): its bingo is
-- the controller's decision, said as the pilot's report (announce_controller_orders.lua).
local function fuelWatched(m)
    for _, name in ipairs(AIR_CONTROL.directives_by_mission_type[m.mission_type] or {}) do
        if name == "fuel" then return true end
    end
    return false
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

-- ── answers to Darkstar's orders ────────────────────────────────

local ORDER_KINDS = { engage = "engage", return_to_base = "rtb", land_at = "land", scramble_vector = "vector" }

local function has(list, word)
    for _, w in ipairs(list or {}) do if w == word then return true end end
    return false
end

-- The first jet of group `name` still there (in the air or not), or nil.
local function firstAlive(name)
    local g = Group.getByName(name)
    local ok, units = pcall(function() return g and g:getUnits() end)
    for _, u in ipairs(ok and units or {}) do
        local okE, e = pcall(function() return u:isExist() end)
        if okE and e then return u end
    end
    return nil
end

-- How far jet u's nose is off the line to `pos`, degrees; and how far away it is, m.
local function offLine(u, pos)
    local p, v = u:getPoint(), u:getVelocity()
    local heading = norm(math.deg(math.atan2(v.z, v.x)))
    local to = norm(math.deg(math.atan2(pos.z - p.z, pos.x - p.x)))
    return math.abs((heading - to + 180) % 360 - 180), Util.dist(pos2(p), pos)
end

-- A call written (SendRadioCalls.onCall): Darkstar's order to one of our flights waits for
-- its answer; a pilot's report (bingo, Magnum complete …) was its check-out, its bingo or
-- its Winchester, and ends any order still waiting.
local function callHeard(_, call)
    local f = call.group and flightFor(call.group)
    if not f then return end
    if call.call == "report" then
        f.pending = nil
        if has(call.flags, "rtb") or has(call.flags, "on_way_home") then f.once.check_out = true end
        if has(call.flags, "bingo") then f.once.bingo = true end
        if has(call.flags, "salvo_complete") or has(call.flags, "out_of_missiles") then f.once.winchester = true end
        return
    end
    local what = ORDER_KINDS[call.call]
    if call.call == "resume" then what = has(call.flags, "on_way_home") and "resume_home" or "resume_mission" end
    if not what then return end
    -- an order to one jet ("Weasel 1-2") is answered by that jet
    local n = call.callsign ~= call.flight and tonumber((call.callsign or ""):match("%-(%d+)$") or "")
    f.pending = { order = call.call, what = what, id = call.id, at = timer.getTime(), priority = call.priority,
                  bandit = call.bandit, bandit_type = call.call == "engage" and call.bandit_type or nil,
                  addressee = call.callsign,
                  unit = n and (call.group .. "_" .. n) or nil, looks = 0 }
end

-- The answer, by the flight's callsign (or the one jet the order was to) in the voice of
-- the jet saying it.
local function answer(f)
    local p, m = f.pending, f.m
    f.pending = nil
    local jet = p.unit
    if not jet then
        local lead = jetsUp(m.id)[1]
        jet = lead and nameOf(lead)
    end
    if not jet or _down[jet] then return end
    local facts = { callsign = p.addressee or FlightCallsigns.text(m), flight = FlightCallsigns.text(m),
                    voice_key = jetCallsign(m, jet), group = m.id, answers = p.id, priority = p.priority,
                    base = m.landing_base, bandit_type = p.bandit_type,
                    flags = flags({ [p.what] = true, type_known = p.bandit_type ~= nil }) }
    SendRadioCalls.say(f.side, "answer", "awacs", facts)
    WriteEventLog.add(f.side, "RADIO_CALL", jet, string.format("answer on awacs by %s to %s, %s (%d s after the order)",
        facts.callsign, RADIO_CALLS.awacs_callsign[f.side] or "AWACS", p.order, math.floor(timer.getTime() - p.at + 0.5)))
    -- "copy, RTB" is how a flight leaves the controller: its check-out
    if p.what == "rtb" or p.what == "resume_home" or p.what == "land" then f.once.check_out = true end
end

-- True once the flight is seen doing what it was told.
local function following(f, p)
    local A = RADIO_CALLS.answers
    local m = f.m
    local u = p.unit and Unit.getByName(p.unit) or jetsUp(m.id)[1]
    local okAir, air = pcall(function() return u and u:isExist() and u:inAir() end)
    if not (okAir and air) then return false end
    if p.what == "engage" or p.what == "vector" then
        -- toward the bandit (an engage also closing on it; a shot at it answers at once, onShot)
        local b = p.bandit and firstAlive(p.bandit)
        if not b then return false end
        local off, d = offLine(u, pos2(b:getPoint()))
        local closing = p.last_m ~= nil and d < p.last_m
        p.last_m = d
        return off <= A.toward_deg and (p.what == "vector" or closing)
    elseif p.what == "resume_mission" then
        -- back toward one of its next two waypoints
        local route, i = m.route or {}, f.last_waypoint or 1
        for k = i + 1, i + 2 do
            local r = route[k]
            if r and r.x and offLine(u, { x = r.x, z = r.z }) <= A.route_deg then return true end
        end
        return false
    end
    -- RTB, continue RTB, land: pointing home, looks in a row
    local home = basePos(m.landing_base)
    if not home then return false end
    p.looks = offLine(u, home) <= A.home_deg and p.looks + 1 or 0
    return p.looks >= A.home_looks
end

local function answerRound()
    local now = timer.getTime()
    for _, f in pairs(_flights) do
        local p = f.pending
        if p then
            local ok, yes = pcall(following, f, p)
            local within = RADIO_CALLS.answers.within_s[p.order] or 30
            if not ok then
                f.pending = nil
                Log.warn(string.format("flight calls: answer for %s: %s", f.m.id, tostring(yes)))
            elseif yes then
                answer(f)
            elseif now - p.at >= within then
                f.pending = nil
                WriteEventLog.add(f.side, "RADIO_CALL", f.m.id, string.format("no answer to %s from %s: not seen following it in %d s",
                    p.order, p.addressee or FlightCallsigns.text(f.m), within))
            end
        end
    end
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
    -- a shot at the bandit it was told to engage: "committing" first, then the Fox
    local p = f.pending
    if kind == "fox" and p and p.what == "engage" and okT and target and groupNameOf(target) == p.bandit then
        answer(f)
    end
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
    -- a scramble names its raid by type, worded by the helper as the other calls do
    -- ("intercept, Fullback"; bug 65: "intercept on Su-34 at Ivalo", the DCS type name)
    local intercept = f.kind == "intercept"
    local raidType = intercept and m.target_label ~= "type unknown" and m.target_label or nil
    local target = not intercept and targetWords(m) or nil
    sayOnce(f, "airborne", "awacs", nameOf(e.initiator), {
        base = m.launch_base, count = m.count, mission = MISSION_WORDS[m.mission_type] or "", target = target or "",
        target_type = raidType,
        flags = flags({ patrol = f.kind == "patrol", sead = f.kind == "sead", attack = f.kind == "attack",
                        intercept = intercept, type_known = raidType ~= nil,
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

    -- weapons gone (only once it has had some)
    local aboard = weaponsAboard(jets)
    if aboard > 0 then f.had_weapons = true end
    if f.had_weapons and aboard == 0 then sayOnce(f, "winchester", "awacs", leadName) end

    if not home then return end
    local homeKm = Util.dist(p, home) / 1000
    f.farthest_km = math.max(f.farthest_km or 0, homeKm)

    -- bingo: low on fuel, still far from home (a flight the controller watches for fuel
    -- reports it when the controller sends it home)
    local okFuel, fuel = pcall(function() return lead:getFuel() end)
    if not fuelWatched(m) and okFuel and fuel and fuel <= R.bingo_fuel and homeKm >= R.bingo_min_home_km then
        sayOnce(f, "bingo", "awacs", leadName, { base = m.landing_base })
    end

    -- heading home: pointing at its landing base, closing on it, well back from its farthest
    -- point; a patrol once it has left its station, whose race-track may lie over its own
    -- base (bug 62: Viper 5 at Alakurtti never got far enough from it to check out)
    local toHome = norm(math.deg(math.atan2(home.z - p.z, home.x - p.x)))
    local off = math.abs((heading - toHome + 180) % 360 - 180)
    local closing = f.last_home_km and (f.last_home_km - homeKm) >= R.rtb_closing_km
    local wentHome
    if f.kind == "patrol" then
        wentHome = f.left_station
    else
        wentHome = f.farthest_km - homeKm >= R.rtb_after_target_km
    end
    if not f.once.off_target and off <= R.rtb_heading_deg and closing and wentHome then
        local fl = flags({ patrol = f.kind == "patrol", sead = f.kind == "sead", attack = f.kind == "attack",
                           intercept = f.kind == "intercept" })
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
-- the controller's decisions that send a flight home (ControlAirFlights.say)
local SENT_HOME = { handover = true, bingo = true, ["leash home"] = true, ["go cold"] = true, leave = true, land = true }

-- A patrol says it is on station at its station waypoint, and has left it at its
-- off-station waypoint (its orbit is over), also told by the waypoint's script command.
function AnnounceFlightActivity.waypoint(groupName, index)
    local ok, err = pcall(function()
        local f = _flights[groupName]
        local r = f and f.m.route and f.m.route[index]
        if not r then return end
        f.last_waypoint = index   -- where "back to its route" points (an answer to resume)
        local lead = jetsUp(groupName)[1]
        if f.kind == "patrol" then
            if r.kind == "station" then
                sayOnce(f, "on_station", "awacs", lead and nameOf(lead), { station = "" })
            elseif r.kind == "station_end" then
                f.left_station = true
            end
            return
        end
        if f.once.pushing or (f.kind ~= "attack" and f.kind ~= "sead") or not PUSH_WAYPOINT[r.kind] then return end
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
    -- a patrol sent home has left its station; its check-out still waits until it is seen
    -- heading home (an order the DCS AI ignores gets no call)
    ControlAirFlights.onDecision(function(d)
        local f = _flights[d.subject]
        if f and f.kind == "patrol" and SENT_HOME[d.decision] then f.left_station = true end
    end)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(lookAll)
        if not ok then Log.error("flight calls: round failed: " .. tostring(err)) end
        return now + RADIO_CALLS.watch_every_s
    end, nil, timer.getTime() + RADIO_CALLS.watch_every_s)
    -- Darkstar's orders as said, and the pilots' reports: answers wait for the flight
    SendRadioCalls.onCall(callHeard)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(answerRound)
        if not ok then Log.error("flight calls: answer round failed: " .. tostring(err)) end
        return now + RADIO_CALLS.answers.every_s
    end, nil, timer.getTime() + RADIO_CALLS.answers.every_s)
    Log.info(string.format("--- Flight calls: AI flights check in on %s, mission calls on %s ---",
        SendRadioCalls.channelText("awacs"), SendRadioCalls.channelText("mission")))
end
