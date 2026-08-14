# Tâches en cours / à faire

État à la suite de l'audit de code + des 4 ajouts demandés (auto-complétion bash, page
man, journal d'actions, `list-isolable`).

## Fait

- **Audit de sécurité complet** des 24 fichiers du projet. Un seul point trouvé : dans
  `lib/zgp-game-isolator.sh`, `old_id` (colonne `id` de la base Lutris) était interpolé
  sans échappement ni validation numérique dans un `DELETE ... WHERE id=${old_id}`.
  Corrigé : validation `^[0-9]+$` avant utilisation.
- **Journal des actions (`lpm log`)**
  - `lib/zgu-log-utils.sh` : fonction `zgu_log <commande> <statut> <détail>`, écrit dans
    `$XDG_DATA_HOME/lpm/lpm.log` (repli `~/.local/share/lpm/lpm.log`), best-effort (ne
    fait jamais échouer la commande appelante).
  - Instrumenté dans `install`, `uninstall`, `pack` (jeux) et `isolate` : un événement
    par succès, et un par échec avec la raison (slug, nom, raison technique).
  - `lib/zgp-log-viewer.sh` : sous-commande `lpm log` (défaut : 50 dernières lignes),
    `-n <N>`, `--all`, `--grep <motif>`, `--clear` (avec confirmation).
- **`lpm list-isolable`**
  - Détection de store extraite de `zgp-game-isolator.sh` vers
    `zgu-lutris-utils.sh` (`zgu_detect_isolation_store`, `zgu_store_display_name`),
    réutilisée à l'identique par l'isolateur et par la nouvelle commande, pour que les
    deux ne divergent jamais sur le store détecté.
  - `lib/zgp-isolable-lister.sh` : liste slug / nom / store à viser, uniquement pour les
    jeux dont le store est réellement reconnu (jamais un slug que `isolate` refuserait
    ensuite).
- **Page man** : `man/lpm.1` (troff complet : toutes les commandes, options, fichiers).
  `bin/lpm --help`/`-h` exécute `man lpm` si la page est installée (`man -w lpm`
  réussit), sinon repli sur le texte d'aide intégré existant (utile en dev, avant
  installation).
- **Routage `bin/lpm`** : `list-isolable` et `log` ajoutés au dispatch de commandes et à
  l'aide affichée.
- Clés de langue ajoutées dans `lang/fr.lang` et `lang/en.lang` pour tout ce qui précède.
- Syntaxe (`bash -n`) vérifiée sur tous les fichiers modifiés/créés : OK.

- **Complétion bash** (`completions/lpm.bash`, créé) : équivalent de `completions/_lpm`
  (zsh) au format `complete`/`compgen`. Couvre les sous-commandes (dont `list-isolable`
  et `log`), `-y`, les niveaux de compression `-0` à `-22`, la complétion dynamique des
  slugs (`lpm list`) et noms de runners (`lpm list-runner`) installés, les slugs
  isolables (`lpm list-isolable`, réutilisé aussi côté `isolate`), la complétion de
  fichiers `*.zgp`/`*.zgr` pour `install`/`install-runner`, et pour `log` : `-n`,
  `--all`, `--grep`, `--clear`.
- **`completions/_lpm` (zsh)** : mis à jour — `list-isolable` et `log` (avec ses
  options) ajoutés à `_lpm_commands` et au `case` de `_lpm()` ; le `case isolate)`
  complète désormais dynamiquement via `lpm list-isolable` (nouvelle fonction
  `_lpm_isolable_slugs`) au lieu de laisser le champ libre.
- **`install.sh`** : installe désormais aussi :
  - `man/lpm.1` → `/usr/local/share/man/man1/lpm.1`, puis `mandb 2>/dev/null || true`
    (best-effort, comme `update-desktop-database`/`update-mime-database`).
  - `completions/lpm.bash` → `/usr/local/share/bash-completion/completions/lpm`,
    optionnel comme la complétion zsh (absence de dossier n'interrompt pas
    l'installation).
- **`uninstall.sh`** : symétrique — retire `/usr/local/share/man/man1/lpm.1` (+
  `mandb`) et `/usr/local/share/bash-completion/completions/lpm` en plus de ce qui
  était déjà désinstallé.
- **Vérification** : `bash -n` OK sur `completions/lpm.bash`, `install.sh`,
  `uninstall.sh`. `_lpm` (zsh) relu manuellement (pas de zsh disponible pour `zsh -n`
  dans cette session).

- **Rotation du journal** : `zgu_log_rotate_if_needed` (dans `zgu-log-utils.sh`),
  appelée avant chaque écriture. Au-delà de `ZGU_LOG_MAX_LINES` (10000) lignes,
  `lpm.log` est renommé `lpm.log.1` (un seul niveau de sauvegarde) et un nouveau
  `lpm.log` reprend. `lpm log --all`/`--grep` ne portent que sur `lpm.log` courant, pas
  sur `.1` (cohérent avec l'objectif "déboguer le plus récent", pas un historique
  permanent). `lpm log --clear` purge aussi `lpm.log.1`. Testé fonctionnellement avec un
  seuil abaissé (5 lignes) : rotation confirmée.

- **`lpm info <slug>`** (`lib/zgp-game-info.sh`, nouveau) : affiche les métadonnées d'un
  jeu installé -- nom, slug, wineprefix (résolu en chemin réel), exécutable, version du
  runner Wine/Proton propre à ce jeu (lue dans le YAML de config Lutris, clé
  `wine.version`), date d'installation (`installed_at`), et statut d'isolement (préfixe
  dédié, ou préfixe partagé avec le store visé si reconnu -- même détection que
  `isolate`/`list-isolable`, jamais de divergence). Routé dans `bin/lpm`, aide, page man,
  complétions bash et zsh (complétion sur les slugs installés). Clés `fr`/`en` ajoutées.
  Testé fonctionnellement avec une base Lutris factice (sqlite3 simulé via python3, vrai
  binaire non disponible dans cet environnement sandbox) : jeu à préfixe dédié, jeu en
  préfixe partagé EGS, slug inexistant, argument manquant -- tous les cas se comportent
  comme attendu.

## À faire

- **Vérification finale en conditions réelles** (nécessite un système avec zsh/
  bash-completion/mandb) : `zsh -n completions/_lpm`, tester la complétion bash après
  `source completions/lpm.bash`, tester `lpm --help` avant/après une installation
  réelle (pas seulement simulée), tester `lpm log` sur un journal vide/rempli, tester
  `lpm list-isolable` sur une base sans jeu isolable.
