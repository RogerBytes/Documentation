# VM W10 avec Virtman / Qemu / Kvm

## Présentation

Ici c'est du simple et efficace, c'est pour faire la vm Windows10 sur linux, aucune fioriture, le but est d'avoir une machine propre et lègère, avec le moins de modif sur le système après atlas os et avoir viré quelques app.

## Téléchargement

```bash
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/light.w10.vm.tar.gz
tar -xzf "light.w10.vm.tar.gz"
for p in aa ab ac ad ae af; do
  wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.$p
done
mkdir -p "$HOME/Local/VMs/iso"
mkdir -p "$HOME/Local/VMs/Partage"
cat wiso.tzst* > wiso.tzst && tar -I zstd -xf wiso.tzst -C "$HOME/Local/VMs/iso"
rm wiso.tzst*
```

## Utilisation

Après avoir téléchargé votre iso `Win10_22H2_French_x64v1.iso` et l'avoir mis dans `~/Local/VMs/iso`

1. Lancez Virt-Manager "Gestionnaire de machines virtuelles" `virt-manager`  :

2. Cliquez sur **Créer une nouvelle machine virtuelle**.

3. Choisissez **Média d'installation local (image ISO ou CD-ROM)**.

4. Cliquez sur **Parcourir**, puis **Parcourir en Local** et sélectionnez votre fichier ISO.

5. Décochez **Détecter automatiquement depuis la source/média d'installation** (ou choisissez manuellement Windows 10).

6. Allouez la **RAM** (4 à 6 Go suffisent) et le **nombre de cœurs CPU** (2 à 4 coeur suffisent), s'il y a une demande de permission, cochez `Ne plus faire de demandes sur ces dossiers` et cliquez sur `Oui`.

7. Créez un **disque virtuel**, 40 Go c'est assez.

8. Finalisez la configuration :

   - Donnez un nom à la VM, ici "Windows10".
   - Si souhaité, activez **l’interface réseau en mode NAT** (recommandé pour accès Internet).

9. Cliquez sur **Terminer** pour démarrer la VM et lancer l'installation de l’OS.

10. faire l'install en mode hors ligne même s'il rechigne un peu (ca evite de mettre un compte windows)

11. Virer l'iso des disque de la VM (plus besoin)

12. En nom d'user mettre "Windows 10" ne rien mettre pour me mdp.

13. Reboot et faire encore maj en boucle jusqu'à ce qu'il y a plus de maj

14. Installer MAS via c/c dans powershell (chercher sur le web le lien)

15. Installer Atlas os, dans les options, choisir de désactiver windows defender

16. Lancer OOSU10.exe, appliquer les trucs recommandés

17. BCUninstaller_5.9.0_setup_fixed.exe, desisntaller un max de truc, ne pas virer windows store

18. installer floorp-stub.installer.exe une fois installé virer les autres navigateurs

---

Pour afficher les options de votre machine, il faut aller dans `Afficher/Détail`, `Afficher/Console` permet d'afficher l'écran.
Vérifier les options de RAM et que le CD d'ISO est bien coché au démarrage en cas de soucis lors de l'installation.

## Créer un pont entre host et vm via smb

Pour ajouter le dossier partagé

```bash
mkdir - ~/Local/VMs/Partage
sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[Partage]
   path = /home/%U/Local/VMs/Partage
   browsable = yes
   read only = no
   create mask = 0664
   directory mask = 2775
   valid users = %U
EOF

sudo systemctl restart smbd
sudo systemctl enable smbd
```

Puis ajouter un mdp à son serveur samba avec

```bash
sudo smbpasswd -a $USER
```


Récupérer son ip avec

```bash
ip addr show virbr0 | grep -oP 'inet \K[\d\.]+'
```


il retourne `192.168.122.1` dans mon cas, donc

Dans la machine windows :

- Ouvre l’explorateur de fichiers.
- Clique sur **“Ce PC”** → **“Connecter un lecteur réseau”**.
- Dossier :

```text
\\192.168.122.1\Partage
```

- Coche **“Se reconnecter à la connexion”**.
- Quand demandé : entre ton **nom d’utilisateur Linux** et ton **mot de passe Samba**.

Il est possible que le pare-feu bloque il faut donc fait

```bash
sudo ufw allow 137,138,139,445/tcp
sudo ufw reload
```

## Créer un lanceur pour une VM

Ici c'est pour une VM nommée `Windows10`.

```bash
sudo tee /usr/local/bin/lancer-windows10.sh > /dev/null <<'EOF'
#!/bin/bash
virsh start Windows10
virt-manager --connect qemu:///system --show-domain-console Windows10
EOF

sudo chmod +x /usr/local/bin/lancer-windows10.sh

sudo tee /usr/share/applications/Windows10.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Windows10 VM
Comment=Lancer Windows10 via Virt-Manager
Exec=/usr/local/bin/lancer-windows10.sh
Icon=computer
Terminal=false
Categories=Utility;
EOF
```

## Pour avoir une taille dynamique

Les commandes utilisent "Windows10.qcow2" par défaut.

```bash
qemu-img convert -O qcow2 Windows10.qcow2 Windows10-shrink.qcow2
```

Bouger "Windows10.qcow2" ailleurs puir renommer "Windows10-shrink.qcow2" en "Windows10.qcow2"

La taille du fichier qcows2 augmentera (ou diminuera) de manière dynamique

## Augmenter la taille du disque

Ici je lui ajoute 110 Go a ce qu'il a déja comme capacité.

```bash
qemu-img resize Windows10.qcow2 +251G
```

## Etendre la partion dans la vm windows

Il faut utiliser minitool partition wizard

