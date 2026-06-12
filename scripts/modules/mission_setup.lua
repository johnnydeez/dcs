-- Mission Setup: orchestrates all mission types for the session.
-- Mark ID ranges: S&D = 3000–3099, CAS = 3100–3199.

MissionSetup = {}

function MissionSetup.generate(assignments)
    SdMission.generate(assignments)
    -- CasMission.generate(assignments)  -- not yet implemented
end
