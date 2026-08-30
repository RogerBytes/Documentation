#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./zgl-lang-loader.sh
source "${script_dir}/zgl-lang-loader.sh"
# shellcheck source=./zgu-lutris-utils.sh
source "${script_dir}/zgu-lutris-utils.sh"
# shellcheck source=./zgu-desktop-utils.sh
source "${script_dir}/zgu-desktop-utils.sh"
# shellcheck source=./zgu-progress-utils.sh
source "${script_dir}/zgu-progress-utils.sh"
# shellcheck source=./zgu-log-utils.sh
source "${script_dir}/zgu-log-utils.sh"

# --- Analyse des arguments transmis par bin/lpm ---
# $1 = mode ("click" = double-clic depuis le gestionnaire de fichiers, "cli" = commande
#      terminal explicite, vide/absent = menu interactif Zenity sans cible)
# $2 = confirm_flag ("yes" si -y)
# $3, $4... = cibles (fichiers .zgp)
mode="${1:-}"
shift || true
confirm_flag="${1:-}"
shift || true
cli_targets=("$@")
is_double_click=false
[[ "${mode}" = "click" ]] && is_double_click=true

# Configuration des chemins
lutris_flatpak_db="${HOME}/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="${HOME}/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="${HOME}/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="${HOME}/.config/lutris/games"

lutris_flatpak_system_file="${HOME}/.var/app/net.lutris.Lutris/data/lutris/system.yml"
lutris_package_system_file="${HOME}/.config/lutris/system.yml"

games_dir="${HOME}/Games"

# 1. Vérification des dépendances
# sqlite3, pv et bsdtar sont toujours nécessaires (CLI comme interactif). bsdtar (paquet
# "libarchive-tools" sur Debian/Ubuntu) remplace le tar GNU pour l'extraction : il refuse
# par défaut (ARCHIVE_EXTRACT_SECURE_NODOTDOT / ARCHIVE_EXTRACT_SECURE_SYMLINKS) tout membre
# d'archive tentant de sortir de son dossier de destination via "../" ou un lien symbolique
# piégé -- un .zgp est un paquet potentiellement partagé par un tiers, donc non fiable (voir
# la vérification de slug plus bas), et cette protection doit s'appliquer dès l'extraction,
# pas seulement après coup sur le nom du dossier de premier niveau. bsdtar lit le zstd
# nativement (libzstd liée en dur), donc zstd n'est plus une dépendance externe requise ici.
for cmd in sqlite3 pv bsdtar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    t install_game.cmd_missing "${cmd}"
    exit 1
  fi
done

# zenity n'est requis que si on va effectivement afficher une fenêtre : c'est le cas
# partout SAUF en mode CLI strict avec au moins une cible fournie sur la ligne de commande.
will_use_zenity=true
if [[ "${mode}" = "cli" ]] && [[ ${#cli_targets[@]} -gt 0 ]]; then
  will_use_zenity=false
fi
if [[ "${will_use_zenity}" = true ]] && ! command -v zenity >/dev/null 2>&1; then
  t install_game.zenity_missing
  exit 1
fi

# python3 lui-même est requis, distinctement de PyYAML ci-dessous : sans cette vérification
# séparée, une machine sans python3 du tout recevait le même message "PyYAML manquant" qu'une
# machine avec python3 mais sans le module, ce qui égarait l'utilisateur sur la vraie cause.
if ! command -v python3 >/dev/null 2>&1; then
  t install_game.cmd_missing "python3"
  exit 1
fi

# PyYAML est utilisé pour lire/écrire le YAML embarqué (zgp-game-config.yml) : sans lui,
# l'installation se poursuivait avant en silence avec un exécutable Lutris vide.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  if [[ "${will_use_zenity}" = true ]]; then
    zenity --error --text="$(t install_game.pyyaml_missing_gui)" 2>/dev/null
  fi
  t install_game.pyyaml_missing_cli >&2
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
  zenity --error --text="$(t install_game.lutris_missing_gui)" 2>/dev/null
  t install_game.lutris_missing_cli
  exit 1
fi

case "${version}" in
  flatpak)
    lutris_config_dir="${lutris_flatpak_config_dir}"
    lutris_db="${lutris_flatpak_db}"
    lutris_system_file="${lutris_flatpak_system_file}"
    ;;
  package)
    lutris_config_dir="${lutris_package_config_dir}"
    lutris_db="${lutris_package_db}"
    lutris_system_file="${lutris_package_system_file}"
    ;;
  *)
    # Ne devrait jamais arriver : $version n'est affecté qu'à "flatpak" ou "package"
    # ci-dessus (sinon exit 1). Garde-fou si cette invariant venait à changer.
    echo "Erreur interne : version Lutris inattendue '${version}'." >&2
    exit 1
    ;;
esac

# Chemin Games personnalisé (si défini dans Lutris) : cette préférence globale ("appliquée à
# tous les jeux", donc côté système et non côté runner Wine) vit dans system.yml, sous la clé
# "system: game_path:" -- PAS dans runners/wine.yml (qui ne contient que des options propres
# au runner Wine, comme system_winetricks/version). L'awk ne dépend pas de l'indentation ou
# de la clé parente : il matche n'importe quelle ligne "game_path:" (avec espaces de tête),
# donc il fonctionne tel quel une fois pointé vers le bon fichier.
if [[ -f "${lutris_system_file}" ]]; then
  extracted_path=$(awk -F': ' '/^[[:space:]]*game_path:/ {print $2}' "${lutris_system_file}")
  if [[ -n "${extracted_path}" ]]; then
    games_dir="${extracted_path}"
  fi
fi

mkdir -p "${lutris_config_dir}"
mkdir -p "$(dirname "${lutris_db}")"
mkdir -p "${games_dir}"

# ---------------------------------------------------------------------------------------------

games_to_install=()
declare -A filepath_by_name
create_menu=false
create_desktop=false

# Gestion Mode CLI strict vs Mode Interactif / Double-clic
if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
  # --- MODE CLI STRICT (depuis le terminal avec ou sans -y) ---
  for target in "${cli_targets[@]}"; do
    if [[ -f "${target}" ]]; then
      filename=$(basename "${target}" .zgp)
      games_to_install+=("${filename}")
      filepath_by_name["${filename}"]="${target}"
    else
      t install_game.file_not_found "${target}" >&2
      exit 1
    fi
  done

  # Gestion de la confirmation interactive si le flag -y n'est pas présent
  if [[ "${confirm_flag}" != "yes" ]]; then
    t install_game.confirm_cli_header
    for name in "${games_to_install[@]}"; do
      t install_game.confirm_cli_item "${name}" "${filepath_by_name[${name}]}"
    done
    read -r -p "$(t install_game.confirm_cli_prompt)" response
    case "${response}" in
      [nN])
        t install_game.cancelled_cli
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
  if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = true ]]; then
    search_dir="$(dirname "${cli_targets[0]}")"
  else
    if ! selected_file=$(zenity --file-selection --title="$(t install_game.file_selection_title)" --file-filter="$(t install_game.file_selection_filter_name) (*.zgp) | *.zgp" 2>/dev/null) || [[ -z "${selected_file}" ]]; then
        exit 0
    fi
    search_dir="$(dirname "${selected_file}")"
  fi

  shopt -s nullglob
  zgp_files=("${search_dir}"/*.zgp)

  if [[ ${#zgp_files[@]} -eq 0 ]]; then
      zenity --info --text="$(t install_game.no_zgp_found)" 2>/dev/null
      exit 0
  fi

  zenity_args=()
  for file in "${zgp_files[@]}"; do
    filename=$(basename "${file}" .zgp)
    filepath_by_name["${filename}"]="${file}"
    zenity_args+=( "TRUE" "${filename}" )
  done

  opt_menu_label="$(t install_game.shortcuts_opt_menu)"
  opt_desktop_label="$(t install_game.shortcuts_opt_desktop)"

  shortcuts_options=$(zenity --list --checklist --title="$(t install_game.shortcuts_title)" --text="$(t install_game.shortcuts_text)" --column="$(t install_game.shortcuts_col_create)" --column="$(t install_game.shortcuts_col_location)" --separator=$'\x1f' TRUE "${opt_menu_label}" TRUE "${opt_desktop_label}" --width=500 --height=220 2>/dev/null)

  if [[ "${shortcuts_options}" == *"${opt_menu_label}"* ]]; then
    create_menu=true
  fi
  if [[ "${shortcuts_options}" == *"${opt_desktop_label}"* ]]; then
    create_desktop=true
  fi

  selected_games=$(zenity --list --checklist --title="$(t install_game.select_title)" --text="$(t install_game.select_text)" --column="$(t install_game.select_col_install)" --column="$(t install_game.select_col_game)" --separator=$'\x1f' "${zenity_args[@]}" --width=600 --height=400 2>/dev/null)

  if [[ -z "${selected_games}" ]]; then
    exit 0
  fi

  IFS=$'\x1f' read -r -a games_to_install <<< "${selected_games}"
fi

# ---------------------------------------------------------------------------------------------

# Traitement de chaque jeu sélectionné
for name in "${games_to_install[@]}"; do
  filepath="${filepath_by_name[${name}]}"

  # 1. Extraction dans un dossier temporaire DIRECTEMENT dans $games_dir (renommage instantané garanti)
  temp_extract_dir=$(mktemp -d "${games_dir}/.zgp-extract-XXXXXX")
  file_size=$(stat -c %s "${filepath}" 2>/dev/null || stat -f %z "${filepath}" 2>/dev/null)

  if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
    t install_game.importing_cli "${name}"
    # bsdtar (et non tar -I zstd) : voir le commentaire sur la vérification des dépendances
    # plus haut dans ce fichier pour le détail des protections SECURE_NODOTDOT/SECURE_SYMLINKS.
    # umask 022 le temps de l'extraction : bsdtar préserve par défaut les bits de permission
    # d'origine de l'archive, sans "--no-same-permissions". Sans ce garde-fou, un .zgp
    # forgé par un tiers pouvait planter un fichier monde-inscriptible (777) dans le
    # dossier de jeux -- exploitable par un autre utilisateur local sur une machine
    # partagée -- ou un fichier illisible (000) pour saboter silencieusement l'installation.
    _lpm_old_umask=$(umask)
    umask 022
    pv -s "${file_size:-0}" "${filepath}" | bsdtar -xf - -C "${temp_extract_dir}"
    tar_exit="${PIPESTATUS[1]}"
    umask "${_lpm_old_umask}"
  else
    # Délégué à zgu_gui_extract_zstd (voir zgu-progress-utils.sh) : même mécanisme pv que
    # le bloc CLI ci-dessus, factorisé et partagé avec les autres scripts de lib/. Le statut
    # de sortie de Zenity est vérifié : une annulation (statut 2) doit être distinguée des
    # vrais échecs de tar plutôt que de tomber dans le même message "archive corrompue".
    zgu_gui_extract_zstd "${filepath}" "${temp_extract_dir}" \
      "$(t install_game.importing_gui_title "${name}")" \
      "$(t install_game.decompressing_gui_text)"
    extract_status=$?
    if [[ "${extract_status}" -eq 2 ]]; then
      rm -rf "${temp_extract_dir}"
      continue
    fi
    tar_exit="${ZGU_LAST_TAR_EXIT:-1}"
  fi

  # 1bis. Vérification de l'intégrité de l'extraction : si tar a échoué (archive corrompue,
  # tronquée ou invalide), on abandonne proprement ce jeu sans toucher à Lutris ni créer de raccourcis
  if [[ "${tar_exit}" -ne 0 ]]; then
    err_msg="$(t install_game.corrupt_archive "${name}" "${tar_exit}")"
    if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
      echo "${err_msg}" >&2
    else
      zenity --error --title="$(t install_game.corrupt_archive_title)" --text="${err_msg}" 2>/dev/null
    fi
    zgu_log "install" "ERREUR" "fichier=${name} raison=archive_corrompue code=${tar_exit}"
    rm -rf "${temp_extract_dir}"
    continue
  fi

  # 2. Découverte du véritable slug à partir de ce qui a été réellement extrait
  # find + head plutôt que "ls -1 | head -n 1" (SC2012) : comportement identique dans le
  # cas normal (un seul dossier top-level attendu), la protection réelle contre un nom de
  # fichier pathologique reste de toute façon assurée par les vérifications qui suivent
  # (-d, anti-symlink, realpath) plutôt que par ce choix de commande.
  slug=$(basename "$(find "${temp_extract_dir}" -mindepth 1 -maxdepth 1 | head -n 1)")
  if [[ -z "${slug}" ]] || [[ ! -d "${temp_extract_dir}/${slug}" ]]; then
    t install_game.slug_detect_failed "${name}" >&2
    zgu_log "install" "ERREUR" "fichier=${name} raison=slug_introuvable"
    rm -rf "${temp_extract_dir}"
    continue
  fi

  # 2bis. Durcissement anti-traversée : un .zgp est un paquet potentiellement partagé
  # par un tiers, donc non fiable. Un lien symbolique nommé comme entrée de premier
  # niveau dans l'archive (ex: pointant vers /etc ou $HOME) ferait passer le test
  # "-d" ci-dessus tout en pointant hors de $temp_extract_dir : on refuse tout lien
  # symbolique ici, et on vérifie en plus que le chemin réel résolu reste bien un
  # enfant direct de $temp_extract_dir avant de continuer.
  if [[ -L "${temp_extract_dir}/${slug}" ]]; then
    t install_game.slug_detect_failed "${name}" >&2
    zgu_log "install" "ERREUR" "fichier=${name} raison=slug_lien_symbolique"
    rm -rf "${temp_extract_dir}"
    continue
  fi
  # shellcheck disable=SC2249 # filtre de rejet, pas un dispatch : un slug qui ne matche
  # pas ces motifs dangereux continue normalement le traitement ci-dessous, c'est voulu.
  case "${slug}" in
    */*|.|..)
      t install_game.slug_detect_failed "${name}" >&2
      zgu_log "install" "ERREUR" "fichier=${name} raison=slug_traversee_chemin"
      rm -rf "${temp_extract_dir}"
      continue
      ;;
  esac

  # Rejet de tout caractère de contrôle (saut de ligne, retour chariot...) dans le slug :
  # un nom de dossier Linux peut légalement en contenir, et slug sert de repli pour
  # icon_path, lui-même injecté tel quel dans le fichier .desktop généré plus bas
  # ("Icon=${icon_path}"). Sans ce filtre, un \n dans le slug d'un .zgp forgé par un tiers
  # pouvait ajouter une ligne "Exec=" arbitraire dans le .desktop -- qui, marqué
  # "metadata::trusted true" à la création, s'exécute sans avertissement au double-clic.
  # Même risque déjà mitigé pour game_real_name plus bas ; slug suit exactement le même
  # chemin et doit être filtré de façon identique, ici en amont, par rejet plutôt que
  # nettoyage a posteriori.
  case "${slug}" in
    *[$'\n\r\t']*)
      t install_game.slug_detect_failed "${name}" >&2
      zgu_log "install" "ERREUR" "fichier=${name} raison=slug_caractere_controle"
      rm -rf "${temp_extract_dir}"
      continue
      ;;
  esac
  real_slug_dir=$(realpath -e "${temp_extract_dir}/${slug}" 2>/dev/null)
  real_temp_dir=$(realpath -e "${temp_extract_dir}" 2>/dev/null)
  if [[ -z "${real_slug_dir}" ]] || [[ -z "${real_temp_dir}" ]] || [[ "${real_slug_dir%/*}" != "${real_temp_dir}" ]]; then
    t install_game.slug_detect_failed "${name}" >&2
    zgu_log "install" "ERREUR" "fichier=${name} raison=slug_chemin_reel_invalide"
    rm -rf "${temp_extract_dir}"
    continue
  fi

  prefix_dir="${games_dir}/${slug}"

  # 3. Vérification stricte : si le préfixe existe déjà, on refuse catégoriquement l'installation
  if [[ -d "${prefix_dir}" ]]; then
    err_msg="$(t install_game.already_installed "${slug}")"
    if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
      echo "${err_msg}" >&2
    else
      zenity --error --title="$(t install_game.already_installed_title)" --text="${err_msg}" 2>/dev/null
    fi
    zgu_log "install" "ERREUR" "fichier=${name} slug=${slug} raison=deja_installe"
    rm -rf "${temp_extract_dir}"
    continue
  fi

  # 4. Déplacement définitif instantané (0 seconde)
  if ! mv "${temp_extract_dir}/${slug}" "${games_dir}/"; then
    err_msg="$(t install_game.move_failed "${name}")"
    if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
      echo "${err_msg}" >&2
    else
      zenity --error --title="$(t install_game.move_failed_title)" --text="${err_msg}" 2>/dev/null
    fi
    zgu_log "install" "ERREUR" "fichier=${name} slug=${slug} raison=deplacement_echoue"
    rm -rf "${temp_extract_dir}"
    continue
  fi
  rm -rf "${temp_extract_dir}"

  run_post_install() {
    t install_game.analyzing "${name}"

    timestamp=$(date +%s%N)
    config_id="${slug}-${timestamp}"

    meta_json="${prefix_dir}/zgp-meta.json"
    game_real_name=""

    if [[ -f "${meta_json}" ]]; then
      # Pas de test "command -v python3" ici : python3 est déjà vérifié comme dépendance
      # obligatoire en tête de script (le script quitte sinon), donc toujours présent à ce stade.
      # $meta_json dérive de $slug, potentiellement forgé par quiconque a créé le
      # paquet .zgp partagé (voir la même remarque plus bas concernant l'échappement
      # SQL) : passé via l'environnement plutôt qu'interpolé dans le code Python, pour
      # qu'une apostrophe ou tout autre caractère spécial dans le nom du dossier extrait
      # ne puisse plus casser la chaîne littérale et injecter du code Python arbitraire.
      game_real_name=$(META_JSON="${meta_json}" python3 -c '
import json, os
try:
    with open(os.environ["META_JSON"]) as f:
        print(json.load(f).get("game_real_name", ""))
except Exception:
    pass
' 2>/dev/null)
    fi

    rm -f "${meta_json}"

    # game_real_name vient d'un zgp-meta.json potentiellement forgé par quiconque a créé
    # le paquet .zgp partagé (voir remarque plus haut sur l'échappement SQL/Python). Cette
    # valeur est ensuite réutilisée telle quelle dans le fichier .desktop généré plus bas
    # ("Name=${game_real_name}") et dans bonus_dir_name : un saut de ligne injecté ici
    # pourrait ajouter une clé "Exec=" arbitraire dans le .desktop (exécution de commande
    # au clic sur le raccourci), et un "/" ou "../" pourrait faire sortir le rm -rf de
    # bonus_dir_name de desktop_dir. On retire donc tout caractère de contrôle (CR/LF en
    # tête) et tout séparateur de chemin avant toute autre utilisation de cette variable.
    game_real_name="${game_real_name//[$'\n\r']/ }"
    game_real_name="${game_real_name//\//-}"

    [[ -z "${game_real_name}" ]] && game_real_name="${name}"

    t install_game.processing_registry
    for reg in "system.reg" "user.reg" "userdef.reg" "lutris.json"; do
      if [[ -f "${prefix_dir}/${reg}" ]]; then
        sed -i "s|anonuser|${USER}|g" "${prefix_dir}/${reg}"
      fi
    done

    # find + head -n 1 plutôt qu'un glob passé tel quel à basename : si "Games/" contient
    # plusieurs sous-dossiers, basename recevait plusieurs arguments et interprétait le
    # second comme un suffixe à retirer du premier (voire échouait avec "extra operand"
    # sur 3+ dossiers), ce qui pouvait faire sauter silencieusement ce patch goglog.ini.
    # Même mécanisme que dans zgp-game-packer.sh pour rester cohérent.
    gamefolder=$(basename "$(find "${prefix_dir}/drive_c/Games" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n 1)")
    if [[ -n "${gamefolder}" ]]; then
      ini_parent_dir="${prefix_dir}/drive_c/Games/${gamefolder}"
      goglog="${ini_parent_dir}/goglog.ini"
      if [[ -f "${goglog}" ]]; then
        sed -i "s|anonuser|${USER}|g" "${goglog}"
      fi
    fi

    mkdir -p "${prefix_dir}/dosdevices"
    ln -sf "../drive_c" "${prefix_dir}/dosdevices/c:"
    if [[ ! -e "${prefix_dir}/pfx" ]]; then
      ln -sf "." "${prefix_dir}/pfx"
    fi

    # "Local Settings" (jonction/dossier hérité de Windows XP, sous le profil steamuser) : même
    # nettoyage idempotent qu'à l'empaquetage (zgp-game-packer.sh), nécessaire ici aussi pour
    # les .zgp déjà empaquetés avant ce correctif -- ne fait rien s'il est déjà absent.
    local_settings_dir="${prefix_dir}/drive_c/users/steamuser/Local Settings"
    [[ -e "${local_settings_dir}" || -L "${local_settings_dir}" ]] && rm -rf -- "${local_settings_dir}"

    t install_game.registering_lutris
    safe_name="${game_real_name//\'/\'\'}"
    # slug et config_id dérivent du nom du dossier extrait de l'archive .zgp (voir plus haut :
    # slug=$(ls -1 "$temp_extract_dir" | head -n 1)), donc potentiellement forgés par quiconque a
    # créé le paquet .zgp partagé, pas seulement par l'utilisateur local. Sans échappement, un nom
    # de dossier contenant une apostrophe permettait une injection SQL dans les requêtes ci-dessous.
    safe_slug="${slug//\'/\'\'}"
    safe_config_id="${config_id//\'/\'\'}"
    
    bundled_yml="${prefix_dir}/zgp-game-config.yml"
    yml_config_file="${lutris_config_dir}/${config_id}.yml"

    executable_path=""

    if [[ -f "${bundled_yml}" ]]; then
      BUN_YML="${bundled_yml}" YML_OUT="${yml_config_file}" PFX_DIR="${prefix_dir}" USER_HOME="${HOME}" ERR_YAML_LABEL="$(t install_game.yaml_processing_error)" python3 -c '
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

        # zgp-game-config.yml vient du paquet .zgp partage, potentiellement forge par
        # quiconque l a cree (meme remarque que pour game_real_name/safe_slug plus haut) --
        # voire edite a la main pour y glisser un hook. Lutris execute automatiquement
        # tout ce qui ressemble a une commande/script au lancement ou a la fermeture du
        # jeu (prelaunch_script/postexit_script sous "game", prelaunch_command/
        # postexit_command sous "system"), sans aucune confirmation demandee a
        # l utilisateur. Plutot qu une liste figee de noms de cles connus (qui ne
        # couvrirait pas un futur hook Lutris ni une cle ajoutee a la main sous une
        # autre section), on retire recursivement, dans TOUT le YAML, toute cle dont le
        # nom se termine par "_command"/"_script"/"_wait" ou contient "exec". Ce filtre
        # ne touche pas system.env (LD_PRELOAD, WINEDLLOVERRIDES, etc.) : ces variables
        # sont un usage legitime tres courant (gamemode, mangohud, overrides DXVK...)
        # qu on ne peut pas distinguer d une valeur malveillante sans whitelist de
        # valeurs, donc on les laisse volontairement intactes.
        def strip_exec_hooks(obj):
            if isinstance(obj, dict):
                cleaned = {}
                for k, v in obj.items():
                    kl = k.lower() if isinstance(k, str) else ""
                    if kl.endswith("_command") or kl.endswith("_script") or kl.endswith("_wait") or "exec" in kl:
                        continue
                    cleaned[k] = strip_exec_hooks(v)
                return cleaned
            elif isinstance(obj, list):
                return [strip_exec_hooks(v) for v in obj]
            return obj

        data = strip_exec_hooks(data)

        if "game" not in data:
            data["game"] = {}
        data["game"]["prefix"] = os.environ["PFX_DIR"]

        with open(os.environ["YML_OUT"], "w") as f:
            yaml.dump(data, f, sort_keys=False)
except Exception as e:
    err_label = os.environ.get("ERR_YAML_LABEL", "YAML processing error")
    print(f"{err_label}: {e}")
' 2>/dev/null
      rm -f "${bundled_yml}"

      # Chemin de l'exécutable relu depuis le YAML DÉJÀ PATCHÉ (game.prefix, "$GAMEDIR"
      # et "/home/<user>" déjà résolus vers cette machine ci-dessus), et non depuis le YAML
      # brut embarqué dans le paquet : sinon le "$GAMEDIR" littéral (ou le "anonuser" du
      # paquetage) se retrouverait tel quel dans la base Lutris, pointant vers un chemin
      # inexistant dès qu'on installe sur une autre machine ou un dossier de jeux différent
      # de celui de la machine ayant créé le paquet.
      if [[ -f "${yml_config_file}" ]]; then
        executable_path=$(YML_OUT="${yml_config_file}" python3 -c '
import os, yaml
try:
    with open(os.environ["YML_OUT"], "r") as f:
        data = yaml.safe_load(f)
    if isinstance(data, dict):
        print(data.get("game", {}).get("exe", ""))
except Exception:
    pass
' 2>/dev/null)
      fi
    fi

    if [[ ! -f "${yml_config_file}" ]]; then
      t install_game.yml_missing
    fi

    if [[ "${executable_path}" != /* ]]; then
      executable_path="${prefix_dir}/${executable_path}"
    fi

    safe_prefix_dir="${prefix_dir//\'/\'\'}"
    safe_executable_path="${executable_path//\'/\'\'}"

    sqlite3 "${lutris_db}" "DELETE FROM games WHERE slug='${safe_slug}';"
    sqlite3 "${lutris_db}" <<EOF
INSERT INTO games (name, slug, installer_slug, parent_slug, runner, executable, directory, configpath, updated, installed, installed_at)
VALUES (
  '${safe_name}',
  '${safe_slug}',
  '${safe_slug}',
  '',
  'wine',
  '${safe_executable_path}',
  '${safe_prefix_dir}',
  '${safe_config_id}',
  strftime('%s','now'),
  1,
  strftime('%s','now')
);
EOF

    icon_path="lutris_${slug}"
    if [[ -d "${prefix_dir}/icon" ]]; then
      icon_file=$(find "${prefix_dir}/icon" -maxdepth 1 -type f \( -name "*.png" -o -name "*.ico" -o -name "*.svg" -o -name "*.xpm" \) -print -quit 2>/dev/null)
      # icon_file est un nom de fichier réel extrait du .zgp (donc potentiellement forgé par
      # un tiers, comme slug plus haut) et injecté tel quel dans "Icon=${icon_path}" du .desktop
      # généré plus bas : un \n dans ce nom de fichier pourrait ajouter une ligne "Exec="
      # arbitraire, avec le même impact que pour slug (exécution silencieuse au double-clic,
      # le .desktop étant marqué "metadata::trusted true"). Même filtre que pour slug.
      icon_file="${icon_file//[$'\n\r\t']/}"
      [[ -n "${icon_file}" ]] && icon_path="${icon_file}"
    fi

    t install_game.creating_shortcuts
    game_id=$(sqlite3 "${lutris_db}" "SELECT id FROM games WHERE slug='${safe_slug}';")
    desktop_dir=$(zgu_get_desktop_dir)

    if [[ "${version}" = "flatpak" ]]; then
      exec_cmd="env LUTRIS_SKIP_INIT=1 flatpak run net.lutris.Lutris lutris:rungameid/${game_id}"
    else
      exec_cmd="env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/${game_id}"
    fi

    shortcut_content="[Desktop Entry]
Type=Application
Name=${game_real_name}
Icon=${icon_path}
Exec=${exec_cmd}
Categories=Game"

    if [[ "${create_menu}" = true ]]; then
      mkdir -p "${HOME}/.local/share/applications"
      echo "${shortcut_content}" > "${HOME}/.local/share/applications/net.lutris.${slug}.desktop"
      update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    fi

    if [[ "${create_desktop}" = true ]] && [[ -d "${desktop_dir}" ]]; then
      echo "${shortcut_content}" > "${desktop_dir}/${slug}.desktop"
      chmod +x "${desktop_dir}/${slug}.desktop"
      gio set "${desktop_dir}/${slug}.desktop" metadata::trusted true 2>/dev/null || true

      if [[ -d "${prefix_dir}/extras" ]]; then
        bonus_dir_name="${game_real_name} $(t install_game.bonus_folder_suffix)"
        rm -rf "${desktop_dir}/${bonus_dir_name:?}"
        ln -s "${prefix_dir}/extras" "${desktop_dir}/${bonus_dir_name}"
      fi
    fi

    zgu_log "install" "OK" "slug=${slug} nom=${game_real_name}"
    t install_game.finalizing
  }

  if [[ ${#cli_targets[@]} -gt 0 ]] && [[ "${is_double_click}" = false ]]; then
    run_post_install
  else
    (
      run_post_install
      sleep 0.3
    ) | zenity --progress --title="$(t install_game.configuring_gui_title "${name}")" --text="$(t install_game.post_extraction_text)" --pulsate --auto-close --width=500 2>/dev/null
  fi
done

notify-send "$(t install_game.notify_title)" "$(t install_game.notify_body)" 2>/dev/null
exit 0
