@echo off
:menu
cls
echo.
echo     ----------
echo     Elden Ring
echo     ----------
echo.
echo ========================================
echo         Choisissez une campagne
echo ========================================
echo.
echo 1. Elden Ring
echo 2. Guide
echo 3. Extras
echo 4. Extras Erdtree
echo 0. Quitter
echo ========================================
echo.
echo Entrez votre choix (1-9) :
set /p choice=

rem Définir le préfixe Wine
set WINEPREFIX=/chemin/vers/votre/prefixe

rem Vérification des choix valides
if "%choice%"=="1" (
  cd "C:\Games\ELDEN RING Shadow of the Erdtree\Game\"
  "eldenring.exe"
  exit
)
if "%choice%"=="2" (
  cd "C:\Games\ELDEN RING Shadow of the Erdtree\AdvGuide\"
  "ELDEN RING Adventure Guide.exe"
  exit
)
if "%choice%"=="3" (
  cd "C:\Games\ELDEN RING Shadow of the Erdtree\ArtbookOST\"
  "ELDEN RING Digital Artbook & Soundtrack.exe"
  exit
)
if "%choice%"=="4" (
  cd "C:\Games\ELDEN RING Shadow of the Erdtree\ERD_ArtbookOST\"
  "ELDEN RING Shadow of the Erdtree Digital Artbook & Original Soundtrack.exe"
  exit
)
if "%choice%"=="0" goto :exit

rem Si l'utilisateur n'entre pas une option valide, on le renvoie au menu
echo Choix invalide. Veuillez entrer un chiffre entre 1 et 4.
pause
goto :menu

:exit
exit
