-- Zone terrain survey: runs in the zone drawing mission (khola_ground_zones.miz) only,
-- never in the flyable mission. Standalone: loads nothing else from kola_f16.
-- ME trigger in khola_ground_zones.miz:  ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\kola_f16\\survey\\survey_zone_terrain.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- Measures the DCS terrain in and around every trigger zone in the mission and writes
-- Saved Games\DCS\kola_zone_terrain.lua, keyed by the ME zone id. tools/miz_zones.py
-- reads that file next to the .miz, turns the measurements into classes and writes them
-- into kola_f16/data/zones.lua. Workflow after drawing or moving zones:
--   1. save khola_ground_zones.miz
--   2. fly it once (this script runs at start, takes a few seconds, says when done)
--   3. python tools/miz_zones.py "<path to khola_ground_zones.miz>"
--
-- Raw measurements only; the class thresholds live in tools/miz_zones.py, so classes can
-- be tuned without flying this again. Trees are invisible to every API (probes,
-- 2026-09-23), so nothing here can tell forest from open ground.
--   inside      heights and surface types on 25 points (centre, 8 at 40 %, 16 at 80 %
--               of the usable radius)
--   rings       heights and water on 16 points per ring at RING_M around the centre
--   road_m      distance from the centre to the nearest road; railway_m the same for rail
--   radar_view  bearings (of 16) on which a VIEW_MAST_M mast on the zone sees a flyer
--               VIEW_TARGET_AGL_M above the ground, at each VIEW_M distance
--   buildings   map scenery objects within BUILDING_SEARCH_M: in_zone, near
--               (≤ BUILDING_NEAR_M), total, nearest_m, and every type name as
--               { name, total, near, in_zone, nearest_m }, most common first

local RING_M            = { 250, 500, 1000, 2000, 3000 }
local RING_POINTS       = 16
local VIEW_M            = { 5000, 15000, 30000 }
local VIEW_MAST_M       = 10
local VIEW_TARGET_AGL_M = 100
local BUILDING_SEARCH_M = 2000
local BUILDING_NEAR_M   = 500
local OUT_FILE          = "kola_zone_terrain.lua"
local ZONE_TYPE         = { [0] = "circle", [2] = "quad" }

local function log(msg) env.info("[ZONE SURVEY] " .. msg) end
local function round(v) return math.floor(v + 0.5) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
local function height(p) return land.getHeight({ x = p.x, y = p.z }) end

local function around(c, d, i, n)
    local a = (i - 1) * 2 * math.pi / n
    return { x = c.x + d * math.cos(a), z = c.z + d * math.sin(a) }
end

local SURFACE_NAME = {}
for name, v in pairs(land.SurfaceType) do SURFACE_NAME[v] = name:lower() end
local function surface(p)
    return SURFACE_NAME[land.getSurfaceType({ x = p.x, y = p.z })] or "unknown"
end
local function isWater(s) return s == "water" or s == "shallow_water" end

-- ── zones as the ME stores them ─────────────────────────────────

local function distToSegment(p, a, b)
    local vx, vz = b.x - a.x, b.z - a.z
    local wx, wz = p.x - a.x, p.z - a.z
    local len2 = vx * vx + vz * vz
    local t = len2 > 0 and math.max(0, math.min(1, (wx * vx + wz * vz) / len2)) or 0
    return math.sqrt((wx - t * vx) ^ 2 + (wz - t * vz) ^ 2)
end

-- Usable radius: a circle's radius, or the distance from a quad's centre to its nearest
-- edge (the disc that stays inside it).
local function usableRadius(raw, c)
    if ZONE_TYPE[raw.type or 0] ~= "quad" then return raw.radius or 0 end
    local vs, best = {}, math.huge
    for _, v in ipairs(raw.verticies or raw.vertices or {}) do vs[#vs + 1] = { x = v.x, z = v.y } end
    for i = 1, #vs do best = math.min(best, distToSegment(c, vs[i], vs[i % #vs + 1])) end
    return best < math.huge and best or 0
end

-- ── measurements ────────────────────────────────────────────────

local function measureInside(c, radius)
    local pts = { { x = c.x, z = c.z } }
    for i = 1, 8  do pts[#pts + 1] = around(c, radius * 0.4, i, 8) end
    for i = 1, 16 do pts[#pts + 1] = around(c, radius * 0.8, i, 16) end
    local lo, hi, surfaces = math.huge, -math.huge, {}
    for _, p in ipairs(pts) do
        local h = height(p)
        lo, hi = math.min(lo, h), math.max(hi, h)
        local s = surface(p)
        surfaces[s] = (surfaces[s] or 0) + 1
    end
    return { height_min_m = round(lo), height_max_m = round(hi), points = #pts, surfaces = surfaces }
end

local function measureRings(c)
    local rings = {}
    for _, d in ipairs(RING_M) do
        local sum, lo, hi, water = 0, math.huge, -math.huge, 0
        for i = 1, RING_POINTS do
            local p = around(c, d, i, RING_POINTS)
            local h = height(p)
            sum, lo, hi = sum + h, math.min(lo, h), math.max(hi, h)
            if isWater(surface(p)) then water = water + 1 end
        end
        rings[#rings + 1] = { distance_m = d, height_mean_m = round(sum / RING_POINTS),
                              height_min_m = round(lo), height_max_m = round(hi), water_points = water }
    end
    return rings
end

local function distanceToNetwork(c, kind)
    local ok, x, z = pcall(land.getClosestPointOnRoads, kind, c.x, c.z)
    if not ok or not x then return nil end
    return round(dist(c, { x = x, z = z }))
end

local function measureRadarView(c, groundH)
    local from = { x = c.x, y = groundH + VIEW_MAST_M, z = c.z }
    local view = {}
    for _, d in ipairs(VIEW_M) do
        local seen = 0
        for i = 1, RING_POINTS do
            local p = around(c, d, i, RING_POINTS)
            if land.isVisible(from, { x = p.x, y = height(p) + VIEW_TARGET_AGL_M, z = p.z }) then
                seen = seen + 1
            end
        end
        view[#view + 1] = { distance_m = d, bearings_seen = seen }
    end
    return view
end

-- Every map object within BUILDING_SEARCH_M, counted per type name: the tool decides
-- which types are buildings, clutter (woodpiles, fences, pylons) or prepared military
-- positions (SAM revetments, aircraft shelters), so no type list lives here.
local function measureBuildings(c, groundH, radius)
    local out, tally = { in_zone = 0, near = 0, total = 0, types = {} }, {}
    local volume = { id = world.VolumeType.SPHERE,
                     params = { point = { x = c.x, y = groundH, z = c.z }, radius = BUILDING_SEARCH_M } }
    local ok, err = pcall(world.searchObjects, Object.Category.SCENERY, volume, function(obj)
        local okP, pt = pcall(obj.getPoint, obj)
        if okP and pt then
            local d = dist(c, { x = pt.x, z = pt.z })
            if d <= BUILDING_SEARCH_M then
                out.total = out.total + 1
                if d <= radius then out.in_zone = out.in_zone + 1 end
                if d <= BUILDING_NEAR_M then out.near = out.near + 1 end
                if not out.nearest_m or d < out.nearest_m then out.nearest_m = round(d) end
                local okT, tn = pcall(obj.getTypeName, obj)
                tn = okT and tn or "?"
                local t = tally[tn]
                if not t then
                    t = { tn, 0, 0, 0, round(d) }
                    tally[tn] = t
                end
                t[2] = t[2] + 1
                if d <= BUILDING_NEAR_M then t[3] = t[3] + 1 end
                if d <= radius then t[4] = t[4] + 1 end
                t[5] = math.min(t[5], round(d))
            end
        end
        return true
    end)
    if not ok then log("searchObjects failed: " .. tostring(err)) end
    for _, t in pairs(tally) do out.types[#out.types + 1] = t end
    table.sort(out.types, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    return out
end

local function surveyZone(raw)
    local c = { x = raw.x, z = raw.y }   -- the ME calls east `y`
    local radius  = usableRadius(raw, c)
    local groundH = height(c)
    return {
        me_name    = raw.name,
        x          = round(c.x),   -- where the zone was when surveyed: the tool flags moved zones
        z          = round(c.z),
        radius_m   = round(radius),
        height_m   = round(groundH),
        inside     = measureInside(c, radius),
        rings      = measureRings(c),
        road_m     = distanceToNetwork(c, "roads"),
        railway_m  = distanceToNetwork(c, "railroads"),
        radar_view = measureRadarView(c, groundH),
        buildings  = measureBuildings(c, groundH, radius),
    }
end

-- ── output ──────────────────────────────────────────────────────

local function isIdent(k) return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil end

local function serialize(v, indent)
    indent = indent or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then return v == math.floor(v) and string.format("%d", v) or string.format("%.1f", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    if #keys == 0 then return "{}" end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    local isSeq, allScalar = #v == #keys, true
    for _, k in ipairs(keys) do if type(v[k]) == "table" then allScalar = false end end
    local parts, pad = {}, indent .. "    "
    if allScalar then
        for _, k in ipairs(keys) do
            local ks = isSeq and "" or ((isIdent(k) and k or ("[" .. serialize(k) .. "]")) .. " = ")
            parts[#parts + 1] = ks .. serialize(v[k])
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    for _, k in ipairs(keys) do
        local ks = isSeq and "" or ((isIdent(k) and k or ("[" .. serialize(k) .. "]")) .. " = ")
        parts[#parts + 1] = pad .. ks .. serialize(v[k], pad)
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

local function run()
    local zones = env.mission.triggers and env.mission.triggers.zones or {}
    log(string.format("surveying %d zones", #zones))
    local out, done, failed = {}, 0, 0
    for _, raw in ipairs(zones) do
        local ok, res = pcall(surveyZone, raw)
        if ok then
            out[raw.zoneId] = res
            done = done + 1
            log(string.format("  %5d %-24s h %4d m, road %s, rail %s, view %d/%d at %d km, buildings %d",
                raw.zoneId, raw.name, res.height_m,
                res.road_m and (res.road_m .. " m") or "-", res.railway_m and (res.railway_m .. " m") or "-",
                res.radar_view[2].bearings_seen, RING_POINTS, VIEW_M[2] / 1000, res.buildings.total))
        else
            failed = failed + 1
            log("  FAILED zone " .. tostring(raw.zoneId) .. " " .. tostring(raw.name) .. ": " .. tostring(res))
        end
    end

    local header = table.concat({
        "-- Zone terrain measured in-sim by kola_f16/survey/survey_zone_terrain.lua in the zone",
        "-- drawing mission" .. (os and os.date and (" on " .. os.date("%Y-%m-%d %H:%M")) or "")
            .. ". Input to tools/miz_zones.py, keyed by ME zone id;",
        "-- do not hand-edit. Units: metres; see the script header for what each field means.",
        "",
    }, "\n")
    local path = lfs.writedir() .. OUT_FILE
    local f, err = io.open(path, "w")
    if not f then
        log("cannot write " .. path .. ": " .. tostring(err))
        trigger.action.outText("ZONE SURVEY FAILED — cannot write " .. path .. "\n" .. tostring(err), 60)
        return
    end
    f:write(header .. "ZONE_TERRAIN = " .. serialize(out) .. "\n")
    f:close()
    log(string.format("%d zones surveyed, %d failed → %s", done, failed, path))
    trigger.action.outText(string.format(
        "ZONE SURVEY DONE: %d zones surveyed, %d failed.\n%s\nNext: python tools/miz_zones.py \"<zones .miz>\"",
        done, failed, path), 60)
end

local ok, err = pcall(run)
if not ok then
    log("run failed: " .. tostring(err))
    trigger.action.outText("ZONE SURVEY FAILED: " .. tostring(err), 60)
end
