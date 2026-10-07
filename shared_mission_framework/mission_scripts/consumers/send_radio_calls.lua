-- Consumer: hands the mission's radio calls to the radio programs outside DCS, so they're
-- heard, not only read (roadmap.md item 7; data/radio_calls.lua). Every call carries its
-- channel and frequency (RADIO_CHANNELS), its priority and how long it may wait
-- (RADIO_CALLS.kinds). The AI pilots' calls and Darkstar's orders come in through
-- SendRadioCalls.say (announce_flight_activity.lua, track_airfield_traffic.lua,
-- announce_controller_orders.lua).
--
-- Darkstar's two kinds of call to a player, both from the facts CallAirPicture works out
-- for its on-screen list, each to one player's jet (not their group's first player):
--   picture  every time CallAirPicture shows a player the picture (every 2 min): the
--            groups in threat order, or clean, or no radar coverage;
--   threat   at once, on the radar picture's round (every 30 s), when the player's
--            highest-threat hot group with a known range is inside RADIO_CALLS.threat_nm;
--            the same group again for the same player only after threat_repeat_s.
-- Their frequency: the player's slot's own Darkstar frequency
-- (RADIO_CHANNELS.awacs_per_player_slot, the mission's data; roadmap.md item 19), else the
-- AWACS channel. Darkstar's calls to all (SendRadioCalls.say on the AWACS channel: its
-- orders, the pilots' check-ins and answers) then also carry every player's Darkstar
-- frequency (frequencies_mhz), so each player hears them on their own; one player's
-- picture and threat calls are on their frequency only. A mission with no per-slot list
-- (Kola) has every player on the AWACS channel, as before.
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
local _threatCalled = {}    -- player unit name → contact group → mission time it was called
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
        _airfieldMhz[base] = f and f.vhf or RADIO_CHANNELS.airfield.common_traffic_mhz
    end
    return _airfieldMhz[base]
end

-- The Darkstar frequency of a player's group, MHz: its slot's
-- (RADIO_CHANNELS.awacs_per_player_slot, by the slot's group name; a dynamically spawned
-- group whose name only starts with the slot's counts as that slot), else the AWACS channel.
function SendRadioCalls.awacsFrequencyFor(groupName)
    local slots = RADIO_CHANNELS.awacs_per_player_slot
    if slots and groupName then
        if slots[groupName] then return slots[groupName] end
        local best
        for slot in pairs(slots) do
            if groupName:sub(1, #slot) == slot and (not best or #slot > #best) then best = slot end
        end
        if best then return slots[best] end
    end
    return RADIO_CHANNELS.awacs.mhz
end

local _awacsFrequencies   -- every Darkstar frequency, sorted, once worked out

-- Every Darkstar frequency (the AWACS channel and each slot's own), sorted, or nil when the
-- mission lists no slots' own.
local function awacsFrequencies()
    local slots = RADIO_CHANNELS.awacs_per_player_slot
    if not slots or next(slots) == nil then return nil end
    if not _awacsFrequencies then
        local seen, list = { [RADIO_CHANNELS.awacs.mhz] = true }, { RADIO_CHANNELS.awacs.mhz }
        for _, mhz in pairs(slots) do
            if not seen[mhz] then seen[mhz] = true; list[#list + 1] = mhz end
        end
        table.sort(list)
        _awacsFrequencies = list
    end
    return _awacsFrequencies
end

-- "Darkstar UHF 262.000"-style text of a channel, for the brief.
function SendRadioCalls.channelText(channel, base)
    local c = RADIO_CHANNELS[channel]
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
                          or RADIO_CHANNELS[channel].mhz
    -- to all: on every player's Darkstar frequency (set only when there are slots' own: a
    -- nil assignment would still reorder the table, and so the call's line)
    local all = channel == "awacs" and awacsFrequencies()
    if all then facts.frequencies_mhz = all end
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

-- Darkstar's call to one player: on the AWACS channel, the frequency their slot's.
local function awacsCall(call)
    call.channel, call.frequency_mhz = "awacs", SendRadioCalls.awacsFrequencyFor(call.player_group)
    return call
end

-- One group's facts as the helper reads them (radio_calls/phrase_bank_wording.py).
local function groupFacts(g)
    return { type = g.type, bearing = g.bearing, range_nm = math.floor(g.range_nm * 10 + 0.5) / 10,
             range_known = g.range_known and true or false, altitude_ft = math.floor(g.altitude_ft + 0.5),
             aspect = g.aspect, track = g.track, age_s = g.age_s }
end

local DIGIT_WORDS = { ["0"] = "zero", ["1"] = "one", ["2"] = "two", ["3"] = "three", ["4"] = "four",
                      ["5"] = "five", ["6"] = "six", ["7"] = "seven", ["8"] = "eight", ["9"] = "nine" }

-- A player's callsign as spoken: their jet's callsign from the mission file ("Python11",
-- set on the slot in the mission editor) → "Python one one". RADIO_CALLS.player_callsign
-- when the jet has none that reads as a name and a number (John, 2026-10-07: each F-16
-- slot carries its own callsign).
function SendRadioCalls.playerCallsign(unit)
    local ok, raw = pcall(function() return unit:getCallsign() end)
    local name, digits = (ok and type(raw) == "string" and raw or ""):match("^(%a+)[%s%-]*([%d%s%-]+)$")
    if not name then return RADIO_CALLS.player_callsign end
    local words = {}
    for d in digits:gmatch("%d") do words[#words + 1] = DIGIT_WORDS[d] end
    return name:sub(1, 1):upper() .. name:sub(2) .. " " .. table.concat(words, " ")
end

-- CallAirPicture has shown a player the picture: say it too.
function SendRadioCalls.picture(sideName, unit, groups, inCoverage)
    if not _file or not RADIO_CALLS.coalitions[sideName] then return end
    local call = { to = SendRadioCalls.playerCallsign(unit), player_group = unit:getGroup():getName() }
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

-- The radar picture's round: a threat call to each player's jet with a hot group close in.
local function threatRound(sideName)
    local now = timer.getTime()
    local side = sideName == "blue" and 2 or 1
    local done = {}
    for _, unit in ipairs(coalition.getPlayers(side) or {}) do
        local ok, err = pcall(function()
            if not unit:isExist() then return end
            local group = unit:getGroup()
            local groupName = group and group:getName()
            local unitName = unit:getName()
            if not groupName or not unitName or done[unitName] then return end
            done[unitName] = true
            if not AIR_PICTURE_CALLS.on_the_ground and not unit:inAir() then return end
            local _, groups = CallAirPicture.pictureFor(sideName, unit)
            local called = _threatCalled[unitName] or {}
            _threatCalled[unitName] = called
            for _, g in ipairs(groups) do
                if g.aspect == "hot" and g.range_known and g.range_nm <= RADIO_CALLS.threat_nm then
                    local name = g.contact.group
                    if not called[name] or now - called[name] >= RADIO_CALLS.threat_repeat_s then
                        called[name] = now
                        write(awacsCall({ call = "threat", to = SendRadioCalls.playerCallsign(unit), player_group = groupName,
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
    local slots = 0
    for _ in pairs(RADIO_CHANNELS.awacs_per_player_slot or {}) do slots = slots + 1 end
    Log.info(string.format("--- Radio calls: to each player by their jet's callsign (else %s); picture every %d s, threat calls inside %d nm; AWACS %s%s, mission %s; %s ---",
        RADIO_CALLS.player_callsign, AIR_PICTURE_CALLS.call_every_s, RADIO_CALLS.threat_nm,
        SendRadioCalls.channelText("awacs"),
        slots > 0 and string.format(" (and %d player slots' own Darkstar frequencies)", slots) or "",
        SendRadioCalls.channelText("mission"), RADIO_CALLS.calls_file))
end
