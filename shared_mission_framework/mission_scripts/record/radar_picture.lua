-- The record of each coalition's radar picture: the enemy aircraft its radars report, and
-- the sensors asked this round. One writer: watch\radar_picture.lua.
--
-- Events (published as subject "radar_picture"), per coalition, once per round:
--   new_contact, airspace_changed (extra = the airspace before), contact_stale,
--   contact_dropped, then picture_updated (no contact) once the round is complete.
-- A contact = { group, category, first_seen, last_seen, seen_by, state ("tracked" /
--   "stale"), pos, pos_seen_at, altitude_m, heading_deg, speed_mps, type_known, type,
--   range_known, airspace, nearest_base, nearest_base_km, inside_own_sam_ring, inbound,
--   threat_asset, threat_minutes } (watch\radar_picture.lua says how each is worked out).
-- Contacts are returned as they are kept: read them, never change them.

RecordRadarPicture = {}

local SUBJECT = "radar_picture"
local EVENTS = { new_contact = true, airspace_changed = true, contact_stale = true, contact_dropped = true,
                 picture_updated = true }

local _contacts = { red = {}, blue = {} }   -- coalition → group name → contact
local _sensors  = { red = {}, blue = {} }   -- coalition → this round's sensors { id, kind, ground }

-- ── Writes (watch\radar_picture.lua only) ───────────────────────

-- The coalition's contacts table; the watcher keeps it up to date in place.
function RecordRadarPicture.writeContacts(coalitionName, contacts)
    _contacts[coalitionName] = contacts
end

-- This round's sensors.
function RecordRadarPicture.writeSensors(coalitionName, sensors)
    _sensors[coalitionName] = sensors
end

function RecordRadarPicture.publish(coalitionName, event, contact, extra)
    Record.publish(SUBJECT, { coalition = coalitionName, event = event, contact = contact, extra = extra },
        function(e) return string.format("%s picture %s", e.coalition:upper(), e.event) end)
end

-- ── Reads ───────────────────────────────────────────────────────

-- fn(contact, extra) on `event` in `coalition`'s picture (the events above): scrambles and
-- the controller's checks run on picture_updated.
function RecordRadarPicture.on(coalitionName, event, fn)
    if not EVENTS[event] then error("RecordRadarPicture.on: unknown event " .. tostring(event)) end
    Record.subscribe(SUBJECT, function(e)
        if e.coalition == coalitionName and e.event == event then fn(e.contact, e.extra) end
    end)
end

-- The coalition's contacts matching every field in `filter` (e.g. { airspace = "own" }),
-- sorted by group name.
function RecordRadarPicture.contacts(coalitionName, filter)
    local list = {}
    for _, c in pairs(_contacts[coalitionName]) do
        local match = true
        for k, v in pairs(filter or {}) do
            if c[k] ~= v then match = false break end
        end
        if match then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.group < b.group end)
    return list
end

-- The coalition's contacts within radius_m of pos, nearest first.
function RecordRadarPicture.contactsNear(coalitionName, pos, radius_m)
    local list = {}
    for _, c in pairs(_contacts[coalitionName]) do
        if Util.dist(pos, c.pos) <= radius_m then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return Util.dist(pos, a.pos) < Util.dist(pos, b.pos) end)
    return list
end

function RecordRadarPicture.contact(coalitionName, groupName)
    return _contacts[coalitionName][groupName]
end

-- The coalition's sensors this round: { id, kind }.
function RecordRadarPicture.sensors(coalitionName)
    local list = {}
    for _, s in ipairs(_sensors[coalitionName]) do list[#list + 1] = { id = s.id, kind = s.kind } end
    return list
end
