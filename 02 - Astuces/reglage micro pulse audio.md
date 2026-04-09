# reglage micro pulse audio

On va générer un script qui règle automatiquement le micro quand il est branché

## Étape 1 : Vérifier le nom de ton micro

Ouvre un terminal et tape :

```bash
pactl list sources short
```

Ça va afficher tous tes micros. Exemple de sortie chez moi :

```bash
$ pactl list sources short
50	alsa_output.usb-HP__Inc_HyperX_Cloud_Stinger_2_Wireless_0-00.analog-stereo.monitor	PipeWire	s16le 2ch 48000Hz	RUNNING
51	alsa_input.usb-HP__Inc_HyperX_Cloud_Stinger_2_Wireless_0-00.mono-fallback	PipeWire	s16le 1ch 48000Hz	RUNNING
53	alsa_output.pci-0000_2f_00.4.iec958-stereo.monitor	PipeWire	s32le 2ch 48000Hz	IDLE
54	alsa_input.pci-0000_2f_00.4.analog-stereo	PipeWire	s32le 2ch 48000Hz	RUNNING
75	alsa_output.pci-0000_2d_00.1.hdmi-stereo.monitor	PipeWire	s32le 2ch 48000Hz	IDLE
```

Le nom qui nous intéresse ici est la **première colonne** (`alsa_input.pci-0000_00_1f.3.analog-stereo`).

Donc mon micro c'est le input `alsa_input.usb-HP__Inc_HyperX_Cloud_Stinger_2_Wireless_0-00.mono-fallback`

---

## Étape 2 : Créer le script

Dans ton terminal :

```bash
mkdir -p ~/.local/bin
cat << 'EOF' > ~/.local/bin/set-micro-auto-event.sh
#!/bin/bash
# Script événementiel : met le micro HyperX à 150% quand il est actif

MIC_NAME="alsa_input.usb-HP__Inc_HyperX_Cloud_Stinger_2_Wireless_0-00.mono-fallback"

# Écoute les événements PulseAudio
pactl subscribe | while read -r line; do
    if echo "$line" | grep -q "source"; then
        # Si le micro est présent, règle le volume
        if pactl list short sources | grep -q "$MIC_NAME"; then
            pactl set-source-volume "$MIC_NAME" 150%
        fi
    fi
done
EOF
chmod +x ~/.local/bin/set-micro-auto-event.sh
```

## Étape 3 : Lancer le script automatiquement au démarrage

1. Sur Linux Mint, va dans **Menu → Applications lancées au démarrage**.
2. Clique sur **Ajouter/+**, puis :
   - Nom : `Micro Max`
   - Commande : `~/.local/bin/set-micro-max.sh`
   - Commentaire : `Met le micro à 150% à la connexion de l'appareil`

---

Après ça, à chaque démarrage, le micro sera automatiquement réglé à 150 %.
