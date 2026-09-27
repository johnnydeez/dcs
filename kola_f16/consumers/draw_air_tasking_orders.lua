-- Consumer: debug view of plan.air_tasking_orders on the F10 map.
--   CONFIG.DRAW_AIR_TASKING_ORDERS: each flight's planned route as a dotted line in its
--   coalition's colour, and a text mark at the target (mission, aircraft, base, times,
--   package); a suppression flight's mark sits at its attack waypoint, with the threats
--   it engages. Defensive air: each patrol station and the AWACS orbit as a solid
--   race-track with one label listing its flights, a patrol station's defended zone as a
--   dashed circle and its commit circles as faint dotted ones, each alert base's
--   posture, and (with CONFIG.DRAW_AIR_ZONES, off: the map got too cluttered) the defended air zones as
--   dashed circles.
-- Reads the plan; writes nothing back to it.

DrawAirTaskingOrders = {}

-- Mark ids 50000-59999 (territory 1000-3999, base defenses 4000-19999, SAM 20000-29999,
-- fixed ground targets 30000-39999, convoys 40000-49999).
local _mark = 50000

local SIDE_COLOR  = { red = { 1, 0.5, 0, 0.9 }, blue = { 0, 0.8, 0.8, 0.9 } }
local LINE_DOTTED = 3
local LINE_SOLID  = 1
local LINE_DASHED = 2
local NO_FILL     = { 0, 0, 0, 0 }
-- commit circles are fainter than the defended zone: there are many of them
local COMMIT_COLOR = { red = { 1, 0.5, 0, 0.4 }, blue = { 0, 0.8, 0.8, 0.4 } }

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

function DrawAirTaskingOrders.apply(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems or not CONFIG.DRAW_AIR_TASKING_ORDERS then return end
    for _, coalition in ipairs({ "red", "blue" }) do
        local byStation = {}
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            local r = m.route
            for i = 2, #r do
                trigger.action.lineToAll(-1, _mark, Util.toVec3(r[i - 1]), Util.toVec3(r[i]),
                    SIDE_COLOR[coalition], LINE_DOTTED, true, "")
                _mark = _mark + 1
            end
            if m.station then
                -- patrols and the AWACS: one label per station, below
                byStation[m.station] = byStation[m.station] or {}
                table.insert(byStation[m.station], string.format("%s %s from %s, on station %s–%s", m.id,
                    m.aircraft_type, m.launch_base, clock(m.tot_s), clock(m.attack.until_s)))
            else
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

        for _, st in ipairs(ato[coalition] and ato[coalition].stations or {}) do
            trigger.action.lineToAll(-1, _mark, Util.toVec3(st.ends[1]), Util.toVec3(st.ends[2]),
                SIDE_COLOR[coalition], LINE_SOLID, true, "")
            _mark = _mark + 1
            local lines = byStation[st.id] or { "no flights" }
            trigger.action.markToAll(_mark, string.format("%s %s\n%s\n%s", st.id, coalition:upper(), st.label,
                table.concat(lines, "\n")), Util.toVec3(st.centre), true, "")
            _mark = _mark + 1
            if st.zone then
                trigger.action.circleToAll(-1, _mark, Util.toVec3(st.zone), st.zone.radius_m, SIDE_COLOR[coalition],
                    NO_FILL, LINE_DASHED, true, "")
                _mark = _mark + 1
            end
            for _, z in ipairs(st.commit or {}) do
                trigger.action.circleToAll(-1, _mark, Util.toVec3(z), z.radius_m, COMMIT_COLOR[coalition],
                    NO_FILL, LINE_DOTTED, true, "")
                _mark = _mark + 1
            end
        end

        local alert = ato[coalition] and ato[coalition].alert
        if alert then
            for _, b in ipairs(alert.bases) do
                local types = {}
                for _, e in ipairs(b.aircraft) do types[#types + 1] = e[1] end
                trigger.action.markToAll(_mark, string.format("ALERT %s %s\n%s\n%d launches, %d min between",
                    coalition:upper(), b.base, table.concat(types, " / "), b.scrambles, math.floor(b.cooldown_s / 60)),
                    Util.toVec3(b.pos), true, "")
                _mark = _mark + 1
            end
            for _, z in ipairs(CONFIG.DRAW_AIR_ZONES and alert.zones or {}) do
                trigger.action.circleToAll(-1, _mark, Util.toVec3(z), z.radius_m, SIDE_COLOR[coalition], NO_FILL,
                    LINE_DASHED, true, "")
                _mark = _mark + 1
            end
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
            parts[#parts + 1] = string.format("%s %d missions + %d suppression flights, %d patrols on %d stations, %d AWACS, %d alert bases%s",
                c:upper(), s.missions, s.suppression_flights or 0, s.patrols or 0, s.stations or 0, s.early_warning or 0,
                s.alert_bases or 0, first and (", first starts " .. clock(first.start_s)) or "")
        end
    end
    return "AIR TASKING: " .. table.concat(parts, "; ")
end
