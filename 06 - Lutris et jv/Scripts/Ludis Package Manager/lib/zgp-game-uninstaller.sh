#!/bin/bash

# --- Récupération des arguments du routeur lpm ---
# $1 = Flag de confirmation ("yes" si -y)
# $2, $3, ... = Liste des slugs de jeux cibles en CLI
confirm_flag="${1:-}"
shift || true
cli_games=("$@")

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"
# shellcheck source=./zgu-desktop-utils.sh
source "${script_dir}/zgu-desktop-utils.sh"

# Configuration des chemins Lutris
lutris_flatpak_db="${HOME}/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="${HOME}/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="${HOME}/.config/lutris/games"

lutris_flatpak_system_file="${HOME}/.var/app/net.lutris.Lutris/data/lutris/system.yml"
lutris_package_system_file="${HOME}/.config/lutris/system.yml"

games_dir="${HOME}/Games"

# 1. Vérifications de base (sqlite3 requis, zenity uniquement si mode interactif)
if ! command -v sqlite3 >/dev/null 2>&1; then
  if [[ ${#cli_games[@]} -gt 0 ]]; then
    t uninstall_game.sqlite_missing >&2
  else
    zenity --error --text="$(t uninstall_game.sqlite_missing)" 2>/dev/null
  fi
  exit 1
fi

# 2. Fermeture préalable de Lutris pour libérer la BDD
if flatpak list 2>/dev/null | grep -q lutris; then
  flatpak kill net.lutris.Lutris 2>/dev/null
fi
pkill -9 -x lutris 2>/dev/null
pkill -9 -f "/usr/bin/lutris" 2>/dev/null

# 3. Détection Flatpak vs Paquet natif (fonction fournie par zgu-lutris-utils.sh)
if check_flatpak_lutris_installed; then
  version="flatpak"
elif check_native_lutris_installed "${lutris_package_db}" ""; then
  version="package"
else
  if [[ ${#cli_games[@]} -gt 0 ]]; then
    t uninstall_game.lutris_missing >&2
  else
    zenity --error --text="$(t uninstall_game.lutris_missing)" 2>/dev/null
  fi
  exit 1
fi

case "${version}" in
  flatpak)
    lutris_system_file="${lutris_flatpak_system_file}"
    lutris_config_dir="${lutris_flatpak_config_dir}"
    lutris_db="${lutris_flatpak_db}"
    ;;
  package)
    lutris_system_file="${lutris_package_system_file}"
    lutris_config_dir="${lutris_package_config_dir}"
    lutris_db="${lutris_package_db}"
    ;;
  *)
    # Ne devrait jamais arriver : $version n'est affecté qu'à "flatpak" ou "package"
    # ci-dessus (sinon exit 1). Garde-fou si cette invariant venait à changer.
    echo "Erreur interne : version Lutris inattendue '${version}'." >&2
    exit 1
    ;;
esac

# Chemin Games personnalisé (si défini dans Lutris) : préférence globale stockée dans
# system.yml ("system: game_path:"), pas dans runners/wine.yml (options propres au runner
# Wine uniquement). Voir la même remarque détaillée dans zgp-game-installer.sh.
if [[ -f "${lutris_system_file}" ]]; then
  extracted_path=$(awk -F': ' '/^[[:space:]]*game_path:/ {print $2}' "${lutris_system_file}")
  if [[ -n "${extracted_path}" ]]; then
    games_dir="${extracted_path}"
  fi
fi

if [[ ! -f "${lutris_db}" ]]; then
  if [[ ${#cli_games[@]} -gt 0 ]]; then
    t uninstall_game.db_missing "${lutris_db}" >&2
  else
    zenity --error --text="$(t uninstall_game.db_missing "${lutris_db}")" 2>/dev/null
  fi
  exit 1
fi

# 4. Récupération des jeux Wine depuis la BDD Lutris
games_list=$(sqlite3 "${lutris_db}" "SELECT name || '|' || slug || '|' || directory FROM games WHERE runner='wine' ORDER BY name COLLATE NOCASE ASC;" 2>/dev/null)

if [[ -z "${games_list}" ]]; then
  if [[ ${#cli_games[@]} -gt 0 ]]; then
    t uninstall_game.none_found >&2
  else
    zenity --info --text="$(t uninstall_game.none_found)" 2>/dev/null
  fi
  exit 0
fi

declare -A slug_by_name
declare -A dir_by_name
declare -A name_by_slug

while IFS="|" read -r game_name game_slug game_dir; do
  [[ -z "${game_name}" ]] && continue
  
  [[ -z "${game_dir}" ]] && game_dir="${games_dir}/${game_slug}"

  slug_by_name["${game_name}"]="${game_slug}"
  dir_by_name["${game_name}"]="${game_dir}"
  name_by_slug["${game_slug}"]="${game_name}"
done <<< "${games_list}"

games_to_delete=()

# Supprime physiquement un préfixe de jeu, mais SEULEMENT s'il se résout bien en un
# sous-dossier direct de games_dir. "directory" en base Lutris peut provenir de N'IMPORTE
# QUEL jeu runner='wine' de la base, pas uniquement de ceux installés par lpm (jeu ajouté
# manuellement dans Lutris, base éditée à la main, entrée résiduelle après changement de
# dossier de jeux...) : sans cette vérification, un rm -rf aveugle sur cette valeur pouvait
# supprimer un dossier arbitraire du système si "directory" pointait hors de games_dir.
# Retourne 0 si supprimé (ou déjà absent), 1 si le chemin a été jugé dangereux (rien n'est
# supprimé dans ce cas, à l'appelant d'avertir l'utilisateur).
safe_delete_prefix_dir() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 0

  local real_dir real_games_dir
  real_dir=$(realpath -e "${dir}" 2>/dev/null)
  real_games_dir=$(realpath -e "${games_dir}" 2>/dev/null)

  if [[ -z "${real_dir}" ]] || [[ -z "${real_games_dir}" ]] || [[ "${real_dir}" != "${real_games_dir}/"* ]]; then
    return 1
  fi

  rm -rf "${real_dir}"
  return 0
}

# --- Mode CLI vs Mode Interactif ---
if [[ ${#cli_games[@]} -gt 0 ]]; then
  # --- MODE CLI (100% Terminal, zéro Zenity) ---
  for target_slug in "${cli_games[@]}"; do
    found_name="${name_by_slug[${target_slug}]}"
    if [[ -n "${found_name}" ]]; then
      games_to_delete+=("${found_name}")
    else
      # Recherche par correspondance partielle de slug
      matched_name=""
      for g_name in "${!slug_by_name[@]}"; do
        if [[ "${slug_by_name[${g_name}]}" = "${target_slug}" ]]; then
          matched_name="${g_name}"
          break
        fi
      done
      
      if [[ -n "${matched_name}" ]]; then
        games_to_delete+=("${matched_name}")
      else
        t uninstall_game.slug_not_found "${target_slug}" >&2
        exit 1
      fi
    fi
  done
else
  # --- MODE INTERACTIF (Avec Zenity) ---
  if ! command -v zenity >/dev/null 2>&1; then
    t uninstall_game.zenity_missing >&2
    exit 1
  fi

  zenity_args=()
  for g_name in "${!slug_by_name[@]}"; do
    zenity_args+=( "FALSE" "${g_name}" "${slug_by_name[${g_name}]}" )
  done

  selected_games=$(zenity --list --checklist \
    --title="$(t uninstall_game.select_title)" \
    --text="$(t uninstall_game.select_text)" \
    --column="$(t uninstall_game.select_col_delete)" --column="$(t uninstall_game.select_col_game)" --column="$(t uninstall_game.select_col_slug)" \
    "${zenity_args[@]}" \
    --width=650 --height=450 2>/dev/null)

  if [[ -z "${selected_games}" ]]; then
    exit 0
  fi

  IFS="|" read -r -a games_to_delete <<< "${selected_games}"
fi

# 6. Gestion de la confirmation
if [[ ${#cli_games[@]} -gt 0 ]]; then
  # En mode CLI, si le flag 'yes' n'est pas passé, on demande une confirmation textuelle dans le terminal
  if [[ "${confirm_flag}" != "yes" ]]; then
    t uninstall_game.confirm_cli_header
    for game_name in "${games_to_delete[@]}"; do
      t uninstall_game.confirm_cli_item "${game_name}" "${dir_by_name[${game_name}]}"
    done
    read -r -p "$(t uninstall_game.confirm_cli_prompt)" response
    case "${response}" in
      [nN])
        t uninstall_game.confirm_cli_cancelled
        exit 0
        ;;
      *)
        ;;
    esac
  fi
else
  # En mode interactif graphique
  summary_text="$(t uninstall_game.confirm_gui_header)"
  for game_name in "${games_to_delete[@]}"; do
    p_dir="${dir_by_name[${game_name}]}"
    summary_text+="$(t uninstall_game.confirm_gui_item "${game_name}" "${p_dir}")"
  done

  summary_text+="$(t uninstall_game.confirm_gui_footer)"

  if ! zenity --question --title="$(t uninstall_game.confirm_title)" \
    --text="${summary_text}" \
    --width=550 --height=350 2>/dev/null; then
    zenity --info --title="$(t uninstall_game.cancel_title)" --text="$(t uninstall_game.cancel_text)" 2>/dev/null
    exit 0
  fi
fi

# 7. Traitement de la suppression (avec affichage CLI textuel ou barre Zenity)
total_games=${#games_to_delete[@]}

if [[ ${#cli_games[@]} -gt 0 ]]; then
  # --- EXÉCUTION EN MODE CLI (Affichage textuel épuré) ---
  current=0
  for game_name in "${games_to_delete[@]}"; do
    current=$((current + 1))
    t uninstall_game.progress_cli "${current}" "${total_games}" "${game_name}"

    game_slug="${slug_by_name[${game_name}]}"
    # Échappement par cohérence avec zgp-game-installer.sh : ces slugs viennent de la base
    # Lutris elle-même (donc fiables en pratique), mais toute valeur interpolée dans une
    # requête SQL doit l'être de façon homogène dans tout le projet.
    safe_game_slug="${game_slug//\'/\'\'}"
    prefix_dir=$(sqlite3 "${lutris_db}" "SELECT directory FROM games WHERE slug='${safe_game_slug}';")
    [[ -z "${prefix_dir}" ]] && prefix_dir="${dir_by_name[${game_name}]}"

    # A. Suppression du préfixe physique sur le disque
    if ! safe_delete_prefix_dir "${prefix_dir}"; then
      t uninstall_game.unsafe_prefix_skip "${game_name}" "${prefix_dir}" >&2
    fi

    # B. Suppression de la configuration YML Lutris
    rm -f "${lutris_config_dir}/${game_slug}-"*.yml

    # C. Suppression de l'entrée dans la base de données SQLite
    sqlite3 "${lutris_db}" "DELETE FROM games WHERE slug='${safe_game_slug}';"

    # D. Suppression des raccourcis .desktop
    desktop_dir=$(zgu_get_desktop_dir)

    rm -f "${desktop_dir}/${game_slug}.desktop"
    rm -f "${desktop_dir}/${game_name} $(t install_game.bonus_folder_suffix)"
    rm -f "${HOME}/.local/share/applications/net.lutris.${game_slug}.desktop"
  done

  update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
  t uninstall_game.done_cli
else
  # --- EXÉCUTION EN MODE INTERACTIF (Barre de progression Zenity) ---
  (
    current=0
    for game_name in "${games_to_delete[@]}"; do
      current=$((current + 1))
      percent=$(( current * 100 / total_games ))
      
      echo "${percent}"
      t uninstall_game.progress_gui "${game_name}" "${current}" "${total_games}"

      game_slug="${slug_by_name[${game_name}]}"
      safe_game_slug="${game_slug//\'/\'\'}"
      prefix_dir=$(sqlite3 "${lutris_db}" "SELECT directory FROM games WHERE slug='${safe_game_slug}';")
      [[ -z "${prefix_dir}" ]] && prefix_dir="${dir_by_name[${game_name}]}"

      if ! safe_delete_prefix_dir "${prefix_dir}"; then
        t uninstall_game.unsafe_prefix_skip "${game_name}" "${prefix_dir}" >&2
      fi
      rm -f "${lutris_config_dir}/${game_slug}-"*.yml
      sqlite3 "${lutris_db}" "DELETE FROM games WHERE slug='${safe_game_slug}';"

      desktop_dir=$(zgu_get_desktop_dir)

      rm -f "${desktop_dir}/${game_slug}.desktop"
      rm -f "${desktop_dir}/${game_name} $(t install_game.bonus_folder_suffix)"
      rm -f "${HOME}/.local/share/applications/net.lutris.${game_slug}.desktop"
      
      sleep 0.3
    done

    echo "100"
    t uninstall_game.cleanup_gui
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    sleep 0.4

  ) | zenity --progress \
    --title="$(t uninstall_game.progress_gui_title)" \
    --text="$(t uninstall_game.progress_gui_text)" \
    --percentage=0 \
    --auto-close \
    --no-cancel 2>/dev/null

  notify-send "$(t uninstall_game.notify_title)" "$(t uninstall_game.notify_body)" 2>/dev/null
fi

exit 0
