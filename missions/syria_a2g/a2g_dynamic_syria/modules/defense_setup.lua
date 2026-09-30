-- Defines what ground defenses spawn at Red-controlled bases on mission start.
-- Calls Spawner (lib/spawner.lua) — load that first.
--
-- Each entry in RED_BASE_UNITS spawns N individual units at every Red base,
-- where N is randomized between minCount and maxCount each session.
-- Every unit gets its own independent position — no type-clumping.
--
-- Distance note: Airbase:getPoint() returns the runway threshold, not the
-- geographic center. Distances are set large enough (~1000-2000m) to push
-- units past the runway and out to the true perimeter on all sides.
--
-- snapRoad=true  → unit snaps to nearest road  (vehicles)
-- snapRoad=false → unit placed at raw random offset (infantry/MANPADS)

DefenseSetup = {}

local RED_BASE_UNITS = {
    -- Infantry: dismounted, scattered around the perimeter off-road
    { name="AK",   unitType="Soldier AK",        minCount=3, maxCount=8, skill="Average", minDist=800,  maxDist=1800, snapRoad=false },
    { name="RPG",  unitType="Soldier RPG",        minCount=1, maxCount=3, skill="Average", minDist=800,  maxDist=1800, snapRoad=false },
    { name="Igla", unitType="SA-18 Igla manpad",  minCount=1, maxCount=3, skill="Average", minDist=800,  maxDist=1800, snapRoad=false },

    -- Vehicles: road-snapped
    { name="BTR",  unitType="BTR-80",             minCount=1, maxCount=3, skill="Average", minDist=1000, maxDist=2000, snapRoad=true  },
    { name="Ural", unitType="Ural-4320-31",        minCount=2, maxCount=4, skill="Average", minDist=800,  maxDist=1800, snapRoad=true  },
    { name="ZU23", unitType="Ural-375 ZU-23",     minCount=1, maxCount=3, skill="Average", minDist=800,  maxDist=1800, snapRoad=true  },
}

-- Called after CoalitionSetup.assign(). assignments is a list of {name, side}.
function DefenseSetup.spawn(assignments)
    local count = 0
    for _, a in ipairs(assignments) do
        if a.side == coalition.side.RED then
            local ab = Airbase.getByName(a.name)
            if ab then
                local center = ab:getPoint()
                for _, def in ipairs(RED_BASE_UNITS) do
                    local n = math.random(def.minCount, def.maxCount)
                    for i = 1, n do
                        local pos = Spawner.nearPos(center, def.minDist, def.maxDist, def.snapRoad)
                        Spawner.spawnGroundGroup(
                            country.id.CJTF_RED,
                            pos,
                            { { type = def.unitType, skill = def.skill } },
                            { name = "DEF_" .. a.name .. "_" .. def.name .. "_" .. i }
                        )
                    end
                end
                count = count + 1
            end
        end
    end
    Log.info("DefenseSetup: spawned defenses at " .. count .. " Red bases")
end
