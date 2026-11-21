---
name: studio-galerie
description: Ajoute une nouvelle galerie (série) au Studio Instagram (lien Pic-Time ou dossier, lieu, date, prestataires, prénoms publiables, anecdotes), puis l'indexe et l'analyse. À utiliser quand la photographe livre une nouvelle galerie ou dit « ajoute le mariage de… », ou quand l'app lance l'analyse d'une galerie qu'elle vient d'enregistrer.
---

# Ajouter une galerie

## Mode app autonome

Si ton prompt système dit que l'app Studio Instagram t'a lancé (mode app autonome), personne ne lit la conversation et ton dernier message s'affiche dans l'app :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ;
- tu es déjà dans le studio : lance `./studio …` tel quel, sans `cd` ; pour lire ou chercher, Read, Glob et Grep (les autres commandes Bash sont refusées) ;
- pour montrer un écran : `./studio ui <écran> --jour <jour>`, jamais avec `--attendre`, puis termine ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier.

En mode app, la fiche est déjà enregistrée par l'app (écran Galeries) : ne pose aucune question, relis la fiche de la série indiquée (`config/galeries.yaml`) et va directement aux étapes 3 et 4. Si aucune fiche ne correspond (demande écrite dans le panneau « Demander à Claude »), ouvre l'écran Galeries (`./studio ui galeries --jour <jour>`) et dis-lui en deux phrases d'y remplir la fiche (lien, lieu, date, prestataires, prénoms) : l'analyse partira dès qu'elle l'aura enregistrée. Les autres points propres à ce skill sont marqués « Mode app ». Sinon (mode conversation, dans l'application Claude), suis le skill tel quel.

## 0. Se placer dans le studio

Mode app : tu y es déjà. Mode conversation : le studio est le dossier courant s'il contient `config/compte.yaml`, sinon le chemin donné dans la demande, sinon `~/Studio-Instagram` ; place-toi dedans (`cd`). S'il n'existe pas, lance le skill `studio-instagram:studio-installation`. Puis remets-le à niveau si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

Si elle a déjà ajouté la galerie dans l'app (écran Galeries), tout est dans `config/galeries.yaml` : relis la fiche et passe à l'étape 3. Elle peut aussi la saisir maintenant dans l'app (`./studio ui galeries --forcer`), ce qui évite les questions.

## 1. La fiche

1. Sinon, rassemble les informations, en deux messages au plus (AskUserQuestion pour les choix fermés, texte libre pour le reste) :
   - le lien de la galerie : dans Pic-Time, ouvrir la galerie, Partager, copier le lien d'accès direct (`docs/pic-time.md`). À défaut, un dossier d'exports sur l'ordinateur ;
   - le type (mariage, shooting, éditorial), le lieu exact, la date ;
   - les prénoms des mariés, et s'ils acceptent qu'ils apparaissent dans les légendes ;
   - les prestataires : rôle, nom, compte Instagram. Seulement ce qu'elle donne : si elle ne connaît pas un compte, `compte: null`. Ne devine jamais un compte ;
   - le contexte et les anecdotes, avec ses mots à elle : c'est la seule matière autorisée pour les récits ;
   - les consignes éventuelles (thème, priorité, à éviter).
2. Ajoute la série dans `config/galeries.yaml` (identifiant court sans accent, par exemple `mas-uzes-2026`, statut `active`). Garde ses mots tels quels dans `notes`.

## 2. L'accès et l'analyse

3. Vérifie l'accès : `./studio pictime analyser-lien "<lien>"` (nombre de photos, scènes, photos mises en avant). Si Pic-Time refuse, explique en une phrase comment obtenir le lien direct, ou propose la source dossier.
4. `./studio pictime indexer <id>`, puis l'analyse visuelle comme dans le skill `studio-instagram:studio-matin` (étape 3 : planches, notes, `./studio noter`), sur toute la série si le temps le permet. Mode app : une quinzaine de planches au plus par exécution ; les routines du matin analyseront le reste.
5. Résume en quelques lignes : nombre de photos, ce qui ressort de la série, deux ou trois idées de posts qu'elle permet. Montre une planche des cinq plus fortes si elle le souhaite.
   Mode app : `./studio ui galeries --jour <jour>`, puis deux phrases : le nombre de photos analysées et ce qui ressort de la série, avec une idée de post qu'elle permet.
