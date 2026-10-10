-- Logs: the sleeping base defenses in the event log, so problems with sleeping can be seen
-- without a line per switch (record\ground_units_awake.lua):
--   UNIT_AWAKE   BLUE  DEF_ROVA  "6 groups / 14 units awake: MSN7023_STRIKE_1 (Su-34) 28 km out"
--   UNIT_ASLEEP  BLUE  DEF_ROVA  "6 groups / 14 units asleep after 12 min awake; 3 close passes, 41 shots, 6 hits, 1 kill"
--   LATE_WAKE    BLUE  DEF_ROVA  "MSN7023_STRIKE_1 (Su-34) 8 km out while the base slept: woken now"
--                                 never expected: the wake-up rule missed an aircraft
--   AWAKE_COUNT  BLUE            "2 of 18 bases awake: 27 of 160 sleeping units awake"   every summary_every_s
-- and a table per base in the event log's end summary: wakes, minutes awake, close passes,
-- shots, hits, kills, and "CHECK" on a base that had close passes but never fired (a sign
-- DCS didn't wake it properly).

GroundUnitsAwakeLog = {}

local function plural(n, word)
    if n == 1 then return "1 " .. word end
    return string.format("%d %s%s", n, word, word:sub(-1) == "s" and "es" or "s")
end

-- Units alive in a base's sleeping groups.
local function aliveUnits(b)
    local n = 0
    for _, id in ipairs(b.groups) do n = n + RecordGroups.size(id) end
    return n
end

local function summaryLine()
    for _, c in ipairs({ "blue", "red" }) do
        local bases, awake, units, awakeUnits = 0, 0, 0, 0
        for _, b in ipairs(RecordGroundUnitsAwake.bases()) do
            if b.side == c then
                local n = aliveUnits(b)
                bases, units = bases + 1, units + n
                if b.awake then awake, awakeUnits = awake + 1, awakeUnits + n end
            end
        end
        EventLog.add(c, "AWAKE_COUNT", "", string.format("%d of %d bases awake: %d of %d sleeping units awake",
            awake, bases, awakeUnits, units))
    end
end

-- After the controller has put them to sleep (controller\wake_ground_units.lua).
function GroundUnitsAwakeLog.start()
    if not RecordGroundUnitsAwake.started() then return end
    RecordGroundUnitsAwake.on("late_wake", function(e)
        EventLog.add(e.base.side, "LATE_WAKE", e.base.subject, string.format(
            "%s %.0f km out while the base slept: woken now", e.who, e.km))
    end)
    RecordGroundUnitsAwake.on("awake", function(e)
        EventLog.add(e.base.side, "UNIT_AWAKE", e.base.subject, string.format("%d groups / %d units awake: %s %.0f km out",
            e.groups, e.units, e.who, e.km))
    end)
    RecordGroundUnitsAwake.on("asleep", function(e)
        local w = e.wake
        EventLog.add(e.base.side, "UNIT_ASLEEP", e.base.subject, string.format(
            "%d groups / %d units asleep after %.0f min awake; %s, %s, %s, %s", e.groups, e.units, e.minutes,
            plural(w.passes, "close pass"), plural(w.shots, "shot"), plural(w.hits, "hit"),
            plural(w.kills, "kill")))
    end)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(summaryLine)
        if not ok then Log.warn("sleep ground units: summary failed: " .. tostring(err)) end
        return now + GROUND_UNIT_SLEEP.summary_every_s
    end, nil, timer.getTime() + GROUND_UNIT_SLEEP.summary_every_s)
end

-- The table for the event log's end summary: one line per base that ever woke or saw a
-- late wake; "CHECK" where enemy aircraft passed close while it was awake but it never
-- fired.
function GroundUnitsAwakeLog.summaryLines()
    if not RecordGroundUnitsAwake.started() then return {} end
    local now = timer.getTime()
    local bases = RecordGroundUnitsAwake.bases()
    local lines = { "Sleeping ground units (bases that woke; never woken: asleep all mission):",
        string.format("%-4s  %-10s %5s %9s %7s %6s %5s %6s %5s", "", "", "wakes", "min awake", "passes", "shots",
            "hits", "kills", "late") }
    local never = 0
    for _, b in ipairs(bases) do
        if b.wakes == 0 then
            never = never + 1
        else
            local awakeS = b.awake_s + (b.awake and (now - b.woke_at) or 0)
            lines[#lines + 1] = string.format("%-4s  %-10s %5d %9.0f %7d %6d %5d %6d %5d%s", b.side:upper(), b.subject,
                b.wakes, awakeS / 60, b.passes, b.shots, b.hits, b.kills, b.late_wakes,
                (b.passes >= 2 and b.shots == 0) and "  CHECK: close passes but never fired" or "")
        end
    end
    lines[#lines + 1] = string.format("%d of %d bases never woke", never, #bases)
    return lines
end
