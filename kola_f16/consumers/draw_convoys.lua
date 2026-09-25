-- Consumer: debug view of plan.convoys on the F10 map.
--   CONFIG.DRAW_CONVOYS: the planned route as a dashed line through the waypoints, in the
--   coalition's colour, a text mark at the start (id, what it is, where it goes, how
--   long it takes) and one at the parking spot.
-- Reads the plan; writes nothing back to it.

DrawConvoys = {}

-- Mark ids 40000-49999 (territory 1000-3999, base defenses 4000-19999, SAM 20000-29999,
-- fixed ground targets 30000-39999).
local _mark = 40000

local SIDE_COLOR  = { red = { 1, 0.5, 0, 0.9 }, blue = { 0, 0.8, 0.8, 0.9 } }
local LINE_DASHED = 2

function DrawConvoys.apply(plan)
    local pc = plan.convoys
    if not pc or not CONFIG.DRAW_CONVOYS then return end
    for _, c in ipairs(pc.convoys) do
        local pts = c.waypoints
        for i = 2, #pts do
            trigger.action.lineToAll(-1, _mark, Util.toVec3(pts[i - 1]), Util.toVec3(pts[i]),
                SIDE_COLOR[c.coalition], LINE_DASHED, true, "")
            _mark = _mark + 1
        end
        local text = string.format("%s\n%s, %d vehicles: %s → %s, %d km by road, ~%d min", c.id, c.label,
            c.units, c.from_base, c.to_base, c.road_km, c.travel_minutes)
        trigger.action.markToAll(_mark, text, Util.toVec3(pts[1]), true, "")
        _mark = _mark + 1
        trigger.action.markToAll(_mark, c.id .. "\nparks here", Util.toVec3(pts[#pts]), true, "")
        _mark = _mark + 1
    end
end

-- One line for the on-screen summary.
function DrawConvoys.summaryText(plan)
    local pc = plan.convoys
    if not pc then return "CONVOYS: not planned" end
    if pc.problems then return "CONVOYS: data errors — see dcs.log" end
    local parts = {}
    for _, c in ipairs(pc.convoys) do
        parts[#parts + 1] = string.format("%s %s → %s (%d vehicles)", c.coalition:upper(), c.from_base,
            c.to_base, c.units)
    end
    return "CONVOYS: " .. (#parts > 0 and table.concat(parts, "; ") or "none")
end
