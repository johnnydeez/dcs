# DCS Airbase Ownership API — Research Notes

## The Key Correction: `setAirbassOwner()` Does Not Exist

The community-referenced function `trigger.action.setAirbassOwner()` **does not exist** in the DCS scripting API. It appears nowhere in the Hoggit Wiki, ED official documentation, or any scripting library. It is a myth that circulated in some community guides.

The correct function is:

```lua
Airbase:setCoalition(coalitionEnum)
-- Added in DCS 2.8.8 (2023)
-- coalition.side.BLUE = 2, RED = 1, NEUTRAL = 0

local ab = Airbase.getByName("Batumi")
ab:autoCapture(false)           -- REQUIRED — see below
ab:setCoalition(coalition.side.BLUE)
```

---

## The Airbase API

### Getting Airbase Objects

```lua
-- All airbases/FARPs/ships on the map, regardless of coalition:
local allBases = world.getAirbases()

-- Only bases owned by a specific coalition:
local blueBases = coalition.getAirbases(coalition.side.BLUE)

-- By name:
local ab = Airbase.getByName("Incirlik")
```

Both `world.getAirbases()` and `coalition.getAirbases()` return a table of Airbase objects. The returned objects include all three airbase categories.

### Category Enum

```lua
Airbase.Category.AIRDROME = 0   -- fixed-wing airfields
Airbase.Category.HELIPAD  = 1   -- FARPs, helipads
Airbase.Category.SHIP     = 2   -- carrier/ship
```

**Important:** Use `airbase:getDesc().category` (not `airbase:getCategory()`) to get this value. `getCategory()` (inherited from Object) returns `Object.Category.BASE` for all airbases, not the airbase-specific subtype.

### Key Instance Methods

| Method | Added | Notes |
|---|---|---|
| `getName()` | 1.2.4 | String name matching ME |
| `getCoalition()` | 1.2.4 | Returns 0/1/2 |
| `getPosition()` | 1.2.4 | Vec3 world position |
| `getDesc()` | 1.2.4 | Contains `.category` field |
| `getParking(available)` | 2.5.2 | Parking spots; pass `true` for free spots only. WIP. |
| `getRunways()` | 2.7.0 | Returns table with position, width, length, course |
| `setCoalition(coa)` | **2.8.8** | Flip coalition ownership |
| `autoCapture(bool)` | **2.8.8** | Enable/disable auto-revert by ground presence |
| `autoCaptureIsOn()` | **2.8.8** | Query auto-capture state |
| `getWarehouse()` | **2.8.8** | Warehouse inventory access |
| `isExist()` | — | Safety check |

---

## Critical Usage Notes

### 1. Always Disable autoCapture First

If `autoCapture` is enabled (the DCS default), the game's built-in ground-force presence mechanic can immediately revert the base back after you flip it. Always pair the calls:

```lua
local ab = Airbase.getByName("Bassel_Al_Assad")
if ab and ab:isExist() then
    ab:autoCapture(false)
    ab:setCoalition(coalition.side.RED)
end
```

### 2. Added in DCS 2.8.8 Only

`setCoalition()` and `autoCapture()` did not exist before DCS 2.8.8. If you need to support older installs, old workarounds (spawning ground units and waiting for auto-capture) are the only option.

### 3. Ships Are Broken

The wiki explicitly notes: "Can be called on ships, however they will still behave as if the unit belonged to their initial coalition." Data model updates but in-game behavior does not. Not a concern for ground-based missions.

---

## Effects on Players

| Effect | Certainty | Notes |
|---|---|---|
| Map F10 icon updates to new coalition color | Medium-High | Community confirmed, not officially documented |
| Players can rearm/refuel at flipped base | Medium | Expected by game design; MP bugs exist separately |
| Player spawn slots update automatically | Low | Spawn slots are baked into the mission at load time |
| Dynamic FARPs register slots immediately | Low | Known bug (March 2025): slots can lock as "occupied" after a blocked spawn attempt |

### Spawn Slots — The Important Caveat

Player spawn slots are fixed at mission load time based on the mission file. `setCoalition()` at runtime does NOT automatically give players new spawn points at a newly-flipped base. For a mission where both players are always Blue (flying air-to-ground against Red), this is not a problem — no slot management needed.

---

## Workarounds (if needed)

### SimpleSlotBlock (ciribob)
Hooks `onPlayerChangeSlot` via the Hooks environment. Blocks or allows slot selection based on DCS mission flags. You tie flags to your scripted ownership state. Works without `setCoalition()` at all — enforces ownership purely by kicking players who try to spawn at the wrong base.
- GitHub: https://github.com/ciribob/DCS-SimpleSlotBlock
- Variant `cfxSSBClient` designed specifically for capturable airfields/FARPs

### Zone-Based Tracking Only
Skip `setCoalition()` and track ownership purely in your own Lua table. Spawn ground defenders to represent control. The map icons won't update automatically but the gameplay can still function. Useful as a fallback if `setCoalition()` causes unexpected issues.

### Spawning Ground Units + Auto-Capture
Pre-2.8.8 pattern: spawn ground units of the owning coalition at a base and let DCS's auto-capture do the rest. Slow and unreliable but requires no `setCoalition()` call.

---

## Airbase vs FARP in Scripting

| Property | Airdrome | FARP (Invisible FARP static) | Ship |
|---|---|---|---|
| `Airbase.Category` | AIRDROME (0) | HELIPAD (1) | SHIP (2) |
| Exists at mission start | Yes (map-fixed) | Only if placed in editor or spawned | Only if placed |
| `setCoalition()` works | Yes | Yes | Partial (data only) |
| `autoCapture()` applies | Yes | Yes | N/A |
| Visible in `world.getAirbases()` | Yes | Yes, if spawned | Yes |
| Coalition set by | `setCoalition()` | `countryId` in `coalition.addStaticObject()` | Initial unit country |

FARPs in scripting are static objects of type "Invisible FARP." Created with `coalition.addStaticObject(countryId, data)` — the `countryId` determines initial coalition. Once placed, they appear in `world.getAirbases()` as `Airbase.Category.HELIPAD` and support `setCoalition()`.

---

## Recommended Pattern for Mission-Start Ownership Assignment

```lua
local function setBaseOwnership(baseName, coalitionSide)
    local ab = Airbase.getByName(baseName)
    if ab and ab:isExist() then
        ab:autoCapture(false)
        ab:setCoalition(coalitionSide)
    end
end

-- Example: flip a list of bases to Red at mission start
local redBases = { "Bassel_Al_Assad", "Hama", "Aleppo", "Tiyas" }
for _, name in ipairs(redBases) do
    setBaseOwnership(name, coalition.side.RED)
end
```

---

## Certainty Summary

| Claim | Certainty |
|---|---|
| `trigger.action.setAirbassOwner()` does not exist | High |
| `Airbase:setCoalition(coa)` is the correct function | High |
| Added in DCS 2.8.8 | High |
| `autoCapture(false)` required to prevent revert | High |
| Ships ignore `setCoalition()` for behavior | High |
| Map icon updates for players | Medium |
| Spawn slots update automatically | Low — they do not |
| Dynamic FARP slot lock bug exists | Medium (reported March 2025) |

---

## Sources

- [DCS Class Airbase — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_Class_Airbase)
- [DCS func setCoalition — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_setCoalition)
- [DCS func autoCaptureIsOn — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_autoCaptureIsOn)
- [DCS func getAirbases — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_getAirbases)
- [DCS func getRunways — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_getRunways)
- [DCS func getParking — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_func_getParking)
- [DCS event base_captured — Hoggit Wiki](https://wiki.hoggitworld.com/view/DCS_event_base_captured)
- [DCS 2.8.8 Changelog — Eagle Dynamics](https://www.digitalcombatsimulator.com/en/news/changelog/openbeta/2.8.8.43489/)
- [Airbase API — ED Official FAQ](https://www.digitalcombatsimulator.com/en/support/faq/1263/)
- [GitHub — ciribob/DCS-SimpleSlotBlock](https://github.com/ciribob/DCS-SimpleSlotBlock)
- [Functional.ZoneCaptureCoalition — MOOSE Docs](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Functional.ZoneCaptureCoalition.html)
- [asherao/DCS-Scripting-Library coalition.lua](https://github.com/asherao/DCS-Scripting-Library/blob/main/coalition.lua)
