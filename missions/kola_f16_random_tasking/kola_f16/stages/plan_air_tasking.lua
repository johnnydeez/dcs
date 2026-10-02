-- Stages 5–6: the air tasking orders — each coalition's air plan over the mission window.
-- Defensive air first ("support up first"): one AWACS, combat air patrols rotating over
-- stations near the front, and (when planned) the scramble posture (the alert bases;
-- the controller (consumers/control_air_flights/) scrambles on the radar picture at run time). Then the ground attack
-- missions: strike, airfield strike and destruction of air defenses, one flight per
-- mission, each with the suppression flights its route needs (a package), filling what
-- the airborne cap leaves. Each coalition is planned from the target catalog and its own
-- bases only, never from the other coalition's air plan (plan.md, "No side reads the other side's plan").
-- Reads plan.world, plan.territory, plan.target_catalog, the planned units and static
-- objects (for the positions of each target's critical objects) and the enemy SAM sites
-- and base defenses (the threats routes go around) + data/air_tasking.lua,
-- data/aircraft_profiles.lua, data/aircraft_loadouts.lua and COALITION_AIRCRAFT. Writes
-- plan.air_tasking_orders. Spawns nothing; the scheduler consumer spawns each flight at
-- its start time.
--
-- Per mission: a mission type (weighted) → an aircraft type (roster) → an enemy target
-- of that type near the front — in the contested airspace or at most
-- AIR_TARGETING.max_km_past_contested beyond it (plan.airspace) — within the aircraft's
-- reach from a base that can launch it, in the own region facing the target, so no
-- flight crosses enemy ground to another front (weighted by value; no target is hit
-- twice) → the launch base (one of the three nearest that fit)
-- → the route → its suppression flights, if the route crosses threat rings → start times
-- that keep the coalition under its planned cap (plannedCap) → parking spots free at those times
-- → the attack tasks. A mission whose suppression can't be planned isn't flown; another
-- target is tried.
--
-- Routes (data/air_tasking.lua AIR_ROUTING, lib/threat_routing.lua): every km is priced
-- by the airspace it lies in (own, contested, enemy: airspace_cost), so routes keep to
-- own airspace and cross the contested zone where it's narrowest; a route that ends up
-- deeper in enemy airspace than its target (plus a slack) isn't flown. Flights cruise at
-- least 7,500 m, above guns, shoulder-launched missiles and short-range SAMs, and route
-- around the enemy threats that reach higher (medium- and long-range SAM rings, Pantsir /
-- Tor-M2 at enemy bases) when the way around is at most max_detour × direct and within
-- reach. A route that still crosses a ring marks the mission needs_suppression, listing
-- the threats in suppression_threats in the order the route meets them. Cruise altitude
-- holds until a descent point before the ingress; from the ingress over the target the
-- flight is at its attack altitude for that mission type.
--
-- Packages (AIR_PACKAGE): an AI package flies in sequence (John, 2026-10-01): its
-- suppression flights first, then, strike_after_suppression_s after they're planned to
-- land, the mission; each flight is held under the cap only for its own time in the air,
-- so a package needs room for one flight at a time. A threat an earlier suppression
-- flight already takes (ctx.cleared) gets no new flight: the mission starts after that
-- one lands (rolling the air defenses back). At run time the mission launches only once
-- its threats are dead (the scheduler). A package with a human flight flies together,
-- its AI suppression flights first thing (below). The threats are shared out in route
-- order between suppression flights. A threat is one or more DCS groups: a SAM site and its point-defense escort
-- (engaged together, so the escort can't shoot the missiles down unopposed), or a
-- base-defense group. Each flight takes one threat (John, 2026-10-01): it flies around
-- the other threats to a launch point launch_km from the site, runs in low and pops up,
-- fires every anti-radiation missile at the site's group there (harm_salvo) and comes
-- straight back the way it went (suppressionRoute).
-- In a human package it takes off as early as it can (first_start_s on) and is over the
-- target at least suppression_lead_s before the player.
--
-- Defensive air (AIR_DEFENSE, only when AIR_DEFENSE.planned): patrol stations deny the
-- own and contested airspace over the coalition's sites near the front (planStations):
-- each covers a circle of sites, its defended zone, and its race-track sits as close to
-- them as it can on own held ground, out of enemy kill zones (a fraction of each ring:
-- AIR_DEFENSE.killzone_fraction; attack flights keep to the full ring + margin). Its
-- patrols also engage enemy aircraft over the own and contested airspace of its sector
-- (its commit circles). Each is held on_station_s by
-- one flight after another from bases in the station's region, overlapping
-- rotation_overlap_s. The AWACS takes off from the runway of its base farthest from the
-- enemy at mission start and orbits, in own airspace, as far forward as
-- early_warning_standoff_km allows, until the window ends. The alert posture only with
-- AIR_DEFENSE.alert_posture_planned.
--
-- Human flights (HUMAN_TASKING, after defensive air and before the AI attack missions):
-- for the players' coalition, HUMAN_TASKING.missions flights of one aircraft from held
-- bases with a player slot, any mission type a player can fly, planned with the same
-- targets, routes and packages as the AI's but timed from mission start (takeoff after
-- startup_s); the AI flights of their packages are timed around them. Not spawned.
--
-- plan.air_tasking_orders = {
--   red  = { missions = { mission }, packages = { package }, human_missions = { mission ids },
--            stations = { { id, kind (front | early_warning), home, region, centre,
--                           ends = { a, b }, defends = { catalog ids }, defended_value,
--                           zone = { x, z, radius_m }, commit = { { x, z, radius_m } },
--                           label, patrols } },
--            alert = { bases = { { base, code, region, aircraft = { { type, weight } }, pos,
--                                  enemy_km, alert_aircraft, cooldown_s } },
--                      max_airborne_aircraft, first_number },
--            summary = { missions, suppression_flights, flights, by_type, not_planned,
--                        failures = { reason = n }, patrols, stations, early_warning,
--                        alert_bases } },
--   blue = … ,
-- }
-- Patrols and the AWACS are missions too, with station = their station id; their target
-- is the station, their attack = { kind, station = { x1, z1, x2, z2 }, altitude_m,
-- speed_mps, until_s, engage_range_m, zone (patrols: the station's defended zone),
-- commit (patrols: the circles of their commit area) }.
-- package = { id, mission (the escorted mission's id), suppression_flights = { ids }, tot_s }
-- mission = { id, number, coalition, package, mission_type, group_task,
--   flown_by ("ai" | "human"), player_slot = { group, spot, terminal_index } (human), target,
--   target_label, target_kind, target_pos, aircraft_type, count, skill, launch_base,
--   landing_base, parking = { { terminal_index, x, z } } (one per aircraft, lead first),
--   start_s, takeoff_s, tot_s, end_s, distance_km, route_km,
--   route = { { kind, x, z, alt_m, speed_mps, carries_attack_tasks } },
--   attack = { kind, points = { { x, z } } | groups = { DCS group names }, weapon_type,
--              expend },
--   return_when_out_of (weapon mask or nil), loadout = { … }, keeps_gun, may_jettison, success,
--   critical_names,
--   needs_suppression, suppression_threats = { threat ids the route crosses },
--   suppressed_by = { suppression flight ids }        (escorted missions)
--   cleared_by = { threat id → the suppression flight that takes it }, own or an earlier
--     package's; requires_cleared = { threat ids } (AI missions flown in sequence: the
--     scheduler launches the mission only once these are dead)
--   escorts, suppresses = { threat ids it takes } } (suppression flights; attack.groups
--   holds their groups, escorts included)
--   front, facing_region, target_depth_km, enemy_airspace_km   (ground attack and
--   suppression flights: the target's front, the own region flying against it, how far
--   past the contested airspace the target lies, km of the way out in enemy airspace)
--   route kinds: takeoff, departure, transit, descent, ingress, target, egress, landing,
--   and for patrols and the AWACS station (orbit start) and station_end;
--   the attack tasks go on the waypoint with carries_attack_tasks
--   times are mission time in seconds (timer.getTime())
-- Ids: MSN<number>_<mission type's group_name_tag> (MSN2002_CAP), the DCS group name; Blue
-- numbers from 2001, Red from 7001 (plan.md "Naming and ids"; Red was 5001 until 2026-10-02, bug 21); scrambles, spawned at run
-- time, from 2901 / 7901 (MSN2901_SCRAM). Units are <id>_<n>. A package
-- is PKG<number of the mission it escorts>; a station CAP_<CODE>_<kind>_<n> / AEW_<CODE>_1.

PlanAirTasking = {}

local COALITIONS     = { "red", "blue" }
local FIRST_NUMBER   = { blue = 2001, red = 7001 }
local ATTACKS        = { bomb_critical_objects = true, attack_group = true, engage_group = true, engage_in_zone = true,
                         harm_salvo = true,
                         engage_aircraft_on_station = true, early_warning_on_station = true, intercept = true }
local PLANNED_AS     = { mission = true, escort = true, station = true, response = true }
local RULES          = { open_fire = true, weapons_free = true, weapons_hold = true }
local TAKEOFFS       = { parking = true, runway = true }
local PATROL         = "combat_air_patrol"
local EARLY_WARNING  = "airborne_early_warning"
local INTERCEPTION   = "interception"
local BASE_CLASSES   = { hub = true, fighter = true, bomber = true, dispersal = true, strip = true, heli = true }
local SUPPRESSION    = "suppression_of_air_defenses"
local MISSION_TRIES  = 8     -- aircraft/target picks tried per mission
local START_TRIES    = 60    -- start times tried per package
local AIRCRAFT_TRIES = 4     -- aircraft picks tried per suppression flight
local NEAREST_BASES  = 3     -- the launch base is one of this many nearest that fit
local DEPARTURE_KM   = 20    -- the climb-out point, this far from the base toward the ingress
local SAME_POINT_M   = 30    -- attack points closer than this are one point
local REACH_FACTOR   = 1.2   -- a leg may be this much longer than the combat radius

local function round(v) return math.floor(v + 0.5) end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function clock(s)
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- ── data checks ─────────────────────────────────────────────────

function PlanAirTasking.validate()
    local problems = {}
    local function bad(msg) problems[#problems + 1] = msg end

    for mt, m in pairs(AIR_MISSION_TYPE) do
        if not ATTACKS[m.attack] then bad(string.format("mission type '%s': attack '%s' is unknown", mt, tostring(m.attack))) end
        if not AIR_WEAPON_TYPE[m.weapon_type] then bad(string.format("mission type '%s': weapon_type '%s' is unknown", mt, tostring(m.weapon_type))) end
        if m.return_when_out_of and not AIR_WEAPON_TYPE[m.return_when_out_of] then
            bad(string.format("mission type '%s': return_when_out_of '%s' is unknown", mt, tostring(m.return_when_out_of)))
        end
        if type(m.group_task) ~= "string" then bad(string.format("mission type '%s' needs a group_task", mt)) end
        if type(m.ingress_km) ~= "number" or type(m.egress_km) ~= "number" then
            bad(string.format("mission type '%s' needs ingress_km and egress_km", mt))
        end
        if m.attack == "bomb_critical_objects" and type(m.max_attack_points) ~= "number" then
            bad(string.format("mission type '%s' needs max_attack_points", mt))
        end
        if m.planned_as and not PLANNED_AS[m.planned_as] then
            bad(string.format("mission type '%s': planned_as '%s' is unknown", mt, tostring(m.planned_as)))
        end
        if m.rules_of_engagement and not RULES[m.rules_of_engagement] then
            bad(string.format("mission type '%s': rules_of_engagement '%s' is unknown", mt, tostring(m.rules_of_engagement)))
        end
        if m.takeoff and not TAKEOFFS[m.takeoff] then
            bad(string.format("mission type '%s': takeoff '%s' is unknown", mt, tostring(m.takeoff)))
        end
        if type(m.group_name_tag) ~= "string" or not m.group_name_tag:match("^%u+$") then
            bad(string.format("mission type '%s' needs a group_name_tag in capital letters", mt))
        end
        if m.flight_size and (type(m.flight_size) ~= "table" or #m.flight_size ~= 2 or m.flight_size[1] > m.flight_size[2]) then
            bad(string.format("mission type '%s': flight_size must be { min, max }", mt))
        end
        if m.attack == "engage_aircraft_on_station" and type(m.engage_range_km) ~= "number" then
            bad(string.format("mission type '%s' needs engage_range_km", mt))
        end
    end
    for _, mt in ipairs({ PATROL, EARLY_WARNING, INTERCEPTION }) do
        local m = AIR_MISSION_TYPE[mt]
        if not (m and m.built) then bad(mt .. " must be a built mission type (defensive air needs it)") end
    end
    for _, f in ipairs({ "max_stations", "defended_depth_km", "min_defended_value", "min_zone_radius_km",
                         "station_spacing_km", "station_leg_km", "station_clearance_km", "step_km", "on_station_s", "rotation_overlap_s",
                         "station_enemy_airspace_km", "commit_range_km", "commit_spacing_km", "commit_radius_km",
                         "commit_min_radius_km",
                         "early_warning_standoff_km", "early_warning_clearance_km", "early_warning_leg_km",
                         "alert_bases", "alert_aircraft_per_base", "scramble_turnaround_s", "scramble_cooldown_s", "scramble_warning_min",
                         "scramble_inbound_rounds", "scramble_reserve_aircraft", "scramble_takeoff_s",
                         "scramble_min_leg_km", "raid_radius_km", "raid_heading_deg" }) do
        if type(AIR_DEFENSE[f]) ~= "number" or AIR_DEFENSE[f] < 0 then bad("AIR_DEFENSE needs a non-negative " .. f) end
    end
    local reaction = AIR_DEFENSE.scramble_reaction_s
    if type(reaction) ~= "table" or type(reaction[1]) ~= "number" or type(reaction[2]) ~= "number"
       or reaction[1] < 0 or reaction[1] > reaction[2] then
        bad("AIR_DEFENSE.scramble_reaction_s must be { min, max } seconds")
    end
    if type(AIR_DEFENSE.killzone_fraction) ~= "number" or AIR_DEFENSE.killzone_fraction <= 0
       or AIR_DEFENSE.killzone_fraction > 1 then
        bad("AIR_DEFENSE.killzone_fraction must be more than 0 and at most 1")
    end
    if AIR_DEFENSE.rotation_overlap_s >= AIR_DEFENSE.on_station_s then
        bad("AIR_DEFENSE.rotation_overlap_s must be shorter than on_station_s")
    end
    local sead = AIR_MISSION_TYPE[SUPPRESSION]
    if not (sead and sead.built and sead.planned_as == "escort" and sead.attack == "harm_salvo") then
        bad(SUPPRESSION .. " must be a built harm_salvo mission type planned_as escort (packages need it)")
    else
        for _, f in ipairs({ "launch_km", "low_altitude_m", "low_speed_mps", "low_entry_margin_km", "low_waypoint_km",
                             "popup_km", "popup_altitude_m", "low_fuel_factor" }) do
            if type(sead[f]) ~= "number" or sead[f] <= 0 then bad(SUPPRESSION .. " needs a positive " .. f) end
        end
        -- the launch point is only cleared of other sites' low-altitude reach, which holds up
        -- to killzone_low_altitude_m: the pop-up must stay below it
        if type(sead.popup_altitude_m) == "number" and sead.popup_altitude_m > AIR_DEFENSE.killzone_low_altitude_m then
            bad(SUPPRESSION .. ".popup_altitude_m must be at most AIR_DEFENSE.killzone_low_altitude_m")
        end
        if type(AIR_PACKAGE.strike_after_suppression_s) ~= "number" or type(AIR_PACKAGE.wait_for_room_s) ~= "number" then
            bad("AIR_PACKAGE needs strike_after_suppression_s and wait_for_room_s")
        end
    end
    for _, k in ipairs({ "own", "contested", "enemy" }) do
        local v = AIR_ROUTING.airspace_cost and AIR_ROUTING.airspace_cost[k]
        if type(v) ~= "number" or v < 1 then bad("AIR_ROUTING.airspace_cost needs " .. k .. " of at least 1") end
    end
    for _, f in ipairs({ "max_km_past_contested", "facing_search_km", "enemy_airspace_slack_km" }) do
        if type(AIR_TARGETING[f]) ~= "number" or AIR_TARGETING[f] < 0 then bad("AIR_TARGETING needs a non-negative " .. f) end
    end
    local lead = AIR_PACKAGE and AIR_PACKAGE.suppression_lead_s
    if type(lead) ~= "table" or type(lead[1]) ~= "number" or type(lead[2]) ~= "number" or lead[1] > lead[2] then
        bad("AIR_PACKAGE needs suppression_lead_s = { min, max }")
    end
    local H = HUMAN_TASKING
    if type(H) ~= "table" then
        bad("HUMAN_TASKING is missing")
    else
        if type(H.missions) ~= "number" or H.missions < 0 then bad("HUMAN_TASKING needs a non-negative missions") end
        if H.coalition ~= "red" and H.coalition ~= "blue" then bad("HUMAN_TASKING.coalition must be red or blue") end
        local t = H.aircraft_type
        if not AIRCRAFT_PROFILE[t] then bad(string.format("HUMAN_TASKING: aircraft_type '%s' has no profile", tostring(t))) end
        local s = H.startup_s
        if type(s) ~= "table" or type(s[1]) ~= "number" or type(s[2]) ~= "number" or s[1] > s[2] then
            bad("HUMAN_TASKING needs startup_s = { min, max }")
        end
        for _, e in ipairs(H.mission_types or {}) do
            local m = AIR_MISSION_TYPE[e[1]]
            local as = m and (m.planned_as or "mission")
            if not (m and m.built) then
                bad(string.format("HUMAN_TASKING: '%s' is not a built mission type", tostring(e[1])))
            elseif as ~= "mission" and e[1] ~= SUPPRESSION and e[1] ~= PATROL then
                bad(string.format("HUMAN_TASKING: '%s' is planned as %s, which players can't fly", e[1], as))
            end
            if AIRCRAFT_PROFILE[t] and m and e[1] ~= SUPPRESSION and e[1] ~= PATROL
               and type(AIRCRAFT_PROFILE[t].attack_altitude_m[e[1]]) ~= "number" then
                bad(string.format("HUMAN_TASKING: profile '%s' has no attack_altitude_m.%s", t, e[1]))
            end
            if not (AIRCRAFT_LOADOUT[t] and AIRCRAFT_LOADOUT[t][e[1]]) then
                bad(string.format("HUMAN_TASKING: '%s' has no %s loadout (the brief lists it)", tostring(t), e[1]))
            end
            if type(e[2]) ~= "number" or e[2] <= 0 then bad(string.format("HUMAN_TASKING: '%s' needs a positive weight", e[1])) end
        end
    end

    for t, p in pairs(AIRCRAFT_PROFILE) do
        local where = "profile '" .. t .. "'"
        if not UNIT_POOL.plane[t] then bad(where .. ": not a plane in UNIT_POOL") end
        for _, c in ipairs(p.base_classes or {}) do
            if not BASE_CLASSES[c] then bad(string.format("%s: base class '%s' is unknown", where, tostring(c))) end
        end
        if p.base_classes ~= nil and (type(p.base_classes) ~= "table" or #p.base_classes == 0) then
            bad(where .. ": base_classes, when given, must list at least one class")
        end
        if type(p.parking) ~= "table" or #p.parking == 0 then bad(where .. " needs parking terminal types") end
        if type(p.flight_size) ~= "table" or #p.flight_size ~= 2 or p.flight_size[1] > p.flight_size[2] then
            bad(where .. " needs flight_size = { min, max }")
        end
        for _, f in ipairs({ "min_runway_m", "combat_radius_km", "cruise_speed_mps", "cruise_altitude_m" }) do
            if type(p[f]) ~= "number" or p[f] <= 0 then bad(string.format("%s needs a positive %s", where, f)) end
        end
        if type(p.cruise_altitude_m) == "number" and p.cruise_altitude_m < AIR_ROUTING.min_cruise_altitude_m then
            bad(string.format("%s: cruise_altitude_m below AIR_ROUTING.min_cruise_altitude_m (%d)", where,
                AIR_ROUTING.min_cruise_altitude_m))
        end
        if type(p.attack_altitude_m) ~= "table" then bad(where .. " needs attack_altitude_m = { mission type = m }") end
    end

    for _, c in ipairs(COALITIONS) do
        for mt, list in pairs(COALITION_AIRCRAFT[c] or {}) do
            if not AIR_MISSION_TYPE[mt] then bad(string.format("COALITION_AIRCRAFT.%s: '%s' is not a mission type", c, mt)) end
            for _, e in ipairs(list) do
                local t = e[1]
                if not AIRCRAFT_PROFILE[t] then bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' has no profile", c, mt, t)) end
                if not (AIRCRAFT_LOADOUT[t] and AIRCRAFT_LOADOUT[t][mt]) then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' has no %s loadout (kola_data_tools/aircraft_loadouts.py)", c, mt, t, mt))
                end
                local p = AIRCRAFT_PROFILE[t]
                -- (a SEAD flight's altitudes are the mission type's: suppressionRoute)
                if p and mt ~= SUPPRESSION and type(p.attack_altitude_m) == "table" and type(p.attack_altitude_m[mt]) ~= "number" then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: profile '%s' has no attack_altitude_m.%s", c, mt, t, mt))
                end
                if p and mt == INTERCEPTION and (type(p.dash_speed_mps) ~= "number" or p.dash_speed_mps <= 0) then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: profile '%s' needs a positive dash_speed_mps", c, mt, t))
                end
                if p and mt == SUPPRESSION and (type(p.anti_radiation_missiles) ~= "number" or p.anti_radiation_missiles <= 0) then
                    bad(string.format("COALITION_AIRCRAFT.%s.%s: profile '%s' needs a positive anti_radiation_missiles", c, mt, t))
                end
                if type(e[2]) ~= "number" or e[2] <= 0 then bad(string.format("COALITION_AIRCRAFT.%s.%s: '%s' needs a positive weight", c, mt, t)) end
            end
        end
        for _, mt in ipairs({ SUPPRESSION, PATROL, EARLY_WARNING, INTERCEPTION }) do
            if not (COALITION_AIRCRAFT[c] and COALITION_AIRCRAFT[c][mt]) then
                bad(string.format("COALITION_AIRCRAFT.%s has no %s roster", c, mt))
            end
        end
        local per = AIR_TASKING_PER_COALITION[c]
        if not per then
            bad("AIR_TASKING_PER_COALITION has no " .. c)
        else
            if type(per.max_airborne_aircraft) ~= "number" or per.max_airborne_aircraft <= 0 then
                bad(string.format("AIR_TASKING_PER_COALITION.%s needs a positive max_airborne_aircraft", c))
            elseif type(AIR_DEFENSE.scramble_reserve_aircraft) == "number"
                   and AIR_DEFENSE.scramble_reserve_aircraft >= per.max_airborne_aircraft then
                bad(string.format("AIR_TASKING_PER_COALITION.%s: max_airborne_aircraft must be more than "
                    .. "AIR_DEFENSE.scramble_reserve_aircraft", c))
            end
            for _, e in ipairs(per.mission_types or {}) do
                local m = AIR_MISSION_TYPE[e[1]]
                if not m then bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' is not a mission type", c, e[1])) end
                if m and (m.planned_as or "mission") ~= "mission" then
                    bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' is planned as %s, not from mission_types", c, e[1], m.planned_as))
                end
                if m and m.built and not (COALITION_AIRCRAFT[c] and COALITION_AIRCRAFT[c][e[1]]) then
                    bad(string.format("AIR_TASKING_PER_COALITION.%s: '%s' has no COALITION_AIRCRAFT roster", c, e[1]))
                end
            end
        end
    end
    return problems
end

local _problems
function PlanAirTasking.checkData()
    if not _problems then
        _problems = PlanAirTasking.validate()
        for _, p in ipairs(_problems) do Log.error("air tasking data: " .. p) end
        if #_problems == 0 then Log.info("air tasking data: OK") end
    end
    return _problems
end

-- ── what's where ────────────────────────────────────────────────

-- Every planned unit and static object by DCS name → { x, z }.
local function objectPositions(plan)
    local pos = {}
    local function addGroups(groups)
        for _, g in ipairs(groups or {}) do
            for i, u in ipairs(g.units) do pos[g.id .. "_" .. i] = { x = u.x, z = u.z } end
        end
    end
    addGroups(plan.sam_sites and plan.sam_sites.groups)
    addGroups(plan.fixed_ground_targets and plan.fixed_ground_targets.groups)
    addGroups(plan.convoys and plan.convoys.groups)
    for _, o in ipairs(plan.fixed_ground_targets and plan.fixed_ground_targets.static_objects or {}) do
        pos[o.id] = { x = o.x, z = o.z }
    end
    return pos
end

local function longestRunway(ab)
    local m = 0
    for _, r in ipairs(ab.runways or {}) do if r.length > m then m = r.length end end
    return m
end

-- The enemy medium / long-range SAM site whose low-altitude kill zone holds pos (a base:
-- jets leave it low), or nil (lib/sam_reach.lua).
local function underEnemySam(ctx, pos)
    for _, s in ipairs(ctx.plan.sam_sites and ctx.plan.sam_sites.sites or {}) do
        if s.side ~= ctx.coalition and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0
           and Util.dist(pos, s.pos) < SamReach.killZone(s, 0) then
            return s.id
        end
    end
    return nil
end

-- The coalition's bases that can launch this aircraft type: runway and parking type, and
-- for the heavies (profiles with base_classes) the base's class. Never a base inside an
-- enemy SAM's low-altitude kill zone (John, 2026-10-01: no flights up into instant death).
local function launchBases(ctx, aircraftType)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local classes, terminals = nil, {}
    if p.base_classes then
        classes = {}
        for _, c in ipairs(p.base_classes) do classes[c] = true end
    end
    for _, t in ipairs(p.parking) do terminals[t] = true end
    local out = {}
    for _, name in ipairs(ctx.held) do
        local ab = ctx.plan.world.airbases[name]
        if (not classes or classes[AIRBASE_CLASS[name]]) and longestRunway(ab) >= p.min_runway_m
           and not underEnemySam(ctx, ab.pos) then
            local spots = 0
            for _, s in ipairs(ab.parking) do if terminals[s[3]] then spots = spots + 1 end end
            if spots >= p.flight_size[2] then out[#out + 1] = name end
        end
    end
    return out
end

-- ── parking ─────────────────────────────────────────────────────

-- Free spots of the right types at `base` for `count` aircraft, held from start_s, lead's
-- spot first and the others nearest to it, plus the reservations made (for release); or nil.
local function reserveParking(ctx, base, aircraftType, count, start_s)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local terminals = {}
    for _, t in ipairs(p.parking) do terminals[t] = true end
    local busy = ctx.parking_busy[base] or {}
    ctx.parking_busy[base] = busy
    local hold = AIR_TASKING_TIMING.parking_hold_s
    local statics = ctx.plan.fixed_ground_targets and ctx.plan.fixed_ground_targets.parking_used[base] or {}
    local ab = ctx.plan.world.airbases[base]
    local free = {}
    for _, s in ipairs(ab.parking) do
        local idx = s[4]
        local taken = statics[idx] ~= nil or ab.player_slots[idx] ~= nil
        for _, span in ipairs(busy[idx] or {}) do
            if start_s < span[2] and start_s + hold > span[1] then taken = true end
        end
        if terminals[s[3]] and not taken then free[#free + 1] = s end
    end
    if #free < count then return nil end
    local lead = Util.pick(free)
    table.sort(free, function(a, b)
        return (a[1] - lead[1]) ^ 2 + (a[2] - lead[2]) ^ 2 < (b[1] - lead[1]) ^ 2 + (b[2] - lead[2]) ^ 2
    end)
    local spots, held = {}, {}
    for i = 1, count do
        local s = free[i]
        spots[i] = s
        busy[s[4]] = busy[s[4]] or {}
        local span = { start_s, start_s + hold }
        table.insert(busy[s[4]], span)
        held[#held + 1] = { list = busy[s[4]], span = span }
    end
    return spots, held
end

local function releaseParking(held)
    for _, h in ipairs(held) do
        for i, span in ipairs(h.list) do
            if span == h.span then table.remove(h.list, i) break end
        end
    end
end

-- ── route and timing ────────────────────────────────────────────

local function offset(from, towards, km)
    local d = Util.dist(from, towards)
    if d < 1 then return { x = from.x, z = from.z } end
    local f = km * 1000 / d
    return { x = from.x + (towards.x - from.x) * f, z = from.z + (towards.z - from.z) * f }
end

-- The point `d` metres along a polyline, and the polyline's points strictly before it.
local function cutAt(points, d)
    local before = { points[1] }
    for i = 2, #points do
        local seg = Util.dist(points[i - 1], points[i])
        if d <= seg then
            local t = seg > 0 and d / seg or 0
            local a, b = points[i - 1], points[i]
            return { x = a.x + t * (b.x - a.x), z = a.z + t * (b.z - a.z) }, before
        end
        d = d - seg
        before[#before + 1] = points[i]
    end
    return points[#points], before
end

-- The route between two points around the coalition's threat map: the way round if it
-- is at most max_detour × direct and within reach, else straight through. The search only
-- looks at paths within that length; searches are cached per coalition, since retried
-- missions ask for the same base → target legs. `map` is the threat map to route around:
-- ctx.threats (attack flights, the default), ctx.low_threats (a SEAD flight's low run-in)
-- or ctx.station_threats (patrols, the AWACS).
local function threatRoute(ctx, from, to, reach_m, map)
    map = map or ctx.threats
    local maxLength = math.min(AIR_ROUTING.max_detour * Util.dist(from, to), reach_m)
    local key = string.format("%s%d,%d>%d,%d<%d", map == ctx.threats and "" or map == ctx.low_threats and "low " or "station ",
        round(from.x), round(from.z), round(to.x), round(to.z), round(maxLength))
    local path = ctx.routes[key]
    if not path then
        path = ThreatRouting.route(map, from, to, maxLength)
        ctx.routes[key] = path
    end
    local len = ThreatRouting.length(path)
    if len > maxLength then
        path = { { x = from.x, z = from.z }, { x = to.x, z = to.z } }
    end
    return path
end

local function reachOf(p) return p.combat_radius_km * 1000 * REACH_FACTOR end

-- Aircraft in one flight: the mission type's flight_size if it has one, else the profile's.
local function flightSize(mt, p)
    local size = mt.flight_size or p.flight_size
    return math.random(size[1], size[2])
end

-- Route points from base to target and home, around what the flight can't overfly:
--   takeoff → departure → transit … → descent → ingress → target → egress → transit … → landing
-- The way home is the way out reversed (John, after the first package run: a flight
-- that went around SAMs on the way in flew straight over an SA-11 on the way back).
-- Cruise altitude until the descent point, the mission's attack altitude from the
-- ingress over the target, cruise again from the egress; the attack tasks go on the
-- ingress. Returns the route and the ids of the threat circles it still crosses.
local function buildRoute(ctx, basePos, target, missionType, mt, p)
    local attackAlt = p.attack_altitude_m[missionType]
    local cruise, speed = p.cruise_altitude_m, p.cruise_speed_mps
    local reach = reachOf(p)
    local route = { { kind = "takeoff", x = basePos.x, z = basePos.z, alt_m = 0, speed_mps = 0 } }
    local function add(kind, q, alt) route[#route + 1] = { kind = kind, x = q.x, z = q.z, alt_m = alt, speed_mps = speed } end

    local direct = Util.dist(basePos, target)
    local start = basePos
    if direct > (DEPARTURE_KM + 40) * 1000 then
        start = offset(basePos, target, DEPARTURE_KM)
        add("departure", start, cruise)
    end

    -- out: the ingress and the descent point sit on the path, counted back from the target
    local out = threatRoute(ctx, start, target, reach)
    local outLen = ThreatRouting.length(out)
    local ingressM = math.min(mt.ingress_km * 1000, outLen * 0.5)
    local descentM = math.max(AIR_ROUTING.min_descent_km,
        (cruise - attackAlt) / 1000 * AIR_ROUTING.descent_km_per_km) * 1000
    descentM = math.min(descentM, math.max(outLen - ingressM - 5000, 0))
    local ingress = cutAt(out, outLen - ingressM)
    local descent, transit = cutAt(out, outLen - ingressM - descentM)
    for i = 2, #transit do add("transit", transit[i], cruise) end
    if descentM > 0 then add("descent", descent, cruise) end
    add("ingress", ingress, attackAlt)
    route[#route].carries_attack_tasks = true
    add("target", target, attackAlt)

    -- back: the way out reversed, so the flight comes home through the same gaps it went
    -- in by; the egress sits on it
    local back = {}
    for i = #out, 1, -1 do back[#back + 1] = out[i] end
    local egressAt = math.min(mt.egress_km * 1000, outLen * 0.5)
    local egress = cutAt(back, egressAt)
    add("egress", egress, cruise)
    local walked = 0
    for i = 2, #back do
        walked = walked + Util.dist(back[i - 1], back[i])
        -- (the way out starts at the base itself when there is no departure point)
        if walked > egressAt and Util.dist(back[i], basePos) > 1000 then add("transit", back[i], cruise) end
    end
    add("landing", basePos, 0)

    for _, r in ipairs(route) do r.x, r.z = round(r.x), round(r.z) end
    return route, ThreatRouting.crossed(ctx.threats, route)
end

-- A suppression flight's route against one SAM site, under the radar (roadmap item 10,
-- John's profile, 2026-10-01; data/air_tasking.lua has the numbers):
--   takeoff → departure → transit … (cruise) → descent → low … (low_altitude_m above the
--   ground, every low_waypoint_km) → popup → target (the launch point, popup_altitude_m,
--   carries the attack) → egress (back down, afterburner allowed) → low … → climb (out of
--   the rings, afterburner off again) → transit … (cruise) → landing
-- The way in is routed around every other site's low-altitude reach (ctx.low_threats)
-- to a launch point launch_km from the site on the side the flight comes from, outside
-- every other site's low-altitude reach (+ margin): the bearing from the site toward the
-- base first, then every 15° either side; nil and no route when none is clear. The
-- flight is down low_entry_margin_km before the route first enters any enemy ring (full
-- reach + margin, ctx.threats) and stays low until the pop-up; the way back is the way
-- in reversed. A long-range SAM's ring may reach past the launch point: the flight pops
-- up, fires and turns away. Returns the route, or nil.
local function launchPoint(ctx, basePos, site, threat, km)
    local function clear(q)
        for _, c in ipairs(ctx.low_threats.circles) do
            if c.id ~= threat and (q.x - c.x) ^ 2 + (q.z - c.z) ^ 2 < c.r2 then return false end
        end
        return true
    end
    local home = math.atan2(basePos.z - site.z, basePos.x - site.x)
    for step = 0, 12 do
        for _, sign in ipairs(step == 0 and { 1 } or { 1, -1 }) do
            local a = home + sign * math.rad(15 * step)
            local q = { x = site.x + math.cos(a) * km * 1000, z = site.z + math.sin(a) * km * 1000 }
            if clear(q) then return q end
        end
    end
    return nil
end

-- Metres along the polyline to its first sample inside any circle of `map`; its length
-- when it enters none.
local function firstInside(map, points)
    local walked = 0
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = Util.dist(a, b)
        local steps = math.max(1, math.ceil(d / 2000))
        for s = 0, steps do
            local t = s / steps
            local x, z = a.x + t * (b.x - a.x), a.z + t * (b.z - a.z)
            for _, c in ipairs(map.circles) do
                if (x - c.x) ^ 2 + (z - c.z) ^ 2 < c.r2 then return walked + t * d end
            end
        end
        walked = walked + d
    end
    return walked
end

local function suppressionRoute(ctx, baseName, p, threat)
    local mt = AIR_MISSION_TYPE[SUPPRESSION]
    local basePos = ctx.plan.world.airbases[baseName].pos
    local c = ThreatRouting.circle(ctx.threats, threat)
    local site = { x = c.x, z = c.z }
    local cruise, speed = p.cruise_altitude_m, p.cruise_speed_mps
    local fast = mt.low_speed_mps
    local route = { { kind = "takeoff", x = basePos.x, z = basePos.z, alt_m = 0, speed_mps = 0 } }
    local function add(kind, q, alt, v, extra)
        local r = { kind = kind, x = round(q.x), z = round(q.z), alt_m = alt, speed_mps = v or speed }
        for k, val in pairs(extra or {}) do r[k] = val end
        route[#route + 1] = r
        return r
    end
    local function addLow(kind, q, extra)
        local fields = { alt_type = "RADIO" }
        for k, val in pairs(extra or {}) do fields[k] = val end
        return add(kind, q, mt.low_altitude_m, fast, fields)
    end
    local launch = launchPoint(ctx, basePos, site, threat, mt.launch_km)
    if not launch then return nil end
    local start = basePos
    if Util.dist(basePos, launch) > (DEPARTURE_KM + 40) * 1000 then
        start = offset(basePos, launch, DEPARTURE_KM)
        add("departure", start, cruise)
    end
    -- around every other site's low-altitude reach; the site's own ring holds the launch point
    local out = threatRoute(ctx, start, launch, reachOf(p), ctx.low_threats)
    local outLen = ThreatRouting.length(out)
    -- where it goes low, where the descent starts, where it pops up; a route that enters
    -- no enemy ring at all (a short-reaching site, launch point outside its own ring) has
    -- no low leg: down to the shot's altitude and back
    local goesLow = firstInside(ctx.threats, out) < outLen - 1000
    local bottom = goesLow and mt.low_altitude_m or mt.popup_altitude_m
    local lowAt = goesLow and math.max(0, firstInside(ctx.threats, out) - mt.low_entry_margin_km * 1000) or outLen
    local popAt = math.max(lowAt, outLen - mt.popup_km * 1000)
    local descentM = math.max(AIR_ROUTING.min_descent_km,
        (cruise - bottom) / 1000 * AIR_ROUTING.descent_km_per_km) * 1000
    local descentAt = math.max(0, lowAt - descentM)
    -- the marks along the way in: the route's corners, the descent, the low entry, a low
    -- waypoint every low_waypoint_km, the pop-up
    local marks = {}
    local function mark(d, kind) marks[#marks + 1] = { d = d, kind = kind } end
    local walked = 0
    for i = 2, #out - 1 do
        walked = walked + Util.dist(out[i - 1], out[i])
        -- the route's own corners: cruising, on the way down, or low (none past the pop-up:
        -- the climb to the shot is straight)
        if walked < popAt then
            mark(walked, walked < descentAt and "transit" or walked < lowAt and "descending" or "low")
        end
    end
    if descentAt > 0 then mark(descentAt, "descent") end
    if goesLow then
        mark(lowAt, "low")
        local lows = math.floor((popAt - lowAt) / (mt.low_waypoint_km * 1000))
        for k = 1, lows do mark(lowAt + (popAt - lowAt) * k / (lows + 1), "low") end
        mark(popAt, "popup")
    end
    table.sort(marks, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        return a.kind ~= "popup" and b.kind == "popup"
    end)
    -- the way in; a mark within a km of the last one at the same height folds into it
    -- (the pop-up wins)
    local high, lowPoints = {}, {}
    local lastD = -math.huge
    for _, mk in ipairs(marks) do
        local isLow = mk.kind == "low" or mk.kind == "popup"
        if mk.d - lastD < 1000 and isLow == (route[#route].alt_type == "RADIO") then
            if mk.kind == "popup" then route[#route].kind = "popup" end
        else
            local q = cutAt(out, mk.d)
            if mk.kind == "transit" or mk.kind == "descent" then
                high[#high + 1] = add(mk.kind, q, cruise)
            elseif mk.kind == "descending" then
                -- a corner between the descent point and the low entry: on the way down
                local f = (mk.d - descentAt) / math.max(lowAt - descentAt, 1)
                high[#high + 1] = add("descent", q, round(cruise - (cruise - bottom) * f))
            else
                addLow(mk.kind, q)
                lowPoints[#lowPoints + 1] = q
            end
            lastD = mk.d
        end
    end
    add("target", launch, mt.popup_altitude_m, fast)
    route[#route].carries_attack_tasks = true
    -- the way back: straight back down and out low the way it came, afterburner allowed;
    -- at the low entry, afterburner off again and climb to cruise
    for i = #lowPoints, 1, -1 do
        addLow(i == #lowPoints and "egress" or "low", lowPoints[i], i == #lowPoints and { afterburner = true } or nil)
    end
    if #lowPoints > 1 then
        route[#route].kind, route[#route].afterburner = "climb", false
    end
    -- back up the way it came down (the heights it had there)
    for i = #high, 1, -1 do
        add("transit", high[i], high[i].alt_m, nil, i == #high and #lowPoints == 1 and { afterburner = false } or nil)
    end
    if start ~= basePos then add("transit", start, cruise) end
    add("landing", basePos, 0)
    return route
end

-- How far a route takes from the flight's fuel, in metres of cruise: a low leg (either
-- end low) counts low_fuel_factor times its length.
local function fuelLength(route)
    local factor = AIR_MISSION_TYPE[SUPPRESSION].low_fuel_factor
    local m = 0
    for i = 2, #route do
        local d = Util.dist(route[i - 1], route[i])
        local low = route[i].alt_type == "RADIO" or route[i - 1].alt_type == "RADIO"
        m = m + d * (low and factor or 1)
    end
    return m
end

-- Seconds of flight from the takeoff point to the target, and from the target home.
local function legSeconds(route, speed)
    local toTarget, home, reached = 0, 0, false
    for i = 2, #route do
        local d = Util.dist(route[i - 1], route[i]) / speed
        if reached then home = home + d else toTarget = toTarget + d end
        if route[i].kind == "target" then reached = true end
    end
    return toTarget, home
end

-- ── one mission ─────────────────────────────────────────────────

-- The attack points for a bomb_critical_objects target: its critical objects' positions,
-- merged when closer than SAME_POINT_M, at most max; or the centre for carpet bombing.
local function attackPoints(ctx, target, mt, p)
    local pts = {}
    for _, name in ipairs(target.critical_names or {}) do
        local q = ctx.positions[name]
        if q then
            local near = false
            for _, e in ipairs(pts) do if Util.dist(e, q) < SAME_POINT_M then near = true end end
            if not near then pts[#pts + 1] = { x = round(q.x), z = round(q.z) } end
        end
    end
    if #pts == 0 then pts[1] = { x = round(target.pos.x), z = round(target.pos.z) } end
    if p.carpet_bombing then
        local cx, cz = 0, 0
        for _, q in ipairs(pts) do cx, cz = cx + q.x, cz + q.z end
        return { { x = round(cx / #pts), z = round(cz / #pts) } }
    end
    Util.shuffle(pts)
    while #pts > mt.max_attack_points do table.remove(pts) end
    return pts
end

-- What the flight is told to hit, by attack kind.
local function attackOf(ctx, draft)
    if draft.attack then return draft.attack end   -- stations build theirs
    local mt, p, t = draft.mt, draft.p, draft.target
    if mt.attack == "bomb_critical_objects" then
        local points = attackPoints(ctx, t, mt, p)
        return { kind = mt.attack, points = points,
                 weapon_type = AIR_WEAPON_TYPE[p.carpet_bombing and "bombs" or mt.weapon_type],
                 expend = (#points == 1) and "All" or "Auto" }
    elseif mt.attack == "engage_group" then
        return { kind = mt.attack, groups = draft.groups, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type] }
    elseif mt.attack == "harm_salvo" then
        -- the site's own group (radars and launchers); its escort is saturated, not shot at
        local launch
        for _, r in ipairs(draft.route) do if r.kind == "target" then launch = { x = r.x, z = r.z } end end
        return { kind = mt.attack, groups = { draft.threats[1] }, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type],
                 site = draft.site, launch = launch }
    end
    return { kind = mt.attack, groups = t.group_ids, weapon_type = AIR_WEAPON_TYPE[mt.weapon_type], expend = "Auto" }
end

-- Where a target sits against the front, cached per target: nil when it lies more than
-- AIR_TARGETING.max_km_past_contested from the contested airspace; else { front, depth_m
-- (0 inside the contested airspace), region (the own region facing it) }.
local function targetFront(ctx, t)
    local cached = ctx.target_fronts[t.id]
    if cached == nil then
        local a = ctx.plan.airspace
        local front, depth = DivideAirspace.nearestFront(a, t.pos, AIR_TARGETING.max_km_past_contested * 1000)
        cached = false
        if front then
            local region = DivideAirspace.facingRegion(a, t.pos, ctx.coalition, AIR_TARGETING.facing_search_km * 1000)
            if region then cached = { front = front, depth_m = depth, region = region } end
        end
        ctx.target_fronts[t.id] = cached
    end
    return cached or nil
end

-- Enemy targets offering this mission type, not taken yet, near the front (targetFront)
-- and in reach of one of `bases` in the own region facing them.
-- Returns { { target, front = targetFront(…), bases = { { name, km } } } }.
local function reachableTargets(ctx, missionType, aircraftType, bases)
    local p = AIRCRAFT_PROFILE[aircraftType]
    local cat, world = ctx.plan.target_catalog, ctx.plan.world
    local out = {}
    for _, id in ipairs(cat.list) do
        local t = cat.targets[id]
        if t.coalition ~= ctx.coalition and not ctx.taken[id] then
            local offers = false
            for _, m in ipairs(t.mission_types) do if m == missionType then offers = true end end
            local front = offers and targetFront(ctx, t)
            if front then
                local inReach = {}
                for _, b in ipairs(bases) do
                    local km = Util.dist(world.airbases[b].pos, t.pos) / 1000
                    if ctx.base_region[b] == front.region and km <= p.combat_radius_km then
                        inReach[#inReach + 1] = { name = b, km = km }
                    end
                end
                if #inReach > 0 then out[#out + 1] = { target = t, front = front, bases = inReach } end
            end
        end
    end
    return out
end

-- Km of the route, from takeoff to the target (or a patrol's station), that lie in enemy
-- airspace.
local function enemyAirspaceKm(ctx, route)
    local a, m = ctx.plan.airspace, 0
    for i = 2, #route do
        local p, q = route[i - 1], route[i]
        local d = Util.dist(p, q)
        local steps = math.max(1, math.ceil(d / 2000))
        for s = 1, steps do
            local t = (s - 0.5) / steps
            if DivideAirspace.kindFor(a, { x = p.x + t * (q.x - p.x), z = p.z + t * (q.z - p.z) }, ctx.coalition) == "enemy" then
                m = m + d / steps
            end
        end
        if q.kind == "target" or q.kind == "station" then break end
    end
    return m / 1000
end

-- A flight before its times and parking are fixed: what flies, from where, the route
-- and how long the legs take. `human` (a human flight): { aircraft_type, bases, count }
-- instead of the roster, the bases that can launch it and the flight size.
-- Returns the draft, or nil and why not.
local function draftMission(ctx, missionType, human)
    local mt = AIR_MISSION_TYPE[missionType]
    local aircraftType = human and human.aircraft_type or Util.weightedPick(COALITION_AIRCRAFT[ctx.coalition][missionType])
    local p = AIRCRAFT_PROFILE[aircraftType]
    local choices = reachableTargets(ctx, missionType, aircraftType, human and human.bases or launchBases(ctx, aircraftType))
    if #choices == 0 then return nil, "no target near the front in reach" end
    local weighted = {}
    for _, c in ipairs(choices) do weighted[#weighted + 1] = { c, c.target.value or 1 } end
    local pick = Util.weightedPick(weighted)
    table.sort(pick.bases, function(a, b) return a.km < b.km end)
    local nearest = {}
    for i = 1, math.min(NEAREST_BASES, #pick.bases) do nearest[i] = pick.bases[i] end
    local base = Util.pick(nearest)
    -- routed from the base centre; the takeoff point moves to the lead's spot later
    local route, crossed = buildRoute(ctx, ctx.plan.world.airbases[base.name].pos, pick.target.pos, missionType, mt, p)
    -- a route deeper into enemy airspace than the target itself went the wrong way round
    -- (no way through own and contested airspace within reach)
    local enemyKm = enemyAirspaceKm(ctx, route)
    if enemyKm > pick.front.depth_m / 1000 + AIR_TARGETING.enemy_airspace_slack_km then
        return nil, "route through enemy airspace"
    end
    local toTarget, home = legSeconds(route, p.cruise_speed_mps)
    return { mission_type = missionType, mt = mt, aircraft_type = aircraftType, p = p, target = pick.target,
             base = base.name, distance_km = base.km, count = human and human.count or flightSize(mt, p),
             route = route, crossed = crossed, to_target_s = toTarget, home_s = home, lead_s = 0,
             front = pick.front, enemy_airspace_km = enemyKm }
end

-- One suppression flight for the next threats in `remaining` (taken off it on success),
-- escorting `mission`: an aircraft from the roster with a base in the mission's region
-- that can reach the target — the escorted mission's own base when it can launch this
-- type, else the one nearest the target — whose route is within twice the reach and no
-- deeper in enemy airspace than the escorted mission may fly (the same rule; before,
-- escorts were exempt and Rovaniemi F-16s flew 211 km of enemy airspace to join an
-- Evenes strike, John's run 2026-09-27). `human` as for draftMission. Returns the draft,
-- or nil and why not (the last reason a try failed on).
local function draftSuppressionFlight(ctx, mission, remaining, human)
    local mt = AIR_MISSION_TYPE[SUPPRESSION]
    local maxEnemyKm = mission.front.depth_m / 1000 + AIR_TARGETING.enemy_airspace_slack_km
    local why = "no base in reach"
    for _ = 1, AIRCRAFT_TRIES do
        local aircraftType = human and human.aircraft_type or Util.weightedPick(COALITION_AIRCRAFT[ctx.coalition][SUPPRESSION])
        local p = AIRCRAFT_PROFILE[aircraftType]
        local candidates = {}
        for _, b in ipairs(human and human.bases or launchBases(ctx, aircraftType)) do
            local pos = ctx.plan.world.airbases[b].pos
            local km = Util.dist(pos, mission.target.pos) / 1000
            if ctx.base_region[b] == mission.front.region and km <= p.combat_radius_km then
                candidates[#candidates + 1] = { name = b, order = b == mission.base and -1 or km }
            end
        end
        table.sort(candidates, function(a, b) return a.order < b.order end)
        if #candidates > 0 then
            local count = human and human.count or flightSize(mt, p)
            -- one SAM site per flight, every missile at it (John, 2026-10-01)
            local threats = { remaining[1] }
            local groups = ctx.threat_groups[remaining[1]] or { remaining[1] }
            local circle = ThreatRouting.circle(ctx.threats, remaining[1])
            local site = circle and { x = round(circle.x), z = round(circle.z) }
            for _, c in ipairs(site and candidates or {}) do
                local route = suppressionRoute(ctx, c.name, p, remaining[1])
                local enemyKm = route and enemyAirspaceKm(ctx, route)
                if not route then
                    why = "no launch point clear of other sites"
                elseif fuelLength(route) > 2 * reachOf(p) then
                    why = "too far for its fuel"
                elseif enemyKm > maxEnemyKm then
                    why = "too deep in enemy airspace"
                else
                    for _ = 1, #threats do table.remove(remaining, 1) end
                    local toTarget, home = legSeconds(route, p.cruise_speed_mps)
                    local lead = AIR_PACKAGE.suppression_lead_s
                    -- low-altitude reaches its route passes through on purpose (the go-cold
                    -- rule leaves these alone; the full rings it flies under, low)
                    local routeThreats = ThreatRouting.crossed(ctx.low_threats, route)
                    return { mission_type = SUPPRESSION, mt = mt, aircraft_type = aircraftType, p = p,
                             target = mission.target, base = c.name, front = mission.front,
                             enemy_airspace_km = enemyKm,
                             distance_km = Util.dist(ctx.plan.world.airbases[c.name].pos, mission.target.pos) / 1000,
                             count = count, route = route, crossed = {}, threats = threats, groups = groups, site = site,
                             route_threats = routeThreats,
                             to_target_s = toTarget, home_s = home,
                             lead_s = round(lead[1] + math.random() * (lead[2] - lead[1])) }
                end
            end
        end
    end
    return nil, why
end

-- Every suppression flight the mission's crossed threats need, or nil and why if one
-- can't be had.
-- `remaining`: the threats still to cover (default: all the route crosses).
local function draftSuppression(ctx, mission, remaining)
    local flights = {}
    if not remaining then
        remaining = {}
        for i, id in ipairs(mission.crossed) do remaining[i] = id end
    end
    while #remaining > 0 do
        local f, why = draftSuppressionFlight(ctx, mission, remaining)
        if not f then return nil, why end
        flights[#flights + 1] = f
    end
    return flights
end

-- What the planned flights (packages, patrols, AWACS) may fill of the coalition's
-- max_airborne_aircraft: the rest is kept free for scrambles, when they're planned
-- (AIR_DEFENSE.scramble_reserve_aircraft; John, 2026-10-01).
local function plannedCap(per)
    if AIR_DEFENSE.planned and AIR_DEFENSE.alert_posture_planned then
        return per.max_airborne_aircraft - AIR_DEFENSE.scramble_reserve_aircraft
    end
    return per.max_airborne_aircraft
end

-- AI aircraft of this coalition in the air, most at any moment, with `extra` flights added:
-- { { up_s, down_s, count } }; airborne from takeoff until landing_s before the end.
local function airborneAtMost(ctx, extra)
    local spans = {}
    for _, m in ipairs(ctx.out.missions) do
        -- the cap is for AI aircraft: a human flight never counts (John, 2026-10-01)
        if m.flown_by ~= "human" then
            spans[#spans + 1] = { m.takeoff_s, m.end_s - AIR_TASKING_TIMING.landing_s, m.count }
        end
    end
    for _, s in ipairs(extra) do spans[#spans + 1] = s end
    local most = 0
    for _, a in ipairs(spans) do
        local up = 0
        for _, b in ipairs(spans) do
            if b[1] <= a[1] and a[1] < b[2] then up = up + b[3] end
        end
        if up > most then most = up end
    end
    return most
end

-- ── packages with a human flight: flown together ────────────────

-- Every flight's time over the target is the escorted mission's TOT minus its lead.
-- Each flight's times relative to the escorted mission's (flights[1]) start: rel_start,
-- rel_tot, rel_end. Returns the earliest start and the latest end.
local function relativeTimes(flights)
    local T = AIR_TASKING_TIMING
    local main = flights[1]
    local earliest, latest = math.huge, -math.huge
    for _, f in ipairs(flights) do
        f.rel_tot = T.taxi_s + main.to_target_s - f.lead_s
        f.rel_start = f.rel_tot - f.to_target_s - T.taxi_s
        f.rel_end = f.rel_tot + T.attack_s + f.home_s + T.landing_s
        earliest = math.min(earliest, f.rel_start)
        latest = math.max(latest, f.rel_end)
    end
    return earliest, latest
end

-- Sets each flight's start_s / takeoff_s / tot_s / end_s from the package's zero (the
-- escorted mission's start) and returns their airborne spans.
local function setTimes(flights, zero)
    local T = AIR_TASKING_TIMING
    local spans = {}
    for i, f in ipairs(flights) do
        f.start_s = zero + round(f.rel_start)
        f.takeoff_s = f.start_s + T.taxi_s
        f.tot_s = zero + round(f.rel_tot)
        f.end_s = zero + round(f.rel_end)
        -- a human flight (it has a player slot) never counts against the cap
        spans[i] = { f.takeoff_s, f.end_s - T.landing_s, f.player_slot and 0 or f.count }
    end
    return spans
end

-- Parking for every flight of a package: free spots from its start, or a human flight's
-- player slot. Returns true, or releases what it held and returns false.
local function parkPackage(ctx, flights)
    local held = {}
    for _, f in ipairs(flights) do
        if f.player_slot then
            f.spots = { f.player_slot.parking }
        else
            local spots, h = reserveParking(ctx, f.base, f.aircraft_type, f.count, f.start_s)
            if not spots then
                releaseParking(held)
                return false
            end
            f.spots = spots
            for _, x in ipairs(h) do held[#held + 1] = x end
        end
    end
    return true
end

-- ── AI packages in sequence ──────────────────────────────────────

-- A flight's times from its start; returns its airborne span for the cap.
local function timesFrom(f, start)
    local T = AIR_TASKING_TIMING
    f.start_s = round(start)
    f.takeoff_s = f.start_s + T.taxi_s
    f.tot_s = f.takeoff_s + round(f.to_target_s)
    f.end_s = f.tot_s + T.attack_s + round(f.home_s) + T.landing_s
    return { f.takeoff_s, f.end_s - T.landing_s, f.count }
end

local function duration(f)
    local T = AIR_TASKING_TIMING
    return T.taxi_s + f.to_target_s + T.attack_s + f.home_s + T.landing_s
end

-- Start times to try between first and last: the first one itself (the first attack of
-- the coalition goes at once), then random ones spread over the window.
local function spreadStarts(ctx, first, last)
    local starts = {}
    if ctx.attack_missions == 0 then starts[1] = first end
    for _ = #starts + 1, START_TRIES do starts[#starts + 1] = first + math.random() * math.max(0, last - first) end
    return starts
end

-- Start times from `first` on, every 10 minutes, until the flight no longer fits the window.
local function steppedStarts(first, dur)
    local starts = {}
    local t = first
    while t + dur <= AIR_TASKING_TIMING.window_s and #starts < START_TRIES do
        starts[#starts + 1] = t
        t = t + 600
    end
    return starts
end

-- One flight at the first of `starts` that keeps the coalition under its planned cap,
-- with the package's flights already placed (`pending` spans), and finds parking.
-- Returns true and its span, or false and why.
local function scheduleFlight(ctx, f, starts, pending)
    local reason = #starts == 0 and "too long for the window" or "over the airborne cap"
    for _, start in ipairs(starts) do
        local span = timesFrom(f, start)
        if f.end_s <= AIR_TASKING_TIMING.window_s then
            local extra = { span }
            for _, s in ipairs(pending) do extra[#extra + 1] = s end
            if airborneAtMost(ctx, extra) <= ctx.planned_cap then
                local spots, held = reserveParking(ctx, f.base, f.aircraft_type, f.count, f.start_s)
                if spots then
                    f.spots, f.held = spots, held
                    return true, span
                end
                reason = "no parking"
            end
        else
            reason = "too long for the window"
        end
    end
    return false, reason
end

-- An AI package in sequence: its suppression flights (`flights[2..]`) at spread start
-- times, then the mission (`flights[1]`) from strike_after_suppression_s after the last
-- of them lands, and no earlier than `after_s` (an earlier package's suppression of a
-- threat it relies on). Returns true, or false and why (parking released).
local function scheduleSequentialPackage(ctx, flights, after_s)
    local T = AIR_TASKING_TIMING
    local gap = AIR_PACKAGE.strike_after_suppression_s
    local main = flights[1]
    local pending, held = {}, {}
    local function fail(why)
        releaseParking(held)
        return false, why
    end
    local ready = math.max(T.first_start_s, after_s or 0)
    if #flights > 1 then
        local longest = 0
        for i = 2, #flights do longest = math.max(longest, duration(flights[i])) end
        local last = T.window_s - longest - gap - duration(main)
        if last < T.first_start_s then return fail("too long for the window") end
        local starts = spreadStarts(ctx, T.first_start_s, last)
        for i = 2, #flights do
            local ok, span = scheduleFlight(ctx, flights[i], starts, pending)
            if not ok then return fail(span) end
            pending[#pending + 1] = span
            for _, h in ipairs(flights[i].held) do held[#held + 1] = h end
            ready = math.max(ready, flights[i].end_s + gap)
        end
    end
    local starts = (#flights > 1 or (after_s or 0) > 0) and steppedStarts(ready, duration(main))
                   or spreadStarts(ctx, ready, T.window_s - duration(main))
    local ok, why = scheduleFlight(ctx, main, starts, pending)
    if not ok then return fail(why) end
    return true
end

-- A player's SEAD tasking in front of an AI mission: the player's flight at its takeoff,
-- the package's AI flights in sequence after it (John, 2026-10-01: an AI mission only
-- flies after a successful SEAD, a player's too), the mission starting
-- strike_after_suppression_s after the player's planned landing; at run time it
-- launches only once its threats are out of the fight. Returns true, or false and why.
local function scheduleHumanSeadPackage(ctx, flights, human, takeoff_s)
    local T = AIR_TASKING_TIMING
    timesFrom(human, takeoff_s - T.taxi_s)
    if human.end_s > T.window_s then return false, "too long for the window" end
    human.spots = { human.player_slot.parking }
    local ai = { flights[1] }
    for i = 2, #flights do
        if flights[i] ~= human then ai[#ai + 1] = flights[i] end
    end
    return scheduleSequentialPackage(ctx, ai, human.end_s + AIR_PACKAGE.strike_after_suppression_s)
end

-- A package with a human flight in it, timed around the player: the human takes off at
-- `takeoff_s`, and every other flight of the package keeps its place relative to it. If
-- that would start an AI flight before first_start_s, the whole package moves later (the
-- player waits), but never past the end of HUMAN_TASKING.startup_s: a package whose AI
-- flights can't be there in time isn't flown with this player (John: prep ~15 min and
-- go, not an hour on the ramp). Then the airborne cap and parking, as for any package.
local function scheduleHumanPackage(ctx, flights, human, takeoff_s)
    local T = AIR_TASKING_TIMING
    local _, latest = relativeTimes(flights)
    local zero = takeoff_s - T.taxi_s - human.rel_start
    for _, f in ipairs(flights) do
        if f ~= human and zero + f.rel_start < T.first_start_s then zero = T.first_start_s - f.rel_start end
    end
    zero = round(zero)
    if zero + human.rel_start + T.taxi_s > HUMAN_TASKING.startup_s[2] + 60 then
        return false, "package's AI flights can't be there in time"
    end
    if zero + latest > T.window_s then return false, "too long for the window" end
    local spans = setTimes(flights, zero)
    -- the AI suppression flights of a player's own mission take off first thing (John,
    -- 2026-10-01: they make the player's tasking possible, so they fly before anything
    -- else), keeping their time over the target at least suppression_lead_s ahead
    if flights[1] == human then
        for i = 2, #flights do
            local f = flights[i]
            local early = T.first_start_s - f.start_s
            if early < 0 then
                f.start_s, f.takeoff_s, f.tot_s, f.end_s = f.start_s + early, f.takeoff_s + early, f.tot_s + early, f.end_s + early
                spans[i] = { f.takeoff_s, f.end_s - T.landing_s, f.count }
            end
        end
    end
    if airborneAtMost(ctx, spans) > ctx.planned_cap then return false, "over the airborne cap" end
    if not parkPackage(ctx, flights) then return false, "no parking" end
    return true
end

-- A drafted and scheduled flight → its plan entry, numbered.
local function commitFlight(ctx, f, packageId)
    local number = ctx.next_number
    ctx.next_number = number + 1
    local t = f.target
    local parking = {}
    if f.spots then   -- a runway takeoff (AWACS) needs no spot: the takeoff point is the base
        for i, s in ipairs(f.spots) do parking[i] = { terminal_index = s[4], x = s[1], z = s[2] } end
        f.route[1].x, f.route[1].z = round(f.spots[1][1]), round(f.spots[1][2])
    end
    local mission = {
        id = string.format("MSN%d_%s", number, f.mt.group_name_tag), number = number,
        coalition = ctx.coalition, package = packageId,
        mission_type = f.mission_type, group_task = f.mt.group_task,
        flown_by = f.player_slot and "human" or "ai",
        player_slot = f.player_slot and { group = f.player_slot.group, spot = f.player_slot.spot,
                                          terminal_index = f.player_slot.terminal_index },
        target = t.id, target_label = t.label, target_kind = t.kind, target_pos = t.pos,
        aircraft_type = f.aircraft_type, count = f.count,
        skill = (not f.player_slot) and Util.pick(AIR_TASKING_SKILL) or nil,
        launch_base = f.base, landing_base = f.base, parking = parking,
        start_s = f.start_s, takeoff_s = f.takeoff_s, tot_s = f.tot_s, end_s = f.end_s,
        distance_km = round(f.distance_km), route = f.route,
        route_km = round(ThreatRouting.length(f.route) / 1000),
        needs_suppression = #f.crossed > 0, suppression_threats = f.crossed,
        front = f.front and f.front.front, facing_region = f.front and f.front.region,
        target_depth_km = f.front and round(f.front.depth_m / 1000),
        enemy_airspace_km = f.enemy_airspace_km and round(f.enemy_airspace_km),
        attack = attackOf(ctx, f),
        return_when_out_of = f.mt.return_when_out_of and AIR_WEAPON_TYPE[f.mt.return_when_out_of],
        rules_of_engagement = f.mt.rules_of_engagement or "open_fire", takeoff = f.mt.takeoff or "parking",
        route_threats = f.route_threats,
        loadout = AIRCRAFT_LOADOUT[f.aircraft_type][f.mission_type], keeps_gun = f.p.keeps_gun == true or f.mt.keeps_gun == true,
        may_jettison = f.mt.may_jettison == true,
        success = t.success, critical_names = t.critical_names,
    }
    ctx.out.missions[#ctx.out.missions + 1] = mission
    f.committed = mission
    return mission
end

local function logFlight(ctx, m, extra)
    Log.info(string.format("  %-13s %-4s %s%-27s %dx %-13s %-22s → %-34s %4d km (%d flown, %d in enemy airspace, target %d km past contested)  start %s  TOT %s  back %s%s",
        m.id, ctx.coalition:upper(), m.flown_by == "human" and "HUMAN " or "", m.mission_type, m.count,
        m.aircraft_type, m.launch_base, m.target,
        m.distance_km, m.route_km, m.enemy_airspace_km or 0, m.target_depth_km or 0,
        clock(m.start_s), clock(m.tot_s), clock(m.end_s), extra))
end

-- A scheduled package (flights[1] the escorted mission, then its suppression flights)
-- → plan entries; the target is taken. Returns the mission and the package.
local function commitPackage(ctx, flights)
    local main = flights[1]
    local packageId = "PKG" .. ctx.next_number
    ctx.taken[main.target.id] = true
    ctx.attack_missions = ctx.attack_missions + 1
    local mission = commitFlight(ctx, main, packageId)
    local package = { id = packageId, mission = mission.id, suppression_flights = {}, tot_s = mission.tot_s }
    local attack = mission.attack
    logFlight(ctx, mission, string.format("  %s%s", attack.points and (#attack.points .. " attack point(s)")
        or (#attack.groups .. " group(s)"),
        mission.needs_suppression and ("  crosses: " .. table.concat(mission.suppression_threats, ", ")) or ""))
    mission.suppressed_by, mission.cleared_by = {}, {}
    for threat, by in pairs(main.cleared_by or {}) do mission.cleared_by[threat] = by end
    local sequence = main.sequence
    for i = 2, #flights do
        local s = commitFlight(ctx, flights[i], packageId)
        s.escorts, s.suppresses = mission.id, flights[i].threats
        mission.suppressed_by[#mission.suppressed_by + 1] = s.id
        package.suppression_flights[#package.suppression_flights + 1] = s.id
        for _, threat in ipairs(s.suppresses) do
            mission.cleared_by[threat] = s.id
            -- later packages whose routes cross this threat can wait for it instead (not
            -- for a player's: nobody may fly it)
            if s.flown_by ~= "human" and (not ctx.cleared[threat] or ctx.cleared[threat].after_s > s.end_s) then
                ctx.cleared[threat] = { by = s.id, after_s = s.end_s + AIR_PACKAGE.strike_after_suppression_s }
            end
        end
        logFlight(ctx, s, sequence and string.format("  clears the way for %s, engages: %s", mission.id,
                table.concat(s.attack.groups, ", "))
            or string.format("  escorts %s, over target %s, engages: %s", mission.id, clock(s.tot_s),
                table.concat(s.attack.groups, ", ")))
    end
    if sequence and #mission.suppression_threats > 0 then
        mission.requires_cleared = {}
        for i, threat in ipairs(mission.suppression_threats) do mission.requires_cleared[i] = threat end
    end
    ctx.out.packages[#ctx.out.packages + 1] = package
    return mission, package
end

-- One mission and its package, or nil. `failures` counts why tries failed.
local function planMission(ctx, missionType, failures)
    local function fail(reason) failures[reason] = (failures[reason] or 0) + 1 end
    for _ = 1, MISSION_TRIES do
        local main, why = draftMission(ctx, missionType)
        if not main then
            fail(why)
        else
            local flights, escorts = { main }, {}
            -- threats an earlier package's suppression flight already takes: wait for it
            -- instead of sending another (rolling the air defenses back)
            local remaining, after_s = {}, 0
            main.cleared_by, main.sequence = {}, true
            for _, threat in ipairs(main.crossed) do
                local c = ctx.cleared[threat]
                if c then
                    main.cleared_by[threat] = c.by
                    after_s = math.max(after_s, c.after_s)
                else
                    remaining[#remaining + 1] = threat
                end
            end
            local noEscort
            if #remaining > 0 then escorts, noEscort = draftSuppression(ctx, main, remaining) end
            if not escorts then
                fail("no suppression flight: " .. noEscort)
            else
                for _, f in ipairs(escorts) do flights[#flights + 1] = f end
                local ok, why = scheduleSequentialPackage(ctx, flights, after_s)
                if not ok then
                    fail(why)
                else
                    return commitPackage(ctx, flights)
                end
            end
        end
    end
    return nil
end

-- ── defensive air: patrol stations, the AWACS, the alert posture ─

local FIGHTER_BASE_CLASSES = { hub = true, fighter = true, bomber = true, dispersal = true }
local ALERT_BASE_CLASSES   = { hub = true, fighter = true }

-- Held (or, with `enemy`, enemy-held) bases whose class is in `classes`, sorted by name.
local function basesOf(ctx, classes, enemy)
    local out = {}
    for name, b in pairs(ctx.plan.territory.bases) do
        if (b.side == ctx.coalition) ~= (enemy == true) and classes[AIRBASE_CLASS[name]] then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

local function nearestBase(ctx, pos, names)
    local best, bestD
    for _, n in ipairs(names) do
        local d = Util.dist(pos, ctx.plan.world.airbases[n].pos)
        if not bestD or d < bestD then best, bestD = n, d end
    end
    return best, bestD
end

-- Own held ground, as the airspace grid (and the F10 map) has it: own airspace, or
-- contested airspace on own ground.
local HELD_BY = { B = "blue", b = "blue", R = "red", r = "red" }
local function inOwnTerritory(ctx, pos)
    return HELD_BY[DivideAirspace.classAt(ctx.plan.airspace, pos)] == ctx.coalition
end

-- Outside every enemy kill zone (ctx.station_threats) by at least clearance_m.
local function clearOfThreats(ctx, pos, clearance_m)
    for _, c in ipairs(ctx.station_threats.circles) do
        local r = math.sqrt(c.r2) + clearance_m
        if (pos.x - c.x) ^ 2 + (pos.z - c.z) ^ 2 < r * r then return false end
    end
    return true
end

-- A race-track centred on `centre`, leg_m long, across the axis from → to.
local function raceTrack(centre, from, to, leg_m)
    local d = Util.dist(from, to)
    local ux, uz = (to.x - from.x) / math.max(d, 1), (to.z - from.z) / math.max(d, 1)
    local h = leg_m / 2
    return { x = round(centre.x - uz * h), z = round(centre.z + ux * h) },
           { x = round(centre.x + uz * h), z = round(centre.z - ux * h) }
end

-- Walks from `home` toward `goal` and returns the farthest point (with its race-track
-- ends, all three on own held ground) clear of enemy kill zones by clearance_m, never past
-- max_m; nil if even the first point fails. Stops at the first point that fails.
-- The race-track's legs run across the line axis_from → axis_to (default home → goal).
-- With own_airspace_only, the point and both ends must also lie in own (not contested)
-- airspace.
local function farthestClearPoint(ctx, home, goal, clearance_m, leg_m, max_m, axis_from, axis_to, own_airspace_only)
    local step, total = AIR_DEFENSE.step_km * 1000, math.min(Util.dist(home, goal), max_m or math.huge)
    local function ownAirspace(q)
        return not own_airspace_only or DivideAirspace.kindFor(ctx.plan.airspace, q, ctx.coalition) == "own"
    end
    local best, bestA, bestB
    local d, last = 0, false
    while true do
        local q = offset(home, goal, d / 1000)
        local a, b = raceTrack(q, axis_from or home, axis_to or goal, leg_m)
        if inOwnTerritory(ctx, q) and inOwnTerritory(ctx, a) and inOwnTerritory(ctx, b)
           and clearOfThreats(ctx, q, clearance_m)
           and clearOfThreats(ctx, a, clearance_m) and clearOfThreats(ctx, b, clearance_m)
           and ownAirspace(q) and ownAirspace(a) and ownAirspace(b) then
            best, bestA, bestB = q, a, b
        else
            break
        end
        if last then break end
        d = d + step
        if d >= total then d, last = total, true end   -- the last step ends exactly on the goal
    end
    return best, bestA, bestB
end

-- The coalition's defended sites: its catalog targets (SAM / early-warning sites, fixed
-- ground targets; not convoys, which move) in the contested airspace or at most
-- defended_depth_km behind it, with the region they stand in.
local function defendedSites(ctx)
    local a, cat = ctx.plan.airspace, ctx.plan.target_catalog
    local sites = {}
    for _, id in ipairs(cat.list) do
        local t = cat.targets[id]
        if t.coalition == ctx.coalition and t.category ~= "mobile_ground_target" then
            local front = DivideAirspace.nearestFront(a, t.pos, AIR_DEFENSE.defended_depth_km * 1000)
            if front then
                sites[#sites + 1] = { id = id, label = t.label or t.kind or id, pos = t.pos, value = t.value or 1,
                                      region = DivideAirspace.regionAt(a, t.pos) }
            end
        end
    end
    return sites
end

-- A patrol's commit area: circles over the own and contested airspace within
-- commit_range_km of its race-track's centre, centred on a commit_spacing_km lattice,
-- each commit_radius_km or shrunk (5 km steps) until it holds no enemy airspace (checked
-- on its rim and half-way in, 16 bearings) and stays out of every enemy kill zone;
-- dropped below commit_min_radius_km. Returns { { x, z, radius_m } }.
local function commitCircles(ctx, centre)
    local D, a = AIR_DEFENSE, ctx.plan.airspace
    local range, spacing = D.commit_range_km * 1000, D.commit_spacing_km * 1000
    local maxR, minR = D.commit_radius_km * 1000, D.commit_min_radius_km * 1000
    local function enemyAt(x, z) return DivideAirspace.kindFor(a, { x = x, z = z }, ctx.coalition) == "enemy" end
    local function fits(q, r)
        for _, c in ipairs(ctx.station_threats.circles) do
            if Util.dist(q, c) - math.sqrt(c.r2) < r then return false end
        end
        for k = 0, 15 do
            local ang = k * math.pi / 8
            local dx, dz = math.cos(ang), math.sin(ang)
            if enemyAt(q.x + dx * r, q.z + dz * r) or enemyAt(q.x + dx * r / 2, q.z + dz * r / 2) then return false end
        end
        return true
    end
    local out = {}
    local n = math.floor(range / spacing)
    for i = -n, n do
        for j = -n, n do
            local q = { x = centre.x + i * spacing, z = centre.z + j * spacing }
            if Util.dist(q, centre) <= range and not enemyAt(q.x, q.z) then
                local r = maxR
                while r >= minR and not fits(q, r) do r = r - 5000 end
                if r >= minR then out[#out + 1] = { x = round(q.x), z = round(q.z), radius_m = r } end
            end
        end
    end
    return out
end

-- Combat air patrol stations over the defended sites near the front, greedily: each
-- station covers the sites within the patrol's engage range of the best-valued uncovered
-- site (same region), up to max_stations, while what it covers is worth at least
-- min_defended_value. Its defended zone is that circle around the covered sites'
-- value-weighted centre; its race-track is walked out from the nearest own base of that
-- region toward the centre, as far as it stays on own held ground and clear of enemy
-- rings, with legs across the line to the nearest enemy base.
local function planStations(ctx)
    local D = AIR_DEFENSE
    local radius = AIR_MISSION_TYPE[PATROL].engage_range_km * 1000
    local leg, clearance = D.station_leg_km * 1000, D.station_clearance_km * 1000
    local enemies = basesOf(ctx, BASE_CLASSES, true)
    local sites = defendedSites(ctx)
    local stations, covered, tried = {}, {}, {}
    if #enemies == 0 then return stations end
    while #stations < D.max_stations do
        -- the uncovered site whose circle holds the most uncovered value
        local best, bestValue, bestMembers
        for _, s in ipairs(sites) do
            if not covered[s.id] and not tried[s.id] then
                local value, members = 0, {}
                for _, o in ipairs(sites) do
                    if not covered[o.id] and o.region == s.region and Util.dist(s.pos, o.pos) <= radius then
                        value = value + o.value
                        members[#members + 1] = o
                    end
                end
                if not bestValue or value > bestValue then best, bestValue, bestMembers = s, value, members end
            end
        end
        if not best or bestValue < D.min_defended_value then break end
        tried[best.id] = true

        local cx, cz = 0, 0
        for _, o in ipairs(bestMembers) do cx, cz = cx + o.pos.x * o.value, cz + o.pos.z * o.value end
        local zoneCentre = { x = round(cx / bestValue), z = round(cz / bestValue) }
        -- the zone stops short of every enemy threat ring (their routing margin
        -- included), so a patrol isn't sent after aircraft under enemy SAMs; never
        -- smaller than min_zone_radius_km
        local zoneRadius = radius
        for _, c in ipairs(ctx.station_threats.circles) do
            local gap = Util.dist(zoneCentre, c) - math.sqrt(c.r2)
            zoneRadius = math.min(zoneRadius, gap)
        end
        zoneRadius = round(math.max(zoneRadius, D.min_zone_radius_km * 1000))
        local homes = {}
        for _, name in ipairs(ctx.held) do
            if ctx.base_region[name] == best.region then homes[#homes + 1] = name end
        end
        local home = #homes > 0 and nearestBase(ctx, zoneCentre, homes)
        local centre, a, b
        if home then
            local enemyPos = ctx.plan.world.airbases[nearestBase(ctx, zoneCentre, enemies)].pos
            centre, a, b = farthestClearPoint(ctx, ctx.plan.world.airbases[home].pos, zoneCentre, clearance, leg,
                nil, zoneCentre, enemyPos)
        end
        local spaced = centre ~= nil
        for _, st in ipairs(stations) do
            if centre and Util.dist(st.centre, centre) < D.station_spacing_km * 1000 then spaced = false end
        end
        if spaced then
            local names = {}
            for _, o in ipairs(bestMembers) do
                covered[o.id] = true
                names[#names + 1] = o.id
            end
            local n = #stations + 1
            stations[n] = {
                id = string.format("CAP_%s_front_%d", AIRBASE_CODE[home] or home, n), kind = "front",
                home = home, region = best.region, centre = { x = round(centre.x), z = round(centre.z) },
                ends = { a, b }, defends = names, defended_value = bestValue,
                zone = { x = zoneCentre.x, z = zoneCentre.z, radius_m = zoneRadius },
                commit = commitCircles(ctx, centre),
                label = string.format("front station from %s, defends %d sites (value %d)", home, #names, bestValue),
            }
            Log.info(string.format("  %s %s: %d sites (value %d), zone %.0f km, orbit %.0f km from its centre, %d commit circles: %s",
                ctx.coalition:upper(), stations[n].id, #names, bestValue, zoneRadius / 1000,
                Util.dist(centre, zoneCentre) / 1000, #stations[n].commit, table.concat(names, ", ")))
        end
    end
    local left = 0
    for _, s in ipairs(sites) do if not covered[s.id] then left = left + 1 end end
    Log.info(string.format("  %s: %d defended sites near the front, %d covered by %d patrol stations",
        ctx.coalition:upper(), #sites, #sites - left, #stations))
    return stations
end

-- Route to a station and home the same way:
--   takeoff → departure → transit … → station (orbit start, the tasks) → station_end → transit … → landing
local function stationRoute(ctx, basePos, station, p, alt)
    local speed, cruise = p.cruise_speed_mps, p.cruise_altitude_m
    local route = { { kind = "takeoff", x = round(basePos.x), z = round(basePos.z), alt_m = 0, speed_mps = 0 } }
    local function add(kind, q, a) route[#route + 1] = { kind = kind, x = round(q.x), z = round(q.z), alt_m = a, speed_mps = speed } end
    local first = station.ends[1]
    local start = basePos
    if Util.dist(basePos, first) > (DEPARTURE_KM + 40) * 1000 then
        start = offset(basePos, first, DEPARTURE_KM)
        add("departure", start, cruise)
    end
    local out = threatRoute(ctx, start, first, reachOf(p), ctx.station_threats)
    for i = 2, #out - 1 do add("transit", out[i], cruise) end
    add("station", first, alt)
    route[#route].carries_attack_tasks = true
    add("station_end", station.ends[2], alt)
    for i = #out - 1, 2, -1 do add("transit", out[i], cruise) end
    if start ~= basePos then add("transit", start, cruise) end
    add("landing", basePos, 0)
    return route
end

-- Seconds from takeoff to the station, and from the station's far end home.
local function stationLegs(route, speed)
    local to, home, phase = 0, 0, "out"
    for i = 2, #route do
        local d = Util.dist(route[i - 1], route[i]) / speed
        if phase == "out" then to = to + d elseif phase == "home" then home = home + d end
        if route[i].kind == "station" then phase = "on" elseif route[i].kind == "station_end" then phase = "home" end
    end
    return to, home
end

-- A flight for a station: aircraft from the roster with a base in reach (nearest first)
-- whose route enters no enemy kill zone and at most station_enemy_airspace_km of enemy
-- airspace, parking free at its start, and under the
-- airborne cap; or nil and why. `arrive_s` and
-- `leave_s` are its time on station; `takeoff` "runway" needs no parking.
-- `human` (a human flight): { aircraft_type, bases, count, takeoff_s } as for
-- draftMission; the flight takes off at takeoff_s and stays on station on_station_s from
-- when it gets there (arrive_s / leave_s are ignored); its parking is its player slot.
local function draftStationFlight(ctx, missionType, station, arrive_s, leave_s, human)
    local mt = AIR_MISSION_TYPE[missionType]
    local T = AIR_TASKING_TIMING
    local reason = "no aircraft in reach"
    for _ = 1, AIRCRAFT_TRIES do
        local aircraftType = human and human.aircraft_type or Util.weightedPick(COALITION_AIRCRAFT[ctx.coalition][missionType])
        local p = AIRCRAFT_PROFILE[aircraftType]
        local bases = {}
        for _, b in ipairs(human and human.bases or launchBases(ctx, aircraftType)) do
            local d = Util.dist(ctx.plan.world.airbases[b].pos, station.centre)
            if d <= p.combat_radius_km * 1000 and (not station.region or ctx.base_region[b] == station.region) then
                bases[#bases + 1] = { name = b, d = d }
            end
        end
        if station.base then   -- the AWACS: its base is chosen with its orbit
            bases = { { name = station.base, d = Util.dist(ctx.plan.world.airbases[station.base].pos, station.centre) } }
        end
        table.sort(bases, function(a, b) return a.d < b.d end)
        for _, b in ipairs(bases) do
            local basePos = ctx.plan.world.airbases[b.name].pos
            local alt = p.attack_altitude_m[missionType]
            local route = stationRoute(ctx, basePos, station, p, alt)
            local to, home = stationLegs(route, p.cruise_speed_mps)
            -- station flights have no suppression: a base whose way there enters an enemy
            -- kill zone (or that stands inside one) can't fly them
            local crossed = ThreatRouting.crossed(ctx.station_threats, route)
            -- patrols and the AWACS work own and contested airspace: a base that can only
            -- reach the station through enemy airspace can't fly it
            local enemyKm = enemyAirspaceKm(ctx, route)
            local count = human and human.count or flightSize(mt, p)
            local taxi = (mt.takeoff == "runway") and 60 or T.taxi_s
            -- the AWACS goes at mission start; patrols no earlier than the first attack flights
            local earliest = (missionType == EARLY_WARNING) and 0 or T.first_start_s
            local f = { mission_type = missionType, mt = mt, aircraft_type = aircraftType, p = p, base = b.name,
                        distance_km = b.d / 1000, count = count, route = route, crossed = {},
                        enemy_airspace_km = enemyKm,
                        start_s = round(math.max(earliest, arrive_s - to - taxi)) }
            if human then
                f.start_s = human.takeoff_s - taxi
                arrive_s = human.takeoff_s + to
                leave_s = math.min(arrive_s + AIR_DEFENSE.on_station_s, T.window_s)
                f.player_slot = human.slot_at[b.name]
            end
            f.takeoff_s = f.start_s + taxi
            f.tot_s = round(f.takeoff_s + to)
            f.end_s = round(leave_s + home + T.landing_s)
            local up = airborneAtMost(ctx, { { f.takeoff_s, f.end_s - T.landing_s, human and 0 or count } })
            if #crossed > 0 then
                reason = "route enters " .. crossed[1]
            elseif enemyKm > AIR_DEFENSE.station_enemy_airspace_km then
                reason = "route through enemy airspace"
            elseif up > ctx.planned_cap then
                reason = "over the airborne cap"
            else
                local ok = true
                if f.player_slot then
                    f.spots = { f.player_slot.parking }
                elseif mt.takeoff ~= "runway" then
                    f.spots = reserveParking(ctx, b.name, aircraftType, count, f.start_s)
                    ok = f.spots ~= nil
                    if not ok then reason = "no parking" end
                end
                if ok then
                    local e = station.ends
                    local tasks = { kind = mt.attack, station = { e[1].x, e[1].z, e[2].x, e[2].z },
                                    altitude_m = alt, speed_mps = p.cruise_speed_mps, until_s = round(leave_s),
                                    engage_range_m = mt.engage_range_km and mt.engage_range_km * 1000,
                                    zone = station.zone, commit = station.commit }
                    f.attack = tasks
                    f.target = { id = station.id, label = station.label, kind = station.kind .. "_station",
                                 pos = station.centre, critical_names = {} }
                    return f
                end
            end
        end
    end
    return nil, reason
end

-- Patrol rotations over each station for the whole window: each flight is on station
-- on_station_s, the next arrives rotation_overlap_s before it leaves. A rotation that
-- can't be flown leaves a gap (logged); the next one is tried on time.
local function planPatrols(ctx, stations)
    local D, T = AIR_DEFENSE, AIR_TASKING_TIMING
    local flights = {}
    for _, station in ipairs(stations) do
        -- the first patrol is up as early as the first attack flights: spawned from
        -- first_start_s, on station about five minutes after a jet that close could be
        -- (one from a farther base gets there as soon as its transit allows)
        local arrive = T.first_start_s + T.taxi_s + 5 * 60
        local n = 0
        while arrive < T.window_s - D.rotation_overlap_s do
            local leave = math.min(arrive + D.on_station_s, T.window_s)
            local f, why = draftStationFlight(ctx, PATROL, station, arrive, leave)
            if f then
                local m = commitFlight(ctx, f, station.id)
                m.station = station.id
                flights[#flights + 1] = m
                n = n + 1
                logFlight(ctx, m, string.format("  on station %s–%s", clock(arrive), clock(leave)))
            else
                Log.warn(string.format("  %s %s: no patrol on station %s–%s (%s)", ctx.coalition:upper(), station.id,
                    clock(arrive), clock(leave), why))
            end
            arrive = arrive + D.on_station_s - D.rotation_overlap_s
        end
        station.patrols = n
    end
    return flights
end

-- One AWACS: taken off the runway of the held base (that can launch it) farthest from
-- the enemy, orbiting on the line from there toward the nearest enemy fighter base as far
-- forward as it stays early_warning_standoff_km from every enemy base and clear of enemy
-- rings; on station until the window ends.
local function planEarlyWarning(ctx)
    local D, T = AIR_DEFENSE, AIR_TASKING_TIMING
    local roster = COALITION_AIRCRAFT[ctx.coalition][EARLY_WARNING]
    local aircraftType = Util.weightedPick(roster)
    local bases = launchBases(ctx, aircraftType)
    local enemiesAll = basesOf(ctx, BASE_CLASSES, true)
    local enemies = basesOf(ctx, FIGHTER_BASE_CLASSES, true)
    if #bases == 0 or #enemies == 0 then
        Log.warn(string.format("  %s: no base can launch an %s — no AWACS", ctx.coalition:upper(), aircraftType))
        return nil
    end
    local base, far
    for _, b in ipairs(bases) do
        local _, d = nearestBase(ctx, ctx.plan.world.airbases[b].pos, enemiesAll)
        if not far or d > far then base, far = b, d end
    end
    local basePos = ctx.plan.world.airbases[base].pos
    local toward = ctx.plan.world.airbases[nearestBase(ctx, basePos, enemies)].pos
    -- as far forward as it keeps the standoff from every enemy base
    local limit = 0
    local step = D.step_km * 1000
    local total = Util.dist(basePos, toward)
    local d = 0
    while d <= total do
        local q = offset(basePos, toward, d / 1000)
        local _, e = nearestBase(ctx, q, enemiesAll)
        if e < D.early_warning_standoff_km * 1000 then break end
        limit = d
        d = d + step
    end
    local centre, a, b = farthestClearPoint(ctx, basePos, toward, D.early_warning_clearance_km * 1000,
        D.early_warning_leg_km * 1000, limit, nil, nil, true)
    if not centre then
        centre = basePos
        a, b = raceTrack(basePos, basePos, toward, D.early_warning_leg_km * 1000)
    end
    local station = { id = string.format("AEW_%s_1", AIRBASE_CODE[base] or base), kind = "early_warning",
                      home = base, base = base, centre = { x = round(centre.x), z = round(centre.z) }, ends = { a, b },
                      label = string.format("early-warning orbit from %s", base) }
    -- the orbit is reached as soon as it can be: spawned at early_warning_start_s
    local p = AIRCRAFT_PROFILE[aircraftType]
    local to = stationLegs(stationRoute(ctx, basePos, station, p, p.attack_altitude_m[EARLY_WARNING]), p.cruise_speed_mps)
    local f, why = draftStationFlight(ctx, EARLY_WARNING, station, D.early_warning_start_s + 60 + to, T.window_s)
    if not f then
        Log.warn(string.format("  %s: no AWACS (%s)", ctx.coalition:upper(), why))
        return nil
    end
    local m = commitFlight(ctx, f, station.id)
    m.station = station.id
    logFlight(ctx, m, "  on station until the window ends")
    return m, station
end

-- Ramp spots held for the alert jets at an alert base for the whole mission, like player
-- slots: free of parked-aircraft statics, player slots and any flight already planned
-- there, of a terminal type every interception type at the base fits, nearest a runway.
-- No other flight is given them (they're busy from 0 to the end). Returns
-- { { terminal_index, x, z } } or nil when the base can't spare `count`.
local function reserveAlertSpots(ctx, base, types, count)
    local ab = ctx.plan.world.airbases[base]
    local statics = ctx.plan.fixed_ground_targets and ctx.plan.fixed_ground_targets.parking_used[base] or {}
    local busy = ctx.parking_busy[base] or {}
    ctx.parking_busy[base] = busy
    local fits = {}
    for _, s in ipairs(ab.parking) do
        local ok = statics[s[4]] == nil and ab.player_slots[s[4]] == nil and #(busy[s[4]] or {}) == 0
        for _, t in ipairs(types) do
            local fitsType = false
            for _, term in ipairs(AIRCRAFT_PROFILE[t[1]].parking) do
                if term == s[3] then fitsType = true end
            end
            ok = ok and fitsType
        end
        if ok then
            local d = math.huge
            for _, r in ipairs(ab.runways or {}) do d = math.min(d, (s[1] - r.x) ^ 2 + (s[2] - r.z) ^ 2) end
            fits[#fits + 1] = { s = s, d = d }
        end
    end
    if #fits < count then return nil end
    table.sort(fits, function(a, b) return a.d < b.d end)
    local spots = {}
    for i = 1, count do
        local s = fits[i].s
        busy[s[4]] = busy[s[4]] or {}
        table.insert(busy[s[4]], { 0, math.huge })
        spots[i] = { terminal_index = s[4], x = s[1], z = s[2] }
    end
    return spots
end

-- The scramble posture: the alert bases and the aircraft they hold. Nothing here spawns;
-- the controller (consumers/control_air_flights/scramble_fighters.lua) launches from it at run time, on what the radar picture
-- shows. Alert bases: held bases whose runway and parking fit an interception type (in
-- wartime every usable runway is used: Finnish and Swedish dispersal doctrine), the
-- AIR_DEFENSE.alert_bases nearest the enemy, each holding alert_aircraft_per_base jets, plus the nearest of each other region that
-- has one, so a pocket can answer for itself. A base inside an enemy kill zone holds no
-- alert: nobody keeps quick-reaction fighters under the enemy's SAM umbrella, and every
-- way out of it would start inside the kill zone. Each alert base holds ramp spots for
-- its alert jets (reserveAlertSpots); a base that can't spare them isn't one.
local function planAlertPosture(ctx)
    local D = AIR_DEFENSE
    local roster = COALITION_AIRCRAFT[ctx.coalition][INTERCEPTION]
    local enemiesAll = basesOf(ctx, BASE_CLASSES, true)
    local typesAt = {}
    for _, e in ipairs(roster) do
        for _, b in ipairs(launchBases(ctx, e[1])) do
            typesAt[b] = typesAt[b] or {}
            table.insert(typesAt[b], { e[1], e[2] })
        end
    end
    local candidates = {}
    for _, name in ipairs(ctx.held) do
        if typesAt[name] then   -- launchBases already left out bases under enemy SAMs
            local pos = ctx.plan.world.airbases[name].pos
            local _, d = nearestBase(ctx, pos, enemiesAll)
            candidates[#candidates + 1] = { base = name, code = AIRBASE_CODE[name], aircraft = typesAt[name],
                                            region = ctx.base_region[name], pos = pos,
                                            enemy_km = round((d or 0) / 1000) }
        end
    end
    table.sort(candidates, function(a, b)
        if a.enemy_km ~= b.enemy_km then return a.enemy_km < b.enemy_km end
        return a.base < b.base
    end)
    local alert, regions, tried = {}, {}, {}
    local function take(c)
        if tried[c] then return false end
        tried[c] = true
        c.spots = reserveAlertSpots(ctx, c.base, c.aircraft, D.alert_aircraft_per_base)
        if not c.spots then
            Log.warn(string.format("  %s: %s has no %d free ramp spots for alert jets — not an alert base",
                ctx.coalition:upper(), c.base, D.alert_aircraft_per_base))
            return false
        end
        c.alert_aircraft = D.alert_aircraft_per_base
        c.cooldown_s = D.scramble_cooldown_s
        alert[#alert + 1] = c
        regions[c.region] = true
        return true
    end
    local taken = 0
    for _, c in ipairs(candidates) do
        if taken >= D.alert_bases then break end
        if take(c) then taken = taken + 1 end
    end
    for _, c in ipairs(candidates) do
        if not regions[c.region] then take(c) end   -- the nearest of a region not covered yet
    end
    local names = {}
    for _, c in ipairs(alert) do names[#names + 1] = string.format("%s (%d km from the enemy)", c.base, c.enemy_km) end
    Log.info(string.format("  %s alert bases: %s", ctx.coalition:upper(), #names > 0 and table.concat(names, ", ") or "none"))
    return { bases = alert, max_airborne_aircraft = ctx.per.max_airborne_aircraft,
             first_number = FIRST_NUMBER[ctx.coalition] + 900 }
end

-- ── human flights ───────────────────────────────────────────────

-- The bases a human flight can launch from: held bases that can launch
-- HUMAN_TASKING.aircraft_type and have a player slot whose spot exists. Returns the base
-- names and, per base, its slot { group, spot, terminal_index, parking (the spot) }.
local function humanSlotBases(ctx)
    local bases, slotAt = {}, {}
    for _, name in ipairs(launchBases(ctx, HUMAN_TASKING.aircraft_type)) do
        for _, slot in ipairs(PLAYER_SLOTS[name] or {}) do
            for _, s in ipairs(ctx.plan.world.airbases[name].parking) do
                if not slotAt[name] and s[4] == slot.terminal_index then
                    slotAt[name] = { group = slot.group, spot = slot.spot, terminal_index = slot.terminal_index, parking = s }
                end
            end
        end
        if slotAt[name] then bases[#bases + 1] = name end
    end
    return bases, slotAt
end

-- One human flight of `missionType` and its package, or nil. `human` = { aircraft_type,
-- bases, count, takeoff_s, slot_at }. A strike, airfield strike or destruction of air
-- defenses is planned like the AI's, with the player's aircraft and bases, and gets AI
-- suppression flights if its route needs them. Suppression: an AI mission whose route
-- needs it, the player taking the first threats on the way and AI flights the rest. A
-- patrol: one of the front stations. Returns the human flight's plan entry.
local function planHumanMission(ctx, missionType, human, failures)
    local function fail(reason) failures[reason] = (failures[reason] or 0) + 1 end
    if missionType == PATROL then
        local stations = {}
        for _, s in ipairs(ctx.out.stations or {}) do
            if s.kind == "front" then stations[#stations + 1] = s end
        end
        if #stations == 0 then fail("no patrol station") return nil end
        Util.shuffle(stations)
        for _, st in ipairs(stations) do
            local f, why = draftStationFlight(ctx, PATROL, st, 0, 0, human)
            if f then
                local m = commitFlight(ctx, f, st.id)
                m.station = st.id
                logFlight(ctx, m, string.format("  on station %s–%s", clock(m.tot_s), clock(m.attack.until_s)))
                return m
            end
            fail(why)
        end
        return nil
    end
    for _ = 1, MISSION_TRIES do
        local flights, own
        if missionType == SUPPRESSION then
            local main, why = draftMission(ctx, Util.weightedPick(ctx.attack_types))
            if not main then
                fail(why)
            elseif #main.crossed == 0 then
                fail("route needs no suppression")
            else
                local remaining = {}
                for i, id in ipairs(main.crossed) do remaining[i] = id end
                local noOwn, rest, noRest
                own, noOwn = draftSuppressionFlight(ctx, main, remaining, human)
                if own then rest, noRest = draftSuppression(ctx, main, remaining) end
                if not own then
                    fail("no player SEAD: " .. noOwn)
                elseif not rest then
                    fail("no suppression flight: " .. noRest)
                else
                    flights = { main, own }
                    for _, f in ipairs(rest) do flights[#flights + 1] = f end
                end
            end
        else
            local main, why = draftMission(ctx, missionType, human)
            local escorts, noEscort = {}, nil
            if main and #main.crossed > 0 then escorts, noEscort = draftSuppression(ctx, main) end
            if not main then
                fail(why)
            elseif not escorts then
                fail("no suppression flight: " .. noEscort)
            else
                own, flights = main, { main }
                for _, f in ipairs(escorts) do flights[#flights + 1] = f end
            end
        end
        if flights then
            own.player_slot = human.slot_at[own.base]
            local ok, why
            if missionType == SUPPRESSION then
                -- the AI mission behind the player's SEAD flies in sequence, after it
                flights[1].sequence, flights[1].cleared_by = true, {}
                ok, why = scheduleHumanSeadPackage(ctx, flights, own, human.takeoff_s)
            else
                ok, why = scheduleHumanPackage(ctx, flights, own, human.takeoff_s)
            end
            if ok then
                commitPackage(ctx, flights)
                return own.committed
            end
            fail(why)
        end
    end
    return nil
end

-- HUMAN_TASKING.missions human flights, each taking off startup_s after mission start.
-- Each tries its mission types in weighted random order (types another human flight
-- already has go last, for variety), first from slot bases no other human flight uses,
-- then from any slot base. Returns the plan entries.
local function planHumanMissions(ctx)
    local H = HUMAN_TASKING
    local bases, slotAt = humanSlotBases(ctx)
    local out, usedBases, usedTypes = {}, {}, {}
    if #bases == 0 then
        Log.warn(string.format("  %s: no held base with a player slot can launch an %s — no human flights",
            ctx.coalition:upper(), H.aircraft_type))
        return out
    end
    for n = 1, H.missions do
        local takeoff = round(H.startup_s[1] + math.random() * (H.startup_s[2] - H.startup_s[1]))
        local pool, fresh, again = {}, {}, {}
        for i, e in ipairs(H.mission_types) do pool[i] = e end
        while #pool > 0 do
            local mt = Util.weightedPick(pool)
            for i, e in ipairs(pool) do
                if e[1] == mt then table.remove(pool, i) break end
            end
            table.insert(usedTypes[mt] and again or fresh, mt)
        end
        for _, mt in ipairs(again) do fresh[#fresh + 1] = mt end
        local failures, m = {}, nil
        for pass = 1, 2 do
            local list = {}
            for _, b in ipairs(bases) do
                if pass == 2 or not usedBases[b] then list[#list + 1] = b end
            end
            if #list > 0 and not m then
                local human = { aircraft_type = H.aircraft_type, bases = list, count = 1, takeoff_s = takeoff,
                                slot_at = slotAt }
                for _, mt in ipairs(fresh) do
                    m = planHumanMission(ctx, mt, human, failures)
                    if m then break end
                end
            end
        end
        if m then
            usedBases[m.launch_base], usedTypes[m.mission_type] = true, true
            out[#out + 1] = m
        else
            local parts = {}
            for _, k in ipairs(sortedKeys(failures)) do parts[#parts + 1] = k .. " " .. failures[k] end
            Log.warn(string.format("  %s human flight %d of %d not planned (%s)", ctx.coalition:upper(), n, H.missions,
                table.concat(parts, ", ")))
        end
    end
    return out
end

-- ── what a coalition's flights route around ─────────────────────

-- The enemy threats this coalition's flights can't overfly, as circles: SAM sites of the
-- layers in AIR_ROUTING.threat_layers (engagement ring + margin) and enemy base-defense
-- groups of AIR_ROUTING.base_defense_roles (their longest reach + margin). Also returns,
-- per circle id, the DCS groups a suppression flight engages for it: a SAM site's own
-- group first, then its point-defense escort; a base-defense group itself.
-- `kind` "killzone": each circle is instead the threat's kill zone, its reach times
-- AIR_DEFENSE.killzone_fraction, no margin (what patrols and the AWACS keep out of).
-- `kind` "low": a SAM site's circle is how far it reaches a low flyer
-- (lib/sam_reach.lua) + margin (what a SEAD flight's low run-in keeps out of; base
-- defenses keep their full reach, they are low-altitude weapons).
local function threatCircles(plan, coalition, kind)
    local killzone = kind == "killzone"
    local circles, groups = {}, {}
    local scale = killzone and AIR_DEFENSE.killzone_fraction or 1
    local margin = killzone and 0 or AIR_ROUTING.threat_margin_km * 1000
    for _, s in ipairs(plan.sam_sites and plan.sam_sites.sites or {}) do
        if s.side ~= coalition and AIR_ROUTING.threat_layers[s.layer] and (s.engage_m or 0) > 0 then
            local reach = kind == "low" and SamReach.radius(s, 0) or s.engage_m
            circles[#circles + 1] = { id = s.id, x = s.pos.x, z = s.pos.z, radius_m = reach * scale + margin }
            local g = { s.id }
            for _, name in ipairs(s.group_ids or {}) do
                if name ~= s.id then g[#g + 1] = name end
            end
            groups[s.id] = g
        end
    end
    local bdMargin = killzone and 0 or AIR_ROUTING.base_defense_margin_km * 1000
    for _, g in ipairs(plan.base_defenses and plan.base_defenses.groups or {}) do
        if g.side ~= coalition and AIR_ROUTING.base_defense_roles[g.role] then
            local reach = 0
            for _, u in ipairs(g.units) do
                local pool = UNIT_POOL.ground[u.type]
                if pool and (pool.threat_m or 0) > reach then reach = pool.threat_m end
            end
            if reach > 0 then
                circles[#circles + 1] = { id = g.id, x = g.pos.x, z = g.pos.z, radius_m = reach * scale + bdMargin }
                groups[g.id] = { g.id }
            end
        end
    end
    return circles, groups
end

-- The map area the routing grid covers: every airbase, plus room to fly around.
local function mapBounds(world)
    local b = { min_x = math.huge, max_x = -math.huge, min_z = math.huge, max_z = -math.huge }
    for _, ab in pairs(world.airbases) do
        b.min_x, b.max_x = math.min(b.min_x, ab.pos.x), math.max(b.max_x, ab.pos.x)
        b.min_z, b.max_z = math.min(b.min_z, ab.pos.z), math.max(b.max_z, ab.pos.z)
    end
    local pad = 200000
    return { min_x = b.min_x - pad, max_x = b.max_x + pad, min_z = b.min_z - pad, max_z = b.max_z + pad }
end

-- ── stage ───────────────────────────────────────────────────────

function PlanAirTasking.run(plan)
    Log.info("--- Stages 5–6: air tasking orders ---")
    local out = {}
    plan.air_tasking_orders = out
    if #PlanAirTasking.checkData() > 0 then
        out.problems = _problems
        return plan
    end

    if not plan.airspace then
        Log.error("air tasking needs plan.airspace (DivideAirspace runs first) — nothing planned")
        out.problems = { "no plan.airspace" }
        return plan
    end
    local positions = objectPositions(plan)
    for _, coalition in ipairs(COALITIONS) do
        local per = AIR_TASKING_PER_COALITION[coalition]
        local res = { missions = {}, packages = {},
                      summary = { missions = 0, suppression_flights = 0, flights = 0, by_type = {},
                                  not_planned = 0, failures = {}, patrols = 0, stations = 0,
                                  early_warning = 0, alert_bases = 0 } }
        out[coalition] = res
        local held = {}
        for name, b in pairs(plan.territory.bases) do
            if b.side == coalition then held[#held + 1] = name end
        end
        table.sort(held)
        local circles, threatGroups = threatCircles(plan, coalition)
        -- routes are priced by the airspace they fly through, as this coalition sees it
        local function airspaceCost(x, z)
            return AIR_ROUTING.airspace_cost[DivideAirspace.kindFor(plan.airspace, { x = x, z = z }, coalition)]
        end
        local baseRegion = {}
        for _, name in ipairs(held) do baseRegion[name] = DivideAirspace.regionAt(plan.airspace, plan.world.airbases[name].pos) end
        local bounds = mapBounds(plan.world)
        local ctx = { plan = plan, coalition = coalition, per = per, out = res, held = held,
                      planned_cap = plannedCap(per),
                      threats = ThreatRouting.buildMap(circles, bounds, airspaceCost),
                      low_threats = ThreatRouting.buildMap((threatCircles(plan, coalition, "low")), bounds, airspaceCost),
                      station_threats = AIR_DEFENSE.planned
                          and ThreatRouting.buildMap((threatCircles(plan, coalition, "killzone")), bounds, airspaceCost),
                      threat_groups = threatGroups, base_region = baseRegion, target_fronts = {},
                      positions = positions, taken = {}, parking_busy = {}, routes = {},
                      next_number = FIRST_NUMBER[coalition], attack_missions = 0,
                      cleared = {} }   -- threat id → { by = suppression flight id, after_s }

        -- defensive air first ("support up first"): its share of the cap is taken before
        -- the attack packages fill the rest
        if AIR_DEFENSE.planned then
            local earlyWarning, orbit = planEarlyWarning(ctx)
            -- the alert bases hold their alert jets' ramp spots for the whole mission, so they
            -- are picked before any patrol takes parking
            if AIR_DEFENSE.alert_posture_planned then res.alert = planAlertPosture(ctx) end
            local stations = planStations(ctx)
            local patrols = planPatrols(ctx, stations)
            if orbit then table.insert(stations, 1, orbit) end
            res.stations = stations
            res.summary.patrols, res.summary.stations = #patrols, #stations - (orbit and 1 or 0)
            res.summary.early_warning = earlyWarning and 1 or 0
            res.summary.alert_bases = res.alert and #res.alert.bases or 0
        end

        local types = {}
        for _, e in ipairs(per.mission_types) do
            local m = AIR_MISSION_TYPE[e[1]]
            if m.built and (m.planned_as or "mission") == "mission" then types[#types + 1] = e end
        end
        ctx.attack_types = types

        -- human flights next: they get the pick of the targets, and the AI missions fill
        -- in around them
        res.human_missions = {}
        if coalition == HUMAN_TASKING.coalition then
            for _, m in ipairs(planHumanMissions(ctx)) do res.human_missions[#res.human_missions + 1] = m.id end
        end
        res.summary.human = #res.human_missions

        local wanted = math.random(per.missions[1], per.missions[2])
        for _ = 1, wanted do
            local missionType = Util.weightedPick(types)
            local failures = {}
            local m, package = planMission(ctx, missionType, failures)
            if m then
                res.summary.missions = res.summary.missions + 1
                res.summary.suppression_flights = res.summary.suppression_flights + #package.suppression_flights
                res.summary.by_type[missionType] = (res.summary.by_type[missionType] or 0) + 1
            else
                res.summary.not_planned = res.summary.not_planned + 1
                local parts = {}
                for _, k in ipairs(sortedKeys(failures)) do
                    parts[#parts + 1] = k .. " " .. failures[k]
                    res.summary.failures[k] = (res.summary.failures[k] or 0) + failures[k]
                end
                Log.warn(string.format("  %s %s: mission not planned (%s)", coalition:upper(), missionType,
                    table.concat(parts, ", ")))
            end
        end
        res.summary.flights = #res.missions
        table.sort(res.missions, function(a, b) return a.start_s < b.start_s end)
        local parts = {}
        for _, k in ipairs(sortedKeys(res.summary.by_type)) do parts[#parts + 1] = k .. " " .. res.summary.by_type[k] end
        Log.info(string.format("  %s: %d human flights (%s), %d of %d missions planned, %d suppression flights, %d patrols on %d stations, %d AWACS, %d flights  [%s]",
            coalition:upper(), res.summary.human, table.concat(res.human_missions, ", "), res.summary.missions, wanted,
            res.summary.suppression_flights, res.summary.patrols,
            res.summary.stations, res.summary.early_warning, res.summary.flights, table.concat(parts, ", ")))
    end
    return plan
end
