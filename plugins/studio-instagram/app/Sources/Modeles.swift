import AppKit
import Foundation

// Les noms des champs reprennent exactement ceux du JSON du moteur (./studio app …).

struct ReponseErreur: Decodable { let erreur: String? }
struct ReponseEnregistrement: Decodable { let etat: String?; let erreurs: [String]? }
struct Demande: Decodable { let id: String; let ecran: String; let jour: String?; let le: String?; let activer: Bool? }

// MARK: - Journée

struct VueJour: Decodable {
    let jour: String
    let aujourdhui: String?
    let existe: Bool?
    let date_longue: String?
    let creneau: String?
    let statut: String?
    let statut_libelle: String?
    let publier_a: String?
    let permalink: String?
    let erreur: String?
    let claude_attend: Bool?
    let decision: Decision?
    let lecture_du_feed: String?
    let choix: Choix?
    let idees: [Idee]?
    let post: Post?
    let verdict: Verdict?
    let grille: [String?]?
}

struct Decision: Decodable {
    let id: String?
    let type: String?
    let le: String?
    let traitee: Bool?
    let claude_attend: Bool?
    let numero: Int?
    let titre: String?
    let texte: String?
    let demande: String?
    let permalink: String?
    let publier_a: String?
    let avertissements: [String]?
}

struct Choix: Decodable { let numero: Int?; let titre: String?; let libre: String? }

struct Idee: Decodable, Identifiable {
    let numero: Int
    var id: Int { numero }
    let titre: String?
    let pitch: String?
    let format: String?
    let format_libelle: String?
    let nb_medias: Int?
    let duree_s: Double?
    let pilier: String?
    let pilier_libelle: String?
    let serie: String?
    let type: String?
    let longueur_legende: String?
    let musique: String?
    let pourquoi: String?
    let couverture: String?
    let vignettes: [String]?
}

struct Post: Decodable {
    let titre: String?
    let format: String?
    let format_libelle: String?
    let pilier: String?
    let pilier_libelle: String?
    let intention: String?
    let pourquoi: String?
    let legende: String?
    let longueur_legende: String?
    let hashtags: [String]?
    let collaborateurs: [String]?
    let localisation: String?
    let date: String?
    let heure: String?
    let serie: String?
    let alertes: [String]?
    let compte: String?
    let nom: String?
    let musique: Musique?
    let medias: [MediaPost]?
    let video: String?
    let couverture: String?
}

/// Musique du post. Lue dans `Post.musique`, renvoyée par `modifierPost` (seuls les champs non nuls partent).
struct Musique: Codable, Equatable {
    /// api_reel | integree | a_ajouter_dans_l_app | aucune
    var mode: String? = nil
    var titre: String? = nil
    var artiste: String? = nil
    var direction_sonore: String? = nil
    var apercu_url: String? = nil
    /// Identifiant de la piste Instagram (mode api_reel).
    var audio_id: String? = nil
    var requete: String? = nil
    /// 0 à 100.
    var volume_musique: Double? = nil
    var volume_video: Double? = nil

    static let modes = ["api_reel", "integree", "a_ajouter_dans_l_app", "aucune"]

    static func libelleMode(_ m: String?) -> String {
        switch m {
        case "api_reel": return "Musique Instagram"
        case "integree": return "Déjà dans la vidéo"
        case "a_ajouter_dans_l_app": return "À ajouter dans Instagram"
        case "aucune": return "Sans musique"
        default: return "Non choisie"
        }
    }
}

extension Musique {
    enum CodingKeys: String, CodingKey {
        case mode, titre, artiste, direction_sonore, apercu_url, audio_id, requete, volume_musique, volume_video
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.texte(.mode)?.nonVide
        titre = c.texte(.titre)?.nonVide
        artiste = c.texte(.artiste)?.nonVide
        direction_sonore = c.texte(.direction_sonore)?.nonVide
        apercu_url = c.texte(.apercu_url)?.nonVide
        audio_id = c.texte(.audio_id)?.nonVide ?? c.entier(.audio_id).map(String.init)
        requete = c.texte(.requete)?.nonVide
        volume_musique = c.nombre(.volume_musique)
        volume_video = c.nombre(.volume_video)
    }
}

struct MediaPost: Decodable, Identifiable {
    let ordre: Int
    var id: Int { ordre }
    let role: String?
    let presentation: String?
    let texte_alternatif: String?
    let identifications: [String]?
    let image: String?
    /// Photo d'origine (identifiant du catalogue) : nécessaire pour `modifierPost`. Absent avec un moteur ancien.
    let photo_id: String?
    /// clair | sombre | papier
    let fond: String?
}

struct Verdict: Decodable {
    let conforme: Bool?
    let erreurs: [String]?
    let avertissements: [String]?
    let alertes: [String]?
    let caracteres: Int?
}

struct ResumeJour: Decodable, Identifiable {
    let jour: String
    var id: String { jour }
    let date_longue: String?
    let statut: String?
    let statut_libelle: String?
    let titre: String?
}

// MARK: - Réglages

struct Reglages: Codable {
    var nom: String
    var compte_instagram: String
    /// Ce que la personne photographie (« photographe de mariage »…) : voir `Reglages.activitesSuggerees`.
    /// Renvoyée par `enregistrer-reglages` ; un moteur ancien qui ne la connaît pas l'ignore.
    var activite: String
    var localisation: String
    var voix: String
    var langue: String
    var fuseau: String
    var approche: String
    var exemples_de_legendes: [String]
    var publication: Publication
    var routine: Routine
    var instagram: ReglagesInstagram
    var mise_en_page: MiseEnPage
    var interface: Interface
    var comptes_autorises: [String]
    var images_deja_publiees: [String]
    /// Lecture seule : `planification.active` de config/compte.yaml (absent avec un moteur ancien).
    /// Jamais renvoyé par `enregistrer-reglages` (une copie périmée pourrait couper les tâches) :
    /// pour activer ou arrêter les tâches automatiques, appeler `EtatApp.planifier(activer:)`.
    var planification: ReglagesPlanification?
    /// Modèle et effort de Claude (section `claude` de config/compte.yaml ; absente avec un moteur ancien).
    /// Renvoyée au moteur seulement si elle est présente.
    var claude: ReglagesClaude?
    /// Étapes de l'assistant de création que la photographe veut valider (absente avec un moteur ancien).
    /// Renvoyée au moteur seulement si elle est présente. Voir `EtatApp.etapesAValider`.
    var creation: ReglagesCreation?

    enum CodingKeys: String, CodingKey {
        case nom, compte_instagram, activite, localisation, voix, langue, fuseau, approche, exemples_de_legendes,
             publication, routine, instagram, mise_en_page, interface, comptes_autorises, images_deja_publiees,
             planification, claude, creation
    }

    /// Même JSON qu'avant la 2.0 : `planification` n'est pas renvoyée au moteur ; `claude` et `creation` le sont si présentes.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nom, forKey: .nom)
        try c.encode(compte_instagram, forKey: .compte_instagram)
        try c.encode(activite, forKey: .activite)
        try c.encode(localisation, forKey: .localisation)
        try c.encode(voix, forKey: .voix)
        try c.encode(langue, forKey: .langue)
        try c.encode(fuseau, forKey: .fuseau)
        try c.encode(approche, forKey: .approche)
        try c.encode(exemples_de_legendes, forKey: .exemples_de_legendes)
        try c.encode(publication, forKey: .publication)
        try c.encode(routine, forKey: .routine)
        try c.encode(instagram, forKey: .instagram)
        try c.encode(mise_en_page, forKey: .mise_en_page)
        try c.encode(interface, forKey: .interface)
        try c.encode(comptes_autorises, forKey: .comptes_autorises)
        try c.encode(images_deja_publiees, forKey: .images_deja_publiees)
        try c.encodeIfPresent(claude, forKey: .claude)
        try c.encodeIfPresent(creation, forKey: .creation)
    }
}

extension Reglages {
    /// Lecture : mêmes champs obligatoires qu'en 1.x ; `activite`, `planification`, `claude`, `creation` facultatifs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nom = try c.decode(String.self, forKey: .nom)
        compte_instagram = try c.decode(String.self, forKey: .compte_instagram)
        activite = c.texte(.activite) ?? Reglages.activiteParDefaut
        localisation = try c.decode(String.self, forKey: .localisation)
        voix = try c.decode(String.self, forKey: .voix)
        langue = try c.decode(String.self, forKey: .langue)
        fuseau = try c.decode(String.self, forKey: .fuseau)
        approche = try c.decode(String.self, forKey: .approche)
        exemples_de_legendes = try c.decode([String].self, forKey: .exemples_de_legendes)
        publication = try c.decode(Publication.self, forKey: .publication)
        routine = try c.decode(Routine.self, forKey: .routine)
        instagram = try c.decode(ReglagesInstagram.self, forKey: .instagram)
        mise_en_page = try c.decode(MiseEnPage.self, forKey: .mise_en_page)
        interface = try c.decode(Interface.self, forKey: .interface)
        comptes_autorises = try c.decode([String].self, forKey: .comptes_autorises)
        images_deja_publiees = try c.decode([String].self, forKey: .images_deja_publiees)
        planification = c.souple(ReglagesPlanification.self, .planification)
        claude = c.souple(ReglagesClaude.self, .claude)
        creation = c.souple(ReglagesCreation.self, .creation)
    }

    /// Valeur du moteur quand `activite` manque.
    static let activiteParDefaut = "photographe de mariage"

    /// Activités proposées dans l'onboarding et les Réglages (la personne peut aussi écrire la sienne).
    static let activitesSuggerees = [
        "photographe de mariage",
        "photographe portrait et famille",
        "photographe de mode et éditorial",
        "photographe de voyage et de paysage",
    ]

    /// Les champs du profil encore à remplir, dans l'ordre de l'onboarding : `nom`, `compte_instagram`, `activite`,
    /// `localisation`, `voix`, `langue` (vides ou « [À COMPLÉTER … »), puis `approche` si elle contient encore
    /// « [À COMPLÉTER » (elle peut rester vide).
    var champsACompleter: [String] {
        var liste: [String] = []
        for (nom, valeur) in [("nom", nom), ("compte_instagram", compte_instagram), ("activite", activite),
                              ("localisation", localisation), ("voix", voix), ("langue", langue)]
            where champACompleter(valeur) {
            liste.append(nom)
        }
        if approche.contains("[À COMPLÉTER") { liste.append("approche") }
        return liste
    }

    /// Tout le profil est rempli.
    var profilComplet: Bool { champsACompleter.isEmpty }
}

/// Vrai si la valeur est vide (ou faite d'espaces) ou contient encore « [À COMPLÉTER » (modèle de config/compte.yaml).
func champACompleter(_ valeur: String?) -> Bool {
    guard let v = valeur?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return true }
    return v.contains("[À COMPLÉTER") || v.contains("[A COMPLETER")
}

/// `creation` de config/compte.yaml : les étapes de l'assistant qui attendent la validation de la photographe.
/// L'aperçu final se valide toujours ; les autres étapes non cochées passent toutes seules.
struct ReglagesCreation: Codable, Equatable {
    /// Sous-ensemble ordonné de `ReglagesCreation.etapes`.
    var etapes_a_valider = ReglagesCreation.etapes

    static let etapes = ["photos", "legende", "musique"]

    static func libelle(_ etape: String) -> String {
        switch etape {
        case "photos": return "Photos"
        case "legende": return "Légende"
        case "musique": return "Musique"
        default: return etape
        }
    }

    static func symbole(_ etape: String) -> String {
        switch etape {
        case "photos": return "photo.on.rectangle"
        case "legende": return "text.alignleft"
        case "musique": return "music.note"
        default: return "circle"
        }
    }
}

extension ReglagesCreation {
    enum CodingKeys: String, CodingKey { case etapes_a_valider }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let liste = c.souple([String].self, .etapes_a_valider) ?? ReglagesCreation.etapes
        etapes_a_valider = ReglagesCreation.etapes.filter { liste.contains($0) }
    }
}

/// `claude` de config/compte.yaml : texte vide = valeur par défaut de Claude Code.
struct ReglagesClaude: Codable, Equatable {
    /// Alias ou nom complet du modèle (« opus », « sonnet »…), ou vide.
    var modele = ""
    /// low | medium | high | xhigh | max, ou vide.
    var effort = ""

    static let efforts = ["", "low", "medium", "high", "xhigh", "max"]

    static func libelleEffort(_ e: String) -> String {
        switch e {
        case "low": return "Rapide"
        case "medium": return "Équilibré"
        case "high": return "Soigné"
        case "xhigh": return "Très soigné"
        case "max": return "Maximum"
        default: return "Par défaut"
        }
    }
}

extension ReglagesClaude {
    enum CodingKeys: String, CodingKey { case modele, effort }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modele = c.texte(.modele) ?? ""
        effort = c.texte(.effort) ?? ""
    }
}

struct ReglagesPlanification: Codable, Equatable {
    var active = false
}

extension ReglagesPlanification {
    enum CodingKeys: String, CodingKey { case active }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.booleen(.active) ?? false
    }
}

struct Publication: Codable {
    var creneaux: [String: String]
    var part_reels: Double
    var hebergement: String
    var bucket_supabase: String
}

struct Routine: Codable {
    var heure_idees: String
    var nombre_idees: Int
    var idees_exploration: Int
    var jour_bilan: String
    var heure_bilan: String
}

struct ReglagesInstagram: Codable { var api: String; var version_api: String }
struct MiseEnPage: Codable { var marge_px: Int; var fonds: [String: String] }
struct Interface: Codable { var artifact: Bool; var ouvrir_app: Bool }

// MARK: - Galeries

struct Galerie: Codable, Identifiable {
    var id: String
    var type: String
    var lieu: String
    var date: String
    var notes: String
    var consignes: String
    var statut: String
    var location_id: String
    var exports_hd: String
    var maries: Maries
    var prestataires: [Prestataire]
    var source: SourceGalerie
    var photos: Int?
    var analysees: Int?
    var fortes: Int?

    static func nouvelle() -> Galerie {
        Galerie(id: "", type: "mariage", lieu: "", date: "", notes: "", consignes: "", statut: "active",
                location_id: "", exports_hd: "", maries: Maries(prenoms: "", prenoms_publiables: false),
                prestataires: [], source: SourceGalerie(type: "pictime", url: "", chemin: ""),
                photos: nil, analysees: nil, fortes: nil)
    }
}

struct Maries: Codable { var prenoms: String; var prenoms_publiables: Bool }

struct Prestataire: Codable, Identifiable {
    var id = UUID()
    var role: String
    var nom: String
    var compte: String
    enum CodingKeys: String, CodingKey { case role, nom, compte }
}

struct SourceGalerie: Codable { var type: String; var url: String; var chemin: String }

// MARK: - Charte, règles, mémoire, santé

struct Charte: Decodable { let texte: String; let personnalisee: Bool?; let nouvelle_base: Bool?; let base: String? }

struct Regles: Codable { var legende: ReglesLegende; var limites: Limites; var alternance: Alternance }

struct ReglesLegende: Codable {
    var cliches: [String]
    var commercial: [String]
    var commercial_possible: [String]
    var incitations: [String]
    var mots_du_prompt: [String]
    var superlatifs: [String]
    var hashtags_generiques: [String]
}

struct Limites: Codable {
    var legende_caracteres: Int
    var mentions: Int
    var hashtags: Int
    var collaborateurs: Int
    var medias_carrousel: Int
    var carrousel_court: Int
}

struct Alternance: Codable {
    var pilier_consecutif_interdit: Bool
    var serie_consecutive_interdite: Bool
    var criteres_couverture_differents: Int
    var meme_tonalite_max: Int
    var meme_longueur_max: Int
    var couple_max_sur_8: Int
    var piliers_min_sur_10: Int
}

struct Memoire: Decodable {
    let apprentissages: String
    let gouts: String
    let performance: String
    let resume: Resume?
    let historique: [PostHistorique]?
}

struct Resume: Decodable {
    let mesurees: Int?
    let message: String?
    let moyennes: [String: Double]?
    let abonnes: Abonnes?
    let fonctionne: [Constat]?
    let a_ameliorer: [Constat]?
}

struct Abonnes: Decodable { let debut: PointAbonnes?; let fin: PointAbonnes? }
struct PointAbonnes: Decodable { let jour: String?; let abonnes: Int? }

struct Constat: Decodable, Identifiable {
    var id: String { (dimension ?? "") + "·" + (valeur ?? "") }
    let dimension: String?
    let valeur: String?
    let n: Int?
    let score_median: Double?
    let ecart: Double?
    let confiance: String?
}

struct PostHistorique: Decodable, Identifiable {
    var id: String { (date ?? "") + (permalink ?? "") + (titre ?? "") }
    let date: String?
    let titre: String?
    let format: String?
    let pilier: String?
    let permalink: String?
    let couverture: String?
}

struct Sante: Decodable {
    let version: String?
    let dossier: String?
    let a_completer: [String]?
    let instagram_connecte: Bool?
    let jeton_expire_le: String?
    let hebergement: String?
    let hebergement_pret: Bool?
    let ffmpeg: Bool?
    let galeries: Int?
    let publications: Int?
}

// MARK: - Décodage tolérant (2.0)
//
// Les types de la 2.0 ne font jamais échouer le décodage : une clé absente, `null` ou d'un type
// inattendu prend sa valeur par défaut. Le moteur peut ainsi ajouter des champs sans casser l'app.
// Les `init(from:)` sont dans des extensions : l'initialiseur membre à membre reste disponible.

extension KeyedDecodingContainer {
    /// La valeur si elle est présente et du bon type, sinon nil.
    func souple<T: Decodable>(_ type: T.Type, _ cle: Key) -> T? {
        (try? decodeIfPresent(type, forKey: cle)) ?? nil
    }

    func texte(_ cle: Key) -> String? { souple(String.self, cle) }

    func booleen(_ cle: Key) -> Bool? {
        if let b = souple(Bool.self, cle) { return b }
        if let n = souple(Int.self, cle) { return n != 0 }
        if let s = souple(String.self, cle) { return ["true", "oui", "yes", "1"].contains(s.lowercased()) }
        return nil
    }

    func nombre(_ cle: Key) -> Double? {
        if let d = souple(Double.self, cle) { return d }
        if let s = souple(String.self, cle) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func entier(_ cle: Key) -> Int? {
        guard let d = nombre(cle), d.isFinite else { return nil }
        return Int(d.rounded())
    }
}

/// Clé JSON quelconque (lecture d'objets dont on ne connaît qu'une partie).
struct CleJSON: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ nom: String) { stringValue = nom }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension String {
    /// Le texte sans espaces autour, ou nil s'il est vide.
    var nonVide: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Réponse minimale `{"etat": …, "conseil": …}` (deconnecter, annuler, retablir-apparence…).
struct ReponseEtat: Decodable {
    var etat = ""
    var conseil: String?
}

extension ReponseEtat {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        conseil = c.texte(CleJSON("conseil"))?.nonVide
    }
}

// MARK: - Claude (./studio claude …)

/// `./studio claude statut` : Claude Code est-il installé et connecté sur ce Mac ?
struct ClaudeStatut: Decodable, Equatable {
    var installe = false
    var chemin: String?
    /// reglage | path | app_claude
    var source: String?
    var version: String?
    var connecte = false
    /// claude.ai | console | cle_api | aucune
    var methode: String?
    var plugin_present = false
    /// Identifiant de l'exécution en cours (le moteur peut donner l'id ou l'objet entier), sinon nil.
    var en_cours: String?
    /// Phrase simple quand quelque chose manque, sinon nil.
    var conseil: String?
}

extension ClaudeStatut {
    enum CodingKeys: String, CodingKey {
        case installe, chemin, source, version, connecte, methode, plugin_present, en_cours, conseil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installe = c.booleen(.installe) ?? false
        chemin = c.texte(.chemin)?.nonVide
        source = c.texte(.source)?.nonVide
        version = c.texte(.version)?.nonVide
        connecte = c.booleen(.connecte) ?? false
        methode = c.texte(.methode)?.nonVide
        plugin_present = c.booleen(.plugin_present) ?? false
        if let id = c.texte(.en_cours)?.nonVide {
            en_cours = id
        } else if let objet = try? c.nestedContainer(keyedBy: CleJSON.self, forKey: .en_cours) {
            en_cours = objet.texte(CleJSON("id"))?.nonVide
        }
        conseil = c.texte(.conseil)?.nonVide
    }

    /// Installé et connecté : Claude peut travailler.
    var pret: Bool { installe && connecte }

    var libelleMethode: String {
        switch methode {
        case "claude.ai": return "Compte Claude"
        case "console": return "Console Anthropic"
        case "cle_api": return "Clé d'API"
        default: return connecte ? "Connecté" : "Non connecté"
        }
    }

    var libelleSource: String? {
        switch source {
        case "reglage": return "Chemin choisi dans les réglages"
        case "path": return "Installé sur ce Mac"
        case "app_claude": return "Fourni avec l'app Claude"
        default: return nil
        }
    }
}

/// Une étape lisible d'une exécution (« Je regarde les photos de la série »).
struct EtapeClaude: Decodable, Identifiable, Equatable {
    /// Stable d'un rafraîchissement à l'autre (horodatage + texte), unique dans l'exécution.
    var id = ""
    var le: String?
    var texte = ""
    /// Nom de symbole SF proposé par le moteur (voir `symbole`, qui le vérifie).
    var icone: String?
    var fait = true
    /// Nombre d'actions regroupées dans cette étape (« Je regarde les photos (12) »).
    var n = 1
}

extension EtapeClaude {
    enum CodingKeys: String, CodingKey { case le, texte, icone, fait, n }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        le = c.texte(.le)
        texte = c.texte(.texte) ?? ""
        icone = c.texte(.icone)?.nonVide
        fait = c.booleen(.fait) ?? true
        n = max(1, c.entier(.n) ?? 1)
        id = "\(le ?? "")|\(texte)"
    }

    /// Symbole SF à afficher : celui du moteur s'il existe sur ce Mac, sinon un symbole neutre.
    var symbole: String { EtapeClaude.symboleVerifie(icone, defaut: "sparkle") }

    var date: Date? { ExecutionClaude.date(le) }

    private static var symbolesConnus: [String: Bool] = [:]

    /// Le nom s'il désigne un symbole SF disponible sur ce système, sinon `defaut`.
    static func symboleVerifie(_ nom: String?, defaut: String) -> String {
        guard let nom = nom?.nonVide else { return defaut }
        if let connu = symbolesConnus[nom] { return connu ? nom : defaut }
        let existe = NSImage(systemSymbolName: nom, accessibilityDescription: nil) != nil
        symbolesConnus[nom] = existe
        return existe ? nom : defaut
    }
}

/// `./studio claude etat` et `.ui/claude/<id>.json` : une exécution de Claude, en cours ou finie.
struct ExecutionClaude: Decodable, Identifiable, Equatable {
    var id = ""
    /// matin | creation | retouche | galerie | bilan | demande (voir `tacheClaude`)
    var tache: String?
    var jour: String?
    var titre: String?
    /// en_attente | en_cours | termine | erreur | annule (vide si inconnu)
    var etat = ""
    var debut: String?
    var fin: String?
    var duree_s: Double?
    var etapes: [EtapeClaude] = []
    /// Dernière phrase de Claude (courte).
    var message: String?
    /// Résumé final de Claude (deux phrases au plus).
    var resultat: String?
    var erreur: String?
    /// apercu | idees | galeries | statistiques (voir `ecranSuivant`)
    var ecran_suivant: String?
    var session: String?
    var cout_usd: Double?
    /// Facultatifs : présents seulement si le moteur les fournit.
    var serie: String?
    var consigne: String?
    /// Lancée par la planification du Mac (launchd), pas par un clic dans l'app.
    var auto: Bool?
    /// Préparée par `lancer` (avant le démarrage effectif).
    var cree_le: String?
    /// Modèle utilisé par Claude Code (connu une fois l'exécution démarrée).
    var modele: String?
    /// Terminée, mais Claude a dû renoncer à des actions non autorisées.
    var avertissement: String?
}

extension ExecutionClaude {
    enum CodingKeys: String, CodingKey {
        case id, tache, jour, titre, etat, debut, fin, duree_s, etapes, message, resultat, erreur,
             ecran_suivant, session, cout_usd, serie, consigne, auto, cree_le, modele, avertissement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texte(.id)?.nonVide ?? ""
        tache = c.texte(.tache)?.nonVide
        jour = c.texte(.jour)?.nonVide
        titre = c.texte(.titre)?.nonVide
        etat = c.texte(.etat)?.nonVide ?? ""
        debut = c.texte(.debut)?.nonVide
        fin = c.texte(.fin)?.nonVide
        duree_s = c.nombre(.duree_s)
        message = c.texte(.message)?.nonVide
        resultat = c.texte(.resultat)?.nonVide
        erreur = c.texte(.erreur)?.nonVide
        ecran_suivant = c.texte(.ecran_suivant)?.nonVide
        session = c.texte(.session)?.nonVide
        cout_usd = c.nombre(.cout_usd)
        serie = c.texte(.serie)?.nonVide
        consigne = c.texte(.consigne)?.nonVide
        auto = c.booleen(.auto)
        cree_le = c.texte(.cree_le)?.nonVide
        modele = c.texte(.modele)?.nonVide
        avertissement = c.texte(.avertissement)?.nonVide
        // Une étape illisible est ignorée ; les identifiants restent uniques (doublons numérotés).
        var vus: [String: Int] = [:]
        etapes = (c.souple([EtapeTolerante].self, .etapes) ?? []).compactMap { $0.etape }.map { e in
            var e = e
            let n = vus[e.id, default: 0]
            vus[e.id] = n + 1
            if n > 0 { e.id += "|\(n)" }
            return e
        }
    }

    /// Exécution provisoire, affichée dès la réponse de `lancer` en attendant le fichier du moteur.
    static func provisoire(id: String, tache: TacheClaude, jour: String?) -> ExecutionClaude {
        ExecutionClaude(id: id, tache: tache.rawValue, jour: jour, titre: tache.titreEnCours, etat: "en_attente",
                        debut: nil, fin: nil, duree_s: 0, etapes: [], message: nil, resultat: nil, erreur: nil,
                        ecran_suivant: nil, session: nil, cout_usd: nil)
    }

    /// Réponse `{"id": null, "etat": "aucune"}` : aucune exécution connue.
    var aucune: Bool { id.isEmpty || etat == "aucune" }
    /// En attente ou en cours : l'app la suit de près (toutes les 0,7 s).
    var enCours: Bool { etat == "en_attente" || etat == "en_cours" }
    var terminee: Bool { etat == "termine" || etat == "erreur" || etat == "annule" }
    var reussie: Bool { etat == "termine" }
    var tacheClaude: TacheClaude? { tache.flatMap { TacheClaude(rawValue: $0) } }
    var ecranSuivant: Ecran? { ecran_suivant.flatMap { Ecran(rawValue: $0) } }
    var dateDebut: Date? { ExecutionClaude.date(debut) }
    var dateFin: Date? { ExecutionClaude.date(fin) }

    /// Titre à afficher (celui du moteur, sinon celui de la tâche).
    var titreAffiche: String { titre ?? tacheClaude?.titreEnCours ?? "Claude travaille" }

    var libelleEtat: String {
        switch etat {
        case "en_attente": return "Claude se prépare"
        case "en_cours": return "Claude travaille"
        case "termine": return "Terminé"
        case "erreur": return "Interrompu"
        case "annule": return "Arrêté"
        case "aucune": return "Rien pour l'instant"
        default: return "État inconnu"
        }
    }

    /// L'étape en cours (la première non faite, sinon la dernière) tant que Claude travaille.
    var etapeCourante: EtapeClaude? {
        guard enCours else { return nil }
        return etapes.first(where: { !$0.fait }) ?? etapes.last
    }

    /// Durée écoulée : fixe une fois finie, vivante pendant l'exécution (passer la date d'un TimelineView).
    func duree(a maintenant: Date = Date()) -> TimeInterval? {
        if terminee, let d = duree_s { return d }
        guard let debut = dateDebut else { return duree_s }
        return max(0, (dateFin ?? (enCours ? maintenant : debut)).timeIntervalSince(debut))
    }

    /// « 42 s », « 3 min 05 », « 1 h 02 ».
    func libelleDuree(a maintenant: Date = Date()) -> String? {
        guard let d = duree(a: maintenant) else { return nil }
        let s = Int(d.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return String(format: "%d min %02d", s / 60, s % 60) }
        return String(format: "%d h %02d", s / 3600, (s % 3600) / 60)
    }

    /// Vrai si cette exécution a commencé après l'autre (dates, sinon identifiants horodatés).
    func plusRecente(que autre: ExecutionClaude) -> Bool {
        if let a = dateDebut, let b = autre.dateDebut, a != b { return a > b }
        return id > autre.id
    }

    /// Formateurs partagés (en créer un à chaque appel coûte cher dans un `TimelineView`).
    private static let iso = ISO8601DateFormatter()
    private static let isoFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ texte: String?) -> Date? {
        guard let t = texte?.nonVide else { return nil }
        return iso.date(from: t) ?? isoFractions.date(from: t)
    }
}

/// Lit une étape sans faire échouer toute la liste si l'une d'elles est mal formée.
private struct EtapeTolerante: Decodable {
    let etape: EtapeClaude?
    init(from decoder: Decoder) throws { etape = try? EtapeClaude(from: decoder) }
}

/// `./studio claude historique` : une liste, ou un objet qui la contient.
struct ListeExecutions: Decodable {
    var executions: [ExecutionClaude] = []

    init(from decoder: Decoder) throws {
        if let liste = try? [ExecutionClaude](from: decoder) {
            executions = liste
            return
        }
        let c = try decoder.container(keyedBy: CleJSON.self)
        executions = c.souple([ExecutionClaude].self, CleJSON("executions"))
            ?? c.souple([ExecutionClaude].self, CleJSON("historique")) ?? []
    }
}

/// `./studio claude lancer …` → lance | deja_en_cours | non_connecte | absent | erreur
struct ReponseLancement: Decodable {
    var etat = ""
    /// Identifiant de l'exécution lancée (`lance`, `erreur`) ou de celle qui occupe déjà Claude (`deja_en_cours`).
    var id: String?
    var conseil: String?
}

extension ReponseLancement {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        id = c.texte(CleJSON("id"))?.nonVide
        conseil = c.texte(CleJSON("conseil"))?.nonVide
    }

    var lance: Bool { etat == "lance" || etat == "termine" }
    var dejaEnCours: Bool { etat == "deja_en_cours" }
    /// Claude n'est pas utilisable : installé mais pas connecté (`non_connecte`) ou introuvable (`absent`).
    var nonConnecte: Bool { etat == "non_connecte" }
    var absent: Bool { etat == "absent" }
}

/// `./studio claude connecter [--console]` → navigateur_ouvert | terminal_ouvert | deja_connecte | absent | echec
struct ReponseConnexion: Decodable {
    var etat = ""
    /// Lien de secours si le navigateur ne s'est pas ouvert.
    var url: String?
    var conseil: String?
    /// La page de connexion affichera un code à coller dans l'app (`./studio claude code <code>`).
    var code_attendu = false
}

extension ReponseConnexion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        url = c.texte(CleJSON("url"))?.nonVide
        conseil = c.texte(CleJSON("conseil"))?.nonVide
        code_attendu = c.booleen(CleJSON("code_attendu")) ?? false
    }

    /// La page de connexion (ou la fenêtre Terminal de secours) est ouverte : il reste à attendre.
    var enAttente: Bool { etat == "navigateur_ouvert" || etat == "terminal_ouvert" }
    var dejaConnecte: Bool { etat == "deja_connecte" }
    var lien: URL? { url.flatMap { URL(string: $0) } }
}

/// `./studio claude installer` → installe | deja_installe | echec
struct ReponseInstallation: Decodable {
    var etat = ""
    var chemin: String?
    /// Dernières lignes du journal d'installation.
    var journal: String?
    var conseil: String?
}

extension ReponseInstallation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        chemin = c.texte(CleJSON("chemin"))?.nonVide
        journal = c.texte(CleJSON("journal"))?.nonVide
        conseil = c.texte(CleJSON("conseil"))?.nonVide
    }
}

// MARK: - Planification (./studio planifier …)

struct Planification: Decodable, Equatable {
    var active = false
    var taches: [TachePlanifiee] = []
    var dossier_agents: String?
    var conseil: String?
}

extension Planification {
    enum CodingKeys: String, CodingKey { case active, taches, dossier_agents, conseil }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.booleen(.active) ?? false
        taches = c.souple([TachePlanifiee].self, .taches) ?? []
        dossier_agents = c.texte(.dossier_agents)?.nonVide
        conseil = c.texte(.conseil)?.nonVide
    }
}

/// Une tâche automatique (LaunchAgent) : matin, publication ou bilan.
struct TachePlanifiee: Decodable, Identifiable, Equatable {
    var id = ""
    var titre: String?
    /// En clair : « chaque jour à 08:00 ».
    var quand: String?
    /// Chargée dans launchd (elle tournera même app fermée).
    var chargee = false
    /// Prochain déclenchement (ISO 8601, minute près), si la planification est active et la tâche chargée.
    var prochaine: String?
}

extension TachePlanifiee {
    enum CodingKeys: String, CodingKey { case id, titre, quand, chargee, prochaine }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texte(.id) ?? ""
        titre = c.texte(.titre)?.nonVide
        quand = c.texte(.quand)?.nonVide
        chargee = c.booleen(.chargee) ?? false
        prochaine = c.texte(.prochaine)?.nonVide
    }

    /// `prochaine` en date (le moteur l'écrit sans secondes : « 2026-11-20T08:00+01:00 »).
    var dateProchaine: Date? {
        guard let t = prochaine else { return nil }
        if let d = ExecutionClaude.date(t) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    /// « demain à 08:00 », « vendredi à 12:30 », « aujourd'hui à 18:30 ».
    var libelleProchaine: String? {
        guard let d = dateProchaine else { return nil }
        let cal = Calendar.current
        let heure = DateFormatter()
        heure.locale = Locale(identifier: "fr_FR")
        heure.dateFormat = "HH:mm"
        let h = heure.string(from: d)
        if cal.isDateInToday(d) { return "aujourd'hui à \(h)" }
        if cal.isDateInTomorrow(d) { return "demain à \(h)" }
        let jour = DateFormatter()
        jour.locale = Locale(identifier: "fr_FR")
        jour.dateFormat = "EEEE"
        return "\(jour.string(from: d)) à \(h)"
    }

    var titreAffiche: String {
        if let t = titre { return t }
        switch id {
        case "matin": return "Idées du matin"
        case "publication": return "Publication"
        case "bilan": return "Bilan de la semaine"
        default: return id
        }
    }

    var symbole: String {
        switch id {
        case "matin": return "sunrise"
        case "publication": return "paperplane"
        case "bilan": return "chart.line.uptrend.xyaxis"
        default: return "clock"
        }
    }
}

// MARK: - Apparence (config/app.yaml, ./studio app apparence)

struct CouleursApparence: Codable, Equatable {
    /// Boutons, sélection (olive).
    var accent = "#3d4130"
    /// Fonds doux, badges (pêche).
    var accent_doux = "#efdccd"
    /// Fond en mode clair (papier).
    var fond_clair = "#f7f3ed"
    var fond_sombre = "#17160f"
    var succes = "#3f6b45"
    var alerte = "#a8551c"
}

extension CouleursApparence {
    enum CodingKeys: String, CodingKey { case accent, accent_doux, fond_clair, fond_sombre, succes, alerte }

    init(from decoder: Decoder) throws {
        let d = CouleursApparence()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accent = c.texte(.accent) ?? d.accent
        accent_doux = c.texte(.accent_doux) ?? d.accent_doux
        fond_clair = c.texte(.fond_clair) ?? d.fond_clair
        fond_sombre = c.texte(.fond_sombre) ?? d.fond_sombre
        succes = c.texte(.succes) ?? d.succes
        alerte = c.texte(.alerte) ?? d.alerte
    }

    /// Chaque couleur au format « #rrggbb » ; une valeur illisible reprend la couleur d'origine.
    func normalisees() -> CouleursApparence {
        let d = CouleursApparence()
        func hex(_ v: String, _ defaut: String) -> String {
            var s = v.trimmingCharacters(in: .whitespaces).lowercased()
            if !s.hasPrefix("#") { s = "#" + s }
            if s.count == 4 { s = "#" + s.dropFirst().map { "\($0)\($0)" }.joined() }   // #abc → #aabbcc
            let chiffres = s.dropFirst()
            return chiffres.count == 6 && chiffres.allSatisfy({ $0.isHexDigit }) ? s : defaut
        }
        return CouleursApparence(accent: hex(accent, d.accent), accent_doux: hex(accent_doux, d.accent_doux),
                                 fond_clair: hex(fond_clair, d.fond_clair), fond_sombre: hex(fond_sombre, d.fond_sombre),
                                 succes: hex(succes, d.succes), alerte: hex(alerte, d.alerte))
    }
}

/// Apparence de l'app, personnalisable par Claude : l'app la relit dès que config/app.yaml change.
struct Apparence: Codable, Equatable {
    var nom_affiche = "Studio Instagram"
    /// En tête de l'écran Aujourd'hui.
    var salutation = "Bonjour"
    /// auto | clair | sombre
    var mode = "auto"
    var couleurs = CouleursApparence()
    /// Dégradé de fond : provence | lavande | aube | sauge | nuit
    var ambiance = "provence"
    /// Police du texte : jakarta (Plus Jakarta Sans) | systeme | arrondie
    var police = "jakarta"
    /// Titres : police (la même que le texte) | serif | arrondi | standard
    var titres = "police"
    /// Fine trame de points sur le fond : toujours coupée (fixée par le moteur).
    var points = false
    /// compacte | confortable | aeree
    var densite = "confortable"
    /// Rayon des coins, de 0 à 28.
    var arrondi = 14
    /// aucune | discretes | normales | riches
    var animations = "normales"
    /// pleines | contours
    var icones = "pleines"
    /// Écrans de la barre d'icônes, fixés par le moteur : aujourdhui, galeries, statistiques, reglages
    /// (« + » ouvre `creation` ; idées et aperçu passent par « + » et l'accueil ; charte et règles par les Réglages).
    var ecrans = Apparence.ecransEssentiels.map(\.rawValue)

    /// Les valeurs d'origine (ARCHITECTURE.md §4.3).
    static let defaut = Apparence()

    /// Seuls champs que la photographe (ou Claude) peut changer ; le moteur fixe tous les autres.
    static let reglables = ["nom_affiche", "salutation", "mode", "ambiance"]
    static let ecransEssentiels: [Ecran] = [.aujourdhui, .galeries, .statistiques, .reglages]

    static let modes = ["auto", "clair", "sombre"]
    static let ambiances = ["provence", "lavande", "aube", "sauge", "nuit"]
    static let polices = ["jakarta", "systeme", "arrondie"]
    static let stylesTitres = ["police", "serif", "arrondi", "standard"]
    static let densites = ["compacte", "confortable", "aeree"]
    static let niveauxAnimations = ["aucune", "discretes", "normales", "riches"]
    static let stylesIcones = ["pleines", "contours"]

    /// Libellés à montrer dans Réglages › Apparence (valeur → texte).
    static func libelle(_ valeur: String) -> String {
        switch valeur {
        case "auto": return "Automatique"
        case "clair": return "Clair"
        case "sombre": return "Sombre"
        case "provence": return "Provence"
        case "lavande": return "Lavande"
        case "aube": return "Aube"
        case "sauge": return "Sauge"
        case "nuit": return "Nuit"
        case "jakarta": return "Plus Jakarta Sans"
        case "systeme": return "Police du Mac"
        case "arrondie": return "Arrondie"
        case "police": return "Comme le texte"
        case "serif": return "Serif"
        case "standard": return "Standard"
        case "compacte": return "Compacte"
        case "confortable": return "Confortable"
        case "aeree": return "Aérée"
        case "aucune": return "Aucune"
        case "discretes": return "Discrètes"
        case "normales": return "Normales"
        case "riches": return "Riches"
        case "pleines": return "Pleines"
        case "contours": return "Contours"
        default: return valeur
        }
    }
}

extension Apparence {
    enum CodingKeys: String, CodingKey {
        case nom_affiche, salutation, mode, couleurs, ambiance, police, titres, points, densite, arrondi, animations,
             icones, ecrans
    }

    init(from decoder: Decoder) throws {
        let d = Apparence.defaut
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nom_affiche = c.texte(.nom_affiche) ?? d.nom_affiche
        salutation = c.texte(.salutation) ?? d.salutation
        mode = c.texte(.mode) ?? d.mode
        couleurs = c.souple(CouleursApparence.self, .couleurs) ?? d.couleurs
        ambiance = c.texte(.ambiance) ?? d.ambiance
        police = c.texte(.police) ?? d.police
        points = c.booleen(.points) ?? d.points
        titres = c.texte(.titres) ?? d.titres
        densite = c.texte(.densite) ?? d.densite
        arrondi = c.entier(.arrondi) ?? d.arrondi
        animations = c.texte(.animations) ?? d.animations
        icones = c.texte(.icones) ?? d.icones
        ecrans = c.souple([String].self, .ecrans) ?? d.ecrans
    }

    /// Les écrans à montrer, dans l'ordre voulu. « aujourdhui » et « reglages » sont toujours là.
    var ecransVisibles: [Ecran] {
        var liste: [Ecran] = []
        for nom in ecrans {
            if let e = Ecran(rawValue: Apparence.simplifier(nom)), !liste.contains(e) { liste.append(e) }
        }
        if !liste.contains(.aujourdhui) { liste.insert(.aujourdhui, at: 0) }
        if !liste.contains(.reglages) { liste.append(.reglages) }
        return liste
    }

    func estVisible(_ e: Ecran) -> Bool { ecransVisibles.contains(e) }

    /// Toujours des valeurs connues (casse et accents ignorés), sinon celles d'origine.
    func normalisee() -> Apparence {
        let d = Apparence.defaut
        func choix(_ v: String, _ permis: [String], _ defaut: String) -> String {
            let s = Apparence.simplifier(v)
            return permis.contains(s) ? s : defaut
        }
        var a = self
        a.nom_affiche = nom_affiche.nonVide ?? d.nom_affiche
        a.salutation = salutation.nonVide ?? d.salutation
        a.mode = choix(mode, Apparence.modes, d.mode)
        a.ambiance = choix(ambiance, Apparence.ambiances, d.ambiance)
        // Comme le moteur : tout le reste garde sa valeur d'origine (app simple et rapide).
        a.couleurs = d.couleurs
        a.police = d.police
        a.titres = d.titres
        a.points = false
        a.densite = d.densite
        a.arrondi = d.arrondi
        a.animations = d.animations
        a.icones = d.icones
        a.ecrans = d.ecrans
        return a
    }

    /// « Aérée » → « aeree », « Discrètes » → « discretes ».
    static func simplifier(_ texte: String) -> String {
        texte.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }
}

// MARK: - Assistant de création (./studio app modifier-post, candidats, musique chercher)

/// Une photo du post envoyée à `modifier-post`, dans l'ordre voulu. Seuls les champs non nuls partent :
/// une photo déjà dans le post garde ses réglages, une nouvelle reçoit ceux que le moteur choisit.
struct MediaModifie: Encodable, Equatable, Identifiable {
    var photo_id: String
    /// plein_cadre | marges
    var presentation: String? = nil
    /// clair | sombre | papier
    var fond: String? = nil
    var texte_alternatif: String? = nil

    var id: String { photo_id }

    static let presentations = ["plein_cadre", "marges"]
    static let fonds = ["clair", "sombre", "papier"]
}

/// Corps de `./studio app modifier-post <jour> <fichier>` : seules les parties présentes sont modifiées.
struct ModificationPost: Encodable {
    var medias: [MediaModifie]? = nil
    var legende: String? = nil
    var musique: Musique? = nil

    var vide: Bool { medias == nil && legende == nil && musique == nil }
}

/// Résultat de `regles.valider_post` (champ `controle` de `modifier-post`).
struct ControlePost: Decodable, Equatable {
    var conforme = false
    var erreurs: [String] = []
    var avertissements: [String] = []
    var alertes: [String] = []
    /// Longueur de la légende.
    var caracteres: Int?
}

extension ControlePost {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        conforme = c.booleen(CleJSON("conforme")) ?? false
        erreurs = c.souple([String].self, CleJSON("erreurs")) ?? []
        avertissements = c.souple([String].self, CleJSON("avertissements")) ?? []
        alertes = c.souple([String].self, CleJSON("alertes")) ?? []
        caracteres = c.entier(CleJSON("caracteres"))
        if caracteres == nil, let l = try? c.nestedContainer(keyedBy: CleJSON.self, forKey: CleJSON("legende")) {
            caracteres = l.entier(CleJSON("caracteres"))
        }
    }
}

/// `modifier-post` → enregistre | inchange
struct ReponseModificationPost: Decodable {
    var etat = ""
    /// photos | legende | musique
    var changements: [String] = []
    var controle: ControlePost?
    var avertissements: [String] = []
}

extension ReponseModificationPost {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        changements = c.souple([String].self, CleJSON("changements")) ?? []
        controle = c.souple(ControlePost.self, CleJSON("controle"))
        avertissements = c.souple([String].self, CleJSON("avertissements")) ?? []
    }
}

/// `./studio app candidats <serie>` : une photo de la galerie à proposer (meilleures notes d'abord).
struct PhotoCandidate: Decodable, Identifiable, Equatable {
    var id = ""
    /// Note de Claude, de 1 à 5.
    var note: Double?
    var pilier: String?
    var description: String?
    /// portrait | paysage | carre
    var orientation: String?
    /// Chemin absolu de la vignette, ou nil si elle n'existe pas encore.
    var vignette: String?
}

extension PhotoCandidate {
    enum CodingKeys: String, CodingKey { case id, note, pilier, description, orientation, vignette }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texte(.id) ?? c.entier(.id).map(String.init) ?? ""
        note = c.nombre(.note)
        pilier = c.texte(.pilier)?.nonVide
        description = c.texte(.description)?.nonVide
        orientation = c.texte(.orientation)?.nonVide
        vignette = c.texte(.vignette)?.nonVide
    }

    var urlVignette: URL? { vignette.map { URL(fileURLWithPath: $0) } }
    var paysage: Bool { orientation == "paysage" }
    /// Nombre d'étoiles pleines (0 à 5).
    var etoiles: Int { min(5, max(0, Int((note ?? 0).rounded()))) }
}

/// `./studio musique chercher <mots>` : une piste de la bibliothèque musicale d'Instagram (route Facebook).
struct PisteMusique: Decodable, Identifiable, Equatable {
    var audio_id = ""
    var titre: String?
    var artiste: String?
    var duree_s: Double?
    var apercu_url: String?
    var lien_instagram: String?
    var pochette: String?

    var id: String { audio_id }
}

extension PisteMusique {
    enum CodingKeys: String, CodingKey { case audio_id, titre, artiste, duree_s, apercu_url, lien_instagram, pochette }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audio_id = c.texte(.audio_id) ?? c.entier(.audio_id).map(String.init) ?? ""
        titre = c.texte(.titre)?.nonVide
        artiste = c.texte(.artiste)?.nonVide
        duree_s = c.nombre(.duree_s)
        apercu_url = c.texte(.apercu_url)?.nonVide
        lien_instagram = c.texte(.lien_instagram)?.nonVide
        pochette = c.texte(.pochette)?.nonVide
    }

    /// La musique à envoyer à `modifierPost` pour cette piste (Reel : volume de la vidéo d'origine coupé).
    func musique(volumeVideo: Double = 0) -> Musique {
        Musique(mode: "api_reel", titre: titre, artiste: artiste, apercu_url: apercu_url, audio_id: audio_id,
                volume_musique: 100, volume_video: volumeVideo)
    }
}

// MARK: - Instagram (./studio app instagram, enregistrer-instagram)

/// État de la connexion à Instagram (aucun jeton n'est jamais montré).
struct InstagramEtat: Decodable, Equatable {
    /// valide | absent | invalide
    var etat = ""
    /// facebook | instagram
    var route: String?
    var compte: String?
    var abonnes: Int?
    /// Date d'expiration du jeton (AAAA-MM-JJ) ou « jamais ».
    var expire_le: String?
    var erreur: String?
}

extension InstagramEtat {
    enum CodingKeys: String, CodingKey { case etat, route, compte, abonnes, expire_le, erreur }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        etat = c.texte(.etat) ?? ""
        route = c.texte(.route)?.nonVide
        compte = c.texte(.compte)?.nonVide
        abonnes = c.entier(.abonnes)
        expire_le = c.texte(.expire_le)?.nonVide
        erreur = c.texte(.erreur)?.nonVide
    }

    var connecte: Bool { etat == "valide" }
    var absent: Bool { etat == "absent" }

    /// « Connecté à @atelier · 1 240 abonnés », « Pas encore connecté », « Connexion à refaire ».
    var libelle: String {
        switch etat {
        case "valide":
            var t = compte.map { "Connecté à @\($0.hasPrefix("@") ? String($0.dropFirst()) : $0)" } ?? "Connecté"
            if let n = abonnes {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.locale = Locale(identifier: "fr_FR")
                t += " · \(f.string(from: NSNumber(value: n)) ?? "\(n)") abonnés"
            }
            return t
        case "absent": return "Pas encore connecté"
        default: return "Connexion à refaire"
        }
    }

    /// Jours avant l'expiration du jeton (nil si inconnue ou « jamais »).
    var joursRestants: Int? {
        guard let t = expire_le, t != "jamais" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(t.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day
    }
}

/// Identifiants collés par la photographe : écrits dans un fichier privé (0600), lus puis effacés par le moteur.
struct IdentifiantsInstagram: Encodable {
    /// facebook | instagram
    var route: String
    var app_id: String
    var app_secret: String
    var jeton: String
}

/// `enregistrer-instagram` → connecte | refuse | echec
struct ReponseInstagram: Decodable {
    var etat = ""
    var erreurs: [String] = []
    var compte: String?
    var abonnes: Int?
}

extension ReponseInstagram {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleJSON.self)
        etat = c.texte(CleJSON("etat")) ?? ""
        erreurs = c.souple([String].self, CleJSON("erreurs")) ?? []
        compte = c.texte(CleJSON("compte"))?.nonVide
        abonnes = c.entier(CleJSON("abonnes"))
    }
}

// MARK: - Listes tolérantes

/// Une liste JSON dont les éléments illisibles sont ignorés (au lieu de faire échouer toute la liste).
struct ListeSouple<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let e = try? c.decode(Element.self) {
                elements.append(e)
            } else if (try? c.decode(ElementIgnore.self)) == nil {
                break
            }
        }
    }
}

private struct ElementIgnore: Decodable {
    init(from decoder: Decoder) throws {}
}
