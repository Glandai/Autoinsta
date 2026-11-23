import SwiftUI

// Accueil (écran `aujourdhui`), version dépouillée (conception/simplification.md, 22/11) : une salutation qui dit
// où en est la journée, UNE carte avec UNE action (ou Claude au travail), une ligne discrète si quelque chose bloque,
// et la barre « Demande à Claude ». Plus de frise, de feed, de semaine ni de « À régler » détaillé.
// Rapide : pas d'illustration animée ici, rien qui se redessine au repos.

struct VueAujourdhui: View {
    @EnvironmentObject var etat: EtatApp
    @EnvironmentObject var coque: CoqueStudio
    @Environment(\.jetons) private var j
    @Local private var demande = ""

    var body: some View {
        // La barre Claude a sa propre place sous le contenu : elle ne recouvre jamais rien.
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                colonne
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView { colonne.padding(.vertical, j.esp.blocs) }
            }
            barreClaude
        }
        .task {
            if etat.reglages == nil { await etat.chargerReglages() }
            if etat.sante == nil { await etat.chargerSante() }
        }
    }

    private var moment: MomentDuJour { MomentDuJour(statut: etat.vue?.statut) }

    private var colonne: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.6) {
            TitreDeuxTons(debut: Jour.salutation(etat), suite: Jour.suite(etat, moment))
                .frame(maxWidth: .infinity, alignment: .leading)
            CarteDuMoment(moment: moment)
            if let blocage = blocage {
                Button { etat.montrer(.reglages) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(j.alerte)
                        Text(blocage).lineLimit(1).truncationMode(.tail)
                        Text("Réglages").foregroundStyle(j.accentTexte)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(j.accentTexte)
                    }
                    .font(j.police(.legende))
                    .foregroundStyle(j.texteSecondaire)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir les réglages")
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(.horizontal, j.esp.page)
        .animation(j.anim(.doux), value: moment)
    }

    /// Une seule phrase, la plus utile, quand quelque chose empêche le studio de publier.
    private var blocage: String? {
        guard let s = etat.sante else { return nil }
        if s.instagram_connecte == false { return "Instagram n'est pas encore relié : rien ne peut partir." }
        if s.hebergement_pret == false { return "L'outil qui envoie les images manque : relance l'installation." }
        if let a = s.a_completer, !a.isEmpty {
            return a.count == 1 ? "À compléter : \(a[0])." : "\(a.count) réglages à compléter."
        }
        return nil
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

    private var raccourcis: [RaccourciClaude] {
        [
            RaccourciClaude("Propose des idées", symbole: "lightbulb", demande: DemandeRapide.idees),
            RaccourciClaude("Change la légende", symbole: "text.quote", demande: DemandeRapide.legende),
            j.schema == .dark
                ? RaccourciClaude("Mode clair", symbole: "sun.max", demande: DemandeRapide.modeClair)
                : RaccourciClaude("Mode sombre", symbole: "moon", demande: DemandeRapide.modeSombre),
        ]
    }

    /// Un raccourci lance la bonne tâche quand il y en a une (idées, retouche, apparence) ;
    /// tout le reste part à Claude en demande libre, et le panneau s'ouvre sur la réponse.
    private func envoyer(_ texte: String) {
        switch texte {
        case DemandeRapide.idees:
            if (moment == .rien || moment == .reporte) && !etat.claudeTravaille {
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
    /// Le prénom du compte, s'il est rempli (un compte neuf contient « [À COMPLÉTER : …] »).
    static func prenom(_ etat: EtatApp) -> String? {
        guard let nom = etat.reglages?.nom, !nom.contains("[") else { return nil }
        return nom.split(separator: " ").first.map(String.init)
    }

    static func salutation(_ etat: EtatApp) -> String {
        let salut = etat.apparence.salutation.nonVide ?? "Bonjour"
        if let p = prenom(etat) { return "\(salut) \(p), " }
        return "\(salut), "
    }

    /// La suite du titre : où en est la journée, en quelques mots.
    static func suite(_ etat: EtatApp, _ moment: MomentDuJour) -> String {
        if let e = etat.execution, e.enCours {
            switch e.tacheClaude {
            case .matin?: return "tes idées arrivent."
            case .creation?, .retouche?: return "Claude prépare ton post."
            default: return "Claude s'en occupe."
            }
        }
        switch moment {
        case .idees:
            let n = etat.vue?.idees?.count ?? 0
            return n == 1 ? "une idée t'attend." : "\(nombre(n)) idées t'attendent."
        case .preparation: return "ton idée est choisie."
        case .pret: return "ton post est prêt."
        case .valide: return "il part à \(heure(etat) ?? "l'heure prévue")."
        case .publie: return "c'est en ligne."
        case .echec: return "la publication a coincé."
        case .reporte, .rien: return "rien à faire aujourd'hui."
        }
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

// MARK: - La carte du moment

/// Ce qui se passe, en une phrase, avec une image si elle aide, et UNE action. Pendant un travail de Claude,
/// la carte est remplacée par son activité en direct (qui porte son propre « Arrêter »).
private struct CarteDuMoment: View {
    let moment: MomentDuJour
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    var body: some View {
        if let e = etat.execution, e.enCours {
            ActiviteClaude(execution: e, compacte: true)
                .transition(j.transition(.apparition))
        } else {
            Carte {
                HStack(alignment: .top, spacing: j.esp.carte) {
                    visuel
                    VStack(alignment: .leading, spacing: j.esp.blocs) {
                        Text(phrase)
                            .typo(.chapo, couleur: j.texte)
                            .fixedSize(horizontal: false, vertical: true)
                        action
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .transition(j.transition(.apparition))
        }
    }

    private var occupe: Bool { etat.lancementEnCours || etat.claudeTravaille }

    // MARK: Phrase

    private var phrase: String {
        let v = etat.vue
        switch moment {
        case .idees:
            return "Choisis celle qui te plaît, ou propose la tienne."
        case .preparation:
            let titre = v?.choix?.titre ?? v?.choix?.libre ?? "Ton idée"
            return v?.claude_attend == true
                ? "« \(titre) » : Claude reprend ton idée, le post arrivera ici."
                : "« \(titre) ». Claude n'a pas encore commencé le post."
        case .pret:
            return "« \(v?.post?.titre ?? "Ton post") » partira \(Jour.quand(etat)) si tu le valides."
        case .valide:
            return "Le studio le publiera \(Jour.quand(etat)), même app fermée. Tu n'as plus rien à faire."
        case .publie:
            return "« \(v?.post?.titre ?? "Ton post") » est publié."
        case .echec:
            return v?.erreur?.nonVide ?? "Instagram n'a pas accepté la publication. Revois l'aperçu pour réessayer."
        case .reporte, .rien:
            return "Tes prochaines idées arrivent \(Jour.prochainesIdees(etat)). Une envie précise ? Crée un post maintenant."
        }
    }

    // MARK: Visuel

    @ViewBuilder private var visuel: some View {
        switch moment {
        case .idees:
            let couvertures = (etat.vue?.idees ?? []).prefix(3).compactMap { $0.couverture?.nonVide }
            if couvertures.isEmpty {
                symbole("lightbulb")
            } else {
                HStack(spacing: -22) {
                    ForEach(Array(couvertures.enumerated()), id: \.offset) { i, c in
                        photo(c, largeur: 64)
                            .rotationEffect(.degrees(Double(i - 1) * 4))
                            .zIndex(Double(3 - i))
                    }
                }
                .padding(.horizontal, 6)
            }
        case .preparation:
            if let c = Jour.ideeChoisie(etat)?.couverture?.nonVide { photo(c, largeur: 84) } else { symbole("wand.and.stars") }
        case .pret, .valide, .publie, .echec:
            if let c = Jour.couverturePost(etat) {
                photo(c, largeur: 84).id(etat.versionImages)
            } else {
                symbole(moment == .publie ? "paperplane.fill" : "iphone")
            }
        case .reporte, .rien:
            symbole("sun.max")
        }
    }

    private func photo(_ chemin: String, largeur: CGFloat) -> some View {
        ImageLocale(chemin: chemin)
            .frame(width: largeur, height: largeur * 1.25)
            .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous)
                .strokeBorder(Color.white.opacity(j.schema == .dark ? 0.1 : 0.8), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func symbole(_ nom: String) -> some View {
        Image(systemName: nom)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(j.texte)
            .frame(width: 56, height: 56)
            .background(Circle().fill(j.fondDoux))
            .accessibilityHidden(true)
    }

    // MARK: Action (une seule)

    @ViewBuilder private var action: some View {
        switch moment {
        case .idees:
            Button { etat.montrer(.idees) } label: { Label("Choisir une idée", systemImage: "lightbulb") }
                .buttonStyle(.principal)
        case .preparation:
            if etat.vue?.claude_attend != true {
                Button { Task { await etat.lancerClaude(.creation) } } label: {
                    Label("Préparer le post", systemImage: "wand.and.stars")
                }
                .buttonStyle(BoutonPrincipal(enCours: etat.lancementEnCours))
                .disabled(occupe)
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
            Button { etat.montrer(.creation) } label: { Label("Créer un post", systemImage: "plus") }
                .buttonStyle(.principal)
        }
    }
}
