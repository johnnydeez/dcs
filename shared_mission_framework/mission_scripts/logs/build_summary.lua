-- Logs: the build summary in dcs.log once the mission is built: the territory roll, the
-- airspace, defenses, SAM sites, fixed ground targets, convoys and air tasking, from the
-- plan (the screen shows only the weather and the human taskings; John, session 10).

BuildSummary = {}

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- The territory roll: who holds what, the front.
local function territory(plan)
    local terr = plan.territory
    local lines = { "=== " .. MISSION.display_name .. " — TERRITORY ROLL ===", "BLUE:" }
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

-- The airspace in one line.
local function airspace(plan)
    local s = plan.airspace and plan.airspace.summary
    if not s then return "" end
    local function k(v) return math.floor(v / 1000 + 0.5) end
    return string.format("AIRSPACE (1000 km²): blue %d, red %d, contested %d; front line %d km",
        k(s.blue_km2), k(s.red_km2), k(s.contested_km2), s.front_line_km)
end

-- One line.
local function baseDefenses(plan)
    local bd = plan.base_defenses
    if not bd then return "DEFENSES: not planned" end
    if bd.problems then return "DEFENSES: data errors — see dcs.log" end
    local t = bd.totals
    local n = 0
    for _ in pairs(bd.bases) do n = n + 1 end
    return string.format("DEFENSES: %d bases, %d groups / %d units  (red %d/%d, blue %d/%d)",
        n, t.groups, t.units, t.red.groups, t.red.units, t.blue.groups, t.blue.units)
end

-- One line.
local function samSites(plan)
    local ss = plan.sam_sites
    if not ss then return "SAM SITES: not planned" end
    if ss.problems then return "SAM SITES: data errors — see dcs.log" end
    local parts = {}
    for _, side in ipairs({ "red", "blue" }) do
        local s = ss.summary[side]
        if s then
            parts[#parts + 1] = string.format("%s %d (of %d zones)", side:upper(), s.sites, s.zones_held)
        end
    end
    return "SAM SITES: " .. table.concat(parts, ", ")
end

-- One line.
local function fixedGroundTargets(plan)
    local sg = plan.fixed_ground_targets
    if not sg then return "FIXED GROUND TARGETS: not planned" end
    if sg.problems then return "FIXED GROUND TARGETS: data errors — see dcs.log" end
    local parts = {}
    for _, c in ipairs({ "red", "blue" }) do
        local s = sg.summary[c]
        if s then parts[#parts + 1] = string.format("%s %d", c:upper(), s.sites) end
    end
    return "FIXED GROUND TARGETS: " .. table.concat(parts, ", ")
end

-- One line.
local function convoys(plan)
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

-- One line.
local function airTaskingOrders(plan)
    local ato = plan.air_tasking_orders
    if not ato then return "AIR TASKING: not planned" end
    if ato.problems then return "AIR TASKING: data errors — see dcs.log" end
    local parts = {}
    for _, c in ipairs({ "red", "blue" }) do
        local s = ato[c] and ato[c].summary
        if s then
            local first = ato[c].missions[1]
            parts[#parts + 1] = string.format("%s %d missions + %d SEAD flights (%d in the rotation), %d patrols on %d stations, %d AWACS, %d alert bases%s",
                c:upper(), s.missions, s.suppression_flights or 0, s.rotation_flights or 0, s.patrols or 0, s.stations or 0, s.early_warning or 0,
                s.alert_bases or 0, first and (", first starts " .. clock(first.start_s)) or "")
        end
    end
    return "AIR TASKING: " .. table.concat(parts, "; ")
end

-- The whole summary, one block per part.
function BuildSummary.text(plan)
    return territory(plan) .. "\n" .. airspace(plan) .. "\n" .. baseDefenses(plan)
        .. "\n" .. samSites(plan) .. "\n" .. fixedGroundTargets(plan)
        .. "\n" .. convoys(plan) .. "\n" .. airTaskingOrders(plan)
end
