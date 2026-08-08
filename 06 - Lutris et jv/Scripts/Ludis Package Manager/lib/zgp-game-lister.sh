#!/bin/bash

# --- Lister les jeux Wine installés via Lutris ---
# Sortie : <slug>  <nom du jeu>

# Configuration des chemins Lutris
lutris_flatpak_db="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="$HOME/.local/share/lutris/pga.db"

# 1. Vérification de sqlite3
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "Erreur : 'sqlite3' n'est pas installé sur le système." >&2
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  lutris_db="$lutris_flatpak_db"
elif command -v lutris >/dev/null 2>&1 || [ -f "$lutris_package_db" ]; then
  lutris_db="$lutris_package_db"
else
  echo "Erreur : Lutris n'est pas installé sur le système." >&2
  exit 1
fi

if [ ! -f "$lutris_db" ]; then
  echo "Erreur : Base de données Lutris introuvable : $lutris_db" >&2
  exit 1
fi

# 3. Récupération des jeux Wine (slug puis nom), triés par nom
games_list=$(sqlite3 "$lutris_db" "SELECT slug || '|' || name FROM games WHERE runner='wine' ORDER BY name COLLATE NOCASE ASC;" 2>/dev/null)

if [ -z "$games_list" ]; then
  echo "Aucun jeu installé."
  exit 0
fi

while IFS="|" read -r slug name; do
  [ -z "$slug" ] && continue
  echo "$slug  $name"
done <<< "$games_list"

exit 0
