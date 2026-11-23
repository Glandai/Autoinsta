import AppKit
import SwiftUI

// Réglages (DESIGN.md §4.9) : deux colonnes dans la page. À gauche les rubriques en lignes arrondies,
// à droite leur contenu en cartes douces. Tout s'enregistre tout seul (0,6 s après le dernier changement),
// sans bandeau : un discret « Enregistré » en légende sous les rubriques.
//
// Rubriques : Compte, Publication, Création (étapes à valider), Claude, Instagram, Planification,
// Apparence (en direct, aperçu clair et sombre), Avancé.
//
// Partagé avec VueCharte.swift (Charte, Règles) : `EtatSauvegarde`, `IndicateurSauvegarde`, `LigneReglage`,
// `ChoixEnPilules`, `ReglageNombre`, `RangeesSouples`, `DemandeClaudeReglages`, et l'extension
// `EtatApp.enregistrerSansBandeau(_:action:)`.
//
// Pour ouvrir une rubrique depuis un autre écran : `UserDefaults.standard.set("claude", forKey: RubriqueReglages.cle)`
// puis `etat.montrer(.reglages)`.
//
// Sécurité : les identifiants Instagram ne passent que par des `SecureField`, sont vidés dès l'envoi (réussi ou non),
// ne sont jamais affichés, copiés ni journalisés. La connexion à Claude passe par la feuille de la coque
// (`FeuilleConnexionClaude`, `coque.feuilleConnexion`).

// MARK: - Rubriques

enum RubriqueReglages: String, CaseIterable, Identifiable {
    case compte, publication, claude, instagram, planification, apparence, charte, avance
    var id: String { rawValue }

    /// Clé UserDefaults de la rubrique ouverte (gardée d'une visite à l'autre).
    static let cle = "reglages.rubrique"

    /// Une valeur gardée par une version précédente (« creation ») retombe sur la bonne rubrique.
    init(brute: String) {
        self = RubriqueReglages(rawValue: brute) ?? (brute == "creation" ? .publication : .compte)
    }

    var titre: String {
        switch self {
        case .compte: return "Compte"
        case .publication: return "Publication et création"
        case .claude: return "Claude"
        case .instagram: return "Instagram"
        case .planification: return "Planification"
        case .apparence: return "Apparence"
        case .charte: return "Charte et règles"
        case .avance: return "Avancé"
        }
    }

    var symbole: String {
        switch self {
        case .compte: return "person.crop.circle"
        case .publication: return "paperplane"
        case .claude: return "sparkles"
        case .instagram: return "camera"
        case .planification: return "clock.badge.checkmark"
        case .apparence: return "paintpalette"
        case .charte: return "text.book.closed"
        case .avance: return "slider.horizontal.3"
        }
    }

    var chapo: String {
        switch self {
        case .compte: return "Qui tu es, ce que tu photographies et ta voix : Claude s'en sert pour chaque idée et chaque légende."
        case .publication: return "Tes jours de publication, et ce que tu valides toi-même quand tu crées un post."
        case .claude: return "Claude sur ce Mac : sa connexion, sa façon de travailler et ce qu'il a fait dernièrement."
        case .instagram: return "Le compte où le studio publie, seulement ce que tu as validé."
        case .planification: return "Ce que le studio fait tout seul, même quand l'app est fermée."
        case .apparence: return "Le mode, l'ambiance et le nom de ton studio. Tout s'applique en direct."
        case .charte: return "Ce que Claude suit pour chaque post, et ce que le contrôle refuse avant de publier."
        case .avance: return "Le dossier du studio, sa version et son état."
        }
    }
}

// MARK: - Écran

struct VueReglages: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @AppStorage(RubriqueReglages.cle) private var rubriqueBrute = RubriqueReglages.compte.rawValue
    @Local private var r: Reglages?
    @Local private var lecture = true
    @Local private var sauvegarde = EtatSauvegarde.repos
    @Local private var tache: Task<Void, Never>?
    @Local private var serie = 0
    /// Quand les valeurs affichées ont été (re)montrées : un changement n'est voulu que s'il suit un geste fait après.
    @Local private var affichage = Date()

    private var rubrique: RubriqueReglages { RubriqueReglages(brute: rubriqueBrute) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            colonneRubriques
            ZStack {
                contenu
                    .id(rubrique)
                    .transition(j.transition(.ecran))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(j.anim(.page), value: rubrique)
        }
        .background(raccourciEnregistrer)
        .onAppear { InteractionsUtilisateur.partage.demarrer() }
        .onChange(of: rubrique) { _, _ in affichage = Date() }
        .task { await charger() }
        .onDisappear { enregistrerSiBesoin() }
    }

    // MARK: Colonne des rubriques

    private var colonneRubriques: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Pas de titre ici : « Réglages » est déjà le surtitre de chaque rubrique.
            ForEach(Array(RubriqueReglages.allCases.enumerated()), id: \.element) { i, rub in
                LigneRubrique(rubrique: rub, choisie: rub == rubrique, alerte: alerte(rub)) {
                    withAnimation(j.anim(.selection)) { rubriqueBrute = rub.rawValue }
                }
                .entreeEnCascade(i, pas: 0.03)
            }
            Spacer(minLength: j.esp.blocs)
            IndicateurSauvegarde(etat: sauvegarde)
                .padding(.leading, 10)
        }
        .frame(width: 224, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rubriques des réglages")
        .padding(.top, j.esp.page * 0.7 + 30)
        .padding(.bottom, j.esp.page * 0.6)
        .padding(.leading, j.esp.page * 0.6)
    }

    private func alerte(_ rub: RubriqueReglages) -> Bool {
        switch rub {
        case .claude: return etat.claude.map { !$0.pret } ?? false
        case .instagram: return etat.instagram.map { !$0.connecte && !$0.etat.isEmpty } ?? false
        default: return false
        }
    }

    // MARK: Contenu

    @ViewBuilder private var contenu: some View {
        if rubrique == .apparence {
            RubriqueApparence(prenom: prenom, sauvegarde: $sauvegarde)
        } else if let lies = reglagesLies {
            ScrollView {
                VStack(alignment: .leading, spacing: j.esp.sections * 0.6) {
                    EnTeteEcran(surTitre: "Réglages", titre: rubrique.titre, chapo: rubrique.chapo)
                    corps(lies)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, j.esp.page)
                .padding(.top, j.esp.page * 0.7)
                .padding(.bottom, j.esp.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if lecture {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Je lis tes réglages…").typo(.legende)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EtatVide(symbole: "gearshape", titre: "Réglages introuvables",
                     phrase: "Je n'arrive pas à lire les réglages du studio pour l'instant.",
                     actionTitre: "Réessayer") { Task { await charger() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func corps(_ lies: Binding<Reglages>) -> some View {
        switch rubrique {
        case .compte: RubriqueCompte(r: lies, adapterCharte: adapterCharte)
        case .publication:
            VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
                RubriqueCreation(r: lies)
                RubriquePublication(r: lies)
            }
        case .charte: RubriqueCharteRegles()
        case .claude: RubriqueClaude(r: lies)
        case .instagram: RubriqueInstagram(r: lies)
        case .planification: RubriquePlanification(r: lies)
        case .apparence: EmptyView()
        case .avance: RubriqueAvance(r: lies)
        }
    }

    private var prenom: String {
        let nom = (r ?? etat.reglages)?.nom.trimmingCharacters(in: .whitespaces) ?? ""
        let premier = nom.split(separator: " ").first.map(String.init) ?? ""
        return premier.isEmpty || premier.contains("[") ? "" : premier
    }

    /// « Adapter ma charte à cette activité » : enregistre d'abord ce qui attend, puis confie la charte à Claude.
    private func adapterCharte() {
        Task {
            if sauvegarde == .enAttente {
                tache?.cancel()
                serie += 1
                await enregistrer(serie)
            }
            _ = await etat.lancerClaude(.charte)
        }
    }

    /// Les réglages en brouillon. Seul un vrai changement, fait par la photographe après l'affichage, relance
    /// l'enregistrement automatique : une réécriture identique ou sans geste est ignorée (rien n'est écrit).
    private var reglagesLies: Binding<Reglages>? {
        guard let actuel = r else { return nil }
        return Binding(get: { r ?? actuel }, set: { nouveau in
            guard let ancien = r, !InteractionsUtilisateur.memesDonnees(ancien, nouveau) else { return }
            r = nouveau
            if InteractionsUtilisateur.partage.voulu(depuis: affichage) { planifierEnregistrement() }
        })
    }

    /// ⌘S : enregistre tout de suite (l'enregistrement est de toute façon automatique).
    private var raccourciEnregistrer: some View {
        Button("Enregistrer") { enregistrerSiBesoin() }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    // MARK: Chargement et enregistrement

    private func charger() async {
        lecture = true
        await etat.chargerReglages()
        if r == nil { r = etat.reglages }
        affichage = Date()
        lecture = false
        if etat.claude == nil { await etat.chargerClaude(silencieux: true) }
        if etat.instagram == nil { await etat.chargerInstagram(silencieux: true) }
    }

    private func planifierEnregistrement() {
        tache?.cancel()
        serie += 1
        let numero = serie
        sauvegarde = .enAttente
        tache = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await enregistrer(numero)
        }
    }

    private func enregistrerSiBesoin() {
        guard sauvegarde == .enAttente else { return }
        tache?.cancel()
        serie += 1
        let numero = serie
        Task { await enregistrer(numero) }
    }

    private func enregistrer(_ numero: Int) async {
        guard var copie = r else { return }
        sauvegarde = .enCours
        let ok = await etat.enregistrerSansBandeau(copie, action: "enregistrer-reglages")
        if ok {
            copie.planification = etat.reglages?.planification ?? copie.planification
            etat.reglages = copie
        }
        guard numero == serie else { return }   // un changement plus récent attend déjà
        tache = nil
        sauvegarde = ok ? .fait : .echec
    }
}

// MARK: - Garde : rien ne s'écrit sans un geste de la photographe

/// Retient l'heure du dernier geste réel dans l'app (clic, glissé, touche), grâce à un moniteur d'événements
/// local. Un changement de valeur n'est « voulu » (et donc enregistré) que s'il suit de près un geste fait
/// *après* l'affichage des valeurs : un contrôle qui réécrit sa valeur en apparaissant, un chargement du moteur,
/// une mise à jour de `etat.apparence` venue d'ailleurs, ou un rendu hors écran (aucun événement) n'écrivent rien.
/// Avec VoiceOver (ses réglages ne passent pas par des événements souris ou clavier), on se contente de la
/// seconde condition : l'écran est affiché depuis plus d'une demi-seconde.
final class InteractionsUtilisateur {
    static let partage = InteractionsUtilisateur()
    private(set) var derniere = Date.distantPast
    private var moniteur: Any?

    /// À appeler à l'apparition d'un écran qui enregistre tout seul (avant tout geste dessus).
    func demarrer() {
        guard moniteur == nil else { return }
        moniteur = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] e in
            self?.derniere = Date()
            return e
        }
    }

    /// Vrai si un changement fait maintenant vient d'un geste de la photographe sur des valeurs affichées
    /// depuis `affichage`.
    func voulu(depuis affichage: Date) -> Bool {
        let maintenant = Date()
        if NSWorkspace.shared.isVoiceOverEnabled { return maintenant.timeIntervalSince(affichage) > 0.5 }
        return derniere > affichage.addingTimeInterval(0.15) && maintenant.timeIntervalSince(derniere) < 2
    }

    /// Même contenu une fois encodé (les types de réglages ne sont pas `Equatable`).
    static func memesDonnees<T: Encodable>(_ a: T, _ b: T) -> Bool {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let da = try? e.encode(a), let db = try? e.encode(b) else { return false }
        return da == db
    }

    /// Une couleur réécrite par un `ColorPicker` (conversion d'espace de couleur) n'est pas un changement.
    static func memeCouleur(_ hex: String, _ c: Color) -> Bool {
        (Color(hex: hex)?.hex ?? hex).lowercased() == c.hex.lowercased()
    }
}

// MARK: - Enregistrement discret (partagé avec Règles)

/// Où en est l'enregistrement automatique.
enum EtatSauvegarde: Equatable {
    case repos, enAttente, enCours, fait, echec
}

/// « Enregistré » en légende succès, qui s'efface au bout de quelques secondes ; « Pas enregistré » si le moteur refuse.
struct IndicateurSauvegarde: View {
    let etat: EtatSauvegarde
    @Environment(\.jetons) private var j
    @Local private var visible = false

    var body: some View {
        HStack(spacing: 6) {
            switch etat {
            case .enAttente, .enCours:
                ProgressView().controlSize(.mini)
                Text("Enregistrement…").typo(.legende)
            case .fait:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(j.succes).imageScale(.small)
                Text("Enregistré").typo(.legende, couleur: j.succes)
            case .echec:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(j.alerte).imageScale(.small)
                Text("Pas enregistré").typo(.legende, couleur: j.alerte)
            case .repos:
                EmptyView()
            }
        }
        .opacity(visible ? 1 : 0)
        .frame(height: 18)
        .animation(j.anim(.survol), value: visible)
        .task(id: etat) {
            visible = etat != .repos
            guard etat == .fait else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { visible = false }
        }
        .accessibilityElement(children: .combine)
        .onChange(of: etat) { _, e in
            if e == .fait { AccessibilityNotification.Announcement("Enregistré").post() }
        }
    }
}

extension EtatApp {
    /// Comme `envoyer(_:action:)`, mais sans le bandeau « Enregistré. » : pour l'enregistrement automatique
    /// des Réglages et des Règles. Une erreur remplit toujours `erreur`.
    func enregistrerSansBandeau<T: Encodable>(_ valeur: T, action: String) async -> Bool {
        do {
            let encodeur = JSONEncoder()
            encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString).json")
            try encodeur.encode(valeur).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let reponse = try await appeler(ReponseEnregistrement.self, ["app", action, url.path])
            if let erreurs = reponse.erreurs, !erreurs.isEmpty {
                erreur = erreurs.joined(separator: "\n")
                return false
            }
            if reponse.etat == "refuse" {
                erreur = "Le studio a refusé ces valeurs."
                return false
            }
            return true
        } catch {
            erreur = error.localizedDescription
            return false
        }
    }

    /// Comme `enregistrerApparence(_:)`, sans bandeau : la page Apparence montre elle-même « Apparence mise à jour ».
    fileprivate func appliquerApparenceSansBandeau(_ a: Apparence) async -> Bool {
        let n = a.normalisee()
        guard await enregistrerSansBandeau(n, action: "enregistrer-apparence") else { return false }
        withAnimation(n.animations == "aucune" ? nil : .easeInOut(duration: 0.4)) { apparence = n }
        await chargerApparence(silencieux: true)
        return true
    }
}

// MARK: - Briques partagées

/// Une ligne de réglage : symbole (facultatif), titre et aide à gauche, contrôle à droite.
struct LigneReglage<Controle: View>: View {
    let titre: String
    var aide: String?
    var symbole: String?
    let controle: Controle
    @Environment(\.jetons) private var j

    init(_ titre: String, aide: String? = nil, symbole: String? = nil, @ViewBuilder controle: () -> Controle) {
        self.titre = titre
        self.aide = aide
        self.symbole = symbole
        self.controle = controle()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let s = symbole {
                Image(systemName: s)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(j.texte)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(j.fondDoux))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).typo(.corpsFort)
                if let a = aide {
                    Text(a)
                        .typo(.legende)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controle
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

/// Une option d'un choix en pilules.
struct OptionReglage: Identifiable, Equatable {
    let valeur: String
    let titre: String
    var symbole: String? = nil
    var id: String { valeur }
}

/// Choix exclusif en petites pilules : la sombre est choisie, les claires ne le sont pas.
struct ChoixEnPilules: View {
    let options: [OptionReglage]
    @Binding var selection: String
    @Environment(\.jetons) private var j

    var body: some View {
        RangeesSouples(espacement: 6, interligne: 6) {
            ForEach(options) { o in
                let choisie = o.valeur == selection
                Button {
                    withAnimation(j.anim(.selection)) { selection = o.valeur }
                } label: {
                    if let s = o.symbole { Label(o.titre, systemImage: s) } else { Text(o.titre) }
                }
                .buttonStyle(.pilule(choisie ? .sombre : .claire, taille: .petite))
                .accessibilityAddTraits(choisie ? .isSelected : [])
            }
        }
    }
}

/// Un nombre réglé par − et + (boutons ronds clairs) ; VoiceOver : réglable par glissement.
struct ReglageNombre: View {
    @Binding var valeur: Int
    let plage: ClosedRange<Int>
    var pas = 1
    var unite: String? = nil
    var libelle = "Valeur"
    @Environment(\.jetons) private var j

    private static let format: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private var texte: String {
        let n = ReglageNombre.format.string(from: NSNumber(value: valeur)) ?? "\(valeur)"
        return unite.map { "\(n) \($0)" } ?? n
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { changer(-pas) } label: { Image(systemName: "minus") }
                .buttonStyle(.rond(.claire, diametre: 28))
                .disabled(valeur <= plage.lowerBound)
                .accessibilityLabel("Moins")
            Text(texte)
                .font(.jakarta(15, graisse: 600))
                .monospacedDigit()
                .foregroundStyle(j.texte)
                .frame(minWidth: 52)
                .contentTransition(.numericText())
            Button { changer(pas) } label: { Image(systemName: "plus") }
                .buttonStyle(.rond(.claire, diametre: 28))
                .disabled(valeur >= plage.upperBound)
                .accessibilityLabel("Plus")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelle)
        .accessibilityValue(texte)
        .accessibilityAdjustableAction { sens in
            switch sens {
            case .increment: changer(pas)
            case .decrement: changer(-pas)
            @unknown default: break
            }
        }
    }

    private func changer(_ d: Int) {
        let n = min(plage.upperBound, max(plage.lowerBound, valeur + d))
        guard n != valeur else { return }
        withAnimation(j.anim(.compteur)) { valeur = n }
    }
}

/// Disposition en rangées qui passent à la ligne (pastilles, pilules).
struct RangeesSouples: Layout {
    var espacement: CGFloat = 8
    var interligne: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeurMax = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var hauteurLigne: CGFloat = 0
        var largeur: CGFloat = 0
        for s in subviews {
            var t = s.sizeThatFits(.unspecified)
            t.width = min(t.width, largeurMax)
            if x > 0 && x + t.width > largeurMax {
                y += hauteurLigne + interligne
                x = 0
                hauteurLigne = 0
            }
            largeur = max(largeur, x + t.width)
            x += t.width + espacement
            hauteurLigne = max(hauteurLigne, t.height)
        }
        return CGSize(width: proposal.width ?? largeur, height: y + hauteurLigne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var hauteurLigne: CGFloat = 0
        for s in subviews {
            var t = s.sizeThatFits(.unspecified)
            t.width = min(t.width, bounds.width)
            if x > bounds.minX && x + t.width > bounds.maxX {
                y += hauteurLigne + interligne
                x = bounds.minX
                hauteurLigne = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacement
            hauteurLigne = max(hauteurLigne, t.height)
        }
    }
}

/// « Envie d'autre chose ? » : une demande à Claude préremplie ; l'envoyer ouvre le panneau sur sa réponse.
struct DemandeClaudeReglages: View {
    let titre: String
    let texte: String
    /// Début de la demande, déjà écrit dans le champ.
    let debut: String
    /// L'écran d'où elle parle (ajouté à la consigne de Claude).
    let contexte: String
    var bouton = "Demander à Claude"
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @Local private var demande = ""
    @Local private var ouvert = false

    private var vide: Bool { demande.trimmingCharacters(in: .whitespacesAndNewlines).count <= debut.trimmingCharacters(in: .whitespaces).count }

    var body: some View {
        Carte {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(j.accentTexte)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(j.fondDoux))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).typo(.titre3)
                    Text(texte).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !ouvert {
                    Button {
                        demande = debut
                        withAnimation(j.anim(.doux)) { ouvert = true }
                    } label: { Label(bouton, systemImage: "text.bubble") }
                    .buttonStyle(.pilule(.sombre, taille: .petite))
                }
            }
            if ouvert {
                HStack(alignment: .bottom, spacing: 10) {
                    ChampDoux(texte: $demande, exemple: "Dis-le simplement…", lignes: 1...4, envoyer: envoyer)
                    Button(action: envoyer) { Image(systemName: "arrow.up") }
                        .buttonStyle(.rond(.sombre, diametre: 40))
                        .disabled(vide)
                        .help("Envoyer à Claude")
                        .accessibilityLabel("Envoyer à Claude")
                    Button {
                        withAnimation(j.anim(.doux)) { ouvert = false }
                        demande = ""
                    } label: { Image(systemName: "xmark") }
                    .buttonStyle(.rond(.transparente, diametre: 32))
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .transition(j.transition(.apparition))
                Text("Claude répond dans le panneau à droite (⌘K).").typo(.legende)
            }
        }
    }

    private func envoyer() {
        guard !vide else { return }
        coque.demander(demande, etat: etat, contexte: contexte)
        demande = ""
        withAnimation(j.anim(.doux)) { ouvert = false }
    }
}

// MARK: - Ligne d'une rubrique

private struct LigneRubrique: View {
    let rubrique: RubriqueReglages
    let choisie: Bool
    let alerte: Bool
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        let sombre = j.schema == .dark
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: rubrique.symbole)
                    .font(.system(size: 13, weight: .medium))
                    .symbolVariant(choisie ? .fill : .none)
                    .foregroundStyle(j.texte)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(j.fondDoux))
                Text(rubrique.titre)
                    .font(j.police(choisie ? .corpsFort : .corps))
                    .foregroundStyle(j.texte)
                Spacer(minLength: 0)
                if alerte {
                    PointEtat(couleur: j.alerte, diametre: 7)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(forme.fill(choisie ? (sombre ? Color.white.opacity(0.10) : Color.white)
                                           : (survol ? Color.white.opacity(sombre ? 0.05 : 0.45) : Color.clear)))
            .ombre(choisie ? .carte : .repos)
            .contentShape(forme)
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(j.anim(.survol), value: survol)
        .animation(j.anim(.selection), value: choisie)
        .accessibilityLabel(rubrique.titre + (alerte ? ", à régler" : ""))
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

// MARK: - Petites aides

/// Un champ d'une ligne avec son nom au-dessus.
private struct ChampNomme: View {
    let titre: String
    var aide: String? = nil
    let exemple: String
    @Binding var texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).typo(.corpsFort)
            ChampDoux(texte: $texte, exemple: exemple, lignes: 1...1)
                .accessibilityLabel(titre)
            if let a = aide { Text(a).typo(.legende) }
        }
    }
}

/// Une ligne d'information (clé à gauche, valeur à droite), avec un point d'état facultatif.
private struct LigneInfo: View {
    let cle: String
    let valeur: String
    var couleur: Color? = nil
    var selection = false
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(cle).typo(.corps, couleur: j.texteSecondaire).frame(width: 190, alignment: .leading)
            if let c = couleur {
                PointEtat(couleur: c, diametre: 7).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            Group {
                if selection {
                    Text(valeur).textSelection(.enabled)
                } else {
                    Text(valeur)
                }
            }
            .typo(.corps)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private extension Binding where Value == Bool {
    /// Interrupteur dans une `LigneReglage`.
    func interrupteur(_ titre: String) -> some View {
        Toggle(titre, isOn: self).toggleStyle(.switch).labelsHidden().accessibilityLabel(titre)
    }
}

/// Les champs de config/compte.yaml encore « [À COMPLÉTER : …] » (`champACompleter`, Modeles.swift).
private enum ChampsACompleter {
    /// Vrai si la valeur est un modèle à compléter (ou vide).
    static func vide(_ v: String) -> Bool { champACompleter(v) }
    /// Ce qu'on montre dans le champ : vide pour un modèle, la valeur sinon.
    static func affiche(_ v: String) -> String { champACompleter(v) ? "" : v }
}

private let joursSemaine = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

// MARK: - Compte

private struct RubriqueCompte: View {
    @Binding var r: Reglages
    /// Enregistre ce qui attend, puis lance Claude sur la charte (`lancerClaude(.charte)`).
    let adapterCharte: () -> Void
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    /// L'activité telle qu'elle était à l'arrivée sur la rubrique : si elle change, on propose d'adapter la charte.
    @Local private var activiteInitiale: String?
    @Local private var adaptationDemandee = false

    private var activiteChangee: Bool {
        guard let initiale = activiteInitiale else { return false }
        let a = r.activite.trimmingCharacters(in: .whitespacesAndNewlines)
        return !champACompleter(a) && a.lowercased() != initiale.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            carteActivite
            Carte(titre: "Toi", symbole: "person.crop.circle") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    ChampNomme(titre: "Ton nom", exemple: "Camille Martin", texte: aCompleter(\.nom))
                    ChampNomme(titre: "Compte Instagram", aide: "Sans le @.", exemple: "camille.photo",
                               texte: compteSansArobase)
                    ChampNomme(titre: "Où tu travailles", exemple: "Lyon et alentours", texte: aCompleter(\.localisation))
                    ChampNomme(titre: "Fuseau horaire", aide: "Par exemple Europe/Paris.", exemple: "Europe/Paris",
                               texte: aCompleter(\.fuseau))
                }
            }
            Carte(titre: "Ta voix", symbole: "text.quote") {
                LigneReglage("Tu écris", aide: "La personne des légendes.") {
                    ChoixEnPilules(options: [OptionReglage(valeur: "je", titre: "Je"),
                                             OptionReglage(valeur: "nous", titre: "Nous")],
                                   selection: $r.voix)
                        .fixedSize()
                }
                Filet()
                LigneReglage("Langue des légendes") {
                    ChoixEnPilules(options: [OptionReglage(valeur: "francais", titre: "Français"),
                                             OptionReglage(valeur: "anglais", titre: "Anglais"),
                                             OptionReglage(valeur: "bilingue", titre: "Les deux")],
                                   selection: $r.langue)
                        .fixedSize()
                }
                if r.langue == "bilingue" {
                    Text("Le français d'abord, puis l'anglais.").typo(.legende)
                }
            }
            Carte(titre: "Ton approche", symbole: "camera.aperture") {
                Text("La seule source que Claude utilise pour parler de ta pratique. Écris-la comme tu la raconterais.")
                    .typo(.legende)
                    .fixedSize(horizontal: false, vertical: true)
                ChampDoux(texte: aCompleter(\.approche), exemple: "Je photographie comme…", lignes: 4...14)
                    .accessibilityLabel("Ton approche")
            }
            Carte(titre: "Exemples de vraies légendes", symbole: "quote.bubble") {
                Text("Claude s'en inspire pour garder ta voix. Deux ou trois suffisent.")
                    .typo(.legende)
                ForEach(r.exemples_de_legendes.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        ChampDoux(texte: exemple(i), exemple: "Une légende que tu as écrite…", lignes: 2...8)
                            .accessibilityLabel("Exemple \(i + 1)")
                        Button {
                            withAnimation(j.anim(.doux)) {
                                if i < r.exemples_de_legendes.count { r.exemples_de_legendes.remove(at: i) }
                            }
                        } label: { Image(systemName: "minus") }
                        .buttonStyle(.rond(.claire, diametre: 30))
                        .help("Retirer cet exemple")
                        .accessibilityLabel("Retirer l'exemple \(i + 1)")
                        .padding(.top, 8)
                    }
                }
                Button {
                    withAnimation(j.anim(.doux)) { r.exemples_de_legendes.append("") }
                } label: { Label("Ajouter une légende", systemImage: "plus") }
                .buttonStyle(.pilule(.claire, taille: .petite))
            }
        }
    }

    // MARK: Ce que tu photographies

    private var carteActivite: some View {
        Carte(titre: "Ce que tu photographies", symbole: "camera.aperture") {
            Text("Claude choisit ses idées, son vocabulaire et ta charte en fonction de ton activité.")
                .typo(.legende)
                .fixedSize(horizontal: false, vertical: true)
            ChoixEnPilules(options: Reglages.activitesSuggerees.map { OptionReglage(valeur: $0, titre: $0.prefix(1).uppercased() + $0.dropFirst()) },
                           selection: aCompleter(\.activite))
                .padding(.top, 2)
            ChampDoux(texte: aCompleter(\.activite), exemple: "Ou écris la tienne : photographe culinaire, d'architecture…",
                      lignes: 1...1)
                .accessibilityLabel("Ce que tu photographies")
            if activiteChangee {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(j.accentTexte)
                        .accessibilityHidden(true)
                    Text(adaptationDemandee
                         ? "Claude adapte ta charte. Tu la retrouves dans Charte et règles."
                         : "Ta charte parle encore de ton ancienne activité.")
                        .typo(.corps)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !adaptationDemandee {
                        Button {
                            adaptationDemandee = true
                            adapterCharte()
                        } label: { Label("Adapter ma charte à cette activité", systemImage: "text.book.closed") }
                        .buttonStyle(.pilule(.sombre, taille: .petite, enCours: etat.lancementEnCours))
                        .disabled(etat.lancementEnCours || etat.claudeTravaille)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous).fill(j.fondDoux))
                .transition(j.transition(.apparition))
            }
        }
        .animation(j.anim(.doux), value: activiteChangee)
        .onAppear { if activiteInitiale == nil { activiteInitiale = ChampsACompleter.affiche(r.activite) } }
    }

    private var compteSansArobase: Binding<String> {
        Binding(get: { ChampsACompleter.affiche(r.compte_instagram) },
                set: { v in
                    let n = v.hasPrefix("@") ? String(v.dropFirst()) : v
                    if !(n.isEmpty && ChampsACompleter.vide(r.compte_instagram)) { r.compte_instagram = n }
                })
    }

    private func exemple(_ i: Int) -> Binding<String> {
        Binding(get: { i < r.exemples_de_legendes.count ? ChampsACompleter.affiche(r.exemples_de_legendes[i]) : "" },
                set: { v in
                    guard i < r.exemples_de_legendes.count,
                          !(v.isEmpty && ChampsACompleter.vide(r.exemples_de_legendes[i])) else { return }
                    r.exemples_de_legendes[i] = v
                })
    }

    /// Un champ encore « [À COMPLÉTER : …] » s'affiche vide, avec son exemple ; il ne change que si elle écrit.
    private func aCompleter(_ chemin: WritableKeyPath<Reglages, String>) -> Binding<String> {
        Binding(get: { ChampsACompleter.affiche(r[keyPath: chemin]) },
                set: { v in
                    if !(v.isEmpty && ChampsACompleter.vide(r[keyPath: chemin])) { r[keyPath: chemin] = v }
                })
    }
}

// MARK: - Publication

private struct RubriquePublication: View {
    @Binding var r: Reglages
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            Carte(titre: "Tes jours de publication", symbole: "calendar") {
                Text("Le studio publie ces jours-là, à l'heure choisie, seulement ce que tu as validé.")
                    .typo(.legende)
                ForEach(Array(joursSemaine.enumerated()), id: \.element) { i, jour in
                    if i > 0 { Filet() }
                    ligneJour(jour)
                }
            }
            Carte(titre: "Formats", symbole: "play.rectangle") {
                LigneReglage("Part de Reels", aide: "Le reste en carrousels et en images.") {
                    HStack(spacing: 12) {
                        Slider(value: $r.publication.part_reels, in: 0...0.6, step: 0.05)
                            .frame(width: 180)
                            .accessibilityLabel("Part de Reels")
                        Text("\(Int((r.publication.part_reels * 100).rounded())) %")
                            .font(.jakarta(14, graisse: 600))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Carte(titre: "Mise en page des images", symbole: "square.on.square") {
                LigneReglage("Marge autour des images sur fond", aide: "Pour les photos présentées avec des marges.") {
                    ReglageNombre(valeur: $r.mise_en_page.marge_px, plage: 0...200, pas: 8, unite: "px", libelle: "Marge")
                }
                ForEach([("clair", "Fond clair"), ("sombre", "Fond sombre"), ("papier", "Fond papier")], id: \.0) { cle, titre in
                    Filet()
                    LigneReglage(titre) {
                        ColorPicker(titre, selection: fond(cle), supportsOpacity: false).labelsHidden()
                    }
                }
            }
            Carte(titre: "Comptes toujours citables", symbole: "at") {
                EditeurLignes(titre: "Un compte par ligne, sans @",
                              aide: "En plus des prestataires de chaque galerie.",
                              valeurs: $r.comptes_autorises)
            }
        }
    }

    private func ligneJour(_ jour: String) -> some View {
        let heure = r.publication.creneaux[jour] ?? ""
        let actif = Binding(get: { !(r.publication.creneaux[jour] ?? "").isEmpty },
                            set: { r.publication.creneaux[jour] = $0 ? heureHabituelle : "" })
        return LigneReglage(jour.capitalized) {
            HStack(spacing: 14) {
                if !heure.isEmpty {
                    ChampHeure(heure: Binding(get: { r.publication.creneaux[jour] ?? "18:30" },
                                              set: { r.publication.creneaux[jour] = $0 }))
                        .transition(j.transition(.apparition))
                }
                actif.interrupteur("Publier le \(jour)")
            }
            .animation(j.anim(.doux), value: heure.isEmpty)
        }
    }

    /// L'heure déjà choisie pour les autres jours (18:30 sinon).
    private var heureHabituelle: String {
        joursSemaine.compactMap { r.publication.creneaux[$0]?.nonVide }.first ?? "18:30"
    }

    private func fond(_ cle: String) -> Binding<Color> {
        Binding(get: { Color(hex: r.mise_en_page.fonds[cle] ?? "#f6f2ec") ?? .white },
                set: { c in
                    let actuel = r.mise_en_page.fonds[cle] ?? "#f6f2ec"
                    if !InteractionsUtilisateur.memeCouleur(actuel, c) { r.mise_en_page.fonds[cle] = c.hex }
                })
    }
}

// MARK: - Création

private struct RubriqueCreation: View {
    @Binding var r: Reglages
    @Environment(\.jetons) private var j

    private var aValider: [String] { r.creation?.etapes_a_valider ?? ReglagesCreation.etapes }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            Carte(titre: "Les étapes que tu valides", symbole: "checkmark.circle") {
                Text("Quand tu crées un post, l'assistant s'arrête sur ces étapes pour que tu valides. Les autres, Claude les fait et passe à la suite.")
                    .typo(.legende)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ReglagesCreation.etapes, id: \.self) { etape in
                    LigneReglage(ReglagesCreation.libelle(etape), aide: aide(etape),
                                 symbole: ReglagesCreation.symbole(etape)) {
                        valider(etape).interrupteur("Valider : \(ReglagesCreation.libelle(etape))")
                    }
                    Filet()
                }
                LigneReglage("Aperçu et publication", aide: "L'aperçu se valide toujours : rien ne part sans toi.",
                             symbole: "iphone") {
                    Label("Toujours", systemImage: "lock.fill")
                        .typo(.legende)
                        .help("Cette étape ne se désactive pas.")
                }
            }
            Carte(titre: "Les idées du matin", symbole: "sunrise") {
                LigneReglage("Idées proposées chaque matin") {
                    ReglageNombre(valeur: nombreIdees, plage: 1...6, libelle: "Idées proposées")
                }
                Filet()
                LigneReglage("Dont idées « exploration »", aide: "Des pistes nouvelles, pour sortir de tes habitudes.") {
                    ReglageNombre(valeur: $r.routine.idees_exploration, plage: 0...max(0, r.routine.nombre_idees),
                                  libelle: "Idées exploration")
                }
            }
        }
    }

    private func aide(_ etape: String) -> String {
        let actif = aValider.contains(etape)
        switch etape {
        case "photos": return actif ? "Claude propose ; tu retires, ajoutes et réordonnes." : "Claude choisit les photos et leur ordre."
        case "legende": return actif ? "Claude écrit ; tu modifies le texte directement." : "Claude écrit la légende tout seul."
        case "musique": return actif ? "Claude propose trois musiques ; tu choisis." : "Claude choisit la musique."
        default: return ""
        }
    }

    private func valider(_ etape: String) -> Binding<Bool> {
        Binding(get: { aValider.contains(etape) }, set: { oui in
            var liste = Set(aValider)
            if oui { liste.insert(etape) } else { liste.remove(etape) }
            var c = r.creation ?? ReglagesCreation()
            c.etapes_a_valider = ReglagesCreation.etapes.filter { liste.contains($0) }
            withAnimation(j.anim(.selection)) { r.creation = c }
        })
    }

    private var nombreIdees: Binding<Int> {
        Binding(get: { r.routine.nombre_idees }, set: { n in
            r.routine.nombre_idees = n
            if r.routine.idees_exploration > n { r.routine.idees_exploration = n }
        })
    }
}

// MARK: - Claude

private struct RubriqueClaude: View {
    @Binding var r: Reglages
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @Local private var confirmerDeconnexion = false

    private static let modeles = [
        OptionReglage(valeur: "", titre: "Par défaut"),
        OptionReglage(valeur: "opus", titre: "Opus"),
        OptionReglage(valeur: "sonnet", titre: "Sonnet"),
        OptionReglage(valeur: "haiku", titre: "Haiku"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            carteEtat
            carteModele
            carteTravaux
        }
        .task {
            await etat.chargerClaude(silencieux: true)
            await etat.chargerHistoriqueClaude()
        }
        .confirmationDialog("Déconnecter Claude de ce Mac ?", isPresented: $confirmerDeconnexion) {
            Button("Se déconnecter", role: .destructive) { Task { await etat.deconnecterClaude() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Claude ne pourra plus préparer tes posts tant que tu ne l'auras pas reconnecté.")
        }
    }

    // MARK: État

    private var phrase: String {
        guard let c = etat.claude else { return "Je vérifie Claude…" }
        if etat.connexionEnCours { return "Termine la connexion dans ton navigateur." }
        if !c.installe { return "Claude n'est pas encore sur ce Mac." }
        if !c.connecte { return "Claude n'est pas connecté." }
        return etat.claudeTravaille ? "Claude travaille en ce moment." : "Claude est prêt."
    }

    private var couleur: Color {
        guard let c = etat.claude else { return j.texteTertiaire }
        if etat.claudeTravaille || etat.connexionEnCours { return j.accent }
        return c.pret ? j.succes : j.alerte
    }

    private var carteEtat: some View {
        Carte(titre: "Claude sur ce Mac", symbole: "sparkles") {
            HStack(spacing: 10) {
                PointEtat(couleur: couleur, pulse: etat.claudeTravaille || etat.connexionEnCours, diametre: 10)
                Text(phrase).typo(.titre3)
            }
            .accessibilityElement(children: .combine)
            if let c = etat.claude {
                VStack(spacing: 0) {
                    LigneInfo(cle: "Connexion", valeur: c.libelleMethode)
                    Filet()
                    LigneInfo(cle: "Version", valeur: c.version ?? (c.installe ? "Inconnue" : "—"))
                    if let s = c.libelleSource {
                        Filet()
                        LigneInfo(cle: "Installation", valeur: s)
                    }
                    if c.installe {
                        Filet()
                        LigneInfo(cle: "Outils du studio", valeur: c.plugin_present ? "Présents" : "Absents : réinstalle le studio",
                                  couleur: c.plugin_present ? j.succes : j.alerte)
                    }
                }
                if let conseil = c.conseil, !c.pret {
                    Text(conseil).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if etat.connexionEnCours {
                attenteConnexion
            }
            actions
                .padding(.top, 4)
        }
    }

    private var attenteConnexion: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Je t'attends ici. Ton mot de passe se tape dans le navigateur, jamais dans l'app.")
                .typo(.legende)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if etat.lienConnexion != nil {
                Button("Rouvrir la page") { etat.ouvrirLienConnexion() }.buttonStyle(.discret)
            }
            Button("Annuler") { etat.arreterConnexion() }.buttonStyle(.discret)
        }
    }

    @ViewBuilder private var actions: some View {
        let c = etat.claude
        HStack(spacing: 8) {
            if c?.installe == false {
                Button { Task { await etat.installerClaude() } } label: {
                    Label("Installer Claude", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.pilule(.sombre, enCours: etat.installationEnCours))
                .disabled(etat.installationEnCours)
            } else if c?.connecte == false {
                Button { coque.feuilleConnexion = true } label: {
                    Label("Se connecter", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.pilule(.sombre))
                .disabled(etat.connexionEnCours)
            } else if c?.connecte == true {
                Button {
                    Task {
                        await etat.deconnecterClaude()
                        coque.feuilleConnexion = true
                    }
                } label: { Label("Changer de compte", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.pilule(.claire))
                .disabled(etat.claudeTravaille)
                Button("Se déconnecter") { confirmerDeconnexion = true }
                    .buttonStyle(.destructif)
                    .disabled(etat.claudeTravaille)
            }
            Spacer(minLength: 0)
            Button { Task { await etat.chargerClaude() } } label: {
                Label("Vérifier", systemImage: "checkmark.seal")
            }
            .buttonStyle(.pilule(.claire, taille: .petite))
        }
    }

    // MARK: Modèle et effort

    private var reglagesClaude: Binding<ReglagesClaude> {
        Binding(get: { r.claude ?? ReglagesClaude() }, set: { r.claude = $0 })
    }

    private var optionsModele: [OptionReglage] {
        var o = RubriqueClaude.modeles
        let actuel = r.claude?.modele ?? ""
        if !o.contains(where: { $0.valeur == actuel }) { o.append(OptionReglage(valeur: actuel, titre: actuel)) }
        return o
    }

    private var carteModele: some View {
        Carte(titre: "Sa façon de travailler", symbole: "dial.medium") {
            // Titre au-dessus, pilules dessous : les deux rangées partent du même bord.
            choixEmpile("Modèle", aide: "Opus réfléchit davantage, Sonnet va plus vite. « Par défaut » suit Claude Code.") {
                ChoixEnPilules(options: optionsModele, selection: reglagesClaude.modele)
            }
            Filet()
            choixEmpile("Effort", aide: "Plus d'effort : des posts plus soignés, mais plus longs à préparer.") {
                ChoixEnPilules(options: ReglagesClaude.efforts.map { OptionReglage(valeur: $0, titre: ReglagesClaude.libelleEffort($0)) },
                               selection: reglagesClaude.effort)
            }
        }
    }

    private func choixEmpile<C: View>(_ titre: String, aide: String, @ViewBuilder _ choix: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).typo(.corpsFort)
                Text(aide).typo(.legende).fixedSize(horizontal: false, vertical: true)
            }
            choix()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    // MARK: Derniers travaux

    private var carteTravaux: some View {
        Carte(titre: "Derniers travaux", symbole: "clock.arrow.circlepath") {
            if etat.historiqueClaude.isEmpty {
                Text("Claude n'a encore rien fait sur ce Mac.").typo(.legende)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(etat.historiqueClaude.prefix(6).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Filet() }
                        LigneTravail(execution: e)
                    }
                }
            }
        }
    }
}

private struct LigneTravail: View {
    let execution: ExecutionClaude
    @Environment(\.jetons) private var j

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM 'à' HH:mm"
        return f
    }()

    private var quand: String {
        guard let d = execution.dateDebut else { return "" }
        let cal = Calendar.current
        let h = DateFormatter()
        h.locale = Locale(identifier: "fr_FR")
        h.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return "Aujourd'hui à \(h.string(from: d))" }
        if cal.isDateInYesterday(d) { return "Hier à \(h.string(from: d))" }
        let t = LigneTravail.date.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private var ton: TonPastille {
        if execution.enCours { return .douce }
        switch execution.etat {
        case "termine": return .succes
        case "erreur": return .alerte
        default: return .neutre
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: execution.tacheClaude?.symbole ?? "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(j.texte)
                .frame(width: 30, height: 30)
                .background(Circle().fill(j.fondDoux))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(execution.titreAffiche).typo(.corpsFort).lineLimit(1)
                Text([quand, execution.libelleDuree() ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .typo(.legende)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Pastille(execution.libelleEtat, ton: ton)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Instagram

private struct RubriqueInstagram: View {
    @Binding var r: Reglages
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var formulaire = false
    @Local private var route = "facebook"
    @Local private var appId = ""
    @Local private var secret = ""
    @Local private var jeton = ""
    @Local private var technique = false

    private static let siteApps = URL(string: "https://developers.facebook.com/apps/")!
    private static let explorateur = URL(string: "https://developers.facebook.com/tools/explorer/")!

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            carteEtat
            if formulaire {
                carteFormulaire
                    .transition(j.transition(.apparition))
            }
            carteReglages
        }
        .animation(j.anim(.doux), value: formulaire)
        .task { await etat.chargerInstagram(silencieux: true) }
        .onAppear { route = r.instagram.api == "instagram" ? "instagram" : "facebook" }
        .onDisappear { viderSecrets() }
    }

    // MARK: État

    private var couleur: Color {
        guard let i = etat.instagram else { return j.texteTertiaire }
        if i.connecte { return (i.joursRestants ?? 99) <= 10 ? j.alerte : j.succes }
        return j.alerte
    }

    private var expiration: String {
        guard let e = etat.instagram?.expire_le else { return "Inconnue" }
        if e == "jamais" { return "Sans expiration" }
        let lire = DateFormatter()
        lire.locale = Locale(identifier: "en_US_POSIX")
        lire.dateFormat = "yyyy-MM-dd"
        let ecrire = DateFormatter()
        ecrire.locale = Locale(identifier: "fr_FR")
        ecrire.dateFormat = "d MMMM yyyy"
        var t = lire.date(from: String(e.prefix(10))).map { ecrire.string(from: $0) } ?? e
        if let n = etat.instagram?.joursRestants {
            t += n < 0 ? " (expiré)" : (n == 0 ? " (aujourd'hui)" : (n == 1 ? " (demain)" : " (dans \(n) jours)"))
        }
        return t
    }

    private var carteEtat: some View {
        Carte(titre: "Ton compte", symbole: "camera") {
            if let i = etat.instagram {
                HStack(spacing: 10) {
                    PointEtat(couleur: couleur, diametre: 10)
                    Text(i.libelle).typo(.titre3)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 0) {
                    if let c = i.compte {
                        LigneInfo(cle: "Compte", valeur: "@" + (c.hasPrefix("@") ? String(c.dropFirst()) : c))
                        Filet()
                    }
                    LigneInfo(cle: "Relié", valeur: i.route == "instagram" ? "Avec Instagram seulement" : "Avec Facebook (musique d'Instagram)")
                    if i.connecte {
                        Filet()
                        LigneInfo(cle: "La connexion expire", valeur: expiration)
                    }
                }
                if let n = i.joursRestants, i.connecte, n <= 10 {
                    Label(n < 0 ? "La connexion a expiré : reconnecte ton compte pour continuer à publier."
                                : "La connexion expire bientôt : reconnecte ton compte pour ne rien manquer.",
                          systemImage: "exclamationmark.triangle.fill")
                        .typo(.legende, couleur: j.texte)
                        .foregroundStyle(j.alerte)
                }
                if let e = i.erreur, !i.connecte {
                    Text(e).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Je vérifie la connexion…").typo(.legende)
                }
            }
            HStack(spacing: 8) {
                if !formulaire {
                    Button { formulaire = true } label: {
                        Label(etat.instagram?.connecte == true ? "Reconnecter" : "Relier mon compte", systemImage: "link")
                    }
                    .buttonStyle(.pilule(etat.instagram?.connecte == true ? .claire : .sombre))
                }
                Spacer(minLength: 0)
                Button { Task { await etat.chargerInstagram() } } label: {
                    Label("Vérifier", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.pilule(.claire, taille: .petite))
            }
            .padding(.top, 4)
        }
    }

    // MARK: Formulaire sécurisé

    private var complet: Bool {
        guard !jeton.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if route == "instagram" { return true }
        return !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var carteFormulaire: some View {
        Carte(titre: "Relier ton compte", symbole: "lock.shield") {
            Text("Tes codes restent sur ce Mac, dans ton studio. Ils ne s'affichent jamais, même ici.")
                .typo(.legende)
            ChoixEnPilules(options: [OptionReglage(valeur: "facebook", titre: "Avec Facebook", symbole: "link"),
                                     OptionReglage(valeur: "instagram", titre: "Avec Instagram seulement", symbole: "camera")],
                           selection: $route)
            Text(route == "facebook"
                 ? "Recommandé : donne aussi accès à la musique d'Instagram. Il faut l'identifiant et la clé secrète de ton app Meta, puis un jeton de l'Explorateur."
                 : "Un seul jeton à copier (« Générer le jeton », dans le produit Instagram de ton app Meta), sans la musique d'Instagram.")
                .typo(.legende)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(Self.siteApps) } label: {
                    Label("Ouvrir le site de Meta", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.pilule(.claire, taille: .petite))
                if route == "facebook" {
                    Button { NSWorkspace.shared.open(Self.explorateur) } label: {
                        Label("Ouvrir l'Explorateur", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                }
            }
            VStack(alignment: .leading, spacing: j.esp.blocs) {
                if route == "facebook" {
                    ChampSecretNomme(titre: "Identifiant de l'app", aide: "Paramètres › Général, sur le site de Meta.",
                                     texte: $appId, envoyer: nil)
                    ChampSecretNomme(titre: "Clé secrète de l'app", aide: "Au même endroit, bouton « Afficher ».",
                                     texte: $secret, envoyer: nil)
                }
                ChampSecretNomme(titre: "Jeton d'accès",
                                 aide: route == "facebook" ? "Celui de l'Explorateur de l'API Graph."
                                                           : "Celui de « Générer le jeton », dans le produit Instagram.",
                                 texte: $jeton, envoyer: { if complet { relier() } })
            }
            .frame(maxWidth: 460, alignment: .leading)
            HStack(spacing: 8) {
                Button { relier() } label: { Label("Relier mon compte", systemImage: "link") }
                    .buttonStyle(.pilule(.sombre, enCours: etat.connexionInstagramEnCours))
                    .disabled(!complet || etat.connexionInstagramEnCours)
                Button("Annuler") {
                    viderSecrets()
                    formulaire = false
                }
                .buttonStyle(.discret)
                .disabled(etat.connexionInstagramEnCours)
            }
        }
    }

    /// Envoie les codes (fichier privé effacé par le moteur), puis vide les champs, que ça marche ou non.
    private func relier() {
        guard complet, !etat.connexionInstagramEnCours else { return }
        let rt = route
        let a = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = jeton.trimmingCharacters(in: .whitespacesAndNewlines)
        viderSecrets()
        etat.erreur = nil
        Task {
            let ok = await etat.connecterInstagram(route: rt, appId: rt == "facebook" ? a : "",
                                                   secret: rt == "facebook" ? s : "", jeton: t)
            if ok {
                formulaire = false
                if r.instagram.api != rt { r.instagram.api = rt }
                AccessibilityNotification.Announcement("Instagram est relié.").post()
            }
        }
    }

    private func viderSecrets() {
        appId = ""
        secret = ""
        jeton = ""
    }

    // MARK: Réglages de publication

    private var carteReglages: some View {
        Carte(titre: "Publication", symbole: "paperplane") {
            LigneReglage("Route utilisée", aide: "Avec Facebook, les Reels reçoivent leur musique automatiquement.") {
                ChoixEnPilules(options: [OptionReglage(valeur: "facebook", titre: "Facebook"),
                                         OptionReglage(valeur: "instagram", titre: "Instagram seul")],
                               selection: $r.instagram.api)
                    .fixedSize()
            }
            Filet()
            LigneReglage("Adresse temporaire pour publier", aide: "Instagram va chercher les images à cette adresse le temps de la publication.") {
                ChoixEnPilules(options: [OptionReglage(valeur: "tunnel", titre: "Cloudflare"),
                                         OptionReglage(valeur: "supabase", titre: "Supabase")],
                               selection: $r.publication.hebergement)
                    .fixedSize()
            }
            if r.publication.hebergement == "supabase" {
                ChampNomme(titre: "Bucket Supabase", exemple: "studio", texte: $r.publication.bucket_supabase)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            DisclosureGroup(isExpanded: $technique) {
                ChampNomme(titre: "Version de l'API", aide: "À changer seulement si Claude te le conseille.",
                           exemple: "v21.0", texte: $r.instagram.version_api)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(.top, 8)
            } label: {
                Text("Détails techniques").typo(.corpsFort)
            }
            .padding(.top, 4)
        }
    }
}

/// Champ sécurisé au style de `ChampDoux` (capsule blanche, focus d'encre) : rien ne s'affiche en clair.
private struct ChampSecretNomme: View {
    let titre: String
    let aide: String
    @Binding var texte: String
    let envoyer: (() -> Void)?
    @Environment(\.jetons) private var j
    @FocusState private var focus: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            Text(titre).typo(.corpsFort)
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .foregroundStyle(j.texteSecondaire)
                    .accessibilityHidden(true)
                SecureField(titre, text: $texte)
                    .focused($focus)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focusEffectDisabled()
                    .onSubmit { envoyer?() }
                    .typo(.champ)
                    .accessibilityLabel(titre)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(forme.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
            .overlay(forme.strokeBorder(focus ? j.encre.opacity(0.75) : j.traitFort.opacity(0.8), lineWidth: focus ? 1.5 : 1))
            .background(forme.stroke(j.accent.opacity(focus ? 0.16 : 0), lineWidth: 8))
            .animation(j.anim(.survol), value: focus)
            Text(aide).typo(.legende)
        }
    }
}

// MARK: - Planification

private struct RubriquePlanification: View {
    @Binding var r: Reglages
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var changement = false
    @Local private var affichage = Date()

    private var active: Bool { etat.planification?.active ?? etat.reglages?.planification?.active ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            Carte {
                LigneReglage("Le studio travaille tout seul",
                             aide: "Ton Mac doit être allumé ; en veille, la tâche part au réveil. Rien n'est publié sans ta validation.",
                             symbole: "clock.badge.checkmark") {
                    HStack(spacing: 10) {
                        if changement { ProgressView().controlSize(.small) }
                        Binding(get: { active }, set: { basculer($0) })
                            .interrupteur("Le studio travaille tout seul")
                            .disabled(changement)
                    }
                }
                if let conseil = etat.planification?.conseil {
                    Text(conseil).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            }
            carteTaches
            Carte(titre: "Les horaires", symbole: "clock") {
                Text("Les tâches suivent ces horaires dès leur prochain passage.").typo(.legende)
                LigneReglage("Idées du matin", aide: "Claude prépare tes idées à cette heure-là.", symbole: "sunrise") {
                    ChampHeure(heure: $r.routine.heure_idees)
                }
                Filet()
                LigneReglage("Bilan de la semaine", aide: "Claude relit tes chiffres et retient ce qui marche.",
                             symbole: "chart.bar.doc.horizontal") {
                    HStack(spacing: 10) {
                        Picker("Jour du bilan", selection: $r.routine.jour_bilan) {
                            ForEach(joursSemaine, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        ChampHeure(heure: $r.routine.heure_bilan)
                    }
                }
                Text("Les heures de publication se règlent dans Publication.").typo(.legende)
            }
            Carte(titre: "Quand une décision t'attend", symbole: "macwindow") {
                LigneReglage("Ouvrir l'app toute seule", aide: "Quand tes idées sont prêtes ou qu'un post attend ta validation.") {
                    $r.interface.ouvrir_app.interrupteur("Ouvrir l'app toute seule")
                }
            }
        }
        .task {
            affichage = Date()
            await etat.chargerPlanification(silencieux: true)
            affichage = Date()
        }
    }

    private var carteTaches: some View {
        Carte(titre: "Ses tâches", symbole: "checklist") {
            let taches = etat.planification?.taches ?? []
            if etat.planification == nil {
                ProgressView().controlSize(.small)
            } else if taches.isEmpty {
                Text(active ? "Aucune tâche pour l'instant." : "Active « Le studio travaille tout seul » pour que les tâches partent toutes seules.")
                    .typo(.legende)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(taches.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Filet() }
                        LigneReglage(t.titreAffiche, aide: t.quand, symbole: t.symbole) {
                            etatTache(t)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func etatTache(_ t: TachePlanifiee) -> some View {
        if !active {
            Pastille("Arrêtée", symbole: "moon.zzz")
        } else if t.chargee {
            Pastille(t.libelleProchaine.map { "Prochaine : \($0)" } ?? "Prévue", symbole: "clock.fill", ton: .succes)
        } else {
            Pastille("À relancer", symbole: "exclamationmark.circle.fill", ton: .alerte)
                .help("Désactive puis réactive « Le studio travaille tout seul ».")
        }
    }

    private func basculer(_ oui: Bool) {
        // Seulement sur un geste réel : jamais à l'affichage ni quand le moteur renvoie l'état.
        guard oui != active, !changement, InteractionsUtilisateur.partage.voulu(depuis: affichage) else { return }
        changement = true
        Task {
            let ok = await etat.planifier(activer: oui)
            if ok { etat.message = nil }   // l'interrupteur suffit : pas de bandeau en plus
            r.planification = etat.reglages?.planification
            changement = false
        }
    }
}

// MARK: - Charte et règles

private struct RubriqueCharteRegles: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            Carte(titre: "Ta charte", symbole: "text.book.closed") {
                Text("Le texte que Claude suit pour chaque idée et chaque post : ton identité, tes thèmes, ton feed, tes légendes.")
                    .typo(.legende)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { etat.montrer(.charte) } label: { Label("Ouvrir la charte", systemImage: "arrow.right") }
                        .buttonStyle(.pilule(.sombre))
                    Button { Task { _ = await etat.lancerClaude(.charte) } } label: {
                        Label("L'adapter à mon activité", systemImage: "sparkles")
                    }
                    .buttonStyle(.pilule(.claire, enCours: etat.lancementEnCours))
                    .disabled(etat.lancementEnCours || etat.claudeTravaille)
                    .help("Claude réécrit ta charte pour ce que tu photographies (Réglages › Compte).")
                }
                .padding(.top, 4)
            }
            Carte(titre: "Tes règles", symbole: "checkmark.shield") {
                Text("Ce que le contrôle refuse ou signale avant chaque publication : mots interdits, limites, alternance du feed.")
                    .typo(.legende)
                    .fixedSize(horizontal: false, vertical: true)
                Button { etat.montrer(.regles) } label: { Label("Ouvrir les règles", systemImage: "arrow.right") }
                    .buttonStyle(.pilule(.claire))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Avancé

private struct RubriqueAvance: View {
    @Binding var r: Reglages
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    private var versionApp: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "2.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            Carte(titre: "Le dossier du studio", symbole: "folder") {
                Text(etat.dossier.path)
                    .typo(.mono)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([etat.dossier]) } label: {
                        Label("Montrer dans le Finder", systemImage: "folder")
                    }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                    Button { etat.choisirDossier() } label: {
                        Label("Choisir un autre dossier…", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                }
            }
            carteEtat
            Carte(titre: "Sur ton téléphone", symbole: "iphone") {
                LigneReglage("Publier aussi les pages en Artifact privé",
                             aide: "Pour relire les idées et l'aperçu depuis ton téléphone.") {
                    $r.interface.artifact.interrupteur("Publier aussi les pages en Artifact privé")
                }
            }
            Carte(titre: "Photos à ne jamais reprendre", symbole: "eye.slash") {
                EditeurLignes(titre: "Un identifiant de photo par ligne",
                              aide: "Le studio les écarte de toutes les propositions.",
                              valeurs: $r.images_deja_publiees)
            }
        }
        .task { await etat.chargerSante() }
    }

    private var carteEtat: some View {
        Carte(titre: "Version et état", symbole: "info.circle") {
            if let s = etat.sante {
                VStack(spacing: 0) {
                    LigneInfo(cle: "Version du studio", valeur: s.version ?? "Inconnue")
                    Filet()
                    LigneInfo(cle: "Version de l'app", valeur: versionApp)
                    Filet()
                    LigneInfo(cle: "Instagram",
                              valeur: (s.instagram_connecte ?? false)
                                ? "Connecté" + (s.jeton_expire_le.map { $0 == "jamais" ? "" : ", jusqu'au \($0)" } ?? "")
                                : "Non connecté",
                              couleur: (s.instagram_connecte ?? false) ? j.succes : j.alerte)
                    Filet()
                    LigneInfo(cle: "Adresse temporaire",
                              valeur: (s.hebergement_pret ?? false) ? "Prête (\(s.hebergement == "supabase" ? "Supabase" : "Cloudflare"))" : "À installer",
                              couleur: (s.hebergement_pret ?? false) ? j.succes : j.alerte)
                    Filet()
                    LigneInfo(cle: "Montage des Reels", valeur: (s.ffmpeg ?? false) ? "Prêt" : "Outil de montage manquant",
                              couleur: (s.ffmpeg ?? false) ? j.succes : j.alerte)
                    Filet()
                    LigneInfo(cle: "Galeries et publications", valeur: "\(s.galeries ?? 0) galeries, \(s.publications ?? 0) publications")
                    if let manques = s.a_completer, !manques.isEmpty {
                        Filet()
                        LigneInfo(cle: "À compléter", valeur: manques.joined(separator: ", "), couleur: j.alerte)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Button { Task { await etat.chargerSante() } } label: {
                Label("Vérifier de nouveau", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.pilule(.claire, taille: .petite))
        }
    }
}

// MARK: - Apparence (quatre réglages : mode, ambiance, nom du studio, salutation)

private struct RubriqueApparence: View {
    let prenom: String
    @Binding var sauvegarde: EtatSauvegarde
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var brouillon = Apparence.defaut
    @Local private var tache: Task<Void, Never>?
    @Local private var serie = 0
    @Local private var enAttente = false
    /// L'apparence d'avant la série de changements en cours (pour « Annuler »).
    @Local private var avant: Apparence?
    /// Dernière série enregistrée : « Apparence mise à jour » + Annuler (revient à cette valeur).
    @Local private var annulable: Apparence?
    @Local private var derniere: Apparence?
    @Local private var confirmerRetablir = false
    /// Quand le brouillon a été (re)pris de `etat.apparence` : un changement n'est voulu que s'il suit un geste fait après.
    @Local private var affichage = Date()

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > 800 {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        colonneReglages
                            .padding(.leading, j.esp.page)
                            .padding(.trailing, j.esp.page * 0.6)
                            .padding(.top, j.esp.page * 0.7)
                            .padding(.bottom, j.esp.page)
                    }
                    colonneApercu
                        .padding(.top, j.esp.page * 0.7)
                        .padding(.trailing, j.esp.page)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: j.esp.sections * 0.6) {
                        rangeeApercu
                        colonneReglages
                    }
                    .padding(.horizontal, j.esp.page)
                    .padding(.top, j.esp.page * 0.7)
                    .padding(.bottom, j.esp.page)
                }
            }
        }
        .onAppear {
            InteractionsUtilisateur.partage.demarrer()
            brouillon = etat.apparence
            affichage = Date()
        }
        .onChange(of: etat.apparence) { _, a in
            // Une personnalisation faite par Claude (ou Rétablir) s'affiche ici aussi, sans rien réécrire.
            guard !enAttente, a != brouillon, a != derniere?.normalisee() else { return }
            withAnimation(j.anim(.theme)) { brouillon = a }
            affichage = Date()
        }
        .onDisappear { enregistrerMaintenant() }
        .alert("Rétablir l'apparence d'origine ?", isPresented: $confirmerRetablir) {
            Button("Rétablir", role: .destructive) { retablir() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'ambiance Provence, le mode automatique et le nom d'origine reviennent. Tes autres réglages ne changent pas.")
        }
    }

    // MARK: Colonnes

    private var colonneReglages: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.5) {
            entete
            carteAmbiance
            carteMode
            carteStudio
            DemandeClaudeReglages(titre: "Envie d'autre chose ?",
                                  texte: "Demande-le à Claude : une couleur, une ambiance, une autre salutation…",
                                  debut: "Pour l'apparence de l'app, j'aimerais ",
                                  contexte: "Réglages › Apparence")
            HStack {
                Button("Rétablir l'apparence d'origine") { confirmerRetablir = true }
                    .buttonStyle(.destructif)
                Spacer()
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            EnTeteEcran(surTitre: "Réglages", titre: RubriqueReglages.apparence.titre,
                        chapo: RubriqueReglages.apparence.chapo)
            if let precedente = annulable {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(j.succes)
                    Text("Apparence mise à jour").typo(.corps)
                    Button("Annuler") { annuler(vers: precedente) }
                        .buttonStyle(.discret)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(j.fondSucces))
                .transition(j.transition(.apparition))
                .task(id: precedente) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if !Task.isCancelled { withAnimation(j.anim(.doux)) { annulable = nil } }
                }
            }
        }
        .animation(j.anim(.doux), value: annulable)
    }

    private var colonneApercu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aperçu").typo(.surtitre)
            miniature(.light, echelle: 0.5)
            Text("Clair").typo(.legende)
            miniature(.dark, echelle: 0.5)
                .padding(.top, 4)
            Text("Sombre").typo(.legende)
        }
    }

    private var rangeeApercu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aperçu").typo(.surtitre)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) { miniature(.light, echelle: 0.42); Text("Clair").typo(.legende) }
                VStack(alignment: .leading, spacing: 6) { miniature(.dark, echelle: 0.42); Text("Sombre").typo(.legende) }
            }
        }
    }

    private func miniature(_ schema: ColorScheme, echelle: CGFloat) -> some View {
        ApercuTheme(apparence: brouillon, schema: schema) {
            MiniFenetreStudio(prenom: prenom, ecrans: brouillon.ecransVisibles)
        }
        .frame(width: 560, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .scaleEffect(echelle, anchor: .topLeading)
        .frame(width: 560 * echelle, height: 360 * echelle, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 30 * echelle, style: .continuous).strokeBorder(j.trait, lineWidth: 1))
        .ombre(.carte)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(schema == .dark ? "Aperçu de l'app en mode sombre" : "Aperçu de l'app en mode clair")
    }

    // MARK: Les quatre réglages

    private var carteAmbiance: some View {
        Carte(titre: "Ambiance", symbole: "paintpalette") {
            Text("Les couleurs du fond de l'app.").typo(.legende)
            // Les cinq sur une seule rangée, quelle que soit la largeur.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 84), spacing: 10, alignment: .top), count: 5),
                      alignment: .leading, spacing: 14) {
                ForEach(Ambiance.allCases) { a in
                    VignetteAmbiance(ambiance: a, apparence: brouillon, choisie: brouillon.ambiance == a.rawValue) {
                        changer { $0.ambiance = a.rawValue }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var carteMode: some View {
        Carte(titre: "Mode", symbole: "circle.lefthalf.filled") {
            Text("« Auto » suit le réglage de ton Mac, clair le jour et sombre le soir.").typo(.legende)
            ChoixEnPilules(options: [OptionReglage(valeur: "auto", titre: "Auto", symbole: "circle.lefthalf.filled"),
                                     OptionReglage(valeur: "clair", titre: "Clair", symbole: "sun.max"),
                                     OptionReglage(valeur: "sombre", titre: "Sombre", symbole: "moon")],
                           selection: lien(\.mode))
                .fixedSize()
                .padding(.top, 4)
        }
    }

    private var carteStudio: some View {
        Carte(titre: "Ton studio", symbole: "textformat") {
            HStack(alignment: .top, spacing: 16) {
                ChampNomme(titre: "Nom du studio", aide: "En haut de chaque page.", exemple: "Studio Instagram",
                           texte: lien(\.nom_affiche))
                ChampNomme(titre: "Salutation", aide: "Le premier mot de l'accueil, avant ton prénom.", exemple: "Bonjour",
                           texte: lien(\.salutation))
            }
        }
    }

    // MARK: Brouillon et enregistrement

    private func lien<T>(_ chemin: WritableKeyPath<Apparence, T>) -> Binding<T> {
        Binding(get: { brouillon[keyPath: chemin] }, set: { v in changer { $0[keyPath: chemin] = v } })
    }

    /// Change le brouillon (aperçu en direct aussitôt), puis l'enregistre 0,6 s après le dernier changement —
    /// seulement si la valeur change vraiment et que le changement suit un geste de la photographe
    /// (jamais à l'affichage, au chargement ni quand `etat.apparence` change d'ailleurs).
    private func changer(_ modification: (inout Apparence) -> Void) {
        var a = brouillon
        modification(&a)
        guard a != brouillon, InteractionsUtilisateur.partage.voulu(depuis: affichage) else { return }
        if avant == nil { avant = etat.apparence }
        withAnimation(j.anim(.theme)) { brouillon = a }
        planifier(delai: 600_000_000)
    }

    private func planifier(delai: UInt64) {
        tache?.cancel()
        serie += 1
        let numero = serie
        enAttente = true
        sauvegarde = .enAttente
        tache = Task { @MainActor in
            if delai > 0 { try? await Task.sleep(nanoseconds: delai) }
            guard !Task.isCancelled else { return }
            await enregistrer(numero)
        }
    }

    private func enregistrerMaintenant() {
        guard enAttente else { return }
        planifier(delai: 0)
    }

    private func enregistrer(_ numero: Int) async {
        let a = brouillon
        let precedente = avant
        sauvegarde = .enCours
        derniere = a
        let ok = await etat.appliquerApparenceSansBandeau(a)
        guard numero == serie else { return }   // un changement plus récent attend déjà
        enAttente = false
        tache = nil
        avant = nil
        if ok {
            sauvegarde = .fait
            if let p = precedente, p != etat.apparence { withAnimation(j.anim(.doux)) { annulable = p } }
        } else {
            sauvegarde = .echec
            withAnimation(j.anim(.theme)) { brouillon = etat.apparence }
        }
    }

    private func annuler(vers precedente: Apparence) {
        withAnimation(j.anim(.doux)) { annulable = nil }
        withAnimation(j.anim(.theme)) { brouillon = precedente }
        avant = nil
        planifier(delai: 0)
    }

    private func retablir() {
        tache?.cancel()
        serie += 1
        enAttente = false
        annulable = nil
        avant = nil
        Task {
            await etat.retablirApparence()
            withAnimation(j.anim(.theme)) { brouillon = etat.apparence }
            affichage = Date()
            sauvegarde = .fait
        }
    }
}

/// Une ambiance en vignette : son fond qui dérive lentement, son nom et sa phrase ; choisie = anneau d'encre.
private struct VignetteAmbiance: View {
    let ambiance: Ambiance
    let apparence: Apparence
    let choisie: Bool
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        var variante = apparence
        variante.ambiance = ambiance.rawValue
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte * 0.75, style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ApercuTheme(apparence: variante, schema: j.schema) {
                    FondAmbiance(anime: false)
                }
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                .clipShape(forme)
                .overlay(forme.strokeBorder(choisie ? j.encre : j.trait, lineWidth: choisie ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if choisie {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(j.surEncre, j.encre)
                            .padding(6)
                            .transition(j.transition(.apparition))
                    }
                }
                .ombre(survol || choisie ? .carte : .repos)
                .offset(y: survol && j.deplacements ? -2 : 0)
                Text(ambiance.nom).typo(.corpsFort)
                Text(ambiance.description)
                    .typo(.legende)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(j.anim(.survol), value: survol)
        .animation(j.anim(.selection), value: choisie)
        .accessibilityLabel("\(ambiance.nom). \(ambiance.description)")
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

/// Une mini-fenêtre du studio, dessinée avec les vrais composants et les jetons du brouillon
/// (rendue à 560 × 360, puis réduite) : barre d'icônes, page de verre, titre en deux tons, cartes, pilule.
private struct MiniFenetreStudio: View {
    let prenom: String
    let ecrans: [Ecran]
    @Environment(\.jetons) private var j

    var body: some View {
        let sombre = j.schema == .dark
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(j.surEncre)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(j.encre))
                ForEach(Array(ecrans.prefix(6).enumerated()), id: \.offset) { i, e in
                    Image(systemName: e.symbole)
                        .font(.system(size: 13, weight: i == 0 ? .semibold : .regular))
                        .symbolVariant(i == 0 ? .fill : j.varianteSymboles)
                        .foregroundStyle(j.encre.opacity(i == 0 ? 1 : 0.62))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(i == 0 ? (sombre ? 0.14 : 1) : (sombre ? 0.06 : 0.55))))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 22)
            .frame(width: 66)
            PanneauPage {
                VStack(alignment: .leading, spacing: 12) {
                    TitreDeuxTons(debut: "\(prenomSalue), ", suite: "trois idées t'attendent.", role: .titre1)
                        .lineLimit(2)
                    Text("Claude les a préparées ce matin.").typo(.chapo).lineLimit(1)
                    Carte(titre: "Tes idées du jour", symbole: "lightbulb") {
                        Text("Choisis celle que Claude prépare.").typo(.legende).lineLimit(1)
                        Button {} label: { Label("Choisir une idée", systemImage: "wand.and.stars") }
                            .buttonStyle(.pilule(.sombre))
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(22)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 12)
        }
        .background(FondAmbiance(anime: false))
    }

    private var prenomSalue: String {
        let salut = j.apparence.salutation.trimmingCharacters(in: .whitespaces)
        return [salut.isEmpty ? "Bonjour" : salut, prenom].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
