-- Radio callsigns for AI flights, from data/flight_callsigns.lua (roadmap.md item 7,
-- design 6). A flight's callsign is set once, on its plan entry (m.callsign = "Weasel",
-- m.callsign_number = 3), when it is planned or, for a scramble or a SEAD retry, when it
-- is decided at run time; it never changes after that.
-- The numbers given out so far live in a table per coalition, `numbers` (name → last
-- number), handed to `assign`: the planner keeps it in the plan
-- (air_tasking_orders[coalition].callsign_numbers), and at run time the controller passes
-- the Record's (record\callsigns.lua), which carries on from the plan's.

FlightCallsigns = {}

-- The list of names a flight of this kind takes, in order.
local function namesFor(coalition, missionType, aircraftType)
    local C = FLIGHT_CALLSIGNS
    local byMission = C.by_mission_type[coalition]
    return (byMission and byMission[missionType]) or C.by_aircraft_type[aircraftType] or C.default[coalition]
end

-- The next free callsign for `m` in `numbers`, written onto `m`; `preferName`: keep this
-- name if it has a number left (a retry). Returns "Weasel 3".
function FlightCallsigns.assign(numbers, m, preferName)
    if m.flown_by == "human" then return nil end
    local names = namesFor(m.coalition, m.mission_type, m.aircraft_type)
    local order = {}
    if preferName then order[1] = preferName end
    for _, n in ipairs(names) do order[#order + 1] = n end
    for _, name in ipairs(order) do
        local last = numbers[name] or 0
        if last < FLIGHT_CALLSIGNS.max_number then
            numbers[name] = last + 1
            m.callsign, m.callsign_number = name, last + 1
            return FlightCallsigns.text(m)
        end
    end
    -- every name used up: start the first name over (a long mission; the earliest flights
    -- with those numbers are long down by then)
    local name = preferName or names[1]
    numbers[name] = 1
    m.callsign, m.callsign_number = name, 1
    return FlightCallsigns.text(m)
end

-- "Weasel 3", or nil for a flight with no callsign (a player's).
function FlightCallsigns.text(m)
    return m and m.callsign and string.format("%s %d", m.callsign, m.callsign_number) or nil
end

-- Jet `index` of the flight: "Weasel 3-2".
function FlightCallsigns.jet(m, index)
    return m and m.callsign and string.format("%s %d-%d", m.callsign, m.callsign_number, index) or nil
end

-- "MSN2023_SEAD Weasel 3": the id with its callsign, for lists and logs.
function FlightCallsigns.label(m)
    local text = FlightCallsigns.text(m)
    return text and (m.id .. " " .. text) or m.id
end
