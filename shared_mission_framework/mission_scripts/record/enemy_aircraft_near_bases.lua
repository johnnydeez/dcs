-- The record of the enemy aircraft the sleeping base defenses wake for. One writer:
-- watch\enemy_aircraft_near_bases.lua, worked out when read (rule 11).

RecordEnemyAircraftNearBases = {}

-- Every aircraft of `coalitionName`'s enemy now: { pos, name, who }.
function RecordEnemyAircraftNearBases.enemyAircraft(coalitionName)
    return WatchEnemyAircraftNearBases.enemyAircraft(coalitionName)
end
