#!/bin/bash

# --- Utilitaires partagés : barres de progression Zenity unifiées sur le modèle CLI ---
#
# GUI et CLI convergent vers un seul et même mécanisme de progression : pv, dont le
# comptage d'octets est gratuit (aucun balayage disque additionnel, il compte simplement
# ce qui transite déjà dans le pipe) :
#   - CLI  : pv lit le flux (compressé en entrée pour l'extraction, non compressé en
#            entrée pour la compression) et donne un pourcentage réel, exact, sans jamais
#            balayer le système de fichiers.
#   - GUI  : même flux pv, avec sa sortie numérique (-n) redirigée vers Zenity au lieu du
#            terminal. Un pourcentage GUI deviné en scrutant périodiquement le système de
#            fichiers (ex: "du -sb" répété sur le dossier de sortie pendant l'extraction)
#            serait un balayage récursif RÉPÉTÉ de tout l'arbre déjà extrait, à chaque tick,
#            en concurrence directe avec l'extraction elle-même -- pour un paquet de jeu de
#            plusieurs centaines de Go, ce coût devient non négligeable.
#
# Le seul balayage disque qui subsiste est le "du -sb" INITIAL et UNIQUE du dossier source
# avant compression (nécessaire pour connaître la taille totale à donner à "pv -s"), et
# n'est jamais répété pendant l'opération.
#
# Ce fichier ne fait AUCUNE decision d'affichage de message d'erreur/annulation : chaque
# appelant reste responsable de son propre message (traductions différentes selon le
# contexte jeu/runner), seule la mécanique de progression, identique partout, est
# factorisée ici.

# Variable de sortie annexe : après un appel à zgu_gui_extract_zstd, contient le code de
# sortie réel de tar (utile pour un message d'erreur détaillé). Non garantie après un
# retour 2 (annulation).
ZGU_LAST_TAR_EXIT=""

# zgu_gui_extract_zstd <archive_path> <dest_dir> <zenity_title> <zenity_text>
#
# Extrait une archive .tar.zst avec une barre de progression Zenity réelle, pilotée par
# le compteur d'octets de pv sur le FLUX COMPRESSÉ D'ENTRÉE (identique au mode CLI) :
# aucun balayage du dossier de sortie n'est jamais effectué, donc le coût de la barre
# reste constant et négligeable quelle que soit la taille du résultat extrait.
#
# Retourne 0 (succès), 1 (tar en échec -- archive corrompue/tronquée, rien n'est nettoyé
# ici, à l'appelant de le faire s'il le souhaite) ou 2 (annulé par l'utilisateur via le
# bouton Zenity).
#
# Extraction via bsdtar (libarchive) et non le tar GNU classique : bsdtar active par défaut
# ARCHIVE_EXTRACT_SECURE_NODOTDOT et ARCHIVE_EXTRACT_SECURE_SYMLINKS (voir tar/bsdtar.c dans
# libarchive), qui refusent respectivement tout membre d'archive dont le chemin contient
# ".." et tout piège par lien symbolique planté dans l'archive -- sans cela, un .zgp/.zgr
# partagé par un tiers pouvait contenir un membre du type "jeu/../../../.ssh/authorized_keys"
# et écrire hors de dest_dir dès l'extraction, avant même les vérifications de slug faites
# par l'appelant. bsdtar lit le zstd nativement (libzstd liée en dur), donc pas besoin de
# "-I zstd" ni de zstd en dépendance externe pour ce chemin de code. Ne JAMAIS ajouter
# --insecure à cet appel : cela désactiverait les deux protections ci-dessus.
zgu_gui_extract_zstd() {
  local archive_path="$1" dest_dir="$2" zen_title="$3" zen_text="$4"

  local archive_size
  archive_size=$(stat -c%s "${archive_path}" 2>/dev/null || stat -f%z "${archive_path}" 2>/dev/null)
  [[ -z "${archive_size}" ]] && archive_size=0

  local tar_exit_file
  tar_exit_file=$(mktemp)

  (
    # umask 022 le temps de l'extraction : même garde-fou que les chemins CLI équivalents
    # (voir zgp-game-installer.sh) contre un .zgp/.zgr forgé plantant un fichier trop
    # permissif. Portée limitée à ce sous-shell, pas de restauration nécessaire.
    umask 022
    pv -n -s "${archive_size}" "${archive_path}" | bsdtar -xf - -C "${dest_dir}"
    echo "${PIPESTATUS[1]}" > "${tar_exit_file}"
  ) 2>&1 | zenity --progress --title="${zen_title}" --text="${zen_text}" --percentage=0 --auto-close --width=500 2>/dev/null

  local zenity_status=$?

  if [[ "${zenity_status}" -ne 0 ]]; then
    # Annulation utilisateur : pv reçoit SIGPIPE dès sa prochaine écriture (Zenity a fermé
    # le tube), ce qui coupe l'entrée de tar en cascade -- pas besoin de kill explicite.
    rm -f "${tar_exit_file}"
    ZGU_LAST_TAR_EXIT=""
    return 2
  fi

  local tar_exit
  tar_exit=$(cat "${tar_exit_file}" 2>/dev/null)
  rm -f "${tar_exit_file}"
  [[ -z "${tar_exit}" ]] && tar_exit=1
  # shellcheck disable=SC2034 # lue par les scripts qui sourcent ce fichier (ex: zgp-game-installer.sh)
  ZGU_LAST_TAR_EXIT="${tar_exit}"

  [[ "${tar_exit}" -eq 0 ]] && return 0
  return 1
}

# zgu_gui_compress_zstd <parent_dir> <item_name> <archive_path> <level> <zenity_title> <zenity_text>
#
# Compresse "<parent_dir>/<item_name>" en <archive_path> avec une barre de progression
# Zenity réelle, pilotée par pv sur le flux tar D'ENTRÉE (mesure ce qui a déjà été lu
# depuis le dossier source, comme en mode CLI).
#
# Le seul balayage disque effectué est le "du -sb" initial et unique sur le dossier
# source, identique à celui utilisé en mode CLI.
#
# Retourne 0 (succès), 1 (échec compression, archive déjà supprimée) ou 2 (annulé par
# l'utilisateur, archive déjà supprimée).
zgu_gui_compress_zstd() {
  local parent_dir="$1" item_name="$2" archive_path="$3" level="$4" zen_title="$5" zen_text="$6"

  local zstd_opt
  if [[ "${level}" -gt 19 ]]; then
    zstd_opt="--ultra -${level}"
  else
    zstd_opt="-${level}"
  fi

  local source_size
  source_size=$(du -sb "${parent_dir}/${item_name}" 2>/dev/null | cut -f1)
  [[ -z "${source_size}" ]] && source_size=0

  rm -f "${archive_path}"

  local tar_exit_file
  tar_exit_file=$(mktemp)

  (
    tar -C "${parent_dir}" -cf - "${item_name}" | pv -n -s "${source_size}" | zstd "${zstd_opt}" > "${archive_path}"
    echo "${PIPESTATUS[0]}" > "${tar_exit_file}"
  ) 2>&1 | zenity --progress --title="${zen_title}" --text="${zen_text}" --percentage=0 --auto-close --width=500 2>/dev/null

  local zenity_status=$?

  if [[ "${zenity_status}" -ne 0 ]]; then
    rm -f "${tar_exit_file}" "${archive_path}"
    return 2
  fi

  local tar_exit
  tar_exit=$(cat "${tar_exit_file}" 2>/dev/null)
  rm -f "${tar_exit_file}"
  [[ -z "${tar_exit}" ]] && tar_exit=1

  if [[ "${tar_exit}" -ne 0 ]] || [[ ! -s "${archive_path}" ]]; then
    rm -f "${archive_path}"
    return 1
  fi

  # L'archive (.zgp/.zgr) peut embarquer des données sensibles (registre Wine : clés de
  # licence, chemins...) : restreint aux seuls droits du propriétaire, même raison que
  # les chemins CLI équivalents (voir zgp-game-packer.sh/zgr-runner-packer.sh).
  chmod 600 "${archive_path}"
  return 0
}

# zgu_gui_download <url> <dest> <expected_size> <zenity_title> <zenity_text>
#
# Télécharge <url> vers <dest> avec une barre de progression Zenity réelle pilotée par pv,
# quand <expected_size> (en octets) est connue (digest/size fournis par l'API GitHub) :
# même mécanisme que l'extraction/compression ci-dessus. Se rabat sur une barre
# indéterminée (pulsate, non annulable) quand la taille est inconnue, sans jamais deviner
# ni pré-charger quoi que ce soit.
#
# Retourne 0 (succès), 1 (échec : fichier vide ou absent) ou 2 (annulé par l'utilisateur --
# uniquement possible quand la taille est connue, la barre indéterminée n'étant pas
# annulable).
zgu_gui_download() {
  local url="$1" dest="$2" expected_size="${3:-0}" zen_title="$4" zen_text="$5"

  rm -f "${dest}"

  if [[ "${expected_size}" -gt 0 ]] 2>/dev/null; then
    (
      if command -v curl >/dev/null 2>&1; then
        curl -sLf "${url}" | pv -n -s "${expected_size}" > "${dest}"
      else
        wget -qO- "${url}" | pv -n -s "${expected_size}" > "${dest}"
      fi
    ) 2>&1 | zenity --progress --title="${zen_title}" --text="${zen_text}" --percentage=0 --auto-close --width=450 2>/dev/null

    local zenity_status=$?
    if [[ "${zenity_status}" -ne 0 ]]; then
      rm -f "${dest}"
      return 2
    fi
  else
    (
      if command -v wget >/dev/null 2>&1; then
        wget -qO "${dest}" "${url}" 2>/dev/null
      else
        curl -sLf "${url}" -o "${dest}" 2>/dev/null
      fi
    ) &
    local dl_pid=$!

    (
      while kill -0 "${dl_pid}" 2>/dev/null; do
        echo "${zen_text}"
        sleep 0.5
      done
    ) | zenity --progress --title="${zen_title}" --text="${zen_text}" --pulsate --auto-close --no-cancel 2>/dev/null

    wait "${dl_pid}"
  fi

  if [[ ! -f "${dest}" ]] || [[ ! -s "${dest}" ]]; then
    rm -f "${dest}"
    return 1
  fi
  return 0
}
