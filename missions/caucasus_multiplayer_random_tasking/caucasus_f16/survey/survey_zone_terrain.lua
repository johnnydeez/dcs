-- Caucasus's zone terrain survey: loaded by the trigger in caucasus_multiplayer_rt_zones.miz
-- (the zone drawing mission), never in the flyable mission:  ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\caucasus_f16\\survey\\survey_zone_terrain.lua")
-- Loads Caucasus's settings (mission_settings.lua: MISSION, its file names and folders), then
-- the shared survey (shared_mission_framework\mission_scripts\survey\survey_zone_terrain.lua),
-- which measures every zone and runs the map tools on Caucasus's folder.

local function load(path)
    local ok, err = pcall(dofile, path)
    if not ok then
        env.info("[ZONE SURVEY] FATAL: could not load " .. path .. ": " .. tostring(err))
        trigger.action.outText("ZONE SURVEY FAILED — could not load " .. path .. "\n" .. tostring(err), 60)
    end
    return ok
end

if not load(lfs.writedir() .. "Scripts\\caucasus_f16\\mission_settings.lua") then return end
load(lfs.writedir() .. "Scripts\\" .. MISSION.framework_folder .. "\\survey\\survey_zone_terrain.lua")
