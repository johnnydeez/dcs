-- Controller, part of directing the air flights (direct_flights.lua): scrambles — each coalition's
-- quick-reaction fighters, launched at raids its own radars actually see (roadmap.md items
-- 2 and 11; moved here from consumers/run_scrambles.lua, unchanged in what it decides).
-- The plan holds only the alert posture; the alert jets' state is controller\air_flights\assign_alert_jets.lua;
-- this decides, on the radar picture's round (picture_updated, every 30 s).
--
-- Per coalition, each round:
--   1. trigger: a tracked contact (range known, not a helicopter) that is over own
--      airspace, or that the picture has inbound on an own asset (a held base, a catalog
--      target) it will reach within scramble_warning_min minutes, for
--      scramble_inbound_rounds rounds in a row — in whatever airspace it is now (John:
--      100 km was far too close; a jet at 60 nm can bomb a base in ~5 min); still over
--      its own airspace, scramble_inbound_rounds_enemy_airspace (longer than a race-track
--      leg, bug 3)
--   2. skipped when a live scramble is already after it, when an airborne patrol's
--      defended zone or commit circle covers where it is (the patrol handles it), or
--      while it is inside an enemy kill zone (under enemy SAM cover: the leash would only
--      bring the scramble home again; checked again every round)
--   3. the raid: it and the other contacts within raid_radius_km on a heading within
--      raid_heading_deg; one scramble takes them all, in order
--   4. the base: the nearest alert base, in the own region facing the raid, with a
--      jet ready and off cooldown, that the raid isn't flying away from (no tail chases:
--      scramble_tail_chase_deg), whose intercept point (the raid pushed ahead along
--      its heading, pulled back to own or contested airspace and
--      scramble_killzone_margin_km outside enemy kill zones) is in reach and at least
--      scramble_min_leg_km out, and which gets there before the raid reaches what it
--      threatens (reaction, scramble_takeoff_s and the dash); never over the airborne cap
--      (the planner keeps AIR_DEFENSE.scramble_reserve_aircraft of it free for scrambles;
--      players don't count). Refused: the reason of the ready base nearest the raid
--   5. after scramble_reaction_s (cockpit alert) a one-ship spawns hot on one of the ramp
--      spots the plan holds for its base's alert jets (never on the runway: John), with
--      EngageGroup on each raid group from takeoff, open fire, dash speed with afterburner
--      allowed. The scheduler records it; its radar joins the picture; the controller
--      watches it with the leash, which brings it home
--
-- Event log lines (word CONTROL):
--   RED  MSN7901_SCRAM   "scramble: MiG-31 from Monchegorsk after MSN2014_STRIKE (F-16C_50), own airspace,
--                         9 min from Olenya; intercept 85 km out; launching in 95 s; Monchegorsk has 2 alert jet(s) ready"
--   RED  MSN2014_STRIKE  "no scramble: F-16C_50: covered by patrol MSN7003_CAP"   once per reason
--   RED  MSN2014_STRIKE  "no scramble: F-16C_50: Kuusamo: flying away from it (and 2 more alert bases refused)"
--   RED  MSN7901_SCRAM   "stand down before launch: MSN2014_STRIKE destroyed"
-- Scramble ids are MSN<first_number + n>_SCRAM (Blue 2901+, Red 7901+), the DCS group name.
-- Reads the plan; writes nothing back to it.

ControllerScrambleFighters = {}

local FRONT_SEARCH_M = 300000                  -- how far to look for the own region facing a raid
local INTERCEPT_STEP_M = 5000                  -- the intercept point is pulled back in steps this long

local _plan
local _state = {}   -- coalition → { coalition, posture, answered, pending, refused, inbound, next_number, patrols }

-- ── small helpers ───────────────────────────────────────────────

local function liveGroup(name)
    return name ~= nil and RecordGroups.alive(name)
end

local function inAir(name)
    return RecordGroups.inAir(name)
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

local function pendingCount(st)
    local n = 0
    for _ in pairs(st.pending) do n = n + 1 end
    return n
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
    return id and (st.pending[id] or RecordWatchedFlights.onTask(id))
end

-- ── where and from where ────────────────────────────────────────

-- The enemy medium / long-range SAM site, or base-defense radar SAM (Tor, Pantsir, …;
-- bug 41), whose kill zone (+ margin_m) holds pos, or nil: at altitude_m (above sea
-- level; tools/sam_reach.lua goes by the height above the ground there), or the full ring
-- without one (an intercept point, flown high). A base defense: its full reach at any height.
-- A site out of the fight (its radars destroyed: RecordThreats.outOfTheFight) isn't one.
local function enemyKillZone(coalitionName, pos, altitude_m, margin_m)
    local height = SamReach.aboveGround(pos, altitude_m)
    for _, s in ipairs(_plan.sam_sites and _plan.sam_sites.sites or {}) do
        if s.side ~= coalitionName and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0
           and Util.dist(pos, s.pos) < SamReach.killZone(s, height) + (margin_m or 0) and liveGroup(s.id)
           and not RecordThreats.outOfTheFight(s.id) then
            return s.id
        end
    end
    for _, g in ipairs(SamReach.baseDefenses(_plan, coalitionName)) do
        if Util.dist(pos, g.pos) < g.reach_m * AIR_DEFENSE.killzone_fraction + (margin_m or 0) and liveGroup(g.id) then
            return g.id
        end
    end
    return nil
end

-- The raid pushed ahead along its heading by the time the scramble needs to get there,
-- then pulled back toward the base until it lies in own or contested airspace, and
-- scramble_killzone_margin_km outside enemy kill zones (the leash's line: bug 8).
local function interceptPoint(coalitionName, from, c, dash)
    local margin = AIR_DEFENSE.scramble_killzone_margin_km * 1000
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
        if Airspace.kindFor(_plan.airspace, p, coalitionName) == "enemy" or enemyKillZone(coalitionName, p, nil, margin) then
            break
        end
        good = p
    end
    return good
end

-- True when the raid flies away from the base: its heading more than
-- scramble_tail_chase_deg off the line from the raid to the base (bug 16: no tail chases;
-- a base ahead of the raid answers it). A raid too slow to have a heading never is.
local function flyingAway(c, basePos)
    if (c.speed_mps or 0) < 50 then return false end
    local toBase = math.deg(math.atan2(basePos.z - c.pos.z, basePos.x - c.pos.x))
    return angleBetween(c.heading_deg, toBase) > AIR_DEFENSE.scramble_tail_chase_deg
end

-- The alert base to answer from: { base (posture entry), aircraft_type, intercept, leg_m }
-- or nil and why not: the reason of the ready base nearest the raid, "<base>: <why>" (bug
-- 23: the reason used to be the last base tried, wherever it was).
local function pickBase(st, c, now)
    local region = Airspace.facingRegion(_plan.airspace, c.pos, st.coalition, FRONT_SEARCH_M)
    local best, nearest, refused = nil, nil, 0
    for _, b in ipairs(st.posture.bases) do
        if ControllerAssignAlertJets.canLaunch(st.coalition, b.base, now) and (not region or b.region == region) then
            local why
            if flyingAway(c, b.pos) then
                why = "flying away from it"
            else
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
                    why = "out of reach"
                elseif c.threat_minutes and arrive_s > c.threat_minutes * 60 then
                    -- it would get there after the raid reached what it threatens (John, 2026-10-01:
                    -- refuse a scramble that can't arrive in time)
                    why = string.format("can't reach the raid before it reaches %s (%.0f min, raid %.0f min)",
                        c.threat_asset or "its target", arrive_s / 60, c.threat_minutes)
                elseif not ControllerAssignAlertJets.freeSpot(st.coalition, b) then
                    why = "no free ramp spot"
                elseif not best or leg < best.leg_m then
                    best = { base = b, aircraft_type = aircraftType, intercept = intercept, leg_m = leg }
                end
            end
            if why then
                refused = refused + 1
                local d = Util.dist(b.pos, c.pos)
                if not nearest or d < nearest.d then nearest = { d = d, base = b.base, why = why } end
            end
        end
    end
    if best then return best end
    if not nearest then return nil, "no alert base with a jet ready" end
    return nil, string.format("%s: %s%s", nearest.base, nearest.why,
        refused > 1 and string.format(" (and %d more alert bases refused)", refused - 1) or "")
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
        local contact = RecordRadarPicture.contact(st.coalition, name)
        if not liveGroup(name) then
            why = why or RecordFlights.goneText(name)
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

local function launch(st, pick, raid, groups, id, number, refundToken)
    local b, aircraftType = pick.base, pick.aircraft_type
    local c = st.coalition
    local function refund(why)
        st.pending[id] = nil
        ControllerAssignAlertJets.refund(c, b.base, refundToken)
        ControllerDirectFlights.say(c, id, "stand down before launch", why)
    end
    local gone = raidGone(st, groups)
    if gone then return refund(gone) end
    local spot = ControllerAssignAlertJets.freeSpot(c, b)
    if not spot then return refund("no free ramp spot at " .. b.base) end
    local now = timer.getTime()
    local mt = AIR_MISSION_TYPE.interception
    local p = AIRCRAFT_PROFILE[aircraftType]
    local alt = p.attack_altitude_m.interception
    local m = {
        id = id, number = number, coalition = c, mission_type = "interception",
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
        keeps_gun = true, may_jettison = true, afterburner = true, critical_names = {},
    }
    FlightCallsigns.assign(RecordCallsigns.numbers(m.coalition), m)
    ControllerAssignAlertJets.hold(c, b.base, spot.terminal_index)
    local grp = ExecuteSpawnAircraftGroups.spawn(m)
    ControllerAssignAlertJets.release(c, b.base, spot.terminal_index)
    if not grp then return refund("spawn failed") end
    st.pending[id] = nil
    ControllerAssignAlertJets.launched(c, b.base, id)   -- its jet goes back on alert at this base after landing
    ControllerScheduleFlights.track(m)   -- launched: the radar picture adds its radar
    ControllerDirectFlights.watch(m, { targets = groups })
end

local function refuse(st, c, why)
    -- once per reason: the minutes in a reason change every round, so they don't count
    local key = why:gsub("%d+", "#")
    if st.refused[c.group] == key then return end
    st.refused[c.group] = key
    ControllerDirectFlights.say(st.coalition, c.group, "no scramble", string.format("%s: %s", c.type or "type unknown", why))
end

local function scramble(st, trigger, contacts, reason, now)
    local pick, why = pickBase(st, trigger, now)
    if not pick then return refuse(st, trigger, why) end
    if RecordAirborneAircraft.count(st.coalition) + pendingCount(st) + 1 > ControllerDecideLaunches.cap(st.coalition, true) then
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
    local base = pick.base.base
    local refundToken = ControllerAssignAlertJets.commit(st.coalition, base, now, pick.base.cooldown_s)
    st.pending[id] = true
    for _, g in ipairs(groups) do
        st.answered[g] = id
        st.refused[g] = nil
    end
    local R = AIR_DEFENSE.scramble_reaction_s
    local delay = math.random(R[1], R[2])
    ControllerDirectFlights.say(st.coalition, id, "scramble", string.format("%s from %s after %s, %s; intercept %.0f km out; launching in %d s; %s has %s",
        pick.aircraft_type, base, table.concat(names, " + "), reason,
        pick.leg_m / 1000, delay, base, ControllerAssignAlertJets.jetsText(st.coalition, base, now)))
    timer.scheduleFunction(function()
        local ok, err = pcall(launch, st, pick, raid, groups, id, number, refundToken)
        if not ok then
            st.pending[id] = nil
            Log.error(string.format("%s scramble %s: launch failed: %s", st.coalition:upper(), id, tostring(err)))
        end
    end, nil, now + delay)
end

-- One radar-picture round: update who's been inbound how long, then answer the raids.
local function check(st)
    local now = timer.getTime()
    local contacts = RecordRadarPicture.contacts(st.coalition, { state = "tracked" })
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
            elseif threatening and st.inbound[c.group] >= (c.airspace == "enemy"
                    and AIR_DEFENSE.scramble_inbound_rounds_enemy_airspace or AIR_DEFENSE.scramble_inbound_rounds) then
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

-- Starts scrambles for each coalition with alert bases; returns the dcs.log lines.
function ControllerScrambleFighters.start(plan)
    local ato = plan.air_tasking_orders
    if not ato or ato.problems then return {} end
    _plan = plan
    local started = ControllerAssignAlertJets.start(plan)
    for _, c in ipairs({ "red", "blue" }) do
        local posture = ControllerAssignAlertJets.posture(c)
        if posture then
            local st = { coalition = c, posture = posture, answered = {}, pending = {}, refused = {},
                         inbound = {}, next_number = posture.first_number, patrols = {} }
            for _, m in ipairs(ato[c].missions or {}) do
                if m.mission_type == "combat_air_patrol" and m.attack and m.attack.zone then st.patrols[#st.patrols + 1] = m end
            end
            _state[c] = st
            RecordRadarPicture.on(c, "picture_updated", function() check(st) end)
        end
    end
    return started
end
