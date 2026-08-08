#!/bin/bash

# --- Récupération des arguments du routeur lpm ---
# $1 = Flag de confirmation ("yes" si -y)
# $2, $3, ... = Liste des slugs de jeux cibles en CLI
confirm_flag="${1:-}"
shift || true
cli_games=("$@")

# Configuration des chemins Lutris
lutris_flatpak_db="$HOME/.var/app/net.lutris.Lutris/data/lutris/pga.db"
lutris_package_db="$HOME/.local/share/lutris/pga.db"

lutris_flatpak_config_dir="$HOME/.var/app/net.lutris.Lutris/data/lutris/games"
lutris_package_config_dir="$HOME/.config/lutris/games"

lutris_flatpak_option_file="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine.yml"
lutris_package_option_file="$HOME/.config/lutris/runners/wine.yml"

games_dir="$HOME/Games"

# 1. Vérifications de base (sqlite3 requis, zenity uniquement si mode interactif)
if ! command -v sqlite3 >/dev/null 2>&1; then
  if [ ${#cli_games[@]} -gt 0 ]; then
    echo "Erreur : 'sqlite3' n'est pas installé sur le système." >&2
  else
    zenity --error --text="Erreur : 'sqlite3' n'est pas installé sur le système." 2>/dev/null
  fi
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
  if [ ${#cli_games[@]} -gt 0 ]; then
    echo "Erreur : Lutris n'est pas installé sur le système." >&2
  else
    zenity --error --text="Lutris n'est pas installé sur le système." 2>/dev/null
  fi
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
  if [ ${#cli_games[@]} -gt 0 ]; then
    echo "Erreur : Base de données Lutris introuvable : $lutris_db" >&2
  else
    zenity --error --text="Base de données Lutris introuvable : $lutris_db" 2>/dev/null
  fi
  exit 1
fi

# 4. Récupération des jeux Wine depuis la BDD Lutris
games_list=$(sqlite3 "$lutris_db" "SELECT name || '|' || slug || '|' || directory FROM games WHERE runner='wine' ORDER BY name COLLATE NOCASE ASC;" 2>/dev/null)

if [ -z "$games_list" ]; then
  if [ ${#cli_games[@]} -gt 0 ]; then
    echo "Aucun jeu Wine trouvé dans la base de données Lutris." >&2
  else
    zenity --info --text="Aucun jeu Wine trouvé dans la base de données Lutris." 2>/dev/null
  fi
  exit 0
fi

declare -A slug_by_name
declare -A dir_by_name
declare -A name_by_slug

while IFS="|" read -r game_name game_slug game_dir; do
  [ -z "$game_name" ] && continue
  
  [ -z "$game_dir" ] && game_dir="$games_dir/$game_slug"

  slug_by_name["$game_name"]="$game_slug"
  dir_by_name["$game_name"]="$game_dir"
  name_by_slug["$game_slug"]="$game_name"
done <<< "$games_list"

games_to_delete=()

# --- Mode CLI vs Mode Interactif ---
if [ ${#cli_games[@]} -gt 0 ]; then
  # --- MODE CLI (100% Terminal, zéro Zenity) ---
  for target_slug in "${cli_games[@]}"; do
    found_name="${name_by_slug[$target_slug]}"
    if [ -n "$found_name" ]; then
      games_to_delete+=("$found_name")
    else
      # Recherche par correspondance partielle de slug
      matched_name=""
      for g_name in "${!slug_by_name[@]}"; do
        if [ "${slug_by_name[$g_name]}" = "$target_slug" ]; then
          matched_name="$g_name"
          break
        fi
      done
      
      if [ -n "$matched_name" ]; then
        games_to_delete+=("$matched_name")
      else
        echo "Erreur : Jeu introuvable dans Lutris avec le slug : $target_slug" >&2
        exit 1
      fi
    fi
  done
else
  # --- MODE INTERACTIF (Avec Zenity) ---
  if ! command -v zenity >/dev/null 2>&1; then
    echo "Erreur : 'zenity' n'est pas installé sur le système." >&2
    exit 1
  fi

  zenity_args=()
  for g_name in "${!slug_by_name[@]}"; do
    zenity_args+=( "FALSE" "$g_name" "${slug_by_name[$g_name]}" )
  done

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
fi

# 6. Gestion de la confirmation
if [ ${#cli_games[@]} -gt 0 ]; then
  # En mode CLI, si le flag 'yes' n'est pas passé, on demande une confirmation textuelle dans le terminal
  if [ "$confirm_flag" != "yes" ]; then
    echo "Jeux à désinstaller :"
    for game_name in "${games_to_delete[@]}"; do
      echo " - $game_name (${dir_by_name[$game_name]})"
    done
    read -r -p "Êtes-vous sûr de vouloir supprimer ces jeux ? [O/n] " response
    case "$response" in
      [nN][oO]|[nN])
        echo "Désinstallation annulée."
        exit 0
        ;;
      *)
        ;;
    esac
  fi
else
  # En mode interactif graphique
  summary_text="Attention, les éléments suivants vont être définitivement supprimés :\n"
  for game_name in "${games_to_delete[@]}"; do
    p_dir="${dir_by_name[$game_name]}"
    summary_text+="\n• <b>$game_name</b>\n  Dossier : <i>$p_dir</i>"
  done

  summary_text+="\n\nVoulez-vous vraiment continuer ?"

  zenity --question --title="Confirmation de suppression" \
    --text="$summary_text" \
    --width=550 --height=350 2>/dev/null

  if [ $? -ne 0 ]; then
    zenity --info --title="Annulation" --text="Opération annulée. Aucun fichier n'a été supprimé." 2>/dev/null
    exit 0
  fi
fi

# 7. Traitement de la suppression (avec affichage CLI textuel ou barre Zenity)
total_games=${#games_to_delete[@]}

if [ ${#cli_games[@]} -gt 0 ]; then
  # --- EXÉCUTION EN MODE CLI (Affichage textuel épuré) ---
  current=0
  for game_name in "${games_to_delete[@]}"; do
    current=$((current + 1))
    echo "[$current/$total_games] Suppression de '$game_name'..."

    game_slug="${slug_by_name[$game_name]}"
    prefix_dir=$(sqlite3 "$lutris_db" "SELECT directory FROM games WHERE slug='$game_slug';")
    [ -z "$prefix_dir" ] && prefix_dir="${dir_by_name[$game_name]}"

    # A. Suppression du préfixe physique sur le disque
    [ -d "$prefix_dir" ] && rm -rf "$prefix_dir"

    # B. Suppression de la configuration YML Lutris
    rm -f "$lutris_config_dir/${game_slug}-"*.yml

    # C. Suppression de l'entrée dans la base de données SQLite
    sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$game_slug';"

    # D. Suppression des raccourcis .desktop
    desktop_dir="$HOME/Desktop"
    [ -d "$HOME/Bureau" ] && desktop_dir="$HOME/Bureau"
    
    rm -f "$desktop_dir/${game_slug}.desktop"
    rm -f "$desktop_dir/${game_name} Bonus"
    rm -f "$HOME/.local/share/applications/net.lutris.${game_slug}.desktop"
  done

  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  echo "Désinstallation CLI terminée avec succès !"
else
  # --- EXÉCUTION EN MODE INTERACTIF (Barre de progression Zenity) ---
  (
    current=0
    for game_name in "${games_to_delete[@]}"; do
      current=$((current + 1))
      percent=$(( current * 100 / total_games ))
      
      echo "$percent"
      echo "# Suppression en cours...\nJeu : $game_name ($current / $total_games)"

      game_slug="${slug_by_name[$game_name]}"
      prefix_dir=$(sqlite3 "$lutris_db" "SELECT directory FROM games WHERE slug='$game_slug';")
      [ -z "$prefix_dir" ] && prefix_dir="${dir_by_name[$game_name]}"

      [ -d "$prefix_dir" ] && rm -rf "$prefix_dir"
      rm -f "$lutris_config_dir/${game_slug}-"*.yml
      sqlite3 "$lutris_db" "DELETE FROM games WHERE slug='$game_slug';"

      desktop_dir="$HOME/Desktop"
      [ -d "$HOME/Bureau" ] && desktop_dir="$HOME/Bureau"
      
      rm -f "$desktop_dir/${game_slug}.desktop"
      rm -f "$desktop_dir/${game_name} Bonus"
      rm -f "$HOME/.local/share/applications/net.lutris.${game_slug}.desktop"
      
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

  notify-send "Désinstallation terminée" "Tous les jeux sélectionnés et leurs préfixes ont été supprimés avec succès !" 2>/dev/null
fi

exit 0
