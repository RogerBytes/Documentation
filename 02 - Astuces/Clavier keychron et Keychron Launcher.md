# Clavier keychron et Keychron Launcher

Dans cette doc on va voir les commandes basiques du clavier (testé sur K10 Pro) et le [site Launcher Keychron](https://launcher.keychron.com/) qui permet de paramétrer le clavier et faire les màj.

## Jumelage Bluetooth

- Mettre son clavier en mode bluetooth (via le bouton à l'arrière, tout à gauche sur K10 pro, les indications sont mélangées)
- Maintenir pendant 4 secondes `FN + 1`
- Faire le jumelage sur l'ordinateur ou le téléphone.

Voilà, il faudra toujours veiller à être en mode bluetooth à l'arrière, c'est tout.

## Rétroéclairage

### Toggle on/off

FN + TAB

### Prochain mode led

FN + A 

## Keychron Launcher

Linux refuse par défaut que le [site de Keychron](https://launcher.keychron.com/) se connecte au clavier, on va régler cela.

### Dépendances

#### dfu-util

On installe `dfu-util` (indispendable pour faire les màj)

```bash
sudo nala install -y dfu-util
```

#### Groupe d'utilsateurs `keychron`

On va créer un groupe d'utilisateurs `keychron`, ce sera plus sécurisé qu'utiliser `users`.

```bash
sudo groupadd keychron 2>/dev/null || true
sudo usermod -aG keychron $USER
```

Il faut se déco/reco pour que ce soit effectif.

### Règle UDEV

Maintenant nous allons paramètrer manuellement les règles udev sur notre session.

#### Récuperer les ID

On commence par récupérer les ID de l'appareil

```bash
lsusb | grep -i keychron
```

Chez moi, pour mon `K10 Pro` il retourne

```bash
 lsusb | grep -i keychron
Bus 001 Device 003: ID 3434:02a1 Keychron Keychron K10 Pro
```

Dans cette chaine `3434:02a1` le vendor id est `3434` (propre à la marque keychron) et le product id est `02a1` (propre au modèle).

#### Ajout de la règle UDEV

Voici un bloc de code qui va donner l'autorisation à l'appareil, vous n'aurez à modifier que les valeurs de `PRODUCTID` au besoin

```bash
PRODUCTID=02a1
VENDORID=3434

echo "KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDORID\", ATTRS{idProduct}==\"$PRODUCTID\", MODE=\"0660\", GROUP=\"keychron\", TAG+=\"uaccess\", TAG+=\"udev-acl\"" | sudo tee /etc/udev/rules.d/99-keychron.rules

sudo udevadm control --reload-rules && sudo udevadm trigger
```

Maintenant l'on peut utiliser normalement le [site du launcher Keychron](https://launcher.keychron.com/) !


## Mise à jour du firmware

On va dans [la partie update de la webapp](https://launcher.keychron.com/#/firmware/flash), il ne faut pas suivre les indication pour windows, et il ne faut pas cliquer sur `Télécharger la boite à outils` (sur linux on a déjà installé `dfu-util` qui fait le job), on ne suit pas les indications pour windows et on clique sur `Prochain`.

Pour entrer en mode update, on va suivre les indications données

- Débrancher le cable usb du clavier
- Maintenir la touche `Esc` enfoncé et alors rebrancher le clavier avec le cable usb
- Cliquer sur `Appareil correspondant` et choisir `STM32 BOOTLOADER associé`
- Sur la page cliquer sur `Micrologiciel Flash` qui vient d'apparaitre.
- Une barre de progression apparait, patientez durant la mise à jour.


## Utiliser VIAL ou VIA au lieu de la webapp officielle

Pas envie de me prendre la tête pour l'instant, ce qui suit n'est absolument pas vérifié ni testé.

On va paramétrer les règles etc (depuis [cette documentation](https://get.vial.today/manual/linux-udev.html))

```bash
export USER_GID=`id -g`; sudo --preserve-env=USER_GID sh -c 'echo "KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", ATTRS{serial}==\"*vial:f64c2b3c*\", MODE=\"0660\", GROUP=\"$USER_GID\", TAG+=\"uaccess\", TAG+=\"udev-acl\"" > /etc/udev/rules.d/59-vial.rules && udevadm control --reload && udevadm trigger'
```

Il y a [un fork open source du firmware](https://github.com/nalf3in/vial-qmk-k10-pro/tree/keychron_k10_pro_support).

Prenez l'appimage sur [la page de téléchargements de VIAL](https://get.vial.today/download/)


https://caniusevia.com


