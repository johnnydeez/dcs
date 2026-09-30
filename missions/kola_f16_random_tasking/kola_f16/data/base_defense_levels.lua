-- How heavily a base's owner defends it: level = BASE_DEFENSE_LEVEL[class][echelon].
-- class from data/airbase_classes.lua; echelon from stage 1 (front / mid / rear by
-- distance to the nearest enemy base, thresholds in CONFIG). Plain data, no logic.
--
-- What a base is matters more than how far it sits from the front: hubs and bomber bases
-- are strategic and defended heavily wherever they are (long-range strikes reach the
-- rear — Olenya and Severomorsk sit under S-400s and Pantsirs), fighter bases ease off
-- only deep in the rear, dispersal fields are never below standard, small fields
-- scale with the front. (2026-09-23)

BASE_DEFENSE_LEVEL = {
    --           front       mid         rear
    hub     = { front = "heavy",    mid = "heavy",    rear = "heavy"    },
    bomber  = { front = "heavy",    mid = "heavy",    rear = "heavy"    },
    fighter = { front = "heavy",    mid = "heavy",    rear = "standard" },
    dispersal = { front = "heavy",  mid = "standard", rear = "standard" },
    strip   = { front = "standard", mid = "light",    rear = "light"    },
    heli    = { front = "standard", mid = "light",    rear = "light"    },
}

-- Crew skill per level (DCS skill strings).
BASE_DEFENSE_SKILL = {
    light    = "Average",
    standard = "Average",
    heavy    = "Good",
}
