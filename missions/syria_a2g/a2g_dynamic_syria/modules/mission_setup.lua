-- Mission Setup: orchestrates all mission types for the session.
-- Mark ID ranges: S&D = 3000–3099, CAS = 3100–3199.

MissionSetup = {}

function MissionSetup.generate(assignments, missionsMenu)
    SdMission.generate(assignments, missionsMenu)
    local casMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "CAS", missionsMenu)
    CasMission.generate(assignments, casMenu)
end
