# Désinstaller Docker

```
nala search docker | awk '/^docker/ {print $1}' | xargs sudo nala remove -y
rm -r $HOME/.docker/
```

et ensuite reboot avec

```
sudo reboot now
```
