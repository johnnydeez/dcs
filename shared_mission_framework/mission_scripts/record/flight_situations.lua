-- The record of the situation of a watched flight at one check, and the kill-zone and
-- depth questions about it. One writer: watch\flight_situations.lua, worked out when read
-- (rule 11; a situation's facts are filled in as a directive asks for them). The
-- controller asks here, so no actor names a Watch module.

RecordFlightSituations = {}

-- The situation of watched flight `w` (its watch entry) now, or nil when it has no live
-- unit to read.
function RecordFlightSituations.build(w)
    return WatchFlightSituations.build(w)
end

-- The enemy SAM site or base-defense radar SAM whose kill zone the aircraft at pos (y: its
-- altitude) is inside, or nil (watch\flight_situations.lua says how).
function RecordFlightSituations.enemyKillZone(coalition, pos, fraction, except, countSilenced)
    return WatchFlightSituations.enemyKillZone(coalition, pos, fraction, except, countSilenced)
end

-- The enemy kill zone any airborne jet of the flight in situation s is inside, and that jet.
function RecordFlightSituations.flightKillZone(s, fraction, except, countSilenced, skip)
    return WatchFlightSituations.flightKillZone(s, fraction, except, countSilenced, skip)
end

-- How far past the contested airspace the deepest airborne jet of the flight is, m.
function RecordFlightSituations.flightEnemyDepth(s, searchM)
    return WatchFlightSituations.flightEnemyDepth(s, searchM)
end

-- Whether a live jet of the flight is still on the ground before its takeoff (bug 48).
function RecordFlightSituations.waitingToTakeOff(s)
    return WatchFlightSituations.waitingToTakeOff(s)
end

-- The SAM sites a flight may be inside on purpose: its own target site and the rings its
-- planned route passes through, as a set.
function RecordFlightSituations.acceptedRings(m)
    return WatchFlightSituations.acceptedRings(m)
end
