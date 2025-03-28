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
kill_package_lutris="pkill -f lutris"
kill_flatpak_lutris="flatpak kill lutris"

declare -A runners_map
declare -A names_map
declare -A files_map
declare -A runners_needed

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
    kill_lutris="$kill_flatpak_lutris"
    ;;
  package)
    lutris_runner_dir="$lutris_package_runner_dir"
    lutris_option_file="$lutris_package_option_file"
    lutris_cmd="$lutris_package_cmd"
    lutris_config_dir="$lutris_package_config_dir"
    kill_lutris="$kill_package_lutris"
    ;;
esac

if [ -f "$lutris_option_file" ]; then
  echo "Fichier de configuration trouvé."
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
  echo "Aucun fichier .tzst trouvé."
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

# Extraction des prefixe et creation des yml

for i in "${!names_map[@]}"; do
  filename="${files_map[$i]}"
  name="${names_map[$i]}"
  yml_file="./$name.yml"
  runner="${runners_map[$i]}"
  slug=$(tar -I zstd -tf "./$filename" | head -1 | cut -d'/' -f1)
  gamepad=false
  preload_script=false
  prefix_dir="$games_dir/$slug"
  echo "verif du YAML DE MERDE"
  echo "$yml_file"
  # extraction
  tar -I zstd -xvf "./$filename" -C "$games_dir"
  if [ $? -ne 0 ]; then
    echo "Erreur lors de l'extraction de $filename."
    exit 1
  fi
  if [ -d "$games_dir/$slug" ]; then
    echo "Dossier extrait : $slug"
  else
    echo "Erreur : Impossible de déterminer le dossier extrait."
    exit 1
  fi

  gamefolder=$(basename "$prefix_dir/drive_c/Games/"*/)

  # Vérification du dossier 'scripts'
  if [ -d "$games_dir/$slug/scripts" ]; then
    echo "Le dossier 'scripts' existe."

    # Vérification du fichier .amgp dans le dossier scripts
    gamepad_file=$(find "$games_dir/$slug/scripts" -type f -name "*.amgp" -print -quit)

    # Vérification du fichier start.sh dans le dossier scripts
    start_file=$(find "$games_dir/$slug/scripts" -type f -name "start.sh" -print -quit)

    if [ -n "$gamepad_file" ]; then
      echo "Fichier .amgp trouvé : $gamepad_file"
      gamepad=true
    else
      echo "Aucun fichier .amgp trouvé dans le dossier 'scripts'."
    fi

    if [ -n "$start_file" ]; then
      echo "Fichier start.sh trouvé : $start_file"
      preload_script=true
    else
      echo "Aucun fichier start.sh trouvé dans le dossier 'scripts'."
    fi

  else
    echo "Le dossier 'scripts' n'existe pas dans $games_dir/$slug."
  fi

  echo "CACA1"
  cat > "$yml_file" <<EOL
name: "$name"
game_slug: "$slug"
version: "$name"
slug: "$slug"
description: "$name"
runner: wine

script:
  game:
    arch: win64
    exe: $prefix_dir/drive_c/Games/$gamefolder/Launch.bat
    working_dir: $prefix_dir/drive_c/Games/$gamefolder
    prefix: $prefix_dir

  wine:
    version: $runner
EOL
  echo "CACA2"

  # Lancer Lutris en tâche de fond en important le fichier d'installation
  $lutris_cmd -i "$yml_file" &
  lutris_pid=$!  # Récupérer l'ID du processus Lutris

  echo "En attente de la création d'un fichier dans $lutris_config_dir..."

  # Récupérer l'état initial du répertoire (avant création de fichiers)
  initial_files=$(ls "$lutris_config_dir")

  # Surveiller le répertoire sans `inotifywait`
  while true; do
    # Vérifier les nouveaux fichiers créés
    current_files=$(ls "$lutris_config_dir")
    new_files=$(comm -13 <(echo "$initial_files") <(echo "$current_files"))

    # Si un nouveau fichier a été créé
    if [ -n "$new_files" ]; then
      config_file=$(echo "$new_files" | head -n 1)
      echo "Nouveau fichier détecté : $config_file"
      $kill_lutris
      break
    fi
    sleep 1
  done

  # Attendre que le processus Lutris se termine
  while kill -0 "$lutris_pid" > /dev/null 2>&1; do
    echo "Lutris est encore en cours..."
    sleep 1
  done
  echo "Lutris a terminé"


# Les derniers réglages a faire, je dois tout corriger pour les indentations et pour que ça utilise $config_file au slieu de $yml_file

if [ -f "$lutris_config_dir/$config_file" ]; then
  echo "Le fichier existe."
else
  echo "Le fichier n'existe pas."
fi


# Précise la version du runner dans les réglages
  sed -i "s|^  version: .*|  version: $runner|" "$lutris_config_dir/$config_file"

# Ajouter la section system
  if [ "$preload_script" = true ] || [ "$gamepad" = true ]; then
    sed -i 's/^system: \{\}/system:/g' "$lutris_config_dir/$config_file"
  fi


#  echo "CACA3"
#  # Ajouter les configurations spécifiques
  if [ "$preload_script" = true ]; then
    sed -i '/^system:/a\  prelaunch_command: $prefix_dir/scripts/start.sh' "$lutris_config_dir/$config_file"
    sed -i '/^system:/a\  prelaunch_command: $prefix_dir/scripts/stop.sh' "$lutris_config_dir/$config_file"
    sed -i "/^system:/a\  locale: ''" "$lutris_config_dir/$config_file"
  fi


    # Ajouter la configuration du gamepad
  if [ "$gamepad" = true ]; then
    sed -i "/^system:/a\  antimicro_config: $prefix_dir/scripts/$gamepad_file" "$lutris_config_dir/$config_file"
  fi
  echo "$yml_file"

  rm $yml_file
done

echo "Fin du script"
