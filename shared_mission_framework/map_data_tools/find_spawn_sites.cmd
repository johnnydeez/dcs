@echo off
rem Spawn sites after the spawn site survey (map_surveys/survey_spawn_sites.lua calls this at
rem the end of its run, then shows the sites; it can also be run by hand):
rem   find_spawn_sites.py on every surveyed area of the map -> spawn_sites_<area>.lua beside them
rem Usage: find_spawn_sites.cmd "<log file>"
rem   e.g. "%USERPROFILE%\Saved Games\DCS\map_surveys\Afghanistan\find_spawn_sites.log"
rem (A batch file because DCS's Lua runs nothing from os.execute past ~260 characters.)

setlocal
set "LOG=%~1"
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"

echo %DATE% %TIME%  spawn sites > "%LOG%"
"%PYTHON%" "%~dp0find_spawn_sites.py" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo find_spawn_sites.py FAILED >> "%LOG%"
    exit /b 1
)
echo done >> "%LOG%"
exit /b 0
