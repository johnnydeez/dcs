-- The record of groups and units now: alive, in the air. One writer: watch\groups.lua,
-- worked out when read (rule 11), so actors and Inform never name a Watch module.

RecordGroups = {}

-- Whether group `name` exists with at least one live unit.
function RecordGroups.alive(name)
    return WatchGroups.live(name) ~= nil
end

-- Whether the unit or static object `name` exists with life of at least 1.
function RecordGroups.liveUnit(name)
    return WatchGroups.liveUnit(name)
end

-- Whether the unit `name` exists.
function RecordGroups.unitExists(name)
    return WatchGroups.unitExists(name)
end

-- The names of group `name`'s live units.
function RecordGroups.liveUnitNames(name)
    return WatchGroups.liveUnitNames(name)
end

-- The first live jet of group `name` in the air: { name, type, point, velocity }, or nil.
function RecordGroups.airborneLead(name)
    return WatchGroups.airborneLead(name)
end

-- Where unit `name` is: { x, y, z }, or nil.
function RecordGroups.unitPoint(name)
    return WatchGroups.unitPoint(name)
end

-- Where the first unit of group `name` is: { x, y, z }, or nil.
function RecordGroups.firstUnitPoint(name)
    return WatchGroups.firstUnitPoint(name)
end

-- The type of every unit of group `name`.
function RecordGroups.unitTypes(name)
    return WatchGroups.unitTypes(name)
end

-- How many jets of group `name` are in the air now, and how many exist.
function RecordGroups.jetsUp(name)
    return WatchGroups.jetsUp(name)
end

-- Every unit of group `name` as { name, point }.
function RecordGroups.units(name)
    return WatchGroups.units(name)
end

-- Whether DCS knows group `name`.
function RecordGroups.exists(name)
    return WatchGroups.exists(name)
end

-- How many units group `name` has, 0 when it isn't there.
function RecordGroups.size(name)
    return WatchGroups.size(name)
end

-- Whether group `name` exists with a DCS controller.
function RecordGroups.hasController(name)
    return WatchGroups.hasController(name)
end

-- Whether any unit of group `name` is in the air.
function RecordGroups.inAir(name)
    return WatchGroups.inAir(name)
end
