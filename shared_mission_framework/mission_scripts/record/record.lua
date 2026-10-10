-- The Record's mechanism: one way for every change to reach whoever needs it
-- (framework_design.md, *Roles and actors*, *The Record's mechanism*).
--
--   Record.subscribe(subject, fn)   fn(event) for every event published on `subject`
--   Record.publish(subject, event)  calls each subscriber of `subject`, in the order they
--                                   subscribed, each under pcall: a failing subscriber is
--                                   logged and the others still run
--
-- A subject is the name of its record\<subject>.lua file ("radar_picture", "flights" …).
-- Each of those files holds its entries, the functions to read them and the write
-- functions of its one writer, and publishes its changes here. Subscribers usually go
-- through the subject's own helper (RecordRadarPicture.on …), which picks the events they
-- want; a subject that is only a stream (DCS events, waypoints reached) keeps nothing.

Record = {}

local _subscribers = {}   -- subject → { fn, … } in the order they subscribed

function Record.subscribe(subject, fn)
    local list = _subscribers[subject]
    if not list then
        list = {}
        _subscribers[subject] = list
    end
    list[#list + 1] = fn
end

-- `describe(event)` (optional) names the event in the warning when a subscriber fails.
function Record.publish(subject, event, describe)
    for _, fn in ipairs(_subscribers[subject] or {}) do
        local ok, err = pcall(fn, event)
        if not ok then
            Log.warn(string.format("%s: a subscriber failed: %s",
                describe and describe(event) or ("record " .. subject), tostring(err)))
        end
    end
end
