-- Tests how DCS's AI ground units drive on the Afghanistan map, so we know whether the
-- campaign needs off-road routing of its own (John, 2026-10-09: "Primarily, I just want to
-- keep them from driving up mountains"; missions\afghanistan_campaign\mission_design.md,
-- *Ground war*). Runs in its own test mission, never in a flyable one:
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\test_ground_unit_driving.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io / os).
--
-- Three drives, all started when the script loads (the comms menu, Ground driving test, has
-- Status and Write summaries now), each with two identical companies side by side at the same start: one ordered "Off Road" straight to the
-- end point, one "On Road" (DCS finds the road route: start → the road nearest the start →
-- the road nearest the end → the end point). Every 5 s every unit's position, height and
-- speed go to a log file, with when each company arrives, gets stuck or moves on again, how
-- high it climbed and the steepest climb it drove; at the end a summary per company.
--
-- The start and end points are spawn sites (flat, clear discs), picked by script from the
-- whole-map survey (2026-10-09; the picker was a one-off in that session's scratchpad):
--   ridge   a ridge on the straight line, >= 400 m above both ends with 400 m steps over
--           25 %, both ends within 2 km of a road, a gentler way round on the 1 km grid
--   desert  10-15 km, the straight line never over 5 %, no map objects on it
--   town    5-10 km, flat, the line through the most map objects (here: Kandahar city)
--
-- Writes Saved Games\DCS\map_surveys\<map>\ground_driving_test_<date>_<time>.log.
-- What it answers: does the Off Road company drive over the ridge (or get stuck on it), and
-- does the On Road one go round; does On Road work through a town and across the desert;
-- how long DCS takes to accept an On Road order (a long road route might stall the game).

local DRIVES = {
    {
        key = "ridge", title = "Ridge in the way (Wardak, between Ghazni and Kabul)",
        from = { site = 174124, x = 12200, z = 236500 },
        to   = { site = 174386, x = 14100, z = 226200 },
        picked = "10.5 km; ridge 452 m above the higher end, steepest 400 m step 38 %; gentler way round ~13 km",
    },
    {
        key = "desert", title = "Open desert (west of Kandahar)",
        from = { site = 64081, x = -289800, z = -47100 },
        to   = { site = 66748, x = -285600, z = -61500 },
        picked = "15.0 km; steepest 400 m step 2 %; no map objects on the line",
    },
    {
        key = "town", title = "Through a town (Kandahar city, west to east)",
        from = { site = 83814, x = -255600, z = -45100 },
        to   = { site = 83986, x = -255300, z = -35300 },
        picked = "9.8 km; ~16,000 map objects in the cells crossed; steepest 400 m step 4 %",
    },
}

-- A small mixed company: trucks, an infantry fighting vehicle and a tank (different
-- wheeled and tracked limits).
local COMPANY       = { "Ural-375", "Ural-375", "BMP-2", "T-72B" }
local UNIT_SPACING  = 25       -- m between vehicles at the start, in a column
local COMPANY_APART = 100      -- m each company starts north / south of the site's centre
local ORDER_SPEED   = 40       -- m/s asked for (~144 km/h): flat out, DCS holds each vehicle to its own top speed (John: no long waits)
local LOG_EVERY_S   = 5
local ARRIVED_M     = 300      -- every live vehicle this close to the end point
local STUCK_S       = 60       -- a vehicle that moved less than STUCK_M in this long is stuck
local STUCK_M       = 10
local CLIMB_MIN_M   = 15       -- a 5 s move shorter than this doesn't count for the climb grade
local GIVE_UP_S     = 3 * 3600 -- stop watching a company after this long
local PROFILE_STEP  = 100      -- m between heights read along the straight line at the start

local MAP    = (env.mission and env.mission.theatre) or "unknown_map"
local FOLDER = lfs.writedir() .. "map_surveys\\" .. MAP .. "\\"

local function info(msg) env.info("[GROUND DRIVING TEST] " .. msg) end
local function say(msg, s) trigger.action.outText("GROUND DRIVING TEST: " .. msg, s or 20) end

local logFile
local function log(msg)
    local line = string.format("%s  T+%07.1f  %s", os.date("%H:%M:%S"), timer.getTime(), msg)
    if not logFile then
        lfs.mkdir(lfs.writedir() .. "map_surveys")
        lfs.mkdir(FOLDER)
        local path = FOLDER .. "ground_driving_test_" .. os.date("%Y-%m-%d_%H%M") .. ".log"
        logFile = io.open(path, "a")
        if logFile then
            info("log file " .. path)
            say("logging to " .. path, 15)
        end
    end
    if logFile then
        logFile:write(line, "\n")
        logFile:flush()
    else
        info(msg)
    end
end

local function ground(x, z) return land.getHeight({ x = x, y = z }) end
local function dist(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end
local function km(m) return string.format("%.1f km", m / 1000) end

-- The straight line's terrain, from DCS itself: highest point, and steepest 100 m step.
local function profile(a, b)
    local d = dist(a.x, a.z, b.x, b.z)
    local n = math.max(1, math.floor(d / PROFILE_STEP))
    local top, steepest, prev = -1e9, 0, nil
    for i = 0, n do
        local f = i / n
        local h = ground(a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f)
        if h > top then top = h end
        if prev then steepest = math.max(steepest, math.abs(h - prev) / (d / n)) end
        prev = h
    end
    return top, steepest, d
end

local function waypoint(x, z, action)
    return {
        x = x, y = z, type = "Turning Point", action = action, speed = ORDER_SPEED,
        speed_locked = true, ETA = 0, ETA_locked = false, formation_template = "",
        task = { id = "ComboTask", params = { tasks = {} } },
    }
end

local function clock() return (os and os.clock) and os.clock() or 0 end

-- A read-only F10 map mark; every mark needs its own number.
local nextMark = 7000
local function mark(text, pos)
    nextMark = nextMark + 1
    trigger.action.markToAll(nextMark, text, pos, true)
end

-- ── the companies ────────────────────────────────────────────────

local companies = {}   -- name → company
local started = {}     -- drive key → true

local function spawnCompany(drive, kind, offsetX)
    local name = string.format("DRIVE_%s_%s", drive.key, kind)
    local a, b = drive.from, drive.to
    -- the column faces the end point, its lead at the site's centre (shifted north / south)
    local hx, hz = b.x - a.x, b.z - a.z
    local len = math.sqrt(hx * hx + hz * hz)
    hx, hz = hx / len, hz / len
    local heading = math.atan2(hz, hx)
    if heading < 0 then heading = heading + 2 * math.pi end
    local units = {}
    for i, typeName in ipairs(COMPANY) do
        local back = (i - 1) * UNIT_SPACING
        units[#units + 1] = {
            name = string.format("%s_%d", name, i), type = typeName, skill = "Average",
            x = a.x + offsetX - hx * back, y = a.z - hz * back, heading = heading,
        }
    end
    local ok, group = pcall(coalition.addGroup, country.id.CJTF_RED, Group.Category.GROUND,
        { name = name, task = "Ground Nothing", units = units, x = units[1].x, y = units[1].y, visible = true })
    if not ok or not group then
        log(string.format("SPAWN FAILED  %s: %s", name, tostring(group)))
        return nil
    end
    local c = { name = name, drive = drive, kind = kind, group = group, spawned_at = timer.getTime(),
                units = {}, state = "spawned" }
    for i, u in ipairs(units) do
        c.units[i] = { name = u.name, type = u.type, last = { x = u.x, z = u.y }, driven = 0, top = ground(u.x, u.y),
                       start_h = ground(u.x, u.y), steepest = 0, history = {}, stuck = false }
    end
    companies[name] = c
    log(string.format("SPAWNED  %s  %d vehicles (%s) at site %d, %s start", name, #units,
        table.concat(COMPANY, ", "), a.site, kind == "off_road" and "Off Road" or "On Road"))
    return c
end

local function orderCompany(c)
    local a, b = c.drive.from, c.drive.to
    local lead = c.units[1]
    local points
    local note = ""
    if c.kind == "off_road" then
        points = { waypoint(lead.last.x, lead.last.z, "Off Road"), waypoint(b.x, b.z, "Off Road") }
    else
        local t0 = clock()
        local sx, sz = land.getClosestPointOnRoads("roads", a.x, a.z)
        local ex, ez = land.getClosestPointOnRoads("roads", b.x, b.z)
        local t1 = clock()
        local path = land.findPathOnRoads("roads", sx, sz, ex, ez)
        local t2 = clock()
        local length = 0
        if path then
            for i = 2, #path do length = length + dist(path[i - 1].x, path[i - 1].y, path[i].x, path[i].y) end
        end
        note = string.format("; road nearest the start %s away, nearest the end %s away (%.0f ms); "
            .. "findPathOnRoads: %s, %d points, %s (%.0f ms)",
            km(dist(a.x, a.z, sx, sz)), km(dist(b.x, b.z, ex, ez)), (t1 - t0) * 1000,
            path and "a road route" or "NO ROAD ROUTE", path and #path or 0, km(length), (t2 - t1) * 1000)
        points = { waypoint(lead.last.x, lead.last.z, "Off Road"), waypoint(sx, sz, "On Road"),
                   waypoint(ex, ez, "On Road"), waypoint(b.x, b.z, "Off Road") }
        mark(string.format("%s: road start", c.name), { x = sx, y = ground(sx, sz), z = sz })
        mark(string.format("%s: road end", c.name), { x = ex, y = ground(ex, ez), z = ez })
    end
    local t0 = clock()
    local ok, err = pcall(function()
        Group.getByName(c.name):getController():setTask({ id = "Mission", params = { route = { points = points } } })
    end)
    local took = (clock() - t0) * 1000
    c.ordered_at = timer.getTime()
    c.state = "driving"
    log(string.format("ORDERED  %s  %s to site %d, %d waypoints; setTask %s in %.0f ms%s", c.name,
        c.kind == "off_road" and "Off Road" or "On Road", b.site, #points, ok and "accepted" or ("FAILED: " .. tostring(err)),
        took, note))
end

local function summary(c, why)
    local b = c.drive.to
    local parts = {}
    for _, u in ipairs(c.units) do
        if u.dead then
            parts[#parts + 1] = string.format("%s %s: lost", u.name, u.type)
        else
            parts[#parts + 1] = string.format("%s %s: drove %s, %s from the end, highest %d m (%+d m from its start), steepest climb %d %%%s",
                u.name, u.type, km(u.driven), km(dist(u.last.x, u.last.z, b.x, b.z)), u.top, u.top - u.start_h,
                math.floor(u.steepest * 100 + 0.5), u.stuck and ", STUCK" or "")
        end
    end
    local elapsed = timer.getTime() - (c.ordered_at or c.spawned_at)
    log(string.format("SUMMARY  %s  %s after %d min %02d s (straight line %s)\n    %s", c.name, why,
        math.floor(elapsed / 60), math.floor(elapsed % 60), km(c.drive.straight or 0), table.concat(parts, "\n    ")))
end

local function watch(c, now)
    local b = c.drive.to
    local all_there, alive = true, 0
    local lines = {}
    for _, u in ipairs(c.units) do
        local unit = Unit.getByName(u.name)
        if not unit or not unit:isExist() then
            if not u.dead then
                u.dead = true
                log(string.format("LOST  %s %s", u.name, u.type))
            end
        else
            alive = alive + 1
            local p = unit:getPoint()
            local v = unit:getVelocity()
            local speed = math.sqrt(v.x * v.x + v.z * v.z)
            local moved = dist(p.x, p.z, u.last.x, u.last.z)
            u.driven = u.driven + moved
            if moved >= CLIMB_MIN_M then
                local h0 = u.last_h or ground(u.last.x, u.last.z)
                u.steepest = math.max(u.steepest, (p.y - h0) / moved)
            end
            if p.y > u.top then u.top = p.y end
            u.last = { x = p.x, z = p.z }
            u.last_h = p.y
            -- stuck: hardly moved over STUCK_S
            u.history[#u.history + 1] = { t = now, x = p.x, z = p.z }
            while #u.history > 1 and now - u.history[1].t > STUCK_S do table.remove(u.history, 1) end
            local away = dist(p.x, p.z, b.x, b.z)
            if away > ARRIVED_M then all_there = false end
            local first = u.history[1]
            if c.state == "driving" and away > ARRIVED_M and now - first.t >= STUCK_S - LOG_EVERY_S then
                local over = dist(p.x, p.z, first.x, first.z)
                if over < STUCK_M and not u.stuck then
                    u.stuck = true
                    log(string.format("STUCK  %s %s: moved %d m in %d s, %s from the end, %d m high", u.name, u.type,
                        math.floor(over), STUCK_S, km(away), math.floor(p.y)))
                    say(string.format("%s %s stuck, %s from the end", u.name, u.type, km(away)), 10)
                elseif over >= STUCK_M and u.stuck then
                    u.stuck = false
                    log(string.format("MOVING  %s %s again", u.name, u.type))
                end
            end
            lines[#lines + 1] = string.format("%s %s %.0f/%.0f %dm %.1fm/s %s", u.name:match("_(%d+)$"), u.type,
                p.x, p.z, math.floor(p.y), speed, km(away))
        end
    end
    log(string.format("POSITION  %s  %s", c.name, table.concat(lines, " | ")))
    if alive == 0 then
        c.state = "lost"
        summary(c, "every vehicle lost")
    elseif all_there then
        c.state = "arrived"
        say(string.format("%s arrived", c.name), 10)
        summary(c, "ARRIVED")
    elseif now - (c.ordered_at or c.spawned_at) > GIVE_UP_S then
        c.state = "given up"
        summary(c, "given up (still driving)")
    end
end

local function watchAll(_, now)
    for _, c in pairs(companies) do
        if c.state == "driving" then
            local ok, err = pcall(watch, c, now)
            if not ok then log("ERROR watching " .. c.name .. ": " .. tostring(err)) end
        end
    end
    return now + LOG_EVERY_S
end

-- ── the drives ───────────────────────────────────────────────────

local function startDrive(drive)
    if started[drive.key] then
        say(drive.title .. ": already started", 10)
        return
    end
    started[drive.key] = true
    local a, b = drive.from, drive.to
    local top, steepest, d = profile(a, b)
    drive.straight = d
    log(string.format("DRIVE  %s: site %d (%.0f, %.0f, %d m) to site %d (%.0f, %.0f, %d m); picked: %s; "
        .. "the straight line in DCS: %s, highest %d m, steepest 100 m step %d %%",
        drive.title, a.site, a.x, a.z, math.floor(ground(a.x, a.z)), b.site, b.x, b.z, math.floor(ground(b.x, b.z)),
        drive.picked, km(d), math.floor(top), math.floor(steepest * 100 + 0.5)))
    mark(drive.title .. ": start", { x = a.x, y = ground(a.x, a.z), z = a.z })
    mark(drive.title .. ": end", { x = b.x, y = ground(b.x, b.z), z = b.z })
    local off = spawnCompany(drive, "off_road", COMPANY_APART)
    local on = spawnCompany(drive, "on_road", -COMPANY_APART)
    timer.scheduleFunction(function()
        if off then pcall(orderCompany, off) end
        if on then pcall(orderCompany, on) end
    end, nil, timer.getTime() + 3)
    say(string.format("%s: two companies spawned at site %d; the end is %s away. F10 map: the start and end marks.",
        drive.title, a.site, km(d)), 20)
end

local function status()
    local lines = {}
    for _, drive in ipairs(DRIVES) do
        for _, kind in ipairs({ "off_road", "on_road" }) do
            local c = companies[string.format("DRIVE_%s_%s", drive.key, kind)]
            if c then
                local b = drive.to
                local near, stuck = 1e12, 0
                for _, u in ipairs(c.units) do
                    if not u.dead then
                        near = math.min(near, dist(u.last.x, u.last.z, b.x, b.z))
                        if u.stuck then stuck = stuck + 1 end
                    end
                end
                local elapsed = timer.getTime() - (c.ordered_at or c.spawned_at)
                lines[#lines + 1] = string.format("%s: %s, nearest vehicle %s from the end, %d min%s", c.name, c.state,
                    km(near), math.floor(elapsed / 60), stuck > 0 and (", " .. stuck .. " stuck") or "")
            end
        end
    end
    say(#lines > 0 and ("\n" .. table.concat(lines, "\n")) or "no drive started yet", 20)
end

local function summariesNow()
    for _, c in pairs(companies) do
        if c.state == "driving" then summary(c, "summary asked for (still driving)") end
    end
    say("summaries written to the log", 10)
end

local menu = missionCommands.addSubMenu("Ground driving test")
missionCommands.addCommand("Status", menu, status)
missionCommands.addCommand("Write summaries now", menu, summariesNow)

timer.scheduleFunction(watchAll, nil, timer.getTime() + LOG_EVERY_S)
log(string.format("ready on %s: %d drives, companies of %s", MAP, #DRIVES, table.concat(COMPANY, ", ")))
-- All three drives start at once, on load (John, 2026-10-09: no need to start them by hand).
for _, drive in ipairs(DRIVES) do startDrive(drive) end
say("all three drives started; watch on the F10 map. Comms menu → Ground driving test: Status, "
    .. "Write summaries now. Time acceleration is fine.", 30)
