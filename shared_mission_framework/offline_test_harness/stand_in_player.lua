-- Offline test harness, test B level 2: one stand-in player, so the mission's player code
-- runs (the air picture and threat calls, Darkstar's picture on the radio, airfield traffic
-- calls, PLAYER_IN) (shared_mission_framework plan.md, *How the transfer is tested*).
-- Loaded after simple_flight_model.lua; StandInPlayer.install(side name).
--
-- At SPAWN_AT_S, an F-16C appears in the air in the slot group of the coalition's player-
-- slot base nearest an enemy airbase (PLAYER_SLOTS; the busiest front, so threats and AI
-- traffic come near), with a player named PLAYER_NAME, and circles that base RADIUS_M out
-- at ALTITUDE_M and SPEED_MPS for the rest of the run. It never fires, lands or leaves.
-- The base is picked when it spawns, from the airbases' coalitions then (the roll applied).

StandInPlayer = {}

local SPAWN_AT_S = 60
local PLAYER_NAME = "Harness Pilot"
local RADIUS_M = 30000
local ALTITUDE_M = 6000
local SPEED_MPS = 200
local STEP_S = 2

local W = StubDcsWorld

local function pickBase(side)
    local enemy = side == coalition.side.BLUE and coalition.side.RED or coalition.side.BLUE
    local enemyBases = coalition.getAirbases(enemy)
    local names = {}
    for name in pairs(PLAYER_SLOTS or {}) do names[#names + 1] = name end
    table.sort(names)
    local best, bestD
    for _, name in ipairs(names) do
        local ab = Airbase.getByName(name)
        if ab and ab:getCoalition() == side then
            local p = ab:getPoint()
            for _, e in ipairs(enemyBases) do
                local q = e:getPoint()
                local d = math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2)
                if not bestD or d < bestD then best, bestD = name, d end
            end
        end
    end
    return best
end

function StandInPlayer.install(sideName)
    local side = sideName == "red" and coalition.side.RED or coalition.side.BLUE
    timer.scheduleFunction(function()
        local baseName = pickBase(side)
        if not baseName then
            env.info("OFFLINE HARNESS: no player-slot base held by the player's coalition: no stand-in player")
            return nil
        end
        local slot = PLAYER_SLOTS[baseName][1]
        local centre = Airbase.getByName(baseName):getPoint()
        local angle = 0
        local function at(a) return centre.x + RADIUS_M * math.cos(a), centre.z + RADIUS_M * math.sin(a) end
        local x, z = at(angle)
        local g = coalition.addGroup(side == coalition.side.RED and country.id.CJTF_RED or country.id.CJTF_BLUE,
            Group.Category.AIRPLANE, {
                name = slot.group,
                units = { { name = slot.group .. "-1-1", type = slot.type, x = x, y = z, alt = ALTITUDE_M,
                            speed = SPEED_MPS, heading = math.pi / 2, player_name = PLAYER_NAME, payload = {} } },
                route = { points = {} },
            })
        env.info(string.format("OFFLINE HARNESS: stand-in player %s in %s, circling %s", PLAYER_NAME, slot.group, baseName))
        W.fireEvent({ id = world.event.S_EVENT_PLAYER_ENTER_UNIT, initiator = g.unit_list[1] })
        -- around the base, counter-clockwise, every STEP_S
        local turn = SPEED_MPS * STEP_S / RADIUS_M
        timer.scheduleFunction(function(_, now)
            local u = g.unit_list[1]
            if not (u and u.alive) then return nil end
            angle = angle + turn
            u.pos.x, u.pos.z = at(angle)
            u.pos.y, u.speed, u.heading = ALTITUDE_M, SPEED_MPS, angle + math.pi / 2
            return now + STEP_S
        end, nil, SPAWN_AT_S + STEP_S)
        return nil
    end, nil, SPAWN_AT_S)
end
