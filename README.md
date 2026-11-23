# Catalogue « atelier-photo » : plugin Studio Instagram

## Le plus simple : l'installateur Mac (.pkg)

1. Télécharge **Studio-Instagram-2.3.0.pkg** dans la page [Releases](https://github.com/Glandai/Autoinsta/releases) du dépôt.
2. Double-clique dessus et suis l'installateur : l'app **Studio Instagram** arrive dans Applications.
3. Ouvre-la : elle crée ton studio, te demande ton nom, ton compte Instagram et ce que tu photographies, puis te guide pour connecter Claude et Instagram. Aucune commande, aucun outil à installer.

Il faut un Mac Apple Silicon (M1 ou plus récent) sous macOS 14 ou plus, et un abonnement Claude. L'installateur n'est pas signé par un compte développeur Apple : si macOS refuse de l'ouvrir, fais clic droit › Ouvrir, ou Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ». Pour le reconstruire : `bash paquet/fabriquer-pkg.sh`.

## Pour les habitués de Claude : le plugin

Ce dossier est aussi un catalogue de plugins Claude (une « marketplace ») qui contient un seul plugin : **studio-instagram**, le studio de publication Instagram pour photographe (mariage par défaut, toute activité possible). Depuis la version 2.0, il installe aussi une app Mac, **Studio Instagram**, qui fait travailler Claude en arrière-plan et laisse le Mac tenir les horaires. Le plugin ne contient ni photo, ni jeton, ni donnée personnelle : seulement les skills, le moteur, les sources de l'app, la charte, la documentation et des modèles de réglages vierges, remplis par l'onboarding de l'app.

```
plugin-studio-instagram/
├── .claude-plugin/marketplace.json      le catalogue
└── plugins/studio-instagram/            le plugin
    ├── .claude-plugin/plugin.json
    ├── skills/                          7 skills
    ├── app/                             sources de l'app Mac (SwiftUI) et son architecture
    ├── moteur/  studio  installer.sh    le moteur et son installateur
    ├── prompt/  docs/  modeles/         la charte, les guides, les modèles de réglages
    └── README.md  METHODE.md
```

## Ce qu'il faut

Un Mac (macOS 14 ou plus récent) avec l'application Claude, connectée au compte Claude de la photographe, et un abonnement qui inclut Claude Code (onglet Code). Les outils de développement d'Apple (gratuits) servent à construire l'app : l'installation les demande s'ils manquent.

## 1. Installer le plugin

### Option 1 : la plus simple, sans GitHub

1. Envoie-lui ce dossier (le zip passe par AirDrop) et décompresse-le.
2. Dans le Finder : menu Aller, Aller au dossier…, tape `~/.claude/skills` (crée le dossier `skills` s'il n'existe pas).
3. Glisse-y le dossier `plugins/studio-instagram` en entier.
4. Quitte puis relance l'application Claude. Dans l'onglet Code, tape `/` : les commandes `/studio-instagram:…` apparaissent.

Pour une nouvelle version, remplace le dossier `~/.claude/skills/studio-instagram` par le nouveau et relance l'application.

### Option 2 : avec mises à jour, via GitHub

1. Le catalogue est sur GitHub, dans le dépôt public `Glandai/Autoinsta` : aucun compte GitHub n'est nécessaire pour l'installer.
2. Sur le Mac de la photographe, dans une session de l'onglet Code, ajoute le catalogue et installe le plugin en une étape :
   ```text
   /plugin install studio-instagram --marketplace Glandai/Autoinsta
   ```
   Ou, à la souris : `/plugin marketplace add Glandai/Autoinsta`, puis bouton **+** à côté de la zone de saisie, **Add plugins** (ou **Plugins**, puis **Browse plugins**), choisis **studio-instagram**, portée « pour moi ».
   Depuis un terminal, c'est l'équivalent de :
   ```bash
   claude plugin marketplace add Glandai/Autoinsta
   ```
   ```bash
   claude plugin install studio-instagram@atelier-photo
   ```

Pour publier une nouvelle version : augmente `version` dans `plugins/studio-instagram/.claude-plugin/plugin.json` (et dans `moteur/VERSION`), puis envoie les fichiers sur GitHub. Chez elle, la mise à jour se fait depuis l'onglet **Installed** du gestionnaire de plugins (**Update now**), ou automatiquement si la mise à jour automatique est activée pour ce catalogue.

### Option 3 : catalogue local (pour tester)

```bash
claude plugin marketplace add /chemin/vers/plugin-studio-instagram
```

```bash
claude plugin install studio-instagram@atelier-photo
```

## 2. Installer le studio et l'app

- **Avec Claude (recommandé)** : dans l'onglet Code, `/studio-instagram:studio-installation`. Une trentaine de minutes, guidée : dossier de travail `~/Studio-Instagram`, app Mac dans `~/Applications`, connexion de Claude Code, paramètres du compte, Instagram, galeries, historique, planification du Mac (avec son accord). Venant de la version 1, la même commande met à jour le studio et met en pause les anciennes tâches planifiées de l'application Claude.
- **En une commande**, dans le Terminal : `bash <dossier du plugin>/installer.sh` (par exemple `bash ~/.claude/skills/studio-instagram/installer.sh` avec l'option 1). Le studio et l'app sont prêts en quelques minutes ; l'app guide ensuite la connexion de Claude Code. Pour le compte, Instagram et les galeries, lancer ensuite `/studio-instagram:studio-installation`, qui reprend où on en est.

Le détail (journée type, personnalisation de l'app, planification) est dans `plugins/studio-instagram/README.md` ; le dépannage dans `plugins/studio-instagram/docs/depannage.md`.
