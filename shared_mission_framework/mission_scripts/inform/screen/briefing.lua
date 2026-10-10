-- Inform: the briefing for players, from plan.air_tasking_orders.
--   InformScreenBriefing.startText(plan)  the on-screen text at mission start: the weather and
--                                    one short entry per human flight (where to spawn,
--                                    takeoff, TOT, what)
--   InformScreenBriefing.start(plan)      Comms menu entries (\ > F10. Other...), each player group of
--                                    the human flights' coalition its own (inform/screen/player_menus.lua):
--     Human taskings > <flight> > Frag         the tasking: times, target (degrees and
--                                              decimal minutes for the F-16, MGRS,
--                                              elevation), loadout, threats, the SEAD
--                                              flights it needs (and their state now)
--                                 > Steerpoints the points to enter by hand: out to the
--                                              target (its ground elevation, then each aim
--                                              point) or the station, then the landing base
--     Hide text                                 clears the screen
--     Air tasking order > …                     every flight of the coalition, with its
--                                              state now (planned / airborne / landed / lost):
--                                              attack missions (tagged with the SEAD flights
--                                              they wait on), SEAD flights, patrols
-- A human flight is only listed: nobody is assigned to it. A player who destroys a static
-- object the mission spawned gets a popup (DCS's kill list doesn't show static objects),
-- with the tasking's progress when the object is part of a human tasking's target.
-- Coordinates are converted when the texts are built, once, at start.
-- Reads the plan; writes nothing back to it.

InformScreenBriefing = {}

local MESSAGE_S       = 60    -- how long a comms menu text stays on screen
local FRAG_MESSAGE_S  = 180   -- the frag, and the steerpoints, stay long enough to read and
local STEERPOINT_MESSAGE_S = 300   -- type in (John, 2026-10-01)
local START_MESSAGE_S = 180
local KILL_MESSAGE_S  = 15    -- the popup for a static object a player destroyed
local MENU_PAGE       = 9     -- entries per comms submenu (the menu shows 10 at most)
local NEAR_ROUTE_KM   = 20    -- enemy SAM rings the route passes this close to are listed
local FEET_PER_METRE  = 3.28084
local SUPPRESSION     = "suppression_of_air_defenses"

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
    low = "LOW", popup = "POP",   -- a SEAD run-in: low legs, then the pop-up to the launch point
    popup_top = "TOP",            -- the top of the pop-up, at the shot altitude
}

local _plan

-- ── formatting ──────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

local function missionName(t) return MISSION_NAME[t] or t:upper() end
InformScreenBriefing.missionName = missionName   -- "SEAD", "CAP", …: the airfield brief uses it too

-- Mission time (s) → local clock time "08:41".
local function at(t) return Weather.hhmm(_plan.world.time.start_local + t) end

local function feet(m)
    local ft = round(m * FEET_PER_METRE / 100) * 100
    if ft < 1000 then return string.format("%d ft", ft) end
    return string.format("%d,%03d ft", math.floor(ft / 1000), ft % 1000)
end

-- A route point's altitude: above sea level, or above the ground on a low leg.
local function altitudeText(r)
    return feet(r.alt_m) .. (r.alt_type == "RADIO" and " AGL" or "")
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

-- The site table of the mission's coalition: threat id → the SEAD flight that takes it.
local function seadBySite(m)
    local ato = _plan.air_tasking_orders[m.coalition]
    return ato and ato.suppression_by_site or {}
end

-- The flights waiting on SEAD flight `s` (those listing its site in requires_cleared),
-- by start time.
local function waitingOn(s, byId)
    local out = {}
    for _, o in pairs(byId) do
        if o.coalition == s.coalition and o.id ~= s.id then
            for _, t in ipairs(o.requires_cleared or {}) do
                if t == s.target then out[#out + 1] = o break end
            end
        end
    end
    table.sort(out, function(a, b) return a.start_s < b.start_s end)
    return out
end

-- The SEAD flight for each threat the mission waits on, in route order:
-- { { threat, sead (mission, or nil) } }.
local function seadNeeded(m, byId)
    local bySite, out = seadBySite(m), {}
    for _, t in ipairs(m.requires_cleared or {}) do
        local id = bySite[t]
        out[#out + 1] = { threat = t, sead = id and byId[id] }
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
local function loadoutText(loadout)
    local counts, order = {}, {}
    for _, py in ipairs(loadout and loadout.pylons or {}) do
        local w = py.weapon or py.CLSID
        if not counts[w] then order[#order + 1] = w end
        counts[w] = (counts[w] or 0) + 1
    end
    local parts = {}
    for _, w in ipairs(order) do parts[#parts + 1] = string.format("%dx %s", counts[w], w) end
    return #parts > 0 and table.concat(parts, "\n    ") or "clean"
end

-- Every player slot at a human flight's base (data/player_slots.lua): any player there can
-- fly it, in whichever aircraft the slot holds; by group name. Falls back to the slot its
-- route starts at.
local function slotsAt(m)
    local out = {}
    for _, s in ipairs(PLAYER_SLOTS and PLAYER_SLOTS[m.launch_base] or {}) do out[#out + 1] = s end
    table.sort(out, function(a, b) return a.group < b.group end)
    if #out == 0 then out[1] = { group = m.player_slot.group, spot = m.player_slot.spot, type = m.aircraft_type } end
    return out
end

-- The aircraft types of those slots, in slot order, each once.
local function typesAt(m)
    local out, seen = {}, {}
    for _, s in ipairs(slotsAt(m)) do
        if not seen[s.type] then seen[s.type], out[#out + 1] = true, s.type end
    end
    return out
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

-- One line per flight: "MSN2005_SEAD Weasel 2 SEAD 2x F-16C_50 from Kallax, T/O 08:12, TOT 08:37".
local function flightLine(m, byId)
    return string.format("%s%s %s %dx %s from %s, T/O %s, %s %s", FlightCallsigns.label(m), m.flown_by == "human" and " (PLAYER)" or "",
        missionName(m.mission_type), m.count, m.aircraft_type, m.launch_base, at(m.takeoff_s),
        m.station and "on station" or "TOT", at(m.tot_s))
end

-- ── the frag ────────────────────────────────────────────────────

-- "Needs down: SAM_KUUS_SA11_1 (MSN2024_SEAD, airborne)", one line per threat the
-- mission waits on (John, 2026-10-02: which SEAD flight had to succeed for it to run).
local function needsDownLines(m, byId)
    local out = {}
    for i, n in ipairs(seadNeeded(m, byId)) do
        local who = n.sead and (n.sead.id == m.id and "yours"
            or string.format("%s, %s", FlightCallsigns.label(n.sead), RecordFlightLaunches.statusOf(n.sead.id))) or "no SEAD flight"
        out[#out + 1] = string.format("%s%s (%s)", i == 1 and "Needs down: " or "            ", n.threat, who)
    end
    return out
end

local function threatSection(m, byId, threats, lines)
    lines[#lines + 1] = "THREATS"
    local bySite = seadBySite(m)
    local listed, shown = 0, {}
    for _, r in ipairs(samRingsNear(m, threats)) do
        local s = bySite[r.id] and byId[bySite[r.id]]
        shown[r.id] = true
        local who = ""
        if s then
            who = s.id == m.id and " — YOURS to suppress"
                  or string.format(" — SEAD %s (%s), salvo %s", FlightCallsigns.label(s), s.aircraft_type, at(s.tot_s))
        end
        lines[#lines + 1] = string.format("  %s: route %s%s", r.label,
            r.gap_m < 0 and string.format("crosses its ring (%d km inside)", round(-r.gap_m / 1000))
                        or string.format("passes %d km outside its ring", round(r.gap_m / 1000)), who)
        listed = listed + 1
    end
    -- threats on the route that aren't SAM rings (base-defense groups), and its own site
    local own = m.mission_type == SUPPRESSION and { m.target } or {}
    for _, list in ipairs({ m.requires_cleared or {}, own }) do
        for _, id in ipairs(list) do
            local t = threats[id]
            if t and not shown[id] then
                shown[id] = true
                local s = bySite[id] and byId[bySite[id]]
                lines[#lines + 1] = string.format("  %s%s", t.label, (s and s.id == m.id) and " — YOURS to suppress"
                    or s and string.format(" — SEAD %s", FlightCallsigns.label(s)) or "")
                listed = listed + 1
            end
        end
    end
    if listed == 0 then lines[#lines + 1] = "  no known SAM ring on or near the route" end
    lines[#lines + 1] = string.format("  %d km of the way in is in enemy airspace. Expect AAA / MANPADS near targets.",
        m.enemy_airspace_km or 0)
end

local function fragText(m)
    local byId, threats = missionsById(), threatsById()
    local slots, slotNames = slotsAt(m), {}
    for i, s in ipairs(slots) do slotNames[i] = string.format("%s (spot %s)", s.group, s.spot) end
    local slotCount = #slots
    local cat = _plan.target_catalog and _plan.target_catalog.targets or {}
    local lines = {
        slotCount == 1 and string.format("%s  %s  (1x %s, PLAYER)", m.id, missionName(m.mission_type), slots[1].type)
            or string.format("%s  %s  (1-%d players: %s)", m.id, missionName(m.mission_type), slotCount,
                table.concat(typesAt(m), ", ")),
        string.format("FROM  %s, %s %s", m.launch_base, slotCount == 1 and "slot" or "slots", table.concat(slotNames, ", ")),
        -- every frequency in one place, the player's own Darkstar's too (roadmap.md item 19)
        "RADIO  Comms menu > Other > Radio frequencies",
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
                lines[#lines + 1] = string.format("  %s %s from %s, on station %s–%s", FlightCallsigns.label(o), o.aircraft_type,
                    o.launch_base, at(o.tot_s), at(o.attack.until_s))
            end
        end
    else
        local t = cat[m.target]
        lines[#lines + 1] = string.format("TARGET  %s  [%s]", t and t.label or m.target_label or m.target, m.target)
        if t and t.description then lines[#lines + 1] = "  " .. t.description end
        lines[#lines + 1] = "  " .. where(m.target_pos)
        if m.mission_type == SUPPRESSION then
            local launch = m.attack.launch
            lines[#lines + 1] = string.format("  Fire every anti-radiation missile at it from the LAUNCH steerpoint, %d km from the site, at %s; then straight back out low.",
                launch and round(Util.dist(launch, m.target_pos) / 1000) or 0, at(m.tot_s))
            if m.attack.press_on then
                lines[#lines + 1] = string.format("  No radar to shoot at there: press on toward the site to %d km at most, then home.",
                    round(Util.dist(m.attack.press_on, m.target_pos) / 1000))
            end
            lines[#lines + 1] = string.format("  (groups: %s)", table.concat(m.attack.groups or {}, ", "))
        else
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
    local types = typesAt(m)
    if #types == 1 then
        lines[#lines + 1] = "    " .. loadoutText(types[1] == m.aircraft_type and m.loadout
            or (AIRCRAFT_LOADOUT[types[1]] or {})[m.mission_type])
    else
        for _, t in ipairs(types) do
            lines[#lines + 1] = "  " .. t .. ":"
            lines[#lines + 1] = "    " .. loadoutText(t == m.aircraft_type and m.loadout
                or (AIRCRAFT_LOADOUT[t] or {})[m.mission_type])
        end
    end
    lines[#lines + 1] = ""
    threatSection(m, byId, threats, lines)

    local needs = needsDownLines(m, byId)
    if #needs > 0 then
        lines[#lines + 1] = ""
        for _, l in ipairs(needs) do lines[#lines + 1] = l end
    end
    if m.mission_type == SUPPRESSION then
        local waiting = waitingOn(m, byId)
        if #waiting > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "OPENING THE WAY FOR"
            for _, o in ipairs(waiting) do lines[#lines + 1] = "  " .. flightLine(o, byId) end
        end
    end
    return table.concat(lines, "\n")
end

local function elevation(pos)
    return string.format("elev %d ft", round(land.getHeight({ x = pos.x, y = pos.z }) * FEET_PER_METRE))
end

-- The points a player types in: the route out to the target or the station's far end,
-- then the landing base; no egress or way home (a player follows the way out back;
-- closed.md, bug 11). The target is its exact spot on the ground with its elevation,
-- not the attack altitude, then each aim point the same way, so fire-and-forget weapons
-- (JDAM, JSOW) can be given them (closed.md, bug 10).
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
        if r.kind == "target" and m.mission_type == SUPPRESSION then
            -- a SEAD flight's target point is its launch point, at the pop-up altitude
            add("LAUNCH", r, altitudeText(r), at(m.tot_s))
        elseif r.kind == "target" then
            local p = m.target_pos or r
            add("TGT", p, elevation(p), at(m.tot_s))
            for k, a in ipairs(m.attack and m.attack.points or {}) do add("AIM " .. k, a, elevation(a)) end
        else
            add(STEERPOINT_NAME[r.kind] or r.kind, r, r.kind == "takeoff" and "" or altitudeText(r), at(t))
        end
    end
    local home = m.route[#m.route]
    if last < #m.route and home.kind == "landing" then
        add("LAND", home, elevation(home), "~" .. at(m.end_s - AIR_TASKING_TIMING.landing_s))
    end
    return table.concat(lines, "\n")
end

-- "MSN2003 STRIKE from Rovaniemi (slot Q3): T/O 08:14, TOT 08:41 — <what>"; with more
-- than one player slot at the base, "(slots 10, 11)".
local function shortLine(m, byId)
    local what
    if m.station then
        what = string.format("patrol %s", m.station)
    elseif m.mission_type == SUPPRESSION then
        what = string.format("SEAD on %s", m.target_label or m.target)
    else
        what = m.target_label or m.target
    end
    local spots = {}
    for i, s in ipairs(slotsAt(m)) do spots[i] = s.spot end
    return string.format("%s %s from %s (%s %s): T/O %s, %s %s — %s", m.id, missionName(m.mission_type),
        m.launch_base:upper(), #spots == 1 and "slot" or "slots", table.concat(spots, ", "), at(m.takeoff_s), m.station and "on station" or "TOT", at(m.tot_s), what)
end

-- ── the air tasking order ───────────────────────────────────────

-- An attack mission or a SEAD flight, its state now, and the SEAD it waits on (or, for a
-- SEAD flight, what waits on it).
local function missionText(m, byId)
    local lines = { string.format("%s on %s", missionName(m.mission_type), m.target_label or m.target),
                    "  " .. flightLine(m, byId) .. " — " .. RecordFlightLaunches.statusOf(m.id) }
    for _, l in ipairs(needsDownLines(m, byId)) do lines[#lines + 1] = "  " .. l end
    if m.mission_type == SUPPRESSION then
        local waiting = waitingOn(m, byId)
        if #waiting > 0 then
            local ids = {}
            for i, o in ipairs(waiting) do ids[i] = FlightCallsigns.label(o) end
            lines[#lines + 1] = "  opening the way for " .. table.concat(ids, ", ")
        end
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
        lines[#lines + 1] = string.format("  %s%s %s from %s, on station %s–%s — %s", FlightCallsigns.label(m),
            m.flown_by == "human" and " (PLAYER)" or "", m.aircraft_type, m.launch_base, at(m.tot_s),
            at(m.attack.until_s), RecordFlightLaunches.statusOf(m.id))
    end
    return table.concat(lines, "\n")
end

-- ── static objects destroyed by players ─────────────────────────

-- DCS's kill list doesn't show static objects (parked aircraft, buildings), so a player
-- who destroys one the mission spawned gets a popup naming it, plus the tasking's
-- progress when it is part of a human tasking's target (closed.md, bug 9). Map
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
            if m.flown_by == "human" and m.mission_type ~= SUPPRESSION and m.target and not m.station then tasking[m.target] = m end
        end
    end
    local launchedBy = {}   -- weapon (its key) → the player group that fired it
    local done = {}         -- human taskings already reported a success
    local function playerGroup(u)
        return u.player and u.group_id or nil
    end
    local function message(groupId, name, o)
        local t = o.target
        local text = string.format("Destroyed: %s (%s)", o.type, t and t.description or "target")
        local m = t and tasking[t.id]
        if m then
            local destroyed, critical = RecordFlights.targetProgress(m.id)
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
    -- shots and kills (record\dcs_events.lua)
    local function onEvent(e)
        local ok, err = pcall(function()
            if e.id == world.event.S_EVENT_SHOT then
                local g = e.initiator and playerGroup(e.initiator)
                if g and e.weapon then launchedBy[e.weapon.key] = g end
            elseif e.id == world.event.S_EVENT_KILL and e.target then
                local name = e.target.name
                local o = name and objects[name]
                if not o then return end
                local g = (e.initiator and playerGroup(e.initiator)) or (e.weapon and launchedBy[e.weapon.key])
                if not g then return end
                -- a moment later, so the scheduler has counted the kill
                timer.scheduleFunction(function() pcall(message, g, name, o) end, nil, timer.getTime() + 1)
            end
        end)
        if not ok then Log.warn("brief: static kill popup failed: " .. tostring(err)) end
    end
    RecordDcsEvents.on(onEvent)
end

-- ── menus and the start text ────────────────────────────────────

-- `items` = { { name, text function } } as commands under `parent`, MENU_PAGE per submenu,
-- in one player group's menu (inform/screen/player_menus.lua).
local function addPaged(menu, parent, title, items)
    if #items == 0 then return end
    local top = menu.sub(title, parent)
    local pages = math.ceil(#items / MENU_PAGE)
    for p = 1, pages do
        local sub = top
        if pages > 1 then
            sub = menu.sub(string.format("%d–%d", (p - 1) * MENU_PAGE + 1, math.min(p * MENU_PAGE, #items)), top)
        end
        for i = (p - 1) * MENU_PAGE + 1, math.min(p * MENU_PAGE, #items) do
            local item = items[i]
            menu.command(item[1], sub, function() menu.show(item[2](), MESSAGE_S) end)
        end
    end
end

-- The on-screen text at mission start: the weather and the human flights.
function InformScreenBriefing.startText(plan)
    _plan = plan
    local w, t = plan.world.weather, plan.world.time
    local c = w.clouds
    local function wind(v, label) return string.format("%s %03d° %d kt", label, v.from_deg, round(v.kts)) end
    local lines = {
        string.format("%s — %s, mission start %s local", MISSION.display_name, t.date_str, t.start_hhmm),
        string.format("WEATHER  %s, clouds %s base %d ft%s, vis %d km, %s", c.name or "", c.coverage, c.base_ft,
            c.ceiling_ft and string.format(" (ceiling %d ft)", c.ceiling_ft) or "", round(w.visibility_m / 1000), w.flight_rules),
        string.format("  wind from: %s, %s, %s", wind(w.wind.ground, "ground"), wind(w.wind.at2000, "6,600 ft"),
            wind(w.wind.at8000, "26,000 ft")),
        string.format("  %s°C, QNH %s inHg; %s", tostring(w.temp_c), tostring(w.qnh.inhg),
            (t.sun.sunrise or t.sun.sunset) and string.format("sunrise %s, sunset %s", t.sun.sunrise or "--", t.sun.sunset or "--")
            or (t.sun.polar or "no sunrise or sunset today")),
        "RADIO  Comms menu > Other > Radio frequencies",
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

function InformScreenBriefing.showStart(plan)
    trigger.action.outText(InformScreenBriefing.startText(plan), START_MESSAGE_S)
end

function InformScreenBriefing.start(plan)
    _plan = plan
    local ato = plan.air_tasking_orders
    local sideName = HUMAN_TASKING and HUMAN_TASKING.coalition
    if not ato or ato.problems or not sideName or not ato[sideName] then return end
    local side = sideName == "red" and coalition.side.RED or coalition.side.BLUE
    local res = ato[sideName]
    local byId = missionsById()

    -- built once: positions don't change
    local taskings, summary = {}, {}
    for _, id in ipairs(res.human_missions) do
        local m = byId[id]
        -- the frag is built again when asked for: it says how the SEAD flights it needs are doing
        local frag, steer = fragText(m), steerpointText(m)
        summary[#summary + 1] = shortLine(m, byId)
        taskings[#taskings + 1] = { m = m, steer = steer }
        Log.info("HUMAN TASKING " .. (frag:gsub("\n", "\n    ")) .. "\n    " .. (steer:gsub("\n", "\n    ")))
    end
    local summaryText = #summary > 0 and table.concat(summary, "\n") or "No human taskings this time."

    -- the air tasking order: states change, so the texts are built when asked for
    -- attack missions by start, each tagged with the SEAD flights it waits on; SEAD flights
    local attacks, seads = {}, {}
    for _, m in ipairs(res.missions) do
        if not m.station then
            local item = { nil, function() return missionText(m, byId) end, m.start_s }
            local short = (m.id:match("^MSN%d+") or m.id) .. (m.callsign and (" " .. FlightCallsigns.text(m)) or "")
            if m.mission_type == SUPPRESSION then
                item[1] = string.format("%s SEAD %s on %s", at(m.tot_s), short, m.target)
                seads[#seads + 1] = item
            else
                local after = {}
                for _, n in ipairs(seadNeeded(m, byId)) do
                    if n.sead then after[#after + 1] = FlightCallsigns.text(n.sead) or n.sead.id:match("^MSN%d+") or n.sead.id end
                end
                item[1] = string.format("%s %s %s%s", at(m.tot_s), missionName(m.mission_type), short,
                    #after > 0 and (" (after " .. table.concat(after, ", ") .. " SEAD)") or "")
                attacks[#attacks + 1] = item
            end
        end
    end
    table.sort(attacks, function(a, b) return a[3] < b[3] end)
    table.sort(seads, function(a, b) return a[3] < b[3] end)
    local stations = {}
    for _, st in ipairs(res.stations or {}) do
        stations[#stations + 1] = { st.id, function() return stationText(st, byId) end }
    end
    local function allFlights()
        local lines = {}
        for _, m in ipairs(res.missions) do
            lines[#lines + 1] = flightLine(m, byId) .. " — " .. RecordFlightLaunches.statusOf(m.id)
        end
        return table.concat(lines, "\n")
    end

    -- each player group gets its own menu, so what one player opens shows on their screen only
    InformScreenPlayerMenus.add(side, function(menu)
        local human = menu.sub("Human taskings")
        for _, e in ipairs(taskings) do
            local m = e.m
            local sub = menu.sub(string.format("%s %s from %s", m.id, missionName(m.mission_type), m.launch_base), human)
            menu.command("Frag", sub, function() menu.show(fragText(m), FRAG_MESSAGE_S) end)
            menu.command("Steerpoints", sub, function() menu.show(e.steer, STEERPOINT_MESSAGE_S) end)
        end
        menu.command("All human taskings", human, function() menu.show(summaryText, MESSAGE_S) end)
        local order = menu.sub("Air tasking order")
        addPaged(menu, order, "Attack missions", attacks)
        addPaged(menu, order, "SEAD flights", seads)
        addPaged(menu, order, "Patrols and AWACS", stations)
        menu.command("All flights", order, function() menu.show(allFlights(), MESSAGE_S) end)
        -- clears a long-lasting frag or steerpoint list once it's entered
        menu.command("Hide text", nil, function() menu.show(" ", 1) end)
    end)
    watchStaticKills(plan)
    Log.info(string.format("--- Briefing: %d human taskings, %d attack missions, %d SEAD flights and %d stations in the %s comms menu ---",
        #res.human_missions, #attacks, #seads, #stations, sideName:upper()))
end
