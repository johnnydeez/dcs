-- Consumer part of the controller (control_air_flights.lua): the situation of one watched
-- flight at one check — the facts its directives decide on, from what the coalition
-- knows: the flight's own state (read live), its coalition's radar picture
-- (consumers/track_radar_picture.lua) and the plan. Directives read the situation and
-- never ask DCS themselves, so the costly work (picture searches, ammo, kill-zone
-- geometry) happens at most once per flight per check.
--
-- A situation is a plain table. The basic facts are filled in at once:
--   id, coalition, mission, group, pos { x, y, z } (the lead: its first jet in the air,
--   y = altitude), airborne
-- the others are worked out the first time a directive asks for them:
--   jets                 every airborne jet { unit, name, pos }: kill zones, depth and
--                        threats are asked for each, not the lead alone
--   velocity             { x, y, z } of the lead
--   air_to_air           { count, radar_count, longest_radar } — missiles aboard the flight
--   anti_radiation_missiles  count aboard the flight
--   anti_radiation_missiles_by_jet  count aboard each live jet, by unit name
--   threats              enemy airplanes the picture holds within the warning range of any
--                        jet (and one that just fired at the flight, at any range), nearest
--                        first, each measured from the jet of ours closest to it:
--                        { group, type, range_m, aspect_deg, closing_mps, pos }
--   shot_at              the last report of an enemy firing at the flight (from the
--                        controller's DCS event handler), or false
--   units                every live jet of the flight: { name, pos, airborne }
--   landing_base_pos     { x, z } of its landing base, or false
--   fuel                 every airborne jet's fuel: { name, fraction (of internal fuel;
--                        over 1 with external tanks), km (straight to its landing base) }
--   relief               patrols: the next patrol of its station, on station now
--                        ({ id, km from the race-track }), or false
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

-- Why group `name` is no longer there, for a CONTROL line: "MSN2017_CAP destroyed",
-- "… landed" (its jets despawned after landing), "… down (1 lost, 1 landed)", or "… gone"
-- for a group the scheduler doesn't keep (a player). (2026-10-04 22:39 run: "leash stand
-- down: MSN2017_CAP destroyed" for an F-15C that had landed at Alakurtti.)
function AssessFlightSituations.goneText(name)
    local r = ScheduleAirTaskingOrders.record(name)
    if not r then return name .. " gone" end
    local landed = r.landed + (r.removed or 0)
    if r.lost > 0 and landed == 0 then return name .. " destroyed" end
    if landed > 0 and r.lost == 0 then return name .. " landed" end
    if landed > 0 then return string.format("%s down (%d lost, %d landed)", name, r.lost, landed) end
    return name .. " gone"
end

-- The first live unit of a group: its first airborne one when any jet of it is in the
-- air (a lead still on the ramp or landed isn't where the flight is), else its first.
local function leadOf(g)
    local ok, lead = pcall(function()
        local first
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then
                if u:inAir() then return u end
                first = first or u
            end
        end
        return first
    end)
    return ok and lead or nil
end

-- Every live jet of group g in the air, as { unit, name, pos }.
local function airborneJets(g)
    local list = {}
    pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 and u:inAir() then
                list[#list + 1] = { unit = u, name = u:getName(), pos = u:getPoint() }
            end
        end
    end)
    return list
end

-- How far past the contested airspace pos lies, in metres (0 when not in enemy airspace).
function AssessFlightSituations.enemyDepth(coalition, pos, searchM)
    local a = _plan.airspace
    if DivideAirspace.kindFor(a, pos, coalition) ~= "enemy" then return 0 end
    local _, d = DivideAirspace.nearestFront(a, pos, searchM)
    if not d then return math.huge end
    return math.max(0, d - a.cell_m / 2)
end

-- The enemy medium / long-range SAM site, or base-defense radar SAM (Tor, Pantsir, …;
-- bug 41), whose kill zone the aircraft at pos (y: its altitude) is inside, or nil. The
-- zone is `fraction` of how far it reaches at the aircraft's height above the ground
-- (lib/sam_reach.lua; a base defense its full reach at any height). Never one of
-- `except` (a set of site or group ids). A site out of the fight (its radars destroyed
-- to its success fraction: the launch gate's test, DecideLaunches.outOfTheFight) isn't
-- one, unless `countSilenced`: SEAD flights keep counting every live site, so their
-- attack and go cold stay as they flew (John, 2026-10-04: don't change SEAD attack behavior).
function AssessFlightSituations.enemyKillZone(coalition, pos, fraction, except, countSilenced)
    local height = SamReach.aboveGround(pos, pos.y)
    local p = { x = pos.x, z = pos.z }
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalition and not (except and except[s.id]) and AIR_ROUTING.threat_layers[s.layer]
           and (s.engage_m or 0) > 0
           and Util.dist(p, s.pos) < SamReach.radius(s, height) * fraction
           and AssessFlightSituations.liveGroup(s.id)
           and (countSilenced or not DecideLaunches.outOfTheFight(s.id)) then
            return s.id
        end
    end
    for _, g in ipairs(SamReach.baseDefenses(_plan, coalition)) do
        if not (except and except[g.id]) and Util.dist(p, g.pos) < g.reach_m * fraction
           and AssessFlightSituations.liveGroup(g.id) then
            return g.id
        end
    end
    return nil
end

-- The enemy kill zone (enemyKillZone) any airborne jet of the flight in situation s is
-- inside, and that jet's name; nil when none is. `skip(p)`: a jet at p ({ x, z }) isn't
-- asked. Every jet, not the lead alone (2026-10-04 22:39 run: MSN2043_STRIKE's wingman
-- fought 16 km inside an Ivalo SA-11's ring and died while its lead stayed outside it,
-- and the fight was never broken off).
function AssessFlightSituations.flightKillZone(s, fraction, except, countSilenced, skip)
    for _, j in ipairs(s.jets) do
        if not (skip and skip({ x = j.pos.x, z = j.pos.z })) then
            local site = AssessFlightSituations.enemyKillZone(s.coalition, j.pos, fraction, except, countSilenced)
            if site then return site, j.name end
        end
    end
    return nil
end

-- How far past the contested airspace the deepest airborne jet of the flight is, m.
function AssessFlightSituations.flightEnemyDepth(s, searchM)
    local deepest = 0
    for _, j in ipairs(s.jets) do
        deepest = math.max(deepest, AssessFlightSituations.enemyDepth(s.coalition, { x = j.pos.x, z = j.pos.z }, searchM))
    end
    return deepest
end

-- Whether a live jet of the flight is still on the ground before its takeoff (a wingman
-- in the taxi queue): the flight isn't down while one is (bug 48).
function AssessFlightSituations.waitingToTakeOff(s)
    for _, u in ipairs(s.units) do
        if not u.airborne and not ScheduleAirTaskingOrders.tookOff(u.name) then return true end
    end
    return false
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

-- Anti-radiation missiles aboard each live jet of the flight: { [unit name] = count }.
FACTS.anti_radiation_missiles_by_jet = function(s)
    local byJet = {}
    pcall(function()
        for _, u in ipairs(s.group:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then
                local n = 0
                for _, a in ipairs(u:getAmmo() or {}) do
                    local d = a.desc
                    if d and d.category == Weapon.Category.MISSILE and d.guidance == Weapon.GuidanceType.RADAR_PASSIVE then
                        n = n + (a.count or 0)
                    end
                end
                byJet[u:getName()] = n
            end
        end
    end)
    return byJet
end

local function headingDeg(v)
    local h = math.deg(math.atan2(v.z, v.x))
    return h < 0 and h + 360 or h
end

local function angleBetween(a, b)
    local d = math.abs(a - b) % 360
    return d > 180 and 360 - d or d
end

-- The live geometry of enemy group `name` against the flight, or nil: the closest pair
-- of an airborne jet of the flight and a live jet of the group (an enemy wingman, or our
-- own wingman far from its lead, counts as much as the leads).
local function geometry(s, name, typeName)
    local g = AssessFlightSituations.liveGroup(name)
    if not g then return nil end
    local theirs = airborneJets(g)
    if #theirs == 0 then
        local lead = leadOf(g)
        local ok, p = pcall(function() return lead:getPoint() end)
        if ok and p then theirs[1] = { unit = lead, pos = p } end
    end
    local best
    for _, t in ipairs(theirs) do
        local okV, v = pcall(function() return t.unit:getVelocity() end)
        for _, j in ipairs(s.jets) do
            local okMy, myV = pcall(function() return j.unit:getVelocity() end)
            if okV and v and okMy and myV then
                local p, me = t.pos, j.pos
                local dx, dz = me.x - p.x, me.z - p.z
                local range = math.sqrt(dx * dx + dz * dz)
                if not best or range < best.range_m then
                    local ux, uz = dx / math.max(range, 1), dz / math.max(range, 1)   -- from the threat toward the jet
                    local closing = (v.x - myV.x) * ux + (v.z - myV.z) * uz
                    local speed = math.sqrt(v.x * v.x + v.z * v.z)
                    local aspect = speed > 1 and angleBetween(headingDeg(v), headingDeg({ x = ux, z = uz })) or 180
                    best = { group = name, type = typeName, range_m = range, aspect_deg = aspect, closing_mps = closing, pos = p }
                end
            end
        end
    end
    return best
end

-- Enemy airplanes the coalition's picture tracks within the warning range of any
-- airborne jet of the flight, with their live geometry against the flight, nearest first;
-- plus the enemy that fired at the flight in the last shot_memory_s, at any range (the
-- shot gives it away).
FACTS.threats = function(s)
    local lookM = AIR_CONTROL.self_defence.warning_range_km * 1000
    local list, seen = {}, {}
    local spread = 0
    for _, j in ipairs(s.jets) do spread = math.max(spread, Util.dist({ x = j.pos.x, z = j.pos.z }, { x = s.pos.x, z = s.pos.z })) end
    for _, c in ipairs(TrackRadarPicture.contactsNear(s.coalition, { x = s.pos.x, z = s.pos.z }, lookM + 20000 + spread)) do
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

-- How many of the flight's own air-to-air missiles are still flying (the controller's
-- DCS event handler keeps each one the flight fires; spent ones are dropped here).
FACTS.own_missiles_in_flight = function(s)
    local list = s.watch.reports.own_missiles
    if not list then return 0 end
    local flying = {}
    for _, weapon in ipairs(list) do
        local ok, exists = pcall(function() return weapon:isExist() end)
        if ok and exists then flying[#flying + 1] = weapon end
    end
    s.watch.reports.own_missiles = flying
    return #flying
end

FACTS.shot_at = function(s)
    local r = s.watch.reports.shot_at
    if r and timer.getTime() - r.time <= AIR_CONTROL.self_defence.shot_memory_s then return r end
    return false
end

-- Every live jet of the flight in the air, { unit, name, pos }; the lead alone when none
-- is. The kill zones, the threats and the leash ask each one.
FACTS.jets = function(s)
    local list = airborneJets(s.group)
    if #list == 0 then list[1] = { unit = s.lead, name = s.lead:getName(), pos = s.pos } end
    return list
end

-- Every live jet of the flight: { name, pos, airborne }.
FACTS.units = function(s)
    local list = {}
    pcall(function()
        for _, u in ipairs(s.group:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then
                list[#list + 1] = { name = u:getName(), pos = u:getPoint(), airborne = u:inAir() }
            end
        end
    end)
    return list
end

-- Every airborne jet's fuel and how far it is from its landing base.
FACTS.fuel = function(s)
    local list, base = {}, s.landing_base_pos
    for _, j in ipairs(s.jets) do
        local ok, f = pcall(function() return j.unit:getFuel() end)
        if ok and f then
            list[#list + 1] = { name = j.name, fraction = f, km = base and Util.dist(j.pos, base) / 1000 or 0 }
        end
    end
    return list
end

-- Where the flight lands: { x, z } of its landing base (from the plan), or false.
FACTS.landing_base_pos = function(s)
    local ab = _plan.world.airbases[s.mission.landing_base]
    return ab and { x = ab.pos.x, z = ab.pos.z } or false
end

local function distanceToSegment(p, a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local len2 = dx * dx + dz * dz
    local t = len2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / len2)) or 0
    return Util.dist(p, { x = a.x + t * dx, z = a.z + t * dz })
end

-- A patrol's relief: the next patrol of its station (a later planned start) that is in
-- the air, on its task and within handover.on_station_km of the race-track, as
-- { id, km }; or false.
FACTS.relief = function(s)
    local m = s.mission
    local a = m.attack
    if not (m.station and a and a.station) then return false end
    local e1, e2 = { x = a.station[1], z = a.station[2] }, { x = a.station[3], z = a.station[4] }
    local limit = AIR_CONTROL.handover.on_station_km * 1000
    for _, w in ipairs(ControlAirFlights.watchedFlights()) do
        local other = w.mission
        if other.station == m.station and other.id ~= m.id and other.start_s > m.start_s
           and w.state == "on_task" then
            local g = AssessFlightSituations.liveGroup(other.id)
            local lead = g and leadOf(g)
            local ok, p, air = pcall(function() return lead:getPoint(), lead:inAir() end)
            if ok and p and air then
                local d = distanceToSegment(p, e1, e2)
                if d <= limit then return { id = other.id, km = d / 1000 } end
            end
        end
    end
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
