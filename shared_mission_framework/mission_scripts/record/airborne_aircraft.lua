-- The record of AI aircraft in the air per coalition (players don't count). One writer:
-- watch\airborne_aircraft.lua, worked out when read (rule 11).

RecordAirborneAircraft = {}

function RecordAirborneAircraft.count(c)
    return WatchAirborneAircraft.count(c)
end
