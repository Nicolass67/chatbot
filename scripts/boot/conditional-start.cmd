@echo off
setlocal
cd /d "%~dp0..\.."
node "%~dp0conditional-start.mjs" >> "%~dp0..\..\data\boot-conditional.log" 2>&1
