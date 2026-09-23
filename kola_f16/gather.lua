-- Gather inputs: the one place that reads from DCS. Everything the stages need is
-- converted here into plain values on plan.world so no stage ever touches a DCS
-- object, and the plan dump is self-contained.
--
-- Position shape used everywhere in the plan: { x = north, z = east, lat, lon }.

Gather = {}

local SIDE_NAME = { [0] = "neutral", [1] = "red", [2] = "blue" }

local function round(v) return math.floor(v + 0.5) end

-- Counts how many of 4 points along a runway axis are runway surface.
local function runwayHits(x, z, headingRad, length)
    local hits = 0
    for _, f in ipairs({ -0.4, -0.2, 0.2, 0.4 }) do
        local px = x + f * length * math.cos(headingRad)
        local pz = z + f * length * math.sin(headingRad)
        if land.getSurfaceType({ x = px, y = pz }) == land.SurfaceType.RUNWAY then hits = hits + 1 end
    end
    return hits
end

-- Runways as plain data: { x, z, heading_deg, length, width, axis }. The sign convention
-- of `course` is inconsistently documented, so both candidates are probed against the
-- terrain and the one lying on runway surface wins; `axis` records which (or
-- "unverified" when neither probe hit runway surface).
local function gatherRunways(ab)
    local ok, rws = pcall(ab.getRunways, ab)
    if not ok or type(rws) ~= "table" then return {} end
    local out = {}
    for _, rw in ipairs(rws) do
        if rw.position and rw.course and rw.length then
            local x, z = rw.position.x, rw.position.z
            local hitsPos = runwayHits(x, z,  rw.course, rw.length)
            local hitsNeg = runwayHits(x, z, -rw.course, rw.length)
            local course, axis = -rw.course, "-course"
            if hitsPos > hitsNeg then course, axis = rw.course, "course" end
            if hitsPos == 0 and hitsNeg == 0 then axis = "unverified" end
            local deg = math.deg(course) % 360
            out[#out + 1] = {
                x = round(x), z = round(z),
                heading_deg = round(deg) % 360,
                length = round(rw.length), width = round(rw.width or 60),
                axis = axis,
            }
        end
    end
    return out
end

-- Parking spots as { x, z } — used to keep spawns off aprons.
local function gatherParking(ab)
    local ok, spots = pcall(ab.getParking, ab)
    if not ok or type(spots) ~= "table" then return {} end
    local out = {}
    for _, s in ipairs(spots) do
        local p = s.vTerminalPos
        if p then out[#out + 1] = { round(p.x), round(p.z) } end
    end
    return out
end

local function gatherAirbases(world_)
    local byName, list = {}, {}
    for _, ab in ipairs(world.getAirbases() or {}) do
        local desc = ab:getDesc()
        if desc.category == Airbase.Category.AIRDROME then
            local p = ab:getPoint()
            local runways = gatherRunways(ab)
            -- Anchor = mean runway midpoint: the middle of the field. getPoint() is the
            -- runway threshold, so rings around it sit lopsided (Syria lesson).
            local anchor
            if #runways > 0 then
                local sx, sz = 0, 0
                for _, rw in ipairs(runways) do sx, sz = sx + rw.x, sz + rw.z end
                anchor = Util.withLatLon({ x = sx / #runways, z = sz / #runways })
            else
                anchor = Util.withLatLon({ x = p.x, z = p.z })
            end
            local entry = {
                name     = ab:getName(),
                pos      = Util.withLatLon({ x = p.x, z = p.z }),
                anchor   = anchor,
                runways  = runways,
                parking  = gatherParking(ab),
                me_side  = SIDE_NAME[ab:getCoalition()] or "neutral",  -- as set in the ME, before we touch it
            }
            byName[entry.name] = entry
            list[#list + 1] = entry.name
        end
    end
    table.sort(list)
    world_.airbases = byName
    world_.airbase_list = list
end

local function gatherZones(world_)
    local byName, list = {}, {}
    for _, z in ipairs(ZONES) do
        local entry = {}
        for k, v in pairs(z) do entry[k] = v end
        entry.pos = Util.withLatLon({ x = z.x, z = z.z })
        entry.x, entry.z = nil, nil
        byName[z.name] = entry
        list[#list + 1] = z.name
    end
    table.sort(list)
    world_.zones = byName
    world_.zone_list = list
end

-- Reference point for anything evaluated "for the map as a whole" (sun position for
-- now): the centroid of all airdromes. Per-base evaluation comes later with the brief.
local function airbaseCentroid(world_)
    local sx, sz, n = 0, 0, 0
    for _, name in ipairs(world_.airbase_list) do
        local p = world_.airbases[name].pos
        sx, sz, n = sx + p.x, sz + p.z, n + 1
    end
    if n == 0 then return nil end
    local c = Util.withLatLon({ x = sx / n, z = sz / n })
    c.label = "airbase centroid"
    return c
end

-- Deep-copies the ME weather and derives the planner's view of it (lib/weather.lua).
-- The two atmosphere.* point queries are the only runtime measurements; they let the
-- debug display confirm the .miz wind-direction convention and the temperature.
local function gatherWeather(world_)
    local m = env.mission
    local function copy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = copy(v) end
        return out
    end

    local ref = airbaseCentroid(world_) or Util.withLatLon({ x = 0, z = 0 })
    local measured = {}
    local groundPt = { x = ref.x, y = land.getHeight({ x = ref.x, y = ref.z }) + 10, z = ref.z }
    local ok, wind = pcall(atmosphere.getWind, groundPt)
    if ok and wind then
        local mps = math.sqrt(wind.x * wind.x + wind.z * wind.z)
        measured.wind = { to_deg = Util.bearing({ x = 0, z = 0 }, { x = wind.x, z = wind.z }), mps = mps }
    else
        Log.warn("atmosphere.getWind failed: " .. tostring(wind))
    end
    local ok2, tempK, pressPa = pcall(atmosphere.getTemperatureAndPressure, groundPt)
    if ok2 and tempK then
        measured.temp_c = tempK - 273.15
        measured.pressure_hpa = pressPa and pressPa / 100 or nil
    else
        Log.warn("atmosphere.getTemperatureAndPressure failed: " .. tostring(tempK))
    end

    world_.time    = Weather.deriveTime(m.date, m.start_time, timer.getAbsTime(), ref)
    world_.weather = Weather.derive(copy(m.weather), measured)
end

-- Cross-checks the cluster table against what DCS reports.
local function checkClusters(world_)
    local inCluster = {}
    world_.unknown_bases = {}
    for _, c in ipairs(CLUSTERS) do
        for _, name in ipairs(c.bases) do
            inCluster[name] = c.id
            if not world_.airbases[name] then
                world_.unknown_bases[#world_.unknown_bases + 1] = name
                Log.warn("clusters.lua lists '" .. name .. "' but DCS has no such airdrome")
            end
        end
    end
    world_.unlisted_bases = {}
    for _, name in ipairs(world_.airbase_list) do
        if not inCluster[name] then
            world_.unlisted_bases[#world_.unlisted_bases + 1] = name
            Log.warn("DCS airdrome '" .. name .. "' is not in any cluster")
        end
    end
    world_.base_cluster = inCluster
end

function Gather.run()
    Log.info("--- Gather inputs ---")
    local w = {}
    w.rng_steps = Util.seedRandom()
    gatherAirbases(w)
    gatherZones(w)
    gatherWeather(w)
    checkClusters(w)
    Log.info(string.format("  %d airdromes, %d zones, %d clusters, rng advanced %d",
        #w.airbase_list, #w.zone_list, #CLUSTERS, w.rng_steps))
    local nRw, nPark, unverified = 0, 0, {}
    for _, name in ipairs(w.airbase_list) do
        local ab = w.airbases[name]
        nRw, nPark = nRw + #ab.runways, nPark + #ab.parking
        if #ab.runways == 0 then unverified[#unverified + 1] = name .. " (no runways)" end
        for _, rw in ipairs(ab.runways) do
            if rw.axis == "unverified" then unverified[#unverified + 1] = name .. " (axis)" end
        end
    end
    Log.info(string.format("  %d runways, %d parking spots", nRw, nPark))
    if #unverified > 0 then
        Log.warn("runway geometry unverified: " .. table.concat(unverified, ", "))
    end
    Log.info(string.format("  weather: %s, %s, vis %d m, %s; sun %+.1f° (%s)",
        w.weather.clouds.name, w.weather.clouds.coverage, w.weather.visibility_m,
        w.weather.flight_rules, w.time.sun.elev_deg, w.time.sun.condition))
    return w
end
