# Installer WinBoat

Depuis [cette page](https://winboat.app).

## Prérequis

On installe ces dépendances

```bash
sudo nala install -y curl dialog freerdp3-x11 git iproute2 libnotify-bin netcat-openbsd
```

Ici, on a bien pu installer aussi `freerdp3` qui est indispensable (sinon on aurait du le compiler).

On télécharge le paquet debian [ici](https://winboat.app/#download)

puis

```bash
sudo nala install -y winboat-*.*.*-amd64.deb
```

Puis je le lance, pour le chemin, je choisis "/home/harry/Local/VMs/winboat/winboat", pour l'édition, je choisis windows 10 pro en FR.

Pour le mdp, je mets "1234"

je mets la moitié de mes ressources, et je laisse la taille de disque par défauts, l'installation se fait toute seule.

Ensuite je fais les màj, jusqu'à plus rien à faire, puis maj windows store

## Augmenter la taille

<https://github.com/TibixDev/winboat/issues/254#issuecomment-3416581514>

1. Go into your `~/.winboat`
2. Run `docker compose down` there.
3. Modify `docker-compose.yml` and set the `DISK_SIZE: 32G` to `DISK_SIZE: 100G`.
4. Run `docker compose up` and wait until the Windows Docker container is up again.
5. I then used `MiniTool Partition Wizard Free` to resize the Windows Partition.

Comme d'habitude, ecryptfs fout le bazar "Warning: the filesystem of /storage is ecryptfs, which does not support O_DIRECT mode, adjusting settings..."

On télécharge cet iso :

```bash
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/Fichiers.pour.vm.tar.gz
```

puis on va installer vivaldi comme navi

wincedemu

