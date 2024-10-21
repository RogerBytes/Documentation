@echo off
:menu
cls
echo ========================================
echo           Choisissez un jeu
echo ========================================
echo 1. Kingdom Hearts HD Deam Drop Distance
echo 2. Kingdom Hearts 0.2 Birth by Sleep
echo 3. Kingdom Hearts x Back Cover
echo 4. Quitter
echo ========================================
set /p choice="Entrez votre choix (1-4) : "

if "%choice%"=="1" start "" "Kingdom Hearts - DDD.lnk"
if "%choice%"=="2" start "" "Kingdom Hearts - 0.2 Birth by Sleep.lnk"
if "%choice%"=="3" start "" "Kingdom Hearts HD 2.8 FCP.lnk"
if "%choice%"=="4" goto :exit

goto menu

:exit
exit
