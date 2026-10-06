@echo off
rem Zone workflow after the terrain survey (mission_scripts/survey/survey_zone_terrain.lua
rem calls this at the end of its flight; it can also be run by hand):
rem   1. map_data_tools/miz_zones.py on the mission's zone drawing mission -> its data/zones.lua
rem   2. copy the mission's scripts folder to Saved Games\DCS\Scripts\<scripts folder>
rem Usage: update_zone_data.cmd "<mission folder>" "<Saved Games\DCS folder>" <scripts folder> <log file>
rem   e.g. "C:\Users\johnk\Git\dcs\missions\kola_f16_random_tasking" "C:\Users\johnk\Saved Games\DCS" kola_f16 kola_zone_update.log
rem Everything is logged to <Saved Games\DCS folder>\<log file>.
rem (A batch file because DCS's Lua runs nothing from os.execute past ~260 characters.)

setlocal
set "MISSION=%~1"
set "WRITEDIR=%~2"
set "SCRIPTS=%~3"
set "LOG=%WRITEDIR%\%~4"
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"

echo %DATE% %TIME%  zones for "%MISSION%" > "%LOG%"
"%PYTHON%" "%~dp0miz_zones.py" "%MISSION%" --saved-games "%WRITEDIR%" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo miz_zones.py FAILED >> "%LOG%"
    exit /b 1
)
xcopy "%MISSION%\%SCRIPTS%" "%WRITEDIR%\Scripts\%SCRIPTS%" /E /I /Y /Q >> "%LOG%" 2>&1
if errorlevel 1 (
    echo copy to Scripts FAILED >> "%LOG%"
    exit /b 2
)
echo done >> "%LOG%"
exit /b 0
