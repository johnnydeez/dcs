-- Low-level spawn utilities.
-- Provides position helpers and thin wrappers around coalition.addGroup / Group:activate.
-- No mission-specific logic here — callers decide what to spawn and where.

Spawner = {}

-- Returns a position {x, y, alt} randomly placed within a ring around a Vec3 center.
-- If snapRoad is true, snaps to the nearest road; falls back to raw offset if no road nearby.
-- center: Vec3 from getPoint() — uses center.x and center.z as the horizontal plane.
function Spawner.nearPos(center, minDist, maxDist, snapRoad)
    local a    = math.random() * 2 * math.pi
    local dist = minDist + math.random() * (maxDist - minDist)
    local x    = center.x + dist * math.cos(a)
    local y    = center.z + dist * math.sin(a)

    if snapRoad then
        local rx, ry = land.getClosestPointOnRoads("roads", x, y)
        if rx then
            x, y = rx, ry
        else
            Log.debug("Spawner.nearPos: no road found, using raw offset")
        end
    end

    return { x = x, y = y, alt = land.getHeight({x = x, y = y}) }
end

-- Spawns a ground group at pos {x, y, alt}.
--
-- countryId : country.id constant (e.g. country.id.CJTF_RED)
-- pos       : {x, y, alt} from Spawner.nearPos or built manually
-- unitDefs  : array of { type, skill, heading }
--             skill defaults to "Average"; heading defaults to random
-- options   : { name, spread }
--             name   — group base name, should be unique per mission
--             spread — radius in metres within which units are randomly scattered
--                      around pos (default 0 = all at same point)
--
-- Returns the Group object, or nil on failure.
function Spawner.spawnGroundGroup(countryId, pos, unitDefs, options)
    options = options or {}
    local groupName = options.name
        or ("Group_" .. math.floor(timer.getAbsTime()) .. "_" .. math.random(999))
    local spread = options.spread or 0

    local units = {}
    for i, def in ipairs(unitDefs) do
        local ux, uy = pos.x, pos.y
        if spread > 0 then
            local a = math.random() * 2 * math.pi
            local d = math.random() * spread
            ux = ux + d * math.cos(a)
            uy = uy + d * math.sin(a)
        end
        units[i] = {
            name           = groupName .. "_" .. i,
            type           = def.type,
            skill          = def.skill or "Average",
            x              = ux,
            y              = uy,
            alt            = land.getHeight({x = ux, y = uy}),
            heading        = def.heading or (math.random() * 2 * math.pi),
            playerCanDrive = false,
        }
    end

    local grp = coalition.addGroup(countryId, Group.Category.GROUND, {
        name  = groupName,
        task  = "Ground Nothing",
        x     = pos.x,
        y     = pos.y,
        units = units,
    })

    if grp then
        Log.debug("Spawner: spawned '" .. groupName .. "' (" .. #units .. " units)")
    else
        Log.warn("Spawner: coalition.addGroup returned nil for '" .. groupName .. "'")
    end

    return grp
end

-- Activates a late-activation group placed in the Mission Editor.
function Spawner.activateGroup(groupName)
    local grp = Group.getByName(groupName)
    if grp then
        grp:activate()
        Log.debug("Spawner: activated '" .. groupName .. "'")
        return true
    end
    Log.warn("Spawner.activateGroup: '" .. groupName .. "' not found")
    return false
end
