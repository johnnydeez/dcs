-- Controller: ground units sleep while no enemy aircraft is near (roadmap.md, performance
-- in VR). A sleeping group has its AI switched off (execute\ground_units_on_off.lua), so it
-- doesn't scan the sky: with ~500 short-reach base-defense units, that work multiplied
-- by every aircraft and missile in the air is what costs frames, not the units standing
-- there.
--
-- Per base, every GROUND_UNIT_SLEEP.check_every_s:
--   - its sleeping groups (base defenses of GROUND_UNIT_SLEEP.components) wake together
--     when an enemy aircraft (record\enemy_aircraft_near_bases.lua) is within wake_km of
--     the base, with alarm state red so they don't stay passive;
--   - they go back to sleep once no enemy aircraft has been within wake_km, and the base
--     hasn't fired, for sleep_after_s. A base never goes to sleep mid-fight.
-- Everything starts asleep. SAM sites and radar missile launchers never sleep.
--
-- Each wake and sleep is a decision written to record\ground_units_awake.lua first (the
-- event log's UNIT_AWAKE / UNIT_ASLEEP / LATE_WAKE lines and its end table,
-- logs\ground_units_awake.lua), then the AI switched (rule 3). HIT and DESTROYED lines of
-- a sleeping unit end in "(asleep)" (the event log asks RecordGroundUnitsAwake.isAsleep).
-- Reads the plan; writes nothing back to it.

ControllerWakeGroundUnits = {}

local _bases = {}        -- list of bases with sleeping groups (state below)
local _baseOfGroup = {}  -- group name → its base's state
-- the bases are the Record's (record\ground_units_awake.lua)

-- Units alive in a base's sleeping groups, and its groups still there.
local function aliveUnits(b)
    local n = 0
    for _, id in ipairs(b.groups) do n = n + RecordGroups.size(id) end
    return n
end

local function liveGroups(b)
    local n = 0
    for _, id in ipairs(b.groups) do
        if RecordGroups.hasController(id) then n = n + 1 end
    end
    return n
end

local function setAwake(b, awake)
    ExecuteGroundUnitsOnOff.set(b.groups, awake)
    b.awake = awake
end

local function wake(b, now, nearest)
    b.woke_at, b.last_near = now, now
    b.wakes = b.wakes + 1
    b.passed_now = {}
    RecordGroundUnitsAwake.publish({ event = "awake", base = b, groups = liveGroups(b), units = aliveUnits(b),
                                     who = nearest.who, km = nearest.km })
    setAwake(b, true)
end

local function sleep(b, now)
    local minutes = (now - b.woke_at) / 60
    b.awake_s = b.awake_s + (now - b.woke_at)
    RecordGroundUnitsAwake.publish({ event = "asleep", base = b, groups = liveGroups(b), units = aliveUnits(b),
                                     minutes = minutes, wake = b.this_wake })
    setAwake(b, false)
    b.this_wake = { passes = 0, shots = 0, hits = 0, kills = 0 }
end

local function check()
    local now = timer.getTime()
    local enemies = { red = RecordEnemyAircraftNearBases.enemyAircraft("red"),
                      blue = RecordEnemyAircraftNearBases.enemyAircraft("blue") }
    local wakeM, reachM = GROUND_UNIT_SLEEP.wake_km * 1000, GROUND_UNIT_SLEEP.reach_km * 1000
    for _, b in ipairs(_bases) do
        local nearest
        for _, e in ipairs(enemies[b.side]) do
            local d = Util.dist(b.pos, e.pos)
            if d <= wakeM and (not nearest or d < nearest.d) then nearest = { d = d, km = d / 1000, who = e.who, name = e.name } end
            if b.awake and d <= reachM and not b.passed_now[e.name] then
                b.passed_now[e.name] = true
                b.this_wake.passes = b.this_wake.passes + 1
                b.passes = b.passes + 1
            end
        end
        if not b.awake then
            if nearest then
                if nearest.d <= reachM then
                    b.late_wakes = b.late_wakes + 1
                    RecordGroundUnitsAwake.publish({ event = "late_wake", base = b, who = nearest.who, km = nearest.km })
                end
                wake(b, now, nearest)
                -- the aircraft that woke it may already be a close pass
                if nearest.d <= reachM then
                    b.passed_now[nearest.name] = true
                    b.this_wake.passes, b.passes = 1, b.passes + 1
                end
            end
        else
            if nearest then b.last_near = now end
            if now - math.max(b.last_near, b.last_shot or 0) >= GROUND_UNIT_SLEEP.sleep_after_s then
                sleep(b, now)
            end
        end
    end
end

-- Shots, gun bursts, hits and kills by a sleeping group's units (record\dcs_events.lua)
-- count for its base: they keep it awake, and go in the UNIT_ASLEEP line and the end summary.
local function onEvent(e)
    local ok, err = pcall(function()
        local ev = world.event
        local field
        if e.id == ev.S_EVENT_SHOT or e.id == ev.S_EVENT_SHOOTING_START then
            field = "shots"
        elseif e.id == ev.S_EVENT_HIT then
            field = "hits"
        elseif e.id == ev.S_EVENT_KILL then
            field = "kills"
        else
            return
        end
        local b = _baseOfGroup[e.initiator and e.initiator.group or ""]
        if not b then return end
        b[field] = b[field] + 1
        b.this_wake[field] = b.this_wake[field] + 1
        if field == "shots" then b.last_shot = timer.getTime() end
    end)
    if not ok then Log.warn("sleep ground units: event failed: " .. tostring(err)) end
end

-- Puts every sleeping group to sleep and starts the checks. After the ground groups have
-- spawned, after EventLog.start.
function ControllerWakeGroundUnits.start(plan)
    if not CONFIG.SLEEP_GROUND_UNITS then
        Log.info("--- Sleep ground units: off (CONFIG.SLEEP_GROUND_UNITS) ---")
        return
    end
    local byBase = {}
    for _, g in ipairs(plan.base_defenses and plan.base_defenses.groups or {}) do
        if GROUND_UNIT_SLEEP.components[g.component] and RecordGroups.exists(g.id) then
            local b = byBase[g.base]
            if not b then
                local info = plan.base_defenses.bases[g.base] or {}
                b = { base = g.base, side = g.side, subject = "DEF_" .. (info.code or g.base),
                      pos = plan.world.airbases[g.base].pos, groups = {}, awake = true,
                      wakes = 0, awake_s = 0, passes = 0, shots = 0, hits = 0, kills = 0, late_wakes = 0,
                      passed_now = {}, this_wake = { passes = 0, shots = 0, hits = 0, kills = 0 } }
                byBase[g.base] = b
                _bases[#_bases + 1] = b
            end
            b.groups[#b.groups + 1] = g.id
            _baseOfGroup[g.id] = b
        end
    end
    table.sort(_bases, function(a, b) return a.base < b.base end)
    local units = 0
    for _, b in ipairs(_bases) do
        setAwake(b, false)
        units = units + aliveUnits(b)
    end
    RecordGroundUnitsAwake.writeBases(_bases, _baseOfGroup)
    RecordDcsEvents.on(onEvent)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(check)
        if not ok then Log.warn("sleep ground units: check failed: " .. tostring(err)) end
        return now + GROUND_UNIT_SLEEP.check_every_s
    end, nil, timer.getTime() + 1)
    -- the AWAKE_COUNT lines' timer comes next (logs\ground_units_awake.lua, started right after)
    Log.info(string.format("--- Sleep ground units: %d units at %d bases asleep; wake at %d km ---",
        units, #_bases, GROUND_UNIT_SLEEP.wake_km))
end
