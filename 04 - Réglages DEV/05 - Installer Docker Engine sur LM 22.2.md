# Installer Docker Engine sur LM 22.2

[Documentation d'installation de Docker](https://docs.docker.com/desktop/setup/install/linux/)

## Prérequis

- 64 bit et virtualisation CPU
- KVM virtualisation
- QEMU >= 5.2 `qemu-system-x86_64 --version`
- systemd `systemctl --version`
- 4 GB de Ram

### Vérifier KVM

```bash
modprobe kvm
```

Puis on vérifie

```bash
lsmod | grep kvm
```

Il doit retourner

```output
kvm_amd               245760  0
ccp                   155648  1 kvm_amd
kvm                  1425408  1 kvm_amd
irqbypass              12288  1 kvm
```

Puis ajouter l'utilisateur au groupe

```bash
sudo usermod -aG kvm $USER
```

Se déco/reco à sa session, puis vérifier

```bash
groups
```

`kvm` doit être dans la liste

### Gnome Terminal

```bash
sudo nala install -y gnome-terminal
```

## Ajouter le repo officiel

Depuis [cette page de Docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)

```bash
sudo apt update
sudo nala install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
```

## Installation

```bash
sudo nala install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Vérification

Puis on vérifie :

```bash
sudo systemctl status docker
```

S'il n'est pas en vert "active", il faut :

```bash
sudo systemctl start docker
```

Puis on le teste avec

```bash
sudo docker run hello-world
```

Voilà, `docker-engine` est correctement installé !
