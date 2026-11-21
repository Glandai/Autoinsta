# La méthode du Studio Instagram

Ce document explique comment le studio fonctionne et pourquoi il est construit ainsi (version 2.0). Il est livré sous forme de plugin Claude (`studio-instagram`) : le plugin apporte les skills, le moteur, la charte et les sources de l'app Mac ; un dossier de travail (`~/Studio-Instagram`) garde les réglages, les données et l'app personnalisée de la photographe. Pour installer, voir le `README.md` du plugin ; l'architecture de l'app est décrite dans `app/ARCHITECTURE.md`.

## 1. Le principe

Claude fait le travail de jugement : regarder les photos, imaginer les idées, construire la séquence, écrire la légende, apprendre des goûts et des résultats. Des scripts font tout ce qui doit être exact et identique à chaque fois : lire Pic-Time, mesurer les images, recadrer en 4:5, contrôler les règles du prompt, publier par l'API, relever les statistiques. La photographe garde une seule décision par étape, prise d'un clic dans l'app Studio Instagram.

```
08:00  le Mac (launchd)     lance Claude sans fenêtre : statistiques → apprentissages
                            → galeries → 3 idées ─────────────────────────────────┐
                                                                                  │ l'app s'ouvre
       la photographe       choisit une idée, ou écrit la sienne  ◄───────────────┘
       l'app                relance Claude : photos → séquence → mise en page
                            → légende → musique → contrôle → aperçu ─────────────┐ l'app s'ouvre
       la photographe       « Publier à 18:30 » · « Publier maintenant »  ◄──────┘
                            · « Reporter » · une retouche écrite (Claude la fait)
18:30  le Mac               publie le post validé (sans Claude) → notification
dim.   le Mac               lance le bilan : apprentissages, expériences proposées
```

Trois acteurs, une seule source de vérité :
- **l'app** (SwiftUI) affiche et recueille les décisions ; elle n'écrit jamais elle-même dans le dossier du studio, elle appelle `./studio …` et lit du JSON ;
- **le moteur** (`./studio`, Python) applique les décisions avec les mêmes contrôles, que la demande vienne de l'app ou de Claude ;
- **Claude Code** travaille sans fenêtre, lancé par l'app ou par le Mac ; l'app montre son avancement en direct (« Je regarde les photos », « J'écris la légende ») et son résumé final.

## 2. Analyse du prompt d'origine

Le prompt est solide : une identité précise, des règles vérifiables, des formats JSON, une section de sécurité. Pour en faire une automatisation quotidienne, quinze points ont été traités :

| Point du prompt | Problème pour l'automatisation | Solution retenue |
|---|---|---|
| Rythme : 2 posts par semaine | la demande est d'un post par jour | créneaux configurables (7 par défaut), règles converties en fenêtres glissantes |
| Règles « par mois » (5 piliers, 3 sur 8 pour le couple, N&B / couleur) | impossibles à évaluer jour après jour | 5 piliers sur 10 posts, 3 posts couple sur 8, équilibre sur 10 |
| « Réponds uniquement par un JSON publié tel quel » | aucune étape de validation humaine | fichiers JSON contrôlés par script, aperçu, validation en un geste |
| Pas de mode « idées » | la photographe veut choisir le matin | nouveau mode « idees » (3 pitchs dont une exploration) et mode « affinage » |
| Musique : « direction sonore, jamais de morceau protégé » | la demande inclut une musique ajoutée | Reels : bibliothèque Instagram via l'API Audio officielle ; carrousels : suggestion à ajouter dans l'app (l'API ne le permet pas) |
| « fichier : nom exact du fichier reçu » | les photos viennent de Pic-Time | identifiants Pic-Time, catalogue local par série |
| « Si tu ne vois pas une image » | rien ne montrait les images | planches contact numérotées puis photos en 1 600 px, regardées par Claude |
| Couverture lisible en 3:4 dans la grille | invérifiable à l'aveugle | vignette 3:4 générée et grille simulée dans l'aperçu |
| 10 médias par carrousel | l'API en accepte désormais 20 | la règle éditoriale reste 10 |
| Identifications | l'API demande une position | coordonnées x, y par identification |
| Localisation | l'API veut un identifiant de lieu Facebook | `location_id` facultatif par série |
| Interdits de légende | la relecture humaine rate des détails | contrôle automatique (clichés, ton commercial, mots du prompt, tirets, emojis, questions, hashtags génériques, comptes inventés, prénoms non publiables) |
| Section 0 à compléter | aucun paramètre rempli | pré-rempli depuis le profil public ; l'approche doit être écrite par la photographe |
| Pas d'apprentissage | la demande : « l'IA évolue » | section 13 : identité, puis goûts, puis performances |
| Images modifiables ? | risque d'outils génératifs | interdiction explicite : recadrer ou poser sur un fond, rien d'autre |

Le prompt adapté est `prompt/directeur-artistique.md` ; ses notes de version listent les changements.

## 3. Pic-Time : aller chercher les meilleures photos

Pic-Time n'a pas d'API publique (seulement Zapier, sans accès aux photos). L'analyse des pages Pic-Time a montré qu'une galerie ouverte par son lien de partage (`sectoken2`) charge un manifeste public : liste des photos par scène, orientation, photos mises en avant par la photographe, puis des métadonnées avec l'heure de prise de vue, la palette et le nom de fichier d'origine. Les images existent en 3 tailles, jusqu'à 1 600 px. Le portfolio est protégé par un code : le studio ne s'en sert pas.

Sélection des meilleures photos, en entonnoir :
1. **Indexation** (script) : manifeste, vignettes 640 px, mesures locales (tonalité, luminosité, contraste, netteté, orientation) et empreinte visuelle pour regrouper les rafales.
2. **Analyse visuelle** (Claude) : planches contact de 20 photos, une seule par rafale. Pour chaque photo : note de 1 à 5, pilier, plan, sujet, moment, description factuelle, centrée sur le couple ou non. Les photos mises en avant par la photographe dans Pic-Time reçoivent une attention particulière.
3. **Candidates** (script) : notes de 4 et plus, jamais publiées. On exclut aussi les photos qui ressemblent à une image déjà publiée, en comparant les empreintes avec l'historique importé du compte.
4. **Construction** (Claude) : 15 à 25 photos regardées en 1 600 px, puis séquence de 6 à 10 selon les rôles du prompt (ouverture, progression, respiration, surprise, clôture).

Si Pic-Time change son format interne, le script échoue proprement et la source « dossier » (exports locaux ou Google Drive synchronisé) prend le relais.

## 4. Création du post

- **Mise en page** : 1080 × 1350. Deux présentations : plein cadre, recadré avec un point d'ancrage, ou pose sur fond uni (clair, sombre, papier), adaptée aux scans argentiques et aux images horizontales. Les fichiers sont convertis en sRGB, sans données EXIF ni GPS. L'agrandissement est contrôlé : au-delà de ×1,2, le studio conseille le fond ou l'export HD.
- **Reels** : montage local avec ffmpeg, à partir de clips ou de photos. Approche lente, fondus discrets, 1080 × 1920, couverture choisie.
- **Légende** : écrite par Claude selon le point 6 du prompt, à partir des seules données. Contrôlée automatiquement, puis relue par la photographe dans l'aperçu.
- **Musique** : l'API Audio officielle cherche une piste dans la bibliothèque Instagram et l'attache au Reel au moment de publier. Pour un carrousel, l'API ne le permet pas : le studio propose un titre, ajouté dans l'app après publication (possible depuis juillet 2026).
- **Contrôle final** : le script `valider` vérifie le point 12 du prompt et les limites de l'API. Une erreur bloque la validation ; un avertissement s'affiche dans l'aperçu.

## 5. L'interface : l'app Mac Studio Instagram

L'app est construite sur le Mac à l'installation, avec les seuls outils de développement d'Apple. La photographe ne change jamais de fenêtre : l'app lance Claude, montre ce qu'il fait, et s'ouvre toute seule quand une décision l'attend.
- **Aujourd'hui** : où en est le post du jour, ce que Claude est en train de faire, ce qui l'attend.
- **Idées** : trois cartes (couverture envisagée, vignettes, format, pilier, raison) ; un clic pour choisir, ou un champ pour proposer son idée.
- **Aperçu** : le post tel qu'il apparaîtra (carrousel qu'on fait défiler, légende, musique, collaborateurs, lieu), la grille du profil avec la nouvelle couverture, les points à vérifier ; « Publier à HH:MM », « Publier maintenant », « Reporter » et un champ de retouche.
- **Galeries, Statistiques, Réglages, Charte, Règles** : tout se règle dans l'app, sans fichier à ouvrir.
- **Demander à Claude** : un panneau pour lui écrire librement (« ajoute le mariage de samedi », « change la couleur de l'app ») ; la conversation continue jusqu'à « Nouvelle conversation ».
- **Notifications du Mac** : idées prêtes, bilan prêt, post publié, publication à reprendre.

**Connexion de Claude.** L'app cherche Claude Code sur le Mac (y compris la copie livrée avec l'application Claude). S'il manque, elle propose de l'installer ; s'il n'est pas connecté, elle ouvre la page de connexion d'Anthropic dans le navigateur. Aucun mot de passe ne passe par l'app.

**Apparence et personnalisation.** Couleurs, mode clair ou sombre, titres, densité, animations et écrans visibles sont dans `config/app.yaml` : l'app se met à jour dès que le fichier change. Pour aller plus loin (mise en page, fonctionnement), Claude modifie les sources de l'app de ce studio (`app/Sources`), la reconstruit, la rouvre et note le changement dans `app/PERSONNALISATIONS.md`. Si la compilation échoue, il revient en arrière : l'app installée n'est remplacée qu'après une construction réussie. À chaque mise à jour du plugin, un fichier jamais modifié suit la nouvelle version ; un fichier personnalisé est gardé, et signalé s'il a aussi changé dans le plugin, pour que Claude aide à fusionner.

**Sans app** (outils de développement absents), les idées et l'aperçu restent disponibles en pages HTML dans l'application Claude, avec des cartes de question.

## 6. Apprendre

Trois sources, par ordre de priorité : **identité** (le prompt, non négociable), **goûts** (idées choisies ou refusées, idées proposées par la photographe, retouches demandées, écart entre légende proposée et légende publiée), **performances** (statistiques Instagram).

- Chaque matin, le studio relève les statistiques des posts âgés de 1 à 60 jours, une fois par jour au plus. Il calcule un score par post : rangs pondérés des enregistrements (30 %), des partages (25 %), de la portée rapportée aux abonnés (25 %), de l'engagement (10 %) et des abonnements gagnés (10 %). Il compare ensuite par pilier, format, tonalité, longueur de légende, jour, heure et taille de carrousel. Chaque constat porte un niveau de confiance selon le nombre de posts.
- Ces résultats nourrissent le choix des idées. Une idée sur trois reste une exploration, pour ne pas tourner en rond sur ce qui a marché.
- Le dimanche, le bilan réécrit `memoire/apprentissages.md` : ce qui fonctionne, ce qui est à améliorer, les préférences, les expériences de la semaine suivante. Les réglages (heures, part de Reels) ne changent qu'avec l'accord de la photographe.

## 7. Outils : ce qui est utilisé, et pourquoi pas le reste

**Utilisés**
- Claude Code, lancé sans fenêtre par l'app ou par le Mac (`claude -p`), avec la copie du plugin du studio : 7 skills (`studio-installation`, `studio-matin`, `studio-creation`, `studio-publication`, `studio-bilan`, `studio-galerie`, `studio-app`) et le `CLAUDE.md` du dossier de travail. Dans ce mode, Claude n'a droit qu'aux commandes du studio et aux fichiers du studio (jamais `.env`).
- L'app Mac Studio Instagram (SwiftUI, compilée sur place avec `swiftc`, sans Xcode).
- La planification de macOS (launchd) : trois tâches (matin, publication, bilan) qui tournent même quand l'app et l'application Claude sont fermées.
- L'application Claude (onglet Code) pour l'installation, les mises à jour et les longues conversations ; cartes de question, affichage de pages, Contrôle à distance (téléphone), Artifacts privés (facultatif).
- Vision de Claude : planches contact, photos, rendus.
- API Graph officielle de Meta : publication, statistiques, API Audio.
- Python (Pillow, requests, PyYAML, imageio-ffmpeg), Cloudflare Quick Tunnel ou Supabase pour l'adresse temporaire.
- Pendant la conception : navigateur intégré, pour analyser les pages Pic-Time et le profil Instagram.

**Écartés**
- Canva, Adobe Express, Figma : les modèles de mise en page rendent les posts génériques. Ici, la photo reste la photo, et la mise en page (4:5 ou fond uni) se fait localement, de façon fidèle et transportable. L'extension générative d'Adobe est exclue : elle inventerait des pixels dans une photo documentaire.
- Descript, invideo, HeyGen : invideo et HeyGen génèrent ou composent des vidéos, ce qui ne convient pas. Descript pourrait plus tard servir à monter de vrais rushes. Le montage local avec ffmpeg suffit et ne demande aucun compte.
- Modèles d'esthétique (Hugging Face) : ils notent une beauté générique, pas l'identité du compte. Claude, guidé par la charte, juge mieux.
- Zapier pour Pic-Time : il ne donne accès ni aux photos ni aux galeries existantes.
- Skills génériques de contenu et de marketing : les calendriers de contenu standard sont remplacés par la charte sur mesure.
- Routines dans le cloud : elles demandent GitHub et des secrets dans le cloud, n'ont pas de fichiers locaux et ne permettent pas le choix interactif.
- Tâches planifiées de l'application Claude (version 1) : elles demandaient que l'application reste ouverte et passaient par une conversation. La planification du Mac les remplace ; les anciennes tâches sont mises en pause à l'installation de la 2.0, pour éviter les doublons.
- Gmail, Google Drive, Google Agenda : facultatifs. Un dossier Drive synchronisé peut servir de source ; un résumé par e-mail pourrait remplacer les notifications.

## 8. Sécurité et limites

- Rien n'est publié sans validation explicite : son clic dans l'app, ou sa réponse dans une conversation avec Claude. Lancé par l'app ou par le Mac, Claude ne peut ni approuver ni publier ; la tâche de publication du Mac ne publie que les posts au statut « approuve », sans Claude.
- Les secrets restent dans `.env` : Claude a l'interdiction de lire ce fichier (règle dans `.claude/settings.json`), et la photographe y colle ses jetons elle-même. La connexion de Claude se fait dans le navigateur, sur la page d'Anthropic.
- Lancé sans fenêtre, Claude n'a droit qu'aux commandes du studio, à la reconstruction de l'app et aux fichiers du studio ; la copie du plugin (`.plugin/`) lui est interdite en écriture.
- Une personnalisation de l'app ne peut pas contourner ces règles, et une app qui ne compile plus est remise comme avant.
- Les photos restent en local. Seules les images du post validé sont exposées, quelques minutes, à une adresse aléatoire.
- Limites connues : pas de musique par l'API sur les carrousels ; jeton de 60 jours à renouveler en route Facebook, sauf avec un utilisateur système ; format Pic-Time interne susceptible de changer ; le Mac doit être allumé, session ouverte, aux heures des tâches ; le Claude de l'app partage les limites d'utilisation de l'abonnement.
