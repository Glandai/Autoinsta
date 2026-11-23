import SwiftUI

// Écran « Idées » (ouvert depuis l'accueil quand des idées attendent) et composants partagés avec l'assistant de
// création (conception/simplification.md, point 1) : trois grandes cartes d'idées, et seulement trois actions —
// choisir une carte, « D'autres idées » (Claude en propose trois nouvelles), « Mon idée ».

struct VueIdees: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

    private var statut: String { etat.vue?.statut ?? "nouveau" }
    private var retenue: String? {
        guard ["idee_choisie", "brouillon_pret"].contains(statut), let c = etat.vue?.choix else { return nil }
        return (c.titre ?? c.libre)?.nonVide ?? "ton idée"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.sections * 0.7) {
            VStack(alignment: .leading, spacing: 6) {
                Text(surTitre).typo(.surtitre)
                Text(retenue.map { "Idée retenue : « \($0) »." } ?? "Choisis l'histoire du jour.")
                    .typo(.titre1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if retenue != nil {
                Button { etat.montrer(.creation) } label: { Label("Voir où en est le post", systemImage: "arrow.right") }
                    .buttonStyle(BoutonPrincipal())
                    .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            } else {
                TroisCartesIdees(lancer: { Task { _ = await etat.lancerClaude(.idees) } }) { idee in
                    Task {
                        await etat.decider("choix", "\(idee.numero)")
                        if etat.vue?.statut == "idee_choisie" || etat.claudeTravaille { etat.montrer(.creation) }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                HStack {
                    Spacer()
                    ActionsIdees { texte in
                        Task {
                            await etat.decider("libre", texte)
                            if etat.vue?.statut == "idee_choisie" || etat.claudeTravaille { etat.montrer(.creation) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: j.esp.largeurPage, maxHeight: .infinity, alignment: .topLeading)
        .padding(j.esp.page)
        .frame(maxWidth: .infinity)
    }

    private var surTitre: String {
        "Idées du jour"
    }
}

// MARK: - Composants partagés (Idées, assistant de création)

extension EtatApp {
    /// L'exécution de Claude qui prépare des idées pour le jour affiché (`idees`, ou la routine du matin).
    var executionIdeesDuJour: ExecutionClaude? {
        guard let e = execution, !e.aucune, e.jour == nil || e.jour == jour,
              e.tacheClaude == .idees || e.tacheClaude == .matin else { return nil }
        return e
    }

    /// Vrai quand rien n'empêche de lancer Claude ou d'envoyer une décision.
    var librePourIdees: Bool { !occupe && !lancementEnCours && !claudeTravaille }
}

/// Les trois idées du jour en grandes cartes ; un clic choisit l'idée. Pendant que Claude en prépare, son
/// avancement s'affiche à la place des cartes. Sans idée ni travail en cours : `lancer` (bouton).
struct TroisCartesIdees: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    var hauteurCouverture: CGFloat = 200
    let lancer: () -> Void
    let choisir: (Idee) -> Void

    private var idees: [Idee] { Array((etat.vue?.idees ?? []).prefix(3)) }

    var body: some View {
        Group {
            if let e = etat.executionIdeesDuJour, e.enCours || (idees.isEmpty && !e.reussie) {
                attente(e)
            } else if idees.isEmpty {
                vide
            } else {
                HStack(alignment: .top, spacing: j.esp.gouttiere) {
                    ForEach(Array(idees.enumerated()), id: \.element.id) { i, idee in
                        carte(idee).entreeEnCascade(i)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(j.anim(.doux), value: idees.map(\.numero))
    }

    private func attente(_ e: ExecutionClaude) -> some View {
        VStack(spacing: j.esp.blocs) {
            Illustration(e.etat == "erreur" ? .erreur : .idee, taille: 140).frame(width: 140, height: 140)
            CarteActiviteClaude(execution: e, compacte: true,
                                arreter: { Task { await etat.annulerClaude() } },
                                reessayer: lancer,
                                reconnecter: { Task { await etat.accepterInvitation() } })
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
    }

    private var vide: some View {
        VStack(spacing: j.esp.blocs) {
            Illustration(.idee, taille: 140).frame(width: 140, height: 140)
            if let inv = etat.invitationClaude {
                Text(inv.texte).typo(.chapo).multilineTextAlignment(.center).frame(maxWidth: 460)
                Button { Task { await etat.accepterInvitation() } } label: { Label(inv.libelleBouton, systemImage: inv.symbole) }
                    .buttonStyle(BoutonPilule(.claire))
            } else if etat.lancementEnCours {
                ProgressView().controlSize(.small)
                Text("Claude se met au travail…").typo(.voixCarte, couleur: j.texteSecondaire)
            } else {
                Button(action: lancer) { Label("Proposer trois idées", systemImage: "sparkles") }
                    .buttonStyle(BoutonPilule(.claire))
                    .disabled(!etat.librePourIdees)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func carte(_ idee: Idee) -> some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous)
        return Button { choisir(idee) } label: {
            Carte(style: .cliquable) {
                VStack(alignment: .leading, spacing: j.esp.pile + 2) {
                    ImageLocale(chemin: idee.couverture)
                        .frame(maxWidth: .infinity)
                        .frame(height: hauteurCouverture)
                        .clipShape(forme)
                    HStack(spacing: 6) {
                        Text("\(idee.numero)").font(Font.jakarta(15, graisse: 700)).foregroundStyle(j.accentTexte)
                        Pastille(LibellesIdee.format(idee), symbole: LibellesIdee.symboleFormat(idee.format))
                    }
                    Text(idee.titre ?? "Idée \(idee.numero)")
                        .typo(.titre3)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let p = idee.pitch?.nonVide {
                        Text(p).typo(.legende).lineLimit(4).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Label("Choisir cette idée", systemImage: "arrow.right")
                        .font(Font.jakarta(13.5, graisse: 600))
                        .foregroundStyle(j.accentTexte)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!etat.librePourIdees)
        .accessibilityLabel("Idée \(idee.numero) : \(idee.titre ?? "")")
        .accessibilityHint("Choisir cette idée")
    }
}

/// « D'autres idées » et « Mon idée » : deux pilules claires, chacune avec un petit champ dans une bulle.
struct ActionsIdees: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    let monIdee: (String) -> Void
    @Local private var autresOuvert = false
    @Local private var monIdeeOuvert = false
    @Local private var envie = ""
    @Local private var texte = ""

    var body: some View {
        HStack(spacing: j.esp.blocs) {
            Button { autresOuvert = true } label: { Label("D'autres idées", systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(BoutonPilule(.claire))
                .disabled(!etat.librePourIdees)
                .popover(isPresented: $autresOuvert, arrowEdge: .top) {
                    bulle(titre: "D'autres idées",
                          aide: "Claude en propose trois nouvelles. Une envie ? (facultatif)",
                          champ: $envie, exemple: "par exemple « plus de portraits »",
                          bouton: "Proposer trois idées", symbole: "sparkles", vide: true, valider: autresIdees)
                }
            Button { monIdeeOuvert = true } label: { Label("Mon idée", systemImage: "square.and.pencil") }
                .buttonStyle(BoutonPilule(.claire))
                .disabled(!etat.librePourIdees)
                .popover(isPresented: $monIdeeOuvert, arrowEdge: .top) {
                    bulle(titre: "Ton idée", aide: "Écris-la comme un titre de magazine : Claude prépare le reste.",
                          champ: $texte, exemple: "par exemple « les mains pendant les discours »",
                          bouton: "Créer ce post", symbole: "wand.and.stars", vide: false, valider: envoyerMonIdee)
                }
        }
    }

    private func bulle(titre: String, aide: String, champ: Binding<String>, exemple: String, bouton: String,
                       symbole: String, vide: Bool, valider: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: j.esp.pile + 4) {
            Text(titre).typo(.titre3)
            Text(aide).typo(.legende).fixedSize(horizontal: false, vertical: true)
            ChampDoux(texte: champ, exemple: exemple, lignes: 1...3, envoyer: valider)
            HStack {
                Spacer()
                Button(action: valider) { Label(bouton, systemImage: symbole) }
                    .buttonStyle(BoutonPilule(.sombre))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!etat.librePourIdees || (!vide && champ.wrappedValue.nonVide == nil))
            }
        }
        .padding(20)
        .frame(width: 360)
        .environment(\.jetons, j)
    }

    private func autresIdees() {
        guard etat.librePourIdees else { return }
        let consigne = envie.nonVide
        autresOuvert = false
        envie = ""
        Task { _ = await etat.lancerClaude(.idees, consigne: consigne) }
    }

    private func envoyerMonIdee() {
        guard etat.librePourIdees, let t = texte.nonVide else { return }
        monIdeeOuvert = false
        texte = ""
        monIdee(t)
    }
}

/// Libellés et symboles d'une idée.
enum LibellesIdee {
    static func format(_ idee: Idee) -> String {
        let f = idee.format_libelle ?? idee.format ?? "Post"
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
}
