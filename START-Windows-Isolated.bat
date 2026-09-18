@echo off
:: Runs TherAssist with its own private gcloud profile so the SUNY sign-in,
:: active project and ADC file do not overwrite (or get overwritten by)
:: other Google Cloud projects on this machine.
set "CLOUDSDK_CONFIG=%USERPROFILE%\.gcloud-therassist"
if not exist "%CLOUDSDK_CONFIG%" mkdir "%CLOUDSDK_CONFIG%"

:: Launch from a short drive letter. This folder's real path is long enough
:: that google-cloud-discoveryengine exceeds the Windows 260-char path limit,
:: which breaks both pip install and import for therapy-analysis.
if not exist "T:\START-Windows.bat" subst T: "%~dp0."
if not exist "T:\START-Windows.bat" (
    echo  Could not map drive T: to this folder. Is T: already used by something else?
    pause
    exit /b 1
)
set "THERASSIST_REAL_DIR=%~dp0"
call "T:\START-Windows.bat"
