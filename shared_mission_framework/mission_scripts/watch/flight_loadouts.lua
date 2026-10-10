-- Watch: what each jet of a launched flight actually carries, as DCS reports it, a few
-- seconds after the spawn (John's run, 2026-09-27: a Su-24M flight looked unarmed although
-- the plan gave it a loadout). One LOADOUT line per jet in the event log. A jet with no
-- weapon aboard (its gun aside) while its loadout lists weapon pylons is a warning in
-- dcs.log and a fact on record\flight_loadouts.lua: the controller removes it on the ramp
-- (bug 6), so it never flies into a fight with nothing.

WatchFlightLoadouts = {}

-- Seconds after the spawn that each unit's ammo is read.
local AMMO_CHECK_DELAY_S = 5

-- Pylons of a loadout that hold weapons (not fuel tanks, targeting or jamming pods, smoke).
local function weaponPylons(loadout)
    local n = 0
    for _, py in ipairs(loadout.pylons or {}) do
        local w = (py.weapon or ""):lower()
        if not (w:find("fuel tank", 1, true) or w:find("targeting pod", 1, true) or w:find("ecm", 1, true)
                or w:find("jamm", 1, true) or w:find("smoke", 1, true)) then
            n = n + 1
        end
    end
    return n
end

local function check(m)
    local grp = Group.getByName(m.id)
    if not (grp and grp:isExist()) then return end
    local pylons = weaponPylons(m.loadout)
    local unarmed = {}
    for _, u in ipairs(grp:getUnits() or {}) do
        local parts, weapons = {}, 0
        for _, a in ipairs(u:getAmmo() or {}) do
            local d = a.desc or {}
            parts[#parts + 1] = string.format("%s x%d", d.displayName or d.typeName or "?", a.count or 0)
            if d.category ~= Weapon.Category.SHELL and (a.count or 0) > 0 then weapons = weapons + 1 end
        end
        local carries = #parts > 0 and table.concat(parts, ", ") or "nothing"
        EventLog.add(m.coalition, "LOADOUT", u:getName(), string.format("%s carries %s", m.aircraft_type, carries))
        if weapons == 0 and pylons > 0 then
            Log.warn(string.format("%s: %s carries no weapons — its loadout '%s' lists %d weapon pylons", m.id, u:getName(),
                m.loadout.name, pylons))
            unarmed[#unarmed + 1] = u:getName()
        end
    end
    if #unarmed > 0 then
        RecordFlightLoadouts.publish({ event = "unarmed", mission = m, units = unarmed,
                                       loadout_text = string.format("'%s' lists %d weapon pylons", m.loadout.name, pylons) })
    end
end

function WatchFlightLoadouts.start()
    RecordFlightLaunches.on("launched", function(e)
        timer.scheduleFunction(function() check(e.mission) end, nil, timer.getTime() + AMMO_CHECK_DELAY_S)
    end)
end
