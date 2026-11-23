# Studio Instagram 2.0 — architecture de l'app autonome

Ce document décrit l'app Mac « Studio Instagram », son lien avec le moteur (`./studio`) et avec Claude. Il sert aux développeurs… et à Claude quand la photographe lui demande de personnaliser l'app (skill `studio-app`).

## 1. Ce que veut la photographe

- **Une app autonome.** Elle ne change jamais de fenêtre : l'app lance Claude elle-même (en arrière-plan, sans fenêtre), montre ce qu'il fait, et s'ouvre toute seule quand une décision l'attend.
- **Connexion à Claude automatique, ou guidée.** Si Claude Code est installé et connecté, l'app le trouve. Sinon, elle guide en deux clics : installer, puis se connecter (le navigateur s'ouvre sur la page de connexion Anthropic).
- **Une interface claire, intuitive et belle** : photo d'abord, peu de mots, animations douces, icônes cohérentes.
- **Personnalisable par Claude.** Depuis l'app Claude (ou le panneau « Demander à Claude » de l'app), elle peut demander de changer l'apparence ou le fonctionnement de l'app. Claude modifie `config/app.yaml` (apparence, effet immédiat) ou les sources de l'app dans le dossier du studio, puis la reconstruit.

## 2. Vue d'ensemble

```
 App Mac (SwiftUI)  ── ./studio app|claude|planifier …  ──▶  Moteur Python (dossier du studio)
        ▲   lit .ui/claude/*.json, jours/*/etat.json…              │
        │                                                           ├─▶ claude -p … (Claude Code, sans fenêtre)
        └──────────── open -a (écran demandé dans .ui/demande.json) ◀┘      avec le plugin (--plugin-dir .plugin)
 launchd (LaunchAgents) ── ./studio claude lancer matin|bilan --attendre ; ./studio publier-dus
```

- L'app n'écrit jamais elle-même dans les fichiers du studio : elle appelle `./studio …` et reçoit du JSON (une seule source de vérité, les mêmes contrôles que Claude).
- **Claude travaille sans fenêtre** : le moteur lance `claude -p` dans le dossier du studio, lit son flux (`stream-json`) et écrit l'avancement dans `.ui/claude/<id>.json`. L'app affiche cet avancement en direct.
- **La planification ne dépend plus de l'app Claude** : des LaunchAgents macOS lancent la routine du matin, les publications aux créneaux et le bilan, même si l'app est fermée.
- Les décisions simples (approuver, publier, reporter) sont appliquées par l'app via le moteur ; les décisions créatives (créer le post choisi, retoucher) relancent Claude.

## 3. Le dossier du studio (ajouts de la 2.0)

| Chemin | Rôle |
|---|---|
| `.plugin/` | copie du plugin (skills, moteur d'origine, sources de l'app) ; passée à Claude avec `--plugin-dir` |
| `app/` | sources de l'app **de ce studio** (personnalisables) ; `app/.base.json` garde l'empreinte des fichiers d'origine ; `app/PERSONNALISATIONS.md` liste les changements faits par Claude |
| `config/app.yaml` | apparence de l'app (couleurs, mode, titres, densité, animations, écrans visibles) |
| `.ui/claude/` | exécutions de Claude : `<id>.json` (état), `<id>.jsonl` (flux brut), `actuel.json` (dernière exécution), `verrou` |
| `.ui/logs/` | journaux des LaunchAgents et des exécutions |

Mise à jour du plugin (installer.sh) : `.plugin/` est remplacé ; dans `app/`, un fichier jamais modifié suit la nouvelle version, un fichier personnalisé est conservé et, s'il a aussi changé dans le plugin, signalé dans `app/.conflits.json` (le skill `studio-app` aide à fusionner).

## 4. Contrats moteur ↔ app (JSON)

Toutes les commandes écrivent un objet JSON sur la sortie standard ; en cas d'erreur : `{"erreur": "message lisible"}` et un code de sortie non nul.

### 4.1 Claude

`./studio claude statut`
```json
{"installe": true, "chemin": "/Users/x/.local/bin/claude", "source": "reglage|path|app_claude",
 "version": "2.1.326", "connecte": true, "methode": "claude.ai|console|cle_api|aucune",
 "plugin_present": true, "en_cours": null,
 "conseil": "phrase simple quand quelque chose manque, sinon null"}
```
Recherche du binaire, dans l'ordre : `claude.chemin` de `config/compte.yaml` ; `claude` dans le PATH augmenté de `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin` ; enfin la copie livrée avec l'app Claude (`~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`, version la plus récente). Connexion : `claude auth status --json` (`loggedIn`, `authMethod`).

`./studio claude installer` → `{"etat": "installe|deja_installe|echec", "chemin": "...", "journal": "dernières lignes"}`. Utilise `<copie de l'app Claude> install stable` si elle existe, sinon l'installeur officiel (`curl -fsSL https://claude.ai/install.sh | bash`). Lancé seulement sur un clic de la photographe.

`./studio claude connecter [--console]` → `{"etat": "navigateur_ouvert|deja_connecte|absent|terminal_ouvert|echec", "url": "lien de secours ou null", "code_attendu": true, "conseil": "..."}`. Lance `claude auth login --claudeai` (ou `--console`) détaché, l'entrée standard reliée à une file nommée `.ui/claude/connexion.fifo`. La page de connexion affiche ensuite un **code** à recopier : la photographe le colle dans l'app, qui appelle `./studio claude code <code>` → `{"etat": "connecte|refuse|echec|expire", "conseil": "..."}` (attend jusqu'à ~20 s la connexion). L'app interroge aussi `statut` toutes les 2 s. Le mot de passe se tape dans le navigateur, jamais dans l'app ni dans Claude ; le code n'est jamais enregistré.

`./studio claude deconnecter` → `{"etat": "deconnecte"}` (`claude auth logout`).

`./studio claude lancer <tache> [--jour J] [--serie S] [--consigne "texte"] [--attendre] [--auto]`
- `tache` ∈ `matin`, `creation`, `retouche`, `galerie`, `bilan`, `demande`.
- Réponse immédiate : `{"etat": "lance", "id": "20261119-150026-creation"}`, ou `{"etat": "deja_en_cours", "id": "..."}`, ou `{"etat": "non_connecte", "conseil": "..."}`, ou `{"etat": "absent", "conseil": "..."}`.
- `--attendre` : exécute au premier plan et rend l'état final (utilisé par launchd). `--auto` : lancé par la planification (notification macOS à la fin).

`./studio claude etat [--id ID]` → l'exécution demandée, ou la dernière :
```json
{"id": "20261119-150026-creation", "tache": "creation", "jour": "2026-11-19",
 "titre": "Claude prépare ton post", "etat": "en_attente|en_cours|termine|erreur|annule",
 "debut": "2026-11-19T15:00:26+01:00", "fin": null, "duree_s": 42,
 "etapes": [{"le": "…", "texte": "Je regarde les photos de la série", "icone": "eye", "fait": true}],
 "message": "dernière phrase de Claude (courte)", "resultat": "résumé final de Claude ou null",
 "erreur": "message lisible ou null", "ecran_suivant": "apercu|idees|galeries|statistiques|null",
 "session": "uuid", "cout_usd": 0.42}
```
`./studio claude annuler` → `{"etat": "annule|rien_en_cours"}`. `./studio claude historique` → les 20 dernières exécutions (mêmes objets, sans `etapes`).

**Exécution** (`./studio claude executer <id>`, interne) :
- Une seule à la fois par studio (`.ui/claude/verrou` avec le PID ; un verrou dont le PID est mort est ignoré).
- Commande : `claude -p --output-format stream-json --verbose --plugin-dir <studio>/.plugin --permission-mode acceptEdits --permission-prompts none --allowedTools "Bash(./studio:*)" Read Write Edit Glob Grep --append-system-prompt <MODE_APP> -n "Studio · <tâche> · <jour>" (--session-id U | --resume U) [--model M] [--effort E]`. Le texte de la demande passe par l'entrée standard (jamais par la ligne de commande). Dossier courant : le studio.
- Environnement : celui de l'utilisateur, PATH augmenté, `STUDIO_APP=1`, et **sans** aucune variable commençant par `CLAUDE` (ni `CLAUDECODE`) ni `ANTHROPIC_BASE_URL` : elles appartiennent à une éventuelle session Claude parente.
- Session : les tâches d'une journée (`matin`, `creation`, `retouche`) partagent une session (`jours/<J>/claude.json` → `{"session": "uuid"}`) : la première crée (`--session-id`), les suivantes reprennent (`--resume`), avec repli sur une nouvelle session si la reprise échoue. `demande` reprend la conversation du panneau « Demander à Claude » (`.ui/claude/conversation.json`), remise à zéro par « Nouvelle conversation ». `galerie` et `bilan` : nouvelle session à chaque fois.
- Avancement : chaque appel d'outil devient une étape lisible (table dans `moteur/claude.py`, par exemple `./studio planches` → « Je prépare les planches contact », lecture d'un JPEG → « Je regarde les photos », écriture de `post.json` → « J'écris le post »). Le dernier texte de Claude alimente `message`.
- Fin : `resultat`, `cout_usd`, `ecran_suivant` ; puis le moteur montre cet écran (`app.ouvrir`, qui respecte `interface.ouvrir_app`). Délai maximal : `claude.delai_max_min` (45 min par défaut).
- Erreurs reconnues et traduites : non connecté, quota ou limite atteinte, réseau, permission refusée.

**MODE_APP** (ajouté au prompt système) : Claude est lancé par l'app, sans personne devant la conversation. Pas d'AskUserQuestion, SendUserFile, PushNotification, TaskStop ni de commande en arrière-plan ; pas d'`installer.sh` ; jamais `./studio ui … --attendre`. Pour montrer un écran : `./studio ui <écran> --jour <J>`, puis terminer. Résumé final de deux phrases au plus, en français simple (il s'affiche dans l'app).

### 4.2 Planification (launchd)

`./studio planifier --etat|--activer|--desactiver` →
```json
{"active": true, "taches": [{"id": "matin", "titre": "Idées du matin", "quand": "chaque jour à 08:00", "chargee": true},
  {"id": "publication", "titre": "Publication", "quand": "lun., mar., mer., jeu. à 18:30 · ven. à 12:30 …", "chargee": true},
  {"id": "bilan", "titre": "Bilan de la semaine", "quand": "dimanche à 19:00", "chargee": true}],
 "dossier_agents": "~/Library/LaunchAgents"}
```
- Fichiers : `~/Library/LaunchAgents/fr.atelier-photo.studio-instagram.<matin|publication|bilan>.plist`, chargés avec `launchctl bootstrap gui/<uid>` (et `bootout` avant remplacement).
- `matin` → `<studio>/studio claude lancer matin --attendre --auto` ; `publication` → `<studio>/studio publier-dus --auto` (sans Claude) ; `bilan` → `<studio>/studio claude lancer bilan --attendre --auto`.
- `EnvironmentVariables.PATH` augmenté, journaux dans `<studio>/.ui/logs/`.
- `planification.active` est enregistré dans `config/compte.yaml` ; `enregistrer-reglages` replanifie si la planification est active.
- Tests : `STUDIO_LAUNCHAGENTS_DIR` (autre dossier) et `STUDIO_SANS_LAUNCHCTL=1` (n'appelle pas launchctl).

### 4.3 Apparence (`config/app.yaml`)

`./studio app apparence` → l'objet normalisé ; `./studio app enregistrer-apparence <fichier.json>` → `{"etat": "enregistre|refuse", "erreurs": [...]}` ; `./studio app retablir-apparence`.
```yaml
nom_affiche: "Studio Instagram"
salutation: "Bonjour"            # en tête de l'écran Aujourd'hui
mode: auto                       # auto | clair | sombre
couleurs:
  accent: "#3d4130"              # olive : boutons, sélection
  accent_doux: "#efdccd"         # pêche : fonds doux, badges
  fond_clair: "#f7f3ed"          # papier
  fond_sombre: "#17160f"
  succes: "#3f6b45"
  alerte: "#a8551c"
titres: serif                    # serif | arrondi | standard
densite: confortable             # compacte | confortable | aeree
arrondi: 14                      # 0 à 28
animations: normales             # aucune | discretes | normales | riches
icones: pleines                  # pleines | contours
ecrans: [aujourdhui, idees, apercu, galeries, statistiques, reglages, charte, regles]   # ordre et écrans visibles
```
L'app relit ce fichier dès qu'il change : une personnalisation faite par Claude s'affiche aussitôt, sans reconstruire l'app. « aujourdhui » et « reglages » restent toujours visibles.

### 4.3 bis Assistant de création, Instagram, nouvelles clés d'apparence

- `config/app.yaml` gagne `ambiance` (provence | lavande | aube | sauge | nuit : dégradé de fond animé), `points` (trame de points sur le dégradé), `police` (jakarta = Plus Jakarta Sans, livrée dans `app/Ressources/Polices` | systeme | arrondie) ; `titres` accepte aussi `police` (valeur par défaut : même police que le texte). Écran `creation` (assistant de création), atteint par le bouton « + » et par les fins d'exécution `creation`/`retouche` (`ecran_suivant` = `creation`).
- `config/compte.yaml` → `creation.etapes_a_valider` : sous-ensemble de `photos`, `legende`, `musique` (l'aperçu final se valide toujours) ; exposé par `./studio app reglages` (`creation`), renvoyé par `enregistrer-reglages`.
- `./studio app modifier-post <jour> <fichier.json>` : `{"medias": [identifiants, ou {photo_id, presentation, fond, texte_alternatif}] (ordre voulu), "legende": "…", "musique": {mode, audio_id, titre, artiste, apercu_url, …}}` → refait la mise en page (si les photos changent), le contrôle et l'aperçu → `{"etat": "enregistre|inchange", "changements": [...], "controle": {...}, "avertissements": [...]}`. Refusé pour un post déjà validé ou publié. Journalisé dans `donnees/retouches.jsonl` (`modification_dans_l_app`) pour que Claude apprenne de ses choix.
- `./studio app candidats <serie>` → `[{id, note, pilier, description, orientation, vignette}]` (photos à proposer, les mieux notées d'abord).
- `./studio app instagram` → `{"etat": "valide|absent|invalide", "route", "compte", "abonnes", "expire_le", "erreur"}` (jamais de jeton). `./studio app enregistrer-instagram <fichier.json>` : `{"route": "facebook|instagram", "app_id", "app_secret", "jeton"}` → écrit `.env`, échange et vérifie le jeton → `{"etat": "connecte|refuse|echec", "erreurs", "compte", "abonnes"}`. Le fichier est effacé dès sa lecture ; l'app l'écrit en 0600 et ne le journalise jamais.

### 4.4 Déjà existants (1.2)

`./studio ui <écran> [--jour J] [--attendre] [--forcer]`, `./studio app jour|jours|reglages|enregistrer-reglages|galeries|enregistrer-galerie|supprimer-galerie|indexer-galerie|charte|enregistrer-charte|retablir-charte|regles|enregistrer-regles|retablir-regles|memoire|enregistrer-memoire|sante|decider|decision-traitee|attente`, `./studio taches` (ancienne planification par l'app Claude, remplacée par `planifier`).

## 5. L'app SwiftUI

- macOS 14 minimum. Compilée sur place par `app/construire.sh` avec les seuls outils de développement d'Apple (`swiftc`), sans Xcode.
- **Interdits** (macros dont le greffon n'est livré qu'avec Xcode) : `@State` → utiliser `@Local` (alias de `State`, voir `Compat.swift`), `@Entry`, `@Animatable`, `@AnimatableIgnored`, `#Preview`, `@Previewable`. Pas de `@Observable` : `ObservableObject` + `@Published`.
- Frameworks : SwiftUI, AppKit, AVKit, Charts, UserNotifications.
- Fichiers : `StudioApp.swift` (fenêtre, navigation, accueil), `Theme.swift` (apparence), `Style.swift` (composants), `Modeles.swift` (types JSON), `Moteur.swift` (`EtatApp` : appels au moteur, surveillance des fichiers), `Vue*.swift` (écrans).
- `EtatApp` lance Claude avec `lancerClaude(_:jour:serie:consigne:)`, suit l'exécution en cours (`execution`), et enchaîne : idée choisie → création ; retouche demandée → retouche ; sauf si une session Claude attend déjà la décision (`claude_attend`), auquel cas c'est elle qui continue.

## 6. Personnaliser l'app avec Claude (skill `studio-app`)

1. Apparence (couleurs, mode, typographie, densité, animations, écrans) : modifier `config/app.yaml`, vérifier avec `./studio app apparence`. Effet immédiat.
2. Fonctionnement ou mise en page : modifier `app/Sources/*.swift` **dans le dossier du studio** (jamais dans `.plugin/`), reconstruire avec `bash app/construire.sh`, rouvrir l'app (`./studio ui aujourdhui --forcer`), noter le changement dans `app/PERSONNALISATIONS.md`. En cas d'échec de compilation, corriger ou revenir en arrière : l'app ne doit jamais rester cassée.

## 7. API de l'app pour les vues

`EtatApp` (`Moteur.swift`) est le seul objet que les écrans utilisent : `@EnvironmentObject var etat: EtatApp`. Il est `@MainActor` ; ses méthodes `async` s'appellent depuis un bouton avec `Task { await etat.… }`. Elles ne lèvent jamais d'erreur : un échec remplit `erreur` (ou `invitationClaude` quand c'est Claude qui manque), une réussite remplit souvent `message`. Les vues n'écrivent jamais dans le dossier du studio : elles passent par ces méthodes, qui appellent `./studio …`.

**Rapidité.** Chaque appel au moteur (processus et décodage JSON) tourne hors du fil principal ; `toutCharger()` lance tout en parallèle ; la surveillance ne relit un fichier que si sa date a changé et ne recharge que ce qui en dépend, sans empiler les chargements. Les vues ne lancent jamais d'appel au moteur dans `body` : seulement dans `.task`, `.onAppear` ou une action.

### 7.1 Propriétés publiées

| Propriété | Type | Rôle |
|---|---|---|
| `dossier` | `URL` | dossier du studio suivi (pointeur `~/Library/Application Support/Studio Instagram/reglages.json`) ; `studioInstalle` dit s'il contient `studio` |
| `ecran` | `Ecran?` | écran affiché (liaison de la barre latérale) ; pour changer d'écran avec animation : `montrer(_:jour:)`. `.creation` (« Nouveau post », symbole `plus`) n'est pas dans la barre : bouton « + » → `montrer(.creation)` (trois cartes d'idées, ou « D'autres idées » → `lancerClaude(.idees)`). Barre d'icônes : `Apparence.ecransEssentiels` (accueil, galeries, statistiques, réglages) ; idées et aperçu s'ouvrent par « + » et l'accueil, charte et règles par les Réglages |
| `jour` | `String` | jour affiché (`AAAA-MM-JJ`) ; après l'avoir changé, appeler `chargerJour()` (ou passer par `montrer`) |
| `vue`, `jours` | `VueJour?`, `[ResumeJour]` | la journée affichée, la liste des journées |
| `reglages`, `galeries`, `charte`, `regles`, `memoire`, `sante` | types 1.x | chargés à la demande (`chargerReglages()`…) |
| `occupe` | `Bool` | une décision est en cours d'envoi (boutons désactivés) |
| `message`, `erreur` | `String?` | bandeau de confirmation (s'efface au bout de quelques secondes) ou d'erreur (fermé par la photographe) ; une vue peut les remettre à `nil` |
| `claude` | `ClaudeStatut?` | Claude Code sur ce Mac ; `nil` tant que le moteur n'a pas répondu. Raccourci : `claudePret` |
| `execution` | `ExecutionClaude?` | l'exécution en cours, sinon la dernière connue ; `claudeTravaille` = en attente ou en cours |
| `historiqueClaude` | `[ExecutionClaude]` | 20 dernières exécutions, sans étapes, la plus récente d'abord |
| `planification` | `Planification?` | tâches automatiques du Mac (launchd) |
| `apparence` | `Apparence` | apparence normalisée (`config/app.yaml`) ; `Apparence.defaut` tant que rien n'est lu. Changée avec animation |
| `invitationClaude` | `InvitationClaude?` | Claude manque pour ce qui vient d'être demandé : texte + bouton (`libelleBouton`, `symbole`) → `accepterInvitation()` |
| `connexionEnCours` | `Bool` | page de connexion ouverte, l'app attend (3 min au plus) |
| `codeConnexionAttendu` | `Bool` | la page de connexion va afficher un code à coller dans l'app → `envoyerCodeConnexion(_:)` |
| `envoiCodeEnCours` | `Bool` | le code est transmis, le moteur attend la connexion (jusqu'à ~20 s) : champ et bouton désactivés, indicateur d'attente |
| `lienConnexion` | `URL?` | lien de secours si le navigateur ne s'est pas ouvert → `ouvrirLienConnexion()` |
| `installationEnCours`, `lancementEnCours` | `Bool` | installation de Claude Code ; envoi d'une tâche à Claude (entre le clic et la réponse du moteur) |
| `animationEcran` | `Animation?` (calculée) | animation des changements d'écran selon `apparence.animations` (`nil` si « aucune ») |
| `instagram` | `InstagramEtat?` | connexion à Instagram (`chargerInstagram()`) ; nil tant qu'elle n'a pas été vérifiée |
| `connexionInstagramEnCours` | `Bool` | identifiants Instagram en cours de vérification |
| `modificationEnCours` | `Bool` | `modifierPost` : le moteur refait mise en page, contrôle et aperçu (quelques secondes) |
| `progressionCreation` | `Double` (calculée) | avancement de l'exécution en cours ou de la dernière, de 0 à 1, pour la barre de chargement : étapes faites sur étapes attendues pour la tâche, relevé par les étapes repères d'une création (« J'écris le post » 0,55, mise en page 0,7, contrôle 0,8, aperçu 0,9) ; plafonné à 0,96 tant que Claude travaille, 1 une fois réussie ; ne recule jamais. Texte à côté : `execution?.etapeCourante?.texte` |
| `ajoutSourceEnCours`, `exportEnCours` | `Bool` | `ajouterSource` (copie et lecture des photos ; plus long pour un lien Pic-Time), `exporter` |
| `versionImages` | `Int` | augmente quand les images du post sont refaites (mêmes chemins, nouveau contenu) : `.id(etat.versionImages)` sur une image du post force sa relecture |
| `etapesAValider` | `[String]` (calculée) | étapes de l'assistant que la photographe valide (`photos`, `legende`, `musique`, dans cet ordre ; toutes sans réglage) ; `doitValider(_:)`. L'aperçu se valide toujours |
| `mediasDuPost` | `[MediaModifie]?` (calculée) | photos actuelles du post, dans l'ordre, prêtes à être retirées, ajoutées ou réordonnées ; nil si le moteur ne donne pas leurs `photo_id` |

### 7.2 Méthodes

Chargement et navigation :
- `demarrer()` (une fois, à l'apparition de la fenêtre), `toutCharger()` (⌘R, tout en parallèle), `chargerJour(liste: Bool = true)` (le jour affiché, et la liste des jours si `liste`, en parallèle ; une réponse arrivée après un changement de jour est ignorée), `chargerReglages()`, `chargerGaleries()`, `chargerCharte()`, `chargerRegles()`, `chargerMemoire()`, `chargerSante()`, `choisirDossier()`.
- `montrer(_ ecran: Ecran, jour: String? = nil)` : change d'écran (et de jour) avec `animationEcran`.

Décisions et studio (1.x, inchangées) :
- `decider(_ action: String, _ valeur: String? = nil)` : `choix` (numéro), `libre` (texte), `approuver` (`creneau`, `maintenant` ou `HH:MM`), `retouche` (texte), `reporter`. Enchaînements en 7.4.
- `envoyer(_:action:avant:) -> Bool` (JSON, ex. `enregistrer-reglages`), `envoyerTexte(_:action:avant:) -> Bool` (Markdown), `retablir(_ action:)`, `indexerGalerie(_:)`, `supprimerGalerie(_:)`, `appeler(_:_:)` (appel brut au moteur, lève une erreur), `ouvrirClaude(commande:)` (ouvre l'app Claude, commande copiée : secours de la 1.x).

Claude, installation et connexion :
- `chargerClaude(silencieux: Bool = false)` : `./studio claude statut` → `claude`.
- `installerClaude()` : seulement sur un clic ; à la fin, invite à se connecter (`invitationClaude`).
- `connecterClaude(console: Bool = false)` : ouvre la page de connexion d'Anthropic, puis interroge le statut toutes les 2 s (3 min au plus) jusqu'à `claude.connecte`. Pendant l'attente : `connexionEnCours`, éventuellement `codeConnexionAttendu` et `lienConnexion`. À la réussite : `message`, fin de l'invitation, l'app repasse au premier plan.
- `envoyerCodeConnexion(_ code: String) -> Bool` : transmet le code affiché par la page (`./studio claude code <code>`, qui attend jusqu'à ~20 s la connexion). Espaces et retours à la ligne retirés ; jamais enregistré. Réponses : `connecte` (même fin que la connexion réussie), `refuse` (code mal recopié : `erreur`, l'attente continue), `expire` ou `echec` (`erreur`, l'attente s'arrête : recliquer sur « Se connecter »). Le suivi de `statut` toutes les 2 s continue en parallèle : la connexion est vue même si le code est collé ailleurs (Terminal).
- `arreterConnexion()` (cesse d'attendre), `ouvrirLienConnexion()`, `deconnecterClaude()`.
- `accepterInvitation()` : le bouton de `invitationClaude` (installer ou se connecter).

Claude, exécutions :
- `lancerClaude(_ tache: TacheClaude, jour: String? = nil, serie: String? = nil, consigne: String? = nil) -> Bool` : vrai si Claude a démarré (`execution` montre aussitôt une exécution provisoire « en attente », puis la vraie). Sinon : `invitationClaude` (pas connecté, pas installé), `message` (Claude travaille déjà : l'exécution en cours est chargée) ou `erreur`. `jour` vaut par défaut le jour affiché ; `serie` est obligatoire pour `.galerie`, `consigne` pour `.retouche` et `.demande` (voir `demandeSerie`, `demandeConsigne`).
- `annulerClaude()` : arrête l'exécution en cours ; sa fin (« annule ») arrive par la surveillance.
- `chargerExecution(id: String? = nil)` (silencieux), `chargerHistoriqueClaude()` (silencieux), `nouvelleConversation()` (le panneau « Demander à Claude » repart de zéro).

Assistant de création (écran `creation`) :
- `modifierPost(jour: String? = nil, medias: [MediaModifie]? = nil, legende: String? = nil, musique: Musique? = nil) -> Bool` : `./studio app modifier-post`. Seules les parties données changent (ordre de `medias` = ordre du carrousel ; une photo déjà là garde ses réglages). Le moteur refait la mise en page (si les photos changent), le contrôle et l'aperçu ; `vue` est rechargée et `versionImages` augmente. Vrai si c'est enregistré ; un contrôle non conforme est signalé dans `erreur` (« C'est enregistré, mais à revoir : … »). Refusé (faux, `erreur`) pour un post déjà validé ou publié, une légende vide, aucune photo.
- `candidats(serie: String) -> [PhotoCandidate]` : photos de la galerie à proposer, les mieux notées d'abord (60 au plus).
- `chercherMusique(_ requete: String) -> [PisteMusique]` : bibliothèque musicale d'Instagram (route Facebook) ; choisir une piste : `modifierPost(musique: piste.musique())`.

Flux de l'accueil (`conception/flux-unique.md` : idées → photos → génération → aperçu → finaliser) :
- Idées : `vue.idees` (cartes : `couverture` et `briefAffiche`, le `brief` d'une phrase du moteur) ; choisir → `decider("choix", "\(numero)")` ; son propre brief → `decider("libre", texte)` ; « D'autres idées » → `lancerClaude(.idees)`.
- `ajouterSource(fichiers: [URL], nom: String? = nil) -> String?`, `ajouterSource(dossier: URL, nom:) -> String?`, `ajouterSource(pictime: String, nom:) -> String?` : `./studio app ajouter-source` (fichiers copiés dans le studio, jamais modifiés ; dossier lu sur place ; lien Pic-Time lu). Rend l'identifiant de la série créée (« post-… »), puis `lancerClaude(.creation, serie: id)` : Claude utilise ces photos (et les analyse d'abord s'il le faut). Nil avec `erreur` sinon. « Utiliser les photos de l'idée » : `lancerClaude(.creation, serie: idee.serie)`.
- Génération : barre `progressionCreation` + `execution?.etapeCourante?.texte` ; l'app peut être fermée, elle se rouvre quand c'est prêt.
- Aperçu : `vue.post` ; « Dis à Claude ce qu'il faut changer… » → `decider("retouche", texte)` (lance `.retouche`).
- `exporter(jour: String? = nil) -> URL?` : copie images (ou Reel), `legende.txt` et `textes-alternatifs.txt` dans `~/Downloads/Studio Instagram/<jour> <titre>` (l'app passe ce dossier au moteur : `./studio app exporter <jour> <dossier>`), puis l'ouvre dans le Finder ; nil avec `erreur` si le post n'est pas prêt. Publier : `decider("approuver", "maintenant")` après confirmation.

Instagram (onboarding « Connexions », Réglages) :
- `chargerInstagram(silencieux: Bool = false)` : `./studio app instagram` → `instagram` (interroge Instagram : une à deux secondes ; à appeler à l'apparition de l'écran qui l'affiche).
- `connecterInstagram(route: String, appId: String = "", secret: String = "", jeton: String) -> Bool` : route `facebook` (identifiant de l'app, clé secrète, jeton) ou `instagram` (jeton seul). Les identifiants passent par un fichier créé en 0600 que le moteur efface dès sa lecture (`enregistrer-instagram`) ; jamais sur la ligne de commande, dans un message ou un journal. Réussite : `message`, `instagram` rechargé ; sinon `erreur` (champs manquants, ou refus d'Instagram).

Planification et apparence :
- `chargerPlanification(silencieux: Bool = false)`, `planifier(activer: Bool) -> Bool` (met aussi à jour `reglages?.planification`).
- `chargerApparence(silencieux: Bool = false)`, `enregistrerApparence(_ a: Apparence) -> Bool` (normalise, enregistre, applique aussitôt ; faux si le moteur refuse, avec `erreur`), `retablirApparence()`.

### 7.3 Types (`Modeles.swift`, `Moteur.swift`)

Les types 2.0 se décodent toujours : une clé absente, `null` ou d'un type inattendu prend sa valeur par défaut.
- `TacheClaude` : `matin`, `idees` (« Nouvelles idées », `sparkles` : trois nouvelles idées depuis « + », consigne facultative ; tâche du jour), `creation`, `retouche`, `galerie`, `bilan`, `demande`, `charte` (« Adapter la charte », `text.book.closed` : Claude adapte `config/charte.md` à l'activité) ; `titre` (court), `titreEnCours` (« Claude cherche de nouvelles idées », « Claude adapte ta charte à ton activité »…), `symbole`, `duJour`, `demandeSerie`, `demandeConsigne` (obligatoire), `accepteConsigne` (obligatoire ou facultative).
- `ClaudeStatut` : `installe`, `chemin`, `source`, `version`, `connecte`, `methode`, `plugin_present`, `en_cours`, `conseil` ; `pret`, `libelleMethode`, `libelleSource`.
- `ExecutionClaude` : `id`, `tache`, `jour`, `titre`, `etat` (`en_attente|en_cours|termine|erreur|annule`, ou `aucune`), `debut`, `fin`, `duree_s`, `etapes`, `message`, `resultat`, `erreur`, `ecran_suivant`, `session`, `cout_usd`, `serie`, `consigne`, `auto`, `modele`, `avertissement` ; `enCours`, `terminee`, `reussie`, `aucune`, `tacheClaude`, `ecranSuivant`, `titreAffiche`, `libelleEtat`, `etapeCourante`, `duree(a:)` et `libelleDuree(a:)` (durée vivante : passer la date d'un `TimelineView`), `plusRecente(que:)`.
- `EtapeClaude` : `id` (stable), `le`, `texte`, `icone`, `fait`, `n` (actions regroupées) ; `symbole` (l'icône du moteur si elle existe sur ce Mac, sinon un symbole neutre), `date`.
- `ReponseLancement` (`etat` : `lance|deja_en_cours|non_connecte|absent|erreur`, `id`, `conseil`), `ReponseConnexion` (`etat` : `navigateur_ouvert|terminal_ouvert|deja_connecte|absent|echec`, `url`, `code_attendu`, `conseil`), `ReponseInstallation`, `ReponseEtat` : utilisées par `EtatApp`, rarement utiles aux vues.
- `Planification` (`active`, `taches`, `dossier_agents`) et `TachePlanifiee` (`id` : `matin|publication|bilan`, `titre`, `quand`, `chargee`, `prochaine`) ; `titreAffiche`, `symbole`, `dateProchaine`, `libelleProchaine` (« demain à 08:00 »).
- `Ecran` : `aujourdhui`, `idees`, `creation`, `apercu`, `galeries`, `statistiques`, `reglages`, `charte`, `regles` ; `titre`, `symbole` (ceux de DESIGN.md §5 ; `creation` : « Nouveau post », `plus`).
- `Apparence` : **seuls `mode`, `ambiance`, `nom_affiche` et `salutation` se règlent** (`Apparence.reglables` ; `enregistrerApparence` n'envoie qu'eux) ; le moteur fixe le reste et `normalisee()` fait de même (pas de trame de points, `ecrans` = `Apparence.ecransEssentiels`). Ancienne description, valable en lecture : (+ `CouleursApparence`) champs de §4.3 avec `ambiance` (`provence` par défaut), `police` (`jakarta`), `points` (`true`), `titres` (`police` par défaut : même police que le texte) ; `Apparence.defaut` (sans `creation` dans `ecrans`), listes des choix permis (`modes`, `ambiances`, `polices`, `stylesTitres`, `densites`, `niveauxAnimations`, `stylesIcones`), `Apparence.libelle(_:)` (« Plus Jakarta Sans », « Comme le texte »…), `ecransVisibles`, `estVisible(_:)`, `normalisee()`. Pour un écran de réglage : modifier une copie, puis `enregistrerApparence(copie)`.
- `Reglages` : `activite` (ce que la personne photographie ; « photographe de mariage » si le moteur ne la donne pas ; renvoyée par `enregistrer-reglages`), `Reglages.activitesSuggerees` (« photographe de mariage », « photographe portrait et famille », « photographe de mode et éditorial », « photographe de voyage et de paysage » ; la personne peut écrire la sienne), `champsACompleter` (noms des champs du profil vides ou « [À COMPLÉTER … » : `nom`, `compte_instagram`, `activite`, `localisation`, `voix`, `langue`, puis `approche` seulement si elle contient encore le repère, car elle peut rester vide), `profilComplet` ; `planification` (lecture seule, jamais renvoyée : passer par `planifier(activer:)`), `claude` (`ReglagesClaude` : `modele`, `effort` ; renvoyée par `enregistrer-reglages` si présente ; `ReglagesClaude.efforts`, `libelleEffort(_:)`) et `creation` (`ReglagesCreation` : `etapes_a_valider` ; renvoyée si présente ; `ReglagesCreation.etapes`, `libelle(_:)`, `symbole(_:)`). Pour les cocher : modifier `reglages.creation`, puis `envoyer(reglages, action: "enregistrer-reglages")`.
- `MediaPost` (dans `Post.medias`) gagne `photo_id` et `fond` (facultatifs). `Musique` est maintenant `Codable` (+ `audio_id`, `requete`, `volume_musique`, `volume_video` ; `Musique.modes`, `libelleMode(_:)`).
- `MediaModifie` (`photo_id`, `presentation` : `plein_cadre|marges`, `fond` : `clair|sombre|papier`, `texte_alternatif` ; seuls les champs non nuls partent), `ModificationPost`, `ReponseModificationPost` (`etat`, `changements`, `controle`, `avertissements`), `ControlePost` (`conforme`, `erreurs`, `avertissements`, `alertes`, `caracteres`).
- `PhotoCandidate` : `id`, `note`, `pilier`, `description`, `orientation`, `vignette` (chemin absolu ou nil) ; `urlVignette`, `paysage`, `etoiles`.
- `PisteMusique` : `audio_id`, `titre`, `artiste`, `duree_s`, `apercu_url`, `lien_instagram`, `pochette` ; `musique(volumeVideo:)`.
- `InstagramEtat` : `etat` (`valide|absent|invalide`), `route`, `compte`, `abonnes`, `expire_le`, `erreur` ; `connecte`, `absent`, `libelle` (« Connecté à @atelier · 1 240 abonnés »), `joursRestants`. `IdentifiantsInstagram`, `ReponseInstagram` : internes à `EtatApp`.
- `ListeSouple<T>` : liste JSON dont les éléments illisibles sont ignorés.
- `Idee.brief` (une phrase, facultatif) et `briefAffiche` (`brief`, sinon `pitch`, sinon `titre`).
- `SourcePhotos` (`type` : `fichiers|dossier|pictime`, `fichiers`, `chemin`, `url`, `nom`), `ReponseSource` (`etat` : `ajoutee|refuse|echec`, `id`, `photos`, `erreurs`), `ReponseExport` (`etat`, `dossier`, `fichiers`) : internes à `EtatApp`.
- `champACompleter(_ valeur: String?) -> Bool` (fonction libre) : vrai si la valeur est vide ou contient « [À COMPLÉTER » (modèle vierge de `config/compte.yaml`).
- `appeler(_:_:)` demande un type `Decodable & Sendable` (une structure de valeurs l'est d'office).
- `InvitationClaude` : `action` (`.installer|.connecter`), `texte`, `libelleBouton`, `symbole`.

### 7.4 Enchaînements et surveillance

- **Décisions** : après `decider("choix"|"libre")` réussi, si `claude_attend` est faux, l'app lance `.creation` pour ce jour ; après `decider("retouche", texte)`, elle lance `.retouche` avec ce texte comme consigne. Si une session de Claude attend déjà la décision (`claude_attend`), elle ne lance rien : c'est cette session qui continue. Si Claude n'est pas connecté, rien n'est lancé : la décision reste enregistrée, `invitationClaude` mène à la connexion et le message le dit.
- **Minuteur de fond (1,5 s)** : seulement des dates de modification ; un fichier n'est relu que s'il a changé. Pointeur du dossier ; `.ui/demande.json` (écran demandé par le moteur ou Claude, montré avec animation, l'app passe au premier plan si demandé) ; fichiers du jour affiché (`etat.json`, `idees.json`, `post.json` → vue et liste des jours ; `decision.json` seul → vue du jour ; demandes regroupées : un seul chargement à la fois, un seul de plus s'il en arrive pendant) ; `.ui/claude/actuel.json` (nouvelle exécution, lancée aussi par la planification → `chargerExecution()`) ; date de `config/app.yaml` (→ `chargerApparence()` : une personnalisation faite par Claude s'affiche aussitôt).
- **Suivi rapide (0,7 s)**, actif seulement pendant une exécution en attente ou en cours : l'app relit `.ui/claude/<id>.json` dès qu'il change ; sans nouvelles depuis 10 s, elle demande `./studio claude etat --id` (le moteur repère une exécution interrompue).
- **Fin d'une exécution suivie** (vue en cours par l'app) : `message` = résumé de Claude (ou `erreur` ; « plus connecté » devient une invitation à se connecter), rechargement du jour (et des galeries, de la mémoire, ou des réglages et de l'apparence selon la tâche), puis l'écran `ecran_suivant` avec `animationEcran`, sur le jour de l'exécution (tâches du jour). Après `idees` réussie, le moteur donne `creation` : les trois nouvelles cartes s'affichent. Après `charte`, l'écran `charte` (charte rechargée). Après `creation` ou `retouche` réussie, le moteur donne `creation` : l'assistant continue à l'étape suivante (photos, légende, musique selon `etapesAValider`, puis aperçu) ; `versionImages` augmente. `demande` ne change pas d'écran. Une exécution déjà finie au lancement de l'app ne déplace rien.

### 7.5 Conseils pour les écrans

- Bandeau : `invitationClaude` (avec son bouton) d'abord, sinon `erreur`, sinon `message`.
- Panneau d'avancement : visible quand `etat.execution?.enCours == true` ; titre `titreAffiche`, étapes avec `symbole` et `texte` (la dernière non faite est l'étape courante), `message` de Claude, durée dans un `TimelineView(.periodic(from: .now, by: 1))` avec `libelleDuree(a:)`, bouton « Arrêter » → `annulerClaude()`. Une fois finie : `resultat` ou `erreur`.
- Connexion : bouton « Se connecter » → `connecterClaude()` ; pendant `connexionEnCours`, montrer l'attente, le lien de secours si `lienConnexion` (« Rouvrir la page de connexion » → `ouvrirLienConnexion()`) et « Annuler » → `arreterConnexion()`. Si `codeConnexionAttendu` : un champ **sécurisé** (`SecureField`) « Colle le code affiché par la page », validé par Entrée ou un bouton « Valider » → `Task { await etat.envoyerCodeConnexion(code) }`, désactivés pendant `envoiCodeEnCours` (avec un `ProgressView`) ; vider le champ après l'envoi.
- Boutons qui lancent Claude : désactivés pendant `lancementEnCours` ou `claudeTravaille`.
- Icônes : `Ecran.symbole`, `TacheClaude.symbole`, `EtapeClaude.symbole`, `TachePlanifiee.symbole`, `InvitationClaude.symbole` (tous disponibles sur macOS 14).
- Animations : `withAnimation(etat.animationEcran)` pour suivre le réglage « animations » de l'apparence.
- Assistant de création : une étape à la fois, pas de bouton « Passer ». Étapes `photos`, `legende`, `musique` : à montrer pour validation si `etat.doitValider(étape)`, sinon passées toutes seules ; l'aperçu se valide toujours (`decider("approuver", …)`). Photos : partir de `etat.mediasDuPost`, ajouter depuis `candidats(serie: vue.post.serie)`, réordonner par glisser-déposer, valider → `modifierPost(medias:)`. Légende : `TextEditor` sur `vue.post.legende`, valider → `modifierPost(legende:)` ; le contrôle refait s'affiche avec `vue.verdict`. Boutons désactivés pendant `modificationEnCours`. Images du post : `.id(etat.versionImages)`.
- Instagram : identifiant de l'app en champ normal ; clé secrète et jeton en **`SecureField`** ; bouton « Connecter » désactivé pendant `connexionInstagramEnCours` ; vider les champs secrets après l'envoi, qu'il réussisse ou non. Ne jamais afficher ni copier ces valeurs ailleurs.
