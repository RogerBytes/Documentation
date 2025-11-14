# **CalDAV** gestion calendrier, **CardDAV** gestion carnet d'adresse

## Préambule

Je n'ai pas testé les services gratuits d'EteSync, je recommande d'utiliser Vivaldi (il suffit de faire un compte), j'ai régulièrement des soucis de sync avec fruux.

En dehors de CalDAV/CardDAV attention à passer via Bitwarden ou KeePassXC pour vos mdp sur navigateur et Floccus (je conseille avec WebDAV) pour vos signets, Vivaldi m'a déjà tout supprimé par exemple, plus niveau sécurité c'est vraiment pas top (faire des backups de coffre de sécurité, d'agendas, de calendriers et de signets et recommandé).


**Services CalDAV/CardDAV gratuits**

- [Compte Vivaldi (recommandé)](https://vivaldi.net/wp-login.php)
- [Compte Fruux](https://fruux.com)  (`https://dav.fruux.com`)
- [Compte EteSync](https://www.etesync.com)

## Connexion Thunderbird (Desktop) et DAVx5 (Android)

Je vais ici décrire la marche à suivre pour Thunderbird, c'est quasi identique avec DAVx5, au moment d'ajouter un compte il suffit de veiller à choisir `Connexion avec une URL et un nom d'utilisateur`.


- Aller dans la partie "Agenda" et cliquer sur "Nouvel agenda..." "Sur le réseau"

- Nom d'utilisateur :
*nom_de_compte_mail*@vivaldi.net

- Adresse :
vivaldi.net

- Cliquer sur "Rechercher des agendas", puis :
Mdp
*Votre MDP*

## Autres

Veillez bien dans les exemples donnés ici (pour les comptes vivaldi) à remplacer `<user@vivaldi.net>` par votre adresse mail (et sans les chevrons `<` `>`).


### Lister les calendriers

`https://calendar.vivaldi.net/calendars/<user@vivaldi.net>/`


On peut lister les agendas  
`https://calendar.vivaldi.net/addressbooks/<user@vivaldi.net>/`



Et on peut se connecter directement à un calendrier, par exemple pour `Personnel`  
`https://calendar.vivaldi.net/calendars/<user@vivaldi.net>/Personnel/`


Sinon, pour celui par défaut  
`https://calendar.vivaldi.net/calendars/<user@vivaldi.net>/default/`

