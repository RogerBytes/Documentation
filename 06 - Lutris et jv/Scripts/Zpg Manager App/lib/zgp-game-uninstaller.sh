#!/bin/bash

# Configuration des chemins Lutris
lutris_flatpak_db="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="$HOME/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="$HOME/.config/lutris/games"

lutris_flatpak_option_file="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml"
lutris_package_option_file="$HOME/.config/lutris/runners/wine.yml"

games_dir="$HOME/Games"

# 1. Vérification de zenity et sqlite3
if ! command -v zenity >/dev/null 2>&1; then
  echo "Erreur : 'zenity' n'est pas installé."
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  zenity --error --text="Erreur : 'sqlite3' n'est pas installé sur le système." 2>/dev/null
  exit 1
fi

# 2. Fermeture préalable de Lutris pour libérer la BDD
if flatpak list 2>/dev/null | grep -q lutris; then
  flatpak kill net.lutris.Lutris 2>/dev/null
fi
pkill -9 -x lutris 2>/dev/null
pkill -9 -f "/usr/bin/lutris" 2>/dev/null

# 3. Détection Flatpak vs Paquet natif
check_flatpak_lutris_installed() {
  flatpak list 2>/dev/null | grep -q lutris
}

if check_flatpak_lutris_installed; then
  version="flatpak"
elif command -v lutris >/dev/null 2>&1; then
  version="package"
else
  zenity --error --text="Lutris n'est pas installé sur le système." 2>/dev/null
  exit 1
fi

case "$version" in
  flatpak)
    lutris_option_file="$lutris_flatpak_option_file"
    lutris_config_dir="$lutris_flatpak_config_dir"
    lutris_db="$lutris_flatpak_db"
    ;;
  package)
    lutris_option_file="$lutris_package_option_file"
    lutris_config_dir="$lutris_package_config_dir"
    lutris_db="$lutris_package_db"
    ;;
esac

# Chemin Games personnalisé (si défini dans Lutris)
if [ -f "$lutris_option_file" ]; then
  extracted_path=$(awk -F': ' '/^\s*game_path:/ {print $2}' "$lutris_option_file")
  if [ -n "$extracted_path" ]; then
    games_dir="$extracted_path"
  fi
fi

if [ ! -f "$lutris_db" ]; then
  zenity --error --text="Base de données Lutris introuvable : $lutris_db" 2>/dev/null
  exit 1
fi

# 4. Récupération des jeux Wine depuis la BDD Lutris, triés par ordre alphabétique sur le nom
games_list=$(sqlite3 "$lutris_db" "SELECT name || '|' || slug || '|' || directory FROM games WHERE runner='wine' ORDER BY name COLLATE NOCASE ASC;" 2>/dev/null)

if [ -z "$games_list" ]; then
  zenity --info --text="Aucun jeu Wine trouvé dans la base de données Lutris." 2>/dev/null
  exit 0
fi

zenity_args=()
declare -A slug_by_name
declare -A dir_by_name

while IFS="|" read -r game_name game_slug game_dir; do
  [ -z "$game_name" ] && continue
  
  [ -z "$game_dir" ] && game_dir="$games_dir/$game_slug"

  slug_by_name["$game_name"]="$game_slug"
  dir_by_name["$game_name"]="$game_dir"

  zenity_args+=( "FALSE" "$game_name" "$game_slug" )
done <<< "$games_list"

# 5. Fenêtre de sélection (checklist)
selected_games=$(zenity --list --checklist \
  --title="Désinstalleur de Jeux Lutris" \
  --text="Sélectionnez les jeux à supprimer (ainsi que leur préfixe) :" \
  --column="Supprimer" --column="Nom du Jeu" --column="Slug" \
  "${zenity_args[@]}" \
  --width=650 --height=450 2>/dev/null)

if [ -z "$selected_games" ]; then
  exit 0
fi

IFS="|" read -r -a games_to_delete <<< "$selected_games"

# 6. Construction du résumé pour la fenêtre de confirmation
summary_text="Attention, les éléments suivants vont être définitivement supprimés :\n"
for game_name in "${games_to_delete[@]}"; do
  p_dir="${dir_by_name[$game_name]}"
  summary_text+="\n• <b>$game_name</b>\n  Dossier : <i>$p_dir</i>"
done

summary_text+="\n\nVoulez-vous vraiment continuer ?"

# 7. Demande de confirmation finale
zenity --question --title="Confirmation de suppression" \
  --text="$summary_text" \
  --width=550 --height=350 2>/dev/null

if [ $? -ne 0 ]; then
  zenity --info --title="Annulation" --text="Opération annulée. Aucun fichier n'a été supprimé." 2>/dev/null
  exit 0
fi

# 8. Traitement de la suppression avec une barre de progression en arrière-plan
total_games=${#games_to_delete[@]}

(
  current=0
  for game_name in "${games_to_delete[@]}"; do
    current=$((current + 1))
    percent=$(( current * 100 / total_games ))
    
    echo "$percent"
    echo "# Suppression en cours...\nJeu : $game_name ($current / $total_games)"

    game_slug="${slug_by_name[$game_name]}"
    prefix_dir="${dir_by_name[$game_name]}"

    # A. Suppression du préfixe physique sur le disque
    if [ -d "$prefix_dir" ]; then
      rm -rf "$prefix_dir"
    fi

    # B. Suppression de la configuration YML Lutris
    rm -f "$lutris_config_dir/${game_slug}-"*.yml

    # C. Suppression de l'entrée dans la base de données SQLite
    sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$game_slug';"

    # D. Suppression des éventuels raccourcis .desktop (Bureau et Applications)
    desktop_dir="$HOME/Desktop"
    [ -d "$HOME/Bureau" ] && desktop_dir="$HOME/Bureau"
    
    rm -f "$desktop_dir/${game_name}.desktop"
    rm -f "$desktop_dir/${game_name} Bonus"
    
    find "$HOME/.local/share/applications" -type f -name "*${game_slug}*" -delete 2>/dev/null
    
    sleep 0.3
  done

  echo "100"
  echo "# Nettoyage final des menus..."
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  sleep 0.4

) | zenity --progress \
  --title="Désinstallation des jeux" \
  --text="Préparation de la suppression..." \
  --percentage=0 \
  --auto-close \
  --no-cancel 2>/dev/null

notify-send "Désinstallation terminée" "Tous les jeux sélectionnés et leurs préfixes ont été supprimés avec succès." 2>/dev/null
exit 0
