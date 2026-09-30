-- Consumer: debug view of plan.base_defenses on the F10 map.
--   CONFIG.DRAW_DEFENSES: a ring at each defended base's anchor, coloured by defense
--                         level, and a text mark on each group: id + unit types
--   CONFIG.DRAW_ANCHORS:  a dot per placement anchor at each defended base — infield
--                         yellow, apron cyan, building magenta, runway side orange
--                         (parking spots are already labelled by DCS)
-- Reads the plan; writes nothing back to it.

DrawBaseDefenses = {}

-- Mark ids 4000-9999 (territory uses 1000-3999).
local _mark = 4000

local ANCHOR_COLOR = {
    infield     = { 1, 1, 0, 1 },
    apron       = { 0, 1, 1, 1 },
    building    = { 1, 0, 1, 1 },
    runway_side = { 1, 0.5, 0, 1 },
}
local ANCHOR_DOT_R   = 12
local MAX_DOTS_KIND  = 400

local function drawAnchors(plan)
    for name in pairs(plan.base_defenses.bases) do
        local anchors = Placement.buildAnchors(plan.world.airbases[name], AIRBASE_FOOTPRINT[name])
        for kind, color in pairs(ANCHOR_COLOR) do
            for i, p in ipairs(anchors[kind] or {}) do
                if i > MAX_DOTS_KIND then break end
                trigger.action.circleToAll(-1, _mark, Util.toVec3(p), ANCHOR_DOT_R, color, color, 1, true, "")
                _mark = _mark + 1
            end
        end
    end
end

local RING_RADIUS = 2500
local LEVEL_COLOR = {           -- positional {r, g, b, a}
    light    = { 0.2, 0.9, 0.2, 1 },
    standard = { 1.0, 0.9, 0.1, 1 },
    heavy    = { 1.0, 0.4, 0.0, 1 },
}
local NO_FILL = { 0, 0, 0, 0 }

-- "3x ZU-23 Emplacement" / "4x Soldier AK, 1x Soldier RPG"
local function unitText(units)
    local counts, order = {}, {}
    for _, u in ipairs(units) do
        if not counts[u.type] then order[#order + 1] = u.type end
        counts[u.type] = (counts[u.type] or 0) + 1
    end
    local parts = {}
    for _, t in ipairs(order) do parts[#parts + 1] = counts[t] .. "x " .. t end
    return table.concat(parts, ", ")
end

function DrawBaseDefenses.apply(plan)
    local bd = plan.base_defenses
    if not bd then return end
    if CONFIG.DRAW_ANCHORS then drawAnchors(plan) end
    if not CONFIG.DRAW_DEFENSES then return end

    for name, b in pairs(bd.bases) do
        local anchor = plan.world.airbases[name].anchor
        trigger.action.circleToAll(-1, _mark, Util.toVec3(anchor), RING_RADIUS,
            LEVEL_COLOR[b.level] or LEVEL_COLOR.standard, NO_FILL, 2, true, "")
        _mark = _mark + 1
    end

    for _, g in ipairs(bd.groups) do
        trigger.action.markToAll(_mark, g.id .. "\n" .. unitText(g.units), Util.toVec3(g.pos), true, "")
        _mark = _mark + 1
    end
end

-- One line for the on-screen summary.
function DrawBaseDefenses.summaryText(plan)
    local bd = plan.base_defenses
    if not bd then return "DEFENSES: not planned" end
    if bd.problems then return "DEFENSES: data errors — see dcs.log" end
    local t = bd.totals
    local n = 0
    for _ in pairs(bd.bases) do n = n + 1 end
    return string.format("DEFENSES: %d bases, %d groups / %d units  (red %d/%d, blue %d/%d)",
        n, t.groups, t.units, t.red.groups, t.red.units, t.blue.groups, t.blue.units)
end
