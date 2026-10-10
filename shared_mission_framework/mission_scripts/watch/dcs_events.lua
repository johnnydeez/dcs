-- Watch: DCS's events, the one place they come in (rule 13). Each is read once into a
-- plain fact (record\dcs_events.lua says what one holds) and published; everything that
-- needs an event subscribes there.

WatchDcsEvents = {}

local function kindOf(o, category)
    if category == Object.Category.UNIT then return "unit" end
    if category == Object.Category.WEAPON then return "weapon" end
    if category == Object.Category.STATIC then return "static" end
    if category == Object.Category.SCENERY then return "scenery" end
    if category == Object.Category.BASE then return "airbase" end
    return "other"
end

local function read(o, method)
    if type(o[method]) ~= "function" then return nil end
    local ok, v = pcall(o[method], o)
    return ok and v or nil
end

-- An object of an event as plain fields, or nil. `deep`: a weapon's target is described
-- too (one level).
local function describe(o, deep)
    if not o then return nil end
    local category = read(o, "getCategory")
    local d = { name = read(o, "getName"), type = read(o, "getTypeName"), category = category,
                kind = kindOf(o, category), coalition = read(o, "getCoalition"),
                -- the same object in another event: DCS's id (each event hands a fresh table)
                key = o.id_ or o }
    local point = read(o, "getPoint")
    if point then d.point = { x = point.x, y = point.y, z = point.z } end
    local desc = read(o, "getDesc")
    d.desc_category = desc and desc.category
    if d.kind == "unit" then
        d.unit_category = desc and desc.category
        local g = read(o, "getGroup")
        d.group, d.group_id = g and read(g, "getName"), g and read(g, "getID")
        d.player = read(o, "getPlayerName")
        -- grid heading of its nose (on the ground its velocity may be ~0)
        local position = read(o, "getPosition")
        if position then d.nose_deg = (math.deg(math.atan2(position.x.z, position.x.x)) % 360 + 360) % 360 end
    elseif d.kind == "weapon" then
        if desc then
            d.weapon_category, d.guidance, d.missile_category = desc.category, desc.guidance, desc.missileCategory
        end
        if deep then
            d.target = describe(read(o, "getTarget"))
            d.launcher = describe(read(o, "getLauncher"))
        end
    end
    return d
end

local _hits = 0   -- hits so far, each fact's `hit` number

-- The life a hit object has left a second on, once the hit's damage is in (2026-10-06:
-- the Kalevala Mi-8 was hit twice and nothing said how badly): "destroyed", "life now 92 %",
-- or nil.
local function lifeText(target)
    local ok, text = pcall(function()
        if not target:isExist() then return "destroyed" end
        local life = target:getLife()
        local full = (target.getLife0 and target:getLife0()) or (target:getDesc() or {}).life
        if not life or not full or full <= 0 then return nil end
        return string.format("life now %d %%", math.floor(math.max(0, math.min(1, life / full)) * 100 + 0.5))
    end)
    return ok and text or nil
end

local handler = {}
function handler:onEvent(e)
    local ok, fact = pcall(function()
        local place = e.place and { name = read(e.place, "getName") }
        return { id = e.id, time = e.time, raw = e, weapon_name = e.weapon_name, place = place,
                 initiator = describe(e.initiator), target = describe(e.target), weapon = describe(e.weapon, true) }
    end)
    if not ok then
        Log.warn("DCS events: reading event " .. tostring(e.id) .. " failed: " .. tostring(fact))
        fact = { id = e.id, time = e.time, raw = e }
    end
    -- a hit: what the target has left is a follow-up fact a second on ("hit_life")
    if e.id == world.event.S_EVENT_HIT and e.target then
        _hits = _hits + 1
        local n, target = _hits, e.target
        fact.hit = n
        timer.scheduleFunction(function()
            RecordDcsEvents.publish({ id = "hit_life", hit = n, life = lifeText(target) })
            return nil
        end, nil, timer.getTime() + 1)
    end
    RecordDcsEvents.publish(fact)
end

function WatchDcsEvents.start()
    world.addEventHandler(handler)
end
