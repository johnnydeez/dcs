-- Mission radio calls: the jet's radios, for the radio player (radio_player.py).
--
-- Runs inside DCS's export system, loaded by one line in Saved Games\DCS\Scripts\Export.lua
-- (radio_player.py adds that line when it starts; README.md, "Mission radio calls"). About
-- twice a second it reads the player's radios (frequency, on / off, volume knob) and sends
-- them as one JSON line over UDP to 127.0.0.1:47112, where the radio player listens: a
-- call is then played only when a radio is tuned to its frequency, at that radio's volume.
-- It reads the cockpit only (as SRS does, DCS-SRS-Modules\F16C.lua and FA18C.lua), never
-- writes to it, and never stops DCS's other export scripts (SRS's): it calls them as before.
--
-- Aircraft it knows (DCS device numbers and cockpit volume knobs):
--   F-16C: UHF AN/ARC-164 device 36, volume knob 430; VHF AN/ARC-222 device 38, knob 431.
--   F/A-18C: COMM1 AN/ARC-210 device 38, volume knob 108; COMM2 AN/ARC-210 device 39,
--            knob 123 (each radio tunes VHF and UHF both; roadmap.md item 19).
-- Any other type (or no aircraft) is reported with no radios: the radio player then plays
-- every call, as before.

package.path  = package.path .. ";.\\LuaSocket\\?.lua"
package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll"

local okSocket, socket = pcall(require, "socket")
if not okSocket then
    log.write("COCKPIT-RADIOS", log.ERROR, "LuaSocket not found: the jet's radios won't reach the radio player")
    return
end

local PORT = 47112
local SEND_EVERY_S = 0.5

local RADIOS_BY_TYPE = {
    F16 = {
        { name = "UHF", device = 36, volume_knob = 430 },
        { name = "VHF", device = 38, volume_knob = 431 },
    },
    FA18 = {
        { name = "COMM1", device = 38, volume_knob = 108 },
        { name = "COMM2", device = 39, volume_knob = 123 },
    },
}
local TYPE_RADIOS = {
    ["F-16C_50"] = "F16", ["F-16D_50"] = "F16", ["F-16D_52"] = "F16", ["F-16D_50_NS"] = "F16",
    ["F-16D_52_NS"] = "F16", ["F-16I"] = "F16",
    ["FA-18C_hornet"] = "FA18",
}

local udp = socket.udp()
local nextSend = 0
-- said once each in dcs.log (COCKPIT-RADIOS), so a run shows whether the radios were read:
-- the first reading with radios, the first failure to read one (2026-10-06: the volume
-- knobs did nothing in the 00:16 run, and nothing showed whether a reading ever went out)
local firstReadingSaid, readFailureSaid = false, false

local function readRadio(r)
    local device = GetDevice(r.device)
    if not device then return nil end
    local on = device:is_on() == true
    local hz = tonumber(device:get_frequency()) or 0
    local volume = 1.0
    local cockpit = GetDevice(0)
    if cockpit and type(cockpit) ~= "number" then
        volume = tonumber(cockpit:get_argument_value(r.volume_knob)) or 1.0
    end
    -- rounded to 5 kHz, as the numbers aren't exact
    local mhz = math.floor(hz / 5000 + 0.5) * 5000 / 1e6
    return string.format('{"name":"%s","mhz":%.3f,"on":%s,"volume":%.2f}', r.name, mhz, tostring(on), volume)
end

local function report()
    local self = LoGetSelfData()
    if not self then return '{"type":null,"radios":[]}' end
    local typeName = self.Name or "?"
    local radios = {}
    local which = RADIOS_BY_TYPE[TYPE_RADIOS[typeName] or ""]
    -- a dead or ejected pilot's cockpit is gone: GetDevice(0) is no longer a device
    local cockpit = GetDevice(0)
    if which and cockpit and type(cockpit) ~= "number" then
        for _, r in ipairs(which) do
            local ok, text = pcall(readRadio, r)
            if ok and text then
                radios[#radios + 1] = text
            elseif not readFailureSaid then
                readFailureSaid = true
                log.write("COCKPIT-RADIOS", log.WARNING, string.format("%s radio of the %s not read: %s", r.name, typeName,
                    ok and "no such device" or tostring(text)))
            end
        end
    end
    local line = string.format('{"type":"%s","radios":[%s]}', typeName, table.concat(radios, ","))
    if #radios > 0 and not firstReadingSaid then
        firstReadingSaid = true
        log.write("COCKPIT-RADIOS", log.INFO, "first reading of the jet's radios: " .. line)
    end
    return line
end

local previousActivityNextEvent = LuaExportActivityNextEvent

LuaExportActivityNextEvent = function(t)
    local tNext = t + SEND_EVERY_S
    if t >= nextSend then
        nextSend = t + SEND_EVERY_S
        local ok, text = pcall(report)
        if ok then
            local sent, err = pcall(function() return udp:sendto(text, "127.0.0.1", PORT) end)
            if not sent and not readFailureSaid then
                readFailureSaid = true
                log.write("COCKPIT-RADIOS", log.WARNING, "the jet's radios not sent: " .. tostring(err))
            end
        elseif not readFailureSaid then
            readFailureSaid = true
            log.write("COCKPIT-RADIOS", log.WARNING, "the jet's radios not read: " .. tostring(text))
        end
    end
    if previousActivityNextEvent then
        local ok, theirs = pcall(previousActivityNextEvent, t)
        if ok and theirs and theirs > t and theirs < tNext then tNext = theirs end
    end
    return tNext
end

log.write("COCKPIT-RADIOS", log.INFO, "mission radio calls: sending the jet's radios to 127.0.0.1:" .. PORT)
