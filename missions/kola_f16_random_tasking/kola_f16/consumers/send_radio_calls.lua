-- Consumer: hands the mission's radio calls to the radio programs outside DCS, so they're
-- heard, not only read (roadmap.md item 7; data/radio_calls.lua). Every call carries its
-- channel and frequency (RADIO_CALLS.channels), its priority and how long it may wait
-- (RADIO_CALLS.kinds). The AI pilots' calls and Darkstar's orders come in through
-- SendRadioCalls.say (announce_flight_activity.lua, track_airfield_traffic.lua,
-- announce_controller_orders.lua).
--
-- Darkstar's two kinds of call, on the AWACS channel, both from the facts CallAirPicture
-- works out for its on-screen list:
--   picture  every time CallAirPicture shows a player the picture (every 2 min): the
--            groups in threat order, or clean, or no radar coverage;
--   threat   at once, on the radar picture's round (every 30 s), when the player's
--            highest-threat hot group with a known range is inside RADIO_CALLS.threat_nm;
--            the same group again for the same player only after threat_repeat_s.
-- Each call is one JSON line in RADIO_CALLS.calls_file (emptied at mission start); the
-- helper (radio_calls/speak_mission_calls.py) words it, speaks it and passes it to the
-- radio player. Both are started here, once. Nothing here waits on them.
-- Event log: threat calls as PICTURE_CALL "threat: …" (picture calls are already logged
-- by CallAirPicture).
-- Every call gets an id (`id`); an answer names the call it answers (`answers`), so the
-- radio player drops an answer whose order it dropped. Every call made through
-- SendRadioCalls.say is published to listeners once written (SendRadioCalls.onCall), the
-- way the controller publishes its decisions: the watcher hears Darkstar's orders that
-- were really said, and answers them (announce_flight_activity.lua).

SendRadioCalls = {}

local _file                 -- the open calls file, or nil when off
local _threatCalled = {}    -- player group name → contact group → mission time it was called
local _nextId = 0           -- the last call id given
local _listeners = {}       -- fn(sideName, call) for every call written through SendRadioCalls.say

-- ── JSON, just enough for the call facts ───────────────────────

local function encode(v)
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(ch)
            if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" end
            return string.format("\\u%04x", ch:byte())
        end) .. '"'
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return v == math.floor(v) and string.format("%d", v) or string.format("%.3f", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        if #v > 0 then
            local parts = {}
            for _, x in ipairs(v) do parts[#parts + 1] = encode(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- ── calls ───────────────────────────────────────────────────────

local _airfieldMhz = {}   -- base name → its traffic frequency, MHz

-- An airfield's traffic frequency: its tower VHF from the map, else the common traffic one.
function SendRadioCalls.airfieldFrequency(base)
    if _airfieldMhz[base] == nil then
        local ok, id = pcall(function() return Airbase.getByName(base):getID() end)
        local f = ok and AIRFIELD_FREQUENCIES and AIRFIELD_FREQUENCIES[id]
        _airfieldMhz[base] = f and f.vhf or RADIO_CALLS.channels.airfield.common_traffic_mhz
    end
    return _airfieldMhz[base]
end

-- "Darkstar UHF 262.000"-style text of a channel, for the brief.
function SendRadioCalls.channelText(channel, base)
    local c = RADIO_CALLS.channels[channel]
    local mhz = channel == "airfield" and SendRadioCalls.airfieldFrequency(base) or c.mhz
    return string.format("%s %.3f", c.radio, mhz)
end

local function write(call)
    if not _file then return end
    _nextId = _nextId + 1
    call.id = _nextId
    call.mission_time_s = math.floor(timer.getTime())
    local kind = RADIO_CALLS.kinds[call.call]
    if kind then
        call.priority = call.priority or kind.priority
        call.expires_s = call.expires_s or kind.expires_s
    end
    local ok, err = pcall(function()
        _file:write(encode(call), "\n")
        _file:flush()
    end)
    if not ok then Log.warn("radio calls: couldn't write a call: " .. tostring(err)) end
end

-- A call from an AI pilot (announce_flight_activity.lua, track_airfield_traffic.lua):
-- `kind` (RADIO_CALLS.kinds), `channel` ("awacs", "mission", "airfield" with `base`), its
-- facts (callsign = the jet talking, flight, voice_key, and the call's own). Written only
-- for a coalition that talks (RADIO_CALLS.coalitions).
function SendRadioCalls.say(sideName, kind, channel, facts, base)
    if not _file or not RADIO_CALLS.coalitions[sideName] then return end
    facts.call, facts.channel = kind, channel
    facts.frequency_mhz = channel == "airfield" and SendRadioCalls.airfieldFrequency(base)
                          or RADIO_CALLS.channels[channel].mhz
    facts.awacs = RADIO_CALLS.awacs_callsign[sideName]
    write(facts)
    for _, fn in ipairs(_listeners) do
        local ok, err = pcall(fn, sideName, facts)
        if not ok then Log.warn(string.format("radio calls: a call listener failed on %s: %s", kind, tostring(err))) end
    end
    return facts.id
end

-- fn(sideName, call) for every call written through SendRadioCalls.say from now on: the
-- call's facts as written (id, call, channel, priority, expires_s and its own facts).
-- Read them, never change them.
function SendRadioCalls.onCall(fn)
    _listeners[#_listeners + 1] = fn
end

-- True when calls are being written for this coalition.
function SendRadioCalls.on(sideName)
    return _file ~= nil and RADIO_CALLS.coalitions[sideName] == true
end

-- Darkstar's calls are on the AWACS channel.
local function awacsCall(call)
    call.channel, call.frequency_mhz = "awacs", RADIO_CALLS.channels.awacs.mhz
    return call
end

-- One group's facts as the helper reads them (radio_calls/phrase_bank_wording.py).
local function groupFacts(g)
    return { type = g.type, bearing = g.bearing, range_nm = math.floor(g.range_nm * 10 + 0.5) / 10,
             range_known = g.range_known and true or false, altitude_ft = math.floor(g.altitude_ft + 0.5),
             aspect = g.aspect, track = g.track, age_s = g.age_s }
end

-- CallAirPicture has shown a player the picture: say it too.
function SendRadioCalls.picture(sideName, groupName, groups, inCoverage)
    if not _file or not RADIO_CALLS.coalitions[sideName] then return end
    local call = { to = RADIO_CALLS.player_callsign, player_group = groupName }
    if #groups == 0 then
        call.call = inCoverage and "picture_clean" or "no_coverage"
    else
        call.call = "picture"
        local facts = {}
        for i, g in ipairs(groups) do
            if i > 10 then break end
            facts[i] = groupFacts(g)
        end
        call.groups = facts
    end
    write(awacsCall(call))
end

-- The radar picture's round: a threat call to each player with a hot group close in.
local function threatRound(sideName)
    local now = timer.getTime()
    local side = sideName == "blue" and 2 or 1
    local done = {}
    for _, unit in ipairs(coalition.getPlayers(side) or {}) do
        local ok, err = pcall(function()
            if not unit:isExist() then return end
            local group = unit:getGroup()
            local groupName = group and group:getName()
            if not groupName or done[groupName] then return end
            done[groupName] = true
            if not AIR_PICTURE_CALLS.on_the_ground and not unit:inAir() then return end
            local _, groups = CallAirPicture.pictureFor(sideName, unit)
            local called = _threatCalled[groupName] or {}
            _threatCalled[groupName] = called
            for _, g in ipairs(groups) do
                if g.aspect == "hot" and g.range_known and g.range_nm <= RADIO_CALLS.threat_nm then
                    local name = g.contact.group
                    if not called[name] or now - called[name] >= RADIO_CALLS.threat_repeat_s then
                        called[name] = now
                        write(awacsCall({ call = "threat", to = RADIO_CALLS.player_callsign, player_group = groupName,
                                          groups = { groupFacts(g) } }))
                        WriteEventLog.add(sideName, "PICTURE_CALL", groupName, string.format(
                            "threat: %s, %03d/%dnm, %d ft, hot", g.type, g.bearing,
                            math.floor(g.range_nm + 0.5), math.floor(g.altitude_ft + 0.5)))
                    end
                    return   -- one threat call per player per round: the highest threat
                end
            end
        end)
        if not ok then Log.warn("radio calls: threat check failed: " .. tostring(err)) end
    end
end

function SendRadioCalls.start()
    if not RADIO_CALLS.enabled then
        Log.info("--- Radio calls: off (RADIO_CALLS.enabled) ---")
        return
    end
    local f, err = io.open(RADIO_CALLS.calls_file, "w")
    if not f then
        Log.warn("radio calls: off, can't write " .. RADIO_CALLS.calls_file .. ": " .. tostring(err))
        return
    end
    _file = f
    if os and os.execute then
        -- "start" returns at once; the .cmd starts the player and the helper minimised
        os.execute(string.format('start "" /min "%s"', RADIO_CALLS.start_command))
    else
        Log.warn("radio calls: os.execute is sanitized; start radio_calls\\start_radio_calls.cmd by hand")
    end
    for sideName in pairs(RADIO_CALLS.coalitions) do
        TrackRadarPicture.on(sideName, "picture_updated", function() threatRound(sideName) end)
    end
    Log.info(string.format("--- Radio calls: to %s; picture every %d s, threat calls inside %d nm; AWACS %s, mission %s; %s ---",
        RADIO_CALLS.player_callsign, AIR_PICTURE_CALLS.call_every_s, RADIO_CALLS.threat_nm,
        SendRadioCalls.channelText("awacs"), SendRadioCalls.channelText("mission"), RADIO_CALLS.calls_file))
end
