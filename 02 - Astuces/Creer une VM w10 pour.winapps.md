# Utiliser WinApps

Depuis [cette page](https://github.com/winapps-org/winapps).

## Télécharger les fichiers annexes

```bash
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/Fichiers.pour.vm.tar.gz
```

Pour info virtio.iso de l'archive vient de <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win-0.1.285.iso>

Et déplacer les ISO dans `~/Local/VMs/Iso`

## Télécharger l'iso de Windows 10

```bash
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.aa
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.ab
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.ac
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.ad
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.ae
wget https://github.com/RogerBytes/VistaTen/releases/download/v0.0.1-WIP/wiso.tzst.af
cat wiso.tzst.* > wiso.tar.zst
tar -I zstd -xvf wiso.tar.zst && rm -f wiso.tzst.* wiso.tar.zst
```

Et déplacer l'ISO dans `~/Local/VMs/Iso`

## Prérequis

On va créer créé une VM de Windows avec libvirt (virt-manager/QEMU/KVM pour faire simple)

Ajouter partie dl de mon iso w10 que j'ai backup okazou


Et faire 

```bash
echo 'LIBVIRT_DEFAULT_URI="qemu:///system"' | sudo tee -a /etc/environment
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.zshrc
```

Ouvrir virt-man  `Gestionnaire de machines virtuelles` et aller dans `Édition/préférences` dans l'onglet `Général` cocher `Enable XML editing`

## Création de l'image

- Ouvrez virtman `Gestionnaire de machines virtuelles`
- Faire `Créer une nouvelle machine virtuelle` et `Média d'installation local'` puis `Forward`, choisir mon iso 
- Dans la recherche en dessous mettre :

```text
Microsoft Windows 10
```

- et cliquer sur `Forward`
- Dans Mémoire mettre `4096`
- CPU mettre `2`
- Pour la taille, laisser `40` go, on verra ça après, puis `Forward`.
- Dans le nom, mettre `RDPWindows`, cocher `Personnaliser la configuration avant l'installation` et cliquer sur `Terminer`
- Dans le menu `Processeurs`, veiller à ce que `Copier la configuration du processeur de l'hôte` soit coché et cliquer sur `Apply`
- Retourner sur le menu `Aperçu` et aller dans l'onglet `XML` remplacer la section `clock` par

```xml
  <clock offset='localtime'>
    <timer name='rtc' present='no' tickpolicy='catchup'/>
    <timer name='pit' present='no' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
    <timer name='kvmclock' present='no'/>
    <timer name='hypervclock' present='yes'/>
  </clock>
```

- Maintenant on remplace la section hyperv

```xml
    <hyperv>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vpindex state='on'/>
      <synic state='on'/>
      <stimer state='on'>
        <direct state='on'/>
      </stimer>
      <reset state='on'/>
      <frequencies state='on'/>
      <reenlightenment state='on'/>
      <tlbflush state='on'/>
      <ipi state='on'/>
    </hyperv>
```

- et maitnenant aussi dans la partie device, ajouter (pas remplacer, bien ajouter)


```xml
    <channel type='unix'>
      <source mode='bind'/>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </channel>
```

- et cliquer sur `Apply`
- Retourner dans l'onglet `Détails` et choisissez le menu `Mémoire` dans `Allocation actuelle` mettre `1024`, et cliquer sur `Apply`
- Choisissez le menu `Options de démarrage` et cochez `Démarrer la machine virtuelle au démarrage de l'hôte` et cliquez sur `Apply`
- Choisissez le menu `SATA Disque 1` et pour `Bus du disque` choisir `VirtIO` et cliquez sur `Apply`
- Choisissez le menu `NIC:**:**:**` et pour `Modèle du périphérique` choisir `virtio` et cliquez sur `Apply`
- Cliquez en bas sur `Ajouter un matériel`, sur le menu `Stockage` dans `type de périphérique` choisir `Périphérique CD-ROM`, dans options avancées, cocher `En lecture seule` et cliquer sur `Terminer`
- Choisissez le menu `SATA CD-ROM 2` et pour `Répertoire source` choisir `virtio-win.iso` et cliquez sur `Apply`
- Enfin, en haut à gauche, cliquer sur `Commencer l'installation`, dire qu'on pas de clef de produit
- Choisir `Windows 10 Professionnel` et choisir `installation personnalisée` aucun disque apparait, il faut cliquer sur `charger un pilote`
- Choisir `Parcourir` et choisir le drive de l'iso virtio.iso et aller dans amd64/win10, décocher  et enfin choisir `Red Hat VirtIO SCSI controller (E\amd64\W10\viostor.inf)`
- Maintenant le lecteur 0 apparait, on le choisit et on appuie sur `Suivant`
- L'install se fait, puis la VM redémmare jusqu'à arriver à l'écran de réglage, on clique sur `je n'ai pas internet` et `Continuer avec l'installation limitée` pour le réseau
- Pour le nom d'utilisateur, mettre juste Windows et ne mettez rien pour le mot de passe. Choisir non pour les options de télémetrie et pour cortana.
- Quand c'est enfin installé, aller dans `Ce pc` et allez dans le disque de driver virtio, et lancez `virtio-win-guest-tools` (tout en bas)
- Ca marche s'il a ajouté un reseau (il y a un prompt/notif en dehors de l'installeur). Redémmarez windows
- Ca lance la machine, dans `Afficher` choisir `Mettre à l'échelle l'affichage` sur `Toujours`
- Sur la machine il faut télécharger  les saloperie reg instalkl etc (je vais en faire un backup quanbd fini)
- Allez dans le bouton info de la VM 
- Choisissez le menu `Mémoire` et cochez `Enable shared memory` et cliquez sur `Apply`
- Cliquez en bas sur `Ajouter un matériel`, sur le menu `Système de fichier` avec le pilote `virtiofs` sur `Chemin de la source` choisir `Parcourir`, choisir le chemin du répertoire `Partage`, et dans chemin de cible mettre `Dossier de partage` `Terminer`

## Ensuite

Et après Atlas os et les trucs présents sur les iso de `Fichiers pour vm.tar.gz`

