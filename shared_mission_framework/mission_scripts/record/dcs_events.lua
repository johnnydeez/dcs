-- The record of DCS's events, each read once into a plain fact (rule 13). One writer:
-- watch\dcs_events.lua, which holds the mission's only world.addEventHandler. A stream:
-- nothing kept.
--
-- A fact:
--   id           the DCS event id (world.event.S_EVENT_…)
--   time         mission time of the event
--   initiator    the object that did it, target the object it was done to, weapon the
--                weapon (each nil when DCS gave none), as plain fields:
--                  { name, type, kind ("unit" / "weapon" / "static" / "scenery" /
--                    "airbase" / "other"), key (the same object in another event),
--                    coalition (coalition.side), category (Object.Category),
--                    desc_category (its getDesc().category), unit_category (the same, for
--                    units: Unit.Category airplane, helicopter …), group, group_id, player
--                    (player name), point { x, y, z }, nose_deg (a unit's grid heading
--                    of its nose) }; a weapon also weapon_category,
--                    guidance, missile_category, target (what it was fired at, the same
--                    fields) and launcher (who fired it, the same fields)
--   weapon_name  DCS's own weapon name, when it gives one
--   place        { name } of the airbase a takeoff, landing or birth names
--   hit          a hit's number: a second later a follow-up fact { id = "hit_life", hit,
--                life ("destroyed", "life now 92 %", or nil) } says what the target has left
--   raw          the DCS event itself: for Watch's own files only (rule 1: only Watch
--                reads DCS), which may follow an object on from here
--
-- Subscribers are called in the order they subscribed (the order the old per-file
-- handlers were added: the event log, weapon impacts, flights, shots, sleeping ground
-- units, comms menus, the brief, flight calls, airfield traffic, Darkstar's orders).

RecordDcsEvents = {}

local SUBJECT = "dcs_events"

function RecordDcsEvents.publish(fact)
    Record.publish(SUBJECT, fact, function(e) return "DCS event " .. tostring(e.id) end)
end

-- fn(fact) on every DCS event from now on.
function RecordDcsEvents.on(fn)
    Record.subscribe(SUBJECT, fn)
end
