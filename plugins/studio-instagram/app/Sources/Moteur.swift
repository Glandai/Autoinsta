import AppKit
import Foundation
import SwiftUI

enum Ecran: String, CaseIterable, Identifiable {
    /// `creation` : l'assistant « Nouveau post » (bouton « + »), hors de la liste d'écrans par défaut.
    case aujourdhui, idees, creation, apercu, galeries, statistiques, reglages, charte, regles
    var id: String { rawValue }

    var titre: String {
        switch self {
        case .aujourdhui: return "Aujourd'hui"
        case .idees: return "Idées du jour"
        case .creation: return "Nouveau post"
        case .apercu: return "Aperçu du post"
        case .galeries: return "Galeries"
        case .statistiques: return "Statistiques"
        case .reglages: return "Réglages"
        case .charte: return "Charte"
        case .regles: return "Règles"
        }
    }

    /// Symboles de DESIGN.md §5.
    var symbole: String {
        switch self {
        case .aujourdhui: return "sun.max"
        case .idees: return "lightbulb"
        case .creation: return "plus"
        case .apercu: return "iphone"
        case .galeries: return "photo.stack"
        case .statistiques: return "chart.line.uptrend.xyaxis"
        case .reglages: return "gearshape"
        case .charte: return "text.book.closed"
        case .regles: return "checkmark.shield"
        }
    }
}

/// Ce que l'app confie à Claude : `./studio claude lancer <tâche>` (ARCHITECTURE.md §4.1).
enum TacheClaude: String, CaseIterable, Identifiable, Codable {
    case matin, creation, retouche, galerie, bilan, demande
    var id: String { rawValue }

    /// Nom court, pour un bouton ou un historique.
    var titre: String {
        switch self {
        case .matin: return "Idées du jour"
        case .creation: return "Préparer le post"
        case .retouche: return "Retoucher le post"
        case .galerie: return "Analyser une galerie"
        case .bilan: return "Bilan de la semaine"
        case .demande: return "Demande à Claude"
        }
    }

    /// Phrase affichée pendant le travail (la même que le titre donné par le moteur).
    var titreEnCours: String {
        switch self {
        case .matin: return "Claude prépare les idées du jour"
        case .creation: return "Claude prépare ton post"
        case .retouche: return "Claude retouche ton post"
        case .galerie: return "Claude analyse la galerie"
        case .bilan: return "Claude fait le bilan de la semaine"
        case .demande: return "Claude s'occupe de ta demande"
        }
    }

    /// Symbole SF (macOS 14).
    var symbole: String {
        switch self {
        case .matin: return "sunrise"
        case .creation: return "wand.and.stars"
        case .retouche: return "pencil.line"
        case .galerie: return "photo.stack"
        case .bilan: return "chart.line.uptrend.xyaxis"
        case .demande: return "text.bubble"
        }
    }

    /// Les tâches d'une journée partagent une conversation de Claude (et suivent le jour affiché).
    var duJour: Bool { self == .matin || self == .creation || self == .retouche }
    /// `consigne` obligatoire (le texte de la retouche ou de la demande).
    var demandeConsigne: Bool { self == .retouche || self == .demande }
    /// `serie` obligatoire (l'identifiant de la galerie).
    var demandeSerie: Bool { self == .galerie }
}

/// Message qui mène à Claude quand il manque (bandeau avec un bouton) : voir `EtatApp.invitationClaude`.
struct InvitationClaude: Equatable {
    enum Action: Equatable { case installer, connecter }
    var action: Action
    var texte: String

    var libelleBouton: String { action == .installer ? "Installer Claude Code" : "Se connecter à Claude" }
    var symbole: String { action == .installer ? "arrow.down.circle" : "person.crop.circle.badge.checkmark" }

    static func installer(_ conseil: String?) -> InvitationClaude {
        InvitationClaude(action: .installer, texte: conseil ?? "Claude Code n'est pas installé sur ce Mac. "
            + "Clique sur « Installer Claude Code » : c'est gratuit et prend une minute.")
    }

    static func connecter(_ conseil: String?) -> InvitationClaude {
        InvitationClaude(action: .connecter, texte: conseil ?? "Claude n'est pas connecté. Clique sur "
            + "« Se connecter » : la page de connexion d'Anthropic s'ouvre dans ton navigateur.")
    }
}

struct ErreurMoteur: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Tout ce que l'app sait du studio. Elle ne lit que des réponses JSON du moteur
/// (`./studio app …`, `./studio claude …`, `./studio planifier …`) et quelques fichiers du dossier
/// pour se rafraîchir toute seule. API pour les vues : ARCHITECTURE.md §7.
@MainActor
final class EtatApp: ObservableObject {
    @Published var dossier: URL
    @Published var ecran: Ecran? = .aujourdhui
    @Published var jour: String
    @Published var vue: VueJour?
    @Published var jours: [ResumeJour] = []
    @Published var reglages: Reglages?
    @Published var galeries: [Galerie] = []
    @Published var charte: Charte?
    @Published var regles: Regles?
    @Published var memoire: Memoire?
    @Published var sante: Sante?
    @Published var occupe = false
    @Published var message: String?
    @Published var erreur: String?

    // MARK: 2.0 — Claude, planification, apparence

    /// Claude Code sur ce Mac (installé, connecté…) ; nil tant que le moteur n'a pas répondu.
    @Published var claude: ClaudeStatut?
    /// L'exécution en cours, ou la dernière connue. Suivie de près tant qu'elle est en attente ou en cours.
    @Published var execution: ExecutionClaude?
    /// Les 20 dernières exécutions (sans leurs étapes), la plus récente d'abord.
    @Published var historiqueClaude: [ExecutionClaude] = []
    /// Les tâches automatiques du Mac (launchd).
    @Published var planification: Planification?
    /// Apparence (config/app.yaml), normalisée, relue dès que le fichier change.
    @Published var apparence: Apparence = .defaut
    /// Claude manque pour ce qui vient d'être demandé : à montrer avec son bouton (`accepterInvitation()`).
    @Published var invitationClaude: InvitationClaude?
    /// La page de connexion est ouverte : l'app attend (3 min au plus) que Claude soit connecté.
    @Published var connexionEnCours = false
    /// La page de connexion va afficher un code à coller dans l'app (`envoyerCodeConnexion`).
    @Published var codeConnexionAttendu = false
    /// Le code est transmis : le moteur attend la connexion (jusqu'à ~20 s).
    @Published var envoiCodeEnCours = false
    /// Lien de secours vers la page de connexion, si le navigateur ne s'est pas ouvert.
    @Published var lienConnexion: URL?
    @Published var installationEnCours = false
    /// Entre le clic et la réponse du moteur à `lancer`.
    @Published var lancementEnCours = false
    /// Connexion à Instagram (`chargerInstagram()`) ; nil tant qu'elle n'a pas été vérifiée.
    @Published var instagram: InstagramEtat?
    @Published var connexionInstagramEnCours = false
    /// `modifierPost` refait la mise en page, le contrôle et l'aperçu (quelques secondes).
    @Published var modificationEnCours = false
    /// Augmente quand les images du post sont refaites (mêmes chemins, nouveau contenu) : `.id(etat.versionImages)`
    /// sur une image locale force sa relecture.
    @Published var versionImages = 0

    private var derniereDemande: String?
    private var signatures: [String: Date] = [:]
    private var minuteur: Timer?
    private var minuteurRapide: Timer?
    private var demarre = false

    /// Exécutions vues en attente ou en cours par cette app : seules leurs fins mènent à l'écran suivant.
    private var executionsSuivies: Set<String> = []
    private var executionsFinies: Set<String> = []
    private var signatureExecution: Date?
    private var dernierSigneDeVie = Date.distantPast
    private var controleEnCours = false
    private var jetonConnexion: UUID?

    init() {
        dossier = EtatApp.trouverDossier()
        jour = EtatApp.aujourdhuiISO()
    }

    // MARK: Démarrage et surveillance

    static func trouverDossier() -> URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Studio Instagram/reglages.json")
        if let data = try? Data(contentsOf: support),
           let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chemin = objet["dossier"] as? String {
            return URL(fileURLWithPath: chemin)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Studio-Instagram")
    }

    static func aujourdhuiISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: Date())
    }

    var studioInstalle: Bool {
        FileManager.default.isExecutableFile(atPath: dossier.appendingPathComponent("studio").path)
    }

    /// Claude est installé et connecté.
    var claudePret: Bool { claude?.pret == true }
    /// Une exécution de Claude est en attente ou en cours.
    var claudeTravaille: Bool { execution?.enCours == true }

    func demarrer() {
        guard !demarre else { return }
        demarre = true
        surveiller(premierPassage: true)
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.surveiller(premierPassage: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        minuteur = t
        Task { await toutCharger() }
    }

    func choisirDossier() {
        let panneau = NSOpenPanel()
        panneau.canChooseDirectories = true
        panneau.canChooseFiles = false
        panneau.prompt = "Utiliser ce dossier"
        panneau.message = "Choisis le dossier de travail du Studio Instagram (celui qui contient « studio »)."
        if panneau.runModal() == .OK, let url = panneau.url {
            let support = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Studio Instagram")
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let data = try? JSONSerialization.data(withJSONObject: ["dossier": url.path], options: [.prettyPrinted])
            try? data?.write(to: support.appendingPathComponent("reglages.json"))
            changerDossier(url)
        }
    }

    /// Un autre studio : tout ce qui venait de l'ancien est oublié, puis tout est rechargé.
    private func changerDossier(_ url: URL) {
        dossier = url
        signatures = [:]
        execution = nil
        historiqueClaude = []
        executionsSuivies = []
        executionsFinies = []
        signatureExecution = nil
        claude = nil
        planification = nil
        invitationClaude = nil
        ajusterSuiviRapide()
        Task { await toutCharger() }
    }

    private func surveiller(premierPassage: Bool) {
        // Le studio qui sollicite l'app l'indique dans le pointeur : l'app le suit.
        let pointe = EtatApp.trouverDossier()
        if pointe.standardizedFileURL.path != dossier.standardizedFileURL.path {
            changerDossier(pointe)
            return
        }
        let demandeURL = dossier.appendingPathComponent(".ui/demande.json")
        if let data = try? Data(contentsOf: demandeURL),
           let d = try? JSONDecoder().decode(Demande.self, from: data), d.id != derniereDemande {
            derniereDemande = d.id
            if !premierPassage || EtatApp.estRecente(d.le) {
                if let j = d.jour { jour = j }
                if let e = Ecran(rawValue: d.ecran) { withAnimation(animationEcran) { ecran = e } }
                if d.activer ?? true {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                Task { await chargerJour() }
            }
        }
        var change = false
        for nom in ["etat.json", "idees.json", "post.json", "decision.json"] {
            if aChange(dossier.appendingPathComponent("jours/\(jour)/\(nom)")) {
                change = true
                if nom == "post.json" && !premierPassage { versionImages += 1 }
            }
        }
        if change && !premierPassage && !occupe && !modificationEnCours {
            Task { await chargerJour() }
        }
        // Claude : une nouvelle exécution (lancée par l'app, la planification ou Claude) remplace actuel.json.
        let actuel = dossier.appendingPathComponent(".ui/claude/actuel.json")
        if aChange(actuel) && !premierPassage, let id = EtatApp.lireIdentifiant(actuel), id != execution?.id {
            Task { await chargerExecution() }
        }
        // Apparence : modifiée dans l'app ou par Claude, elle s'applique aussitôt.
        if aChange(dossier.appendingPathComponent("config/app.yaml")) && !premierPassage {
            Task { await chargerApparence(silencieux: true) }
        }
        ajusterSuiviRapide()
    }

    /// Vrai si la date de modification du fichier a changé depuis le dernier passage (apparition et disparition comprises).
    private func aChange(_ url: URL) -> Bool {
        let date = EtatApp.dateModification(url)
        if signatures[url.path] == date { return false }
        signatures[url.path] = date
        return true
    }

    private static func dateModification(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private static func lireIdentifiant(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (objet["id"] as? String)?.nonVide
    }

    static func estRecente(_ le: String?) -> Bool {
        guard let le = le, let date = ISO8601DateFormatter().date(from: le) else { return false }
        return Date().timeIntervalSince(date) < 180
    }

    // MARK: Appels au moteur

    nonisolated private static func executer(_ arguments: [String], dossier: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { suite in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = dossier.appendingPathComponent("studio")
                p.arguments = arguments
                p.currentDirectoryURL = dossier
                let sortie = Pipe()
                p.standardOutput = sortie
                p.standardError = FileHandle.nullDevice
                p.standardInput = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    suite.resume(throwing: ErreurMoteur(message: "Impossible de lancer le studio dans \(dossier.path) : \(error.localizedDescription)"))
                    return
                }
                let data = sortie.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                suite.resume(returning: data)
            }
        }
    }

    func appeler<T: Decodable>(_ type: T.Type, _ arguments: [String]) async throws -> T {
        guard studioInstalle else {
            throw ErreurMoteur(message: "Le studio n'est pas installé dans \(dossier.path). Lance /studio-instagram:studio-installation dans Claude, ou choisis le bon dossier.")
        }
        let data = try await EtatApp.executer(arguments, dossier: dossier)
        if let e = try? JSONDecoder().decode(ReponseErreur.self, from: data), let m = e.erreur {
            throw ErreurMoteur(message: m)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let extrait = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw ErreurMoteur(message: "Réponse inattendue du studio : \(error.localizedDescription) \(extrait)")
        }
    }

    private func fichierTemporaire(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    func envoyer<T: Encodable>(_ valeur: T, action: String, avant: [String] = []) async -> Bool {
        do {
            let encodeur = JSONEncoder()
            encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = try fichierTemporaire(try encodeur.encode(valeur), extension: "json")
            defer { try? FileManager.default.removeItem(at: url) }
            let r = try await appeler(ReponseEnregistrement.self, ["app", action] + avant + [url.path])
            if let erreurs = r.erreurs, !erreurs.isEmpty {
                erreur = erreurs.joined(separator: "\n")
                return false
            }
            if r.etat == "refuse" {
                erreur = "Le studio a refusé ces valeurs."
                return false
            }
            message = "Enregistré."
            return true
        } catch {
            erreur = error.localizedDescription
            return false
        }
    }

    func envoyerTexte(_ texte: String, action: String, avant: [String] = []) async -> Bool {
        do {
            let url = try fichierTemporaire(Data(texte.utf8), extension: "md")
            defer { try? FileManager.default.removeItem(at: url) }
            let r = try await appeler(ReponseEnregistrement.self, ["app", action] + avant + [url.path])
            if let erreurs = r.erreurs, !erreurs.isEmpty {
                erreur = erreurs.joined(separator: "\n")
                return false
            }
            message = "Enregistré."
            return true
        } catch {
            erreur = error.localizedDescription
            return false
        }
    }

    // MARK: Chargements

    func toutCharger() async {
        await chargerApparence(silencieux: true)
        await chargerJour()
        async let r: Void = chargerReglages()
        async let g: Void = chargerGaleries()
        async let s: Void = chargerSante()
        async let c: Void = chargerToutClaude()
        _ = await (r, g, s, c)
    }

    private func chargerToutClaude() async {
        await chargerExecution()
        await chargerClaude(silencieux: true)
        await chargerHistoriqueClaude()
        await chargerPlanification(silencieux: true)
    }

    func chargerJour() async {
        do {
            vue = try await appeler(VueJour.self, ["app", "jour", jour])
            jours = try await appeler([ResumeJour].self, ["app", "jours"])
        } catch {
            erreur = error.localizedDescription
        }
    }

    func chargerReglages() async {
        do { reglages = try await appeler(Reglages.self, ["app", "reglages"]) } catch { erreur = error.localizedDescription }
    }

    func chargerGaleries() async {
        do { galeries = try await appeler([Galerie].self, ["app", "galeries"]) } catch { erreur = error.localizedDescription }
    }

    func chargerCharte() async {
        do { charte = try await appeler(Charte.self, ["app", "charte"]) } catch { erreur = error.localizedDescription }
    }

    func chargerRegles() async {
        do { regles = try await appeler(Regles.self, ["app", "regles"]) } catch { erreur = error.localizedDescription }
    }

    func chargerMemoire() async {
        do { memoire = try await appeler(Memoire.self, ["app", "memoire"]) } catch { erreur = error.localizedDescription }
    }

    func chargerSante() async {
        do { sante = try await appeler(Sante.self, ["app", "sante"]) } catch { erreur = error.localizedDescription }
    }

    // MARK: Navigation

    /// Animation des changements d'écran, selon `apparence.animations` (nil : aucune).
    var animationEcran: Animation? {
        switch apparence.animations {
        case "aucune": return nil
        case "discretes": return .easeInOut(duration: 0.2)
        case "riches": return .spring(response: 0.5, dampingFraction: 0.8)
        default: return .easeInOut(duration: 0.35)
        }
    }

    /// Montre un écran (et un autre jour si besoin), avec l'animation choisie dans l'apparence.
    func montrer(_ e: Ecran, jour j: String? = nil) {
        if let j = j, j != jour {
            jour = j
            Task { await chargerJour() }
        }
        withAnimation(animationEcran) { ecran = e }
    }

    // MARK: Décisions

    /// Applique une décision (`choix`, `libre`, `approuver`, `retouche`, `reporter`) puis enchaîne :
    /// idée choisie → Claude crée le post ; retouche → Claude retouche ; sauf si une session de Claude
    /// attend déjà la décision (`claude_attend`), auquel cas c'est elle qui continue.
    func decider(_ action: String, _ valeur: String? = nil) async {
        occupe = true
        defer { occupe = false }
        let d: Decision
        do {
            var arguments = ["app", "decider", jour, action]
            if let v = valeur { arguments.append(v) }
            d = try await appeler(Decision.self, arguments)
        } catch {
            erreur = error.localizedDescription
            return
        }
        var suite: TacheClaude?
        if !(d.claude_attend ?? false) {
            switch d.type {
            case "choix", "libre": suite = .creation
            case "retouche": suite = .retouche
            default: break
            }
        }
        if let t = suite {
            let consigne = t == .retouche ? (d.demande ?? valeur) : nil
            if await lancerClaude(t, jour: jour, consigne: consigne) {
                message = EtatApp.confirmation(d, relais: "Claude s'y met : tu peux suivre son travail ici.")
            } else if invitationClaude != nil {
                message = EtatApp.confirmation(d, relais: "Connecte Claude pour qu'il s'en occupe.")
            } else {
                message = EtatApp.confirmation(d, relais: "Claude s'en occupera à son prochain passage.")
            }
        } else {
            message = EtatApp.confirmation(d)
        }
        await chargerJour()
    }

    static func confirmation(_ d: Decision) -> String {
        let relais = (d.claude_attend ?? false) ? "Claude s'en occupe maintenant."
                                                 : "Claude s'en occupera à son prochain passage."
        return confirmation(d, relais: relais)
    }

    static func confirmation(_ d: Decision, relais: String) -> String {
        let suite = (d.claude_attend ?? false) ? "Claude s'en occupe maintenant." : relais
        switch d.type {
        case "choix": return "Idée choisie : « \(d.titre ?? "") ». \(suite)"
        case "libre": return "Ton idée est envoyée. \(suite)"
        case "approuve": return "Post validé : il partira à l'heure du créneau."
        case "publie": return "Publié sur Instagram."
        case "retouche": return "Retouche demandée. \(suite)"
        case "reporte": return "Post reporté."
        default: return "C'est noté."
        }
    }

    func indexerGalerie(_ id: String) async {
        occupe = true
        defer { occupe = false }
        struct Resultat: Decodable { let photos: Int?; let nouvelles_vignettes: Int? }
        do {
            let r = try await appeler(Resultat.self, ["app", "indexer-galerie", id])
            message = "Galerie lue : \(r.photos ?? 0) photos. Claude les analysera à son prochain passage."
            await chargerGaleries()
        } catch {
            erreur = error.localizedDescription
        }
    }

    func supprimerGalerie(_ id: String) async {
        struct Resultat: Decodable { let etat: String? }
        do {
            _ = try await appeler(Resultat.self, ["app", "supprimer-galerie", id])
            message = "Galerie retirée du studio."
            await chargerGaleries()
        } catch {
            erreur = error.localizedDescription
        }
    }

    func retablir(_ action: String) async {
        struct Resultat: Decodable { let etat: String? }
        do {
            _ = try await appeler(Resultat.self, ["app", action])
            message = "Valeurs d'origine rétablies."
        } catch {
            erreur = error.localizedDescription
        }
    }

    // MARK: Claude — installation et connexion

    /// `./studio claude statut`. Silencieux : une erreur ne s'affiche pas (rafraîchissements de fond).
    func chargerClaude(silencieux: Bool = false) async {
        do {
            let s = try await appeler(ClaudeStatut.self, ["claude", "statut"])
            claude = s
            if let inv = invitationClaude {
                if s.pret || (inv.action == .installer && s.installe && s.connecte) {
                    invitationClaude = nil
                } else if inv.action == .installer && s.installe {
                    invitationClaude = .connecter(s.conseil)
                }
            }
            if let id = s.en_cours, id != execution?.id || execution?.enCours != true {
                await chargerExecution(id: id)
            }
        } catch {
            if !silencieux { erreur = error.localizedDescription }
        }
    }

    /// Ouvre la page de connexion d'Anthropic (le mot de passe ne passe jamais par l'app), puis
    /// interroge le statut toutes les 2 s, 3 min au plus, jusqu'à ce que Claude soit connecté.
    func connecterClaude(console: Bool = false) async {
        let jeton = UUID()
        jetonConnexion = jeton
        connexionEnCours = true
        codeConnexionAttendu = false
        lienConnexion = nil
        defer {
            if jetonConnexion == jeton {
                connexionEnCours = false
                codeConnexionAttendu = false
                jetonConnexion = nil
            }
        }
        do {
            let r = try await appeler(ReponseConnexion.self, ["claude", "connecter"] + (console ? ["--console"] : []))
            guard jetonConnexion == jeton else { return }
            lienConnexion = r.lien
            switch r.etat {
            case "deja_connecte":
                invitationClaude = nil
                message = "Claude est déjà connecté : il peut travailler pour toi."
                await chargerClaude(silencieux: true)
                return
            case "absent":
                invitationClaude = .installer(r.conseil)
                return
            case "navigateur_ouvert", "terminal_ouvert":
                codeConnexionAttendu = r.code_attendu
                message = r.conseil ?? "Connecte-toi dans la page qui vient de s'ouvrir dans ton navigateur, puis reviens ici."
            default:
                erreur = r.conseil ?? "La connexion à Claude n'a pas pu démarrer. Réessaie dans un instant."
                return
            }
        } catch {
            erreur = error.localizedDescription
            return
        }
        let fin = Date().addingTimeInterval(180)
        while Date() < fin {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard jetonConnexion == jeton, !Task.isCancelled else { return }
            await chargerClaude(silencieux: true)
            guard jetonConnexion == jeton else { return }
            if claude?.connecte == true {
                connexionReussie()
                return
            }
        }
        if jetonConnexion == jeton {
            erreur = "La connexion n'a pas abouti dans les 3 minutes. Clique de nouveau sur « Se connecter » quand tu es prête."
        }
    }

    /// Transmet le code affiché par la page de connexion (`./studio claude code <code>`). Vrai si Claude est connecté.
    @discardableResult
    func envoyerCodeConnexion(_ code: String) async -> Bool {
        let net = code.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !net.isEmpty else {
            erreur = "Colle d'abord le code affiché par la page de connexion."
            return false
        }
        envoiCodeEnCours = true
        defer { envoiCodeEnCours = false }
        do {
            let r = try await appeler(ReponseEtat.self, ["claude", "code"] + (net.hasPrefix("-") ? ["--", net] : [net]))
            switch r.etat {
            case "connecte":
                await chargerClaude(silencieux: true)
                connexionReussie()
                return true
            case "expire", "echec":
                erreur = r.conseil ?? "Le code n'a pas été accepté. Clique de nouveau sur « Se connecter »."
                arreterConnexion()
            default:
                erreur = r.conseil ?? "Ce code ne ressemble pas à celui de la page de connexion : recopie-le en entier."
            }
        } catch {
            erreur = error.localizedDescription
        }
        return false
    }

    private func connexionReussie() {
        jetonConnexion = nil
        connexionEnCours = false
        codeConnexionAttendu = false
        lienConnexion = nil
        invitationClaude = nil
        erreur = nil
        message = "Claude est connecté : il peut travailler pour toi."
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Arrête d'attendre la connexion (la page du navigateur reste ouverte).
    func arreterConnexion() {
        jetonConnexion = nil
        connexionEnCours = false
        codeConnexionAttendu = false
    }

    /// Rouvre la page de connexion si le navigateur ne l'a pas montrée.
    func ouvrirLienConnexion() {
        if let url = lienConnexion { NSWorkspace.shared.open(url) }
    }

    func deconnecterClaude() async {
        do {
            let r = try await appeler(ReponseEtat.self, ["claude", "deconnecter"])
            switch r.etat {
            case "deconnecte": message = "Claude est déconnecté de ce Mac."
            case "absent": message = "Claude Code n'est pas installé sur ce Mac."
            default: erreur = r.conseil ?? "La déconnexion n'a pas abouti. Réessaie dans un instant."
            }
        } catch {
            erreur = error.localizedDescription
        }
        await chargerClaude(silencieux: true)
    }

    /// Installe Claude Code (seulement sur un clic : une à plusieurs minutes), puis invite à se connecter.
    func installerClaude() async {
        installationEnCours = true
        defer { installationEnCours = false }
        do {
            let r = try await appeler(ReponseInstallation.self, ["claude", "installer"])
            switch r.etat {
            case "installe": message = "Claude Code est installé. Dernière étape : connecte-le."
            case "deja_installe": message = "Claude Code est déjà installé sur ce Mac."
            default: erreur = r.conseil ?? "L'installation n'a pas abouti. Vérifie la connexion Internet, puis réessaie."
            }
        } catch {
            erreur = error.localizedDescription
        }
        await chargerClaude(silencieux: true)
        if let s = claude, s.installe, !s.connecte {
            invitationClaude = .connecter(s.conseil)
        } else if claude?.pret == true {
            invitationClaude = nil
        }
    }

    /// Le bouton de `invitationClaude` : installer, ou se connecter.
    func accepterInvitation() async {
        switch invitationClaude?.action {
        case .installer?: await installerClaude()
        case .connecter?: await connecterClaude()
        case nil: break
        }
    }

    // MARK: Claude — exécutions

    /// Lance Claude sans fenêtre. Vrai si l'exécution a démarré ; sinon un message clair est affiché
    /// (`invitationClaude` si Claude manque, `message` s'il travaille déjà, `erreur` sinon).
    @discardableResult
    func lancerClaude(_ tache: TacheClaude, jour j: String? = nil, serie: String? = nil,
                      consigne: String? = nil) async -> Bool {
        let leJour = j ?? jour
        // Forme « --option=valeur » : un texte qui commence par un tiret reste une valeur.
        var arguments = ["claude", "lancer", tache.rawValue, "--jour=\(leJour)"]
        if let s = serie?.nonVide { arguments.append("--serie=\(s)") }
        if let c = consigne?.nonVide { arguments.append("--consigne=\(c)") }
        lancementEnCours = true
        defer { lancementEnCours = false }
        do {
            let r = try await appeler(ReponseLancement.self, arguments)
            switch r.etat {
            case "lance", "termine":
                invitationClaude = nil
                if let id = r.id {
                    if execution?.id != id {
                        signatureExecution = nil
                        appliquer(.provisoire(id: id, tache: tache, jour: leJour))
                    }
                    await chargerExecution(id: id)
                }
                return true
            case "deja_en_cours":
                if let id = r.id { await chargerExecution(id: id) }
                let enCours = execution?.enCours == true ? execution?.titreAffiche : nil
                message = "\(enCours ?? "Claude travaille déjà") : attends qu'il ait fini, ou arrête-le, avant de lui demander autre chose."
            case "non_connecte":
                invitationClaude = .connecter(r.conseil)
                await chargerClaude(silencieux: true)
            case "absent":
                await chargerClaude(silencieux: true)
                if claude?.installe == true {
                    erreur = r.conseil ?? "Le studio n'a pas sa copie du plugin : relance l'installation du studio."
                } else {
                    invitationClaude = .installer(r.conseil)
                }
            case "erreur":
                erreur = r.conseil ?? "Claude n'a pas pu démarrer. Réessaie dans un instant."
                if let id = r.id { await chargerExecution(id: id) }
            default:
                erreur = r.conseil ?? "Réponse inattendue du studio (« \(r.etat) »)."
            }
        } catch {
            erreur = error.localizedDescription
        }
        return false
    }

    /// Arrête l'exécution en cours (le moteur arrête Claude ; la fin arrive par la surveillance).
    func annulerClaude() async {
        do {
            let r = try await appeler(ReponseEtat.self, ["claude", "annuler"])
            message = r.etat == "annule" ? "Claude s'arrête…" : "Claude ne travaillait pas."
        } catch {
            erreur = error.localizedDescription
        }
        await chargerExecution(id: execution?.id)
    }

    /// `./studio claude etat [--id ID]` : l'exécution demandée, ou la dernière. Toujours silencieux.
    func chargerExecution(id: String? = nil) async {
        var arguments = ["claude", "etat"]
        if let id = id?.nonVide { arguments.append("--id=\(id)") }
        guard let e = try? await appeler(ExecutionClaude.self, arguments) else { return }
        dernierSigneDeVie = Date()
        if e.aucune {
            if id == nil, execution?.enCours != true { appliquer(nil) }
            return
        }
        // Une réponse tardive ne remplace jamais une exécution plus récente.
        if let actuelle = execution, actuelle.id != e.id, actuelle.plusRecente(que: e) { return }
        appliquer(e)
    }

    func chargerHistoriqueClaude() async {
        guard let l = try? await appeler(ListeExecutions.self, ["claude", "historique"]) else { return }
        historiqueClaude = l.executions
    }

    /// Le panneau « Demander à Claude » repart d'une conversation vierge.
    func nouvelleConversation() async {
        do {
            _ = try await appeler(ReponseEtat.self, ["claude", "nouvelle-conversation"])
            message = "Nouvelle conversation : Claude repart d'une page blanche."
        } catch {
            erreur = error.localizedDescription
        }
    }

    /// Point d'entrée unique des nouvelles valeurs de `execution` : suivi rapide et fin d'exécution.
    private func appliquer(_ nouvelle: ExecutionClaude?) {
        guard let n = nouvelle, !n.aucune else {
            execution = nil
            ajusterSuiviRapide()
            return
        }
        if n.enCours { executionsSuivies.insert(n.id) }
        if execution != n { execution = n }
        if n.terminee, executionsSuivies.contains(n.id), !executionsFinies.contains(n.id) {
            executionsFinies.insert(n.id)
            Task { await executionTerminee(n) }
        }
        ajusterSuiviRapide()
    }

    /// Second minuteur (0,7 s), actif seulement pendant une exécution en attente ou en cours.
    private func ajusterSuiviRapide() {
        let actif = execution?.enCours == true
        if actif, minuteurRapide == nil {
            dernierSigneDeVie = Date()
            let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.suivreExecution() }
            }
            RunLoop.main.add(t, forMode: .common)
            minuteurRapide = t
        } else if !actif, let t = minuteurRapide {
            t.invalidate()
            minuteurRapide = nil
        }
    }

    /// Lit directement `.ui/claude/<id>.json` quand il change ; sans nouvelles depuis 10 s, demande au
    /// moteur (qui sait voir une exécution interrompue : Mac mis en veille, processus arrêté).
    private func suivreExecution() {
        guard let e = execution, e.enCours else {
            ajusterSuiviRapide()
            return
        }
        let url = dossier.appendingPathComponent(".ui/claude/\(e.id).json")
        let date = EtatApp.dateModification(url)
        if let date = date, date != signatureExecution,
           let data = try? Data(contentsOf: url),
           let lue = try? JSONDecoder().decode(ExecutionClaude.self, from: data), lue.id == e.id {
            signatureExecution = date
            dernierSigneDeVie = Date()
            appliquer(lue)
        } else if Date().timeIntervalSince(dernierSigneDeVie) > 10, !controleEnCours {
            dernierSigneDeVie = Date()
            controleEnCours = true
            Task {
                await chargerExecution(id: e.id)
                controleEnCours = false
            }
        }
    }

    /// Fin d'une exécution suivie : message, données rechargées, puis l'écran suivant (avec animation).
    private func executionTerminee(_ e: ExecutionClaude) async {
        let tache = e.tacheClaude
        switch e.etat {
        case "termine":
            var texte = e.resultat ?? "\(tache?.titre ?? "C'est") : c'est prêt."
            if let a = e.avertissement { texte += "\n" + a }
            message = texte
        case "annule":
            message = "Claude s'est arrêté à ta demande."
        default:
            let texte = e.erreur ?? "Claude n'a pas pu terminer. Réessaie dans un instant."
            if texte.contains("plus connecté") { invitationClaude = .connecter(texte) } else { erreur = texte }
        }
        let suivant = e.reussie && tache != .demande ? e.ecranSuivant : nil
        if suivant != nil, tache?.duJour == true, let j = e.jour, j != jour { jour = j }
        if tache == .creation || tache == .retouche { versionImages += 1 }
        await chargerJour()
        switch tache {
        case .galerie?: await chargerGaleries()
        case .bilan?: await chargerMemoire()
        case .demande?:
            await chargerReglages()
            await chargerGaleries()
            await chargerApparence(silencieux: true)
        default: break
        }
        if let s = suivant { withAnimation(animationEcran) { ecran = s } }
        await chargerHistoriqueClaude()
        await chargerClaude(silencieux: true)
    }

    // MARK: Planification (launchd)

    func chargerPlanification(silencieux: Bool = false) async {
        do {
            planification = try await appeler(Planification.self, ["planifier", "--etat"])
        } catch {
            if !silencieux { erreur = error.localizedDescription }
        }
    }

    /// Active ou arrête les tâches automatiques du Mac. Vrai si le Mac est dans l'état voulu.
    @discardableResult
    func planifier(activer: Bool) async -> Bool {
        do {
            let p = try await appeler(Planification.self, ["planifier", activer ? "--activer" : "--desactiver"])
            planification = p
            reglages?.planification = ReglagesPlanification(active: p.active)
            if p.active == activer {
                message = activer ? "Tâches automatiques activées : le Mac s'en charge, même app fermée."
                                  : "Tâches automatiques arrêtées."
                return true
            }
            erreur = p.conseil ?? "Le Mac n'a pas pu changer les tâches automatiques."
        } catch {
            erreur = error.localizedDescription
            await chargerPlanification(silencieux: true)
        }
        return false
    }

    // MARK: Apparence (config/app.yaml)

    func chargerApparence(silencieux: Bool = false) async {
        do {
            let a = try await appeler(Apparence.self, ["app", "apparence"]).normalisee()
            if a != apparence { withAnimation(EtatApp.animation(pour: a)) { apparence = a } }
        } catch {
            if !silencieux { erreur = error.localizedDescription }
        }
    }

    /// Enregistre l'apparence (normalisée d'abord) ; elle s'applique aussitôt. Faux si le moteur la refuse.
    @discardableResult
    func enregistrerApparence(_ a: Apparence) async -> Bool {
        let n = a.normalisee()
        guard await envoyer(n, action: "enregistrer-apparence") else { return false }
        withAnimation(EtatApp.animation(pour: n)) { apparence = n }
        message = "Apparence enregistrée."
        await chargerApparence(silencieux: true)
        return true
    }

    func retablirApparence() async {
        do {
            _ = try await appeler(ReponseEtat.self, ["app", "retablir-apparence"])
            withAnimation(EtatApp.animation(pour: .defaut)) { apparence = .defaut }
            message = "Apparence d'origine rétablie."
        } catch {
            erreur = error.localizedDescription
        }
        await chargerApparence(silencieux: true)
    }

    private static func animation(pour a: Apparence) -> Animation? {
        a.animations == "aucune" ? nil : .easeInOut(duration: 0.4)
    }

    // MARK: Assistant de création (écran `creation`)

    /// Étapes que la photographe veut valider (Réglages › Création), dans l'ordre photos, légende, musique.
    /// L'aperçu final se valide toujours. Sans réglage (moteur ancien) : toutes.
    var etapesAValider: [String] { reglages?.creation?.etapes_a_valider ?? ReglagesCreation.etapes }

    func doitValider(_ etape: String) -> Bool { etapesAValider.contains(etape) }

    /// Les photos actuelles du post, dans l'ordre, prêtes à être retirées, ajoutées ou réordonnées puis renvoyées
    /// à `modifierPost`. Nil si le post n'a pas de photos ou si le moteur ne donne pas leurs identifiants.
    var mediasDuPost: [MediaModifie]? {
        guard let medias = vue?.post?.medias, !medias.isEmpty else { return nil }
        var liste: [MediaModifie] = []
        for m in medias.sorted(by: { $0.ordre < $1.ordre }) {
            guard let id = m.photo_id?.nonVide else { return nil }
            liste.append(MediaModifie(photo_id: id))
        }
        return liste
    }

    /// Applique les choix de l'assistant (`./studio app modifier-post`) : photos et leur ordre, légende, musique.
    /// Seules les parties données changent ; le moteur refait la mise en page, le contrôle et l'aperçu, puis
    /// `vue` est rechargée. Vrai si c'est enregistré (un contrôle non conforme le dit dans `erreur`).
    @discardableResult
    func modifierPost(jour j: String? = nil, medias: [MediaModifie]? = nil, legende: String? = nil,
                      musique: Musique? = nil) async -> Bool {
        let leJour = j ?? jour
        let corps = ModificationPost(medias: medias, legende: legende, musique: musique)
        if corps.vide { return true }
        if let l = legende, l.nonVide == nil {
            erreur = "La légende ne peut pas être vide."
            return false
        }
        if let m = medias, m.isEmpty {
            erreur = "Garde au moins une photo."
            return false
        }
        modificationEnCours = true
        defer { modificationEnCours = false }
        do {
            let url = try fichierTemporaire(try JSONEncoder().encode(corps), extension: "json")
            defer { try? FileManager.default.removeItem(at: url) }
            let r = try await appeler(ReponseModificationPost.self, ["app", "modifier-post", leJour, url.path])
            switch r.etat {
            case "enregistre":
                if r.changements.contains("photos") { versionImages += 1 }
                if let c = r.controle, !c.conforme, !c.erreurs.isEmpty {
                    erreur = "C'est enregistré, mais à revoir : " + c.erreurs.joined(separator: " ")
                } else {
                    message = (["C'est enregistré."] + r.avertissements).joined(separator: "\n")
                }
                if leJour == jour { await chargerJour() }
                return true
            case "inchange":
                return true
            default:
                erreur = "Le studio n'a pas enregistré ces changements (« \(r.etat) »)."
            }
        } catch {
            erreur = error.localizedDescription
        }
        return false
    }

    /// Photos d'une galerie à proposer dans l'assistant, les mieux notées d'abord (`./studio app candidats`).
    func candidats(serie: String) async -> [PhotoCandidate] {
        do {
            return try await appeler(ListeSouple<PhotoCandidate>.self, ["app", "candidats", serie]).elements
                .filter { !$0.id.isEmpty }
        } catch {
            erreur = error.localizedDescription
            return []
        }
    }

    /// Pistes de la bibliothèque musicale d'Instagram (`./studio musique chercher`, route Facebook seulement).
    /// Pour en choisir une : `modifierPost(musique: piste.musique())`.
    func chercherMusique(_ requete: String) async -> [PisteMusique] {
        var arguments = ["musique", "chercher"]
        if let mots = requete.nonVide { arguments += mots.hasPrefix("-") ? ["--", mots] : [mots] }
        do {
            return try await appeler(ListeSouple<PisteMusique>.self, arguments).elements.filter { !$0.audio_id.isEmpty }
        } catch {
            erreur = error.localizedDescription
            return []
        }
    }

    // MARK: Instagram (onboarding, Réglages)

    /// `./studio app instagram` → `instagram` (interroge Instagram : une seconde ou deux).
    func chargerInstagram(silencieux: Bool = false) async {
        do {
            instagram = try await appeler(InstagramEtat.self, ["app", "instagram"])
        } catch {
            if !silencieux { erreur = error.localizedDescription }
        }
    }

    /// Enregistre les identifiants collés par la photographe, puis vérifie la connexion.
    /// Route `facebook` : `appId`, `secret` et `jeton` ; route `instagram` : `jeton` seul.
    /// Les identifiants passent par un fichier privé (0600) que le moteur efface dès sa lecture ; ils ne sont
    /// jamais sur la ligne de commande, dans un message ou un journal.
    @discardableResult
    func connecterInstagram(route: String, appId: String = "", secret: String = "", jeton: String) async -> Bool {
        guard route == "facebook" || route == "instagram" else {
            erreur = "Choisis la route Facebook ou Instagram."
            return false
        }
        connexionInstagramEnCours = true
        defer { connexionInstagramEnCours = false }
        do {
            let ids = IdentifiantsInstagram(route: route, app_id: appId, app_secret: secret, jeton: jeton)
            let url = try EtatApp.fichierPrive(try JSONEncoder().encode(ids))
            defer { try? FileManager.default.removeItem(at: url) }
            let r = try await appeler(ReponseInstagram.self, ["app", "enregistrer-instagram", url.path])
            switch r.etat {
            case "connecte":
                message = "Instagram est connecté" + (r.compte.map { " : @\($0)" } ?? "") + "."
                await chargerInstagram(silencieux: true)
                return true
            case "refuse":
                erreur = r.erreurs.isEmpty ? "Vérifie les champs : il en manque un." : r.erreurs.joined(separator: "\n")
            default:
                erreur = r.erreurs.first ?? "Instagram n'a pas accepté ces identifiants. Vérifie-les, puis réessaie."
                await chargerInstagram(silencieux: true)
            }
        } catch {
            erreur = error.localizedDescription
        }
        return false
    }

    /// Fichier temporaire lisible par la seule photographe (créé directement en 0600, jamais en clair ailleurs).
    nonisolated private static func fichierPrive(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString).json")
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else { throw ErreurMoteur(message: "Impossible de préparer l'envoi des identifiants.") }
        let ecrits = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        close(fd)
        guard ecrits == data.count else {
            unlink(url.path)
            throw ErreurMoteur(message: "Impossible de préparer l'envoi des identifiants.")
        }
        return url
    }

    // MARK: Claude (1.x)

    /// Ouvre l'application Claude et copie la commande utile, pour reprendre la main.
    func ouvrirClaude(commande: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commande, forType: .string)
        let claude = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: claude.path) {
            NSWorkspace.shared.openApplication(at: claude, configuration: NSWorkspace.OpenConfiguration())
        }
        message = "Claude s'ouvre. La commande « \(commande) » est copiée : colle-la dans une session de l'onglet Code."
    }
}
