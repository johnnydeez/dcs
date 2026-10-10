-- The record of what happened to each flight: jets that took off, landed, were lost; its
-- mission's target objects destroyed; wingmen possibly orphaned; whether it is down. One
-- writer: watch\flights.lua. What the controller did with each flight (launched, noted,
-- flown again, removed) is record\flight_launches.lua.
--
-- Facts per flight: { destroyed (its target's critical objects), lost, landed,
--   last_landing_at, last_landed (unit name), orphans (unit name → { since, lead, closed }),
--   down (every jet landed, lost or removed) }
--
-- Events (published as subject "flights"):
--   down  { id }  every jet of flight `id` is down, said once

RecordFlights = {}

local SUBJECT = "flights"

local _facts, _gone, _tookOff = {}, {}, {}

-- ── Writes (watch\flights.lua only) ─────────────────────────────

-- The watcher's tables, kept up to date in place, never replaced: flight id → facts;
-- names counted destroyed or lost; unit names of AI jets that have taken off.
function RecordFlights.writeTables(facts, gone, tookOff)
    _facts, _gone, _tookOff = facts, gone, tookOff
end

function RecordFlights.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s %s", tostring(e.id), e.event) end)
end

-- ── Reads ───────────────────────────────────────────────────────

-- fn(event) on `eventName` (above).
function RecordFlights.on(eventName, fn)
    Record.subscribe(SUBJECT, function(e)
        if e.event == eventName then fn(e) end
    end)
end

-- Flight `id`'s facts, or nil. Read them, never change them.
function RecordFlights.facts(id)
    return _facts[id]
end

-- True once AI jet `unitName` has taken off.
function RecordFlights.tookOff(unitName)
    return _tookOff[unitName] == true
end

-- True once the object `name` has been counted destroyed or lost.
function RecordFlights.isGone(name)
    return _gone[name] == true
end

-- A mission's target progress: critical objects destroyed so far (anyone's hits count),
-- and how many it has.
function RecordFlights.targetProgress(id)
    local f, l = _facts[id], RecordFlightLaunches.launch(id)
    if not (f and l) then return 0, 0 end
    return f.destroyed, #(l.mission.critical_names or {})
end

-- Why group `name` is no longer there, for a CONTROL line: "MSN2017_CAP destroyed",
-- "… landed" (its jets despawned after landing), "… down (1 lost, 1 landed)", or "… gone"
-- for a group the flights record doesn't keep (a player). (2026-10-04 22:39 run: "leash
-- stand down: MSN2017_CAP destroyed" for an F-15C that had landed at Alakurtti.)
function RecordFlights.goneText(name)
    local r, l = _facts[name], RecordFlightLaunches.launch(name)
    if not r then return name .. " gone" end
    local landed = r.landed + (l.removed or 0)
    if r.lost > 0 and landed == 0 then return name .. " destroyed" end
    if landed > 0 and r.lost == 0 then return name .. " landed" end
    if landed > 0 then return string.format("%s down (%d lost, %d landed)", name, r.lost, landed) end
    return name .. " gone"
end

-- Where jet `unitName` of mission `m` is now, for an >>orphan<< line: "Su-34 at 4,232 ft,
-- 7 km from Banak" (worked out when read).
function RecordFlights.jetWhere(m, unitName)
    return WatchFlights.jetWhere(m, unitName)
end
