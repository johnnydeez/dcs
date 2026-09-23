-- Stage 2: plan a ground defense for every base, sized to how hard its owner holds it.
-- Reads plan.world (airbase anchors, runways, parking) + plan.territory (side, echelon)
-- + the base-defense data files. Writes plan.base_defenses. Spawns nothing.
--
-- Per base: level = BASE_DEFENSE_LEVEL[class][echelon] → components from
-- BASE_DEFENSE_COMPOSITION[level] → types from COALITION_ROSTER[side][role] → positions
-- from BASE_DEFENSE_PLACEMENT: a group centre is placed off a footprint anchor per the
-- component's `anchors` spec (data/airbase_footprints.lua + live parking/runways), at least
-- BASE_DEFENSE_GROUP_SPACING_M from the base's other groups, and passes
-- Placement.isClear. Bases with no anchors fall back to the ring around the base anchor.
--
-- plan.base_defenses = {
--   groups = { { id, base, side, class, echelon, level, component, role, skill, anchor_kind,
--                pos = { x, z, lat, lon }, units = { { type, x, z, heading_deg } } } },
--   bases  = { [name] = { code, side, class, echelon, level, groups, units, anchors, rejects } },
--   totals = { groups, units, dropped_groups, dropped_units, red = {groups, units}, blue = {...} },
-- }
-- Each group entry is spawn-ready; `id` is used verbatim as the DCS group name.

PlanBaseDefenses = {}

local TRIES_GROUP = 80   -- attempts to find a clear group centre
local TRIES_UNIT  = 12   -- attempts per unit around that centre

local COALITIONS = { "red", "blue" }
local ECHELONS   = { "front", "mid", "rear" }

-- Checks the data files against each other and against UNIT_POOL. Needs no sim state,
-- so init can run it before anything else. Returns a list of problem strings.
function PlanBaseDefenses.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end

    for _, side in ipairs(COALITIONS) do
        local roster = COALITION_ROSTER[side]
        if not roster then
            bad("COALITION_ROSTER has no '" .. side .. "'")
        else
            for role, list in pairs(roster) do
                for _, e in ipairs(list) do
                    if not UNIT_POOL.ground[e[1]] then
                        bad(string.format("roster %s.%s: '%s' is not in UNIT_POOL.ground", side, role, tostring(e[1])))
                    end
                    if type(e[2]) ~= "number" or e[2] <= 0 then
                        bad(string.format("roster %s.%s: '%s' needs a positive weight", side, role, tostring(e[1])))
                    end
                end
            end
        end
    end

    for comp, pl in pairs(BASE_DEFENSE_PLACEMENT) do
        if type(pl.anchors) ~= "table" or type(pl.ring) ~= "table" then
            bad(string.format("placement '%s' needs anchors and ring", comp))
        else
            for kind, s in pairs(pl.anchors) do
                if type(s) ~= "table" or #s ~= 3 or s[2] > s[3] then
                    bad(string.format("placement '%s' anchor '%s' must be { weight, min_m, max_m }", comp, kind))
                end
            end
        end
        for _, side in ipairs(COALITIONS) do
            local list = COALITION_ROSTER[side] and COALITION_ROSTER[side][pl.role]
            if not list or #list == 0 then
                bad(string.format("placement '%s' needs role '%s' but roster %s has none", comp, pl.role, side))
            end
        end
    end

    for level, comps in pairs(BASE_DEFENSE_COMPOSITION) do
        if not BASE_DEFENSE_SKILL[level] then bad("BASE_DEFENSE_SKILL has no '" .. level .. "'") end
        for _, c in ipairs(comps) do
            if not BASE_DEFENSE_PLACEMENT[c[1]] then
                bad(string.format("composition '%s' names component '%s' with no placement", level, tostring(c[1])))
            end
        end
    end

    for class, row in pairs(BASE_DEFENSE_LEVEL) do
        for _, ech in ipairs(ECHELONS) do
            if not BASE_DEFENSE_COMPOSITION[row[ech]] then
                bad(string.format("BASE_DEFENSE_LEVEL.%s.%s = '%s' has no composition", class, ech, tostring(row[ech])))
            end
        end
    end

    for name, class in pairs(AIRBASE_CLASS) do
        if not BASE_DEFENSE_LEVEL[class] then
            bad(string.format("AIRBASE_CLASS['%s'] = '%s' is not in BASE_DEFENSE_LEVEL", name, tostring(class)))
        end
    end

    return problems
end

-- validate() once, logging each problem once. init calls this at load; the stage
-- reuses the result.
local _problems
function PlanBaseDefenses.checkData()
    if not _problems then
        _problems = PlanBaseDefenses.validate()
        for _, p in ipairs(_problems) do Log.error("base defenses data: " .. p) end
        if #_problems == 0 then Log.info("base defenses data: OK") end
    end
    return _problems
end

-- ── helpers ─────────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

local function addRejects(into, from)
    for k, n in pairs(from) do into[k] = (into[k] or 0) + n end
end

local function rejectText(r)
    local keys = {}
    for k in pairs(r) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. r[k] end
    return #parts > 0 and table.concat(parts, " ") or "none"
end

-- The set of bases to plan, from CONFIG.DEFENSE_TEST_BASES (empty = all).
local function baseFilter()
    local list = CONFIG.DEFENSE_TEST_BASES or {}
    if #list == 0 then return nil end
    local set = {}
    for _, n in ipairs(list) do set[n] = true end
    return set
end

-- "parking=98 building=172 apron=3 runway_side=32"
local function anchorText(anchors)
    local keys = {}
    for k in pairs(anchors) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. #anchors[k] end
    return #parts > 0 and table.concat(parts, " ") or "none"
end

-- Plans one group. ctx.anchors = footprint anchors by kind; ctx.centres = group centres
-- already placed at this base. Returns the entry (or nil if no clear ground was found)
-- and the number of units dropped.
local function planGroup(ab, ctx, comp, pl, index, rejects)
    local kindUsed
    local function candidate()
        local p, kind = Placement.pickAnchorPoint(ctx.anchors, pl.anchors)
        if p then
            kindUsed = kind
            return p
        end
        kindUsed = "ring"
        return Placement.ringPoint(ab.anchor, pl.ring)
    end
    local spacing2 = BASE_DEFENSE_GROUP_SPACING_M * BASE_DEFENSE_GROUP_SPACING_M
    local function spaced(p)
        for _, c in ipairs(ctx.centres) do
            local dx, dz = p.x - c.x, p.z - c.z
            if dx * dx + dz * dz < spacing2 then return false, "spacing" end
        end
        return true
    end
    local centre, rj = Placement.findClear(ab, candidate, TRIES_GROUP, spaced)
    addRejects(rejects, rj)
    if not centre then return nil, 0 end
    ctx.centres[#ctx.centres + 1] = centre

    local roster    = COALITION_ROSTER[ctx.side][pl.role]
    local groupType = Util.weightedPick(roster)
    local outward   = math.atan2(centre.z - ab.anchor.z, centre.x - ab.anchor.x)

    local units, dropped = {}, 0
    for u = 1, math.random(pl.units[1], pl.units[2]) do
        local p
        if u == 1 then
            p = centre
        else
            local rju
            p, rju = Placement.findClear(ab, function()
                return Placement.discPoint(centre, pl.spread)
            end, TRIES_UNIT)
            addRejects(rejects, rju)
        end
        if p then
            local h = outward + (math.random() - 0.5) * 0.8
            units[#units + 1] = {
                type        = pl.mixed_types and Util.weightedPick(roster) or groupType,
                x           = round(p.x),
                z           = round(p.z),
                heading_deg = round(math.deg(h)) % 360,
            }
        else
            dropped = dropped + 1
        end
    end

    return {
        id        = string.format("DEF_%s_%s_%d", ctx.code, comp, index),
        base      = ctx.name,
        side      = ctx.side,
        class     = ctx.class,
        echelon   = ctx.echelon,
        level     = ctx.level,
        component = comp,
        role      = pl.role,
        skill     = ctx.skill,
        anchor_kind = kindUsed,
        pos       = Util.withLatLon({ x = round(centre.x), z = round(centre.z) }),
        units     = units,
    }, dropped
end

-- ── stage ───────────────────────────────────────────────────────

function PlanBaseDefenses.run(plan)
    Log.info("--- Stage 2: base defenses ---")
    local world, terr = plan.world, plan.territory
    local out = {
        groups = {},
        bases  = {},
        totals = { groups = 0, units = 0, dropped_groups = 0, dropped_units = 0,
                   red = { groups = 0, units = 0 }, blue = { groups = 0, units = 0 } },
    }
    plan.base_defenses = out

    local problems = PlanBaseDefenses.checkData()
    if #problems > 0 then
        out.problems = problems
        return plan
    end

    for name in pairs(AIRBASE_CLASS) do
        if not world.airbases[name] then
            Log.warn("airbase_classes.lua lists '" .. name .. "' but DCS has no such airdrome")
        end
    end

    local only  = baseFilter()
    local names = {}
    for name in pairs(terr.bases) do
        if not only or only[name] then names[#names + 1] = name end
    end
    table.sort(names)

    for _, name in ipairs(names) do
        local b, ab = terr.bases[name], world.airbases[name]
        local class = AIRBASE_CLASS[name]
        if not class then
            Log.warn("no AIRBASE_CLASS for '" .. name .. "' — treating as strip")
            class = "strip"
        end
        local code = AIRBASE_CODE[name]
        if not code then
            code = name:gsub("%W", ""):upper():sub(1, 4)
            Log.warn("no AIRBASE_CODE for '" .. name .. "' — using " .. code)
        end
        local level = BASE_DEFENSE_LEVEL[class][b.echelon]
        local footprint = AIRBASE_FOOTPRINT[name]
        if not footprint then
            Log.warn("no surveyed footprint for '" .. name .. "' — parking + runway sides only (run the survey)")
        end
        local anchors = Placement.buildAnchors(ab, footprint)
        if not next(anchors) then
            Log.warn("no placement anchors at '" .. name .. "' — falling back to the ring")
        end
        local ctx = { name = name, code = code, side = b.side, class = class,
                      echelon = b.echelon, level = level, skill = BASE_DEFENSE_SKILL[level],
                      anchors = anchors, centres = {} }

        local anchorCounts = {}
        for k, list in pairs(anchors) do anchorCounts[k] = #list end
        local summary = { code = code, side = b.side, class = class, echelon = b.echelon,
                          level = level, groups = 0, units = 0, anchors = anchorCounts, rejects = {},
                          dropped = {} }
        for _, c in ipairs(BASE_DEFENSE_COMPOSITION[level]) do
            local comp, lo, hi = c[1], c[2], c[3]
            local pl = BASE_DEFENSE_PLACEMENT[comp]
            local index = 0
            for _ = 1, math.random(lo, hi) do
                local entry, dropped = planGroup(ab, ctx, comp, pl, index + 1, summary.rejects)
                out.totals.dropped_units = out.totals.dropped_units + dropped
                if entry and #entry.units > 0 then
                    index = index + 1
                    out.groups[#out.groups + 1] = entry
                    summary.groups = summary.groups + 1
                    summary.units  = summary.units + #entry.units
                else
                    -- no open ground left for it: fewer guns beats guns in the trees
                    out.totals.dropped_groups = out.totals.dropped_groups + 1
                    summary.dropped[comp] = (summary.dropped[comp] or 0) + 1
                end
            end
        end
        out.bases[name] = summary

        local t = out.totals
        t.groups, t.units = t.groups + summary.groups, t.units + summary.units
        t[b.side].groups = t[b.side].groups + summary.groups
        t[b.side].units  = t[b.side].units + summary.units

        Log.info(string.format("  %-22s %-4s %s/%s → %-8s %d groups %d units  (anchors: %s; rejects: %s; no room for: %s)",
            name, b.side:upper(), class, b.echelon, level:upper(), summary.groups, summary.units,
            anchorText(anchors), rejectText(summary.rejects), rejectText(summary.dropped)))
    end

    local t = out.totals
    Log.info(string.format("  total: %d bases, %d groups, %d units (red %d/%d, blue %d/%d); dropped %d groups, %d units",
        #names, t.groups, t.units, t.red.groups, t.red.units, t.blue.groups, t.blue.units,
        t.dropped_groups, t.dropped_units))
    return plan
end
