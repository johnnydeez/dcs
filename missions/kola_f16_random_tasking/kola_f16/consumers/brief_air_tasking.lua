-- Consumer: the briefing for players, from plan.air_tasking_orders.
--   BriefAirTasking.startText(plan)  the on-screen text at mission start: the weather and
--                                    one short entry per human flight (where to spawn,
--                                    takeoff, TOT, what)
--   BriefAirTasking.start(plan)      Comms menu entries (\ > F10. Other...) for the human flights' coalition:
--     Human taskings > <flight> > Frag         the tasking: times, target (degrees and
--                                              decimal minutes for the F-16, MGRS,
--                                              elevation), loadout, threats, package
--                                 > Steerpoints the points to enter by hand: out to the
--                                              target (its ground elevation, then each aim
--                                              point) or the station, then the landing base
--     Hide text                                 clears the screen
--     Air tasking order > …                     every flight of the coalition, with its
--                                              state now (planned / airborne / landed / lost)
-- A human flight is only listed: nobody is assigned to it. A player who destroys a static
-- object the mission spawned gets a popup (DCS's kill list doesn't show static objects),
-- with the tasking's progress when the object is part of a human tasking's target.
-- Coordinates are converted when the texts are built, once, at start.
-- Reads the plan; writes nothing back to it.

BriefAirTasking = {}

local MESSAGE_S       = 60    -- how long a comms menu text stays on screen
local FRAG_MESSAGE_S  = 180   -- the frag, and the steerpoints, stay long enough to read and
local STEERPOINT_MESSAGE_S = 300   -- type in (John, 2026-10-01)
local START_MESSAGE_S = 180
local KILL_MESSAGE_S  = 15    -- the popup for a static object a player destroyed
local MENU_PAGE       = 9     -- entries per comms submenu (the menu shows 10 at most)
local NEAR_ROUTE_KM   = 20    -- enemy SAM rings the route passes this close to are listed
local FEET_PER_METRE  = 3.28084

local MISSION_NAME = {
    strike                      = "STRIKE",
    airfield_strike             = "AIRFIELD STRIKE",
    destruction_of_air_defenses = "DEAD",
    suppression_of_air_defenses = "SEAD",
    combat_air_patrol           = "CAP",
    airborne_early_warning      = "AWACS",
    interception                = "INTERCEPT",
}
local STEERPOINT_NAME = {
    takeoff = "BASE", departure = "DEP", transit = "NAV", descent = "DESC", ingress = "IP",
    target = "TGT", egress = "EGR", landing = "LAND", station = "CAP A", station_end = "CAP B",
}

local _plan

-- ── formatting ──────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

local function missionName(t) return MISSION_NAME[t] or t:upper() end

-- Mission time (s) → local clock time "08:41".
local function at(t) return Weather.hhmm(_plan.world.time.start_local + t) end

local function feet(m)
    local ft = round(m * FEET_PER_METRE / 100) * 100
    return string.format("%d,%03d ft", math.floor(ft / 1000), ft % 1000)
end

-- Degrees and decimal minutes, as the F-16 takes them: "N68°36.123' E027°24.567'".
local function ddm(lat, lon)
    local function part(deg, pos, neg, width)
        local a = math.abs(deg)
        local d = math.floor(a)
        local m = (a - d) * 60
        if m >= 59.9995 then d, m = d + 1, 0 end
        return string.format("%s%0" .. width .. "d°%06.3f'", deg >= 0 and pos or neg, d, m)
    end
    return part(lat, "N", "S", 2) .. " " .. part(lon, "E", "W", 3)
end

-- A plan position → "N68°36.123' E027°24.567'  35W MS 12345 67890  elev 420 ft".
local function where(pos)
    local lat, lon = coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
    local text = ddm(lat, lon)
    local ok, g = pcall(coord.LLtoMGRS, lat, lon)
    if ok and g then
        text = string.format("%s  %s %s %05d %05d", text, g.UTMZone, g.MGRSDigraph,
            math.floor(g.Easting), math.floor(g.Northing))
    end
    local elev = land.getHeight({ x = pos.x, y = pos.z })
    return string.format("%s  elev %d ft", text, round(elev * FEET_PER_METRE))
end

-- ── what's in the plan ──────────────────────────────────────────

local function missionsById()
    local out = {}
    for _, c in ipairs({ "red", "blue" }) do
        for _, m in ipairs(_plan.air_tasking_orders[c] and _plan.air_tasking_orders[c].missions or {}) do out[m.id] = m end
    end
    return out
end

-- A threat id (a SAM site's or a base-defense group's) → { label, pos, engage_m }.
local function threatsById()
    local out = {}
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        out[s.id] = { label = string.format("%s %s", s.system, s.id), pos = s.pos, engage_m = s.engage_m, side = s.side,
                      layer = s.layer }
    end
    for _, g in ipairs(_plan.base_defenses and _plan.base_defenses.groups or {}) do
        out[g.id] = { label = string.format("%s at %s", (g.role:gsub("_", " ")), g.base), pos = g.pos, side = g.side }
    end
    return out
end

-- The loadout's weapons, counted: "2x GBU-31(V)1/B - JDAM…, 2x AIM-120C …".
local function loadoutText(m)
    local counts, order = {}, {}
    for _, py in ipairs(m.loadout and m.loadout.pylons or {}) do
        local w = py.weapon or py.CLSID
        if not counts[w] then order[#order + 1] = w end
        counts[w] = (counts[w] or 0) + 1
    end
    local parts = {}
    for _, w in ipairs(order) do parts[#parts + 1] = string.format("%dx %s", counts[w], w) end
    return #parts > 0 and table.concat(parts, "\n    ") or "clean"
end

-- Distance (m) from p to the segment a-b.
local function toSegment(p, a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local len2 = dx * dx + dz * dz
    local t = len2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / len2)) or 0
    return Util.dist(p, { x = a.x + t * dx, z = a.z + t * dz })
end

-- The route out, from takeoff to the target (or the station's far end).
local function routeOut(m)
    local out = {}
    for _, r in ipairs(m.route) do
        out[#out + 1] = r
        if r.kind == "target" or r.kind == "station_end" then break end
    end
    return out
end

-- Enemy medium / long-range SAM rings the route out enters or passes within NEAR_ROUTE_KM
-- of: { id, label, gap_m (negative: inside) }, nearest first.
local function samRingsNear(m, threats)
    local out, route = {}, routeOut(m)
    for id, t in pairs(threats) do
        if t.side ~= m.coalition and t.engage_m and AIR_ROUTING.threat_layers[t.layer] then
            local d = math.huge
            for i = 2, #route do d = math.min(d, toSegment(t.pos, route[i - 1], route[i])) end
            local gap = d - t.engage_m
            if gap < NEAR_ROUTE_KM * 1000 then out[#out + 1] = { id = id, label = t.label, gap_m = gap } end
        end
    end
    table.sort(out, function(a, b) return a.gap_m < b.gap_m end)
    return out
end

-- One line per flight: "MSN2005 SEAD 2x F-16C_50 from Kallax, over target 08:37".
local function flightLine(m, byId)
    return string.format("%s%s %s %dx %s from %s, T/O %s, %s %s", m.id, m.flown_by == "human" and " (PLAYER)" or "",
        missionName(m.mission_type), m.count, m.aircraft_type, m.launch_base, at(m.takeoff_s),
        m.station and "on station" or "TOT", at(m.tot_s))
end

-- ── the frag ────────────────────────────────────────────────────

local function threatSection(m, byId, threats, lines)
    lines[#lines + 1] = "THREATS"
    local suppressor = {}
    local main = m.escorts and byId[m.escorts] or m
    for _, sid in ipairs(main.suppressed_by or {}) do
        for _, id in ipairs(byId[sid].suppresses or {}) do suppressor[id] = byId[sid] end
    end
    local listed = 0
    for _, r in ipairs(samRingsNear(m, threats)) do
        local s = suppressor[r.id]
        local who = ""
        if s then
            who = s.id == m.id and " — YOURS to suppress"
                  or string.format(" — suppressed by %s (%s), over target %s", s.id, s.aircraft_type, at(s.tot_s))
        end
        lines[#lines + 1] = string.format("  %s: route %s%s", r.label,
            r.gap_m < 0 and string.format("crosses its ring (%d km inside)", round(-r.gap_m / 1000))
                        or string.format("passes %d km outside its ring", round(r.gap_m / 1000)), who)
        listed = listed + 1
    end
    -- threats a suppression flight takes that aren't SAM rings (base-defense groups)
    for id, s in pairs(suppressor) do
        local t = threats[id]
        if t and not t.engage_m then
            lines[#lines + 1] = string.format("  %s%s", t.label, s.id == m.id and " — YOURS to suppress"
                or string.format(" — suppressed by %s", s.id))
            listed = listed + 1
        end
    end
    if listed == 0 then lines[#lines + 1] = "  no known SAM ring on or near the route" end
    lines[#lines + 1] = string.format("  %d km of the way in is in enemy airspace. Expect AAA / MANPADS near targets.",
        m.enemy_airspace_km or 0)
end

local function fragText(m)
    local byId, threats = missionsById(), threatsById()
    local cat = _plan.target_catalog and _plan.target_catalog.targets or {}
    local lines = {
        string.format("%s  %s  (1x %s, PLAYER)", m.id, missionName(m.mission_type), m.aircraft_type),
        string.format("FROM  %s, slot %s (spot %s)", m.launch_base, m.player_slot.group, m.player_slot.spot),
        string.format("TAKEOFF %s   %s %s   HOME ~%s   (mission start %s)", at(m.takeoff_s),
            m.station and "ON STATION" or "TOT", at(m.tot_s), at(m.end_s - AIR_TASKING_TIMING.landing_s),
            at(0)),
        "",
    }
    if m.station then
        local st
        for _, s in ipairs(_plan.air_tasking_orders[m.coalition].stations or {}) do
            if s.id == m.station then st = s end
        end
        local a = m.attack
        lines[#lines + 1] = string.format("STATION %s: race-track at %s, %s–%s", m.station, feet(a.altitude_m),
            at(m.tot_s), at(a.until_s))
        lines[#lines + 1] = "  A " .. where({ x = a.station[1], z = a.station[2] })
        lines[#lines + 1] = "  B " .. where({ x = a.station[3], z = a.station[4] })
        if a.zone then
            lines[#lines + 1] = string.format("DEFEND  enemy aircraft within %d km of", round(a.zone.radius_m / 1000))
            lines[#lines + 1] = "  " .. where(a.zone)
        end
        if st then
            lines[#lines + 1] = string.format("  covering %d own sites near the front: %s", #st.defends, table.concat(st.defends, ", "))
        end
        lines[#lines + 1] = "  Stay out of enemy airspace and enemy SAM rings."
        local others = {}
        for _, o in pairs(byId) do
            if o.station == m.station and o.id ~= m.id then others[#others + 1] = o end
        end
        table.sort(others, function(x, y) return x.tot_s < y.tot_s end)
        if #others > 0 then
            lines[#lines + 1] = "OTHER PATROLS ON THIS STATION"
            for _, o in ipairs(others) do
                lines[#lines + 1] = string.format("  %s %s from %s, on station %s–%s", o.id, o.aircraft_type,
                    o.launch_base, at(o.tot_s), at(o.attack.until_s))
            end
        end
    else
        local t = cat[m.target]
        local main = m.escorts and byId[m.escorts] or m
        if m.escorts then
            lines[#lines + 1] = string.format("ESCORT  %s %s: %dx %s from %s, TOT %s", main.id,
                missionName(main.mission_type), main.count, main.aircraft_type, main.launch_base, at(main.tot_s))
            lines[#lines + 1] = string.format("  Be over the target %s, %d min ahead of %s, and suppress:",
                at(m.tot_s), round((main.tot_s - m.tot_s) / 60), main.id)
            for _, id in ipairs(m.suppresses or {}) do
                local th = threats[id]
                lines[#lines + 1] = string.format("  %s", th and th.label or id)
                if th then lines[#lines + 1] = "    " .. where(th.pos) end
            end
            lines[#lines + 1] = string.format("  (groups: %s)", table.concat(m.attack.groups or {}, ", "))
        end
        lines[#lines + 1] = string.format("TARGET  %s  [%s]", t and t.label or m.target_label or m.target, m.target)
        if t and t.description then lines[#lines + 1] = "  " .. t.description end
        lines[#lines + 1] = "  " .. where(m.target_pos)
        if not m.escorts then
            local points = m.attack.points or {}
            if #points > 0 then
                lines[#lines + 1] = string.format("  Aim points (%d):", #points)
                for i, p in ipairs(points) do lines[#lines + 1] = string.format("   %d %s", i, where(p)) end
            elseif m.attack.groups then
                lines[#lines + 1] = string.format("  Groups: %s", table.concat(m.attack.groups, ", "))
            end
            local frac = m.success and m.success.critical_fraction
            local n = #(m.critical_names or {})
            if frac and n > 0 then
                local need = math.max(1, math.ceil(frac * n - 1e-9))
                lines[#lines + 1] = need == n and n == 1 and "  Success: destroy its critical object"
                    or string.format("  Success: destroy %s%d of its %d critical objects", need < n and "at least " or "",
                        need, n)
            end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "LOADOUT (as planned for an AI jet)"
    lines[#lines + 1] = "    " .. loadoutText(m)
    lines[#lines + 1] = ""
    threatSection(m, byId, threats, lines)

    if m.package and not m.station then
        local main = m.escorts and byId[m.escorts] or m
        local members = { main }
        for _, sid in ipairs(main.suppressed_by or {}) do members[#members + 1] = byId[sid] end
        if #members > 1 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "PACKAGE " .. m.package
            for _, o in ipairs(members) do
                local role = o.escorts and ("SEAD: " .. table.concat(o.suppresses or {}, ", ")) or "the mission"
                lines[#lines + 1] = string.format("  %s%s %dx %s from %s, T/O %s, over target %s — %s", o.id,
                    o.flown_by == "human" and " (PLAYER)" or "", o.count, o.aircraft_type, o.launch_base,
                    at(o.takeoff_s), at(o.tot_s), role)
            end
        end
    end
    return table.concat(lines, "\n")
end

local function elevation(pos)
    return string.format("elev %d ft", round(land.getHeight({ x = pos.x, y = pos.z }) * FEET_PER_METRE))
end

-- The points a player types in: the route out to the target or the station's far end,
-- then the landing base; no egress or way home (a player follows the way out back;
-- closed_issues.md, bug 11). The target is its exact spot on the ground with its elevation,
-- not the attack altitude, then each aim point the same way, so fire-and-forget weapons
-- (JDAM, JSOW) can be given them (closed_issues.md, bug 10).
local function steerpointText(m)
    local lines = { string.format("%s STEERPOINTS (from %s; times at %d kt)", m.id, m.launch_base,
        round(m.route[2] and m.route[2].speed_mps * 1.94384 or 0)) }
    local n = 0
    local function add(name, pos, what, time)
        n = n + 1
        lines[#lines + 1] = string.format("%2d %-6s %s  %s  %s", n, name, ddm(coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })),
            what, time or "")
    end
    local last = #m.route
    for i, r in ipairs(m.route) do
        if r.kind == "target" or r.kind == "station_end" then last = i break end
    end
    local t = m.takeoff_s
    for i = 1, last do
        local r = m.route[i]
        if i > 1 then t = t + Util.dist(m.route[i - 1], r) / math.max(r.speed_mps or 1, 1) end
        if r.kind == "target" then
            local p = (not m.escorts and m.target_pos) or r
            add("TGT", p, elevation(p), at(m.tot_s))
            if not m.escorts then
                for k, a in ipairs(m.attack and m.attack.points or {}) do add("AIM " .. k, a, elevation(a)) end
            end
        else
            add(STEERPOINT_NAME[r.kind] or r.kind, r, r.kind == "takeoff" and "" or feet(r.alt_m), at(t))
        end
    end
    local home = m.route[#m.route]
    if last < #m.route and home.kind == "landing" then
        add("LAND", home, elevation(home), "~" .. at(m.end_s - AIR_TASKING_TIMING.landing_s))
    end
    return table.concat(lines, "\n")
end

-- "MSN2003 STRIKE from Rovaniemi (slot Q3): T/O 08:14, TOT 08:41 — <what>"
local function shortLine(m, byId)
    local what
    if m.station then
        what = string.format("patrol %s", m.station)
    elseif m.escorts then
        local main = byId[m.escorts]
        what = string.format("escort %s %s on %s", main.id, missionName(main.mission_type), main.target_label or main.target)
    else
        what = m.target_label or m.target
    end
    return string.format("%s %s from %s (slot %s): T/O %s, %s %s — %s", m.id, missionName(m.mission_type),
        m.launch_base:upper(), m.player_slot.spot, at(m.takeoff_s), m.station and "on station" or "TOT", at(m.tot_s), what)
end

-- ── the air tasking order ───────────────────────────────────────

local function packageText(pkg, byId)
    local main = byId[pkg.mission]
    local lines = { string.format("%s: %s on %s, TOT %s", pkg.id, missionName(main.mission_type),
        main.target_label or main.target, at(main.tot_s)) }
    local members = { main }
    for _, sid in ipairs(pkg.suppression_flights) do members[#members + 1] = byId[sid] end
    for _, m in ipairs(members) do
        lines[#lines + 1] = "  " .. flightLine(m, byId) .. " — " .. ScheduleAirTaskingOrders.statusOf(m.id)
    end
    return table.concat(lines, "\n")
end

local function stationText(st, byId)
    local lines = { string.format("%s: %s", st.id, st.label) }
    local flights = {}
    for _, m in pairs(byId) do
        if m.station == st.id then flights[#flights + 1] = m end
    end
    table.sort(flights, function(a, b) return a.tot_s < b.tot_s end)
    for _, m in ipairs(flights) do
        lines[#lines + 1] = string.format("  %s%s %s from %s, on station %s–%s — %s", m.id,
            m.flown_by == "human" and " (PLAYER)" or "", m.aircraft_type, m.launch_base, at(m.tot_s),
            at(m.attack.until_s), ScheduleAirTaskingOrders.statusOf(m.id))
    end
    return table.concat(lines, "\n")
end

-- ── static objects destroyed by players ─────────────────────────

-- DCS's kill list doesn't show static objects (parked aircraft, buildings), so a player
-- who destroys one the mission spawned gets a popup naming it, plus the tasking's
-- progress when it is part of a human tasking's target (closed_issues.md, bug 9). Map
-- scenery and units get none (DCS shows units). A kill whose shooter is gone (shot down
-- or ejected before the bomb landed) is credited through the weapon, remembered at launch.
local function watchStaticKills(plan)
    local cat = plan.target_catalog and plan.target_catalog.targets or {}
    local objects = {}   -- static object id → { type, target }
    for _, o in ipairs(plan.fixed_ground_targets and plan.fixed_ground_targets.static_objects or {}) do
        objects[o.id] = { type = o.type, target = cat[o.site] }
    end
    local tasking = {}   -- catalog target id → the human tasking against it
    for _, c in ipairs({ "red", "blue" }) do
        for _, m in ipairs(plan.air_tasking_orders[c] and plan.air_tasking_orders[c].missions or {}) do
            if m.flown_by == "human" and not m.escorts and m.target then tasking[m.target] = m end
        end
    end
    local launchedBy = {}   -- weapon → the player group that fired it
    local done = {}         -- human taskings already reported a success
    local function playerGroup(u)
        local ok, id = pcall(function() return u:getPlayerName() and u:getGroup():getID() end)
        return ok and id or nil
    end
    local function message(groupId, name, o)
        local t = o.target
        local text = string.format("Destroyed: %s (%s)", o.type, t and t.description or "target")
        local m = t and tasking[t.id]
        if m then
            local destroyed, critical = ScheduleAirTaskingOrders.targetProgress(m.id)
            local frac = m.success and m.success.critical_fraction or 1
            local need = math.max(1, math.ceil(frac * critical - 1e-9))
            local isCritical = false
            for _, c in ipairs(m.critical_names or {}) do if c == name then isCritical = true end end
            text = text .. (isCritical and string.format(": %d of %d critical for %s", destroyed, critical, m.id)
                                       or string.format(": not one of %s's critical objects", m.id))
            if destroyed >= need and not done[m.id] then
                done[m.id] = true
                text = text .. string.format("\n%s target destroyed: success", m.id)
            end
        end
        trigger.action.outTextForGroup(groupId, text, KILL_MESSAGE_S)
    end
    local handler = {}
    function handler:onEvent(e)
        local ok, err = pcall(function()
            if e.id == world.event.S_EVENT_SHOT then
                local g = e.initiator and playerGroup(e.initiator)
                if g and e.weapon then launchedBy[e.weapon.id_ or e.weapon] = g end
            elseif e.id == world.event.S_EVENT_KILL and e.target then
                local name = e.target:getName()
                local o = name and objects[name]
                if not o then return end
                local g = (e.initiator and playerGroup(e.initiator)) or (e.weapon and launchedBy[e.weapon.id_ or e.weapon])
                if not g then return end
                -- a moment later, so the scheduler has counted the kill
                timer.scheduleFunction(function() pcall(message, g, name, o) end, nil, timer.getTime() + 1)
            end
        end)
        if not ok then Log.warn("brief: static kill popup failed: " .. tostring(err)) end
    end
    world.addEventHandler(handler)
end

-- ── menus and the start text ────────────────────────────────────

local function show(side, text, seconds)
    trigger.action.outTextForCoalition(side, text, seconds or MESSAGE_S, true)
end

-- `items` = { { name, text function } } as commands under `parent`, MENU_PAGE per submenu.
local function addPaged(side, parent, title, items)
    if #items == 0 then return end
    local menu = missionCommands.addSubMenuForCoalition(side, title, parent)
    local pages = math.ceil(#items / MENU_PAGE)
    for p = 1, pages do
        local sub = menu
        if pages > 1 then
            sub = missionCommands.addSubMenuForCoalition(side, string.format("%d–%d", (p - 1) * MENU_PAGE + 1,
                math.min(p * MENU_PAGE, #items)), menu)
        end
        for i = (p - 1) * MENU_PAGE + 1, math.min(p * MENU_PAGE, #items) do
            local item = items[i]
            missionCommands.addCommandForCoalition(side, item[1], sub, function() show(side, item[2]()) end)
        end
    end
end

-- The on-screen text at mission start: the weather and the human flights.
function BriefAirTasking.startText(plan)
    _plan = plan
    local w, t = plan.world.weather, plan.world.time
    local c = w.clouds
    local function wind(v, label) return string.format("%s %03d° %d kt", label, v.from_deg, round(v.kts)) end
    local lines = {
        string.format("KOLA — %s, mission start %s local", t.date_str, t.start_hhmm),
        string.format("WEATHER  %s, clouds %s base %d ft%s, vis %d km, %s", c.name or "", c.coverage, c.base_ft,
            c.ceiling_ft and string.format(" (ceiling %d ft)", c.ceiling_ft) or "", round(w.visibility_m / 1000), w.flight_rules),
        string.format("  wind from: %s, %s, %s", wind(w.wind.ground, "ground"), wind(w.wind.at2000, "6,600 ft"),
            wind(w.wind.at8000, "26,000 ft")),
        string.format("  %s°C, QNH %s inHg; %s", tostring(w.temp_c), tostring(w.qnh.inhg),
            (t.sun.sunrise or t.sun.sunset) and string.format("sunrise %s, sunset %s", t.sun.sunrise or "--", t.sun.sunset or "--")
            or (t.sun.polar or "no sunrise or sunset today")),
        "",
    }
    local ato = plan.air_tasking_orders
    local side = HUMAN_TASKING and HUMAN_TASKING.coalition
    local res = ato and not ato.problems and side and ato[side]
    if res and #res.human_missions > 0 then
        local byId = missionsById()
        lines[#lines + 1] = string.format("HUMAN TASKINGS (%s) — spawn at the base:", side:upper())
        for i, id in ipairs(res.human_missions) do
            lines[#lines + 1] = string.format(" %d. %s", i, shortLine(byId[id], byId))
        end
        lines[#lines + 1] = "Full brief and steerpoints: Comms menu > Other > Human taskings. All flights: Comms menu > Other > Air tasking order."
    else
        lines[#lines + 1] = "No human taskings this time — see dcs.log."
    end
    return table.concat(lines, "\n")
end

function BriefAirTasking.showStart(plan)
    trigger.action.outText(BriefAirTasking.startText(plan), START_MESSAGE_S)
end

function BriefAirTasking.start(plan)
    _plan = plan
    local ato = plan.air_tasking_orders
    local sideName = HUMAN_TASKING and HUMAN_TASKING.coalition
    if not ato or ato.problems or not sideName or not ato[sideName] then return end
    local side = sideName == "red" and coalition.side.RED or coalition.side.BLUE
    local res = ato[sideName]
    local byId = missionsById()

    -- built once: positions don't change
    local human = missionCommands.addSubMenuForCoalition(side, "Human taskings")
    local summary = {}
    for _, id in ipairs(res.human_missions) do
        local m = byId[id]
        local frag, steer = fragText(m), steerpointText(m)
        summary[#summary + 1] = shortLine(m, byId)
        local sub = missionCommands.addSubMenuForCoalition(side,
            string.format("%s %s from %s", m.id, missionName(m.mission_type), m.launch_base), human)
        missionCommands.addCommandForCoalition(side, "Frag", sub, function() show(side, frag, FRAG_MESSAGE_S) end)
        missionCommands.addCommandForCoalition(side, "Steerpoints", sub, function() show(side, steer, STEERPOINT_MESSAGE_S) end)
        Log.info("HUMAN TASKING " .. (frag:gsub("\n", "\n    ")) .. "\n    " .. (steer:gsub("\n", "\n    ")))
    end
    local summaryText = #summary > 0 and table.concat(summary, "\n") or "No human taskings this time."
    missionCommands.addCommandForCoalition(side, "All human taskings", human, function() show(side, summaryText) end)

    -- the air tasking order: states change, so the texts are built when asked for
    local order = missionCommands.addSubMenuForCoalition(side, "Air tasking order")
    local packages = {}
    for _, pkg in ipairs(res.packages or {}) do
        local main = byId[pkg.mission]
        packages[#packages + 1] = { string.format("%s %s %s", at(main.tot_s), missionName(main.mission_type), pkg.id),
            function() return packageText(pkg, byId) end, main.tot_s }
    end
    table.sort(packages, function(a, b) return a[3] < b[3] end)
    addPaged(side, order, "Attack packages", packages)
    local stations = {}
    for _, st in ipairs(res.stations or {}) do
        stations[#stations + 1] = { st.id, function() return stationText(st, byId) end }
    end
    addPaged(side, order, "Patrols and AWACS", stations)
    missionCommands.addCommandForCoalition(side, "All flights", order, function()
        local lines = {}
        for _, m in ipairs(res.missions) do
            lines[#lines + 1] = flightLine(m, byId) .. " — " .. ScheduleAirTaskingOrders.statusOf(m.id)
        end
        show(side, table.concat(lines, "\n"))
    end)
    -- clears a long-lasting frag or steerpoint list once it's entered
    missionCommands.addCommandForCoalition(side, "Hide text", nil, function() show(side, " ", 1) end)
    watchStaticKills(plan)
    Log.info(string.format("--- Briefing: %d human taskings, %d packages and %d stations in the %s comms menu ---",
        #res.human_missions, #packages, #stations, sideName:upper()))
end
