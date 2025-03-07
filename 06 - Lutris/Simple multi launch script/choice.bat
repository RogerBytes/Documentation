@echo off
setlocal enabledelayedexpansion

:: Vérifier si le script a été relancé en mode minimisé
if "%1"=="_min" (
  set choice=%2
  goto :launch_game
)

:: Menu principal
:menu
cls
echo.
echo     -----------------
echo     Final Fantasy VII
echo     -----------------
echo.
echo ========================================
echo         Choisissez une option
echo ========================================
echo.
echo  1. Final Fantasy VII DX (remaster fan made)
echo  2. Final Fantasy VII Vanilla
echo  3. Final Fantasy VII Hardmode (Mexico) DX
echo  0. Quitter
echo ========================================
echo.
echo Entrez votre choix (1-3) :
set /p choice=

:: Vérifier si le choix est valide (0-3)
echo %choice% | findstr /r "^[0-3]\+$" >nul
if errorlevel 1 if %choice% LSS 0 if %choice% GTR 15 (
    echo Choix invalide. Veuillez entrer un nombre entre 0 et 3.
    pause
    goto :menu
)

:: Relancer le script en mode minimisé avec le choix sélectionné
start /min "" cmd /c "%~f0" _min %choice%
exit

:: Partie du script exécutée après minimisation
:launch_game

if "%choice%"=="1" (
  cd "C:\Games\Final Fantasy VII DX\7th Heaven\"
  "7th Heaven.exe" /MINI /PROFILE:"Final Fantasy VII DX" /LAUNCH /QUIT
)
if "%choice%"=="2" (
  cd "C:\Games\Final Fantasy VII DX\7th Heaven\"
  "7th Heaven.exe" /MINI /PROFILE:"Final Fantasy VII Vanilla" /LAUNCH /QUIT
)
if "%choice%"=="3" (
  cd "C:\Games\Final Fantasy VII DX\7th Heaven\"
  "7th Heaven.exe"
)

exit
