#!/bin/bash

# Configuration des chemins
lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

lutris_flatpak_db="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="$HOME/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="$HOME/.config/lutris/games"

lutris_flatpak_option_file="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml"
lutris_package_option_file="$HOME/.config/lutris/runners/wine.yml"

games_dir="$HOME/Games"
default_runner="proton-cachyos-11.0-x86_64"

# 1. Vérification des dépendances (sqlite3 et zenity)
if ! command -v sqlite3 >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'sqlite3' n'est pas installé sur le système." 2>/dev/null || echo "Erreur : sqlite3 manquant."
  exit 1
fi

if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé pour l'interface graphique."
  exit 1
fi

# 2. Fermeture préalable de Lutris pour libérer la BDD
if flatpak list 2>/dev/null | grep -q lutris; then
  flatpak kill net.lutris.Lutris 2>/dev/null
fi
pkill -9 -x lutris 2>/dev/null
pkill -9 -f "/usr/bin/lutris" 2>/dev/null

# 3. Détection Flatpak vs Paquet natif
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  version="flatpak"
elif command -v lutris >/dev/null 2>&1; then
  version="package"
else
  zenity --error --text="Lutris n'est pas installé sur le système."
  exit 1
fi

case "$version" in
  flatpak)
    lutris_runner_dir="$lutris_flatpak_runner_dir"
    lutris_option_file="$lutris_flatpak_option_file"
    lutris_config_dir="$lutris_flatpak_config_dir"
    lutris_db="$lutris_flatpak_db"
    ;;
  package)
    lutris_runner_dir="$lutris_package_runner_dir"
    lutris_option_file="$lutris_package_option_file"
    lutris_config_dir="$lutris_package_config_dir"
    lutris_db="$lutris_package_db"
    ;;
esac

# Chemin Games personnalisé (si défini dans Lutris)
if [ -f "$lutris_option_file" ]; then
  extracted_path=$(awk -F': ' '/^\s*game_path:/ {print $2}' "$lutris_option_file")
  if [ -n "$extracted_path" ]; then
    games_dir="$extracted_path"
  fi
fi

mkdir -p "$lutris_config_dir"
mkdir -p "$(dirname "$lutris_db")"

# ---------------------------------------------------------------------------------------------

# Recherche des archives .tzst
shopt -s nullglob
tzst_files=( ./*.tzst )
if [ ${#tzst_files[@]} -eq 0 ]; then
  zenity --info --text="Aucun fichier de jeu (.tzst) trouvé dans ce dossier."
  exit 0
fi

# Préparation de la liste Zenity des jeux
zenity_args=()
declare -A file_by_name
declare -A runner_by_name

for file in "${tzst_files[@]}"; do
  filename=$(basename "$file")
  name=$(basename "$file" .tzst)
  if [[ "$name" =~ \[(.*?)\] ]]; then
    runner="${BASH_REMATCH[1]}"
    name=$(echo "$name" | sed -E 's/\s*\[.*?\]\s*//g')
  else
    runner="$default_runner"
  fi
  
  file_by_name["$name"]="$filename"
  runner_by_name["$name"]="$runner"
  
  zenity_args+=( "TRUE" "$name" "$runner" )
done

# 4. Fenêtre de sélection des options de raccourcis (cochés par défaut)
shortcuts_options=$(zenity --list --checklist \
  --title="Options de création des lanceurs" \
  --text="Où souhaitez-vous créer les raccourcis ?" \
  --column="Créer" --column="Emplacement" \
  TRUE "Menu des applications" \
  TRUE "Raccourci sur le Bureau" \
  --width=500 --height=220 2>/dev/null)

create_menu=false
create_desktop=false

if [[ "$shortcuts_options" =~ "Menu des applications" ]]; then
  create_menu=true
fi
if [[ "$shortcuts_options" =~ "Raccourci sur le Bureau" ]]; then
  create_desktop=true
fi

# 5. Affichage de la fenêtre de sélection des jeux avec Checkboxes
selected_games=$(zenity --list --checklist \
  --title="Importateur Lutris" \
  --text="Sélectionnez les jeux à importer :" \
  --column="Installer" --column="Jeu" --column="Runner" \
  "${zenity_args[@]}" \
  --width=600 --height=400 2>/dev/null)

if [ -z "$selected_games" ]; then
  exit 0
fi

IFS="|" read -r -a games_to_install <<< "$selected_games"

# ---------------------------------------------------------------------------------------------

# Traitement de chaque jeu sélectionné
for name in "${games_to_install[@]}"; do
  filename="${file_by_name[$name]}"
  runner="${runner_by_name[$name]}"

  # 1. Vérification / Installation du runner
  if [ ! -d "$lutris_runner_dir/$runner" ]; then
    if [ -f "./resources/$runner.tzst" ]; then
      tar -I zstd -xvf "./resources/$runner.tzst" -C "$lutris_runner_dir" 2>&1 | \
      zenity --progress --title="Installation du Runner" \
        --text="Extraction locale du runner $runner..." --pulsate --auto-close --no-cancel 2>/dev/null
    else
      temp_dir=$(mktemp -d)
      wget "https://github.com/RogerBytes/Mintage/releases/download/wine-pkg/$runner.tzst" -O "$temp_dir/$runner.tzst" 2>&1 | \
      zenity --progress --title="Téléchargement du Runner" \
        --text="Téléchargement du runner $runner..." --pulsate --auto-close --no-cancel 2>/dev/null
      mkdir -p "$lutris_runner_dir"
      tar -I zstd -xvf "$temp_dir/$runner.tzst" -C "$lutris_runner_dir" 2>&1 | \
      zenity --progress --title="Installation du Runner" \
        --text="Extraction du runner $runner..." --pulsate --auto-close --no-cancel 2>/dev/null
      rm -rf "$temp_dir"
    fi
  fi

  # 2. Extraction du jeu avec calcul de taille dynamique en temps réel
  slug=$(tar -I zstd -tf "./$filename" | grep '/' | head -n 1 | cut -d'/' -f1)
  timestamp=$(date +%s)
  config_id="${slug}-${timestamp}"
  prefix_dir="$games_dir/$slug"

  mkdir -p "$games_dir"

  archive_size=$(stat -c%s "./$filename" 2>/dev/null || stat -f%z "./$filename" 2>/dev/null)
  estimated_uncompressed_size=$(( archive_size * 3 ))

  tar -I zstd -xf "./$filename" -C "$games_dir" &
  tar_pid=$!

  (
    while kill -0 $tar_pid 2>/dev/null; do
      if [ -d "$prefix_dir" ]; then
        current_size=$(du -sb "$prefix_dir" 2>/dev/null | cut -f1)
        [ -z "$current_size" ] && current_size=0

        percent=$(( current_size * 100 / estimated_uncompressed_size ))
        if [ "$percent" -ge 99 ]; then
          percent=99
        fi
        
        current_mb=$(( current_size / 1024 / 1024 ))
        echo "$percent"
        echo "# Extraction de $name ($current_mb Mo extraits)..."
      fi
      sleep 0.2
    done

    echo "100"
    echo "# Finalisation de l'extraction de $name..."
    sleep 0.5
  ) | zenity --progress \
    --title="Importation de $name" \
    --text="Début de l'extraction..." \
    --percentage=0 \
    --auto-close \
    --no-cancel 2>/dev/null

  wait $tar_pid
  if [ $? -ne 0 ]; then
    zenity --error --text="Une erreur est survenue lors de l'extraction de $name." 2>/dev/null
    exit 1
  fi

  # 3. Anonymisation inverse (anonuser -> $USER)
  for reg in "system.reg" "user.reg" "userdef.reg" "lutris.json"; do
    if [ -f "${prefix_dir}/${reg}" ]; then
      sed -i "s|anonuser|${USER}|g" "${prefix_dir}/${reg}"
    fi
  done

  gamefolder=$(basename "$prefix_dir/drive_c/Games/"*/)
  ini_parent_dir="$prefix_dir/drive_c/Games/$gamefolder"
  goglog="$ini_parent_dir/goglog.ini"
  if [ -f "$goglog" ]; then
    sed -i "s|anonuser|${USER}|g" "$goglog"
  fi

  # 4. Liens Proton/UMU
  mkdir -p "${prefix_dir}/dosdevices"
  ln -sf "../drive_c" "${prefix_dir}/dosdevices/c:"
  if [ ! -e "${prefix_dir}/pfx" ]; then
    ln -sf "." "${prefix_dir}/pfx"
  fi

  # 5. Scripts / Gamepad
  gamepad=false
  preload_script=false
  if [ -d "$prefix_dir/scripts" ]; then
    gamepad_file=$(find "$prefix_dir/scripts" -type f -name "*.amgp" -print -quit)
    start_file=$(find "$prefix_dir/scripts" -type f -name "start.sh" -print -quit)
    [ -n "$gamepad_file" ] && gamepad=true
    [ -n "$start_file" ] && preload_script=true
  fi

  rm -f "$lutris_config_dir/${slug}-"*.yml

  # 6. Insertion SQLite
  sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$slug';"
  sqlite3 "$lutris_db" <<EOF
INSERT INTO games (name, slug, installer_slug, parent_slug, runner, executable, directory, configpath, updated, installed, installed_at)
VALUES (
  '$name',
  '$slug',
  '$slug',
  '',
  'wine',
  '$prefix_dir/drive_c/Games/$gamefolder/Launch.bat',
  '$prefix_dir',
  '$config_id',
  strftime('%s','now'),
  1,
  strftime('%s','now')
);
EOF

  # 7. Config YML
  yml_config_file="$lutris_config_dir/${config_id}.yml"
  cat > "$yml_config_file" <<EOL
game:
  exe: drive_c/Games/$gamefolder/Launch.bat
  prefix: $prefix_dir
wine:
  version: $runner
EOL

  if [ "$preload_script" = true ] || [ "$gamepad" = true ]; then
    echo "system:" >> "$yml_config_file"
    if [ "$preload_script" = true ]; then
      echo "  prelaunch_command: $prefix_dir/scripts/start.sh" >> "$yml_config_file"
      echo "  postexit_command: $prefix_dir/scripts/stop.sh" >> "$yml_config_file"
      echo "  locale: ''" >> "$yml_config_file"
    fi
    if [ "$gamepad" = true ]; then
      echo "  antimicro_config: $gamepad_file" >> "$yml_config_file"
    fi
  fi

  # 8. Recherche Icône dans icon/
  icon_file=$(find "$prefix_dir/icon" -type f \( -name "*.png" -o -name "*.ico" -o -name "*.svg" -o -name "*.xpm" \) 2>/dev/null | head -n 1)
  if [ -n "$icon_file" ]; then
    icon_path="$icon_file"
  else
    icon_path="lutris_${slug}"
  fi

  # 9. Raccourcis .desktop (selon les options cochées par l'utilisateur)
  game_id=$(sqlite3 "$lutris_db" "SELECT id FROM games WHERE slug='$slug';")
  desktop_dir="$HOME/Desktop"
  [ -d "$HOME/Bureau" ] && desktop_dir="$HOME/Bureau"

  if [ "$version" = "flatpak" ]; then
    exec_cmd="env LUTRIS_SKIP_INIT=1 flatpak run net.lutris.Lutris lutris:rungameid/$game_id"
  else
    exec_cmd="env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/$game_id"
  fi

  shortcut_content="[Desktop Entry]
Type=Application
Name=$name
Icon=$icon_path
Exec=$exec_cmd
Categories=Game"

  # A. Création dans le Menu des applications (si coché)
  if [ "$create_menu" = true ]; then
    mkdir -p "$HOME/.local/share/applications"
    echo "$shortcut_content" > "$HOME/.local/share/applications/net.lutris.${slug}-${game_id}.desktop"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  fi

  # B. Création sur le Bureau (si coché)
  if [ "$create_desktop" = true ] && [ -d "$desktop_dir" ]; then
    # 1. Création du lanceur principal du jeu sur le bureau
    echo "$shortcut_content" > "$desktop_dir/${name}.desktop"
    chmod +x "$desktop_dir/${name}.desktop"
    gio set "$desktop_dir/${name}.desktop" metadata::trusted true 2>/dev/null || true

    # 2. Vérification et création du VRAI LIEN SYMBOLIQUE vers le dossier "extras" à la racine du préfixe
    extras_path=""
    if [ -d "$prefix_dir/extras" ]; then
      extras_path="$prefix_dir/extras"
    elif [ -n "$(find "$prefix_dir" -maxdepth 2 -type d -iname "extras" -print -quit 2>/dev/null)" ]; then
      extras_path="$(find "$prefix_dir" -maxdepth 2 -type d -iname "extras" -print -quit 2>/dev/null)"
    fi

    if [ -n "$extras_path" ]; then
      # Supprime un éventuel ancien lien ou fichier du même nom avant de le créer
      rm -rf "$desktop_dir/${name} Bonus"
      # Crée un lien symbolique direct pointant vers le dossier extras à la racine du préfixe
      ln -s "$extras_path" "$desktop_dir/${name} Bonus"
    fi
  fi
done

zenity --info --title="Installation terminée" --text="Tous les jeux sélectionnés ont été importés avec succès !" 2>/dev/null
