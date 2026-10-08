-- The rings around each base, and when a base's new owner may spawn in each (John, 2026-10-08:
-- "sites closest to the base can be spawned in immediately after capture, sites 2 and 3 layers
-- out will have timers for base ownership before spawn", so taking a base doesn't put an SA-10
-- covering a huge piece of enemy ground there the same minute). Plain data, no logic; the
-- campaign's own setting, not the map's (mission_design.md, *Base domains and rings*).
--
-- A site's ring comes from its distance to its home base (map_data\afghanistan\site_domains\):
-- the first ring whose out_to_km reaches it; the last ring has none and runs to the domain's
-- edge. open_after_capture_min counts campaign time from when the base last changed hands; at
-- the campaign's start every base counts as long held, so every ring is open.
-- Numbers to tune once the domains have been seen on the map.

BASE_RINGS = {
    {
        ring = 1,
        out_to_km = 25,               -- base defences, short-range SAMs, the capture fight
        open_after_capture_min = 0,
    },
    {
        ring = 2,
        out_to_km = 75,               -- medium SAMs, depots, companies
        open_after_capture_min = 60,
    },
    {
        ring = 3,                     -- long-range SAMs, deep targets: to the domain's edge
        open_after_capture_min = 180,
    },
}
