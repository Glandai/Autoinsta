# Catalogue « atelier-photo » : plugin Studio Instagram

Ce dossier est un catalogue de plugins Claude (une « marketplace ») qui contient un seul plugin : **studio-instagram**, le studio de publication Instagram pour photographe de mariage. Le plugin ne contient ni photo, ni jeton, ni donnée personnelle : seulement les skills, le moteur, la charte, la documentation et des modèles de réglages pré-remplis à partir du profil public.

```
plugin-studio-instagram/
├── .claude-plugin/marketplace.json      le catalogue
└── plugins/studio-instagram/            le plugin
    ├── .claude-plugin/plugin.json
    ├── skills/                          6 skills
    ├── moteur/  studio  installer.sh    le moteur et son installateur
    ├── prompt/  docs/  modeles/         la charte, les guides, les modèles de réglages
    └── README.md  METHODE.md
```

## Installer sur un autre Mac, avec un autre compte Claude

Il faut l'application Claude pour Mac, connectée au compte Claude de la photographe, avec un abonnement qui inclut Claude Code (onglet Code).

### Option 1 : la plus simple, sans GitHub

1. Envoie-lui ce dossier (le zip passe par AirDrop) et décompresse-le.
2. Dans le Finder : menu Aller, Aller au dossier…, tape `~/.claude/skills` (crée le dossier `skills` s'il n'existe pas).
3. Glisse-y le dossier `plugins/studio-instagram` en entier.
4. Quitte puis relance l'application Claude. Dans l'onglet Code, tape `/` : les commandes `/studio-instagram:…` apparaissent.
5. Lance `/studio-instagram:studio-installation`.

Pour une nouvelle version, remplace le dossier `~/.claude/skills/studio-instagram` par le nouveau et relance l'application.

### Option 2 : avec mises à jour, via GitHub

1. Le catalogue est sur GitHub, dans le dépôt public `Glandai/Autoinsta` : aucun compte GitHub n'est nécessaire pour l'installer.
2. Sur le Mac de la photographe, dans une session de l'onglet Code, ajoute le catalogue puis installe le plugin :
   ```text
   /plugin marketplace add Glandai/Autoinsta
   ```
   Ensuite : bouton **+** à côté de la zone de saisie, **Add plugins** (ou **Plugins**, puis **Browse plugins**), choisis **studio-instagram**, portée « pour moi ».
   Depuis un terminal, c'est l'équivalent de :
   ```bash
   claude plugin install studio-instagram --marketplace Glandai/Autoinsta
   ```
3. Lance `/studio-instagram:studio-installation`.

Pour publier une nouvelle version : augmente `version` dans `plugins/studio-instagram/.claude-plugin/plugin.json` (et dans `moteur/VERSION`), puis envoie les fichiers sur GitHub. Chez elle, la mise à jour se fait depuis l'onglet **Installed** du gestionnaire de plugins (**Update now**), ou automatiquement si la mise à jour automatique est activée pour ce catalogue.

### Option 3 : catalogue local (pour tester)

```bash
claude plugin marketplace add /chemin/vers/plugin-studio-instagram
claude plugin install studio-instagram@atelier-photo
```

## Après l'installation

`/studio-instagram:studio-installation` crée le dossier de travail `~/Studio-Instagram` (réglages, photos analysées, posts, mémoire), installe le moteur, guide la connexion Instagram, ajoute les galeries et crée les tâches planifiées. Le détail est dans `plugins/studio-instagram/README.md`.
