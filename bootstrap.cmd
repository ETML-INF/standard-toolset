@ECHO off
setlocal enabledelayedexpansion
SET "installScript=.\install.ps1"
SET "tempScript=%TEMP%\install_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.ps1"
SET "url=https://github.com/ETML-INF/standard-toolset/raw/main/install.ps1"
IF NOT EXIST "%installScript%" (
    echo No local %installScript% found, downloading from %url% to %tempScript%
    powershell.exe -Command Invoke-WebRequest -Uri "%url%" -OutFile "%tempScript%"
    SET "installScript=%tempScript%"
) ELSE (
    echo Using local %installScript% script (from repo probably^)
)
powershell.exe -Command "& {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; & '!installScript!'}"
