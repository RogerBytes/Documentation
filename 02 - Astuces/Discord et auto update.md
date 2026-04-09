# Discord et auto update

Depuis [le repo de Doc0x1](https://github.com/Doc0x1/Discord-Auto-Updater-For-Linux)

Il suffit de faire

```bash
curl -L https://raw.githubusercontent.com/Doc0x1/Discord-Auto-Updater-For-Linux/master/setup_discord_update.sh -o setup_discord_update.sh
chmod +x setup_discord_update.sh
sudo ./setup_discord_update.sh
```

Ca vérifiera automatiquement s'il y a une màj, s'il y en a une ca arrete discord et ça l'installe et le relance.
./