# Theme Flatpak

## Trouver les dépendances utilisées

On liste les runtimes avec 

```bash
flatpak list --app --columns=application,runtime
```

Perso j'ai

```
org.gnome.Platform/x86_64/48
org.gnome.Platform/x86_64/49
org.freedesktop.Platform/x86_64/24.08
org.freedesktop.Platform/x86_64/25.08
org.kde.Platform/x86_64/6.8
org.kde.Platform/x86_64/6.9
```

Les app utilisant GTK sont les "org.freedesktop" et "org.gnome"

## Appliquer un thème sombre

On va forcer leur theme avec

```bash
sudo flatpak override --env=GTK_THEME=Adwaita-dark
```

Ca marche pour les applications GTK3
`org.gnome.Platform/x86_64/48`

Ca ne marche pas avec les applications GTK4/libadwaita
`org.gnome.Platform/x86_64/49`


Il n'y a rien à faire pour les applications utilisant GTK4/libadwaita pour l'instant, c'est redhat qui fait exprès d'embêter le monde.
