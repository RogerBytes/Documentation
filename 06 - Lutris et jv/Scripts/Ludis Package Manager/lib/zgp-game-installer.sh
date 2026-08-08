#!/bin/bash

# --- Analyse robuste des arguments (CLI, Double-clic et flags) ---
confirm_flag="$1"
shift
cli_targets=("$@")
is_double_click=false

# Si le premier argument reçu de bin/lpm est vide ou qu'aucun argument de fichier n'est présent
if [ -z "$confirm_flag" ] && [ ${#cli_targets[@]} -eq 1 ] && [ ! -t 0 ]; then
    is_double_click=true
fi

# Configuration des chemins
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
        default_runner=$(awk -F': ' '/^\s*version:/ {print $2; exit}' "$runners_path" | tr -d '"'\''[:space:]')
        [ -n "$default_runner" ] && break
    fi
done
[ -z "$default_runner" ] && default_runner="proton-cachyos-x86_64"

# 1. Vérification des dépendances (sqlite3, zenity et pv)
for cmd in sqlite3 zenity pv; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Erreur : '$cmd' n'est pas installé sur le système."
    exit 1
  fi
done

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
  zenity --error --text="Lutris n'est pas installé sur le système." 2>/dev/null
  echo "Erreur : Lutris n'est pas installé sur le système."
  exit 1
fi

case "$version" in
  flatpak)
    lutris_config_dir="$lutris_flatpak_config_dir"
    lutris_db="$lutris_flatpak_db"
    lutris_option_file="$lutris_flatpak_option_file"
    ;;
  package)
    lutris_config_dir="$lutris_package_config_dir"
    lutris_db="$lutris_package_db"
    lutris_option_file="$lutris_package_option_file"
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
mkdir -p "$games_dir"

# ---------------------------------------------------------------------------------------------

games_to_install=()
declare -A filepath_by_name
create_menu=false
create_desktop=false

# Gestion Mode CLI strict vs Mode Interactif / Double-clic
if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
  # --- MODE CLI STRICT (depuis le terminal avec ou sans -y) ---
  for target in "${cli_targets[@]}"; do
    if [ -f "$target" ]; then
      filename=$(basename "$target" .zgp)
      games_to_install+=("$filename")
      filepath_by_name["$filename"]="$target"
    else
      echo "Erreur : Fichier introuvable : $target" >&2
      exit 1
    fi
  done

  # Gestion de la confirmation interactive si le flag -y n'est pas présent
  if [ "$confirm_flag" != "yes" ]; then
    echo "Jeux à installer :"
    for name in "${games_to_install[@]}"; do
      echo " - $name (${filepath_by_name[$name]})"
    done
    read -r -p "Êtes-vous sûr de vouloir installer ces jeux ? [O/n] " response
    case "$response" in
      [nN][oO]|[nN])
        echo "Installation annulée."
        exit 0
        ;;
      *)
        ;;
    esac
  fi

  create_menu=true
  create_desktop=true
else
  # --- MODE INTERACTIF / DOUBLE-CLIC (Avec interface graphique Zenity) ---
  search_dir="."
  if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = true ]; then
    search_dir="$(dirname "${cli_targets[0]}")"
  else
    selected_file=$(zenity --file-selection --title="Sélectionner un jeu (.zgp)" --file-filter="Archives ZGP (*.zgp) | *.zgp" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$selected_file" ]; then
        exit 0
    fi
    search_dir="$(dirname "$selected_file")"
  fi

  shopt -s nullglob
  zgp_files=("$search_dir"/*.zgp)

  if [ ${#zgp_files[@]} -eq 0 ]; then
      zenity --info --text="Aucun fichier de jeu (.zgp) trouvé dans le répertoire." 2>/dev/null
      exit 0
  fi

  zenity_args=()
  for file in "${zgp_files[@]}"; do
    filename=$(basename "$file" .zgp)
    filepath_by_name["$filename"]="$file"
    zenity_args+=( "TRUE" "$filename" )
  done

  shortcuts_options=$(zenity --list --checklist --title="Options de création des lanceurs" --text="Où souhaitez-vous créer les raccourcis ?" --column="Créer" --column="Emplacement" TRUE "Menu des applications" TRUE "Raccourci sur le Bureau" --width=500 --height=220 2>/dev/null)

  if [[ "$shortcuts_options" =~ "Menu des applications" ]]; then
    create_menu=true
  fi
  if [[ "$shortcuts_options" =~ "Raccourci sur le Bureau" ]]; then
    create_desktop=true
  fi

  selected_games=$(zenity --list --checklist --title="Zgp-Installer" --text="Sélectionnez les jeux à importer :" --column="Installer" --column="Jeu" "${zenity_args[@]}" --width=600 --height=400 2>/dev/null)

  if [ -z "$selected_games" ]; then
    exit 0
  fi

  IFS="|" read -r -a games_to_install <<< "$selected_games"
fi

# ---------------------------------------------------------------------------------------------

# Traitement de chaque jeu sélectionné
for name in "${games_to_install[@]}"; do
  filepath="${filepath_by_name[$name]}"

  # 1. Extraction dans un dossier temporaire DIRECTEMENT dans $games_dir (renommage instantané garanti)
  temp_extract_dir=$(mktemp -d "$games_dir/.zgp-extract-XXXXXX")
  file_size=$(stat -c %s "$filepath" 2>/dev/null || stat -f %z "$filepath" 2>/dev/null)

  if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
    echo "Importation de $name en cours..."
    pv -s "$file_size" "$filepath" | tar -I zstd -xf - -C "$temp_extract_dir"
    tar_exit="${PIPESTATUS[1]}"
  else
    tar_exit_file=$(mktemp)
    (
      pv -n -s "$file_size" "$filepath" | tar -I zstd -xf - -C "$temp_extract_dir"
      echo "${PIPESTATUS[1]}" > "$tar_exit_file"
    ) 2>&1 | zenity --progress --title="Importation de $name" --text="Décompression en cours..." --percentage=0 --auto-close --width=500 2>/dev/null
    tar_exit=$(cat "$tar_exit_file" 2>/dev/null)
    rm -f "$tar_exit_file"
    [ -z "$tar_exit" ] && tar_exit=1
  fi

  # 1bis. Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
  # tronquée ou invalide), on abandonne proprement ce jeu sans toucher à Lutris ni créer de raccourcis
  if [ "$tar_exit" -ne 0 ]; then
    err_msg="Erreur : L'archive de '$name' est corrompue ou invalide (échec de la décompression, code $tar_exit)."
    if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
      echo "$err_msg" >&2
    else
      zenity --error --title="Archive corrompue" --text="$err_msg" 2>/dev/null
    fi
    rm -rf "$temp_extract_dir"
    continue
  fi

  # 2. Découverte du véritable slug à partir de ce qui a été réellement extrait
  slug=$(ls -1 "$temp_extract_dir" | head -n 1)
  if [ -z "$slug" ] || [ ! -d "$temp_extract_dir/$slug" ]; then
    echo "Erreur critique : Impossible de déterminer le préfixe extrait pour $name." >&2
    rm -rf "$temp_extract_dir"
    continue
  fi

  prefix_dir="$games_dir/$slug"

  # 3. Vérification stricte : si le préfixe existe déjà, on refuse catégoriquement l'installation
  if [ -d "$prefix_dir" ]; then
    err_msg="Erreur : Le jeu '$slug' est déjà installé. Veuillez d'abord le désinstaller avant de le réinstaller."
    if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
      echo "$err_msg" >&2
    else
      zenity --error --title="Paquet déjà existant" --text="$err_msg" 2>/dev/null
    fi
    rm -rf "$temp_extract_dir"
    continue
  fi

  # 4. Déplacement définitif instantané (0 seconde)
  mv "$temp_extract_dir/$slug" "$games_dir/"
  rm -rf "$temp_extract_dir"

  run_post_install() {
    echo "Analyse et configuration de $name..."

    timestamp=$(date +%s%N)
    config_id="${slug}-${timestamp}"

    meta_json="${prefix_dir}/zgp-meta.json"
    game_real_name=""
    extracted_runner=""

    if [ -f "$meta_json" ]; then
      if command -v python3 >/dev/null 2>&1; then
        game_real_name=$(python3 -c "import json; data=json.load(open('$meta_json')); print(data.get('game_real_name', ''))" 2>/dev/null)
        extracted_runner=$(python3 -c "import json; data=json.load(open('$meta_json')); print(data.get('game_runner', ''))" 2>/dev/null)
      else
        game_real_name=$(grep -o '"game_real_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_json" | cut -d'"' -f4)
        extracted_runner=$(grep -o '"game_runner"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_json" | cut -d'"' -f4)
      fi
    fi

    rm -f "$meta_json"

    [ -z "$game_real_name" ] && game_real_name="$name"

    echo "Traitement des registres Windows..."
    for reg in "system.reg" "user.reg" "userdef.reg" "lutris.json"; do
      if [ -f "${prefix_dir}/${reg}" ]; then
        sed -i "s|anonuser|${USER}|g" "${prefix_dir}/${reg}"
      fi
    done

    gamefolder=$(basename "$prefix_dir/drive_c/Games/"* 2>/dev/null || echo "")
    if [ -n "$gamefolder" ]; then
      ini_parent_dir="$prefix_dir/drive_c/Games/$gamefolder"
      goglog="$ini_parent_dir/goglog.ini"
      if [ -f "$goglog" ]; then
        sed -i "s|anonuser|${USER}|g" "$goglog"
      fi
    fi

    mkdir -p "${prefix_dir}/dosdevices"
    ln -sf "../drive_c" "${prefix_dir}/dosdevices/c:"
    if [ ! -e "${prefix_dir}/pfx" ]; then
      ln -sf "." "${prefix_dir}/pfx"
    fi

    echo "Enregistrement dans Lutris..."
    safe_name=$(echo "$game_real_name" | sed "s/'/''/g")
    
    bundled_yml="$prefix_dir/zgp-game-config.yml"
    yml_config_file="$lutris_config_dir/${config_id}.yml"

    executable_path=""

    if [ -f "$bundled_yml" ]; then
      executable_path=$(BUN_YML="$bundled_yml" python3 -c '
import os, yaml
try:
    with open(os.environ["BUN_YML"], "r") as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        exe = data.get("game", {}).get("exe", "")
        print(exe)
except Exception:
    pass
' 2>/dev/null)

      BUN_YML="$bundled_yml" YML_OUT="$yml_config_file" PFX_DIR="$prefix_dir" USER_HOME="$HOME" python3 -c '
import os, yaml, re
try:
    with open(os.environ["BUN_YML"], "r") as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        data.pop("script", None)
        data.pop("version", None)
        
        def update_paths(obj):
            if isinstance(obj, dict):
                return {k: update_paths(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [update_paths(v) for v in obj]
            elif isinstance(obj, str):
                res = re.sub(r"/home/[^/]+", os.environ["USER_HOME"], obj)
                res = res.replace("$GAMEDIR", os.environ["PFX_DIR"])
                return res
            return obj
            
        data = update_paths(data)
        
        if "game" not in data:
            data["game"] = {}
        data["game"]["prefix"] = os.environ["PFX_DIR"]

        with open(os.environ["YML_OUT"], "w") as f:
            yaml.dump(data, f, sort_keys=False)
except Exception as e:
    print(f"Erreur traitement YAML: {e}")
' 2>/dev/null
      rm -f "$bundled_yml"
    fi

    if [ ! -f "$yml_config_file" ]; then
      echo "Erreur critique : Le fichier zgp-game-config.yml est introuvable dans l'archive !"
    fi

    if [[ "$executable_path" != /* ]]; then
      executable_path="$prefix_dir/$executable_path"
    fi

    safe_prefix_dir=$(echo "$prefix_dir" | sed "s/'/''/g")
    safe_executable_path=$(echo "$executable_path" | sed "s/'/''/g")

    sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$slug';"
    sqlite3 "$lutris_db" <<EOF
INSERT INTO games (name, slug, installer_slug, parent_slug, runner, executable, directory, configpath, updated, installed, installed_at)
VALUES (
  '$safe_name',
  '$slug',
  '$slug',
  '',
  'wine',
  '$safe_executable_path',
  '$safe_prefix_dir',
  '$config_id',
  strftime('%s','now'),
  1,
  strftime('%s','now')
);
EOF

    icon_path="lutris_${slug}"
    if [ -d "$prefix_dir/icon" ]; then
      icon_file=$(find "$prefix_dir/icon" -maxdepth 1 -type f \( -name "*.png" -o -name "*.ico" -o -name "*.svg" -o -name "*.xpm" \) -print -quit 2>/dev/null)
      [ -n "$icon_file" ] && icon_path="$icon_file"
    fi

    echo "Création des raccourcis..."
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
Name=$game_real_name
Icon=$icon_path
Exec=$exec_cmd
Categories=Game"

    if [ "$create_menu" = true ]; then
      mkdir -p "$HOME/.local/share/applications"
      echo "$shortcut_content" > "$HOME/.local/share/applications/net.lutris.${slug}.desktop"
      update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi

    if [ "$create_desktop" = true ] && [ -d "$desktop_dir" ]; then
      echo "$shortcut_content" > "$desktop_dir/${slug}.desktop"
      chmod +x "$desktop_dir/${slug}.desktop"
      gio set "$desktop_dir/${slug}.desktop" metadata::trusted true 2>/dev/null || true

      if [ -d "$prefix_dir/extras" ]; then
        rm -rf "$desktop_dir/${game_real_name} Bonus"
        ln -s "$prefix_dir/extras" "$desktop_dir/${game_real_name} Bonus"
      fi
    fi

    echo "Finalisation..."
  }

  if [ ${#cli_targets[@]} -gt 0 ] && [ "$is_double_click" = false ]; then
    run_post_install
  else
    (
      run_post_install
      sleep 0.3
    ) | zenity --progress --title="Configuration de $name" --text="Traitement post-extraction..." --pulsate --auto-close --width=500 2>/dev/null
  fi
done

notify-send "Installation terminée" "Tous les jeux valides ont été importés avec succès !" 2>/dev/null
exit 0
