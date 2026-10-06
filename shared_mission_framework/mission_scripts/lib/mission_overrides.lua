-- Mission overrides: a mission's own values for shared settings, merged into the shared
-- defaults once every data file is loaded (shared_mission_framework\development_docs\plan.md,
-- *Settings: shared defaults, mission overrides*; John, 2026-10-06: no duplicated code, so a
-- mission tunes a shared setting by naming only the values that differ).
--
-- An override file looks exactly like the shared data file, holding only what differs:
--     AIR_CONTROL = { suppression = { killzone_fraction = 0.9 } }
-- It runs with globals of its own (it can read every shared global, but what it sets stays
-- its own), then each global it set is merged into the shared one:
--   keyed tables   merge key by key, as deep as the override goes
--   lists          ({ "a", "b" }, weighted rosters) are replaced whole: merging lists entry by
--                  entry is never what's meant
--   values         replace the default
-- A global or key the shared settings don't have stops the load with its name (a typo would
-- otherwise change nothing, silently); something only one mission has is mission data, not an
-- override. Every value changed is logged to dcs.log, default and override, so a run's log
-- shows how its mission differs.
--
-- MissionOverrides.apply(folder, fileNames) → true, or false and why.

MissionOverrides = {}

-- A list: a non-empty table whose keys are exactly 1..n.
local function isList(t)
    local n = #t
    if n == 0 then return false end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == n
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    return keys
end

local function shown(v)
    local text = type(v) == "table" and Util.serialize(v, "", true) or tostring(v)
    if #text > 120 then text = text:sub(1, 117) .. "..." end
    return text
end

local function keyPath(path, k)
    if type(k) == "number" then return string.format("%s[%d]", path, k) end
    return path .. "." .. tostring(k)
end

-- Merges `override` into `default` (both keyed tables), logging every change; errors on a key
-- the default doesn't have.
local function merge(path, default, override, fileName)
    for _, k in ipairs(sortedKeys(override)) do
        local v, old = override[k], default[k]
        local where = keyPath(path, k)
        if old == nil then
            error(string.format("%s: %s isn't a shared setting (a typo? something only this mission has belongs in its data)",
                fileName, where), 0)
        end
        if type(v) == "table" and type(old) == "table" and not isList(v) and not isList(old) then
            merge(where, old, v, fileName)
        else
            Log.info(string.format("override: %s %s → %s (%s)", where, shown(old), shown(v), fileName))
            default[k] = v
        end
    end
end

local function applyFile(path, fileName)
    local chunk, err = loadfile(path)
    if not chunk then error(string.format("%s: can't load: %s", fileName, tostring(err)), 0) end
    local set = setmetatable({}, { __index = _G })
    setfenv(chunk, set)
    chunk()
    for _, name in ipairs(sortedKeys(set)) do
        local v, default = set[name], _G[name]
        if default == nil then
            error(string.format("%s: %s isn't a shared setting", fileName, tostring(name)), 0)
        end
        if type(v) == "table" and type(default) == "table" and not isList(v) and not isList(default) then
            merge(name, default, v, fileName)
        else
            Log.info(string.format("override: %s %s → %s (%s)", name, shown(default), shown(v), fileName))
            _G[name] = v
        end
    end
end

function MissionOverrides.apply(folder, fileNames)
    if not fileNames or #fileNames == 0 then
        Log.info("--- Mission overrides: none (the shared settings as they are) ---")
        return true
    end
    Log.info(string.format("--- Mission overrides: %s ---", table.concat(fileNames, ", ")))
    for _, fileName in ipairs(fileNames) do
        local ok, err = pcall(applyFile, folder .. fileName, fileName)
        if not ok then return false, tostring(err) end
    end
    return true
end
