-- Consumer part of the controller (control_air_flights.lua): the directives a controller
-- gives one flight, each a check of the flight's situation
-- (assess_flight_situations.lua) that returns an intent, or nil to leave the flight as it
-- is. Settings in data/air_control.lua; which flights get which directives:
-- AIR_CONTROL.directives_by_mission_type.
--
-- An intent is { kind, why, … }:
--   home        go home now, returning fire only ("going home: <why>")
--   land        a flight lost on its way home: a new landing order straight to its base
--   stand_down  still on the ramp: removed, never flies
--   remove      `units` still in the air long after the flight's last landing: removed,
--               counted as landed
--   defend      engage one of `threats` (the coordination across flights picks which)
--   resume      the fight is over: back to the mission
--
-- Each directive has:
--   clock          "picture" (the radar picture's round, 30 s) or "fast" (AIR_CONTROL.check_every_s)
--   on_task_only   true: no longer asked once the flight is going home
--   check(w, s)    → intent or nil; w is the controller's watch entry (w.memo[directive]
--                  is the directive's own memory for this flight), s the situation
--
-- Directives:
--   leash         scrambles: home when the raid is gone or back over its own airspace
--                 heading away, or the scramble is too deep in enemy airspace or inside
--                 an enemy kill zone; stood down on the ramp when the raid is gone first
--   suppression   SEAD flights: go cold after the salvo (see data/air_control.lua); home
--                 with "no shot" at its press-on point when it has fired nothing
--   handover      patrols: home once the next patrol of its station is on station
--   landing       every flight on its way home: a new landing order when a jet of it
--                 gets lost (flies away from its base, or is long overdue); a jet still
--                 up 8 min after the flight's last landing is removed
--   self_defence  attack flights: a bandit hot on the flight is called at once; a flight
--                 with radar missiles engages it, then carries on with its mission; one
--                 without leaves (goes home)
--
-- New directives are one more entry here and one more name in
-- AIR_CONTROL.directives_by_mission_type.

DirectivesPerFlight = {}

local A = AssessFlightSituations

local DIRECTIVES = {}

-- "inside the kill zone of <site>", naming the jet when the flight has more than one in
-- the air ("MSN2043_STRIKE_2 inside the kill zone of SAM_IVAL_SA11_3").
local function insideText(s, jet, site)
    if #s.jets > 1 and jet then return string.format("%s inside the kill zone of %s", jet, site) end
    return "inside the kill zone of " .. site
end

-- ── leash ───────────────────────────────────────────────────────

DIRECTIVES.leash = {
    clock = "picture",
    on_task_only = true,
    check = function(w, s)
        local L = AIR_CONTROL.leash
        local c = s.coalition
        -- the raid: any group still alive, in the picture and not back over its own airspace?
        local why
        for _, name in ipairs(w.targets) do
            if A.liveGroup(name) then
                local contact = TrackRadarPicture.contact(c, name)
                if contact and not (contact.airspace == "enemy" and not contact.inbound) then
                    why = nil
                    break
                end
                why = why or (contact and (name .. " back over its own airspace, heading away")
                                       or (name .. " lost from the radar picture"))
            else
                why = why or A.goneText(name)
            end
        end
        local raidGone = why ~= nil
        if not s.airborne then
            if raidGone and not w.airborne_once then return { kind = "stand_down", why = why } end
            return nil
        end
        if raidGone then return { kind = "home", why = why } end
        local depth = A.flightEnemyDepth(s, L.front_search_km * 1000)
        if depth > L.enemy_airspace_km * 1000 then
            return { kind = "home", why = depth == math.huge and "deep in enemy airspace"
                or string.format("%.0f km into enemy airspace", depth / 1000) }
        end
        local site, jet = A.flightKillZone(s, L.killzone_fraction)
        if site then return { kind = "home", why = insideText(s, jet, site) } end
        return nil
    end,
}

-- ── suppression (go cold) ───────────────────────────────────────

-- On the fast clock, and the controller runs it again the moment the flight fires an
-- anti-radiation missile, so it turns as its last missile leaves (John, 2026-10-02: "go
-- cold as soon as they loose the salvo"; on the 30 s picture round MSN2024 flew on into
-- the SA-11 for 26 s after its last HARM).
DIRECTIVES.suppression = {
    clock = "fast",
    on_task_only = true,
    check = function(w, s)
        if not s.airborne then return nil end
        local R = AIR_CONTROL.suppression
        local mem = w.memo.suppression
        local m = s.mission
        local a = m.attack or {}
        local arms = s.anti_radiation_missiles
        if not mem.arms_at_start then mem.arms_at_start = arms end
        if mem.arms_at_start > 0 and arms == 0 then return { kind = "home", why = "every anti-radiation missile fired" } end
        local now = timer.getTime()
        -- the flight goes cold together: once one jet has fired its last, the others get
        -- salvo_time_s to finish (bug 40, 2026-10-02: MSN2024_SEAD_2 fired one HARM at a
        -- time for 76 s after its lead was empty, inside the SA-10's envelope, and died)
        local byJet = s.anti_radiation_missiles_by_jet
        mem.jet_arms_at_start = mem.jet_arms_at_start or byJet
        if not mem.first_empty then
            for name, n in pairs(byJet) do
                if n == 0 and (mem.jet_arms_at_start[name] or 0) > 0 then
                    mem.first_empty = { name = name, at = now }
                    break
                end
            end
        end
        if mem.first_empty and arms > 0 and now > mem.first_empty.at + R.salvo_time_s then
            return { kind = "home", why = string.format("salvo over: %s fired its last %d s ago, %d anti-radiation missile%s left aboard",
                mem.first_empty.name, math.floor(now - mem.first_empty.at), arms, arms == 1 and "" or "s") }
        end
        local p = { x = s.pos.x, z = s.pos.z }
        if a.site and a.launch then
            -- pressed on past where it may go: its press-on point (bug 36), or its launch
            -- point on a plan without one; its jet closest to the site counts
            local limit = a.press_on or a.launch
            local closest = math.huge
            for _, j in ipairs(s.jets) do closest = math.min(closest, Util.dist({ x = j.pos.x, z = j.pos.z }, a.site)) end
            local pressed = Util.dist(limit, a.site) - closest
            if pressed > R.press_km * 1000 then
                return { kind = "home", why = string.format("%.0f km past its %s toward %s", pressed / 1000,
                    a.press_on and "press-on point" or "launch point", a.groups and a.groups[1] or "its site") }
            end
            -- at its press-on point and still no radar to shoot at: home as planned (bug 36)
            if mem.pressed_on and arms > 0 and arms == mem.arms_at_start then
                return { kind = "home", why = string.format(
                    "no shot: pressed on to %.0f km from %s with no radar to shoot at, all %d anti-radiation missiles aboard",
                    Util.dist(p, a.site) / 1000, a.groups and a.groups[1] or "its site", arms) }
            end
            -- the attack clock starts when it gets there, however late (bugs.md 20): at its
            -- pop-up waypoint (ControlAirFlights.waypoint, bug 33), or within arrival_km of
            -- the launch point once it is up at the pop-up altitude (a missed waypoint)
            if not mem.arrived_s and Util.dist(p, a.launch) <= R.arrival_km * 1000
               and s.pos.y >= AIR_MISSION_TYPE.suppression_of_air_defenses.popup_altitude_m * 0.8 then
                mem.arrived_s = now
            end
        end
        -- not its own site, nor a ring its planned route was routed through on purpose; and
        -- not from the pop-up until the salvo is away: up there the other sites reach
        -- farther than their low figure, and that short exposure is the plan's (the
        -- launch point is cleared only of their low reach; roadmap item 12, bug 27), the
        -- press-on leg included (bug 36); asked for each jet, a jet in its shot area with
        -- missiles still aboard the flight left alone
        mem.accepted = mem.accepted or A.acceptedRings(m)
        local popping = a.launch and arms > 0 and function(q) return DirectivesPerFlight.inShotArea(m, q) end or nil
        local other, jet = A.flightKillZone(s, R.killzone_fraction, mem.accepted, true, popping)
        if other then return { kind = "home", why = insideText(s, jet, other) } end
        if mem.arrived_s and now > mem.arrived_s + R.attack_time_s then
            return { kind = "home", why = string.format("still on the attack %d min after it reached its launch point",
                math.floor(R.attack_time_s / 60)) }
        end
        -- said once: at its launch point a while and not one missile away (bug 29); a flight
        -- with a press-on point goes home from there instead (above)
        if not a.press_on and mem.arrived_s and not mem.no_shot and arms > 0 and arms == mem.arms_at_start
           and now > mem.arrived_s + R.no_shot_after_s then
            mem.no_shot = true
            ControlAirFlights.say(m.coalition, m.id, "no shot", string.format(
                "%d min after reaching its launch point, %.0f km from %s, all %d anti-radiation missiles still aboard",
                math.floor(R.no_shot_after_s / 60), a.site and Util.dist({ x = s.pos.x, z = s.pos.z }, a.site) / 1000 or 0,
                a.groups and a.groups[1] or "its site", arms))
        end
        return nil
    end,
}

-- ── handover (patrols) ──────────────────────────────────────────

DIRECTIVES.handover = {
    clock = "picture",
    on_task_only = true,
    check = function(w, s)
        if not s.airborne then return nil end
        local r = s.relief
        if not r then return nil end
        return { kind = "home", why = string.format("relieved by %s, on station (%.0f km from the race-track)", r.id, r.km) }
    end,
}

-- ── landing ─────────────────────────────────────────────────────

DIRECTIVES.landing = {
    clock = "picture",
    on_task_only = false,
    check = function(w, s)
        local L = AIR_CONTROL.landing
        local mem = w.memo.landing
        local m = s.mission
        local now = timer.getTime()
        -- an orphan: a jet still up long after its flight's last landing never comes down
        -- (bug 19: the wingman stays in its hold and flies a straight line, deaf to landing
        -- orders); removed, counted as landed, fight or not
        local record = ScheduleAirTaskingOrders.record(m.id)
        if s.airborne and record and record.last_landing_at
            and now - record.last_landing_at >= L.orphan_remove_after_s then
            local names, words = {}, {}
            for _, u in ipairs(s.units) do
                if u.airborne then
                    names[#names + 1] = u.name
                    words[#words + 1] = s.landing_base_pos
                        and string.format("%s %.0f km from %s", u.name, Util.dist({ x = u.pos.x, z = u.pos.z }, s.landing_base_pos) / 1000, m.landing_base)
                        or u.name
                end
            end
            return { kind = "remove", units = names,
                     why = string.format("%s still in the air %d min after %s landed; removed, counted as landed",
                         table.concat(words, ", "), math.floor((now - record.last_landing_at) / 60), record.last_landed or "its lead") }
        end
        if not s.airborne or w.defending then
            mem.closest = nil   -- a fight takes it anywhere: measure again afterwards
            return nil
        end
        local base = s.landing_base_pos
        if not base or (mem.orders or 0) >= L.max_orders then return nil end
        -- (a jet on the ground may also be a wingman not yet taken off: only the record's
        -- landings say one is home)
        local up, onGround = {}, false
        for _, u in ipairs(s.units) do
            if u.airborne then up[#up + 1] = u else onGround = true end
        end
        local landedOne = record and (record.landed or 0) > 0
        -- a jet of the flight just landed and another is still up: each one still up gets
        -- its own landing order at once (bug 19: the wingman left its hold the moment its
        -- lead touched down and flew a straight line; in the 2026-10-04 22:39 run 9 of 11
        -- two-ships ended that way; the group's order went to the lead on the ground)
        if landedOne and #up > 0 and onGround and mem.after_landing ~= record.last_landing_at then
            mem.after_landing = record.last_landing_at
            local names = {}
            for _, u in ipairs(up) do names[#names + 1] = u.name end
            return { kind = "land", why = string.format("%s landed, %s still in the air", record.last_landed or "a jet", table.concat(names, ", ")) }
        end
        local homebound = w.state == "going_home" or landedOne or (m.end_s and now > m.end_s)
        if not homebound then return nil end
        -- each jet's closest approach to its base since it was on its way home
        mem.closest = mem.closest or {}
        local lost
        for _, u in ipairs(up) do
            local d = Util.dist({ x = u.pos.x, z = u.pos.z }, base)
            local closest = math.min(mem.closest[u.name] or d, d)
            mem.closest[u.name] = closest
            if not lost and d > closest + L.away_km * 1000 then
                lost = string.format("%s lost after its landing: %.0f km from %s and getting farther (it was %.0f km away)",
                    u.name, d / 1000, m.landing_base, closest / 1000)
            end
        end
        -- overdue: counted from the planned landing, or from the last landing order
        if not lost and m.end_s and now > math.max(m.end_s, mem.ordered_at or 0) + L.overdue_s then
            lost = string.format("still in the air %d min after its planned landing", math.floor((now - m.end_s) / 60))
        end
        -- with a jet of it on the ground the order goes to each jet in the air on its own
        -- (GiveOrders.land), so a landed one isn't sent up again
        if not lost then return nil end
        return { kind = "land", why = lost }
    end,
}

-- ── self-defence ────────────────────────────────────────────────

local function km(m) return string.format("%.0f km", m / 1000) end

local function threatText(t)
    return string.format("%s (%s), %s, %s", t.group, t.type or "type unknown", km(t.range_m),
        t.aspect_deg <= AIR_CONTROL.self_defence.hot_aspect_deg and "hot" or string.format("aspect %.0f°", t.aspect_deg))
end

local function findThreat(s, group)
    for _, t in ipairs(s.threats) do
        if t.group == group then return t end
    end
    return nil
end

local function closingText(t)
    return string.format("%s %s kt", t.closing_mps >= 0 and "closing" or "opening",
        Util.thousands(math.abs(t.closing_mps) * 1.94384))
end

-- The kill zone a fight has taken the flight into, or nil: the rings its route passes
-- through on purpose don't count. A SEAD flight: no ring is accepted, its own target's
-- neither, outside its shot area; the kill zone is by height, so a fight that keeps it
-- low on its run-in goes on, one that climbs it into a ring is broken off (2026-10-02,
-- 16:50 run: MSN7023's fight took both Su-34s up to 14,000 ft inside the Patriot it was
-- sent against). Inside the shot area no ring breaks the fight off, as for the go cold
-- (bug 39: MSN2025_SEAD_AGAIN's fight was broken off at its pop-up for the Olenya SA-10).
-- A SEAD flight counts every live site, silenced or not, as it always has.
-- Every airborne jet is asked (a wingman fighting far from its lead, 2026-10-04 22:39
-- run); returns the site and the jet.
local function fightKillZone(s, mem, R)
    local m = s.mission
    if m.attack and m.attack.kind == "harm_salvo" then
        return A.flightKillZone(s, R.killzone_fraction, nil, true, function(q) return DirectivesPerFlight.inShotArea(m, q) end)
    end
    mem.accepted = mem.accepted or A.acceptedRings(m)
    return A.flightKillZone(s, R.killzone_fraction, mem.accepted)
end

-- Whether any airborne jet of a SEAD flight is in its shot area.
local function inShotAreaAny(s)
    for _, j in ipairs(s.jets) do
        if DirectivesPerFlight.inShotArea(s.mission, { x = j.pos.x, z = j.pos.z }) then return true end
    end
    return false
end

-- Whether a flight commits to bandit t. Every flight does, but a SEAD flight with its
-- anti-radiation missiles still aboard: it isn't the air-to-air asset; it stays low on its
-- route and leaves the fighter to the patrols, and turns to fight only when fired upon,
-- or (outside its shot area) when the bandit is inside sead_commit_km, too close to get
-- away from; in its shot area it finishes the salvo unless fired upon (John, 2026-10-02,
-- bug 39: in the 17:15 run fights cost 6 SEAD jets, sent one SEAD flight home 82 s after
-- takeoff and broke a salvo off after 3 of 8 missiles). Said once per bandit.
-- After its salvo it is still no hunter: on its way home it commits only when fired upon
-- or inside sead_commit_km, and otherwise keeps going (2026-10-04, John: option (a); in the
-- 2026-10-03 14:15 run the two rotations met head-on after their salvoes, committed at
-- 72-99 km, and 10 of the 15 jets lost were SEAD jets in those fights).
local function seadCommits(w, s, mem, R, t)
    local m = s.mission
    if not (m.attack and m.attack.kind == "harm_salvo") or t.fired then return true end
    local arms = s.anti_radiation_missiles
    local shooting = arms > 0 and inShotAreaAny(s)
    if not shooting and t.range_m <= R.sead_commit_km * 1000 then return true end
    mem.pressed_on = mem.pressed_on or {}
    if not mem.pressed_on[t.group] then
        mem.pressed_on[t.group] = true
        ControlAirFlights.say(m.coalition, m.id, "press on", string.format("bandit %s, %s; %s",
            threatText(t), closingText(t),
            arms == 0 and "salvo away, staying on its way home"
                or string.format("%s, %d anti-radiation missiles aboard",
                    shooting and "finishing its salvo first" or "staying low on its route", arms)))
    end
    return false
end

DIRECTIVES.self_defence = {
    clock = "fast",
    on_task_only = false,   -- a flight going home still shoots back
    check = function(w, s)
        local d = w.defending
        if not s.airborne then
            -- its fighting jet shot down with a wingman still on the ramp: the fight ends,
            -- so the next jet up starts clean (bug 48)
            if d then return { kind = "resume", why = "no jet of the flight left in the air" } end
            return nil
        end
        local R = AIR_CONTROL.self_defence
        local mem = w.memo.self_defence
        local now = timer.getTime()
        if d then
            -- in a fight: back to the mission when it's over
            mem.hot = nil
            local why
            local t = findThreat(s, d.group)
            if not A.liveGroup(d.group) then
                why = A.goneText(d.group)
            -- a bandit that just fired at the flight stays the fight for shot_memory_s
            -- whether the picture holds it or not (2026-10-02: MSN5024_SEAD dropped the
            -- F-15C that had just fired at it 4 s into the fight, Red's picture never held it)
            elseif not TrackRadarPicture.contact(s.coalition, d.group)
                and not (s.shot_at and s.shot_at.shooter_group == d.group) then
                why = d.group .. " lost from the radar picture"
            elseif s.air_to_air.radar_count == 0 then
                why = "out of radar missiles"
            elseif not t then
                why = d.group .. string.format(" beyond %d km", R.warning_range_km)
            elseif t.aspect_deg > R.cold_aspect_deg then
                why = d.group .. " turned cold"
            -- time is up, but never in the middle of the shots: not while a missile of the
            -- flight is still flying, nor within shot_memory_s of being fired upon
            -- (2026-10-04, after the 2026-10-03 14:15 run: both SEAD duels were timed out
            -- the moment the missiles were in the air, and the jets were hit 1-33 s later)
            elseif now - d.since > R.max_engage_s and s.own_missiles_in_flight == 0 and not s.shot_at then
                why = string.format("%d min on %s, time is up", math.floor(R.max_engage_s / 60), d.group)
            else
                local site, jet = fightKillZone(s, mem, R)
                if site then
                    why = "breaking off: " .. insideText(s, jet, site)
                    -- not that bandit again while the flight is still inside a kill zone
                    -- (17:15 run: MSN2025_SEAD_AGAIN defend, break off 5 s later, defend again)
                    mem.held_off = d.group
                end
            end
            if why then return { kind = "resume", why = why } end
            return nil
        end
        if mem.held_off and not fightKillZone(s, mem, R) then mem.held_off = nil end
        -- a bandit: hot on the flight (pointed at it and closing, within the warning
        -- range) for hot_checks_before_call checks in a row, or one that just fired at it
        local shooter = s.shot_at and s.shot_at.shooter_group
        local hot, bandits = {}, {}
        for _, t in ipairs(s.threats) do
            if t.aspect_deg <= R.hot_aspect_deg and t.closing_mps >= R.min_closing_speed_mps then
                hot[t.group] = (mem.hot and mem.hot[t.group] or 0) + 1
            end
            if t.group == shooter or (hot[t.group] or 0) >= R.hot_checks_before_call then
                t.fired = t.group == shooter
                if t.group ~= mem.held_off and seadCommits(w, s, mem, R, t) then bandits[#bandits + 1] = t end
            end
        end
        mem.hot = hot
        if #bandits == 0 then return nil end
        -- can fight: commit now; can't: leave
        if s.air_to_air.radar_count > 0 then
            if mem.last_resume and now - mem.last_resume < R.reengage_after_s then return nil end
            return { kind = "defend", threats = bandits }
        end
        if w.state == "going_home" then return nil end
        local b = bandits[1]
        return { kind = "home", why = string.format("bandit %s, %s%s; %s", threatText(b), closingText(b),
            b.fired and ", it fired at the flight" or "",
            s.air_to_air.count > 0 and "only infrared missiles aboard" or "no air-to-air missiles aboard") }
    end,
}

-- ── calls for the controller ────────────────────────────────────

-- True when SEAD flight m at p is where its plan takes it up to shoot: from popup_km
-- (+ 2 km) before its launch point through its press-on leg. The other sites' reach
-- there is the plan's accepted exposure.
function DirectivesPerFlight.inShotArea(m, p)
    local a = m.attack or {}
    if not a.launch then return false end
    local margin = 2000
    if Util.dist(p, a.launch) <= AIR_MISSION_TYPE.suppression_of_air_defenses.popup_km * 1000 + margin then return true end
    return a.press_on ~= nil and Util.dist(p, a.press_on) <= Util.dist(a.launch, a.press_on) + margin
end

function DirectivesPerFlight.get(name)
    return DIRECTIVES[name]
end

-- One line on a threat, for the event log.
DirectivesPerFlight.threatText = threatText

-- Fails loudly at load time on a directive name the data asks for that doesn't exist.
function DirectivesPerFlight.checkData()
    for missionType, names in pairs(AIR_CONTROL.directives_by_mission_type) do
        for _, name in ipairs(names) do
            if not DIRECTIVES[name] then
                error(string.format("AIR_CONTROL.directives_by_mission_type.%s: unknown directive '%s'", missionType, name))
            end
        end
    end
end
