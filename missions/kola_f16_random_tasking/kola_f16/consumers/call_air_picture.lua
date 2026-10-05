-- Consumer: the air picture for human players (roadmap.md item 5, text first). Every
-- AIR_PICTURE_CALLS.call_every_s each player in an aircraft gets a list of every contact
-- in their own coalition's radar picture (TrackRadarPicture: only what its own radars
-- see), highest threat first, as BRAA from the player's own position (John, 2026-10-02:
-- no bullseye, nothing to ask for; every 2 min, 14 s on screen, short enough to read at a
-- glance):
--
--   DARKSTAR picture, 3 groups
--   Su-27 - 135/42nm, 25k, hot, 5s
--   unknown - 080/96nm, 18k, flank N, 12s
--   MiG-31 - 020/150nm, 30k, drag NE, 95s
--
-- bearing (magnetic) / range, altitude in thousands of feet ("low" under 1,000 ft),
-- aspect (with the contact's direction of travel), and how old the position is (seconds
-- since a radar read it). Only tracked contacts are called: a stale track (no radar has
-- seen it for RADAR_PICTURE.stale_after_s) is left out (John, 2026-10-05: no reason to
-- hear 5 min old contacts).
-- Bearing: magnetic as DCS works it out, grid bearing minus the variation at the player
-- (bug 61, 2026-10-05: the F-16's HUD and the F10 ruler take the map's grid north as true
-- north; a bearing from true north was off by the grid's convergence, ~6° near Ivalo).
-- Variation from DCS's own magvar module (as the mission editor and the DTC use it); an
-- approximate table by longitude (AIR_PICTURE_CALLS.fallback_magnetic_variation) if it
-- can't be loaded or answers 0.
-- Aspect is the angle between the contact's heading and the line from it to the player.
-- Threat order: range × a factor per aspect (AIR_PICTURE_CALLS.threat_range_factor).
-- A contact whose range no sensor knows (a jammer) reads "135/?nm".
-- Coverage (2026-10-02, John: in the 19:29 run Darkstar called "clean" while two Red
-- scrambles closed on him, 450+ km from Blue's E-3A): a player outside every live
-- sensor's reach hears it in the header, "no radar coverage your area", instead of a
-- picture that only looks clean. A sensor's reach at the player's height above the
-- ground (AIR_PICTURE_CALLS.coverage): the AWACS awacs_km, fighters fighter_km, a ground
-- radar its type's detection range (UNIT_POOL), each no farther than the radar horizon.
--
-- The facts per group are worked out in one place (describe) and the text is only one
-- way of sending them, so the AI radio calls (item 7) can speak them later.
-- Informs players only: no orders, nothing written to the plan. Event log:
--   PICTURE_CALL  BLUE  f16_rovaniemi  "to New callsign: 3 groups; first Su-27 - 135/42nm, 25k, hot, 5s"
--   PICTURE_CALL  BLUE  f16_ivalo      "to New callsign: nothing; no radar coverage"

CallAirPicture = {}

local SIDE_NAME = { [1] = "red", [2] = "blue" }   -- coalition.side
local FEET_PER_METRE = 3.28084
local METRES_PER_NM  = 1852
local CARDINAL = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local _magvar          -- DCS's magvar module, or nil
local _variationLogged = false

-- ── geometry ────────────────────────────────────────────────────

local function round(v) return math.floor(v + 0.5) end

local function norm(deg) return (deg % 360 + 360) % 360 end

-- Smallest angle between two directions, 0–180.
local function angleBetween(a, b)
    local d = math.abs(norm(a) - norm(b))
    return d > 180 and 360 - d or d
end

local function latLon(pos)
    return coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
end

-- Grid bearing (map x north, z east), degrees.
local function gridBearing(a, b)
    return norm(math.deg(math.atan2(b.z - a.z, b.x - a.x)))
end

-- DCS's answer at lat/lon, degrees east, or nil.
local function magvarAt(lat, lon)
    if not _magvar then return nil end
    local ok, rad = pcall(_magvar.get_mag_decl, lat, lon)
    local deg = ok and type(rad) == "number" and math.deg(rad)
    if deg and math.abs(deg) < 40 then return deg end
    return nil
end

-- The data's approximate variation at a longitude, degrees east.
local function fallbackAt(lon)
    local t = AIR_PICTURE_CALLS.fallback_magnetic_variation
    if lon <= t[1].lon then return t[1].deg end
    for i = 2, #t do
        if lon <= t[i].lon then
            local f = (lon - t[i - 1].lon) / (t[i].lon - t[i - 1].lon)
            return t[i - 1].deg + f * (t[i].deg - t[i - 1].deg)
        end
    end
    return t[#t].deg
end

-- Magnetic variation at lat/lon, degrees east.
local function variation(lat, lon)
    local deg = magvarAt(lat, lon)
    if deg then return deg end
    if not _variationLogged then
        _variationLogged = true
        Log.warn("air picture: magvar unavailable, using the approximate variation by longitude (AIR_PICTURE_CALLS)")
    end
    return fallbackAt(lon)
end

-- Magnetic variation at lat/lon, degrees east, for other consumers (the airfield brief's
-- wind and runway numbers). DCS's magvar once CallAirPicture.start has loaded it.
-- Subtract it from a grid direction, not a true one (DCS's magnetic is grid-based).
function CallAirPicture.magneticVariation(lat, lon)
    return variation(lat, lon)
end

local function loadMagvar(plan)
    local ok, mod = pcall(require, "magvar")
    if not ok or type(mod) ~= "table" or type(mod.get_mag_decl) ~= "function" then
        Log.warn("air picture: DCS's magvar module could not be loaded (" .. tostring(mod) .. ")")
        return nil
    end
    local date = plan.world and plan.world.time and plan.world.time.date
    if date and type(mod.init) == "function" then pcall(mod.init, date.Month, date.Year) end
    return mod
end

local function cardinal(deg)
    return CARDINAL[math.floor(norm(deg) / 45 + 0.5) % 8 + 1]
end

-- ── one group, from one player ──────────────────────────────────

-- The facts for one contact as seen from `own` ({ pos, lat, lon, variation }):
-- { contact, bearing (magnetic), range_nm, range_known, altitude_ft, aspect, track (the
--   contact's heading as a compass point, magnetic), type, age_s, threat }.
local function describe(c, own)
    -- magnetic = grid - variation, as the F-16 shows it (bug 61)
    local bearingMagnetic = norm(gridBearing(own.pos, c.pos) - own.variation)
    local trackMagnetic = norm(c.heading_deg - own.variation)
    -- aspect: the contact's heading against the line from it to the player (grid frame)
    local toPlayer = gridBearing(c.pos, own.pos)
    local off = angleBetween(c.heading_deg, toPlayer)
    local P = AIR_PICTURE_CALLS
    local aspect = off <= P.hot_deg and "hot" or off <= P.flank_deg and "flank"
                   or off <= P.beam_deg and "beam" or "drag"
    if (c.speed_mps or 0) < 20 then aspect = "slow" end   -- a hovering helicopter has no heading
    local rangeNm = Util.dist(own.pos, c.pos) / METRES_PER_NM
    local now = timer.getTime()
    return {
        contact = c,
        bearing = round(bearingMagnetic) % 360,
        range_nm = rangeNm, range_known = c.range_known,
        altitude_ft = c.altitude_m * FEET_PER_METRE,
        aspect = aspect, track = cardinal(trackMagnetic),
        type = c.type or (c.category == "helicopter" and "unknown helicopter" or "unknown"),
        -- from when a radar read the position, not the round's end (bug 61: was ~27 s short)
        age_s = math.max(0, round(now - (c.pos_seen_at or c.last_seen))),
        threat = rangeNm * (P.threat_range_factor[aspect] or P.threat_range_factor.drag),
    }
end

local function altitudeText(ft)
    if ft < 1000 then return "low" end
    return string.format("%dk", round(ft / 1000))
end

local function aspectText(g)
    if g.aspect == "hot" or g.aspect == "slow" then return g.aspect end
    return g.aspect .. " " .. g.track
end

-- "MiG-29S - 110/120nm, 10k, hot, 5s"
local function lineText(g)
    local range = g.range_known and string.format("%d", round(g.range_nm)) or "?"
    return string.format("%s - %03d/%snm, %s, %s, %ds", g.type, g.bearing, range, altitudeText(g.altitude_ft),
        aspectText(g), g.age_s)
end

-- ── the call ────────────────────────────────────────────────────

-- The player's own position and what bearings need from it.
local function ownFrom(unit)
    local p = unit:getPoint()
    local pos = { x = p.x, z = p.z }
    local lat, lon = latLon(pos)
    local okGround, ground = pcall(land.getHeight, { x = p.x, y = p.z })
    return { pos = pos, lat = lat, lon = lon, variation = variation(lat, lon),
             height_m = p.y - (okGround and ground or 0) }
end

-- ── coverage ────────────────────────────────────────────────────

-- Radar horizon, metres, between antennas / targets h1 and h2 metres up (4/3 earth).
local function horizonM(h1, h2)
    return 4120 * (math.sqrt(math.max(h1, 0)) + math.sqrt(math.max(h2, 0)))
end

local _groundDetection = {}   -- group name → its longest unit detection range, metres

local function groundDetectionM(g, name)
    if _groundDetection[name] == nil then
        local best = 0
        for _, u in ipairs(g:getUnits() or {}) do
            local pool = UNIT_POOL.ground[u:getTypeName()]
            if pool and (pool.detection_m or 0) > best then best = pool.detection_m end
        end
        _groundDetection[name] = best > 0 and best or AIR_PICTURE_CALLS.coverage.ground_default_km * 1000
    end
    return _groundDetection[name]
end

-- True when some live sensor of the coalition reaches the player where they are.
local function covered(sideName, own)
    local C = AIR_PICTURE_CALLS.coverage
    for _, sensor in ipairs(TrackRadarPicture.sensors(sideName)) do
        local ok, yes = pcall(function()
            local g = Group.getByName(sensor.id)
            local u = g and g:getUnits()[1]
            if not u then return false end
            local q = u:getPoint()
            local reach
            if sensor.kind == "awacs" then
                reach = math.min(C.awacs_km * 1000, horizonM(q.y, own.height_m))
            elseif sensor.kind == "patrol" or sensor.kind == "scramble" then
                reach = C.fighter_km * 1000
            else
                reach = math.min(groundDetectionM(g, sensor.id), C.ground_max_km * 1000,
                    horizonM(C.radar_height_m, own.height_m))
            end
            return Util.dist(own.pos, { x = q.x, z = q.z }) <= reach
        end)
        if ok and yes then return true end
    end
    return false
end

-- The list for one player unit: the text, the groups in threat order, and whether the
-- coalition's radars cover the player. SendRadioCalls reads it too (threat calls).
local function pictureFor(sideName, unit)
    local own = ownFrom(unit)
    local inCoverage = covered(sideName, own)
    local groups = {}
    for _, c in ipairs(TrackRadarPicture.contacts(sideName)) do
        -- tracked only: a stale track is old news, often a jet already down or landed
        if c.pos and c.heading_deg and c.state ~= "stale" then groups[#groups + 1] = describe(c, own) end
    end
    table.sort(groups, function(a, b)
        if a.threat ~= b.threat then return a.threat < b.threat end
        return a.contact.group < b.contact.group
    end)
    local P = AIR_PICTURE_CALLS
    local callsign = P.callsign[sideName] or "AWACS"
    local header = callsign .. " picture"
    if #groups == 0 then
        if not inCoverage then return callsign .. ": no radar coverage your area, picture unknown", groups, false end
        return header .. ", clean", groups, true
    end
    local lines = { string.format("%s, %d group%s%s", header, #groups, #groups == 1 and "" or "s",
        inCoverage and "" or "; no radar coverage your area") }
    for i = 1, math.min(#groups, P.max_groups) do lines[#lines + 1] = lineText(groups[i]) end
    if #groups > P.max_groups then lines[#lines + 1] = string.format("+%d more", #groups - P.max_groups) end
    return table.concat(lines, "\n"), groups, inCoverage
end

CallAirPicture.pictureFor = pictureFor

local function airborne(unit)
    local ok, yes = pcall(function() return unit:inAir() end)
    return ok and yes
end

-- One round: every player in an aircraft, one list per group (a group's first player).
local function callAll()
    local P = AIR_PICTURE_CALLS
    for side, sideName in pairs(SIDE_NAME) do
        local done = {}
        for _, unit in ipairs(coalition.getPlayers(side) or {}) do
            local ok, err = pcall(function()
                if not unit:isExist() then return end
                local group = unit:getGroup()
                local groupId = group and group:getID()
                if not groupId or done[groupId] then return end
                if not P.on_the_ground and not airborne(unit) then return end
                done[groupId] = true
                local text, groups, inCoverage = pictureFor(sideName, unit)
                trigger.action.outTextForGroup(groupId, text, P.show_s, false)
                SendRadioCalls.picture(sideName, group:getName(), groups, inCoverage)   -- spoken too
                if P.log_calls then
                    local first = groups[1]
                    WriteEventLog.add(sideName, "PICTURE_CALL", group:getName(), string.format("to %s: %s%s",
                        unit:getPlayerName() or "player",
                        first and string.format("%d group%s; first %s", #groups, #groups == 1 and "" or "s",
                            lineText(first)) or (inCoverage and "clean" or "nothing"),
                        inCoverage and "" or "; no radar coverage"))
                end
            end)
            if not ok then Log.warn("air picture: a call failed: " .. tostring(err)) end
        end
    end
end

function CallAirPicture.start(plan)
    if not AIR_PICTURE_CALLS.enabled then
        Log.info("--- Air picture calls: off (AIR_PICTURE_CALLS.enabled) ---")
        return
    end
    _magvar = loadMagvar(plan)
    -- self-test at Rovaniemi: the real variation on Kola is +5° or more everywhere, so an
    -- answer near 0 means the module isn't working here (it answers 0 outside the game)
    local ab = plan.world and plan.world.airbases and plan.world.airbases["Rovaniemi"]
    if _magvar and ab then
        local lat, lon = latLon(ab.pos)
        local deg = magvarAt(lat, lon)
        if not deg or math.abs(deg) < 1 then
            Log.warn(string.format("air picture: magvar answered %s at Rovaniemi, not used", tostring(deg)))
            _magvar = nil
        else
            Log.info(string.format("air picture: magvar %+.1f° at Rovaniemi (approximate table: %+.1f°)",
                deg, fallbackAt(lon)))
        end
    end
    timer.scheduleFunction(function(_, now)
        local ok, err = pcall(callAll)
        if not ok then Log.error("air picture: round failed: " .. tostring(err)) end
        return now + AIR_PICTURE_CALLS.call_every_s
    end, nil, timer.getTime() + AIR_PICTURE_CALLS.call_every_s)
    Log.info(string.format("--- Air picture calls: every %d s to every player, from their coalition's radar picture ---",
        AIR_PICTURE_CALLS.call_every_s))
end
