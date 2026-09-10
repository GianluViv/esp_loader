@echo off
REM Compila il bundle Windows e tenta il packaging in un singolo exe portabile.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo Compilazione non riuscita. Codice errore: %ERRORLEVEL%.
    pause
    exit /b %ERRORLEVEL%
)
pause
