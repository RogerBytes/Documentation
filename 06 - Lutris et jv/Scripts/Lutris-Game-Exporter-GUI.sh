#!/bin/bash

# Configuration des chemins et variables de base
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${HOME}"
GAMES_DIR="${HOME}/Games"
user_array=("$USER" "johndoe")

# Vérification de zenity et zstd
if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé sur le système."
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'zstd' n'est pas installé sur le système." 2>/dev/null
  exit 1
fi

# 1. Vérifie si le dossier Games existe
if [ ! -d "$GAMES_DIR" ]; then
  zenity --error --text="Erreur : Le dossier '$GAMES_DIR' n'existe pas." 2>/dev/null
  exit 1
fi

# Chemins possibles de la base de données Lutris
lutris_db_path="$HOME/.local/share/lutris/pga.db"
[ -f "$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db" ] && lutris_db_path="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"

# 2. Récupération de la liste des dossiers dans ~/Games et association avec le vrai nom du jeu
shopt -s nullglob
prefix_dirs=( "$GAMES_DIR"/*/ )
if [ ${#prefix_dirs[@]} -eq 0 ]; then
  zenity --info --text="Aucun préfixe de jeu trouvé dans '$GAMES_DIR'." 2>/dev/null
  exit 0
fi

zenity_args=()
declare -A folder_by_name

for dir in "${prefix_dirs[@]}"; do
  folder_name=$(basename "$dir")
  game_real_name=""

  # Recherche dans la base de données Lutris
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$lutris_db_path" ]; then
    game_real_name=$(sqlite3 "$lutris_db_path" "SELECT name FROM games WHERE slug='$folder_name' LIMIT 1;" 2>/dev/null)
  fi

  # Sinon, on regarde le nom du dossier interne dans drive_c/Games/
  if [ -z "$game_real_name" ]; then
    internal_game_dir=$(basename "$dir/drive_c/Games"/*/ 2>/dev/null)
    if [ -n "$internal_game_dir" ] && [ "$internal_game_dir" != "*" ]; then
      game_real_name="$internal_game_dir"
    fi
  fi

  # Fallback ultime sur le nom du dossier si rien d'autre n'est trouvé
  [ -z "$game_real_name" ] && game_real_name="$folder_name"

  folder_by_name["$game_real_name"]="$folder_name"
  zenity_args+=( "FALSE" "$game_real_name" )
done

# Fenêtre de sélection des jeux à exporter (affiche le nom des jeux)
selected_games=$(zenity --list --checklist \
  --title="Exportateur de Préfixes Lutris" \
  --text="Sélectionnez le ou les jeux à exporter :" \
  --column="Exporter" --column="Nom du Jeu" \
  "${zenity_args[@]}" \
  --width=500 --height=400 2>/dev/null)

if [ -z "$selected_games" ]; then
  exit 0
fi

IFS="|" read -r -a games_to_export <<< "$selected_games"

# 3. Demande facultative pour personnaliser le taux de compression
LEVEL=3 # Valeur par défaut

zenity --question \
  --title="Options de compression" \
  --text="Personnaliser le taux de compression ?" \
  --width=400 2>/dev/null

# Si l'utilisateur clique sur "Oui" (code de retour 0)
if [ $? -eq 0 ]; then
  level_choice=$(zenity --scale \
    --title="Niveau de compression Zstandard" \
    --text="Choisissez le niveau de compression :\n(1 = Rapide | 3 = Défaut | 22 = Max/Lent)\n\nAttention : Les niveaux supérieurs à 15 nécessitent beaucoup de RAM." \
    --min-value=1 \
    --max-value=22 \
    --value=3 \
    --step=1 \
    --width=400 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$level_choice" ]; then
    LEVEL="$level_choice"
  fi
fi

# 4. Traitement de chaque jeu sélectionné
for game_real_name in "${games_to_export[@]}"; do
  WINEPREFIX_NAME="${folder_by_name[$game_real_name]}"
  WINEPREFIX_DIR="${GAMES_DIR}/${WINEPREFIX_NAME}"
  
  if [ ! -d "$WINEPREFIX_DIR" ]; then
    continue
  fi

  ARCHIVE_NAME="$game_real_name"
  archive_path="${OUTPUT_DIR}/${ARCHIVE_NAME}.tzst"

  # Nettoyage et anonymisation du préfixe avant l'export
  GAME_DIR=$(basename "$WINEPREFIX_DIR/drive_c/Games"/*/)
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

  # Nettoyage des liens symboliques et dossiers temporaires
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
  [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates" ] && unlink "${WINEPREFIX_DIR}/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates"

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

  # Calcul de la taille du préfixe source pour évaluer la taille finale de l'archive
  source_size=$(du -sb "$WINEPREFIX_DIR" 2>/dev/null | cut -f1)
  [ -z "$source_size" ] && source_size=1
  estimated_archive_size=$(( source_size * 35 / 100 ))
  [ "$estimated_archive_size" -le 0 ] && estimated_archive_size=1

  # Suppression d'une ancienne archive si elle existe déjà
  rm -f "$archive_path"

  # Construction de la commande de compression Zst avec le niveau choisi
  if [ "$LEVEL" -gt 19 ]; then
    tar_cmd="tar -I \"zstd -ultra -$LEVEL\" -cvf \"$archive_path\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
  else
    tar_cmd="tar -I \"zstd -$LEVEL\" -cvf \"$archive_path\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
  fi

  # Lancement de la compression en arrière-plan
  bash -c "$tar_cmd" &
  tar_pid=$!

  # Boucle de suivi par la barre de progression Zenity
  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -f "$archive_path" ]; then
        current_archive_size=$(stat -c%s "$archive_path" 2>/dev/null || stat -f%z "$archive_path" 2>/dev/null)
        [ -z "$current_archive_size" ] && current_archive_size=0

        percent=$(( current_archive_size * 100 / estimated_archive_size ))
        if [ "$percent" -ge 99 ]; then
          percent=99
        fi
        
        current_mb=$(( current_archive_size / 1024 / 1024 ))
        echo "$percent"
        echo "# Compression de $ARCHIVE_NAME ($current_mb Mo écrits)..."
      fi
      sleep 0.3
    done

    echo "100"
    echo "# Finalisation de l'archive de $ARCHIVE_NAME..."
    sleep 0.5
  ) | zenity --progress \
    --title="Exportation de $ARCHIVE_NAME" \
    --text="Préparation de la compression (Niveau $LEVEL)..." \
    --percentage=0 \
    --auto-close \
    --no-cancel 2>/dev/null

  wait $tar_pid
  if [ $? -ne 0 ]; then
    zenity --error --text="Une erreur est survenue lors de la compression de $ARCHIVE_NAME." 2>/dev/null
    exit 1
  fi

done

zenity --info --title="Exportation terminée" --text="Tous les jeux sélectionnés ont été exportés avec succès au format .tzst dans $OUTPUT_DIR !" 2>/dev/null
exit 0
