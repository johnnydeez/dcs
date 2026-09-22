-- Weather: turns the mission's raw env.mission weather / date / start_time into the
-- planner's vocabulary (plan.world.weather, plan.world.time). Pure functions over plain
-- data — the only DCS reads (atmosphere.* point queries) happen in gather.lua and are
-- passed in as `measured`. Also the solar math for day/night at high latitude (§1.11).
--
-- Field names below were pinned from a real 2.9 plan dump (kola_last_plan.lua):
--   clouds{ base, thickness, density, iprecptns, preset }   preset = "PresetN" | "RainyPresetN" | nil
--   fog{ visibility, thickness }  enable_fog                 (legacy fields; still what 2.9 exposes)
--   visibility{ distance }  wind{ atGround|at2000|at8000 = { dir, speed } }
--   qnh (mmHg)  season{ temperature (°C) }  dust_density  enable_dust  groundTurbulence
--
-- Wind direction: the .miz stores `dir` as the direction the wind blows TO; the ME
-- shows the FROM direction (dir + 180). Both are kept; gather also samples
-- atmosphere.getWind() so the debug display can confirm the convention in-sim.

Weather = {}

local MPS_TO_KTS   = 1.943844
local M_TO_FT      = 3.280840
local MMHG_TO_HPA  = 1.333224
local MMHG_TO_INHG = 0.0393701
local SM_TO_M      = 1609.344

-- ── Time ────────────────────────────────────────────────────────

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function isLeap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

function Weather.dayOfYear(date)
    local n = date.Day
    for m = 1, date.Month - 1 do
        n = n + DAYS_IN_MONTH[m] + ((m == 2 and isLeap(date.Year)) and 1 or 0)
    end
    return n
end

-- Seconds since midnight → "HH:MM". Wraps past 24 h.
function Weather.hhmm(secs)
    local s = math.floor(secs) % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function seasonOf(month)
    if month == 12 or month <= 2 then return "winter" end
    if month <= 5 then return "spring" end
    if month <= 8 then return "summer" end
    return "autumn"
end

-- ── Solar position (NOAA low-precision algorithm, good to ~0.1°) ──

-- Sun elevation in degrees at (lat, lon) for the given date and UTC seconds-since-midnight.
function Weather.sunElevation(lat, lon, date, utcSecs)
    local doy   = Weather.dayOfYear(date)
    local hour  = utcSecs / 3600
    local g     = 2 * math.pi / (isLeap(date.Year) and 366 or 365) * (doy - 1 + (hour - 12) / 24)
    local eqt   = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                            - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    local decl  = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g)
                  - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
                  - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
    local tst   = hour * 60 + eqt + 4 * lon              -- true solar time, minutes
    local ha    = math.rad(tst / 4 - 180)                -- hour angle
    local latR  = math.rad(lat)
    local cosZ  = math.sin(latR) * math.sin(decl) + math.cos(latR) * math.cos(decl) * math.cos(ha)
    if cosZ > 1 then cosZ = 1 elseif cosZ < -1 then cosZ = -1 end
    return 90 - math.deg(math.acos(cosZ))
end

function Weather.lightCondition(elev)
    if elev > 0   then return "day" end
    if elev > -6  then return "civil twilight" end
    if elev > -12 then return "nautical twilight" end
    return "night"
end

-- Sunrise/sunset and civil twilight for the local calendar day, by scanning the day in
-- one-minute steps (1440 cheap evaluations). Handles the polar cases: `polar` is
-- "midnight sun" / "polar night" when the sun never crosses the horizon.
-- Times are local "HH:MM"; nil when there is no such event that day.
function Weather.sunTimes(lat, lon, date, utcOffsetH)
    local RISE, CIVIL = -0.833, -6
    local out = { sunrise = nil, sunset = nil, civil_dawn = nil, civil_dusk = nil, polar = nil }
    local minElev, maxElev = math.huge, -math.huge
    local prev
    for m = 0, 1440 do
        local localSecs = m * 60
        local e = Weather.sunElevation(lat, lon, date, localSecs - utcOffsetH * 3600)
        if e < minElev then minElev = e end
        if e > maxElev then maxElev = e end
        if prev then
            local t = Weather.hhmm(localSecs)
            if prev < RISE  and e >= RISE  then out.sunrise    = out.sunrise    or t end
            if prev >= RISE  and e < RISE  then out.sunset     = t end
            if prev < CIVIL and e >= CIVIL then out.civil_dawn = out.civil_dawn or t end
            if prev >= CIVIL and e < CIVIL then out.civil_dusk = t end
        end
        prev = e
    end
    if minElev >= RISE then out.polar = "midnight sun"
    elseif maxElev < RISE then out.polar = "polar night" end
    out.max_elev = math.floor(maxElev * 10 + 0.5) / 10
    out.min_elev = math.floor(minElev * 10 + 0.5) / 10
    return out
end

-- ── Derivation ──────────────────────────────────────────────────

-- US flight categories from ceiling (ft AGL, nil = unlimited) and visibility (m).
function Weather.flightRules(ceilingFt, visM)
    local visSm = visM / SM_TO_M
    local c = ceilingFt or math.huge
    if c < 500  or visSm < 1 then return "LIFR" end
    if c < 1000 or visSm < 3 then return "IFR"  end
    if c <= 3000 or visSm <= 5 then return "MVFR" end
    return "VFR"
end

local function round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

local function windLevel(raw)
    raw = raw or { dir = 0, speed = 0 }
    return {
        to_deg   = math.floor(raw.dir + 0.5) % 360,
        from_deg = (math.floor(raw.dir + 0.5) + 180) % 360,
        mps      = round(raw.speed, 1),
        kts      = round(raw.speed * MPS_TO_KTS, 0),
    }
end

-- raw      : env.mission.weather (already deep-copied)
-- measured : { wind = { to_deg, mps }, temp_c, pressure_hpa } from atmosphere.* at ref (optional)
-- Returns the plan's weather table. Keeps `raw` inside it so the dump stays self-contained.
function Weather.derive(raw, measured)
    local w = { raw = raw }

    -- Clouds: preset weather carries only preset + base; coverage/precip come from CLOUD_PRESETS.
    local rc = raw.clouds or {}
    local preset = rc.preset and CLOUD_PRESETS and CLOUD_PRESETS[rc.preset] or nil
    local clouds = {
        preset      = rc.preset,
        name        = preset and preset.name or (rc.preset and ("unknown preset " .. rc.preset) or "legacy (no preset)"),
        metar       = preset and preset.metar or nil,
        base_m      = rc.base or 0,
        base_ft     = round((rc.base or 0) * M_TO_FT, 0),
        thickness_m = rc.thickness or 0,
    }
    if preset then
        clouds.coverage = preset.coverage
        clouds.precip   = (preset.precip or -1) > 0 and "rain" or "none"
        clouds.precip_power = preset.precip
    else
        -- Legacy fields: density 0-10, iprecptns 0 none / 1 rain / 2 thunderstorm / 3 snow / 4 snowstorm.
        local d = rc.density or 0
        clouds.coverage = d == 0 and "SKC" or d <= 2 and "FEW" or d <= 4 and "SCT" or d <= 7 and "BKN" or "OVC"
        local P = { [0] = "none", "rain", "thunderstorm", "snow", "snowstorm" }
        clouds.precip = P[rc.iprecptns or 0] or "none"
    end
    -- A ceiling exists when the lowest layer is broken or overcast.
    clouds.ceiling_ft = (clouds.coverage:find("BKN") or clouds.coverage:find("OVC")) and clouds.base_ft or nil
    w.clouds = clouds

    -- Visibility: ME distance, capped by fog and by the rain preset's stated range.
    local visM = (raw.visibility and raw.visibility.distance) or 80000
    local fog = {
        enabled      = raw.enable_fog == true,
        visibility_m = raw.fog and raw.fog.visibility or 0,
        thickness_m  = raw.fog and raw.fog.thickness or 0,
    }
    if fog.enabled and fog.visibility_m > 0 and fog.visibility_m < visM then visM = fog.visibility_m end
    if clouds.metar then
        local lo, hi = clouds.metar:match("VIS (%d+)%-(%d+)KM")
        if lo then
            clouds.precip_vis_km = { tonumber(lo), tonumber(hi) }
            local mid = (tonumber(lo) + tonumber(hi)) / 2 * 1000
            if mid < visM then visM = mid end
        end
    end
    w.fog = fog
    w.visibility_m  = round(visM, 0)
    w.visibility_sm = round(visM / SM_TO_M, 1)
    w.flight_rules  = Weather.flightRules(clouds.ceiling_ft, visM)

    w.wind = {
        ground = windLevel(raw.wind and raw.wind.atGround),
        at2000 = windLevel(raw.wind and raw.wind.at2000),
        at8000 = windLevel(raw.wind and raw.wind.at8000),
    }
    if measured and measured.wind then
        w.wind.measured_ground = {
            to_deg   = measured.wind.to_deg,
            from_deg = (measured.wind.to_deg + 180) % 360,
            mps      = round(measured.wind.mps, 1),
            kts      = round(measured.wind.mps * MPS_TO_KTS, 0),
        }
    end

    w.temp_c = raw.season and raw.season.temperature or nil
    w.qnh = {
        mmhg = raw.qnh,
        hpa  = raw.qnh and round(raw.qnh * MMHG_TO_HPA, 0) or nil,
        inhg = raw.qnh and round(raw.qnh * MMHG_TO_INHG, 2) or nil,
    }
    if measured then
        w.measured_temp_c       = measured.temp_c and round(measured.temp_c, 1) or nil
        w.measured_pressure_hpa = measured.pressure_hpa and round(measured.pressure_hpa, 0) or nil
    end
    w.turbulence = raw.groundTurbulence or 0
    w.dust = { enabled = raw.enable_dust == true, density = raw.dust_density or 0 }
    w.name = raw.name

    return w
end

-- date {Year, Month, Day}, startTime (local secs since midnight), absTime (now, local secs),
-- ref { lat, lon, label } — where the sun is evaluated (the airbase centroid for now).
function Weather.deriveTime(date, startTime, absTime, ref)
    local off = CONFIG.UTC_OFFSET_H or 0
    local t = {
        date         = { Year = date.Year, Month = date.Month, Day = date.Day },
        date_str     = string.format("%04d-%02d-%02d", date.Year, date.Month, date.Day),
        day_of_year  = Weather.dayOfYear(date),
        season       = seasonOf(date.Month),
        utc_offset_h = off,
        start_local  = startTime,
        start_hhmm   = Weather.hhmm(startTime),
        start_utc_hhmm = Weather.hhmm(startTime - off * 3600),
        abs_time     = absTime,
    }
    local elev = Weather.sunElevation(ref.lat, ref.lon, date, startTime - off * 3600)
    local times = Weather.sunTimes(ref.lat, ref.lon, date, off)
    t.sun = {
        ref        = { lat = round(ref.lat, 3), lon = round(ref.lon, 3), label = ref.label },
        elev_deg   = round(elev, 1),
        condition  = Weather.lightCondition(elev),
        sunrise    = times.sunrise,
        sunset     = times.sunset,
        civil_dawn = times.civil_dawn,
        civil_dusk = times.civil_dusk,
        polar      = times.polar,
        max_elev   = times.max_elev,
        min_elev   = times.min_elev,
    }
    return t
end

-- ── Debug display ───────────────────────────────────────────────

function Weather.summaryText(world)
    local w, t = world.weather, world.time
    local function wl(label, v)
        return string.format("  %-7s from %03d° (%03d° to)  %2.0f kt", label, v.from_deg, v.to_deg, v.kts)
    end
    local lines = { "=== WEATHER (as read) ===" }
    lines[#lines + 1] = string.format("%s  %s local (%s Z, UTC%+d)  %s  day %d",
        t.date_str, t.start_hhmm, t.start_utc_hhmm, t.utc_offset_h, t.season, t.day_of_year)
    local s = t.sun
    lines[#lines + 1] = string.format("SUN @ %s (%.2f, %.2f): elev %+.1f° — %s%s",
        s.ref.label, s.ref.lat, s.ref.lon, s.elev_deg, s.condition:upper(),
        s.polar and ("  [" .. s.polar:upper() .. "]") or "")
    lines[#lines + 1] = string.format("  civil dawn %s  sunrise %s  sunset %s  civil dusk %s  (max %+.1f°, min %+.1f°)",
        s.civil_dawn or "--", s.sunrise or "--", s.sunset or "--", s.civil_dusk or "--", s.max_elev, s.min_elev)
    local c = w.clouds
    lines[#lines + 1] = string.format("CLOUDS: %s (%s)  %s  base %.0f m / %.0f ft  ceiling %s  precip %s",
        c.name, tostring(c.preset), c.coverage, c.base_m, c.base_ft,
        c.ceiling_ft and string.format("%.0f ft", c.ceiling_ft) or "none", c.precip)
    if c.metar then lines[#lines + 1] = "  METAR: " .. c.metar end
    lines[#lines + 1] = string.format("VIS: %.0f m (%.1f sm)  fog %s%s  →  %s",
        w.visibility_m, w.visibility_sm, w.fog.enabled and "ON" or "off",
        w.fog.enabled and string.format(" (vis %.0f m, thk %.0f m)", w.fog.visibility_m, w.fog.thickness_m) or "",
        w.flight_rules)
    lines[#lines + 1] = "WIND (.miz dir assumed = blows TO; ME shows FROM):"
    lines[#lines + 1] = wl("ground", w.wind.ground)
    lines[#lines + 1] = wl("2000 m", w.wind.at2000)
    lines[#lines + 1] = wl("8000 m", w.wind.at8000)
    if w.wind.measured_ground then
        lines[#lines + 1] = wl("API gnd", w.wind.measured_ground) .. "   ← atmosphere.getWind(); should match 'ground'"
    end
    lines[#lines + 1] = string.format("TEMP %s°C (API %s°C)   QNH %s mmHg = %s hPa / %s inHg (API station %s hPa)   turb %s   dust %s",
        tostring(w.temp_c), tostring(w.measured_temp_c), tostring(w.qnh.mmhg), tostring(w.qnh.hpa),
        tostring(w.qnh.inhg), tostring(w.measured_pressure_hpa), tostring(w.turbulence),
        w.dust.enabled and w.dust.density or "off")
    return table.concat(lines, "\n")
end
