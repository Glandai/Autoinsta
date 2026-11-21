import SwiftUI

// Charte et Règles (DESIGN.md §4.10, §4.11), au style v2.
//
// Charte : le texte que Claude suit, en lecture confortable (une carte de 680 pt, Markdown mis en forme,
// sommaire des grandes parties à gauche). « Modifier » ouvre l'éditeur, « Enregistrer » (⌘S) l'envoie au studio,
// « Rétablir l'original » (confirmé) reprend la charte d'origine, « Demander à Claude de l'ajuster » ouvre le panneau.
//
// Règles : les familles de mots en cartes (pastilles retirables, « Ajouter un mot… »), les limites et l'alternance
// réglables. Tout s'enregistre tout seul, sans bandeau (⌘S pour enregistrer tout de suite).
//
// Briques partagées avec VueReglages.swift : `EtatSauvegarde`, `IndicateurSauvegarde`, `LigneReglage`,
// `ReglageNombre`, `RangeesSouples`, `DemandeClaudeReglages`, `EtatApp.enregistrerSansBandeau(_:action:)`.

// MARK: - Charte

struct VueCharte: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var texte = ""
    @Local private var original = ""
    @Local private var charge = false
    @Local private var edition = false
    @Local private var envoi = false
    @Local private var confirmerRetablir = false
    @Local private var confirmerAbandon = false

    private var modifie: Bool { texte != original }
    private var blocs: [BlocCharte] { BlocCharte.lire(original) }

    var body: some View {
        ScrollViewReader { lecteur in
            ScrollView {
                VStack(alignment: .leading, spacing: j.esp.sections * 0.6) {
                    EnTeteEcran(surTitre: "Personnaliser", titre: "Charte",
                                chapo: "Le texte que Claude suit pour chaque idée et chaque post : ton identité, tes piliers, ton feed, tes légendes, tes interdits.") {
                        actions
                    }
                    .id("haut")
                    if etat.charte?.nouvelle_base == true {
                        avisNouvelleBase
                    }
                    if !charge {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("J'ouvre ta charte…").typo(.legende)
                        }
                    } else if edition {
                        editeur
                            .transition(j.transition(.apparition))
                    } else {
                        lecture(lecteur)
                            .transition(j.transition(.apparition))
                    }
                }
                .animation(j.anim(.doux), value: edition)
                .frame(maxWidth: j.esp.largeurPage, alignment: .leading)
                .padding(.horizontal, j.esp.page)
                .padding(.top, j.esp.page * 0.7)
                .padding(.bottom, j.esp.page)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await charger() }
        .alert("Rétablir la charte d'origine ?", isPresented: $confirmerRetablir) {
            Button("Rétablir", role: .destructive) { Task { await retablir() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes modifications de la charte seront remplacées par le texte d'origine.")
        }
        .confirmationDialog("Abandonner tes changements ?", isPresented: $confirmerAbandon) {
            Button("Abandonner", role: .destructive) { abandonner() }
            Button("Continuer à modifier", role: .cancel) {}
        } message: {
            Text("Le texte reviendra à la dernière version enregistrée.")
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if edition {
                Button("Annuler") { if modifie { confirmerAbandon = true } else { abandonner() } }
                    .buttonStyle(.pilule(.claire))
                    .keyboardShortcut(.cancelAction)
                    .disabled(envoi)
                Button { Task { await enregistrer() } } label: { Label("Enregistrer", systemImage: "checkmark") }
                    .buttonStyle(.pilule(.sombre, enCours: envoi))
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!modifie || envoi)
                    .help("Enregistrer (⌘S)")
            } else {
                Button { confirmerRetablir = true } label: {
                    Label("Rétablir l'original", systemImage: "arrow.uturn.backward")
                }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                    .disabled(!charge || etat.charte?.personnalisee == false && etat.charte?.nouvelle_base != true)
                Button {
                    texte = original
                    edition = true
                } label: { Label("Modifier", systemImage: "pencil.line") }
                .buttonStyle(.pilule(.claire))
                .disabled(!charge)
            }
        }
    }

    private var avisNouvelleBase: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(j.accentTexte)
                .accessibilityHidden(true)
            Text("Une nouvelle version de la charte d'origine est arrivée avec la mise à jour du studio. « Rétablir l'original » la reprend : tes modifications seront remplacées.")
                .typo(.corps)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 640, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous).fill(j.fondDoux))
        .accessibilityElement(children: .combine)
    }

    // MARK: Lecture

    private func lecture(_ lecteur: ScrollViewProxy) -> some View {
        let tout = blocs
        let parties = tout.filter { $0.genre == .titre1 }
        return HStack(alignment: .top, spacing: j.esp.sections * 0.7) {
            if parties.count >= 3 {
                sommaire(parties, lecteur)
                    .frame(width: 210, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: j.esp.gouttiere) {
                DemandeClaudeReglages(titre: "Demander à Claude de l'ajuster",
                                      texte: "Un ton plus doux, un pilier en plus, un mot à bannir… Claude modifie la charte pour toi.",
                                      debut: "Ajuste ma charte : ",
                                      contexte: "Charte",
                                      bouton: "Demander")
                Label("C'est le texte exact que Claude lit : quelques passages techniques s'adressent à lui seul.",
                      systemImage: "info.circle")
                    .typo(.legende)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                Carte {
                    if tout.isEmpty {
                        Text("La charte est vide pour l'instant. « Modifier » pour l'écrire, ou demande à Claude de t'aider.")
                            .typo(.chapo)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(tout) { b in
                                VueBlocCharte(bloc: b).id(b.id)
                            }
                        }
                        .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private func sommaire(_ parties: [BlocCharte], _ lecteur: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sommaire").typo(.surtitre).padding(.leading, 10).padding(.bottom, 6)
            ForEach(parties) { p in
                LienSommaire(titre: p.texte) {
                    withAnimation(j.anim(.doux)) { lecteur.scrollTo(p.id, anchor: .top) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sommaire de la charte")
    }

    // MARK: Édition

    private var editeur: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            Carte {
                TextEditor(text: $texte)
                    .font(.jakarta(15))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 560, idealHeight: 640)
                    .accessibilityLabel("Texte de la charte")
            }
            HStack(spacing: 10) {
                Text("Markdown : « # » pour une grande partie, « ## » pour une sous-partie, « - » pour une liste.")
                    .typo(.legende)
                Spacer()
                Text(modifie ? "\(texte.count) caractères · modifiée" : "\(texte.count) caractères")
                    .typo(.legende)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    // MARK: Chargement, enregistrement

    private func charger() async {
        await etat.chargerCharte()
        original = etat.charte?.texte ?? ""
        if !edition { texte = original }
        withAnimation(j.anim(.doux)) { charge = true }
    }

    private func enregistrer() async {
        guard modifie, !envoi else { return }
        envoi = true
        let t = texte
        if await etat.envoyerTexte(t, action: "enregistrer-charte") {
            await etat.chargerCharte()
            original = etat.charte?.texte ?? t
            texte = original
            etat.message = "Charte enregistrée. Claude la suivra dès sa prochaine idée."
            withAnimation(j.anim(.doux)) { edition = false }
        }
        envoi = false
    }

    private func abandonner() {
        texte = original
        withAnimation(j.anim(.doux)) { edition = false }
    }

    private func retablir() async {
        await etat.retablir("retablir-charte")
        await etat.chargerCharte()
        original = etat.charte?.texte ?? ""
        texte = original
        edition = false
    }
}

/// Un lien du sommaire : texte secondaire, voile doux au survol.
private struct LienSommaire: View {
    let titre: String
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        Button(action: action) {
            Text(titre)
                .typo(.corps, couleur: survol ? j.texte : j.texteSecondaire)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: j.rayons.champ * 0.6, style: .continuous)
                    .fill(survol ? j.selection : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(j.anim(.survol), value: survol)
    }
}

/// Un morceau de la charte, lu depuis son Markdown.
struct BlocCharte: Identifiable, Equatable {
    enum Genre: Equatable { case titre1, titre2, titre3, paragraphe, puce, numero, citation, code, separateur }
    let id: Int
    let genre: Genre
    let texte: String
    /// Le numéro d'une liste numérotée (« 1. »).
    var marque: String = ""

    /// Un titre tout en CAPITALES (« 2. L'IDENTITÉ ») s'affiche en casse normale (« 2. L'identité ») ;
    /// le texte enregistré ne change pas.
    static func adoucir(_ titre: String) -> String {
        let lettres = titre.filter(\.isLetter)
        guard lettres.count > 2, !lettres.contains(where: \.isLowercase) else { return titre }
        var t = titre.lowercased(with: Locale(identifier: "fr_FR"))
        if let i = t.firstIndex(where: \.isLetter) { t.replaceSubrange(i...i, with: String(t[i]).uppercased()) }
        for nom in ["Instagram", "Claude", "Reels", "Reel", "Facebook", "Pic-Time"] {
            t = t.replacingOccurrences(of: "\\b\(nom.lowercased())\\b", with: nom, options: .regularExpression)
        }
        return t
    }

    /// Découpe le Markdown en titres, paragraphes, listes, citations, blocs de code et séparateurs.
    static func lire(_ markdown: String) -> [BlocCharte] {
        var blocs: [BlocCharte] = []
        var paragraphe: [String] = []
        var code: [String]? = nil

        func ajouter(_ genre: Genre, _ texte: String, marque: String = "") {
            blocs.append(BlocCharte(id: blocs.count, genre: genre, texte: texte, marque: marque))
        }
        func finirParagraphe() {
            let t = paragraphe.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { ajouter(.paragraphe, t) }
            paragraphe = []
        }

        for brute in markdown.components(separatedBy: .newlines) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if ligne.hasPrefix("```") {
                if let c = code {
                    ajouter(.code, c.joined(separator: "\n"))
                    code = nil
                } else {
                    finirParagraphe()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(brute)
                continue
            }
            if ligne.isEmpty {
                finirParagraphe()
            } else if ligne.hasPrefix("#") {
                finirParagraphe()
                let dieses = ligne.prefix(while: { $0 == "#" }).count
                let titre = ligne.dropFirst(dieses).trimmingCharacters(in: .whitespaces)
                if titre.isEmpty { continue }
                ajouter(dieses == 1 ? .titre1 : (dieses == 2 ? .titre2 : .titre3), adoucir(titre))
            } else if ligne == "---" || ligne == "***" || ligne == "___" {
                finirParagraphe()
                ajouter(.separateur, "")
            } else if ligne.hasPrefix("- ") || ligne.hasPrefix("* ") || ligne.hasPrefix("+ ") {
                finirParagraphe()
                ajouter(.puce, String(ligne.dropFirst(2)))
            } else if let point = ligne.firstIndex(of: "."), point > ligne.startIndex,
                      ligne[ligne.startIndex..<point].allSatisfy(\.isNumber),
                      ligne[ligne.index(after: point)...].hasPrefix(" ") {
                finirParagraphe()
                ajouter(.numero, ligne[ligne.index(after: point)...].trimmingCharacters(in: .whitespaces),
                        marque: String(ligne[ligne.startIndex...point]))
            } else if ligne.hasPrefix(">") {
                finirParagraphe()
                ajouter(.citation, ligne.dropFirst().trimmingCharacters(in: .whitespaces))
            } else {
                paragraphe.append(ligne)
            }
        }
        if let c = code { ajouter(.code, c.joined(separator: "\n")) }
        finirParagraphe()
        return blocs
    }
}

/// Un bloc mis en forme : titres en Titre 2 et 3, texte en 17/28 pour une lecture confortable.
private struct VueBlocCharte: View {
    let bloc: BlocCharte
    @Environment(\.jetons) private var j

    private var enLigne: AttributedString {
        (try? AttributedString(markdown: bloc.texte,
                               options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(bloc.texte)
    }

    private var lecture: Font { .jakarta(17 * j.echelle, graisse: 400) }

    var body: some View {
        switch bloc.genre {
        case .titre1:
            Text(enLigne)
                .typo(.titre2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, bloc.id == 0 ? 0 : 18)
                .accessibilityAddTraits(.isHeader)
        case .titre2:
            Text(enLigne)
                .typo(.titre3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .titre3:
            Text(enLigne)
                .typo(.corpsFort)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraphe:
            Text(enLigne)
                .font(lecture)
                .lineSpacing(7)
                .foregroundStyle(j.texte)
                .fixedSize(horizontal: false, vertical: true)
        case .puce, .numero:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if bloc.genre == .numero {
                    Text(bloc.marque)
                        .font(.jakarta(15 * j.echelle, graisse: 600))
                        .foregroundStyle(j.accentTexte)
                        .monospacedDigit()
                } else {
                    Circle()
                        .fill(j.accent)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 1 }
                }
                Text(enLigne)
                    .font(lecture)
                    .lineSpacing(7)
                    .foregroundStyle(j.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        case .citation:
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(j.accent).frame(width: 2)
                Text(enLigne)
                    .font(.jakarta(17 * j.echelle, graisse: 400, italique: true))
                    .lineSpacing(7)
                    .foregroundStyle(j.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code:
            Text(bloc.texte)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(j.texte)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous).fill(j.surface))
        case .separateur:
            Filet().padding(.vertical, 8)
        }
    }
}

// MARK: - Règles

struct VueRegles: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var r: Regles?
    @Local private var lecture = true
    @Local private var sauvegarde = EtatSauvegarde.repos
    @Local private var tache: Task<Void, Never>?
    @Local private var serie = 0
    @Local private var confirmerRetablir = false
    /// Quand les règles affichées ont été (re)lues : un changement n'est voulu que s'il suit un geste fait après.
    @Local private var affichage = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: j.esp.sections * 0.6) {
                EnTeteEcran(surTitre: "Personnaliser", titre: "Règles",
                            chapo: "Ce que le contrôle refuse ou signale avant chaque publication. Chaque changement s'enregistre tout seul.") {
                    HStack(spacing: 12) {
                        IndicateurSauvegarde(etat: sauvegarde)
                        Button("Valeurs d'origine") { confirmerRetablir = true }
                            .buttonStyle(.discret)
                            .disabled(r == nil)
                    }
                }
                if let lies = reglesLiees {
                    contenu(lies)
                } else if lecture {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Je lis tes règles…").typo(.legende)
                    }
                } else {
                    EtatVide(symbole: "checkmark.shield", titre: "Règles introuvables",
                             phrase: "Je n'arrive pas à lire les règles du studio pour l'instant.",
                             actionTitre: "Réessayer") { Task { await charger() } }
                }
            }
            .frame(maxWidth: j.esp.largeurPage, alignment: .leading)
            .padding(.horizontal, j.esp.page)
            .padding(.top, j.esp.page * 0.7)
            .padding(.bottom, j.esp.page)
            .frame(maxWidth: .infinity)
        }
        .background(raccourciEnregistrer)
        .onAppear { InteractionsUtilisateur.partage.demarrer() }
        .task { await charger() }
        .onDisappear { enregistrerSiBesoin() }
        .alert("Revenir aux règles d'origine ?", isPresented: $confirmerRetablir) {
            Button("Rétablir", role: .destructive) { Task { await retablir() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes mots, tes limites et ton alternance reviendront aux valeurs d'origine.")
        }
    }

    // MARK: Contenu

    private func grille<C: View>(@ViewBuilder _ contenu: () -> C) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: j.esp.gouttiere, alignment: .top)],
                  alignment: .leading, spacing: j.esp.gouttiere, content: contenu)
    }

    @ViewBuilder private func contenu(_ r: Binding<Regles>) -> some View {
        section("Mots et tournures refusés", "Une légende qui en contient un ne part pas : Claude la réécrit.")
        grille {
            FamilleMots(titre: "Clichés du mariage", symbole: "heart.slash", mots: r.legende.cliches, refuse: true)
            FamilleMots(titre: "Ton commercial", symbole: "megaphone", mots: r.legende.commercial, refuse: true)
            FamilleMots(titre: "Incitations artificielles", aide: "« Like si… », « Tague… »", symbole: "hand.tap",
                        mots: r.legende.incitations, refuse: true)
            FamilleMots(titre: "À faire ressentir, pas à écrire", aide: "Les mots de ta charte qui ne doivent pas apparaître tels quels.",
                        symbole: "text.book.closed", mots: r.legende.mots_du_prompt, refuse: true)
            FamilleMots(titre: "Hashtags trop génériques", aide: "Avec le #.", symbole: "number",
                        mots: r.legende.hashtags_generiques, refuse: true, prefixe: "#")
        }
        section("Mots seulement signalés", "Le post peut partir, mais Claude te le fait remarquer.")
        grille {
            FamilleMots(titre: "Mots commerciaux possibles", symbole: "tag", mots: r.legende.commercial_possible, refuse: false)
            FamilleMots(titre: "Superlatifs", symbole: "star", mots: r.legende.superlatifs, refuse: false)
        }
        section("Limites", nil)
        carteLimites(r)
        section("Alternance du feed", "Pour que le feed respire : jamais la même chose deux fois de suite.")
        carteAlternance(r)
    }

    private func section(_ titre: String, _ texte: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).typo(.titre2).accessibilityAddTraits(.isHeader)
            if let t = texte { Text(t).typo(.chapo).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.top, 6)
    }

    private func carteLimites(_ r: Binding<Regles>) -> some View {
        Carte {
            LigneReglage("Longueur de la légende", aide: "Instagram accepte 2 200 caractères au plus.", symbole: "text.alignleft") {
                ReglageNombre(valeur: r.limites.legende_caracteres, plage: 100...2200, pas: 50, unite: "car.", libelle: "Longueur de la légende")
            }
            Filet()
            LigneReglage("Mentions @", symbole: "at") {
                ReglageNombre(valeur: r.limites.mentions, plage: 0...20, libelle: "Mentions")
            }
            Filet()
            LigneReglage("Hashtags", symbole: "number") {
                ReglageNombre(valeur: r.limites.hashtags, plage: 0...30, libelle: "Hashtags")
            }
            Filet()
            LigneReglage("Collaborateurs", aide: "Comptes invités à cosigner le post.", symbole: "person.2") {
                ReglageNombre(valeur: r.limites.collaborateurs, plage: 0...3, libelle: "Collaborateurs")
            }
            Filet()
            LigneReglage("Images par carrousel", symbole: "square.on.square") {
                ReglageNombre(valeur: r.limites.medias_carrousel, plage: 2...20, libelle: "Images par carrousel")
            }
            Filet()
            LigneReglage("Carrousel jugé court", aide: "En dessous de ce nombre d'images, Claude te le signale.", symbole: "rectangle.stack") {
                ReglageNombre(valeur: r.limites.carrousel_court, plage: 2...10, libelle: "Carrousel jugé court")
            }
        }
    }

    private func carteAlternance(_ r: Binding<Regles>) -> some View {
        Carte {
            LigneReglage("Jamais deux fois le même pilier de suite", symbole: "square.grid.2x2") {
                interrupteur(r.alternance.pilier_consecutif_interdit, "Jamais deux fois le même pilier de suite")
            }
            Filet()
            LigneReglage("Jamais deux fois la même série de suite", symbole: "photo.stack") {
                interrupteur(r.alternance.serie_consecutive_interdite, "Jamais deux fois la même série de suite")
            }
            Filet()
            LigneReglage("Une couverture diffère de la précédente", aide: "Nombre de critères au moins (cadrage, lumière, sujet, couleur).",
                         symbole: "photo") {
                ReglageNombre(valeur: r.alternance.criteres_couverture_differents, plage: 0...4, libelle: "Critères différents")
            }
            Filet()
            LigneReglage("Couvertures de suite dans la même tonalité", aide: "Au plus.", symbole: "circle.lefthalf.filled") {
                ReglageNombre(valeur: r.alternance.meme_tonalite_max, plage: 1...10, libelle: "Même tonalité au plus")
            }
            Filet()
            LigneReglage("Légendes de suite de même longueur", aide: "Au plus.", symbole: "text.justify.left") {
                ReglageNombre(valeur: r.alternance.meme_longueur_max, plage: 1...10, libelle: "Même longueur au plus")
            }
            Filet()
            LigneReglage("Posts centrés sur le couple", aide: "Au plus, sur 8 posts.", symbole: "heart") {
                ReglageNombre(valeur: r.alternance.couple_max_sur_8, plage: 0...8, libelle: "Posts sur le couple, sur 8")
            }
            Filet()
            LigneReglage("Piliers différents", aide: "Au moins, sur 10 posts.", symbole: "square.grid.3x3") {
                ReglageNombre(valeur: r.alternance.piliers_min_sur_10, plage: 1...8, libelle: "Piliers différents, sur 10")
            }
        }
    }

    private func interrupteur(_ lien: Binding<Bool>, _ titre: String) -> some View {
        Toggle(titre, isOn: lien).toggleStyle(.switch).labelsHidden().accessibilityLabel(titre)
    }

    // MARK: Brouillon et enregistrement

    private var reglesLiees: Binding<Regles>? {
        guard let actuelles = r else { return nil }
        return Binding(get: { r ?? actuelles }, set: { nouvelles in
            // Rien ne s'écrit sans vrai changement fait par la photographe après l'affichage.
            guard let anciennes = r, !InteractionsUtilisateur.memesDonnees(anciennes, nouvelles) else { return }
            r = nouvelles
            if InteractionsUtilisateur.partage.voulu(depuis: affichage) { planifierEnregistrement() }
        })
    }

    private var raccourciEnregistrer: some View {
        Button("Enregistrer") { enregistrerSiBesoin() }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private func charger() async {
        lecture = true
        await etat.chargerRegles()
        if r == nil { r = etat.regles }
        affichage = Date()
        lecture = false
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
        guard let copie = r else { return }
        sauvegarde = .enCours
        let ok = await etat.enregistrerSansBandeau(copie, action: "enregistrer-regles")
        if ok { etat.regles = copie }
        guard numero == serie else { return }
        tache = nil
        sauvegarde = ok ? .fait : .echec
    }

    private func retablir() async {
        tache?.cancel()
        serie += 1
        sauvegarde = .repos
        await etat.retablir("retablir-regles")
        await etat.chargerRegles()
        r = etat.regles
        affichage = Date()
    }
}

/// Une famille de mots : ses pastilles retirables (×) et « Ajouter un mot… ».
private struct FamilleMots: View {
    let titre: String
    var aide: String? = nil
    let symbole: String
    @Binding var mots: [String]
    /// Refusés (pastilles d'alerte) ou seulement signalés (pastilles douces).
    let refuse: Bool
    var prefixe: String? = nil
    @Environment(\.jetons) private var j
    @Local private var ajout = false
    @Local private var nouveau = ""
    @FocusState private var focus: Bool

    var body: some View {
        Carte(titre: titre, symbole: symbole) {
            if let a = aide {
                Text(a).typo(.legende).fixedSize(horizontal: false, vertical: true)
            }
            RangeesSouples(espacement: 6, interligne: 6) {
                ForEach(Array(mots.enumerated()), id: \.offset) { i, mot in
                    PastilleMot(mot: mot, refuse: refuse) { retirer(i) }
                }
                if ajout {
                    champ
                } else {
                    Button {
                        ajout = true
                        DispatchQueue.main.async { focus = true }
                    } label: { Label("Ajouter un mot…", systemImage: "plus") }
                    .buttonStyle(.pilule(.claire, taille: .petite))
                }
            }
            .animation(j.anim(.selection), value: mots)
            Text(mots.isEmpty ? "Aucun mot pour l'instant." : (mots.count == 1 ? "1 mot" : "\(mots.count) mots"))
                .typo(.legende)
        }
    }

    private var champ: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        return HStack(spacing: 6) {
            TextField(prefixe.map { "\($0)mot" } ?? "Un mot ou une tournure", text: $nouveau)
                .textFieldStyle(.plain)
                .font(.jakarta(13))
                .focused($focus)
                .focusEffectDisabled()
                .onSubmit(ajouter)
                .onExitCommand { fermer() }
                .frame(width: 180)
                .accessibilityLabel("Nouveau mot pour \(titre)")
            Button(action: ajouter) { Image(systemName: "return") }
                .buttonStyle(.plain)
                .foregroundStyle(j.texteSecondaire)
                .help("Ajouter (⏎)")
                .accessibilityLabel("Ajouter")
        }
        .padding(.horizontal, 12)
        .frame(height: max(26, j.esp.hauteurBouton - 10))
        .background(forme.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
        .overlay(forme.strokeBorder(focus ? j.encre.opacity(0.75) : j.traitFort, lineWidth: focus ? 1.5 : 1))
    }

    /// Ajoute un ou plusieurs mots (séparés par des virgules), sans doublon.
    private func ajouter() {
        let deja = Set(mots.map(AccentsRegles.cle))
        var ajoutes: [String] = []
        for morceau in nouveau.split(separator: ",") {
            var m = morceau.trimmingCharacters(in: .whitespaces)
            if let p = prefixe, !m.isEmpty, !m.hasPrefix(p) { m = p + m }
            guard !m.isEmpty, !deja.contains(AccentsRegles.cle(m)),
                  !ajoutes.map(AccentsRegles.cle).contains(AccentsRegles.cle(m)) else { continue }
            ajoutes.append(m)
        }
        if !ajoutes.isEmpty {
            withAnimation(j.anim(.selection)) { mots.append(contentsOf: ajoutes) }
            AccessibilityNotification.Announcement("Ajouté : \(ajoutes.joined(separator: ", "))").post()
        }
        nouveau = ""
        focus = true
    }

    private func fermer() {
        nouveau = ""
        ajout = false
    }

    private func retirer(_ i: Int) {
        guard mots.indices.contains(i) else { return }
        let mot = mots[i]
        withAnimation(j.anim(.selection)) { _ = mots.remove(at: i) }
        AccessibilityNotification.Announcement("Retiré : \(mot)").post()
    }
}

/// Un mot en pastille, avec son × pour le retirer.
private struct PastilleMot: View {
    let mot: String
    let refuse: Bool
    let retirer: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        let sombre = j.schema == .dark
        HStack(spacing: 4) {
            Text(AccentsRegles.afficher(mot))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: retirer) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(survol ? j.texte : j.texteSecondaire)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(survol ? Color.white.opacity(j.schema == .dark ? 0.12 : 0.7) : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { survol = $0 }
            .help("Retirer « \(mot) »")
            .accessibilityLabel("Retirer \(mot)")
        }
        .font(Font.jakarta(max(11, j.taille(.legende)), graisse: 540))
        .foregroundStyle(j.texte)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(Capsule().fill(refuse ? j.alerte.opacity(sombre ? 0.24 : 0.13) : j.fondDoux))
        .overlay(Capsule().strokeBorder(refuse ? j.alerte.opacity(sombre ? 0.4 : 0.28) : j.trait, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .animation(j.anim(.survol), value: survol)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(refuse ? "\(AccentsRegles.afficher(mot)), refusé" : "\(AccentsRegles.afficher(mot)), signalé")
    }
}

/// Le moteur garde ses listes d'origine sans accents (`moteur/regles.py`) et compare toujours sans accents :
/// on montre ici la forme française correcte, sans changer ce qui est enregistré.
enum AccentsRegles {
    private static let table: [String: String] = [
        "fees": "fées", "ames": "âmes", "ame": "âme", "soeurs": "sœurs", "soeur": "sœur",
        "feerique": "féerique", "feeriques": "féeriques", "parenthese": "parenthèse", "enchantee": "enchantée",
        "reve": "rêve", "etoiles": "étoiles", "reservez": "réservez", "reserve": "réserve",
        "dernieres": "dernières", "derniere": "dernière", "hesitez": "hésitez", "hesite": "hésite",
        "disponibilites": "disponibilités", "elegant": "élégant", "elegante": "élégante", "elegants": "élégants",
        "elegantes": "élégantes", "elegance": "élégance", "editorial": "éditorial", "editoriale": "éditoriale",
        "editoriales": "éditoriales", "editoriaux": "éditoriaux", "authenticite": "authenticité",
        "sophistique": "sophistiqué", "sophistiquee": "sophistiquée", "sophistiques": "sophistiqués",
        "sophistiquees": "sophistiquées", "mariee": "mariée", "etait": "était",
    ]

    /// « conte de fees » → « conte de fées », « n'hesitez pas » → « n'hésitez pas », « #mariee » → « #mariée ».
    static func afficher(_ mot: String) -> String {
        var sortie = ""
        var courant = ""
        func vider() {
            sortie += table[courant] ?? courant
            courant = ""
        }
        for c in mot {
            if c.isLetter { courant.append(c) } else { vider(); sortie.append(c) }
        }
        vider()
        return sortie.trimmingCharacters(in: .whitespaces)
    }

    /// Pour repérer un doublon, accents et casse ignorés.
    static func cle(_ mot: String) -> String {
        mot.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe")
    }
}
