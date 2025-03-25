@ECHO off
setlocal enabledelayedexpansion
SET "installScript=.\install.ps1"
for /F "usebackq tokens=1" %i in (`powershell ^(get-date -format yyyy_MM_dd_H_mm_ss^)`) do set timestamp=%i
SET "tempScript=%TEMP%\install_%timestamp%.ps1"
SET "url=https://github.com/ETML-INF/standard-toolset/raw/main/install.ps1"
IF NOT EXIST "%installScript%" (
    echo No local %installScript% found, downloading from %url% to %tempScript%
    powershell.exe -Command Invoke-WebRequest -Uri "%url%" -OutFile "%tempScript%"
    SET "installScript=%tempScript%"
) ELSE (
    echo Using local %installScript% script (from repo probably^)
)
powershell.exe -Command "& {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; & '!installScript!'}"
