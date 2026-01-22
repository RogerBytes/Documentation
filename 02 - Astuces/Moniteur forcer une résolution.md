# Forcer une résolution


## Truc tout prêt

Faire une résolution customisé (utile sur un vieux portable), voici la commande à c/c.
Modifiez au besoin les valeurs de `MONITOR`, `MODE` et `MODELIN`.

```bash
MONITOR=eDP
MODE="1920x1080_60.00"
MODELIN="173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync"


cat << EOF | sudo tee /etc/X11/Xsession.d/45custom-resolution > /dev/null
#!/bin/sh
xrandr --newmode $MODE $MODELIN
xrandr --addmode $MONITOR $MODE
EOF
sudo chmod +x /etc/X11/Xsession.d/45custom-resolution
```

### Valeur de MONITOR

Pour `MONITOR`:

```bash
xrandr --listactivemonitors
```

Ca retourne

```bash
❯ xrandr --listactivemonitors
Monitors: 1
 0: +*eDP 2560/708x1440/399+0+0  eDP
```

Le monitor c'est `eDP`.

### Valeurs de MODELIN et MODE

On teste pour voir si on arrive à forcer la résolution

```bash
cvt 1920 1080
```

Ca retourne :

```bash
❯ cvt 1920 1080
# 1920x1080 59.96 Hz (CVT 2.07M9) hsync: 67.16 kHz; pclk: 173.00 MHz
Modeline "1920x1080_60.00"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync
```

Le mode c'est `1920x1080_60.00` et le modeline c'est `173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync`.

