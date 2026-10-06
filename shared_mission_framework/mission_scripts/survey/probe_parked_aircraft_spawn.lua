-- One-off probe (CONFIG.PROBE_PARKED_AIRCRAFT_SPAWN): why are parked aircraft slow to
-- spawn? The 2026-09-24 run spent ~3 s per static aircraft (C-130 ~10 s, Hornet ~5 s)
-- inside coalition.addStaticObject, against ~0.03 s per structure. Suspected: DCS
-- searching its livery folders on every spawn when the country is CJTF and no livery_id
-- is given. When the flag is on, init runs only this probe (nothing else plans or spawns).
--
-- At PROBE_BASE, for each type: one warm-up spawn (model loading), then two copies of
-- every variant — country CJTF or a real one, livery none or named — and, for
-- comparison, one uncontrolled AI aircraft group parked on a spot. Each object is timed,
-- then destroyed. Results go to dcs.log ("[KOLA] ... PROBE") and on screen.

ProbeParkedAircraftSpawn = {}

local PROBE_BASE = "Bodo"
local COPIES = 2

-- type, category, coalition, real country, named livery (nil: none to test)
local TYPES = {
    { "FA-18C_hornet", "Planes",   "blue", "NORWAY", "Finland 31" },
    { "C-130",         "Planes",   "blue", "NORWAY", "Royal Norwegian Air Force" },
    { "Su-27",         "Planes",   "red",  "RUSSIA", "Air Force Standard" },
    { "SKP-11",        "Unarmed",  "red",  "RUSSIA", nil },
}
local CJTF = { blue = "CJTF_BLUE", red = "CJTF_RED" }

local function clock()
    local ok, t = pcall(function() return os.clock() end)
    return ok and t or 0
end

local _n = 0
local function nextName()
    _n = _n + 1
    return "PROBE_" .. _n
end

-- Spawns one static object, returns seconds spent in addStaticObject (nil on failure) and why.
local function timeStatic(countryName, t, category, livery, spot)
    local name = nextName()
    local data = { name = name, type = t, category = category, x = spot[1], y = spot[2],
                   heading = 0, dead = false, livery_id = livery }
    local t0 = clock()
    local ok, err = pcall(coalition.addStaticObject, country.id[countryName], data)
    local spent = clock() - t0
    local obj = StaticObject.getByName(name)
    if obj then pcall(obj.destroy, obj) end
    if not ok or not obj then return nil, tostring(err or "not spawned") end
    return spent
end

-- Spawns one uncontrolled AI aircraft group parked on a spot, returns seconds or nil, why.
local function timeUncontrolled(countryName, t, airdromeId, spot)
    local name = nextName()
    local x, y = spot[1], spot[2]
    local data = {
        name = name, task = "Nothing", uncontrolled = true,
        route = { points = { { type = "TakeOffParking", action = "From Parking Area",
                               airdromeId = airdromeId, x = x, y = y, alt = 0, speed = 0 } } },
        units = { { name = name .. "_1", type = t, x = x, y = y, alt = 0, speed = 0, heading = 0,
                    skill = "Average", parking = spot[4], payload = { fuel = 1000 } } },
    }
    local t0 = clock()
    local ok, err = pcall(coalition.addGroup, country.id[countryName], Group.Category.AIRPLANE, data)
    local spent = clock() - t0
    local grp = Group.getByName(name)
    if grp then pcall(grp.destroy, grp) end
    if not ok or not grp then return nil, tostring(err or "not spawned") end
    return spent
end

function ProbeParkedAircraftSpawn.run(world_)
    Log.info("--- PROBE: parked aircraft spawn time ---")
    local ab = world_.airbases[PROBE_BASE]
    local dcsBase = Airbase.getByName(PROBE_BASE)
    if not ab or not dcsBase or #ab.parking < 10 then
        Log.error("PROBE: no usable parking at " .. PROBE_BASE)
        return
    end
    local airdromeId = dcsBase:getID()
    -- large spots only, so every type fits; objects are destroyed after timing, so spots are reused
    local spots = {}
    for _, s in ipairs(ab.parking) do if s[3] == 104 then spots[#spots + 1] = s end end
    if #spots == 0 then spots = ab.parking end

    local lines = {}
    local function report(label, seconds, why)
        local line = seconds and string.format("PROBE %-58s %6.2f s", label, seconds)
                              or string.format("PROBE %-58s FAILED: %s", label, why)
        Log.info("  " .. line)
        lines[#lines + 1] = line
    end

    local k = 0
    local function spot()
        k = k % #spots + 1
        return spots[k]
    end

    for _, e in ipairs(TYPES) do
        local t, category, coalitionName, real, livery = e[1], e[2], e[3], e[4], e[5]
        report(t .. " warm-up (CJTF, no livery)", timeStatic(CJTF[coalitionName], t, category, nil, spot()))
        local variants = {
            { "CJTF, no livery",           CJTF[coalitionName], nil },
            { real .. ", no livery",       real,                nil },
        }
        if livery then
            variants[#variants + 1] = { "CJTF, livery " .. livery,  CJTF[coalitionName], livery }
            variants[#variants + 1] = { real .. ", livery " .. livery, real,             livery }
        end
        for _, v in ipairs(variants) do
            for i = 1, COPIES do
                report(string.format("%s static, %s #%d", t, v[1], i), timeStatic(v[2], t, category, v[3], spot()))
            end
        end
        if category == "Planes" then
            report(t .. " uncontrolled AI group, CJTF", timeUncontrolled(CJTF[coalitionName], t, airdromeId, spot()))
        end
    end
    Log.info("--- PROBE done ---")
    trigger.action.outText("PARKED AIRCRAFT SPAWN PROBE\n" .. table.concat(lines, "\n"), 120)
end
