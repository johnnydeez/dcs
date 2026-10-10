-- Inform: debug view of plan.fixed_ground_targets on the F10 map.
--   CONFIG.DRAW_FIXED_GROUND_TARGETS: a text mark on each site (id, what it is, echelon,
--   where) and a small circle in its coalition's colour.
-- Reads the plan; writes nothing back to it.

InformMapFixedGroundTargets = {}

-- Mark ids 30000-39999 (territory 1000-3999, base defenses 4000-19999, SAM 20000-29999).
local _mark = 30000

local SIDE_COLOR = { red = { 1, 0.5, 0, 0.9 }, blue = { 0, 0.8, 0.8, 0.9 } }
local NO_FILL    = { 0, 0, 0, 0 }
local LINE_DOTTED = 3
local SITE_RING_M = 500

function InformMapFixedGroundTargets.apply(plan)
    local sg = plan.fixed_ground_targets
    if not sg or not CONFIG.DRAW_FIXED_GROUND_TARGETS then return end
    for _, s in ipairs(sg.sites) do
        trigger.action.circleToAll(-1, _mark, Util.toVec3(s.pos), SITE_RING_M, SIDE_COLOR[s.coalition], NO_FILL,
            LINE_DOTTED, true, "")
        _mark = _mark + 1
        local text = string.format("%s\n%s — %s (%d units, %d static objects)", s.id, s.label, s.echelon,
            s.units, s.static_objects)
        trigger.action.markToAll(_mark, text, Util.toVec3(s.pos), true, "")
        _mark = _mark + 1
    end
end
