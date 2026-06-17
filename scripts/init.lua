-- Mission entry point.
-- Loaded by a single Mission Editor trigger:
--   MISSION START → DO SCRIPT → dofile(lfs.writedir() .. "Scripts\\dcs-mission\\init.lua")
--
-- Requires MissionScripting.lua to be de-sanitized (lfs must be available).

local SCRIPT_DIR = lfs.writedir() .. "Scripts\\a2g_dynamic_syria\\"

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
-- Activates debug groups A-D and logs unit type strings; remove after type strings are confirmed.
Log.dumpLateGroupUnits({"A", "B", "C", "D", "E"})

if not load("lib\\spawner.lua")             then return end
if not load("modules\\coalition_setup.lua") then return end
if not load("modules\\defense_setup.lua")   then return end
if not load("modules\\sam_setup.lua")       then return end
if not load("modules\\convoy_setup.lua")    then return end
if not load("modules\\cas_mission.lua")     then return end
if not load("modules\\sd_mission.lua")      then return end
if not load("modules\\mission_setup.lua")   then return end
if not load("modules\\cost_config.lua")        then return end
if not load("modules\\cost_logic.lua")         then return end
if not load("modules\\cost_ui.lua")            then return end
if not load("modules\\blue_air_support.lua")   then return end

-- ── Run startup sequence ─────────────────────────────────────
local assignments, clusterSides = CoalitionSetup.assign()
DefenseSetup.spawn(assignments)

local samMenu      = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "SAM Threats")
local missionsMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Missions")
SamSetup.spawn(clusterSides, assignments, samMenu)
ConvoySetup.spawn(clusterSides, assignments, missionsMenu)
MissionSetup.generate(assignments, missionsMenu)
BlueAirSupport.init(assignments)

Log.info("Init complete.")
