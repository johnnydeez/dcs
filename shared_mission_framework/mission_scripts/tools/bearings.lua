-- Bearings and the magnetic variation, as the F-16 shows them (bug 61, 2026-10-05: DCS's
-- magnetic is grid-based: the F-16's HUD and the F10 ruler take the map's grid north as
-- true north, so a magnetic bearing is the grid bearing minus the variation at the point;
-- a bearing from true north was off by the grid's convergence, ~6° near Ivalo).
-- The variation is DCS's own magvar module (as the mission editor and the DTC use it), kept
-- loaded here once the air picture has checked it (rule 10: the magnetic model is a
-- question about the fixed world); an approximate table by longitude
-- (MISSION.fallback_magnetic_variation) when it can't be loaded or answers 0.
-- Answers from its arguments; used by the air picture, Darkstar and the airfield info.

Bearings = {}

local _magvar          -- DCS's magvar module, or nil
local _variationLogged = false

function Bearings.norm(deg) return (deg % 360 + 360) % 360 end

-- Smallest angle between two directions, 0–180.
function Bearings.angleBetween(a, b)
    local d = math.abs(Bearings.norm(a) - Bearings.norm(b))
    return d > 180 and 360 - d or d
end

function Bearings.latLon(pos)
    return coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
end

-- Grid bearing (map x north, z east), degrees.
function Bearings.gridBearing(a, b)
    return Bearings.norm(math.deg(math.atan2(b.z - a.z, b.x - a.x)))
end

-- DCS's answer at lat/lon, degrees east, or nil.
function Bearings.magvarAt(lat, lon)
    if not _magvar then return nil end
    local ok, rad = pcall(_magvar.get_mag_decl, lat, lon)
    local deg = ok and type(rad) == "number" and math.deg(rad)
    if deg and math.abs(deg) < 40 then return deg end
    return nil
end

-- The map's approximate variation at a longitude, degrees east.
function Bearings.fallbackAt(lon)
    local t = MISSION.fallback_magnetic_variation
    if lon <= t[1].lon then return t[1].deg end
    for i = 2, #t do
        if lon <= t[i].lon then
            local f = (lon - t[i - 1].lon) / (t[i].lon - t[i - 1].lon)
            return t[i - 1].deg + f * (t[i].deg - t[i - 1].deg)
        end
    end
    return t[#t].deg
end

-- Magnetic variation at lat/lon, degrees east. Subtract it from a grid direction, not a
-- true one.
function Bearings.variation(lat, lon)
    local deg = Bearings.magvarAt(lat, lon)
    if deg then return deg end
    if not _variationLogged then
        _variationLogged = true
        Log.warn("air picture: magvar unavailable, using the approximate variation by longitude (AIR_PICTURE_CALLS)")
    end
    return Bearings.fallbackAt(lon)
end

-- Loads DCS's magvar module for the mission's date; true when it loaded.
function Bearings.loadMagvar(plan)
    local ok, mod = pcall(require, "magvar")
    if not ok or type(mod) ~= "table" or type(mod.get_mag_decl) ~= "function" then
        Log.warn("air picture: DCS's magvar module could not be loaded (" .. tostring(mod) .. ")")
        _magvar = nil
        return false
    end
    local date = plan.world and plan.world.time and plan.world.time.date
    if date and type(mod.init) == "function" then pcall(mod.init, date.Month, date.Year) end
    _magvar = mod
    return true
end

-- The module failed its check: the approximate table from here on.
function Bearings.dropMagvar()
    _magvar = nil
end

-- What bearings from a point need: { pos { x, z }, lat, lon, variation, height_m (above
-- the ground) } for point { x, y (altitude), z }.
function Bearings.from(point)
    local pos = { x = point.x, z = point.z }
    local lat, lon = Bearings.latLon(pos)
    local okGround, ground = pcall(land.getHeight, { x = point.x, y = point.z })
    return { pos = pos, lat = lat, lon = lon, variation = Bearings.variation(lat, lon),
             height_m = point.y - (okGround and ground or 0) }
end
