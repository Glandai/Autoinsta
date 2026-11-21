import AppKit
import SwiftUI

// Onboarding plein écran (DESIGN.md §4.2) et feuille de connexion à Claude (Réglages, reconnexion).
//
// Cinq pages, sans carte ni « Passer », points de progression en bas :
//   1. Bonjour !  ·  2. Claude (détecté, ou installé et connecté pas à pas ; obligatoire)
//   3. Instagram (route Facebook ou Instagram seule, guide Meta, identifiants ; « Plus tard » permis)
//   4. Rythme (jours, heures, idées du matin, étapes à valider, planification)  ·  5. Tout est prêt !
//
// Contrat avec la coque (StudioApp.swift) :
//   - La coque affiche `VueBienvenue()` tant que `!etat.studioInstalle || !claudeDejaPret || !onboardingTermine`.
//   - À la fin (« Ouvrir mon studio » ou « Demander mes premières idées »), cette vue met
//     `UserDefaults[CleOnboarding.termine]` à vrai : la coque, qui le lit par `@AppStorage`, passe au studio.
//   - Facultatif : `.environment(\.finBienvenue) { fin in … }` est appelé juste après (`.studio` ou
//     `.premieresIdees` ; dans ce cas Claude a déjà été lancé sur la tâche `matin` et l'écran Aujourd'hui choisi).
//   - Si l'onboarding réapparaît alors qu'il était fini (studio introuvable, Claude jamais vu prêt), il reprend
//     à la page Claude, ou à « Où est ton studio ? ».
//   - `FeuilleConnexionClaude()` : la même page Claude, dans une feuille, avec un « × » (Échap).
//
// Sécurité : le code de connexion de Claude et les identifiants Instagram ne passent que par des `SecureField`,
// sont vidés dès l'envoi (réussi ou non), ne sont jamais affichés, copiés ni journalisés.

// MARK: - Fin de l'onboarding

/// Comment l'onboarding s'est terminé.
enum FinBienvenue: Equatable {
    /// « Ouvrir mon studio ».
    case studio
    /// « Demander mes premières idées » : Claude a été lancé sur les idées du matin.
    case premieresIdees
}

private struct CleFinBienvenue: EnvironmentKey {
    static var defaultValue: ((FinBienvenue) -> Void)? { nil }
}

extension EnvironmentValues {
    /// Appelé à la fin de l'onboarding, après l'enregistrement de `CleOnboarding.termine` (facultatif).
    var finBienvenue: ((FinBienvenue) -> Void)? {
        get { self[CleFinBienvenue.self] }
        set { self[CleFinBienvenue.self] = newValue }
    }
}

// MARK: - Onboarding

struct VueBienvenue: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Environment(\.finBienvenue) private var fin

    @Local private var etape = 0
    @Local private var avance = true
    @Local private var demarre = false

    // Claude
    @Local private var code = ""
    @Local private var claudeAvanceSeul = false

    // Instagram
    @Local private var phaseInsta = PhaseInstagram.choix
    @Local private var choixInsta = ChoixInstagram.facebook
    @Local private var refaireInsta = false
    @Local private var appId = ""
    @Local private var secret = ""
    @Local private var jeton = ""

    // Rythme
    @Local private var rythme = BrouillonRythme()
    @Local private var rythmeLu = false
    @Local private var enregistrement = false
    @Local private var rythmeFait = false
    @Local private var heuresParJour = false

    // Fin
    @Local private var lancement = false

    private let total = 5
    private static let jours = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    var body: some View {
        GeometryReader { geo in
            let compacte = geo.size.height < 820
            ZStack {
                FondAmbiance()
                page(compacte: compacte)
                    .id(cle)
                    .transition(j.transition(avance ? .suivante : .precedente))
            }
            .animation(j.anim(.page), value: cle)
        }
        .onAppear { demarrer() }
        .onChange(of: etat.claudePret) { _, pret in if pret { avancerApresClaude() } }
        .onChange(of: etat.dossier) { _, _ in
            Task { await etat.chargerClaude(silencieux: true) }
        }
        .onChange(of: etat.reglages != nil) { _, _ in lireRythme() }
        .onDisappear { viderSecrets() }
    }

    /// Identité de la page affichée : la changer fait glisser la page (`.suivante` ou `.precedente`).
    private var cle: String {
        if etape >= 1 && !etat.studioInstalle { return "studio" }
        if etape == 2 { return instaRelie ? "2-relie" : "2-\(phaseInsta.rawValue)" }
        return "\(etape)"
    }

    @ViewBuilder private func page(compacte: Bool) -> some View {
        if etape >= 1 && !etat.studioInstalle {
            pageStudio(compacte: compacte)
        } else {
            switch etape {
            case 0: pageBonjour(compacte: compacte)
            case 1: pageClaude(compacte: compacte)
            case 2: pageInstagram(compacte: compacte)
            case 3: pageRythme(compacte: compacte)
            default: pagePret(compacte: compacte)
            }
        }
    }

    // MARK: Navigation

    private func demarrer() {
        guard !demarre else { return }
        demarre = true
        // Déjà fait une fois : l'onboarding revient seulement parce que le studio ou Claude manque.
        if UserDefaults.standard.bool(forKey: CleOnboarding.termine) { etape = 1 }
        if etat.claude == nil { Task { await etat.chargerClaude(silencieux: true) } }
        lireRythme()
    }

    private func aller(_ n: Int) {
        avance = n >= etape
        etat.erreur = nil
        // La direction est posée avant le changement de page, pour que la page qui part la connaisse.
        DispatchQueue.main.async {
            etape = n
            arrivee(n)
        }
    }

    private func allerInsta(_ p: PhaseInstagram) {
        avance = p.rawValue >= phaseInsta.rawValue
        etat.erreur = nil
        DispatchQueue.main.async { phaseInsta = p }
    }

    private func arrivee(_ n: Int) {
        switch n {
        case 1:
            if etat.claudePret { avancerApresClaude() } else { Task { await etat.chargerClaude(silencieux: true) } }
        case 2:
            Task { await etat.chargerInstagram(silencieux: true) }
        case 3:
            Task {
                if etat.reglages == nil { await etat.chargerReglages() }
                await etat.chargerPlanification(silencieux: true)
                lireRythme()
            }
        default:
            break
        }
    }

    /// Claude est (ou vient d'être) prêt : les cercles se cochent, puis Instagram glisse après 1,2 s (une fois).
    private func avancerApresClaude() {
        guard etape == 1, etat.studioInstalle, !claudeAvanceSeul else { return }
        claudeAvanceSeul = true
        code = ""
        AccessibilityNotification.Announcement("C'est bon, Claude est prêt.").post()
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if etape == 1 && etat.claudePret { aller(2) }
        }
    }

    private func viderSecrets() {
        code = ""
        appId = ""
        secret = ""
        jeton = ""
    }

    // MARK: 1. Bonjour

    /// « Bonjour Gabriella ! » : premier mot de `nom` (config/compte.yaml), sinon « Bonjour ! ».
    private var titreBonjour: String {
        let prenom = (etat.reglages?.nom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
        return prenom.isEmpty ? "Bonjour !" : "Bonjour \(prenom) !"
    }

    private func pageBonjour(compacte: Bool) -> some View {
        PageOnboarding(etape: 0, total: total, titre: titreBonjour,
                       texte: "Chaque matin, des idées de post : tu choisis, Claude prépare, tu valides d'un clic.",
                       fond: false) {
            Illustration(.bienvenue, taille: compacte ? 200 : 280)
        } action: {
            Button { aller(1) } label: { Label("Commencer", systemImage: "arrow.right") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Studio introuvable

    private func pageStudio(compacte: Bool) -> some View {
        PageOnboarding(etape: 1, total: total, titre: "Où est ton studio ?",
                       texte: "Je ne trouve pas le dossier du studio sur ce Mac. Montre-le-moi : c'est celui qui a été créé à l'installation.",
                       retour: { aller(0) }, fond: false) {
            Illustration(.erreur, taille: compacte ? 170 : 230)
        } action: {
            Button { etat.choisirDossier() } label: { Label("Choisir le dossier…", systemImage: "folder") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 2. Claude

    private func pageClaude(compacte: Bool) -> some View {
        let phase = PhaseClaude(etat)
        return PageOnboarding(etape: 1, total: total, titre: phase.titre, texte: phase.texte(etat),
                              retour: { aller(0) }, fond: false) {
            Illustration(phase == .attente ? .attente : .claude, taille: compacte ? 150 : 210)
        } contenu: {
            // Les erreurs passent par le bandeau de la coque pendant l'onboarding.
            ZoneClaude(phase: phase, code: $code, erreursEnLigne: false)
        } action: {
            ActionClaude(phase: phase, code: $code, libelleContinuer: "Continuer", continuer: { aller(2) })
        }
    }

    // MARK: 3. Instagram

    private var instaRelie: Bool { etat.instagram?.connecte == true && !refaireInsta }

    @ViewBuilder private func pageInstagram(compacte: Bool) -> some View {
        if instaRelie {
            pageInstaRelie(compacte: compacte)
        } else {
            switch phaseInsta {
            case .choix: pageInstaChoix(compacte: compacte)
            case .guide: pageInstaGuide(compacte: compacte)
            case .identifiants: pageInstaIdentifiants(compacte: compacte)
            }
        }
    }

    private func pageInstaRelie(compacte: Bool) -> some View {
        PageOnboarding(etape: 2, total: total, titre: "Instagram est relié.",
                       texte: (etat.instagram?.libelle ?? "Connecté") + ". Le studio publiera seulement ce que tu as validé.",
                       retour: { aller(1) }, fond: false) {
            Illustration(.instagram, taille: compacte ? 170 : 230)
        } contenu: {
            Button("Relier un autre compte") {
                avance = true
                refaireInsta = true
                phaseInsta = .choix
            }
            .buttonStyle(.discret)
        } action: {
            Button { aller(3) } label: { Label("Continuer", systemImage: "arrow.right") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func pageInstaChoix(compacte: Bool) -> some View {
        let arefaire = etat.instagram.map { !$0.connecte && !$0.absent && !$0.etat.isEmpty } ?? false
        return PageOnboarding(etape: 2, total: total, titre: "Et ton compte Instagram.",
                              texte: arefaire
                                ? "La connexion précédente ne marche plus. Relie de nouveau ton compte pour que le studio publie à ta place."
                                : "Relie ton compte pour que le studio publie à ta place, seulement ce que tu as validé.",
                              retour: { aller(1) }, fond: false) {
            Illustration(.instagram, taille: compacte ? 80 : 120)
        } contenu: {
            VStack(spacing: 8) {
                TuileChoix(titre: "Avec Facebook", badge: "Recommandé",
                           detail: "Compte pro relié à ta page, musique d'Instagram comprise.",
                           symbole: "link", choisie: choixInsta == .facebook) { choixInsta = .facebook }
                TuileChoix(titre: "Avec Instagram seulement",
                           detail: "Un seul code à copier, sans la musique.",
                           symbole: "camera", choisie: choixInsta == .instagram) { choixInsta = .instagram }
                // Une vraie réponse (préparer sans publier), pas un « Passer » : elle reste une tuile parmi les autres.
                TuileChoix(titre: "Préparer sans publier",
                           detail: "Je relierai Instagram plus tard, dans les Réglages.",
                           symbole: "tray.full", choisie: choixInsta == .plusTard) { choixInsta = .plusTard }
                Text(choixInsta == .plusTard
                     ? "Claude prépare tes posts ; tu les publies toi-même en attendant."
                     : "20 à 30 minutes la première fois, guidée pas à pas.")
                    .typo(.legende)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        } action: {
            Button {
                if choixInsta == .plusTard { aller(3) } else { allerInsta(.guide) }
            } label: {
                Label(choixInsta == .plusTard ? "Préparer sans publier" : "Continuer", systemImage: "arrow.right")
            }
            .buttonStyle(.principal)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func pageInstaGuide(compacte: Bool) -> some View {
        PageOnboarding(etape: 2, total: total, titre: "Crée ton app chez Meta.",
                       texte: "Ouvre le site de Meta à côté de cette fenêtre. Je t'attends ici.",
                       retour: { allerInsta(.choix) }, fond: false) {
            Illustration(.instagram, taille: compacte ? 60 : 90)
        } contenu: {
            GuideMeta(route: choixInsta)
        } action: {
            Button { allerInsta(.identifiants) } label: { Label("J'ai mes codes", systemImage: "arrow.right") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var identifiantsComplets: Bool {
        let t = jeton.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if choixInsta == .instagram { return true }
        return !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pageInstaIdentifiants(compacte: Bool) -> some View {
        PageOnboarding(etape: 2, total: total, titre: "Colle tes codes.",
                       texte: "Ils restent sur ce Mac, dans ton studio. Ils ne s'affichent jamais, même ici.",
                       retour: { allerInsta(.guide) }, fond: false) {
            Illustration(.instagram, taille: compacte ? 70 : 110)
        } contenu: {
            VStack(alignment: .leading, spacing: j.esp.blocs) {
                if choixInsta == .facebook {
                    HStack(alignment: .top, spacing: 12) {
                        ChampEtiquete(titre: "Identifiant de l'app", aide: "Paramètres › Général.",
                                      texte: $appId, envoyer: nil)
                        ChampEtiquete(titre: "Clé secrète", aide: "Bouton « Afficher ».",
                                      texte: $secret, envoyer: nil)
                    }
                }
                ChampEtiquete(titre: "Jeton d'accès",
                              aide: choixInsta == .facebook ? "Celui de l'Explorateur de l'API Graph."
                                                            : "Celui de « Générer le jeton », dans le produit Instagram.",
                              texte: $jeton, envoyer: { if identifiantsComplets { relierInstagram() } })
            }
        } action: {
            Button { relierInstagram() } label: { Label("Relier mon compte", systemImage: "link") }
                .buttonStyle(BoutonPrincipal(enCours: etat.connexionInstagramEnCours))
                .keyboardShortcut(.defaultAction)
                .disabled(!identifiantsComplets || etat.connexionInstagramEnCours)
        }
    }

    /// Envoie les codes (fichier privé, effacé par le moteur), puis vide les champs, que ça marche ou non.
    private func relierInstagram() {
        guard identifiantsComplets, !etat.connexionInstagramEnCours else { return }
        let route = choixInsta == .instagram ? "instagram" : "facebook"
        let a = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = jeton.trimmingCharacters(in: .whitespacesAndNewlines)
        appId = ""
        secret = ""
        jeton = ""
        etat.erreur = nil
        Task {
            let ok = await etat.connecterInstagram(route: route, appId: route == "facebook" ? a : "",
                                                   secret: route == "facebook" ? s : "", jeton: t)
            guard ok else { return }
            avance = true
            refaireInsta = false
            AccessibilityNotification.Announcement("Instagram est relié.").post()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if etape == 2 && etat.instagram?.connecte == true { aller(3) }
        }
    }

    // MARK: 4. Rythme

    private func lireRythme() {
        guard !rythmeLu, let r = etat.reglages else { return }
        var creneaux: [String: String] = [:]
        for jour in Self.jours { creneaux[jour] = r.publication.creneaux[jour] ?? "" }
        rythme = BrouillonRythme(creneaux: creneaux,
                                 heureIdees: r.routine.heure_idees.isEmpty ? "08:00" : r.routine.heure_idees,
                                 valider: Set(r.creation?.etapes_a_valider ?? ReglagesCreation.etapes),
                                 planifier: true)
        rythmeLu = true
    }

    private var joursChoisis: [String] { Self.jours.filter { !(rythme.creneaux[$0] ?? "").isEmpty } }

    private var heuresDifferentes: Bool { Set(joursChoisis.map { rythme.creneaux[$0] ?? "" }).count > 1 }

    private var heureCommune: Binding<String> {
        Binding(get: { joursChoisis.first.flatMap { rythme.creneaux[$0] } ?? "18:30" },
                set: { h in for jour in joursChoisis { rythme.creneaux[jour] = h } })
    }

    private func basculer(_ jour: String) {
        if (rythme.creneaux[jour] ?? "").isEmpty {
            rythme.creneaux[jour] = heureCommune.wrappedValue
        } else {
            rythme.creneaux[jour] = ""
        }
    }

    private func pageRythme(compacte: Bool) -> some View {
        PageOnboarding(etape: 3, total: total, titre: "Ton rythme.",
                       texte: "Claude prépare les idées le matin, tu décides, le studio publie.",
                       retour: { aller(2) }, fond: false) {
            // Page la plus dense de l'onboarding : petite illustration, pour que « Activer » reste visible à 860 pt.
            Illustration(.rythme, taille: compacte ? 60 : 84)
        } contenu: {
            if !rythmeLu {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Je lis tes réglages…").typo(.corps)
                }
                // Réglages déjà chargés (retour à l'onboarding, étape atteinte sans `aller`) : lus tout de suite ;
                // sinon, chargés ici.
                .onAppear {
                    lireRythme()
                    if !rythmeLu { arrivee(3) }
                }
            } else if rythmeFait {
                tachesActivees
            } else {
                formulaireRythme
            }
        } action: {
            if rythmeLu && !rythmeFait {
                VStack(spacing: 8) {
                    Button { enregistrerRythme() } label: {
                        Label(rythme.planifier ? "Activer" : "Continuer",
                              systemImage: rythme.planifier ? "clock.badge.checkmark" : "arrow.right")
                    }
                    .buttonStyle(BoutonPrincipal(enCours: enregistrement))
                    .keyboardShortcut(.defaultAction)
                    .disabled(joursChoisis.isEmpty || enregistrement)
                    if joursChoisis.isEmpty {
                        Text("Choisis au moins un jour de publication.").typo(.legende)
                    }
                }
            } else if !rythmeLu && etat.reglages == nil && etat.erreur != nil {
                Button {
                    etat.erreur = nil
                    arrivee(3)
                } label: { Label("Réessayer", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var formulaireRythme: some View {
        VStack(alignment: .leading, spacing: j.esp.pile + 2) {
            ligne("Jours", symbole: "calendar") {
                HStack(spacing: 5) {
                    ForEach(Self.jours, id: \.self) { jour in
                        BoutonJour(jour: jour, heure: rythme.creneaux[jour] ?? "") { basculer(jour) }
                    }
                }
            }
            ligne("Publication", symbole: "paperplane") {
                HStack(spacing: 8) {
                    if joursChoisis.isEmpty {
                        Text("—").typo(.corps, couleur: j.texteSecondaire)
                    } else if heuresDifferentes {
                        Text("Selon le jour").typo(.corps)
                    } else {
                        ChampHeure(heure: heureCommune)
                            .accessibilityLabel("Heure de publication")
                    }
                    Button { heuresParJour = true } label: { Text("Jour par jour") }
                        .buttonStyle(.pilule(.claire, taille: .petite))
                        .disabled(joursChoisis.isEmpty)
                        .help("Une heure différente selon le jour")
                        .popover(isPresented: $heuresParJour, arrowEdge: .bottom) { heuresDesJours }
                }
            }
            ligne("Idées du matin", symbole: "sunrise") {
                ChampHeure(heure: $rythme.heureIdees)
                    .accessibilityLabel("Heure des idées du matin")
            }
            // Pilules sans icône : la rangée tient dans la colonne de 440 pt.
            ligne("Tu valides", symbole: "hand.raised") {
                HStack(spacing: 5) {
                    ForEach(ReglagesCreation.etapes, id: \.self) { e in
                        let choisie = rythme.valider.contains(e)
                        Button {
                            if choisie { rythme.valider.remove(e) } else { rythme.valider.insert(e) }
                        } label: { Text(ReglagesCreation.libelle(e)) }
                        .buttonStyle(.pilule(choisie ? .sombre : .claire, taille: .petite))
                        .help(choisie ? "\(ReglagesCreation.libelle(e)) : à toi de valider"
                                      : "\(ReglagesCreation.libelle(e)) : Claude s'en occupe")
                        .accessibilityValue(choisie ? "tu valides" : "Claude s'en occupe")
                        .accessibilityAddTraits(choisie ? .isSelected : [])
                    }
                }
            }
            Text("L'aperçu final, tu le valides toujours ; le reste, Claude le fait seul.")
                .typo(.legende)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Toggle(isOn: $rythme.planifier) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Le studio travaille même app fermée").typo(.corpsFort)
                    Text("Mac allumé (en veille, la tâche part au réveil). Rien n'est publié sans ta validation.")
                        .typo(.legende)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 4)
        }
    }

    private var heuresDesJours: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heure de publication").typo(.corpsFort)
            ForEach(joursChoisis, id: \.self) { jour in
                HStack {
                    Text(jour.capitalized).typo(.corps)
                    Spacer()
                    ChampHeure(heure: Binding(get: { rythme.creneaux[jour] ?? "18:30" },
                                              set: { rythme.creneaux[jour] = $0 }))
                        .accessibilityLabel("Heure du \(jour)")
                }
            }
        }
        .padding(16)
        .frame(width: 250)
    }

    private func ligne<C: View>(_ titre: String, symbole: String, @ViewBuilder _ controle: () -> C) -> some View {
        HStack(spacing: 12) {
            Label(titre, systemImage: symbole)
                .typo(.corpsFort)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            controle()
        }
        .frame(minHeight: 32)
    }

    private var tachesActivees: some View {
        let taches = etat.planification?.taches ?? []
        return Group {
            if taches.isEmpty {
                Label("C'est enregistré.", systemImage: "checkmark.circle.fill").typo(.corpsFort)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(Array(taches.enumerated()), id: \.element.id) { i, t in
                        VStack(spacing: 4) {
                            CercleEtape(symbole: t.symbole, titre: t.titreAffiche, etat: .fait, diametre: 56)
                            if let q = t.quand {
                                Text(q).typo(.legende).multilineTextAlignment(.center).frame(maxWidth: 130)
                            }
                        }
                        .entreeEnCascade(i, pas: 0.18)
                    }
                }
            }
        }
    }

    private func enregistrerRythme() {
        guard var r = etat.reglages, !joursChoisis.isEmpty, !enregistrement else { return }
        enregistrement = true
        etat.erreur = nil
        for jour in Self.jours { r.publication.creneaux[jour] = rythme.creneaux[jour] ?? "" }
        r.routine.heure_idees = rythme.heureIdees
        r.creation = ReglagesCreation(etapes_a_valider: ReglagesCreation.etapes.filter { rythme.valider.contains($0) })
        let aEnvoyer = r
        let planifier = rythme.planifier
        Task {
            guard await etat.envoyer(aEnvoyer, action: "enregistrer-reglages") else {
                enregistrement = false
                return
            }
            await etat.chargerReglages()
            let actif = etat.planification?.active ?? etat.reglages?.planification?.active ?? false
            if planifier || actif {
                guard await etat.planifier(activer: planifier) else {
                    enregistrement = false
                    return
                }
            }
            enregistrement = false
            if planifier {
                withAnimation(j.anim(.doux)) { rythmeFait = true }
                AccessibilityNotification.Announcement("Tâches automatiques activées.").post()
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
            if etape == 3 { aller(4) }
        }
    }

    // MARK: 5. Prêt

    private var textePret: String {
        let planifie = etat.planification?.active ?? etat.reglages?.planification?.active ?? false
        var t = planifie ? "Demain matin, tes premières idées t'attendront ici."
                         : "Quand tu veux des idées, demande-les à Claude depuis l'accueil."
        if etat.instagram?.connecte != true {
            t += " Pour publier, relie Instagram quand tu veux, dans les Réglages."
        }
        return t
    }

    private func pagePret(compacte: Bool) -> some View {
        PageOnboarding(etape: 4, total: total, titre: "Tout est prêt !", texte: textePret,
                       retour: { aller(3) }, fond: false) {
            Illustration(.pret, taille: compacte ? 200 : 280)
        } action: {
            VStack(spacing: 10) {
                Button { terminer(.studio) } label: { Label("Ouvrir mon studio", systemImage: "arrow.right") }
                    .buttonStyle(.principal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(lancement)
                Button { terminer(.premieresIdees) } label: {
                    if lancement {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Un instant…") }
                    } else {
                        Text("Demander mes premières idées maintenant")
                    }
                }
                .buttonStyle(BoutonDiscret(fleche: true))
                .disabled(lancement || etat.claudeTravaille || etat.lancementEnCours)
            }
        }
    }

    private func terminer(_ f: FinBienvenue) {
        viderSecrets()
        guard f == .premieresIdees else {
            finir(f)
            return
        }
        lancement = true
        Task {
            await etat.lancerClaude(.matin)
            lancement = false
            etat.montrer(.aujourdhui)
            finir(f)
        }
    }

    private func finir(_ f: FinBienvenue) {
        UserDefaults.standard.set(true, forKey: CleOnboarding.termine)
        fin?(f)
    }
}

// MARK: - Feuille de connexion à Claude (Réglages, reconnexion)

/// La page Claude de l'onboarding dans une feuille : installer, se connecter, coller le code, avec un « × » (Échap).
/// La coque la ferme d'elle-même dès que Claude est prêt.
struct FeuilleConnexionClaude: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.dismiss) private var fermer
    @Environment(\.jetons) private var j
    @Local private var code = ""

    var body: some View {
        let phase = PhaseClaude(etat)
        // « × » en haut à droite, à 24 pt : loin de tout coin réservé par le système.
        ZStack(alignment: .topTrailing) {
            FondAmbiance()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                Illustration(phase == .attente ? .attente : .claude, taille: 190)
                    .padding(.bottom, j.esp.sections)
                Text(phase.titre)
                    .typo(.affiche)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(phase.texte(etat))
                    .typo(.chapo)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, j.esp.blocs)
                // Pas de bandeau de la coque au-dessus d'une feuille : les erreurs s'affichent ici.
                ZoneClaude(phase: phase, code: $code, erreursEnLigne: true)
                    .frame(maxWidth: 440)
                    .padding(.top, j.esp.sections * 0.75)
                ActionClaude(phase: phase, code: $code, libelleContinuer: "Revenir au studio", continuer: { fermer() })
                    .padding(.top, j.esp.sections * 0.75)
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, j.esp.page)
            .animation(j.anim(.doux), value: phase)

            Button {
                code = ""
                fermer()
            } label: { Image(systemName: "xmark") }
            .buttonStyle(BoutonRond(.claire, diametre: 36))
            .keyboardShortcut(.cancelAction)
            .help("Fermer")
            .accessibilityLabel("Fermer")
            .padding(24)
        }
        .onAppear { Task { await etat.chargerClaude(silencieux: true) } }
        .onDisappear { code = "" }
    }
}

// MARK: - Claude : phases, cercles, contenu, action (partagés)

private enum PhaseClaude: Equatable {
    case verification, installation, connexion, attente, pret

    @MainActor init(_ etat: EtatApp) {
        guard let s = etat.claude else {
            self = .verification
            return
        }
        if s.pret {
            self = .pret
        } else if etat.installationEnCours || !s.installe {
            self = .installation
        } else if etat.connexionEnCours {
            self = .attente
        } else {
            self = .connexion
        }
    }

    var titre: String { self == .pret ? "Claude est prêt." : "Connectons Claude." }

    @MainActor func texte(_ etat: EtatApp) -> String {
        switch self {
        case .verification:
            return "Je regarde si Claude est déjà sur ce Mac…"
        case .installation:
            return etat.installationEnCours
                ? "J'installe Claude, environ une minute. Tu n'as rien à faire."
                : "Claude n'est pas encore sur ce Mac. Un clic, environ une minute."
        case .connexion:
            return "Ton navigateur va s'ouvrir sur la page de Claude. Ton mot de passe se tape là-bas, jamais ici."
        case .attente:
            return etat.codeConnexionAttendu
                ? "Connecte-toi dans ton navigateur. La page t'affiche ensuite un code : colle-le ici."
                : "Termine la connexion dans ton navigateur, je t'attends ici."
        case .pret:
            return "C'est bon : il préparera tes idées et tes posts."
        }
    }
}

/// Transmet le code collé (jamais enregistré) et vide le champ tout de suite.
@MainActor private func envoyerCodeClaude(_ code: Binding<String>, etat: EtatApp) {
    guard !etat.envoiCodeEnCours else { return }
    let c = code.wrappedValue
    code.wrappedValue = ""
    guard !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    etat.erreur = nil
    Task { await etat.envoyerCodeConnexion(c) }
}

/// Installer, Se connecter, Vérifier : trois cercles qui se cochent en cascade quand Claude est prêt.
private struct CerclesClaude: View {
    let phase: PhaseClaude
    @EnvironmentObject var etat: EtatApp
    @Local private var faits = 0

    var body: some View {
        let e = etats
        HStack(alignment: .top, spacing: 30) {
            CercleEtape(symbole: "arrow.down.circle", titre: "Installer", etat: e.0, diametre: 58)
            CercleEtape(symbole: "person.crop.circle.badge.checkmark", titre: "Se connecter", etat: e.1, diametre: 58)
            CercleEtape(symbole: "checkmark.seal", titre: "Vérifier", etat: e.2, diametre: 58)
        }
        .onAppear { if phase == .pret { cascade() } }
        .onChange(of: phase) { _, p in if p == .pret { cascade() } }
    }

    private var etats: (EtatCercle, EtatCercle, EtatCercle) {
        switch phase {
        case .verification: return (.enAttente, .aVenir, .aVenir)
        case .installation: return (etat.installationEnCours ? .enAttente : .actuel, .aVenir, .aVenir)
        case .connexion: return (.fait, .actuel, .aVenir)
        case .attente: return (.fait, .enAttente, etat.envoiCodeEnCours ? .enAttente : .aVenir)
        case .pret: return (faits > 0 ? .fait : .actuel, faits > 1 ? .fait : .aVenir, faits > 2 ? .fait : .aVenir)
        }
    }

    private func cascade() {
        faits = 0
        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(i)) { faits = i }
        }
    }
}

/// Les cercles, le champ du code (si la page en affiche un) et, dans la feuille, l'erreur.
private struct ZoneClaude: View {
    let phase: PhaseClaude
    @Binding var code: String
    let erreursEnLigne: Bool
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(spacing: j.esp.blocs + 4) {
            CerclesClaude(phase: phase)
            if phase == .attente && etat.codeConnexionAttendu {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le code de la page de connexion").typo(.corpsFort)
                    ChampSecret(exemple: "Colle le code ici", texte: $code) { envoyerCodeClaude($code, etat: etat) }
                        .disabled(etat.envoiCodeEnCours)
                    Text("Il ne s'affiche pas en clair : c'est normal, il reste secret.").typo(.legende)
                }
                .transition(j.transition(.apparition))
            }
            if erreursEnLigne, let e = etat.erreur {
                LigneErreur(texte: e) { etat.erreur = nil }
            }
        }
        .animation(j.anim(.doux), value: etat.codeConnexionAttendu)
    }
}

/// L'action principale de la phase (⏎) et les liens discrets (console, page de secours, annuler).
private struct ActionClaude: View {
    let phase: PhaseClaude
    @Binding var code: String
    let libelleContinuer: String
    let continuer: () -> Void
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(spacing: 8) {
            principal
            secondaires
        }
    }

    @ViewBuilder private var principal: some View {
        switch phase {
        case .verification:
            if etat.erreur != nil {
                Button {
                    etat.erreur = nil
                    Task { await etat.chargerClaude() }
                } label: { Label("Réessayer", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
            } else {
                attente("Un instant…")
            }
        case .installation:
            Button {
                etat.erreur = nil
                Task { await etat.installerClaude() }
            } label: { Label("Installer Claude", systemImage: "arrow.down.circle") }
            .buttonStyle(BoutonPrincipal(enCours: etat.installationEnCours))
            .keyboardShortcut(.defaultAction)
            .disabled(etat.installationEnCours)
        case .connexion:
            Button {
                etat.erreur = nil
                Task { await etat.connecterClaude() }
            } label: { Label("Se connecter dans le navigateur", systemImage: "globe") }
            .buttonStyle(.principal)
            .keyboardShortcut(.defaultAction)
        case .attente:
            if etat.codeConnexionAttendu {
                Button { envoyerCodeClaude($code, etat: etat) } label: { Label("Valider le code", systemImage: "checkmark") }
                    .buttonStyle(BoutonPrincipal(enCours: etat.envoiCodeEnCours))
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || etat.envoiCodeEnCours)
            } else {
                attente("Je t'attends…")
            }
        case .pret:
            Button(action: continuer) { Label(libelleContinuer, systemImage: "arrow.right") }
                .buttonStyle(.principal)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var secondaires: some View {
        switch phase {
        case .connexion:
            Button("J'utilise un compte de la Console Anthropic") {
                etat.erreur = nil
                Task { await etat.connecterClaude(console: true) }
            }
            .buttonStyle(.discret)
        case .attente:
            HStack(spacing: 6) {
                if etat.lienConnexion != nil {
                    Button("Le navigateur ne s'est pas ouvert ?") { etat.ouvrirLienConnexion() }
                        .buttonStyle(.discret)
                        .help("Rouvrir la page de connexion")
                }
                Button("Annuler") {
                    code = ""
                    etat.arreterConnexion()
                }
                .buttonStyle(.discret)
            }
        default:
            EmptyView()
        }
    }

    private func attente(_ texte: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(texte).typo(.corpsFort)
        }
        .frame(minHeight: j.esp.hauteurBouton + 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Instagram : choix, guide

private enum PhaseInstagram: Int { case choix, guide, identifiants }

private enum ChoixInstagram { case facebook, instagram, plusTard }

/// Une réponse possible, sur une tuile douce (pas une boîte de page) : symbole, titre, détail, coche.
private struct TuileChoix: View {
    let titre: String
    var badge: String? = nil
    let detail: String
    let symbole: String
    let choisie: Bool
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbole)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(choisie ? j.surEncre : j.texte)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(choisie ? j.encre : j.fondDoux))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(titre).typo(.corpsFort)
                        if let b = badge { Pastille(b, ton: .douce) }
                    }
                    Text(detail)
                        .typo(.legende)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: choisie ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(choisie ? j.encre : j.traitFort)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(forme.fill(survol && !choisie ? j.surfaceElevee : j.remplissageCarte))
            .overlay(forme.strokeBorder(choisie ? j.encre.opacity(0.8) : j.trait, lineWidth: choisie ? 1.5 : 1))
            .contentShape(forme)
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(j.anim(.selection), value: choisie)
        .animation(j.anim(.survol), value: survol)
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

/// Le guide pas à pas sur le site de Meta, selon la route choisie, avec les liens utiles.
private struct GuideMeta: View {
    let route: ChoixInstagram
    @Environment(\.jetons) private var j

    private static let siteApps = URL(string: "https://developers.facebook.com/apps/")!
    private static let explorateur = URL(string: "https://developers.facebook.com/tools/explorer/")!

    private var etapes: [String] {
        if route == .instagram {
            return [
                "Compte Instagram professionnel (Créateur ou Entreprise).",
                "« Créer une app », type « Entreprise », nom « Mon studio ».",
                "Ajoute le produit « Instagram » (API avec connexion Instagram).",
                "« Générer des jetons d'accès » : ajoute ton compte, puis copie le jeton.",
            ]
        }
        return [
            "Compte Instagram professionnel, relié à ta page Facebook.",
            "« Créer une app », type « Entreprise », nom « Mon studio ».",
            "Paramètres › Général : identifiant de l'app et clé secrète.",
            "Explorateur : coche instagram_basic, instagram_content_publish, pages_show_list, pages_read_engagement, puis « Generate Access Token ».",
            "Copie le jeton : le studio le prolonge tout seul à 60 jours.",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(etapes.enumerated()), id: \.offset) { i, texte in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.jakarta(11, graisse: 700))
                        .foregroundStyle(j.surEncre)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(j.encre))
                        .accessibilityHidden(true)
                    Text(texte)
                        .typo(.corps)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Étape \(i + 1) : \(texte)")
            }
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(Self.siteApps) } label: {
                    Label("Ouvrir le site de Meta", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.pilule(.claire, taille: .petite))
                if route == .facebook {
                    Button { NSWorkspace.shared.open(Self.explorateur) } label: {
                        Label("Ouvrir l'Explorateur", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Rythme

private struct BrouillonRythme: Equatable {
    var creneaux: [String: String] = [:]
    var heureIdees = "08:00"
    var valider: Set<String> = Set(ReglagesCreation.etapes)
    var planifier = true
}

/// Un jour de la semaine en pastille ronde : encre = on publie ce jour-là.
private struct BoutonJour: View {
    let jour: String
    let heure: String
    let action: () -> Void
    @Environment(\.jetons) private var j

    var body: some View {
        let choisi = !heure.isEmpty
        Button(action: action) {
            Text(String(jour.prefix(1)).uppercased())
                .font(.jakarta(13, graisse: 600))
                .foregroundStyle(choisi ? j.surEncre : j.texte)
                .frame(width: 32, height: 32)
                .background(Circle().fill(choisi ? j.encre : j.remplissageCarte))
                .overlay(Circle().strokeBorder(choisi ? Color.clear : j.traitFort, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(j.anim(.selection), value: choisi)
        .help(jour.capitalized)
        .accessibilityLabel(jour.capitalized)
        .accessibilityValue(choisi ? "publication à \(heure)" : "pas de publication")
        .accessibilityAddTraits(choisi ? .isSelected : [])
    }
}

// MARK: - Champs secrets, erreurs

/// Champ sécurisé au style de `ChampDoux` (capsule blanche, focus d'encre) : rien ne s'affiche en clair.
private struct ChampSecret: View {
    let exemple: String
    @Binding var texte: String
    var envoyer: (() -> Void)? = nil
    @Environment(\.jetons) private var j
    @FocusState private var focus: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
                .foregroundStyle(j.texteSecondaire)
                .accessibilityHidden(true)
            SecureField(exemple, text: $texte)
                .focused($focus)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focusEffectDisabled()
                .onSubmit { envoyer?() }
                .typo(.champ)
                .accessibilityLabel(exemple)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(forme.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
        .overlay(forme.strokeBorder(focus ? j.encre.opacity(0.75) : j.traitFort.opacity(0.8), lineWidth: focus ? 1.5 : 1))
        .background(forme.stroke(j.accent.opacity(focus ? 0.16 : 0), lineWidth: 8))
        .animation(j.anim(.survol), value: focus)
    }
}

/// Un champ secret avec son nom et une aide d'une ligne.
private struct ChampEtiquete: View {
    let titre: String
    let aide: String
    @Binding var texte: String
    let envoyer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(titre).typo(.corpsFort)
            ChampSecret(exemple: titre, texte: $texte, envoyer: envoyer)
            Text(aide).typo(.legende)
        }
    }
}

/// Erreur claire, dans la feuille (l'onboarding passe par le bandeau de la coque).
private struct LigneErreur: View {
    let texte: String
    let fermer: () -> Void
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(j.alerte)
                .accessibilityHidden(true)
            Text(texte)
                .typo(.corps)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: fermer) { Image(systemName: "xmark").imageScale(.small) }
                .buttonStyle(.plain)
                .foregroundStyle(j.texteSecondaire)
                .help("Fermer")
                .accessibilityLabel("Fermer le message")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous).fill(j.fondAlerte))
        .onAppear { AccessibilityNotification.Announcement(texte).post() }
    }
}
