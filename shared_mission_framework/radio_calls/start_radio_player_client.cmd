@echo off
rem Another player's PC in multiplayer (roadmap.md item 19): plays the host's radio calls,
rem the ones your own jet's radios are tuned to. Double-click it before flying; close the
rem window when done. The first time, it asks for the host's ZeroTier address and keeps it
rem in host_zerotier_address.txt beside this file (delete that file to type a new one).
set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"
set "ADDRESS_FILE=%~dp0host_zerotier_address.txt"
if not exist "%ADDRESS_FILE%" (
    set /p "HOST_ADDRESS=The host's ZeroTier address (for example 10.147.17.1): "
    call echo %%HOST_ADDRESS%%> "%ADDRESS_FILE%"
)
set /p HOST_ADDRESS=<"%ADDRESS_FILE%"
title Radio player client (the host's calls from %HOST_ADDRESS%)
"%PYTHON%" "%~dp0radio_player.py" --host %HOST_ADDRESS%
pause
