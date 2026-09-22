-- Kola F-16 generator: entry point.
-- Loaded by one ME trigger:  ONCE → TIME MORE 1 → DO SCRIPT
--   dofile(lfs.writedir() .. "Scripts\\kola_f16\\init.lua")
-- Requires a de-sanitized MissionScripting.lua (lfs / io).
--
-- Load order: config → lib → data → gather → stages → consumers, then after a short
-- delay: gather inputs → stages 1..7 → plan dump → hand the plan to each consumer.

local SCRIPT_DIR = lfs.writedir() .. "Scripts\\kola_f16\\"

local function load(rel)
    local ok, err = pcall(dofile, SCRIPT_DIR .. rel)
    if not ok then
        env.info("[KOLA] FATAL: could not load " .. rel .. ": " .. tostring(err))
        trigger.action.outText("KOLA SCRIPT LOAD ERROR — " .. rel .. "\n" .. tostring(err), 60)
    end
    return ok
end

if not load("config.lua")                  then return end
if not load("lib\\util.lua")               then return end
if not load("lib\\logger.lua")             then return end

Log.info("============================================")
Log.info("  Kola F-16 generator loading")
Log.info("  " .. SCRIPT_DIR)
Log.info("============================================")

if not load("data\\clusters.lua")          then return end
if not load("data\\zones.lua")             then return end
if not load("gather.lua")                  then return end
if not load("stages\\s1_territory.lua")    then return end
if not load("consumers\\territory.lua")    then return end

-- ── Run sequence ────────────────────────────────────────────────

local function dumpPlan(plan)
    if not CONFIG.PLAN_DUMP then return end
    local path = Util.writeFile(CONFIG.PLAN_DUMP_FILE, "plan = " .. Util.serialize(plan) .. "\n")
    if path then Log.info("Plan written to " .. path) end
end

local function run()
    Log.dumpWeather()

    local plan = { world = Gather.run() }
    Stage1.run(plan)
    -- stages 2..7 go here

    dumpPlan(plan)

    Territory.apply(plan)
    trigger.action.outText(Territory.summaryText(plan), 120)
    Log.info("Init complete.")
end

timer.scheduleFunction(function()
    local ok, err = pcall(run)
    if not ok then
        Log.error("run() failed: " .. tostring(err))
    end
end, nil, timer.getTime() + CONFIG.START_DELAY)
