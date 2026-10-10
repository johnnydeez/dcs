-- Shows each base's domain on the F10 map, so John can see roughly where each base's
-- territory lies (2026-10-08): runs in the viewer mission (map_data_tools\find_base_domains.py
-- make-mission writes it from the campaign mission, so its bases' owners are the campaign's),
-- never in a flyable mission. Works on any map with base domains.
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\show_base_domains.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- Draws, for everyone: each domain filled faintly in its base's coalition colour (who holds
-- the base in this mission, read from DCS); the front line, where a Red domain meets a Blue
-- one, in yellow; the contested band either side of it, shaded, by Kola's rule (a 10 km cell
-- whose nearest Red and nearest Blue base are within twice AIRSPACE.front_band_km of each
-- other's distance: mission_scripts\data\airspace.lua); each base's rings (RINGS_FILE), dashed,
-- cut to its domain; and a label per base with its sites in each ring. No units: the F10 map
-- is the whole tool.
--
-- Everything is read from the repository, whose place on this PC comes from
-- Saved Games\DCS\Scripts\map_surveys\local_paths.lua (MAP_SURVEY_PATHS.repository_folder;
-- bug 76): the map's data (shared_mission_framework\map_data\<map>\), the shared loader
-- (mission_scripts\tools\spawn_sites.lua), Kola's airspace settings and the campaign's rings.

-- The rings each base's sites fall in (a mission's own setting; relative to the repository).
-- Without it no rings are drawn.
local RINGS_FILE = "missions\\afghanistan_campaign\\afghanistan_campaign\\data\\base_rings.lua"
local CIRCLE_POINTS = 72
local LOOK_AFTER_S = 5       -- airbase queries return nothing at the very start (gotchas)

local MAP = (env.mission and env.mission.theatre) or "unknown_map"

local function log(msg) env.info("[BASE DOMAINS SHOWN] " .. msg) end
local function say(msg, s) trigger.action.outText("BASE DOMAINS: " .. msg, s or 30) end

local nextId = 2000
local function newId()
    nextId = nextId + 1
    return nextId
end

local function point(x, z) return { x = x, y = land.getHeight({ x = x, y = z }), z = z } end

-- Colours are positional { r, g, b, a } (gotchas).
local LINE   = { [0] = { 0.7, 0.7, 0.7, 0.9 }, [1] = { 1, 0.15, 0.15, 0.9 }, [2] = { 0.2, 0.5, 1, 0.9 } }
local FILL   = { [0] = { 0.7, 0.7, 0.7, 0.10 }, [1] = { 1, 0, 0, 0.12 }, [2] = { 0, 0.4, 1, 0.12 } }
local SIDE   = { [0] = "NEUTRAL", [1] = "RED", [2] = "BLUE" }
local FRONT_COLOUR     = { 1, 1, 0, 1 }
local CONTESTED_FILL   = { 1, 1, 0, 0.18 }
local RING_COLOUR      = { 1, 1, 1, 0.7 }
local TEXT_COLOUR      = { 1, 1, 1, 1 }
local TEXT_FILL        = { 0, 0, 0, 0.45 }
local NO_FILL          = { 0, 0, 0, 0 }
local LINE_SOLID, LINE_DASHED, LINE_NONE = 1, 2, 0

local function thousands(n)
    local s = tostring(n)
    while true do
        local done
        s, done = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if done == 0 then return s end
    end
end

-- A freeform polygon (markupToAll shape 7). Its points go in the middle of the arguments,
-- so the call is built as one list: unpack in the middle of an argument list would pass
-- only the first point.
local function polygon(points, colour, fill, lineType)
    local args = { 7, -1, newId() }
    for _, p in ipairs(points) do args[#args + 1] = point(p[1], p[2]) end
    args[#args + 1] = colour
    args[#args + 1] = fill
    args[#args + 1] = lineType
    args[#args + 1] = true
    trigger.action.markupToAll(unpack(args))
end

-- The part of a polygon (list of { x, z }) inside a convex outline (Sutherland–Hodgman).
local function clipToConvex(subject, outline)
    local area = 0
    for k = 1, #outline do
        local a, b = outline[k], outline[k % #outline + 1]
        area = area + a[1] * b[2] - b[1] * a[2]
    end
    local sign = area >= 0 and 1 or -1
    local out = subject
    for k = 1, #outline do
        local a, b = outline[k], outline[k % #outline + 1]
        local function inside(p) return sign * ((b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1])) >= 0 end
        local input = out
        out = {}
        for n = 1, #input do
            local p, q = input[n], input[n % #input + 1]
            local pin, qin = inside(p), inside(q)
            if pin then out[#out + 1] = p end
            if pin ~= qin then
                -- where p–q crosses the line a–b
                local dx, dz = q[1] - p[1], q[2] - p[2]
                local ex, ez = b[1] - a[1], b[2] - a[2]
                local t = (ex * (a[2] - p[2]) - ez * (a[1] - p[1])) / (ex * dz - ez * dx)
                out[#out + 1] = { p[1] + t * dx, p[2] + t * dz }
            end
        end
        if #out == 0 then return out end
    end
    return out
end

local function run()
    MAP_SURVEY_PATHS = nil
    pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\local_paths.lua")
    local repo = MAP_SURVEY_PATHS and MAP_SURVEY_PATHS.repository_folder
    if not repo then
        say("no Scripts\\map_surveys\\local_paths.lua, so the repository's place isn't known", 60)
        return
    end
    local framework = repo .. "\\shared_mission_framework\\"
    dofile(framework .. "mission_scripts\\tools\\spawn_sites.lua")
    local map, err = SpawnSites.open(framework .. "map_data\\" .. MAP:lower() .. "\\")
    if not map then say("no spawn sites for " .. MAP .. ": " .. tostring(err), 60) return end
    if not map.domains then say("no base_domains.lua for " .. MAP .. ": run map_data_tools\\find_base_domains.py", 60) return end

    AIRSPACE = nil
    dofile(framework .. "mission_scripts\\data\\airspace.lua")
    local cellM, bandM = AIRSPACE.cell_km * 1000, AIRSPACE.front_band_km * 1000

    BASE_RINGS = nil
    local okRings, ringsErr = pcall(dofile, repo .. "\\" .. RINGS_FILE)
    local rings = okRings and BASE_RINGS or nil
    if not rings then log("no rings: " .. tostring(ringsErr)) end

    -- who holds each domain's base in this mission
    local holder, mismatches = {}, {}
    for _, b in ipairs(map.domains.bases) do
        local ab = Airbase.getByName(b.name)
        holder[b.id] = ab and ab:getCoalition() or 0
        if not ab then log("no airbase named " .. b.name .. " in DCS") end
        for _, h in ipairs(b.helipads) do
            local hb = Airbase.getByName(h.name)
            if hb and hb:getCoalition() ~= holder[b.id] then
                mismatches[#mismatches + 1] = string.format("%s is %s, its field %s %s", h.name, SIDE[hb:getCoalition()],
                    b.name, SIDE[holder[b.id]])
            end
        end
    end

    -- every site, counted per base and ring (the whole map: this is a viewer)
    local started = os.clock()
    local perBase = {}
    for _, b in ipairs(map.domains.bases) do perBase[b.id] = { total = 0, ring = {} } end
    for _, t in ipairs(map:everyTile()) do
        local sites, why = map:tile(t)
        if not sites then say("could not load " .. t.file .. ": " .. tostring(why), 60) return end
        for _, s in ipairs(sites) do
            local c = perBase[s.base_id]
            c.total = c.total + 1
            if rings then
                local r = SpawnSites.ringOf(rings, s.base_distance_m)
                c.ring[r] = (c.ring[r] or 0) + 1
            end
        end
        map:forget(t)   -- counted; not kept
    end
    log(string.format("counted %d sites in %d tiles in %.1f s", map.domains.sites, #map:everyTile(), os.clock() - started))

    -- the domains
    for _, b in ipairs(map.domains.bases) do
        local side = holder[b.id]
        polygon(b.outline, LINE[side], FILL[side], LINE_SOLID)
    end

    -- the contested band, Kola's rule, on cells merged into strips along each row
    local box = map.domains.box
    local red, blue = {}, {}
    for _, b in ipairs(map.domains.bases) do
        if holder[b.id] == 1 then red[#red + 1] = b elseif holder[b.id] == 2 then blue[#blue + 1] = b end
    end
    local function nearest(list, x, z)
        local best = math.huge
        for _, b in ipairs(list) do
            local d = (b.x - x) ^ 2 + (b.z - z) ^ 2
            if d < best then best = d end
        end
        return math.sqrt(best)
    end
    local strips, contestedKm2 = 0, 0
    if #red > 0 and #blue > 0 then
        for x = box.x_min, box.x_max - 1, cellM do
            local runStart
            local function close(zEnd)
                if runStart then
                    polygon({ { x, runStart }, { x, zEnd }, { math.min(x + cellM, box.x_max), zEnd }, { math.min(x + cellM, box.x_max), runStart } },
                        NO_FILL, CONTESTED_FILL, LINE_NONE)
                    strips = strips + 1
                    runStart = nil
                end
            end
            for z = box.z_min, box.z_max - 1, cellM do
                local cx, cz = x + cellM / 2, z + cellM / 2
                if math.abs(nearest(red, cx, cz) - nearest(blue, cx, cz)) / 2 <= bandM then
                    runStart = runStart or z
                    contestedKm2 = contestedKm2 + (cellM / 1000) ^ 2
                else
                    close(z)
                end
            end
            close(box.z_max)
        end
    end

    -- the front line: each border between a Red and a Blue domain, once
    local frontKm = 0
    for _, b in ipairs(map.domains.bases) do
        for _, n in ipairs(b.neighbours) do
            local hb, hn = holder[b.id], holder[n.id]
            if b.id < n.id and hb ~= hn and hb ~= 0 and hn ~= 0 then
                local p, q = n.border[1], n.border[2]
                trigger.action.lineToAll(-1, newId(), point(p[1], p[2]), point(q[1], q[2]), FRONT_COLOUR, LINE_SOLID, true)
                frontKm = frontKm + math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) / 1000
            end
        end
    end

    -- each base's rings, cut to its domain, and its label
    local ringsDrawn = 0
    for _, b in ipairs(map.domains.bases) do
        if rings then
            for _, r in ipairs(rings) do
                if r.out_to_km then
                    local radius = r.out_to_km * 1000
                    local beyond = false   -- some of the domain lies outside this ring
                    for _, p in ipairs(b.outline) do
                        if (p[1] - b.x) ^ 2 + (p[2] - b.z) ^ 2 > radius * radius then beyond = true break end
                    end
                    if beyond then
                        local circle = {}
                        for k = 0, CIRCLE_POINTS - 1 do
                            local a = k * 2 * math.pi / CIRCLE_POINTS
                            circle[#circle + 1] = { b.x + radius * math.cos(a), b.z + radius * math.sin(a) }
                        end
                        local cut = clipToConvex(circle, b.outline)
                        if #cut >= 3 then
                            polygon(cut, RING_COLOUR, NO_FILL, LINE_DASHED)
                            ringsDrawn = ringsDrawn + 1
                        end
                    end
                end
            end
        end
        local c = perBase[b.id]
        local lines = { string.format("%s (%s)", b.name, SIDE[holder[b.id]]),
                        string.format("%s sites, farthest %d km", thousands(c.total), math.floor(b.farthest_site_m / 1000)) }
        if rings then
            local parts = {}
            for _, r in ipairs(rings) do
                parts[#parts + 1] = string.format("ring %d: %s", r.ring, thousands(c.ring[r.ring] or 0))
            end
            lines[#lines + 1] = table.concat(parts, ", ")
        end
        trigger.action.textToAll(-1, newId(), point(b.x, b.z), TEXT_COLOUR, TEXT_FILL, 12, true, table.concat(lines, "\n"))
    end

    local ringText = "no rings (" .. RINGS_FILE .. " not found)"
    if rings then
        local parts = {}
        for _, r in ipairs(rings) do
            parts[#parts + 1] = string.format("ring %d %s, open %d min after capture", r.ring,
                r.out_to_km and ("to " .. r.out_to_km .. " km") or "to the domain's edge", r.open_after_capture_min or 0)
        end
        ringText = table.concat(parts, "; ")
    end
    local summary = string.format("%d domains (%d Red, %d Blue), %s sites; front line %d km; contested band %s km2 "
        .. "(+/- %d km, %d strips); %d ring outlines\n%s%s",
        #map.domains.bases, #red, #blue, thousands(map.domains.sites), math.floor(frontKm), thousands(math.floor(contestedKm2)),
        AIRSPACE.front_band_km, strips, ringsDrawn, ringText,
        #mismatches > 0 and ("\nhelipads held apart from their field: " .. table.concat(mismatches, "; ")) or "")
    log(summary)
    say(summary, 60)
end

timer.scheduleFunction(function()
    local ok, err = pcall(run)
    if not ok then
        log("failed: " .. tostring(err))
        say("FAILED: " .. tostring(err), 60)
    end
end, nil, timer.getTime() + LOOK_AFTER_S)
