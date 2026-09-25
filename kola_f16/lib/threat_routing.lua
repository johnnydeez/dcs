-- Routes around threat circles: a path search on a coarse grid over the map, where
-- every cell inside a threat circle costs much more to cross than open sky (but isn't
-- forbidden), then smoothed down to a few waypoints. Pure logic over plain data, no DCS
-- calls — used by the air tasking stage for routes that stay out of SAM rings wherever a
-- reasonable way around exists.
--
--   local map = ThreatRouting.buildMap(circles, bounds)
--       circles = { { id, x, z, radius_m } }, bounds = { min_x, max_x, min_z, max_z }
--   local points = ThreatRouting.route(map, from, to)       -- { { x, z } }, from … to
--   local ids = ThreatRouting.crossed(map, points)          -- circle ids the route enters
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

local function heapPush(h, f, id)
    h[#h + 1] = { f, id }
    local i = #h
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p][1] <= h[i][1] then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end

local function heapPop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, s = 2 * i, 2 * i + 1, i
            if l <= #h and h[l][1] < h[s][1] then s = l end
            if r <= #h and h[r][1] < h[s][1] then s = r end
            if s == i then break end
            h[s], h[i] = h[i], h[s]
            i = s
        end
    end
    return top
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function search(map, from, to)
    local nx, w = map.nx, map.weight
    local sx, sz = cellOf(map, from)
    local gx, gz = cellOf(map, to)
    local start, goal = sz * nx + sx + 1, gz * nx + gx + 1
    local g, came, closed, open = { [start] = 0 }, {}, {}, {}
    heapPush(open, 0, start)
    while #open > 0 do
        local id = heapPop(open)[2]
        if id == goal then break end
        if not closed[id] then
            closed[id] = true
            local ix, iz = (id - 1) % nx, math.floor((id - 1) / nx)
            for _, d in ipairs(NEIGHBOURS) do
                local jx, jz = ix + d[1], iz + d[2]
                if jx >= 0 and jx < nx and jz >= 0 and jz < map.nz then
                    local j = jz * nx + jx + 1
                    if not closed[j] then
                        local step = (d[1] ~= 0 and d[2] ~= 0) and 1.41421356 or 1
                        local cost = g[id] + step * (w[id] + w[j]) / 2
                        if not g[j] or cost < g[j] then
                            g[j], came[j] = cost, id
                            local h = math.sqrt((jx - gx) ^ 2 + (jz - gz) ^ 2)
                            heapPush(open, cost + h, j)
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

function ThreatRouting.route(map, from, to)
    if segmentMax(map, from, to) == 0 then return { { x = from.x, z = from.z }, { x = to.x, z = to.z } } end
    return smooth(map, search(map, from, to))
end

-- Ids of the circles any segment of the route enters.
function ThreatRouting.crossed(map, points)
    local hit, ids = {}, {}
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
        local steps = math.max(1, math.ceil(d / SAMPLE_M))
        for s = 0, steps do
            local t = s / steps
            local x, z = a.x + t * (b.x - a.x), a.z + t * (b.z - a.z)
            for _, c in ipairs(map.circles) do
                if not hit[c.id] and (x - c.x) ^ 2 + (z - c.z) ^ 2 < c.r2 then
                    hit[c.id] = true
                    ids[#ids + 1] = c.id
                end
            end
        end
    end
    table.sort(ids)
    return ids
end
