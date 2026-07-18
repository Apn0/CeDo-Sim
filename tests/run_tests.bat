@echo off
REM Headless smoke-test runner for CeDo Simulator.
REM Uses whichever godot.exe is on PATH; falls back to the bundled install.
REM
REM Two suites:
REM   1. BaleComplianceTest (--script mode) — runs on any 4.x install,
REM      verifies the bale collision shape + physics material + delivered gate.
REM   2. VehicleBaleTest (scene mode)       — needs Godot 4.6 to parse the
REM      vehicle .tscn files; covers grab/release lifecycle end-to-end.

setlocal
set GODOT=godot
where %GODOT% >nul 2>&1 || set GODOT="%LOCALAPPDATA%\Godot\godot.exe"
pushd "%~dp0\.."

echo === [1/10] BaleComplianceTest (script mode) ===
%GODOT% --headless --path . --script res://tests/BaleComplianceTest.gd
set RC1=%ERRORLEVEL%

echo.
echo === [2/10] BaleSheetsTest (script mode) ===
%GODOT% --headless --path . --script res://tests/BaleSheetsTest.gd
set RC2=%ERRORLEVEL%

echo.
echo === [3/10] WireFixAndCameraTest (script mode) ===
%GODOT% --headless --path . --script res://tests/WireFixAndCameraTest.gd
set RC3=%ERRORLEVEL%

echo.
echo === [4/10] OperatorLifecycleTest (script mode) ===
%GODOT% --headless --path . --script res://tests/OperatorLifecycleTest.gd
set RC4=%ERRORLEVEL%

echo.
echo === [5/10] VehicleDriveTest (script mode) ===
%GODOT% --headless --path . --script res://tests/VehicleDriveTest.gd
set RC5=%ERRORLEVEL%

echo.
echo === [6/10] SettingsParseTest (script mode) ===
%GODOT% --headless --path . --script res://tests/SettingsParseTest.gd
set RC6=%ERRORLEVEL%

echo.
echo === [7/10] ScanLogTest (script mode) ===
%GODOT% --headless --path . --script res://tests/ScanLogTest.gd
set RC7=%ERRORLEVEL%

echo.
echo === [8/10] VehicleBaleTest (scene mode — needs Godot 4.6) ===
%GODOT% --headless --path . res://tests/VehicleBaleTest.tscn
set RC8=%ERRORLEVEL%

echo.
echo === [9/10] SecuritySaveTest (script mode) ===
%GODOT% --headless --path . --script res://tests/SecuritySaveTest.gd
set RC9=%ERRORLEVEL%

echo.
echo === [10/10] PLCSequencerTest (script mode) ===
%GODOT% --headless --path . --script res://tests/PLCSequencerTest.gd
set RC10=%ERRORLEVEL%

popd
echo.
echo BaleComplianceTest     exit: %RC1%
echo BaleSheetsTest         exit: %RC2%
echo WireFixAndCameraTest   exit: %RC3%
echo OperatorLifecycleTest  exit: %RC4%
echo VehicleDriveTest       exit: %RC5%
echo SettingsParseTest      exit: %RC6%
echo ScanLogTest            exit: %RC7%
echo VehicleBaleTest        exit: %RC8%
echo SecuritySaveTest       exit: %RC9%
echo PLCSequencerTest       exit: %RC10%
if not "%RC1%"=="0" exit /b %RC1%
if not "%RC2%"=="0" exit /b %RC2%
if not "%RC3%"=="0" exit /b %RC3%
if not "%RC4%"=="0" exit /b %RC4%
if not "%RC5%"=="0" exit /b %RC5%
if not "%RC6%"=="0" exit /b %RC6%
if not "%RC7%"=="0" exit /b %RC7%
if not "%RC8%"=="0" exit /b %RC8%
if not "%RC9%"=="0" exit /b %RC9%
exit /b %RC10%
