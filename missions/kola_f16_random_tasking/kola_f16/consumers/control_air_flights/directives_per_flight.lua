-- Consumer part of the controller (control_air_flights.lua): the directives a controller
-- gives one flight, each a check of the flight's situation
-- (assess_flight_situations.lua) that returns an intent, or nil to leave the flight as it
-- is. Settings in data/air_control.lua; which flights get which directives:
-- AIR_CONTROL.directives_by_mission_type.
--
-- An intent is { kind, why, … }:
--   home        go home now, returning fire only ("going home: <why>")
--   stand_down  still on the ramp: removed, never flies
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
--   suppression   SEAD flights: go cold after the salvo (see data/air_control.lua)
--   self_defence  attack flights: a bandit hot on the flight is called at once; a flight
--                 with radar missiles engages it, then carries on with its mission; one
--                 without leaves (goes home)
--
-- New directives are one more entry here and one more name in
-- AIR_CONTROL.directives_by_mission_type.

DirectivesPerFlight = {}

local A = AssessFlightSituations

local DIRECTIVES = {}

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
                why = why or (name .. " destroyed")
            end
        end
        local raidGone = why ~= nil
        if not s.airborne then
            if raidGone and not w.airborne_once then return { kind = "stand_down", why = why } end
            return nil
        end
        if raidGone then return { kind = "home", why = why } end
        local depth = A.enemyDepth(c, { x = s.pos.x, z = s.pos.z }, L.front_search_km * 1000)
        if depth > L.enemy_airspace_km * 1000 then
            return { kind = "home", why = depth == math.huge and "deep in enemy airspace"
                or string.format("%.0f km into enemy airspace", depth / 1000) }
        end
        local site = A.enemyKillZone(c, s.pos, L.killzone_fraction)
        if site then return { kind = "home", why = "inside the kill zone of " .. site } end
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
        if a.site and a.launch then
            local p = { x = s.pos.x, z = s.pos.z }
            local pressed = Util.dist(a.launch, a.site) - Util.dist(p, a.site)
            if pressed > R.press_km * 1000 then
                return { kind = "home", why = string.format("%.0f km past its launch point toward %s", pressed / 1000,
                    a.groups and a.groups[1] or "its site") }
            end
            -- the attack clock starts when it gets there, however late (bugs.md 20)
            if not mem.arrived_s and Util.dist(p, a.launch) <= R.arrival_km * 1000 then mem.arrived_s = now end
        end
        -- not its own site, nor a ring its planned route was routed through on purpose
        mem.accepted = mem.accepted or A.acceptedRings(m)
        local other = A.enemyKillZone(m.coalition, s.pos, R.killzone_fraction, mem.accepted)
        if other then return { kind = "home", why = "inside the kill zone of " .. other } end
        if mem.arrived_s and now > mem.arrived_s + R.attack_time_s then
            return { kind = "home", why = string.format("still on the attack %d min after it reached its launch point",
                math.floor(R.attack_time_s / 60)) }
        end
        return nil
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

DIRECTIVES.self_defence = {
    clock = "fast",
    on_task_only = false,   -- a flight going home still shoots back
    check = function(w, s)
        if not s.airborne then return nil end
        local R = AIR_CONTROL.self_defence
        local mem = w.memo.self_defence
        local now = timer.getTime()
        local d = w.defending
        if d then
            -- in a fight: back to the mission when it's over
            mem.hot = nil
            local why
            local t = findThreat(s, d.group)
            if not A.liveGroup(d.group) then
                why = d.group .. " destroyed"
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
            elseif now - d.since > R.max_engage_s then
                why = string.format("%d min on %s, time is up", math.floor(R.max_engage_s / 60), d.group)
            else
                mem.accepted = mem.accepted or A.acceptedRings(s.mission)
                local site = A.enemyKillZone(s.coalition, s.pos, R.killzone_fraction, mem.accepted)
                if site then why = "breaking off: inside the kill zone of " .. site end
            end
            if why then return { kind = "resume", why = why } end
            return nil
        end
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
                bandits[#bandits + 1] = t
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
