#!/bin/bash

# --- Lister les runners disponibles sur la release GitHub distante ---
# Sortie : <nom du runner> par ligne, triés alphabétiquement.
# Un runner déjà présent localement est signalé par "(déjà installé)".

lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

readonly GITHUB_RELEASE_URL="https://github.com/RogerBytes/Mintage/releases/tag/zgr-pkg"

# 1. Vérification des dépendances nécessaires
if ! command -v python3 >/dev/null 2>&1; then
  echo "Erreur : 'python3' n'est pas installé sur le système." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "Erreur : 'curl' ou 'wget' est requis pour contacter le dépôt distant." >&2
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif (pour marquer les runners déjà installés)
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  runner_dir="$lutris_flatpak_runner_dir"
elif [ -d "$lutris_package_runner_dir" ]; then
  runner_dir="$lutris_package_runner_dir"
else
  runner_dir="$HOME/.local/share/lutris/runners/wine"
fi

# 3. Récupération de la liste des assets .zgr de la release GitHub
api_url=$(echo "$GITHUB_RELEASE_URL" | sed -E 's|https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)|https://api.github.com/repos/\1/\2/releases/tags/\3|')

release_json=""
if command -v curl >/dev/null 2>&1; then
  release_json=$(curl -s "$api_url")
else
  release_json=$(wget -qO- "$api_url")
fi

if [ -z "$release_json" ]; then
  echo "Erreur : Impossible de contacter la release GitHub distante." >&2
  exit 1
fi

remote_runners=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    names = []
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        if name.endswith(".zgr"):
            names.append(name[:-4])
    names.sort(key=str.lower)
    for n in names:
        print(n)
except Exception:
    pass
' "$release_json")

if [ -z "$remote_runners" ]; then
  echo "Aucun runner disponible sur le dépôt distant (ou réponse GitHub invalide)."
  exit 0
fi

while IFS= read -r runner_name; do
  [ -z "$runner_name" ] && continue
  if [ -d "$runner_dir/$runner_name" ]; then
    echo "$runner_name  (déjà installé)"
  else
    echo "$runner_name"
  fi
done <<< "$remote_runners"

exit 0
