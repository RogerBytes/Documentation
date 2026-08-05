#!/bin/bash

# S'assurer que le script est exécuté avec les privilèges root (sudo)
if [ "$EUID" -ne 0 ]; then
  echo "Erreur : Veuillez exécuter ce script d'installation avec les privilèges administrateur (sudo ./install.sh)."
  exit 1
fi

# Définition des chemins de destination sur le système
INSTALL_BIN_DIR="/usr/local/bin"
INSTALL_LIB_DIR="/usr/local/lib/zgp-manager"
APP_DESKTOP_DIR="/usr/share/applications"
MIME_DIR="/usr/share/mime/packages"

echo "=== Installation de Zgp-Manager ==="

# 1. Création des dossiers de destination
mkdir -p "$INSTALL_LIB_DIR"
mkdir -p "$APP_DESKTOP_DIR"
mkdir -p "$MIME_DIR"

# 2. Copie des scripts de la bibliothèque (lib/)
if [ -d "lib" ]; then
  cp -r lib/* "$INSTALL_LIB_DIR/"
  chmod +x "$INSTALL_LIB_DIR"/*.sh
  echo "[OK] Bibliothèques copiées dans $INSTALL_LIB_DIR"
else
  echo "Erreur : Le dossier 'lib' est introuvable."
  exit 1
fi

# 3. Copie et liaison du binaire principal (bin/zgp-manager)
if [ -f "bin/zgp-manager" ]; then
  cp bin/zgp-manager "$INSTALL_BIN_DIR/zgp-manager"
  chmod +x "$INSTALL_BIN_DIR/zgp-manager"
  echo "[OK] Binaire du manager installé dans $INSTALL_BIN_DIR/zgp-manager"
else
  echo "Erreur : Le fichier 'bin/zgp-manager' est introuvable."
  exit 1
fi

# 4. Enregistrement des types MIME (.zgp et .zgr) avec icônes système adaptées
MIME_FILE="$MIME_DIR/zgp-manager.xml"

cat << EOF > "$MIME_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-zgp-game">
    <comment>Jeu Zgp Manager</comment>
    <glob pattern="*.zgp"/>
    <icon name="input-gaming"/>
  </mime-type>
  <mime-type type="application/x-zgr-runner">
    <comment>Runner Zgp Manager</comment>
    <glob pattern="*.zgr"/>
    <icon name="system-run"/>
  </mime-type>
</mime-info>
EOF

update-mime-database /usr/share/mime 2>/dev/null || true
echo "[OK] Types MIME enregistrés avec icônes système."

# 5. Génération du lanceur dans le Menu des applications
DESKTOP_FILE="$APP_DESKTOP_DIR/zgp-manager.desktop"

cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=Zgp Manager
Comment=Gestionnaire de paquets et runners pour jeux
Exec=zgp-manager %f
Icon=input-gaming
Categories=Game;Utility;
Terminal=false
StartupNotify=true
MimeType=application/x-zgp-game;application/x-zgr-runner;
EOF

chmod +x "$DESKTOP_FILE"
update-desktop-database "$APP_DESKTOP_DIR" 2>/dev/null || true
echo "[OK] Lanceur et association de fichiers créés."

echo "========================================"
echo " Installation terminée avec succès !"
echo " Tu peux maintenant lancer 'zgp-manager' ou ouvrir directement tes fichiers .zgp / .zgr !"
echo "========================================"
