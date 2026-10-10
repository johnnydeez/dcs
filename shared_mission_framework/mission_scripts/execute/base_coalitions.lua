-- Execute: applies plan.territory to the sim: every planned base's coalition (autoCapture
-- off so it sticks). Its map circles are inform\map\territory.lua's.
-- Reads the plan; writes nothing back to it.

ExecuteBaseCoalitions = {}

local SIDE_ID = { blue = coalition.side.BLUE, red = coalition.side.RED, neutral = coalition.side.NEUTRAL }

local function setBaseCoalition(name, side)
    local ab = Airbase.getByName(name)
    if not ab then
        Log.warn("Territory: airbase '" .. name .. "' not found")
        return false
    end
    ab:autoCapture(false)
    ab:setCoalition(SIDE_ID[side])
    return true
end

-- Sets every planned base's coalition. Returns the set of bases it set (name → true).
function ExecuteBaseCoalitions.apply(plan)
    Log.info("--- Territory: apply ---")
    local set, ok, fail = {}, 0, 0
    for name, b in pairs(plan.territory.bases) do
        if setBaseCoalition(name, b.side) then
            ok = ok + 1
            set[name] = true
        else
            fail = fail + 1
        end
    end
    Log.info(string.format("  bases: %d set, %d not found", ok, fail))
    return set
end
