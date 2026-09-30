-- Stage 3c: the target catalog — one list of everything on the ground the mission stages
-- may send aircraft against, built from what stages 3a, 3b and 4 planned. Runs after
-- stage 4 so the convoys are in it. Mission planning reads only this, never
-- plan.sam_sites / plan.fixed_ground_targets / plan.convoys directly, so a new source of
-- targets only needs an adapter here.
-- Reads plan.world, plan.territory, plan.base_defenses, plan.sam_sites,
-- plan.fixed_ground_targets, plan.convoys. Writes plan.target_catalog. Spawns nothing;
-- built before anything spawns, like every stage. Whether a target is still alive is
-- runtime state, kept elsewhere under the same ids.
--
-- plan.target_catalog = {
--   targets = { [id] = { id, category, kind, label, coalition, cluster, location,
--                        zone | base, pos, value, mission_types, group_ids,
--                        static_object_ids, critical_names, success, covered_by,
--                        defended_base, description } },
--   list    = { ids, by coalition, highest value first },
--   summary = { red = { targets, by_mission_type = { [type] = n } }, blue = … },
-- }
--   category        air_defense (SAM and early-warning sites) | ground_target (fixed ground
--                   targets) | mobile_ground_target (convoys)
--   pos             where it is at mission start (a convoy's lead vehicle); a convoy also
--                   carries from_base, to_base, waypoints, speed_mps and travel_minutes, so a
--                   later stage can work out where it is at a given time
--   critical_names  DCS unit / static-object names that count for success
--   success         { critical_fraction }: destroy at least this share of them (rounded up)
--   covered_by      ids of the owner's other SAM sites whose engagement ring reaches it
--   defended_base   the owner's airbase within DEFENDED_BASE_KM, whose defenses stand
--                   around it, or nil
-- Base defenses are not targets (settled 2026-09-23); they only feed defended_base.

CatalogTargets = {}

local COALITIONS = { "red", "blue" }
local DEFENDED_BASE_KM = 5

-- Every mission type a target can offer; the summary warns about any a coalition lacks.
local MISSION_TYPES = { "suppression_of_air_defenses", "destruction_of_air_defenses", "strike",
                        "airfield_strike", "close_air_support", "interdiction" }

-- SAM parts that count for suppression: the radars (pool roles), else the whole site.
local RADAR_ROLES = { sam_sr = true, sam_tr = true, ewr = true }
local SAM_VALUE   = { long_range = 3, medium_range = 2, short_range = 1, early_warning = 2 }

local function describe(label, zone, base)
    if zone then
        return string.format("%s, %.1f km on bearing %03d from %s", label, zone.km, zone.brg, zone.base)
    end
    return string.format("%s at %s", label, base)
end

-- SAM and early-warning sites → catalog entries.
local function airDefenseTargets(plan, add)
    local ss = plan.sam_sites
    if not ss then return end
    local groupsById = {}
    for _, g in ipairs(ss.groups) do groupsById[g.id] = g end
    for _, s in ipairs(ss.sites) do
        local main = groupsById[s.id]
        local radars, all = {}, {}
        for i, u in ipairs(main and main.units or {}) do
            local name = s.id .. "_" .. i
            all[#all + 1] = name
            local pool = UNIT_POOL.ground[u.type]
            if pool and RADAR_ROLES[pool.role] then radars[#radars + 1] = name end
        end
        local ew = s.layer == "early_warning"
        local zone = plan.world.zones[s.zone]
        local label = s.system .. (ew and " early-warning radar" or " site")
        add({
            id = s.id, category = "air_defense",
            kind = ew and "early_warning_radar" or "surface_to_air_missile_site",
            label = label, coalition = s.side, cluster = zone and zone.cluster, location = "zone",
            zone = s.zone, pos = s.pos, value = SAM_VALUE[s.layer] or 1,
            mission_types = ew and { "strike", "destruction_of_air_defenses" }
                               or { "suppression_of_air_defenses", "destruction_of_air_defenses" },
            group_ids = s.group_ids, static_object_ids = {},
            critical_names = #radars > 0 and radars or all,
            success = { critical_fraction = ew and 1 or 0.5 },
            description = describe(label, zone),
            system = s.system, layer = s.layer,
        })
    end
end

-- Fixed ground targets → catalog entries (already in catalog shape, mostly).
local function fixedGroundTargets(plan, add)
    local sg = plan.fixed_ground_targets
    if not sg then return end
    for _, s in ipairs(sg.sites) do
        local zone = s.zone and plan.world.zones[s.zone]
        add({
            id = s.id, category = "ground_target", kind = s.kind, label = s.label,
            coalition = s.coalition, cluster = s.cluster, location = s.location,
            zone = s.zone, base = s.base, pos = s.pos, value = s.value, echelon = s.echelon,
            mission_types = s.mission_types, group_ids = s.group_ids,
            static_object_ids = s.static_object_ids, critical_names = s.critical_names,
            success = s.success, description = describe(s.label, zone, s.base),
        })
    end
end

-- Convoys → catalog entries. The position is the start; the route goes along.
local function convoyTargets(plan, add)
    local pc = plan.convoys
    if not pc then return end
    for _, c in ipairs(pc.convoys) do
        add({
            id = c.id, category = "mobile_ground_target", kind = c.kind, label = c.label,
            coalition = c.coalition, cluster = c.cluster, location = "road", pos = c.pos,
            value = c.value, mission_types = c.mission_types, group_ids = c.group_ids,
            static_object_ids = {}, critical_names = c.critical_names, success = c.success,
            description = string.format("%s, %d vehicles, driving %s to %s (%d km by road, ~%d min)",
                c.label, c.units, c.from_base, c.to_base, c.road_km, c.travel_minutes),
            from_base = c.from_base, to_base = c.to_base, waypoints = c.waypoints,
            speed_mps = c.speed_mps, travel_minutes = c.travel_minutes,
        })
    end
end

function CatalogTargets.run(plan)
    Log.info("--- Stage 3c: target catalog ---")
    local out = { targets = {}, list = {}, summary = {} }
    plan.target_catalog = out
    local function add(entry) out.targets[entry.id] = entry end

    airDefenseTargets(plan, add)
    fixedGroundTargets(plan, add)
    convoyTargets(plan, add)

    -- what protects each target: the owner's other SAM rings, and its base defenses
    local rings = {}
    for _, s in ipairs(plan.sam_sites and plan.sam_sites.sites or {}) do
        if (s.engage_m or 0) > 0 then rings[#rings + 1] = s end
    end
    local defended = {}
    for name, b in pairs(plan.base_defenses and plan.base_defenses.bases or {}) do
        if (b.groups or 0) > 0 then defended[name] = b.side end
    end
    for id, t in pairs(out.targets) do
        t.covered_by = {}
        for _, s in ipairs(rings) do
            if s.side == t.coalition and s.id ~= id and Util.dist(t.pos, s.pos) <= s.engage_m then
                t.covered_by[#t.covered_by + 1] = s.id
            end
        end
        local best, bestD
        for name, side in pairs(defended) do
            if side == t.coalition then
                local d = Util.dist(t.pos, plan.world.airbases[name].pos)
                if d <= DEFENDED_BASE_KM * 1000 and (not bestD or d < bestD) then best, bestD = name, d end
            end
        end
        t.defended_base = best
        out.list[#out.list + 1] = id
    end
    table.sort(out.list, function(a, b)
        local ta, tb = out.targets[a], out.targets[b]
        if ta.coalition ~= tb.coalition then return ta.coalition < tb.coalition end
        if ta.value ~= tb.value then return ta.value > tb.value end
        return a < b
    end)

    for _, c in ipairs(COALITIONS) do
        local sum = { targets = 0, by_mission_type = {} }
        out.summary[c] = sum
        for _, id in ipairs(out.list) do
            local t = out.targets[id]
            if t.coalition == c then
                sum.targets = sum.targets + 1
                for _, m in ipairs(t.mission_types) do
                    sum.by_mission_type[m] = (sum.by_mission_type[m] or 0) + 1
                end
            end
        end
        local parts, missing = {}, {}
        for _, m in ipairs(MISSION_TYPES) do
            local n = sum.by_mission_type[m] or 0
            parts[#parts + 1] = m .. " " .. n
            if n == 0 then missing[#missing + 1] = m end
        end
        Log.info(string.format("  %s: %d targets  [%s]", c:upper(), sum.targets, table.concat(parts, ", ")))
        if #missing > 0 then
            Log.warn(string.format("  %s has no targets for: %s", c:upper(), table.concat(missing, ", ")))
        end
    end
    return plan
end
