-- Inform: the territory on the F10 map: a circle at each base whose coalition was set
-- (execute\base_coalitions.lua) and a smaller circle at each zone, coloured by the side the
-- plan gave them.
-- Reads the plan; writes nothing back to it.

InformMapTerritory = {}

-- Colours are positional {r, g, b, a} — named keys draw nothing.
local COLORS = {
    blue    = { line = { 0,   0.45, 1,   1 }, fill = { 0,   0.45, 1,   0.30 } },
    red     = { line = { 1,   0.1,  0.1, 1 }, fill = { 1,   0.1,  0.1, 0.30 } },
    neutral = { line = { 0.7, 0.7,  0.7, 1 }, fill = { 0.7, 0.7,  0.7, 0.20 } },
}

-- Mark id ranges: bases 1000-1999, zones 2000-3999 (circle + label per zone).
local _baseMark = 1000
local _zoneMark = 2000

local function drawCircle(id, pos, radius, side)
    local c = COLORS[side] or COLORS.neutral
    trigger.action.circleToAll(-1, id, Util.toVec3(pos), radius, c.line, c.fill, 1, true, "")
end

-- `set`: the bases whose coalition was set (ExecuteBaseCoalitions.apply).
function InformMapTerritory.apply(plan, set)
    local world, terr = plan.world, plan.territory
    for name, b in pairs(terr.bases) do
        if set[name] then
            drawCircle(_baseMark, world.airbases[name].pos, CONFIG.DRAW_BASE_RADIUS, b.side)
            _baseMark = _baseMark + 1
        end
    end

    local counts = { blue = 0, red = 0, neutral = 0 }
    for _, name in ipairs(world.zone_list) do
        local side = terr.zones[name].side
        counts[side] = (counts[side] or 0) + 1
        local pos = world.zones[name].pos
        drawCircle(_zoneMark, pos, CONFIG.DRAW_ZONE_RADIUS, side)
        _zoneMark = _zoneMark + 1
        if CONFIG.DRAW_ZONE_LABELS then
            trigger.action.markToAll(_zoneMark, name, Util.toVec3(pos), true, "")
            _zoneMark = _zoneMark + 1
        end
    end
    Log.info(string.format("  zones: %d blue, %d red, %d neutral", counts.blue, counts.red, counts.neutral))
end
