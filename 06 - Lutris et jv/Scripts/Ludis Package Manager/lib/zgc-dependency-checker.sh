#!/bin/bash

# --- Récupération des arguments du routeur lpm ---
# $1 = mode ("cli" depuis le terminal, "gui" ou vide depuis le menu Zenity)
mode="${1:-gui}"

# Configuration des chemins Lutris
lutris_flatpak_db="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="$HOME/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="$HOME/.config/lutris/games"

lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

readonly GITHUB_RELEASE_URL="https://github.com/RogerBytes/Mintage/releases/tag/zgr-pkg"

say() {
  if [ "$mode" = "cli" ]; then
    echo "$1"
  else
    zenity --info --text="$1" --width=450 2>/dev/null
  fi
}

say_err() {
  if [ "$mode" = "cli" ]; then
    echo "$1" >&2
  else
    zenity --error --text="$1" --width=450 2>/dev/null
  fi
}

# 1. Vérification des dépendances nécessaires
for cmd in sqlite3 python3 zstd tar sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    say_err "Erreur : '$cmd' n'est pas installé sur le système."
    exit 1
  fi
done

if [ "$mode" != "cli" ] && ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé pour l'interface graphique." >&2
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  lutris_db="$lutris_flatpak_db"
  lutris_config_dir="$lutris_flatpak_config_dir"
  runner_dir="$lutris_flatpak_runner_dir"
elif command -v lutris >/dev/null 2>&1 || [ -f "$lutris_package_db" ]; then
  lutris_db="$lutris_package_db"
  lutris_config_dir="$lutris_package_config_dir"
  runner_dir="$lutris_package_runner_dir"
else
  say_err "Erreur : Lutris n'est pas installé sur le système."
  exit 1
fi

if [ ! -f "$lutris_db" ]; then
  say_err "Erreur : Base de données Lutris introuvable : $lutris_db"
  exit 1
fi

mkdir -p "$runner_dir"

# ---------------------------------------------------------------------------------------------
# 3. Détermination des runners requis par les jeux installés (clé wine.version des YAML)
# ---------------------------------------------------------------------------------------------

games_list=$(sqlite3 "$lutris_db" "SELECT name || '|' || slug || '|' || configpath FROM games WHERE runner='wine';" 2>/dev/null)

declare -A games_needing_runner   # runner_name -> "jeu1, jeu2, ..."
required_runners=()

while IFS="|" read -r game_name game_slug configpath; do
  [ -z "$game_slug" ] && continue
  [ -z "$configpath" ] && continue

  yml_path="$lutris_config_dir/${configpath}.yml"
  [ -f "$yml_path" ] || continue

  required_runner=$(YML_PATH="$yml_path" python3 -c '
import os, yaml
try:
    with open(os.environ["YML_PATH"], "r") as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        print(data.get("wine", {}).get("version", ""))
except Exception:
    pass
' 2>/dev/null)

  [ -z "$required_runner" ] && continue

  if [ -z "${games_needing_runner[$required_runner]}" ]; then
    games_needing_runner["$required_runner"]="$game_name"
    required_runners+=("$required_runner")
  else
    games_needing_runner["$required_runner"]="${games_needing_runner[$required_runner]}, $game_name"
  fi
done <<< "$games_list"

if [ ${#required_runners[@]} -eq 0 ]; then
  say "Aucun jeu installé ne référence de runner Wine à vérifier."
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# 4. Comparaison avec les runners réellement installés
# ---------------------------------------------------------------------------------------------

missing_runners=()
for runner_name in "${required_runners[@]}"; do
  if [ ! -d "$runner_dir/$runner_name" ]; then
    missing_runners+=("$runner_name")
  fi
done

if [ ${#missing_runners[@]} -eq 0 ]; then
  say "Tous les runners nécessaires sont déjà installés."
  exit 0
fi

if [ "$mode" = "cli" ]; then
  echo "Runners manquants détectés :"
  for r in "${missing_runners[@]}"; do
    echo " - $r (requis par : ${games_needing_runner[$r]})"
  done
  echo ""
fi

# ---------------------------------------------------------------------------------------------
# 5. Récupération unique de la liste des assets de la release GitHub (avec taille et digest SHA256)
# ---------------------------------------------------------------------------------------------

declare -A release_asset_url     # runner_name (sans .zgr) -> url de téléchargement
declare -A release_asset_size    # runner_name (sans .zgr) -> taille en octets
declare -A release_asset_digest  # runner_name (sans .zgr) -> "sha256:<hash>" (vide si non fourni par GitHub)

api_url=$(echo "$GITHUB_RELEASE_URL" | sed -E 's|https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)|https://api.github.com/repos/\1/\2/releases/tags/\3|')

release_json=""
if command -v curl >/dev/null 2>&1; then
  release_json=$(curl -s "$api_url")
elif command -v wget >/dev/null 2>&1; then
  release_json=$(wget -qO- "$api_url")
fi

if [ -n "$release_json" ]; then
  parsed_assets=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        size = asset.get("size", 0)
        digest = asset.get("digest") or ""
        if name.endswith(".zgr"):
            print(f"{name}|{url}|{size}|{digest}")
except Exception:
    pass
' "$release_json" 2>/dev/null)

  while IFS='|' read -r asset_name download_url asset_size asset_digest; do
    [ -z "$asset_name" ] && continue
    release_asset_url["${asset_name%.zgr}"]="$download_url"
    release_asset_size["${asset_name%.zgr}"]="$asset_size"
    release_asset_digest["${asset_name%.zgr}"]="$asset_digest"
  done <<< "$parsed_assets"
fi

# ---------------------------------------------------------------------------------------------
# 6. Fonctions de téléchargement et d'extraction avec barres de progression réelles
# ---------------------------------------------------------------------------------------------

download_cli() {
  local url="$1" runner_name="$2"
  local dest
  dest=$(mktemp -u "/tmp/${runner_name}-XXXXXX.zgr")

  echo "Téléchargement de '$runner_name' depuis le dépôt lpm :" >&2
  if command -v wget >/dev/null 2>&1; then
    wget --show-progress -O "$dest" "$url"
  else
    curl -L -# -o "$dest" "$url"
  fi

  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    rm -f "$dest"
    return 1
  fi
  echo "$dest"
}

download_gui() {
  local url="$1" runner_name="$2" expected_size="${3:-0}"
  local dest
  dest=$(mktemp -u "/tmp/${runner_name}-XXXXXX.zgr")

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" &
  else
    curl -sL "$url" -o "$dest" &
  fi
  local dl_pid=$!

  (
    while kill -0 $dl_pid 2>/dev/null; do
      current_size=$(stat -c%s "$dest" 2>/dev/null || stat -f%z "$dest" 2>/dev/null)
      [ -z "$current_size" ] && current_size=0

      if [ "$expected_size" -gt 0 ] 2>/dev/null; then
        percent=$(( current_size * 100 / expected_size ))
        [ "$percent" -ge 99 ] && percent=99
        current_mb=$(( current_size / 1024 / 1024 ))
        expected_mb=$(( expected_size / 1024 / 1024 ))
        echo "$percent"
        echo "# Téléchargement de $runner_name\n${current_mb} Mo / ~${expected_mb} Mo"
      else
        echo "0"
        echo "# Téléchargement de $runner_name en cours..."
      fi
      sleep 0.3
    done
    echo "100"
    echo "# Finalisation du téléchargement de $runner_name..."
  ) | zenity --progress --title="Téléchargement de $runner_name" --text="Connexion au dépôt lpm..." --percentage=0 --auto-close --width=450 2>/dev/null

  local zenity_status=$?
  wait $dl_pid

  if [ $zenity_status -ne 0 ]; then
    kill -9 $dl_pid 2>/dev/null
    rm -f "$dest"
    return 1
  fi

  if [ ! -f "$dest" ] || [ ! -s "$dest" ]; then
    rm -f "$dest"
    return 1
  fi
  echo "$dest"
}

# Vérifie le SHA256 d'une archive téléchargée par rapport au digest de la release GitHub.
# Retourne 0 si la vérification passe (ou si aucun digest n'est disponible pour cet asset),
# 1 si le digest est présent mais ne correspond pas.
verify_checksum() {
  local archive_path="$1" runner_name="$2"
  local expected_digest="${release_asset_digest[$runner_name]}"

  [ -z "$expected_digest" ] && return 0

  local expected_sha="${expected_digest#sha256:}"
  local actual_sha
  actual_sha=$(sha256sum "$archive_path" 2>/dev/null | awk '{print $1}')

  if [ "$actual_sha" != "$expected_sha" ]; then
    say_err "Erreur : Somme de contrôle SHA256 invalide pour '$runner_name'. Le fichier téléchargé est corrompu ou a été altéré."
    return 1
  fi
  return 0
}

extract_cli() {
  local archive_path="$1" runner_name="$2"
  echo "Décompression de '$runner_name' :"
  local archive_size
  archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
  if command -v pv >/dev/null 2>&1; then
    pv -s "${archive_size:-0}" "$archive_path" | tar -I zstd -xf - -C "$runner_dir"
    local tar_exit="${PIPESTATUS[1]}"
  else
    tar -I zstd -xf "$archive_path" -C "$runner_dir"
    local tar_exit=$?
  fi
  [ "$tar_exit" -eq 0 ] && [ -d "$runner_dir/$runner_name" ]
}

extract_gui() {
  local archive_path="$1" runner_name="$2"
  local target_dir="$runner_dir/$runner_name"

  local archive_size
  archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
  [ -z "$archive_size" ] && archive_size=1
  local estimated_uncompressed_size=$(( archive_size * 3 ))
  [ "$estimated_uncompressed_size" -le 0 ] && estimated_uncompressed_size=1

  tar -I zstd -xf "$archive_path" -C "$runner_dir" &
  local tar_pid=$!

  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -d "$target_dir" ]; then
        current_size=$(du -sb "$target_dir" 2>/dev/null | cut -f1)
        [ -z "$current_size" ] && current_size=0

        percent=$(( current_size * 100 / estimated_uncompressed_size ))
        [ "$percent" -ge 99 ] && percent=99

        current_mb=$(( current_size / 1024 / 1024 ))
        estimated_mb=$(( estimated_uncompressed_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Installation de $runner_name\nExtraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
      fi
      sleep 0.2
    done
    echo "100"
    echo "# Finalisation de l'installation de $runner_name..."
    sleep 0.3
  ) | zenity --progress --title="Installation de $runner_name" --text="Début de l'extraction..." --percentage=0 --auto-close --width=500 2>/dev/null

  local zenity_status=$?
  if [ $zenity_status -ne 0 ]; then
    kill -9 $tar_pid 2>/dev/null
    rm -rf "$target_dir"
    return 1
  fi

  wait $tar_pid
  local tar_exit=$?
  [ "$tar_exit" -eq 0 ] && [ -d "$target_dir" ]
}

# ---------------------------------------------------------------------------------------------
# 7. Traitement de chaque runner manquant : recherche distante uniquement, pas de question locale
# ---------------------------------------------------------------------------------------------

resolved_runners=()
unresolved_runners=()

for runner_name in "${missing_runners[@]}"; do
  install_ok=false

  if [ -n "${release_asset_url[$runner_name]}" ]; then
    if [ "$mode" = "cli" ]; then
      archive_path=$(download_cli "${release_asset_url[$runner_name]}" "$runner_name")
    else
      archive_path=$(download_gui "${release_asset_url[$runner_name]}" "$runner_name" "${release_asset_size[$runner_name]}")
    fi

    if [ -n "$archive_path" ]; then
      if verify_checksum "$archive_path" "$runner_name"; then
        if [ "$mode" = "cli" ]; then
          extract_cli "$archive_path" "$runner_name" && install_ok=true
        else
          extract_gui "$archive_path" "$runner_name" && install_ok=true
        fi
      fi
      rm -f "$archive_path"
    fi
  fi

  if [ "$install_ok" = true ]; then
    resolved_runners+=("$runner_name")
    [ "$mode" = "cli" ] && echo "Runner '$runner_name' installé avec succès."
  else
    unresolved_runners+=("$runner_name")
  fi
done

# ---------------------------------------------------------------------------------------------
# 8. Récapitulatif final
# ---------------------------------------------------------------------------------------------

if [ ${#unresolved_runners[@]} -eq 0 ]; then
  say "Vérification terminée : tous les runners manquants (${resolved_runners[*]}) ont été installés automatiquement."
  exit 0
fi

# Bloc de noms bruts, un par ligne, pour copier-coller facilement
recap_names=""
for r in "${unresolved_runners[@]}"; do
  recap_names+="$r
"
done

recap_details=""
for r in "${unresolved_runners[@]}"; do
  recap_details+=" - $r : requis par ${games_needing_runner[$r]}
"
done

if [ "$mode" = "cli" ]; then
  echo ""
  echo "=== Runners manquants non disponibles sur le dépôt lpm ==="
  echo "$recap_names"
  echo "Détail :"
  echo "$recap_details"
  echo "Pour chacun : installez-le via un fichier .zgr (lpm install-runner <fichier>.zgr), ou via ProtonUp-Qt."
else
  full_text="Runners manquants non disponibles sur le dépôt lpm :

${recap_names}
Détail :
${recap_details}
Pour chacun : installez-le via un fichier .zgr (lpm install-runner <fichier>.zgr), ou via ProtonUp-Qt."

  echo "$full_text" | zenity --text-info --title="Runners manquants" --width=550 --height=400 2>/dev/null
fi

exit 0
