---
name: studio-app
description: Personnalise l'app Mac Studio Instagram à la demande de la photographe. Apparence (couleurs, mode clair ou sombre, titres, densité, arrondis, animations, icônes, écrans visibles, nom, salutation, icône de l'app) ou fonctionnement et mise en page (sources Swift du studio, reconstruites sur place), retour à l'app d'origine, et fusion des personnalisations après une mise à jour du plugin (app/.conflits.json). À utiliser quand elle demande de changer l'app, depuis l'application Claude ou le panneau « Demander à Claude ».
---

# Personnaliser l'app Studio Instagram

Deux niveaux : l'**apparence** (`config/app.yaml`, effet immédiat, sans risque) et les **sources de l'app de ce studio** (`app/Sources/*.swift`, à reconstruire). Choisis toujours le plus léger qui répond à sa demande. Référence technique : `app/ARCHITECTURE.md` (§4.3 apparence, §5 l'app, §6 personnalisation) et, s'il existe, `app/DESIGN.md`.

## Mode app autonome

Si ton prompt système dit que l'app Studio Instagram t'a lancé (panneau « Demander à Claude »), personne ne lit la conversation et ton dernier message s'affiche dans l'app :
- pas d'AskUserQuestion, de SendUserFile, de PushNotification ni de TaskStop, rien en arrière-plan, pas d'`installer.sh` ;
- tu es déjà dans le studio, sans `cd`. Bash n'accepte que `./studio …` et `bash app/construire.sh …` (exactement sous cette forme) ; pour lire, écrire, chercher : Read, Write, Edit, Glob, Grep ;
- demande claire : fais-la. Demande ambiguë : prends l'interprétation la plus simple et dis-la. Changement profond flou ou risqué : décris en deux phrases ce que tu proposes et attends qu'elle confirme dans le panneau ;
- termine par deux phrases simples au plus, sans commande ni chemin de fichier.

Mode conversation : place-toi dans le studio (dossier courant s'il contient `config/compte.yaml`, sinon `~/Studio-Instagram`). Pour un changement profond, résume ce que tu vas faire en une phrase et vérifie que c'est bien ce qu'elle veut.

## Limites à respecter

- Ne modifie que `config/app.yaml` et `app/` (dans le dossier du studio). Jamais `.plugin/` (copie d'origine, remplacée à chaque mise à jour, et protégée), ni `moteur/`, `studio`, `CLAUDE.md`, `docs/` : ils sont remplacés à chaque mise à jour.
- L'app n'écrit rien elle-même dans le studio : elle appelle `./studio app …`, `./studio claude …`, `./studio planifier …` et lit leur JSON. Une demande qui exigerait une nouvelle commande du moteur n'est pas faisable depuis le studio : dis-le et propose ce qui l'est.
- Aucune personnalisation ne contourne une règle d'or : rien ne se publie sans son clic, `.env` n'est jamais lu ni affiché, les photos ne sont jamais modifiées au-delà du recadrage, de la rotation et des marges. Refuse gentiment et explique en une phrase.

## 1. L'apparence (`config/app.yaml`)

- Regarde l'état actuel : `./studio app apparence`.
- Modifie `config/app.yaml` (Edit, en gardant les commentaires). Clés et valeurs possibles :
  - `nom_affiche` (40 caractères au plus), `salutation` (en tête de l'écran Aujourd'hui) ;
  - `mode` : `auto`, `clair`, `sombre` ;
  - `couleurs` (`#rrggbb`) : `accent` (boutons, sélection), `accent_doux` (fonds doux, badges), `fond_clair`, `fond_sombre`, `succes`, `alerte` ;
  - `titres` : `serif`, `arrondi`, `standard` · `densite` : `compacte`, `confortable`, `aeree` · `arrondi` : 0 à 28 · `animations` : `aucune`, `discretes`, `normales`, `riches` · `icones` : `pleines`, `contours` ;
  - `ecrans` : ordre et écrans visibles parmi `aujourdhui`, `idees`, `apercu`, `galeries`, `statistiques`, `reglages`, `charte`, `regles` (`aujourdhui` et `reglages` restent toujours visibles).
- Vérifie avec `./studio app apparence` : chaque valeur voulue doit s'y retrouver (une valeur invalide est remplacée par celle d'origine sans prévenir : corrige-la).
- Couleurs : garde un texte lisible, en clair comme en sombre (le texte blanc doit rester net sur `accent`). Pour une couleur décrite avec des mots (« un vert sauge »), choisis la teinte, puis donne son nom simple dans tes phrases.
- L'app relit ce fichier dès qu'il change : rien à reconstruire. Pour l'ouvrir et lui montrer : `./studio ui aujourdhui --forcer`.
- Tout remettre comme à l'origine : `./studio app retablir-apparence`.

## 2. L'icône de l'app

L'icône (deux tirages sur l'olive, un soleil de Provence : `app/DESIGN.md` §7) est dessinée par `app/Ressources/icone.py` dans `app/Ressources/icone.png`, que `bash app/construire.sh` intègre à l'app. Le script prend des couleurs (`--accent`, `--doux`, `--fond`, `--alerte`, au format `#rrggbb`) ; en général, reprends celles de `config/app.yaml`.
- Mode conversation : garde d'abord une copie de `app/Ressources/icone.png` (`app/.sauvegarde/Ressources/icone.png`), puis `.venv/bin/python app/Ressources/icone.py --accent "#…" --doux "#…"`. Regarde l'image (Read), montre-la-lui, reconstruis et rouvre (partie 3, étapes 4, 6 et 7).
- Mode app : Python n'est pas autorisé. Change les couleurs de l'app si elle le veut, et dis-lui que l'icône se redessine depuis l'application Claude (onglet Code, dossier du studio : « redessine l'icône avec les couleurs de l'app »).
- Revenir à l'icône d'origine : remets `.plugin/app/Ressources/icone.png` à sa place (copie, en mode conversation), puis reconstruis.

## 3. Le fonctionnement ou la mise en page (`app/Sources`)

1. **Comprendre.** Lis `app/ARCHITECTURE.md` (§5), `app/DESIGN.md` s'il existe, `app/PERSONNALISATIONS.md` s'il existe, et les fichiers concernés de `app/Sources/`. Si `app/.conflits.json` liste des conflits, fusionne-les d'abord (partie 5).
2. **Sauvegarder.** Avant de modifier un fichier, garde sa version actuelle : Read, puis Write dans `app/.sauvegarde/<même chemin>` (par exemple `app/.sauvegarde/Sources/VueIdees.swift`), en écrasant l'ancienne sauvegarde. Note aussi les fichiers que tu crées.
3. **Modifier** les fichiers de `app/Sources/` (seuls les `.swift` posés directement dans ce dossier sont compilés). Règles Swift :
   - aucune macro (leur greffon n'est livré qu'avec Xcode, absent ici) : `@Local` au lieu de `@State` (voir `Compat.swift`), jamais `@Entry`, `@Animatable`, `@AnimatableIgnored`, `#Preview`, `@Previewable` ; pas de `@Observable` : `ObservableObject` et `@Published` ;
   - seulement les frameworks d'Apple (SwiftUI, AppKit, AVKit, Charts, UserNotifications), aucun paquet à télécharger ;
   - respecte la version de macOS visée par `app/construire.sh` (`CIBLE_MACOS`, macOS 14) : une API plus récente demande `if #available(macOS …, *)` ;
   - garde le style de l'app (composants de `Style.swift`, thème, textes en français simple et chaleureux).
4. **Reconstruire** : `bash app/construire.sh` (une à deux minutes ; donne à Bash un délai de 10 minutes). Si `.ui/app.json` place l'app ailleurs que dans `~/Applications`, passe son dossier : `bash app/construire.sh "<dossier qui contient Studio Instagram.app>"`. La dernière ligne affichée est le chemin de l'app ; l'app ouverte est fermée, remplacée puis rouverte.
5. **Si la compilation échoue** (« La compilation a échoué », suivi des erreurs) : corrige, trois essais au plus. Si cela échoue encore, remets chaque fichier modifié tel qu'il était (`app/.sauvegarde/…`, ou `.plugin/app/…` pour un fichier jamais personnalisé) ; un fichier que tu as créé : supprime-le en mode conversation, vide-le en mode app (un fichier Swift vide se compile). L'app installée n'a pas été touchée : elle n'est remplacée qu'après une compilation réussie. L'app ne doit jamais rester cassée : dis-lui simplement que ce changement n'a pas pu se faire et que rien n'a changé.
6. **Rouvrir** sur l'écran concerné : `./studio ui <écran> --forcer` (`aujourdhui` par défaut). Mode conversation : demande-lui de regarder ; si l'app ne s'ouvre plus ou se ferme toute seule, reviens en arrière comme à l'étape 5, puis reconstruis.
7. **Noter** dans `app/PERSONNALISATIONS.md` (crée-le au besoin, titre « Personnalisations de l'app ») une entrée datée : sa demande avec ses mots, les fichiers changés, ce qui a changé en une ou deux phrases. C'est ce qui permet de refaire ses personnalisations après une mise à jour.

## 4. Revenir à l'app d'origine

- Un changement précis : retrouve-le dans `app/PERSONNALISATIONS.md`, remets les fichiers concernés comme dans `.plugin/app/` (Read de l'original, Write dans `app/`), reconstruis, rouvre, note le retour en arrière.
- Toute l'app : même chose pour chaque fichier de `app/` qui diffère de `.plugin/app/`, plus `./studio app retablir-apparence` si elle veut aussi les couleurs d'origine.

## 5. Après une mise à jour : fusionner les personnalisations

`app/.conflits.json` liste (`conflits`) les fichiers qu'elle a fait personnaliser et que la nouvelle version du plugin a aussi changés. Sa version a été gardée ; `nouvelle_version` dit où lire celle du plugin (en général `.plugin/app/<fichier>` ; vide si le plugin a retiré le fichier). Pour chaque entrée :
1. Lis sa version (`app/<fichier>`), la nouvelle (`nouvelle_version`) et ce qu'elle avait demandé (`app/PERSONNALISATIONS.md`).
2. Sauvegarde sa version (`app/.sauvegarde/…`), puis fusionne : en général, pars de la nouvelle version et refais-y ses personnalisations ; garde tout ce qu'elle avait voulu.
3. Fichier retiré du plugin : garde le sien s'il sert encore et compile, sinon retire-le (étape 5 de la partie 3).
4. Reconstruis et rouvre (partie 3, étapes 4 à 6). En cas d'échec, remets sa version, laisse l'entrée et dis-le-lui.
5. Réussi : retire l'entrée de `app/.conflits.json` (Edit) et note la fusion dans `app/PERSONNALISATIONS.md`. Une entrée dont le fichier est redevenu identique à la nouvelle version disparaît d'elle-même à la mise à jour suivante.

Termine en lui disant ce qui a changé dans son app, en une ou deux phrases, sans jargon.
