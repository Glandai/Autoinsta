---
name: studio-installation
description: Installe, met à jour et configure le Studio Instagram sur un ordinateur (dossier de travail, dépendances, paramètres du compte, connexion Instagram, galeries Pic-Time, historique, tâches planifiées, essai complet). À lancer une fois avec la photographe, ou pour mettre à jour le studio et recréer ses tâches planifiées.
---

# Installation guidée (environ 30 minutes)

Avance étape par étape, une chose à la fois, en expliquant simplement ce qui se passe. Tiens un court récapitulatif des étapes terminées. Le plugin apporte le savoir-faire ; le dossier de travail garde les réglages et les données de la photographe.

## 1. Le dossier de travail

- Propose `~/Studio-Instagram` (elle peut en choisir un autre, de préférence sans espace dans le chemin). C'est là que vivront ses réglages, ses photos analysées, ses posts et la mémoire du studio. Note son chemin absolu : `<CHEMIN>`.
- `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" "<CHEMIN>"` (une à deux minutes : moteur, Python, ffmpeg, cloudflared). Si le dossier existe déjà, ses réglages et ses données sont conservés.
- `cd "<CHEMIN>"`, puis `./studio verifier`. Les points d'exclamation sont normaux à ce stade ; un ✗ sur l'installation elle-même se règle maintenant (`docs/depannage.md`).
- Conseille-lui d'ouvrir ce dossier dans l'application Claude (onglet Code, choisir le dossier) pour travailler au quotidien : les instructions du studio (`CLAUDE.md`) et ses autorisations s'y appliquent.

## 2. Les paramètres du compte (`config/compte.yaml`)

Le fichier est pré-rempli à partir du profil public : relis-le avec elle.
- AskUserQuestion, en une fois : la voix des légendes (« je » ou « nous »), la langue (français, anglais, bilingue français puis anglais), le rythme (chaque jour, 5 fois par semaine, 3 fois, 2 fois).
- Demande-lui l'heure de publication qu'elle préfère (par défaut 18:30 en semaine) ; ajuste `publication.creneaux` (supprime les jours sans post).
- Demande-lui de décrire son approche en trois à cinq phrases, avec ses mots : manière de travailler, argentique ou numérique, rapport aux mariés, ce qui distingue son travail. Recopie ses mots tels quels dans `approche` : c'est la seule source autorisée pour parler de sa pratique.
- Propose-lui de coller deux ou trois de ses vraies légendes préférées (`exemples_de_legendes`) : c'est ce qui aide le plus à trouver le ton.
- Montre le résumé et corrige si besoin.

## 3. Connecter Instagram

Explique les deux routes de `docs/connexion-instagram.md` et recommande la route A (Facebook), seule à permettre l'ajout automatique de musique Instagram sur les Reels. Elle fait elle-même chaque étape dans son navigateur : tu guides, tu ne te connectes pas à sa place, tu ne demandes jamais un mot de passe, un code ni un jeton dans la conversation.
- Quand elle a ses identifiants, elle les colle elle-même dans `.env` : propose d'ouvrir le fichier avec `open -e .env` (TextEdit).
- Route A : `./studio jeton echanger` (jeton long + identifiant du compte), puis `./studio jeton verifier`.
- Route B : mets `instagram.api: instagram` dans la config, puis `./studio jeton echanger` (identifiant du compte) et `./studio jeton verifier`.
- Vérifie ensuite `./studio verifier`.

## 4. Les galeries Pic-Time

Lance le skill `studio-instagram:studio-galerie` pour une à trois galeries récentes (les plus fortes pour commencer). Indexe et analyse au moins une série en entier.

## 5. L'historique du compte

- `./studio historique importer --limite 30`, puis `./studio historique planche`.
- Regarde la planche (Read) et, pour chaque numéro, écris le pilier, la fiche feed de la couverture (`tonalite`, `luminosite`, `plan`, `sujet`) et `centree_couple` dans `donnees/classement-historique.json` (format `{"1": {"pilier": "PLACES", "fiche_feed": {...}, "centree_couple": false}}`), puis `./studio historique noter donnees/classement-historique.json`.
- `./studio releve` puis `./studio analyse` : c'est le point de départ des apprentissages.

## 6. Les tâches planifiées

Avant de les créer, demande-lui de passer cette session en mode Auto (sélecteur de mode sous la zone de saisie) : les tâches enregistrées dans ce mode tournent sans rester bloquées sur des demandes d'autorisation. Les règles de `.claude/settings.json` du dossier autorisent déjà les commandes du studio et interdisent la lecture de `.env`.

Crée-les avec l'outil de tâches planifiées (`create_scheduled_task`), en remplaçant `<CHEMIN>` par le chemin absolu du dossier de travail :

- `studio-instagram-matin`, titre « Studio Instagram · idées du matin », cron `0 8 * * *` (heure `routine.heure_idees`), prompt :
  > Tu es le Studio Instagram de la photographe. Le dossier du studio est « <CHEMIN> » : commence par `cd "<CHEMIN>"` et travailles-y. Lance le skill `studio-instagram:studio-matin` et suis-le exactement. Parle en français, simplement. Rien n'est publié sans sa validation explicite dans cette conversation.
- `studio-instagram-publication`, titre « Studio Instagram · publication », une tâche par heure de créneau distincte (cron avec les jours concernés, par exemple `30 18 * * 1-4` et `30 12 * * 5`), prompt :
  > Tu es le Studio Instagram. Le dossier est « <CHEMIN> » : `cd "<CHEMIN>"`. Lance le skill `studio-instagram:studio-publication` et suis-le exactement. Ne publie que les posts qu'elle a validés.
- `studio-instagram-bilan`, titre « Studio Instagram · bilan de la semaine », cron `0 19 * * 0`, prompt :
  > Tu es le Studio Instagram. Le dossier est « <CHEMIN> » : `cd "<CHEMIN>"`. Lance le skill `studio-instagram:studio-bilan` et suis-le exactement.

Dis-lui clairement : les tâches tournent quand l'application Claude est ouverte ; si elle est fermée à l'heure prévue, la tâche part au prochain lancement. Le Mac doit être allumé (réglages Batterie / Économie d'énergie si besoin).

## 7. Sur son téléphone

Pour recevoir les notifications et répondre depuis son téléphone, propose d'activer le Contrôle à distance (Remote Control) dans les réglages de l'application Claude, puis d'ouvrir l'application Claude sur son téléphone. Si elle préfère voir les pages sur téléphone, mets `interface.artifact: true` : les pages seront aussi publiées en Artifact privé.

## 8. Essai

- `./studio demo` : montre les deux pages de démonstration (`jours/demo/idees.html` et `jours/demo/apercu.html`) avec SendUserFile pour qu'elle découvre l'interface. Rien n'est publié.
- Propose de lancer la routine du matin tout de suite (skill `studio-instagram:studio-matin`) pour un premier vrai post.

## 9. Récapitulatif

Termine par la liste de ce qui est en place et de ce qui reste à faire (par exemple : approche à compléter, galerie à ajouter, jeton à renouveler le JJ/MM).

## Mettre à jour le studio

Après une mise à jour du plugin, chaque routine rafraîchit le moteur toute seule. Pour le faire à la main : `bash "${CLAUDE_PLUGIN_ROOT}/installer.sh" "<CHEMIN>"`. Les réglages, la mémoire et les données ne sont jamais touchés, et les tâches planifiées n'ont pas besoin d'être recréées.
