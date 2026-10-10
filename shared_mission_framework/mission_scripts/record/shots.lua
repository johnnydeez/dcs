-- The record of shots at and by the flights the controller watches: per flight, the last
-- missile fired at it (when, by which airplane group, which weapon) and its own air-to-air
-- missiles still flying. One writer: watch\shots.lua.
--
-- Events (published as subject "shots"):
--   anti_radiation_fired  { flight }  a watched flight fired an anti-radiation missile
--                                     (the controller's go-cold check runs at once)
--   shot_at               { flight }  a missile was fired at a watched flight (its
--                                     coalition's fast check runs at once)

RecordShots = {}

local SUBJECT = "shots"

local _shots = {}   -- flight id → { shot_at = { time, shooter_group, weapon }, own_missiles = { weapon, … } }

-- The watcher's table, kept up to date in place, never replaced.
function RecordShots.writeTable(shots)
    _shots = shots
end

function RecordShots.publish(event)
    Record.publish(SUBJECT, event, function(e) return string.format("%s %s", tostring(e.flight), e.event) end)
end

function RecordShots.on(eventName, fn)
    Record.subscribe(SUBJECT, function(e)
        if e.event == eventName then fn(e) end
    end)
end

-- The last report of a missile fired at flight `id`: { time, shooter_group (an airplane's
-- group, or nil), weapon }, or nil.
function RecordShots.shotAt(id)
    local s = _shots[id]
    return s and s.shot_at
end
