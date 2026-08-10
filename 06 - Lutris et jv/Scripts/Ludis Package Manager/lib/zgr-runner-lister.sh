#!/bin/bash

# --- Lister les runners Wine/Proton installés pour Lutris ---
# Sortie : <nom du runner> (un par ligne, triés alphabétiquement)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"

lutris_flatpak_runner_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="${HOME}/.local/share/lutris/runners/wine"

# Détection Flatpak vs Paquet natif (fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  runner_dir="${lutris_flatpak_runner_dir}"
elif check_native_lutris_installed "" "${lutris_package_runner_dir}"; then
  runner_dir="${lutris_package_runner_dir}"
else
  # Détection explicite (alignée sur les autres scripts de lib/) : évite le repli
  # silencieux vers un chemin natif par défaut qui masquerait l'absence de Lutris.
  t list_runner.lutris_missing >&2
  exit 1
fi

if [[ ! -d "${runner_dir}" ]]; then
  t list_runner.dir_missing "${runner_dir}" >&2
  exit 1
fi

cd "${runner_dir}" || exit 1

shopt -s nullglob
runners_list=( */ )

if [[ ${#runners_list[@]} -eq 0 ]]; then
  t list_runner.none_installed
  exit 0
fi

# Tri alphabétique propre
mapfile -t sorted_runners < <(printf '%s\n' "${runners_list[@]}" | sort)

for runner in "${sorted_runners[@]}"; do
  runner="${runner%/}"
  [[ -d "${runner}" ]] || continue
  echo "${runner}"
done

exit 0
