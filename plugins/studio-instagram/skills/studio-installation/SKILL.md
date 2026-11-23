---
name: studio-installation
description: Installe, met à jour et configure le Studio Instagram sur un Mac (dossier de travail, app Mac Studio Instagram, connexion de Claude Code, paramètres du compte, Instagram, galeries Pic-Time, historique, planification du Mac, essai). À lancer une fois avec la photographe depuis l'application Claude, pour reprendre une installation faite en une commande, pour mettre à jour le studio, ou pour passer de la version 1 (tâches planifiées de l'application Claude) à la version 2.0.
---

# Installation guidée (environ 30 minutes)

Avance une étape à la fois, en expliquant simplement ce qui se passe, et tiens un court récapitulatif des étapes terminées. Le plugin apporte le savoir-faire ; le dossier de travail garde ses réglages et ses données ; l'app Mac **Studio Instagram** est l'endroit où elle travaillera chaque jour : c'est elle qui lance Claude, sans fenêtre, et la planification du Mac s'occupe des heures.

Si le dossier existe déjà (installation faite en une commande, ou version précédente), rien n'est perdu : refais l'étape 1 (rapide), puis saute les étapes déjà faites (`./studio verifier` et `config/compte.yaml` le disent).

## Mode app autonome

L'installation se fait avec elle, dans l'application Claude. Si ton prompt système dit que l'app Studio Instagram t'a lancé (panneau « Demander à Claude »), personne ne lit la conversation :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ; tu es déjà dans le studio : lance `./studio …` sans `cd` ;
- tu peux vérifier (`./studio verifier --rapide`, `./studio claude statut`, `./studio planifier --etat`), montrer l'écran utile (`./studio ui reglages --jour <jour>`, sans `--attendre`), activer ou couper la planification si sa demande le dit clairement (`./studio planifier --activer` ou `--desactiver`), et, si elle dit avoir collé ses identifiants Instagram dans `.env`, lancer `./studio jeton echanger` puis `./studio jeton verifier` ;
- pour une installation complète, une mise à jour ou la connexion Instagram pas à pas, dis-lui d'ouvrir l'application Claude, onglet Code, et d'écrire `/studio-instagram:studio-installation` ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier.

## 1. Le dossier de travail

- Propose `~/Studio-Instagram` (elle peut en choisir un autre, de préférence sans espace dans le chemin). Note son chemin absolu : `<CHEMIN>`.
- `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" "<CHEMIN>"` (deux à cinq minutes : moteur, Python, ffmpeg, cloudflared, copie du plugin pour l'app (`.plugin/`), sources de l'app (`app/`), puis l'app construite sur place dans `~/Applications`). Dans un dossier existant, réglages, données, apparence et personnalisations de l'app sont conservés.
- `cd "<CHEMIN>"`, puis `./studio verifier`. Les points d'exclamation sont normaux à ce stade ; un ✗ sur l'installation elle-même se règle maintenant (`docs/depannage.md`).
- « app non construite » : les outils de développement d'Apple manquent. Propose `xcode-select --install` (elle clique sur « Installer » dans la fenêtre qui s'ouvre), puis relance l'installation. Sans app, tout fonctionne quand même avec des pages web dans l'application Claude, mais sans l'autonomie de l'app.
- « Personnalisations de l'app à fusionner » : après l'installation, lance le skill `studio-instagram:studio-app` (partie « Après une mise à jour »).

## 2. L'app et la connexion de Claude Code

- `./studio ui aujourdhui --forcer` ouvre l'app. Présente-la en deux phrases : elle y choisira les idées du matin, validera les posts d'un clic et réglera tout elle-même (réglages, charte, règles, galeries, statistiques, apparence) ; Claude y travaille en arrière-plan, elle voit ce qu'il fait, et l'app s'ouvre toute seule quand une décision l'attend.
- L'app a besoin de Claude Code, la version de Claude qu'elle lance sans fenêtre. Regarde `./studio claude statut` :
  - `installe` et `connecte` à true : rien à faire, dis-le en une phrase ;
  - sinon, l'app la guide d'elle-même, en deux clics : « Installer Claude Code » si besoin, puis « Se connecter ». Le navigateur s'ouvre sur la page de connexion d'Anthropic, où elle se connecte avec son compte Claude habituel (celui de son abonnement). Laisse-la faire dans l'app. Si elle préfère que tu le lances, avec son accord explicite : `./studio claude installer`, puis `./studio claude connecter` (`url` donne un lien de secours si le navigateur ne s'ouvre pas ; `terminal_ouvert` : une petite fenêtre Terminal la guide) ;
  - relance `./studio claude statut` jusqu'à `"connecte": true`. En cas de blocage, le champ `conseil` dit quoi faire (voir aussi `docs/depannage.md`). `plugin_present` à false : refais l'étape 1.
- Elle tape son mot de passe dans le navigateur, jamais ici ni dans l'app. Ne lance jamais `claude auth login` toi-même.
- Dis-lui en une phrase que le Claude de l'app utilise son abonnement : ses limites d'utilisation sont partagées avec l'application Claude.
- Au quotidien, l'app suffit. Pour discuter plus longuement avec Claude, personnaliser l'app ou faire une mise à jour, elle ouvre ce dossier dans l'application Claude (onglet Code) : `CLAUDE.md` et les autorisations du studio s'y appliquent.

## 3. Les paramètres du compte (`config/compte.yaml`)

Le fichier part vide (`[À COMPLÉTER : …]`) : le studio sert à n'importe quel compte. L'onboarding de l'app pose les questions (nom, compte Instagram, activité, ville, voix, langue, approche) ; si l'activité n'est pas la photo de mariage, l'app demande à Claude d'adapter la charte (`./studio claude lancer charte`). Deux façons de le compléter : dans l'app (`./studio ui reglages --forcer`, écran Réglages, « Enregistrer » ; relis ensuite `config/compte.yaml` avec elle), ou ici :
- AskUserQuestion, en une fois : la voix des légendes (« je » ou « nous »), la langue (français, anglais, bilingue français puis anglais), le rythme (chaque jour, 5, 3 ou 2 fois par semaine).
- L'heure de publication qu'elle préfère (par défaut 18:30 en semaine) : ajuste `publication.creneaux` (supprime les jours sans post).
- Son approche en trois à cinq phrases, avec ses mots : manière de travailler, argentique ou numérique, rapport aux mariés, ce qui distingue son travail. Recopie ses mots tels quels dans `approche` : c'est la seule source autorisée pour parler de sa pratique.
- Deux ou trois de ses vraies légendes préférées (`exemples_de_legendes`) : c'est ce qui aide le plus à trouver le ton.
- Montre le résumé et corrige si besoin. Si tu as changé des heures alors que la planification est déjà active, lance `./studio planifier --appliquer`.

## 4. Connecter Instagram

Explique les deux routes de `docs/connexion-instagram.md` et recommande la route A (Facebook). Elle fait elle-même chaque étape dans son navigateur : tu guides, tu ne te connectes pas à sa place, tu ne demandes jamais un mot de passe, un code ni un jeton dans la conversation, et tu ne lis jamais `.env`.
- Quand elle a ses identifiants, elle les colle elle-même dans `.env` : propose de l'ouvrir dans TextEdit (`open -e .env`).
- Route A : `./studio jeton echanger` (jeton long et identifiant du compte), puis `./studio jeton verifier`.
- Route B : mets `instagram.api: instagram` dans `config/compte.yaml`, puis `./studio jeton echanger` et `./studio jeton verifier`.
- Puis `./studio verifier`.

## 5. Les galeries Pic-Time

Une à trois galeries récentes pour commencer (les plus fortes). Elle peut les ajouter dans l'app (`./studio ui galeries --forcer`, « Ajouter une galerie » : l'app confie ensuite l'analyse à Claude, en arrière-plan) ou ici avec le skill `studio-instagram:studio-galerie`. Au moins une série doit être indexée et analysée en entier avant la première routine.

## 6. L'historique du compte

- `./studio historique importer --limite 30`, puis `./studio historique planche`.
- Regarde la planche (Read) et, pour chaque numéro, écris le pilier, la fiche feed de la couverture (`tonalite`, `luminosite`, `plan`, `sujet`) et `centree_couple` dans `donnees/classement-historique.json` (format `{"1": {"pilier": "PLACES", "fiche_feed": {...}, "centree_couple": false}}`), puis `./studio historique noter donnees/classement-historique.json`.
- `./studio releve` puis `./studio analyse` : c'est le point de départ des apprentissages.

## 7. La planification du Mac

Explique simplement, en trois phrases au plus :
- chaque matin à l'heure des idées, Claude les prépare et l'app s'ouvre pour qu'elle choisisse ; aux heures de publication, les posts qu'elle a validés partent ; chaque semaine (le dimanche par défaut), le bilan arrive ;
- c'est le Mac qui s'en charge, même quand l'app et l'application Claude sont fermées : il doit être allumé, sa session ouverte (s'il est en veille, la tâche part à son réveil) ;
- rien n'est publié sans sa validation : un post qu'elle n'a pas validé ne part jamais.

Puis demande son accord (AskUserQuestion « Activer la planification sur ce Mac ? » : « Oui, activer (Recommandé) », « Pas maintenant »).
- **Oui** : `./studio planifier --activer`. Montre les horaires (`taches[].quand`) en une ou deux lignes. macOS peut signaler qu'un élément d'arrière-plan a été ajouté : c'est normal, il doit rester autorisé (Réglages Système › Général › Ouverture). Si une tâche n'est pas `chargee`, voir `docs/depannage.md`. Elle change ensuite ses heures dans l'app (Réglages) : la planification suit toute seule.
- **Anciennes tâches** (version 1), juste après l'activation : si l'outil des tâches planifiées est disponible, `list_scheduled_tasks`, puis, pour chaque tâche `studio-instagram-*` encore active (matin, publication, publication-2…, bilan), `update_scheduled_task` avec `enabled: false`. Sinon tout serait fait deux fois, publications comprises. Dis-lui qu'elles sont mises en pause, pas supprimées (elle peut les supprimer dans l'application Claude). Sans cet outil, demande-lui de les mettre en pause elle-même (section des tâches planifiées de l'application Claude). Ne crée plus jamais de tâche planifiée dans l'application Claude (ni `./studio taches`, ni `create_scheduled_task`).
- **Pas maintenant** : rien ne part tout seul. Elle demande les idées depuis l'app quand elle veut, et un post validé « à l'heure prévue » ne partira pas : qu'elle utilise « Publier maintenant ». Elle pourra activer la planification plus tard (Réglages de l'app, ou en le demandant à Claude). D'éventuelles anciennes tâches de la version 1 continuent de fonctionner comme avant.

## 8. Sur son téléphone (facultatif)

Les notifications du studio s'affichent sur le Mac. Pour suivre depuis son téléphone ses conversations avec Claude (installation, personnalisation), propose le Contrôle à distance (Remote Control) dans les réglages de l'application Claude. Pour y voir aussi les pages (idées, aperçu) quand elle travaille dans l'application Claude, mets `interface.artifact: true` : elles seront aussi publiées en Artifact privé.

## 9. Essai

- `./studio demo`, puis `./studio ui idees --jour demo --forcer` : elle découvre l'app avec des idées et un post de démonstration (l'écran Aperçu montre le post). Rien n'est publié. Sans app : montre `jours/demo/idees.html` et `jours/demo/apercu.html` avec SendUserFile.
- Propose une première vraie routine du matin. Avec son accord : `./studio claude lancer matin` (Claude travaille sans fenêtre ; l'app montre son avancement, puis les idées). `non_connecte` ou `absent` : reviens à l'étape 2. `deja_en_cours` : Claude travaille déjà pour l'app (une analyse de galerie, par exemple) ; elle relancera la routine depuis l'app quand ce sera fini.

## 10. Récapitulatif

Termine par la liste de ce qui est en place et de ce qui reste à faire (par exemple : approche à compléter, galerie à ajouter, jeton à renouveler le JJ/MM, planification à activer).

## Mettre à jour le studio

- Après une mise à jour du plugin, chaque skill lancé depuis l'application Claude remet le studio à niveau tout seul (`installer.sh --si-besoin` : moteur, copie du plugin, sources et app reconstruite si besoin). À la main : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" "<CHEMIN>"`. Les routines lancées par l'app ou par le Mac utilisent la copie du plugin du studio et ne font pas cette mise à jour : une session dans l'application Claude suffit, une fois.
- Les réglages, la mémoire, les données, l'apparence (`config/app.yaml`) et les personnalisations de l'app (`app/`) ne sont jamais écrasés. Un fichier de l'app personnalisé qui a aussi changé dans la nouvelle version est signalé dans `app/.conflits.json` : lance alors le skill `studio-instagram:studio-app` pour fusionner en gardant ses personnalisations.
- Depuis la version 1 (tâches planifiées de l'application Claude) : étape 1, étape 2 (ouvrir l'app, connecter Claude Code), puis étape 7 (planification du Mac avec son accord, et mise en pause des anciennes tâches).
