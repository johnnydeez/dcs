-- Shows the spawn sites map_data_tools\find_spawn_sites.py found, so John can check them by
-- eye (2026-10-07): runs in the viewer mission (find_spawn_sites.py make-missions writes it),
-- never in a flyable mission. Works on any map.
--   ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\map_surveys\\show_spawn_sites.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- Reads every Saved Games\DCS\map_surveys\<map>\spawn_sites_*.lua (SPAWN_SITES) and, on the
-- F10 map for everyone: each surveyed area's outline and name; each site as a circle of its
-- radius with its number; the cells that were flat and dry enough for pass 2 but held no
-- site, as a faint square, so a near miss can be told from steep ground. On the ground:
-- Red trucks in each site (TRUCKS_*, one group per site, AI off; F7 cycles them), so a site
-- on top of a house or a wall shows up in the 3D world; and in SAM_TEST_SITES of them a
-- whole SA-10 instead, laid out as the framework lays one out. Every vehicle's own spot is
-- checked (goodSpot: dry and flat under the vehicle). The comms menu has no entries; the
-- F10 map and the external view are the whole tool.
--
-- The SA-10's recipe is the framework's own (mission_scripts\data\sam_site_recipes.lua),
-- read from the repository, whose place on this PC comes from
-- Saved Games\DCS\Scripts\map_surveys\local_paths.lua (MAP_SURVEY_PATHS.repository_folder;
-- bug 76). Without it the trucks are shown and the SA-10s left out.

-- Kept light (2026-10-08: three areas at 19 trucks a site were 11,533 units and ~3,400 map
-- drawings, DCS's antifreeze kicked in and the F10 map ran at 9 fps): John, 2026-10-08: one
-- truck in the centre and 3 on each ring (7 a site; the outer ring turned 60° from the inner,
-- so the six spread evenly), shown on the F10 map so he can see what sits where; and areas
-- he has already approved aren't shown at all.
local TRUCK_TYPE      = "Ural-375"
local TRUCKS_INNER    = 3      -- at TRUCK_INNER_F of the site's radius
local TRUCKS_OUTER    = 3      -- at TRUCK_OUTER_F
local TRUCK_INNER_F   = 0.45
local TRUCK_OUTER_F   = 0.9
local OUTER_TURN      = math.pi / 3
local SPAWN_TRUCKS    = true
local TRUCKS_ON_F10_MAP = true
-- spawn_sites_<name>.lua areas John has reviewed and approved: left off the map and the ground
local APPROVED_AREAS  = { Bagram_Kabul_probe = true }   -- John, 2026-10-07: "looks pretty good"

-- Flat ground under each vehicle (John, 2026-10-08: every site suits trucks off road, but
-- parts of a site wouldn't take an SA-10; "require a more stringent flat area for the
-- vehicles within the zone"). A spot is flat when the ground at it and at FLAT_DIRECTIONS
-- points FLAT_SAMPLE_M around it lies within FLAT_MAX_RISE_M: a 16 m footprint (a 5P85
-- launcher is ~13 m long) with no more than ~3° of slope. The real missions' spawner must
-- do the same.
local FLAT_SAMPLE_M    = 8
local FLAT_DIRECTIONS  = 8
local FLAT_MAX_RISE_M  = 0.8

-- SA-10s for John to judge (2026-10-08: "do 50 SA-10 sites at various zones"): picked
-- evenly through every shown area's sites (numbered row by row across the area, so they
-- spread over each area, more in the area with more sites), each laid out by the
-- framework's recipe in the site.
local SAM_TEST_SYSTEM  = "SA-10"
local SAM_TEST_SITES   = 50
local SAM_TEST_TRIES   = 60    -- random spots tried per unit in its ring of the footprint
local SAM_COLOUR       = { 1, 0, 0, 1 }
local SAM_FILL         = { 1, 0, 0, 0.25 }

local MAP    = (env.mission and env.mission.theatre) or "unknown_map"
local FOLDER = lfs.writedir() .. "map_surveys\\" .. MAP .. "\\"

local function log(msg) env.info("[SPAWN SITES SHOWN] " .. msg) end
local function say(msg, s) trigger.action.outText("SPAWN SITES: " .. msg, s or 30) end

local nextId = 1000
local function newId()
    nextId = nextId + 1
    return nextId
end

local function point(x, z) return { x = x, y = land.getHeight({ x = x, y = z }), z = z } end

-- Our own random numbers in [0, 1): the mission environment has no math.randomseed, and a
-- fixed seed lays the SA-10s out the same way every time (dcs_scripting_gotchas.md).
local seed = 12345
local function random()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
end

local AREA_COLOUR   = { 1, 1, 0, 0.9 }
local SITE_COLOUR   = { 0, 1, 0, 1 }
local SITE_FILL     = { 0, 1, 0, 0.25 }
local MISS_COLOUR   = { 1, 0.5, 0, 0.35 }
local MISS_FILL     = { 1, 0.5, 0, 0.12 }
local TEXT_COLOUR   = { 1, 1, 1, 1 }
local NO_FILL       = { 0, 0, 0, 0 }

local function drawArea(sites)
    local a = sites.area
    trigger.action.quadToAll(-1, newId(), point(a.x_min, a.z_min), point(a.x_min, a.z_max), point(a.x_max, a.z_max),
        point(a.x_max, a.z_min), AREA_COLOUR, NO_FILL, 1, true)
    trigger.action.textToAll(-1, newId(), point(a.x_max + 500, a.z_min), TEXT_COLOUR, NO_FILL, 14, true,
        string.format("%s: %d sites", a.name, #sites.sites))
    for _, c in ipairs(sites.near_misses or {}) do
        trigger.action.quadToAll(-1, newId(), point(c.x, c.z), point(c.x, c.z + c.size_m), point(c.x + c.size_m, c.z + c.size_m),
            point(c.x + c.size_m, c.z), MISS_COLOUR, MISS_FILL, 1, true)
    end
end

-- ── A vehicle's own spot ─────────────────────────────────────────
-- Dry (John, 2026-10-07: some trucks stood in rivers; the survey samples the surface every
-- 100 m, and a narrower river passes between the points) and flat (above).
local function isDry(x, z)
    local s = land.getSurfaceType({ x = x, y = z })
    return s == land.SurfaceType.LAND or s == land.SurfaceType.ROAD
end

local function isFlat(x, z)
    local low = land.getHeight({ x = x, y = z })
    local high = low
    for k = 0, FLAT_DIRECTIONS - 1 do
        local a = k * 2 * math.pi / FLAT_DIRECTIONS
        local h = land.getHeight({ x = x + FLAT_SAMPLE_M * math.cos(a), y = z + FLAT_SAMPLE_M * math.sin(a) })
        if h < low then low = h end
        if h > high then high = h end
        if high - low > FLAT_MAX_RISE_M then return false end
    end
    return true
end

-- Why (x, z) won't take a vehicle, or nil: water first (cheap), then the slope, then
-- `spacing` from the units already placed.
local function spotProblem(x, z, placed, spacing)
    if not isDry(x, z) then return "water" end
    if not isFlat(x, z) then return "slope" end
    for _, u in ipairs(placed or {}) do
        if (u.x - x) ^ 2 + (u.y - z) ^ 2 < spacing * spacing then return "spacing" end
    end
    return nil
end

-- The nearest good spot to (x, z) no farther than `limit` from the site's centre, looked for
-- on rings 10 m apart, 16 directions each; or nil. Returns x, z, how far it moved, and why
-- the spot asked for wasn't good.
local SEARCH_STEP_M     = 10
local SEARCH_DIRECTIONS = 16
local function goodSpot(site, x, z, limit, placed, spacing)
    local why = spotProblem(x, z, placed, spacing)
    if not why then return x, z, 0 end
    for r = SEARCH_STEP_M, 2 * site.radius_m, SEARCH_STEP_M do
        for k = 0, SEARCH_DIRECTIONS - 1 do
            local a = k * 2 * math.pi / SEARCH_DIRECTIONS
            local px, pz = x + r * math.cos(a), z + r * math.sin(a)
            if math.sqrt((px - site.x) ^ 2 + (pz - site.z) ^ 2) <= limit
                and not spotProblem(px, pz, placed, spacing) then
                return px, pz, r, why
            end
        end
    end
    return nil, nil, nil, why
end

local counts = { trucks = 0, sam_units = 0, sam_sites = 0, moved = { water = 0, slope = 0, spacing = 0 },
                 left_out = { water = 0, slope = 0, spacing = 0 } }

local function addGroup(name, units, visibleOnMap)
    local ok, group = pcall(coalition.addGroup, country.id.CJTF_RED, Group.Category.GROUND,
        { name = name, task = "Ground Nothing", units = units, x = units[1].x, y = units[1].y, visible = true,
          hidden = not visibleOnMap })
    if not ok or not group then
        log("group " .. name .. " failed: " .. tostring(group))
        return
    end
    -- AI off: the trucks stay where they were put, and the SA-10s' radars stay quiet
    pcall(function() group:getController():setOnOff(false) end)
end

-- One Red ground group per site (John, 2026-10-07: Red units, so F7 cycles through them;
-- static objects aren't units and F7 skips them).
local function spawnTrucks(name, s)
    local units = {}
    local function one(x, z, heading)
        local dx, dz, moved, why = goodSpot(s, x, z, s.radius_m)
        if not dx then
            counts.left_out[why] = counts.left_out[why] + 1
            log(string.format("%s: no dry, flat spot near x %d z %d within the site (%s): truck left out", name, x, z, why))
            return
        end
        if moved > 0 then counts.moved[why] = counts.moved[why] + 1 end
        counts.trucks = counts.trucks + 1
        units[#units + 1] = { name = string.format("%s_truck_%d", name, #units + 1), type = TRUCK_TYPE,
                              x = dx, y = dz, heading = heading, skill = "Average" }
    end
    one(s.x, s.z, 0)
    for k = 1, TRUCKS_INNER do
        local a = (k - 1) * 2 * math.pi / TRUCKS_INNER
        one(s.x + s.radius_m * TRUCK_INNER_F * math.cos(a), s.z + s.radius_m * TRUCK_INNER_F * math.sin(a), a)
    end
    for k = 1, TRUCKS_OUTER do
        local a = (k - 1) * 2 * math.pi / TRUCKS_OUTER + OUTER_TURN
        one(s.x + s.radius_m * TRUCK_OUTER_F * math.cos(a), s.z + s.radius_m * TRUCK_OUTER_F * math.sin(a), a)
    end
    if #units > 0 then addGroup(name, units, TRUCKS_ON_F10_MAP) end
end

-- ── The SA-10s ───────────────────────────────────────────────────
-- The framework's recipe and its places (SAM_SITE_RECIPE, SAM_SITE_PLACE), or nil and why.
local function loadRecipes()
    MAP_SURVEY_PATHS = nil
    pcall(dofile, lfs.writedir() .. "Scripts\\map_surveys\\local_paths.lua")
    local repo = MAP_SURVEY_PATHS and MAP_SURVEY_PATHS.repository_folder
    if not repo then return nil, "no Scripts\\map_surveys\\local_paths.lua, so the recipes' place isn't known" end
    local file = repo .. "\\shared_mission_framework\\mission_scripts\\data\\sam_site_recipes.lua"
    local ok, err = pcall(dofile, file)
    if not ok or not SAM_SITE_RECIPE or not SAM_SITE_PLACE then return nil, "could not load " .. file .. ": " .. tostring(err) end
    if not SAM_SITE_RECIPE[SAM_TEST_SYSTEM] then return nil, "no recipe for " .. SAM_TEST_SYSTEM end
    return SAM_SITE_RECIPE[SAM_TEST_SYSTEM]
end

-- One site of the recipe at the spawn site's centre, as the framework lays it out (each part
-- at a random spot in its ring of the footprint, unit_spacing apart; the most of each part),
-- every spot dry and flat. A unit that finds no spot in its ring takes the nearest good spot
-- anywhere in the spawn site; with none it is left out. Returns how many units it placed.
local function spawnSamSite(name, s, recipe)
    local units = {}
    local footprint, spacing = recipe.footprint_m, recipe.unit_spacing
    for _, placeName in ipairs({ "centre", "launchers", "edge" }) do
        local fracs = SAM_SITE_PLACE[placeName]
        for _, part in ipairs(recipe.parts) do
            if part[4] == placeName then
                for _ = 1, part[3] do
                    local x, z, a
                    for _ = 1, SAM_TEST_TRIES do
                        local r1, r2 = footprint * fracs[1], footprint * fracs[2]
                        local d = math.sqrt(r1 * r1 + random() * (r2 * r2 - r1 * r1))
                        a = random() * 2 * math.pi
                        local px, pz = s.x + d * math.cos(a), s.z + d * math.sin(a)
                        if not spotProblem(px, pz, units, spacing) then x, z = px, pz; break end
                    end
                    if not x then
                        local px, pz, _, why = goodSpot(s, s.x + footprint * fracs[2] * math.cos(a),
                            s.z + footprint * fracs[2] * math.sin(a), s.radius_m, units, spacing)
                        if px then
                            x, z = px, pz
                            if why then   -- nil: the ring's outer edge itself was good
                                counts.moved[why] = counts.moved[why] + 1
                                log(string.format("%s: %s found no spot in its ring (%s); moved within the site", name, part[1], why))
                            end
                        else
                            counts.left_out[why] = counts.left_out[why] + 1
                            log(string.format("%s: %s found no dry, flat spot in the site (%s): left out", name, part[1], why))
                        end
                    end
                    if x then
                        -- launchers face outward, the rest any way
                        local heading = placeName == "launchers" and math.atan2(z - s.z, x - s.x) or random() * 2 * math.pi
                        units[#units + 1] = { name = string.format("%s_%d", name, #units + 1), type = part[1],
                                              x = x, y = z, heading = heading, skill = "Average" }
                    end
                end
            end
        end
    end
    if #units > 0 then addGroup(name, units, true) end
    counts.sam_units = counts.sam_units + #units
    counts.sam_sites = counts.sam_sites + 1
    local p = point(s.x, s.z)
    trigger.action.circleToAll(-1, newId(), p, footprint, SAM_COLOUR, SAM_FILL, 1, true)
    trigger.action.textToAll(-1, newId(), point(s.x - s.radius_m - 900, s.z), SAM_COLOUR, NO_FILL, 12, true,
        string.format("%s %s", SAM_TEST_SYSTEM, name))
    return #units
end

local function drawSite(s, prefix, samRecipe)
    local name = prefix .. "_" .. s.number
    trigger.action.circleToAll(-1, newId(), point(s.x, s.z), s.radius_m, SITE_COLOUR, SITE_FILL, 1, true)
    trigger.action.textToAll(-1, newId(), point(s.x + s.radius_m + 100, s.z), TEXT_COLOUR, NO_FILL, 11, true,
        string.format("%d", s.number))
    if samRecipe then
        local placed = spawnSamSite(name, s, samRecipe)
        local planned = 0
        for _, part in ipairs(samRecipe.parts) do planned = planned + part[3] end
        log(string.format("%s %s: %d of %d units placed (rise %s m)", SAM_TEST_SYSTEM, name, placed, planned, tostring(s.rise_m)))
    elseif SPAWN_TRUCKS then
        spawnTrucks(name, s)
    end
end

local function run()
    local attributes = lfs.attributes((FOLDER:gsub("\\$", "")))   -- gsub's count left out (gotchas)
    if not (attributes and attributes.mode == "directory") then
        say("no folder " .. FOLDER .. ": run the survey and find_spawn_sites.py first", 60)
        return
    end
    local files = {}
    for name in lfs.dir(FOLDER) do   -- the iterator itself, never through pcall (gotchas)
        local area = name:match("^spawn_sites_(.*)%.lua$")
        if area and APPROVED_AREAS[area] then
            log(area .. ": approved already, not shown")
        elseif area then
            files[#files + 1] = name
        end
    end
    table.sort(files)

    local loaded, shown, total = {}, {}, 0
    for _, name in ipairs(files) do
        SPAWN_SITES = nil
        local okLoad, err = pcall(dofile, FOLDER .. name)
        if okLoad and SPAWN_SITES then
            loaded[#loaded + 1] = SPAWN_SITES
            total = total + #SPAWN_SITES.sites
        else
            log("could not load " .. name .. ": " .. tostring(err))
            shown[#shown + 1] = name .. ": could not load (dcs.log)"
        end
    end

    -- which sites get an SA-10: evenly through all of them, in area and number order
    local recipe, why = loadRecipes()
    if not recipe then log("no " .. SAM_TEST_SYSTEM .. "s: " .. why) end
    local samAt, index = {}, 0
    if recipe and total > 0 then
        for k = 0, math.min(SAM_TEST_SITES, total) - 1 do
            samAt[math.floor(k * total / math.min(SAM_TEST_SITES, total)) + 1] = true
        end
    end

    for _, sites in ipairs(loaded) do
        drawArea(sites)
        local prefix = sites.area.name:gsub("[^%w_]", "_")
        local sams = 0
        for _, s in ipairs(sites.sites) do
            index = index + 1
            if samAt[index] then sams = sams + 1 end
            drawSite(s, prefix, samAt[index] and recipe or nil)
        end
        shown[#shown + 1] = string.format("%s: %d sites, %d with an %s", sites.area.name, #sites.sites, sams, SAM_TEST_SYSTEM)
    end

    local moved = string.format("moved %d off water, %d off a slope, %d for spacing", counts.moved.water,
        counts.moved.slope, counts.moved.spacing)
    local leftOut = string.format("left out %d (water %d, slope %d, spacing %d)",
        counts.left_out.water + counts.left_out.slope + counts.left_out.spacing,
        counts.left_out.water, counts.left_out.slope, counts.left_out.spacing)
    log(string.format("%d areas, %d sites; %d trucks; %d %s sites, %d units; %s; %s",
        #loaded, total, counts.trucks, counts.sam_sites, SAM_TEST_SYSTEM, counts.sam_units, moved, leftOut))
    say(string.format("%d areas, %d sites (green circles; orange squares: flat and dry, but no site)\n"
        .. "%d trucks; %d %s sites (red circles), %d units%s\n%s; %s\n%s",
        #loaded, total, counts.trucks, counts.sam_sites, SAM_TEST_SYSTEM, counts.sam_units,
        recipe and "" or (" (none: " .. why .. ")"), moved, leftOut, table.concat(shown, "\n")), 60)
end

local ok, err = pcall(run)
if not ok then
    log("failed: " .. tostring(err))
    say("FAILED: " .. tostring(err), 60)
end
