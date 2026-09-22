-- Gather inputs: the one place that reads from DCS. Everything the stages need is
-- converted here into plain values on plan.world so no stage ever touches a DCS
-- object, and the plan dump is self-contained.
--
-- Position shape used everywhere in the plan: { x = north, z = east, lat, lon }.

Gather = {}

local SIDE_NAME = { [0] = "neutral", [1] = "red", [2] = "blue" }

local function gatherAirbases(world_)
    local byName, list = {}, {}
    for _, ab in ipairs(world.getAirbases() or {}) do
        local desc = ab:getDesc()
        if desc.category == Airbase.Category.AIRDROME then
            local p = ab:getPoint()
            local entry = {
                name     = ab:getName(),
                pos      = Util.withLatLon({ x = p.x, z = p.z }),
                me_side  = SIDE_NAME[ab:getCoalition()] or "neutral",  -- as set in the ME, before we touch it
            }
            byName[entry.name] = entry
            list[#list + 1] = entry.name
        end
    end
    table.sort(list)
    world_.airbases = byName
    world_.airbase_list = list
end

local function gatherZones(world_)
    local byName, list = {}, {}
    for _, z in ipairs(ZONES) do
        local entry = {}
        for k, v in pairs(z) do entry[k] = v end
        entry.pos = Util.withLatLon({ x = z.x, z = z.z })
        entry.x, entry.z = nil, nil
        byName[z.name] = entry
        list[#list + 1] = z.name
    end
    table.sort(list)
    world_.zones = byName
    world_.zone_list = list
end

local function gatherWeather(world_)
    local m = env.mission
    world_.date = { Year = m.date.Year, Month = m.date.Month, Day = m.date.Day }
    world_.start_time = m.start_time
    world_.abs_time = timer.getAbsTime()
    -- Deep-copy the weather table so the plan dump is plain data we own.
    local function copy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = copy(v) end
        return out
    end
    world_.weather = copy(m.weather)
end

-- Cross-checks the cluster table against what DCS reports.
local function checkClusters(world_)
    local inCluster = {}
    world_.unknown_bases = {}
    for _, c in ipairs(CLUSTERS) do
        for _, name in ipairs(c.bases) do
            inCluster[name] = c.id
            if not world_.airbases[name] then
                world_.unknown_bases[#world_.unknown_bases + 1] = name
                Log.warn("clusters.lua lists '" .. name .. "' but DCS has no such airdrome")
            end
        end
    end
    world_.unlisted_bases = {}
    for _, name in ipairs(world_.airbase_list) do
        if not inCluster[name] then
            world_.unlisted_bases[#world_.unlisted_bases + 1] = name
            Log.warn("DCS airdrome '" .. name .. "' is not in any cluster")
        end
    end
    world_.base_cluster = inCluster
end

function Gather.run()
    Log.info("--- Gather inputs ---")
    local w = {}
    w.rng_steps = Util.seedRandom()
    gatherAirbases(w)
    gatherZones(w)
    gatherWeather(w)
    checkClusters(w)
    Log.info(string.format("  %d airdromes, %d zones, %d clusters, rng advanced %d",
        #w.airbase_list, #w.zone_list, #CLUSTERS, w.rng_steps))
    return w
end
