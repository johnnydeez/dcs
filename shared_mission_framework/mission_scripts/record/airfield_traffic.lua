-- The record of AI jets around the airfields: on the ground or in the air, where, how fast,
-- nose heading. One writer: watch\airfield_traffic.lua, worked out when read (rule 11).

RecordAirfieldTraffic = {}

-- Every unit of group `group` (watch\airfield_traffic.lua says what each holds).
function RecordAirfieldTraffic.jets(group)
    return WatchAirfieldTraffic.jets(group)
end
