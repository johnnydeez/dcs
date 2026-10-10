-- The record of AI flights reaching their waypoints: { id (the flight), index (the
-- waypoint in its route) }, each as it happens. One writer: watch\flight_routes.lua (the
-- waypoint's script command). A stream: nothing kept.
--
-- Subscribers, in the order they subscribe: the event log (its WAYPOINT line), Watch's
-- radar warning snapshot at a SEAD flight's launch and press-on points, the controller,
-- the flight calls (a flight "pushing", a patrol on and off station).

RecordWaypointsReached = {}

local SUBJECT = "waypoints_reached"

function RecordWaypointsReached.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s waypoint %d", e.id, e.index) end)
end

-- fn(id, index) on every waypoint reached from now on.
function RecordWaypointsReached.on(fn)
    Record.subscribe(SUBJECT, function(e) fn(e.id, e.index) end)
end
