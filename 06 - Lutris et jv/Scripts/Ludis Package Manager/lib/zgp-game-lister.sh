#!/bin/bash

# --- Lister les jeux Wine installés via Lutris ---
# Sortie : <slug>  <nom du jeu>

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"

# Configuration des chemins Lutris
lutris_flatpak_db="${HOME}/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="${HOME}/.local/share/lutris/pga.db"

# 1. Vérification de sqlite3
if ! command -v sqlite3 >/dev/null 2>&1; then
  t list_games.sqlite_missing >&2
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif (fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  lutris_db="${lutris_flatpak_db}"
elif check_native_lutris_installed "${lutris_package_db}" ""; then
  lutris_db="${lutris_package_db}"
else
  t list_games.lutris_missing >&2
  exit 1
fi

if [[ ! -f "${lutris_db}" ]]; then
  t list_games.db_missing "${lutris_db}" >&2
  exit 1
fi

# 3. Récupération des jeux Wine (slug puis nom), triés par nom
games_list=$(sqlite3 "${lutris_db}" "SELECT slug || '|' || name FROM games WHERE runner='wine' ORDER BY name COLLATE NOCASE ASC;" 2>/dev/null)

if [[ -z "${games_list}" ]]; then
  t list_games.none_installed
  exit 0
fi

while IFS="|" read -r slug name; do
  [[ -z "${slug}" ]] && continue
  echo "${slug}  ${name}"
done <<< "${games_list}"

exit 0
