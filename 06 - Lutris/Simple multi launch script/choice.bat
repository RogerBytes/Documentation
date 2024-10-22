@echo off
:menu
cls
echo.
echo     ---------------------
echo     Medieval II Total War
echo     ---------------------
echo.
echo ========================================
echo         Choisissez une campagne
echo ========================================
echo.
echo 1. Medieval II Total War
echo 2. Medieval II Total War - Americas
echo 3. Medieval II Total War - Britannia
echo 4. Medieval II Total War - Crusades
echo 5. Medieval II Total War - Teutonic
echo 6. Stainless Steel
echo 7. Europa Barbarorum 2
echo 8. Third Age
echo 9. Call of Warhammer
echo 0. Quitter
echo ========================================
echo.
set /p choice=Entrez votre choix (1-9) : 

rem Vérification des choix valides
if "%choice%"=="1" (
    start "" "Medieval II Total War.lnk"
    exit
)
if "%choice%"=="2" (
    start "" "Medieval II Total War - Americas.lnk"
    exit
)
if "%choice%"=="3" (
    start "" "Medieval II Total War - Britannia.lnk"
    exit
)
if "%choice%"=="4" (
    start "" "Medieval II Total War - Crusades.lnk"
    exit
)
if "%choice%"=="5" (
    start "" "Medieval II Total War - Teutonic.lnk"
    exit
)
if "%choice%"=="6" (
    start "" "Stainless Steel.bat"
    exit
)
if "%choice%"=="7" (
    start "" "Europa Barbarorum 2.bat"
    exit
)
if "%choice%"=="8" (
    start "" "Third Age.bat"
    exit
)
if "%choice%"=="9" (
    start "" "Call of Warhammer.bat"
    exit
)
if "%choice%"=="0" goto :exit

rem Si l'utilisateur n'entre pas une option valide, on le renvoie au menu
echo Choix invalide. Veuillez entrer un chiffre entre 1 et 9.
pause
goto :menu

:exit
exit
