@echo off
setlocal

set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH_EXE=%LocalAppData%\Programs\Git\bin\bash.exe"

if not defined BASH_EXE (
  where bash.exe >nul 2>&1
  if not errorlevel 1 set "BASH_EXE=bash.exe"
)

if not defined BASH_EXE (
  echo BPS SH icin Git Bash gerekli.
  echo https://git-scm.com/download/win adresinden Git for Windows kurun.
  exit /b 1
)

"%BASH_EXE%" "%~dp0bps.sh" %*
exit /b %errorlevel%
