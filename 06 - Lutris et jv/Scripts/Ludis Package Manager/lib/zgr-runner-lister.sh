#!/bin/bash

# --- Lister les runners Wine/Proton installés pour Lutris ---
# Sortie : <nom du runner> (un par ligne, triés alphabétiquement)

lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

# Détection Flatpak vs Paquet natif
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
  echo "Erreur : Dossier de runners introuvable : $runner_dir" >&2
  exit 1
fi

cd "$runner_dir" || exit 1

shopt -s nullglob
runners_list=( */ )

if [ ${#runners_list[@]} -eq 0 ]; then
  echo "Aucun runner installé."
  exit 0
fi

# Tri alphabétique propre
IFS=$'\n' sorted_runners=($(sort <<< "${runners_list[*]}"))
unset IFS

for runner in "${sorted_runners[@]}"; do
  runner="${runner%/}"
  [ -d "$runner" ] || continue
  echo "$runner"
done

exit 0
