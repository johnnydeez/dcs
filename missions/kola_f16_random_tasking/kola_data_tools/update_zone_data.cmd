@echo off
rem Zone workflow after the terrain survey (kola_f16/survey/survey_zone_terrain.lua calls
rem this at the end of its flight; it can also be run by hand):
rem   1. kola_data_tools/miz_zones.py on the zone drawing mission -> kola_f16/data/zones.lua
rem   2. copy the mission folder's kola_f16 tree to Saved Games\DCS\Scripts\kola_f16
rem Usage: update_zone_data.cmd "<zones .miz>" "<Saved Games\DCS folder>"
rem Everything is logged to <Saved Games\DCS folder>\kola_zone_update.log.
rem (A batch file because DCS's Lua runs nothing from os.execute past ~260 characters.)

setlocal
set "MIZ=%~1"
set "WRITEDIR=%~2"
set "LOG=%WRITEDIR%\kola_zone_update.log"
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"

cd /d "%~dp0.."
echo %DATE% %TIME%  zones from "%MIZ%" > "%LOG%"
"%PYTHON%" kola_data_tools\miz_zones.py "%MIZ%" >> "%LOG%" 2>&1
if errorlevel 1 (
    echo miz_zones.py FAILED >> "%LOG%"
    exit /b 1
)
xcopy kola_f16 "%WRITEDIR%\Scripts\kola_f16" /E /I /Y /Q >> "%LOG%" 2>&1
if errorlevel 1 (
    echo copy to Scripts FAILED >> "%LOG%"
    exit /b 2
)
echo done >> "%LOG%"
exit /b 0
