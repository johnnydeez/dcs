-- The record of the controller's decisions about AI flights, each as it is made:
-- { coalition, subject (the flight, jet or contact it is about), decision (its word:
-- "defend", "go cold", "scramble", …), text, details }. details carry what a listener needs
-- without reading the text: reason (one word per why, e.g. "salvo_over", "bingo",
-- "raid_turned_away"), threat (the bandit's group), relief (a patrol's relief), units (the
-- jets a landing order went to), targets (a scramble's raid).
-- One writer: the controller (rule 3: a decision is written here first, then the controller
-- calls Execute, whose result is record\orders.lua). A stream: nothing is kept.
--
-- Subscribers, in the order they subscribe: the event log first (logs\event_log.lua: one
-- CONTROL line per decision), then the flight calls and Darkstar (inform\radio\).

RecordAirFlightDecisions = {}

local SUBJECT = "air_flight_decisions"

-- Writes decision `d` (the controller only) and returns it.
function RecordAirFlightDecisions.write(d)
    Record.publish(SUBJECT, d, function(e) return string.format("%s %s", tostring(e.subject), tostring(e.decision)) end)
    return d
end

-- fn(decision) on every decision from now on.
function RecordAirFlightDecisions.on(fn)
    Record.subscribe(SUBJECT, fn)
end
