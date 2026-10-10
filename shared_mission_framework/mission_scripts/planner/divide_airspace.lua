-- Stage (divide airspace): splits the map into Blue airspace, Red airspace and the
-- contested airspace between them, from the territory roll and the SAM network.
-- Reads plan.world, plan.territory, plan.sam_sites + AIRSPACE (data/airspace.lua).
-- Writes plan.airspace. Pure data.
--
-- On a grid of AIRSPACE.cell_km cells, each cell's centre is:
--   held ground  the coalition holding the nearest airbase
--   contested    within front_band_km of the front line (where held ground flips), or
--                under the other coalition's SAM reach
--   otherwise    its holder's own airspace
--
-- plan.airspace = {
--   cell_m, x0, z0, rows, cols,         cell (i, j) spans x0 + (i-1)·cell_m … and z0 + (j-1)·cell_m …
--   grid       = { "BBBbbrRRR…", … },   one string per row i (x, north), one character per column j
--                                        (z, east): B / R own airspace, b / r contested on Blue / Red ground
--   front_line = { { { x, z }, … }, … }, polylines where held ground flips
--   regions    = { [id] = { id, coalition, km2, bases = { names }, main } }
--   region_grid = { "AAAABBB…", … }     region id per cell, same layout as grid
--   fronts     = { [id] = { id, km2, regions = { blue = { ids }, red = { ids } } } }
--   front_grid = { "..AA..", … }         front id per contested cell, "." elsewhere
--   summary    = { blue_km2, red_km2, contested_km2, contested_on = { blue, red },
--                  contested_by = { front_band, enemy_sam }, front_line_km, regions, fronts },
-- }
-- A region is one connected piece of a coalition's held ground (4-neighbour): usually one
-- per coalition, more when the roll leaves a pocket. `main` marks each coalition's
-- largest. A front is one connected stretch of contested airspace (8-neighbour); it
-- touches the regions its cells lie in. A flight from a base belongs on the fronts its
-- base's region touches, never across enemy ground to another front.
-- The lookups on this table (classAt, kindFor, regionAt, nearestFront, facingRegion) are
-- the tool tools\airspace.lua (Airspace), asked by every role.

PlannerDivideAirspace = {}

-- One character per region / front id.
local IDS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local HOLDER = { B = "blue", b = "blue", R = "red", r = "red" }

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- ── regions and fronts ──────────────────────────────────────────

-- Labels connected cells for which member(i, j) is true: 4 or 8 neighbours. Returns
-- label[i][j] (number) and the cells per label.
local function label(rows, cols, member, eight)
    local lab, sizes, n = {}, {}, 0
    for i = 1, rows do lab[i] = {} end
    local steps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    if eight then
        steps[5], steps[6], steps[7], steps[8] = { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }
    end
    for i = 1, rows do
        for j = 1, cols do
            if not lab[i][j] and member(i, j) then
                n = n + 1
                local key = member(i, j)
                local stack, size = { { i, j } }, 0
                lab[i][j] = n
                while #stack > 0 do
                    local c = table.remove(stack)
                    size = size + 1
                    for _, s in ipairs(steps) do
                        local ii, jj = c[1] + s[1], c[2] + s[2]
                        if ii >= 1 and ii <= rows and jj >= 1 and jj <= cols and not lab[ii][jj]
                           and member(ii, jj) == key then
                            lab[ii][jj] = n
                            stack[#stack + 1] = { ii, jj }
                        end
                    end
                end
                sizes[n] = size
            end
        end
    end
    return lab, sizes, n
end

local function regionsAndFronts(plan, a, cellKm2)
    local rows, cols = a.rows, a.cols
    local function holder(i, j) return HOLDER[a.grid[i]:sub(j, j)] end
    local function contested(i, j)
        local c = a.grid[i]:sub(j, j)
        return (c == "b" or c == "r") and "contested" or nil
    end
    local rLab, rSize, rCount = label(rows, cols, holder, false)
    local fLab, fSize, fCount = label(rows, cols, contested, true)
    if rCount > #IDS or fCount > #IDS then
        Log.warn(string.format("  %d regions / %d fronts — more than %d ids; the rest share the last", rCount, fCount, #IDS))
    end
    local function id(n) return IDS:sub(math.min(n, #IDS), math.min(n, #IDS)) end

    local regions, fronts = {}, {}
    local regionGrid, frontGrid = {}, {}
    for i = 1, rows do
        local rc, fc = {}, {}
        for j = 1, cols do
            local r = id(rLab[i][j])
            rc[j] = r
            if not regions[r] then
                regions[r] = { id = r, coalition = holder(i, j), km2 = rSize[rLab[i][j]] * cellKm2, bases = {} }
            end
            if fLab[i][j] then
                local f = id(fLab[i][j])
                fc[j] = f
                local front = fronts[f]
                if not front then
                    front = { id = f, km2 = fSize[fLab[i][j]] * cellKm2, regions = { blue = {}, red = {} }, seen = {} }
                    fronts[f] = front
                end
                if not front.seen[r] then
                    front.seen[r] = true
                    table.insert(front.regions[regions[r].coalition], r)
                end
            else
                fc[j] = "."
            end
        end
        regionGrid[i], frontGrid[i] = table.concat(rc), table.concat(fc)
    end
    for _, f in pairs(fronts) do
        f.seen = nil
        table.sort(f.regions.blue)
        table.sort(f.regions.red)
    end
    a.region_grid, a.front_grid = regionGrid, frontGrid

    local names = {}
    for name in pairs(plan.territory.bases) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local r = regions[Airspace.regionAt(a, plan.world.airbases[name].pos)]
        table.insert(r.bases, name)
    end
    for _, c in ipairs({ "blue", "red" }) do
        local largest
        for _, r in pairs(regions) do
            if r.coalition == c and (not largest or r.km2 > largest.km2) then largest = r end
        end
        if largest then largest.main = true end
    end
    return regions, fronts, rCount, fCount
end

local OWN       = { blue = "B", red = "R" }
local CONTESTED = { blue = "b", red = "r" }
local ENEMY     = { blue = "red", red = "blue" }

-- Distance to the nearest of the positions.
local function nearest(list, x, z)
    local best = math.huge
    for _, p in ipairs(list) do
        local dx, dz = p.x - x, p.z - z
        local d = dx * dx + dz * dz
        if d < best then best = d end
    end
    return math.sqrt(best)
end

local function underSam(sites, x, z)
    for _, s in ipairs(sites) do
        local dx, dz = s.x - x, s.z - z
        if dx * dx + dz * dz <= s.reach2 then return true end
    end
    return false
end

-- ── front line: marching squares on (distance to nearest Red base − to nearest Blue) ──

-- Where the front line crosses the grid edge between corners a and b. Keyed by the edge,
-- so the two cells sharing an edge produce the same point and the pieces chain.
local function crossing(corner, pts, ia, ja, ib, jb, x0, z0, cell)
    local key = ia .. "," .. ja .. ":" .. ib .. "," .. jb
    if not pts[key] then
        local fa, fb = corner[ia][ja], corner[ib][jb]
        local t = fa / (fa - fb)
        pts[key] = { x = x0 + ((ia - 1) + t * (ib - ia)) * cell, z = z0 + ((ja - 1) + t * (jb - ja)) * cell }
    end
    return key
end

local function frontSegments(corner, rows, cols, x0, z0, cell)
    local pts, segments = {}, {}
    for i = 1, rows do
        for j = 1, cols do
            local f1, f2, f3, f4 = corner[i][j], corner[i][j + 1], corner[i + 1][j + 1], corner[i + 1][j]
            -- edges: 1 = (i,j)-(i,j+1), 2 = (i,j+1)-(i+1,j+1), 3 = (i+1,j)-(i+1,j+1), 4 = (i,j)-(i+1,j)
            local cut = {}
            if (f1 >= 0) ~= (f2 >= 0) then cut[1] = crossing(corner, pts, i, j, i, j + 1, x0, z0, cell) end
            if (f2 >= 0) ~= (f3 >= 0) then cut[2] = crossing(corner, pts, i, j + 1, i + 1, j + 1, x0, z0, cell) end
            if (f4 >= 0) ~= (f3 >= 0) then cut[3] = crossing(corner, pts, i + 1, j, i + 1, j + 1, x0, z0, cell) end
            if (f1 >= 0) ~= (f4 >= 0) then cut[4] = crossing(corner, pts, i, j, i + 1, j, x0, z0, cell) end
            if cut[1] and cut[2] and cut[3] and cut[4] then
                -- saddle: the centre's sign decides which corners join
                if ((f1 + f2 + f3 + f4) >= 0) == (f1 >= 0) then
                    segments[#segments + 1] = { cut[1], cut[2] }
                    segments[#segments + 1] = { cut[3], cut[4] }
                else
                    segments[#segments + 1] = { cut[4], cut[1] }
                    segments[#segments + 1] = { cut[2], cut[3] }
                end
            else
                local a, b
                for e = 1, 4 do
                    if cut[e] then if a then b = cut[e] else a = cut[e] end end
                end
                if b then segments[#segments + 1] = { a, b } end
            end
        end
    end
    return segments, pts
end

-- Joins segments that share an end into polylines of points.
local function chain(segments, pts)
    local at = {}   -- point key → segment indices
    for n, s in ipairs(segments) do
        for _, k in ipairs(s) do
            at[k] = at[k] or {}
            table.insert(at[k], n)
        end
    end
    local used, lines = {}, {}
    local function walk(startKey)
        local line, key = { pts[startKey] }, startKey
        while true do
            local nextSeg
            for _, n in ipairs(at[key]) do if not used[n] then nextSeg = n break end end
            if not nextSeg then break end
            used[nextSeg] = true
            local s = segments[nextSeg]
            key = (s[1] == key) and s[2] or s[1]
            line[#line + 1] = pts[key]
        end
        return line
    end
    -- open lines start at an end (a key with one segment), then whatever loops are left
    for key, list in pairs(at) do
        if #list == 1 and not used[list[1]] then lines[#lines + 1] = walk(key) end
    end
    for n, s in ipairs(segments) do
        if not used[n] then lines[#lines + 1] = walk(s[1]) end
    end
    return lines
end

-- Douglas–Peucker: drops points within tolerance of the line through their neighbours.
local function simplify(line, tolerance)
    if #line < 3 then return line end
    local keep = { [1] = true, [#line] = true }
    local function run(a, b)
        local ax, az, bx, bz = line[a].x, line[a].z, line[b].x, line[b].z
        local dx, dz = bx - ax, bz - az
        local len = math.sqrt(dx * dx + dz * dz)
        local worst, worstD = nil, tolerance
        for k = a + 1, b - 1 do
            local px, pz = line[k].x - ax, line[k].z - az
            local d = len > 0 and math.abs(px * dz - pz * dx) / len or math.sqrt(px * px + pz * pz)
            if d > worstD then worst, worstD = k, d end
        end
        if worst then
            keep[worst] = true
            run(a, worst)
            run(worst, b)
        end
    end
    run(1, #line)
    local out = {}
    for k = 1, #line do if keep[k] then out[#out + 1] = line[k] end end
    return out
end

local function lineLength(line)
    local m = 0
    for k = 2, #line do m = m + Util.dist(line[k - 1], line[k]) end
    return m
end

function PlannerDivideAirspace.run(plan)
    Log.info("--- Stage: divide airspace ---")
    local A = AIRSPACE
    local cell = A.cell_km * 1000
    local band = A.front_band_km * 1000

    local bases = { blue = {}, red = {} }
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for name, b in pairs(plan.territory.bases) do
        local pos = plan.world.airbases[name].pos
        if bases[b.side] then table.insert(bases[b.side], pos) end
        minX, maxX = math.min(minX, pos.x), math.max(maxX, pos.x)
        minZ, maxZ = math.min(minZ, pos.z), math.max(maxZ, pos.z)
    end
    local sams = { blue = {}, red = {} }
    for _, s in ipairs(plan.sam_sites.sites) do
        if A.sam_layers[s.layer] and sams[s.side] then
            local reach = s.engage_m * A.sam_reach_fraction
            table.insert(sams[s.side], { x = s.pos.x, z = s.pos.z, reach2 = reach * reach })
        end
    end

    local margin = A.margin_km * 1000
    local x0, z0 = minX - margin, minZ - margin
    local rows = math.ceil((maxX + margin - x0) / cell)
    local cols = math.ceil((maxZ + margin - z0) / cell)

    local grid, cellKm2 = {}, (cell / 1000) ^ 2
    local summary = { blue_km2 = 0, red_km2 = 0, contested_km2 = 0, contested_on = { blue = 0, red = 0 },
                      contested_by = { front_band = 0, enemy_sam = 0 } }
    for i = 1, rows do
        local x = x0 + (i - 0.5) * cell
        local chars = {}
        for j = 1, cols do
            local z = z0 + (j - 0.5) * cell
            local dBlue, dRed = nearest(bases.blue, x, z), nearest(bases.red, x, z)
            local holder = dBlue <= dRed and "blue" or "red"
            -- distance to the front line, as the halved difference of the two nearest bases
            local toFront = math.abs(dRed - dBlue) / 2
            local reason
            if toFront <= band then
                reason = "front_band"
            elseif underSam(sams[ENEMY[holder]], x, z) then
                reason = "enemy_sam"
            end
            if reason then
                chars[j] = CONTESTED[holder]
                summary.contested_km2 = summary.contested_km2 + cellKm2
                summary.contested_on[holder] = summary.contested_on[holder] + cellKm2
                summary.contested_by[reason] = summary.contested_by[reason] + cellKm2
            else
                chars[j] = OWN[holder]
                summary[holder .. "_km2"] = summary[holder .. "_km2"] + cellKm2
            end
        end
        grid[i] = table.concat(chars)
    end

    -- the front line itself, on the grid corners
    local corner = {}
    for i = 1, rows + 1 do
        corner[i] = {}
        local x = x0 + (i - 1) * cell
        for j = 1, cols + 1 do
            local z = z0 + (j - 1) * cell
            corner[i][j] = nearest(bases.red, x, z) - nearest(bases.blue, x, z)
        end
    end
    local segments, pts = frontSegments(corner, rows, cols, x0, z0, cell)
    local frontLine, frontM = {}, 0
    for _, line in ipairs(chain(segments, pts)) do
        local simple = simplify(line, A.simplify_km * 1000)
        frontLine[#frontLine + 1] = simple
        frontM = frontM + lineLength(line)
    end
    summary.front_line_km = math.floor(frontM / 1000)

    local a = { cell_m = cell, x0 = x0, z0 = z0, rows = rows, cols = cols, grid = grid,
                front_line = frontLine, summary = summary }
    local regions, fronts, regionCount, frontCount = regionsAndFronts(plan, a, cellKm2)
    a.regions, a.fronts = regions, fronts
    summary.regions, summary.fronts = regionCount, frontCount
    plan.airspace = a

    local function k(v) return math.floor(v / 1000 + 0.5) end
    for _, id in ipairs(sortedKeys(regions)) do
        local r = regions[id]
        Log.info(string.format("  region %s: %s%s, %d thousand km², bases: %s", id, r.coalition:upper(),
            r.main and "" or " POCKET", k(r.km2), #r.bases > 0 and table.concat(r.bases, ", ") or "none"))
    end
    for _, id in ipairs(sortedKeys(fronts)) do
        local f = fronts[id]
        Log.info(string.format("  front %s: %d thousand km², touches blue region(s) %s, red region(s) %s", id, k(f.km2),
            #f.regions.blue > 0 and table.concat(f.regions.blue, ",") or "none",
            #f.regions.red > 0 and table.concat(f.regions.red, ",") or "none"))
    end
    Log.info(string.format("  grid %d x %d cells of %d km; front line %d km in %d piece(s)", rows, cols, A.cell_km,
        summary.front_line_km, #frontLine))
    Log.info(string.format("  airspace (1000 km²): blue %d, red %d, contested %d (on blue ground %d, on red %d; "
        .. "front band %d, under enemy SAMs %d)", k(summary.blue_km2), k(summary.red_km2), k(summary.contested_km2),
        k(summary.contested_on.blue), k(summary.contested_on.red), k(summary.contested_by.front_band),
        k(summary.contested_by.enemy_sam)))
    return plan
end
