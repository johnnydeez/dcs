-- Consumer: scrambles — each coalition's quick-reaction fighters, launched at raids its
-- own radars actually see (roadmap.md item 2). The plan holds only the alert posture
-- (plan.air_tasking_orders[coalition].alert: the alert bases and their aircraft); this
-- runs on the radar picture (consumers/track_radar_picture.lua) at the end of every
-- round (picture_updated, every 30 s).
--
-- Per coalition, each round:
--   1. trigger: a tracked contact (range known, not a helicopter) that is over own
--      airspace, or that the picture has inbound on an own asset (a held base, a catalog
--      target) it will reach within scramble_warning_min minutes, for
--      scramble_inbound_rounds rounds in a row — in whatever airspace it is now (John:
--      100 km was far too close; a jet at 60 nm can bomb a base in ~5 min)
--   2. skipped when a live scramble is already after it, when an airborne patrol's
--      defended zone or commit circle covers where it is (the patrol handles it), or
--      while it is inside an enemy kill zone (under enemy SAM cover: the leash would only
--      bring the scramble home again; checked again every round)
--   3. the raid: it and the other contacts within raid_radius_km on a heading within
--      raid_heading_deg; one scramble takes them all, in order
--   4. the base: the nearest alert base, in the own region facing the raid, with a
--      jet ready and off cooldown, whose intercept point (the raid pushed ahead along
--      its heading, pulled back to own or contested airspace and out of enemy kill zones)
--      is in reach and at least scramble_min_leg_km out, and which gets there before the
--      raid reaches what it threatens (reaction, scramble_takeoff_s and the dash); never
--      over the airborne cap (the planner keeps AIR_DEFENSE.scramble_reserve_aircraft of
--      it free for scrambles; players don't count)
--   5. after scramble_reaction_s (cockpit alert) a one-ship spawns hot on one of the ramp
--      spots the plan holds for its base's alert jets (never on the runway: John), with EngageGroup on each raid group from
--      takeoff, open fire, dash speed with afterburner allowed. The scheduler logs its
--      shots, kills and losses; its radar joins the picture; the leash
--      (consumers/enforce_air_behaviour_rules.lua) brings it home
--
-- Event log lines (consumers/write_event_log.lua):
--   SCRAMBLE     RED  MSN5901_SCRAM   "MiG-31 from Monchegorsk after MSN2014_STRIKE (F-16C_50), own airspace,
--                     9 min from Olenya; intercept 85 km out; launching in 95 s; Monchegorsk has 2 alert jet(s) ready"
--   ALERT        RED  MSN5901_SCRAM   "landed; its jet is back on alert at Monchegorsk in 30 min; …"
--   NO_SCRAMBLE  RED  MSN2014_STRIKE  "F-16C_50: covered by patrol MSN5003_CAP"   once per reason
--   STOOD_DOWN   RED  MSN5901_SCRAM   "before launch: MSN2014_STRIKE destroyed"
-- The alert bases at start go to dcs.log (grep "Scrambles").
-- Scramble ids are MSN<first_number + n>_SCRAM (Blue 2901+, Red 5901+), the DCS group name.
-- Reads the plan; writes nothing back to it. Launches, cooldowns and who was answered are
-- runtime state kept here.

RunScrambles = {}

local SIDE = { red = 1, blue = 2 }             -- coalition.side
local FRONT_SEARCH_M = 300000                  -- how far to look for the own region facing a raid
local INTERCEPT_STEP_M = 5000                  -- the intercept point is pulled back in steps this long

local _plan
local _state = {}   -- coalition → state (RunScrambles.start)

-- ── small helpers ───────────────────────────────────────────────

-- AI aircraft of the coalition in the air: players don't count against the cap (John,
-- 2026-10-01: the cap is for AI aircraft)
local function airborneAircraft(coalitionName)
    local n = 0
    for _, g in ipairs(coalition.getGroups(SIDE[coalitionName], Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            local ok, air = pcall(function() return u:inAir() and not u:getPlayerName() end)
            if ok and air then n = n + 1 end
        end
    end
    return n
end

local function liveGroup(name)
    local g = name and Group.getByName(name)
    local ok, live = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:isExist() and u:getLife() > 0 then return true end
        end
        return false
    end)
    return ok and live
end

local function inAir(name)
    local g = Group.getByName(name)
    local ok, air = pcall(function()
        if not (g and g:isExist()) then return false end
        for _, u in ipairs(g:getUnits() or {}) do
            if u:inAir() then return true end
        end
        return false
    end)
    return ok and air
end

local function angleBetween(a, b)
    local d = math.abs(a - b) % 360
    return d > 180 and 360 - d or d
end

local function headingVector(c)
    local r = math.rad(c.heading_deg)
    return math.cos(r), math.sin(r)   -- x north, z east
end

local function describe(c)
    return string.format("%s (%s)", c.group, c.type or "type unknown")
end

local function threatText(minutes, asset)
    if minutes < 1 then return "passing " .. asset end
    return string.format("%.0f min from %s", minutes, asset)
end

-- ── alert jets ──────────────────────────────────────────────────

-- Jets back from a scramble return to alert once their turnaround is over.
local function readyJets(s, now)
    for i = #s.returning, 1, -1 do
        if s.returning[i] <= now then
            s.ready = s.ready + 1
            table.remove(s.returning, i)
        end
    end
    return s.ready
end

local function jetsText(s, now)
    local text = string.format("%d alert jet(s) ready", readyJets(s, now))
    if #s.returning > 0 then
        local soonest = math.huge
        for _, t in ipairs(s.returning) do soonest = math.min(soonest, t) end
        text = text .. string.format(", %d turning around (next in %d min)", #s.returning,
            math.ceil((soonest - now) / 60))
    end
    return text
end

-- ── trigger ─────────────────────────────────────────────────────

-- The airborne patrol whose defended zone or commit circle holds pos, or nil.
local function coveringPatrol(st, pos)
    for _, m in ipairs(st.patrols) do
        if inAir(m.id) then
            local a = m.attack
            local circles = { a.zone }
            for _, z in ipairs(a.commit or {}) do circles[#circles + 1] = z end
            for _, z in ipairs(circles) do
                if (pos.x - z.x) ^ 2 + (pos.z - z.z) ^ 2 <= z.radius_m ^ 2 then return m.id end
            end
        end
    end
    return nil
end

local function answered(st, group)
    local id = st.answered[group]
    return id and (st.pending[id] or EnforceAirBehaviourRules.watching(id))
end

-- ── where and from where ────────────────────────────────────────

-- The enemy medium / long-range SAM site whose kill zone holds pos, or nil: at
-- altitude_m (lib/sam_reach.lua), or the full ring without one (an intercept point,
-- flown high).
local function enemyKillZone(coalitionName, pos, altitude_m)
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalitionName and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0
           and Util.dist(pos, s.pos) < SamReach.killZone(s, altitude_m) and liveGroup(s.id) then
            return s.id
        end
    end
    return nil
end

-- The raid pushed ahead along its heading by the time the scramble needs to get there,
-- then pulled back toward the base until it lies in own or contested airspace, outside
-- enemy kill zones.
local function interceptPoint(coalitionName, from, c, dash)
    local hx, hz = headingVector(c)
    local t = Util.dist(from, c.pos) / dash
    local ahead
    for _ = 1, 2 do
        ahead = { x = c.pos.x + hx * c.speed_mps * t, z = c.pos.z + hz * c.speed_mps * t }
        t = Util.dist(from, ahead) / dash
    end
    local d = Util.dist(from, ahead)
    local good = { x = from.x, z = from.z }
    local steps = math.ceil(d / INTERCEPT_STEP_M)
    for i = 1, steps do
        local f = math.min(1, i * INTERCEPT_STEP_M / d)
        local p = { x = from.x + (ahead.x - from.x) * f, z = from.z + (ahead.z - from.z) * f }
        if DivideAirspace.kindFor(_plan.airspace, p, coalitionName) == "enemy" or enemyKillZone(coalitionName, p) then
            break
        end
        good = p
    end
    return good
end

-- A free ramp spot for an alert jet at alert base b: one of the spots the plan holds for
-- its alert jets (b.spots, nearest the runway first) that DCS reports free now and no
-- other scramble is spawning on. { terminal_index, x, z } or nil.
local function freeSpot(st, b)
    local ab = Airbase.getByName(b.base)
    if not ab then return nil end
    local held = st.held_spots[b.base] or {}
    local ok, spots = pcall(function() return ab:getParking(true) end)
    if not ok or type(spots) ~= "table" then return nil end
    local free = {}
    for _, s in ipairs(spots) do free[s.Term_Index] = true end
    for _, s in ipairs(b.spots or {}) do
        if free[s.terminal_index] and not held[s.terminal_index] then return s end
    end
    return nil
end

-- The alert base to answer from: { base (posture entry), aircraft_type, intercept, leg_m }
-- or nil and why not.
local function pickBase(st, c, now)
    local region = DivideAirspace.facingRegion(_plan.airspace, c.pos, st.coalition, FRONT_SEARCH_M)
    local best, why = nil, "no alert base with a jet ready"
    for _, b in ipairs(st.posture.bases) do
        local s = st.bases[b.base]
        local ab = Airbase.getByName(b.base)
        if readyJets(s, now) > 0 and now >= s.ready_s and ab and ab:getCoalition() == SIDE[st.coalition]
           and (not region or b.region == region) then
            local aircraftType = Util.weightedPick(b.aircraft)
            local p = AIRCRAFT_PROFILE[aircraftType]
            local intercept = interceptPoint(st.coalition, b.pos, c, p.dash_speed_mps)
            local leg = Util.dist(b.pos, intercept)
            -- from the decision to the intercept point: cockpit alert, taxi and takeoff, the dash
            local R = AIR_DEFENSE.scramble_reaction_s
            local arrive_s = (R[1] + R[2]) / 2 + AIR_DEFENSE.scramble_takeoff_s + leg / p.dash_speed_mps
            if leg < AIR_DEFENSE.scramble_min_leg_km * 1000 then
                why = "no way to the raid outside enemy airspace and kill zones"
            elseif leg > p.combat_radius_km * 1000 then
                why = "out of reach of every ready alert base"
            elseif c.threat_minutes and arrive_s > c.threat_minutes * 60 then
                -- it would get there after the raid reached what it threatens (John, 2026-10-01:
                -- refuse a scramble that can't arrive in time)
                why = string.format("can't reach the raid before it reaches %s (%.0f min, raid %.0f min)",
                    c.threat_asset or "its target", arrive_s / 60, c.threat_minutes)
            elseif not freeSpot(st, b) then
                why = "no free ramp spot at " .. b.base
            elseif not best or leg < best.leg_m then
                best = { base = b, aircraft_type = aircraftType, intercept = intercept, leg_m = leg }
            end
        end
    end
    return best, why
end

-- ── launch ──────────────────────────────────────────────────────

local function raidOf(st, trigger, contacts)
    local raid = { trigger }
    local rest = {}
    for _, c in ipairs(contacts) do
        if c ~= trigger and c.category ~= "helicopter" and c.range_known and not answered(st, c.group)
           and Util.dist(c.pos, trigger.pos) <= AIR_DEFENSE.raid_radius_km * 1000
           and angleBetween(c.heading_deg, trigger.heading_deg) <= AIR_DEFENSE.raid_heading_deg then
            rest[#rest + 1] = c
        end
    end
    table.sort(rest, function(a, b) return Util.dist(a.pos, trigger.pos) < Util.dist(b.pos, trigger.pos) end)
    for _, c in ipairs(rest) do raid[#raid + 1] = c end
    return raid
end

-- The first reason the raid no longer needs answering, or nil while a group of it does.
local function raidGone(st, groups)
    local why
    for _, name in ipairs(groups) do
        local contact = TrackRadarPicture.contact(st.coalition, name)
        if not liveGroup(name) then
            why = why or (name .. " destroyed")
        elseif not contact then
            why = why or (name .. " lost from the radar picture")
        elseif contact.airspace == "enemy" and not contact.inbound then
            why = why or (name .. " back over its own airspace, heading away")
        else
            return nil
        end
    end
    return why
end

local function launch(st, pick, raid, groups, id, number, reserved)
    local b, aircraftType = pick.base, pick.aircraft_type
    local s = st.bases[b.base]
    local function refund(why)
        st.pending[id] = nil
        s.ready, s.ready_s = s.ready + 1, reserved.ready_s
        WriteEventLog.add(st.coalition, "STOOD_DOWN", id, "before launch: " .. why)
    end
    local gone = raidGone(st, groups)
    if gone then return refund(gone) end
    local spot = freeSpot(st, b)
    if not spot then return refund("no free ramp spot at " .. b.base) end
    local now = timer.getTime()
    local mt = AIR_MISSION_TYPE.interception
    local p = AIRCRAFT_PROFILE[aircraftType]
    local alt = p.attack_altitude_m.interception
    local m = {
        id = id, number = number, coalition = st.coalition, mission_type = "interception",
        group_task = mt.group_task, target = groups[1], target_label = raid[1].type or "type unknown",
        target_pos = { x = raid[1].pos.x, z = raid[1].pos.z },
        aircraft_type = aircraftType, count = 1, skill = Util.pick(AIR_TASKING_SKILL),
        launch_base = b.base, landing_base = b.base, parking = { spot }, takeoff = "parking",
        start_s = math.floor(now), takeoff_s = math.floor(now),
        tot_s = math.floor(now + pick.leg_m / p.dash_speed_mps),
        end_s = math.floor(now + pick.leg_m / p.dash_speed_mps + pick.leg_m / p.cruise_speed_mps + 1800),
        route = {
            { kind = "takeoff", x = b.pos.x, z = b.pos.z, alt_m = 0, speed_mps = 0, carries_attack_tasks = true },
            { kind = "intercept", x = pick.intercept.x, z = pick.intercept.z, alt_m = alt, speed_mps = p.dash_speed_mps },
            { kind = "landing", x = b.pos.x, z = b.pos.z, alt_m = 0, speed_mps = p.cruise_speed_mps },
        },
        attack = { kind = "intercept", groups = groups, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type] },
        rules_of_engagement = mt.rules_of_engagement, loadout = AIRCRAFT_LOADOUT[aircraftType].interception,
        keeps_gun = true, may_jettison = true, afterburner = true, critical_names = {}, suppression_threats = {},
    }
    st.held_spots[b.base] = st.held_spots[b.base] or {}
    st.held_spots[b.base][spot.terminal_index] = true
    local grp = SpawnAircraftGroups.spawn(m)
    st.held_spots[b.base][spot.terminal_index] = nil
    if not grp then return refund("spawn failed") end
    st.pending[id] = nil
    st.flights[id] = b.base   -- its jet goes back on alert at this base after landing
    ScheduleAirTaskingOrders.track(m)
    TrackRadarPicture.addFlight(st.coalition, id, "scramble")
    EnforceAirBehaviourRules.watch(m, "leash", { targets = groups })
end

local function refuse(st, c, why)
    -- once per reason: the minutes in a reason change every round, so they don't count
    local key = why:gsub("%d+", "#")
    if st.refused[c.group] == key then return end
    st.refused[c.group] = key
    WriteEventLog.add(st.coalition, "NO_SCRAMBLE", c.group, string.format("%s: %s", c.type or "type unknown", why))
end

local function scramble(st, trigger, contacts, reason, now)
    local pick, why = pickBase(st, trigger, now)
    if not pick then return refuse(st, trigger, why) end
    if airborneAircraft(st.coalition) + st.pending_count() + 1
       > st.posture.max_airborne_aircraft then
        return refuse(st, trigger, "over the airborne cap")
    end
    local raid = raidOf(st, trigger, contacts)
    local groups, names = {}, {}
    for i, c in ipairs(raid) do
        groups[i] = c.group
        names[i] = describe(c)
    end
    local number = st.next_number
    st.next_number = number + 1
    local id = string.format("MSN%d_%s", number, AIR_MISSION_TYPE.interception.group_name_tag)
    local s = st.bases[pick.base.base]
    local reserved = { ready_s = s.ready_s }
    s.ready, s.ready_s = s.ready - 1, now + pick.base.cooldown_s
    st.pending[id] = true
    for _, g in ipairs(groups) do
        st.answered[g] = id
        st.refused[g] = nil
    end
    local R = AIR_DEFENSE.scramble_reaction_s
    local delay = math.random(R[1], R[2])
    WriteEventLog.add(st.coalition, "SCRAMBLE", id, string.format("%s from %s after %s, %s; intercept %.0f km out; launching in %d s; %s has %s",
        pick.aircraft_type, pick.base.base, table.concat(names, " + "), reason,
        pick.leg_m / 1000, delay, pick.base.base, jetsText(s, now)))
    timer.scheduleFunction(function()
        local ok, err = pcall(launch, st, pick, raid, groups, id, number, reserved)
        if not ok then
            st.pending[id] = nil
            Log.error(string.format("%s scramble %s: launch failed: %s", st.coalition:upper(), id, tostring(err)))
        end
    end, nil, now + delay)
end

-- One radar-picture round: update who's been inbound how long, then answer the raids.
local function check(st)
    local now = timer.getTime()
    local contacts = TrackRadarPicture.contacts(st.coalition, { state = "tracked" })
    local seen = {}
    for _, c in ipairs(contacts) do
        seen[c.group] = true
        if c.category ~= "helicopter" and c.range_known then
            local asset, minutes = c.threat_asset, c.threat_minutes
            local threatening = minutes and minutes <= AIR_DEFENSE.scramble_warning_min
            st.inbound[c.group] = threatening and (st.inbound[c.group] or 0) + 1 or 0
            local reason
            if c.airspace == "own" then
                reason = "over own airspace"
            elseif threatening and st.inbound[c.group] >= AIR_DEFENSE.scramble_inbound_rounds then
                reason = string.format("%s airspace, %s", c.airspace, threatText(minutes, asset))
            end
            if reason and not answered(st, c.group) then
                if c.airspace == "own" and threatening then
                    reason = string.format("%s, %s", reason, threatText(minutes, asset))
                end
                local patrol = coveringPatrol(st, c.pos)
                local cover = not patrol and enemyKillZone(st.coalition, c.pos, c.altitude_m)
                if patrol then
                    refuse(st, c, "covered by patrol " .. patrol)
                elseif cover then
                    -- no fighter is sent into enemy SAM coverage: the leash would only
                    -- bring it home again. Answered once it comes out
                    refuse(st, c, "under enemy SAM cover (the kill zone of " .. cover .. ")")
                else
                    scramble(st, c, contacts, reason, now)
                end
            end
        end
    end
    for group in pairs(st.inbound) do
        if not seen[group] then st.inbound[group] = nil end
    end
end

-- A scramble's jet that lands goes back on alert at its base after the turnaround; a jet
-- shot down never comes back.
local landingHandler = {}
function landingHandler:onEvent(e)
    if e.id ~= world.event.S_EVENT_LAND or not e.initiator then return end
    local ok, name = pcall(function() return e.initiator:getGroup():getName() end)
    if not ok or not name then return end
    for _, st in pairs(_state) do
        local base = st.flights[name]
        if base then
            st.flights[name] = nil
            local s = st.bases[base]
            local now = timer.getTime()
            table.insert(s.returning, now + AIR_DEFENSE.scramble_turnaround_s)
            WriteEventLog.add(st.coalition, "ALERT", name, string.format("landed; its jet is back on alert at %s in %d min; %s has %s",
                base, math.floor(AIR_DEFENSE.scramble_turnaround_s / 60), base, jetsText(s, now)))
        end
    end
end

-- A scramble the leash stood down on the ramp (consumers/enforce_air_behaviour_rules.lua):
-- its jet never flew, so it is back on alert at once (closed_issues.md, bug 2).
function RunScrambles.stoodDown(id)
    for _, st in pairs(_state) do
        local base = st.flights[id]
        if base then
            st.flights[id] = nil
            local s = st.bases[base]
            s.ready = s.ready + 1
            WriteEventLog.add(st.coalition, "ALERT", id, string.format("stood down on the ramp; its jet is back on alert at %s; %s has %s",
                base, base, jetsText(s, timer.getTime())))
        end
    end
end

function RunScrambles.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return end
    _plan = plan
    local started = {}
    for _, c in ipairs({ "red", "blue" }) do
        local posture = ato[c] and ato[c].alert
        if posture and #posture.bases > 0 then
            local st = { coalition = c, posture = posture, bases = {}, answered = {}, pending = {}, refused = {},
                         inbound = {}, held_spots = {}, flights = {}, next_number = posture.first_number, patrols = {} }
            st.pending_count = function()
                local n = 0
                for _ in pairs(st.pending) do n = n + 1 end
                return n
            end
            for _, b in ipairs(posture.bases) do
                st.bases[b.base] = { ready = b.alert_aircraft, returning = {}, ready_s = 0 }
            end
            for _, m in ipairs(ato[c].missions or {}) do
                if m.mission_type == "combat_air_patrol" and m.attack and m.attack.zone then st.patrols[#st.patrols + 1] = m end
            end
            _state[c] = st
            TrackRadarPicture.on(c, "picture_updated", function() check(st) end)
            local names = {}
            for _, b in ipairs(posture.bases) do names[#names + 1] = b.base end
            started[#started + 1] = string.format("%s from %s", c:upper(), table.concat(names, ", "))
        end
    end
    if #started == 0 then return end
    world.addEventHandler(landingHandler)
    Log.info(string.format("--- Scrambles: every radar-picture round; %s ---", table.concat(started, "; ")))
end
