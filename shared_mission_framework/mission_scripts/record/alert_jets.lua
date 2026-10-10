-- The record of each coalition's alert jets: the posture from the plan and, per alert
-- base, jets on alert, jets turning around, the next launch allowed. One writer: the
-- controller's ledger, controller\air_flights\assign_alert_jets.lua. Read by the airfield
-- info (inform\screen\airfield_info.lua).

RecordAlertJets = {}

local _ledger = {}   -- coalition → { posture, bases = { [base] = { ready, returning, ready_s } }, … }

-- The controller's ledger of a coalition, kept up to date in place, never replaced.
function RecordAlertJets.writeLedger(c, ledger)
    _ledger[c] = ledger
end

-- The coalition's alert posture from the plan (bases, max_airborne_aircraft,
-- first_number), or nil when it has no alert bases.
function RecordAlertJets.posture(c)
    return _ledger[c] and _ledger[c].posture
end

-- Alert base `base` at mission time `now`: jets ready, jets still turning around, and
-- seconds until the first of those is back on alert (nil when none is). nil when it isn't
-- an alert base. Read only: a jet whose turnaround is over counts as ready here; the
-- ledger itself moves it when the controller next looks.
function RecordAlertJets.ready(c, base, now)
    local s = _ledger[c] and _ledger[c].bases[base]
    if not s then return nil end
    local ready, returning, soonest = s.ready, 0, nil
    for _, t in ipairs(s.returning) do
        if t <= now then
            ready = ready + 1
        else
            returning = returning + 1
            soonest = math.min(soonest or t, t)
        end
    end
    return ready, returning, soonest and soonest - now
end
