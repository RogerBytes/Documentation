#!/bin/bash

# Configuration des chemins des runners Lutris
lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

OUTPUT_DIR="$HOME"

# Récupération des arguments optionnels (pour le mode CLI direct)
# $1 = Nom du runner (ex: "proton-cachyos-x86_64")
# $2 = Niveau de compression optionnel (de 1 à 22)
target_runner_arg="${1:-}"
cli_level="${2:-}"

# 1. Vérification de zenity
if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé."
  exit 1
fi

if ! command -v zstd >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'zstd' n'est pas installé sur le système." 2>/dev/null
  exit 1
fi

# 2. Détection du type de Lutris (Flatpak vs Paquet natif)
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  runner_dir="$lutris_flatpak_runner_dir"
elif [ -d "$lutris_package_runner_dir" ]; then
  runner_dir="$lutris_package_runner_dir"
else
  runner_dir="$HOME/.local/share/lutris/runners/wine"
fi

if [ ! -d "$runner_dir" ]; then
  zenity --error --text="Aucun dossier de runners Wine introuvable : $runner_dir" 2>/dev/null
  exit 1
fi

cd "$runner_dir" || exit 1

declare -A path_by_runner

# 3. Gestion Mode CLI vs Mode Interactif
if [ -n "$target_runner_arg" ]; then
  # --- MODE CLI ---
  if [ ! -d "$runner_dir/$target_runner_arg" ]; then
    zenity --error --text="Le runner '$target_runner_arg' est introuvable dans $runner_dir." 2>/dev/null
    exit 1
  fi
  runners_to_export=("$target_runner_arg")
  path_by_runner["$target_runner_arg"]="$runner_dir/$target_runner_arg"
  LEVEL="${cli_level:-3}"
else
  # --- MODE INTERACTIF ---
  runners_list=( * )

  if [ ${#runners_list[@]} -eq 0 ] || [ "${runners_list[0]}" = "*" ]; then
    zenity --info --text="Aucun runner Wine/Proton trouvé dans $runner_dir." 2>/dev/null
    exit 0
  fi

  # Tri alphabétique propre
  IFS=$'\n' sorted_runners=($(sort <<< "${runners_list[*]}"))
  unset IFS

  zenity_args=()
  for runner in "${sorted_runners[@]}"; do
    [ -d "$runner" ] || continue
    path_by_runner["$runner"]="$runner_dir/$runner"
    zenity_args+=( "FALSE" "$runner" )
  done

  selected_runners=$(zenity --list --checklist \
    --title="Exportateur de Runners ZGR" \
    --text="Sélectionnez le ou les runners à exporter :" \
    --column="Exporter" --column="Nom du Runner" \
    "${zenity_args[@]}" \
    --width=650 --height=350 2>/dev/null)

  if [ -z "$selected_runners" ]; then
    exit 0
  fi

  # Demande facultative pour personnaliser le taux de compression
  LEVEL=3
  zenity --question \
    --title="Options de compression" \
    --text="Personnaliser le taux de compression ?" \
    --width=400 2>/dev/null

  if [ $? -eq 0 ]; then
    level_choice=$(zenity --scale \
      --title="Niveau de compression Zstandard" \
      --text="Choisissez le niveau de compression :\n(1 = Rapide | 3 = Défaut | 22 = Max/Lent)\n\nAttention : Les niveaux supérieurs à 15 nécessitent beaucoup de RAM et de temps." \
      --min-value=1 \
      --max-value=22 \
      --value=3 \
      --step=1 \
      --width=400 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$level_choice" ]; then
      LEVEL="$level_choice"
    fi
  fi

  IFS="|" read -r -a runners_to_export <<< "$selected_runners"
fi

# 4. Traitement de la compression (Commun aux deux modes, avec barre Zenity)
cd "$runner_dir" || exit 1

total_runners=${#runners_to_export[@]}
current=0

for runner in "${runners_to_export[@]}"; do
  current=$((current + 1))
  r_path="${path_by_runner[$runner]}"
  
  ARCHIVE_NAME="$runner"
  archive_path="${OUTPUT_DIR}/${ARCHIVE_NAME}.zgr"

  source_size=$(du -sb "$r_path" 2>/dev/null | cut -f1)
  [ -z "$source_size" ] && source_size=1
  estimated_archive_size=$(( source_size * 40 / 100 ))
  [ "$estimated_archive_size" -le 0 ] && estimated_archive_size=1

  rm -f "$archive_path"

  # Commande de compression sécurisée avec support du mode ultra (20 à 22)
  if [ "$LEVEL" -gt 19 ]; then
    tar_cmd="tar --use-compress-program='zstd --ultra -$LEVEL' -cvf '$archive_path' -C '$runner_dir' '$runner'"
  else
    tar_cmd="tar -I 'zstd -$LEVEL' -cvf '$archive_path' -C '$runner_dir' '$runner'"
  fi

  bash -c "$tar_cmd" &
  tar_pid=$!

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
        estimated_mb=$(( estimated_archive_size / 1024 / 1024 ))

        echo "$percent"
        echo "# Compression de $ARCHIVE_NAME ($current / $total_runners)\nÉcrit : ${current_mb} Mo / ~${estimated_mb} Mo estimés (Niveau $LEVEL)"
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
    --width=450 2>/dev/null

  zenity_status=$?

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

notify-send "Exportation terminée" "Tous les runners sélectionnés ont été exportés avec succès dans :\n$OUTPUT_DIR" 2>/dev/null
exit 0
