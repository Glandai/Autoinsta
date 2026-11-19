---
name: studio-galerie
description: Ajoute une nouvelle galerie (série) au Studio Instagram (lien Pic-Time ou dossier, lieu, date, prestataires, prénoms publiables, anecdotes), puis l'indexe et l'analyse. À utiliser quand la photographe livre une nouvelle galerie, ou dit « ajoute le mariage de… ».
---

# Ajouter une galerie

## 0. Se placer dans le studio

Le dossier du studio est le dossier courant s'il contient `config/compte.yaml` ; sinon le chemin donné par la tâche planifiée ; sinon `~/Studio-Instagram`. Place-toi dedans (`cd`). S'il n'existe pas encore, lance le skill `studio-instagram:studio-installation`.
Mets ensuite le moteur à jour si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

1. Rassemble les informations, en deux messages au plus (AskUserQuestion pour les choix fermés, texte libre pour le reste) :
   - le lien de la galerie : dans Pic-Time, ouvrir la galerie, Partager, copier le lien d'accès direct (`docs/pic-time.md`). À défaut, un dossier d'exports sur l'ordinateur ;
   - le type (mariage, shooting, éditorial), le lieu exact, la date ;
   - les prénoms des mariés, et s'ils acceptent qu'ils apparaissent dans les légendes ;
   - les prestataires : rôle, nom, compte Instagram. Seulement ce qu'elle donne : si elle ne connaît pas un compte, `compte: null`. Ne devine jamais un compte ;
   - le contexte et les anecdotes, avec ses mots à elle : c'est la seule matière autorisée pour les récits ;
   - les consignes éventuelles (thème, priorité, à éviter).
2. Ajoute la série dans `config/galeries.yaml` (identifiant court sans accent, par exemple `mas-uzes-2026`, statut `active`). Garde ses mots tels quels dans `notes`.
3. Vérifie l'accès : `./studio pictime analyser-lien "<lien>"` (nombre de photos, scènes, photos mises en avant). Si Pic-Time refuse, explique en une phrase comment obtenir le lien direct, ou propose la source dossier.
4. `./studio pictime indexer <id>`, puis l'analyse visuelle comme dans le skill `studio-instagram:studio-matin` (étape 3 : planches, notes, `./studio noter`), sur toute la série si le temps le permet.
5. Résume en quelques lignes : nombre de photos, ce qui ressort de la série, deux ou trois idées de posts qu'elle permet. Montre une planche des cinq plus fortes si elle le souhaite.
