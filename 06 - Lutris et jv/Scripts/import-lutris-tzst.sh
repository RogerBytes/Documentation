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

declare -A runners_map
declare -A names_map
declare -A files_map

# 1. Vérification de la commande sqlite3
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo -e "\033[31mErreur : 'sqlite3' n'est pas installé. Installez-le avec votre gestionnaire de paquets.\033[0m"
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
  echo "Lutris n'est pas installé. Fermeture du programme."
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
  echo "Aucun fichier de préfixe au format .tzst trouvé."
  exit 1
fi

index=1
for file in "${tzst_files[@]}"; do
  filename=$(basename "$file")
  name=$(basename "$file" .tzst)
  if [[ "$name" =~ \[(.*?)\] ]]; then
    runner="${BASH_REMATCH[1]}"
    name=$(echo "$name" | sed -E 's/\s*\[.*?\]\s*//g')
  else
    runner="$default_runner"
  fi
  files_map[$index]="$filename"
  names_map[$index]="$name"
  runners_map[$index]="$runner"
  ((index++))
done

# ---------------------------------------------------------------------------------------------

# Traitement et importation
for i in "${!names_map[@]}"; do
  filename="${files_map[$i]}"
  name="${names_map[$i]}"
  runner="${runners_map[$i]}"
  
  # Détection du slug
  slug=$(tar -I zstd -tf "./$filename" | grep '/' | head -n 1 | cut -d'/' -f1)
  
  # Timestamp pour le configpath
  timestamp=$(date +%s)
  config_id="${slug}-${timestamp}"
  
  gamepad=false
  preload_script=false
  prefix_dir="$games_dir/$slug"

  echo "Importation de '$name' ($slug)..."

  # 1. Extraction de l'archive
  mkdir -p "$games_dir"
  tar -I zstd -xvf "./$filename" -C "$games_dir"
  if [ $? -ne 0 ]; then
    echo "Erreur lors de l'extraction de $filename."
    exit 1
  fi

  # 2. Anonymisation inverse (anonuser -> $USER)
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

  # 3. Restauration des liens UMU / Proton (dosdevices/c: & pfx)
  mkdir -p "${prefix_dir}/dosdevices"
  ln -sf "../drive_c" "${prefix_dir}/dosdevices/c:"
  if [ ! -e "${prefix_dir}/pfx" ]; then
    ln -sf "." "${prefix_dir}/pfx"
  fi

  # 4. Détection scripts/gamepad
  if [ -d "$prefix_dir/scripts" ]; then
    gamepad_file=$(find "$prefix_dir/scripts" -type f -name "*.amgp" -print -quit)
    start_file=$(find "$prefix_dir/scripts" -type f -name "start.sh" -print -quit)

    if [ -n "$gamepad_file" ]; then
      gamepad=true
    fi
    if [ -n "$start_file" ]; then
      preload_script=true
    fi
  fi

  # 5. Nettoyage des anciennes configs YML du même slug
  rm -f "$lutris_config_dir/${slug}-"*.yml

  # 6. Insertion SQLite dans pga.db
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

  # 7. Écriture directe du YML ($config_id.yml)
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

  # 8. Recherche de l'icône dans le dossier icon/ du préfixe
  icon_file=$(find "$prefix_dir/icon" -type f \( -name "*.png" -o -name "*.ico" -o -name "*.svg" -o -name "*.xpm" \) 2>/dev/null | head -n 1)

  if [ -n "$icon_file" ]; then
    icon_path="$icon_file"
  else
    icon_path="lutris_${slug}"
  fi

  # 9. Génération exacte des raccourcis Lutris (.desktop)
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

  # Menu des applications
  mkdir -p "$HOME/.local/share/applications"
  echo "$shortcut_content" > "$HOME/.local/share/applications/net.lutris.${slug}-${game_id}.desktop"

  # Bureau
  if [ -d "$desktop_dir" ]; then
    echo "$shortcut_content" > "$desktop_dir/${name}.desktop"
    chmod +x "$desktop_dir/${name}.desktop"
    gio set "$desktop_dir/${name}.desktop" metadata::trusted true 2>/dev/null || true
  fi

  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

  echo -e "\e[32m[OK] $name importé (ID: $game_id) et raccourcis créés avec l'icône : $icon_path !\e[0m"
done

echo -e "\e[32mImportation terminée avec succès !\e[0m"
