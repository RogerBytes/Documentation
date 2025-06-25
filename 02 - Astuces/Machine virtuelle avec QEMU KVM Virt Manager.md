# Machine virtuelle QEMU, KVM et Virt Manager

## Présentation

### QEMU + KVM

* Hyperviseur open-source ultra-performant, avec accélération matérielle via KVM (Kernel-based Virtual Machine).
* Supporte quasiment tous les OS invités.
* Très configurable, scripts, snapshots, passthrough GPU, etc.
* Interface en ligne de commande, mais souvent utilisé avec un GUI comme **Virt-Manager**.

### Virt-Manager

* Interface graphique simple pour gérer QEMU/KVM.

* Permet de créer, configurer, démarrer des VM facilement.

* Performances proches du natif grâce à KVM.

* Support matériel complet (CPU, GPU passthrough, USB, réseau).

* Stable et maintenu par la communauté Linux.

* Moins gourmand que VirtualBox en ressources.

### Intêret par rapport à VirtualBox etc

* Performances proches du natif grâce à KVM.
* Support matériel complet (CPU, GPU passthrough, USB, réseau).
* Stable et maintenu par la communauté Linux.
* Moins gourmand que VirtualBox en ressources.

## Dépendances

```bash
sudo nala update
sudo nala install -y qemu-system libvirt-daemon-system libvirt-clients bridge-utils virt-manage virtiofsd samba
```

## Installation

### Ajouter sa session au groupe libvirt

```
sudo usermod -aG libvirt $USER
mkdir -p ~/Local/VMs/iso
chmod 777 ~/Local/VMs/iso
mkdir -p ~/Local/VMs/Partage
chmod 777 ~/Local/VMs/Partage
```

### Activer libvirt et virtlogd

```
sudo systemctl enable --now libvirtd
sudo systemctl enable --now virtlogd
newgrp libvirt
```

Faire un redémmarage pour terminer l'installation.

## Utilisation

Après avoir téléchargé votre iso et l'avoir mis dans `~/Local/VMs/iso`

1. Lancez Virt-Manager :
   
   ```bash
   virt-manager
   ```
   
   ou recherchez "Gestionnaire de machines virtuelles" dans le menu.

2. Cliquez sur **Créer une nouvelle machine virtuelle**.

3. Choisissez **Média d'installation local (image ISO ou CD-ROM)**.

4. Cliquez sur **Parcourir**, puis **Parcourir en Local** et sélectionnez votre fichier ISO.

5. Cochez **Détecter automatiquement depuis la source/média d'installation** (ou choisissez manuellement Windows 10 si Tiny10 n'est pas reconnu).

6. Allouez la **RAM** (entre 25% et 50% de votre RAM) et le **nombre de cœurs CPU** ((entre 25% et 50% de vos CPU), s'il y a une demande de permission, cochez `Ne plus faire de demandes sur ces dossiers`  et cliquez sur `Oui`.

7. Créez un **disque virtuel**, vous pouvez augmenter la taille au besoin.

8. Finalisez la configuration :
   
   - Donnez un nom à la VM.
   - Si souhaité, activez **l’interface réseau en mode NAT** (recommandé pour accès Internet).

9. Cliquez sur **Terminer** pour démarrer la VM et lancer l'installation de l’OS.

---

Pour afficher les options de votre machine, il faut aller dans `Afficher/Détail`, `Afficher/Console` permet d'afficher l'écran.
Vérifier les options de RAM et que le CD d'ISO est bien coché au démarrage en cas de soucis lors de l'installation. 

Pour ajouter le dossier partagé

```bash
sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[Partage]
   path = /home/$USER/Local/VMs/Partage
   browsable = yes
   read only = no
   guest ok = yes
   force user = $USER
EOF

sudo systemctl restart smbd
```

Récupérer son ip avec

```bash
ip -4 -o addr show wlp41s0 | awk '{print $4}' | cut -d/ -f1
```

il retourne `192.168.1.91` 

Il faut maintenant se connecter à 

```
smb://192.168.1.91/Partage
```

### Windows 10/11

Attention sur Tiny10 le smb doit être activé

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
```

- Ouvre l’explorateur de fichiers.

- Clic droit sur "Ce PC" et "Add network location" et "Choisir un emplacement réseau personnalisé"

- Dans la barre d’adresse, tape `\\192.168.1.91\Partage` et appuie sur Entrée.

- Si ça demande un identifiant, renseigne ton utilisateur Samba (Linux) et mot de passe.

---

### Linux (Nautilus, Dolphin, etc.)

- Ouvre ton gestionnaire de fichiers.

- Dans la barre d’adresse, tape `smb://192.168.1.91/Partage` puis Entrée.

- Si besoin, entre tes identifiants Samba.

---

### macOS

- Dans Finder, clique sur **Aller** > **Se connecter au serveur…** (ou Cmd+K).

- Tape `smb://192.168.1.91/Partage` puis clique sur **Se connecter**.

- Identifie-toi avec ton utilisateur Samba si demandé.
