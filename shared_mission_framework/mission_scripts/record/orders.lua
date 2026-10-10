-- The record of the orders Execute carried out for the controller, each as it is given
-- (rule 3: the decision first, record\air_flight_decisions.lua; then the order; then this):
-- { order ("home", "land", "remove", "stand_down", "defend", "resume"), flight, coalition,
--   carried_out (true / false), why (when it failed), decision (the decision it carries
--   out, or nil), and what DCS gave back (a fight: { group, since, flag }) }.
-- One writer: Execute (execute\air_flight_orders.lua). A stream: nothing is kept; the
-- result is also returned to the controller, which updates its own state from it.
--
-- Subscribers: the event log (a line for an order that failed) and Darkstar (an order is
-- said only once it was given, never one that failed).

RecordOrders = {}

local SUBJECT = "orders"

-- Writes the result `r` (Execute only) and returns it.
function RecordOrders.write(r)
    Record.publish(SUBJECT, r, function(e) return string.format("%s %s order", tostring(e.flight), tostring(e.order)) end)
    return r
end

-- fn(result) on every order's result from now on.
function RecordOrders.on(fn)
    Record.subscribe(SUBJECT, fn)
end
