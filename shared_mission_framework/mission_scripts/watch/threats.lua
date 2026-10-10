-- Watch: whether a threat is out of the fight now: a SAM site (a catalog target) whose
-- critical objects (its radars) are destroyed to its success fraction; a group (a
-- base-defense radar missile launcher) with no live unit. Worked out when asked, from the
-- plan's catalog, the flights record's gone names and the live units. Read through
-- record\threats.lua (the launch gate, the kill zones of the controller and scrambles).

WatchThreats = {}

local _catalog = {}   -- catalog target id → target

-- Whether `names` are destroyed to `success`'s fraction (rounded up, at least one); and
-- how many are, of how many.
function WatchThreats.destroyedTo(names, success)
    local dead = 0
    for _, name in ipairs(names) do
        if RecordFlights.isGone(name) or not WatchGroups.liveUnit(name) then dead = dead + 1 end
    end
    local frac = success and success.critical_fraction or 1
    return dead >= math.max(1, math.ceil(frac * #names - 1e-9)), dead, #names
end

function WatchThreats.outOfTheFight(id)
    local t = _catalog[id]
    if t and t.critical_names and #t.critical_names > 0 then
        return (WatchThreats.destroyedTo(t.critical_names, t.success))
    end
    return WatchGroups.live(id) == nil
end

function WatchThreats.start(plan)
    _catalog = plan.target_catalog and plan.target_catalog.targets or {}
end
