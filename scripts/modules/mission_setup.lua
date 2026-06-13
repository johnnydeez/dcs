-- Mission Setup: orchestrates all mission types for the session.
-- Mark ID ranges: S&D = 3000–3099, CAS = 3100–3199.

MissionSetup = {}

function MissionSetup.generate(assignments, missionsMenu)
    SdMission.generate(assignments, missionsMenu)
    -- CasMission.generate(assignments, missionsMenu)  -- not yet implemented
end
