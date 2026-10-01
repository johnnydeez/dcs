-- How far a SAM site really reaches an aircraft at a given altitude. The plan's ring
-- (engage_m) is ED's high-altitude figure; close to the ground a site reaches much less
-- (radar horizon, low-altitude envelope: SA-10 120 km high, 40 km low). Jets took off
-- unharmed from Vuojarvi, 60 km from a Blue SA-10, while the kill zone at 85 % of the
-- high figure (102 km) called it deadly (John's run, 2026-10-01).
--   SamReach.radius(site, altitude_m)  metres: the recipe's low_altitude_engage_km up to
--       AIR_DEFENSE.killzone_low_altitude_m, the full engage_m from
--       killzone_high_altitude_m, straight between; the full engage_m with no altitude
--       given, or for a system without a low figure
--   SamReach.killZone(site, altitude_m)  that radius × AIR_DEFENSE.killzone_fraction

SamReach = {}

function SamReach.radius(site, altitude_m)
    local full = site.engage_m or 0
    local recipe = SAM_SITE_RECIPE[site.system]
    local low = recipe and recipe.low_altitude_engage_km and recipe.low_altitude_engage_km * 1000
    if not altitude_m or not low or low >= full then return full end
    local a, b = AIR_DEFENSE.killzone_low_altitude_m, AIR_DEFENSE.killzone_high_altitude_m
    if altitude_m <= a then return low end
    if altitude_m >= b then return full end
    return low + (full - low) * (altitude_m - a) / (b - a)
end

function SamReach.killZone(site, altitude_m)
    return SamReach.radius(site, altitude_m) * AIR_DEFENSE.killzone_fraction
end
