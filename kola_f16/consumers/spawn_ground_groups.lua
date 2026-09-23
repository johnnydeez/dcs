-- Consumer: spawns plan ground-group entries with coalition.addGroup.
-- Takes any list of entries shaped { id, side, skill, units = { { type, x, z, heading_deg } } }
-- (plan.base_defenses.groups now; zone garrisons later). The entry id is the DCS group
-- name; unit names are <id>_<n>. Every group holds position (no route).
--
-- After each spawn, every unit's getTypeName() is compared with the type the plan asked
-- for — DCS silently swaps an unknown type for a Leopard-2, and this catches it by name.
-- Reads the plan; writes nothing back to it.

SpawnGroundGroups = {}

local COUNTRY = { red = "CJTF_RED", blue = "CJTF_BLUE" }

local function buildGroup(entry)
    local units = {}
    for i, u in ipairs(entry.units) do
        units[i] = {
            name           = entry.id .. "_" .. i,
            type           = u.type,
            skill          = entry.skill or "Average",
            x              = u.x,
            y              = u.z,                       -- DCS group tables: y = east
            heading        = math.rad(u.heading_deg or 0),
            playerCanDrive = false,
        }
    end
    return {
        name  = entry.id,
        task  = "Ground Nothing",
        x     = entry.pos.x,
        y     = entry.pos.z,
        units = units,
    }
end

-- Returns the number of units whose spawned type differs from the plan.
local function checkTypes(entry, grp)
    local mismatches = 0
    local spawned = grp:getUnits() or {}
    if #spawned ~= #entry.units then
        Log.warn(string.format("%s: planned %d units, DCS has %d", entry.id, #entry.units, #spawned))
    end
    for i, u in ipairs(spawned) do
        local want = entry.units[i] and entry.units[i].type
        local got  = u:getTypeName()
        if want and got ~= want then
            mismatches = mismatches + 1
            Log.warn(string.format("%s unit %d: asked for '%s', DCS spawned '%s'", entry.id, i, want, got))
        end
    end
    return mismatches
end

function SpawnGroundGroups.run(entries, label)
    label = label or "ground groups"
    Log.info("--- Spawn: " .. label .. " ---")
    local groups, units, failed, mismatches = 0, 0, 0, 0
    for _, entry in ipairs(entries or {}) do
        local countryId = country.id[COUNTRY[entry.side]]
        local ok, grp = pcall(coalition.addGroup, countryId, Group.Category.GROUND, buildGroup(entry))
        if ok and grp then
            groups = groups + 1
            units  = units + #entry.units
            mismatches = mismatches + checkTypes(entry, grp)
        else
            failed = failed + 1
            Log.warn(string.format("%s: coalition.addGroup failed (%s)", entry.id, tostring(grp)))
        end
    end
    Log.info(string.format("  spawned %d groups / %d units; %d failed; %d type mismatches",
        groups, units, failed, mismatches))
    return { groups = groups, units = units, failed = failed, mismatches = mismatches }
end
