#!/bin/bash

lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"
lutris_flatpak_option_file="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml"
lutris_package_option_file="$HOME/.config/lutris/runners/wine.yml"
lutris_package_config_dir="$HOME/.config/lutris/games"
lutris_flatpak_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_flatpak_cmd="flatpak run net.lutris.Lutris"
lutris_package_cmd="lutris"
games_dir="$HOME/Games"
default_runner="wine-ge-8-26-x86_64"
lutrisbefore_pid=$(pgrep -xo lutris)

declare -A runners_map
declare -A names_map
declare -A files_map
declare -A runners_needed

# Fermer uniquement Lutris (et pas le script lui-même !)
if flatpak list | grep -q lutris; then
  flatpak kill net.lutris.Lutris 2>/dev/null
fi

pkill -9 -x lutris 2>/dev/null
pkill -9 -f "/usr/bin/lutris" 2>/dev/null

# Affectation de variable en fonction du type d'installation
check_flatpak_lutris_installed() {
  flatpak list | grep -q lutris
}

if check_flatpak_lutris_installed; then
  version="flatpak"
elif command -v lutris >/dev/null 2>&1; then
  version="package"
else
  echo "Lutris n'est pas installé, fermeture du programme."
  exit 1
fi

case "$version" in
  flatpak)
    lutris_runner_dir="$lutris_flatpak_runner_dir"
    lutris_option_file="$lutris_flatpak_option_file"
    lutris_cmd="$lutris_flatpak_cmd"
    lutris_config_dir="$lutris_flatpak_config_dir"
    ;;
  package)
    lutris_runner_dir="$lutris_package_runner_dir"
    lutris_option_file="$lutris_package_option_file"
    lutris_cmd="$lutris_package_cmd"
    lutris_config_dir="$lutris_package_config_dir"
    ;;
esac

if [ -f "$lutris_option_file" ]; then
  extracted_path=$(awk -F': ' '/^\s*game_path:/ {print $2}' "$lutris_option_file")
  if [ -n "$extracted_path" ]; then
    games_dir="$extracted_path"
  fi
fi

# ---------------------------------------------------------------------------------------------

# Création/remplissage des tableaux associatifs
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
  runners_needed["$runner"]=1
  ((index++))
done

# ---------------------------------------------------------------------------------------------

# Installation des runners nécessaires
install_runner_if_needed() {
  runner=$1
  if [ ! -d "$lutris_runner_dir/$runner" ]; then
    if [ -f "./resources/$runner.tzst" ]; then
      echo "Extraction du runner $runner depuis les ressources locales..."
      tar -I zstd -xvf "./resources/$runner.tzst" -C "$lutris_runner_dir" || { echo "Erreur lors de l'extraction de $runner depuis les ressources locales."; exit 1; }
    else
      echo "Téléchargement du runner $runner..."
      temp_dir=$(mktemp -d)
      wget "https://github.com/RogerBytes/Mintage/releases/download/wine-pkg/$runner.tzst" -O "$temp_dir/$runner.tzst" || { echo "Erreur lors du téléchargement de $runner."; rm -rf "$temp_dir"; exit 1; }
      mkdir -p "$lutris_runner_dir"
      tar -I zstd -xvf "$temp_dir/$runner.tzst" -C "$lutris_runner_dir" || { echo "Erreur lors de l'extraction de $runner."; rm -rf "$temp_dir"; exit 1; }
      rm -rf "$temp_dir"
    fi
  else
    echo "Le runner \"$runner\" est déjà installé."
  fi
}

for runner in "${!runners_needed[@]}"; do
  install_runner_if_needed "$runner"
done

# ---------------------------------------------------------------------------------------------

# Extraction des préfixes et création des YML
for i in "${!names_map[@]}"; do
  filename="${files_map[$i]}"
  name="${names_map[$i]}"
  yml_file="./$name.yml"
  runner="${runners_map[$i]}"
  slug=$(tar -I zstd -tf "./$filename" | head -1 | cut -d'/' -f1)
  gamepad=false
  preload_script=false
  prefix_dir="$games_dir/$slug"

  # Extraction
  mkdir -p "$games_dir"
  tar -I zstd -xvf "./$filename" -C "$games_dir"
  if [ $? -ne 0 ]; then
    echo "Erreur lors de l'extraction de $filename."
    exit 1
  fi

  # Remplace "anonuser" par le véritable nom d'utilisateur système
  for reg in "system.reg" "user.reg" "userdef.reg" "lutris.json"; do
    if [ -f "${prefix_dir}/${reg}" ]; then
      sed -i "s|anonuser|${USER}|g" "${prefix_dir}/${reg}"
    fi
  done

  # Restauration des liens de base Wine/Proton pour UMU
  mkdir -p "${prefix_dir}/dosdevices"
  ln -sf "../drive_c" "${prefix_dir}/dosdevices/c:"
  if [ ! -e "${prefix_dir}/pfx" ]; then
    ln -sf "." "${prefix_dir}/pfx"
  fi

  gamefolder=$(basename "$prefix_dir/drive_c/Games/"*/)
  ini_parent_dir="$prefix_dir/drive_c/Games/$gamefolder"
  goglog="$ini_parent_dir/goglog.ini"

  if [ -f "$goglog" ]; then
    sed -i "s|anonuser|${USER}|g" "$goglog"
  fi

  # Vérification du dossier 'scripts'
  if [ -d "$games_dir/$slug/scripts" ]; then
    gamepad_file=$(find "$games_dir/$slug/scripts" -type f -name "*.amgp" -print -quit)
    start_file=$(find "$games_dir/$slug/scripts" -type f -name "start.sh" -print -quit)

    if [ -n "$gamepad_file" ]; then
      gamepad=true
    fi
    if [ -n "$start_file" ]; then
      echo "Fichier start.sh trouvé : $start_file"
      preload_script=true
    fi
  fi

  # Création du fichier yml pour lutris
  cat > "$yml_file" <<EOL
name: "$name"
game_slug: "$slug"
version: Installateur
slug: "$slug"
runner: wine

script:
  game:
    exe: drive_c/Games/$gamefolder/Launch.bat
    prefix: \$GAMEDIR
  installer:
  - task:
      description: Création du préfixe en cours
      name: create_prefix
      prefix: \$GAMEDIR
EOL

  # Renommer le dossier extrait complet
  mv "$prefix_dir" "${prefix_dir}TRUE"

  # Surveiller le répertoire de config avant de lancer Lutris
  initial_files=$(ls "$lutris_config_dir")
  new_files=""

  # Lancer Lutris en tâche de fond
  $lutris_cmd -i "$yml_file" &
  lutris_pid=$!

  # Attendre l'apparition du fichier de configuration généré par Lutris
  config_file=""
  while [ -z "$config_file" ]; do
    sleep 0.5
    current_files=$(ls "$lutris_config_dir")
    new_files=$(comm -13 <(echo "$initial_files" | sort) <(echo "$current_files" | sort))
    config_file=$(echo "$new_files" | head -n 1)
  done

  # 1. On arrête proprement Lutris et Wine
  if [ "$version" == "flatpak" ]; then
    flatpak kill net.lutris.Lutris 2>/dev/null || true
  else
    pkill -9 -f "lutris" 2>/dev/null || true
  fi
  kill $lutris_pid 2>/dev/null || true
  wineserver -k 2>/dev/null || true

  # 2. Suppression forcée et attente active du préfixe temporaire généré par Lutris
  rm -rf "${prefix_dir}"
  while [ -d "${prefix_dir}" ]; do
    sleep 0.1
    rm -rf "${prefix_dir}" 2>/dev/null
  done

  # 3. Déplacement sécurisé (-T empêche la création d'un sous-dossier)
  mv -T "${prefix_dir}TRUE" "${prefix_dir}"

  # 4. Ajustements du fichier de configuration Lutris généré
  if [ -f "$lutris_config_dir/$config_file" ]; then
    sed -i 's/^wine: *{}/wine:/' "$lutris_config_dir/$config_file"
    sed -i '/^wine:/a\  version: '"$runner" "$lutris_config_dir/$config_file"

    if [ "$preload_script" = true ] || [ "$gamepad" = true ]; then
      sed -i 's/^system: {}$/system:/g' "$lutris_config_dir/$config_file"
    fi

    if [ "$preload_script" = true ]; then
      sed -i "/^system:/a\  prelaunch_command: $prefix_dir/scripts/start.sh" "$lutris_config_dir/$config_file"
      sed -i "/^system:/a\  postexit_command: $prefix_dir/scripts/stop.sh" "$lutris_config_dir/$config_file"
      sed -i "/^system:/a\  locale: ''" "$lutris_config_dir/$config_file"
    fi

    if [ "$gamepad" = true ]; then
      sed -i "/^system:/a\  antimicro_config: $gamepad_file" "$lutris_config_dir/$config_file"
    fi
  fi

  rm -f "$yml_file"
  echo -e "\e[32m$name installé avec succès !\e[0m"
done

echo -e "\e[32mFin du programme\e[0m"
