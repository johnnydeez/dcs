-- Placement: geometry for putting ground units on valid ground. No mission logic.
-- Reads airbase geometry from plan.world.airbases[name] (runways, parking) and the
-- terrain via land.*; returns plain { x, z } points. Margins come from CONFIG.

Placement = {}

local BLOCKED_SURFACE = {}

-- Built lazily: land.SurfaceType does not exist when this file is loaded offline.
local function blockedSurface()
    if not next(BLOCKED_SURFACE) then
        BLOCKED_SURFACE[land.SurfaceType.RUNWAY]        = true
        BLOCKED_SURFACE[land.SurfaceType.WATER]         = true
        BLOCKED_SURFACE[land.SurfaceType.SHALLOW_WATER] = true
    end
    return BLOCKED_SURFACE
end

-- Random point on a ring { min_m, max_m } around anchor { x, z }.
function Placement.ringPoint(anchor, ring)
    local a = math.random() * 2 * math.pi
    local d = ring[1] + math.random() * (ring[2] - ring[1])
    return { x = anchor.x + d * math.cos(a), z = anchor.z + d * math.sin(a) }
end

-- Random point within `radius` of centre { x, z }.
function Placement.discPoint(centre, radius)
    local a = math.random() * 2 * math.pi
    local d = math.sqrt(math.random()) * radius
    return { x = centre.x + d * math.cos(a), z = centre.z + d * math.sin(a) }
end

-- True if p is inside any runway's keep-clear box: the runway plus CLEAR_RUNWAY_SIDE_M
-- either side, extended CLEAR_RUNWAY_END_M past each end. At a forested field
-- (base.forested) only the approach lane past each end is kept clear — the runway width
-- plus CLEAR_APPROACH_LANE_M either side — so the cleared overrun beside it is usable.
function Placement.onRunwayBox(base, p)
    for _, rw in ipairs(base.runways or {}) do
        local h  = math.rad(rw.heading_deg)
        local dx, dz = p.x - rw.x, p.z - rw.z
        local along  = math.abs(dx * math.cos(h) + dz * math.sin(h))
        local across = math.abs(-dx * math.sin(h) + dz * math.cos(h))
        local side   = rw.width / 2 + CONFIG.CLEAR_RUNWAY_SIDE_M
        if along <= rw.length / 2 + CONFIG.CLEAR_RUNWAY_END_M then
            if along > rw.length / 2 and base.forested then
                side = rw.width / 2 + CONFIG.CLEAR_APPROACH_LANE_M
            end
            if across <= side then return true end
        end
    end
    return false
end

-- True if p is within CLEAR_PARKING_M of any parking spot.
function Placement.nearParking(base, p)
    local r2 = CONFIG.CLEAR_PARKING_M * CONFIG.CLEAR_PARKING_M
    for _, s in ipairs(base.parking or {}) do
        local dx, dz = p.x - s[1], p.z - s[2]
        if dx * dx + dz * dz <= r2 then return true end
    end
    return false
end

-- True if p or any of 8 points on a CLEAR_SAMPLE_M ring is runway or water.
function Placement.badSurface(p)
    local blocked = blockedSurface()
    local r = CONFIG.CLEAR_SAMPLE_M
    if blocked[land.getSurfaceType({ x = p.x, y = p.z })] then return true end
    for i = 0, 7 do
        local a = i * math.pi / 4
        if blocked[land.getSurfaceType({ x = p.x + r * math.cos(a), y = p.z + r * math.sin(a) })] then
            return true
        end
    end
    return false
end

-- The one question every spawn point must pass. base may be nil (no airfield nearby).
-- Returns ok, reason.
function Placement.isClear(base, p)
    if base then
        if Placement.onRunwayBox(base, p) then return false, "runway" end
        if Placement.nearParking(base, p) then return false, "parking" end
    end
    if Placement.badSurface(p) then return false, "surface" end
    return true
end

-- The check for a point on an airfield road: off runway boxes and parking, and not on
-- runway/taxiway or water. No surface ring — a road may run beside a taxiway or a lake.
function Placement.isClearRoad(base, p)
    if Placement.onRunwayBox(base, p) then return false, "runway" end
    if Placement.nearParking(base, p) then return false, "parking" end
    if blockedSurface()[land.getSurfaceType({ x = p.x, y = p.z })] then return false, "surface" end
    return true
end

-- Tries `pointFn()` up to `tries` times until a point passes `clearFn` (default isClear)
-- and, if given, `extraCheck(p)` (returns ok, reason). pointFn may return nil (counted
-- as "no_point"). Returns point or nil, plus a { reason = count } tally of rejections.
function Placement.findClear(base, pointFn, tries, extraCheck, clearFn)
    clearFn = clearFn or Placement.isClear
    local rejects = {}
    for _ = 1, tries do
        local p = pointFn()
        local ok, why = false, "no_point"
        if p then ok, why = clearFn(base, p) end
        if ok and extraCheck then ok, why = extraCheck(p) end
        if ok then return p, rejects end
        rejects[why] = (rejects[why] or 0) + 1
    end
    return nil, rejects
end

-- ── Footprint anchors ───────────────────────────────────────────
-- Trees are invisible to the API, so placement starts from ground that is open by
-- construction instead of a blind ring. Derived at startup from the surveyed footprint
-- (data/airbase_footprints.lua) plus live runways/parking. Anchors by kind:
--   infield      grass between a runway's keep-clear edge and the first taxiway beyond
--                it — open on every field (DCS keeps the runway/taxiway strip clear)
--   apron        taxiway-surface cells whose 4 neighbours are taxiway surface too: inside
--                an apron. Thin taxiway lines can run through forest and are not anchors.
--   parking      parking spots
--   building     the airfield's own buildings (can sit in forest — infantry use them)
--   runway_side  just outside the runway keep-clear box, ONLY at fields with no taxiway
--                surface at all (short strips); elsewhere the sides without taxiways
--                are where the tree lines are.
--   runway_end   the cleared overrun beside each runway end's approach lane, ONLY at
--                forested fields (data/forested_airfields.lua), where it is the only
--                anchor kind: their infield, aprons and parking edges are forest.

local INFIELD_WALK_M     = 600   -- m beyond the keep-clear edge to look for a taxiway
local INFIELD_WALK_STEP  = 25    -- m per step of that walk
local INFIELD_ALONG_STEP = 50    -- m between stations along the runway
local INFIELD_POINT_STEP = 50    -- m between infield points across the band
local INFIELD_TAXI_PAD   = 40    -- m kept clear of the taxiway at the band's outer end
local RUNWAY_SIDE_STEP   = 150   -- m between runway_side anchors
local RUNWAY_SIDE_PAD    = 30    -- m beyond the runway keep-clear box
local RUNWAY_END_ALONG   = { 80, 380, 60 }   -- m past the threshold: from, to, step
local RUNWAY_END_ACROSS  = { 25, 45 }        -- m beyond the runway edge, either side:
                                             -- inside the ~±80 m cleared overrun

local function runwayPoint(rw, along, across)
    local h = math.rad(rw.heading_deg)
    return { x = rw.x + along * math.cos(h) - across * math.sin(h),
             z = rw.z + along * math.sin(h) + across * math.cos(h) }
end

-- ── Road fallback ───────────────────────────────────────────────
-- When a group finds no clear open ground, it goes onto one of the airfield's own roads
-- (perimeter and access roads): open by construction, and vehicles parked on a road
-- are normal.

-- Nearest point on the road network to p, or nil.
function Placement.snapToRoad(p)
    local rx, rz = land.getClosestPointOnRoads("roads", p.x, p.z)
    if not rx then return nil end
    return { x = rx, z = rz }
end

-- Direction the road runs at p (radians, atan2(dz, dx) like every heading here), or
-- nil. Snaps points 30 m out in 8 directions: the ones along the road come back ~30 m
-- away, the ones across it snap back to p.
function Placement.roadHeading(p)
    local best, bestD
    for i = 0, 7 do
        local a = i * math.pi / 4
        local q = Placement.snapToRoad({ x = p.x + 30 * math.cos(a), z = p.z + 30 * math.sin(a) })
        if q then
            local d = Util.dist(p, q)
            if not bestD or d > bestD then best, bestD = q, d end
        end
    end
    if not best or bestD < 5 then return nil end
    return math.atan2(best.z - p.z, best.x - p.x)
end

-- True if p is within `margin` m (default CONFIG.ROAD_FALLBACK_RUNWAY_M) of any runway's box.
function Placement.onAirfieldGround(base, p, margin)
    local m = margin or CONFIG.ROAD_FALLBACK_RUNWAY_M
    for _, rw in ipairs(base.runways or {}) do
        local h  = math.rad(rw.heading_deg)
        local dx, dz = p.x - rw.x, p.z - rw.z
        local along  = dx * math.cos(h) + dz * math.sin(h)
        local across = -dx * math.sin(h) + dz * math.cos(h)
        if math.abs(along) <= rw.length / 2 + m and math.abs(across) <= rw.width / 2 + m then
            return true
        end
    end
    return false
end

-- A random point on an airfield road: a random spot within `margin` m (default
-- CONFIG.ROAD_FALLBACK_RUNWAY_M) of a random runway's box, snapped to the nearest road.
-- nil if the snap lands outside that area.
function Placement.airfieldRoadPoint(base, margin)
    if not base.runways or #base.runways == 0 then return nil end
    local rw = Util.pick(base.runways)
    local m  = margin or CONFIG.ROAD_FALLBACK_RUNWAY_M
    local p  = Placement.snapToRoad(runwayPoint(rw, (math.random() - 0.5) * (rw.length + 2 * m),
                                                    (math.random() - 0.5) * (rw.width + 2 * m)))
    if p and Placement.onAirfieldGround(base, p, m) then return p end
    return nil
end

-- Returns { [kind] = { {x, z}, ... } } — only kinds that have points.
function Placement.buildAnchors(base, footprint)
    if base.forested then
        local ends = {}
        for _, rw in ipairs(base.runways or {}) do
            for _, dir in ipairs({ -1, 1 }) do
                for d = RUNWAY_END_ALONG[1], RUNWAY_END_ALONG[2], RUNWAY_END_ALONG[3] do
                    for _, c in ipairs(RUNWAY_END_ACROSS) do
                        for _, side in ipairs({ -1, 1 }) do
                            ends[#ends + 1] = runwayPoint(rw, dir * (rw.length / 2 + d), side * (rw.width / 2 + c))
                        end
                    end
                end
            end
        end
        return #ends > 0 and { runway_end = ends } or {}
    end
    local a = { infield = {}, apron = {}, parking = {}, building = {}, runway_side = {} }
    for _, s in ipairs(base.parking or {}) do a.parking[#a.parking + 1] = { x = s[1], z = s[2] } end

    local taxi, grid = {}, footprint and footprint.grid
    if footprint then
        for _, b in ipairs(footprint.buildings or {}) do a.building[#a.building + 1] = { x = b[1], z = b[2] } end
        for _, c in ipairs(footprint.taxiway or {}) do taxi[c[1] .. ":" .. c[2]] = true end
    end
    local function isTaxi(p)
        if not grid then return false end
        local i = math.floor((p.x - grid.x0) / grid.step + 0.5)
        local j = math.floor((p.z - grid.z0) / grid.step + 0.5)
        return taxi[i .. ":" .. j] == true
    end

    -- apron interiors
    for _, c in ipairs(footprint and footprint.taxiway or {}) do
        local i, j = c[1], c[2]
        if taxi[(i - 1) .. ":" .. j] and taxi[(i + 1) .. ":" .. j] and taxi[i .. ":" .. (j - 1)] and taxi[i .. ":" .. (j + 1)] then
            a.apron[#a.apron + 1] = { x = grid.x0 + i * grid.step, z = grid.z0 + j * grid.step }
        end
    end

    -- infield: walk out from each runway's keep-clear edge to the first taxiway
    local hasTaxi = next(taxi) ~= nil
    for _, rw in ipairs(base.runways or {}) do
        local edge = rw.width / 2 + CONFIG.CLEAR_RUNWAY_SIDE_M
        for along = -rw.length / 2, rw.length / 2, INFIELD_ALONG_STEP do
            for _, side in ipairs({ -1, 1 }) do
                for d = edge, edge + INFIELD_WALK_M, INFIELD_WALK_STEP do
                    if isTaxi(runwayPoint(rw, along, side * d)) then
                        for b = edge + INFIELD_POINT_STEP / 2, d - INFIELD_TAXI_PAD, INFIELD_POINT_STEP do
                            a.infield[#a.infield + 1] = runwayPoint(rw, along, side * b)
                        end
                        break
                    end
                end
            end
        end
        if not hasTaxi then
            local off = edge + RUNWAY_SIDE_PAD
            for along = -rw.length / 2, rw.length / 2, RUNWAY_SIDE_STEP do
                for _, side in ipairs({ -1, 1 }) do
                    a.runway_side[#a.runway_side + 1] = runwayPoint(rw, along, side * off)
                end
            end
        end
    end

    for kind, list in pairs(a) do
        if #list == 0 then a[kind] = nil end
    end
    return a
end

-- Picks an anchor for a component. spec = { [kind] = { weight, min_m, max_m } }: a kind
-- is chosen by weight among the kinds present, then a random anchor of that kind, then a
-- point min..max m from it. Returns point, kind — or nil when no listed kind exists.
function Placement.pickAnchorPoint(anchors, spec)
    local choices = {}
    for kind, s in pairs(spec) do
        if anchors[kind] and s[1] > 0 then choices[#choices + 1] = { kind, s[1] } end
    end
    if #choices == 0 then return nil end
    table.sort(choices, function(x, y) return x[1] < y[1] end)   -- stable across runs
    local kind = Util.weightedPick(choices)
    local s = spec[kind]
    return Placement.ringPoint(Util.pick(anchors[kind]), { s[2], s[3] }), kind
end
