# Nala Update erreur UPGRADABLE

Si à la fin d'un `sudo nala update` on a le retour `32 packages can be upgraded. Run 'nala list --upgradable' to see them.`
Ca indique que des paquets ne sont pas mis à jour automatiquement.

## Forcer la màj auto

Ce sont des paquet qu'il faut installer manuellement, mais avec cette commande, il va s'en occuper seul

```bash
sudo nala update && sudo nala full-upgrade -y && for pkg in $(nala list --upgradable | sed 's/^[├└─ ]*//; s/ .*//'); do sudo nala install -y "$pkg" 2>/dev/null || echo "Skipped $pkg"; done
```

## Faire la màj manuellement

Si on souhaite, on peut le faire manuellement.
Faites la commande :

```bash
nala list --upgradable
```

Il retourne (par exemple)

```bash
❯ nala list --upgradable
grub-efi-amd64-bin 2.12-1ubuntu7.1 [local]
├── is installed and upgradable to 2.12-1ubuntu7.3
└── GRand Unified Bootloader, version 2 (EFI-AMD64 modules)

grub-efi-amd64-signed 1.202.2+2.12-1ubuntu7.1 [local]
├── is installed and upgradable to 1.202.5+2.12-1ubuntu7.3
└── GRand Unified Bootloader, version 2 (EFI-AMD64 version, signed)

Les deux paquets (en vert dans le shell) sont ici
grub-efi-amd64-bin
grub-efi-amd64-signed
```

On précise manuellement les paquets que l'on souhaite upgrade

```bash
sudo nala install -y grub-efi-amd64-bin grub-efi-amd64-signed
```
