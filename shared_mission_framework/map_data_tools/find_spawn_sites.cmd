@echo off
rem Spawn sites after the spawn site survey (map_surveys/survey_spawn_sites.lua calls this at
rem the end of its run; it can also be run by hand):
rem   find_spawn_sites.cmd "<log file>"
rem       test areas: find_spawn_sites.py on every surveyed area of the map -> spawn_sites_<area>.lua
rem       beside them, e.g. "%USERPROFILE%\Saved Games\DCS\map_surveys\Afghanistan\find_spawn_sites.log"
rem   find_spawn_sites.cmd map-survey <map folder> <run>
rem       whole map: find_spawn_sites.py map-survey on the run in
rem       ..\map_data\<map folder>\survey_measurements\<run>\ -> ..\map_data\<map folder>\spawn_sites_index.lua
rem       (the index) and ..\map_data\<map folder>\spawn_sites\tile_*.lua (the sites by tile); its log, find_spawn_sites.log, in the run's folder (the survey reads it as it goes)
rem (A batch file because DCS's Lua runs nothing from os.execute past ~260 characters.)

setlocal
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"

if /i "%~1"=="map-survey" (
    set "LOG=%~dp0..\map_data\%~2\survey_measurements\%~3\find_spawn_sites.log"
    set "ARGUMENTS=map-survey --map-folder %~2 --run %~3"
) else (
    set "LOG=%~1"
    set "ARGUMENTS="
)

>"%LOG%" echo %DATE% %TIME%  spawn sites
"%PYTHON%" -u "%~dp0find_spawn_sites.py" %ARGUMENTS% >> "%LOG%" 2>&1
if errorlevel 1 (
    >>"%LOG%" echo find_spawn_sites.py FAILED
    exit /b 1
)
>>"%LOG%" echo done
exit /b 0
