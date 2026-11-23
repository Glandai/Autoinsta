# Connecter le studio à Instagram

Le studio publie avec l'API officielle de Meta. Il faut une fois pour toutes : un compte Instagram professionnel, une petite « app » Meta (gratuite, privée, utilisée seulement par toi) et un jeton d'accès. Compte 20 à 30 minutes.

Tu fais toi-même ces étapes dans ton navigateur. Claude peut te guider, mais ne se connecte jamais à ta place et ne doit jamais voir tes mots de passe ni tes jetons : tu les colles toi-même dans le fichier `.env` du dossier (ouvre-le avec TextEdit : `open -e .env`).

## Quelle route choisir ?

| | Route A : Facebook (recommandée) | Route B : Instagram seul |
|---|---|---|
| Il faut | une Page Facebook reliée au compte Instagram | rien de plus |
| Publier carrousels, images, Reels | oui | oui |
| Statistiques | oui | oui |
| Musique Instagram ajoutée automatiquement aux Reels | **oui** (API Audio) | non |
| Renouvellement du jeton | tous les 60 jours (5 minutes), ou jamais avec un utilisateur système | automatique |

Si ton compte a déjà une Page Facebook, la route A est la bonne.

## Route A : Facebook

### 1. Préparer le compte

1. Dans l'application Instagram : vérifie que le compte est **professionnel** (Créateur ou Entreprise). Sinon : Paramètres, Type de compte et outils, Passer à un compte professionnel.
2. Relie le compte Instagram à la Page Facebook : depuis la Page (Paramètres, Comptes liés, Instagram) ou depuis Meta Business Suite.

### 2. Créer l'app Meta

1. Va sur developers.facebook.com, connecte-toi avec ton compte Facebook, et active le compte développeur si c'est la première fois.
2. « Créer une app ». Choisis le cas d'utilisation lié à Instagram ou « Autre », puis le type **Entreprise**. Nom : « Studio Instagram ».
3. Dans le tableau de bord de l'app, ajoute le produit **Instagram** (API Instagram avec connexion Facebook) et, si on te le propose, **Facebook Login for Business**.
4. L'app reste en mode développement : c'est normal et suffisant, puisque tu es la seule à l'utiliser sur ton propre compte. Aucun examen de Meta n'est nécessaire.

### 3. Obtenir le jeton

1. Ouvre l'**Explorateur de l'API Graph** (developers.facebook.com/tools/explorer).
2. En haut à droite, choisis l'app « Studio Instagram » et « Jeton d'utilisateur ».
3. Ajoute ces autorisations : `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights`, `pages_show_list`, `pages_read_engagement`, `business_management`.
4. « Generate Access Token » : connecte-toi, et coche ta Page et ton compte Instagram quand Facebook le demande.
5. Copie le jeton affiché.
6. Dans l'app (Paramètres, Général), copie l'**identifiant de l'app** et la **clé secrète** (bouton « Afficher »).

### 4. Le donner au studio

1. Ouvre `.env` (`open -e .env`) et remplis :
   ```
   FB_APP_ID=identifiant de l'app
   FB_APP_SECRET=clé secrète
   FB_SHORT_TOKEN=jeton copié dans l'Explorateur
   ```
2. Enregistre, puis dis à Claude « c'est fait » (dans l'application Claude, ou dans le panneau « Demander à Claude » de l'app). Il lance `./studio jeton echanger` : le jeton court devient un jeton de 60 jours, l'identifiant du compte Instagram est trouvé, et tout est rangé dans `.env`. `./studio jeton verifier` confirme la connexion.

### Renouveler (tous les 60 jours)

Le studio te prévient dix jours avant l'expiration. Refais l'étape 3 (Explorateur, nouveau jeton), colle-le dans `FB_SHORT_TOKEN`, puis « c'est fait ». Cinq minutes.

Pour ne plus jamais renouveler : dans Meta Business Suite, Paramètres de l'entreprise, Utilisateurs système, crée un utilisateur système, donne-lui accès à l'app, à la Page et au compte Instagram, puis génère un jeton avec les mêmes autorisations et l'expiration « Jamais ». Colle-le dans `IG_ACCESS_TOKEN` (laisse `FB_SHORT_TOKEN` vide) et lance `./studio jeton echanger`.

## Route B : Instagram seul

1. Compte Instagram professionnel (voir plus haut). Pas besoin de Page Facebook.
2. developers.facebook.com, « Créer une app », cas d'utilisation **gérer les messages et le contenu sur Instagram**.
3. Dans « Configuration de l'API avec connexion Instagram », ajoute ton compte et **génère un jeton** (connexion Instagram). Copie-le.
4. Dans `.env` : `IG_ACCESS_TOKEN=le jeton`. Dans les Réglages de l'app (ou `config/compte.yaml`) : route `instagram` (`instagram.api: instagram`).
5. « C'est fait » : Claude lance `./studio jeton echanger` (identifiant du compte) puis `./studio jeton verifier`. Le studio renouvelle ensuite le jeton tout seul.

## L'adresse temporaire au moment de publier

Instagram ne reçoit pas les photos directement : il vient les chercher à une adresse publique. Au moment de publier, le studio ouvre une adresse temporaire (Cloudflare, sans compte), y dépose uniquement les images du post validé, attend qu'Instagram les ait prises, puis ferme tout. Rien d'autre n'est exposé.

Si cela échoue chez toi (réseau d'entreprise, pare-feu), utilise Supabase (gratuit) :
1. Crée un projet sur supabase.com, puis dans Storage un bucket **public** nommé `instagram-temp`.
2. Dans Paramètres, API : copie l'URL du projet et la clé `service_role` dans `.env` (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`).
3. Dans les Réglages de l'app (ou `config/compte.yaml`) : hébergement `supabase` (`publication.hebergement: supabase`).
Les fichiers sont supprimés juste après la publication.

## Ce que l'API ne fait pas

- Ajouter de la musique à un carrousel : impossible par l'API. Le studio te propose un titre ; tu l'ajoutes en 15 secondes après publication (sur le post : ••• puis Modifier, puis Ajouter de la musique). Selon le type de compte, la bibliothèque proposée peut être plus réduite (comptes Entreprise).
- Programmer un post chez Instagram : le studio publie lui-même à l'heure du créneau, grâce à la planification du Mac (activée dans les Réglages de l'app), à condition que le Mac soit allumé et la session ouverte.
- Identifier un lieu sans son identifiant Facebook : le champ `location_id` d'une série reste facultatif.
