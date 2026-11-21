# Studio Instagram 2.0 — design de l'app Mac (version 2)

**Direction retenue : « Lumière douce ».** L'app est une grande page claire posée sur un dégradé vivant : des taches de couleur de son ambiance (abricot et lavande en Provence) dérivent très lentement sous une fine trame de points. À gauche, une barre d'icônes rondes avec le « + » sombre en haut ; au centre, de gros titres légers et serrés en Plus Jakarta Sans, des cartes blanches très douces, des boutons en pilules sombres avec icône ; en bas de l'accueil, la barre « Demande à Claude ». L'onboarding et la création d'un post se font plein écran, une étape à la fois, sans boîte.

Ce document remplace la version « papier » (éditoriale). `Theme.swift` et `Style.swift` l'implémentent : les noms Swift cités ici existent et compilent (macOS 14, SDK 26.5 et 27.0). Sources : `conception/choix-de-la-photographe.md` (QCM du 20/11, qui gagne en cas de doute), `conception/inspiration-style.png` (image 2) et `conception/inspiration-onboarding.png` (image 1).

## 0. Ce qui change en version 2

| Avant (v1, papier) | Maintenant (v2) | Pourquoi |
|---|---|---|
| Papier uni et grain argentique | `FondAmbiance` : dégradé de quatre taches qui dérivent + trame de points (`ambiance`, `points`) | Elle aime les « dégradés dynamiques avec des points » de l'image 2 |
| Titres New York, interface SF Pro | Plus Jakarta Sans partout (fichier variable 200–800) ; `titres: serif` reste possible | Choix 12 : la police de l'image 2 |
| Bouton principal rectangle olive | Grande pilule d'encre avec icône (`BoutonPrincipal`, `BoutonPilule`) | Choix 13 : « Deep Research » |
| Sommaire natif à gauche | `BarreIcones` : icônes rondes, « + » sombre en haut, nom au survol | Choix 8 et 11 |
| Cartes à filet sur papier | `Carte` blanche à 80 %, liseré de verre, ombre colorée diffuse, rayon 22 | Cartes de l'image 2 |
| Panneau Claude seul (⌘K) | `BarreDemandeClaude` en bas d'Aujourd'hui (champ + raccourcis en pilules) ; le panneau reste pour la conversation | Choix 14 |
| Bienvenue en deux colonnes | `PageOnboarding` plein écran, sans carte, points en bas, sans « Passer » | Choix 1, 2, 4 |
| Création par l'écran Idées | `EtapeAssistant` : idée → Claude → photos → légende → musique → aperçu | Choix 5 |
| Surtitres en CAPITALES espacées | Petits libellés en casse normale, semi-gras | Plus calme, comme l'image 2 |

Ce qui reste : un seul bouton principal par écran, « à qui le tour », la voix de Claude, le dévoilement progressif, l'accessibilité, les textes simples, l'iconographie SF Symbols, `sparkles` réservé à Claude, le téléphone Instagram fidèle.

## 1. Principes

1. **La lumière d'abord.** Le fond est vivant mais lent : on doit le sentir, pas le regarder. Les seules couleurs vives restent ses photos ; l'interface est blanche, encre et ambiance. Les photos ont des coins presque droits (`rayons.photo`) et ne sont jamais recouvertes de texte (sauf le voile bas du Reel).
2. **Une page, une décision.** Un seul `BoutonPrincipal` (grande pilule d'encre) par écran, relié à ⏎ (`.keyboardShortcut(.defaultAction)`). Le reste : pilules claires, pilules petites, liens discrets.
3. **À qui le tour.** La journée alterne Claude, toi, Claude, toi, puis le studio. Chaque état dit en une phrase s'il faut agir ou si on peut fermer l'app. Dans l'assistant, un point « à toi » (`aToi`) marque les étapes qu'elle valide.
4. **La typographie fait la hiérarchie.** Gros titres légers et serrés, texte calme, libellés semi-gras ; aucun cadre inutile : du blanc et des cartes douces.
5. **Claude travaille sous ses yeux.** Ce qu'il fait s'affiche dans l'app, en phrases simples, dans la voix de Claude (italique de Jakarta). Elle lui parle depuis l'accueil (`BarreDemandeClaude`) ou le panneau (⌘K).
6. **Une étape à la fois.** Onboarding et création d'un post : plein écran, une question par page, retour possible, jamais de « Passer ».
7. **Natif, accessible, réversible.** Clavier partout, VoiceOver, contrastes de 4,5:1 au moins (calculés et garantis par `assurer`). « Réduire les animations » fige le fond, « Augmenter le contraste » retire la trame et renforce les filets, « Réduire la transparence » rend les cartes opaques. Tout changement d'apparence s'annule d'un clic.

## 2. Jetons

Tous les jetons sont calculés par `Jetons(apparence:schema:systeme:)` à partir de `config/app.yaml` (type `Apparence`) : `ambiance`, `points`, `police`, `titres`, `mode`, `couleurs`, `densite`, `arrondi`, `animations`, `icones`, `ecrans`. Aucune couleur n'est écrite en dur dans un écran.

### 2.1 Ambiances et couleurs

Chaque ambiance (`Ambiance`, clé `ambiance`) fixe, pour le clair et le sombre : le **fond** uni, quatre **taches** (haut gauche, haut droite, bas droite, bas gauche au repos), l'**encre** (texte, pilules sombres, « + » ; claire en mode sombre : les pilules s'inversent), l'**accent** (sélection, liens, progression, badges), l'**accent doux** et la couleur de la **trame**. Valeurs exactes (contraste WCAG sur le fond entre parenthèses) :

| Ambiance | Taches (1 · 2 · 3 · 4) | Fond | Carte opaque | Texte = encre | Texte secondaire | Pilule sombre / texte dessus | Accent | Accent doux | Trame |
|---|---|---|---|---|---|---|---|---|---|
| **provence** clair (défaut) | #f5c39c abricot · #d2c6f0 lavande · #f7e1b8 blé · #c6d6bd sauge | #f6f1eb | #fefefd | #22201c (14,5) | #6f6c67 (4,7) | #22201c / #fefdfc (16,0) | #5b6236 olive (5,8) | #f1dccb | #3a2f25 |
| provence sombre | #7a4124 · #40356e · #5f4920 · #2c4331 | #16130f | #272521 | #f4eee6 (16,1) | #9b9690 (6,3) | #f4eee6 / #16130f (16,1) | #c9cf9c (11,4) | #f1dccb | #ffffff |
| **lavande** clair (image 2) | #b5bdef pervenche · #d9cdf6 lavande · #f8d9c4 lueur pêche · #c2dbf8 ciel | #eff0f8 | #fdfefe | #1b1c2c (14,8) | #686975 (4,8) | #1b1c2c / #fdfdfe (16,5) | #4c4fa6 (6,2) | #e4e1f6 | #2a2d55 |
| lavande sombre | #2b3580 · #47307f · #633b42 · #1c4375 | #0f1020 | #212231 | #eef0fa (16,6) | #9596a3 (6,4) | #eef0fa / #0f1020 (16,6) | #aeb2f2 (9,4) | #e4e1f6 | #ffffff |
| **aube** clair | #f7bba5 corail · #f9d79c or · #ebbfd9 rose · #c8d8f1 bleu pâle | #faf1ed | #fffefd | #261b1c (15,0) | #756c6b (4,6) | #261b1c / #fefdfc (16,5) | #b0533a terre cuite (4,6) | #f7dfd3 | #4a2a22 |
| aube sombre | #7c3329 · #744f1b · #632a55 · #21365e | #18100f | #292221 | #f8ece6 (16,2) | #9e9490 (6,3) | #f8ece6 / #18100f (16,2) | #f0a487 (9,3) | #f7dfd3 | #ffffff |
| **sauge** clair | #bfd6b8 sauge · #e3eac6 tilleul · #c8e1dc eucalyptus · #f0e0c8 lin | #f0f3ed | #fefefd | #1b221d (14,5) | #696e69 (4,7) | #1b221d / #fdfdfc (16,0) | #3e6a4c (5,6) | #dfe9d8 | #22352a |
| sauge sombre | #2d4d35 · #454f24 · #1e4842 · #50412a | #0f1411 | #212623 | #edf3ec (16,5) | #949a94 (6,5) | #edf3ec / #0f1411 (16,5) | #a3cdb0 (10,6) | #dfe9d8 | #ffffff |
| **nuit** clair | #a5aee4 · #c4b1e9 · #9ec4e8 · #e8c3d7 | #e9eaf4 | #fdfdfe | #13152a (15,0) | #666877 (4,6) | #13152a / #fcfcfd (17,5) | #3d43a0 (7,0) | #dcdcf3 | #1c2050 |
| nuit sombre | #1f2e7a · #3f206e · #0d4566 · #511f4b | #0a0b16 | #1c1d27 | #eceefb (17,0) | #92939f (6,4) | #eceefb / #0a0b16 (17,0) | #9ea6f5 (8,6) | #dcdcf3 | #ffffff |

**Surfaces** (calculées, `m(a, b, t)` = mélange) :

| Jeton Swift | Clair | Sombre | Usage |
|---|---|---|---|
| `remplissageCarte` | blanc à 80 % (opaque `carte` si transparence réduite ou contraste augmenté) | blanc à 7 % | cartes, pilules claires, boutons ronds clairs |
| `carte` | m(fond, blanc, .90) | m(fond, blanc, .075) | version opaque |
| `carteBord` | blanc (m(fond, texte, .30) si contraste augmenté) | m(fond, blanc, .13) | bord de verre |
| `surface` | m(fond, blanc, .72) | m(fond, blanc, .05) | zones calmes |
| `surfaceElevee` | blanc | m(fond, blanc, .10) | champs, popovers, survol des pilules claires |
| `texte` = `encre` | encre, assurer 12:1 (15 si contraste) | idem | texte, pilules sombres, « + » |
| `encreSurvol` | m(encre, blanc, .16) | m(encre, noir, .10) | survol des pilules sombres |
| `surEncre` | m(fond, blanc, .85) | fond | texte d'une pilule sombre |
| `texteSecondaire` | m(texte, fond, .42), assurer 4,6 | m(texte, fond, .40), assurer 4,6 | chapô, légendes, libellés |
| `texteTertiaire` | m(texte, fond, .58) | idem | désactivé seulement |
| `trait`, `traitFort` | m(fond, texte, .10 / .20) | m(fond, texte, .13 / .24) | filets, bord des champs |
| `accent`, `accentSurvol`, `accentTexte`, `surAccent` | accent assuré 4,5:1 ; survol −15 % ; liens ; texte sur accent (blanc ou encre) | idem, survol +15 % | sélection, liens, badges, progression |
| `accentDoux`, `fondDoux`, `aToi` | accent doux ; m(m(fond, doux, .62), blanc, .25) ; tsl(doux, .36) assuré 4,5 sur fondDoux | doux ; m(fond, doux, .14) ; doux | pastilles douces, bulles, « à toi » |
| `succes`, `alerte`, `fondSucces`, `fondAlerte` | `couleurs.succes`/`alerte` assurées 4,5 ; fonds à 10 % sur fond éclairci | tsl(.62 / .64) ; fonds à 14 % | états |
| `selection` | m(fond, accent, .10) | m(fond, accent, .16) | survol de lignes, liens |
| `trame`, `taches` | de l'ambiance | idem | `FondAmbiance` |

Règles :

- **Les couleurs de `couleurs:`** (config/app.yaml) restent prioritaires : `accent`, `accent_doux`, `fond_clair`, `fond_sombre` remplacent celles de l'ambiance **seulement si elles ont été changées** (différentes des valeurs d'origine #3d4130, #efdccd, #f7f3ed, #17160f). `succes` et `alerte` viennent toujours de `couleurs:`. Ainsi « passe le bleu en terracotta » marche, et changer d'ambiance change tout le reste.
- Garde-fou de Réglages › Apparence : `Jetons.accentPeuLisible` (accent < 3:1 sur le fond) → « Cette couleur est peu lisible sur le fond. L'app utilisera le texte pour les liens. »
- Sur un fond teinté (`fondDoux`, `fondSucces`, `fondAlerte`), le texte reste `texte` ; seule l'icône prend la couleur d'état. Toujours un mot avec une couleur, jamais la couleur seule.
- **Augmenter le contraste** : trame retirée, taches à 35 %, `trait` et `traitFort` renforcés, `texteSecondaire` m(texte, fond, .22), cartes opaques avec bord `traitFort`, accent assuré 7:1.
- **Réduire la transparence** : `remplissageCarte` = `carte` opaque, pas de matériau sous les surfaces flottantes, `PanneauPage` opaque.
- Le téléphone de l'Aperçu garde les couleurs d'Instagram (`CouleursInstagram`, inchangées).

**Dans Réglages › Apparence**, chaque ambiance se montre en vignette (un mini `FondAmbiance` figé de 120 × 80, rayon `carte`, nom et `Ambiance.description` dessous) : « Abricot, lavande et blé, comme un soir d'été. », « Pervenche et lavande, une lueur pêche. », « Corail, or et rose, le ciel du matin. », « Sauge, tilleul et lin, très calme. », « Indigo et violet, une lumière de soirée. ».

### 2.2 Fond animé et matières

- **`FondAmbiance`** (`.fondAmbiance()`) : `fond` uni, puis les quatre taches en dégradés radiaux (pas de flou : léger pour le processeur), rayon 54 à 66 % du grand côté, opacité 92 % (clair) ou 78 % (sombre), avec un dégradé en quatre paliers (1 · 0,72 à 32 % · 0,28 à 62 % · 0). En clair, une **lueur blanche** au centre (75 % → 0, rayon 42 %) garde le cœur de la page lumineux, comme l'image 2.
- **Dérive** : chaque tache suit une courbe de Lissajous lente (±10 % en x, ±8 % en y, rayon qui respire de ±6 %), un tour en **90 s** (`periodeDerive`, 60 s en `riches`), redessinée à 15 images/s par `TimelineView(.animation(minimumInterval: 1/15))`, **en pause** quand la fenêtre n'est pas au premier plan (`controlActiveState == .inactive`). **Figé** (`Jetons.fondFige`) si `animations: aucune` ou « Réduire les animations » ; `FondAmbiance(anime: false)` le fige aussi (vignettes, panneau).
- **Trame de points** (`TrameDePoints`, si `points: true` et contraste normal) : points de 1,5 pt tous les 15 pt, couleur `trame` à 20 % (clair) ou 13 % (sombre), masquée par un dégradé radial (25 % au centre, 100 % sur les bords) : plus présente sur les bords, sur la couleur.
- **La page** (`PanneauPage`) : grand verre blanc posé sur le dégradé, dégradé diagonal blanc 72 % → 42 % (sombre : 6 % → 2,5 %), liseré blanc 65 %, rayon `feuille` + 8, ombre `.carte`. La barre d'icônes reste dehors, sur le dégradé.
- **Cartes** : `remplissageCarte` + `LisereHaut` (bord de verre blanc, 70 % en haut → 0 au milieu ; 9 % en sombre) + ombre `.carte`.
- **Ce qui flotte** (bandeau, capsule de Claude, barre collante) : `FondFlottant` = `.ultraThinMaterial` + `remplissageCarte` (opaque si la transparence est réduite).
- **Barre d'outils** : transparente, sans titre ; la fenêtre est en `.hiddenTitleBar`, le dégradé va jusqu'en haut.

### 2.3 Typographie : Plus Jakarta Sans

Fichiers : `app/Ressources/Polices/PlusJakartaSans.ttf` (romaine variable) et `PlusJakartaSans-Italic.ttf`, licence OFL (`OFL.txt`). `construire.sh` les copie dans le paquet et règle `ATSApplicationFontsPath` ; `Theme.init` appelle en plus `Typographie.enregistrerPolices()` (`CTFontManagerRegisterFontsForURL`, portée `.process`), par sécurité. Les graisses sont prises **sur l'axe variable `wght`** (200 à 800) par `Typographie.ctFont(taille:graisse:italique:)` : on peut demander 330 ou 360, pas seulement les crans. Si la police manque (`Typographie.jakartaDisponible == false`), repli sur SF Pro à la graisse la plus proche.

Clés de config/app.yaml :

| Clé | Valeurs | Effet |
|---|---|---|
| `police` | `jakarta` (défaut) · `systeme` (SF Pro) · `arrondie` (SF Rounded, +40 de graisse) | tout le texte |
| `titres` | `police` (défaut : la même) · `serif` (New York) · `arrondi` · `standard` (SF Pro) | affiche, titres 1–3, chiffres, numéros |

Rôles (`RoleTexte`), densité **confortable** (×0,92 compacte, ×1,08 aérée, arrondi au demi-point, jamais sous 11 pt) :

| Rôle | Taille | Graisse (axe) | Approche | Interligne ajouté | Couleur | Usage |
|---|---|---|---|---|---|---|
| `.affiche` | 54 | 330 | −3,2 % (−1,7 pt) | 0 | texte | accueil, onboarding |
| `.titre1` | 36 | 360 | −2,6 % | 0 | texte | titres d'écran, de l'assistant |
| `.titre2` | 25 | 430 | −1,8 % | 0 | texte | idées, galeries, états vides |
| `.titre3` | 18 | 580 | −0,6 % | 0 | texte | cartes, sections |
| `.voix` | 17 | 400 italique | 0 | +5 | texte | Claude, salutation |
| `.voixCarte` | 15 | 400 italique | 0 | +3 + densité/2 | texte | étapes de Claude |
| `.reponse` | 15 | 400 | 0 | +3 + densité/2 | texte | réponses de Claude |
| `.chiffre` | 40 | 300, chiffres tabulaires | −3 % | 0 | texte | statistiques |
| `.numero` | 44 | 260 | −3 % | 0 | accentTexte | « 1 », « 2 », « 3 » |
| `.chapo` | 16 | 400 | 0 | +6 | texteSecondaire | phrase sous un titre |
| `.corps` | 14 | 400 | 0 | densité + 1 | texte | texte courant (police par défaut de la fenêtre) |
| `.corpsFort` | 14 | 600 | 0 | densité + 1 | texte | libellés |
| `.legende` | 12 | 450 | 0 | +2 | texteSecondaire | dates, aides |
| `.surtitre` | 12 | 600, **casse normale** | +0,2 | 0 | texteSecondaire | petit libellé au-dessus d'un titre |
| `.bouton` | 14 | 600 | 0 | 0 | — | grandes pilules |
| `.boutonSecondaire` | 13,5 | 520 | 0 | 0 | — | pilules normales et petites, liens |
| `.champ` | 15 | 400 | 0 | densité + 1 | texte | ce qu'elle écrit |
| `.mono` | 12 | SF Mono | 0 | 0 | texteSecondaire | journal d'installation |

Gros titres **légers et serrés**, texte calme : jamais de gras au-dessus de 24 pt. Titre en deux tons (`TitreDeuxTons`) : le début en `texteSecondaire`, la suite en `texte` (« Bonjour Gabriella, trois idées t'attendent. »). Lignes de texte : `esp.largeurTexte` au plus. `Text("…").typo(.titre1)` applique police, approche, interligne et couleur ; `j.police(.corps)` rend la seule `Font` ; `Font.jakarta(13, graisse: 600)` pour un cas particulier (pastilles, badges).

### 2.4 Espacements (`Espacements`, selon `densite`)

| Jeton | compacte | confortable | aérée |
|---|---|---|---|
| `page` (marge de page) | 28 | 44 | 60 |
| `sections` | 32 | 44 | 60 |
| `blocs` | 12 | 16 | 24 |
| `carte` (intérieur des cartes) | 18 | 24 | 30 |
| `gouttiere` (grilles) | 14 | 18 | 26 |
| `pile` | 6 | 8 | 12 |
| `ligne` | 30 | 34 | 40 |
| `hauteurBouton` (pilule normale ; petite −10, grande +8) | 34 | 40 | 46 |
| `icone` (boutons ronds de la barre ; « + » +4) | 38 | 42 | 46 |
| `interligne` (ajouté au corps) | 2 | 4 | 6 |
| `largeurTexte` | 600 | 620 | 640 |
| `largeurPage` | 1180 | 1180 | 1180 |
| `controle` (`ControlSize`) | `.small` | `.regular` | `.large` |

### 2.5 Rayons (`Rayons`, à partir de `arrondi` = r, 14 par défaut, toujours `.continuous`)

| Jeton | Règle | r = 14 |
|---|---|---|
| `carte` | min(32, 1,6 r) | 22 |
| `feuille` (héros, feuilles, popovers ; page = feuille + 8) | min(40, 2 r) | 28 |
| `pilule` = `bouton` (pilules, boutons ronds, icônes de la barre, champ d'une ligne) | 999 (capsule) si r ≥ 6, sinon r | capsule |
| `champ` (champs de plusieurs lignes, barre Claude ; cadre extérieur + 8) | min(26, 1,6 r) | 22 |
| `photo` | min(12, 0,6 r) | 8 |
| `vignette` (grille du feed) | min(4, 0,3 r) | 4 |
| `telephone`, `ecranTelephone` | fixes | 54, 44 |

Avec `arrondi: 0`, tout est droit, pilules comprises : c'est son choix. `RoundedRectangle(cornerRadius: j.rayons.pilule)` devient une capsule (SwiftUI ramène le rayon à la demi-hauteur).

### 2.6 Ombres (`NiveauOmbre`, modificateur `.ombre(_:)`)

En clair, l'ombre est **colorée** : m(encre, première tache, .35), jamais grise.

| Niveau | Usage | Clair | Sombre |
|---|---|---|---|
| `.repos` | rien | aucune | aucune |
| `.carte` | cartes, page, barre Claude, icône choisie, étape en cours | 3,5 % r 1 y 1 + 7 % r 28 y 12 | noir 30 % + 30 % |
| `.survol` | carte cliquable survolée (en plus) | 5 % r 2 y 1 + 12 % r 34 y 18 | noir 35 % + 45 % |
| `.flottante` | bandeau, bulle de survol, héros, popovers | 5 % r 1 y 1 + 14 % r 30 y 14 | noir 45 % + 40 % |
| `.feuille` | téléphone, feuilles | 18 % r 40 y 22 | noir 55 % |

### 2.7 Mouvement

Toute animation passe par `j.anim(_ m: Mouvement) -> Animation?` (`nil` au niveau `aucune`). Le niveau effectif `j.niveau` est celui d'`animations`, plafonné à `discretes` si « Réduire les animations » est actif ; alors `j.deplacements == false` et `j.transition(_:)` ne rend que des fondus.

| `Mouvement` | discrètes | normales | riches | Usage |
|---|---|---|---|---|
| `.appui` | — | spring(0,22 ; 0,75), échelle 0,97 (ronds 0,94) | idem | pilules, ronds |
| `.survol` | easeOut 0,12 | easeOut 0,18 | idem | bulle, pilules, cartes |
| `.selection` | easeInOut 0,2 | spring(0,35 ; 0,80) | idem | barre d'icônes, points, rappel des étapes, cartes choisies |
| `.doux` | easeInOut 0,2 | spring(0,40 ; 0,86) | idem | panneaux |
| `.page` | easeInOut 0,2 | spring(0,52 ; 0,92) | spring(0,62 ; 0,88) | écran, étape d'onboarding ou de l'assistant |
| `.cascade` | — | spring(0,45 ; 0,85), 40 ms (70 ms dans l'onboarding) | idem | premier affichage |
| `.bandeau`, `.etape`, `.frise`, `.carrousel`, `.compteur`, `.revelation`, `.celebration`, `.pulsation` | comme v1 | comme v1 | comme v1 | — |
| `.theme` | easeInOut 0,25 | easeInOut 0,45 | easeInOut 0,6 | changement d'apparence ou d'ambiance |

`TransitionStudio` : `.ecran` (fondu + montée de 10 pt), `.bandeau`, `.etape`, `.apparition`, `.panneau`, et **`.suivante` / `.precedente`** (glissement de 48 pt + fondu, vers la gauche ou la droite) pour l'onboarding et l'assistant. Fond : voir §2.2 (dérive sans `Animation`, figée selon `fondFige`). Symboles : seulement ceux de macOS 14 (`.pulse`, `.bounce`, `.variableColor`, `.replace`…) ; jamais `MeshGradient`.

## 3. API Swift

Contraintes : macOS 14, compilé par `swiftc` sans Xcode. Pas de macros : `@Local` (alias de `State`), pas de `#Preview`, `@Entry`, `@Observable`, `@Animatable`. Clés d'environnement écrites à la main.

### 3.1 Theme (`Theme.swift`)

```swift
@MainActor final class Theme: ObservableObject {           // @dynamicMemberLookup sur Jetons
    static let partage: Theme                                // init : Typographie.enregistrerPolices()
    @Published private(set) var apparence: Apparence
    @Published private(set) var jetons: Jetons               // pour le schéma effectif
    @Published private(set) var systeme: OptionsSysteme
    var mode: ModeApparence; var schemaForce: ColorScheme?; var schema: ColorScheme
    func appliquer(_ a: Apparence)                           // normalise, fondu .theme, NSApp.appearance
    func suivre(_ etat: EtatApp)                             // applique etat.apparence à chaque changement
    func jetons(pour schema: ColorScheme, apparence: Apparence? = nil) -> Jetons   // aperçus
}

@dynamicMemberLookup struct Jetons: Equatable {             // @Environment(\.jetons) private var j
    let apparence: Apparence; let schema: ColorScheme; let systeme: OptionsSysteme
    let couleurs: Palette                                    // j.encre, j.fond, j.taches… (dynamicMember)
    let mode: ModeApparence; let ambiance: Ambiance; let police: PoliceTexte; let titres: StyleTitres
    let densite: Densite; let niveauDemande: NiveauAnimations; let niveau: NiveauAnimations
    let esp: Espacements; let rayons: Rayons
    let trameActive: Bool                                    // points: true et contraste normal
    var fondFige: Bool; var periodeDerive: Double; var opaciteTaches: Double; var opaciteTrame: Double
    var remplissageCarte: Color                              // blanc 80 % / 7 %, opaque si besoin
    var echelle: CGFloat; var deplacements: Bool; var accentPeuLisible: Bool
    var materiauFlottant: AnyShapeStyle; var varianteSymboles: SymbolVariants
    var opaciteGrain: Double                                 // compatibilité : toujours 0
    func police(_ r: RoleTexte) -> Font; func taille(_ r: RoleTexte) -> CGFloat; func graisse(_ r: RoleTexte) -> CGFloat
    func approche(_ r: RoleTexte) -> CGFloat; func interligne(_ r: RoleTexte) -> CGFloat; func couleurParDefaut(_ r: RoleTexte) -> Color
    func anim(_ m: Mouvement) -> Animation?; func delaiCascade(_ index: Int, pas: Double = 0.04) -> Double
    func transition(_ t: TransitionStudio) -> AnyTransition; func ombres(_ n: NiveauOmbre) -> [Ombre]
    static func defaut(_ schema: ColorScheme = .light) -> Jetons
}

struct Palette: Equatable   // Color : fond, surface, surfaceElevee, texte, texteSecondaire, texteTertiaire, trait, traitFort,
                            // accent, accentSurvol, accentTexte, surAccent, accentDoux, fondDoux, aToi,
                            // succes, alerte, fondSucces, fondAlerte, selection,
                            // encre, encreSurvol, surEncre, carte, carteBord, trame ; taches: [Color] ; rvb: PaletteRVB
struct PaletteRVB           // les mêmes en RVB ; init(apparence: Apparence, sombre: Bool, contraste: Bool)
enum Ambiance: String, CaseIterable, Identifiable { provence, lavande, aube, sauge, nuit
    init(_ texte: String); var nom: String; var description: String
    func definition(sombre: Bool) -> DefinitionAmbiance }   // fond, taches[4], encre, accent, accentDoux, trame (RVB)
enum PoliceTexte { jakarta, systeme, arrondie }      enum StyleTitres { police, serif, arrondi, standard }
enum ModeApparence { auto, clair, sombre }           enum Densite { compacte, confortable, aeree }
enum NiveauAnimations: Comparable { aucune, discretes, normales, riches }
enum RoleTexte { affiche, titre1, titre2, titre3, voix, voixCarte, reponse, chiffre, numero,
                 chapo, corps, corpsFort, legende, surtitre, bouton, boutonSecondaire, champ, mono }
enum Mouvement { appui, survol, selection, doux, page, cascade, bandeau, etape, frise, carrousel, compteur,
                 theme, revelation, celebration, pulsation }
enum TransitionStudio { ecran, bandeau, etape, apparition, panneau, suivante, precedente }
enum NiveauOmbre { repos, carte, survol, flottante, feuille }
struct Espacements { page, sections, blocs, carte, gouttiere, pile, ligne, hauteurBouton, icone, interligne,
                     largeurTexte, largeurPage: CGFloat; controle: ControlSize }
struct Rayons { carte, feuille, bouton, pilule, champ, photo, vignette, telephone, ecranTelephone: CGFloat }

enum Typographie {
    static let famille = "Plus Jakarta Sans"
    static func enregistrerPolices(dossier: URL? = nil)      // paquet (Resources/Polices) ou dossier donné
    static var jakartaDisponible: Bool
    static func ctFont(taille: CGFloat, graisse: CGFloat, italique: Bool) -> CTFont   // axe wght 200–800, cache
    static func jakarta(_ taille: CGFloat, graisse: CGFloat, italique: Bool = false) -> Font
    static func graisseSysteme(_ g: CGFloat) -> Font.Weight
}
func lireOui(_ v: Bool | Bool? | String | String?) -> Bool   // lecture souple de `points`

extension View {
    func themeStudio(_ theme: Theme) -> some View   // racine : jetons, environmentObject, schéma, tint, variante, police du corps
    func typo(_ role: RoleTexte, couleur: Color? = nil) -> some View
    func ombre(_ niveau: NiveauOmbre) -> some View
}
struct ApercuTheme<Contenu: View>(apparence:schema:contenu:)   // thème en brouillon (Réglages › Apparence)
struct LisereHaut(rayon: CGFloat)                               // bord de verre des surfaces
// Inchangés : RVB, OptionsSysteme, CouleursInstagram, ThemeCourant, Ombre.
```

Racine de l'app : `@StateObject private var theme = Theme.partage`, puis `VueRacine().themeStudio(theme).onAppear { theme.suivre(etat) }`. Les vues lisent `@Environment(\.jetons) private var j`. Sans injection, `\.jetons` vaut les jetons courants du thème partagé. Pour les écrans : `j.anim(.page)` + `j.transition(.ecran)` ; pour les étapes : `j.transition(.suivante)` (ou `.precedente` quand elle revient).

### 3.2 Composants (`Style.swift`)

**Nouveaux en v2**

```swift
// Fond
struct FondAmbiance: View { init(anime: Bool = true) }          // dégradé animé + trame ; .fondAmbiance(anime:)
struct TachesAmbiance: View { init(temps: Double) }             // les taches à l'instant `temps` (0 = repos)
struct TrameDePoints: View { init(pas: CGFloat = 15, diametre: CGFloat = 1.5) }
struct PanneauPage<Contenu: View>: View { init(@ViewBuilder contenu: () -> Contenu) }   // la grande page de verre

// Boutons
enum VariantePilule { sombre, claire, accent }    enum TaillePilule { petite, normale, grande }
struct BoutonPilule: ButtonStyle {
    init(_ variante: VariantePilule = .sombre, taille: TaillePilule = .normale, pleineLargeur: Bool = false, enCours: Bool = false) }
    // .buttonStyle(.pilule)  ·  .buttonStyle(.pilule(.claire, taille: .petite))
    // label avec icône : Button { … } label: { Label("Créer ce post", systemImage: "wand.and.stars") }
enum VarianteRond { sombre, claire, transparente }
struct BoutonRond: ButtonStyle { init(_ variante: VarianteRond = .claire, diametre: CGFloat = 40) }
    // .buttonStyle(.rond)  ·  .buttonStyle(.rond(.sombre, diametre: 44)) ; label : Image(systemName:)

// Barre d'icônes
struct ElementBarre<ID: Hashable>: Identifiable { init(id: ID, titre: String, symbole: String, badge: Int? = nil) }
struct BarreIcones<ID: Hashable, Pied: View>: View {
    init(elements: [ElementBarre<ID>], selection: Binding<ID>, nouveau: (() -> Void)? = nil,
         titreNouveau: String = "Créer un post", @ViewBuilder pied: () -> Pied)
    init(elements:selection:nouveau:titreNouveau:)                                   // Pied == EmptyView
    init(ecrans: [Ecran], selection: Binding<Ecran>, badges: [Ecran: Int] = [:], nouveau: (() -> Void)? = nil,
         @ViewBuilder pied: () -> Pied)                                               // ID == Ecran
    init(ecrans:selection:badges:nouveau:)                                           // ID == Ecran, Pied == EmptyView
}
struct BulleSurvol<Contenu: View>: View { init(titre: String, @ViewBuilder contenu: () -> Contenu) }

// Claude
struct RaccourciClaude: Identifiable { init(_ titre: String, symbole: String, demande: String); static let parDefaut: [RaccourciClaude] }
struct BarreDemandeClaude: View {
    init(texte: Binding<String>, exemple: String = "Demande à Claude… par exemple « une idée pour samedi »",
         raccourcis: [RaccourciClaude] = RaccourciClaude.parDefaut,
         note: String? = "Claude connaît ta charte, tes galeries et tes statistiques",
         etat: String? = nil, occupe: Bool = false, plus: (() -> Void)? = nil, envoyer: @escaping (String) -> Void)
    static func hauteur(_ j: Jetons, note: Bool = true, raccourcis: Bool = true) -> CGFloat }   // place à réserver

// Onboarding et assistant
struct PointsProgression: View { init(total: Int, courant: Int, aller: ((Int) -> Void)? = nil) }
struct PageOnboarding<Illustration: View, Contenu: View, Action: View>: View {
    init(etape: Int, total: Int, titre: String, texte: String? = nil, retour: (() -> Void)? = nil, fond: Bool = true,
         @ViewBuilder illustration: () -> Illustration, @ViewBuilder contenu: () -> Contenu, @ViewBuilder action: () -> Action)
    init(etape:total:titre:texte:retour:fond:illustration:action:)                  // Contenu == EmptyView
    static var margeFeux: CGFloat                                                    // 44 : haut libre pour les feux
}
struct EtapeCreation: Identifiable, Equatable { let id, titre, symbole: String; var aValider: Bool
    static func etapes(aValider: [String] = ["photos", "legende", "musique"]) -> [EtapeCreation] }
    // ids : idee, claude, photos, legende, musique, apercu ; idee et apercu toujours à valider, claude jamais
struct RappelEtapes: View { init(etapes: [EtapeCreation], courante: Int) }
struct EtapeAssistant<Contenu: View, Actions: View>: View {
    init(etapes: [EtapeCreation], courante: Int, titre: String, texte: String? = nil,
         retour: (() -> Void)? = nil, fermer: (() -> Void)? = nil, fond: Bool = true,
         @ViewBuilder contenu: () -> Contenu, @ViewBuilder actions: () -> Actions) }

// Texte
struct TitreDeuxTons: View { init(debut: String, suite: String, role: RoleTexte = .affiche, alignement: TextAlignment = .leading) }
extension Font { static func jakarta(_ taille: CGFloat, graisse: CGFloat = 400, italique: Bool = false) -> Font }
extension Color { static var encre: Color }                      // dynamique, comme Color.olive
```

| Composant | Comportement |
|---|---|
| `FondAmbiance` | §2.2. Toujours en fond de fenêtre, de l'onboarding et de l'assistant (`fond: true`). Ignore les clics et VoiceOver. |
| `PanneauPage` | la page de verre à droite de la barre : `HStack(spacing: 0) { BarreIcones(…).zIndex(1); PanneauPage { écran }.padding(.vertical, 16).padding(.trailing, 16) }.fondAmbiance()`. |
| `BoutonPilule` | capsule (`rayons.pilule`) ; `.sombre` : `encre`, texte `surEncre`, survol `encreSurvol` ; `.claire` : `remplissageCarte` + filet `trait`, survol blanc ; `.accent` : `accent` / `surAccent`. Hauteurs : petite `hauteurBouton − 10` (marges 13, `.boutonSecondaire`, icône petite), normale `hauteurBouton` (marges 18), grande `+ 8` (marges 24, `.bouton`). Appui ×0,97, inactif à 38 %, `enCours` : roue + « Un instant… ». |
| `BoutonPrincipal` | = pilule **sombre grande**, avec `pleineLargeur`, `enCours`, `illumine` (halo d'accent doux une fois). Un seul par écran, avec `.keyboardShortcut(.defaultAction)`. |
| `BoutonSecondaire` | = pilule **claire normale**. |
| `BoutonDiscret(fleche:)`, `BoutonDestructif` | texte `accentTexte` / `alerte`, voile `selection` au survol, capsule. Destructif toujours confirmé. |
| `BoutonRond` | disque `.sombre` (« + », envoyer, « … »), `.claire` (retour, fermer : blanc doux + filet) ou `.transparente` ; icône à 40 % du diamètre (46 % transparente) ; appui ×0,94. `BoutonIcone(diametre:)` = rond transparent (compatibilité). |
| `BarreIcones` | largeur `esp.icone + 32`, marges verticales 22. En haut, le « + » : `BoutonRond(.sombre, diametre: icone + 4)`, ⌘N, bulle « Créer un post ». Puis une icône ronde par écran (`esp.icone`, symbole à 40 %) : au repos blanc 55 % (sombre : 6 %) et icône encre à 62 % ; survol blanc 85 % ; **choisie** : blanc plein, symbole plein et semi-gras, ombre `.carte`, repère d'encre de 3 × 18 pt collé au bord gauche. Badge : capsule `accent` 17 pt, chiffre Jakarta 700 en `surAccent`, bord `fond`. ⌘1 à ⌘9 dans l'ordre. **Nom au survol** : `BulleSurvol`, capsule d'encre de 28 pt à 12 pt à droite, Jakarta 12,5/560 en `surEncre`, ombre `.flottante`, sans délai. Entrée en cascade (30 ms). À placer en `.zIndex(1)`. VoiceOver : nom, « 3 en attente », état sélectionné. |
| `BarreDemandeClaude` | cadre extérieur **givré presque opaque** (`.regularMaterial` + `carte` à 86 %, opaque si la transparence est réduite ; rayon `champ + 8`, liseré, ombre `.flottante`, marge 8) : rien ne se lit à travers. L'écran réserve sa place (`BarreDemandeClaude.hauteur(j)`, ≈ 156 pt en confortable) au lieu de la poser sur les cartes ; au-dessus, la `note` (sparkles + légende) à gauche et l'`etat` (point succès, ou accent pulsé si `occupe`) à droite ; dedans, une carte **blanche** (rayon `champ`) : champ `.champ` sur 1 à 4 lignes et `BoutonRond(.sombre, diametre: 40)` `arrow.up` (inactif si vide) ; dessous, les raccourcis en **petites pilules sombres** avec icône et « … » rond (`plus`), sur une rangée qui défile de côté si elle ne tient pas. ⏎ envoie et vide le champ ; un raccourci envoie sa `demande`. Filet du champ en encre à 50 % au focus. |
| `PointsProgression` | points de 8 pt espacés de 9 : courant plein d'encre (allongé à 20 pt si `deplacements`), autres en contour d'encre à 55 % ; étapes passées cliquables si `aller` ; « Étape 2 sur 4 » pour VoiceOver. |
| `PageOnboarding` | plein écran, **sans carte** : en haut à gauche, sous les feux tricolores (`margeFeux` = 44 pt), `BoutonRond(.claire, 38)` « Revenir » (⌘←) si `retour` ; **aucun « Passer »**. Le milieu **défile** s'il est plus haut que la fenêtre ; « ‹ » et les points restent toujours visibles. **Compact** sous 780 pt de haut : illustration 240 × 150, titre en `.titre1`, espacements réduits. Colonne centrée de 640 pt : illustration (380 × 280 au plus), espace `sections`, titre `.affiche` centré (3 lignes, réduit jusqu'à 70 %), texte `.chapo` centré 460 pt, contenu 440 pt (champs, choix), action ; points de progression en bas (34 pt du bord). Entrée en cascade à 70 ms. Changer d'étape : `.id(etape)` + `.transition(j.transition(.suivante))` dans `withAnimation(j.anim(.page))`. |
| `EtapeAssistant` | plein écran, même style : en haut (sous les feux, `margeFeux`) `RappelEtapes` centré et « × » (`BoutonRond(.claire, 36)`, Échap) à gauche ; titre `.titre1` et texte `.chapo` centrés ; contenu jusqu'à 1000 pt, à sa **hauteur naturelle**, centré, et qui **défile** s'il dépasse (jamais coupé ; un champ ne s'étire plus sur toute la hauteur : lui donner une hauteur ou `lineLimit`) ; pas de points de progression (le rappel suffit) ; en bas « Retour » (`BoutonPilule(.claire)`, `chevron.left`) à gauche, `actions` à droite (le `BoutonPrincipal`). |
| `RappelEtapes` | les six étapes reliées par des traits de 18 pt : faites (disque d'encre coché, titre secondaire), en cours (pilule blanche avec symbole et titre Jakarta 600, ombre `.carte` ; `sparkles` pulsé pour « Claude au travail »), à venir (cercle `traitFort`, titre tertiaire) ; point `aToi` de 7 pt sur celles qu'elle valide. Aide au survol : « Photos : à toi de valider » / « Musique : Claude s'en occupe ». |
| `TitreDeuxTons` | début `texteSecondaire`, suite `texte`, même police et approche, en-tête pour VoiceOver. |

**Restylés (mêmes noms, mêmes signatures qu'en v1)**

| Composant | Signature | v2 |
|---|---|---|
| Carte | `Carte(titre: String? = nil, symbole: String? = nil, style: StyleCarte = .simple, choisie: Bool = false) { … }` | `remplissageCarte`, liseré de verre, ombre `.carte`, rayon `carte`, intérieur `esp.carte` ; symbole dans un disque `fondDoux` de 34 pt ; ligne d'en-tête seulement avec `titre` ou `symbole` (sinon la coche de `choisie` se pose dans le coin, sans ligne vide) ; `.cliquable` : se soulève (+2 pt, ombre `.survol`, curseur main) ; `.heros` : rayon `feuille`, ombre `.flottante` ; `choisie` : anneau accent 2 pt, fond `fondDoux`, coche accent. |
| Pastille | `Pastille(_ texte: String, symbole: String? = nil, ton: TonPastille = .neutre)` | capsule 4 × 10, Jakarta 12/540 ; `.neutre` blanc doux + filet, `.douce`/`.aToi` `fondDoux`, `.forte` encre / `surEncre`, `.succes`/`.alerte` fond d'état. |
| En-tête d'écran | `EnTeteEcran(surTitre:titre:chapo:voixDeClaude:) { action }` | petit libellé (casse normale), Titre 1 léger, chapô ; **plus de filet** dessous. |
| État vide | `EtatVide(symbole:titre:phrase:actionTitre:action:)` | cadre à traits de coupe 96 × 120 sur un disque blanc doux de 180 pt ; action en pilule claire. |
| Champ doux | `ChampDoux(texte:exemple:lignes:envoyer:)` | blanc (sombre : `surfaceElevee`), capsule si `lignes` vaut 1…1, sinon rayon `champ` ; marges 18 × 13 ; filet `traitFort` ; focus : filet d'encre 1,5 pt + halo accent 16 %, sans anneau natif. |
| Bandeau | `BandeauMessage(_:fermer:)`, `.bandeau($m)`, `Bandeau()` | même logique ; rayon 22, verre blanc, texte `.corps`. |
| Carte d'activité | `CarteActiviteClaude(…)` | carte blanche douce (sans filet), ombre `.carte`. |
| Panneau Claude | `PanneauDemandeClaude(…)` | fond d'ambiance figé ; envoi par `BoutonRond(.sombre, 36)` `arrow.up`. |
| Fond flottant | `FondFlottant(forme:survol:)` | `.ultraThinMaterial` + `remplissageCarte`. |
| Papier | `FondPapier()`, `.fondPapier()` | **= `FondAmbiance`** (compatibilité). |

Pilules (`BoutonPilule`, principal, secondaire) : toujours à leur **largeur naturelle**, jamais tronquées ; dans un espace étroit, c'est à l'écran de passer à la ligne ou de raccourcir le libellé. `ListePoints(couleur:)` : seul le point prend la couleur, le texte reste `texte`. `IndicateurClaude` : capsule à la taille de son texte (40 caractères au plus), plus d'étirement à 300 pt.

Inchangés : `ImageLocale`, `CacheImages`, `.entreeEnCascade`, `.survol(_:)`, `FriseDuJour`, `TelephoneInstagram`, `ContenuInstagram`, `FormatInstagram`, `IndicateurClaude`, `FiletProgression`, `CercleEtape`, `ChiffreCle`, `VoixDeClaude`, `Filet`, `PointEtat`, `CadreTraitsDeCoupe`, `SymboleEtape`, `MessagePanneau`, `EditeurLignes`, `ChampHeure`, `ListePoints`, `SurTitre`. Ils lisent les jetons : ils prennent l'ambiance tout seuls.

Compatibilité (écrans 1.2) : `Color.olive` (= accent), `Color.peche`, `Color.alerte`, `Color.succes`, `Color.surface`, `Color.fond`, `Color.trait`, `Color(hex:)`, `Color.hex`, `Font.titre(_:)` (Jakarta 360 au-dessus de 24 pt, 560 en dessous, selon `titres`), `Carte(titre:) { }`, `Puce(texte:forte:couleur:)`, `EnTete(surTitre:titre:sousTitre:)`, `Bandeau()`.

**Banc d'essai.** Les rendus de vérification ont été faits hors écran (`ImageRenderer`, et `NSHostingView` + `cacheDisplay` pour voir les champs) sur provence, lavande, aube, sauge et nuit, en clair et en sombre : accueil (barre, page, cartes, pilules, barre Claude), onboarding et étape de l'assistant. Note : `ImageRenderer` ne dessine pas les `TextField` (rectangle jaune) ; pour vérifier un écran avec un champ, rendre une `NSHostingView` dans une fenêtre hors écran.

## 4. Les écrans

### 4.1 Fenêtre, barre d'icônes, page

- Fenêtre 1320 × 860 par défaut, 1080 × 700 au minimum, barre de titre cachée (`.windowStyle(.hiddenTitleBar)`) : le dégradé va jusqu'en haut, les feux tricolores flottent au-dessus de la barre d'icônes (prévoir 28 pt en haut de la barre).
- Mise en page : `HStack(spacing: 0) { BarreIcones(ecrans: etat.apparence.ecransVisibles, selection: $ecran, badges: …, nouveau: { creer() }) { pied }.zIndex(1); PanneauPage { écran } }` sur `.fondAmbiance()`. Contenu de la page centré, `esp.largeurPage` au plus, marges `esp.page`.
- **Barre** : « + » (créer un post à tout moment, ⌘N) ; les écrans dans l'ordre d'`ecrans` (Aujourd'hui, Idées, Aperçu, Galeries, Statistiques, Réglages, Charte, Règles ; ⌘1 à ⌘8) ; badges : idées qui attendent, post à valider. Pied : un `PointEtat` de Claude dans un rond clair (succès prêt, accent pulsé au travail, alerte déconnecté ; bulle « Claude est prêt » au survol, clic → Réglages › Claude), puis l'initiale de son compte dans un rond d'encre.
- **En-tête de la page** (dans la page, 64 pt) : à gauche `sparkles` + nom du studio (`.corpsFort`) ; au centre la date ou le jour choisi (« ‹ Jeudi 19 novembre › », ⌘[ ⌘]) ; à droite `IndicateurClaude` et, quand utile, une pilule sombre (« Créer un post » n'y est pas : c'est le « + »).
- Changement d'écran : `.id(ecran)` + `j.transition(.ecran)` animé par `.page`.
- Panneau « Demander à Claude » : `.inspector` à droite (340 pt), ⌘K, comme v1 (§4.13).

### 4.2 Onboarding (plein écran, sans carte)

Toute la fenêtre, sans barre ni page : `PageOnboarding` sur `FondAmbiance`. Quatre pages (points en bas), comme les cartes « Hi there! », « Who are you? », « We're all set! » de l'image 1 mais sans leur boîte. Pas de « Passer » : aucune étape ne se saute ; « Revenir » (rond clair) dès la page 2. Les illustrations (`Illustrations.swift`) sont des dessins à main levée, traits d'encre et formes texturées aux couleurs des taches.

1. **Bonjour** (point 1) : illustration de bienvenue, Affiche « Bonjour Gabriella. » (prénom de `compte.yaml`), texte 1, **Commencer** (pilule sombre, ⏎). `./studio claude statut` part déjà en arrière-plan.
2. **Connexions** (point 2) — deux temps sur la même page, l'un après l'autre :
   - **Claude** : illustration de connexion, titre « Connectons Claude. », texte selon l'état (2 pas installé, 3 pas connecté, 4 en attente). Contenu : trois `CercleEtape` en ligne (Installer, Se connecter, Vérifier) ; action : **Installer Claude** / **Se connecter dans le navigateur** (`enCours` pendant l'attente ; l'app revient seule au premier plan une fois connectée). Si déjà prêt : les trois cercles se remplissent en cascade, « C'est bon, Claude est prêt. », puis la partie Instagram glisse (`.suivante`) après 1,2 s.
   - **Instagram** : titre « Et ton compte Instagram. », texte 31 ; contenu : `ChampDoux` (« @gabriellafeyer.photo », une ligne) et la ligne d'état de la connexion ; action **Relier mon compte**. Liens repliés : « Le navigateur ne s'est pas ouvert ? », « J'utilise une clé de la Console ».
3. **Rythme et planification** (point 3) : titre « Ton rythme. », texte 32 ; contenu : jours de publication en pilules à bascule (L M M J V S D : pilule sombre = choisi, claire = non), heure de publication (`ChampHeure` dans une pilule claire), heure des idées du matin, et l'interrupteur « Le studio travaille même app fermée » avec la note 25 en légende ; action **Activer** (les trois tâches se cochent en cascade).
4. **C'est prêt** (point 4) : illustration de fête (fanions, comme l'image 1), Affiche « Ton studio est prêt. », texte 33, **Ouvrir mon studio** ; dessous en lien discret « Demander mes premières idées maintenant ».

Studio introuvable : même gabarit, titre « Où est ton studio ? », **Choisir le dossier…**. Une déconnexion plus tard ne relance pas l'onboarding : le pied de la barre passe en alerte et le bandeau propose **Me reconnecter** (page Connexions dans une feuille plein écran).

### 4.3 Assistant de création d'un post

Ouvert par le « + », par **Créer ce post** (Idées) ou par une demande à Claude. Plein écran dans la fenêtre (la barre d'icônes disparaît, transition `.apparition`), `EtapeAssistant` sur `FondAmbiance`, une étape à la fois (`.suivante` / `.precedente`). « × » ferme et garde le brouillon (bandeau « Brouillon gardé. »). Les étapes à valider viennent de `creation.etapes_a_valider` (Réglages › Création : photos, légende, musique ; l'aperçu se valide toujours) : `EtapeCreation.etapes(aValider:)`. Une étape non validée est faite par Claude et passe seule (elle reste visible, cochée, dans le rappel).

1. **Idée** : titre « De quoi parle ce post ? » ; contenu : les idées du jour en `Carte(.cliquable)` (couverture 4:5, titre, pitch), plus une carte « Ton idée » (`CadreTraitsDeCoupe` + `ChampDoux`, texte 9) ; action **Créer ce post** (⏎).
2. **Claude au travail** : titre « Claude prépare ton post. », texte 10 ; contenu : `CarteActiviteClaude` centrée (520 pt) et une illustration qui respire ; pas d'action, seulement « × » (Arrêter dans la carte). Passe seule à l'étape suivante à la fin.
3. **Photos** : titre « Les photos que Claude propose », texte « Retire, ajoute, glisse pour changer l'ordre. » ; contenu : la séquence en vignettes 4:5 (rayon `photo`, numéro en pastille forte, × au survol pour retirer), glisser-déposer pour réordonner (`.draggable` / `.dropDestination`), dernière case « + Ajouter » qui ouvre la galerie de la série ; action **Valider les photos**.
4. **Légende** : titre « La légende », texte « Claude l'a écrite ; modifie-la directement. » ; contenu : la légende dans un grand `ChampDoux` (Jakarta 16, 8 à 16 lignes) à gauche, compteur « 642 / 2 200 », et à droite le contrôle refait à chaque pause de frappe (pastille succès / à vérifier / à corriger + `ListePoints`) ; action **Valider la légende**.
5. **Musique** : titre « La musique », trois propositions en cartes cliquables (titre, artiste, pourquoi en voix de Claude) + « Sans musique » ; action **Garder cette musique**.
6. **Aperçu et publication** : titre « Voici ton post. » ; contenu : `TelephoneInstagram` à gauche, à droite la pastille de verdict, l'intention en `VoixDeClaude`, « Changer quelque chose ? » (`ChampDoux`) ; actions : **Publier à 18:30** (principal), « Publier maintenant… » (pilule claire, confirmé, texte 13). Validation : célébration v1 puis retour à Aujourd'hui.

### 4.4 Aujourd'hui

Dans la page :

- **Titre en deux tons** (`TitreDeuxTons`, `.affiche`) : « Bonjour Gabriella, » + l'état (« trois idées t'attendent. », « ton post est prêt. », « il part à 18:30. », « c'est en ligne. », « rien à faire pour l'instant. ») ; dessous la phrase d'état (textes 7, 10, 12) en `.chapo` et `FriseDuJour`.
- **Trois cartes** (`Carte`, comme l'image 2) selon l'état : les idées (couverture, titre `.titre3`, « Idée 1 · Lieux » en légende), ou le post prêt (couverture, verdict), ou la dernière publication, la semaine et le feed. Chaque carte est `.cliquable` et mène à l'écran ou à l'étape de l'assistant.
- **L'action principale** sous les cartes (pilule sombre grande : **Choisir une idée**, **Voir l'aperçu**…) ; pendant un travail de Claude, `CarteActiviteClaude` la remplace.
- **En bas, `BarreDemandeClaude`** (860 pt au plus, centrée, 24 pt du bas de la page) : `etat` = « Claude est prêt » / « Claude travaille… », `plus` ouvre le panneau (⌘K), une demande envoyée ouvre le panneau sur la réponse. Raccourcis : `RaccourciClaude.parDefaut`.
- « À régler » (conflits de personnalisation, déconnexion) : une carte à fond `fondAlerte` au-dessus des cartes, une seule action.

### 4.5 Idées

`EnTeteEcran` (« Idées du jour », « Choisis l'histoire du jour. », chapô = lecture du feed en voix de Claude), puis les idées en grille de cartes (`Carte(.cliquable, choisie:)`, 280 pt minimum) : numéro `.numero`, couverture 4:5, pastilles format et pilier, `.titre2`, pitch, « Pourquoi » replié. Un clic sélectionne ; la barre collante (`FondFlottant`, rayon `feuille`) monte avec **Créer ce post**, qui ouvre l'assistant à l'étape 2.

### 4.6 Aperçu

Comme v1 (téléphone à gauche, décision à droite), dans la page : la décision dans une `Carte(.heros)`, **Publier à 18:30** en pilule sombre grande pleine largeur, « Publier maintenant… » et « Reporter » en pilules claires, « Changer quelque chose ? » en `ChampDoux`. Sélecteur clair/sombre du téléphone : deux pilules petites.

### 4.7 Galeries

`EnTeteEcran` avec **Ajouter une galerie** (pilule sombre, ⇧⌘N). Grille de `Carte(.cliquable)` : mosaïque 3:2 (rayon `photo`), lieu en `.titre2`, date en légende, barre fine d'accent « 24 sur 30 photos lues », pastille d'état ; menu ⋯ au survol (rond transparent). Vide : `EtatVide` (texte 8). Fiche d'édition : feuille, sections numérotées en cartes.

### 4.8 Statistiques

`EnTeteEcran`, puis quatre `ChiffreCle` dans une rangée de cartes, et les graphiques Charts dans des cartes (sans quadrillage, axes en légende ; courbe et aire en `accent` à 12 %, barres positives accent, négatives alerte à 70 %). Dessous, « Ce que le studio a retenu » en carte.

### 4.9 Réglages

Deux colonnes dans la page : à gauche les rubriques en lignes arrondies (symbole dans un disque `fondDoux`, sélection = pilule blanche + ombre `.carte`), à droite le contenu en cartes (une carte par groupe, lignes séparées de filets). Rubriques : Compte, Publication, **Création** (étapes à valider : trois interrupteurs Photos, Légende, Musique ; « L'aperçu se valide toujours »), **Claude**, **Planification**, **Apparence**, Instagram, Avancé. Enregistrement automatique (0,6 s) et « Enregistré » en légende succès.

**Apparence (en direct)** : **Ambiance** (les cinq vignettes `FondAmbiance` figées, nom et description ; choisie = anneau d'encre 2 pt), **Mode** (Auto, Clair, Sombre), **Points** (interrupteur « Trame de points »), **Police** (trois tuiles « Bonjour » : Plus Jakarta Sans, SF Pro, SF Rounded), **Titres** (Comme le texte, Serif, Arrondis, Standard), **Couleurs** (accent et accent doux, avec « Revenir aux couleurs de l'ambiance »), Densité, Arrondi (curseur 0–28 et une pilule témoin), Animations, Icônes, Écrans. À droite, l'aperçu en direct clair + sombre (`ApercuTheme`) : une mini-fenêtre avec barre d'icônes, page, titre en deux tons, une carte, une pilule. Chaque changement s'applique en fondu `.theme` ; bandeau « Apparence mise à jour » avec **Annuler**.

### 4.10 Charte et 4.11 Règles

Comme v1, dans la page : la Charte en une carte de lecture (640 pt, `.champ` agrandi 17/28, titres Markdown en Titre 2 et 3), **Modifier** en pilule claire, **Enregistrer** (⌘S) en pilule sombre. Règles : les familles en cartes, les mots refusés en pastilles `.alerte` avec ×, « Ajouter un mot… » en pilule claire petite.

### 4.12 Activité de Claude en direct

Comme v1 : `IndicateurClaude` dans l'en-tête de la page, `CarteActiviteClaude` en popover, en ligne là où le résultat arrivera, dans l'étape 2 de l'assistant et dans le panneau. Rafraîchissement 0,7 s, durée vivante, erreurs traduites avec une seule action.

### 4.13 Panneau « Demander à Claude »

Comme v1 (`.inspector`, ⌘K, contexte retirable, suggestions, fil, envoi), avec le fond d'ambiance figé et l'envoi en rond sombre. Une demande partie de `BarreDemandeClaude` y apparaît comme premier message.

### 4.14 Clavier et VoiceOver

⌘N (créer un post, le « + »), ⇧⌘N (nouvelle galerie), ⌘1 à ⌘8 (écrans), ⏎ (action principale), ⌘← (revenir dans l'onboarding), Échap (fermer l'assistant, le panneau, une feuille), ⌘K (Claude), ⌘[ ⌘] (jour), ⌘R (actualiser), ⌘S (Charte, Règles). Barre d'icônes : chaque rond a son nom, son badge et son état sélectionné ; points de progression et rappel des étapes se lisent « Étape 3 sur 6 : Photos, à toi de valider ». Les pastilles et points d'état ont toujours un libellé.

## 5. Iconographie (SF Symbols)

SF Symbols seulement, du poids du texte voisin, `light` au-delà de 28 pt. `icones: pleines` applique `.symbolVariant(.fill)` à la racine (SwiftUI garde le contour quand la version pleine manque) ; `contours` applique `.none`, mais l'icône choisie de la barre reste pleine. Rendu hiérarchique dans les en-têtes, palette pour les états, monochrome dans les boutons. `sparkles` est réservé à Claude.

| Domaine | Élément | Symbole |
|---|---|---|
| Écrans | Aujourd'hui | `sun.max` |
| | Idées | `lightbulb` |
| | Aperçu | `iphone` |
| | Galeries | `photo.stack` |
| | Statistiques | `chart.line.uptrend.xyaxis` |
| | Réglages | `gearshape` |
| | Charte | `text.book.closed` |
| | Règles | `checkmark.shield` |
| Claude | Claude (capsule, panneau, avatar) | `sparkles` |
| | Demander à Claude | `text.bubble` |
| | Nouvelle conversation | `square.and.pencil` |
| | Envoyer | `arrow.up.circle.fill` |
| | Arrêter | `stop.circle` |
| | Étape faite | `checkmark.circle.fill` |
| | Étape inconnue | `circle.dotted` |
| Actions | Créer un post (le « + » de la barre) | `plus` |
| | Créer ce post | `wand.and.stars` |
| | Publier, publié | `paperplane`, `paperplane.fill` |
| | Reporter | `calendar.badge.clock` |
| | Retoucher | `pencil.line` |
| | Ajouter | `plus` |
| | Relire, réessayer | `arrow.triangle.2.circlepath` |
| | Retirer | `trash` (menus seulement) |
| | Voir sur Instagram | `arrow.up.right.square` |
| | Plus d'actions | `ellipsis.circle` |
| | Jour précédent, suivant | `chevron.left`, `chevron.right` |
| Connexion | Installer | `arrow.down.circle` |
| | Se connecter | `person.crop.circle.badge.checkmark` |
| | Navigateur | `globe` |
| | Vérifier, connecté | `checkmark.seal`, `checkmark.seal.fill` |
| Planification | Planification | `clock.badge.checkmark` |
| | Idées du matin | `sunrise` |
| | Publication | `paperplane` |
| | Bilan | `chart.bar.doc.horizontal` |
| Formats | Carrousel, Image, Reel | `square.on.square`, `photo`, `play.rectangle` |
| | Exploration | `binoculars` |
| Piliers | Éditorial, Documentaire, Détails, Lieux | `newspaper`, `camera.viewfinder`, `magnifyingglass`, `building.columns` |
| | Portraits, Love story, Atmosphère, Vision artistique | `person.crop.rectangle`, `heart`, `cloud.sun`, `paintbrush.pointed` |
| États | Prêt, à vérifier, à corriger | `checkmark.circle.fill`, `exclamationmark.circle.fill`, `exclamationmark.triangle.fill` |
| | Prévu, reporté, info | `clock.fill`, `moon.zzz`, `info.circle.fill` |
| Apparence | Mode clair, sombre, auto | `sun.max`, `moon`, `circle.lefthalf.filled` |
| | Ambiance, police, points | `paintpalette`, `textformat`, `circle.grid.3x3` |
| Assistant | Idée, Claude, Photos, Légende, Musique, Aperçu | `lightbulb`, `sparkles`, `photo.on.rectangle`, `text.quote`, `music.note`, `iphone` |
| | Retour, fermer, envoyer | `chevron.left`, `xmark`, `arrow.up` |
| Demande à Claude | Raccourcis | `lightbulb`, `text.quote`, `photo.on.rectangle`, `paintpalette`, `ellipsis` |
| | Écran verrouillé | `lock.fill` |
| Téléphone | Actions Instagram | `heart`, `bubble.right`, `paperplane`, `bookmark`, `ellipsis` |
| | Barre d'état | `cellularbars`, `wifi`, `battery.100` |
| | Musique | `music.note` |

Étapes de Claude : le symbole vient du champ `icone` du moteur (table de `moteur/claude.py` : `eye`, `square.grid.3x3`, `lightbulb`, `square.and.pencil`, `checkmark.seal`, `music.note`, `photo.stack`…), vérifié par `SymboleEtape.valide(_:)`.

## 6. Textes de référence

Français simple, tutoiement, phrases courtes, jamais de jargon (ni « session », ni « JSON », ni « LaunchAgent »). Les boutons commencent par un verbe.

1. Accueil : « Chaque matin, des idées de post : tu choisis, Claude prépare, tu valides d'un clic. » — **Commencer**
2. Installation : « Claude n'est pas encore sur ce Mac. Un clic, environ une minute. » — **Installer Claude**
3. Connexion : « Ton navigateur va s'ouvrir sur la page de Claude. Ton mot de passe se tape là-bas, jamais ici. » — **Se connecter dans le navigateur**
4. Attente : « Termine la connexion dans ton navigateur, je t'attends ici. »
5. Connecté : « C'est bon, Claude est prêt. »
6. Planification : « Chaque matin à 8:00, Claude prépare tes idées, même app fermée. Rien ne part sans ton accord. » — **Activer**, « Plus tard »
7. Rien à faire : « Rien à faire pour l'instant. Tes idées arrivent demain à 8:00, l'app s'ouvrira toute seule. »
8. Pas de galerie : « Aucune galerie pour l'instant. Colle un lien Pic-Time ou glisse un dossier : Claude s'occupe du reste. »
9. Ton idée : « Écris ton idée comme un titre de magazine… » — **Proposer mon idée**
10. Claude au travail : « Claude prépare ton post. Tu peux fermer l'app : elle se rouvrira quand ce sera prêt. »
11. Idées prêtes : « Trois idées t'attendent. » — **Choisir une idée**
12. Post prêt : « Ton post est prêt. Il partira ce soir à 18:30 si tu le valides. » — **Voir l'aperçu**
13. Publier maintenant : « Publier tout de suite ? Le post part maintenant sur Instagram, sans attendre 18:30. » — **Publier maintenant**, « Annuler »
14. Validé : « Validé. Il partira jeudi à 18:30. »
15. Retouche : « Une photo, l'ordre, un mot de la légende… dis-le simplement. » — **Demander la retouche**
16. Publié : « C'est en ligne ! » — **Voir sur Instagram**
17. Reporté : « Reporté. Rien ne part aujourd'hui ; tu pourras le reprendre plus tard. »
18. Choix fait : « Idée choisie. Claude prépare le post, il arrivera ici. »
19. Pas de post : « Pas encore de post pour ce jour. Choisis d'abord une idée. »
20. À vérifier : « Prêt, 2 points à vérifier. »
21. À corriger : « À corriger avant publication. Claude peut s'en occuper. »
22. Fin de travail : « C'est prêt. Jette un œil à l'aperçu. »
23. Étapes : « Je relis ta charte », « Je regarde les photos de la série », « Je choisis l'ordre des images », « J'écris la légende », « Je vérifie que tout est en règle ».
24. Enregistré : « Enregistré »
25. Note de planification : « Ton Mac doit être allumé ; en veille, la tâche part au réveil. Rien n'est publié sans ta validation. »
26. Panneau vide : « Demande ce que tu veux : une autre idée, un changement d'apparence, une explication. »
27. Déconnecté : « Claude n'est plus connecté. Un clic pour revenir. » — **Me reconnecter**
28. Limite : « Claude a atteint sa limite pour l'instant. Ton post t'attend, on reprendra plus tard. »
29. Hors ligne : « Pas d'internet pour le moment. Le studio réessaiera dès son retour. » — **Réessayer**
30. Reconstruction : « Pour ce changement, Claude reconstruit l'app : elle se ferme quelques secondes, puis revient ici. »
31. Instagram (onboarding) : « Relie ton compte pour que le studio publie à ta place, seulement ce que tu as validé. » — **Relier mon compte**
32. Rythme (onboarding) : « Choisis tes jours et ton heure. Claude prépare les idées le matin, tu décides, le studio publie. » — **Activer**
33. Prêt (onboarding) : « Demain matin, tes premières idées t'attendront ici. » — **Ouvrir mon studio**
34. Barre Claude : « Demande à Claude… par exemple « une idée pour samedi » »
35. Assistant fermé : « Brouillon gardé. Tu le retrouves avec le « + ». »

## 7. Icône de l'app

**« Le tirage au soleil »** : deux tirages argentiques posés sur l'olive de ses stories ; sur celui de devant, un soleil de Provence se couche derrière deux collines et un cyprès. Rien n'emprunte au logo d'Instagram, rien ne signale « IA ».

Fichiers : `app/Ressources/icone.py` (Pillow, suréchantillonnage ×4) produit `app/Ressources/icone.png` (1024 × 1024, fond transparent) et, avec `--jeu <dossier>`, les tailles d'un `.iconset`. `construire.sh` prend `app/Ressources/icone.png` (puis `iconutil`).

```
.venv/bin/python app/Ressources/icone.py [--accent #3d4130] [--doux #efdccd] [--fond #f7f3ed] [--sortie icone.png] [--taille 1024] [--jeu AppIcon.iconset]
```

Spécification sur une toile de 1024 (coordonnées en px, origine en haut à gauche) :

1. **Squircle** de 824 × 824 centré (marge 100), superellipse d'exposant 5 (forme des icônes macOS). Fond en dégradé vertical de m(accent, blanc, .14) en haut à m(accent, noir, .22) en bas (#5a5d4f → #30332a), reflet radial blanc à 9 % centré en (330, 250), rayon 520. Liseré intérieur blanc à 7 %, 2 px. **Ombre portée** noire à 32 %, flou 22, décalée de 12 vers le bas (comme les icônes du système).
2. **Tirage arrière** : 4:5 de 400 × 500, `accent_doux`, rayon 10, centre (548, 500), tourné de 8° dans le sens horaire, ombre noire 25 %, flou 18, y +6.
3. **Tirage avant** : 4:5 de 440 × 550, m(fond, blanc, .35), rayon 12, centre (486, 534), tourné de 5° dans le sens inverse, ombre noire 35 %, flou 26, y +14. Bord de 30 px (32 en bas, comme un tirage).
4. **Photo** dans le tirage avant (fenêtre de 380 × 488, rayon 4), dessinée dans cet ordre :
   - ciel en dégradé vertical de m(fond, accent_doux, .25) à m(accent_doux, alerte, .24) ;
   - halo : disque de 2,1 × le rayon du soleil, m(accent_doux, blanc, .45) à 55 %, flou 0,55 × le rayon ;
   - soleil couchant plat de 176 px, centré à 46 % de la largeur et 62 % de la hauteur, dégradé vertical de m(accent_doux, alerte, .38) en haut à m(alerte, accent_doux, .12) en bas ;
   - colline lointaine (profil en cosinus, sommet à 22 % de la largeur) en m(accent, fond, .45) ;
   - cyprès : flamme de 36 × 196 en m(accent, noir, .28), à 73 % de la largeur, la plus large aux quatre cinquièmes, pied à 80 % de la hauteur ;
   - colline proche en `accent` (sommet à 80 %), dessinée en dernier : elle cache le pied du cyprès et le bas du soleil.
5. **Petites tailles** (≤ 64 px, `--jeu` ou `--simple`) : pas de tirage arrière, pas de colline lointaine ni de cyprès ; tirage avant centré (512, 520), tourné de 3°, bord de 36 px ; soleil de 210 px.

Contrôle : lisible en 32 px (squircle olive, tirage clair, soleil terre cuite, colline sombre) sur fond clair comme sombre.

## 8. Faisabilité

Faits : thème et jetons v2 (`Theme.swift`, ~900 lignes), composants v2 (`Style.swift`, ~3 100 lignes, dont fond d'ambiance, barre d'icônes, pilules, barre Claude, onboarding et assistant). À faire par les écrans : onboarding (≈ 350 lignes avec les illustrations à part), assistant de création (≈ 600), Aujourd'hui (≈ 250), les autres écrans à adapter (en-têtes, cartes, pilules : surtout du remplacement). Performance : le fond se redessine à 15 images/s (quatre dégradés radiaux dans un `Canvas`), en pause quand la fenêtre n'est pas active, figé si « Réduire les animations » ; la trame ne se redessine qu'au redimensionnement. Sans macros, sans `MeshGradient`, sans effets de symboles de macOS 15.
