# Tests

Juste une séries de tests à effectuer pour vérifier que tout est fonctionnel.

## Aide

Le menu d'aide.

```bash
lpm -h
ou
lpm --help
```

## Mimetype

Double cliquer sur fichier.zgp|.zgr.
Le .zgr doit ouvrir le menu d'import de masse de runners (et prendre tous tous les paquets .zgr présents dans le répertoire), uniquement les runners non installés doivent apparaître.
Le .zgp doit ouvrir le menu d'import de masse, après décompression, il vérifie si le prefixe est déjà présent, si oui, il annule l'installation pour ne rien écraser.

## Installer un ou plusieur jeux

```bash
lpm install -y Mariovania.zgp "Papers, Please.zgp"
```

```bash
lpm install -y "/home/harry/Bureau/test lpm/Mariovania.zgp" "/home/harry/Bureau/test lpm/Papers, Please.zgp"
```

## Empaquettage jeux

```bash
lpm pack mariovania papers-please
```

```bash
lpm pack -2 mariovania papers-please
```

## Lister les jeux

```bash
lpm list
```

## Désinstaller un jeu

```bash
lpm uninstall -y mariovania papers-please
```

## Installer un runner

Depuis le repo

```bash
lpm install-runner -y wine-11.14-amd64 proton-cachyos-11.0-20260703-slr-x86_64_v3
```

ou local

```bash
lpm install-runner -y wine-11.14-amd64.zgr proton-cachyos-11.0-20260703-slr-x86_64_v3.zgr
```

```bash
lpm install-runner -y "/home/harry/Bureau/test lpm/wine-11.14-amd64.zgr" "/home/harry/Bureau/test lpm/proton-cachyos-11.0-20260703-slr-x86_64_v3.zgr"
```

## Empaquettage runners

```bash
lpm pack-runner wine-11.14-amd64 proton-cachyos-11.0-20260703-slr-x86_64_v3
```

```bash
lpm pack-runner -2 wine-11.14-amd64 proton-cachyos-11.0-20260703-slr-x86_64_v3
```

## Lister les runners

```bash
lpm list-runner
```

## Désinstaller un runner

```bash
lpm uninstall-runner -y wine-11.14-amd64 proton-cachyos-11.0-20260703-slr-x86_64_v3
```

## Vérification des dépendances

```bash
lpm check
```

