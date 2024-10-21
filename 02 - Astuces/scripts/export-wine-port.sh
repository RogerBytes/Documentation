#!/bin/bash

# Vérifie si le nombre d'arguments est correct
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
 echo "Usage: $0 <wineprefix_name> <archive_name> [tar]"
 exit 1
fi

# Affecte les arguments aux variables
WINEPREFIX_NAME=$1
ARCHIVE_NAME=$2
COMPRESSION_TYPE=${3:-gz}

# Vérifie si le troisième argument est fourni et s'il est correct
if [ "$#" -eq 3 ] && [ "$COMPRESSION_TYPE" != "tar" ]; then
 echo "Le troisième argument doit être 'tar' s'il est fourni."
 exit 1
fi

# Vérifie si le Wineprefix existe
if [ ! -d "$HOME/Games/$WINEPREFIX_NAME" ]; then
  echo "Le Wineprefix $WINEPREFIX_NAME n'existe pas dans $HOME/Games"
  exit 1
fi

# Opérations de néttoyage du préfixe
if [ -d "$HOME/Games/$WINEPREFIX_NAME/dosdevices" ]; then
  rm -r "$HOME/Games/$WINEPREFIX_NAME/dosdevices"
fi

if [ -L "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser" ]; then
  rm -r "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser"
fi

if [ -d "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/$USER" ]; then
  mv "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/$USER" "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser"
fi

if [ -L "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser/Downloads" ]; then
  rm -r "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser/Downloads"
fi

if [ -L "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates" ]; then
  rm -r "$HOME/Games/$WINEPREFIX_NAME/drive_c/users/steamuser/AppData/Roaming/Microsoft/Windows/Templates"
fi

echo "CACA"

# Vérifie le type de compression et crée l'archive
if [ "$COMPRESSION_TYPE" == "tar" ]; then
  tar -cvf "$HOME/${ARCHIVE_NAME}.tar" -C "$HOME/Games" "$WINEPREFIX_NAME"
  echo "L'archive ${ARCHIVE_NAME}.tar a été créée avec succès."
else
  tar -czvf "$HOME/${ARCHIVE_NAME}.tar.gz" -C "$HOME/Games" "$WINEPREFIX_NAME"
  echo "L'archive ${ARCHIVE_NAME}.tar.gz a été créée avec succès."
fi

exit 0
