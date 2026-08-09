#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"

# --- Récupération des arguments du routeur lpm ---
# $1 = Flag de confirmation ("yes" si -y)
# $2, $3, ... = Liste des runners cibles à supprimer en CLI
confirm_flag="${1:-}"
shift || true
cli_runners=("$@")

# Configuration des chemins des runners Lutris
lutris_flatpak_runner_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="${HOME}/.local/share/lutris/runners/wine"

# 1. Détection du type de Lutris (Flatpak vs Paquet natif ; fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  runner_dir="${lutris_flatpak_runner_dir}"
elif check_native_lutris_installed "" "${lutris_package_runner_dir}"; then
  runner_dir="${lutris_package_runner_dir}"
else
  runner_dir="${HOME}/.local/share/lutris/runners/wine"
fi

if [[ ! -d "${runner_dir}" ]]; then
  if [[ ${#cli_runners[@]} -gt 0 ]]; then
    t uninstall_runner.dir_missing_cli "${runner_dir}" >&2
  else
    zenity --error --text="$(t uninstall_runner.dir_missing_gui "${runner_dir}")" 2>/dev/null
  fi
  exit 1
fi

cd "${runner_dir}" || exit 1

declare -A path_by_runner
runners_to_delete=()

# 2. Gestion Mode CLI (Multi-runners) vs Mode Interactif
if [[ ${#cli_runners[@]} -gt 0 ]]; then
  # --- MODE CLI (Terminal, aucun Zenity) ---
  missing=()

  for target_runner_raw in "${cli_runners[@]}"; do
    # basename() neutralise toute tentative de traversée de chemin ("../", chemin absolu...)
    # dans un nom de runner fourni en CLI : sans cela, "lpm uninstall-runner ../../Games/x"
    # pouvait faire pointer r_path en dehors de runner_dir et déclencher un rm -rf sur un
    # dossier arbitraire du système accessible par traversée relative depuis runner_dir.
    target_runner_arg=$(basename -- "${target_runner_raw}")
    r_path="${runner_dir}/${target_runner_arg}"
    if [[ ! -d "${r_path}" ]]; then
      missing+=("${target_runner_raw}")
      continue
    fi
    runners_to_delete+=("${target_runner_arg}")
    path_by_runner["${target_runner_arg}"]="${r_path}"
  done

  # Vérification stricte : le moindre runner introuvable annule tout, rien n'est supprimé
  if [[ ${#missing[@]} -gt 0 ]]; then
    t uninstall_runner.missing_cli_header "${runner_dir}" >&2
    for name in "${missing[@]}"; do
      t uninstall_runner.missing_cli_item "${name}" >&2
    done
    t uninstall_runner.missing_cli_footer >&2
    exit 1
  fi

  # Confirmation interactive si le flag -y n'est pas présent
  if [[ "${confirm_flag}" != "yes" ]]; then
    t uninstall_runner.confirm_cli_header
    for name in "${runners_to_delete[@]}"; do
      t uninstall_runner.confirm_cli_item "${name}" "${path_by_runner[${name}]}"
    done
    read -r -p "$(t uninstall_runner.confirm_cli_prompt)" response
    case "${response}" in
      [nN])
        t uninstall_runner.confirm_cli_cancelled
        exit 0
        ;;
      *)
        ;;
    esac
  fi
else
  # --- MODE INTERACTIF (Avec Zenity) ---
  if ! command -v zenity >/dev/null 2>&1; then
    t uninstall_runner.zenity_missing >&2
    exit 1
  fi

  shopt -s nullglob
  runners_list=( */ )

  if [[ ${#runners_list[@]} -eq 0 ]]; then
    zenity --info --text="$(t uninstall_runner.none_found_gui "${runner_dir}")" 2>/dev/null
    exit 0
  fi

  # Tri alphabétique propre
  mapfile -t sorted_runners < <(sort <<< "${runners_list[*]}")
  unset IFS

  zenity_args=()

  for runner in "${sorted_runners[@]}"; do
    runner="${runner%/}"
    [[ -d "${runner}" ]] || continue
    path_by_runner["${runner}"]="${runner_dir}/${runner}"
    # Décoché par défaut (FALSE) pour éviter les erreurs d'étourderie
    zenity_args+=( "FALSE" "${runner}" )
  done

  # Fenêtre de sélection (checklist) pour choisir les runners à supprimer
  selected_runners=$(zenity --list --checklist \
    --title="$(t uninstall_runner.list_title)" \
    --text="$(t uninstall_runner.list_text)" \
    --column="$(t uninstall_runner.list_column_delete)" --column="$(t uninstall_runner.list_column_name)" \
    "${zenity_args[@]}" \
    --width=650 --height=400 2>/dev/null)

  if [[ -z "${selected_runners}" ]]; then
    exit 0
  fi

  IFS="|" read -r -a runners_to_delete <<< "${selected_runners}"

  # Construction du résumé pour la fenêtre de confirmation
  summary_text="$(t uninstall_runner.confirm_gui_header)"
  for runner in "${runners_to_delete[@]}"; do
    r_path="${path_by_runner[${runner}]}"
    summary_text+="$(t uninstall_runner.confirm_gui_item "${runner}" "${r_path}")"
  done

  summary_text+="$(t uninstall_runner.confirm_gui_footer)"

  # Demande de confirmation finale
  if ! zenity --question --title="$(t uninstall_runner.confirm_title)" \
    --text="${summary_text}" \
    --width=550 --height=350 2>/dev/null; then
    zenity --info --title="$(t uninstall_runner.cancel_title)" --text="$(t uninstall_runner.cancel_text)" 2>/dev/null
    exit 0
  fi
fi

# 3. Traitement de la suppression
total_runners=${#runners_to_delete[@]}

if [[ ${#cli_runners[@]} -gt 0 ]]; then
  # --- MODE CLI (Affichage textuel épuré) ---
  current=0
  for runner in "${runners_to_delete[@]}"; do
    current=$((current + 1))
    t uninstall_runner.progress_cli "${current}" "${total_runners}" "${runner}"

    r_path="${path_by_runner[${runner}]}"
    if [[ -d "${r_path}" ]]; then
      rm -rf "${r_path}"
    fi
  done

  t uninstall_runner.done_cli
else
  # --- MODE INTERACTIF (Barre de progression Zenity) ---
  (
    current=0
    for runner in "${runners_to_delete[@]}"; do
      current=$((current + 1))
      percent=$(( current * 100 / total_runners ))

      echo "${percent}"
      t uninstall_runner.progress_gui "${runner}" "${current}" "${total_runners}"

      r_path="${path_by_runner[${runner}]}"

      # Suppression physique du dossier du runner
      if [[ -d "${r_path}" ]]; then
        rm -rf "${r_path}"
      fi

      sleep 0.2
    done

    echo "100"
    t uninstall_runner.cleanup_gui
    sleep 0.3

  ) | zenity --progress \
    --title="$(t uninstall_runner.progress_gui_title)" \
    --text="$(t uninstall_runner.progress_gui_text)" \
    --percentage=0 \
    --auto-close \
    --width=450 2>/dev/null

  zenity_status=$?

  if [[ "${zenity_status}" -ne 0 ]]; then
    zenity --info --title="$(t uninstall_runner.interrupted_title)" --text="$(t uninstall_runner.interrupted_text)" 2>/dev/null
    exit 0
  fi

  notify-send "$(t uninstall_runner.notify_title)" "$(t uninstall_runner.notify_body)" 2>/dev/null
fi

exit 0
