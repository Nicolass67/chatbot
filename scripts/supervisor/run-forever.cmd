@echo off
setlocal EnableExtensions
REM Relance le supervisor tant que la session Windows est ouverte.
REM Exit 0 = autre instance saine (singleton) : on s'arrete proprement.
REM Tout autre exit code : pause courte puis relance.

cd /d "%~dp0..\.."
set "NODE_BIN=node"
where node >nul 2>&1 || set "NODE_BIN=node.exe"

:loop
"%NODE_BIN%" "%~dp0index.mjs" %*
set "EC=%ERRORLEVEL%"
if "%EC%"=="0" (
  echo [%DATE% %TIME%] supervisor exited 0 ^(singleton / clean^) — stop forever loop.
  exit /b 0
)
echo [%DATE% %TIME%] supervisor exited %EC% — restart in 5s...
timeout /t 5 /nobreak >nul
goto loop
