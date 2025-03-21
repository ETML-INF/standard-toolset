@ECHO off
powershell.exe -Command "& {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force; & '.\install.ps1'}"
