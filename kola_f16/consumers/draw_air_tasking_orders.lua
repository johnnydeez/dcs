-- Consumer: debug view of plan.air_tasking_orders on the F10 map.
--   CONFIG.DRAW_AIR_TASKING_ORDERS: each flight's planned route as a dotted line in its
--   coalition's colour, and a text mark at the target (mission, aircraft, base, times,
--   package); a suppression flight's mark sits at its attack waypoint, with the threats
--   it engages.
-- Reads the plan; writes nothing back to it.

DrawAirTaskingOrders = {}

-- Mark ids 50000-59999 (territory 1000-3999, base defenses 4000-19999, SAM 20000-29999,
-- fixed ground targets 30000-39999, convoys 40000-49999).
local _mark = 50000

local SIDE_COLOR  = { red = { 1, 0.5, 0, 0.9 }, blue = { 0, 0.8, 0.8, 0.9 } }
local LINE_DOTTED = 3

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

function DrawAirTaskingOrders.apply(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems or not CONFIG.DRAW_AIR_TASKING_ORDERS then return end
    for _, coalition in ipairs({ "red", "blue" }) do
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            local r = m.route
            for i = 2, #r do
                trigger.action.lineToAll(-1, _mark, Util.toVec3(r[i - 1]), Util.toVec3(r[i]),
                    SIDE_COLOR[coalition], LINE_DOTTED, true, "")
                _mark = _mark + 1
            end
            local detail
            if m.escorts then
                detail = string.format("escorts %s\nengages: %s", m.escorts, table.concat(m.attack.groups, ", "))
            else
                detail = "→ " .. m.target
                if m.needs_suppression then
                    detail = string.format("%s\ncrosses: %s\nsuppressed by: %s", detail,
                        table.concat(m.suppression_threats, ", "), table.concat(m.suppressed_by or {}, ", "))
                end
            end
            local text = string.format("%s %s %s (%s)\n%dx %s from %s\nstart %s  TOT %s  back %s\n%s",
                m.id, coalition:upper(), m.mission_type, m.package or "", m.count, m.aircraft_type, m.launch_base,
                clock(m.start_s), clock(m.tot_s), clock(m.end_s), detail)
            -- suppression flights share their mission's target: label them at their attack waypoint
            local at = m.target_pos
            if m.escorts then
                for _, w in ipairs(r) do if w.carries_attack_tasks then at = w end end
            end
            trigger.action.markToAll(_mark, text, Util.toVec3(at), true, "")
            _mark = _mark + 1
        end
    end
end

-- One line for the on-screen summary.
function DrawAirTaskingOrders.summaryText(plan)
    local ato = plan.air_tasking_orders
    if not ato then return "AIR TASKING: not planned" end
    if ato.problems then return "AIR TASKING: data errors — see dcs.log" end
    local parts = {}
    for _, c in ipairs({ "red", "blue" }) do
        local s = ato[c] and ato[c].summary
        if s then
            local first = ato[c].missions[1]
            parts[#parts + 1] = string.format("%s %d missions + %d suppression flights%s", c:upper(), s.missions,
                s.suppression_flights or 0, first and (", first starts " .. clock(first.start_s)) or "")
        end
    end
    return "AIR TASKING: " .. table.concat(parts, "; ")
end
