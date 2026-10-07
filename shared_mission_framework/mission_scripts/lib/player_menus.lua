-- Comms menus per player group (\ > F10. Other...), so in multiplayer each player's
-- menu texts show on their own screen only: a frag or a steerpoint list one player opens
-- doesn't cover another player's screen, and their "Hide text" doesn't clear it.
--   PlayerMenus.add(side, build)   build(menu) adds one consumer's entries for one group;
--                                  called for every player group of coalition `side`
--                                  (coalition.side.*), in the order the builders were added
--   menu.sub(name, parent)         a submenu (parent nil: the top of the comms menu)
--   menu.command(name, parent, fn) a command; fn() runs when the player picks it
--   menu.show(text, seconds)       text to this group only, replacing what it shows
--   menu.group_name                the group's name (a player slot's: data/player_slots.lua)
-- A group's menus are built the first time a player is seen in it (every CHECK_S, and at
-- once on a player's birth or entering a unit), and removed once no player is in it any
-- more, so a group id DCS gives out again starts clean.

PlayerMenus = {}

local CHECK_S = 5

local _builders = {}   -- { side, build }, in the order added
local _groups = {}     -- group id → { side, roots = { the top-level items added } }
local _started = false

local function playerGroups()
    local out = {}   -- group id → { side, name }
    for _, side in ipairs({ coalition.side.RED, coalition.side.BLUE }) do
        for _, u in ipairs(coalition.getPlayers(side) or {}) do
            local ok, id, name = pcall(function() local g = u:getGroup(); return g:getID(), g:getName() end)
            if ok and id then out[id] = { side = side, name = name } end
        end
    end
    return out
end

local function build(groupId, side, groupName)
    local entry = { side = side, roots = {} }
    _groups[groupId] = entry
    local menu = { group_name = groupName }
    function menu.sub(name, parent)
        local item = missionCommands.addSubMenuForGroup(groupId, name, parent)
        if not parent then entry.roots[#entry.roots + 1] = item end
        return item
    end
    function menu.command(name, parent, fn)
        local item = missionCommands.addCommandForGroup(groupId, name, parent, function()
            local ok, err = pcall(fn)
            if not ok then Log.warn(string.format("comms menu '%s' failed: %s", name, tostring(err))) end
        end)
        if not parent then entry.roots[#entry.roots + 1] = item end
        return item
    end
    function menu.show(text, seconds)
        trigger.action.outTextForGroup(groupId, text, seconds, true)
    end
    for _, b in ipairs(_builders) do
        if b.side == side then
            local ok, err = pcall(b.build, menu)
            if not ok then Log.warn(string.format("comms menu for group %s: a builder failed: %s", tostring(groupId), tostring(err))) end
        end
    end
end

local function check()
    local now = playerGroups()
    for id, g in pairs(now) do
        if not _groups[id] then build(id, g.side, g.name) end
    end
    for id, entry in pairs(_groups) do
        if not now[id] then
            for _, item in ipairs(entry.roots) do pcall(missionCommands.removeItemForGroup, id, item) end
            _groups[id] = nil
        end
    end
end

local function start()
    _started = true
    timer.scheduleFunction(function(_, t)
        local ok, err = pcall(check)
        if not ok then Log.warn("comms menus: check failed: " .. tostring(err)) end
        return t + CHECK_S
    end, nil, timer.getTime() + 1)
    local handler = {}
    function handler:onEvent(e)
        if e.id == world.event.S_EVENT_BIRTH or e.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
            -- a moment later: DCS sets the player on a new unit after its birth
            timer.scheduleFunction(function() pcall(check) end, nil, timer.getTime() + 1)
        end
    end
    world.addEventHandler(handler)
end

function PlayerMenus.add(side, buildFn)
    _builders[#_builders + 1] = { side = side, build = buildFn }
    if not _started then start() end
end
