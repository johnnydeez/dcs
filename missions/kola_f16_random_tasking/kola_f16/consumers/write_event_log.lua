-- Consumer: the event log — every event of the air war in plain language, unit by unit,
-- in a file of its own per mission run (roadmap.md item 3). Watch it live while the
-- mission runs, or comb through it afterwards: grep a unit or flight name for its whole
-- story, from spawn to landing or loss, including the lines where others shot at it.
--
-- The file: missions\kola_f16_random_tasking\event_logs\<wall-clock date and time>.log in the
-- repository (git-ignored; EVENT_LOG.folder), else Saved Games\DCS\kola_event_logs\
--   1. the plan: territory, weather, SAM sites, alert bases, the air tasking order,
--      convoys — what was intended, to read the timeline against
--   2. the timeline, one line per event:
--        14:43:12  T+00:43:12  BLUE  TAKEOFF      MSN2014_DEAD_1             F-16C_50, from Rovaniemi
--      local clock, time since mission start, coalition, event word, subject, details
--   3. a summary when the mission ends: flights, losses by cause, ground losses, and
--      each flight's outcome
--
-- Event words (grep them): SPAWNED LOADOUT TAKEOFF WAYPOINT LAND POSITION SHOT GUNS HIT
-- DESTROYED CRASHED EJECTED PILOT_DEAD PARACHUTE ABORTED TARGET CONTACT TRACKING PICTURE
-- SCRAMBLE NO_SCRAMBLE STOOD_DOWN ALERT LEASH PLAYER_IN PLAYER_OUT
--
-- The DCS events (shots, hits, kills, takeoffs, landings, …) are caught here for every
-- unit. The other modules hand their own events over with WriteEventLog.add: the flight
-- spawner (SPAWNED, LOADOUT, and WAYPOINT through a script command on each waypoint),
-- the scheduler (TARGET), the radar picture, scrambles and the leash.
--
-- Cheap on purpose: a DCS event only builds a line into memory. Lines are held
-- EVENT_LOG.hold_s so repeats fold into one (a burst of gun hits, a stick of bombs, a
-- kill that arrives just after the death), and are written to disk every
-- EVENT_LOG.write_every_s in one write. The only polling is the POSITION line for each
-- airborne aircraft every EVENT_LOG.position_every_s.
-- Reads the plan; writes nothing back to it.

WriteEventLog = {}

local FEET_PER_METRE = 3.28084
local KNOTS_PER_MPS = 1.94384
local SIDE_LABEL = { [0] = "NEUT", [1] = "RED", [2] = "BLUE" }
local SIDE_OF = { red = 1, blue = 2 }
local MISSION_NAME = {
    strike = "strike", airfield_strike = "airfield strike", destruction_of_air_defenses = "DEAD",
    suppression_of_air_defenses = "SEAD", combat_air_patrol = "CAP", airborne_early_warning = "AWACS",
    interception = "scramble", interdiction = "interdiction", close_air_support = "close air support",
}
local WAYPOINT_LABEL = {
    departure = "departure", transit = "transit", descent = "descent",
    ingress = "ingress, pushing: attack tasks active", target = "target", egress = "egress, off target",
    station = "on station", station_end = "off station", intercept = "intercept point",
}

local _plan
local _file, _path
local _pending = {}     -- lines not written yet, oldest first
local _folds = {}       -- fold key → a pending line repeats fold into
local _deaths = {}      -- unit or object name → its DESTROYED line (each is reported once)
local _flights = {}     -- group name → mission (planned, or spawned at run time)
local _launched = { red = 0, blue = 0 }
local _stations = {}    -- station id → station
local _ended = false

-- ── small helpers ───────────────────────────────────────────────

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function nameOf(o)   return o and safe(function() return o:getName() end) end
local function typeOf(o)   return o and safe(function() return o:getTypeName() end) end
local function sideOf(o)   return o and safe(function() return o:getCoalition() end) end
local function playerOf(o) return o and safe(function() return o.getPlayerName and o:getPlayerName() end) end
local function groupOf(o)  return o and safe(function() return o:getGroup():getName() end) end

local function isUnit(o)
    return o and safe(function() return o:getCategory() == Object.Category.UNIT end) == true
end

local function isAircraft(o)
    return isUnit(o) and safe(function() return o:getDesc().category <= Unit.Category.HELICOPTER end) == true
end

local function isNamedThing(o)
    return o and safe(function()
        local c = o:getCategory()
        return c == Object.Category.UNIT or c == Object.Category.STATIC
    end) == true
end

-- "MSN5901_SCRAM_1 (Su-30)", with the player's name when a player flies it
local function who(o)
    if not o then return "unknown" end
    local text = string.format("%s (%s)", nameOf(o) or "?", typeOf(o) or "?")
    local player = playerOf(o)
    if player then text = text .. ", player " .. player end
    return text
end

local function coalitionName(side)
    return side == 1 and "red" or side == 2 and "blue" or nil
end

local function clock(t)
    local s = math.floor((_plan and _plan.world.time.start_local or 0) + t) % 86400
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

local function elapsed(t)
    local s = math.floor(t)
    return string.format("T+%02d:%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

-- Where an aircraft of `side` is: altitude, airspace, and the enemy medium / long-range
-- SAM ring it is inside, or the nearest one.
local function whereIs(u, side)
    local p = u and safe(function() return u:getPoint() end)
    if not p then return nil end
    local c = coalitionName(side or sideOf(u))
    local text = string.format("%s ft", Util.thousands(p.y * FEET_PER_METRE))
    if not c or not _plan then return text end
    local pos = { x = p.x, z = p.z }
    local nearest, edge
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= c and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0 then
            local d = Util.dist(pos, s.pos) - s.engage_m
            if not edge or d < edge then nearest, edge = s.id, d end
        end
    end
    text = text .. string.format(", %s airspace", DivideAirspace.kindFor(_plan.airspace, pos, c))
    if nearest then
        text = text .. string.format(", %.0f km %s %s", math.abs(edge) / 1000, edge < 0 and "inside" or "outside", nearest)
    end
    return text
end

-- ── lines ───────────────────────────────────────────────────────

local function render(e)
    local details = e.render and e.render(e) or e.details or ""
    return string.format("%s  %s  %-4s  %-11s  %-" .. EVENT_LOG.subject_width .. "s  %s",
        clock(e.t), elapsed(e.t), e.side or "", e.event, e.subject or "", details)
end

-- A new line at mission time now. `side` is "red" / "blue" or a DCS coalition number.
local function push(side, event, subject, details, fields)
    local label = type(side) == "number" and SIDE_LABEL[side] or (side and side:upper()) or ""
    local e = { t = timer.getTime(), side = label, event = event, subject = subject, details = details }
    for k, v in pairs(fields or {}) do e[k] = v end
    _pending[#_pending + 1] = e
    return e
end

-- The pending line under `key` if the last repeat was within `window` seconds (its count
-- goes up), else a new line from make().
local function fold(key, window, make)
    local now = timer.getTime()
    local e = _folds[key]
    if e and not e.written and now - e.last <= window then
        e.count, e.last = e.count + 1, now
        return e
    end
    e = make()
    e.count, e.last = 1, now
    _folds[key] = e
    return e
end

local function writeText(text)
    if _file then
        _file:write(text)
        _file:flush()
    else
        for line in text:gmatch("[^\n]+") do Log.info("event: " .. line) end
    end
end

-- Write every line held long enough (or all of them); lines are pending in time order.
local function writeOut(all)
    local cutoff = timer.getTime() - EVENT_LOG.hold_s
    local n = 0
    while n < #_pending and (all or _pending[n + 1].t <= cutoff) do n = n + 1 end
    if n == 0 then return end
    local lines = {}
    for i = 1, n do
        local e = _pending[i]
        e.written = true
        lines[i] = render(e)
    end
    local rest = {}
    for i = n + 1, #_pending do rest[#rest + 1] = _pending[i] end
    _pending = rest
    for key, e in pairs(_folds) do
        if e.written then _folds[key] = nil end
    end
    writeText(table.concat(lines, "\n") .. "\n")
end

-- ── what other modules hand over ────────────────────────────────

-- One line now: coalition ("red" / "blue"), event word, subject (a unit or group name),
-- details in plain words.
function WriteEventLog.add(coalition, event, subject, details)
    push(coalition, event, subject, details)
end

-- "F-16C_50 2x DEAD from Kittila on SAM_BANA_SA15_1 (SA-15 site), TOT 08:32, PKG2025";
-- without the TOT when `noTot` (the plan table has its own column)
local function missionText(m, noTot)
    local text = string.format("%s %dx %s from %s", m.aircraft_type, m.count, MISSION_NAME[m.mission_type] or m.mission_type,
        m.launch_base)
    if m.station then
        local st = _stations[m.station]
        text = text .. string.format(", station %s%s", m.station, st and st.label and (" (" .. st.label .. ")") or "")
    elseif m.escorts then
        text = text .. string.format(", escorting %s, engaging %s", m.escorts, table.concat(m.suppresses or {}, ", "))
    elseif m.target then
        text = text .. string.format(" on %s (%s)", m.target, m.target_label or "?")
    end
    if m.tot_s and not m.station and not noTot then text = text .. ", TOT " .. clock(m.tot_s):sub(1, 5) end
    if m.package and not m.station then text = text .. ", " .. m.package end
    return text
end

-- A flight has spawned (SpawnAircraftGroups): its line, and it is known by name from now.
function WriteEventLog.spawned(m, runway)
    _flights[m.id] = m
    _launched[m.coalition] = (_launched[m.coalition] or 0) + 1
    push(m.coalition, "SPAWNED", m.id, string.format("%s; %s", missionText(m),
        runway and "on the runway" or (m.mission_type == "interception" and "hot on the ramp" or "on the ramp")))
end

-- A flight reached waypoint `index` of its planned route (a script command on the
-- waypoint, added by SpawnAircraftGroups).
function WriteEventLog.waypoint(groupName, index)
    local ok, err = pcall(function()
        local m = _flights[groupName]
        local r = m and m.route[index]
        if not r then return end
        local text = string.format("%d of %d: %s", index, #m.route, WAYPOINT_LABEL[r.kind] or r.kind)
        if r.kind == "target" and m.tot_s then
            local late = timer.getTime() - m.tot_s
            text = text .. string.format(", TOT planned %s, %s", clock(m.tot_s):sub(1, 5),
                math.abs(late) < 60 and "on time"
                or string.format("%d min %s", math.floor(math.abs(late) / 60 + 0.5), late > 0 and "late" or "early"))
        end
        local g = Group.getByName(groupName)
        local units = g and safe(function() return g:getUnits() end) or {}
        local lead = units[1]
        local where = lead and whereIs(lead, SIDE_OF[m.coalition])
        if where then text = text .. string.format("; lead %s", where) end
        text = text .. string.format("; %d aircraft", #units)
        push(m.coalition, "WAYPOINT", groupName, text)
    end)
    if not ok then Log.warn("event log: waypoint line failed: " .. tostring(err)) end
end

-- ── DCS events ──────────────────────────────────────────────────

local function killerKind(killer)
    if not killer then return "no killer recorded" end
    if isAircraft(killer) then return "aircraft" end
    local g = groupOf(killer) or ""
    if g:find("^SAM_") then return "SAM sites" end
    if g:find("^DEF_") then return "base defenses" end
    return "other ground units"
end

local function deathText(e)
    local text = e.what
    if e.killer then
        text = text .. " by " .. e.killer
        if e.weapon then text = text .. " with " .. e.weapon end
    else
        text = text .. ", no killer recorded"
    end
    if e.where then text = text .. ", " .. e.where end
    return text
end

-- A unit or static object destroyed: one DESTROYED line, whichever DCS event comes first;
-- the kill event (who did it) fills in the line if it arrives while it is still held.
local function destroyed(o, killer, weapon)
    local name = nameOf(o)
    if not name then return end
    local e = _deaths[name]
    if e then
        if killer and not e.killer and not e.written then
            e.killer, e.killer_kind, e.weapon = who(killer), killerKind(killer), weapon
        end
        return
    end
    local side = sideOf(o)
    local aircraft = isAircraft(o)
    local t = typeOf(o) or "?"
    local player = playerOf(o)
    e = push(side, "DESTROYED", name, nil, {
        what = t .. (player and (", player " .. player) or ""),
        killer = killer and who(killer), killer_kind = killerKind(killer), weapon = weapon,
        where = aircraft and whereIs(o, side) or nil,
        aircraft = aircraft, static = not isUnit(o), coalition = coalitionName(side),
        render = deathText,
    })
    _deaths[name] = e
end

local function weaponName(e)
    return e.weapon_name or typeOf(e.weapon) or "gun"
end

local function shot(e)
    local shooter = e.initiator
    local name = nameOf(shooter)
    if not name then return end
    local weapon = typeOf(e.weapon) or "?"
    local target = e.weapon and safe(function() return e.weapon:getTarget() end)
    local targetName = target and nameOf(target)
    fold(table.concat({ "shot", name, weapon, targetName or "" }, "|"), EVENT_LOG.fold_shots_s, function()
        local text = ""
        if targetName then
            text = " at " .. who(target)
            local a, b = safe(function() return shooter:getPoint() end), safe(function() return target:getPoint() end)
            if a and b then text = text .. string.format(", %.0f km", Util.dist(a, b) / 1000) end
        end
        if isAircraft(shooter) then
            local p = safe(function() return shooter:getPoint() end)
            if p then text = text .. string.format(", from %s ft", Util.thousands(p.y * FEET_PER_METRE)) end
        end
        return push(sideOf(shooter), "SHOT", name, nil, { weapon = weapon, rest = text, shooter_type = typeOf(shooter),
            render = function(l)
                return string.format("%s fired %s%s%s", l.shooter_type or "?",
                    l.count > 1 and (l.count .. "x ") or "", l.weapon, l.rest)
            end })
    end)
end

local function guns(e)
    local shooter = e.initiator
    local name = nameOf(shooter)
    if not name then return end
    local weapon = weaponName(e)
    fold("guns|" .. name, EVENT_LOG.fold_guns_s, function()
        return push(sideOf(shooter), "GUNS", name, nil, { weapon = weapon, shooter_type = typeOf(shooter),
            render = function(l)
                return string.format("%s opened fire with %s%s", l.shooter_type or "?", l.weapon,
                    l.count > 1 and string.format(" (%d bursts)", l.count) or "")
            end })
    end)
end

local function hit(e)
    local target = e.target
    if not isNamedThing(target) then return end
    local name = nameOf(target)
    if not name then return end
    local shooterName = nameOf(e.initiator) or "?"
    local weapon = weaponName(e)
    fold(table.concat({ "hit", name, shooterName, weapon }, "|"), EVENT_LOG.fold_hits_s, function()
        local by = e.initiator and who(e.initiator) or "unknown"
        return push(sideOf(target), "HIT", name, nil, { weapon = weapon, by = by, target_type = typeOf(target),
            where = isAircraft(target) and whereIs(target) or nil,
            render = function(l)
                local text = string.format("%s hit by %s%s from %s", l.target_type or "?", l.weapon,
                    l.count > 1 and string.format(" (%d hits)", l.count) or "", l.by)
                if l.where then text = text .. ", " .. l.where end
                return text
            end })
    end)
end

local function placeName(e)
    return e.place and nameOf(e.place)
end

local handler = {}
function handler:onEvent(e)
    if _ended then return end
    local ok, err = pcall(function()
        local ev, o = world.event, e.initiator
        local id = e.id
        if id == ev.S_EVENT_SHOT then
            shot(e)
        elseif id == ev.S_EVENT_SHOOTING_START then
            guns(e)
        elseif id == ev.S_EVENT_HIT then
            hit(e)
        elseif id == ev.S_EVENT_KILL then
            if isNamedThing(e.target) then destroyed(e.target, o, e.weapon_name or typeOf(e.weapon)) end
        elseif id == ev.S_EVENT_DEAD or id == ev.S_EVENT_UNIT_LOST then
            if isNamedThing(o) then destroyed(o) end
        elseif id == ev.S_EVENT_CRASH then
            if isAircraft(o) then push(sideOf(o), "CRASHED", nameOf(o), string.format("%s crashed%s", typeOf(o) or "?",
                whereIs(o) and (", " .. whereIs(o)) or "")) end
        elseif id == ev.S_EVENT_EJECTION then
            if isAircraft(o) then push(sideOf(o), "EJECTED", nameOf(o), string.format("pilot of %s ejected%s",
                typeOf(o) or "?", whereIs(o) and (", " .. whereIs(o)) or "")) end
        elseif id == ev.S_EVENT_PILOT_DEAD then
            if isAircraft(o) then push(sideOf(o), "PILOT_DEAD", nameOf(o), "pilot of " .. (typeOf(o) or "?") .. " killed") end
        elseif ev.S_EVENT_LANDING_AFTER_EJECTION and id == ev.S_EVENT_LANDING_AFTER_EJECTION then
            push(sideOf(o), "PARACHUTE", nameOf(o) or "pilot", "an ejected pilot landed by parachute")
        elseif id == ev.S_EVENT_TAKEOFF then
            if isAircraft(o) then push(sideOf(o), "TAKEOFF", nameOf(o), string.format("%s, from %s", typeOf(o) or "?",
                placeName(e) or "open ground")) end
        elseif id == ev.S_EVENT_LAND then
            if isAircraft(o) then push(sideOf(o), "LAND", nameOf(o), string.format("%s, at %s", typeOf(o) or "?",
                placeName(e) or "open ground")) end
        elseif id == ev.S_EVENT_BIRTH then
            local player = isAircraft(o) and playerOf(o)
            if player then push(sideOf(o), "PLAYER_IN", nameOf(o), string.format("%s in a %s at %s", player,
                typeOf(o) or "?", placeName(e) or "an unknown place")) end
        elseif id == ev.S_EVENT_PLAYER_LEAVE_UNIT then
            local player = playerOf(o)
            if player then push(sideOf(o), "PLAYER_OUT", nameOf(o), player .. " left the " .. (typeOf(o) or "?")) end
        elseif ev.S_EVENT_AI_ABORT_MISSION and id == ev.S_EVENT_AI_ABORT_MISSION then
            push(sideOf(o), "ABORTED", groupOf(o) or nameOf(o), "the DCS AI gave up its mission")
        elseif id == ev.S_EVENT_MISSION_END then
            WriteEventLog.finish()
        end
    end)
    if not ok then Log.warn("event log: event " .. tostring(e.id) .. " failed: " .. tostring(err)) end
end

-- ── POSITION lines ──────────────────────────────────────────────

local function positions()
    for _, side in ipairs({ 1, 2 }) do
        for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
            for _, g in ipairs(coalition.getGroups(side, category) or {}) do
                local m = _flights[nameOf(g) or ""]
                local st = m and m.station and _stations[m.station]
                for _, u in ipairs(safe(function() return g:getUnits() end) or {}) do
                    if safe(function() return u:inAir() end) then
                        local v = u:getVelocity()
                        local speed = math.sqrt(v.x * v.x + v.z * v.z)
                        local heading = math.deg(math.atan2(v.z, v.x))
                        if heading < 0 then heading = heading + 360 end
                        local text = string.format("%s, %.0f kt, heading %03d, fuel %.0f %%, %s", typeOf(u) or "?",
                            speed * KNOTS_PER_MPS, math.floor(heading + 0.5) % 360, (u:getFuel() or 0) * 100,
                            whereIs(u, side) or "?")
                        if st and st.centre then
                            local p = u:getPoint()
                            text = text .. string.format(", %.0f km from station centre", Util.dist({ x = p.x, z = p.z }, st.centre) / 1000)
                        end
                        local player = playerOf(u)
                        if player then text = text .. ", player " .. player end
                        push(side, "POSITION", nameOf(u), text)
                    end
                end
            end
        end
    end
end

-- ── the plan, at the top of the file ────────────────────────────

local function sortedNames(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return list
end

local function planText(plan)
    local L = {}
    local function add(s) L[#L + 1] = s end
    local t = plan.world.time
    add("Kola F-16 random tasking: event log")
    add(string.format("Run started %s (wall clock); mission day %s, start %s local (UTC%+d)",
        safe(function() return os.date("%Y-%m-%d %H:%M:%S") end) or "?", t.date_str, t.start_hhmm, t.utc_offset_h))
    add("The full plan: Saved Games\\DCS\\" .. (CONFIG.PLAN_DUMP_FILE or "?"))
    add("")
    add("== Territory ==")
    local held = { red = {}, blue = {} }
    for _, name in ipairs(sortedNames(plan.territory.bases)) do
        local side = plan.territory.bases[name].side
        if held[side] then held[side][#held[side] + 1] = name end
    end
    for _, c in ipairs({ "blue", "red" }) do
        add(string.format("%-4s  %d bases: %s", c:upper(), #held[c], table.concat(held[c], ", ")))
    end
    add("")
    add("== Weather ==")
    add(safe(function() return Weather.summaryText(plan.world) end) or "?")
    add("")
    add("== SAM sites ==")
    local sites = {}
    for _, s in ipairs(plan.sam_sites and plan.sam_sites.sites or {}) do sites[#sites + 1] = s end
    table.sort(sites, function(a, b)
        if a.side ~= b.side then return a.side < b.side end
        return a.id < b.id
    end)
    for _, s in ipairs(sites) do
        add(string.format("%-4s  %-28s %s, %s, ring %.0f km", s.side:upper(), s.id, s.system, s.layer, (s.engage_m or 0) / 1000))
    end
    local ato = plan.air_tasking_orders or {}
    add("")
    add("== Alert bases (scrambles) ==")
    for _, c in ipairs({ "blue", "red" }) do
        local list = {}
        for _, b in ipairs(ato[c] and ato[c].alert and ato[c].alert.bases or {}) do
            list[#list + 1] = string.format("%s (%d jets)", b.base, b.alert_aircraft or b.scrambles or 0)
        end
        add(string.format("%-4s  %s", c:upper(), #list > 0 and table.concat(list, ", ") or "none"))
    end
    add("")
    add("== Air tasking order (planned; times are spawn / takeoff / TOT or on station / end) ==")
    for _, c in ipairs({ "blue", "red" }) do
        local list = {}
        for _, m in ipairs(ato[c] and ato[c].missions or {}) do list[#list + 1] = m end
        table.sort(list, function(a, b)
            if a.start_s ~= b.start_s then return a.start_s < b.start_s end
            return a.id < b.id
        end)
        for _, m in ipairs(list) do
            add(string.format("%-4s  %-16s %s / %s / %s / %s  %s%s", c:upper(), m.id, clock(m.start_s):sub(1, 5),
                clock(m.takeoff_s or m.start_s):sub(1, 5), m.tot_s and clock(m.tot_s):sub(1, 5) or "--:--",
                m.end_s and clock(m.end_s):sub(1, 5) or "--:--", missionText(m, true),
                m.flown_by == "human" and "  [for a player]" or ""))
        end
    end
    add("")
    add("== Convoys ==")
    for _, cv in ipairs(plan.convoys and plan.convoys.convoys or {}) do
        add(string.format("%-4s  %s: %d vehicles, %s to %s, %d km of road, ~%d min", cv.coalition:upper(), cv.id,
            cv.units or 0, cv.from_base or "?", cv.to_base or "?", cv.road_km or 0, cv.travel_minutes or 0))
    end
    add("")
    add("== Timeline ==")
    add("local     since start  side  event        subject                     details")
    return table.concat(L, "\n") .. "\n"
end

-- ── the summary, when the mission ends ──────────────────────────

local function summaryText()
    local L = {}
    local function add(s) L[#L + 1] = s end
    local now = timer.getTime()
    add("")
    add(string.format("== Mission end %s (%s) ==", clock(now), elapsed(now)))
    for _, c in ipairs({ "blue", "red" }) do
        local lost, byCause, units, statics = 0, {}, 0, 0
        for _, e in pairs(_deaths) do
            if e.coalition == c then
                if e.aircraft then
                    lost = lost + 1
                    byCause[e.killer_kind] = (byCause[e.killer_kind] or 0) + 1
                elseif e.static then
                    statics = statics + 1
                else
                    units = units + 1
                end
            end
        end
        local causes = {}
        for _, k in ipairs(sortedNames(byCause)) do causes[#causes + 1] = string.format("%s %d", k, byCause[k]) end
        add(string.format("%-4s  %d flights launched; %d aircraft lost%s; on the ground %d units and %d objects destroyed",
            c:upper(), _launched[c] or 0, lost, #causes > 0 and (" (" .. table.concat(causes, ", ") .. ")") or "",
            units, statics))
    end
    add("")
    add("Flights:")
    for _, id in ipairs(sortedNames(_flights)) do
        local m = _flights[id]
        add(string.format("%-4s  %-16s %s — %s", m.coalition:upper(), id, missionText(m),
            safe(function() return ScheduleAirTaskingOrders.statusOf(id) end) or "?"))
    end
    return table.concat(L, "\n") .. "\n"
end

-- ── start and end ───────────────────────────────────────────────

-- Opens this run's file and writes the plan at its top. Before anything spawns.
function WriteEventLog.open(plan)
    _plan = plan
    for _, c in ipairs({ "red", "blue" }) do
        local ato = plan.air_tasking_orders and plan.air_tasking_orders[c]
        for _, st in ipairs(ato and ato.stations or {}) do _stations[st.id] = st end
        for _, m in ipairs(ato and ato.missions or {}) do _flights[m.id] = m end
    end
    local stamp = safe(function() return os.date("%Y-%m-%d_%H%M%S") end)
        or string.format("%s_%s", plan.world.time.date_str, tostring(math.floor(timer.getTime())))
    -- the repository's folder first; if it can't be written (another machine, the repo
    -- moved), Saved Games\DCS; if neither, dcs.log
    for _, folder in ipairs({ EVENT_LOG.folder, lfs.writedir() .. EVENT_LOG.fallback_folder }) do
        pcall(lfs.mkdir, folder)
        local path = folder .. "\\" .. stamp .. ".log"
        local f, err = io.open(path, "w")
        if f then
            _file, _path = f, path
            break
        end
        Log.warn("event log: cannot open " .. path .. " (" .. tostring(err) .. ")")
    end
    if not _file then Log.warn("event log: no file could be opened — its lines go to dcs.log instead") end
    local ok, text = pcall(planText, plan)
    writeText(ok and text or ("(the plan could not be written: " .. tostring(text) .. ")\n"))
    timer.scheduleFunction(function(_, now)
        if _ended then return nil end
        local okWrite, errWrite = pcall(writeOut, false)
        if not okWrite then Log.warn("event log: write failed: " .. tostring(errWrite)) end
        return now + EVENT_LOG.write_every_s
    end, nil, timer.getTime() + EVENT_LOG.write_every_s)
    Log.info("--- Event log: " .. (_file and _path or "dcs.log (file not opened)") .. " ---")
end

-- Starts catching DCS events and the POSITION lines. After the preload (whose spawns
-- aren't part of the story), before the first flight spawns.
function WriteEventLog.start()
    world.addEventHandler(handler)
    if EVENT_LOG.position_every_s > 0 then
        timer.scheduleFunction(function(_, now)
            if _ended then return nil end
            local ok, err = pcall(positions)
            if not ok then Log.warn("event log: positions failed: " .. tostring(err)) end
            return now + EVENT_LOG.position_every_s
        end, nil, timer.getTime() + EVENT_LOG.position_every_s)
    end
end

-- The mission is ending: everything held is written, then the summary; the file closes.
function WriteEventLog.finish()
    if _ended then return end
    pcall(writeOut, true)
    local ok, text = pcall(summaryText)
    writeText(ok and text or ("(the summary failed: " .. tostring(text) .. ")\n"))
    _ended = true
    if _file then _file:close() _file = nil end
end
