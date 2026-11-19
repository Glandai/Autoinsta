# La méthode du Studio Instagram

Ce document explique comment le studio fonctionne et pourquoi il est construit ainsi. Il est livré sous forme de plugin Claude (`studio-instagram`) : le plugin apporte les skills, le moteur et la charte ; un dossier de travail (`~/Studio-Instagram`) garde les réglages et les données de la photographe. Pour installer, voir le `README.md` du plugin.

## 1. Le principe

Claude fait le travail de jugement : regarder les photos, imaginer les idées, construire la séquence, écrire la légende, apprendre des goûts et des résultats. Des scripts font tout ce qui doit être exact et identique à chaque fois : lire Pic-Time, mesurer les images, recadrer en 4:5, contrôler les règles du prompt, publier par l'API, relever les statistiques. La photographe garde une seule décision par étape, prise en un geste.

```
08:00  tâche « matin »      statistiques → apprentissages → galeries → 3 idées ──┐
                                                                                  │ notification
       la photographe       choisit une idée, ou écrit la sienne  ◄───────────────┘
                                                                                  
       Claude               photos → séquence → mise en page → légende → musique
                            → contrôle automatique → aperçu ─────────────────────┐ notification
       la photographe       « Publier à 18:30 » · « Publier maintenant »  ◄──────┘
                            · « Changer quelque chose » · « Reporter »
18:30  tâche « publication » publie le post validé → lien envoyé
dim.   tâche « bilan »      réécrit les apprentissages, propose des expériences
```

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

## 5. L'interface

L'interface est l'application Claude elle-même, sur Mac et sur téléphone avec le Contrôle à distance :
- **Idées du matin** : une page avec trois cartes (couverture envisagée, vignettes, format, pilier, raison). Le choix se fait par une carte de question : trois boutons et un champ libre pour proposer son idée.
- **Aperçu** : une page qui imite le post Instagram (carrousel qu'on fait défiler, légende avec « plus », musique, collaborateurs, lieu). On y voit aussi la grille du profil avec la nouvelle couverture, les points à vérifier, l'intention, la séquence et les textes alternatifs. Quatre boutons : publier au créneau, publier maintenant, changer quelque chose, reporter.
- **Notifications** : idées prêtes, post prêt, post publié avec son lien, rappel si un post attend.
- Les pages sont des fichiers HTML autonomes, avec les images intégrées. On peut les publier en Artifact privé pour les ouvrir sur téléphone.

## 6. Apprendre

Trois sources, par ordre de priorité : **identité** (le prompt, non négociable), **goûts** (idées choisies ou refusées, idées proposées par la photographe, retouches demandées, écart entre légende proposée et légende publiée), **performances** (statistiques Instagram).

- Chaque matin, le studio relève les statistiques des posts âgés de 1 à 60 jours, une fois par jour au plus. Il calcule un score par post : rangs pondérés des enregistrements (30 %), des partages (25 %), de la portée rapportée aux abonnés (25 %), de l'engagement (10 %) et des abonnements gagnés (10 %). Il compare ensuite par pilier, format, tonalité, longueur de légende, jour, heure et taille de carrousel. Chaque constat porte un niveau de confiance selon le nombre de posts.
- Ces résultats nourrissent le choix des idées. Une idée sur trois reste une exploration, pour ne pas tourner en rond sur ce qui a marché.
- Le dimanche, le bilan réécrit `memoire/apprentissages.md` : ce qui fonctionne, ce qui est à améliorer, les préférences, les expériences de la semaine suivante. Les réglages (heures, part de Reels) ne changent qu'avec l'accord de la photographe.

## 7. Outils : ce qui est utilisé, et pourquoi pas le reste

**Utilisés**
- Application Claude (onglet Code) : plugin `studio-instagram` avec 6 skills (`studio-installation`, `studio-matin`, `studio-creation`, `studio-publication`, `studio-bilan`, `studio-galerie`), et un dossier de travail avec son `CLAUDE.md`.
- Tâches planifiées de l'application : matin, publication, bilan.
- Cartes de question, affichage de pages, notifications, Contrôle à distance (téléphone), Artifacts privés (facultatif).
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
- Routines dans le cloud : elles demandent GitHub et des secrets dans le cloud, n'ont pas de fichiers locaux et ne permettent pas le choix interactif. Les tâches planifiées locales sont plus simples.
- Gmail, Google Drive, Google Agenda : facultatifs. Un dossier Drive synchronisé peut servir de source ; un résumé par e-mail pourrait remplacer les notifications.

## 8. Sécurité et limites

- Rien n'est publié sans validation explicite dans la conversation. La tâche de publication ne publie que les posts au statut « approuve ».
- Les secrets restent dans `.env` : Claude a l'interdiction de lire ce fichier (règle dans `.claude/settings.json`), et la photographe y colle ses jetons elle-même.
- Les photos restent en local. Seules les images du post validé sont exposées, quelques minutes, à une adresse aléatoire.
- Limites connues : pas de musique par l'API sur les carrousels ; jeton de 60 jours à renouveler en route Facebook, sauf avec un utilisateur système ; format Pic-Time interne susceptible de changer ; l'application Claude doit être ouverte et le Mac allumé aux heures des tâches.
