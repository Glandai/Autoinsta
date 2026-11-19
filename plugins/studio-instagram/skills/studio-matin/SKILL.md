---
name: studio-matin
description: Routine du matin du Studio Instagram. Relève les statistiques, met à jour ce qui fonctionne, analyse les nouvelles galeries Pic-Time, présente 3 idées de post à la photographe puis enchaîne sur la création du post choisi. À lancer chaque matin (tâche planifiée) ou quand elle demande « les idées du jour ».
---

# Routine du matin

## 0. Se placer dans le studio

Le dossier du studio est le dossier courant s'il contient `config/compte.yaml` ; sinon le chemin donné par la tâche planifiée ; sinon `~/Studio-Instagram`. Place-toi dedans (`cd`). S'il n'existe pas encore, lance le skill `studio-instagram:studio-installation`.
Mets ensuite le moteur à jour si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

Lis `prompt/directeur-artistique.md` si ce n'est pas déjà fait dans cette session. `<jour>` = date du jour au format AAAA-MM-JJ.

## 1. Vérifier et reprendre

- `./studio verifier --rapide`. Si une ligne ✗ bloque (jeton invalide, outil manquant), explique la cause et la solution en une phrase (voir `docs/depannage.md`) et continue ce qui peut l'être : les idées peuvent être proposées même si Instagram n'est pas connecté.
- Si `jours/<jour>/etat.json` existe déjà, reprends où on en était : idées proposées → repose la question ; brouillon prêt → remontre l'aperçu et repose la question ; approuvé ou publié → résume en une ligne et termine.
- `./studio etat` : si `prochain_creneau_aujourdhui` vaut null, il n'y a pas de post aujourd'hui. Fais seulement l'étape 2, puis termine.

## 2. Apprendre

- `./studio releve`, puis `./studio analyse`.
- Lis `memoire/performance.md`, `memoire/gouts.md` et `memoire/apprentissages.md`.
- Jeton Instagram (`./studio jeton verifier`) : en route Instagram (`instagram.api: instagram`), s'il expire dans moins de 30 jours, lance `./studio jeton renouveler` (automatique). En route Facebook, s'il expire dans moins de 10 jours, signale-le en une ligne avec la marche à suivre (`docs/connexion-instagram.md`, partie « Renouveler »).

## 3. Préparer la matière

- `./studio pictime etat`.
- Série `a_indexer` : `./studio pictime indexer <serie>`.
- Série avec des photos `a_analyser` (au plus 2 séries et environ 120 photos par matin ; le reste attendra demain) :
  1. `./studio planches <serie>` ;
  2. regarde chaque planche avec Read. Pour chaque numéro, note : `note` de 1 à 5 (5 = arrête le défilement : force, singularité, émotion, lumière), `pilier`, `plan`, `sujet`, `moment` (préparatifs, cérémonie, cocktail, portraits, dîner, soirée, lieu…), `description` factuelle en une phrase, `centree_couple` (vrai ou faux). Les quasi-doublons d'une même rafale prennent une note plus basse et une `remarque`. Une photo couchée ou à l'envers (appareil sans orientation) reçoit `rotation` : 90, 180 ou 270, dans le sens horaire. Les photos `mise_en_avant` (choisies par la photographe dans Pic-Time) méritent un regard particulier ;
  3. écris `catalogue/<serie>/planches/notes.json` au format `{"12": {"note": 4, "pilier": "PLACES", ...}}`, puis `./studio noter <serie> catalogue/<serie>/planches/notes.json`.
- `./studio etat` (contraintes du feed) et `./studio candidats` (meilleures photos jamais publiées).

## 4. Imaginer les idées (mode « idees » du prompt)

- Imagine au moins six idées. Écarte celles qui enfreignent une contrainte de `./studio etat`. Garde-en `routine.nombre_idees` (3 par défaut) :
  - vraiment différentes (format, pilier, série, ton) ;
  - dont `routine.idees_exploration` (1) en « exploration » : un format, un pilier ou une approche peu essayés ;
  - un brouillon reporté d'un jour précédent peut redevenir une idée.
- Pour classer, pèse dans cet ordre : règles (obligatoire), identité, goûts de la photographe, performances, fraîcheur (séries et piliers absents depuis longtemps).
- Regarde vraiment la couverture envisagée de chaque idée (`catalogue/<serie>/vignettes/<id>.jpg`).
- Écris `jours/<jour>/idees.json` (format au point 11 du prompt), puis `./studio idees <jour>` (corrige si des erreurs reviennent).

## 5. Présenter

- Montre `jours/<jour>/idees.html` avec SendUserFile (`display: "render"`). Si `interface.artifact` vaut true, publie-la aussi en Artifact privé (même chemin de fichier chaque jour) et donne le lien.
- PushNotification : « 3 idées pour le post de HH:MM t'attendent ».
- AskUserQuestion « Quelle idée pour aujourd'hui ? » : une option par idée (label : le titre, 5 mots maximum ; description : le pitch en une phrase). Elle peut aussi écrire sa propre idée dans le champ libre. Si l'outil n'est pas disponible, termine par la liste numérotée et attends sa réponse.
- Ton message : deux ou trois phrases, sans jargon (pas de JSON, pas de commande).

## 6. Quand elle répond

- Idée n : `./studio choix <jour> n`. Idée libre : `./studio choix <jour> --libre "<ses mots>"`. Si l'idée libre est ambiguë (quelle série ?), pose une seule question ; sinon décide.
- Si le choix révèle une préférence, ajoute une ligne datée à `memoire/gouts.md` (par exemple : « 18/11 : a choisi le lieu vide plutôt que les portraits »).
- Enchaîne aussitôt avec le skill `studio-instagram:studio-creation`.
