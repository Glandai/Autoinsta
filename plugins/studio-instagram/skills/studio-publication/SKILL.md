---
name: studio-publication
description: Publie sur Instagram les posts que la photographe a validés et dont l'heure est venue, puis donne le lien. À utiliser quand elle demande « publie le post validé » ou « où en est la publication », ou quand une ancienne tâche planifiée de l'application Claude (version 1) le lance. En version 2.0, la publication au créneau part toute seule, par la planification du Mac, sans Claude.
---

# Publication au créneau

## Mode app autonome

Si ton prompt système dit que l'app Studio Instagram t'a lancé (mode app autonome), personne ne lit la conversation et ton dernier message s'affiche dans l'app :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ;
- tu es déjà dans le studio : lance `./studio …` tel quel, sans `cd` ; pour lire ou chercher, Read, Glob et Grep (les autres commandes Bash sont refusées) ;
- pour montrer un écran : `./studio ui <écran> --jour <jour>`, jamais avec `--attendre`, puis termine ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier (le lien d'un post publié peut y figurer).

Les points propres à ce skill sont marqués « Mode app ». Sinon (mode conversation, dans l'application Claude), suis le skill tel quel.

## 0. Se placer dans le studio

Mode app : tu y es déjà. Mode conversation : le studio est le dossier courant s'il contient `config/compte.yaml`, sinon le chemin donné dans la demande, sinon `~/Studio-Instagram` ; place-toi dedans (`cd`). S'il n'existe pas, lance le skill `studio-instagram:studio-installation`. Puis remets-le à niveau si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

**Anciennes tâches (mode conversation seulement).** Si ta consigne commence par « Tu es le Studio Instagram. Le dossier du studio est … » (tâche planifiée de la version 1) et que `./studio planifier --etat` rend `"active": true`, ne publie rien : le Mac publie déjà au créneau, et deux publications en même temps risqueraient un doublon. Si l'outil des tâches planifiées est disponible, désactive les tâches `studio-instagram-*` encore actives (`update_scheduled_task` avec `enabled: false`). Termine en une ligne.

## 1. Publier ce qui est dû

1. `./studio publier-dus`. Seuls partent les posts qu'elle a validés (statut « approuve ») et dont l'heure est passée.
2. Pour chaque post publié : le titre et le lien. Si la musique est à ajouter dans Instagram (`musique.mode` = `a_ajouter_dans_l_app`) : « Pour la musique : ••• puis Modifier, puis Ajouter de la musique, et cherche « titre » ». Mode conversation : en PushNotification si elle n'est probablement pas devant l'écran.
3. Pour chaque échec : la cause et la marche à suivre (`docs/depannage.md`), en une phrase. Pas de nouvel essai automatique : elle décidera (bouton « Publier maintenant » de l'app, ou ici).
4. Si rien n'était dû : `./studio en-attente`. Si le post du jour est prêt mais pas validé et que le créneau est passé ou dans moins d'une heure : mode conversation, une seule PushNotification « Le post du jour attend ton feu vert » ; mode app, montre-le (`./studio ui apercu --jour <jour>`) et dis qu'il attend son feu vert. Un post validé « au créneau » alors que `./studio planifier --etat` rend `"active": false` ne partira pas tout seul : dis-le.
5. Termine par un résumé de deux lignes. Ne publie jamais un post qu'elle n'a pas validé.
