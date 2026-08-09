#!/bin/bash

# --- Utilitaire partagé : détection du dossier "Bureau" de l'utilisateur ---
#
# Utilise le mécanisme standard XDG (commande xdg-user-dir, adossée à
# ~/.config/user-dirs.dirs) : c'est la seule source fiable, car c'est elle que les
# environnements de bureau eux-mêmes utilisent pour savoir où poser une icône,
# quelle que soit la langue du système ET même si l'utilisateur a renommé ou
# déplacé son dossier Bureau depuis les paramètres de son environnement.
#
# Remplace l'ancienne détection codée en dur ("Desktop" / "Bureau" uniquement,
# dupliquée à l'identique dans zgp-game-installer.sh et zgp-game-uninstaller.sh) :
# un système installé dans une autre langue (allemand "Schreibtisch", espagnol
# "Escritorio"...) se retrouvait avec un chemin "$HOME/Desktop" inexistant, sans
# le moindre message d'erreur (le raccourci n'était simplement jamais créé/supprimé,
# silencieusement).
#
# Se rabat sur l'ancienne heuristique Desktop/Bureau si xdg-user-dir est absent ou
# ne renvoie rien d'exploitable (environnement minimal sans le paquet xdg-user-dirs).
zgu_get_desktop_dir() {
  if command -v xdg-user-dir >/dev/null 2>&1; then
    local xdg_desktop
    xdg_desktop=$(xdg-user-dir DESKTOP 2>/dev/null)
    # xdg-user-dir renvoie $HOME tel quel quand XDG_DESKTOP_DIR n'est pas configuré :
    # dans ce cas précis, ce n'est pas une vraie réponse, on continue vers le fallback.
    if [[ -n "${xdg_desktop}" ]] && [[ "${xdg_desktop}" != "${HOME}" ]]; then
      echo "${xdg_desktop}"
      return 0
    fi
  fi

  if [[ -d "${HOME}/Bureau" ]]; then
    echo "${HOME}/Bureau"
  else
    echo "${HOME}/Desktop"
  fi
}
