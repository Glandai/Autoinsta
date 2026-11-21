# Dépannage

Le plus simple : décrire le souci à Claude, dans le panneau « Demander à Claude » de l'app, ou dans l'application Claude (onglet Code, dossier du studio). Pour un diagnostic complet : `./studio verifier` (dans le Terminal, depuis le dossier du studio).

## Installation et app

| Ce qui s'affiche | Ce que ça veut dire | Que faire |
|---|---|---|
| « Le studio n'est pas installé dans ce dossier » | le dossier de travail n'a pas été préparé | dans l'application Claude : `/studio-instagram:studio-installation` |
| « Python 3 est introuvable », « Compilateur Swift introuvable », « app non construite » | les outils de développement d'Apple manquent | dans le Terminal : `xcode-select --install`, cliquer sur « Installer », puis relancer l'installation |
| L'app Studio Instagram est introuvable, ou Claude dit que les idées sont prêtes « dans l'application Claude » | l'app n'a pas été construite, ou a été déplacée ou supprimée | relancer l'installation : elle reconstruit l'app dans `~/Applications` (le dossier Applications de ton compte) |
| Les commandes `/studio-instagram:…` n'apparaissent pas | le plugin n'est pas installé ou pas activé | voir le README du catalogue (installation du plugin), puis redémarrer l'application Claude |
| « Le studio n'a pas sa copie du plugin » | la copie que l'app donne à Claude manque | relancer l'installation |

## Claude dans l'app

| Ce qui s'affiche | Ce que ça veut dire | Que faire |
|---|---|---|
| « Claude Code n'est pas installé sur ce Mac » | l'app ne trouve pas Claude Code | dans l'app, « Installer Claude Code ». En cas d'échec : vérifier Internet et réessayer, ou l'installer depuis claude.com/product/claude-code |
| « Claude Code est installé mais pas connecté », « Claude n'est plus connecté » | la connexion à ton compte Claude manque ou a expiré | dans l'app (Réglages, partie Claude), « Se connecter » : la page d'Anthropic s'ouvre dans le navigateur. Si rien ne s'ouvre, utilise le lien de secours affiché ; si une petite fenêtre Terminal s'ouvre, suis ses indications |
| « La limite d'utilisation de Claude est atteinte » | ton abonnement a atteint sa limite pour quelques heures ; elle est partagée avec l'application Claude | attendre qu'elle se renouvelle, puis relancer depuis l'app. Si cela revient souvent : un modèle plus léger dans les Réglages (partie Claude), moins de longues conversations le matin, ou un abonnement plus large |
| « Les serveurs de Claude sont surchargés » | souci passager chez Anthropic | réessayer dans quelques minutes |
| « Claude n'arrive pas à joindre Internet » | pas de réseau | vérifier la connexion du Mac, puis relancer |
| « Claude a mis trop de temps et a été arrêté » | la tâche a dépassé le délai maximal (45 minutes par défaut) | relancer ; pour une grosse galerie, l'analyse se fera en plusieurs fois |
| « Claude a été interrompu (Mac éteint ou mis en veille ?) » | le Mac s'est arrêté pendant le travail | relancer la tâche depuis l'app |
| « Claude a dû renoncer à … action(s) non autorisée(s) » | dans l'app, Claude n'a le droit qu'aux commandes du studio | en général sans conséquence ; si quelque chose manque, le demander dans l'application Claude |
| « Claude travaille déjà » | une seule tâche de Claude à la fois par studio | attendre la fin (l'app montre l'avancement) ou l'arrêter |

## Planification du Mac

| Ce qui se passe | Pourquoi | Que faire |
|---|---|---|
| La tâche du matin n'est pas partie | planification désactivée, Mac éteint ou session fermée à l'heure prévue, tâche bloquée par macOS, ou Claude non connecté | 1. Réglages de l'app : la planification est-elle active ? 2. Le Mac était-il allumé, session ouverte ? (en veille, la tâche part au réveil ; éteint, elle est sautée : lance les idées depuis l'app). 3. Réglages Système › Général › Ouverture et extensions (« Ouverture » sur les anciens macOS) : Studio Instagram doit être autorisé en arrière-plan. 4. Claude est-il connecté (Réglages de l'app) ? 5. Si rien n'y fait : désactiver puis réactiver la planification dans les Réglages, et regarder `.ui/logs/planification-matin-erreurs.log` avec Claude |
| Un post validé n'est pas parti à l'heure | même causes que ci-dessus, ou publication en échec | l'app (écran Aujourd'hui) dit pourquoi ; « Publier maintenant » |
| « Le Mac n'a pas pu programmer … » | macOS a refusé une tâche | réessayer dans un instant ; si cela se répète, redémarrer le Mac |
| Tout arrive en double (deux routines, deux notifications) | les anciennes tâches planifiées de l'application Claude (version 1) tournent encore | les mettre en pause dans l'application Claude (tâches planifiées `studio-instagram-…`), ou lancer `/studio-instagram:studio-installation`, qui s'en charge |
| Pas de notification sur le Mac | les notifications du studio sont bloquées | Réglages Système › Notifications : autoriser « Éditeur de script » (c'est lui qui affiche les notifications du studio) |

## Personnaliser l'app

| Ce qui se passe | Pourquoi | Que faire |
|---|---|---|
| « Personnalisations de l'app à fusionner » après une mise à jour | un fichier de l'app que tu as fait personnaliser a aussi changé dans la nouvelle version ; ta version est gardée | demander à Claude « fusionne les personnalisations de l'app » (panneau « Demander à Claude » ou application Claude) |
| Une couleur ou un réglage d'apparence ne change pas | valeur non reconnue dans `config/app.yaml` | Réglages › Apparence dans l'app, ou demander à Claude de corriger |
| Une personnalisation n'a pas donné ce que tu voulais | | demander à Claude « annule le dernier changement de l'app » ou « reviens à l'app d'origine » |
| L'app ne s'ouvre plus après une personnalisation | cas rare : l'app compile mais plante | dans l'application Claude, onglet Code, dossier du studio : « l'app ne s'ouvre plus, reviens en arrière ». En dernier recours : supprimer le dossier `app` du studio et relancer l'installation (les personnalisations sont perdues, tout le reste est gardé) |

## Instagram, Pic-Time et publication

| Ce qui s'affiche | Ce que ça veut dire | Que faire |
|---|---|---|
| « Jeton Instagram absent » | Instagram pas encore connecté | `docs/connexion-instagram.md` |
| « Jeton Instagram invalide » ou « a expiré » | le jeton de 60 jours est périmé, ou le mot de passe Facebook a changé | refaire « Obtenir le jeton » (route A), puis dire « c'est fait » à Claude |
| « Pic-Time ne donne pas accès à cette galerie » | le lien demande un code ou une inscription | copier le lien de partage direct (`docs/pic-time.md`) |
| « cloudflared est absent » | l'outil d'adresse temporaire n'a pas été téléchargé | relancer l'installation, ou passer à Supabase |
| « L'adresse temporaire ne répond pas » | réseau qui bloque Cloudflare | réessayer plus tard, ou passer à Supabase (`docs/connexion-instagram.md`) |
| « Instagram a refusé : … aspect ratio » | une image hors format | demander à Claude de refaire la mise en page du post (`./studio rendre <jour>`) |
| « Identification refusée … publiée sans » | un compte identifié n'existe pas ou n'accepte pas les identifications | corriger le compte de la galerie (écran Galeries) |
| « Collaborateurs ou lieu refusés » | un collaborateur ou un identifiant de lieu non valide | le post est parti sans ; corriger la galerie |

Pour une publication sans risque (rien n'est envoyé, on voit seulement les requêtes) : `./studio publier <jour> --simulation`.
