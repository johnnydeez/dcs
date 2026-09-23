-- Airfields whose infield, aprons and parking edges are forest in DCS (overgrown or
-- disused fields). Trees are invisible to every API, so this is read off the F10 map.
-- Base defenses there use only the cleared overrun beside each runway end's approach
-- lane (anchor kind runway_end), then airfield roads. Plain data, no logic.
--
-- Added after a DCS run showed the default anchors putting units in the trees.

FORESTED_AIRFIELDS = {
    ["Afrikanda"] = true,   -- disused; trees between the runway and every taxiway (2026-09-23)
}
