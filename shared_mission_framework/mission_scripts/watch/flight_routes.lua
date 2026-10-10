-- Watch: AI flights along their routes. Every waypoint between takeoff and landing carries
-- one script command (execute\spawn_aircraft_groups.lua) that calls
-- WatchFlightRoutes.waypointReached when the flight gets there, so nothing polls; it goes
-- to record\waypoints_reached.lua.
-- At a watched SEAD flight's launch and press-on points (bug 36: in the 16:03 run no
-- flight fired, and nothing showed whether the site's radar ever reached them), one
-- RADAR_WARNING line in the event log: which radars the flight's warning receivers hold,
-- whether its site's is one, and the lead's height above the ground.

WatchFlightRoutes = {}

-- The waypoint's script command: flight `id` reached waypoint `index` of its route.
function WatchFlightRoutes.waypointReached(id, index)
    RecordWaypointsReached.publish({ id = id, index = index })
end

local function radarWarningLine(m, kind)
    local g = Group.getByName(m.id)
    if not (g and g:isExist()) then return end
    local site = m.attack and m.attack.groups and m.attack.groups[1]
    local emitters, siteSeen = {}, false
    for _, t in ipairs(g:getController():getDetectedTargets(Controller.Detection.RWR) or {}) do
        local obj = t.object
        local okName, groupName = pcall(function() return obj:getGroup():getName() end)
        if okName and groupName then
            if groupName == site then siteSeen = true end
            emitters[groupName] = true
        end
    end
    local names = {}
    for name in pairs(emitters) do names[#names + 1] = name end
    table.sort(names)
    local lead
    for _, u in ipairs(g:getUnits() or {}) do
        if u:isExist() and u:inAir() then lead = u break end
    end
    local p = lead and lead:getPoint()
    local height = p and string.format("; lead %s ft, %s ft above the ground",
        Util.thousands(p.y * 3.28084), Util.thousands((p.y - land.getHeight({ x = p.x, y = p.z })) * 3.28084)) or ""
    EventLog.add(m.coalition, "RADAR_WARNING", m.id, string.format("at its %s, %.0f km from %s: its radar %s; on the warning receivers: %s%s",
        kind == "target" and "launch point" or "press-on point",
        p and m.attack.site and Util.dist({ x = p.x, z = p.z }, m.attack.site) / 1000 or 0, site or "its site",
        siteSeen and "SEEN" or "not seen", #names > 0 and table.concat(names, ", ") or "nothing", height))
end

local function hasSuppression(w)
    for _, name in ipairs(w.directives or {}) do
        if name == "suppression" then return true end
    end
    return false
end

-- The radar warning snapshot (after the event log's WAYPOINT line, before the flight calls).
function WatchFlightRoutes.start()
    RecordWaypointsReached.on(function(id, index)
        local w = RecordWatchedFlights.flight(id)
        local r = w and w.mission.route and w.mission.route[index]
        if not (r and hasSuppression(w)) then return end
        if r.kind == "target" or r.kind == "press_on" then
            local ok, err = pcall(radarWarningLine, w.mission, r.kind)
            if not ok then Log.warn(string.format("%s: radar warning line failed: %s", id, tostring(err))) end
        end
    end)
end
