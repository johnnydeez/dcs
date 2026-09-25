-- Consumer: spawns plan static-object entries with coalition.addStaticObject.
-- Takes any list of entries shaped { id, coalition, type, category, shape_name, x, z,
-- heading_deg } (plan.fixed_ground_targets.static_objects now). The entry id is the
-- DCS static object's name.
--
-- After each spawn the object is looked up by name and its getTypeName() compared with
-- the type the plan asked for: an unknown static type doesn't fail loudly in DCS, it
-- just isn't there. Reads the plan; writes nothing back to it.
--
-- ORDER: run this BEFORE any SpawnGroundGroups (init.lua). addStaticObject gets very
-- slow once many AI units exist — ~3 s per parked aircraft after ~800 units, ~0.00 s
-- into an empty world (measured 2026-09-24).

SpawnStaticObjects = {}

local COUNTRY = { red = "CJTF_RED", blue = "CJTF_BLUE" }

local function buildStatic(entry)
    return {
        name       = entry.id,
        type       = entry.type,
        category   = entry.category,
        shape_name = entry.shape_name,
        x          = entry.x,
        y          = entry.z,                         -- DCS tables: y = east
        heading    = math.rad(entry.heading_deg or 0),
        dead       = false,
    }
end

function SpawnStaticObjects.run(entries, label)
    label = label or "static objects"
    Log.info("--- Spawn: " .. label .. " ---")
    local spawned, failed, mismatches = 0, 0, 0
    for _, entry in ipairs(entries or {}) do
        local countryId = country.id[COUNTRY[entry.coalition]]
        local ok, err = pcall(coalition.addStaticObject, countryId, buildStatic(entry))
        local obj = ok and StaticObject.getByName(entry.id) or nil
        if obj then
            spawned = spawned + 1
            local got = obj:getTypeName()
            if got ~= entry.type then
                mismatches = mismatches + 1
                Log.warn(string.format("%s: asked for '%s', DCS spawned '%s'", entry.id, entry.type, tostring(got)))
            end
        else
            failed = failed + 1
            Log.warn(string.format("%s: static object '%s' (%s) not spawned%s", entry.id, entry.type,
                tostring(entry.category), ok and "" or (" (" .. tostring(err) .. ")")))
        end
    end
    Log.info(string.format("  spawned %d static objects; %d failed; %d type mismatches", spawned, failed, mismatches))
    return { spawned = spawned, failed = failed, mismatches = mismatches }
end
