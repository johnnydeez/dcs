-- Mission entry point.
-- Loaded by a single Mission Editor trigger:
--   MISSION START → DO SCRIPT → dofile(lfs.writedir() .. "Scripts\\dcs-mission\\init.lua")
--
-- Requires MissionScripting.lua to be de-sanitized (lfs must be available).

local SCRIPT_DIR = lfs.writedir() .. "Scripts\\a2a_dynamic_syria\\"

local function load(relativePath)
    local fullPath = SCRIPT_DIR .. relativePath
    local ok, err = pcall(dofile, fullPath)
    if not ok then
        -- env.info is always available even without other libs
        env.info("[DCS-MISSION] FATAL: could not load " .. fullPath)
        env.info("[DCS-MISSION] Error: " .. tostring(err))
        trigger.action.outText("MISSION SCRIPT LOAD ERROR — check dcs.log\n" .. tostring(err), 60)
    end
    return ok
end

-- ── Load libraries first, then modules ───────────────────────
if not load("lib\\logger.lua") then return end

Log.info("============================================")
Log.info("  Mission scripts loading")
Log.info("  Script dir: " .. SCRIPT_DIR)
Log.info("============================================")

-- Uncomment the next line to dump all airbase names for debugging.
-- Log.dumpAirbases()
-- Uncomment the next line to dump all group names for debugging.
Log.dumpGroups()

if not load("lib\\spawner.lua")             then return end
if not load("modules\\coalition_setup.lua") then return end
if not load("modules\\defense_setup.lua")   then return end
if not load("modules\\sam_setup.lua")       then return end

-- ── Run startup sequence ─────────────────────────────────────
local assignments, clusterSides = CoalitionSetup.assign()
DefenseSetup.spawn(assignments)
SamSetup.spawn(clusterSides, assignments)

Log.info("Init complete.")
