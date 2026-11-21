import SwiftUI

// Écran « Idées » (DESIGN.md §4.5) : les idées du jour en cartes douces (numéro, couverture 4:5, pastilles
// format et pilier, titre, pitch, « Pourquoi » replié). Un clic sélectionne ; la barre collante monte avec
// « Créer ce post », qui enregistre le choix et ouvre l'assistant de création à l'étape « Claude au travail ».

struct VueIdees: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var selection: Int? = nil
    @Local private var pourquoiOuverts: Set<Int> = []

    private var idees: [Idee] { etat.vue?.idees ?? [] }
    private var statut: String { etat.vue?.statut ?? "nouveau" }
    private var aChoisir: Bool { statut == "idees_proposees" }
    private var peutChoisir: Bool { aChoisir && !etat.occupe }
    private var retenue: Int? { etat.vue?.choix?.numero }

    private var barreVisible: Bool {
        if aChoisir { return selection != nil }
        return retenue != nil && ["idee_choisie", "brouillon_pret"].contains(statut)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: j.esp.sections) {
                EnTeteEcran(surTitre: surTitre, titre: titre, chapo: chapo, voixDeClaude: etat.vue?.lecture_du_feed?.nonVide != nil)
                if idees.isEmpty {
                    EtatVide(symbole: "lightbulb", titre: "Pas encore d'idées",
                             phrase: "Les idées arrivent chaque matin à \(etat.reglages?.routine.heure_idees ?? "8:00"). "
                                 + "L'app s'ouvrira ici toute seule. Tu peux aussi écrire la tienne avec le « + ».",
                             actionTitre: etat.claudeTravaille ? nil : "Demander des idées maintenant",
                             action: { Task { _ = await etat.lancerClaude(.matin) } })
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: j.esp.gouttiere, alignment: .top)],
                              alignment: .leading, spacing: j.esp.gouttiere) {
                        ForEach(Array(idees.enumerated()), id: \.element.id) { i, idee in
                            carte(idee).entreeEnCascade(i)
                        }
                    }
                }
            }
            .frame(maxWidth: j.esp.largeurPage, alignment: .leading)
            .padding(j.esp.page)
            .padding(.bottom, barreVisible ? 110 : 0)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if barreVisible {
                barre.transition(j.transition(.bandeau))
            }
        }
        .animation(j.anim(.doux), value: barreVisible)
        .onChange(of: statut) { _, _ in if !aChoisir { selection = nil } }
    }

    // MARK: En-tête

    private var surTitre: String {
        guard let d = etat.vue?.date_longue?.nonVide else { return "Idées du jour" }
        // « Jeudi 19 novembre » : seule la première lettre en capitale.
        return "Idées du jour · " + d.prefix(1).uppercased() + d.dropFirst()
    }

    private var titre: String {
        if !aChoisir, let c = etat.vue?.choix, let t = (c.titre ?? c.libre)?.nonVide { return "Idée retenue : « \(t) »." }
        return "Choisis l'histoire du jour."
    }

    private var chapo: String? {
        if let l = etat.vue?.lecture_du_feed?.nonVide { return l }
        return aChoisir ? "Choisis une idée : Claude prépare le post complet, prêt à valider." : nil
    }

    // MARK: Carte d'une idée

    private func carte(_ idee: Idee) -> some View {
        let choisie = selection == idee.numero || (!aChoisir && retenue == idee.numero)
        let forme = RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous)
        return Carte(style: peutChoisir ? .cliquable : .simple, choisie: choisie) {
            // Couverture basse (bandeau de 150 pt) avec les vignettes à côté : titre, pitch et pastilles restent
            // visibles sans défiler dans une fenêtre de 860 pt.
            VStack(alignment: .leading, spacing: j.esp.pile + 2) {
                HStack(spacing: 4) {
                    ImageLocale(chemin: idee.couverture)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(forme)
                    if let v = idee.vignettes, !v.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(Array(v.prefix(2).enumerated()), id: \.offset) { _, c in
                                ImageLocale(chemin: c).frame(width: 73, height: 73).clipShape(forme)
                            }
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if idee.type == "exploration" {
                        Pastille("Exploration", symbole: "binoculars", ton: .douce).padding(8)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(idee.numero)").typo(.numero)
                    Text(idee.titre ?? "Idée \(idee.numero)")
                        .typo(.titre3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { pastilles(idee) }
                    VStack(alignment: .leading, spacing: 6) { pastilles(idee) }
                }
                if let p = idee.pitch?.nonVide {
                    Text(p).typo(.corps).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                if let p = idee.pourquoi?.nonVide { pourquoi(idee.numero, p, musique: idee.musique?.nonVide) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard peutChoisir else { return }
            withAnimation(j.anim(.selection)) { selection = selection == idee.numero ? nil : idee.numero }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(peutChoisir ? .isButton : [])
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }

    @ViewBuilder private func pastilles(_ idee: Idee) -> some View {
        Pastille(LibellesIdee.format(idee), symbole: LibellesIdee.symboleFormat(idee.format))
        if let p = idee.pilier_libelle?.nonVide { Pastille(p, symbole: LibellesIdee.symbolePilier(p)) }
    }

    private func pourquoi(_ numero: Int, _ texte: String, musique: String?) -> some View {
        let ouvert = pourquoiOuverts.contains(numero)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(j.anim(.doux)) {
                    if ouvert { pourquoiOuverts.remove(numero) } else { pourquoiOuverts.insert(numero) }
                }
            } label: {
                Label("Pourquoi aujourd'hui", systemImage: ouvert ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.discret)
            if ouvert {
                VoixDeClaude(texte, compacte: true).transition(.opacity)
                if let m = musique {
                    Label(m, systemImage: "music.note").typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Barre collante

    private var barre: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.feuille, style: .continuous)
        let numero = aChoisir ? selection : retenue
        let idee = idees.first { $0.numero == numero }
        return HStack(spacing: j.esp.blocs) {
            if let c = idee?.couverture {
                ImageLocale(chemin: c)
                    .frame(width: 40, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(aChoisir ? "Idée \(numero ?? 0)" : "Idée retenue").typo(.surtitre)
                Text(idee?.titre ?? etat.vue?.choix?.titre ?? "Ton idée").typo(.titre3).lineLimit(1)
            }
            Spacer(minLength: j.esp.blocs)
            if aChoisir {
                Button { creer() } label: { Label("Créer ce post", systemImage: "wand.and.stars") }
                    .buttonStyle(BoutonPrincipal(enCours: etat.occupe))
                    .keyboardShortcut(.defaultAction)
                    .disabled(etat.occupe || etat.lancementEnCours || etat.claudeTravaille)
                    .help(etat.claudeTravaille ? "Claude termine une autre tâche : un instant." : "Claude prépare le post complet")
            } else {
                Button { etat.montrer(.creation) } label: { Label("Voir où en est le post", systemImage: "arrow.right") }
                    .buttonStyle(BoutonPrincipal())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, j.esp.carte)
        .padding(.vertical, 14)
        .background(FondFlottant(forme: forme))
        .overlay(LisereHaut(rayon: j.rayons.feuille))
        .ombre(.flottante)
        .frame(maxWidth: 760)
        .padding(.horizontal, j.esp.page)
        .padding(.bottom, 24)
    }

    private func creer() {
        guard let n = selection, peutChoisir else { return }
        Task {
            await etat.decider("choix", "\(n)")
            if etat.vue?.statut == "idee_choisie" || etat.claudeTravaille {
                selection = nil
                etat.montrer(.creation)
            }
        }
    }
}

/// Libellés et symboles d'une idée, partagés par l'écran Idées et l'assistant de création.
enum LibellesIdee {
    static func format(_ idee: Idee) -> String {
        let f = idee.format_libelle ?? idee.format ?? "Post"
        if idee.format == "reel", let d = idee.duree_s { return "\(f) · \(Int(d)) s" }
        if idee.format == "carrousel", let n = idee.nb_medias { return "\(f) · \(n)" }
        return f
    }

    static func symboleFormat(_ format: String?) -> String {
        switch format {
        case "reel": return "play.rectangle"
        case "image": return "photo"
        default: return "square.on.square"
        }
    }

    static func symbolePilier(_ libelle: String) -> String {
        switch libelle.lowercased() {
        case "éditorial": return "newspaper"
        case "documentaire": return "camera.viewfinder"
        case "détails": return "magnifyingglass"
        case "lieux": return "building.columns"
        case "portraits": return "person.crop.rectangle"
        case "love story": return "heart"
        case "atmosphère": return "cloud.sun"
        case "vision artistique": return "paintbrush.pointed"
        default: return "tag"
        }
    }
}
