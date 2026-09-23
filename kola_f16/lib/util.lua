-- Small pure helpers: RNG, geometry, table serialization, file IO.
-- No mission logic here.

Util = {}

-- ── RNG ─────────────────────────────────────────────────────────

-- No seeding: math.randomseed is unavailable in DCS mission Lua, and DCS already gives
-- math.random a different sequence each launch (verified: rolls differ between runs).
-- A time-based advance was tried and removed — the mission clock at gather time is the
-- same every launch, so it always advanced the same number of steps.

function Util.pick(tbl)
    return tbl[math.random(#tbl)]
end

-- Picks from { { value, weight }, ... }; returns the value.
function Util.weightedPick(list)
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return list[#list][1]
end

function Util.shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

-- ── Geometry (plan coordinates: x = north, z = east, metres) ────

function Util.dist(a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    return math.sqrt(dx * dx + dz * dz)
end

-- Compass bearing from a to b, degrees 0-359.
function Util.bearing(a, b)
    local deg = math.deg(math.atan2(b.z - a.z, b.x - a.x))
    if deg < 0 then deg = deg + 360 end
    return math.floor(deg + 0.5) % 360
end

-- Plan pos → DCS Vec3 {x=north, y=alt, z=east} for map marks and spawns.
function Util.toVec3(pos)
    return { x = pos.x, y = land.getHeight({ x = pos.x, y = pos.z }), z = pos.z }
end

-- Fills lat/lon on a plan pos in place and returns it.
function Util.withLatLon(pos)
    local lat, lon = coord.LOtoLL({ x = pos.x, y = 0, z = pos.z })
    pos.lat, pos.lon = lat, lon
    return pos
end

-- "N68°07'12"  E033°21'40""
function Util.formatLL(lat, lon)
    local function dms(deg)
        local a = math.abs(deg)
        local d = math.floor(a)
        local m = math.floor((a - d) * 60)
        local s = math.floor(((a - d) * 60 - m) * 60)
        return d, m, s
    end
    local d1, m1, s1 = dms(lat)
    local d2, m2, s2 = dms(lon)
    return string.format("%s%d°%02d'%02d\"  %s%03d°%02d'%02d\"",
        lat >= 0 and "N" or "S", d1, m1, s1, lon >= 0 and "E" or "W", d2, m2, s2)
end

-- ── Serialization ───────────────────────────────────────────────

local function isIdent(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

-- Serializes plain data (strings, numbers, booleans, nested tables) to a Lua literal.
-- Sequences print inline when they hold only scalars. `inline` forces one line.
function Util.serialize(v, indent, inline)
    indent = indent or ""
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        local s = string.format("%.6f", v)
        s = s:gsub("0+$", "")
        s = s:gsub("%.$", ".0")
        return s
    end
    if t ~= "table" then return tostring(v) end

    local keys = sortedKeys(v)
    if #keys == 0 then return "{}" end

    local isSeq = (#v == #keys)
    local allScalar = true
    for _, k in ipairs(keys) do
        if type(v[k]) == "table" then allScalar = false break end
    end

    local parts = {}
    if isSeq and (allScalar or inline) then
        for i = 1, #v do parts[i] = Util.serialize(v[i], indent, true) end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end
    if inline then
        for _, k in ipairs(keys) do
            local ks = isIdent(k) and k or ("[" .. Util.serialize(k) .. "]")
            parts[#parts + 1] = ks .. " = " .. Util.serialize(v[k], indent, true)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    local pad = indent .. "    "
    for _, k in ipairs(keys) do
        local ks = isSeq and "" or ((isIdent(k) and k or ("[" .. Util.serialize(k) .. "]")) .. " = ")
        parts[#parts + 1] = pad .. ks .. Util.serialize(v[k], pad)
    end
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
end

-- ── Files (requires de-sanitized io/lfs) ─────────────────────────

function Util.writeFile(relPath, text)
    local path = lfs.writedir() .. relPath
    local f, err = io.open(path, "w")
    if not f then
        Log.warn("Util.writeFile: cannot open " .. path .. ": " .. tostring(err))
        return false
    end
    f:write(text)
    f:close()
    return path
end
