-- The record of the flights the controller launches: every planned mission (never
-- changed), and per flight what the controller did with it. One writer: the controller
-- (controller\air_flights\schedule_flights.lua, decide_launches.lua, direct_flights.lua,
-- scramble_fighters.lua). What happened to each flight once flying is record\flights.lua.
--
-- A launch entry: { mission (as planned, or the copy for a retry or a scramble),
--   mission_flown (a late launch's copy), spawned, spawned_at, note ("delayed",
--   "cancelled", "not needed"), again (the id of its second try), later (its third, a
--   rotation flight's come-back), removed (jets removed on the ramp, unarmed), stood_down }
--
-- Events (published as subject "flight_launches"):
--   added           { id }         a flight entered the ledger (planned at start, a retry, a scramble)
--   removed         { id }         jets of it were removed on the ramp (`removed` grew)
--   removed_in_air  { id, names }  jets of it the controller is removing in the air, counted as landed

RecordFlightLaunches = {}

local SUBJECT = "flight_launches"

local _byId = {}       -- planned mission id → mission
local _launches = {}   -- flight id → launch entry

-- ── Writes (the controller only) ────────────────────────────────

-- A planned mission, at start.
function RecordFlightLaunches.addPlanned(m)
    _byId[m.id] = m
end

-- A flight into the ledger: `entry` holds at least `mission`.
function RecordFlightLaunches.add(id, entry)
    _launches[id] = entry
    RecordFlightLaunches.publish({ event = "added", id = id })
end

-- Sets `fields` on flight `id`'s entry (nil values clear a field).
function RecordFlightLaunches.write(id, fields)
    local e = _launches[id]
    for k, v in pairs(fields) do e[k] = v end
end

-- Clears field `key` on flight `id`'s entry.
function RecordFlightLaunches.clear(id, key)
    _launches[id][key] = nil
end

function RecordFlightLaunches.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s %s", tostring(e.id), e.event) end)
end

-- ── Reads ───────────────────────────────────────────────────────

-- fn(event) on `eventName` (above).
function RecordFlightLaunches.on(eventName, fn)
    Record.subscribe(SUBJECT, function(e)
        if e.event == eventName then fn(e) end
    end)
end

-- The planned mission `id` (never changed).
function RecordFlightLaunches.planned(id)
    return _byId[id]
end

-- Flight `id`'s launch entry, or nil. Read it, never change it.
function RecordFlightLaunches.launch(id)
    return _launches[id]
end

-- The mission flight `id` flies (a late launch or a retry has its own copy), or nil.
function RecordFlightLaunches.missionFlown(id)
    local l = id and _launches[id]
    return l and (l.mission_flown or l.mission) or nil
end

-- A planned flight's state now, in a few words: "planned", "airborne", "landed",
-- "2 of 2 lost", …, plus its target objects destroyed so far (anyone's hits count).
-- Reads record\flights.lua too.
function RecordFlightLaunches.statusOf(id)
    local l = _launches[id]
    local f = RecordFlights.facts(id)
    if not l or not f then return "unknown" end
    local m = l.mission
    local state
    if m.flown_by == "human" then
        state = "for a player"
    elseif l.note == "not needed" or l.note == "cancelled" then
        state = l.note
    elseif l.stood_down then
        state = "stood down on the ramp"
    elseif not l.spawned then
        state = l.note == "delayed" and "delayed" or "planned"
    elseif (l.removed or 0) >= m.count then
        state = "removed on the ramp, unarmed"
    elseif f.lost >= m.count then
        state = string.format("%d of %d lost", f.lost, m.count)
    elseif f.lost + f.landed + (l.removed or 0) >= m.count then
        state = f.lost > 0 and string.format("landed, %d lost", f.lost) or "landed"
    else
        state = f.lost > 0 and string.format("airborne, %d lost", f.lost) or "airborne"
    end
    if (l.removed or 0) > 0 and l.removed < m.count then
        state = string.format("%s, %d removed unarmed", state, l.removed)
    end
    if f.destroyed > 0 then
        state = string.format("%s; target %d of %d critical destroyed", state, f.destroyed, #(m.critical_names or {}))
    end
    return state
end
