# **CalDAV** gestion calendrier, **CardDAV** gestion carnet d'adresse

## Préambule

Je n'ai pas testé les services gratuits d'EteSync, je recommande d'utiliser Vivaldi (il suffit de faire un compte), j'ai régulièrement des soucis de sync avec fruux.

En dehors de CalDAV/CardDAV attention à passer via KeePassXC pour vos mdp sur navigateur et Floccus (je conseille avec WebDAV) pour vos signets, il n'est pas recommandé de mettre tous ses œufs dans le même panier.

### Services CalDAV/CardDAV gratuits

- [Compte Vivaldi (recommandé)](https://vivaldi.net/wp-login.php)
- [Compte Fruux](https://fruux.com) - (`https://dav.fruux.com`)
- [Compte EteSync](https://www.etesync.com)

## Connexion Thunderbird (Desktop) et DAVx5 (Android)

Je vais ici décrire la marche à suivre pour Thunderbird, c'est quasi identique avec DAVx5, au moment d'ajouter un compte il suffit de veiller à choisir `Connexion avec une URL et un nom d'utilisateur`.

- Aller dans la partie "Agenda" et cliquer sur "Nouvel agenda..." "Sur le réseau"

- Nom d'utilisateur :
  `_nom_de_compte_mail_@vivaldi.net`

- Adresse :
  `vivaldi.net`

- Cliquer sur "Rechercher des agendas", puis :
  Mdp
  `_Votre MDP_`

## Linux - Application `Comptes en ligne`

Dans l'exemple j'utilise un compte vivaldi.

- Ouvrir l'application `Comptes en ligne`
- Choisir `WebDAV`
- Adresse de serveur : `https://calendar.vivaldi.net/`
- Nom d’utilisateur : `#Adresse mail complète#`
- Mot de passe : `#VotreMDP#`
- Ne rien mettre dans `Fichier`, `Calendrier (CalDAV)` et `Contacts (CardDAV)`

Voilà, Agenda et Contacts seront bien synchronisés.
