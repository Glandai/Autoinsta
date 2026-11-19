---
name: studio-creation
description: Construit entièrement le post choisi (sélection et ordre des photos, mise en page 4:5, légende, crédits, hashtags, textes alternatifs, musique, identifications), le contrôle, montre l'aperçu à la photographe puis gère sa validation ou ses retouches. À utiliser après le choix d'une idée, ou quand elle demande de créer un post.
---

# Créer le post du jour

## 0. Se placer dans le studio

Le dossier du studio est le dossier courant s'il contient `config/compte.yaml` ; sinon le chemin donné par la tâche planifiée ; sinon `~/Studio-Instagram`. Place-toi dedans (`cd`). S'il n'existe pas encore, lance le skill `studio-instagram:studio-installation`.
Mets ensuite le moteur à jour si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

Charte : `prompt/directeur-artistique.md` (mode « publication »). `<jour>` = dossier du jour dans `jours/`.

## 1. Rassembler

- L'idée choisie : `jours/<jour>/idees.json`, champ `choix`.
- La série : `config/galeries.yaml` (lieu, date, prénoms et autorisation, notes, prestataires, consignes).
- Les contraintes : `./studio etat`. Les goûts et leçons : `memoire/gouts.md`, `memoire/apprentissages.md`.
- Les photos : `./studio candidats --serie <serie> --note-min 3 -n 80`. Présélectionne 15 à 25 photos, télécharge-les (`./studio pictime telecharger <serie> <id> <id> …`) et regarde-les vraiment (Read sur `catalogue/<serie>/hd/<id>.jpg`).

## 2. Construire

- **Carrousel** : 6 à 10 images avec ouverture, progression, respirations, au moins une surprise, clôture. Pour chaque image : `plein_cadre` (avec `ancrage` ou `point_focal` qui protège le sujet) ou `marges` (fond `clair`, `sombre` ou `papier`). Les scans argentiques avec bord de pellicule et les images horizontales qui perdraient leur sens au recadrage vont sur fond. Jamais deux images trop semblables à la suite.
- **Reel** : un plan de montage de 15 à 45 secondes à partir des clips ou des photos de la série (`presentation` par plan), puis `./studio reel monter <jour>`. Regarde `rendu/couverture.jpg`.
- **Musique** :
  - Reel : `./studio musique chercher "<mots simples>"` (par exemple « piano ambient », « strings slow »), choisis une piste cohérente avec la direction sonore et la durée, puis remplis `musique` : `mode: api_reel`, `audio_id`, `titre`, `artiste`, `apercu_url`, `volume_musique` 100, `volume_video` entre 0 et 20 ;
  - carrousel : cherche aussi une piste, en `mode: a_ajouter_dans_l_app` (elle l'ajoutera dans l'application après publication) ; un carrousel peut aussi rester sans musique (`aucune`) ;
  - si la recherche échoue (route Instagram, API indisponible), garde la direction sonore et mets une alerte courte.
- **Légende** : relis le point 6 du prompt. Langue et voix : `config/compte.yaml`. Uniquement des faits venant des notes de la série et de ce qui se voit. Si `exemples_de_legendes` existe, prends leur ton. Crédits « Rôle @compte » après une ligne vide, puis hashtags précis.
- **Identifications et collaborateurs** : seulement les comptes des prestataires de la série, placés sur l'élément concerné (x, y entre 0 et 1). Collaborateurs seulement quand la publication les met vraiment en valeur.
- Remplis `pourquoi` : ce que tu as retenu des statistiques et de ses goûts.
- Écris `jours/<jour>/post.json` (format au point 11), avec `"jour": "<jour>"` et le créneau du jour comme heure.

## 3. Contrôler

- `./studio rendre <jour>` (carrousel ou image). Regarde `rendu/01.jpg` et `rendu/grille.jpg` (la vignette 3:4 du profil) : le sujet doit rester lisible, rien d'important ne touche les bords. Regarde aussi chaque rendu en `plein_cadre` : rien d'essentiel coupé.
- `./studio valider <jour>`. Corrige toutes les erreurs ; pèse chaque avertissement. Recommence, trois tours au maximum. Si une erreur reste impossible à corriger, explique-la dans `alertes` et mets `controle.conforme` à false.
- `./studio apercu <jour>`.

## 4. Montrer et demander

- SendUserFile (`display: "render"`) sur `jours/<jour>/apercu.html`. Artifact privé en plus si `interface.artifact` vaut true.
- PushNotification : « Ton post de HH:MM est prêt, un coup d'œil et c'est parti ».
- S'il y a des alertes, résume-les en une phrase.
- AskUserQuestion « Que fait-on de ce post ? » avec ces options : « Publier à HH:MM (Recommandé) », « Publier maintenant », « Changer quelque chose », « Reporter ». Sa réponse libre décrit une retouche.

## 5. Selon sa réponse

- **Publier au créneau** : `./studio approuver <jour> --quand creneau`. La tâche « Publication » s'en charge à l'heure dite. Confirme en une ligne.
- **Publier maintenant** : `./studio approuver <jour> --quand maintenant`, puis `./studio publier <jour>`. Donne le lien. Si une musique est à ajouter : « Ouvre le post, ••• puis Modifier, puis Ajouter de la musique, et cherche « titre » ».
- **Changer quelque chose** : si elle n'a pas précisé, demande quoi en une question. Puis `./studio retouche <jour> "<sa demande>"`, applique exactement la demande sans tout refaire, retourne à l'étape 3 et redemande. Note dans `memoire/gouts.md` ce que la retouche t'apprend (une ligne datée).
- **Reporter** : `./studio statut <jour> reporte`. Le brouillon pourra revenir comme idée un autre jour.
- Ne lance jamais `approuver` ni `publier` sans sa réponse explicite dans cette conversation.
