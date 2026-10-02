-- Consumer part of the controller (control_air_flights.lua): the situation of one watched
-- flight at one check — the facts its directives decide on, from what the coalition
-- knows: the flight's own state (read live), its coalition's radar picture
-- (consumers/track_radar_picture.lua) and the plan. Directives read the situation and
-- never ask DCS themselves, so the costly work (picture searches, ammo, kill-zone
-- geometry) happens at most once per flight per check.
--
-- A situation is a plain table. The basic facts are filled in at once:
--   id, coalition, mission, group, pos { x, y, z } (the lead, y = altitude), airborne
-- the others are worked out the first time a directive asks for them:
--   velocity             { x, y, z } of the lead
--   air_to_air           { count, radar_count, longest_radar } — missiles aboard the flight
--   anti_radiation_missiles  count aboard the flight
--   threats              enemy airplanes the picture holds within the warning range (and
--                        one that just fired at the flight, at any range), nearest first:
--                        { group, type, range_m, aspect_deg, closing_mps, pos }
--   shot_at              the last report of an enemy firing at the flight (from the
--                        controller's DCS event handler), or false
-- Fair-knowledge rule (as the radar picture's): an enemy group's exact position and
-- motion are read live only once the picture holds it.
-- Reads the plan; writes nothing back to it.

AssessFlightSituations = {}

local _plan

-- ── helpers other parts of the controller share ─────────────────

function AssessFlightSituations.liveGroup(name)
    local g = Group.getByName(name)
    local ok, live = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then return true end
        end
        return false
    end)
    return ok and live and g or nil
end

-- The first live unit of a group.
local function leadOf(g)
    local ok, lead = pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then return u end
        end
    end)
    return ok and lead or nil
end

-- How far past the contested airspace pos lies, in metres (0 when not in enemy airspace).
function AssessFlightSituations.enemyDepth(coalition, pos, searchM)
    local a = _plan.airspace
    if DivideAirspace.kindFor(a, pos, coalition) ~= "enemy" then return 0 end
    local _, d = DivideAirspace.nearestFront(a, pos, searchM)
    if not d then return math.huge end
    return math.max(0, d - a.cell_m / 2)
end

-- The enemy medium / long-range SAM site whose kill zone the aircraft at pos (y: its
-- altitude) is inside, or nil. The zone is `fraction` of how far the site reaches at
-- that altitude (lib/sam_reach.lua). Never one of `except` (a set of site ids).
function AssessFlightSituations.enemyKillZone(coalition, pos, fraction, except)
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalition and not (except and except[s.id]) and AIR_ROUTING.threat_layers[s.layer]
           and (s.engage_m or 0) > 0
           and Util.dist({ x = pos.x, z = pos.z }, s.pos) < SamReach.radius(s, pos.y) * fraction
           and AssessFlightSituations.liveGroup(s.id) then
            return s.id
        end
    end
    return nil
end

-- The SAM sites a flight may be inside on purpose: its own target site and the rings
-- its planned route passes through (route_threats), as a set.
function AssessFlightSituations.acceptedRings(m)
    local set = {}
    local a = m.attack or {}
    if a.kind == "harm_salvo" and a.groups and a.groups[1] then set[a.groups[1]] = true end
    for _, id in ipairs(m.route_threats or {}) do set[id] = true end
    return set
end

-- ── facts worked out on demand ──────────────────────────────────

local FACTS = {}

FACTS.velocity = function(s)
    local ok, v = pcall(function() return s.lead:getVelocity() end)
    return ok and v or { x = 0, y = 0, z = 0 }
end

local function isRadarGuided(d)
    local G = Weapon.GuidanceType
    return d.guidance == (G.RADAR_ACTIVE or 3) or d.guidance == (G.RADAR_SEMI_ACTIVE or 4)
end

-- Air-to-air missiles aboard every live jet of the flight: all of them, the radar-guided
-- ones (what lets a flight fight a fighter; infrared ones alone don't, John), and the
-- name of the longest-reaching radar missile (DCS's rangeMaxAltMax).
FACTS.air_to_air = function(s)
    local count, radar, bestM, longest = 0, 0, -1, nil
    pcall(function()
        for _, u in ipairs(s.group:getUnits() or {}) do
            if u:isExist() then
                for _, a in ipairs(u:getAmmo() or {}) do
                    local d = a.desc
                    if d and d.category == Weapon.Category.MISSILE and d.missileCategory == Weapon.MissileCategory.AAM
                       and (a.count or 0) > 0 then
                        count = count + a.count
                        if isRadarGuided(d) then
                            radar = radar + a.count
                            local rangeM = type(d.rangeMaxAltMax) == "number" and d.rangeMaxAltMax or 0
                            if rangeM > bestM then bestM, longest = rangeM, d.displayName or d.typeName end
                        end
                    end
                end
            end
        end
    end)
    return { count = count, radar_count = radar, longest_radar = longest }
end

-- Anti-radiation missiles aboard the flight now (missiles with passive radar guidance).
FACTS.anti_radiation_missiles = function(s)
    local n = 0
    pcall(function()
        for _, u in ipairs(s.group:getUnits() or {}) do
            for _, a in ipairs(u:getAmmo() or {}) do
                local d = a.desc
                if d and d.category == Weapon.Category.MISSILE and d.guidance == Weapon.GuidanceType.RADAR_PASSIVE then
                    n = n + (a.count or 0)
                end
            end
        end
    end)
    return n
end

local function headingDeg(v)
    local h = math.deg(math.atan2(v.z, v.x))
    return h < 0 and h + 360 or h
end

local function angleBetween(a, b)
    local d = math.abs(a - b) % 360
    return d > 180 and 360 - d or d
end

-- The live geometry of enemy group `name` against the flight, or nil.
local function geometry(s, name, typeName)
    local g = AssessFlightSituations.liveGroup(name)
    local lead = g and leadOf(g)
    local ok, p, v = pcall(function() return lead:getPoint(), lead:getVelocity() end)
    if not (ok and p and v) then return nil end
    local me, myV = s.pos, s.velocity
    local dx, dz = me.x - p.x, me.z - p.z
    local range = math.sqrt(dx * dx + dz * dz)
    local ux, uz = dx / math.max(range, 1), dz / math.max(range, 1)   -- from the threat toward the flight
    local closing = (v.x - myV.x) * ux + (v.z - myV.z) * uz
    local speed = math.sqrt(v.x * v.x + v.z * v.z)
    local aspect = speed > 1 and angleBetween(headingDeg(v), headingDeg({ x = ux, z = uz })) or 180
    return { group = name, type = typeName, range_m = range, aspect_deg = aspect, closing_mps = closing, pos = p }
end

-- Enemy airplanes the coalition's picture tracks within the warning range, with their
-- live geometry against the flight, nearest first; plus the enemy that fired at the
-- flight in the last shot_memory_s, at any range (the shot gives it away).
FACTS.threats = function(s)
    local lookM = AIR_CONTROL.self_defence.warning_range_km * 1000
    local list, seen = {}, {}
    for _, c in ipairs(TrackRadarPicture.contactsNear(s.coalition, { x = s.pos.x, z = s.pos.z }, lookM + 20000)) do
        if c.category == "airplane" and c.state == "tracked" then
            local t = geometry(s, c.group, c.type)
            if t and t.range_m <= lookM then
                list[#list + 1] = t
                seen[c.group] = true
            end
        end
    end
    local shooter = s.shot_at and s.shot_at.shooter_group
    if shooter and not seen[shooter] then
        local contact = TrackRadarPicture.contact(s.coalition, shooter)
        local t = geometry(s, shooter, contact and contact.type)
        if t then list[#list + 1] = t end
    end
    table.sort(list, function(a, b) return a.range_m < b.range_m end)
    return list
end

FACTS.shot_at = function(s)
    local r = s.watch.reports.shot_at
    if r and timer.getTime() - r.time <= AIR_CONTROL.self_defence.shot_memory_s then return r end
    return false
end

-- ── building one ────────────────────────────────────────────────

local LAZY = {
    __index = function(s, key)
        local fact = FACTS[key]
        if not fact then return nil end
        local value = fact(s)
        rawset(s, key, value)
        return value
    end,
}

-- The situation of watched flight w (live group g), or nil when it has no live unit to
-- read.
function AssessFlightSituations.build(w, g)
    local lead = leadOf(g)
    if not lead then return nil end
    local ok, pos, airborne = pcall(function()
        local inAir = false
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:inAir() then inAir = true end
        end
        return lead:getPoint(), inAir
    end)
    if not (ok and pos) then return nil end
    local m = w.mission
    return setmetatable({ id = m.id, coalition = m.coalition, mission = m, watch = w, group = g, lead = lead,
                          pos = pos, airborne = airborne }, LAZY)
end

function AssessFlightSituations.start(plan)
    _plan = plan
end
