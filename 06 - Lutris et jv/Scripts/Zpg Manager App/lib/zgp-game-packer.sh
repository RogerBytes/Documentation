#!/bin/bash

# Configuration des chemins et variables de base
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${HOME}"
GAMES_DIR="${HOME}/Games"
user_array=("$USER" "johndoe")

# Récupération dynamique du runner par défaut global de Lutris
default_runner=""
for runners_path in "${HOME}/.local/share/lutris/runners/wine.yml" "${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml"; do
    if [ -f "$runners_path" ]; then
        default_runner=$(awk -F': ' '/^\s*version:/ {print $2; exit}' "$runners_path" | tr -d '"'\''[:space:]')
        [ -n "$default_runner" ] && break
    fi
done
[ -z "$default_runner" ] && default_runner="proton-cachyos-x86_64"

# Récupération des arguments optionnels (mode CLI direct)
target_game_folder="${1:-}"
cli_level="${2:-}"

# Vérification de zenity et zstd
if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé sur le système."
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'zstd' n'est pas installé sur le système." 2>/dev/null
  exit 1
fi

if [ ! -d "$GAMES_DIR" ]; then
  zenity --error --text="Erreur : Le dossier '$GAMES_DIR' n'existe pas." 2>/dev/null
  exit 1
fi

lutris_db_path="$HOME/.local/share/lutris/pga.db"
[ -f "$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db" ] && lutris_db_path="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"

lutris_config_dir="$HOME/.config/lutris/games"
[ -d "$HOME/.var/app/net.lutris.Lutris/data/lutris/games" ] && lutris_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"

declare -A folder_by_name

# Mode CLI vs Mode Interactif
if [ -n "$target_game_folder" ]; then
  if [ ! -d "$GAMES_DIR/$target_game_folder" ]; then
    zenity --error --text="Le dossier de jeu '$target_game_folder' est introuvable dans '$GAMES_DIR'." 2>/dev/null
    exit 1
  fi
  
  game_real_name=""
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$lutris_db_path" ]; then
    game_real_name=$(sqlite3 "$lutris_db_path" "SELECT name FROM games WHERE slug='$target_game_folder' LIMIT 1;" 2>/dev/null)
  fi
  [ -z "$game_real_name" ] && game_real_name="$target_game_folder"

  games_to_export=("$game_real_name")
  folder_by_name["$game_real_name"]="$target_game_folder"
  LEVEL="${cli_level:-3}"
else
  shopt -s nullglob
  prefix_dirs=( "$GAMES_DIR"/*/ )
  if [ ${#prefix_dirs[@]} -eq 0 ]; then
    zenity --info --text="Aucun préfixe de jeu trouvé dans '$GAMES_DIR'." 2>/dev/null
    exit 0
  fi

  zenity_args=()
  for dir in "${prefix_dirs[@]}"; do
    folder_name=$(basename "$dir")
    game_real_name=""

    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$lutris_db_path" ]; then
      game_real_name=$(sqlite3 "$lutris_db_path" "SELECT name FROM games WHERE slug='$folder_name' LIMIT 1;" 2>/dev/null)
    fi

    if [ -z "$game_real_name" ]; then
      internal_game_dir=$(basename "$dir/drive_c/Games"/*/ 2>/dev/null)
      [ -n "$internal_game_dir" ] && [ "$internal_game_dir" != "*" ] && game_real_name="$internal_game_dir"
    fi

    [ -z "$game_real_name" ] && game_real_name="$folder_name"

    folder_by_name["$game_real_name"]="$folder_name"
    zenity_args+=( "FALSE" "$game_real_name" )
  done

  selected_games=$(zenity --list --checklist \
    --title="Exportateur de Préfixes Lutris" \
    --text="Sélectionnez le ou les jeux à exporter :" \
    --column="Exporter" --column="Nom du Jeu" \
    "${zenity_args[@]}" \
    --width=500 --height=400 2>/dev/null)

  [ -z "$selected_games" ] && exit 0

  IFS="|" read -r -a games_to_export <<< "$selected_games"

  LEVEL=3
  zenity --question \
    --title="Options de compression" \
    --text="Personnaliser le taux de compression ?" \
    --width=400 2>/dev/null

  if [ $? -eq 0 ]; then
    level_choice=$(zenity --scale \
      --title="Niveau de compression Zstandard" \
      --text="Choisissez le niveau de compression :\n(1 = Rapide | 3 = Défaut | 22 = Max/Lent)" \
      --min-value=1 --max-value=22 --value=3 --step=1 --width=400 2>/dev/null)
    [ $? -eq 0 ] && [ -n "$level_choice" ] && LEVEL="$level_choice"
  fi
fi

# Traitement de chaque jeu sélectionné
for game_real_name in "${games_to_export[@]}"; do
  WINEPREFIX_NAME="${folder_by_name[$game_real_name]}"
  WINEPREFIX_DIR="${GAMES_DIR}/${WINEPREFIX_NAME}"
  
  [ ! -d "$WINEPREFIX_DIR" ] && continue

  game_runner="$default_runner"
  cpu_limit=""
  configpath=""

  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$lutris_db_path" ]; then
    configpath=$(sqlite3 "$lutris_db_path" "SELECT configpath FROM games WHERE slug='$WINEPREFIX_NAME' LIMIT 1;" 2>/dev/null)
  fi

  ARCHIVE_NAME="$game_real_name"
  archive_path="${OUTPUT_DIR}/${ARCHIVE_NAME}.zgp"

  # Recherche robuste du sous-dossier de jeu interne
  GAME_DIR=$(basename "$(find "$WINEPREFIX_DIR/drive_c/Games" -maxdepth 1 -mindepth 1 -type d | head -n 1)")
  [ -z "$GAME_DIR" ] && GAME_DIR="$WINEPREFIX_NAME"

  ini_parent_dir="$WINEPREFIX_DIR/drive_c/Games/$GAME_DIR"
  goglog="$ini_parent_dir/goglog.ini"
  lutris_json="${WINEPREFIX_DIR}/lutris.json"

  if [ -f "$goglog" ]; then
    for user in "${user_array[@]}"; do
      sed -i "s|$user|anonuser|g" "$goglog"
    done
  fi

  if [ -f "$lutris_json" ]; then
    for user in "${user_array[@]}"; do
      sed -i "s|$user|anonuser|g" "$lutris_json"
    done
  fi

  # Nettoyage des liens symboliques et dossiers temporaires inutiles
  [ -d "${WINEPREFIX_DIR}/dosdevices" ] && rm -rf "${WINEPREFIX_DIR}/dosdevices"
  [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser" ] && unlink "${WINEPREFIX_DIR}/drive_c/users/steamuser"
  [ -L "${WINEPREFIX_DIR}/drive_c/users/${USER}" ] && unlink "${WINEPREFIX_DIR}/drive_c/users/${USER}"
  [ -d "${WINEPREFIX_DIR}/drive_c/users/${USER}" ] && mv -n "${WINEPREFIX_DIR}/drive_c/users/${USER}" "${WINEPREFIX_DIR}/drive_c/users/steamuser"
  [ -L "${WINEPREFIX_DIR}/pfx" ] && unlink "${WINEPREFIX_DIR}/pfx"

  for link_name in "Application Data" "Desktop" "Music" "Pictures" "Videos" "Documents" "My Documents" "Downloads"; do
    [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser/$link_name" ] && unlink "${WINEPREFIX_DIR}/drive_c/users/steamuser/$link_name"
  done

  [ -d "${WINEPREFIX_DIR}/drive_c/ProgramData/Package Cache/" ] && rm -rf -- "${WINEPREFIX_DIR}/drive_c/ProgramData/Package Cache/"*
  [ -d "${WINEPREFIX_DIR}/drive_c/users/steamuser/Temp" ] && rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser/Temp/"*
  [ -d "${WINEPREFIX_DIR}/drive_c" ] && mkdir -p "${WINEPREFIX_DIR}/drive_c/users/steamuser/Temp"

  find "${WINEPREFIX_DIR}/drive_c" -type l ! -exec test -e {} \; -delete
  find "${WINEPREFIX_DIR}/drive_c" -type l -exec bash -c 'target=$(readlink "{}"); rm "{}"; cp -r "$target" "{}"' \;
  find "${WINEPREFIX_DIR}/drive_c/windows/system32" -type f -name '*.orig' -delete
  find "${WINEPREFIX_DIR}/drive_c/windows/syswow64" -type f -name '*.orig' -delete

  for reg_file in "system.reg" "user.reg" "userdef.reg"; do
    if [ -f "${WINEPREFIX_DIR}/${reg_file}" ]; then
      for user in "${user_array[@]}"; do
        sed -i "s|${user}|anonuser|g" "${WINEPREFIX_DIR}/${reg_file}"
      done
    fi
  done

  # --- CRÉATION DU FICHIER MÊTA POUR LE VRAI NOM DU JEU ---
  python3 -c "
import json
meta = {'game_real_name': '''$game_real_name'''}
with open('${WINEPREFIX_DIR}/zgp-meta.json', 'w') as f:
    json.dump(meta, f)
" 2>/dev/null

  # --- EMBARQUEMENT PROPRE DU YAML LUTRIS (si disponible) ---
  if [ -n "$configpath" ] && [ -f "$lutris_config_dir/${configpath}.yml" ]; then
    cp "$lutris_config_dir/${configpath}.yml" "${WINEPREFIX_DIR}/zgp-game-config.yml"
    
    # Nettoyage et suppression du champ slug (mais conservation de game_slug)
    python3 -c "
import yaml, re
yml_path = '${WINEPREFIX_DIR}/zgp-game-config.yml'
try:
    with open(yml_path, 'r') as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        data.pop('script', None)
        data.pop('version', None)
        data.pop('slug', None)
        
        def clean_paths(obj):
            if isinstance(obj, dict):
                return {k: clean_paths(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [clean_paths(v) for v in obj]
            elif isinstance(obj, str):
                return re.sub(r'/home/[^/]+/', '/home/anonuser/', obj)
            return obj
            
        data = clean_paths(data)
        with open(yml_path, 'w') as f:
            yaml.dump(data, f, sort_keys=False)
except Exception as e:
    print(f'Erreur nettoyage YAML: {e}')
" 2>/dev/null
  fi
  # ---------------------------------------------------------

  source_size=$(du -sb "$WINEPREFIX_DIR" 2>/dev/null | cut -f1)
  [ -z "$source_size" ] && source_size=1
  
  estimated_percentage=$(( 85 - (LEVEL * 2) ))
  [ "$estimated_percentage" -lt 40 ] && estimated_percentage=40
  
  estimated_archive_size=$(( source_size * estimated_percentage / 100 ))
  [ "$estimated_archive_size" -le 0 ] && estimated_archive_size=1

  rm -f "$archive_path"

  (
    echo "20" ; sleep 0.4
    echo "# Analyse du préfixe et allocation de la mémoire..."
    echo "60" ; sleep 0.4
    echo "# Initialisation de la compression zstd (Niveau $LEVEL)..."
    echo "90" ; sleep 0.4
  ) | zenity --progress \
    --title="Préparation de $ARCHIVE_NAME" \
    --text="Initialisation en cours..." \
    --percentage=0 --auto-close --no-cancel 2>/dev/null

  if [ "$LEVEL" -gt 19 ]; then
    tar_cmd="tar -I \"zstd --ultra -$LEVEL\" -cvf \"$archive_path\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
  else
    tar_cmd="tar -I \"zstd -$LEVEL\" -cvf \"$archive_path\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
  fi

  bash -c "$tar_cmd" &
  tar_pid=$!

  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -f "$archive_path" ]; then
        current_archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
        [ -z "$current_archive_size" ] && current_archive_size=0

        percent=$(( current_archive_size * 100 / estimated_archive_size ))
        [ "$percent" -ge 99 ] && percent=99
        
        current_mb=$(( current_archive_size / 1024 / 1024 ))
        estimated_mb=$(( estimated_archive_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Compression de $ARCHIVE_NAME\nÉcrit : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
      fi
      sleep 0.3
    done
    echo "100"
    echo "# Finalisation de l'archive de $ARCHIVE_NAME..."
    sleep 0.5
  ) | zenity --progress \
    --title="Exportation de $ARCHIVE_NAME" \
    --text="Compression du préfixe (Niveau $LEVEL)..." \
    --percentage=0 --auto-close 2>/dev/null

  zenity_status=$?

  # Nettoyage des fichiers temporaires embarqués avant la fin
  rm -f "${WINEPREFIX_DIR}/zgp-game-config.yml"
  rm -f "${WINEPREFIX_DIR}/zgp-meta.json"

  if [ $zenity_status -ne 0 ]; then
    pkill -P $tar_pid 2>/dev/null
    kill -9 $tar_pid 2>/dev/null
    rm -f "$archive_path"
    zenity --info --title="Annulation" --text="L'exportation de $ARCHIVE_NAME a été annulée." 2>/dev/null
    exit 0
  fi

  wait $tar_pid
  if [ $? -ne 0 ]; then
    zenity --error --text="Une erreur est survenue lors de la compression de $ARCHIVE_NAME." 2>/dev/null
    exit 1
  fi

done

notify-send "Exportation terminée" "Tous les jeux sélectionnés ont été exportés avec succès au format .zgp !" 2>/dev/null
exit 0
