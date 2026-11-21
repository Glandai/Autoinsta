---
name: studio-matin
description: Routine du matin du Studio Instagram. Relève les statistiques, met à jour ce qui fonctionne, analyse les nouvelles galeries et propose les idées de post du jour dans l'app Mac Studio Instagram, puis enchaîne sur la création du post choisi. Lancée chaque matin par la planification du Mac (Claude sans fenêtre), par l'app, ou quand la photographe demande « les idées du jour ».
---

# Routine du matin

## Mode app autonome

Si ton prompt système dit que l'app Studio Instagram t'a lancé (mode app autonome), personne ne lit la conversation et ton dernier message s'affiche dans l'app :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ;
- tu es déjà dans le studio : lance `./studio …` tel quel, sans `cd` ; pour lire ou chercher, Read, Glob et Grep (les autres commandes Bash sont refusées) ;
- pour montrer un écran : `./studio ui <écran> --jour <jour>`, jamais avec `--attendre`, puis termine. Elle décide dans l'app, qui relance Claude quand il y a du travail ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier.

Les points propres à ce skill sont marqués « Mode app ». Sinon (mode conversation, dans l'application Claude), suis le skill tel quel.

## 0. Se placer dans le studio

Mode app : tu y es déjà. Mode conversation : le studio est le dossier courant s'il contient `config/compte.yaml`, sinon le chemin donné dans la demande, sinon `~/Studio-Instagram` ; place-toi dedans (`cd`). S'il n'existe pas, lance le skill `studio-instagram:studio-installation`. Puis remets-le à niveau si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

Lis la charte si ce n'est pas déjà fait dans cette session : `config/charte.md` (sa version, modifiable dans l'app ; à défaut `prompt/directeur-artistique.md`). `<jour>` = date du jour au format AAAA-MM-JJ.

## 1. Vérifier et reprendre

- **Anciennes tâches (mode conversation seulement).** Si `./studio planifier --etat` rend `"active": true`, c'est le Mac qui lance les routines. Si l'outil des tâches planifiées est disponible et que `list_scheduled_tasks` montre des tâches `studio-instagram-*` encore actives (version 1), désactive-les (`update_scheduled_task` avec `enabled: false`) et dis-le en une ligne. Si c'est l'une d'elles qui vient de te lancer (ta consigne commence par « Tu es le Studio Instagram. Le dossier du studio est … »), arrête-toi après cette ligne : la routine du Mac fait déjà le travail. Ne crée jamais de tâche planifiée dans l'application Claude.
- `./studio verifier --rapide`. Si une ligne ✗ bloque (jeton invalide, outil manquant), donne la cause et la solution en une phrase (`docs/depannage.md`) et continue ce qui peut l'être : les idées peuvent être proposées même si Instagram n'est pas connecté.
- Décision en suspens : si `jours/<jour>/decision.json` existe avec `"traitee": false`, elle a décidé dans l'app sans que personne ne s'en occupe. Traite-la tout de suite : un choix d'idée comme à l'étape 6, une retouche avec le skill `studio-instagram:studio-creation` (étape 5).
- Si `jours/<jour>/etat.json` existe déjà, reprends où on en était : idées proposées → étape 5 ; idée choisie → skill `studio-instagram:studio-creation` ; brouillon prêt → étape 4 de `studio-creation` ; approuvé ou publié → résume en une ligne et termine.
- `./studio etat` : si `prochain_creneau_aujourdhui` vaut null, pas de post aujourd'hui. Fais seulement l'étape 2, puis termine.

## 2. Apprendre

- `./studio releve`, puis `./studio analyse`.
- Lis `memoire/performance.md`, `memoire/gouts.md` et `memoire/apprentissages.md`.
- Jeton Instagram (`./studio jeton verifier`) : en route Instagram (`instagram.api: instagram`), s'il expire dans moins de 30 jours, `./studio jeton renouveler`. En route Facebook, s'il expire dans moins de 10 jours, signale-le en une ligne avec la marche à suivre (`docs/connexion-instagram.md`, « Renouveler »).

## 3. Préparer la matière

- `./studio pictime etat`.
- Série `a_indexer` : `./studio pictime indexer <serie>`.
- Série avec des photos `a_analyser` (au plus 2 séries et environ 120 photos par matin ; le reste attendra demain) :
  1. `./studio planches <serie>` ;
  2. regarde chaque planche avec Read. Pour chaque numéro : `note` de 1 à 5 (5 = arrête le défilement : force, singularité, émotion, lumière), `pilier`, `plan`, `sujet`, `moment` (préparatifs, cérémonie, cocktail, portraits, dîner, soirée, lieu…), `description` factuelle en une phrase, `centree_couple` (vrai ou faux). Les quasi-doublons d'une même rafale prennent une note plus basse et une `remarque`. Une photo couchée ou à l'envers reçoit `rotation` : 90, 180 ou 270, dans le sens horaire. Les photos `mise_en_avant` (choisies par la photographe dans Pic-Time) méritent un regard particulier ;
  3. écris `catalogue/<serie>/planches/notes.json` au format `{"12": {"note": 4, "pilier": "PLACES", ...}}`, puis `./studio noter <serie> catalogue/<serie>/planches/notes.json`.
- `./studio etat` (contraintes du feed) et `./studio candidats` (meilleures photos jamais publiées).

## 4. Imaginer les idées (mode « idees » de la charte)

- Imagine au moins six idées. Écarte celles qui enfreignent une contrainte de `./studio etat`. Garde-en `routine.nombre_idees` (3 par défaut) :
  - vraiment différentes (format, pilier, série, ton) ;
  - dont `routine.idees_exploration` (1) en « exploration » : un format, un pilier ou une approche peu essayés ;
  - un brouillon reporté d'un jour précédent peut redevenir une idée.
- Pour classer, pèse dans cet ordre : règles (obligatoire), identité, goûts de la photographe, performances, fraîcheur (séries et piliers absents depuis longtemps).
- Regarde vraiment la couverture envisagée de chaque idée (`catalogue/<serie>/vignettes/<id>.jpg`).
- Écris `jours/<jour>/idees.json` (format au point 11 de la charte), puis `./studio idees <jour>` (corrige si des erreurs reviennent).

## 5. Présenter les idées

**Mode app**
- `./studio ui idees --jour <jour>`, puis termine en deux phrases, par exemple : « Trois idées pour ton post de 18:30 t'attendent. Choisis celle qui te parle, ou écris la tienne. »
- Ne lance pas la création toi-même : quand elle choisit, l'app enregistre son choix et relance Claude.
- Si la commande rend `"etat": "app_absente"`, dis seulement que les idées sont prêtes et qu'elle peut les voir en demandant « les idées du jour » dans l'application Claude.

**Mode conversation**
- PushNotification : « 3 idées pour le post de HH:MM t'attendent ».
- Lance avec Bash, **en arrière-plan** (`run_in_background: true`) : `./studio ui idees --jour <jour> --attendre --delai 36000`. L'app s'ouvre sur les idées ; elle en choisit une d'un clic ou écrit la sienne. La commande se termine dès qu'elle a décidé et rend sa décision (tu es alors relancé avec le résultat).
- Dis-lui en une ou deux phrases que les idées l'attendent dans l'app, puis termine ton tour, sans autre question.
- Si la commande se termine aussitôt avec `"etat": "app_absente"` : montre `jours/<jour>/idees.html` avec SendUserFile (`display: "render"`), puis AskUserQuestion « Quelle idée pour aujourd'hui ? » : une option par idée (label : le titre, 5 mots au plus ; description : le pitch en une phrase), sa propre idée restant possible dans le champ libre. Sans cet outil, termine par la liste numérotée et attends sa réponse.
- Si `interface.artifact` vaut true, publie aussi `idees.html` en Artifact privé (même chemin de fichier chaque jour) et donne le lien.

## 6. Quand elle a choisi

Mode app : cette étape ne sert qu'à une décision en suspens trouvée à l'étape 1 (sinon l'app lance elle-même la création quand elle clique).

- **Dans l'app** (résultat de la commande d'attente, ou décision en suspens) : `decision.type` vaut `choix` (avec `numero`) ou `libre` (avec `texte`). L'app a déjà enregistré le choix : ne relance pas `./studio choix`. Marque la décision : `./studio app decision-traitee <jour>`.
  - `delai_depasse` : rien n'a été choisi. Dis-le en une ligne (elle peut toujours choisir dans l'app) et termine.
- **Dans la conversation** : idée n → `./studio choix <jour> n` ; idée libre → `./studio choix <jour> --libre "<ses mots>"`. Si l'attente de l'app tourne encore, arrête-la (TaskStop).
- Idée libre ambiguë (quelle série ?) : en conversation, une seule question ; en mode app, prends la série la plus proche de ses mots et dis-le dans tes deux phrases.
- Si le choix révèle une préférence, ajoute une ligne datée à `memoire/gouts.md` (par exemple : « 18/11 : a choisi le lieu vide plutôt que les portraits »).
- Enchaîne aussitôt avec le skill `studio-instagram:studio-creation`.
