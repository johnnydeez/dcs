-- Blue AI air support: spawns CAS aircraft from a random Blue airbase every
-- SPAWN_INTERVAL seconds to suppress a random Red airfield within 200nm.
-- No RTB waypoint needed — DCS handles fuel/RTB automatically once
-- EngageTargetsInZone tasks are exhausted.  Each aircraft type gets a fixed
-- CAS loadout defined in LOADOUTS; watch dcs.log for woCar errors on first run.
--
-- CLSIDs sourced from pydcs/dcs weapons_data.py and planes.py (github.com/pydcs/dcs).
-- Pylon num = aircraft station number; sequential table index is just Lua array order.

BlueAirSupport = {}

local SPAWN_INTERVAL = 1200     -- seconds between spawn attempts
local MAX_AIRCRAFT   = 12       -- total alive aircraft cap across all groups
local AC_MIN         = 2        -- aircraft per group, minimum
local AC_MAX         = 4        -- aircraft per group, maximum
local MAX_RANGE_M    = 200 * 1852  -- 200 nm in metres
local TRANSIT_ALT    = 6000     -- metres (~20,000 ft) cruise altitude
local ATTACK_ALT     = 4500     -- metres (~15,000 ft) attack altitude
local ORBIT_SPEED    = 150      -- m/s (~290 kts) orbit speed at attack point

-- CAS loadouts per aircraft type.
-- fuel = internal fuel kg; gun = gun ammo %; chaff/flare = countermeasure counts.
local LOADOUTS = {
    ["FA-18C_hornet"] = {
        fuel = 4900, chaff = 60, flare = 60, gun = 100,
        pylons = {
            { CLSID = "{5CE2FF2A-645A-4197-B48D-8720AC69394F}", num = 1 },  -- AIM-9X  left tip
            { CLSID = "LAU_117_AGM_65F",                        num = 2 },  -- AGM-65F left outer
            { CLSID = "{GBU-38}",                               num = 3 },  -- GBU-38  left inner
            { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}", num = 4 },  -- AIM-120C left chin
            { CLSID = "{A111396E-D3E8-4b9c-8AC9-2432489304D5}", num = 5 },  -- LITENING TGP
            { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}", num = 6 },  -- AIM-120C right chin
            { CLSID = "{GBU-38}",                               num = 7 },  -- GBU-38  right inner
            { CLSID = "LAU_117_AGM_65F",                        num = 8 },  -- AGM-65F right outer
            { CLSID = "{5CE2FF2A-645A-4197-B48D-8720AC69394F}", num = 9 },  -- AIM-9X  right tip
        },
    },
    ["F-16C_50"] = {
        fuel = 3162, chaff = 60, flare = 60, gun = 100,
        pylons = {
            { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}", num = 1  },  -- AIM-9M  left tip
            { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}", num = 2  },  -- AIM-120C left shoulder
            { CLSID = "{DAC53A2F-79CA-42FF-A77A-F5649B601308}", num = 3  },  -- LAU-88 3x AGM-65D left
            { CLSID = "{A111396E-D3E8-4b9c-8AC9-2432489304D5}", num = 11 },  -- LITENING TGP
            { CLSID = "{DAC53A2F-79CA-42FF-A77A-F5649B601308}", num = 7  },  -- LAU-88 3x AGM-65D right
            { CLSID = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}", num = 8  },  -- AIM-120C right shoulder
            { CLSID = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}", num = 9  },  -- AIM-9M  right tip
        },
    },
    ["A-10C_2"] = {
        fuel = 5000, chaff = 120, flare = 120, gun = 100,
        pylons = {
            { CLSID = "{DB434044-F5D0-4F1F-9BA9-B73027E18DD3}", num = 1  },  -- LAU-105 2x AIM-9M left tip
            { CLSID = "{A111396E-D3E8-4b9c-8AC9-2432489304D5}", num = 2  },  -- LITENING TGP (replaces CBU-87)
            { CLSID = "{DAC53A2F-79CA-42FF-A77A-F5649B601308}", num = 3  },  -- LAU-88 3x AGM-65D left
            { CLSID = "{DAC53A2F-79CA-42FF-A77A-F5649B601308}", num = 9  },  -- LAU-88 3x AGM-65D right
            { CLSID = "{CBU-87}",                               num = 10 },  -- CBU-87  right
            { CLSID = "{DB434044-F5D0-4F1F-9BA9-B73027E18DD3}", num = 11 },  -- LAU-105 2x AIM-9M right tip
        },
    },
}

local AIRCRAFT_POOL = {
    "A-10C_2",
    "F-16C_50",
    "FA-18C_hornet",
}

local _assignments  = nil  -- stored at init, read each loop tick
local _activeGroups = {}   -- group names of spawned flights, pruned when dead
local _groupCounter = 0    -- monotonic counter for unique group names

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function pick(tbl)
    return tbl[math.random(#tbl)]
end

local function dist2D(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- Walks _activeGroups, sums live unit counts, removes dead/gone groups.
local function countAlive()
    local count  = 0
    local living = {}
    for _, name in ipairs(_activeGroups) do
        local grp = Group.getByName(name)
        if grp and grp:getSize() > 0 then
            count = count + grp:getSize()
            table.insert(living, name)
        end
    end
    _activeGroups = living
    return count
end

-- Returns two tables {name, pos} for a random Blue/Red base pair within MAX_RANGE_M,
-- or nil, nil if no valid pair exists.
local function selectBases()
    local bluePool = {}
    local redPool  = {}
    for _, a in ipairs(_assignments) do
        local ab = Airbase.getByName(a.name)
        if ab then
            local entry = { name = a.name, pos = ab:getPoint() }
            if a.side == coalition.side.BLUE then
                table.insert(bluePool, entry)
            else
                table.insert(redPool, entry)
            end
        end
    end

    if #bluePool == 0 or #redPool == 0 then return nil, nil end

    local validPairs = {}
    for _, b in ipairs(bluePool) do
        for _, r in ipairs(redPool) do
            if dist2D(b.pos, r.pos) <= MAX_RANGE_M then
                table.insert(validPairs, { blue = b, red = r })
            end
        end
    end

    if #validPairs == 0 then
        Log.warn("BlueAirSupport: no Blue/Red pairs within 200nm")
        return nil, nil
    end

    local chosen = validPairs[math.random(#validPairs)]
    return chosen.blue, chosen.red
end

-- Spawns one CAS flight from blueBase toward redBase.
local function spawnGroup(blueBase, redBase, acType, acCount)
    _groupCounter = _groupCounter + 1
    local groupName = "BAS_" .. _groupCounter

    local sp  = blueBase.pos   -- spawn Vec3 {x=north, y=alt, z=east}
    local tp  = redBase.pos    -- target Vec3

    local ab  = Airbase.getByName(blueBase.name)
    local gnd = land.getHeight({ x = sp.x, y = sp.z })

    -- Compass heading from spawn base to target base (used as unit facing direction).
    local heading = math.atan2(tp.z - sp.z, tp.x - sp.x)

    local loadout = LOADOUTS[acType]
    local units = {}
    for i = 1, acCount do
        units[i] = {
            name    = groupName .. "_" .. i,
            type    = acType,
            skill   = "Good",
            x       = sp.x,
            y       = sp.z,   -- route-point convention: y = east
            alt     = gnd,
            heading = heading,
            speed   = 0,      -- cold start
            payload = {
                pylons = loadout.pylons,
                fuel   = loadout.fuel,
                chaff  = loadout.chaff,
                flare  = loadout.flare,
                gun    = loadout.gun,
            },
        }
    end

    -- Midpoint for transit climb waypoint.
    local midX = (sp.x + tp.x) / 2
    local midZ = (sp.z + tp.z) / 2

    local wp_takeoff = {
        x          = sp.x,
        y          = sp.z,
        alt        = gnd,
        alt_type   = "BARO",
        type       = "TakeOffParking",
        action     = "From Parking Area",
        speed      = 0,
        ETA        = 0,
        ETA_locked = false,
        airdromeId = ab:getID(),
        task       = { id = "ComboTask", params = { tasks = {} } },
    }

    local wp_transit = {
        x          = midX,
        y          = midZ,
        alt        = TRANSIT_ALT,
        alt_type   = "BARO",
        type       = "Turning Point",
        action     = "Turning Point",
        speed      = 250,
        ETA        = 0,
        ETA_locked = false,
        task       = { id = "ComboTask", params = { tasks = {} } },
    }

    -- Attack waypoint: Orbit in a circle over the Red airfield.
    -- EngageTargets runs as a continuous enroute task (route.tasks) so the
    -- aircraft attack targets they detect while orbiting, rather than firing
    -- once at waypoint arrival and moving on (the EngageTargetsInZone pitfall).
    local wp_attack = {
        x          = tp.x,
        y          = tp.z,
        alt        = ATTACK_ALT,
        alt_type   = "BARO",
        type       = "Turning Point",
        action     = "Turning Point",
        speed      = ORBIT_SPEED,
        ETA        = 0,
        ETA_locked = false,
        task = {
            id = "ComboTask",
            params = {
                tasks = {
                    [1] = {
                        number  = 1,
                        auto    = false,
                        id      = "Orbit",
                        enabled = true,
                        params  = {
                            altitude    = ATTACK_ALT,
                            pattern     = "Circle",
                            speed       = ORBIT_SPEED,
                            speedEdited = true,
                        },
                    },
                },
            },
        },
    }

    local grp = coalition.addGroup(country.id.CJTF_BLUE, Group.Category.AIRPLANE, {
        name  = groupName,
        task  = "CAS",
        route = {
            points = { [1] = wp_takeoff, [2] = wp_transit, [3] = wp_attack },
            tasks  = {
                [1] = {
                    number  = 1,
                    auto    = true,
                    id      = "EngageTargets",
                    enabled = true,
                    key     = "CAS",
                    params  = {
                        targetTypes = {
                            [1] = "Ground Units",
                            [2] = "Air Defence",
                            [3] = "Unarmed vehicles",
                        },
                        priority = 0,
                    },
                },
            },
        },
        units = units,
    })

    if grp then
        -- WEAPON_FREE: engage any detected enemy autonomously.
        -- Default ROE is OPEN_FIRE (designated targets only) which causes orbiting
        -- aircraft to never fire since no targets were individually designated.
        local ctrl = grp:getController()
        ctrl:setOption(AI.Option.Air.id.ROE,
                       AI.Option.Air.val.ROE.WEAPON_FREE)
        ctrl:setOption(AI.Option.Air.id.REACTION_ON_THREAT,
                       AI.Option.Air.val.REACTION_ON_THREAT.ALLOW_ABORT_MISSION)
        table.insert(_activeGroups, groupName)
        Log.info(string.format("BlueAirSupport: %s — %dx %s  %s → %s",
            groupName, acCount, acType, blueBase.name, redBase.name))
    else
        Log.warn("BlueAirSupport: coalition.addGroup returned nil for " .. groupName)
    end
end

-- ── Recurring loop ────────────────────────────────────────────────────────────

local function loop(_, t)
    local alive = countAlive()

    if alive >= MAX_AIRCRAFT then
        Log.debug(string.format("BlueAirSupport: cap reached (%d/%d), skipping", alive, MAX_AIRCRAFT))
        return t + SPAWN_INTERVAL
    end

    local blueBase, redBase = selectBases()
    if not blueBase then
        return t + SPAWN_INTERVAL
    end

    local acType  = pick(AIRCRAFT_POOL)
    local acCount = math.random(AC_MIN, AC_MAX)

    -- Clamp so we don't overshoot the cap.
    if alive + acCount > MAX_AIRCRAFT then
        acCount = MAX_AIRCRAFT - alive
    end

    spawnGroup(blueBase, redBase, acType, acCount)
    return t + SPAWN_INTERVAL
end

-- ── Land event handler — despawn groups after RTB ────────────────────────────

-- When any BAS unit lands, schedule a check 120s later.  If by then no unit in
-- the group is still airborne, the whole group is destroyed so parking slots and
-- the alive-count cap are freed up.
local _landHandler = {}
function _landHandler:onEvent(event)
    if event.id ~= world.event.S_EVENT_LAND then return end
    local unit = event.initiator
    if not unit then return end
    local unitName = unit:getName()
    local groupName = unitName:match("^(BAS_%d+)_")
    if not groupName then return end

    local checkTime = timer.getTime() + 120
    timer.scheduleFunction(function(_, _t)
        local grp = Group.getByName(groupName)
        if not grp then return end
        for _, u in pairs(grp:getUnits()) do
            if u:inAir() then return end   -- someone still flying, abort
        end
        grp:destroy()
        Log.info("BlueAirSupport: despawned " .. groupName .. " (RTB complete)")
    end, nil, checkTime)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function BlueAirSupport.init(assignments)
    _assignments = assignments
    world.addEventHandler(_landHandler)
    -- First spawn delayed 10s to let all other init complete; subsequent every 20 min.
    timer.scheduleFunction(loop, nil, timer.getTime() + 10)
    Log.info("BlueAirSupport: initialized — interval " .. SPAWN_INTERVAL .. "s, cap " .. MAX_AIRCRAFT)
end
