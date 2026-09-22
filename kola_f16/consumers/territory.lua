-- Consumer: applies plan.territory to the sim and draws it on the F10 map.
--   * sets every planned base's coalition (autoCapture off so it sticks)
--   * draws a territory circle at each base and a smaller circle at each zone,
--     coloured by the side the plan gave them
-- Reads the plan; writes nothing back to it.

Territory = {}

local SIDE_ID = { blue = coalition.side.BLUE, red = coalition.side.RED, neutral = coalition.side.NEUTRAL }

-- Colours are positional {r, g, b, a} — named keys draw nothing.
local COLORS = {
    blue    = { line = { 0,   0.45, 1,   1 }, fill = { 0,   0.45, 1,   0.30 } },
    red     = { line = { 1,   0.1,  0.1, 1 }, fill = { 1,   0.1,  0.1, 0.30 } },
    neutral = { line = { 0.7, 0.7,  0.7, 1 }, fill = { 0.7, 0.7,  0.7, 0.20 } },
}

-- Mark id ranges: bases 1000-1999, zones 2000-3999 (circle + label per zone).
local _baseMark = 1000
local _zoneMark = 2000

local function setBaseCoalition(name, side)
    local ab = Airbase.getByName(name)
    if not ab then
        Log.warn("Territory: airbase '" .. name .. "' not found")
        return false
    end
    ab:autoCapture(false)
    ab:setCoalition(SIDE_ID[side])
    return true
end

local function drawCircle(id, pos, radius, side)
    local c = COLORS[side] or COLORS.neutral
    trigger.action.circleToAll(-1, id, Util.toVec3(pos), radius, c.line, c.fill, 1, true, "")
end

function Territory.apply(plan)
    Log.info("--- Territory: apply ---")
    local world, terr = plan.world, plan.territory

    local ok, fail = 0, 0
    for name, b in pairs(terr.bases) do
        if setBaseCoalition(name, b.side) then
            ok = ok + 1
            drawCircle(_baseMark, world.airbases[name].pos, CONFIG.DRAW_BASE_RADIUS, b.side)
            _baseMark = _baseMark + 1
        else
            fail = fail + 1
        end
    end
    Log.info(string.format("  bases: %d set, %d not found", ok, fail))

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

-- On-screen summary of the roll for the debug pass.
function Territory.summaryText(plan)
    local terr = plan.territory
    local lines = { "=== KOLA — TERRITORY ROLL ===", "BLUE:" }
    for _, n in ipairs(terr.summary.blue) do lines[#lines + 1] = "  + " .. n end
    lines[#lines + 1] = "RED:"
    for _, n in ipairs(terr.summary.red) do lines[#lines + 1] = "  - " .. n end
    lines[#lines + 1] = string.format("FRONT (%d km): blue %s | red %s",
        terr.front.range_km,
        table.concat(terr.front.frontline.blue, ", "),
        table.concat(terr.front.frontline.red, ", "))
    for _, adj in ipairs(terr.front.adjacency) do
        lines[#lines + 1] = string.format("  %s <-> %s  %d km", adj.blue, adj.red, adj.km)
    end
    return table.concat(lines, "\n")
end
