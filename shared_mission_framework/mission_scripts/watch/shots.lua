-- Watch: missiles fired at and by the flights the controller watches
-- (record\watched_flights.lua), written to record\shots.lua:
--   a watched flight's anti-radiation missile: published, so the go-cold check runs at once
--     and a SEAD flight turns the moment its last missile is away
--   a watched flight's air-to-air missile: kept, so its fight isn't timed out while one is
--     still flying (the self_defence directive)
--   a missile at a watched flight: who fired (an airplane's group), which weapon, when;
--     published, so its coalition's fast check runs at once

WatchShots = {}

local _shots = {}   -- flight id → { shot_at, own_missiles }
RecordShots.writeTable(_shots)

local function entry(id)
    local s = _shots[id]
    if not s then
        s = {}
        _shots[id] = s
    end
    return s
end

-- True for an anti-radiation missile (passive radar guidance).
local function isAntiRadiation(weapon)
    local d = weapon:getDesc()
    return d and d.category == Weapon.Category.MISSILE and d.guidance == Weapon.GuidanceType.RADAR_PASSIVE
end

-- True for an air-to-air missile.
local function isAirToAir(weapon)
    local d = weapon:getDesc()
    return d and d.category == Weapon.Category.MISSILE and d.missileCategory == Weapon.MissileCategory.AAM
end

local handler = {}
function handler:onEvent(e)
    if e.id ~= world.event.S_EVENT_SHOT or not e.weapon then return end
    pcall(function()
        local own = e.initiator and e.initiator.getGroup and e.initiator:getGroup()
        local ownName = own and own:getName()
        local mine = ownName and RecordWatchedFlights.isWatched(ownName)
        if mine and isAntiRadiation(e.weapon) then
            RecordShots.publish({ event = "anti_radiation_fired", flight = ownName })
        end
        if mine and isAirToAir(e.weapon) then
            local s = entry(ownName)
            s.own_missiles = s.own_missiles or {}
            table.insert(s.own_missiles, e.weapon)
        end
        local target = e.weapon:getTarget()
        local group = target and target.getGroup and target:getGroup()
        local targetName = group and group:getName()
        if not (targetName and RecordWatchedFlights.isWatched(targetName)) then return end
        local shooter = e.initiator
        local sg = shooter and shooter.getGroup and shooter:getGroup()
        local isAirplane = shooter and shooter.getDesc and shooter:getDesc().category == Unit.Category.AIRPLANE
        entry(targetName).shot_at = { time = timer.getTime(), shooter_group = isAirplane and sg and sg:getName() or nil,
                                      weapon = e.weapon:getTypeName() }
        RecordShots.publish({ event = "shot_at", flight = targetName })
    end)
end

-- How many of flight `id`'s own air-to-air missiles are still flying; spent ones are
-- dropped from the record here.
function WatchShots.ownMissilesInFlight(id)
    local s = _shots[id]
    local list = s and s.own_missiles
    if not list then return 0 end
    local flying = {}
    for _, weapon in ipairs(list) do
        local ok, exists = pcall(function() return weapon:isExist() end)
        if ok and exists then flying[#flying + 1] = weapon end
    end
    s.own_missiles = flying
    return #flying
end

function WatchShots.start()
    RecordDcsEvents.on(function(fact) if fact.raw then handler:onEvent(fact.raw) end end)
end
