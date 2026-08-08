#!/bin/bash

# --- Analyse robuste des arguments (CLI, Double-clic et flags) ---
confirm_flag="$1"
shift
cli_targets=("$@")
is_double_click=false

# Si le premier argument reçu de bin/lpm est vide et qu'une seule cible fichier est présente sans tty
if [ -z "$confirm_flag" ] && [ ${#cli_targets[@]} -eq 1 ] && [ ! -t 0 ]; then
    is_double_click=true
fi

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

if ! command -v pv >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'pv' n'est pas installé sur le système." 2>/dev/null || echo "Erreur : pv manquant."
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'sha256sum' n'est pas installé sur le système." 2>/dev/null || echo "Erreur : sha256sum manquant."
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
  echo "Erreur : Lutris ne semble pas installé."
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

# Fonction propre pour télécharger avec une barre Zenity sécurisée
download_runner() {
  local url="$1"
  local dest="$2"
  local name="$3"

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" &
  else
    curl -sL "$url" -o "$dest" &
  fi
  local dl_pid=$!

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
# MODE CLI STRICT (Terminal, une ou plusieurs cibles : paquets locaux .zgr ET/OU noms distants GitHub)
if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
  declare -A runner_source   # "local" ou "distant"
  declare -A runner_archive  # chemin local, ou nom de fichier ciblé pour le distant
  runners_to_install=()
  conflicts=()

  for target in "${cli_targets[@]}"; do
    if [ -f "$target" ]; then
      runner_name=$(basename "$target" .zgr)
      runner_source["$runner_name"]="local"
      runner_archive["$runner_name"]="$target"
    else
      runner_name="${target%.zgr}"
      runner_source["$runner_name"]="distant"
      runner_archive["$runner_name"]="${runner_name}.zgr"
    fi

    if [ -d "$lutris_runner_dir/$runner_name" ]; then
      conflicts+=("$runner_name")
    fi

    runners_to_install+=("$runner_name")
  done

  # Vérification stricte : si UN SEUL runner demandé est déjà installé, on annule tout, sans rien installer
  if [ ${#conflicts[@]} -gt 0 ]; then
    echo "Erreur : le(s) runner(s) suivant(s) sont déjà installés :" >&2
    for name in "${conflicts[@]}"; do
      echo " - $name" >&2
    done
    echo "Désinstallez-les d'abord (ou retirez-les de la commande) avant de relancer l'installation. Aucun runner n'a été installé." >&2
    exit 1
  fi

  # Confirmation interactive si le flag -y n'est pas présent
  if [ "$confirm_flag" != "yes" ]; then
    echo "Runners à installer :"
    for name in "${runners_to_install[@]}"; do
      if [ "${runner_source[$name]}" = "local" ]; then
        echo " - $name (paquet local : ${runner_archive[$name]})"
      else
        echo " - $name (release distante GitHub)"
      fi
    done
    read -r -p "Êtes-vous sûr de vouloir installer ces runners ? [O/n] " response
    case "$response" in
      [nN][oO]|[nN])
        echo "Installation annulée."
        exit 0
        ;;
      *)
        ;;
    esac
  fi

  # Récupération unique des informations de la release GitHub si au moins un runner distant est demandé
  release_json=""
  for name in "${runners_to_install[@]}"; do
    if [ "${runner_source[$name]}" = "distant" ]; then
      api_url=$(echo "$GITHUB_RELEASE_URL" | sed -E 's|https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)|https://api.github.com/repos/\1/\2/releases/tags/\3|')
      if command -v curl >/dev/null 2>&1; then
        release_json=$(curl -s "$api_url")
      elif command -v wget >/dev/null 2>&1; then
        release_json=$(wget -qO- "$api_url")
      fi
      break
    fi
  done

  for runner_name in "${runners_to_install[@]}"; do
    src="${runner_source[$runner_name]}"

    expected_digest=""

    if [ "$src" = "local" ]; then
      archive_path="${runner_archive[$runner_name]}"
      echo "Installation de '$runner_name' depuis le paquet local..."
    else
      target_filename="${runner_archive[$runner_name]}"
      echo "Recherche de '$target_filename' sur la release GitHub..."

      download_url=""
      if command -v python3 >/dev/null 2>&1; then
        asset_info=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    target = sys.argv[2]
    for asset in data.get("assets", []):
        if asset.get("name", "") == target:
            url = asset.get("browser_download_url", "")
            digest = asset.get("digest") or ""
            print(f"{url}|{digest}")
            break
except Exception:
    pass
' "$release_json" "$target_filename")
        download_url="${asset_info%%|*}"
        expected_digest="${asset_info#*|}"
      fi

      if [ -z "$download_url" ]; then
        echo "Erreur : Impossible de trouver le runner '$target_filename' sur GitHub." >&2
        continue
      fi

      temp_cli_dir=$(mktemp -d)
      archive_path="$temp_cli_dir/${target_filename}"

      echo "Téléchargement de '$runner_name' :"
      if command -v wget >/dev/null 2>&1; then
        wget --show-progress -O "$archive_path" "$download_url"
      else
        curl -L -# -o "$archive_path" "$download_url"
      fi

      if [ ! -f "$archive_path" ] || [ ! -s "$archive_path" ]; then
        echo "Erreur : Échec du téléchargement de '$runner_name'." >&2
        rm -rf "$temp_cli_dir"
        continue
      fi

      if [ -n "$expected_digest" ]; then
        expected_sha="${expected_digest#sha256:}"
        actual_sha=$(sha256sum "$archive_path" 2>/dev/null | awk '{print $1}')
        if [ "$actual_sha" != "$expected_sha" ]; then
          echo "Erreur : Somme de contrôle SHA256 invalide pour '$runner_name'. Le fichier téléchargé est corrompu ou a été altéré." >&2
          rm -rf "$temp_cli_dir"
          continue
        fi
      fi
    fi

    echo "Décompression de '$runner_name' :"
    archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
    pv -s "${archive_size:-0}" "$archive_path" | tar -I zstd -xf - -C "$lutris_runner_dir"
    tar_exit="${PIPESTATUS[1]}"

    [ "$src" = "distant" ] && rm -rf "$temp_cli_dir"

    # Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
    # tronquée ou invalide), on nettoie ce qui a pu être extrait et on passe au runner suivant
    if [ "$tar_exit" -ne 0 ]; then
      echo "Erreur : L'archive de '$runner_name' est corrompue ou invalide (échec de la décompression, code $tar_exit)." >&2
      rm -rf "$lutris_runner_dir/$runner_name"
      continue
    fi

    echo "Installation de '$runner_name' terminée avec succès !"
  done

  exit 0
fi

# ---------------------------------------------------------------------------------------------
# MODE DOUBLE-CLIC / FICHIER CIBLÉ (Scan UNIQUEMENT du dossier parent du fichier cliqué)
if [ ${#cli_targets[@]} -eq 1 ] && [ "$is_double_click" = true ] && [ -f "${cli_targets[0]}" ]; then
  target_file="${cli_targets[0]}"
  search_dir="$(dirname "$target_file")"

  shopt -s nullglob
  folder_zgr_files=("$search_dir"/*.zgr)

  declare -A mass_file_by_name
  mass_zenity_args=()

  for f_path in "${folder_zgr_files[@]}"; do
    [ -f "$f_path" ] || continue
    f_name=$(basename "$f_path" .zgr)
    
    if [ -d "$lutris_runner_dir/$f_name" ]; then
      continue
    fi

    mass_file_by_name["$f_name"]="$f_path"
    mass_zenity_args+=( "TRUE" "$f_name" "[Local]" )
  done

  if [ ${#mass_file_by_name[@]} -eq 0 ]; then
    zenity --info --text="Le runner est déjà installé ou aucun autre fichier .zgr valide n'a été trouvé dans ce dossier." 2>/dev/null
    exit 0
  fi

  selected_mass=$(zenity --list --checklist \
    --title="Zgr-Runner-Installer (Import de masse)" \
    --text="Sélectionnez les runners à installer depuis ce dossier :" \
    --column="Installer" --column="Nom du Runner" --column="Source" \
    "${mass_zenity_args[@]}" \
    --width=600 --height=300 2>/dev/null)

  [ -z "$selected_mass" ] && exit 0
  IFS="|" read -r -a mass_to_install <<< "$selected_mass"

  for sub_runner_name in "${mass_to_install[@]}"; do
    target_runner_dir="$lutris_runner_dir/$sub_runner_name"
    archive_path="${mass_file_by_name[$sub_runner_name]}"
    
    [ -f "$archive_path" ] || continue

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
          echo "# Installation de $sub_runner_name\nExtraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
        fi
        sleep 0.2
      done

      echo "100"
      echo "# Finalisation de l'installation de $sub_runner_name..."
      sleep 0.5
    ) | zenity --progress \
      --title="Importation de $sub_runner_name" \
      --text="Début de l'extraction..." \
      --percentage=0 \
      --auto-close \
      --width=500 2>/dev/null

    zenity_status=$?
    if [ $zenity_status -ne 0 ]; then
      pkill -P $tar_pid 2>/dev/null
      kill -9 $tar_pid 2>/dev/null
      rm -rf "$target_runner_dir"
      continue
    fi

    wait $tar_pid
    tar_exit=$?

    # Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
    # tronquée ou invalide), on nettoie le dossier partiellement extrait et on passe au runner suivant
    if [ "$tar_exit" -ne 0 ]; then
      zenity --error --title="Archive corrompue" --text="Erreur : L'archive de '$sub_runner_name' est corrompue ou invalide (échec de la décompression, code $tar_exit)." 2>/dev/null
      rm -rf "$target_runner_dir"
      continue
    fi
  done

  notify-send "Installation terminée" "Tous les runners sélectionnés ont été installés !" 2>/dev/null
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# MODE INTERACTIF NORMAL (Depuis le menu : Uniquement En Ligne, AUCUN scan local par défaut)
declare -A source_by_name
declare -A file_or_url_by_name
declare -A digest_by_name

if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
  api_url=$(echo "$GITHUB_RELEASE_URL" | sed -E 's|https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/]+)|https://api.github.com/repos/\1/\2/releases/tags/\3|')

  if command -v curl >/dev/null 2>&1; then
    release_json=$(curl -s "$api_url")
  else
    release_json=$(wget -qO- "$api_url")
  fi

  if command -v python3 >/dev/null 2>&1; then
    parsed_assets=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        digest = asset.get("digest") or ""
        if name.endswith(".zgr"):
            print(f"{name}|{url}|{digest}")
except Exception:
    pass
' "$release_json")
    while IFS='|' read -r asset_name download_url asset_digest; do
      [ -z "$asset_name" ] && continue
      runner_name="${asset_name%.zgr}"

      if [ -d "$lutris_runner_dir/$runner_name" ]; then
        continue
      fi

      source_by_name["$runner_name"]="[En ligne]"
      file_or_url_by_name["$runner_name"]="$download_url"
      digest_by_name["$runner_name"]="$asset_digest"
    done <<< "$parsed_assets"
  fi
fi

zenity_args=()
for runner_name in "${!file_or_url_by_name[@]}"; do
  source_tag="${source_by_name[$runner_name]}"
  zenity_args+=( "TRUE" "$runner_name" "$source_tag" )
done

zenity_args+=( "FALSE" "Parcourir un fichier .zgr..." "[Fichier externe]" )
file_or_url_by_name["Parcourir un fichier .zgr..."]=""
source_by_name["Parcourir un fichier .zgr..."]="[Externe]"

selected_runners=$(zenity --list --checklist \
  --title="Zgr-Installer (En ligne)" \
  --text="Sélectionnez les runners en ligne à installer :" \
  --column="Installer" --column="Nom du Runner" --column="Source" \
  "${zenity_args[@]}" \
  --width=700 --height=380 2>/dev/null)

if [ -z "$selected_runners" ]; then
  exit 0
fi

IFS="|" read -r -a runners_to_install <<< "$selected_runners"
temp_dir=$(mktemp -d)

for runner_name in "${runners_to_install[@]}"; do
  if [ "$runner_name" = "Parcourir un fichier .zgr..." ]; then
    external_file=$(zenity --file-selection \
        --title="Sélectionner un runner (.zgr)" \
        --file-filter="Archives ZGR (*.zgr) | *.zgr" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$external_file" ]; then
      continue
    fi

    ext_dir="$(dirname "$external_file")"
    
    declare -A ext_file_or_url_by_name
    
    shopt -s nullglob
    for ext_file in "$ext_dir"/*.zgr; do
      [ -f "$ext_file" ] || continue
      ext_filename=$(basename "$ext_file")
      ext_r_name="${ext_filename%.zgr}"
      
      if [ -d "$lutris_runner_dir/$ext_r_name" ]; then
        continue
      fi
      
      ext_file_or_url_by_name["$ext_r_name"]="$ext_file"
    done

    if [ ${#ext_file_or_url_by_name[@]} -eq 0 ] && [ -f "$external_file" ]; then
      ext_filename=$(basename "$external_file")
      ext_r_name="${ext_filename%.zgr}"
      ext_file_or_url_by_name["$ext_r_name"]="$external_file"
    fi

    if [ ${#ext_file_or_url_by_name[@]} -eq 0 ]; then
      zenity --error --text="Aucun runner .zgr valide trouvé dans ce répertoire." 2>/dev/null
      continue
    fi

    ext_zenity_args=()
    for ext_r_name in "${!ext_file_or_url_by_name[@]}"; do
      ext_zenity_args+=( "TRUE" "$ext_r_name" "[Local]" )
    done

    ext_selected_runners=$(zenity --list --checklist \
      --title="Runners trouvés dans le dossier" \
      --text="Sélectionnez les runners à installer depuis ce dossier :" \
      --column="Installer" --column="Nom du Runner" --column="Source" \
      "${ext_zenity_args[@]}" \
      --width=600 --height=300 2>/dev/null)

    if [ -z "$ext_selected_runners" ]; then
      continue
    fi

    IFS="|" read -r -a ext_runners_to_install <<< "$ext_selected_runners"

    for sub_runner_name in "${ext_runners_to_install[@]}"; do
      target_runner_dir="$lutris_runner_dir/$sub_runner_name"
      archive_path="${ext_file_or_url_by_name[$sub_runner_name]}"
      
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
            echo "# Installation de $sub_runner_name\nExtraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
          fi
          sleep 0.2
        done

        echo "100"
        echo "# Finalisation de l'installation de $sub_runner_name..."
        sleep 0.5
      ) | zenity --progress \
        --title="Importation de $sub_runner_name" \
        --text="Début de l'extraction..." \
        --percentage=0 \
        --auto-close \
        --width=500 2>/dev/null

      zenity_status=$?
      if [ $zenity_status -ne 0 ]; then
        pkill -P $tar_pid 2>/dev/null
        kill -9 $tar_pid 2>/dev/null
        rm -rf "$target_runner_dir"
        continue
      fi
      wait $tar_pid
      tar_exit=$?

      # Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
      # tronquée ou invalide), on nettoie le dossier partiellement extrait et on passe au runner suivant
      if [ "$tar_exit" -ne 0 ]; then
        zenity --error --title="Archive corrompue" --text="Erreur : L'archive de '$sub_runner_name' est corrompue ou invalide (échec de la décompression, code $tar_exit)." 2>/dev/null
        rm -rf "$target_runner_dir"
        continue
      fi
    done
    continue
  else
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

      expected_digest="${digest_by_name[$runner_name]}"
      if [ -n "$expected_digest" ]; then
        expected_sha="${expected_digest#sha256:}"
        actual_sha=$(sha256sum "$archive_path" 2>/dev/null | awk '{print $1}')
        if [ "$actual_sha" != "$expected_sha" ]; then
          zenity --error --text="Erreur : Somme de contrôle SHA256 invalide pour '$runner_name'.\nLe fichier téléchargé est corrompu ou a été altéré." 2>/dev/null
          rm -f "$archive_path"
          continue
        fi
      fi
    fi
  fi

  target_runner_dir="$lutris_runner_dir/$runner_name"

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
  tar_exit=$?

  # Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
  # tronquée ou invalide), on nettoie le dossier partiellement extrait et on passe au runner suivant
  if [ "$tar_exit" -ne 0 ]; then
    zenity --error --title="Archive corrompue" --text="Erreur : L'archive de '$runner_name' est corrompue ou invalide (échec de la décompression, code $tar_exit)." 2>/dev/null
    rm -rf "$target_runner_dir"
    continue
  fi
done

rm -rf "$temp_dir"
notify-send "Installation terminée" "Tous les runners sélectionnés ont été installés avec succès !" 2>/dev/null
exit 0
