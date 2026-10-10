-- The record of the flights the controller watches: each flight's watch entry (its
-- mission, directives, state "on_task" / "going_home", on_station_at, defending) and when
-- each came off its task. One writer: the controller (controller\air_flights\direct_flights.lua).
-- Read by Watch (the shots it keeps, a patrol's relief) and the rest of the controller.

RecordWatchedFlights = {}

local _watched, _offTaskAt = {}, {}

-- The controller's tables, kept up to date in place, never replaced: flight id → watch
-- entry; flight id → mission time it came off its task (kept after the watch ends).
function RecordWatchedFlights.writeTables(watched, offTaskAt)
    _watched, _offTaskAt = watched, offTaskAt
end

-- Whether flight `id` is watched now.
function RecordWatchedFlights.isWatched(id)
    return _watched[id] ~= nil
end

-- Flight `id`'s watch entry (its mission, directives, state …), or nil. Read it, never change it.
function RecordWatchedFlights.flight(id)
    return _watched[id]
end

-- True while the flight is watched and still on its task: launched and not yet sent
-- home, stood down, landed or lost (scrambles: is it still after its raid?).
function RecordWatchedFlights.onTask(id)
    local w = _watched[id]
    return w ~= nil and w.state == "on_task"
end

-- The mission time flight `id` came off its task (sent home, landed, lost; the first of
-- these), or nil while it's still on it or the controller hasn't seen it end yet.
function RecordWatchedFlights.offTaskSince(id)
    return _offTaskAt[id]
end

-- Every watched flight's watch entry (for facts that look across flights: a patrol's
-- relief). Read them, never change them.
function RecordWatchedFlights.watchedFlights()
    local list = {}
    for _, w in pairs(_watched) do list[#list + 1] = w end
    return list
end
