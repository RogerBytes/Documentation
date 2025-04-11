#!/bin/bash

TEMP_FILE="/tmp/lutris_games.txt"
OUTPUT_SCRIPT="./lutris_export_list_$(date +%Y%m%d_%H%M%S).sh"

# Partie 1: Extraction des informations dans un fichier temporaire
echo "Extraction des informations des jeux de Lutris..."
lutris -l > "$TEMP_FILE"

# Partie 2: Génération du script avec les commandes export
echo "#!/bin/bash" > "$OUTPUT_SCRIPT"

# Lecture ligne par ligne en ignorant l'entête
tail -n +2 "$TEMP_FILE" | while IFS='|' read -r _ game_name slug _ _; do
    game_name_trimmed=$(echo "$game_name" | xargs)
    slug_trimmed=$(echo "$slug" | xargs)
    echo "./export-lutris-wineprefix.sh \"$slug_trimmed\" \"$game_name_trimmed\"" >> "$OUTPUT_SCRIPT"
done

chmod +x "$OUTPUT_SCRIPT"
echo "Script généré : $OUTPUT_SCRIPT"
