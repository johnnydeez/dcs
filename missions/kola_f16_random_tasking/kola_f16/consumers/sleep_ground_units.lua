-- Consumer: ground units sleep while no enemy aircraft is near (roadmap.md, performance
-- in VR). A sleeping group has its AI switched off (Controller:setOnOff(false)), so it
-- doesn't scan the sky: with ~500 short-reach base-defense units, that work multiplied
-- by every aircraft and missile in the air is what costs frames, not the units standing
-- there.
--
-- Per base, every GROUND_UNIT_SLEEP.check_every_s:
--   - its sleeping groups (base defenses of GROUND_UNIT_SLEEP.components) wake together
--     when an enemy aircraft is within wake_km of the base, with alarm state red so they
--     don't stay passive;
--   - they go back to sleep once no enemy aircraft has been within wake_km, and the base
--     hasn't fired, for sleep_after_s. A base never goes to sleep mid-fight.
-- Everything starts asleep. SAM sites and radar missile launchers never sleep.
--
-- Event log lines (consumers/write_event_log.lua), so problems with sleeping can be seen
-- without a line per switch:
--   UNIT_AWAKE   BLUE  DEF_ROVA  "6 groups / 14 units awake: MSN5023_STRIKE_1 (Su-34) 28 km out"
--   UNIT_ASLEEP  BLUE  DEF_ROVA  "6 groups / 14 units asleep after 12 min awake; 3 close passes, 41 shots, 6 hits, 1 kill"
--   LATE_WAKE    BLUE  DEF_ROVA  "MSN5023_STRIKE_1 (Su-34) 8 km out while the base slept: woken now"
--                                 never expected: the wake-up rule missed an aircraft
--   AWAKE_COUNT  BLUE            "2 of 18 bases awake: 27 of 160 sleeping units awake"   every summary_every_s
-- HIT and DESTROYED lines of a sleeping unit end in "(asleep)" (WriteEventLog asks
-- SleepGroundUnits.isAsleep). The event log's end summary gets a table per base: wakes,
-- minutes awake, close passes, shots, hits, kills, and "CHECK" on a base that had close
-- passes but never fired (a sign DCS didn't wake it properly).
-- Reads the plan; writes nothing back to it.

SleepGroundUnits = {}

local SIDE = { red = 1, blue = 2 }
local ENEMY = { red = "blue", blue = "red" }

local _bases = {}        -- list of bases with sleeping groups (state below)
local _baseOfGroup = {}  -- group name → its base's state
local _started = false

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function controllerOf(groupName)
    local g = Group.getByName(groupName)
    return g and safe(function() return g:isExist() and g:getController() end) or nil
end

local function aliveUnits(b)
    local n = 0
    for _, id in ipairs(b.groups) do
        local g = Group.getByName(id)
        n = n + (g and safe(function() return g:isExist() and g:getSize() end) or 0)
    end
    return n
end

local function liveGroups(b)
    local n = 0
    for _, id in ipairs(b.groups) do
        if controllerOf(id) then n = n + 1 end
    end
    return n
end

local function setAwake(b, awake)
    for _, id in ipairs(b.groups) do
        local c = controllerOf(id)
        if c then
            pcall(function()
                c:setOnOff(awake)
                if awake then
                    c:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                end
            end)
        end
    end
    b.awake = awake
end

local function plural(n, word)
    if n == 1 then return "1 " .. word end
    return string.format("%d %s%s", n, word, word:sub(-1) == "s" and "es" or "s")
end

local function wake(b, now, nearest)
    setAwake(b, true)
    b.woke_at, b.last_near = now, now
    b.wakes = b.wakes + 1
    b.passed_now = {}
    WriteEventLog.add(b.side, "UNIT_AWAKE", b.subject, string.format("%d groups / %d units awake: %s %.0f km out",
        liveGroups(b), aliveUnits(b), nearest.who, nearest.km))
end

local function sleep(b, now)
    setAwake(b, false)
    local minutes = (now - b.woke_at) / 60
    b.awake_s = b.awake_s + (now - b.woke_at)
    local w = b.this_wake
    WriteEventLog.add(b.side, "UNIT_ASLEEP", b.subject, string.format(
        "%d groups / %d units asleep after %.0f min awake; %s, %s, %s, %s", liveGroups(b), aliveUnits(b), minutes,
        plural(w.passes, "close pass"), plural(w.shots, "shot"), plural(w.hits, "hit"),
        plural(w.kills, "kill")))
    b.this_wake = { passes = 0, shots = 0, hits = 0, kills = 0 }
end

-- Every enemy aircraft of `coalitionName`'s enemy: { pos, who }.
local function enemyAircraft(coalitionName)
    local list = {}
    for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        for _, g in ipairs(coalition.getGroups(SIDE[ENEMY[coalitionName]], category) or {}) do
            for _, u in ipairs(safe(function() return g:getUnits() end) or {}) do
                local p = safe(function() return u:isExist() and u:getPoint() end)
                if p then
                    list[#list + 1] = { pos = { x = p.x, z = p.z }, name = u:getName(),
                                        who = string.format("%s (%s)", u:getName(), u:getTypeName()) }
                end
            end
        end
    end
    return list
end

local function check()
    local now = timer.getTime()
    local enemies = { red = enemyAircraft("red"), blue = enemyAircraft("blue") }
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
                    WriteEventLog.add(b.side, "LATE_WAKE", b.subject, string.format(
                        "%s %.0f km out while the base slept: woken now", nearest.who, nearest.km))
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

local function summaryLine()
    for _, c in ipairs({ "blue", "red" }) do
        local bases, awake, units, awakeUnits = 0, 0, 0, 0
        for _, b in ipairs(_bases) do
            if b.side == c then
                local n = aliveUnits(b)
                bases, units = bases + 1, units + n
                if b.awake then awake, awakeUnits = awake + 1, awakeUnits + n end
            end
        end
        WriteEventLog.add(c, "AWAKE_COUNT", "", string.format("%d of %d bases awake: %d of %d sleeping units awake",
            awake, bases, awakeUnits, units))
    end
end

-- Shots, gun bursts, hits and kills by a sleeping group's units count for its base: they
-- keep it awake, and go in the UNIT_ASLEEP line and the end summary.
local function groupNameOf(o)
    return o and safe(function() return o:getGroup():getName() end)
end

local handler = {}
function handler:onEvent(e)
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
        local b = _baseOfGroup[groupNameOf(e.initiator) or ""]
        if not b then return end
        b[field] = b[field] + 1
        b.this_wake[field] = b.this_wake[field] + 1
        if field == "shots" then b.last_shot = timer.getTime() end
    end)
    if not ok then Log.warn("sleep ground units: event failed: " .. tostring(err)) end
end

-- Puts every sleeping group to sleep and starts the checks. After the ground groups have
-- spawned, after WriteEventLog.start.
function SleepGroundUnits.start(plan)
    if not CONFIG.SLEEP_GROUND_UNITS then
        Log.info("--- Sleep ground units: off (CONFIG.SLEEP_GROUND_UNITS) ---")
        return
    end
    local byBase = {}
    for _, g in ipairs(plan.base_defenses and plan.base_defenses.groups or {}) do
        if GROUND_UNIT_SLEEP.components[g.component] and Group.getByName(g.id) then
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
    _started = true
    world.addEventHandler(handler)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(check)
        if not ok then Log.warn("sleep ground units: check failed: " .. tostring(err)) end
        return now + GROUND_UNIT_SLEEP.check_every_s
    end, nil, timer.getTime() + 1)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(summaryLine)
        if not ok then Log.warn("sleep ground units: summary failed: " .. tostring(err)) end
        return now + GROUND_UNIT_SLEEP.summary_every_s
    end, nil, timer.getTime() + GROUND_UNIT_SLEEP.summary_every_s)
    Log.info(string.format("--- Sleep ground units: %d units at %d bases asleep; wake at %d km ---",
        units, #_bases, GROUND_UNIT_SLEEP.wake_km))
end

-- Whether the group `groupName` is a sleeping group that is asleep now.
function SleepGroundUnits.isAsleep(groupName)
    local b = _baseOfGroup[groupName or ""]
    return b ~= nil and not b.awake
end

-- The table for the event log's end summary: one line per base that ever woke or saw a
-- late wake; "CHECK" where enemy aircraft passed close while it was awake but it never
-- fired.
function SleepGroundUnits.summaryLines()
    if not _started then return {} end
    local now = timer.getTime()
    local lines = { "Sleeping ground units (bases that woke; never woken: asleep all mission):",
        string.format("%-4s  %-10s %5s %9s %7s %6s %5s %6s %5s", "", "", "wakes", "min awake", "passes", "shots",
            "hits", "kills", "late") }
    local never = 0
    for _, b in ipairs(_bases) do
        if b.wakes == 0 then
            never = never + 1
        else
            local awakeS = b.awake_s + (b.awake and (now - b.woke_at) or 0)
            lines[#lines + 1] = string.format("%-4s  %-10s %5d %9.0f %7d %6d %5d %6d %5d%s", b.side:upper(), b.subject,
                b.wakes, awakeS / 60, b.passes, b.shots, b.hits, b.kills, b.late_wakes,
                (b.passes >= 2 and b.shots == 0) and "  CHECK: close passes but never fired" or "")
        end
    end
    lines[#lines + 1] = string.format("%d of %d bases never woke", never, #_bases)
    return lines
end
