#!/bin/bash

# --- Utilitaires partagés pour la détection de l'installation Lutris (Flatpak vs paquet natif) ---
#
# check_flatpak_lutris_installed() est utilisée par les 9 fichiers de lib/ qui ont besoin
# de savoir si Lutris est installé (zgc-dependency-checker.sh, zgp-game-installer.sh,
# zgp-game-lister.sh, zgp-game-uninstaller.sh, zgr-runner-installer.sh, zgr-runner-lister.sh,
# zgr-runner-packer.sh, zgr-runner-remote-lister.sh, zgr-runner-uninstaller.sh). Une seule
# définition, sourcée par tous les appelants, garantit qu'une correction de la détection
# s'applique partout à la fois : une détection basée sur la simple existence de fichiers
# résiduels (pga.db, dossier games/) plutôt que sur l'application réellement installée
# risquerait de lire la mauvaise base de données si un ancien profil Flatpak ou natif traîne
# encore sur le disque après un changement de méthode d'installation.
#
# Ce fichier ne fait AUCUN affichage (pas de zenity, pas d'echo) : c'est une pure fonction de
# détection, chaque appelant reste responsable de la résolution des chemins qui en dépendent.

# Retourne 0 (vrai) si Lutris est installé via Flatpak, 1 (faux) sinon (paquet natif ou absent).
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

# Retourne 0 (vrai) si Lutris semble installé en paquet natif (par opposition à Flatpak),
# 1 (faux) sinon. Cette détection centralisée combine trois signaux (command -v lutris,
# existence de pga.db, existence du dossier des runners Wine natif) : se limiter à un seul
# signal laisserait passer les cas où le binaire "lutris" n'est pas dans le PATH (installation
# non standard, profil résiduel après désinstallation, etc.), et une détection incohérente
# entre les fichiers de lib/ ferait échouer certaines commandes de lpm avec "Lutris introuvable"
# alors que d'autres fonctionneraient, pour la même machine dans le même état.
#
# Chaque appelant passe les chemins qu'il a sous la main (chaîne vide pour ceux qu'il n'a
# pas) ; n'importe quel signal positif suffit à confirmer une installation native.
check_native_lutris_installed() {
  local package_db="$1"
  local package_runner_dir="$2"

  command -v lutris >/dev/null 2>&1 && return 0
  [[ -n "${package_db}" ]] && [[ -f "${package_db}" ]] && return 0
  [[ -n "${package_runner_dir}" ]] && [[ -d "${package_runner_dir}" ]] && return 0
  return 1
}

# Retourne (sur stdout) le runner Wine/Proton par défaut configuré globalement dans
# Lutris (clé "version:" de runners/wine.yml, quel que soit l'emplacement Flatpak ou
# paquet natif), ou "proton-cachyos-x86_64" si aucun fichier n'est trouvé ou lisible.
#
# Utilisée par zgp-game-installer.sh et zgp-game-packer.sh : une seule définition garantit
# que le runner de repli par défaut reste identique partout si jamais il doit être changé.
zgu_get_default_runner() {
  local runners_path found=""
  for runners_path in \
    "${HOME}/.local/share/lutris/runners/wine.yml" \
    "${HOME}/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml" \
    "${HOME}/.config/lutris/runners/wine.yml"; do
    if [[ -f "${runners_path}" ]]; then
      found=$(awk -F': ' '/^[[:space:]]*version:/ {print $2; exit}' "${runners_path}" | tr -d '"'\''[:space:]')
      [[ -n "${found}" ]] && break
    fi
  done
  [[ -z "${found}" ]] && found="proton-cachyos-x86_64"
  echo "${found}"
}

# --- Détection des jeux vivant dans un préfixe de store partagé (Epic Games Store,
# EA App, Ubisoft Connect...) ---
#
# lpm applique le principe un-jeu-un-préfixe, mais Lutris ne crée pas systématiquement
# un wineprefix par jeu : certains launchers tiers (client installé + jeux dedans) créent
# UN SEUL wineprefix partagé par plusieurs jeux ("directory" identique pour plusieurs
# lignes de la table games). Ces jeux-là ne doivent apparaître nulle part dans lpm (ni
# listés, ni empaquetables, ni désinstallables), sous peine de casser le préfixe partagé
# pour les autres jeux qui y vivent encore.
#
# GOG, itch.io et ZOOM Platform ont été vérifiés comme respectant déjà un-jeu-un-préfixe
# (chaque jeu a son propre "directory" en base, même si rangé dans un sous-dossier comme
# gog/<jeu>/) : ils ne sont donc PAS dans cette liste.
ZGU_STORE_KEYWORDS=("Epic Games Store" "EA App" "EA Desktop" "Ubisoft Connect" "Battle.net" "Steam")

# Retourne (sur stdout, un slug par ligne) l'ensemble des slugs de jeux runner='wine' à
# exclure de lpm : ceux dont le "directory" est partagé par au moins une autre entrée de
# la table games (signal principal, détecte automatiquement tout store à préfixe partagé
# dès qu'un jeu y est installé, sans connaître son nom à l'avance), complété par un filet
# de sécurité par mots-clés (ZGU_STORE_KEYWORDS) pour bloquer aussi un store fraîchement
# installé mais encore vide (donc sans "directory" dupliqué détectable pour l'instant).
#
# Ne fait aucun affichage, ne modifie rien : pure fonction de lecture, à appeler par
# chaque script (lister/packer/uninstaller) pour filtrer sa propre liste de jeux.
zgu_get_blacklisted_slugs() {
  local lutris_db="$1"
  [[ -f "${lutris_db}" ]] || return 0

  local rows
  rows=$(sqlite3 "${lutris_db}" "SELECT slug || char(31) || name || char(31) || directory FROM games WHERE runner='wine';" 2>/dev/null)
  [[ -z "${rows}" ]] && return 0

  local -A dir_count
  local slug name dir
  while IFS=$'\x1f' read -r slug name dir; do
    [[ -z "${dir}" ]] && continue
    dir_count["${dir}"]=$(( ${dir_count["${dir}"]:-0} + 1 ))
  done <<< "${rows}"

  local kw is_blacklisted
  while IFS=$'\x1f' read -r slug name dir; do
    [[ -z "${slug}" ]] && continue
    is_blacklisted=0

    if [[ -n "${dir}" ]] && [[ "${dir_count[${dir}]:-0}" -gt 1 ]]; then
      is_blacklisted=1
    fi

    if [[ "${is_blacklisted}" -eq 0 ]]; then
      for kw in "${ZGU_STORE_KEYWORDS[@]}"; do
        if [[ "${name}" == *"${kw}"* ]]; then
          is_blacklisted=1
          break
        fi
      done
    fi

    [[ "${is_blacklisted}" -eq 1 ]] && echo "${slug}"
  done <<< "${rows}"
}

# --- Détection du store (Epic/EA/Ubisoft/Battle.net) pour un giga-préfixe donné ---
#
# Partagée par zgp-game-isolator.sh ("lpm isolate") et zgp-isolable-lister.sh
# ("lpm list-isolable") : une seule définition garantit que la liste affichée par
# list-isolable et le store effectivement ciblé par isolate ne divergent jamais.
#
# Distinct de ZGU_STORE_KEYWORDS ci-dessus, qui inclut aussi "Steam" pour le filet de
# sécurité de la blacklist générale : Steam est explicitement hors sujet ici (les jeux
# Steam ne sont pas gérés par lpm). Seuls les 4 stores documentés sont reconnus ; un
# préfixe partagé qui n'en fait pas partie (store inconnu, ou blacklisté uniquement par
# détection générique de "directory" dupliqué) retourne 1, sans rien afficher : ni isolate
# ni list-isolable ne doivent deviner un store qu'ils ne savent pas traiter.
zgu_detect_isolation_store() {
  local lutris_db="$1" giga_dir="$2" safe_dir rows name
  safe_dir="${giga_dir//\'/\'\'}"
  rows=$(sqlite3 "${lutris_db}" "SELECT name FROM games WHERE runner='wine' AND directory='${safe_dir}';" 2>/dev/null)
  while IFS= read -r name; do
    case "${name}" in
      *"Epic Games Store"*) echo "egs"; return 0 ;;
      *"EA App"*|*"EA Desktop"*) echo "ea"; return 0 ;;
      *"Ubisoft Connect"*) echo "ubisoft"; return 0 ;;
      *"Battle.net"*) echo "battlenet"; return 0 ;;
    esac
  done <<< "${rows}"
  return 1
}

# Convertit un code de store interne (retourné par zgu_detect_isolation_store) en son nom
# d'affichage complet, pour l'humain (list-isolable, messages isolate).
zgu_store_display_name() {
  case "$1" in
    egs) echo "Epic Games Store" ;;
    ea) echo "EA App / EA Desktop" ;;
    ubisoft) echo "Ubisoft Connect" ;;
    battlenet) echo "Battle.net" ;;
    *) echo "$1" ;;
  esac
}
