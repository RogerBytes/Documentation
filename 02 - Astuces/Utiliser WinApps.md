# Utiliser WinApps

Depuis [cette page](https://github.com/winapps-org/winapps).

## Prérequis

Il faut avoir une vm `Windows 10 RDPWindows` en ayant suivi [cette page](https://github.com/winapps-org/winapps/blob/main/docs/libvirt.md), ou suivre mon tuto.

On installe ces dépendances

```bash
sudo nala install -y curl dialog freerdp3-x11 git iproute2 libnotify-bin netcat-openbsd
```

Ici, on a bien pu installer aussi `freerdp3` qui est indispensable (sinon on aurait du le compiler).

### Réglage de la VM

- Paramètres → Système → Bureau à distance → activé

#### Dispensable

- Paramètres → Mise à jour et sécurité → Sécurité Windows → Pare-feu et protection réseau → Paramètres avancés
Propriétés du pare-feu de Windows Defender (dans le cadre central "Vue d'ensemble'"") NON CONNARD
et regle de trafic erntrant
Bureau à distance (TCP-In) et activer les deux régle en douvle quilaquand sur ces gros pédés cocher "Activé et applqiuer"

## Changer de mot de passe dans W10

Dans la VM Windows : **Ctrl + Alt + Suppr → “Modifier un mot de passe” → définir un nouveau mot de passe pour ton compte “Windows”**.

## Création du fichier de configuration

On copie-colle cette commande (ça va créer le fichier `~/.config/winapps/winapps.conf`) :

```bash
mkdir -p ~/.config/winapps && cat > ~/.config/winapps/winapps.conf << 'EOF'
##################################
#   WINAPPS CONFIGURATION FILE   #
##################################

# INSTRUCTIONS
# - Leading and trailing whitespace are ignored.
# - Empty lines are ignored.
# - Lines starting with '#' are ignored.
# - All characters following a '#' are ignored.

# [WINDOWS USERNAME]
RDP_USER="Windows"

# [WINDOWS PASSWORD]
# NOTES:
# - If using FreeRDP v3.9.0 or greater, you *have* to set a password
# - RDP_ASKPASS is provided as a more secure option to RDP_PASS:
#   - Calls an external command and uses its stdout as the password
#   - The password is not passed on the command line to freerdp, keeping it out of logs
#   - If specified, takes precedence over RDP_PASS
#   - Examples to use this:
#     - RDP_ASKPASS="~/some-custom-command"
#     - RDP_ASKPASS="bash -c 'cat ~/.some-secret-file'"
#     - RDP_ASKPASS="bash -c 'kwallet-query --folder winapps --read-password rdp kdewallet'"
#
RDP_PASS="1234"
RDP_ASKPASS=""

# [WINDOWS DOMAIN]
# DEFAULT VALUE: '' (BLANK)
RDP_DOMAIN=""

# [WINDOWS IPV4 ADDRESS]
# NOTES:
# - If using 'libvirt', 'RDP_IP' will be determined by WinApps at runtime if left unspecified.
# DEFAULT VALUE:
# - 'docker': '127.0.0.1'
# - 'podman': '127.0.0.1'
# - 'libvirt': '' (BLANK)
# RDP_IP="127.0.0.1"

# [RDP PORT]
# NOTES:
# - For Docker and Podman, this is the host port mapped to Windows port 3389.
# - If you changed the host-side RDP port in compose.yaml, set this to match.
# DEFAULT VALUE: '3389'
RDP_PORT="3389"

# [VM NAME]
# NOTES:
# - Only applicable when using 'libvirt'
# - The libvirt VM name must match so that WinApps can determine VM IP, start the VM, etc.
# DEFAULT VALUE: 'RDPWindows'
VM_NAME="RDPWindows"

# [WINAPPS BACKEND]
# DEFAULT VALUE: 'docker'
# VALID VALUES:
# - 'docker'
# - 'podman'
# - 'libvirt'
# - 'manual'
WAFLAVOR="libvirt"

# [DISPLAY SCALING FACTOR]
# NOTES:
# - If an unsupported value is specified, a warning will be displayed.
# - If an unsupported value is specified, WinApps will use the closest supported value.
# DEFAULT VALUE: '100'
# VALID VALUES:
# - '100'
# - '140'
# - '180'
RDP_SCALE="100"

# [MOUNTING REMOVABLE PATHS FOR FILES]
# NOTES:
# - By default, `udisks` (which you most likely have installed) uses /run/media for mounting removable devices.
#   This improves compatibility with most desktop environments (DEs).
# ATTENTION: The Filesystem Hierarchy Standard (FHS) recommends /media instead. Verify your system's configuration.
# - To manually mount devices, you may optionally use /mnt.
# REFERENCE: https://wiki.archlinux.org/title/Udisks#Mount_to_/media
REMOVABLE_MEDIA="/run/media"

# [ADDITIONAL FREERDP FLAGS & ARGUMENTS]
# NOTES:
# - You can try adding /network:lan to these flags in order to increase performance, however, some users have faced issues with this.
#   If this does not work or if it does not work without the flag, you can try adding /nsc and /gfx.
# DEFAULT VALUE: '/cert:tofu /sound /microphone +home-drive'
# VALID VALUES: See https://github.com/awakecoding/FreeRDP-Manuals/blob/master/User/FreeRDP-User-Manual.markdown
RDP_FLAGS="/cert:tofu /sound /microphone +home-drive"

# [NON FULL WINDOWS RDP FLAGS]
# NOTES:
# - Use these flags to pass specific flags to the freerdp command when you are starting a non-full RDP session (any other command than winapps windows)
# DEFAULT_VALUES: ''
# VALID_VALUES: See https://github.com/awakecoding/FreeRDP-Manuals/blob/master/User/FreeRDP-User-Manual.markdown
RDP_FLAGS_NON_WINDOWS=""

# [FULL WINDOWS RDP FLAGS]
# NOTES:
# - Use these flags to pass specific flags to the freerdp command when you are starting a full RDP session (winapps windows)
# DEFAULT_VALUES: ''
# VALID_VALUES: See https://github.com/awakecoding/FreeRDP-Manuals/blob/master/User/FreeRDP-User-Manual.markdown
RDP_FLAGS_WINDOWS=""

# [DEBUG WINAPPS]
# NOTES:
# - Creates and appends to ~/.local/share/winapps/winapps.log when running WinApps.
# DEFAULT VALUE: 'true'
# VALID VALUES:
# - 'true'
# - 'false'
DEBUG="true"

# [AUTOMATICALLY PAUSE WINDOWS]
# NOTES:
# - This is currently INCOMPATIBLE with 'manual'.
# DEFAULT VALUE: 'off'
# VALID VALUES:
# - 'on'
# - 'off'
AUTOPAUSE="off"

# [AUTOMATICALLY PAUSE WINDOWS TIMEOUT]
# NOTES:
# - This setting determines the duration of inactivity to tolerate before Windows is automatically paused.
# - This setting is ignored if 'AUTOPAUSE' is set to 'off'.
# - The value must be specified in seconds (to the nearest 10 seconds e.g., '30', '40', '50', etc.).
# - For RemoteApp RDP sessions, there is a mandatory 20-second delay, so the minimum value that can be specified here is '20'.
# - Source: https://techcommunity.microsoft.com/t5/security-compliance-and-identity/terminal-services-remoteapp-8482-session-termination-logic/ba-p/246566
# DEFAULT VALUE: '300'
# VALID VALUES: >=20
AUTOPAUSE_TIME="300"

# [FREERDP COMMAND]
# NOTES:
# - WinApps will attempt to automatically detect the correct command to use for your system.
# DEFAULT VALUE: '' (BLANK)
# VALID VALUES: The command required to run FreeRDPv3 on your system (e.g., 'xfreerdp', 'xfreerdp3', etc.).
FREERDP_COMMAND=""

# [TIMEOUTS]
# NOTES:
# - These settings control various timeout durations within the WinApps setup.
# - Increasing the timeouts is only necessary if the corresponding errors occur.
# - Ensure you have followed all the Troubleshooting Tips in the error message first.

# PORT CHECK
# - The maximum time (in seconds) to wait when checking if the RDP port on Windows is open.
# - Corresponding error: "NETWORK CONFIGURATION ERROR" (exit status 13).
# DEFAULT VALUE: '5'
PORT_TIMEOUT="5"

# RDP CONNECTION TEST
# - The maximum time (in seconds) to wait when testing the initial RDP connection to Windows.
# - Corresponding error: "REMOTE DESKTOP PROTOCOL FAILURE" (exit status 14).
# DEFAULT VALUE: '30'
RDP_TIMEOUT="30"

# APPLICATION SCAN
# - The maximum time (in seconds) to wait for the script that scans for installed applications on Windows to complete.
# - Corresponding error: "APPLICATION QUERY FAILURE" (exit status 15).
# DEFAULT VALUE: '60'
APP_SCAN_TIMEOUT="60"

# WINDOWS BOOT
# - The maximum time (in seconds) to wait for the Windows VM to boot if it is not running, before attempting to launch an application.
# DEFAULT VALUE: '120'
BOOT_TIMEOUT="120"

# FREERDP RAIL HIDEF
# - This option controls the value of the `hidef` option passed to the /app parameter of the FreeRDP command.
# - Setting this option to 'off' may resolve window misalignment issues related to maximized windows.
# DEFAULT VALUE: 'on'
HIDEF="on"
EOF
```

et on ajoute une restriction de sécurité dessus

```bash
chown $(whoami):$(whoami) ~/.config/winapps/winapps.conf
chmod 600 ~/.config/winapps/winapps.conf
```

**Attention**

Ici pour `RDP_USER` et `RDP_PASS`, j'ai mis `1234` comme MDP (ça ne marchera pas sans) et j'ai mis comme User `Windows`, donc à modifier au besoin.

j'ai commenté `RDP_IP` vu mon install de VM via libvirt.

En cas de soucis de taille (pour augmenter la taille de l'interface)
Remplacer
RDP_SCALE="100"
par
RDP_SCALE="140"
Pour rendre les fenetre plus petite ou plus grande (la valeur peut être 100, 140, 180)

## Test FreeRDP

Ici on va tester le merdier

On récupère l'ip

```bash
virsh domifaddr RDPWindows
```

ça retourne 

```bash
 virsh domifaddr RDPWindows
 Name       MAC address          Protocol     Address
-------------------------------------------------------------------------------
 vnet0      52:54:00:a7:db:b2    ipv4         192.168.122.130/24
```

L'ip de ma VM est donc `192.168.122.130`
Donc je lance le test

```bash
nc -zv 192.168.122.130 3389
```

```bash
xfreerdp3 /u:"Windows" /p:"1234" /v:192.168.122.130:3389 /cert:tofu
```

Si une fenêtre `FreeRDP` apparait avec votre session windows, ça signifie que le test est réussi
Sinon, il faut bien vérfieri les options dans le parafeu comme expliqué au tout début

## Lancer l'installateur de WinApps

1. Démarrer la VM Windows dans virt-manager (sans cliquer sur ouvrir pour afficher l'image)
2. Lancer WinApps normalement

```bash
bash <(curl https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh)
```

Des fois ça merde la première fois, juste relancer

Chosir :

- Install
- Current User
- Manual
- Skip setting up any officially supported applications
- Select which applications to set up

L'installation est finie.

## Les commandes

```bash
winapps-setup --help
```

qui retourne

```bash
Usage:
      --user                                        # Install WinApps and selected applications in /home/harry
      --system                                      # Install WinApps and selected applications in /usr
      --user --setupAllOfficiallySupportedApps      # Install WinApps and all officially supported applications in /home/harry
      --system --setupAllOfficiallySupportedApps    # Install WinApps and all officially supported applications in /usr
      --user --uninstall                            # Uninstall everything in /home/harry
      --system --uninstall                          # Uninstall everything in /usr
      --user --add-apps                             # Add new applications to existing installation in /home/harry
      --system --add-apps                           # Add new applications to existing installation in /usr
      --help                                        # Display this usage message.
```

## Ajouter et retirer des lanceur

Il suffit de lancer 

```bash
bash <(curl https://raw.githubusercontent.com/winapps-org/winapps/main/setup.sh)
```

De désinstaller et de réinstaller en suivant

- Install
- Current User
- Manual
- Skip setting up any officially supported applications
- Select which applications to set up

ou les chemins seraients dans
~/.local/bin/winapps-src/apps
et / ou 

/home/harry/.local/bin/winapps-src/apps

## Installation de Winapps Launcher

Depuis [cette page](https://github.com/winapps-org/winapps-launcher).

```bash
sudo nala install -y yad
```

Notre chemin étant `/home/harry/.local/bin/winapps-src/apps`

On utilise

```bash
WINAPPS_SRC_DIR="$HOME/.local/bin/winapps-src"
```

et ensuite, toujours dans cet émulateur de terminal

```bash
# Clone the repository into the correct location
git clone https://github.com/winapps-org/winapps-launcher.git "${WINAPPS_SRC_DIR}/winapps-launcher"

# Make the script executable
chmod +x "${WINAPPS_SRC_DIR}/winapps-launcher/winapps-launcher.sh"

# Run the launcher as a test
"${WINAPPS_SRC_DIR}/winapps-launcher/winapps-launcher.sh"
```

### On créé le lanceur

```bash
mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/winapps-launcher.desktop <<EOF
[Desktop Entry]
Type=Application
Name=WinApps Launcher
Comment=Taskbar Launcher for WinApps
Exec="$WINAPPS_SRC_DIR/winapps-launcher/winapps-launcher.sh"
Icon=$WINAPPS_SRC_DIR/winapps-launcher/icons/LinkIcon.svg
Terminal=false
Categories=Utility;
EOF
```

### On créé l'auto start

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/winapps-launcher.service <<EOF
[Unit]
Description=Run 'WinApps Launcher'
After=graphical-session.target default.target
Wants=graphical-session.target

[Service]
Type=simple
Environment="PATH=%h/.local/bin:%h/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LIBVIRT_DEFAULT_URI=qemu:///system"
Environment="SCRIPT_PATH=$WINAPPS_SRC_DIR/winapps-launcher/winapps-launcher.sh"
Environment="LANG=C"
ExecStart=/bin/bash -c "\\"\$SCRIPT_PATH\\""
ExecStopPost=/bin/bash -c 'echo "[SYSTEMD] WINAPPS LAUNCHER SERVICE EXITED."'
TimeoutStartSec=5
TimeoutStopSec=5
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
```

### Activer le user service

```bash
systemctl --user enable winapps-launcher --now
```

Pour tester si le service est lancé :

```bash
systemctl --user status winapps-launcher
```

Et quand je lance l'application winappas, rien ne se passe non plus, j'en ai marre.

## Problème d'affichage linux mint

Je ne sais pas encore, je vais ouvrir une issue sur leur githuib et essayer de comprendre (lien possibles = ecrypt et cinnamon)

## Donner plus de puissance

Vous pouvez donner jusqu'à la moitié de votre ram et de vos cores dans Virtman à la VM.
