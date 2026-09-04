@echo off
setlocal
cd /d "%~dp0..\.."
node "%~dp0poll-boot-request.mjs" >> "%~dp0..\..\data\boot-poll.log" 2>&1
