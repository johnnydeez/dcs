-- Inform: debug view of plan.air_tasking_orders on the F10 map.
--   CONFIG.DRAW_AIR_TASKING_ORDERS: each flight's planned route as a dotted line in its
--   coalition's colour, and a text mark at the target (mission, aircraft, base, times,
--   the threats it needs out of the fight and the SEAD flight for each); a SEAD flight's
--   mark sits at its launch point, with the groups it engages. Defensive air: each patrol station and the AWACS orbit as a solid
--   race-track with one label listing its flights, a patrol station's defended zone as a
--   dashed circle and its commit circles as faint dotted ones, human flights' routes
--   dashed yellow, and each alert base's posture.
-- Reads the plan; writes nothing back to it.

InformMapAirTaskingOrders = {}

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
-- human flights stand out from the AI's: yellow, dashed
local HUMAN_COLOR = { 1, 1, 0, 1 }

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

function InformMapAirTaskingOrders.apply(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems or not CONFIG.DRAW_AIR_TASKING_ORDERS then return end
    for _, coalition in ipairs({ "red", "blue" }) do
        local byStation = {}
        for _, m in ipairs(ato[coalition] and ato[coalition].missions or {}) do
            local r = m.route
            local human = m.flown_by == "human"
            for i = 2, #r do
                trigger.action.lineToAll(-1, _mark, Util.toVec3(r[i - 1]), Util.toVec3(r[i]),
                    human and HUMAN_COLOR or SIDE_COLOR[coalition], human and LINE_DASHED or LINE_DOTTED, true, "")
                _mark = _mark + 1
            end
            if m.station then
                -- patrols and the AWACS: one label per station, below
                byStation[m.station] = byStation[m.station] or {}
                table.insert(byStation[m.station], string.format("%s%s %s from %s, on station %s–%s",
                    human and "HUMAN " or "", FlightCallsigns.label(m), m.aircraft_type, m.launch_base, clock(m.tot_s),
                    clock(m.attack.until_s)))
            else
            local sead = m.mission_type == "suppression_of_air_defenses"
            local detail = sead and string.format("%sengages: %s", m.rotation and "SEAD rotation\n" or "",
                table.concat(m.attack.groups, ", ")) or ("→ " .. m.target)
            if m.requires_cleared then
                local bySite, by = ato[coalition].suppression_by_site or {}, {}
                for i, t in ipairs(m.requires_cleared) do by[i] = string.format("%s (%s)", t, bySite[t] or "none") end
                detail = string.format("%s\nneeds down: %s", detail, table.concat(by, ", "))
            end
            local text = string.format("%s%s %s %s\n%dx %s from %s\nstart %s  TOT %s  back %s\n%s",
                human and "HUMAN " or "", FlightCallsigns.label(m), coalition:upper(), m.mission_type, m.count, m.aircraft_type, m.launch_base,
                clock(m.start_s), clock(m.tot_s), clock(m.end_s), detail)
            -- a SEAD flight is labelled at its launch point (a DEAD on the same site keeps the site)
            local at = m.target_pos
            if sead then
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
                trigger.action.markToAll(_mark, string.format("ALERT %s %s\n%s\n%d alert jets, %d min between launches",
                    coalition:upper(), b.base, table.concat(types, " / "), b.alert_aircraft, math.floor(b.cooldown_s / 60)),
                    Util.toVec3(b.pos), true, "")
                _mark = _mark + 1
            end
        end
    end
end
