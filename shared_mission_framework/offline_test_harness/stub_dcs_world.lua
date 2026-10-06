-- Offline test harness: stand-ins for the objects of a running DCS mission (groups, units,
-- static objects, airbases, their controllers, events, the comms menu, map drawings, user
-- flags), so a mission's consumers run under luae.exe. Loaded after stub_dcs.lua.
--
-- Level 1, everything stands still (shared_mission_framework plan.md, *How the transfer
-- is tested*, test B): a spawned group stays where it spawned, a jet on the ramp never takes
-- off, an air start stays in the air where it started, no radar sees anything, and no
-- player is in the mission. Orders to a controller are recorded and change nothing.
--
-- Every object is a plain table with the methods the mission calls; nothing is random, so
-- the same run gives the same result.
--
-- StubDcsWorld.install(world) after StubDcs.install: `world` is the saved plan.world (its
-- airbases, parking spots).

StubDcsWorld = {
    groups = {},          -- by name, live ones only
    units = {},           -- by name, live ones only
    statics = {},         -- by name, live ones only
    handlers = {},        -- world.addEventHandler, in order added
    menu_items = {},      -- { side, path (text), kind = "menu" / "command", fn, arg }
    drawings = {},        -- { [trigger.action function name] = count }
    flags = {},
    order_counts = {},    -- { ["setTask AttackGroup"] = n, ... } every order given to a controller
    country_counts = {},  -- { ["ground, country 0"] = n, ... } groups and static objects spawned, by country
}

local W = StubDcsWorld
local nextId = 1

-- What a group's sensors detect (Controller:getDetectedTargets): nothing at level 1;
-- simple_sensors.lua replaces it at level 2.
function W.detect() return {} end
local function newId() nextId = nextId + 1 return nextId end

local function vec3(x, y, z) return { x = x, y = y, z = z } end

-- ── DCS enums (values as DCS has them; only that they're distinct matters here) ──

local function installEnums()
    world = world or {}
    world.event = {
        S_EVENT_INVALID = 0, S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4,
        S_EVENT_CRASH = 5, S_EVENT_EJECTION = 6, S_EVENT_REFUELING = 7, S_EVENT_DEAD = 8,
        S_EVENT_PILOT_DEAD = 9, S_EVENT_BASE_CAPTURED = 10, S_EVENT_MISSION_START = 11,
        S_EVENT_MISSION_END = 12, S_EVENT_TOOK_CONTROL = 13, S_EVENT_REFUELING_STOP = 14,
        S_EVENT_BIRTH = 15, S_EVENT_HUMAN_FAILURE = 16, S_EVENT_DETAILED_FAILURE = 17,
        S_EVENT_ENGINE_STARTUP = 18, S_EVENT_ENGINE_SHUTDOWN = 19, S_EVENT_PLAYER_ENTER_UNIT = 20,
        S_EVENT_PLAYER_LEAVE_UNIT = 21, S_EVENT_PLAYER_COMMENT = 22, S_EVENT_SHOOTING_START = 23,
        S_EVENT_SHOOTING_END = 24, S_EVENT_MARK_ADDED = 25, S_EVENT_MARK_CHANGE = 26,
        S_EVENT_MARK_REMOVED = 27, S_EVENT_KILL = 28, S_EVENT_SCORE = 29, S_EVENT_UNIT_LOST = 30,
        S_EVENT_LANDING_AFTER_EJECTION = 31, S_EVENT_PARATROOPER_LENDING = 32,
        S_EVENT_DISCARD_CHAIR_AFTER_EJECTION = 33, S_EVENT_WEAPON_ADD = 34,
        S_EVENT_TRIGGER_ZONE = 35, S_EVENT_LANDING_QUALITY_MARK = 36, S_EVENT_BDA = 37,
        S_EVENT_AI_ABORT_MISSION = 38, S_EVENT_DAYNIGHT = 39, S_EVENT_FLIGHT_TIME = 40,
        S_EVENT_PLAYER_SELF_KILL_PILOT = 41, S_EVENT_PLAYER_CAPTURE_AIRFIELD = 42,
        S_EVENT_EMERGENCY_LANDING = 43, S_EVENT_UNIT_CREATE_TASK = 44, S_EVENT_UNIT_DELETE_TASK = 45,
        S_EVENT_SIMULATION_START = 46, S_EVENT_WEAPON_REARM = 47, S_EVENT_WEAPON_DROP = 48,
        S_EVENT_UNIT_TASK_COMPLETE = 49, S_EVENT_UNIT_TASK_STAGE = 50, S_EVENT_MAX = 51,
    }
    world.VolumeType = { SEGMENT = 0, BOX = 1, SPHERE = 2, PYRAMID = 3 }

    Object = { Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, CARGO = 6 } }
    Unit = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4 },
             SensorType = { OPTIC = 0, RADAR = 1, IRST = 2, RWR = 3 } }
    Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 } }
    Airbase = { Category = { AIRDROME = 0, HELIPAD = 1, SHIP = 2 } }
    StaticObject = {}
    Weapon = {
        Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3, TORPEDO = 4 },
        GuidanceType = { INS = 1, IR = 2, RADAR_ACTIVE = 3, RADAR_SEMI_ACTIVE = 4, RADAR_PASSIVE = 5,
                         TV = 6, LASER = 7, TELE = 8 },
        MissileCategory = { AAM = 1, SAM = 2, BM = 3, ANTI_SHIP = 4, CRUISE = 5, OTHER = 6 },
    }
    Controller = { Detection = { VISUAL = 1, OPTIC = 2, RADAR = 4, IRST = 8, RWR = 16, DLINK = 32 } }
    local ROE = { WEAPON_FREE = 0, OPEN_FIRE_WEAPON_FREE = 1, OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 }
    AI = { Option = {
        Air = {
            id = { NO_OPTION = -1, ROE = 0, REACTION_ON_THREAT = 1, RADAR_USING = 3, FLARE_USING = 4,
                   FORMATION = 5, RTB_ON_BINGO = 6, SILENCE = 7, RTB_ON_OUT_OF_AMMO = 10, ECM_USING = 13,
                   PROHIBIT_AA = 14, PROHIBIT_JETT = 15, PROHIBIT_AB = 16, PROHIBIT_AG = 17,
                   MISSILE_ATTACK = 18, PROHIBIT_WP_PASS_REPORT = 19 },
            val = { ROE = ROE,
                    REACTION_ON_THREAT = { NO_REACTION = 0, PASSIVE_DEFENCE = 1, EVADE_FIRE = 2,
                                           BYPASS_AND_ESCAPE = 3, ALLOW_ABORT_MISSION = 4 } },
        },
        Ground = {
            id = { NO_OPTION = -1, ROE = 0, DISPERSE_ON_ATTACK = 8, ALARM_STATE = 9,
                   ENGAGE_AIR_WEAPONS = 20, AC_ENGAGEMENT_RANGE_RESTRICTION = 24 },
            val = { ROE = ROE, ALARM_STATE = { AUTO = 0, GREEN = 1, RED = 2 } },
        },
    } }
    country = { id = { RUSSIA = 0, UKRAINE = 1, USA = 2, CJTF_BLUE = 80, CJTF_RED = 81 } }
end

local RED_COUNTRIES = { [0] = true, [81] = true }
local function coalitionOfCountry(countryId)
    return RED_COUNTRIES[countryId] and coalition.side.RED or coalition.side.BLUE
end

-- ── Ammo: what a jet carries, from the loadout data's weapon names ──

local clsidWeapon   -- CLSID → the weapon's name in the loadout data

local function findWeaponNames(t, seen)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    if type(t.CLSID) == "string" and type(t.weapon) == "string" then clsidWeapon[t.CLSID] = t.weapon end
    for _, v in pairs(t) do findWeaponNames(v, seen) end
end

-- A weapon name ("LAU-115: 2 x LAU-127 - 2 x AIM-120C AMRAAM - Active Radar AAM") → its
-- DCS desc and count, or nil for tanks and pods.
local function describeWeapon(name)
    local lower = name:lower()
    if lower:find("fuel tank", 1, true) or lower:find("pod", 1, true) then return nil end
    local count = tonumber(name:match("(%d+) x [^x]*$")) or tonumber(name:match("%* (%d+)$")) or 1
    local C, G, M = Weapon.Category, Weapon.GuidanceType, Weapon.MissileCategory
    local d = { typeName = name:match("([^%-:]+) %- [^%-]*$") or name, displayName = name }
    if name:find("ARM", 1, true) or lower:find("anti-radiation", 1, true) then
        d.category, d.guidance, d.missileCategory = C.MISSILE, G.RADAR_PASSIVE, M.OTHER
    elseif name:find("AAM", 1, true) or name:find("Rdr", 1, true) or name:find("Infra Red", 1, true)
            or name:find("Semi%-Act") or name:find("IR Extended", 1, true) then
        d.category, d.missileCategory = C.MISSILE, M.AAM
        if name:find("Active", 1, true) then d.guidance, d.rangeMaxAltMax = G.RADAR_ACTIVE, 60000
        elseif name:find("Semi%-Act") then d.guidance, d.rangeMaxAltMax = G.RADAR_SEMI_ACTIVE, 50000
        else d.guidance, d.rangeMaxAltMax = G.IR, 15000 end
    elseif lower:find("bomb", 1, true) or lower:find("cbu", 1, true) or lower:find("jsow", 1, true)
            or name:find("FAB") or name:find("KAB") or name:find("RBK") or name:find("GBU") then
        d.category = C.BOMB
    else
        d.category, d.guidance, d.missileCategory = C.MISSILE, G.INS, M.OTHER
    end
    d.typeName = d.typeName:gsub("^%s+", ""):gsub("%s+$", "")
    return d, count
end

local function ammoFor(payload)
    if not clsidWeapon then
        clsidWeapon = {}
        findWeaponNames(AIRCRAFT_LOADOUT, {})
        findWeaponNames(AIRCRAFT_LOADOUT_OPTIONS, {})
    end
    local byName, list = {}, {}
    local pylonNumbers = {}
    for num in pairs(payload and payload.pylons or {}) do pylonNumbers[#pylonNumbers + 1] = num end
    table.sort(pylonNumbers)
    for _, num in ipairs(pylonNumbers) do
        local name = clsidWeapon[payload.pylons[num].CLSID]
        local d, count = nil, 0
        if name then d, count = describeWeapon(name) end
        if d then
            local entry = byName[d.displayName]
            if entry then entry.count = entry.count + count
            else
                entry = { count = count, desc = d }
                byName[d.displayName] = entry
                list[#list + 1] = entry
            end
        end
    end
    if payload and (payload.gun or 0) > 0 then
        list[#list + 1] = { count = 500, desc = { typeName = "gun shell", displayName = "gun shell", category = Weapon.Category.SHELL } }
    end
    return list
end

-- ── Units with a radar (UNIT_POOL's detection range) ─────────────

local function hasRadar(typeName)
    for _, kind in ipairs({ "ground", "ship", "plane", "helicopter" }) do
        local e = UNIT_POOL and UNIT_POOL[kind] and UNIT_POOL[kind][typeName]
        if e then return (e.detection_m or 0) > 0 end
    end
    return false
end

-- ── Controllers ─────────────────────────────────────────────────

local function countOrder(kind, task)
    local key = kind .. (type(task) == "table" and task.id and (" " .. task.id) or "")
    W.order_counts[key] = (W.order_counts[key] or 0) + 1
end

-- Orders a flight acts on (simple_flight_model.lua sets these at level 2; at level 1 orders
-- are only counted): W.onSetTask(group, task), W.onPushTask(group, task).
local function newController(owner)
    local c = { owner = owner, tasks = {}, on = true }
    function c:setTask(task)
        countOrder("setTask", task)
        self.tasks = { task }
        if W.onSetTask then W.onSetTask(self.owner, task) end
    end
    function c:pushTask(task)
        countOrder("pushTask", task)
        table.insert(self.tasks, task)
        if W.onPushTask then W.onPushTask(self.owner, task) end
    end
    function c:popTask() countOrder("popTask") table.remove(self.tasks) end
    function c:resetTask() countOrder("resetTask") self.tasks = {} end
    function c:hasTask() return #self.tasks > 0 end
    function c:setOption(id, value) countOrder("setOption " .. tostring(id)) end
    function c:setCommand(command) countOrder("setCommand", command) end
    function c:setOnOff(on) countOrder("setOnOff " .. tostring(on)) self.on = on end
    function c:getDetectedTargets(...) return W.detect(self.owner, ...) end
    function c:knowTarget() end
    function c:isTargetDetected() return false end
    return c
end

-- ── Units and groups ────────────────────────────────────────────

local function newUnit(group, data, index, category, inAir)
    local u = {
        name = data.name, type = data.type, group = group, id = newId(), index = index,
        pos = vec3(data.x, inAir and (data.alt or 0) or land.getHeight({ x = data.x, y = data.y }), data.y),
        heading = data.heading or 0, speed = inAir and (data.speed or 0) or 0, in_air = inAir,
        category = category, alive = true, life0 = 10, life = 10, fuel = 1,
        ammo = category == Unit.Category.AIRPLANE and ammoFor(data.payload) or {},
        has_radar = hasRadar(data.type), parking = data.parking,
        player_name = data.player_name,   -- the harness's own field: a stand-in player (stand_in_player.lua)
    }
    function u:getName() return self.name end
    function u:getID() return self.id end
    function u:isExist() return self.alive end
    function u:isActive() return self.alive end
    function u:getPoint() return vec3(self.pos.x, self.pos.y, self.pos.z) end
    function u:getPosition()
        local cx, cz = math.cos(self.heading), math.sin(self.heading)
        return { p = self:getPoint(), x = vec3(cx, 0, cz), y = vec3(0, 1, 0), z = vec3(-cz, 0, cx) }
    end
    function u:getVelocity()
        return vec3(math.cos(self.heading) * self.speed, 0, math.sin(self.heading) * self.speed)
    end
    function u:inAir() return self.in_air end
    function u:getTypeName() return self.type end
    function u:getGroup() return self.group end
    function u:getCoalition() return self.group.coalition end
    function u:getCountry() return self.group.country end
    function u:getCategory() return Object.Category.UNIT end
    function u:getDesc()
        return { category = self.category, typeName = self.type, displayName = self.type, life = self.life0 }
    end
    function u:getLife() return self.alive and self.life or 0 end
    function u:getLife0() return self.life0 end
    function u:getFuel() return self.fuel end
    function u:getAmmo() return self.ammo end
    function u:getPlayerName() return self.player_name end
    function u:getCallsign() return self.name end
    function u:getNumber() return self.index end
    function u:getController() return self.group:getController() end
    function u:hasSensors(sensorType) return sensorType == Unit.SensorType.RADAR and self.has_radar end
    function u:getRadar() return self.has_radar, nil end
    function u:getSensors() return {} end
    function u:destroy() W.removeUnit(self) end
    return u
end

function W.removeUnit(u)
    if not u.alive then return end
    u.alive = false
    W.units[u.name] = nil
    local g = u.group
    for i, other in ipairs(g.unit_list) do
        if other == u then table.remove(g.unit_list, i) break end
    end
    if #g.unit_list == 0 then g.alive = false W.groups[g.name] = nil end
end

local function newGroup(countryId, category, data)
    local g = {
        name = data.name, id = data.groupId or newId(), category = category, country = countryId,
        coalition = coalitionOfCountry(countryId), alive = true, unit_list = {}, data = data,
    }
    g.controller = newController(g)
    function g:getName() return self.name end
    function g:getID() return self.id end
    function g:isExist() return self.alive end
    function g:getUnits()
        local out = {}
        for i, u in ipairs(self.unit_list) do out[i] = u end
        return out
    end
    function g:getUnit(i) return self.unit_list[i] end
    function g:getSize() return #self.unit_list end
    function g:getInitialSize() return #self.data.units end
    function g:getController() return self.controller end
    function g:getCoalition() return self.coalition end
    function g:getCategory() return self.category end
    function g:activate() end
    function g:destroy()
        for _, u in ipairs(self:getUnits()) do W.removeUnit(u) end
        self.alive = false
        W.groups[self.name] = nil
    end
    return g
end

-- An aircraft group starts in the air unless its first waypoint is a takeoff.
local function startsInAir(category, data)
    if category ~= Group.Category.AIRPLANE and category ~= Group.Category.HELICOPTER then return false end
    local first = data.route and data.route.points and data.route.points[1]
    return not (first and type(first.type) == "string" and first.type:find("^TakeOff"))
end

function W.fireEvent(e)
    e.time = e.time or StubDcs.now
    for _, h in ipairs(W.handlers) do
        local ok, err = pcall(h.onEvent, h, e)
        if not ok then env.error("event handler failed: " .. tostring(err)) end
    end
end

-- ── Airbases ────────────────────────────────────────────────────

local airbases, airbaseList = {}, {}

local function newAirbase(entry, index)
    local SIDE = { red = coalition.side.RED, blue = coalition.side.BLUE, neutral = coalition.side.NEUTRAL }
    local ab = { name = entry.name, id = index, entry = entry, side = SIDE[entry.me_side] or 0 }
    function ab:getName() return self.name end
    function ab:getID() return self.id end
    function ab:isExist() return true end
    function ab:getPoint() return vec3(self.entry.pos.x, land.getHeight({}), self.entry.pos.z) end
    function ab:getDesc() return { category = Airbase.Category.AIRDROME, displayName = self.name } end
    function ab:getCategory() return Object.Category.BASE end
    function ab:getCoalition() return self.side end
    function ab:setCoalition(side) self.side = side end
    function ab:autoCapture() end
    function ab:getCallsign() return self.name end
    function ab:getRunways() return {} end
    -- every spot of the field; only those with no aircraft on the ground or static object
    -- within 15 m when `available`
    function ab:getParking(available)
        local out = {}
        for _, s in ipairs(self.entry.parking or {}) do
            local x, z = s[1], s[2]
            local taken = false
            if available then
                for _, u in pairs(W.units) do
                    if not u.in_air and (u.category == Unit.Category.AIRPLANE or u.category == Unit.Category.HELICOPTER)
                       and (u.pos.x - x) ^ 2 + (u.pos.z - z) ^ 2 < 225 then taken = true break end
                end
                if not taken then
                    for _, o in pairs(W.statics) do
                        if (o.pos.x - x) ^ 2 + (o.pos.z - z) ^ 2 < 225 then taken = true break end
                    end
                end
            end
            if not taken then
                out[#out + 1] = { vTerminalPos = vec3(x, land.getHeight({}), z), Term_Type = s[3], Term_Index = s[4],
                                  fDistToRW = 0 }
            end
        end
        return out
    end
    return ab
end

-- ── Install ─────────────────────────────────────────────────────

function W.install(savedWorld)
    installEnums()

    for i, name in ipairs(savedWorld.airbase_list) do
        local ab = newAirbase(savedWorld.airbases[name], i)
        airbases[name] = ab
        airbaseList[#airbaseList + 1] = ab
    end
    function Airbase.getByName(name) return airbases[name] end
    world.getAirbases = function() return airbaseList end
    world.addEventHandler = function(h) W.handlers[#W.handlers + 1] = h end
    world.removeEventHandler = function(h)
        for i, other in ipairs(W.handlers) do if other == h then table.remove(W.handlers, i) return end end
    end
    world.searchObjects = function() return 0 end
    world.getPlayer = function() return nil end

    function Group.getByName(name) return W.groups[name] end
    function Unit.getByName(name) return W.units[name] end
    function StaticObject.getByName(name) return W.statics[name] end

    coalition.addGroup = function(countryId, category, data)
        local old = W.groups[data.name]
        if old then old:destroy() end
        local g = newGroup(countryId, category, data)
        local CATEGORY_NAME = { [0] = "airplane", [1] = "helicopter", [2] = "ground", [3] = "ship", [4] = "train" }
        local key = string.format("%s groups, country %s", CATEGORY_NAME[category] or tostring(category), tostring(countryId))
        W.country_counts[key] = (W.country_counts[key] or 0) + 1
        local inAir = startsInAir(category, data)
        local unitCategory = (category == Group.Category.AIRPLANE and Unit.Category.AIRPLANE)
            or (category == Group.Category.HELICOPTER and Unit.Category.HELICOPTER)
            or (category == Group.Category.SHIP and Unit.Category.SHIP) or Unit.Category.GROUND_UNIT
        for i, ud in ipairs(data.units or {}) do
            local u = newUnit(g, ud, i, unitCategory, inAir)
            g.unit_list[#g.unit_list + 1] = u
            W.units[u.name] = u
        end
        W.groups[g.name] = g
        for _, u in ipairs(g.unit_list) do W.fireEvent({ id = world.event.S_EVENT_BIRTH, initiator = u }) end
        return g
    end
    coalition.addStaticObject = function(countryId, data)
        local key = "static objects, country " .. tostring(countryId)
        W.country_counts[key] = (W.country_counts[key] or 0) + 1
        local o = { name = data.name, type = data.type, country = countryId, coalition = coalitionOfCountry(countryId),
                    pos = vec3(data.x, land.getHeight({}), data.y), heading = data.heading or 0, alive = true, id = newId() }
        function o:getName() return self.name end
        function o:getID() return self.id end
        function o:getTypeName() return self.type end
        function o:isExist() return self.alive end
        function o:getPoint() return vec3(self.pos.x, self.pos.y, self.pos.z) end
        function o:getCategory() return Object.Category.STATIC end
        function o:getDesc() return { category = Unit.Category.STRUCTURE, typeName = self.type, displayName = self.type, life = 10 } end
        function o:getLife() return self.alive and 10 or 0 end
        function o:getCoalition() return self.coalition end
        function o:destroy() self.alive = false W.statics[self.name] = nil end
        W.statics[o.name] = o
        return o
    end
    coalition.getGroups = function(side, category)
        local names = {}
        for name, g in pairs(W.groups) do
            if g.coalition == side and (category == nil or g.category == category) then names[#names + 1] = name end
        end
        table.sort(names)
        local out = {}
        for i, name in ipairs(names) do out[i] = W.groups[name] end
        return out
    end
    -- units with a player in them (none at level 1), in name order
    coalition.getPlayers = function(side)
        local names = {}
        for name, u in pairs(W.units) do
            if u.player_name and u.group.coalition == side then names[#names + 1] = name end
        end
        table.sort(names)
        local out = {}
        for i, name in ipairs(names) do out[i] = W.units[name] end
        return out
    end
    coalition.getAirbases = function(side)
        local out = {}
        for _, ab in ipairs(airbaseList) do if ab.side == side then out[#out + 1] = ab end end
        return out
    end

    -- trigger.action: map drawings, texts, flags; every call counted by function name
    local action = {}
    setmetatable(action, { __index = function(_, fname)
        return function(...)
            W.drawings[fname] = (W.drawings[fname] or 0) + 1
            if fname:find("^outText") then
                local args = { ... }
                local text = fname == "outText" and args[1] or args[2]
                StubDcs.screen_texts[#StubDcs.screen_texts + 1] = tostring(text)
            end
        end
    end })
    action.setUserFlag = function(flag, value)
        W.flags[tostring(flag)] = value == true and 1 or (value == false and 0 or tonumber(value) or 0)
    end
    trigger = { action = action, misc = {
        getUserFlag = function(flag) return W.flags[tostring(flag)] or 0 end,
        getZone = function() return nil end,
    } }

    -- the comms menu: every item kept, so the harness can open them
    local function addItem(kind, side, name, parent, fn, arg)
        local path = {}
        for i, p in ipairs(parent or {}) do path[i] = p end
        path[#path + 1] = name
        W.menu_items[#W.menu_items + 1] = { kind = kind, side = side, path = table.concat(path, " > "), fn = fn, arg = arg }
        return path
    end
    missionCommands = {
        addSubMenuForCoalition = function(side, name, parent) return addItem("menu", side, name, parent) end,
        addCommandForCoalition = function(side, name, parent, fn, arg) return addItem("command", side, name, parent, fn, arg) end,
        addSubMenuForGroup = function(group, name, parent) return addItem("menu", "group " .. tostring(group), name, parent) end,
        addCommandForGroup = function(group, name, parent, fn, arg) return addItem("command", "group " .. tostring(group), name, parent, fn, arg) end,
        addSubMenu = function(name, parent) return addItem("menu", "all", name, parent) end,
        addCommand = function(name, parent, fn, arg) return addItem("command", "all", name, parent, fn, arg) end,
        removeItemForCoalition = function() end, removeItemForGroup = function() end, removeItem = function() end,
    }
end
