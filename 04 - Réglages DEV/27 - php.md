# Installer php

Php est installé par défaut sur les système linux, mais pas toujours à la toute dernière version.
Pour ubuntu 22.04 (au moins) et linux mint (associé à 22.04), il y a un PPA qui permet d'avoir la dernière version?

[Page officielle de téléchargement PHP.net](https://www.php.net/downloads.php?usage=web&os=linux&osvariant=linux-ubuntu&version=8.5)

```bash
# Add the ondrej/php repository.
sudo apt update
sudo apt install -y software-properties-common
sudo LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php -y
sudo apt update

# Install PHP.
sudo apt install -y php8.5
```
