import SwiftUI

// Aujourd'hui (DESIGN.md §4.4), comme l'accueil de l'inspiration : grand titre léger en deux tons, une
// illustration qui parle, trois cartes douces pour ce qui compte aujourd'hui, l'action principale (ou Claude
// au travail), le feed récent, et en bas la barre « Demande à Claude » avec ses raccourcis en pilules.

struct VueAujourdhui: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @Local private var demande = ""
    /// Gardé ici : `ViewThatFits` peut changer de mise en page quand « À régler » se déplie.
    @Local private var aReglerOuvert = false

    var body: some View {
        // La barre Claude a sa propre place sous la zone qui défile : elle ne recouvre jamais rien.
        VStack(spacing: 0) {
            GeometryReader { geo in
                // Fenêtre par défaut (860 pt) : environ 560 pt ici → mise en page compacte.
                // On essaie le grand titre, puis le Titre 1, et on ne défile qu'en dernier recours ;
                // en compact, la place qui reste se répartit entre les blocs (pas de vide sous le feed).
                let compacte = geo.size.height < 720
                ViewThatFits(in: .vertical) {
                    contenu(compacte: compacte, grandTitre: true, etire: compacte)
                        .frame(maxHeight: .infinity, alignment: .top)
                    contenu(compacte: compacte, grandTitre: false, etire: compacte)
                        .frame(maxHeight: .infinity, alignment: .top)
                    ScrollView {
                        contenu(compacte: compacte, grandTitre: false, etire: false)
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .mask(fonduBas)
            }
            barreClaude
        }
        .task {
            if etat.reglages == nil { await etat.chargerReglages() }
            if etat.planification == nil { await etat.chargerPlanification(silencieux: true) }
            if etat.sante == nil { await etat.chargerSante() }
        }
    }

    /// `grandTitre` : titre à l'affiche (54 pt) même en compact, s'il tient. `etire` : la place libre se répartit
    /// entre les blocs (le parent leur donne toute la hauteur).
    private func contenu(compacte: Bool, grandTitre: Bool, etire: Bool) -> some View {
        let ecart = compacte ? j.esp.blocs + 2 : j.esp.sections * 0.7
        return VStack(alignment: .leading, spacing: etire ? 0 : ecart) {
            EnTeteJour(moment: moment, compacte: compacte && !grandTitre)
                .entreeEnCascade(0)
            if !aRegler.isEmpty {
                if etire { Spacer(minLength: ecart) }
                CarteARegler(points: aRegler, ouvert: $aReglerOuvert)
                    .entreeEnCascade(1)
            }
            if etire { Spacer(minLength: ecart) }
            CartesDuJour(moment: moment, compacte: compacte)
                .entreeEnCascade(2)
            if etire { Spacer(minLength: ecart) }
            // L'action principale (ou Claude au travail) et le feed récent sur la même ligne.
            HStack(alignment: .center, spacing: j.esp.sections) {
                ActionDuJour(moment: moment, compacte: compacte)
                Spacer(minLength: 0)
                FeedRecent(compacte: compacte)
            }
            .entreeEnCascade(3)
        }
        .frame(maxWidth: 1000, alignment: .leading)
        .padding(.horizontal, j.esp.page)
        .padding(.top, compacte ? 4 : j.esp.blocs)
        .padding(.bottom, j.esp.blocs)
        .frame(maxWidth: .infinity)
        .animation(j.anim(.doux), value: moment)
    }

    /// Le contenu s'efface doucement juste au-dessus de la barre Claude, au lieu d'être coupé net.
    private var fonduBas: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
        }
    }

    private var moment: MomentDuJour { MomentDuJour(statut: etat.vue?.statut) }

    // MARK: À régler

    /// Ce qui empêche le studio de tourner (Claude a son propre bandeau).
    private var aRegler: [String] {
        guard let s = etat.sante else { return [] }
        var points = (s.a_completer ?? []).map { "À compléter dans les réglages : \($0)" }
        if s.instagram_connecte == false { points.append("Instagram n'est pas encore relié : le studio ne peut pas publier.") }
        if s.hebergement_pret == false { points.append("L'outil qui envoie les images à Instagram manque : relance l'installation.") }
        return points
    }

    // MARK: Barre « Demande à Claude »

    private var barreClaude: some View {
        BarreDemandeClaude(texte: $demande, raccourcis: raccourcis, etat: etatClaude,
                           occupe: etat.claudeTravaille,
                           plus: { coque.panneauOuvert = true },
                           envoyer: envoyer)
            .frame(maxWidth: 860)
            .padding(.horizontal, j.esp.page)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
    }

    private var etatClaude: String {
        if etat.claudeTravaille { return "Claude travaille…" }
        guard let c = etat.claude else { return "Claude arrive…" }
        return c.pret ? "Claude est prêt" : "Claude n'est pas connecté"
    }

    private var sombre: Bool { j.schema == .dark }

    private var raccourcis: [RaccourciClaude] {
        [
            RaccourciClaude("Propose des idées", symbole: "lightbulb", demande: DemandeRapide.idees),
            RaccourciClaude("Change la légende", symbole: "text.quote", demande: DemandeRapide.legende),
            RaccourciClaude("Choisis les photos", symbole: "photo.on.rectangle", demande: DemandeRapide.photos),
            sombre
                ? RaccourciClaude("Mode clair", symbole: "sun.max", demande: DemandeRapide.modeClair)
                : RaccourciClaude("Mode sombre", symbole: "moon", demande: DemandeRapide.modeSombre),
        ]
    }

    /// Un raccourci lance la bonne tâche quand il y en a une (idées du matin, retouche, apparence) ;
    /// tout le reste part à Claude en demande libre, et le panneau s'ouvre sur la réponse.
    private func envoyer(_ texte: String) {
        switch texte {
        case DemandeRapide.idees:
            if moment == .rien && !etat.claudeTravaille {
                Task { await etat.lancerClaude(.matin) }
            } else {
                coque.demander("Propose-moi d'autres idées de post pour aujourd'hui.", etat: etat, contexte: Ecran.aujourdhui.titre)
            }
        case DemandeRapide.legende:
            if moment == .pret {
                Task { await etat.lancerClaude(.retouche, consigne: "Propose une autre légende, dans ma voix ; garde les photos et la musique.") }
            } else {
                coque.demander(texte, etat: etat, contexte: Ecran.aujourdhui.titre)
            }
        case DemandeRapide.modeSombre, DemandeRapide.modeClair:
            var a = etat.apparence
            a.mode = texte == DemandeRapide.modeSombre ? "sombre" : "clair"
            Task { await etat.enregistrerApparence(a) }
        default:
            coque.demander(texte, etat: etat, contexte: Ecran.aujourdhui.titre)
        }
    }
}

/// Textes des raccourcis : reconnus par `envoyer` pour lancer la bonne tâche.
private enum DemandeRapide {
    static let idees = "Propose-moi des idées de post."
    static let legende = "Change la légende du post : propose une autre version, dans ma voix."
    static let photos = "Choisis les plus belles photos de ma dernière galerie et dis-moi pourquoi."
    static let modeSombre = "Passe l'app en mode sombre."
    static let modeClair = "Passe l'app en mode clair."
}

// MARK: - Le moment de la journée

enum MomentDuJour: Equatable {
    case idees, preparation, pret, valide, publie, echec, reporte, rien

    init(statut: String?) {
        switch statut {
        case "idees_proposees": self = .idees
        case "idee_choisie": self = .preparation
        case "brouillon_pret": self = .pret
        case "approuve": self = .valide
        case "publie": self = .publie
        case "echec": self = .echec
        case "reporte": self = .reporte
        default: self = .rien
        }
    }
}

/// Petites lectures communes de la journée affichée.
@MainActor
private enum Jour {
    static func prenom(_ etat: EtatApp) -> String? {
        etat.reglages?.nom.split(separator: " ").first.map(String.init)
    }

    static func estAujourdhui(_ etat: EtatApp) -> Bool { etat.jour == EtatApp.aujourdhuiISO() }

    /// « 18:30 » : l'heure prévue (validé) ou le créneau du jour.
    static func heure(_ etat: EtatApp) -> String? {
        if let iso = etat.vue?.publier_a, iso.count >= 16 {
            let debut = iso.index(iso.startIndex, offsetBy: 11)
            return String(iso[debut..<iso.index(debut, offsetBy: 5)])
        }
        return etat.vue?.creneau?.nonVide ?? etat.vue?.post?.heure?.nonVide
    }

    /// « ce soir à 18:30 » ou « jeudi à 18:30 ».
    static func quand(_ etat: EtatApp) -> String {
        guard let h = heure(etat) else { return "à l'heure prévue" }
        if estAujourdhui(etat) {
            let heures = Int(h.prefix(2)) ?? 18
            return heures >= 17 ? "ce soir à \(h)" : "aujourd'hui à \(h)"
        }
        let jour = etat.vue?.date_longue?.split(separator: " ").first.map(String.init) ?? "le jour prévu"
        return "\(jour) à \(h)"
    }

    static func nombre(_ n: Int) -> String {
        let mots = ["zéro", "une", "deux", "trois", "quatre", "cinq", "six"]
        return n < mots.count ? mots[n] : "\(n)"
    }

    /// L'idée choisie (pour sa couverture).
    static func ideeChoisie(_ etat: EtatApp) -> Idee? {
        guard let n = etat.vue?.choix?.numero else { return nil }
        return etat.vue?.idees?.first { $0.numero == n }
    }

    /// La vraie photo du post : la vignette du catalogue de la première photo (`catalogue/<série>/vignettes/<id>.jpg`,
    /// le chemin par défaut du moteur), sinon la couverture de l'idée choisie ; l'image mise en page (cadre papier)
    /// seulement en dernier recours.
    static func couverturePost(_ etat: EtatApp) -> String? {
        let post = etat.vue?.post
        if let serie = post?.serie?.nonVide, let id = post?.medias?.first?.photo_id?.nonVide {
            let f = etat.dossier.appendingPathComponent("catalogue").appendingPathComponent(serie)
                .appendingPathComponent("vignettes").appendingPathComponent("\(id).jpg")
            if FileManager.default.fileExists(atPath: f.path) { return f.path }
        }
        return ideeChoisie(etat)?.couverture?.nonVide
            ?? post?.couverture?.nonVide
            ?? post?.medias?.first?.image
    }

    static func prochainesIdees(_ etat: EtatApp) -> String {
        if let t = etat.planification?.taches.first(where: { $0.id == "matin" }), etat.planification?.active == true,
           let l = t.libelleProchaine {
            return l
        }
        return "demain à \(etat.reglages?.routine.heure_idees ?? "08:00")"
    }
}

// MARK: - En-tête : titre en deux tons, phrase, frise, illustration

private struct EnTeteJour: View {
    let moment: MomentDuJour
    var compacte = false
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: j.esp.sections) {
                textes
                Spacer(minLength: 0)
                IllustrationParlante(sujet: sujet, bulle: bulle, taille: compacte ? 130 : 190)
            }
            textes
        }
    }

    private var textes: some View {
        VStack(alignment: .leading, spacing: compacte ? j.esp.pile + 2 : j.esp.blocs) {
            // Compacte : Titre 1 sur une ou deux lignes, pour que l'action et le feed tiennent sans défiler.
            TitreDeuxTons(debut: debut, suite: suite, role: compacte ? .titre1 : .affiche)
                .frame(maxWidth: compacte ? 720 : 640, alignment: .leading)
            Text(phrase)
                .typo(.chapo)
                .lineLimit(compacte ? 2 : nil)
                .frame(maxWidth: j.esp.largeurTexte, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            FriseDuJour(courante: FriseDuJour.index(statut: etat.vue?.statut),
                        claudeTravaille: etat.claudeTravaille,
                        heurePublication: Jour.heure(etat))
                .frame(maxWidth: 640)
                .padding(.top, compacte ? 2 : j.esp.pile)
        }
        .frame(minWidth: 520, alignment: .leading)
    }

    private var debut: String {
        let salut = etat.apparence.salutation.nonVide ?? "Bonjour"
        if let p = Jour.prenom(etat) { return "\(salut) \(p), " }
        return "\(salut), "
    }

    private var suite: String {
        switch moment {
        case .idees:
            let n = etat.vue?.idees?.count ?? 0
            return n == 1 ? "une idée t'attend." : "\(Jour.nombre(n)) idées t'attendent."
        case .preparation: return "ton post se prépare."
        case .pret: return "ton post est prêt."
        case .valide: return "il part à \(Jour.heure(etat) ?? "l'heure prévue")."
        case .publie: return "c'est en ligne."
        case .echec: return "la publication a coincé."
        case .reporte, .rien:
            if etat.claudeTravaille && etat.execution?.tacheClaude == .matin { return "tes idées arrivent." }
            return "rien à faire pour l'instant."
        }
    }

    private var phrase: String {
        let v = etat.vue
        switch moment {
        case .idees:
            return v?.lecture_du_feed?.nonVide ?? "Choisis celle qui te plaît, ou propose la tienne."
        case .preparation:
            if etat.claudeTravaille {
                return "Claude prépare ton post. Tu peux fermer l'app : elle se rouvrira quand ce sera prêt."
            }
            let titre = v?.choix?.titre ?? v?.choix?.libre ?? "ton idée"
            return "Idée choisie : « \(titre) ». Claude prépare le post, il arrivera ici."
        case .pret:
            return "Il partira \(Jour.quand(etat)) si tu le valides. Un coup d'œil, puis publier, retoucher ou reporter."
        case .valide:
            return "Validé. Il partira \(Jour.quand(etat)) : tu n'as plus rien à faire."
        case .publie:
            return "C'est en ligne ! Claude regardera comment il est reçu au prochain bilan."
        case .echec:
            return v?.erreur?.nonVide ?? "La publication n'est pas partie. Revois l'aperçu pour réessayer."
        case .reporte:
            return "Reporté. Rien ne part aujourd'hui ; tu pourras le reprendre plus tard."
        case .rien:
            if etat.claudeTravaille && etat.execution?.tacheClaude == .matin {
                return "Claude prépare les idées du jour. Tu peux fermer l'app : elle se rouvrira quand ce sera prêt."
            }
            return "Tes idées arrivent \(Jour.prochainesIdees(etat)), l'app s'ouvrira toute seule."
        }
    }

    private var sujet: SujetIllustration {
        switch moment {
        case .idees: return .idee
        case .preparation: return .claude
        case .pret: return .apercu
        case .valide: return .attente
        case .publie: return .publication
        case .echec: return .erreur
        case .reporte, .rien: return etat.claudeTravaille ? .claude : .attente
        }
    }

    private var bulle: String {
        switch moment {
        case .idees: return "J'ai trouvé de quoi raconter."
        case .preparation: return etat.claudeTravaille ? "Je m'en occupe." : "C'est noté."
        case .pret: return "Jette un œil ?"
        case .valide: return "On attend l'heure."
        case .publie: return "Bravo !"
        case .echec: return "On réessaie ?"
        case .reporte, .rien: return etat.claudeTravaille ? "Je cherche des idées." : "Rien ne presse."
        }
    }
}

/// L'illustration du moment et une bulle dans la voix de Claude, comme le robot de l'inspiration.
private struct IllustrationParlante: View {
    let sujet: SujetIllustration
    let bulle: String
    var taille: CGFloat = 190
    @Environment(\.jetons) private var j

    var body: some View {
        Illustration(sujet, taille: taille)
            .frame(width: taille, height: taille)
            .overlay(alignment: .topTrailing) {
                Text(bulle)
                    .font(j.police(.voixCarte))
                    .foregroundStyle(j.texte)
                    .lineLimit(2)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(FondFlottant(forme: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                    .overlay(LisereHaut(rayon: 18))
                    .ombre(.flottante)
                    .offset(x: 34, y: -18)
                    .id(bulle)
                    .transition(j.transition(.apparition))
            }
            .padding(.top, 18)
            .padding(.trailing, 34)
            .accessibilityHidden(true)
    }
}

// MARK: - À régler

/// Une ligne repliée (« À régler · 3 points » + le premier) ; dépliée, un point par ligne. Jamais plus haute que
/// quelques lignes. Le texte reste `texte` sur le fond teinté ; seules l'icône et les puces sont en alerte (§2.1).
private struct CarteARegler: View {
    let points: [String]
    @Binding var ouvert: Bool
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous)
        VStack(alignment: .leading, spacing: j.esp.pile) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(j.alerte)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(j.remplissageCarte))
                Button { withAnimation(j.anim(.doux)) { ouvert.toggle() } } label: {
                    HStack(spacing: 8) {
                        Text("À régler").typo(.corpsFort)
                        Text(points.count == 1 ? "1 point" : "\(points.count) points").typo(.legende)
                        if !ouvert, let p = points.first {
                            Text(p).typo(.legende).lineLimit(1).truncationMode(.tail)
                        }
                        Image(systemName: ouvert ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(j.texteSecondaire)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(ouvert ? "Replier" : "Voir les points à régler")
                .accessibilityLabel("À régler, \(points.count) points")
                .accessibilityHint(ouvert ? "Replier" : "Déplier")
                Spacer(minLength: j.esp.blocs)
                Button { etat.montrer(.reglages) } label: { Label("Ouvrir les réglages", systemImage: "gearshape") }
                    .buttonStyle(.pilule(.claire, taille: .petite))
            }
            if ouvert {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(points, id: \.self) { p in
                        HStack(spacing: 8) {
                            Circle().fill(j.alerte).frame(width: 5, height: 5)
                            Text(p).typo(.corps).lineLimit(1).truncationMode(.tail).help(p)
                        }
                    }
                }
                .padding(.leading, 36)
                .transition(j.transition(.apparition))
            }
        }
        .padding(.horizontal, j.esp.carte * 0.75)
        .padding(.vertical, 10)
        .background(forme.fill(j.fondAlerte))
        .overlay(LisereHaut(rayon: j.rayons.carte))
    }
}

// MARK: - Les trois cartes

/// Cartes compactes (fenêtre de 860 pt) : vignette à gauche, texte à droite, ~150 pt de haut.
private struct CleCartesCompactes: EnvironmentKey { static let defaultValue = false }

private extension EnvironmentValues {
    var cartesCompactes: Bool {
        get { self[CleCartesCompactes.self] }
        set { self[CleCartesCompactes.self] = newValue }
    }
}

private struct CartesDuJour: View {
    let moment: MomentDuJour
    var compacte = false
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(alignment: .top, spacing: j.esp.gouttiere) {
            switch moment {
            case .idees: idees
            case .preparation: preparation
            case .pret: pret
            case .valide: valide
            case .publie: publie
            case .echec: echec
            case .reporte, .rien: rien
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.cartesCompactes, compacte)
    }

    // Idées à choisir : une carte par idée.
    @ViewBuilder private var idees: some View {
        let liste = Array((etat.vue?.idees ?? []).prefix(3))
        ForEach(liste) { i in
            CartePhoto(couverture: i.couverture,
                       titre: i.titre ?? "Idée \(i.numero)",
                       libelle: ["Idée \(i.numero)", i.pilier_libelle, i.format_libelle].compactMap { $0 }.joined(separator: " · "),
                       aide: "Voir les idées") { etat.montrer(.idees) }
        }
    }

    // Post en préparation : l'idée retenue et ce que Claude prépare.
    @ViewBuilder private var preparation: some View {
        let idee = Jour.ideeChoisie(etat)
        let choix = etat.vue?.choix
        CartePhoto(couverture: idee?.couverture,
                   titre: choix?.titre ?? choix?.libre ?? idee?.titre ?? "Ton idée",
                   libelle: "Idée retenue" + (idee?.pilier_libelle.map { " · \($0)" } ?? ""),
                   aide: "Voir les idées") { etat.montrer(.idees) }
        CarteDouce(symbole: idee.map { symboleFormat($0.format) } ?? "square.on.square",
                   texte: formatPrevu(idee),
                   libelle: "Ce que Claude prépare")
        CarteDouce(symbole: "paperplane",
                   texte: "Il partira \(Jour.quand(etat)), une fois que tu l'auras validé.",
                   libelle: "Publication")
    }

    // Post à valider.
    @ViewBuilder private var pret: some View {
        let post = etat.vue?.post
        CartePhoto(couverture: Jour.couverturePost(etat),
                   titre: post?.titre ?? "Ton post",
                   libelle: [post?.format_libelle, post?.pilier_libelle].compactMap { $0 }.joined(separator: " · "),
                   pastille: verdict,
                   aide: "Voir l'aperçu") { etat.montrer(.apercu) }
            .id(etat.versionImages)
        CarteDouce(symbole: "text.quote",
                   texte: extrait(post?.legende) ?? "La légende t'attend dans l'aperçu.",
                   libelle: "La légende, écrite par Claude",
                   lignes: 5) { etat.montrer(.apercu) }
        CarteDouce(symbole: "clock",
                   texte: "Il partira \(Jour.quand(etat)) si tu le valides.",
                   libelle: "Publication") { etat.montrer(.apercu) }
    }

    // Validé, en attente du créneau.
    @ViewBuilder private var valide: some View {
        let post = etat.vue?.post
        CartePhoto(couverture: Jour.couverturePost(etat),
                   titre: post?.titre ?? "Ton post",
                   libelle: "Validé",
                   pastille: ("Validé", .succes),
                   aide: "Revoir l'aperçu") { etat.montrer(.apercu) }
        CarteDouce(symbole: "clock.fill",
                   texte: "Le studio le publiera \(Jour.quand(etat)), même app fermée.",
                   libelle: "Publication")
        CarteDouce(symbole: "pencil.line",
                   texte: "Changer d'avis ? Tu peux encore revoir l'aperçu ou le reporter.",
                   libelle: "Aperçu") { etat.montrer(.apercu) }
    }

    // Publié.
    @ViewBuilder private var publie: some View {
        let post = etat.vue?.post
        CartePhoto(couverture: Jour.couverturePost(etat),
                   titre: post?.titre ?? "Ton post",
                   libelle: "En ligne",
                   pastille: ("Publié", .succes),
                   aide: "Voir sur Instagram") { ouvrirInstagram() }
        CarteDouce(symbole: "chart.line.uptrend.xyaxis",
                   texte: "Claude regardera comment il est reçu et en tiendra compte pour les prochaines idées.",
                   libelle: "Statistiques") { etat.montrer(.statistiques) }
        CarteDouce(symbole: "sunrise",
                   texte: "Tes prochaines idées arrivent \(Jour.prochainesIdees(etat)).",
                   libelle: "Demain")
    }

    // La publication a échoué.
    @ViewBuilder private var echec: some View {
        let post = etat.vue?.post
        CartePhoto(couverture: Jour.couverturePost(etat),
                   titre: post?.titre ?? "Ton post",
                   libelle: "Pas encore publié",
                   pastille: ("À revoir", .alerte),
                   aide: "Revoir l'aperçu") { etat.montrer(.apercu) }
        CarteDouce(symbole: "exclamationmark.triangle",
                   texte: etat.vue?.erreur?.nonVide ?? "Instagram n'a pas accepté la publication.",
                   libelle: "Ce qui s'est passé")
        CarteDouce(symbole: "arrow.triangle.2.circlepath",
                   texte: "Revois l'aperçu, puis relance la publication ou reporte-la.",
                   libelle: "Et maintenant") { etat.montrer(.apercu) }
    }

    // Rien aujourd'hui.
    @ViewBuilder private var rien: some View {
        CarteDouce(symbole: "sunrise",
                   texte: "Chaque matin, Claude te propose des idées : tu choisis, il prépare, tu valides.",
                   libelle: "Idées \(Jour.prochainesIdees(etat))")
        CarteDouce(symbole: "photo.stack",
                   texte: texteGaleries,
                   libelle: "Galeries") { etat.montrer(.galeries) }
        CarteDouce(symbole: "plus",
                   texte: "Une envie précise ? Crée un post toi-même, une étape à la fois.",
                   libelle: "Nouveau post") { etat.montrer(.creation) }
    }

    private var texteGaleries: String {
        let n = etat.sante?.galeries ?? etat.galeries.count
        switch n {
        case 0: return "Aucune galerie pour l'instant. Colle un lien Pic-Time : Claude s'occupe du reste."
        case 1: return "Une galerie où Claude puise les photos de tes posts."
        default: return "\(n) galeries où Claude puise les photos de tes posts."
        }
    }

    private var verdict: (String, TonPastille)? {
        guard let v = etat.vue?.verdict else { return nil }
        if !(v.erreurs ?? []).isEmpty || v.conforme == false { return ("À corriger", .alerte) }
        let n = (v.avertissements ?? []).count
        if n > 0 { return (n == 1 ? "1 point à vérifier" : "\(n) points à vérifier", .douce) }
        return ("Prêt", .succes)
    }

    private func extrait(_ legende: String?) -> String? {
        guard let l = legende?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return nil }
        return l
    }

    private func formatPrevu(_ idee: Idee?) -> String {
        guard let i = idee else { return "Les photos, la légende et la musique, dans ta voix." }
        var morceaux: [String] = []
        if let f = i.format_libelle { morceaux.append(f) }
        if let n = i.nb_medias, n > 1 { morceaux.append("\(n) photos") }
        let debut = morceaux.isEmpty ? "Un post" : morceaux.joined(separator: " de ")
        return "\(debut), avec sa légende et sa musique."
    }

    private func symboleFormat(_ f: String?) -> String {
        switch f {
        case "reel": return "play.rectangle"
        case "image": return "photo"
        default: return "square.on.square"
        }
    }

    private func ouvrirInstagram() {
        if let l = etat.vue?.permalink, let url = URL(string: l) { NSWorkspace.shared.open(url) }
    }
}

/// Carte avec photo : couverture (rayon photo), titre, petit libellé ; tout est cliquable.
private struct CartePhoto: View {
    let couverture: String?
    let titre: String
    let libelle: String
    var pastille: (String, TonPastille)? = nil
    var aide: String
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Environment(\.cartesCompactes) private var compacte

    var body: some View {
        Button(action: action) {
            Carte(style: .cliquable) {
                if compacte {
                    HStack(alignment: .top, spacing: j.esp.blocs) {
                        couvertureVue(ratio: 4.0 / 5.0).frame(width: 84)
                        VStack(alignment: .leading, spacing: 6) {
                            if let p = pastille { Pastille(p.0, ton: p.1) }
                            textes
                        }
                    }
                } else {
                    couvertureVue(ratio: 5.0 / 4.0)
                        .overlay(alignment: .topLeading) {
                            if let p = pastille { Pastille(p.0, ton: p.1).padding(8) }
                        }
                    textes
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(aide)
        .accessibilityLabel("\(titre). \(libelle)")
        .accessibilityHint(aide)
    }

    private func couvertureVue(ratio: CGFloat) -> some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { ImageLocale(chemin: couverture, revelation: true) }
            .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
    }

    private var textes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre)
                .typo(.titre3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !libelle.isEmpty { Text(libelle).typo(.legende).lineLimit(1) }
        }
    }
}

/// Carte douce comme celles de l'inspiration : un symbole dans un disque, une phrase, un petit libellé.
private struct CarteDouce: View {
    let symbole: String
    let texte: String
    let libelle: String
    var lignes = 6
    var action: (() -> Void)? = nil
    @Environment(\.jetons) private var j
    @Environment(\.cartesCompactes) private var compacte

    var body: some View {
        if let a = action {
            Button(action: a) { contenu(.cliquable) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
        } else {
            contenu(.simple)
                .frame(maxWidth: .infinity)
        }
    }

    private func contenu(_ style: StyleCarte) -> some View {
        Carte(style: style) {
            if compacte {
                HStack(alignment: .top, spacing: j.esp.blocs) {
                    icone(34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(texte)
                            .typo(.titre3)
                            .lineLimit(min(lignes, 3))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(libelle).typo(.legende).lineLimit(1)
                    }
                }
            } else {
                icone(40).padding(.bottom, j.esp.blocs)
                Text(texte)
                    .typo(.titre3)
                    .lineLimit(lignes)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: j.esp.pile)
                Text(libelle).typo(.legende).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func icone(_ d: CGFloat) -> some View {
        Image(systemName: symbole)
            .font(.system(size: d * 0.42, weight: .medium))
            .foregroundStyle(j.texte)
            .frame(width: d, height: d)
            .background(Circle().fill(j.fondDoux))
    }
}

// MARK: - L'action principale (ou Claude au travail)

private struct ActionDuJour: View {
    let moment: MomentDuJour
    var compacte = false
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        Group {
            if let e = etat.execution, e.enCours {
                ActiviteClaude(execution: e, compacte: compacte)
                    .frame(maxWidth: 620, alignment: .leading)
                    .transition(j.transition(.apparition))
            } else {
                bouton
            }
        }
        .animation(j.anim(.doux), value: etat.claudeTravaille)
    }

    private var occupe: Bool { etat.lancementEnCours || etat.claudeTravaille }

    @ViewBuilder private var bouton: some View {
        switch moment {
        case .idees:
            Button { etat.montrer(.idees) } label: { Label("Choisir une idée", systemImage: "lightbulb") }
                .buttonStyle(.principal)
        case .preparation:
            if etat.vue?.claude_attend != true {
                HStack(spacing: j.esp.blocs) {
                    Button { Task { await etat.lancerClaude(.creation) } } label: {
                        Label("Préparer le post", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(BoutonPrincipal(enCours: etat.lancementEnCours))
                    .disabled(occupe)
                    Text("Claude n'a pas encore commencé.").typo(.legende)
                }
            } else {
                Label("Claude reprend ton idée : le post arrivera ici.", systemImage: "sparkles").typo(.legende)
            }
        case .pret:
            Button { etat.montrer(.apercu) } label: { Label("Voir l'aperçu", systemImage: "iphone") }
                .buttonStyle(.principal)
        case .valide:
            Button { etat.montrer(.apercu) } label: { Label("Revoir l'aperçu", systemImage: "iphone") }
                .buttonStyle(.pilule(.claire))
        case .publie:
            if let l = etat.vue?.permalink, let url = URL(string: l) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Voir sur Instagram", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.principal)
            }
        case .echec:
            Button { etat.montrer(.apercu) } label: { Label("Revoir l'aperçu", systemImage: "iphone") }
                .buttonStyle(.principal)
        case .reporte, .rien:
            Button { Task { await etat.lancerClaude(.matin) } } label: {
                Label("Demander des idées maintenant", systemImage: "sparkles")
            }
            .buttonStyle(BoutonPrincipal(enCours: etat.lancementEnCours))
            .disabled(occupe)
        }
    }
}

// MARK: - Feed récent

/// Le feed récent, en bande à droite de l'action principale : un libellé et les dernières vignettes.
private struct FeedRecent: View {
    var compacte = false
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    private var vignettes: [String] { (etat.vue?.grille ?? []).compactMap { $0?.nonVide } }
    private var largeur: CGFloat { compacte ? 50 : 68 }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label("Ton feed", systemImage: "square.grid.3x3")
                .labelStyle(.titleAndIcon)
                .font(j.police(.surtitre))
                .foregroundStyle(j.texteSecondaire)
            if vignettes.isEmpty {
                Text("Encore vide : la première publication posera le ton.")
                    .typo(.legende)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(vignettes.prefix(6).enumerated()), id: \.offset) { _, c in
                        ImageLocale(chemin: c)
                            .frame(width: largeur, height: largeur * 1.25)
                            .clipShape(RoundedRectangle(cornerRadius: j.rayons.vignette, style: .continuous))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Les \(min(vignettes.count, 6)) derniers posts du feed")
            }
        }
    }
}
