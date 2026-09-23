-- How heavily a base's owner defends it: level = BASE_DEFENSE_LEVEL[class][echelon].
-- class from data/airbase_classes.lua; echelon from stage 1 (front / mid / rear by
-- distance to the nearest enemy base, thresholds in CONFIG). Starting values; tune by feel.
-- Plain data, no logic.

BASE_DEFENSE_LEVEL = {
    --           front       mid         rear
    hub     = { front = "heavy",    mid = "heavy",    rear = "standard" },
    fighter = { front = "heavy",    mid = "standard", rear = "standard" },
    bomber  = { front = "heavy",    mid = "standard", rear = "light"    },
    strip   = { front = "standard", mid = "light",    rear = "light"    },
    heli    = { front = "standard", mid = "light",    rear = "light"    },
}

-- Crew skill per level (DCS skill strings).
BASE_DEFENSE_SKILL = {
    light    = "Average",
    standard = "Average",
    heavy    = "Good",
}
