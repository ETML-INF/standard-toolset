@ECHO off
IF NOT EXIST ".\install.ps1" (
    powershell.exe -Command Invoke-WebRequest -Uri https://github.com/ETML-INF/standard-toolset/raw/main/install.ps1 -OutFile .\install.ps1
)
powershell.exe -Command "& {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; & '.\install.ps1'}"
