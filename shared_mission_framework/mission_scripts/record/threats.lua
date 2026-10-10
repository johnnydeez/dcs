-- The record of threats out of the fight: a SAM site whose radars are destroyed to its
-- success fraction, a base-defense group with no live unit. One writer: watch\threats.lua,
-- worked out when read (rule 11).

RecordThreats = {}

-- Whether threat `id` (a SAM site or a base-defense group) is out of the fight.
function RecordThreats.outOfTheFight(id)
    return WatchThreats.outOfTheFight(id)
end

-- Whether `names` are destroyed to `success`'s fraction; and how many are, of how many.
function RecordThreats.destroyedTo(names, success)
    return WatchThreats.destroyedTo(names, success)
end
