#!/bin/bash

# Vérifie si le nombre d'arguments est correct
if [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
  echo -e "\033[31mErreur : usage incorrect.\033[0m Utilisez : $0 <wineprefix_name> <archive_name> [tar/xz/zst/gzip]" >&2
  exit 1
fi

# Variables d'environnement
OUTPUT_DIR="${HOME}"
SCRIPT_NAME=$0
WINEPREFIX_NAME=$1
ARCHIVE_NAME=$2
COMPRESSION_TYPE=${3:-zst}
LEVEL=${4:-3}
GAMES_DIR="${HOME}/Games"
WINEPREFIX_DIR="${GAMES_DIR}/${WINEPREFIX_NAME}"

# Déclaration des types de compression et des extensions
declare -A compression_types
compression_types=(
  [gzip]="tar -cvzf"
  [tar]="tar -cvf"
  [xz]="tar -cvf"
  [zst]="tar -I \"zstd -$LEVEL\" -cvf"
)

declare -A extensions
extensions=(
  [gzip]="tgz"
  [tar]="tar"
  [xz]="txz"
  [zst]="tzst"
)

# Vérifie si le troisième argument est fourni et s'il est correct
allowed_args=(tar xz gzip zst zpaq)
if [[ ! " ${allowed_args[@]} " =~ " ${COMPRESSION_TYPE} " ]]; then
  echo -e "\033[31mErreur : l'argument optionnel doit être 'tar', 'xz', 'zpaq', 'gzip' ou 'zst' s'il est fourni.\033[0m" >&2
  exit 1
fi

# Vérifie si le Wineprefix existe
if [ ! -d "$WINEPREFIX_DIR" ]; then
  echo -e "\033[31mErreur : le Wineprefix ${WINEPREFIX_NAME} n'existe pas dans ${GAMES_DIR}\033[0m" >&2
  exit 1
fi

# Vérifie si les outils nécessaires sont disponibles
for cmd in tar gzip xz zstd; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "\033[31mErreur : l'outil $cmd n'est pas disponible.\033[0m" >&2
    exit 1
  fi
done

# Ajuste le niveau de compression pour "xz" et "zst"
if [ "$LEVEL" -eq 19 ] && [ "$COMPRESSION_TYPE" == "xz" ]; then
  LEVEL=3
fi

if [ "$LEVEL" -gt 19 ] && [ "$COMPRESSION_TYPE" == "zst" ]; then
  LEVEL="-ultra -$LEVEL"  # Ajoute --ultra à la variable LEVEL
  compression_types[zst]="tar -I \"zstd -$LEVEL\" -cvf"
fi
# Crée la commande d'archive
command=${compression_types[$COMPRESSION_TYPE]}
extension=${extensions[$COMPRESSION_TYPE]}

set -e

# Commande spécifique pour "xz" et "zst"
if [ "$COMPRESSION_TYPE" == "xz" ]; then
  final_command="$command \"${OUTPUT_DIR}/${ARCHIVE_NAME}.${extension}\" --use-compress-program=\"xz -${LEVEL}\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
else
  final_command="$command \"${OUTPUT_DIR}/${ARCHIVE_NAME}.${extension}\" -C \"${GAMES_DIR}\" \"${WINEPREFIX_NAME}\""
fi

# Exécuter la commande dans un nouveau shell
echo -e "\033[32m$final_command\033[0m"
bash -c "$final_command"

exit 0
