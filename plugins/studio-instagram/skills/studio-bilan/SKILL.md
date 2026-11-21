---
name: studio-bilan
description: Bilan hebdomadaire du Studio Instagram. Analyse les performances et les choix de la semaine, réécrit les apprentissages, propose une ou deux expériences et des ajustements. Lancé chaque semaine par la planification du Mac (Claude sans fenêtre), par l'app, ou quand la photographe demande « le bilan ».
---

# Bilan de la semaine

## Mode app autonome

Si ton prompt système dit que l'app Studio Instagram t'a lancé (mode app autonome), personne ne lit la conversation et ton dernier message s'affiche dans l'app :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ;
- tu es déjà dans le studio : lance `./studio …` tel quel, sans `cd` ; pour lire ou chercher, Read, Glob et Grep (les autres commandes Bash sont refusées) ;
- pour montrer un écran : `./studio ui <écran> --jour <jour>`, jamais avec `--attendre`, puis termine ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier.

Les points propres à ce skill sont marqués « Mode app ». Sinon (mode conversation, dans l'application Claude), suis le skill tel quel.

## 0. Se placer dans le studio

Mode app : tu y es déjà. Mode conversation : le studio est le dossier courant s'il contient `config/compte.yaml`, sinon le chemin donné dans la demande, sinon `~/Studio-Instagram` ; place-toi dedans (`cd`). S'il n'existe pas, lance le skill `studio-instagram:studio-installation`. Puis remets-le à niveau si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

**Anciennes tâches (mode conversation seulement).** Si ta consigne commence par « Tu es le Studio Instagram. Le dossier du studio est … » (tâche planifiée de la version 1) et que `./studio planifier --etat` rend `"active": true`, le Mac lance déjà le bilan : si l'outil des tâches planifiées est disponible, désactive les tâches `studio-instagram-*` encore actives (`update_scheduled_task` avec `enabled: false`), puis termine en une ligne.

`<jour>` = date du jour au format AAAA-MM-JJ.

## 1. Le bilan

1. `./studio releve`, puis `./studio analyse`. Lis `memoire/performance.md`.
2. Lis les 7 derniers jours de `donnees/choix.jsonl` (idées proposées et choisies), `donnees/retouches.jsonl` (demandes de retouche, et `modification_dans_l_app` : ce qu'elle a changé elle-même dans l'assistant — photos retirées ou ajoutées, légende réécrite, musique) et `donnees/validations.jsonl` (légendes finales). Compare ce que tu avais écrit et ce qui a été publié : c'est la meilleure source pour comprendre son style.
3. Réécris `memoire/apprentissages.md` (60 lignes au plus), en quatre parties :
   - **Ce qui fonctionne** (avec le niveau de confiance : simple indice, à confirmer, solide) ;
   - **À améliorer** ;
   - **Préférences de la photographe** (choix, refus, retouches récurrentes) ;
   - **À tester la semaine prochaine** : deux ou trois expériences précises et compatibles avec la charte (un pilier, un format, une longueur de légende, un créneau).
   Remplace ce qui est dépassé, garde les leçons solides.
4. Si `memoire/gouts.md` dépasse 80 lignes, condense-le (fusionne les doublons, garde les dates des observations récentes).

## 2. Le message pour elle

- **Mode app** : ne modifie aucun réglage. `./studio ui statistiques --jour <jour>`, puis deux phrases : la publication qui a le mieux marché et pourquoi, et l'expérience proposée (avec le réglage suggéré s'il y en a un, qu'elle pourra changer dans Réglages). Pas de notification : le Mac ou l'app la préviennent.
- **Mode conversation** : cinq lignes au plus, sans jargon : la publication qui a le mieux marché et pourquoi, une chose à améliorer, l'expérience proposée. Si un réglage aiderait (heure d'un créneau, part de Reels, nombre d'idées), demande-lui avec AskUserQuestion ; ne modifie `config/compte.yaml` qu'après son accord, puis lance `./studio planifier --appliquer` pour que le Mac suive les nouvelles heures (elle peut aussi tout changer dans l'app, écran Réglages : la planification suit alors toute seule). PushNotification « Ton bilan de la semaine est prêt » si elle n'est probablement pas devant l'écran.
