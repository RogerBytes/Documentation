#!/bin/bash

# --- Récupération des arguments du routeur lpm ---
# $1 = Niveau de compression optionnel (ex: "5" ou vide)
# $2, $3, ... = Liste des runners cibles en CLI
compression_arg="${1:-}"
shift || true
cli_runners=("$@")

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"
# shellcheck source=./zgu-progress-utils.sh
source "${script_dir}/zgu-progress-utils.sh"

# Configuration des chemins des runners Lutris
lutris_flatpak_runner_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="${HOME}/.local/share/lutris/runners/wine"

OUTPUT_DIR="${HOME}"

# 1. Vérification de zstd (toujours requis)
if ! command -v zstd >/dev/null 2>&1; then
  t pack_runner.zstd_missing >&2
  exit 1
fi

# 2. Détection du type de Lutris (Flatpak vs Paquet natif ; fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  runner_dir="${lutris_flatpak_runner_dir}"
elif check_native_lutris_installed "" "${lutris_package_runner_dir}"; then
  runner_dir="${lutris_package_runner_dir}"
else
  # Détection explicite (alignée sur les autres scripts de lib/) : un repli silencieux
  # vers le chemin natif par défaut donnerait un message "dossier introuvable" plus loin
  # dans le script, bien moins clair que la vraie cause (Lutris non installé).
  if [[ ${#cli_runners[@]} -gt 0 ]]; then
    t pack_runner.lutris_missing_cli >&2
  else
    zenity --error --text="$(t pack_runner.lutris_missing_gui)" 2>/dev/null
  fi
  exit 1
fi

if [[ ! -d "${runner_dir}" ]]; then
  if [[ ${#cli_runners[@]} -gt 0 ]]; then
    t pack_runner.dir_missing_cli "${runner_dir}" >&2
  else
    zenity --error --text="$(t pack_runner.dir_missing_gui "${runner_dir}")" 2>/dev/null
  fi
  exit 1
fi

cd "${runner_dir}" || exit 1

declare -A path_by_runner
runners_to_export=()

# 3. Gestion Mode CLI (Multi-runners) vs Mode Interactif
if [[ ${#cli_runners[@]} -gt 0 ]]; then
  # --- MODE CLI (Terminal, aucun Zenity) ---
  LEVEL="${compression_arg:-3}"
  missing=()
  conflicts=()

  for target_runner_raw in "${cli_runners[@]}"; do
    # basename() neutralise toute tentative de traversée de chemin ("../", chemin absolu...)
    # dans un nom de runner fourni en CLI : sans cela, un nom comme "../../home/user/.ssh"
    # aurait pu faire lire/archiver un dossier arbitraire du système en dehors de runner_dir.
    target_runner_arg=$(basename -- "${target_runner_raw}")
    if [[ ! -d "${runner_dir}/${target_runner_arg}" ]]; then
      missing+=("${target_runner_raw}")
      continue
    fi

    archive_path="${OUTPUT_DIR}/${target_runner_arg}.zgr"
    if [[ -f "${archive_path}" ]]; then
      conflicts+=("${target_runner_arg}")
    fi

    runners_to_export+=("${target_runner_arg}")
    path_by_runner["${target_runner_arg}"]="${runner_dir}/${target_runner_arg}"
  done

  # Vérification stricte : le moindre runner manquant ou paquet déjà existant annule tout, rien n'est exporté
  if [[ ${#missing[@]} -gt 0 ]] || [[ ${#conflicts[@]} -gt 0 ]]; then
    if [[ ${#missing[@]} -gt 0 ]]; then
      t pack_runner.missing_header_cli "${runner_dir}" >&2
      for name in "${missing[@]}"; do
        t pack_runner.missing_item_cli "${name}" >&2
      done
    fi
    if [[ ${#conflicts[@]} -gt 0 ]]; then
      t pack_runner.conflict_header_cli "${OUTPUT_DIR}" >&2
      for name in "${conflicts[@]}"; do
        t pack_runner.conflict_item_cli "${name}" >&2
      done
      t pack_runner.conflict_hint >&2
    fi
    t pack_runner.nothing_exported >&2
    exit 1
  fi
else
  # --- MODE INTERACTIF (Avec Zenity) ---
  if ! command -v zenity >/dev/null 2>&1; then
    t pack_runner.zenity_missing >&2
    exit 1
  fi

  shopt -s nullglob
  runners_list=( */ )

  if [[ ${#runners_list[@]} -eq 0 ]]; then
    zenity --info --text="$(t pack_runner.no_runner_found "${runner_dir}")" 2>/dev/null
    exit 0
  fi

  # Tri alphabétique propre
  mapfile -t sorted_runners < <(printf '%s\n' "${runners_list[@]}" | sort)

  zenity_args=()
  for runner in "${sorted_runners[@]}"; do
    runner="${runner%/}"
    [[ -d "${runner}" ]] || continue
    path_by_runner["${runner}"]="${runner_dir}/${runner}"
    zenity_args+=( "FALSE" "${runner}" )
  done

  selected_runners=$(zenity --list --checklist \
    --title="$(t pack_runner.select_title)" \
    --text="$(t pack_runner.select_text)" \
    --column="$(t pack_runner.select_col_export)" --column="$(t pack_runner.select_col_name)" \
    --separator=$'\x1f' \
    "${zenity_args[@]}" \
    --width=650 --height=350 2>/dev/null)

  if [[ -z "${selected_runners}" ]]; then
    exit 0
  fi

  # Demande facultative pour personnaliser le taux de compression
  LEVEL=3
  if zenity --question \
    --title="$(t pack_runner.compression_question_title)" \
    --text="$(t pack_runner.compression_question_text)" \
    --width=400 2>/dev/null; then
    if level_choice=$(zenity --scale \
      --title="$(t pack_runner.compression_scale_title)" \
      --text="$(t pack_runner.compression_scale_text)" \
      --min-value=1 \
      --max-value=22 \
      --value=3 \
      --step=1 \
      --width=400 2>/dev/null) && [[ -n "${level_choice}" ]]; then
      LEVEL="${level_choice}"
    fi
  fi

  IFS=$'\x1f' read -r -a runners_to_export <<< "${selected_runners}"
fi

# 4. Traitement de la compression
cd "${runner_dir}" || exit 1

total_runners=${#runners_to_export[@]}
current=0

for runner in "${runners_to_export[@]}"; do
  current=$((current + 1))
  r_path="${path_by_runner[${runner}]}"

  ARCHIVE_NAME="${runner}"
  archive_path="${OUTPUT_DIR}/${ARCHIVE_NAME}.zgr"

  # Commande de compression sécurisée avec support du mode ultra (20 à 22)
  if [[ "${LEVEL}" -gt 19 ]]; then
    zstd_opt="--ultra -${LEVEL}"
  else
    zstd_opt="-${LEVEL}"
  fi

  if [[ ${#cli_runners[@]} -gt 0 ]]; then
    # --- MODE CLI : pv + zstd, barre de progression texte ---
    t pack_runner.compressing_cli "${current}" "${total_runners}" "${ARCHIVE_NAME}" "${LEVEL}"

    source_size=$(du -sb "${r_path}" 2>/dev/null | cut -f1)
    [[ -z "${source_size}" ]] && source_size=0

    if command -v pv >/dev/null 2>&1; then
      tar -C "${runner_dir}" -cf - "${runner}" | pv -s "${source_size}" | zstd "${zstd_opt}" > "${archive_path}"
      tar_exit="${PIPESTATUS[0]}"
    else
      tar -C "${runner_dir}" -cf - "${runner}" | zstd "${zstd_opt}" > "${archive_path}"
      tar_exit="${PIPESTATUS[0]}"
    fi

    if [[ "${tar_exit}" -ne 0 ]] || [[ ! -s "${archive_path}" ]]; then
      t pack_runner.compression_failed_cli "${ARCHIVE_NAME}" >&2
      rm -f "${archive_path}"
      exit 1
    fi

    # Restreint aux seuls droits du propriétaire, par cohérence avec zgp-game-packer.sh.
    chmod 600 "${archive_path}"

    t pack_runner.done_cli "${archive_path}"
  else
    # --- MODE INTERACTIF : délégué à zgu_gui_compress_zstd (voir zgu-progress-utils.sh) :
    # pourcentage réel piloté par pv sur le flux tar d'entrée, exactement le même mécanisme
    # que le mode CLI ci-dessus. ---
    zgu_gui_compress_zstd "${runner_dir}" "${runner}" "${archive_path}" "${LEVEL}" \
      "$(t pack_runner.export_title "${ARCHIVE_NAME}")" \
      "$(t pack_runner.export_text "${LEVEL}")"
    compress_status=$?

    if [[ "${compress_status}" -eq 2 ]]; then
      zenity --info --title="$(t pack_runner.cancel_title)" --text="$(t pack_runner.cancel_text "${ARCHIVE_NAME}")" 2>/dev/null
      exit 0
    elif [[ "${compress_status}" -ne 0 ]]; then
      zenity --error --text="$(t pack_runner.compression_error "${ARCHIVE_NAME}")" 2>/dev/null
      exit 1
    fi
  fi

done

if [[ ${#cli_runners[@]} -eq 0 ]]; then
  notify-send "$(t pack_runner.notify_title)" "$(t pack_runner.notify_body "${OUTPUT_DIR}")" 2>/dev/null
else
  t pack_runner.cli_done
fi
exit 0
