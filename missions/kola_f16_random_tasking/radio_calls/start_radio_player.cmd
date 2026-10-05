@echo off
rem Starts the radio player in this window (Ctrl+C or close the window to stop).
rem Later the mission starts it by itself; for now it's started by hand to tune the sound.
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"
"%PYTHON%" "%~dp0radio_player.py" %*
