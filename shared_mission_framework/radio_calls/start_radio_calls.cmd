@echo off
rem Started by the mission (mission_scripts/inform/radio/radio_calls.lua) at mission start:
rem the radio player and the radio helper, each in its own minimised window, both closing
rem themselves once DCS stops. Either already running: the second copy exits at once.
rem Can be run by hand too (both then still close with DCS).
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"
start "Radio player" /min "%PYTHON%" "%~dp0radio_player.py" --exit-with-dcs
start "Radio helper" /min "%PYTHON%" "%~dp0speak_mission_calls.py" --exit-with-dcs
