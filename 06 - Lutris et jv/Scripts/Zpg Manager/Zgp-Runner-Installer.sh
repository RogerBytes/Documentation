#!/bin/bash

# Configuration des chemins des runners Lutris
lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

# Constante contenant le lien de la release GitHub
readonly GITHUB_RELEASE_URL="https://github.com/RogerBytes/Mintage/releases/tag/zgr-pkg"

# 1. Vérification de zenity et zstd
if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé pour l'interface graphique."
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'zstd' n'est pas installé sur le système." 2>/dev/null || echo "Erreur : zstd manquant."
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif pour les runners
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  version="flatpak"
elif [ -d "$HOME/.local/share/lutris/runners/wine" ] || command -v lutris >/dev/null 2>&1; then
  version="package"
else
  zenity --error --text="Lutris ne semble pas installé sur le système." 2>/dev/null
  exit 1
fi

case "$version" in
  flatpak)
    lutris_runner_dir="$lutris_flatpak_runner_dir"
    ;;
  package)
    lutris_runner_dir="$lutris_package_runner_dir"
    ;;
esac

mkdir -p "$lutris_runner_dir"

# ---------------------------------------------------------------------------------------------
# COLLECTE DES RUNNERS (LOCAUX ET EN LIGNE)
declare -A source_by_name
declare -A file_or_url_by_name

# A. Récupération des fichiers locaux (.zgr) dans le répertoire courant
shopt -s nullglob
local_zgp_files=( ./*.zgr )

for file in "${local_zgp_files[@]}"; do
  filename=$(basename "$file")
  runner_name="${filename%.zgr}"
  
  if [ -d "$lutris_runner_dir/$runner_name" ]; then
    continue
  fi
  
  source_by_name["$runner_name"]="[Local]"
  file_or_url_by_name["$runner_name"]="$file"
done

# B. Récupération des runners en ligne sur GitHub via python
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
  api_url=$(echo "$GITHUB_RELEASE_URL" | sed -E 's|https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)|https://api.github.com/repos/\1/\2/releases/tags/\3|')

  if command -v curl >/dev/null 2>&1; then
    release_json=$(curl -s "$api_url")
  else
    release_json=$(wget -qO- "$api_url")
  fi

  if command -v python3 >/dev/null 2>&1; then
    parsed_assets=$(echo "$release_json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        if name.endswith(".zgr"):
            print(f"{name}|{url}")
except Exception:
    pass
')
    while IFS='|' read -r asset_name download_url; do
      [ -z "$asset_name" ] && continue
      runner_name="${asset_name%.zgr}"

      if [ -d "$lutris_runner_dir/$runner_name" ]; then
        continue
      fi

      if [ -n "${file_or_url_by_name[$runner_name]}" ]; then
        continue
      fi

      source_by_name["$runner_name"]="[En ligne]"
      file_or_url_by_name["$runner_name"]="$download_url"
    done <<< "$parsed_assets"
  fi
fi

if [ ${#file_or_url_by_name[@]} -eq 0 ]; then
  zenity --info --title="À jour" --text="Tous les runners disponibles sont déjà installés !" 2>/dev/null
  exit 0
fi

# Fonction propre pour télécharger avec une barre Zenity sécurisée
download_runner() {
  local url="$1"
  local dest="$2"
  local name="$3"

  # On lance wget en arrière-plan en écrivant directement dans le fichier de destination
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" &
  else
    curl -sL "$url" -o "$dest" &
  fi
  local dl_pid=$!

  # Boucle de suivi de progression basée sur la taille du fichier par rapport à la taille totale estimée ou affichage simple
  (
    while kill -0 $dl_pid 2>/dev/null; do
      echo "# Téléchargement de $name en cours..."
      sleep 0.5
    done
  ) | zenity --progress \
    --title="Téléchargement de $name" \
    --text="Connexion à GitHub..." \
    --pulsate \
    --auto-close \
    --no-cancel 2>/dev/null

  wait $dl_pid
}

# ---------------------------------------------------------------------------------------------
# MODE ARGUMENT : Si un nom de runner est passé en paramètre
if [ -n "$1" ]; then
  target_arg_runner="$1"
  
  if [ -z "${file_or_url_by_name[$target_arg_runner]}" ]; then
    zenity --error --text="Le runner '$target_arg_runner' est introuvable (ou déjà installé / absent des sources)." 2>/dev/null
    exit 1
  fi

  if [ -d "$lutris_runner_dir/$target_arg_runner" ]; then
    zenity --info --title="Déjà installé" --text="Le runner '$target_arg_runner' est déjà installé sur votre système !" 2>/dev/null
    exit 0
  fi

  target_runner_dir="$lutris_runner_dir/$target_arg_runner"
  temp_dir=""
  source_type="${source_by_name[$target_arg_runner]}"

  if [ "$source_type" = "[Local]" ]; then
    archive_path="${file_or_url_by_name[$target_arg_runner]}"
  else
    temp_dir=$(mktemp -d)
    archive_path="$temp_dir/${target_arg_runner}.zgr"
    download_url="${file_or_url_by_name[$target_arg_runner]}"

    download_runner "$download_url" "$archive_path" "$target_arg_runner"

    if [ ! -f "$archive_path" ] || [ ! -s "$archive_path" ] || ! tar -I zstd -tf "$archive_path" >/dev/null 2>&1; then
      zenity --error --text="Erreur : Échec du téléchargement ou archive zstd invalide pour $target_arg_runner." 2>/dev/null
      rm -rf "$temp_dir"
      exit 1
    fi
  fi

  archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
  [ -z "$archive_size" ] && archive_size=1
  estimated_uncompressed_size=$(( archive_size * 3 ))
  [ "$estimated_uncompressed_size" -le 0 ] && estimated_uncompressed_size=1

  tar -I zstd -xf "$archive_path" -C "$lutris_runner_dir" &
  tar_pid=$!

  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -d "$target_runner_dir" ]; then
        current_size=$(du -sb "$target_runner_dir" 2>/dev/null | cut -f1)
        [ -z "$current_size" ] && current_size=0

        percent=$(( current_size * 100 / estimated_uncompressed_size ))
        if [ "$percent" -ge 99 ]; then
          percent=99
        fi
        
        current_mb=$(( current_size / 1024 / 1024 ))
        estimated_mb=$(( estimated_uncompressed_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Installation de $target_arg_runner\nExtraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
      fi
      sleep 0.2
    done

    echo "100"
    echo "# Finalisation de l'installation de $target_arg_runner..."
    sleep 0.5
  ) | zenity --progress \
    --title="Importation de $target_arg_runner" \
    --text="Début de l'extraction..." \
    --percentage=0 \
    --auto-close \
    --width=500 2>/dev/null

  wait $tar_pid
  [ -n "$temp_dir" ] && rm -rf "$temp_dir"
  notify-send "Installation terminée" "Le runner $target_arg_runner a été installé avec succès !" 2>/dev/null
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# MODE INTERACTIF (Par défaut si aucun argument n'est fourni)

zenity_args=()
for runner_name in "${!file_or_url_by_name[@]}"; do
  source_tag="${source_by_name[$runner_name]}"
  zenity_args+=( "TRUE" "$runner_name" "$source_tag" )
done

selected_runners=$(zenity --list --checklist \
  --title="Zgr-Installer (Hybride Local / En ligne)" \
  --text="Sélectionnez les runners à installer :" \
  --column="Installer" --column="Nom du Runner" --column="Source" \
  "${zenity_args[@]}" \
  --width=700 --height=350 2>/dev/null)

if [ -z "$selected_runners" ]; then
  exit 0
fi

IFS="|" read -r -a runners_to_install <<< "$selected_runners"
temp_dir=$(mktemp -d)

for runner_name in "${runners_to_install[@]}"; do
  target_runner_dir="$lutris_runner_dir/$runner_name"
  source_type="${source_by_name[$runner_name]}"
  
  if [ "$source_type" = "[Local]" ]; then
    archive_path="${file_or_url_by_name[$runner_name]}"
  else
    download_url="${file_or_url_by_name[$runner_name]}"
    archive_path="$temp_dir/${runner_name}.zgr"
    rm -f "$archive_path"

    download_runner "$download_url" "$archive_path" "$runner_name"

    if [ ! -f "$archive_path" ] || [ ! -s "$archive_path" ] || ! tar -I zstd -tf "$archive_path" >/dev/null 2>&1; then
      zenity --error --text="Erreur : Échec du téléchargement ou archive zstd invalide pour $runner_name." 2>/dev/null
      continue
    fi
  fi

  archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
  [ -z "$archive_size" ] && archive_size=1
  estimated_uncompressed_size=$(( archive_size * 3 ))
  [ "$estimated_uncompressed_size" -le 0 ] && estimated_uncompressed_size=1

  tar -I zstd -xf "$archive_path" -C "$lutris_runner_dir" &
  tar_pid=$!

  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -d "$target_runner_dir" ]; then
        current_size=$(du -sb "$target_runner_dir" 2>/dev/null | cut -f1)
        [ -z "$current_size" ] && current_size=0

        percent=$(( current_size * 100 / estimated_uncompressed_size ))
        if [ "$percent" -ge 99 ]; then
          percent=99
        fi
        
        current_mb=$(( current_size / 1024 / 1024 ))
        estimated_mb=$(( estimated_uncompressed_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Installation de $runner_name\nExtraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
      fi
      sleep 0.2
    done

    echo "100"
    echo "# Finalisation de l'installation de $runner_name..."
    sleep 0.5
  ) | zenity --progress \
    --title="Importation de $runner_name" \
    --text="Début de l'extraction..." \
    --percentage=0 \
    --auto-close \
    --width=500 2>/dev/null

  zenity_status=$?

  if [ $zenity_status -ne 0 ]; then
    pkill -P $tar_pid 2>/dev/null
    kill -9 $tar_pid 2>/dev/null
    rm -rf "$target_runner_dir"
    rm -rf "$temp_dir"
    zenity --info --title="Annulation" --text="L'importation a été annulée." 2>/dev/null
    exit 0
  fi

  wait $tar_pid

done

rm -rf "$temp_dir"
notify-send "Installation terminée" "Tous les runners sélectionnés ont été installés avec succès !" 2>/dev/null
exit 0
