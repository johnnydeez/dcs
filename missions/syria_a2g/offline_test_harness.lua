-- Offline test harness for the Syria mission: stubs the DCS scripting API, runs the
-- real init.lua (every module's startup), then drives the cost tracker with scripted
-- combat events and checks the scores. Prints PASS / FAIL lines and a failure count.
-- init.lua builds its paths from lfs.writedir(), so the scripts must sit in a
-- "Scripts\a2g_dynamic_syria\" folder: run it against the deployed copy.
--   "C:\Program Files\Eagle Dynamics\DCS World\bin\luae.exe" offline_test_harness.lua
--       "C:\Users\johnk\Saved Games\DCS\Scripts\a2g_dynamic_syria\"

local SCRIPT_DIR = arg[1]
local now = 0
local scheduled = {}
local handlers = {}
local screen = {}
local objectCounter = 100

env = { info = function(s) io.write(s, "\n") end, warning = function(s) io.write("WARN ", s, "\n") end }
lfs = { writedir = function() return SCRIPT_DIR:gsub("Scripts\\a2g_dynamic_syria\\$", "") end }

timer = {
    getTime = function() return now end,
    getAbsTime = function() return 28800 + now end,
    scheduleFunction = function(fn, arg, t) table.insert(scheduled, { fn = fn, arg = arg, t = t }) return #scheduled end,
}
local function advance(seconds)
    local target = now + seconds
    while true do
        table.sort(scheduled, function(a, b) return a.t < b.t end)
        local nextJob = scheduled[1]
        if not nextJob or nextJob.t > target then break end
        table.remove(scheduled, 1)
        now = nextJob.t
        local nextTime = nextJob.fn(nextJob.arg, now)
        if nextTime then table.insert(scheduled, { fn = nextJob.fn, arg = nextJob.arg, t = nextTime }) end
    end
    now = target
end

world = {
    event = { S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4, S_EVENT_CRASH = 5,
              S_EVENT_EJECTION = 6, S_EVENT_DEAD = 8, S_EVENT_PILOT_DEAD = 9, S_EVENT_BIRTH = 15,
              S_EVENT_PLAYER_ENTER_UNIT = 20, S_EVENT_PLAYER_LEAVE_UNIT = 21, S_EVENT_SHOOTING_START = 23,
              S_EVENT_SHOOTING_END = 24, S_EVENT_KILL = 28, S_EVENT_UNIT_LOST = 30 },
    addEventHandler = function(h) table.insert(handlers, h) end,
    getAirbases = function() return {} end,
}
local function fire(event) for _, h in ipairs(handlers) do h:onEvent(event) end end

coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }
country = { id = { CJTF_RED = 81, CJTF_BLUE = 80 } }
Object = { Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5 } }
Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3 } }
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2 } }
AI = { Option = { Air = { id = { ROE = 0, REACTION_ON_THREAT = 1 }, val = { ROE = { WEAPON_FREE = 0 }, REACTION_ON_THREAT = { ALLOW_ABORT_MISSION = 4 } } } } }
land = { SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 },
         getHeight = function() return 100 end,
         getClosestPointOnRoads = function(_, x, y) return x + 5, y + 5 end,
         getSurfaceType = function() return 1 end }
coord = { LLtoLO = function(lat, lon) return { x = lat * 1000, y = 0, z = lon * 1000 } end,
          LOtoLL = function(p) return 35 + p.x / 1e6, 36 + p.z / 1e6, 0 end }
missionCommands = {
    addSubMenuForCoalition = function() return {} end,
    addCommandForCoalition = function() return {} end,
    addCommandForGroup = function(gid, name, path, fn, arg) screen.menu = { gid = gid, fn = fn, arg = arg } return {} end,
}
trigger = {
    action = setmetatable({
        outText = function(t) table.insert(screen, t) end,
        outTextForCoalition = function(_, t) table.insert(screen, t) end,
        outTextForGroup = function(_, t) table.insert(screen, t) end,
    }, { __index = function() return function() end end }),
    misc = { getZone = function() return { point = { x = 0, y = 0, z = 0 }, radius = 100 } end, getUserFlag = function() return 0 end },
    smokeColor = { Green = 0 },
}

-- ── Fake objects ──────────────────────────────────────────────
-- A dead object raises on every method, like DCS does for a destroyed object.
local ObjectMethods = {}
local function makeObject(props)
    objectCounter = objectCounter + 1
    props.id_ = objectCounter
    return setmetatable(props, { __index = function(t, k)
        local m = ObjectMethods[k]
        if not m then return nil end
        return function(self, ...)
            if rawget(self, "dead") and k ~= "getName" and k ~= "getCoalition" and k ~= "getTypeName" and k ~= "isExist" then
                error("object doesn't exist")
            end
            return m(self, ...)
        end
    end })
end
function ObjectMethods.getName(self) return self.name end
function ObjectMethods.getTypeName(self) return self.typeName end
function ObjectMethods.getCoalition(self) return self.coalitionSide end
function ObjectMethods.getPlayerName(self) return self.player end
function ObjectMethods.isExist(self) return not self.dead end
function ObjectMethods.getID(self) return self.unitId or self.id_ end
function ObjectMethods.getGroup(self) return self.group end
function ObjectMethods.getLauncher(self) return self.launcher end
function ObjectMethods.getPoint(self) return self.point or { x = 0, y = 0, z = 0 } end
function ObjectMethods.getAmmo(self) return { { count = self.shells or 0, desc = { category = 0 } }, { count = 2, desc = { category = 1 } } } end
function ObjectMethods.inAir(self) return self.airborne end
function ObjectMethods.getUnits(self) return self.units end
function ObjectMethods.getSize(self) return #self.units end
function ObjectMethods.getUnit(self, i) return self.units[i] end
function ObjectMethods.activate() end
function ObjectMethods.destroy(self) self.dead = true end
function ObjectMethods.getController() return makeObject({}) end
function ObjectMethods.setOption() end
function ObjectMethods.setTask() end
function ObjectMethods.getDesc() return { category = 0 } end
function ObjectMethods.autoCapture() end
function ObjectMethods.setCoalition(self, side) self.coalitionSide = side end

Object.getCategory = function(obj)
    if obj.dead and obj.category == Object.Category.WEAPON then error("weapon doesn't exist") end
    return obj.category
end

local groupsByName = {}
Group.getByName = function(name)
    local g = groupsByName[name]
    if g and not g.dead then return g end
    if name:match("^RED_") or name:match("^BLUE_CAS") then
        g = makeObject({ name = name, category = 1, units = {} })
        g.units[1] = makeObject({ name = name .. "_1", typeName = "X", category = 1, coalitionSide = 1, group = g })
        groupsByName[name] = g
        return g
    end
    return nil
end
coalition.addGroup = function(countryId, category, def)
    local g = makeObject({ name = def.name, category = 1, units = {} })
    for i, u in ipairs(def.units) do
        g.units[i] = makeObject({ name = u.name, typeName = u.type, category = 1, group = g,
            coalitionSide = (countryId == country.id.CJTF_RED) and 1 or 2 })
    end
    groupsByName[def.name] = g
    return g
end
coalition.addStaticObject = function() return makeObject({ category = 3 }) end
local blueGroups = {}
coalition.getGroups = function(side, category)
    if side == coalition.side.BLUE and category == Group.Category.AIRPLANE then return blueGroups end
    return {}
end
local airbases = {}
Airbase = { getByName = function(name)
    if name == "Ghost Field" then return nil end
    airbases[name] = airbases[name] or makeObject({ name = name, category = 4, point = { x = #name * 7000, y = 0, z = #name * 3000 } })
    return airbases[name]
end }

-- ── Run the real mission startup ──────────────────────────────
dofile(SCRIPT_DIR .. "init.lua")
advance(15)
print("---- startup done; scheduled jobs: " .. #scheduled)

-- ── Scenario helpers ──────────────────────────────────────────
local function playerAircraft(player, unitName, typeName)
    local g = makeObject({ name = unitName .. "_grp", category = 1, units = {} })
    local u = makeObject({ name = unitName, typeName = typeName, category = 1, coalitionSide = 2,
        player = player, group = g, airborne = false, shells = 1150 })
    g.units[1] = u
    table.insert(blueGroups, g)
    fire({ id = world.event.S_EVENT_BIRTH, initiator = u })
    return u
end
local function redUnit(name, typeName, category)
    return makeObject({ name = name, typeName = typeName, category = category or 1, coalitionSide = 1 })
end
local function weaponFrom(launcher, typeName)
    return makeObject({ typeName = typeName, category = 2, launcher = launcher })
end
-- Each event gets fresh wrapper tables with the same id_, as DCS does.
local function again(obj)
    local copy = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do copy[k] = v end
    return copy
end
local function score(player)
    local s = CostTracker.playerScores[player]
    return s and string.format("spent=%.4f destroyed=%.3f", s.spent, s.destroyed) or "none"
end
local failures = 0
local function expect(label, actual, expected)
    local ok = math.abs(actual - expected) < 1e-6
    if not ok then failures = failures + 1 end
    print(string.format("%s %-60s got %.4f expected %.4f", ok and "PASS" or "FAIL", label, actual, expected))
end
local function spent(p) return CostTracker.playerScores[p] and CostTracker.playerScores[p].spent or 0 end
local function destroyed(p) return CostTracker.playerScores[p] and CostTracker.playerScores[p].destroyed or 0 end

-- 1. Direct Maverick kill, KILL then DEAD: credited once.
local a10 = playerAircraft("Alpha", "Incirlik_A10cii-1", "A-10C_2")
fire({ id = world.event.S_EVENT_TAKEOFF, initiator = a10 })
local mav = weaponFrom(a10, "AGM_65D")
fire({ id = world.event.S_EVENT_SHOT, initiator = a10, weapon = mav })
expect("1 Maverick charged", spent("Alpha"), 0.070)
local tank = redUnit("CONVOY_Armor_1_3", "T-72B")
fire({ id = world.event.S_EVENT_HIT, initiator = a10, weapon = again(mav), target = tank })
fire({ id = world.event.S_EVENT_KILL, initiator = a10, weapon = again(mav), target = tank })
tank.dead = true
fire({ id = world.event.S_EVENT_DEAD, initiator = again(tank) })
fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = again(tank) })
expect("1 tank credited once", destroyed("Alpha"), 2.0)

-- 2. Cluster submunition hit (initiator is the weapon), DEAD without KILL (static).
local cbu = weaponFrom(a10, "CBU_97")
fire({ id = world.event.S_EVENT_SHOT, initiator = a10, weapon = cbu })
local sub = weaponFrom(nil, "BLU_108")   -- submunition: no launcher known
local bunker = redUnit("SD_M2_helo", "Mi-8MT", 3)
fire({ id = world.event.S_EVENT_HIT, initiator = sub, weapon = again(cbu), target = bunker })
bunker.dead = true
fire({ id = world.event.S_EVENT_DEAD, initiator = again(bunker) })
expect("2 static credited via HIT->DEAD", destroyed("Alpha"), 2.0 + 8)

-- 3. Weapon still flying when the shooter is gone: credit through the weapon record.
local gbu = weaponFrom(a10, "GBU_12")
fire({ id = world.event.S_EVENT_SHOT, initiator = a10, weapon = gbu })
local sa6 = redUnit("RED_Damascus_SA6_2", "Kub 2P25 ln")
a10.dead = true   -- shot down while the bomb falls
fire({ id = world.event.S_EVENT_KILL, initiator = nil, weapon = again(gbu), target = sa6 })
expect("3 kill after shooter died, SA-6 value", destroyed("Alpha"), 10 + 7)

-- 4. Shot down: DEAD + CRASH + PILOT_DEAD charge the aircraft once.
local before = spent("Alpha")
fire({ id = world.event.S_EVENT_DEAD, initiator = again(a10) })
fire({ id = world.event.S_EVENT_CRASH, initiator = again(a10) })
fire({ id = world.event.S_EVENT_PILOT_DEAD, initiator = again(a10) })
fire({ id = world.event.S_EVENT_PLAYER_LEAVE_UNIT, initiator = again(a10) })
expect("4 A-10C II lost, charged once at 65", spent("Alpha") - before, 65)

-- 5. Land at Blue base, take off again, eject: charged (waiver resets on takeoff).
local viper = playerAircraft("Bravo", "TelNof_F16-1", "F-16C_50")
fire({ id = world.event.S_EVENT_TAKEOFF, initiator = viper })
fire({ id = world.event.S_EVENT_LAND, initiator = viper, place = makeObject({ name = "Tel Nof", category = 4, coalitionSide = 2 }) })
fire({ id = world.event.S_EVENT_TAKEOFF, initiator = viper })
fire({ id = world.event.S_EVENT_EJECTION, initiator = viper })
fire({ id = world.event.S_EVENT_CRASH, initiator = viper })
expect("5 relaunched after safe landing, ejection charged once", spent("Bravo"), 65)

-- 6. Safe landing then slot out: nothing charged.
local hornet = playerAircraft("Charlie", "Beirut_F18-1", "FA-18C_hornet")
fire({ id = world.event.S_EVENT_TAKEOFF, initiator = hornet })
fire({ id = world.event.S_EVENT_LAND, initiator = hornet, place = makeObject({ name = "Beirut", category = 4, coalitionSide = 2 }) })
fire({ id = world.event.S_EVENT_PLAYER_LEAVE_UNIT, initiator = hornet })
hornet.dead = true
fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = again(hornet) })
expect("6 safe landing + slot out: no charge", spent("Charlie"), 0)

-- 7. Airborne slot out: no charge (user rule).
local hornet2 = playerAircraft("Charlie", "Beirut_F18-2", "FA-18C_hornet")
fire({ id = world.event.S_EVENT_TAKEOFF, initiator = hornet2 })
fire({ id = world.event.S_EVENT_PLAYER_LEAVE_UNIT, initiator = hornet2 })
hornet2.dead = true
fire({ id = world.event.S_EVENT_DEAD, initiator = again(hornet2) })
expect("7 airborne slot out: no charge", spent("Charlie"), 0)

-- 8. Gun burst: 150 rounds of M61.
local viper2 = playerAircraft("Bravo", "TelNof_F16-2", "F-16C_50")
before = spent("Bravo")
viper2.shells = 510
fire({ id = world.event.S_EVENT_SHOOTING_START, initiator = viper2 })
viper2.shells = 360
fire({ id = world.event.S_EVENT_SHOOTING_END, initiator = viper2 })
expect("8 150 M61 rounds", spent("Bravo") - before, 150 * 0.00003)

-- 9. Player hits, AI finishes within 5 min: player credited; AI kill with no player hit: nobody.
local btr = redUnit("CAS_HS02_ATTACK_def_12", "BTR-80")
fire({ id = world.event.S_EVENT_HIT, initiator = viper2, target = btr })
advance(60)
local aiJet = makeObject({ name = "BAS_1_1", typeName = "F-16C_50", category = 1, coalitionSide = 2 })
fire({ id = world.event.S_EVENT_KILL, initiator = aiJet, target = btr })
fire({ id = world.event.S_EVENT_DEAD, initiator = again(btr) })
expect("9a AI finish within window credits Bravo", destroyed("Bravo"), 1.2)
local ural = redUnit("CONVOY_Supply_1_4", "Ural-4320-31")
fire({ id = world.event.S_EVENT_KILL, initiator = aiJet, target = ural })
fire({ id = world.event.S_EVENT_DEAD, initiator = again(ural) })
expect("9b AI kill without player hit: no credit", destroyed("Bravo"), 1.2)
local zu = redUnit("DEF_Hama_ZU23_1", "Ural-375 ZU-23")
fire({ id = world.event.S_EVENT_HIT, initiator = viper2, target = zu })
advance(400)
fire({ id = world.event.S_EVENT_KILL, initiator = aiJet, target = zu })
expect("9c AI finish after window: no credit", destroyed("Bravo"), 1.2)

-- 10. Broken event data never escapes as a Lua error.
fire({ id = world.event.S_EVENT_HIT })
fire({ id = world.event.S_EVENT_KILL, target = {} })
fire({ id = world.event.S_EVENT_DEAD, initiator = makeObject({ category = 2, dead = true }) })
fire({ id = world.event.S_EVENT_LAND, initiator = viper2 })
fire({ id = world.event.S_EVENT_SHOOTING_END, initiator = viper2 })
print("PASS 10 malformed events handled")

-- 11. Score menu and broadcast still run.
advance(400)
if screen.menu then screen.menu.fn(screen.menu.arg) end
print("---- last screen message:\n" .. tostring(screen[#screen]))
print(string.format("\n%d failure(s)", failures))
