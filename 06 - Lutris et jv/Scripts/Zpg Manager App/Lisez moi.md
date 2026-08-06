# Zpg Manager

**Zgp Manager** vous permet de sauvegarder vos jeux Wine pour Lutris au format `.zgp` et vos runners au format `.zgr`. Il centralise l'exportation, la gestion et la suppression de vos archives, tandis que l'importation se charge de tout configurer pour que votre jeu soit immédiatement prêt à être lancé.

## Dépendances

<details><summary class="button">🔍 Spoiler</summary><div class="spoiler">

L'application est minimaliste mais requiert plusieurs dépendances :

- Tar
- Zstd
- Curl
- Wget
- Python 3
- Sqlite3
- Lutris
- pv
- grep
- awk

### Ubuntu

Sur une Debian / Ubuntu (et dérivées comme Linux Mint)

```bash
sudo apt install -y tar zstd curl wget python3 sqlite3 pv
flatpak install -y flathub net.lutris.Lutris
```

Sur cinnamon il faut activer les nouvelles fenêtres lancée d'un terminal

`Paramètres du système > Fenêtres > Comportement > **Cibler les nouvelles fenêtres lancées d'un terminal** (à activer).`

### Arch Linux

Sur une Arch Linux (et dérivées comme Manjaro)

```bash
sudo pacman -S --needed tar zstd curl wget python sqlite pv
flatpak install -y flathub net.lutris.Lutris
```

### Fedora

Sur une Fedora (et dérivées comme RHEL)

```bash
sudo dnf install -y tar zstd curl wget python3 sqlite pv
flatpak install -y flathub net.lutris.Lutris
```

### OpenSUSE

Sur une OpenSUSE (et dérivées comme Leap)

```bash
sudo zypper install -y tar zstd curl wget python3 sqlite3 pv
flatpak install -y flathub net.lutris.Lutris
```

</div></details>

## Installation

<details><summary class="button">🔍 Spoiler</summary><div class="spoiler">

Pour l'installer il suffit de lancer le script d'installation.

On le rend executable

```bash
chmod +x ./install.sh
```

Puis on l'installe

```bash
sudo ./install.sh
```

</div></details>

## Information

<details><summary class="button">🔍 Spoiler</summary><div class="spoiler">

Pour avoir une icone au lanceur, il suffit de créer un répertoire `icon` à la racine du préfixe, et y déplacer votre fichier image.

Pour avoir un support automatique de la manette, il suffit de créer un répertoire `scripts` à la racine du préfixe, et y déplacler le fichier `amgp` de Antimicro.

Si vous avez un script au démarrage `start.sh` et/ou à la fermeture `stop.sh`, il suffit de créer un répertoire `scripts` à la racine du préfixe, et y déplacler le ou les script.

</div></details>

## Auteur

[<img src="https://github.com/RogerBytes.png" width="40" height="40" style="border-radius:50%;" alt="RogerBytes' avatar">](https://github.com/RogerBytes)
[**RogerBytes (Harry Richmond)**](https://github.com/RogerBytes)

<span hidden>
<details><summary></summary>
<style>.spoiler{border-left:4px solid #1abc9c;border-bottom-left-radius:3px;padding-left:10px;padding-top:15px;margin-top:-10px;margin-bottom:15px}.button{cursor:pointer;padding:5px 10px;background-color:#3498db;color:white;border-radius:3px;margin-bottom:5px;display:inline-block;transition:background-color 0.2s}.button:hover{background-color:#217dbb}details[open] .button{background-color:#1abc9c}</style>
</details></span>

<p align="right"><a href="#">🔝 Retour en haut</a></p>
