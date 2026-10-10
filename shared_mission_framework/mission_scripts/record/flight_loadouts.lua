-- The record of what launched flights carry: jets that spawned with no weapons although
-- their loadout lists some. One writer: watch\flight_loadouts.lua. A stream: nothing kept.
--
-- Events (published as subject "flight_loadouts"):
--   unarmed  { mission, units (jet names), loadout_text }  the controller removes them on the ramp

RecordFlightLoadouts = {}

local SUBJECT = "flight_loadouts"

function RecordFlightLoadouts.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s %s", e.mission.id, e.event) end)
end

function RecordFlightLoadouts.on(eventName, fn)
    Record.subscribe(SUBJECT, function(e)
        if e.event == eventName then fn(e) end
    end)
end
