import AppKit
import SwiftUI

// La coque de l'app (DESIGN.md §4.1) : fenêtre sur le fond d'ambiance, barre d'icônes à gauche, page de verre
// avec son en-tête, routage animé (Accueil = flux unique `VueAccueil`), onboarding plein écran, bandeau,
// panneau « Demander à Claude » (⌘K), activité de Claude en direct, menus et pastille du Dock.

@main
struct StudioInstagramApp: App {
    @StateObject private var etat = EtatApp()
    @StateObject private var theme = Theme.partage
    @StateObject private var coque = CoqueStudio()

    var body: some Scene {
        Window("Studio Instagram", id: "principal") {
            VueRacine()
                .environmentObject(etat)
                .environmentObject(coque)
                .themeStudio(theme)
                .frame(minWidth: 1080, minHeight: 700)
                .onAppear {
                    theme.suivre(etat)
                    etat.demarrer()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands { CommandesStudio(etat: etat, coque: coque) }
    }
}

// MARK: - Mémoire de l'onboarding

/// Clés UserDefaults partagées avec l'onboarding (`VueBienvenue`).
enum CleOnboarding {
    /// Mise à vrai par « Ouvrir mon studio », la dernière page de l'onboarding.
    static let termine = "onboarding.termine"
    /// Mise à vrai par la coque dès que Claude a été vu prêt une fois : une déconnexion plus tard
    /// ne relance pas l'onboarding (le bandeau propose de se reconnecter).
    static let claudeDejaPret = "onboarding.claudeDejaPret"
    /// Dernière exécution de Claude dont le résultat a été vu (l'indicateur repasse à « Claude est prêt »).
    static let executionVue = "claude.executionVue"
}

// MARK: - État de la coque

/// Ce que la coque partage avec les écrans : le panneau « Demander à Claude » (conversation, file d'attente),
/// la feuille de reconnexion, l'onboarding visible. Injecté à la racine : `@EnvironmentObject var coque: CoqueStudio`.
@MainActor
final class CoqueStudio: ObservableObject {
    /// Panneau « Demander à Claude » (⌘K).
    @Published var panneauOuvert = false
    /// Fil du panneau (ses demandes, les réponses de Claude).
    @Published var messages: [MessagePanneau] = []
    /// Elle a retiré l'écran courant du contexte de ses demandes (revient au changement d'écran).
    @Published var contexteRetire = false
    /// Feuille plein écran « Connexions » (reconnecter ou installer Claude).
    @Published var feuilleConnexion = false
    /// L'onboarding occupe la fenêtre : les commandes du studio sont inactives.
    @Published var onboardingVisible = false
    /// Le bandeau « Claude n'est plus connecté » a été fermé (jusqu'à la prochaine reconnexion).
    @Published var deconnexionMasquee = false
    /// Demandes écrites pendant que Claude travaillait : elles partent dès qu'il a fini.
    @Published private(set) var fileAttente: [String] = []
    /// Dernière exécution dont le résultat a été vu.
    @Published var executionVue: String? = UserDefaults.standard.string(forKey: CleOnboarding.executionVue) {
        didSet { UserDefaults.standard.set(executionVue, forKey: CleOnboarding.executionVue) }
    }

    private var demandesLancees: Set<String> = []
    private var reponsesDonnees: Set<String> = []
    private var premiereExecution = true

    /// Envoie une demande libre à Claude (`.demande`) et, par défaut, ouvre le panneau sur la réponse.
    /// `contexte` : l'écran d'où elle parle (ajouté à la consigne, pas au fil).
    func demander(_ texte: String, etat: EtatApp, contexte: String? = nil, ouvrir: Bool = true) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(MessagePanneau(id: UUID().uuidString, deClaude: false, texte: t, le: Date()))
        if ouvrir { panneauOuvert = true }
        var consigne = t
        if let c = contexte {
            consigne += "\n\n(Elle te parle depuis l'écran « \(c) » de l'app, jour affiché : \(etat.jour).)"
        }
        if etat.claudeTravaille || etat.lancementEnCours {
            fileAttente.append(consigne)
            return
        }
        Task { await lancer(consigne, etat: etat) }
    }

    /// « Nouveau post » (⌘N) : ramène au temps 1 du flux de l'Accueil (les idées). `VueAccueil` peut observer
    /// `demandeNouveauPost` (`.onChange(of: coque.demandeNouveauPost)`) pour repartir de zéro.
    @Published private(set) var demandeNouveauPost = 0

    func nouveauPost(_ etat: EtatApp) {
        demandeNouveauPost += 1
        etat.montrer(.aujourdhui)
    }

    func nouvelleConversation(_ etat: EtatApp) {
        messages = []
        fileAttente = []
        Task { await etat.nouvelleConversation() }
    }

    private func lancer(_ consigne: String, etat: EtatApp) async {
        if await etat.lancerClaude(.demande, consigne: consigne) {
            if let id = etat.execution?.id { demandesLancees.insert(id) }
        } else if etat.claudeTravaille {
            // « deja_en_cours » : elle partira à la fin de l'exécution en cours.
            fileAttente.insert(consigne, at: 0)
        } else if etat.invitationClaude != nil {
            messages.append(MessagePanneau(id: UUID().uuidString, deClaude: true,
                                           texte: "Je ne suis pas connecté pour l'instant. Reconnecte-moi, puis renvoie ta demande.",
                                           le: Date()))
        }
    }

    /// À chaque changement de l'exécution suivie : réponse dans le fil, demande suivante de la file.
    func suivre(_ e: ExecutionClaude?, etat: EtatApp) {
        guard let e = e, !e.aucune else { return }
        if premiereExecution {
            premiereExecution = false
            // Une exécution déjà finie au lancement de l'app n'est plus une nouveauté.
            if e.terminee && executionVue == nil { executionVue = e.id }
        }
        guard e.terminee else { return }
        if demandesLancees.contains(e.id) && !reponsesDonnees.contains(e.id) {
            reponsesDonnees.insert(e.id)
            let texte: String
            switch e.etat {
            case "annule": texte = "Je me suis arrêté à ta demande."
            case "termine": texte = e.resultat ?? "C'est fait."
            default: texte = e.erreur ?? "Je n'ai pas pu terminer. Réessaie dans un instant."
            }
            messages.append(MessagePanneau(id: "claude|\(e.id)", deClaude: true, texte: texte, le: Date()))
            if panneauOuvert { executionVue = e.id }
        }
        if !fileAttente.isEmpty {
            let suivante = fileAttente.removeFirst()
            Task { await lancer(suivante, etat: etat) }
        }
    }
}

// MARK: - Racine

struct VueRacine: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @EnvironmentObject var theme: Theme
    @Environment(\.jetons) private var j
    @AppStorage(CleOnboarding.termine) private var onboardingTermine = false
    @AppStorage(CleOnboarding.claudeDejaPret) private var claudeDejaPret = false

    /// Studio absent, Claude jamais prêt, ou onboarding jamais fini.
    private var montrerOnboarding: Bool { !etat.studioInstalle || !claudeDejaPret || !onboardingTermine }
    var body: some View {
        contenu
            .overlay { BandeauCoque(onboarding: montrerOnboarding) }
            .animation(j.anim(.page), value: montrerOnboarding)
            .sheet(isPresented: $coque.feuilleConnexion) { feuille }
            .modifier(SuiviCoque(onboarding: montrerOnboarding, synchroniser: synchroniserClaude,
                                 dock: mettreAJourDock))
    }

    @ViewBuilder private var contenu: some View {
        ZStack {
            // L'onboarding dessine déjà son propre fond : un seul fond animé à la fois.
            if !montrerOnboarding { FondAmbiance() }
            if montrerOnboarding {
                VueBienvenue()
                    .transition(.opacity)
            } else {
                VueStudio()
                    .transition(.opacity)
            }
        }
    }

    private var feuille: some View {
        FeuilleConnexionClaude()
            .frame(minWidth: 960, idealWidth: 1100, minHeight: 640, idealHeight: 760)
            .environmentObject(etat)
            .environmentObject(coque)
            .themeStudio(theme)
    }

    private func synchroniserClaude() {
        guard etat.claudePret else { return }
        if !claudeDejaPret { claudeDejaPret = true }
        coque.deconnexionMasquee = false
        if coque.feuilleConnexion { coque.feuilleConnexion = false }
    }

    /// Pastille du Dock : nombre de journées où une décision l'attend (idées à choisir, post à valider).
    private func mettreAJourDock() {
        var statuts: [String: String] = [:]
        for r in etat.jours { statuts[r.jour] = r.statut ?? "" }
        if let v = etat.vue { statuts[v.jour] = v.statut ?? "" }
        let n = statuts.values.filter { $0 == "idees_proposees" || $0 == "brouillon_pret" }.count
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }
}

/// Ce que la racine surveille : Claude prêt (mémoire de l'onboarding), exécutions (fil du panneau),
/// statuts des journées (pastille du Dock), messages en double.
private struct SuiviCoque: ViewModifier {
    let onboarding: Bool
    let synchroniser: () -> Void
    let dock: () -> Void
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio

    func body(content: Content) -> some View {
        content
            .onAppear {
                synchroniser()
                coque.onboardingVisible = onboarding
                coque.suivre(etat.execution, etat: etat)
                dock()
            }
            .onChange(of: etat.claude) { _, _ in synchroniser() }
            .onChange(of: onboarding) { _, v in coque.onboardingVisible = v }
            .onChange(of: etat.execution) { _, e in coque.suivre(e, etat: etat) }
            .modifier(SuiviJours(dock: dock))
    }
}

private struct SuiviJours: ViewModifier {
    let dock: () -> Void
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio

    private var statuts: [String] { etat.jours.map { $0.statut ?? "" } }

    func body(content: Content) -> some View {
        content
            .onChange(of: etat.vue?.statut) { _, _ in dock() }
            .onChange(of: statuts) { _, _ in dock() }
            .onChange(of: etat.message) { _, m in effacerDoublon(m) }
    }

    /// La réponse d'une demande s'affiche déjà dans le panneau ouvert : pas de bandeau en double.
    private func effacerDoublon(_ m: String?) {
        guard coque.panneauOuvert, let m = m, let derniere = coque.messages.last, derniere.deClaude,
              m.hasPrefix(derniere.texte) else { return }
        etat.message = nil
    }
}

// MARK: - Studio : barre d'icônes + page

/// La barre réduite à l'essentiel (simplification du 22/11) : « + », Accueil, Galeries, Statistiques, Réglages.
/// Idées et Aperçu s'ouvrent depuis l'accueil et le « + » ; Charte et Règles depuis les Réglages.
enum BarreStudio {
    static let essentiels: [Ecran] = [.aujourdhui, .galeries, .statistiques, .reglages]

    /// Les écrans de la barre, dans l'ordre d'`apparence.ecrans` (le moteur n'y met plus que l'essentiel).
    static func ecrans(_ a: Apparence) -> [Ecran] {
        let liste = a.ecransVisibles.filter { essentiels.contains($0) }
        return liste.count >= 2 ? liste : essentiels
    }

    static func elements(_ a: Apparence) -> [ElementBarre<Ecran>] {
        ecrans(a).map { ElementBarre(id: $0, titre: titre($0), symbole: $0.symbole) }
    }

    static func titre(_ e: Ecran) -> String { e == .aujourdhui ? "Accueil" : e.titre }

    static func parent(_ e: Ecran) -> Ecran {
        switch e {
        case .idees, .apercu, .creation: return .aujourdhui
        case .charte, .regles: return .reglages
        default: return e
        }
    }
}

/// La fenêtre du studio : barre d'icônes à gauche, la page de verre (en-tête + écran) à droite,
/// le panneau « Demander à Claude » en inspecteur.
private struct VueStudio: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j

    private var ecranCourant: Ecran { etat.ecran ?? .aujourdhui }

    /// Accueil, création et idées sont le même flux : même identité, pour que passer de l'un à l'autre
    /// (par exemple `ecran_suivant = creation` à la fin d'une génération) ne remette pas le flux à zéro.
    private var identite: Ecran {
        switch ecranCourant {
        case .creation, .idees: return .aujourdhui
        default: return ecranCourant
        }
    }

    /// L'icône allumée : celle de l'écran, ou de son parent (Idées, Aperçu → Accueil ; Charte, Règles → Réglages).
    private var selection: Binding<Ecran> {
        Binding(get: { BarreStudio.parent(ecranCourant) },
                set: { e in withAnimation(j.anim(.page)) { etat.ecran = e } })
    }

    var body: some View {
        HStack(spacing: 0) {
            // Plus de « + » séparé : l'Accueil EST la création d'un post (conception/flux-unique.md).
            BarreIcones(elements: BarreStudio.elements(etat.apparence), selection: selection) {
                PiedBarre()
            }
            .zIndex(1)
            PanneauPage {
                VStack(spacing: 0) {
                    EnTetePage()
                    ZStack {
                        ecran
                            .id(identite)
                            .transition(j.transition(.ecran))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .animation(j.anim(.page), value: identite)
                }
            }
            .padding(.vertical, 16)
            .padding(.trailing, 16)
        }
        .inspector(isPresented: $coque.panneauOuvert) {
            PanneauClaude()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .onChange(of: ecranCourant) { _, _ in coque.contexteRetire = false }
    }

    @ViewBuilder private var ecran: some View {
        switch ecranCourant {
        // Accueil, création et idées : le même flux (idées → photos → génération → aperçu → finaliser).
        case .aujourdhui, .creation, .idees: VueAccueil()
        case .apercu: VueApercu()
        case .galeries: VueGaleries()
        case .statistiques: VueStatistiques()
        case .reglages: VueReglages()
        case .charte: VueCharte()
        case .regles: VueRegles()
        }
    }
}

// MARK: - Pied de la barre : Claude et le compte

private struct PiedBarre: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j

    private var deconnecte: Bool { etat.claude.map { !$0.pret } ?? false }

    private var libelleClaude: String {
        if etat.claudeTravaille { return etat.execution?.titreAffiche ?? "Claude travaille" }
        guard let c = etat.claude else { return "Claude" }
        if !c.installe { return "Claude n'est pas installé" }
        return c.connecte ? "Claude est prêt" : "Claude n'est plus connecté"
    }

    private var couleurClaude: Color {
        if etat.claudeTravaille { return j.accent }
        if deconnecte { return j.alerte }
        return etat.claude == nil ? j.texteTertiaire : j.succes
    }

    private var initiale: String {
        let nom = etat.reglages?.nom.trimmingCharacters(in: .whitespaces) ?? ""
        return nom.first.map { String($0).uppercased() } ?? "G"
    }

    private var compte: String {
        let nom = etat.reglages?.nom.nonVide
        let ig = etat.reglages?.compte_instagram.nonVide.map { "@\($0)" }
        return [nom, ig].compactMap { $0 }.joined(separator: " · ").nonVide ?? "Mon compte"
    }

    var body: some View {
        let d = j.esp.icone
        VStack(spacing: 12) {
            BulleSurvol(titre: libelleClaude) {
                Button {
                    if deconnecte { coque.feuilleConnexion = true } else { etat.montrer(.reglages) }
                } label: {
                    PointEtat(couleur: couleurClaude, pulse: etat.claudeTravaille, diametre: 10)
                        .frame(width: d, height: d)
                        .background(Circle().fill(Color.white.opacity(j.schema == .dark ? 0.06 : 0.55)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(j.schema == .dark ? 0.06 : 0.5), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(libelleClaude)
            }
            BulleSurvol(titre: compte) {
                Button { etat.montrer(.reglages) } label: {
                    Text(initiale)
                        .font(Font.jakarta(d * 0.38, graisse: 650))
                        .foregroundStyle(j.surEncre)
                        .frame(width: d, height: d)
                        .background(Circle().fill(j.encre))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mon compte, \(compte)")
            }
        }
    }
}

// MARK: - En-tête de la page

/// 64 pt en haut de la page : le studio à gauche, le jour au centre (‹ › et ⌘[ ⌘]), Claude à droite.
private struct EnTetePage: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @Local private var activiteOuverte = false

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(j.accentTexte)
                Text(etat.apparence.nom_affiche.nonVide ?? "Studio Instagram")
                    .typo(.corpsFort)
                    .lineLimit(1)
                Spacer()
                if etat.occupe { ProgressView().controlSize(.small) }
                IndicateurClaude(execution: executionAffichee, statut: etat.claude, action: clicIndicateur)
                    .fixedSize()   // la capsule épouse son texte au lieu de s'étirer à 300 pt
                    .popover(isPresented: $activiteOuverte, arrowEdge: .bottom) { activite }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, j.esp.page * 0.6)
        .onChange(of: activiteOuverte) { _, ouvert in
            if !ouvert, let e = etat.execution, e.terminee { coque.executionVue = e.id }
        }
    }

    /// L'exécution en cours, ou la dernière tant que son résultat n'a pas été vu.
    private var executionAffichee: ExecutionClaude? {
        guard let e = etat.execution, !e.aucune else { return nil }
        if e.enCours { return e }
        return e.id == coque.executionVue ? nil : e
    }

    private func clicIndicateur() {
        if let c = etat.claude, !c.pret, !etat.claudeTravaille {
            coque.feuilleConnexion = true
        } else if executionAffichee != nil {
            activiteOuverte.toggle()
        } else {
            coque.panneauOuvert.toggle()
        }
    }

    @ViewBuilder private var activite: some View {
        if let e = etat.execution {
            ActiviteClaude(execution: e, compacte: false, cadre: false) { ecran in
                activiteOuverte = false
                etat.montrer(ecran, jour: e.tacheClaude?.duJour == true ? e.jour : nil)
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}

/// `CarteActiviteClaude` reliée à l'app : arrêter, ouvrir l'écran suivant, réessayer, se reconnecter.
struct ActiviteClaude: View {
    let execution: ExecutionClaude
    var compacte = false
    var cadre = true
    var ouvrir: ((Ecran) -> Void)? = nil
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio

    var body: some View {
        CarteActiviteClaude(
            execution: execution, compacte: compacte, cadre: cadre,
            arreter: { Task { await etat.annulerClaude() } },
            ouvrir: { e in
                coque.executionVue = execution.id
                if let o = ouvrir { o(e) } else { etat.montrer(e) }
            },
            reessayer: reessayer,
            reconnecter: { coque.feuilleConnexion = true })
    }

    private var reessayer: (() -> Void)? {
        guard let t = execution.tacheClaude else { return nil }
        if t.demandeConsigne && execution.consigne == nil { return nil }
        if t.demandeSerie && execution.serie == nil { return nil }
        return {
            Task {
                await etat.lancerClaude(t, jour: t.duJour ? execution.jour : nil,
                                        serie: execution.serie, consigne: execution.consigne)
            }
        }
    }
}

// MARK: - Jour affiché

enum NavigationJour {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let long: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    /// « Jeudi 19 novembre ».
    static func libelle(_ jour: String, longue: String? = nil) -> String {
        let texte = longue?.nonVide ?? iso.date(from: jour).map { long.string(from: $0) } ?? jour
        return texte.prefix(1).uppercased() + texte.dropFirst()
    }

    static func decaler(_ jour: String, de n: Int) -> String {
        guard let d = iso.date(from: jour),
              let e = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d) else { return jour }
        return iso.string(from: e)
    }

    @MainActor static func changer(_ etat: EtatApp, de n: Int) { aller(etat, a: decaler(etat.jour, de: n)) }

    @MainActor static func aller(_ etat: EtatApp, a jour: String) {
        guard jour != etat.jour else { return }
        etat.jour = jour
        Task { await etat.chargerJour() }
    }
}

// MARK: - Panneau « Demander à Claude » (§4.13)

private struct PanneauClaude: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio

    private var ecranCourant: Ecran { etat.ecran ?? .aujourdhui }

    var body: some View {
        PanneauDemandeClaude(
            messages: coque.messages,
            execution: etat.execution?.tacheClaude == .demande || etat.claudeTravaille ? etat.execution : nil,
            contexte: coque.contexteRetire ? nil : ecranCourant.titre,
            envoyer: { texte in
                coque.demander(texte, etat: etat, contexte: coque.contexteRetire ? nil : ecranCourant.titre)
            },
            nouvelleConversation: { coque.nouvelleConversation(etat) },
            retirerContexte: { coque.contexteRetire = true })
        .onExitCommand { coque.panneauOuvert = false }
        .onAppear {
            if let e = etat.execution, e.terminee, e.tacheClaude == .demande { coque.executionVue = e.id }
        }
    }
}

// MARK: - Bandeau

/// Bandeau de la coque : invitation à (re)connecter Claude (ouvre la feuille « Connexions »), déconnexion,
/// puis erreur, puis message. Pendant l'onboarding, seulement l'erreur et le message.
private struct BandeauCoque: View {
    let onboarding: Bool
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @AppStorage(CleOnboarding.claudeDejaPret) private var claudeDejaPret = false

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                if let m = courant {
                    BandeauMessage(m) { fermer(m) }
                        .id(m.id)
                        .transition(j.transition(.bandeau))
                }
            }
            .animation(j.anim(.bandeau), value: courant)
        }
        .padding(.bottom, basBandeau)
        .padding(.horizontal, 20)
        .allowsHitTesting(courant != nil)
    }

    private var basBandeau: CGFloat { 28 }

    private var courant: MessageBandeau? {
        if !onboarding && !coque.feuilleConnexion {
            if let i = etat.invitationClaude {
                return MessageBandeau(id: "invitation|\(i.texte)", ton: .claude, texte: i.texte, symbole: i.symbole,
                                      actionTitre: i.action == .connecter ? "Me reconnecter" : i.libelleBouton,
                                      action: { coque.feuilleConnexion = true })
            }
            if claudeDejaPret, let c = etat.claude, !c.pret, !coque.deconnexionMasquee, !etat.connexionEnCours {
                return MessageBandeau(id: "deconnexion", ton: .claude,
                                      texte: c.installe ? "Claude n'est plus connecté. Un clic pour revenir."
                                                        : "Claude n'est plus sur ce Mac. Un clic pour le réinstaller.",
                                      symbole: "person.crop.circle.badge.exclamationmark",
                                      actionTitre: c.installe ? "Me reconnecter" : "Installer Claude",
                                      action: { coque.feuilleConnexion = true })
            }
        }
        if let e = etat.erreur { return MessageBandeau(id: "erreur|\(e)", ton: .alerte, texte: e) }
        if let m = etat.message { return MessageBandeau(id: "message|\(m)", ton: .succes, texte: m) }
        return nil
    }

    private func fermer(_ m: MessageBandeau) {
        if m.id.hasPrefix("invitation|") {
            etat.invitationClaude = nil
        } else if m.id == "deconnexion" {
            coque.deconnexionMasquee = true
        } else if m.id.hasPrefix("erreur|") {
            etat.erreur = nil
        } else {
            etat.message = nil
        }
    }
}

// MARK: - Menus et raccourcis

struct CommandesStudio: Commands {
    @ObservedObject var etat: EtatApp
    @ObservedObject var coque: CoqueStudio

    private var inactif: Bool { coque.onboardingVisible }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouveau post") { coque.nouveauPost(etat) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(inactif)
        }
        CommandMenu("Aller") {
            ForEach(Array(BarreStudio.ecrans(etat.apparence).enumerated()), id: \.element) { i, e in
                if i < 9, let c = "\(i + 1)".first {
                    Button(BarreStudio.titre(e)) { etat.montrer(e) }
                        .keyboardShortcut(KeyEquivalent(c), modifiers: .command)
                        .disabled(inactif)
                } else {
                    Button(BarreStudio.titre(e)) { etat.montrer(e) }.disabled(inactif)
                }
            }
            Divider()
            // Hors de la barre, toujours accessibles au clavier et au menu.
            ForEach([Ecran.apercu, .charte, .regles], id: \.self) { e in
                Button(e.titre) { etat.montrer(e) }.disabled(inactif)
            }
            Divider()
            Button("Jour précédent") { NavigationJour.changer(etat, de: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(inactif)
            Button("Jour suivant") { NavigationJour.changer(etat, de: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(inactif)
            Button("Revenir à aujourd'hui") { NavigationJour.aller(etat, a: EtatApp.aujourdhuiISO()) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(inactif)
        }
        CommandMenu("Claude") {
            Button(coque.panneauOuvert ? "Fermer le panneau Claude" : "Demander à Claude…") {
                coque.panneauOuvert.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(inactif)
            Button("Nouvelle conversation") { coque.nouvelleConversation(etat) }
                .disabled(inactif || etat.claudeTravaille)
            Divider()
            Button("Arrêter Claude") { Task { await etat.annulerClaude() } }
                .disabled(!etat.claudeTravaille)
            Button(etat.claudePret ? "Connexion à Claude…" : "Me reconnecter à Claude…") { coque.feuilleConnexion = true }
                .disabled(inactif)
        }
        CommandMenu("Studio") {
            Button("Actualiser") { Task { await etat.toutCharger() } }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Choisir le dossier du studio…") { etat.choisirDossier() }
            Button("Ouvrir le dossier dans le Finder") { NSWorkspace.shared.open(etat.dossier) }
        }
    }
}
