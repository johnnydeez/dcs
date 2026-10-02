-- Consumer part of the controller (control_air_flights.lua): decisions that weigh several
-- flights of a coalition at once, after each flight's directives have had their say.
--
-- Threat assignment: a threat (an enemy group) is taken by one flight only, so two
-- flights don't both leave their missions for one MiG. A group a flight is already
-- fighting stays its own. Flights that want to defend are served nearest threat first:
-- each takes its nearest threat nobody has; a flight left with none stays on its
-- mission (DCS still has it evade anything fired at it).
--
-- Later: re-tasking a flight whose target is gone, patrol handover, holding packages.

CoordinateFlights = {}

-- claims: { { w = watch entry, intent = { kind = "defend", threats = { … } } } } for one
-- coalition; watched: every watch entry of that coalition. Sets intent.threat on each
-- claim that gets a threat; a claim that gets none has its intent cleared (intent = nil)
-- and claim.left = { group, to } (its nearest threat, and the flight that has it).
function CoordinateFlights.assignThreats(claims, watched)
    local taken = {}
    for _, w in ipairs(watched) do
        if w.defending then taken[w.defending.group] = w.mission.id end
    end
    table.sort(claims, function(a, b)
        local ra, rb = a.intent.threats[1].range_m, b.intent.threats[1].range_m
        if ra ~= rb then return ra < rb end
        return a.w.mission.id < b.w.mission.id
    end)
    for _, claim in ipairs(claims) do
        for _, t in ipairs(claim.intent.threats) do
            if not taken[t.group] then
                taken[t.group] = claim.w.mission.id
                claim.intent.threat = t
                break
            end
        end
        if not claim.intent.threat then
            local nearest = claim.intent.threats[1].group
            claim.left = { group = nearest, to = taken[nearest] }
            claim.intent = nil
        end
    end
end
