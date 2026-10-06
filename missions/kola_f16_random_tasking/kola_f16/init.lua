-- Kola F-16 random tasking: entry point.
-- Loaded by one ME trigger:  ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- This mission's settings first (mission_settings.lua: MISSION, its names, map facts, data
-- files and overrides), then the shared mission framework loads everything
-- (load_framework.lua) and plays the run sequence (run_mission.lua).

local SCRIPT_DIR = lfs.writedir() .. "Scripts\\kola_f16\\"

local function load(path)
    local ok, err = pcall(dofile, path)
    if not ok then
        local tag = MISSION and MISSION.log_tag or "MISSION"
        env.info("[" .. tag .. "] FATAL: could not load " .. path .. ": " .. tostring(err))
        trigger.action.outText(tag .. " SCRIPT LOAD ERROR — " .. path .. "\n" .. tostring(err), 60)
    end
    return ok
end

if not load(SCRIPT_DIR .. "mission_settings.lua") then return end
local FRAMEWORK_DIR = lfs.writedir() .. "Scripts\\" .. MISSION.framework_folder .. "\\"
if not load(FRAMEWORK_DIR .. "load_framework.lua") then return end
if not LoadFramework.run() then return end
if not load(FRAMEWORK_DIR .. "run_mission.lua") then return end
RunMission.start()
