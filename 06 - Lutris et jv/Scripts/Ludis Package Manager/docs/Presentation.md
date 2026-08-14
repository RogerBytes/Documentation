J'ai créé un gestionnaire de paquet "Ludis Package Manager" dédié à la bibliothèque de jeux wine avec lutris.
$ tree -l
.
├── bin
│   └── lpm
├── CONTRIBUTING.md
├── docs
│   ├── Lisez moi.md
│   ├── Presentation.md
│   └── Tests.md
├── install.sh
├── lang
│   ├── en.lang
│   └── fr.lang
├── lib
│   ├── zgc-dependency-checker.sh
│   ├── zgl-lang-loader.sh
│   ├── zgp-game-installer.sh
│   ├── zgp-game-lister.sh
│   ├── zgp-game-packer.sh
│   ├── zgp-game-uninstaller.sh
│   ├── zgr-runner-installer.sh
│   ├── zgr-runner-lister.sh
│   ├── zgr-runner-packer.sh
│   ├── zgr-runner-remote-lister.sh
│   ├── zgr-runner-uninstaller.sh
│   ├── zgu-desktop-utils.sh
│   ├── zgu-github-release-utils.sh
│   ├── zgu-lutris-utils.sh
│   └── zgu-progress-utils.sh
└── uninstall.sh

5 directories, 24 files

J'aimerais que tu consultes le code.

Normalement ça devrait être propre, le code est durci.

Ce qu'il ne faut pas faire :

1. **Pas de mise à jour** — `install` refuse catégoriquement si le slug existe déjà, car le gestionnaire de paquet est personnel, il n'a pas pour vocation à servir pour le piratage (le système de mise à jour servirait à ça)
2. **Pas de vérification d'intégrité** — pareil, c'est des paquets personnels, il n'y a pas à utiliser des paquets téléchargés depuis un site, et une vérification d'intégrité peut se faire sans que ce soit builtin.

Ce qu'il faut faire
- Auto completion **bash** (pour l'instant c'est seulement zsh)
- Une page `man`, seulement `--help`.
- Un journal/historique des actions (utile pour déboguer un install/isolate raté a posteriori).
- Il faut une commande dédiée pour *lister* les jeux isolables (elle existe seulement en mode interactif Zenity), il faut les lister, avec le store à viser pour l'isolation des jeux.


Est-ce que je peux tout t'envoyer dans une archive tar, c'est plus simple pour moi (car il y a trop de fichiers sinon).
