-- Airspace queries: where a point lies in the airspace the planner divided (plan.airspace,
-- planner\divide_airspace.lua, which describes the grid). Answers from its arguments only,
-- so every role may ask: the planner, Watch, Logs, the controller.

Airspace = {}

local HOLDER = { B = "blue", b = "blue", R = "red", r = "red" }


-- The cell holding pos, clamped to the grid.
function Airspace.cell(a, pos)
    local i = math.max(1, math.min(a.rows, math.floor((pos.x - a.x0) / a.cell_m) + 1))
    local j = math.max(1, math.min(a.cols, math.floor((pos.z - a.z0) / a.cell_m) + 1))
    return i, j
end

-- B / R own airspace, b / r contested on Blue / Red ground.
function Airspace.classAt(a, pos)
    local i, j = Airspace.cell(a, pos)
    return a.grid[i]:sub(j, j)
end

-- "own", "contested" or "enemy" airspace, seen from `coalition`.
function Airspace.kindFor(a, pos, coalition)
    local c = Airspace.classAt(a, pos)
    if c == "b" or c == "r" then return "contested" end
    return HOLDER[c] == coalition and "own" or "enemy"
end

function Airspace.regionAt(a, pos)
    local i, j = Airspace.cell(a, pos)
    return a.region_grid[i]:sub(j, j)
end

-- The front of the contested cell nearest pos within max_m (cell centres), and the
-- distance to it; 0 when pos is in contested airspace. nil when none is that close.
function Airspace.nearestFront(a, pos, max_m)
    local ci, cj = Airspace.cell(a, pos)
    local here = a.front_grid[ci]:sub(cj, cj)
    if here ~= "." then return here, 0 end
    local span = math.ceil(max_m / a.cell_m) + 1
    local best, bestD
    for i = math.max(1, ci - span), math.min(a.rows, ci + span) do
        local row = a.front_grid[i]
        local x = a.x0 + (i - 0.5) * a.cell_m
        for j = math.max(1, cj - span), math.min(a.cols, cj + span) do
            local f = row:sub(j, j)
            if f ~= "." then
                local z = a.z0 + (j - 0.5) * a.cell_m
                local d = math.sqrt((x - pos.x) ^ 2 + (z - pos.z) ^ 2)
                if d <= max_m and (not bestD or d < bestD) then best, bestD = f, d end
            end
        end
    end
    return best, bestD
end

-- The region of `coalition`'s held ground nearest pos (cell centres, within max_m): the
-- region that faces pos across the front. A target near a pocket faces the pocket even
-- when the contested airspace joins the pocket's front to the main one. nil if none.
function Airspace.facingRegion(a, pos, coalition, max_m)
    local ci, cj = Airspace.cell(a, pos)
    local span = math.ceil(max_m / a.cell_m) + 1
    local best, bestD
    for i = math.max(1, ci - span), math.min(a.rows, ci + span) do
        local row = a.grid[i]
        local x = a.x0 + (i - 0.5) * a.cell_m
        for j = math.max(1, cj - span), math.min(a.cols, cj + span) do
            if HOLDER[row:sub(j, j)] == coalition then
                local z = a.z0 + (j - 0.5) * a.cell_m
                local d = (x - pos.x) ^ 2 + (z - pos.z) ^ 2
                if d <= max_m * max_m and (not bestD or d < bestD) then best, bestD = a.region_grid[i]:sub(j, j), d end
            end
        end
    end
    return best
end
