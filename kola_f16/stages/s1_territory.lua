-- Stage 1: roll cluster sides, derive base and zone ownership, compute the front.
-- Reads plan.world + CLUSTERS + CONFIG. Writes plan.territory. Pure data.
--
-- plan.territory = {
--   clusters   = { [id] = { id, name, side, fixed, bases = {...} } },
--   bases      = { [name] = { side, cluster } },
--   zones      = { [name] = { side, cluster } },
--   front      = {
--     range_km      = CONFIG.FRONT_RANGE_KM,
--     nearest_enemy = { [base] = { base, km, brg } },      every base → closest enemy base
--     frontline     = { blue = { names }, red = { names } }, bases with an enemy inside range
--     adjacency     = { { blue = clusterId, red = clusterId, km, via = { blue = base, red = base } } },
--   },
--   summary    = { blue = { cluster names }, red = { cluster names } },
-- }

Stage1 = {}

local function opposite(side)
    return side == "blue" and "red" or "blue"
end

-- Contested clusters roll Red with probability p_red (default 0.5). A cluster with
-- requires_red only rolls if that cluster already went Red; otherwise it stays Blue.
-- CLUSTERS is walked in file order so dependencies are resolved before dependents.
local function rollClusters(world)
    local clusters = {}
    for _, c in ipairs(CLUSTERS) do
        local side, how = c.fixed, "fixed"
        if CONFIG.FORCE_CLUSTER[c.id] then
            side, how = CONFIG.FORCE_CLUSTER[c.id], "forced"
        elseif not side then
            local dep = c.requires_red and clusters[c.requires_red]
            if c.requires_red and not dep then
                Log.warn("cluster " .. c.id .. " requires_red '" .. c.requires_red .. "' which is not defined earlier in CLUSTERS")
            end
            if c.requires_red and (not dep or dep.side ~= "red") then
                side, how = "blue", "blocked by " .. c.requires_red
            else
                local p = c.p_red or 0.5
                side = (math.random() < p) and "red" or "blue"
                how  = string.format("rolled, p_red=%.2f", p)
            end
        end
        clusters[c.id] = { id = c.id, name = c.name, side = side, fixed = c.fixed, bases = c.bases,
                           p_red = c.p_red, requires_red = c.requires_red, how = how }
        Log.info(string.format("  %-14s → %-4s (%s)", c.id, side:upper(), how))
    end
    return clusters
end

local function assignBases(world, clusters)
    local bases = {}
    for id, c in pairs(clusters) do
        for _, name in ipairs(c.bases) do
            if world.airbases[name] then
                bases[name] = { side = c.side, cluster = id }
            end
        end
    end
    return bases
end

local function assignZones(world, clusters)
    local zones = {}
    for name, z in pairs(world.zones) do
        local c = clusters[z.cluster]
        if c then
            zones[name] = { side = c.side, cluster = z.cluster }
        else
            Log.warn("zone '" .. name .. "' has unknown cluster '" .. tostring(z.cluster) .. "' — left neutral")
            zones[name] = { side = "neutral", cluster = z.cluster }
        end
    end
    return zones
end

local function computeFront(world, clusters, bases)
    local rangeM = CONFIG.FRONT_RANGE_KM * 1000
    local front = {
        range_km      = CONFIG.FRONT_RANGE_KM,
        nearest_enemy = {},
        frontline     = { blue = {}, red = {} },
        adjacency     = {},
    }

    -- Every base → nearest enemy base.
    for name, b in pairs(bases) do
        local myPos = world.airbases[name].pos
        local best, bestD = nil, math.huge
        for other, ob in pairs(bases) do
            if ob.side ~= b.side then
                local d = Util.dist(myPos, world.airbases[other].pos)
                if d < bestD then best, bestD = other, d end
            end
        end
        if best then
            front.nearest_enemy[name] = {
                base = best,
                km   = math.floor(bestD / 1000 + 0.5),
                brg  = Util.bearing(myPos, world.airbases[best].pos),
            }
            if bestD <= rangeM then
                table.insert(front.frontline[b.side], name)
            end
        end
    end
    table.sort(front.frontline.blue)
    table.sort(front.frontline.red)

    -- Opposing cluster pairs with any base pair inside range; record the closest pair.
    local pairs_, bestM = {}, {}
    for name, b in pairs(bases) do
        if b.side == "blue" then
            for other, ob in pairs(bases) do
                if ob.side == "red" then
                    local d = Util.dist(world.airbases[name].pos, world.airbases[other].pos)
                    if d <= rangeM then
                        local key = b.cluster .. "|" .. ob.cluster
                        if not bestM[key] or d < bestM[key] then
                            bestM[key] = d
                            pairs_[key] = {
                                blue = b.cluster, red = ob.cluster,
                                km   = math.floor(d / 1000 + 0.5),
                                via  = { blue = name, red = other },
                            }
                        end
                    end
                end
            end
        end
    end
    for _, adj in pairs(pairs_) do front.adjacency[#front.adjacency + 1] = adj end
    table.sort(front.adjacency, function(a, b) return a.km < b.km end)

    return front
end

function Stage1.run(plan)
    Log.info("--- Stage 1: territory ---")
    local world = plan.world

    local clusters = rollClusters(world)
    local bases    = assignBases(world, clusters)
    local zones    = assignZones(world, clusters)
    local front    = computeFront(world, clusters, bases)

    local summary = { blue = {}, red = {} }
    for _, c in ipairs(CLUSTERS) do
        table.insert(summary[clusters[c.id].side], c.name)
    end

    plan.territory = {
        clusters = clusters,
        bases    = bases,
        zones    = zones,
        front    = front,
        summary  = summary,
    }

    Log.info(string.format("  frontline: %d blue / %d red bases within %d km; %d adjacent cluster pairs",
        #front.frontline.blue, #front.frontline.red, CONFIG.FRONT_RANGE_KM, #front.adjacency))
    for _, adj in ipairs(front.adjacency) do
        Log.info(string.format("    %s ↔ %s  %d km  (%s ↔ %s)", adj.blue, adj.red, adj.km, adj.via.blue, adj.via.red))
    end
    return plan
end
