-- Consumer: draws plan.airspace on the F10 map (CONFIG.DRAW_AIRSPACE): Blue airspace,
-- Red airspace and the contested airspace between them as filled areas, and the front
-- line on top. The grid cells are merged into as few rectangles as possible (runs along
-- a row, grown down while the rows below match), so the map stays light on marks.
-- Reads the plan; writes nothing back to it.

DrawAirspace = {}

-- Mark ids 60000+.
local _mark = 60000

-- Colours are positional {r, g, b, a}.
local FILL = {
    B = { 0,   0.45, 1,   0.15 },   -- Blue airspace
    R = { 1,   0.1,  0.1, 0.15 },   -- Red airspace
    C = { 1,   0.8,  0,   0.25 },   -- contested (on either coalition's ground)
}
local NO_LINE = { 0, 0, 0, 0 }
local FRONT_LINE_COLOR = { 0.1, 0.1, 0.1, 1 }
local LINE_SOLID = 1

-- b and r (contested on Blue / Red ground) draw as one contested class
local function classAt(a, i, j)
    local c = a.grid[i]:sub(j, j)
    if c == "b" or c == "r" then return "C" end
    return c
end

-- { { class, i, j, height, width } } covering the grid, no overlaps.
local function rectangles(a)
    local done, out = {}, {}
    for i = 1, a.rows do done[i] = {} end
    for i = 1, a.rows do
        for j = 1, a.cols do
            if not done[i][j] then
                local c = classAt(a, i, j)
                local w = 1
                while j + w <= a.cols and not done[i][j + w] and classAt(a, i, j + w) == c do w = w + 1 end
                local h = 1
                while i + h <= a.rows do
                    local same = true
                    for jj = j, j + w - 1 do
                        if done[i + h][jj] or classAt(a, i + h, jj) ~= c then same = false break end
                    end
                    if not same then break end
                    h = h + 1
                end
                for ii = i, i + h - 1 do for jj = j, j + w - 1 do done[ii][jj] = true end end
                out[#out + 1] = { c, i, j, h, w }
            end
        end
    end
    return out
end

function DrawAirspace.apply(plan)
    if not CONFIG.DRAW_AIRSPACE or not plan.airspace then return end
    local a = plan.airspace
    local rects = rectangles(a)
    for _, r in ipairs(rects) do
        local c, i, j, h, w = r[1], r[2], r[3], r[4], r[5]
        local p1 = { x = a.x0 + (i - 1) * a.cell_m, y = 0, z = a.z0 + (j - 1) * a.cell_m }
        local p2 = { x = a.x0 + (i - 1 + h) * a.cell_m, y = 0, z = a.z0 + (j - 1 + w) * a.cell_m }
        trigger.action.rectToAll(-1, _mark, p1, p2, NO_LINE, FILL[c], 0, true, "")
        _mark = _mark + 1
    end
    local segments = 0
    for _, line in ipairs(a.front_line) do
        for k = 2, #line do
            trigger.action.lineToAll(-1, _mark, Util.toVec3(line[k - 1]), Util.toVec3(line[k]),
                FRONT_LINE_COLOR, LINE_SOLID, true, "")
            _mark = _mark + 1
            segments = segments + 1
        end
    end
    Log.info(string.format("  airspace drawn: %d filled areas, front line %d segments", #rects, segments))
end

-- On-screen summary line.
function DrawAirspace.summaryText(plan)
    local s = plan.airspace and plan.airspace.summary
    if not s then return "" end
    local function k(v) return math.floor(v / 1000 + 0.5) end
    return string.format("AIRSPACE (1000 km²): blue %d, red %d, contested %d; front line %d km",
        k(s.blue_km2), k(s.red_km2), k(s.contested_km2), s.front_line_km)
end
