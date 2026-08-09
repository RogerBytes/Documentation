#!/bin/bash

# S'assurer que le script est exécuté avec les privilèges root (sudo)
if [[ "${EUID}" -ne 0 ]]; then
  echo "Erreur : Veuillez exécuter ce script d'installation avec les privilèges administrateur (sudo ./install.sh)."
  exit 1
fi

# Définition des chemins de destination sur le système
INSTALL_BIN_DIR="/usr/local/bin"
INSTALL_LIB_DIR="/usr/local/lib/lpm"
APP_DESKTOP_DIR="/usr/share/applications"
MIME_DIR="/usr/share/mime/packages"

echo "=== Installation de lpm ==="

# 1. Création des dossiers de destination
mkdir -p "${INSTALL_LIB_DIR}"
mkdir -p "${APP_DESKTOP_DIR}"
mkdir -p "${MIME_DIR}"

# 2. Copie des scripts de la bibliothèque (lib/)
if [[ -d "lib" ]]; then
  cp -r lib/* "${INSTALL_LIB_DIR}/"
  chmod +x "${INSTALL_LIB_DIR}"/*.sh
  echo "[OK] Bibliothèques copiées dans ${INSTALL_LIB_DIR}"
else
  echo "Erreur : Le dossier 'lib' est introuvable."
  exit 1
fi

# 2bis. Copie des fichiers de langue (lang/)
if [[ -d "lang" ]]; then
  mkdir -p "${INSTALL_LIB_DIR}/lang"
  cp -r lang/* "${INSTALL_LIB_DIR}/lang/"
  echo "[OK] Fichiers de langue copiés dans ${INSTALL_LIB_DIR}/lang"
else
  echo "Erreur : Le dossier 'lang' est introuvable."
  exit 1
fi

# 3. Copie et liaison du binaire principal (bin/lpm)
if [[ -f "bin/lpm" ]]; then
  cp bin/lpm "${INSTALL_BIN_DIR}/lpm"
  chmod +x "${INSTALL_BIN_DIR}/lpm"
  echo "[OK] Binaire du manager installé dans ${INSTALL_BIN_DIR}/lpm"
else
  echo "Erreur : Le fichier 'bin/lpm' est introuvable."
  exit 1
fi

# 4. Enregistrement des types MIME (.zgp et .zgr) avec icônes système adaptées
MIME_FILE="${MIME_DIR}/lpm.xml"

cat << EOF > "${MIME_FILE}"
<?xml-stylesheet type="text/xsl" href="libxslt:shared-mime-info"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-zgp-game">
    <comment>Jeu lpm</comment>
    <glob pattern="*.zgp"/>
    <icon name="input-gaming"/>
  </mime-type>
  <mime-type type="application/x-zgr-runner">
    <comment>Runner lpm</comment>
    <glob pattern="*.zgr"/>
    <icon name="system-run"/>
  </mime-type>
</mime-info>
EOF

update-mime-database /usr/share/mime 2>/dev/null || true
echo "[OK] Types MIME enregistrés avec icônes système."

# 5. Génération du lanceur dans le Menu des applications
DESKTOP_FILE="${APP_DESKTOP_DIR}/lpm.desktop"

cat << EOF > "${DESKTOP_FILE}"
[Desktop Entry]
Type=Application
Name=lpm
Comment=Gestionnaire de paquets et runners pour jeux
Exec=lpm %f
Icon=input-gaming
Categories=Game;Utility;
Terminal=false
StartupNotify=true
MimeType=application/x-zgp-game;application/x-zgr-runner;
EOF

chmod +x "${DESKTOP_FILE}"
update-desktop-database "${APP_DESKTOP_DIR}" 2>/dev/null || true
echo "[OK] Lanceur et association de fichiers créés."

echo "========================================"
echo " Installation terminée avec succès !"
echo " Tu peux maintenant lancer 'lpm' ou ouvrir directement tes fichiers .zgp / .zgr !"
echo "========================================"
