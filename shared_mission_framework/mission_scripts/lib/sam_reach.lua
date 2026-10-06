-- How far a SAM site really reaches an aircraft at a given height above the ground. The
-- plan's ring (engage_m) is ED's high-altitude figure; close to the ground a site reaches
-- much less (radar horizon, low-altitude envelope: SA-10 120 km high, 40 km low). Jets
-- took off unharmed from Vuojarvi, 60 km from a Blue SA-10, while the kill zone at 85 %
-- of the high figure (102 km) called it deadly (John's run, 2026-10-01).
-- The low figure holds only close to the ground (bug 27, 2026-10-02 00:57 run: at the
-- SEAD pop-up the SA-11 fired at 39 km at ~3,200 m (low figure 25), the Patriot at 50 km
-- at ~2,500 m (30), the SA-10 at 46 km at ~900 m (40); the model then held the low
-- figure up to 3,000 m). Heights are above the ground, because the low reach is the
-- radar horizon: a jet 275 m over the Khibiny is over 1,000 m above sea level.
--   SamReach.radius(site, height_m)  metres: the recipe's low_altitude_engage_km up to
--       AIR_DEFENSE.killzone_low_altitude_m above the ground, the full engage_m from
--       killzone_high_altitude_m, straight between; the full engage_m with no height
--       given, or for a system without a low figure
--   SamReach.killZone(site, height_m)  that radius × AIR_DEFENSE.killzone_fraction
--   SamReach.baseDefenses(plan, coalition)  the enemy base-defense radar SAMs (Tor,
--       Pantsir, …) with their full reach, at any height
--   SamReach.aboveGround(pos, altitude_m)  an altitude above sea level at pos ({ x, z })
--       → its height above the ground there (nil stays nil)

SamReach = {}

function SamReach.radius(site, height_m)
    local full = site.engage_m or 0
    local recipe = SAM_SITE_RECIPE[site.system]
    local low = recipe and recipe.low_altitude_engage_km and recipe.low_altitude_engage_km * 1000
    if not height_m or not low or low >= full then return full end
    local a, b = AIR_DEFENSE.killzone_low_altitude_m, AIR_DEFENSE.killzone_high_altitude_m
    if height_m <= a then return low end
    if height_m >= b then return full end
    return low + (full - low) * (height_m - a) / (b - a)
end

function SamReach.killZone(site, height_m)
    return SamReach.radius(site, height_m) * AIR_DEFENSE.killzone_fraction
end

-- The base-defense groups of the coalitions other than `coalition` that the routing
-- treats as threats (AIR_ROUTING.base_defense_roles: Tor M2, Pantsir, Tunguska, Roland),
-- each { id, pos, reach_m } with its longest-reaching unit's reach (UNIT_POOL threat_m,
-- as the planner's threat circles). No low figure: they are low-altitude weapons.
-- Worked out once per plan and coalition (bug 41, 2026-10-02: the controller's kill
-- zones knew only the SAM sites, and a fight took MSN2024_SEAD_1 into the Vuojarvi Tor).
local _baseDefenses = setmetatable({}, { __mode = "k" })
function SamReach.baseDefenses(plan, coalition)
    local byCoalition = _baseDefenses[plan]
    if not byCoalition then
        byCoalition = {}
        _baseDefenses[plan] = byCoalition
    end
    if byCoalition[coalition] then return byCoalition[coalition] end
    local list = {}
    for _, g in ipairs(plan.base_defenses and plan.base_defenses.groups or {}) do
        if g.side ~= coalition and AIR_ROUTING.base_defense_roles[g.role] then
            local reach = 0
            for _, u in ipairs(g.units or {}) do
                local pool = UNIT_POOL.ground[u.type]
                if pool and (pool.threat_m or 0) > reach then reach = pool.threat_m end
            end
            if reach > 0 then list[#list + 1] = { id = g.id, pos = { x = g.pos.x, z = g.pos.z }, reach_m = reach } end
        end
    end
    byCoalition[coalition] = list
    return list
end

function SamReach.aboveGround(pos, altitude_m)
    if not altitude_m then return nil end
    local ok, ground = pcall(land.getHeight, { x = pos.x, y = pos.z })
    return altitude_m - (ok and ground or 0)
end
