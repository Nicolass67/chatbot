@echo off
setlocal
cd /d "%~dp0..\.."
if exist "C:\Program Files\nodejs\node.exe" (
  "C:\Program Files\nodejs\node.exe" "%~dp0conditional-start.mjs" >> "%~dp0..\..\data\boot-conditional.log" 2>&1
) else (
  node "%~dp0conditional-start.mjs" >> "%~dp0..\..\data\boot-conditional.log" 2>&1
)
