-- Offline test harness: the mission override rules (lib/mission_overrides.lua), case by case,
-- on made-up shared settings and override files (shared_mission_framework plan.md,
-- *Settings: shared defaults, mission overrides*).
--
--   luae.exe test_mission_overrides.lua <the mission_overrides.lua to test> <a scratch folder\>
--
-- Prints each case and PASS / FAIL; exit code 0 when every case passes.

local moduleFile, scratch = arg[1], arg[2]
if not (moduleFile and scratch) then
    print("usage: luae.exe test_mission_overrides.lua <mission_overrides.lua> <scratch folder\\>")
    os.exit(1)
end
os.execute('mkdir "' .. scratch .. '" 2>nul')

-- just enough of the mission's lib for the module: Util.serialize and Log
logged = {}
Log = { info = function(text) logged[#logged + 1] = text end }
Util = { serialize = function(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i, x in ipairs(v) do parts[i] = type(x) == "table" and "{...}" or tostring(x) end
    return "{ " .. table.concat(parts, ", ") .. " }"
end }
dofile(moduleFile)

local failures = 0
local function check(name, ok, detail)
    print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, ok and "" or ("  — " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

-- writes one override file, applies it to fresh shared settings, returns ok, err
local function apply(fileText)
    TUNING = { a = 1, nested = { c = 2, d = 3, deeper = { e = 4 } }, list = { "x", "y", "z" },
               roster = { { "Su-27", 2 }, { "Su-30", 1 } } }
    SPACING_KM = 3
    MISSION_NAME_SEEN = nil
    logged = {}
    local f = io.open(scratch .. "override.lua", "w")
    f:write(fileText)
    f:close()
    return MissionOverrides.apply(scratch, { "override.lua" })
end

local ok, err

ok, err = MissionOverrides.apply(scratch, {})
check("no override files: nothing applied", ok and #logged == 1 and logged[1]:find("none", 1, true), err)

ok, err = apply("TUNING = { nested = { c = 9 } }")
check("a keyed table merges: the one value changes", ok and TUNING.nested.c == 9, err)
check("  ... its neighbours keep their defaults", TUNING.nested.d == 3 and TUNING.nested.deeper.e == 4 and TUNING.a == 1)
check("  ... and the change is logged with default and override",
    logged[2] and logged[2]:find("TUNING.nested.c 2 → 9", 1, true), logged[2])

ok, err = apply("TUNING = { nested = { deeper = { e = 7 } } }")
check("merging goes as deep as the override", ok and TUNING.nested.deeper.e == 7 and TUNING.nested.c == 2, err)

ok, err = apply('TUNING = { list = { "q" } }')
check("a list is replaced whole", ok and #TUNING.list == 1 and TUNING.list[1] == "q", err)

ok, err = apply('TUNING = { roster = { { "MiG-31", 1 } } }')
check("a weighted roster (a list of lists) is replaced whole",
    ok and #TUNING.roster == 1 and TUNING.roster[1][1] == "MiG-31", err)

ok, err = apply("SPACING_KM = 4")
check("a plain value replaces the default", ok and SPACING_KM == 4, err)

ok, err = apply("TUNING = { nested = { cc = 9 } }")
check("a key the shared settings don't have stops the load", not ok and err:find("TUNING.nested.cc", 1, true), err)
check("  ... and changes nothing", TUNING.nested.c == 2)

ok, err = apply("TUNNING = { a = 2 }")
check("a global the shared settings don't have stops the load", not ok and err:find("TUNNING", 1, true), err)

ok, err = apply("TUNING = { a = TUNING.a + 1 }")
check("an override can read the shared settings", ok and TUNING.a == 2, err)

local ok2, err2 = MissionOverrides.apply(scratch, { "missing.lua" })
check("a listed override file that doesn't exist stops the load", not ok2 and err2:find("missing.lua", 1, true), err2)

print(failures == 0 and "every case passed" or (failures .. " case(s) failed"))
os.exit(failures == 0 and 0 or 1)
