-- The record of the sleeping base defenses: per base, its groups, awake or asleep, and
-- what happened while awake (wakes, minutes, close passes, shots, hits, kills, late wakes).
-- One writer: the controller (controller\wake_ground_units.lua).
--
-- Events (published as subject "ground_units_awake"), each a decision as it is made:
--   awake      { base, groups, units, who, km }       woken for an enemy aircraft that close
--   asleep     { base, groups, units, minutes, wake }  asleep again; wake = this wake's counts
--   late_wake  { base, who, km }                       an enemy within reach while it slept
-- `base` is the base's entry ({ side, subject, … }); groups and units are those still alive.

RecordGroundUnitsAwake = {}

local SUBJECT = "ground_units_awake"

local _bases, _baseOfGroup = {}, {}
local _started = false

-- The controller's tables, kept up to date in place, never replaced: the bases (sorted by
-- name) and group name → its base.
function RecordGroundUnitsAwake.writeBases(bases, baseOfGroup)
    _bases, _baseOfGroup, _started = bases, baseOfGroup, true
end

function RecordGroundUnitsAwake.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s %s", e.base.subject, e.event) end)
end

function RecordGroundUnitsAwake.on(eventName, fn)
    Record.subscribe(SUBJECT, function(e)
        if e.event == eventName then fn(e) end
    end)
end

-- Whether sleeping was started (CONFIG.SLEEP_GROUND_UNITS).
function RecordGroundUnitsAwake.started()
    return _started
end

-- The bases with sleeping groups. Read them, never change them.
function RecordGroundUnitsAwake.bases()
    return _bases
end

-- Whether the group `groupName` is a sleeping group that is asleep now.
function RecordGroundUnitsAwake.isAsleep(groupName)
    local b = _baseOfGroup[groupName or ""]
    return b ~= nil and not b.awake
end
