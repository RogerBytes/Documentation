# --- Complétion bash pour lpm ---
#
# Équivalent bash de completions/_lpm (zsh) : mêmes sources de vérité (lpm lui-même,
# jamais la base Lutris directement), pour ne jamais diverger sur la logique de
# détection Flatpak/paquet natif ou le filtrage des jeux blacklistés (giga-préfixes
# partagés), qui ne vit qu'à un seul endroit (zgu-lutris-utils.sh).
#
# Installation manuelle (si install.sh ne l'a pas déjà fait) :
#   sudo cp completions/lpm.bash /usr/local/share/bash-completion/completions/lpm
#   (puis ouvrir un nouveau terminal, ou "source /usr/local/share/bash-completion/completions/lpm")

# Slugs des jeux installés ("lpm list", format "slug  Nom du jeu", séparateur deux
# espaces -- voir zgp-game-lister.sh : echo "${slug}  ${name}"). Filtre structurel sur
# ce séparateur plutôt que sur le texte du message "Aucun jeu installé." : indépendant
# de la langue active de lpm.
_lpm_installed_slugs() {
  lpm list 2>/dev/null | awk -F'  ' 'NF>1{print $1}'
}

# Noms des runners installés ("lpm list-runner", un nom par ligne). Un nom de runner
# réel est toujours un seul mot (basename de dossier) ; filtre NF==1 pour ignorer le
# message "Aucun runner installé.", sans dépendre de la langue active de lpm -- même
# logique que _lpm_installed_slugs ci-dessus.
_lpm_installed_runners() {
  lpm list-runner 2>/dev/null | awk 'NF==1{print $1}'
}

_lpm_commands="install install-runner uninstall uninstall-runner pack pack-runner \
isolate list list-isolable info list-runner list-remote-runners check log"

# Niveaux de compression valides (0 à 22, voir bin/lpm : "-[0-9]|-1[0-9]|-2[0-2]") --
# un token collé ("-9", comme gzip), pas une option suivie d'une valeur séparée.
_lpm_compression_opts="-0 -1 -2 -3 -4 -5 -6 -7 -8 -9 -10 -11 -12 -13 -14 -15 -16 -17 \
-18 -19 -20 -21 -22"

_lpm() {
  local cur prev words cword
  _init_completion || {
    # _init_completion vient du paquet bash-completion (fonctions communes) ; si le
    # système ne l'a pas chargé pour une raison quelconque, repli minimal plutôt que de
    # planter la complétion pour tout le shell.
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  }

  local command="${COMP_WORDS[1]:-}"

  # Premier mot : sous-commande, ou -h/--help/-v/--version
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "${_lpm_commands} -h --help -v --version" -- "${cur}"))
    return 0
  fi

  case "${command}" in
    install)
      COMPREPLY=($(compgen -W "-y" -- "${cur}"))
      # Complétion de fichiers .zgp en plus des options : compgen -f puis filtre
      # sur l'extension, pour laisser bash gérer l'échappement des chemins comme
      # d'habitude (espaces, apostrophes...).
      if [[ "${cur}" != -* ]]; then
        COMPREPLY+=($(compgen -f -X '!*.zgp' -- "${cur}"))
      fi
      ;;
    install-runner)
      COMPREPLY=($(compgen -W "-y" -- "${cur}"))
      if [[ "${cur}" != -* ]]; then
        COMPREPLY+=($(compgen -f -X '!*.zgr' -- "${cur}"))
      fi
      ;;
    uninstall)
      COMPREPLY=($(compgen -W "-y $(_lpm_installed_slugs)" -- "${cur}"))
      ;;
    uninstall-runner)
      COMPREPLY=($(compgen -W "-y $(_lpm_installed_runners)" -- "${cur}"))
      ;;
    pack)
      COMPREPLY=($(compgen -W "${_lpm_compression_opts} $(_lpm_installed_slugs)" -- "${cur}"))
      ;;
    pack-runner)
      COMPREPLY=($(compgen -W "${_lpm_compression_opts} $(_lpm_installed_runners)" -- "${cur}"))
      ;;
    isolate)
      # Sans argument : sélection interactive via Zenity (liste les jeux détectés dans
      # un giga-préfixe partagé) -- pas de complétion dynamique fiable ici sans dupliquer
      # la détection de zgu_get_blacklisted_slugs ; on peut en revanche s'appuyer sur
      # "lpm list-isolable" (colonne 1) pour les slugs déjà connus comme isolables.
      COMPREPLY=($(compgen -W "$(lpm list-isolable 2>/dev/null | awk -F'  ' 'NF>1{print $1}')" -- "${cur}"))
      ;;
    info)
      # Un seul slug attendu : pas de complétion au-delà du premier argument.
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$(_lpm_installed_slugs)" -- "${cur}"))
      fi
      ;;
    check)
      COMPREPLY=($(compgen -W "-y" -- "${cur}"))
      ;;
    log)
      case "${prev}" in
        -n|--grep)
          # Valeur attendue ensuite (nombre de lignes ou motif) : pas de complétion
          # utile, on laisse le champ libre.
          COMPREPLY=()
          return 0
          ;;
      esac
      COMPREPLY=($(compgen -W "-n --all --grep --clear" -- "${cur}"))
      ;;
    list|list-isolable|list-runner|list-remote-runners)
      # Aucun argument attendu.
      COMPREPLY=()
      ;;
    *)
      COMPREPLY=()
      ;;
  esac

  return 0
}

complete -F _lpm lpm
