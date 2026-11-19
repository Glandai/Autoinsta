---
name: studio-publication
description: Publie sur Instagram les posts validés dont l'heure est venue, puis prévient la photographe avec le lien. Utilisé par la tâche planifiée de publication ; aussi quand elle demande « publie le post validé ».
---

# Publication au créneau

## 0. Se placer dans le studio

Le dossier du studio est le dossier courant s'il contient `config/compte.yaml` ; sinon le chemin donné par la tâche planifiée ; sinon `~/Studio-Instagram`. Place-toi dedans (`cd`). S'il n'existe pas encore, lance le skill `studio-instagram:studio-installation`.
Mets ensuite le moteur à jour si le plugin a changé (instantané s'il est déjà à jour) : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" --si-besoin "$PWD"`.

1. `./studio publier-dus`. Seuls les posts qu'elle a validés (statut « approuve ») et dont l'heure est passée partent.
2. Pour chaque post publié : PushNotification « Publié : <titre> » avec le lien. Si la musique est à ajouter dans l'application (`musique.mode` = `a_ajouter_dans_l_app`), ajoute une phrase : « Pour la musique : ••• puis Modifier, puis Ajouter de la musique, et cherche « titre » ».
3. Pour chaque échec : une notification courte avec la cause et la marche à suivre (`docs/depannage.md`). Pas de nouvel essai automatique : elle décidera.
4. Si rien n'était dû : `./studio en-attente`. Si le post du jour est prêt mais pas validé et que le créneau est passé ou dans moins d'une heure, envoie une seule notification de rappel : « Le post du jour attend ton feu vert ».
5. Termine par un résumé de deux lignes. Ne publie jamais un post qu'elle n'a pas validé.
