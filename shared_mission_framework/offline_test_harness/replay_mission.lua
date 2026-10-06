-- Offline test harness: runs a mission's real init.lua under luae.exe, on a saved world,
-- with a fixed seed, and writes what came out to an output folder for comparing runs.
--
--   luae.exe replay_mission.lua <scripts name> <scripts folder> <saved plan file> <seed> <mode> <output folder> [<name>=<folder>...] [coverage]
--
--   scripts name     the mission's folder under Saved Games\DCS\Scripts (Kola: kola_f16); its
--                    init.lua is loaded from there, as the mission editor trigger does
--   scripts folder   where those scripts really are (the repository), with a trailing backslash
--   saved plan file  a plan the mission wrote (Saved Games\DCS\kola_last_plan.lua): only its
--                    plan.world is used, in place of what gather.lua reads from DCS
--   seed             the random generator's seed (a different seed rolls a different mission)
--   mode             "plan": stop once the plan is written, before anything spawns (test A)
--                    "mission:<seconds>": the whole mission, its clock run that long after the
--                    start, everything standing still (test B, level 1; stub_dcs_world.lua),
--                    then the mission's end event
--                    "flying:<seconds>": the same, with the AI aircraft flying their routes
--                    radars seeing them and a stand-in Blue player circling a front base
--                    (test B, level 2; simple_flight_model.lua, simple_sensors.lua,
--                    stand_in_player.lua)
--   output folder    every file the run writes, with a trailing backslash
--   name=folder      (optional, any number) another folder under Saved Games\DCS\Scripts the
--                    mission loads from, and where it really is, with a trailing backslash (the
--                    shared framework's: shared_mission_framework=<repository>\
--                    shared_mission_framework\mission_scripts\)
--   coverage         (optional) also write coverage.txt: per file of the scripts folders, how
--                    many of its code lines ran (measure_coverage.lua). Slower; never compared.
--
-- Writes into the output folder: the plan dump (under the mission's own CONFIG.PLAN_DUMP_FILE
-- name), dcs_log.txt (every log line), screen_texts.txt, commands.txt (os.execute, never run),
-- redirected_writes.txt (writes the mission aimed outside the output folder), result.txt;
-- in mission mode also redirected\ (the event log, the radio calls file), menu_items.txt,
-- drawings.txt, orders.txt.
-- Exit code 0 when the run finished as the mode expects, 1 otherwise.

local HARNESS_FOLDER = arg[0]:match("^(.*[\\/])") or ".\\"
dofile(HARNESS_FOLDER .. "stub_dcs.lua")
dofile(HARNESS_FOLDER .. "stub_dcs_world.lua")
dofile(HARNESS_FOLDER .. "simple_flight_model.lua")
dofile(HARNESS_FOLDER .. "simple_sensors.lua")
dofile(HARNESS_FOLDER .. "stand_in_player.lua")
dofile(HARNESS_FOLDER .. "measure_coverage.lua")

local scriptsName, scriptsFolder, savedPlanFile, seed, mode, outputFolder = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5], arg[6]
-- every scripts folder, the mission's first: name under Saved Games\DCS\Scripts, folder on disk
local scriptFolders = { { name = scriptsName, folder = scriptsFolder } }
local measureCoverage = false
for i = 7, #arg do
    local name, folder = arg[i]:match("^([^=]+)=(.+)$")
    if arg[i] == "coverage" then
        measureCoverage = true
    elseif name then
        scriptFolders[#scriptFolders + 1] = { name = name, folder = folder }
    else
        print("unknown argument " .. arg[i] .. " (\"<name>=<folder>\" or \"coverage\")")
        os.exit(1)
    end
end
local scriptFoldersByName = {}
for _, f in ipairs(scriptFolders) do scriptFoldersByName[f.name] = f.folder end
if not (scriptsName and scriptsFolder and savedPlanFile and seed and mode and outputFolder) then
    print("usage: luae.exe replay_mission.lua <scripts name> <scripts folder> <saved plan file> <seed> <mode> <output folder>")
    os.exit(1)
end
local missionKind, missionSeconds = mode:match("^(%a+):(%d+)$")
missionSeconds = tonumber(missionSeconds)
if mode ~= "plan" and not (missionSeconds and (missionKind == "mission" or missionKind == "flying")) then
    print("unknown mode " .. mode .. " (\"plan\", \"mission:<seconds>\" or \"flying:<seconds>\")")
    os.exit(1)
end

-- the saved world, read into a table of its own so its global `plan` doesn't leak
local saved = {}
local chunk = assert(loadfile(savedPlanFile))
setfenv(chunk, saved)
chunk()
local savedWorld = assert(saved.plan and saved.plan.world, savedPlanFile .. " holds no plan.world")

StubDcs.install({
    output_folder = outputFolder,
    script_folders = scriptFoldersByName,
    seed = seed,
    world = savedWorld,
})
if missionSeconds then StubDcsWorld.install(savedWorld) end
if missionKind == "flying" then
    SimpleFlightModel.install()
    SimpleSensors.install()
    StandInPlayer.install("blue")
end

-- After each file the mission loads, the harness's own changes, once their module exists:
--   Gather.run          returns the saved world instead of reading DCS
--   WriteEventLog.open  (mode "plan") the first call after the plan dump: stop there
local STOP = "OFFLINE HARNESS: stopped after planning"
local hooked = {}
local stubDofile = dofile
local loadedFiles, loadedOnce = {}, {}   -- test C: every file the mission loads, in order
dofile = function(path)
    local key = StubDcs.diskPathOf(path):gsub("/", "\\"):lower()
    if loadedOnce[key] then env.error("OFFLINE HARNESS: loaded twice: " .. path) end
    loadedOnce[key] = true
    loadedFiles[#loadedFiles + 1] = path
    local results = { stubDofile(path) }
    if Gather and not hooked.gather then
        hooked.gather = true
        Gather.run = function()
            Log.info("--- Gather inputs --- (offline harness: the saved world from " .. savedPlanFile .. ")")
            return savedWorld
        end
    end
    if mode == "plan" and WriteEventLog and not hooked.event_log then
        hooked.event_log = true
        WriteEventLog.open = function() error(STOP, 0) end
    end
    return unpack(results)
end
-- files read with loadfile (a mission's override files) go in the load list too
local stubLoadfile = loadfile
loadfile = function(path)
    local key = StubDcs.diskPathOf(path):gsub("/", "\\"):lower()
    if loadedOnce[key] then env.error("OFFLINE HARNESS: loaded twice: " .. path) end
    loadedOnce[key] = true
    loadedFiles[#loadedFiles + 1] = path
    return stubLoadfile(path)
end

if measureCoverage then MeasureCoverage.start(scriptFolders) end
dofile(lfs.writedir() .. "Scripts\\" .. scriptsName .. "\\init.lua")
if missionSeconds then
    StubDcs.runClock(missionSeconds)
    -- every comms menu command opened once, in the order added (frags, steerpoints, airfield
    -- info...), so the texts they build are written too
    for _, item in ipairs(StubDcsWorld.menu_items) do
        if item.kind == "command" and item.fn then
            StubDcs.screen_texts[#StubDcs.screen_texts + 1] = "=== comms menu: " .. item.path
            local ok, err = pcall(item.fn, item.arg)
            if not ok then env.error("comms menu " .. item.path .. " failed: " .. tostring(err)) end
        end
    end
    StubDcsWorld.fireEvent({ id = world.event.S_EVENT_MISSION_END })
    StubDcs.runClock(missionSeconds + 30)   -- the event log's last write
else
    StubDcs.runClock(60)
end

-- ── What came out ───────────────────────────────────────────────

-- The output folder is written as "<output>\", so two runs into different folders compare
-- line for line.
local function writeLines(name, lines)
    local f = StubDcs.realOpen(outputFolder .. name, "w")
    for _, line in ipairs(lines) do
        local plain = line:gsub(outputFolder:gsub("%p", "%%%0"), "<output>\\")
        f:write(plain, "\n")
    end
    f:close()
end

-- test C: the files loaded, in order, as the mission named them; then every .lua file in the
-- scripts folders never loaded (one folder: one heading, as before the framework had its own;
-- several: a heading each)
local loadList = {}
for _, path in ipairs(loadedFiles) do loadList[#loadList + 1] = path end
for _, f in ipairs(scriptFolders) do
    loadList[#loadList + 1] = #scriptFolders == 1 and "-- never loaded, in the scripts folder:"
        or "-- never loaded, in Scripts\\" .. f.name .. "\\:"
    local listing = io.popen('dir /s /b "' .. f.folder .. '*.lua" 2>nul')
    local onDisk = {}
    for path in listing:lines() do onDisk[#onDisk + 1] = path end
    listing:close()
    table.sort(onDisk, function(a, b) return a:lower() < b:lower() end)
    for _, path in ipairs(onDisk) do
        if not loadedOnce[path:gsub("/", "\\"):lower()] then loadList[#loadList + 1] = path:sub(#f.folder + 1) end
    end
end
writeLines("loaded_files.txt", loadList)

writeLines("dcs_log.txt", StubDcs.log_lines)
writeLines("screen_texts.txt", StubDcs.screen_texts)
writeLines("commands.txt", StubDcs.commands)
local redirected = {}
for _, r in ipairs(StubDcs.redirected_writes) do redirected[#redirected + 1] = r.asked .. "  ->  " .. r.written end
writeLines("redirected_writes.txt", redirected)

-- finished as expected: planning reached its end (mode "plan": the stop line; a mission:
-- "Init complete." and no error after it), and nothing went wrong
local finished, problems = false, {}
local FINISHED = missionSeconds and "Init complete." or STOP
for _, line in ipairs(StubDcs.log_lines) do
    if line:find(FINISHED, 1, true) then
        finished = true
    elseif line:find("[ERROR]", 1, true) or line:find("FATAL", 1, true) or line:find("^ERROR ") then
        problems[#problems + 1] = line
    end
end
local warnings = 0
for _, line in ipairs(StubDcs.log_lines) do if line:find("[WARN]", 1, true) then warnings = warnings + 1 end end
local result = {}
if not finished then
    result[#result + 1] = missionSeconds and "FAILED: init never completed" or "FAILED: the run never reached the end of planning"
end
for _, line in ipairs(problems) do result[#result + 1] = "FAILED: " .. line end
if #result == 0 then
    result[1] = string.format("OK: %s with seed %d; %d log lines, %d warnings, %d commands recorded, %d writes redirected",
        missionSeconds and string.format("%s run for %d s", missionKind == "flying" and "mission (flying)" or "mission", missionSeconds) or "planned",
        seed, #StubDcs.log_lines, warnings, #StubDcs.commands, #StubDcs.redirected_writes)
end

if missionSeconds then
    local W = StubDcsWorld
    local menus = {}
    for _, m in ipairs(W.menu_items) do menus[#menus + 1] = string.format("%-7s side %s  %s", m.kind, tostring(m.side), m.path) end
    writeLines("menu_items.txt", menus)
    local function counted(t)
        local keys, lines = {}, {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do lines[#lines + 1] = string.format("%6d  %s", t[k], k) end
        return lines
    end
    writeLines("drawings.txt", counted(W.drawings))
    writeLines("orders.txt", counted(W.order_counts))
    writeLines("spawned_countries.txt", counted(W.country_counts))
end

if measureCoverage then writeLines("coverage.txt", MeasureCoverage.report(scriptFolders)) end
writeLines("result.txt", result)
for _, line in ipairs(result) do print(line) end
os.exit(#problems == 0 and finished and 0 or 1)
