# Installer Docker Desktop

## Attention DANGER

Il y a un [bug non résolu](https://github.com/docker/desktop-linux/issues/285) lors de l'initialisation de Docker Desktop (il génère un fichier .raw à l'infini), il faut suivre attentivement cette documentation.
Il y a un workaround (trouvé sur [ce fil de discussion](https://forums.docker.com/t/docker-4-39-0-not-running-able-to-start-on-ubuntu-24-10/147171/4)) à ce bug critique, tout est expliqué ici, il suffit de suivre les indications.
Testé le 14/11/25 sur :

- Docker Engine v28.5.2
- Docker Desktop v4.51.0
- Linux Mint 22.2

## Prerequis

Avoir suivi l'installation de docker engine `Installer Docker Engine sur LM 22.2`

## Télécharement

```bash
wget -O docker-desktop-amd64.deb "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"
```

## Installation

```bash
sudo nala install -y docker-desktop-amd64.deb
rm docker-desktop-amd64.deb
```

**Ne le lancez pas tout de suite !**
**ATTENTION, C'EST MAINTENANT QU'IL VA FALLOIR ÊTRE ATTENTIF**

## Workaround

On va lancer Docker Desktop juste quelques secondes (pour générer les fichier de config) avec cette commande

```bash
systemctl --user start docker-desktop && sleep 10 && systemctl --user stop docker-desktop
```

Maintenant on ajuste les réglages de Docker Desktop

```bash
rm -r ~/.docker/desktop/vms/0
cp "$HOME/.docker/desktop/settings-store.json" "$HOME/.docker/desktop/settings-store.json.bak" \
  && jq '. + {DiskSizeMiB:16000}' "$HOME/.docker/desktop/settings-store.json.bak" \
     > "$HOME/.docker/desktop/settings-store.json"
```

## Initialisation de Docker Desktop

Grâce au workaround dans la partie précédente, la taille du fichier `~/.docker/desktop/vms/0/data/Docker.raw` est désormais limitée à 16GB.

Nous pouvons donc lancer l'application en toute tranquillité

```bash
systemctl --user start docker-desktop
```

Il faut attendre un peu, mais ce coup-ci la génération du fichier s'arrête à 16GB.

Voilà, **Docker Desktop est correctement installé**.

Je conseille un petit reboot qui ne mange pas de pain

```
sudo reboot now
```