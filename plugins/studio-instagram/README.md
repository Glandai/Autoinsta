# Studio Instagram (plugin Claude) · version 2.0

Un directeur artistique Instagram qui vit sur le Mac de la photographe. Chaque matin, il propose des idées de post tirées de ses galeries Pic-Time. Il construit ensuite le post choisi (photos, mise en page 4:5, légende, crédits, musique) et le publie à l'heure prévue, après sa validation d'un clic.

Depuis la version 2.0, tout se passe dans une app Mac, **Studio Instagram** : elle lance Claude elle-même, en arrière-plan, et c'est le Mac qui tient les horaires. Plus besoin de garder l'application Claude ouverte.

Fonctionne pour n'importe quel compte : à l'installation, l'app demande ton nom, ton compte Instagram et ton activité, et Claude adapte la charte (`prompt/directeur-artistique.md`, écrite au départ pour la photographie de mariage) à ce que tu fais.

## Ce qu'il faut

- Un Mac (macOS 14 ou plus récent) allumé, session ouverte, aux heures prévues.
- Un abonnement Claude qui inclut Claude Code.
- Les outils de développement d'Apple (gratuits) : l'installation les demande s'ils manquent (`xcode-select --install`).
- Un compte Instagram professionnel (`docs/connexion-instagram.md`).
- Les liens de partage des galeries Pic-Time (`docs/pic-time.md`).

## Installer

**1. Le plugin**, dans l'application Claude, onglet Code :

```text
/plugin install studio-instagram --marketplace Glandai/Autoinsta
```

Les autres façons (dossier `~/.claude/skills`, catalogue local) sont dans le README du catalogue.

**2. Le studio**, au choix :

- **Avec Claude (recommandé)**, dans l'onglet Code :
  ```text
  /studio-instagram:studio-installation
  ```
  Une trentaine de minutes, guidée pas à pas : dossier `~/Studio-Instagram`, app Mac, connexion de Claude Code, paramètres du compte, Instagram, premières galeries, historique, planification.
- **En une commande**, dans le Terminal (plugin installé depuis GitHub ; sinon, remplace le chemin par celui du dossier du plugin) :
  ```bash
  bash ~/.claude/plugins/marketplaces/atelier-photo/plugins/studio-instagram/installer.sh
  ```
  Cela prépare `~/Studio-Instagram` et construit l'app dans `~/Applications` (quelques minutes). Ouvre ensuite l'app **Studio Instagram** : elle guide la connexion de Claude Code. Pour le reste (compte, Instagram, galeries), lance ensuite `/studio-instagram:studio-installation` : rien de ce qui est déjà fait n'est perdu.

## Connecter Claude Code

L'app a besoin de Claude Code, la version de Claude qu'elle fait travailler sans fenêtre. Au premier lancement, elle le cherche toute seule. S'il manque, deux clics : **Installer Claude Code**, puis **Se connecter**. Le navigateur s'ouvre sur la page de connexion d'Anthropic : on s'y connecte avec son compte Claude habituel. Le mot de passe se tape dans le navigateur, jamais dans l'app ni dans une conversation. Le Claude de l'app utilise l'abonnement : ses limites d'utilisation sont les mêmes que celles de l'application Claude.

## Une journée type

1. **8 h 00** : le Mac lance la routine du matin. L'app s'ouvre sur trois idées, avec la couverture envisagée. Elle en choisit une d'un clic, ou écrit la sienne.
2. **Pendant qu'elle fait autre chose** : Claude construit le post. L'app montre ce qu'il fait (« Je regarde les photos », « J'écris la légende »), puis s'ouvre sur l'aperçu : le post tel qu'il apparaîtra, sa place dans la grille, les points à vérifier.
3. **Sa décision, d'un clic** : « Publier à 18:30 », « Publier maintenant », « Reporter », ou une retouche écrite avec ses mots (« la photo du bouquet en premier ») : Claude la fait et l'aperçu revient.
4. **À l'heure du créneau** : le Mac publie le post validé et une notification annonce qu'il est en ligne.
5. **Dimanche soir** : le bilan de la semaine, avec ce qui a marché, ce qui est à améliorer et l'expérience proposée.

Tout le reste se règle dans l'app : créneaux, charte, règles du contrôle, galeries, statistiques, apparence. Rien n'est publié sans son clic.

## Personnaliser l'app

On peut demander à Claude de changer l'app, avec ses mots : « mets un vert sauge à la place de l'olive », « passe en mode sombre », « cache l'écran des règles », « affiche les idées en grand », « ajoute le nombre d'enregistrements sur l'accueil ».
- **Dans l'app** : panneau **Demander à Claude**. Les changements d'apparence s'affichent aussitôt ; pour un changement plus profond, Claude reconstruit l'app (une à deux minutes) et la rouvre.
- **Dans l'application Claude** : ouvrir le dossier `~/Studio-Instagram` dans l'onglet Code et demander de la même façon (skill `studio-app`).

Chaque changement est noté dans `app/PERSONNALISATIONS.md`, et peut être annulé (« reviens à l'app d'origine »). Si une modification ne fonctionne pas, Claude revient en arrière : l'app ne reste jamais cassée. Les personnalisations survivent aux mises à jour.

## La planification

Trois tâches du Mac : les idées du matin, la publication aux créneaux, le bilan de la semaine. Elles tournent même quand l'app et l'application Claude sont fermées, à condition que le Mac soit allumé et la session ouverte (en veille, la tâche part au réveil). Elles s'activent pendant l'installation, avec l'accord de la photographe, ou dans l'app (Réglages). Changer une heure dans les Réglages met le Mac à jour tout seul.

Sans planification, rien ne part tout seul : on demande les idées depuis l'app et on publie avec « Publier maintenant ».

## Les skills

| Skill | Quand |
|---|---|
| `/studio-instagram:studio-installation` | première installation, mise à jour, connexion de Claude Code, planification |
| `/studio-instagram:studio-matin` | la routine du matin, ou « les idées du jour » |
| `/studio-instagram:studio-creation` | construire le post choisi, gérer validation et retouches |
| `/studio-instagram:studio-publication` | « publie le post validé » (au créneau, le Mac publie sans Claude) |
| `/studio-instagram:studio-bilan` | le bilan de la semaine, ou « le bilan » |
| `/studio-instagram:studio-galerie` | ajouter une nouvelle galerie Pic-Time |
| `/studio-instagram:studio-app` | personnaliser l'app, fusionner après une mise à jour |

L'app lance ces mêmes skills toute seule ; on ne les tape que pour travailler avec Claude dans l'application Claude.

## Le plugin et le dossier de travail

- **Le plugin** apporte le savoir-faire : les skills, la charte, le moteur (`moteur/`), les sources de l'app (`app/`), la documentation et les modèles de réglages.
- **Le dossier de travail** (`~/Studio-Instagram` par défaut) garde ce qui appartient à la photographe : `config/` (paramètres, galeries, charte, apparence de l'app), `.env` (ses jetons, jamais lus par Claude), `catalogue/` (photos analysées), `jours/` (idées, posts, aperçus), `donnees/` (historique, statistiques), `memoire/` (goûts, apprentissages) et `app/` (les sources de son app, avec ses personnalisations). Il contient aussi une copie du plugin (`.plugin/`), que l'app donne à Claude.
- **Mettre à jour** : après une nouvelle version du plugin, il suffit de lancer un skill dans l'application Claude (ou `/studio-instagram:studio-installation`) : le studio et l'app se remettent à niveau. Les réglages, les données et les personnalisations ne sont jamais écrasés ; si une personnalisation croise une nouveauté, Claude aide à fusionner (« fusionne les personnalisations de l'app »).

## Limites connues

- L'API d'Instagram n'ajoute pas de musique aux carrousels : le studio propose un titre, à ajouter dans Instagram après publication.
- Route Facebook : le jeton est à renouveler tous les 60 jours (5 minutes), ou jamais avec un utilisateur système.
- Pic-Time n'a pas d'API publique : le studio lit les galeries par leur lien de partage, et peut aussi lire un dossier d'exports.
- Le Mac doit être allumé, session ouverte, aux heures prévues. Si la limite d'utilisation de Claude est atteinte, la routine s'arrête avec un message : on la relance depuis l'app une fois la limite renouvelée (quelques heures).

En cas de souci : `docs/depannage.md`. Le fonctionnement détaillé est dans `METHODE.md`, l'architecture de l'app dans `app/ARCHITECTURE.md`.
