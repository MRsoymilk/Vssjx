@echo off
set "GODOT=E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
if exist "%GODOT%" (
    if not exist "%~dp0.godot\imported" start "" /wait "%GODOT%" --headless --path "%~dp0." --editor --import --quit
    start "" "%GODOT%" --path "%~dp0."
) else (
    echo Godot 4.7 was not found. Open project.godot with your Godot editor.
    pause
)
