-- Inform: debug view of plan.sam_sites on the F10 map.
--   CONFIG.DRAW_SAM_SITES: a text mark on each site (id, system, role, what it defends)
--   CONFIG.DRAW_SAM_RINGS: each site's engagement ring (ED's range), red or blue;
--                          early-warning sites get their detection ring, dashed
-- Reads the plan; writes nothing back to it.

InformMapSamSites = {}

-- Mark ids 20000-29999 (territory 1000-3999, base defenses 4000-19999).
local _mark = 20000

local SIDE_COLOR = { red = { 1, 0.15, 0.15, 0.9 }, blue = { 0.2, 0.5, 1, 0.9 } }
local NO_FILL    = { 0, 0, 0, 0 }
local LINE_SOLID, LINE_DASHED = 1, 2

function InformMapSamSites.apply(plan)
    local ss = plan.sam_sites
    if not ss then return end
    for _, s in ipairs(ss.sites) do
        if CONFIG.DRAW_SAM_RINGS then
            local ew = s.layer == "early_warning"
            local r  = ew and s.detect_m or s.engage_m
            if r > 0 then
                trigger.action.circleToAll(-1, _mark, Util.toVec3(s.pos), r, SIDE_COLOR[s.side], NO_FILL,
                    ew and LINE_DASHED or LINE_SOLID, true, "")
                _mark = _mark + 1
            end
        end
        if CONFIG.DRAW_SAM_SITES then
            local text = string.format("%s\n%s (%s) — %s%s", s.id, s.system, s.layer:gsub("_", " "),
                s.role:gsub("_", " "), s.defends and (": " .. s.defends) or "")
            trigger.action.markToAll(_mark, text, Util.toVec3(s.pos), true, "")
            _mark = _mark + 1
        end
    end
end
