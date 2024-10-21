#!/bin/bash

# Vérifie si le nombre d'arguments est correct
if [ "$#" -lt 2 ] || [ "$#" -gt 5 ]; then
  echo -e "\033[31mErreur : usage incorrect.\033[0m Utilisez : $0 <wineprefix_name> <archive_name> [tar/xz/zst/gzip]" >&2
  exit 1
fi

# Variables d'environnement
LEVEL=3
OUTPUT_DIR="${HOME}"
SCRIPT_NAME=$0
WINEPREFIX_NAME=$1
ARCHIVE_NAME=$2
COMPRESSION_TYPE=${3:-gzip}
GAMES_DIR="${HOME}/Games"
WINEPREFIX_DIR="${GAMES_DIR}/${WINEPREFIX_NAME}"
export ZSTD_CLEVEL=$LEVEL

echo "le type choisi est $COMPRESSION_TYPE"

# Déclaration de variables
declare -A compression_types
compression_types=(
  [gzip]="tar -cvzf"
  [tar]="tar -cvf"
  [xz]="tar -cvf"
  [zst]="tar -I zstd -cvf"
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
  echo -e "\033[31mErreur : l'argument optionnel doit être 'tar', 'xz', 'zpaq, 'gzip' ou 'zst' s'il est fourni.\033[0m" >&2
  exit 1
fi

# Vérifie si le Wineprefix existe
if [ ! -d "$WINEPREFIX_DIR" ]; then
  echo -e "\033[31mErreur : le Wineprefix ${WINEPREFIX_NAME} n'existe pas dans ${GAMES_DIR}\033[0m" >&2
  exit 1
fi

# Opérations de nettoyage du préfixe
if [ -d "${WINEPREFIX_DIR}/dosdevices" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/dosdevices"
fi

if [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser"
fi

if [ -d "${WINEPREFIX_DIR}/drive_c/users/${USER}" ]; then
  mv -n "${WINEPREFIX_DIR}/drive_c/users/${USER}" "${WINEPREFIX_DIR}/drive_c/users/steamuser"
fi

if [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser/Application Data/" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser/Application Data/"
fi

if [ -d "${WINEPREFIX_DIR}/drive_c/users/steamuser/My Documents/" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser/My Documents/"
fi

if [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser/Downloads" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser/Downloads"
fi

if [ -d "${WINEPREFIX_DIR}/drive_c/ProgramData/Package\ Cache/" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/ProgramData/Package\ Cache/"*
fi

if [ -L "${WINEPREFIX_DIR}/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates" ]; then
  rm -rf -- "${WINEPREFIX_DIR}/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates"
fi

# remplacer les liens symboliques restants par le fichier qu'ils ciblent
find "${WINEPREFIX_DIR}" -type l -exec bash -c 'target=$(readlink "{}"); rm "{}"; cp -r "$target" "{}"' \;




# Vérifie si les outils nécessaires sont disponibles
for cmd in tar gzip xz zstd; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "\033[31mErreur : l'outil $cmd n'est pas disponible.\033[0m" >&2
    exit 1
  fi
done

# Lance la création de l'archive
command=${compression_types[$COMPRESSION_TYPE]}
extension=${extensions[$COMPRESSION_TYPE]}
set -e
if [ "$COMPRESSION_TYPE" == "xz" ]; then
  $command "${OUTPUT_DIR}/${ARCHIVE_NAME}.${extension}" --use-compress-program='xz -${LEVEL}' -C ${GAMES_DIR} "${WINEPREFIX_NAME}"
else
  $command "${OUTPUT_DIR}/${ARCHIVE_NAME}.${extension}" -C ${GAMES_DIR} "${WINEPREFIX_NAME}"
fi

exit 0
