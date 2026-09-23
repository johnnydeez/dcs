-- One-off survey (CONFIG.SURVEY_FOOTPRINTS): measures each airfield's built-up footprint
-- in-sim and writes it to Saved Games\DCS\kola_airbase_footprints.lua. Copy that file to
-- kola_f16\data\airbase_footprints.lua and turn the flag off — normal runs only read the
-- data file. Re-run after a map update.
--
-- Stores raw facts only; lib/placement.lua derives anchors (apron, infield, …) from them
-- at startup, so placement can be tuned without re-surveying.
--   * taxiway: land.getSurfaceType reports taxiways and aprons as RUNWAY. A 50 m grid
--     over the field; cells of RUNWAY surface outside every runway keep-clear box are
--     stored as { i, j } grid indices (point = grid.x0 + i*step, grid.z0 + j*step).
--   * buildings: world.searchObjects(SCENERY) within BUILDING_M of the taxiway/parking/
--     runway footprint — the airfield's own (towns sit farther out).
-- Probe findings behind this (2026-09-23): notes/kola_f16_generator_plan.md.
-- Also installs the result in AIRBASE_FOOTPRINT so the same run uses it.

SurveyAirbaseFootprints = {}

local GRID_STEP      = 50    -- m between surface samples
local GRID_MARGIN    = 700   -- m around the runways + parking bounding box
local BUILDING_M     = 250   -- m, a building this close to the footprint is the airfield's
local FP_RUNWAY_STEP = 100   -- m between runway centreline samples in the footprint
local OUT_FILE       = "kola_airbase_footprints.lua"

local function round(v) return math.floor(v + 0.5) end

-- Spatial hash for "any footprint point within r".
local function buildHash(points, cell)
    local h = {}
    for _, p in ipairs(points) do
        local k = math.floor(p.x / cell) .. ":" .. math.floor(p.z / cell)
        h[k] = h[k] or {}
        table.insert(h[k], p)
    end
    return h
end

local function withinHash(h, cell, p, r)
    local cx, cz = math.floor(p.x / cell), math.floor(p.z / cell)
    local r2 = r * r
    for i = cx - 1, cx + 1 do
        for j = cz - 1, cz + 1 do
            for _, q in ipairs(h[i .. ":" .. j] or {}) do
                local dx, dz = p.x - q.x, p.z - q.z
                if dx * dx + dz * dz <= r2 then return true end
            end
        end
    end
    return false
end

local function surveyBase(ab)
    -- bounding box of runways (ends) and parking
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    local function grow(x, z)
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
    end
    for _, rw in ipairs(ab.runways) do
        local h = math.rad(rw.heading_deg)
        for _, f in ipairs({ -0.5, 0.5 }) do
            grow(rw.x + f * rw.length * math.cos(h), rw.z + f * rw.length * math.sin(h))
        end
    end
    for _, s in ipairs(ab.parking) do grow(s[1], s[2]) end
    if minX == math.huge then grow(ab.anchor.x, ab.anchor.z) end
    local x0, z0 = round(minX - GRID_MARGIN), round(minZ - GRID_MARGIN)
    local ni = math.floor((maxX + GRID_MARGIN - x0) / GRID_STEP)
    local nj = math.floor((maxZ + GRID_MARGIN - z0) / GRID_STEP)

    -- surface grid: taxiway/apron = RUNWAY surface outside every runway box
    local taxiway, fp = {}, {}
    for i = 0, ni do
        for j = 0, nj do
            local p = { x = x0 + i * GRID_STEP, z = z0 + j * GRID_STEP }
            if land.getSurfaceType({ x = p.x, y = p.z }) == land.SurfaceType.RUNWAY
               and not Placement.onRunwayBox(ab, p) then
                taxiway[#taxiway + 1] = { i, j }
                fp[#fp + 1] = p
            end
        end
    end

    -- footprint points for the building test: taxiway + parking + runway centrelines
    for _, s in ipairs(ab.parking) do fp[#fp + 1] = { x = s[1], z = s[2] } end
    for _, rw in ipairs(ab.runways) do
        local h = math.rad(rw.heading_deg)
        for a = -rw.length / 2, rw.length / 2, FP_RUNWAY_STEP do
            fp[#fp + 1] = { x = rw.x + a * math.cos(h), z = rw.z + a * math.sin(h) }
        end
    end
    local hash = buildHash(fp, BUILDING_M)

    local cx, cz = x0 + ni * GRID_STEP / 2, z0 + nj * GRID_STEP / 2
    local radius = math.sqrt((ni * GRID_STEP) ^ 2 + (nj * GRID_STEP) ^ 2) / 2
    local buildings, scanned = {}, 0
    local volume = { id = world.VolumeType.SPHERE,
                     params = { point = { x = cx, y = land.getHeight({ x = cx, y = cz }), z = cz }, radius = radius } }
    local ok, err = pcall(world.searchObjects, Object.Category.SCENERY, volume, function(obj)
        scanned = scanned + 1
        local okP, pt = pcall(obj.getPoint, obj)
        if okP and pt and withinHash(hash, BUILDING_M, { x = pt.x, z = pt.z }, BUILDING_M) then
            local okT, tn = pcall(obj.getTypeName, obj)
            buildings[#buildings + 1] = { round(pt.x), round(pt.z), okT and tn or "?" }
        end
        return true
    end)
    if not ok then Log.warn("survey: searchObjects failed: " .. tostring(err)) end

    return {
        grid            = { x0 = x0, z0 = z0, step = GRID_STEP },
        taxiway         = taxiway,     -- { i, j } cells of taxiway/apron surface
        buildings       = buildings,   -- { x, z, type } the airfield's own buildings
        scenery_scanned = scanned,
    }
end

function SurveyAirbaseFootprints.run(world_)
    Log.info("--- Survey: airbase footprints ---")
    local out = {}
    for _, name in ipairs(world_.airbase_list) do
        local ok, res = pcall(surveyBase, world_.airbases[name])
        if ok then
            out[name] = res
            Log.info(string.format("  %-22s taxiway cells %4d, buildings %4d (of %d scanned)",
                name, #res.taxiway, #res.buildings, res.scenery_scanned))
        else
            Log.error("survey " .. name .. " failed: " .. tostring(res))
        end
    end

    local okD, date = pcall(os.date, "%Y-%m-%d")
    local header = table.concat({
        "-- Airbase footprints surveyed in-sim by survey/survey_airbase_footprints.lua"
            .. (okD and (" on " .. date) or "") .. " — do not hand-edit;",
        "-- re-run the survey (CONFIG.SURVEY_FOOTPRINTS) after a map update and copy",
        "-- Saved Games\\DCS\\" .. OUT_FILE .. " over this file. Plain data, no logic.",
        "--",
        "--   grid             { x0, z0, step } origin + spacing of the taxiway grid (m)",
        "--   taxiway          { i, j } cells of taxiway/apron surface (RUNWAY surface outside",
        "--                    the runway keep-clear boxes); point = x0 + i*step, z0 + j*step",
        "--   buildings        { x, z, type } the airfield's own buildings",
        "--   scenery_scanned  map objects searched (info only)",
        "-- lib/placement.lua derives the placement anchors (apron, infield, …) from these.",
        "",
    }, "\n")
    local path = Util.writeFile(OUT_FILE, header .. "AIRBASE_FOOTPRINT = " .. Util.serialize(out) .. "\n")
    if path then Log.info("  footprints written to " .. path .. " — copy to kola_f16\\data\\airbase_footprints.lua") end

    for name, res in pairs(out) do AIRBASE_FOOTPRINT[name] = res end
end
