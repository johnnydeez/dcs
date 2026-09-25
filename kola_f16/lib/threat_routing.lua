-- Routes around threat circles: a path search on a coarse grid over the map, where
-- every cell inside a threat circle costs much more to cross than open sky (but isn't
-- forbidden), then smoothed down to a few waypoints. Pure logic over plain data, no DCS
-- calls — used by the air tasking stage for routes that stay out of SAM rings wherever a
-- reasonable way around exists.
--
--   local map = ThreatRouting.buildMap(circles, bounds)
--       circles = { { id, x, z, radius_m } }, bounds = { min_x, max_x, min_z, max_z }
--   local points = ThreatRouting.route(map, from, to, max_length_m)
--       { { x, z } }, from … to; max_length_m (optional) keeps the search to paths no
--       longer than that — the straight line when none exists
--   local ids = ThreatRouting.crossed(map, points)          -- circle ids the route enters,
--                                                           -- in the order it enters them
--   local c = ThreatRouting.circle(map, id)                 -- { id, x, z, r2 } or nil
--   ThreatRouting.length(points)                            -- metres

ThreatRouting = {}

local CELL_M         = 10000   -- grid cell size
local THREAT_COST    = 25      -- a cell inside one circle costs this many times open sky, per circle
local SAMPLE_M       = 2000    -- segment check step when smoothing and when listing crossed circles

-- ── helpers ─────────────────────────────────────────────────────

local function countAt(map, x, z)
    local n = 0
    for _, c in ipairs(map.circles) do
        local dx, dz = x - c.x, z - c.z
        if dx * dx + dz * dz < c.r2 then n = n + 1 end
    end
    return n
end

-- Highest number of circles covering any sample point on the segment a → b.
local function segmentMax(map, a, b)
    local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
    local steps = math.max(1, math.ceil(d / SAMPLE_M))
    local m = 0
    for i = 0, steps do
        local t = i / steps
        local n = countAt(map, a.x + t * (b.x - a.x), a.z + t * (b.z - a.z))
        if n > m then m = n end
    end
    return m
end

function ThreatRouting.length(points)
    local len = 0
    for i = 2, #points do
        len = len + math.sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].z - points[i - 1].z) ^ 2)
    end
    return len
end

-- ── the grid ────────────────────────────────────────────────────

function ThreatRouting.buildMap(circles, bounds)
    local map = { circles = {}, x0 = bounds.min_x, z0 = bounds.min_z }
    for _, c in ipairs(circles) do
        map.circles[#map.circles + 1] = { id = c.id, x = c.x, z = c.z, r2 = c.radius_m * c.radius_m }
    end
    map.nx = math.ceil((bounds.max_x - bounds.min_x) / CELL_M) + 1
    map.nz = math.ceil((bounds.max_z - bounds.min_z) / CELL_M) + 1
    map.weight = {}
    for iz = 0, map.nz - 1 do
        for ix = 0, map.nx - 1 do
            local n = countAt(map, map.x0 + ix * CELL_M, map.z0 + iz * CELL_M)
            map.weight[iz * map.nx + ix + 1] = 1 + THREAT_COST * n
        end
    end
    return map
end

local function cellOf(map, p)
    local ix = math.max(0, math.min(map.nx - 1, math.floor((p.x - map.x0) / CELL_M + 0.5)))
    local iz = math.max(0, math.min(map.nz - 1, math.floor((p.z - map.z0) / CELL_M + 0.5)))
    return ix, iz
end

-- ── path search (A*, 8 neighbours) ──────────────────────────────

-- The open list is a binary heap kept in two parallel arrays (f values, cell ids), so a
-- search allocates no table per step — the search is most of the air tasking stage's time.
local NEIGHBOUR_X    = { 1, -1, 0, 0, 1, 1, -1, -1 }
local NEIGHBOUR_Z    = { 0, 0, 1, -1, 1, -1, 1, -1 }
local NEIGHBOUR_STEP = { 1, 1, 1, 1, 1.41421356, 1.41421356, 1.41421356, 1.41421356 }

-- Cells whose centre is farther than max_length_m from→cell→to (plus a cell's slack for
-- the endpoints' snapping) are never entered: every path through them is too long.
local function search(map, from, to, max_length_m)
    local nx, nz, w = map.nx, map.nz, map.weight
    local sqrt, floor = math.sqrt, math.floor
    local sx, sz = cellOf(map, from)
    local gx, gz = cellOf(map, to)
    local limit = max_length_m and (max_length_m + 2 * CELL_M) / CELL_M
    local fx, fz = (from.x - map.x0) / CELL_M, (from.z - map.z0) / CELL_M
    local tx, tz = (to.x - map.x0) / CELL_M, (to.z - map.z0) / CELL_M
    local start, goal = sz * nx + sx + 1, gz * nx + gx + 1
    local g, came, closed = { [start] = 0 }, {}, {}
    local hf, hid, n = { 0 }, { start }, 1
    while n > 0 do
        -- pop the lowest f
        local id = hid[1]
        local lf, lid = hf[n], hid[n]
        hf[n], hid[n] = nil, nil
        n = n - 1
        if n > 0 then
            local i = 1
            hf[1], hid[1] = lf, lid
            while true do
                local l, r, s = 2 * i, 2 * i + 1, i
                if l <= n and hf[l] < hf[s] then s = l end
                if r <= n and hf[r] < hf[s] then s = r end
                if s == i then break end
                hf[s], hf[i] = hf[i], hf[s]
                hid[s], hid[i] = hid[i], hid[s]
                i = s
            end
        end
        if id == goal then break end
        if not closed[id] then
            closed[id] = true
            local ix, iz = (id - 1) % nx, floor((id - 1) / nx)
            local gid, wid = g[id], w[id]
            for k = 1, 8 do
                local jx, jz = ix + NEIGHBOUR_X[k], iz + NEIGHBOUR_Z[k]
                if jx >= 0 and jx < nx and jz >= 0 and jz < nz
                   and (not limit or sqrt((jx - fx) ^ 2 + (jz - fz) ^ 2) + sqrt((jx - tx) ^ 2 + (jz - tz) ^ 2) <= limit) then
                    local j = jz * nx + jx + 1
                    if not closed[j] then
                        local cost = gid + NEIGHBOUR_STEP[k] * (wid + w[j]) / 2
                        local gj = g[j]
                        if not gj or cost < gj then
                            g[j], came[j] = cost, id
                            -- push
                            local dx, dz = jx - gx, jz - gz
                            local f = cost + sqrt(dx * dx + dz * dz)
                            n = n + 1
                            hf[n], hid[n] = f, j
                            local i = n
                            while i > 1 do
                                local p = floor(i / 2)
                                if hf[p] <= hf[i] then break end
                                hf[p], hf[i] = hf[i], hf[p]
                                hid[p], hid[i] = hid[i], hid[p]
                                i = p
                            end
                        end
                    end
                end
            end
        end
    end
    local cells, id = {}, goal
    while id do
        table.insert(cells, 1, id)
        id = came[id]
    end
    local pts = {}
    for i, c in ipairs(cells) do
        pts[i] = { x = map.x0 + ((c - 1) % nx) * CELL_M, z = map.z0 + math.floor((c - 1) / nx) * CELL_M }
    end
    pts[1] = { x = from.x, z = from.z }
    if #pts == 1 then pts[2] = { x = to.x, z = to.z } else pts[#pts] = { x = to.x, z = to.z } end
    return pts
end

-- Drops path points while the straight line between the kept points is no more exposed
-- than the stretch of path it replaces.
local function smooth(map, pts)
    local out, i = { pts[1] }, 1
    while i < #pts do
        local best = i + 1
        local limit = countAt(map, pts[i].x, pts[i].z)
        for j = i + 1, #pts do
            local n = countAt(map, pts[j].x, pts[j].z)
            if n > limit then limit = n end
            if j > i + 1 then
                if segmentMax(map, pts[i], pts[j]) <= limit then best = j else break end
            end
        end
        out[#out + 1] = pts[best]
        i = best
    end
    return out
end

function ThreatRouting.route(map, from, to, max_length_m)
    if segmentMax(map, from, to) == 0 then return { { x = from.x, z = from.z }, { x = to.x, z = to.z } } end
    return smooth(map, search(map, from, to, max_length_m))
end

function ThreatRouting.circle(map, id)
    for _, c in ipairs(map.circles) do
        if c.id == id then return c end
    end
    return nil
end

-- Ids of the circles any segment of the route enters, in the order the route enters them
-- (circles entered at the same sample point in id order).
function ThreatRouting.crossed(map, points)
    local hit, ids = {}, {}
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        local steps = math.max(1, math.ceil(d / SAMPLE_M))
        for s = 0, steps do
            local t = s / steps
            local x, z = a.x + t * (b.x - a.x), a.z + t * (b.z - a.z)
            local here = {}
            for _, c in ipairs(map.circles) do
                if not hit[c.id] and (x - c.x) ^ 2 + (z - c.z) ^ 2 < c.r2 then
                    hit[c.id] = true
                    here[#here + 1] = c.id
                end
            end
            table.sort(here)
            for _, id in ipairs(here) do ids[#ids + 1] = id end
        end
    end
    return ids
end
