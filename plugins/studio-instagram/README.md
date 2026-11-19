# Studio Instagram (plugin Claude)

Un directeur artistique Instagram qui tourne dans l'application Claude, sur le Mac de la photographe. Chaque matin, il propose des idées de post tirées de ses galeries Pic-Time. Il construit ensuite le post choisi (photos, mise en page 4:5, légende, crédits, musique) et le publie à l'heure prévue, après sa validation.

Conçu pour @gabriellafeyer.photo, à partir du prompt « Directeur artistique Instagram » (`prompt/directeur-artistique.md`).

## Installer

Depuis un catalogue hébergé sur GitHub, dans une session de l'onglet Code :

```text
/plugin install studio-instagram --marketplace Glandai/Autoinsta
```

Les autres façons d'installer (dossier `~/.claude/skills`, catalogue local) sont dans le README du catalogue.

## Démarrer

Une fois le plugin installé, ouvre l'application Claude, onglet Code, et écris :

```text
/studio-instagram:studio-installation
```

L'installation guidée dure une trentaine de minutes. Elle crée le dossier de travail `~/Studio-Instagram`, remplit les paramètres du compte avec la photographe, connecte Instagram, ajoute les premières galeries, importe l'historique et crée les trois tâches planifiées.

## Une journée type

1. **8 h 00** : notification « 3 idées pour le post de 18:30 t'attendent ». Une page montre trois propositions avec la couverture envisagée. Elle choisit, ou écrit sa propre idée.
2. **Une dizaine de minutes plus tard** : l'aperçu du post, tel qu'il apparaîtra sur Instagram, avec sa place dans la grille. Quatre réponses possibles : publier à l'heure prévue, publier maintenant, changer quelque chose, reporter.
3. **À l'heure du créneau** : le post part, et elle reçoit le lien.
4. **Dimanche soir** : un bilan court, avec ce qui a marché, ce qui est à améliorer et l'expérience proposée pour la semaine suivante.

## Les skills

| Skill | Quand |
|---|---|
| `/studio-instagram:studio-installation` | première installation, mise à jour, tâches planifiées |
| `/studio-instagram:studio-matin` | chaque matin (tâche planifiée) ou « les idées du jour » |
| `/studio-instagram:studio-creation` | construire le post choisi, gérer validation et retouches |
| `/studio-instagram:studio-publication` | publier les posts validés à l'heure (tâche planifiée) |
| `/studio-instagram:studio-bilan` | bilan du dimanche (tâche planifiée) ou « le bilan » |
| `/studio-instagram:studio-galerie` | ajouter une nouvelle galerie Pic-Time |

## Le plugin et le dossier de travail

- **Le plugin** apporte le savoir-faire : les skills, la charte, le moteur (`moteur/`), la documentation et les modèles de réglages. Il se met à jour sans rien perdre.
- **Le dossier de travail** (`~/Studio-Instagram` par défaut) garde ce qui appartient à la photographe : `config/` (paramètres, galeries), `.env` (ses jetons, jamais lus par Claude), `catalogue/` (photos analysées), `jours/` (idées, posts, aperçus), `donnees/` (historique, statistiques) et `memoire/` (goûts, apprentissages).
- À chaque routine, le moteur du dossier est remis à la version du plugin si besoin. Les réglages et les données ne sont jamais écrasés.

## Ce qu'il faut

- Un Mac qui reste allumé aux heures des tâches, avec l'application Claude ouverte.
- Un abonnement Claude qui inclut Claude Code (onglet Code).
- Un compte Instagram professionnel ; pour la musique automatique sur les Reels, relié à une Page Facebook (`docs/connexion-instagram.md`).
- Les liens de partage des galeries Pic-Time (`docs/pic-time.md`).

## Limites connues

- L'API d'Instagram n'ajoute pas de musique aux carrousels : le studio propose un titre, qu'elle ajoute dans l'application après publication.
- Route Facebook : le jeton est à renouveler tous les 60 jours (5 minutes), ou jamais avec un utilisateur système.
- Pic-Time n'a pas d'API publique : le studio lit les galeries par leur lien de partage, et peut aussi lire un dossier d'exports.

Le fonctionnement détaillé est dans `METHODE.md`.
