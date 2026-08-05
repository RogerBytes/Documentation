#!/bin/bash

# S'assurer que le script est exécuté avec les privilèges root (sudo)
if [ "$EUID" -ne 0 ]; then
  echo "Erreur : Veuillez exécuter ce script de désinstallation avec les privilèges administrateur (sudo ./uninstall.sh)."
  exit 1
fi

# Définition des chemins de destination utilisés lors de l'installation
INSTALL_BIN_DIR="/usr/local/bin"
INSTALL_LIB_DIR="/usr/local/lib/zgp-manager"
APP_DESKTOP_DIR="/usr/share/applications"
DESKTOP_FILE="$APP_DESKTOP_DIR/zgp-manager.desktop"
MIME_FILE="/usr/share/mime/packages/zgp-manager.xml"

echo "=== Désinstallation de Zgp-Manager ==="

# 1. Suppression du binaire principal
if [ -f "$INSTALL_BIN_DIR/zgp-manager" ]; then
  rm -f "$INSTALL_BIN_DIR/zgp-manager"
  echo "[OK] Binaire zgp-manager supprimé de $INSTALL_BIN_DIR"
else
  echo "[Info] Le binaire zgp-manager n'était pas présent dans $INSTALL_BIN_DIR"
fi

# 2. Suppression du dossier des bibliothèques
if [ -d "$INSTALL_LIB_DIR" ]; then
  rm -rf "$INSTALL_LIB_DIR"
  echo "[OK] Dossier des bibliothèques supprimé de $INSTALL_LIB_DIR"
else
  echo "[Info] Le dossier des bibliothèques n'existait pas à $INSTALL_LIB_DIR"
fi

# 3. Suppression des types MIME (.zgp et .zgr) et mise à jour de la base
if [ -f "$MIME_FILE" ]; then
  rm -f "$MIME_FILE"
  update-mime-database /usr/share/mime 2>/dev/null || true
  echo "[OK] Types MIME (.zgp et .zgr) supprimés du système."
else
  echo "[Info] Aucun type MIME associé trouvé."
fi

# 4. Suppression du lanceur dans le Menu des applications
if [ -f "$DESKTOP_FILE" ]; then
  rm -f "$DESKTOP_FILE"
  update-desktop-database "$APP_DESKTOP_DIR" 2>/dev/null || true
  echo "[OK] Lanceur du menu des applications supprimé."
else
  echo "[Info] Aucun lanceur trouvé dans $APP_DESKTOP_DIR"
fi

echo "========================================"
echo " Désinstallation terminée avec succès !"
echo " Zgp-Manager a été complètement retiré de votre système."
echo "========================================"
