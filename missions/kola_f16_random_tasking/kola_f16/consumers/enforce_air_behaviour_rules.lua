-- Consumer: the rules the script enforces on AI flights after they launch, in one place
-- (plan.md backlog "AI behaviour rules, one place"; roadmap.md item 2). A module that
-- launches a flight it wants watched registers it here with a rule; every radar-picture
-- round (picture_updated) each watched flight's rule is checked, and when it says so the
-- flight is sent home (a new route from where it is to its base, returning fire only)
-- or, still on the ramp, stood down. Once sent home a flight stays sent home and is no
-- longer watched; the scheduler removes it after landing as usual.
--
-- Rules (settings in data/air_behaviour_rules.lua):
--   suppression  SEAD flights (John, 2026-10-01: dump the HARMs from a distance, go cold):
--           home, by the way back the plan gave it, once every anti-radiation missile
--           is gone; when it presses more than press_km past its launch point toward its
--           site; inside the kill zone of another SAM site; or still on the attack
--           attack_time_s after its time at the launch point
--   leash   scrambles: home when every group of its raid is dead, dropped from the radar
--           picture or back over its own airspace heading away (a raid that only dips
--           over its own airspace on its way in is still a raid), or when the scramble itself is too
--           deep in enemy airspace or inside an enemy kill zone. Stood down on the ramp
--           when the raid is gone before it takes off.
-- New rules are one more entry in RULES: a check that returns what to do and why.
--
-- Event log lines (consumers/write_event_log.lua):
--   LEASH  RED  MSN5901_SCRAM  "going home: MSN2014_DEAD back over its own airspace, heading away (MiG-31 at 31,000 ft,
--                              contested airspace)"
--   LEASH  RED  MSN5901_SCRAM  "stood down on the ramp: MSN2014_DEAD destroyed"
-- Reads the plan; writes nothing back to it. Which flights are watched is runtime state.

EnforceAirBehaviourRules = {}

local FEET_PER_METRE = 3.28084
local ROE = { weapons_free = 0, open_fire = 2, return_fire = 3, weapons_hold = 4 }   -- AI.Option.Air.val.ROE
local OPTION_ROE = 0

local _plan
local _watched = {}   -- flight id → { mission, rule, targets, airborne_once }

-- ── what a rule can ask ─────────────────────────────────────────

local function liveGroup(name)
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

-- The flight's lead position (first live unit) and whether any of it is in the air.
local function flightState(g)
    local ok, pos, air = pcall(function()
        local first, inAir
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() then
                first = first or u:getPoint()
                if u:inAir() then inAir = true end
            end
        end
        return first, inAir
    end)
    if not ok then return nil, false end
    return pos, air == true
end

-- How far past the contested airspace pos lies, in metres (0 when not in enemy airspace).
local function enemyDepth(coalition, pos, searchM)
    local a = _plan.airspace
    if DivideAirspace.kindFor(a, pos, coalition) ~= "enemy" then return 0 end
    local _, d = DivideAirspace.nearestFront(a, pos, searchM)
    if not d then return math.huge end
    return math.max(0, d - a.cell_m / 2)
end

-- The enemy medium / long-range SAM site whose kill zone the aircraft at pos (y: its
-- altitude) is inside, or nil. The zone is `fraction` of how far the site reaches at
-- that altitude (lib/sam_reach.lua). Never one of `except` (a set of site ids).
local function enemyKillZone(coalition, pos, fraction, except)
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalition and not (except and except[s.id]) and AIR_ROUTING.threat_layers[s.layer]
           and (s.engage_m or 0) > 0
           and Util.dist({ x = pos.x, z = pos.z }, s.pos) < SamReach.radius(s, pos.y) * fraction and liveGroup(s.id) then
            return s.id
        end
    end
    return nil
end

-- ── rules ───────────────────────────────────────────────────────

local RULES = {}

-- Returns "home" | "stand_down" | nil, and the reason.
RULES.leash = function(w, pos, airborne)
    local L = AIR_BEHAVIOUR_RULES.leash
    local c = w.mission.coalition
    -- the raid: any group still alive, in the picture and not back over its own airspace?
    local why
    for _, name in ipairs(w.targets) do
        if liveGroup(name) then
            local contact = TrackRadarPicture.contact(c, name)
            if contact and not (contact.airspace == "enemy" and not contact.inbound) then
                why = nil
                break
            end
            why = why or (contact and (name .. " back over its own airspace, heading away")
                                   or (name .. " lost from the radar picture"))
        else
            why = why or (name .. " destroyed")
        end
    end
    local raidGone = why ~= nil
    if not airborne then
        if raidGone and not w.airborne_once then return "stand_down", why end
        return nil
    end
    if raidGone then return "home", why end
    local depth = enemyDepth(c, { x = pos.x, z = pos.z }, L.front_search_km * 1000)
    if depth > L.enemy_airspace_km * 1000 then
        return "home", depth == math.huge and "deep in enemy airspace"
            or string.format("%.0f km into enemy airspace", depth / 1000)
    end
    local site = enemyKillZone(c, pos, L.killzone_fraction)
    if site then return "home", "inside the kill zone of " .. site end
    return nil
end

-- Anti-radiation missiles aboard the flight now (missiles with passive radar guidance).
local function armsAboard(g)
    local n = 0
    pcall(function()
        for _, u in ipairs(g:getUnits() or {}) do
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

RULES.suppression = function(w, pos, airborne, g)
    if not airborne then return nil end
    local R = AIR_BEHAVIOUR_RULES.suppression
    local m = w.mission
    local a = m.attack or {}
    local arms = armsAboard(g)
    if not w.arms_at_start then w.arms_at_start = arms end
    if w.arms_at_start > 0 and arms == 0 then return "home", "every anti-radiation missile fired" end
    if a.site and a.launch then
        local p = { x = pos.x, z = pos.z }
        local pressed = Util.dist(a.launch, a.site) - Util.dist(p, a.site)
        if pressed > R.press_km * 1000 then
            return "home", string.format("%.0f km past its launch point toward %s", pressed / 1000, a.groups and a.groups[1] or "its site")
        end
    end
    -- not its own site, nor a ring its planned route was routed through on purpose
    if not w.accepted then
        w.accepted = {}
        if a.groups and a.groups[1] then w.accepted[a.groups[1]] = true end
        for _, id in ipairs(m.route_threats or {}) do w.accepted[id] = true end
    end
    local other = enemyKillZone(m.coalition, pos, R.killzone_fraction, w.accepted)
    if other then return "home", "inside the kill zone of " .. other end
    if m.tot_s and timer.getTime() > m.tot_s + R.attack_time_s then
        return "home", string.format("still on the attack %d min after its time at the launch point", math.floor(R.attack_time_s / 60))
    end
    return nil
end

-- ── actions ─────────────────────────────────────────────────────

local function where(w, pos)
    return string.format("%s at %s ft, %s airspace", w.mission.aircraft_type, Util.thousands(pos.y * FEET_PER_METRE),
        DivideAirspace.kindFor(_plan.airspace, { x = pos.x, z = pos.z }, w.mission.coalition))
end

local function goHome(w, g, pos)
    local m = w.mission
    local base = Airbase.getByName(m.landing_base)
    if not base then
        Log.warn(string.format("%s leash: landing base %s not found — left on its task", m.id, m.landing_base))
        return
    end
    local bp = base:getPoint()
    local p = AIRCRAFT_PROFILE[m.aircraft_type]
    local speed = p and p.cruise_speed_mps or 230
    local function point(x, z, alt, v)
        return { x = x, y = z, alt = alt, alt_type = "BARO", speed = v or speed, speed_locked = true,
                 type = "Turning Point", action = "Turning Point", ETA = 0, ETA_locked = false,
                 task = { id = "ComboTask", params = { tasks = {} } } }
    end
    local points = { point(pos.x, pos.z, pos.y) }
    -- a SEAD flight turns around where it is and goes back the way it came (around the
    -- other SAMs), not straight home: before its launch point, its route out flown
    -- backwards from the nearest point behind it; from the launch point on, its planned
    -- way back
    if w.rule == "suppression" and m.route then
        local route, launchAt, nearest = m.route, nil, nil
        for i, r in ipairs(route) do
            if r.kind == "target" then launchAt = i end
            if i > 1 and i < #route and (not nearest or Util.dist(pos, r) < Util.dist(pos, route[nearest])) then nearest = i end
        end
        if nearest and launchAt and nearest >= launchAt then
            for i = nearest + 1, #route - 1 do points[#points + 1] = point(route[i].x, route[i].z, route[i].alt_m, route[i].speed_mps) end
        elseif nearest then
            for i = nearest - 1, 2, -1 do points[#points + 1] = point(route[i].x, route[i].z, route[i].alt_m) end
        end
    end
    points[#points + 1] = { x = bp.x, y = bp.z, alt = bp.y, alt_type = "BARO", speed = speed, speed_locked = true,
          type = "Land", action = "Landing", airdromeId = base:getID(), ETA = 0, ETA_locked = false,
          task = { id = "ComboTask", params = { tasks = {} } } }
    local ok, err = pcall(function()
        local ctl = g:getController()
        ctl:setTask({ id = "Mission", params = { airborne = true, route = { points = points } } })
        ctl:setOption(OPTION_ROE, ROE[AIR_BEHAVIOUR_RULES.going_home_rules_of_engagement])
    end)
    if not ok then Log.warn(string.format("%s leash: sending it home failed: %s", m.id, tostring(err))) end
end

local function check(coalition)
    local ids = {}
    for id, w in pairs(_watched) do
        if w.mission.coalition == coalition then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local w = _watched[id]
        local g = liveGroup(id)
        if not g then
            _watched[id] = nil   -- shot down or gone: the scheduler has logged it
        else
            local pos, airborne = flightState(g)
            if pos then
                if airborne then w.airborne_once = true end
                if w.airborne_once and not airborne then
                    _watched[id] = nil   -- landed
                else
                    local action, why = RULES[w.rule](w, pos, airborne, g)
                    if action == "home" then
                        WriteEventLog.add(coalition, w.rule:upper(), id, string.format("going home: %s (%s)", why, where(w, pos)))
                        goHome(w, g, pos)
                        _watched[id] = nil
                    elseif action == "stand_down" then
                        WriteEventLog.add(coalition, w.rule:upper(), id, "stood down on the ramp: " .. why)
                        pcall(function() g:destroy() end)
                        _watched[id] = nil
                        -- it never flew: its jet goes back on alert, and the end summary says so
                        RunScrambles.stoodDown(id)
                        ScheduleAirTaskingOrders.stoodDown(id)
                    end
                end
            end
        end
    end
end

-- ── calls for other code ────────────────────────────────────────

-- Watch a launched flight (a plan-shaped mission table) under `rule`; params.targets are
-- the enemy group names it was sent after (leash).
function EnforceAirBehaviourRules.watch(m, rule, params)
    if not RULES[rule] then error("EnforceAirBehaviourRules.watch: unknown rule " .. tostring(rule)) end
    _watched[m.id] = { mission = m, rule = rule, targets = params and params.targets or {}, airborne_once = false }
end

-- True while the flight is still watched: launched and not yet sent home, stood down,
-- landed or lost.
function EnforceAirBehaviourRules.watching(id)
    return _watched[id] ~= nil
end

function EnforceAirBehaviourRules.start(plan)
    _plan = plan
    for _, coalition in ipairs({ "red", "blue" }) do
        TrackRadarPicture.on(coalition, "picture_updated", function() check(coalition) end)
    end
    Log.info("--- AI behaviour rules: checked every radar-picture round ---")
end
