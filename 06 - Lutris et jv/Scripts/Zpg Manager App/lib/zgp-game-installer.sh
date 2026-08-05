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

# Récupération dynamique du runner par défaut global de Lutris
default_runner=""
for runners_path in "$HOME/.local/share/lutris/runners/wine.yml" "$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml" "$HOME/.config/lutris/runners/wine.yml"; do
    if [ -f "$runners_path" ]; then
        default_runner=$(awk -F': ' '/^\s*version:/ {print $2; exit}' "$runners_path" | tr -d '"''[:space:]')
        [ -n "$default_runner" ] && break
    fi
done
# Fallback ultime si aucun fichier n'est trouvé
[ -z "$default_runner" ] && default_runner="proton-cachyos-x86_64"

# Répertoire du script courant pour localiser les autres scripts associés proprement
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Détermination du dossier de recherche
search_dir="."
if [ -n "${1:-}" ]; then
    if [ -f "$1" ]; then
        search_dir="$(dirname "$1")"
    else
        zenity --error --text="Le fichier spécifié est introuvable :
$1" 2>/dev/null
        exit 1
    fi
else
    selected_file=$(zenity --file-selection         --title="Sélectionner un jeu (.zgp)"         --file-filter="Archives ZGP (*.zgp) | *.zgp" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$selected_file" ]; then
        exit 0
    fi
    search_dir="$(dirname "$selected_file")"
fi

# Recherche de tous les fichiers .zgp dans le répertoire identifié
shopt -s nullglob
zgp_files=("$search_dir"/*.zgp)

if [ ${#zgp_files[@]} -eq 0 ]; then
    zenity --info --text="Aucun fichier de jeu (.zgp) trouvé dans le répertoire." 2>/dev/null
    exit 0
fi

zenity_args=()
declare -A filepath_by_name
declare -A runner_by_name
declare -A cpu_by_name

for file in "${zgp_files[@]}"; do
  filename=$(basename "$file")
  
  # Dossier temporaire unique et isolé pour CETTE archive
  file_meta_dir=$(mktemp -d)
  
  # Extraction exclusive du zgp-meta.json de cette archive
  tar -I zstd -xf "$file" -C "$file_meta_dir" --wildcards "*/zgp-meta.json" 2>/dev/null
  meta_json=$(find "$file_meta_dir" -type f -name "zgp-meta.json" -print -quit)
  
  game_real_name=""
  extracted_runner=""
  cpu_limit=""

  if [ -n "$meta_json" ] && [ -f "$meta_json" ]; then
    if command -v python3 >/dev/null 2>&1; then
      game_real_name=$(python3 -c "import json; data=json.load(open('$meta_json')); print(data.get('game_real_name', ''))" 2>/dev/null)
      extracted_runner=$(python3 -c "import json; data=json.load(open('$meta_json')); print(data.get('game_runner', ''))" 2>/dev/null)
      cpu_limit=$(python3 -c "import json; data=json.load(open('$meta_json')); print(data.get('cpu_limit') or '')" 2>/dev/null)
    else
      game_real_name=$(grep -o '"game_real_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_json" | cut -d'"' -f4)
      extracted_runner=$(grep -o '"game_runner"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_json" | cut -d'"' -f4)
      extracted_c=$(grep -o '"cpu_limit"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_json" | cut -d'"' -f4)
      [ -n "$extracted_c" ] && cpu_limit="$extracted_c"
    fi
  fi

  # Nettoyage immédiat du dossier temporaire de cette archive
  rm -rf "$file_meta_dir"

  # Fallback si le JSON est absent ou vide
  if [ -z "$game_real_name" ]; then
    game_real_name=$(basename "$file" .zgp)
  fi

  # Priorité absolue au runner trouvé dans le JSON, sinon runner par défaut de Lutris
  if [ -n "$extracted_runner" ]; then
    runner="$extracted_runner"
  else
    runner="$default_runner"
  fi

  filepath_by_name["$game_real_name"]="$file"
  runner_by_name["$game_real_name"]="$runner"
  cpu_by_name["$game_real_name"]="$cpu_limit"

  display_info="$runner"
  [ -n "$cpu_limit" ] && display_info="$display_info, $cpu_limit"

  zenity_args+=( "TRUE" "$game_real_name" "$display_info" )
done

# 4. Fenêtre de sélection des options de raccourcis (cochés par défaut)
shortcuts_options=$(zenity --list --checklist   --title="Options de création des lanceurs"   --text="Où souhaitez-vous créer les raccourcis ?"   --column="Créer" --column="Emplacement"   TRUE "Menu des applications"   TRUE "Raccourci sur le Bureau"   --width=500 --height=220 2>/dev/null)

create_menu=false
create_desktop=false

if [[ "$shortcuts_options" =~ "Menu des applications" ]]; then
  create_menu=true
fi
if [[ "$shortcuts_options" =~ "Raccourci sur le Bureau" ]]; then
  create_desktop=true
fi

# 5. Affichage de la fenêtre de sélection des jeux avec Checkboxes (élargie)
selected_games=$(zenity --list --checklist   --title="Zgp-Installer"   --text="Sélectionnez les jeux à importer :"   --column="Installer" --column="Jeu" --column="Configuration"   "${zenity_args[@]}"   --width=700 --height=400 2>/dev/null)

if [ -z "$selected_games" ]; then
  exit 0
fi

IFS="|" read -r -a games_to_install <<< "$selected_games"

# ---------------------------------------------------------------------------------------------

# Traitement de chaque jeu sélectionné
for name in "${games_to_install[@]}"; do
  filepath="${filepath_by_name[$name]}"
  runner="${runner_by_name[$name]}"
  cpu_limit="${cpu_by_name[$name]}"

  # Génération d'un identifiant unique par itération pour éviter les collisions simultanées
  slug=$(tar -I zstd -tf "$filepath" | grep '/' | head -n 1 | cut -d'/' -f1)
  timestamp=$(date +%s%N)
  config_id="${slug}-${timestamp}"
  prefix_dir="$games_dir/$slug"

  # 1. Vérification / Installation du runner via Zgr-Runner-Installer.sh s'il est absent
  if [ ! -d "$lutris_runner_dir/$runner" ]; then
    runner_installer="$SCRIPT_DIR/zgr-runner-installer.sh"
    [ ! -f "$runner_installer" ] && runner_installer="$SCRIPT_DIR/zgr-runner-installer.sh"

    if [ -f "$runner_installer" ]; then
      bash "$runner_installer" "$runner"
    else
      zenity --error --text="Le runner '$runner' est introuvable et le script d'installation de runner est absent." 2>/dev/null
      exit 1
    fi
  fi

  # 2. Extraction du jeu avec calcul de taille estimée et bouton Annuler actif
  mkdir -p "$games_dir"

  archive_size=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)
  [ -z "$archive_size" ] && archive_size=1
  estimated_uncompressed_size=$(( archive_size * 3 ))
  [ "$estimated_uncompressed_size" -le 0 ] && estimated_uncompressed_size=1

  tar -I zstd -xf "$filepath" -C "$games_dir" &
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
        estimated_mb=$(( estimated_uncompressed_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Extraction de $name
Extraits : ${current_mb} Mo / ~${estimated_mb} Mo estimés"
      fi
      sleep 0.2
    done

    echo "100"
    echo "# Finalisation de l'extraction de $name..."
    sleep 0.5
  ) | zenity --progress     --title="Importation de $name"     --text="Début de l'extraction..."     --percentage=0     --auto-close     --width=500 2>/dev/null

  zenity_status=$?

  if [ $zenity_status -ne 0 ]; then
    pkill -P $tar_pid 2>/dev/null
    kill -9 $tar_pid 2>/dev/null
    rm -rf "$prefix_dir"
    zenity --info --title="Annulation" --text="L'importation de $name a été annulée et le dossier nettoyé." 2>/dev/null
    exit 0
  fi

  wait $tar_pid
  if [ $? -ne 0 ]; then
    zenity --error --text="Une erreur est survenue lors de l'extraction de $name." 2>/dev/null
    exit 1
  fi

  # Nettoyage préventif du zgp-meta.json éventuellement extrait dans le préfixe
  rm -f "${prefix_dir}/zgp-meta.json"

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

  # 6. Insertion SQLite sécurisée contre les apostrophes
  safe_name=$(echo "$name" | sed "s/'/''/g")

  sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$slug';"
  sqlite3 "$lutris_db" <<EOF
INSERT INTO games (name, slug, installer_slug, parent_slug, runner, executable, directory, configpath, updated, installed, installed_at)
VALUES (
  '$safe_name',
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

  # 7. Config YML avec support CPU
  yml_config_file="$lutris_config_dir/${config_id}.yml"
  cat > "$yml_config_file" <<EOL
game:
  exe: drive_c/Games/$gamefolder/Launch.bat
  prefix: $prefix_dir
wine:
  version: $runner
EOL

  # Injection des options système si scripts, gamepad ou limite CPU présents
  if [ "$preload_script" = true ] || [ "$gamepad" = true ] || [ -n "$cpu_limit" ]; then
    echo "system:" >> "$yml_config_file"
    
    if [ -n "$cpu_limit" ]; then
      cpu_num="${cpu_limit#c}"
      if [ "$cpu_num" = "1" ]; then
        echo "  single_cpu: true" >> "$yml_config_file"
      else
        echo "  limit_cpu_count: '$cpu_num'" >> "$yml_config_file"
        echo "  single_cpu: true" >> "$yml_config_file"
      fi
    fi

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
    echo "$shortcut_content" > "$desktop_dir/${name}.desktop"
    chmod +x "$desktop_dir/${name}.desktop"
    gio set "$desktop_dir/${name}.desktop" metadata::trusted true 2>/dev/null || true

    extras_path=""
    if [ -d "$prefix_dir/extras" ]; then
      extras_path="$prefix_dir/extras"
    elif [ -n "$(find "$prefix_dir" -maxdepth 2 -type d -iname "extras" -print -quit 2>/dev/null)" ]; then
      extras_path="$(find "$prefix_dir" -maxdepth 2 -type d -iname "extras" -print -quit 2>/dev/null)"
    fi

    if [ -n "$extras_path" ]; then
      rm -rf "$desktop_dir/${name} Bonus"
      ln -s "$extras_path" "$desktop_dir/${name} Bonus"
    fi
  fi
done

notify-send "Installation terminée" "Tous les jeux sélectionnés ont été importés avec succès !" 2>/dev/null
exit 0
