#!/bin/bash

# --- Récupération des arguments du routeur lpm ---
# $1 = Flag de confirmation ("yes" si -y)
# $2, $3, ... = Liste des runners cibles à supprimer en CLI
confirm_flag="${1:-}"
shift || true
cli_runners=("$@")

# Configuration des chemins des runners Lutris
lutris_flatpak_runner_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"
lutris_package_runner_dir="$HOME/.local/share/lutris/runners/wine"

# 1. Détection du type de Lutris (Flatpak vs Paquet natif)
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  runner_dir="$lutris_flatpak_runner_dir"
elif [ -d "$lutris_package_runner_dir" ]; then
  runner_dir="$lutris_package_runner_dir"
else
  runner_dir="$HOME/.local/share/lutris/runners/wine"
fi

if [ ! -d "$runner_dir" ]; then
  if [ ${#cli_runners[@]} -gt 0 ]; then
    echo "Erreur : Dossier de runners introuvable : $runner_dir" >&2
  else
    zenity --error --text="Aucun dossier de runners Wine introuvable : $runner_dir" 2>/dev/null
  fi
  exit 1
fi

cd "$runner_dir" || exit 1

declare -A path_by_runner
runners_to_delete=()

# 2. Gestion Mode CLI (Multi-runners) vs Mode Interactif
if [ ${#cli_runners[@]} -gt 0 ]; then
  # --- MODE CLI (Terminal, aucun Zenity) ---
  missing=()

  for target_runner_arg in "${cli_runners[@]}"; do
    r_path="$runner_dir/$target_runner_arg"
    if [ ! -d "$r_path" ]; then
      missing+=("$target_runner_arg")
      continue
    fi
    runners_to_delete+=("$target_runner_arg")
    path_by_runner["$target_runner_arg"]="$r_path"
  done

  # Vérification stricte : le moindre runner introuvable annule tout, rien n'est supprimé
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Erreur : le(s) runner(s) suivant(s) sont introuvables dans '$runner_dir' :" >&2
    for name in "${missing[@]}"; do
      echo " - $name" >&2
    done
    echo "Aucun runner n'a été supprimé." >&2
    exit 1
  fi

  # Confirmation interactive si le flag -y n'est pas présent
  if [ "$confirm_flag" != "yes" ]; then
    echo "Runners à supprimer définitivement :"
    for name in "${runners_to_delete[@]}"; do
      echo " - $name (${path_by_runner[$name]})"
    done
    read -r -p "Êtes-vous sûr de vouloir supprimer ces runners ? [O/n] " response
    case "$response" in
      [nN][oO]|[nN])
        echo "Suppression annulée."
        exit 0
        ;;
      *)
        ;;
    esac
  fi
else
  # --- MODE INTERACTIF (Avec Zenity) ---
  if ! command -v zenity >/dev/null 2>&1; then
    echo "Erreur : 'zenity' n'est pas installé sur le système." >&2
    exit 1
  fi

  runners_list=( * )

  if [ ${#runners_list[@]} -eq 0 ] || [ "${runners_list[0]}" = "*" ]; then
    zenity --info --text="Aucun runner Wine/Proton trouvé à supprimer dans $runner_dir." 2>/dev/null
    exit 0
  fi

  # Tri alphabétique propre
  IFS=$'\n' sorted_runners=($(sort <<< "${runners_list[*]}"))
  unset IFS

  zenity_args=()

  for runner in "${sorted_runners[@]}"; do
    [ -d "$runner" ] || continue
    path_by_runner["$runner"]="$runner_dir/$runner"
    # Décoché par défaut (FALSE) pour éviter les erreurs d'étourderie
    zenity_args+=( "FALSE" "$runner" )
  done

  # Fenêtre de sélection (checklist) pour choisir les runners à supprimer
  selected_runners=$(zenity --list --checklist \
    --title="Gestionnaire de Suppression de Runners" \
    --text="Sélectionnez le ou les runners Wine/Proton à supprimer définitivement :" \
    --column="Supprimer" --column="Nom du Runner" \
    "${zenity_args[@]}" \
    --width=650 --height=400 2>/dev/null)

  if [ -z "$selected_runners" ]; then
    exit 0
  fi

  IFS="|" read -r -a runners_to_delete <<< "$selected_runners"

  # Construction du résumé pour la fenêtre de confirmation
  summary_text="Attention, les runners suivants vont être définitivement supprimés du système :\n"
  for runner in "${runners_to_delete[@]}"; do
    r_path="${path_by_runner[$runner]}"
    summary_text+="\n• <b>$runner</b>\n  Chemin : <i>$r_path</i>"
  done

  summary_text+="\n\nVoulez-vous vraiment continuer ?"

  # Demande de confirmation finale
  zenity --question --title="Confirmation de suppression des runners" \
    --text="$summary_text" \
    --width=550 --height=350 2>/dev/null

  if [ $? -ne 0 ]; then
    zenity --info --title="Annulation" --text="Opération annulée. Aucun runner n'a été supprimé." 2>/dev/null
    exit 0
  fi
fi

# 3. Traitement de la suppression
total_runners=${#runners_to_delete[@]}

if [ ${#cli_runners[@]} -gt 0 ]; then
  # --- MODE CLI (Affichage textuel épuré) ---
  current=0
  for runner in "${runners_to_delete[@]}"; do
    current=$((current + 1))
    echo "[$current/$total_runners] Suppression de '$runner'..."

    r_path="${path_by_runner[$runner]}"
    if [ -d "$r_path" ]; then
      rm -rf "$r_path"
    fi
  done

  echo "Désinstallation CLI terminée avec succès !"
else
  # --- MODE INTERACTIF (Barre de progression Zenity) ---
  (
    current=0
    for runner in "${runners_to_delete[@]}"; do
      current=$((current + 1))
      percent=$(( current * 100 / total_runners ))

      echo "$percent"
      echo "# Suppression du runner...\nRunner : $runner ($current / $total_runners)"

      r_path="${path_by_runner[$runner]}"

      # Suppression physique du dossier du runner
      if [ -d "$r_path" ]; then
        rm -rf "$r_path"
      fi

      sleep 0.2
    done

    echo "100"
    echo "# Nettoyage final..."
    sleep 0.3

  ) | zenity --progress \
    --title="Suppression des runners" \
    --text="Préparation..." \
    --percentage=0 \
    --auto-close \
    --width=450 2>/dev/null

  zenity_status=$?

  if [ $zenity_status -ne 0 ]; then
    zenity --info --title="Interruption" --text="L'opération de suppression des runners a été interrompue." 2>/dev/null
    exit 0
  fi

  notify-send "Suppression terminée" "Les runners sélectionnés ont été supprimés du système avec succès." 2>/dev/null
fi

exit 0
