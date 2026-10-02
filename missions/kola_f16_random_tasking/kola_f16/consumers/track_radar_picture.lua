-- Consumer: each coalition's radar picture — the enemy aircraft its own radars actually
-- report, kept as the mission runs (roadmap.md item 1). Scrambles, AWACS calls and
-- later fog of war read it, so they act only on what the defenders could really know.
-- It watches and logs; it gives no orders and spawns nothing.
--
-- Every RADAR_PICTURE.poll_interval_s, per coalition:
--   1. sensors: the SAM sites and base-defense groups from the plan whose units carry a
--      radar (checked once at start), plus the AWACS, patrols and scrambles while
--      airborne. Dead groups drop out, so losing the AWACS thins the picture by itself
--   2. each sensor is asked once, spread over the round:
--      Controller:getDetectedTargets(RADAR) — radar only, never DLINK, or every unit
--      would echo what the others share
--   3. at the end of the round each enemy group seen becomes or refreshes a contact:
--      airplane or helicopter, position, altitude, heading, speed, who saw it, type (only if a sensor knew it),
--      whether the range is known, airspace, nearest own base, own SAM ring, and the own
--      asset its heading will bring it to (inbound) and in how many minutes
--   4. contacts not seen turn stale, then drop; events go to the listeners, then
--      picture_updated once the round is complete
--
-- Event log lines (consumers/write_event_log.lua), coalition = whose picture:
--   PICTURE   RED  "3 contacts (own 1, contested 2, enemy 0; 1 stale), 28 of 30 sensors answered"
--   CONTACT   RED  MSN2014_DEAD  "new, F-16C_50, seen by early_warning SAM_OLEN_55G6_1 212 km away (+2 more),
--                  24,000 ft, contested airspace, 62 km from Olenya, inbound Olenya in 11 min"
--   CONTACT   RED  MSN2014_DEAD  "entered own airspace (was contested), …" / "stale, last seen
--                  65 s ago" / "regained by …" / "dropped, last seen 300 s ago"
--   TRACKING  RED  SAM_OLEN_SA10_1  "radar tracking MSN2014_DEAD (F-16C_50)"   the first time only
-- The sensors found at start go to dcs.log (grep "picture").
--
-- Other code reads it with the calls at the bottom (on, contacts, contactsNear, contact,
-- sensors). Contacts are returned as they are kept: read them, never change them.
-- Reads the plan; writes nothing back to it. Sensors and contacts are runtime state,
-- keyed by the plan's group ids.

TrackRadarPicture = {}

local SIDE  = { red = 1, blue = 2 }             -- coalition.side
local ENEMY = { red = "blue", blue = "red" }
local FEET_PER_METRE = 3.28084
local EVENTS = { new_contact = true, airspace_changed = true, contact_stale = true, contact_dropped = true,
                 picture_updated = true }

local _plan
local _pictures = {}   -- coalition → picture (below)

-- ── Sensors ─────────────────────────────────────────────────────

local function hasRadar(group)
    local ok, yes = pcall(function()
        for _, u in ipairs(group:getUnits() or {}) do
            if u:hasSensors(Unit.SensorType.RADAR) then return true end
        end
        return false
    end)
    return ok and yes
end

local function alive(groupName)
    local g = Group.getByName(groupName)
    local ok, exists = pcall(function() return g and g:isExist() end)
    return ok and exists and g or nil
end

local function airborne(group)
    local ok, yes = pcall(function()
        for _, u in ipairs(group:getUnits() or {}) do
            if u:inAir() then return true end
        end
        return false
    end)
    return ok and yes
end

-- The coalition's ground sensors, from the plan: groups that exist and carry a radar.
local function groundSensors(coalitionName)
    local kinds, candidates = RADAR_PICTURE.sensor_kinds, {}
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side == coalitionName then
            local kind = s.layer == "early_warning" and "early_warning" or "sam_search"
            for _, id in ipairs(s.group_ids or {}) do
                candidates[#candidates + 1] = { id = id, kind = kind }
            end
        end
    end
    for _, g in ipairs(_plan.base_defenses and _plan.base_defenses.groups or {}) do
        if g.side == coalitionName and RADAR_PICTURE.base_defense_components[g.component] then
            candidates[#candidates + 1] = { id = g.id, kind = "base_defense" }
        end
    end
    local sensors, withoutRadar = {}, 0
    for _, c in ipairs(candidates) do
        if kinds[c.kind] then
            local g = alive(c.id)
            if g and hasRadar(g) then
                sensors[#sensors + 1] = { id = c.id, kind = c.kind, ground = true }
            elseif g then
                withoutRadar = withoutRadar + 1
            end
        end
    end
    return sensors, withoutRadar
end

-- Planned AI flights whose radars count, by mission type: id → kind.
local function flightSensors(coalitionName)
    local flights = {}
    local ato = _plan.air_tasking_orders and _plan.air_tasking_orders[coalitionName]
    for _, m in ipairs(ato and ato.missions or {}) do
        local kind = RADAR_PICTURE.flight_sensor_kinds[m.mission_type]
        if kind and m.flown_by ~= "human" and RADAR_PICTURE.sensor_kinds[kind] then
            flights[m.id] = kind
        end
    end
    return flights
end

-- This round's sensors: ground sensors still alive, flights airborne now.
local function roundSensors(p)
    local list = {}
    for _, s in ipairs(p.ground_sensors) do
        if alive(s.id) then list[#list + 1] = s end
    end
    local ids = {}
    for id in pairs(p.flight_sensors) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local g = alive(id)
        if g and airborne(g) then list[#list + 1] = { id = id, kind = p.flight_sensors[id] } end
    end
    return list
end

-- ── Contacts ────────────────────────────────────────────────────

local function kindOf(obj)
    local ok, category, unitCategory = pcall(function()
        local c = obj:getCategory()
        return c, c == Object.Category.UNIT and obj:getDesc().category or nil
    end)
    if not ok then return nil end
    if category == Object.Category.WEAPON then return "missile" end
    if category == Object.Category.UNIT then
        if unitCategory == Unit.Category.AIRPLANE then return "aircraft", "airplane" end
        if unitCategory == Unit.Category.HELICOPTER then return "aircraft", "helicopter" end
    end
    return nil
end

local function isEnemyAirborne(obj, coalitionName)
    local ok, yes = pcall(function()
        return obj:getCoalition() == SIDE[ENEMY[coalitionName]] and obj:inAir()
    end)
    return ok and yes
end

local function typeText(c)
    return c.type or "type unknown"
end

local function nearestOwnBase(coalitionName, pos)
    local best, bestD
    for name, b in pairs(_plan.territory.bases) do
        local ab = b.side == coalitionName and _plan.world.airbases[name]
        if ab and ab.anchor then
            local d = Util.dist(pos, ab.anchor)
            if not bestD or d < bestD then best, bestD = name, d end
        end
    end
    return best, bestD
end

local function ownSamRing(coalitionName, pos)
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side == coalitionName and (s.engage_m or 0) > 0 and Util.dist(pos, s.pos) <= s.engage_m then
            return s.id
        end
    end
    return nil
end

-- The own asset (held base or catalog target) the contact's heading line passes within
-- RADAR_PICTURE.threat_pass_km of, soonest ahead, and the minutes until it gets there.
local function threatOf(p, c)
    if c.speed_mps < RADAR_PICTURE.inbound_min_speed_mps then return nil end
    local r = math.rad(c.heading_deg)
    local hx, hz = math.cos(r), math.sin(r)   -- x north, z east
    local passM = RADAR_PICTURE.threat_pass_km * 1000
    local best, bestMin
    for _, a in ipairs(p.assets) do
        local dx, dz = a.pos.x - c.pos.x, a.pos.z - c.pos.z
        local along = dx * hx + dz * hz
        if along > 0 and math.abs(dx * hz - dz * hx) <= passM then
            local minutes = along / c.speed_mps / 60
            if not bestMin or minutes < bestMin then best, bestMin = a.name, minutes end
        end
    end
    return best, bestMin
end

-- Position, motion and the facts derived from them, from one sighting.
local function locate(p, c, coalitionName, sighting)
    local pt, v = sighting.point, sighting.velocity
    c.pos = { x = pt.x, z = pt.z }
    c.altitude_m = pt.y
    c.speed_mps = math.sqrt(v.x * v.x + v.z * v.z)
    local heading = math.deg(math.atan2(v.z, v.x))
    if heading < 0 then heading = heading + 360 end
    c.heading_deg = math.floor(heading + 0.5) % 360
    c.airspace = DivideAirspace.kindFor(_plan.airspace, c.pos, coalitionName)
    local base, d = nearestOwnBase(coalitionName, c.pos)
    c.nearest_base, c.nearest_base_km = base, d and d / 1000
    c.inside_own_sam_ring = ownSamRing(coalitionName, c.pos)
    c.threat_asset, c.threat_minutes = threatOf(p, c)
    c.inbound = c.threat_asset ~= nil
end

local function whereText(c)
    local text = string.format("%s ft, %s airspace", Util.thousands(c.altitude_m * FEET_PER_METRE), c.airspace)
    if c.nearest_base then text = text .. string.format(", %.0f km from %s", c.nearest_base_km, c.nearest_base) end
    if c.inside_own_sam_ring then text = text .. ", inside " .. c.inside_own_sam_ring end
    if c.inbound then
        text = text .. (c.threat_minutes < 1 and (", passing " .. c.threat_asset)
            or string.format(", inbound %s in %.0f min", c.threat_asset, c.threat_minutes))
    end
    if not c.range_known then text = text .. ", bearing only" end
    return text
end

-- ── Events ──────────────────────────────────────────────────────

local function fire(p, event, contact, extra)
    for _, fn in ipairs(p.listeners[event]) do
        local ok, err = pcall(fn, contact, extra)
        if not ok then Log.warn(string.format("%s picture: a %s listener failed: %s", p.label, event, tostring(err))) end
    end
end

-- ── The round ───────────────────────────────────────────────────

-- Ask one sensor; merge what it reports into this round's sightings.
local function poll(p, sensor)
    local g = alive(sensor.id)
    if not g then return end
    p.asked = p.asked + 1
    local ok, list = pcall(function() return g:getController():getDetectedTargets(Controller.Detection.RADAR) end)
    if not ok or type(list) ~= "table" then return end
    p.answered = p.answered + 1
    -- where the sensor is, for how far it saw each contact (calibrates the coverage the
    -- air picture calls assume, data/air_picture_calls.lua)
    local okPos, sensorPos = pcall(function() return g:getUnits()[1]:getPoint() end)
    if not okPos then sensorPos = nil end
    for _, t in ipairs(list) do
        local obj = t.object
        local kind, category
        if obj then kind, category = kindOf(obj) end
        if kind == "missile" then
            if RADAR_PICTURE.count_missiles then
                local okName, name = pcall(function() return obj:getName() end)
                p.missiles[obj.id_ or (okName and name) or tostring(obj)] = true
            end
        elseif kind == "aircraft" and isEnemyAirborne(obj, p.coalition) then
            local okRead, groupName, typeName, point, velocity = pcall(function()
                return obj:getGroup():getName(), obj:getTypeName(), obj:getPoint(), obj:getVelocity()
            end)
            if okRead and groupName then
                local s = p.sightings[groupName]
                if not s then
                    s = { type_known = false, range_known = false, seen_by = {}, point = point, velocity = velocity,
                          category = category }
                    p.sightings[groupName] = s
                end
                s.type_name = typeName
                s.type_known = s.type_known or t.type == true
                s.range_known = s.range_known or t.distance == true
                s.seen_by[sensor.kind] = (s.seen_by[sensor.kind] or 0) + 1
                s.sensor_count = (s.sensor_count or 0) + 1
                if not s.first_sensor then
                    s.first_sensor = sensor
                    s.first_range_m = sensorPos and Util.dist({ x = sensorPos.x, z = sensorPos.z }, { x = point.x, z = point.z })
                end
            end
        end
    end
    -- test aid: which enemy group a ground radar is tracking (Unit:getRadar)
    if RADAR_PICTURE.log_radar_tracking and sensor.ground then
        pcall(function()
            for _, u in ipairs(g:getUnits() or {}) do
                local on, target = u:getRadar()
                if on and target and kindOf(target) == "aircraft" then
                    local targetGroup = target:getGroup():getName()
                    local key = sensor.id .. "|" .. targetGroup
                    if not p.tracking_logged[key] then
                        p.tracking_logged[key] = true
                        WriteEventLog.add(p.coalition, "TRACKING", sensor.id, string.format("radar tracking %s (%s)",
                            targetGroup, target:getTypeName()))
                    end
                end
            end
        end)
    end
end

-- End of a round: sightings → contacts, then stale and dropped contacts, then events.
local function finishRound(p, now)
    for groupName, s in pairs(p.sightings) do
        local c = p.contacts[groupName]
        local isNew, wasStale = c == nil, c and c.state == "stale"
        local airspaceBefore = c and c.airspace
        if isNew then
            c = { group = groupName, first_seen = now }
            p.contacts[groupName] = c
        end
        c.last_seen = now
        c.state = "tracked"
        c.seen_by = s.seen_by
        c.type_known = s.type_known
        c.type = s.type_known and s.type_name or c.type   -- once identified, stays identified
        c.range_known = s.range_known
        c.category = s.category
        locate(p, c, p.coalition, s)
        local by = string.format("%s %s", s.first_sensor.kind, s.first_sensor.id)
        if s.first_range_m then by = by .. string.format(" %.0f km away", s.first_range_m / 1000) end
        if s.sensor_count > 1 then by = by .. string.format(" (+%d more)", s.sensor_count - 1) end
        if isNew then
            WriteEventLog.add(p.coalition, "CONTACT", groupName, string.format("new, %s, seen by %s, %s",
                typeText(c), by, whereText(c)))
            fire(p, "new_contact", c)
        else
            if wasStale then
                WriteEventLog.add(p.coalition, "CONTACT", groupName, string.format("regained, %s, by %s, %s",
                    typeText(c), by, whereText(c)))
            end
            if airspaceBefore ~= c.airspace then
                WriteEventLog.add(p.coalition, "CONTACT", groupName, string.format("entered %s airspace (was %s), %s, %s",
                    c.airspace, airspaceBefore, typeText(c), whereText(c)))
                fire(p, "airspace_changed", c, airspaceBefore)
            end
        end
    end
    local dropped = {}
    for groupName, c in pairs(p.contacts) do
        local unseen = now - c.last_seen
        if unseen >= RADAR_PICTURE.drop_after_s then
            dropped[#dropped + 1] = groupName
        elseif unseen >= RADAR_PICTURE.stale_after_s and c.state == "tracked" then
            c.state = "stale"
            WriteEventLog.add(p.coalition, "CONTACT", groupName, string.format("stale, %s, last seen %d s ago",
                typeText(c), math.floor(unseen)))
            fire(p, "contact_stale", c)
        end
    end
    table.sort(dropped)
    for _, groupName in ipairs(dropped) do
        local c = p.contacts[groupName]
        p.contacts[groupName] = nil
        WriteEventLog.add(p.coalition, "CONTACT", groupName, string.format("dropped, %s, last seen %d s ago",
            typeText(c), math.floor(now - c.last_seen)))
        fire(p, "contact_dropped", c)
    end
end

local function summary(p, now)
    local count, stale, by = 0, 0, { own = 0, contested = 0, enemy = 0 }
    for _, c in pairs(p.contacts) do
        count = count + 1
        by[c.airspace] = (by[c.airspace] or 0) + 1
        if c.state == "stale" then stale = stale + 1 end
    end
    local missiles = 0
    for _ in pairs(p.missiles) do missiles = missiles + 1 end
    local text = string.format("%d contacts (own %d, contested %d, enemy %d; %d stale), %d of %d sensors answered",
        count, by.own, by.contested, by.enemy, stale, p.last_answered, p.last_asked)
    if RADAR_PICTURE.count_missiles then
        text = text .. string.format(", missiles listed since last summary: %d", missiles)
    end
    WriteEventLog.add(p.coalition, "PICTURE", p.label .. " picture", text)
    p.missiles = {}
    p.next_log_s = now + RADAR_PICTURE.log_every_s
end

local function startRound(p)
    p.queue = roundSensors(p)
    p.slice = 0
    p.sightings = {}
    p.asked, p.answered = 0, 0
end

-- One step: poll the next share of this round's sensors; the last step finishes the round.
local function step(p, now)
    local slices = RADAR_PICTURE.poll_slices
    p.slice = p.slice + 1
    local per = math.ceil(#p.queue / slices)
    local from = (p.slice - 1) * per + 1
    for i = from, math.min(#p.queue, from + per - 1) do poll(p, p.queue[i]) end
    if p.slice >= slices then
        finishRound(p, now)
        p.last_asked, p.last_answered = p.asked, p.answered
        if now >= p.next_log_s then summary(p, now) end
        startRound(p)
        fire(p, "picture_updated")
    end
end

local function newPicture(coalitionName)
    local listeners = {}
    for event in pairs(EVENTS) do listeners[event] = {} end
    return {
        coalition = coalitionName, label = coalitionName:upper(),
        ground_sensors = {}, flight_sensors = {}, assets = {},
        contacts = {}, sightings = {}, missiles = {}, tracking_logged = {},
        listeners = listeners, queue = {}, slice = 0,
        asked = 0, answered = 0, last_asked = 0, last_answered = 0, next_log_s = 0,
    }
end

-- Listeners may register before start: the pictures exist from load time.
for _, c in ipairs({ "red", "blue" }) do _pictures[c] = newPicture(c) end

function TrackRadarPicture.start(plan)
    _plan = plan
    local stepS = RADAR_PICTURE.poll_interval_s / RADAR_PICTURE.poll_slices
    for _, coalitionName in ipairs({ "red", "blue" }) do
        local p = _pictures[coalitionName]
        local withoutRadar
        p.ground_sensors, withoutRadar = groundSensors(coalitionName)
        -- what the coalition defends: its held bases and its catalog targets
        p.assets = {}
        for name, b in pairs(plan.territory.bases) do
            if b.side == coalitionName then p.assets[#p.assets + 1] = { name = name, pos = plan.world.airbases[name].pos } end
        end
        for id, t in pairs(plan.target_catalog and plan.target_catalog.targets or {}) do
            if t.coalition == coalitionName and t.pos then p.assets[#p.assets + 1] = { name = id, pos = t.pos } end
        end
        table.sort(p.assets, function(x, y) return x.name < y.name end)
        p.flight_sensors = flightSensors(coalitionName)
        local byKind, kinds = {}, {}
        for _, s in ipairs(p.ground_sensors) do byKind[s.kind] = (byKind[s.kind] or 0) + 1 end
        for kind, n in pairs(byKind) do kinds[#kinds + 1] = string.format("%s %d", kind, n) end
        table.sort(kinds)
        local flights = 0
        for _ in pairs(p.flight_sensors) do flights = flights + 1 end
        Log.info(string.format("%s picture: %d ground sensors (%s), %d skipped without a radar; %d planned flights join while airborne",
            p.label, #p.ground_sensors, table.concat(kinds, ", "), withoutRadar, flights))
        p.next_log_s = timer.getTime() + RADAR_PICTURE.log_every_s
        startRound(p)
        timer.scheduleFunction(function(_, now)
            local ok, err = pcall(step, p, now)
            if not ok then Log.error(string.format("%s picture: step failed: %s", p.label, tostring(err))) end
            return now + stepS
        end, nil, timer.getTime() + stepS)
    end
    Log.info(string.format("--- Radar picture: every sensor asked once per %d s ---", RADAR_PICTURE.poll_interval_s))
end

-- A flight spawned at run time (a scramble) whose radar should feed the picture while
-- airborne; `kind` is a sensor kind (e.g. "scramble").
function TrackRadarPicture.addFlight(coalitionName, id, kind)
    if RADAR_PICTURE.sensor_kinds[kind] then _pictures[coalitionName].flight_sensors[id] = kind end
end

-- ── Calls for other code ────────────────────────────────────────

-- fn(contact, extra) on `event` in `coalition`'s picture: new_contact, airspace_changed
-- (extra = the airspace before), contact_stale, contact_dropped; and picture_updated
-- (no contact) at the end of every round, after the others: scrambles and the
-- behaviour rules run on it.
function TrackRadarPicture.on(coalitionName, event, fn)
    if not EVENTS[event] then error("TrackRadarPicture.on: unknown event " .. tostring(event)) end
    local list = _pictures[coalitionName].listeners[event]
    list[#list + 1] = fn
end

-- The coalition's contacts matching every field in `filter` (e.g. { airspace = "own" }),
-- sorted by group name.
function TrackRadarPicture.contacts(coalitionName, filter)
    local list = {}
    for _, c in pairs(_pictures[coalitionName].contacts) do
        local match = true
        for k, v in pairs(filter or {}) do
            if c[k] ~= v then match = false break end
        end
        if match then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.group < b.group end)
    return list
end

-- The coalition's contacts within radius_m of pos, nearest first.
function TrackRadarPicture.contactsNear(coalitionName, pos, radius_m)
    local list = {}
    for _, c in pairs(_pictures[coalitionName].contacts) do
        if Util.dist(pos, c.pos) <= radius_m then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return Util.dist(pos, a.pos) < Util.dist(pos, b.pos) end)
    return list
end

function TrackRadarPicture.contact(coalitionName, groupName)
    return _pictures[coalitionName].contacts[groupName]
end

-- The coalition's sensors this round: { id, kind }.
function TrackRadarPicture.sensors(coalitionName)
    local list = {}
    for _, s in ipairs(_pictures[coalitionName].queue) do list[#list + 1] = { id = s.id, kind = s.kind } end
    return list
end
