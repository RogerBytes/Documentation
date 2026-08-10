#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-github-release-utils.sh
source "${script_dir}/zgu-github-release-utils.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"
# shellcheck source=./zgu-progress-utils.sh
source "${script_dir}/zgu-progress-utils.sh"

# --- Récupération des arguments du routeur lpm ---
# $1 = mode ("cli" depuis le terminal, "gui" ou vide depuis le menu Zenity)
mode="${1:-gui}"

# Configuration des chemins Lutris
lutris_flatpak_db="${HOME}/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="${HOME}/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="${HOME}/.config/lutris/games"

lutris_flatpak_runner_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="${HOME}/.local/share/lutris/runners/wine"

# GITHUB_RELEASE_URL est désormais définie dans zgu-github-release-utils.sh (sourcé plus haut),
# seul endroit à modifier pour changer le dépôt/la release des runners.

say() {
  if [[ "${mode}" = "cli" ]]; then
    echo "$1"
  else
    zenity --info --text="$1" --width=450 2>/dev/null
  fi
}

say_err() {
  if [[ "${mode}" = "cli" ]]; then
    echo "$1" >&2
  else
    zenity --error --text="$1" --width=450 2>/dev/null
  fi
}

# 1. Vérification des dépendances nécessaires
# bsdtar (paquet "libarchive-tools" sur Debian/Ubuntu) remplace tar -I zstd pour l'extraction
# des runners téléchargés : ses protections par défaut ARCHIVE_EXTRACT_SECURE_NODOTDOT /
# ARCHIVE_EXTRACT_SECURE_SYMLINKS refusent tout membre d'archive tentant de sortir de son
# dossier de destination via "../" ou un lien symbolique piégé. bsdtar lit le zstd nativement
# (libzstd liée en dur), donc zstd externe n'est plus nécessaire pour ce script.
for cmd in sqlite3 python3 bsdtar sha256sum; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    say_err "$(t check.cmd_missing "${cmd}")"
    exit 1
  fi
done

if [[ "${mode}" != "cli" ]] && ! command -v zenity >/dev/null 2>&1; then
  t check.zenity_missing_gui >&2
  exit 1
fi

# pv n'est requis ici qu'en mode GUI : extract_gui() (plus bas) délègue à
# zgu_gui_extract_zstd (voir zgu-progress-utils.sh), qui appelle pv SANS repli possible en son
# absence (contrairement à extract_cli() juste en dessous, qui bascule proprement sur un appel
# bsdtar direct si pv est absent). Sans cette vérification, un pv manquant en mode GUI faisait
# échouer l'extraction avec un message générique "runner non résolu", sans jamais indiquer que
# la vraie cause était pv manquant.
if [[ "${mode}" != "cli" ]] && ! command -v pv >/dev/null 2>&1; then
  say_err "$(t check.cmd_missing "pv")"
  exit 1
fi

# Le module PyYAML est requis pour lire la clé wine.version des YAML des jeux installés.
# Sans lui, chaque jeu était silencieusement traité comme n'ayant aucun runner requis,
# ce qui rendait `lpm check` inutile sans jamais le signaler.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  say_err "$(t check.pyyaml_missing)"
  exit 1
fi

# 2. Détection Flatpak vs Paquet natif (fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  lutris_db="${lutris_flatpak_db}"
  lutris_config_dir="${lutris_flatpak_config_dir}"
  runner_dir="${lutris_flatpak_runner_dir}"
elif check_native_lutris_installed "${lutris_package_db}" "${lutris_package_runner_dir}"; then
  lutris_db="${lutris_package_db}"
  lutris_config_dir="${lutris_package_config_dir}"
  runner_dir="${lutris_package_runner_dir}"
else
  say_err "$(t check.lutris_missing)"
  exit 1
fi

if [[ ! -f "${lutris_db}" ]]; then
  say_err "$(t check.db_missing "${lutris_db}")"
  exit 1
fi

mkdir -p "${runner_dir}"

# ---------------------------------------------------------------------------------------------
# 3. Détermination des runners requis par les jeux installés (clé wine.version des YAML)
# ---------------------------------------------------------------------------------------------

games_list=$(sqlite3 "${lutris_db}" "SELECT name || char(31) || slug || char(31) || configpath FROM games WHERE runner='wine';" 2>/dev/null)

declare -A games_needing_runner   # runner_name -> "jeu1, jeu2, ..."
required_runners=()

while IFS=$'\x1f' read -r game_name game_slug configpath; do
  [[ -z "${game_slug}" ]] && continue
  [[ -z "${configpath}" ]] && continue

  yml_path="${lutris_config_dir}/${configpath}.yml"
  [[ -f "${yml_path}" ]] || continue

  required_runner=$(YML_PATH="${yml_path}" python3 -c '
import os, yaml
try:
    with open(os.environ["YML_PATH"], "r") as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        print(data.get("wine", {}).get("version", ""))
except Exception:
    pass
' 2>/dev/null)

  [[ -z "${required_runner}" ]] && continue

  if [[ -z "${games_needing_runner[${required_runner}]}" ]]; then
    games_needing_runner["${required_runner}"]="${game_name}"
    required_runners+=("${required_runner}")
  else
    games_needing_runner["${required_runner}"]="${games_needing_runner[${required_runner}]}, ${game_name}"
  fi
done <<< "${games_list}"

if [[ ${#required_runners[@]} -eq 0 ]]; then
  say "$(t check.no_games_reference_runner)"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# 4. Comparaison avec les runners réellement installés
# ---------------------------------------------------------------------------------------------

missing_runners=()
for runner_name in "${required_runners[@]}"; do
  if [[ ! -d "${runner_dir}/${runner_name}" ]]; then
    missing_runners+=("${runner_name}")
  fi
done

if [[ ${#missing_runners[@]} -eq 0 ]]; then
  say "$(t check.all_runners_present)"
  exit 0
fi

if [[ "${mode}" = "cli" ]]; then
  t check.missing_detected_header
  for r in "${missing_runners[@]}"; do
    t check.missing_detected_item "${r}" "${games_needing_runner[${r}]}"
  done
  echo ""
fi

# ---------------------------------------------------------------------------------------------
# 5. Récupération unique de la liste des assets de la release GitHub (avec taille et digest SHA256)
# ---------------------------------------------------------------------------------------------

declare -A release_asset_url     # runner_name (sans .zgr) -> url de téléchargement
declare -A release_asset_size    # runner_name (sans .zgr) -> taille en octets
declare -A release_asset_digest  # runner_name (sans .zgr) -> "sha256:<hash>" (vide si non fourni par GitHub)

api_url=$(zgu_github_api_url "${GITHUB_RELEASE_URL}")
release_json=$(zgu_fetch_url "${api_url}")

if [[ -n "${release_json}" ]]; then
  parsed_assets=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        url = asset.get("browser_download_url", "")
        size = asset.get("size", 0)
        digest = asset.get("digest") or ""
        if name.endswith(".zgr"):
            print(f"{name}\x1f{url}\x1f{size}\x1f{digest}")
except Exception:
    pass
' "${release_json}" 2>/dev/null)

  while IFS=$'\x1f' read -r asset_name download_url asset_size asset_digest; do
    [[ -z "${asset_name}" ]] && continue
    release_asset_url["${asset_name%.zgr}"]="${download_url}"
    release_asset_size["${asset_name%.zgr}"]="${asset_size}"
    release_asset_digest["${asset_name%.zgr}"]="${asset_digest}"
  done <<< "${parsed_assets}"
fi

# ---------------------------------------------------------------------------------------------
# 6. Fonctions de téléchargement et d'extraction avec barres de progression réelles
# ---------------------------------------------------------------------------------------------

download_cli() {
  local url="$1" runner_name="$2"
  local dest
  # Pas de "-u" : "-u" se contente de choisir un nom sans créer le fichier, laissant une
  # fenêtre entre le choix du nom et l'écriture par wget/curl pendant laquelle un autre
  # utilisateur du même systeme peut y placer un lien symbolique dans /tmp (partagé, world-
  # writable) et rediriger l'écriture vers un chemin arbitraire (TOCTOU classique). Sans
  # "-u", mktemp crée réellement le fichier tout de suite, de façon atomique et sous nos
  # seuls droits, avant tout téléchargement dedans.
  dest=$(mktemp "/tmp/${runner_name}-XXXXXX.zgr")

  t check.download_cli_start "${runner_name}" >&2
  if command -v wget >/dev/null 2>&1; then
    wget --show-progress -O "${dest}" "${url}"
  else
    curl -Lf -# -o "${dest}" "${url}"
  fi

  if [[ ! -f "${dest}" ]] || [[ ! -s "${dest}" ]]; then
    rm -f "${dest}"
    return 1
  fi
  echo "${dest}"
}

# Mince wrapper autour de zgu_gui_download (voir zgu-progress-utils.sh) : téléchargement
# piloté par pv, pourcentage réel quand la taille de l'asset est connue, sans aucun
# balayage disque périodique. Conserve le même contrat qu'avant pour l'appelant : imprime
# le chemin du fichier téléchargé sur stdout en cas de succès uniquement.
download_gui() {
  local url="$1" runner_name="$2" expected_size="${3:-0}"
  local dest
  # Voir le commentaire dans download_cli() ci-dessus : pas de "-u", même raison.
  dest=$(mktemp "/tmp/${runner_name}-XXXXXX.zgr")

  zgu_gui_download "${url}" "${dest}" "${expected_size}" \
    "$(t check.download_gui_title "${runner_name}")" \
    "$(t check.download_gui_text)"
  local status=$?

  [[ "${status}" -eq 0 ]] && echo "${dest}"
  return "${status}"
}

# Vérifie le SHA256 d'une archive téléchargée par rapport au digest de la release GitHub
# (calcul factorisé dans zgu_sha256_matches, voir lib/zgu-github-release-utils.sh).
# Retourne 0 si la vérification passe (ou si aucun digest n'est disponible pour cet asset),
# 1 si le digest est présent mais ne correspond pas.
verify_checksum() {
  local archive_path="$1" runner_name="$2"
  local expected_digest="${release_asset_digest[${runner_name}]}"

  if ! zgu_sha256_matches "${archive_path}" "${expected_digest}"; then
    say_err "$(t check.checksum_invalid "${runner_name}")"
    return 1
  fi
  return 0
}

extract_cli() {
  local archive_path="$1" runner_name="$2"
  t check.extract_cli_start "${runner_name}"
  local archive_size
  archive_size=$(stat -c%s "${archive_path}" 2>/dev/null || stat -f%z "${archive_path}" 2>/dev/null)
  if command -v pv >/dev/null 2>&1; then
    pv -s "${archive_size:-0}" "${archive_path}" | bsdtar -xf - -C "${runner_dir}"
    local tar_exit="${PIPESTATUS[1]}"
  else
    bsdtar -xf "${archive_path}" -C "${runner_dir}"
    local tar_exit=$?
  fi
  [[ "${tar_exit}" -eq 0 ]] && [[ -d "${runner_dir}/${runner_name}" ]]
}

# Mince wrapper autour de zgu_gui_extract_zstd (voir zgu-progress-utils.sh) : pourcentage
# réel piloté par pv sur le flux compressé d'entrée, aucun balayage périodique du dossier
# de sortie (contrairement à l'ancien "du -sb" toutes les 0.2s, coûteux sur un runner
# volumineux). Sur annulation ou échec, nettoie la cible avant de retourner, comme avant.
extract_gui() {
  local archive_path="$1" runner_name="$2"
  local target_dir="${runner_dir}/${runner_name}"

  zgu_gui_extract_zstd "${archive_path}" "${runner_dir}" \
    "$(t check.extract_gui_title "${runner_name}")" \
    "$(t check.extract_gui_text)"
  local status=$?

  if [[ "${status}" -ne 0 ]]; then
    rm -rf "${target_dir}"
    return 1
  fi

  [[ -d "${target_dir}" ]]
}

# ---------------------------------------------------------------------------------------------
# 7. Traitement de chaque runner manquant : recherche distante uniquement, pas de question locale
# ---------------------------------------------------------------------------------------------

resolved_runners=()
unresolved_runners=()

for runner_name in "${missing_runners[@]}"; do
  install_ok=false

  if [[ -n "${release_asset_url[${runner_name}]}" ]]; then
    if [[ "${mode}" = "cli" ]]; then
      archive_path=$(download_cli "${release_asset_url[${runner_name}]}" "${runner_name}")
    else
      archive_path=$(download_gui "${release_asset_url[${runner_name}]}" "${runner_name}" "${release_asset_size[${runner_name}]}")
    fi

    if [[ -n "${archive_path}" ]]; then
      if verify_checksum "${archive_path}" "${runner_name}"; then
        if [[ "${mode}" = "cli" ]]; then
          extract_cli "${archive_path}" "${runner_name}" && install_ok=true
        else
          extract_gui "${archive_path}" "${runner_name}" && install_ok=true
        fi
      fi
      rm -f "${archive_path}"
    fi
  fi

  if [[ "${install_ok}" = true ]]; then
    resolved_runners+=("${runner_name}")
    [[ "${mode}" = "cli" ]] && t check.runner_installed_success "${runner_name}"
  else
    unresolved_runners+=("${runner_name}")
  fi
done

# ---------------------------------------------------------------------------------------------
# 8. Récapitulatif final
# ---------------------------------------------------------------------------------------------

if [[ ${#unresolved_runners[@]} -eq 0 ]]; then
  say "$(t check.all_resolved "${resolved_runners[*]}")"
  exit 0
fi

# Bloc de noms bruts, un par ligne, pour copier-coller facilement
recap_names=""
for r in "${unresolved_runners[@]}"; do
  recap_names+="${r}
"
done

recap_details=""
for r in "${unresolved_runners[@]}"; do
  recap_details+="$(t check.unresolved_detail_item "${r}" "${games_needing_runner[${r}]}")
"
done

if [[ "${mode}" = "cli" ]]; then
  echo ""
  echo "=== $(t check.unresolved_header_cli) ==="
  echo "${recap_names}"
  t check.detail_label
  echo "${recap_details}"
  t check.manual_install_hint
else
  full_text="$(t check.unresolved_header_gui)

${recap_names}
$(t check.detail_label)
${recap_details}
$(t check.manual_install_hint)"

  echo "${full_text}" | zenity --text-info --title="$(t check.unresolved_gui_title)" --width=550 --height=400 2>/dev/null
fi

exit 0
