-- Watch: where each bomb and air-to-ground missile from an aircraft came down, and what
-- it did there, as one IMPACT line in the event log (John, 2026-10-06: after the 00:16 run
-- nobody could tell how close his GBU-38s fell to the Kalevala Mi-8, or how hurt it was;
-- "the event log should have better information so we don't have to guess").
--
-- Each weapon is followed from its SHOT until it no longer exists (every
-- EVENT_LOG.impact_every_s); where it hit is its last position carried on along its
-- velocity to the ground. The units and static objects around that point are read twice:
-- the moment it hits (their life before) and impact_settle_s later (after the blast), so a
-- line says what each was left with, or that it was destroyed:
--
--   IMPACT  f16_ivalo  GBU_38 from f16_ivalo (player Snake): hit the ground at 35W NQ 12345 67890,
--                      8 m NE of TGT_KALE_parked_aircraft_1_static_1 (Mi-8MT, life 100 % → 92 %);
--                      34 m SW of DEF_KALE_towed_anti_aircraft_guns_1_2 (ZU-23 Emplacement, destroyed)
--   IMPACT  MSN2024_SEAD_1  AGM_88 from MSN2024_SEAD_1: gone in the air, 2,300 m above the ground,
--                      6 km from SAM_SODA_SA10_1_3 (shot down, or burst)
--
-- The grid reference is the F10 map's (MGRS), to check against it. Reads only.

WatchWeaponImpacts = {}

local _following = {}   -- { weapon, name (shooter), player, type, last = { p, v, t }, aimed_at }
local _count = 0

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local COMPASS_POINTS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- The compass point of the line from a to b (grid).
local function compassFrom(a, b)
    local deg = math.deg(math.atan2(b.z - a.z, b.x - a.x))
    return COMPASS_POINTS[math.floor(((deg % 360) + 360) % 360 / 45 + 0.5) % 8 + 1]
end

local function metres(m)
    if m >= 2000 then return string.format("%.0f km", m / 1000) end
    return string.format("%s m", Util.thousands(math.floor(m + 0.5)))
end

-- "35W NQ 12345 67890", the F10 map's grid reference, or "x, z" if DCS can't convert.
local function gridText(p)
    return safe(function()
        local lat, lon = coord.LOtoLL({ x = p.x, y = p.y or 0, z = p.z })
        local g = coord.LLtoMGRS(lat, lon)
        return string.format("%s %s %05d %05d", g.UTMZone, g.MGRSDigraph, math.floor(g.Easting), math.floor(g.Northing))
    end) or string.format("x %.0f, z %.0f", p.x, p.z)
end

-- A weapon worth following: a bomb, or a missile that isn't air-to-air or a SAM's, from an
-- aircraft. Rockets and shells are left out (too many, and the HIT lines cover them).
local function followed(e)
    local d = safe(function() return e.weapon:getDesc() end)
    if not d then return false end
    local shooterCategory = safe(function() return e.initiator:getDesc().category end)
    if shooterCategory ~= Unit.Category.AIRPLANE and shooterCategory ~= Unit.Category.HELICOPTER then return false end
    if d.category == Weapon.Category.BOMB then return true end
    return d.category == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM
        and d.missileCategory ~= Weapon.MissileCategory.SAM
end

-- An object's life as a fraction of its full life (0 when gone), or nil when DCS won't say.
local function lifeOf(o)
    return safe(function()
        if not o:isExist() then return 0 end
        local life = o:getLife()
        local full = (o.getLife0 and o:getLife0()) or (o:getDesc() or {}).life
        if not life or not full or full <= 0 then return nil end
        return math.max(0, math.min(1, life / full))
    end)
end

local function percent(f) return f and string.format("%d %%", math.floor(f * 100 + 0.5)) or "?" end

-- Units and static objects within `radius` of p: { object, name, type, dist, life }, nearest first.
local function around(p, radius)
    local out = {}
    local volume = { id = world.VolumeType.SPHERE, params = { point = { x = p.x, y = p.y, z = p.z }, radius = radius } }
    pcall(world.searchObjects, { Object.Category.UNIT, Object.Category.STATIC }, volume, function(o)
        local name = safe(function() return o:getName() end)
        local op = safe(function() return o:getPoint() end)
        if type(name) == "string" and op then
            out[#out + 1] = { object = o, name = name, type = safe(function() return o:getTypeName() end) or "?",
                              pos = op, dist = Util.dist({ x = op.x, z = op.z }, { x = p.x, z = p.z }), life = lifeOf(o) }
        end
        return true
    end)
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- Where the weapon came down: its last position carried on along its velocity until it
-- meets the ground (never more than two follow steps on), and its height above the ground.
local function impactPoint(last)
    local p, v = last.p, last.v
    local ground = safe(function() return land.getHeight({ x = p.x, y = p.z }) end) or 0
    local above = p.y - ground
    local dt = 0
    if v.y < -1 then dt = math.min(above / -v.y, 2 * EVENT_LOG.impact_every_s) end
    local q = { x = p.x + v.x * dt, y = p.y + v.y * dt, z = p.z + v.z * dt }
    local groundThere = safe(function() return land.getHeight({ x = q.x, y = q.z }) end) or ground
    return q, q.y - groundThere
end

local function report(f, at, height, before)
    local R = EVENT_LOG
    local head = string.format("%s from %s%s", f.type, f.name, f.player and (" (player " .. f.player .. ")") or "")
    if height > R.impact_air_burst_m then
        -- gone well above the ground: shot down, or a dispenser opening
        local aimed = ""
        if f.aimed_at then
            local tp = safe(function() return f.aimed_at:getPoint() end)
            local tn = safe(function() return f.aimed_at:getName() end)
            if tp and type(tn) == "string" then aimed = string.format(", %s from %s", metres(Util.dist(at, tp)), tn) end
        end
        EventLog.add(f.side, "IMPACT", f.name, string.format("%s: gone in the air at %s, %s above the ground%s (shot down, or burst)",
            head, gridText(at), metres(height), aimed))
        return
    end
    local parts = {}
    local near = {}
    -- measured from where it really hit (the list was read on its way down)
    for _, o in ipairs(before) do o.dist = Util.dist({ x = o.pos.x, z = o.pos.z }, { x = at.x, z = at.z }) end
    table.sort(before, function(a, b) return a.dist < b.dist end)
    for _, o in ipairs(before) do
        if o.dist <= R.impact_near_m and #near < R.impact_list_max then near[#near + 1] = o end
    end
    for _, o in ipairs(near) do
        local after = lifeOf(o.object) or 0
        local state
        if after <= 0 then
            state = "destroyed"
        elseif o.life and after < o.life - 0.005 then
            state = string.format("life %s → %s", percent(o.life), percent(after))
        else
            state = string.format("life %s, no damage", percent(after))
        end
        parts[#parts + 1] = string.format("%s %s of %s (%s, %s)", metres(o.dist), compassFrom(o.pos, at), o.name, o.type, state)
    end
    local text
    if #parts > 0 then
        text = table.concat(parts, "; ")
    else
        local nearest = before[1]
        text = string.format("nothing within %s", metres(R.impact_near_m))
        if nearest then
            text = text .. string.format("; nearest %s %s of %s (%s, life %s)", metres(nearest.dist), compassFrom(nearest.pos, at),
                nearest.name, nearest.type, percent(lifeOf(nearest.object)))
        end
    end
    EventLog.add(f.side, "IMPACT", f.name, string.format("%s: hit the ground at %s, %s", head, gridText(at), text))
end

local function landed(f)
    local at, height = impactPoint(f.last)
    -- what is there before the blast (read on its way down: DCS applies the damage in the
    -- frame the weapon goes, so a read now may already hold it); read again after it settles
    local before = {}
    if height <= EVENT_LOG.impact_air_burst_m then before = f.before or around(at, EVENT_LOG.impact_search_m) end
    timer.scheduleFunction(function()
        local ok, err = pcall(report, f, at, height, before)
        if not ok then Log.warn("weapon impacts: " .. tostring(err)) end
        return nil
    end, nil, timer.getTime() + EVENT_LOG.impact_settle_s)
end

local function follow()
    local now = timer.getTime()
    local keep = {}
    for _, f in ipairs(_following) do
        local p = safe(function() return f.weapon:isExist() and f.weapon:getPoint() end)
        if p then
            f.last = { p = p, v = safe(function() return f.weapon:getVelocity() end) or f.last.v, t = now }
            -- about to come down (within a second, or low): what is around where it will
            -- hit, with each object's life before the blast
            if not f.before then
                local ground = safe(function() return land.getHeight({ x = p.x, y = p.z }) end) or 0
                local above, down = p.y - ground, -f.last.v.y
                if above <= EVENT_LOG.impact_snapshot_m or (down > 1 and above / down <= EVENT_LOG.impact_snapshot_s) then
                    local v = f.last.v
                    local t = down > 1 and math.min(above / down, EVENT_LOG.impact_snapshot_s) or 0
                    f.before = around({ x = p.x + v.x * t, y = ground, z = p.z + v.z * t }, EVENT_LOG.impact_search_m)
                end
            end
            if now - f.fired_at < EVENT_LOG.impact_max_flight_s then keep[#keep + 1] = f end
        else
            local ok, err = pcall(landed, f)
            if not ok then Log.warn("weapon impacts: " .. tostring(err)) end
        end
    end
    _following = keep
    _count = #keep
end

local handler = {}
function handler:onEvent(e)
    if e.id ~= world.event.S_EVENT_SHOT or not e.weapon or not e.initiator then return end
    local ok, err = pcall(function()
        if not followed(e) or _count >= EVENT_LOG.impact_follow_max then return end
        local p = e.weapon:getPoint()
        local name = e.initiator:getName()
        _following[#_following + 1] = {
            weapon = e.weapon, name = name, side = e.initiator:getCoalition(),
            player = safe(function() return e.initiator:getPlayerName() end),
            type = safe(function() return e.weapon:getTypeName() end) or "?",
            aimed_at = safe(function() return e.weapon:getTarget() end),
            fired_at = timer.getTime(), last = { p = p, v = e.weapon:getVelocity(), t = timer.getTime() },
        }
        _count = #_following
    end)
    if not ok then Log.warn("weapon impacts: shot: " .. tostring(err)) end
end

function WatchWeaponImpacts.start()
    RecordDcsEvents.on(function(fact) if fact.raw then handler:onEvent(fact.raw) end end)
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(follow)
        if not ok then Log.error("weapon impacts: round failed: " .. tostring(err)) end
        return now + EVENT_LOG.impact_every_s
    end, nil, timer.getTime() + EVENT_LOG.impact_every_s)
    Log.info("--- Weapon impacts: bombs and air-to-ground missiles from aircraft followed to the ground (event log: IMPACT) ---")
end
