-- Offline test harness: which lines of a mission's scripts a run executes, per file, so the
-- parts no harness run reaches are known (shared_mission_framework framework_design.md, *How the
-- transfer is tested*: whatever never runs here is covered only by John's flight).
--
--   MeasureCoverage.start(folders)         before the mission loads: count every line run in
--                                          a file under one of `folders` ({ { name, folder } }:
--                                          the scripts folders; a debug line hook: slower)
--   MeasureCoverage.report(folders) → lines after the run: "  63 %   412 of   655  controller\x.lua",
--                                          every .lua file under `folders`, the total first
--                                          (several folders: each path starts with its name)
--
-- Lua 5.1 can't list a file's executable lines, so the code lines are an estimate: not blank,
-- not only a comment, not only `end` / `else` / a closing bracket, not a function's first
-- line. A statement over several lines counts all of them but fires on one, so files with
-- long tables or calls read a little low.

MeasureCoverage = {}

local linesRun = {}   -- [lower-case path] = { [line] = true }

local function normalised(path) return (path:gsub("/", "\\")):lower() end

function MeasureCoverage.start(folders)
    local prefixes = {}
    for _, f in ipairs(folders) do prefixes[#prefixes + 1] = normalised(f.folder) end
    local function inside(path)
        for _, prefix in ipairs(prefixes) do
            if path:sub(1, #prefix) == prefix then return true end
        end
        return false
    end
    debug.sethook(function(_, line)
        local source = debug.getinfo(2, "S").source
        if source:sub(1, 1) ~= "@" then return end
        local path = normalised(source:sub(2))
        if not inside(path) then return end
        local lines = linesRun[path]
        if not lines then lines = {} linesRun[path] = lines end
        lines[line] = true
    end, "l")
end

local function codeLines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    local n, inLongComment = 0, false
    for text in f:lines() do
        n = n + 1
        local t = text:gsub("^%s+", ""):gsub("%s+$", "")
        if inLongComment then
            if t:find("]]", 1, true) then inLongComment = false end
        elseif t:find("^%-%-%[%[") then
            inLongComment = not t:find("]]", 1, true)
        elseif t ~= "" and not t:find("^%-%-") and not t:find("^end[%s,;%)]*$") and t ~= "else"
                and not t:find("^[%}%)%]]+[,;]?$") and not t:find("^function") and not t:find("^local function") then
            lines[n] = true
        end
    end
    f:close()
    return lines
end

function MeasureCoverage.report(folders)
    debug.sethook()
    local report, allRun, allCode = {}, 0, 0
    for _, f in ipairs(folders) do
        local files = {}
        local listing = io.popen('dir /s /b "' .. f.folder .. '*.lua" 2>nul')
        for path in listing:lines() do files[#files + 1] = path end
        listing:close()
        table.sort(files, function(a, b) return a:lower() < b:lower() end)
        local label = #folders == 1 and "" or f.name .. "\\"
        for _, path in ipairs(files) do
            local ran = linesRun[normalised(path)] or {}
            local nCode, nRun = 0, 0
            for line in pairs(codeLines(path)) do
                nCode = nCode + 1
                if ran[line] then nRun = nRun + 1 end
            end
            allRun, allCode = allRun + nRun, allCode + nCode
            report[#report + 1] = string.format("%4.0f %%  %5d of %5d  %s", nCode > 0 and 100 * nRun / nCode or 0,
                nRun, nCode, label .. path:sub(#f.folder + 1))
        end
    end
    table.insert(report, 1, string.format("%4.0f %%  %5d of %5d  every file (code lines run; an estimate)",
        allCode > 0 and 100 * allRun / allCode or 0, allRun, allCode))
    return report
end
