import Charts
import SwiftUI

// Écran « Statistiques » (DESIGN.md §4.8) : grand titre, résumé en voix de Claude, chiffres clés animés,
// graphiques Charts aux couleurs de l'ambiance (abonnés, ce qui porte / ce qui freine, variété des piliers),
// publications récentes, « Ce que le studio a retenu » (apprentissages et goûts modifiables),
// pilule « Faire le bilan maintenant » (→ `lancerClaude(.bilan)`). États vides honnêtes.

struct VueStatistiques: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var charge = false
    @Local private var apparu = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: j.esp.sections) {
                EnTeteEcran(surTitre: "Le studio", titre: "Statistiques",
                            chapo: "Ce que tes publications ont donné, et ce que le studio en retient. L'identité passe toujours avant la portée.") {
                    Button {
                        Task { await etat.lancerClaude(.bilan) }
                    } label: {
                        Label("Faire le bilan maintenant", systemImage: "chart.bar.doc.horizontal")
                    }
                    .buttonStyle(.pilule(.sombre, enCours: etat.lancementEnCours))
                    .disabled(etat.lancementEnCours || etat.claudeTravaille)
                    .help("Claude relit les chiffres de la semaine et met à jour ce qu'il a appris.")
                }
                if let e = activiteBilan {
                    CarteActiviteClaude(execution: e, arreter: { Task { await etat.annulerClaude() } })
                        .frame(maxWidth: 640)
                        .transition(j.transition(.apparition))
                }
                contenu
            }
            .animation(j.anim(.doux), value: activiteBilan?.etat)
            .frame(maxWidth: j.esp.largeurPage, alignment: .leading)
            .padding(j.esp.page)
            .frame(maxWidth: .infinity)
        }
        .task {
            await etat.chargerMemoire()
            if etat.instagram == nil { await etat.chargerInstagram(silencieux: true) }
            withAnimation(j.anim(.doux)) { charge = true }
            try? await Task.sleep(nanoseconds: 150_000_000)
            apparu = true
        }
    }

    /// Le bilan en cours, ou fini il y a moins d'un quart d'heure.
    private var activiteBilan: ExecutionClaude? {
        guard let e = etat.execution, e.tacheClaude == .bilan else { return nil }
        if e.enCours { return e }
        if e.terminee, let fin = e.dateFin, Date().timeIntervalSince(fin) < 15 * 60 { return e }
        return nil
    }

    @ViewBuilder private var contenu: some View {
        if let m = etat.memoire {
            let r = m.resume
            let historique = m.historique ?? []
            let mesurees = r?.mesurees ?? 0

            Carte(titre: "Le mot de Claude", symbole: "sparkles") {
                VoixDeClaude(StatsTexte.resume(m, instagram: etat.instagram))
                    .frame(maxWidth: j.esp.largeurTexte, alignment: .leading)
            }
            .entreeEnCascade(3)

            if etat.instagram?.connecte == false {
                instagramAbsent.entreeEnCascade(4)
            }

            if mesurees == 0 && historique.isEmpty {
                // La carte Instagram dit déjà pourquoi il n'y a rien : pas de deuxième état vide.
                if etat.instagram?.connecte != false {
                    aucunePublication.entreeEnCascade(5)
                }
            } else {
                chiffres(m).entreeEnCascade(5)
                graphiques(m).entreeEnCascade(6)
                if !historique.isEmpty {
                    publicationsRecentes(historique).entreeEnCascade(7)
                }
            }

            retenu(m).entreeEnCascade(8)
        } else if !charge {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(j.esp.sections)
        } else {
            EtatVide(symbole: "chart.line.uptrend.xyaxis", titre: "Les statistiques n'ont pas pu être lues",
                     phrase: "Réessaie dans un instant : le studio relit ses chiffres.",
                     actionTitre: "Réessayer", action: { Task { await etat.chargerMemoire() } })
        }
    }

    // MARK: États vides

    private var instagramAbsent: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous)
        return HStack(spacing: j.esp.carte) {
            Illustration(.instagram, taille: 120)
            VStack(alignment: .leading, spacing: j.esp.pile) {
                Text("Instagram n'est pas relié au studio").typo(.titre3)
                Text("Sans lui, Claude ne peut pas relever les vues, les enregistrements ni les abonnés. Relie ton compte dans les Réglages : les chiffres arriveront dès le lendemain matin.")
                    .typo(.corps)
                    .fixedSize(horizontal: false, vertical: true)
                Button { etat.montrer(.reglages) } label: {
                    Label("Relier mon compte", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.pilule(.claire, taille: .petite))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(j.esp.carte)
        .background(forme.fill(j.fondAlerte))
        .overlay(LisereHaut(rayon: j.rayons.carte))
        .ombre(.carte)
        .accessibilityElement(children: .contain)
    }

    /// État vide compact (même gabarit que la carte Instagram) : il tient dans la page sans pousser le reste.
    private var aucunePublication: some View {
        Carte {
            HStack(spacing: j.esp.carte) {
                Illustration(.attente, taille: 120)
                VStack(alignment: .leading, spacing: j.esp.pile) {
                    Text("Pas encore de chiffres").typo(.titre3)
                    Text("Les statistiques arrivent quelques jours après ta première publication : Claude les relève chaque matin et en tire des leçons le dimanche.")
                        .typo(.corps)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Chiffres clés

    private func chiffres(_ m: Memoire) -> some View {
        let r = m.resume
        let mesurees = Double(r?.mesurees ?? 0)
        let points = StatsTexte.pointsAbonnes(r?.abonnes, instagram: etat.instagram)
        let abonnes = points.last.map { Double($0.valeur) }
        let ecartAbonnes: Int? = points.count >= 2 ? points.last!.valeur - points.first!.valeur : nil
        let enregistrements = r?.moyennes?["taux_enregistrement"].map { $0 * 100 }
        let partages = r?.moyennes?["taux_partage"].map { $0 * 100 }
        let unChiffre: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(1))

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: j.esp.gouttiere)], spacing: j.esp.gouttiere) {
            Carte {
                ChiffreCle(valeur: apparu ? mesurees : 0, libelle: "Publications mesurées")
            }
            Carte {
                ChiffreCle(valeur: apparu ? (abonnes ?? 0) : 0, libelle: "Abonnés",
                           texte: abonnes == nil ? "—" : nil,
                           ecart: ecartAbonnes.map { "\($0 >= 0 ? "+" : "")\($0) depuis le \(StatsTexte.jourCourt(points.first!.date))" },
                           ecartPositif: (ecartAbonnes ?? 0) >= 0)
            }
            Carte {
                ChiffreCle(valeur: apparu ? (enregistrements ?? 0) : 0, libelle: "Enregistrements pour 100 personnes",
                           texte: enregistrements == nil ? "—" : nil, format: unChiffre)
            }
            Carte {
                ChiffreCle(valeur: apparu ? (partages ?? 0) : 0, libelle: "Partages pour 100 personnes",
                           texte: partages == nil ? "—" : nil, format: unChiffre)
            }
        }
    }

    // MARK: Graphiques

    private func graphiques(_ m: Memoire) -> some View {
        let r = m.resume
        let points = StatsTexte.pointsAbonnes(r?.abonnes, instagram: etat.instagram)
        let constats = StatsTexte.barres(fonctionne: r?.fonctionne ?? [], freine: r?.a_ameliorer ?? [])
        let piliers = StatsTexte.piliers(m.historique ?? [])

        return VStack(alignment: .leading, spacing: j.esp.gouttiere) {
            HStack(alignment: .top, spacing: j.esp.gouttiere) {
                Carte(titre: "Abonnés", symbole: "person.2") {
                    GraphiqueAbonnes(points: points)
                }
                Carte(titre: "Variété des piliers", symbole: "circle.grid.cross") {
                    GraphiquePiliers(parts: piliers)
                }
            }
            Carte(titre: "Ce qui porte, ce qui freine", symbole: "arrow.up.arrow.down") {
                GraphiqueConstats(barres: constats, mesurees: r?.mesurees ?? 0)
            }
        }
    }

    // MARK: Publications récentes

    private func publicationsRecentes(_ posts: [PostHistorique]) -> some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            Text("Publications récentes").typo(.titre3).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: j.esp.gouttiere, alignment: .top)],
                      alignment: .leading, spacing: j.esp.gouttiere) {
                ForEach(posts.prefix(12)) { p in VignettePublication(post: p) }
            }
        }
    }

    // MARK: Ce que le studio a retenu

    private func retenu(_ m: Memoire) -> some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ce que le studio a retenu").typo(.titre2).accessibilityAddTraits(.isHeader)
                Text("Claude s'en sert pour chaque idée et chaque légende. Tu peux corriger ce qui ne te ressemble pas.")
                    .typo(.chapo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: j.esp.gouttiere) {
                CarteMemoire(titre: "Apprentissages", symbole: "lightbulb",
                             aide: "Réécrits chaque dimanche par le bilan.", nom: "apprentissages", texte: m.apprentissages)
                CarteMemoire(titre: "Tes goûts", symbole: "heart",
                             aide: "Ce que Claude a compris de tes choix et de tes retouches.", nom: "gouts", texte: m.gouts)
            }
        }
        .padding(.top, j.esp.pile)
    }
}

// MARK: - Graphiques

private struct PointAbonne: Identifiable {
    var id: Date { date }
    let date: Date
    let valeur: Int
}

private struct GraphiqueAbonnes: View {
    let points: [PointAbonne]
    @Environment(\.jetons) private var j

    var body: some View {
        if points.count < 2 {
            texteVide(points.isEmpty
                      ? "La courbe se dessinera dès que Claude aura relevé tes abonnés deux fois."
                      : "Un seul relevé pour l'instant (\(points[0].valeur) abonnés) : la courbe apparaît au deuxième.")
        } else {
            Chart(points) { p in
                AreaMark(x: .value("Jour", p.date), y: .value("Abonnés", p.valeur))
                    .foregroundStyle(LinearGradient(colors: [j.accent.opacity(0.18), j.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Jour", p.date), y: .value("Abonnés", p.valeur))
                    .foregroundStyle(j.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Jour", p.date), y: .value("Abonnés", p.valeur))
                    .foregroundStyle(j.accent)
                    .symbolSize(28)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(j.police(.legende))
                        .foregroundStyle(j.texteSecondaire)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().font(j.police(.legende)).foregroundStyle(j.texteSecondaire)
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Abonnés : de \(points.first!.valeur) à \(points.last!.valeur)")
        }
    }

    private func texteVide(_ t: String) -> some View {
        Text(t).typo(.legende).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }
}

private struct BarreConstat: Identifiable {
    var id: String { libelle }
    let libelle: String
    let ecart: Double
    let detail: String
}

private struct GraphiqueConstats: View {
    let barres: [BarreConstat]
    let mesurees: Int
    @Environment(\.jetons) private var j

    var body: some View {
        if barres.isEmpty {
            Text(mesurees < 3
                 ? "Il faut au moins trois publications mesurées pour comparer : pour l'instant, Claude observe."
                 : "Rien de net pour l'instant : aucune différence ne ressort assez pour en tirer une leçon.")
                .typo(.legende)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let borne = max(0.15, barres.map { abs($0.ecart) }.max() ?? 0.15) * 1.25
            VStack(alignment: .leading, spacing: j.esp.pile) {
                HStack(spacing: 6) {
                    Pastille("Ce qui porte", symbole: "arrow.up.right", ton: .douce)
                    Pastille("Ce qui freine", symbole: "arrow.down.right", ton: .alerte)
                    Spacer(minLength: 0)
                    Text("Écart au post moyen").typo(.legende)
                }
                Chart(barres) { b in
                    BarMark(x: .value("Écart", b.ecart), y: .value("Constat", b.libelle), height: .fixed(16))
                        .foregroundStyle(b.ecart >= 0 ? j.accent : j.alerte.opacity(0.7))
                        .clipShape(Capsule())
                        .annotation(position: b.ecart >= 0 ? .trailing : .leading, spacing: 6) {
                            Text(b.detail).font(j.police(.legende)).foregroundStyle(j.texteSecondaire)
                        }
                    RuleMark(x: .value("Moyenne", 0))
                        .foregroundStyle(j.traitFort)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXScale(domain: -borne...borne)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(j.police(.corps)).foregroundStyle(j.texte)
                    }
                }
                .frame(height: CGFloat(barres.count) * 34 + 12)
            }
        }
    }
}

private struct PartPilier: Identifiable {
    var id: String { nom }
    let nom: String
    let nombre: Int
}

private struct GraphiquePiliers: View {
    let parts: [PartPilier]
    @Environment(\.jetons) private var j

    private var couleurs: [Color] {
        var c: [Color] = j.couleurs.taches
        c += [j.accent, j.accentDoux, j.accent.opacity(0.55), j.texteSecondaire.opacity(0.5)]
        return c
    }

    private func couleur(_ i: Int) -> Color { couleurs[i % couleurs.count] }

    var body: some View {
        if parts.isEmpty {
            Text("Le cercle se remplira avec tes premières publications.")
                .typo(.legende)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: j.esp.carte) {
                donut
                legende
            }
            .frame(minHeight: 150)
        }
    }

    private var total: Int { parts.reduce(0) { $0 + $1.nombre } }

    private var donut: some View {
        let noms: [String] = parts.map { $0.nom }
        let teintes: [Color] = parts.indices.map { couleur($0) }
        return Chart(parts) { (p: PartPilier) in
            SectorMark(angle: .value("Publications", p.nombre), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(by: .value("Pilier", p.nom))
        }
        .chartForegroundStyleScale(domain: noms, range: teintes)
        .chartLegend(.hidden)
        .overlay { centre }
        .frame(width: 150, height: 150)
        .accessibilityLabel("\(parts.count) piliers sur \(total) publications")
    }

    private var centre: some View {
        VStack(spacing: 0) {
            Text("\(parts.count)").font(Font.jakarta(26, graisse: 330)).foregroundStyle(j.texte)
            Text(parts.count > 1 ? "piliers" : "pilier").typo(.legende)
        }
    }

    private var legende: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                ligne(p, teinte: couleur(i))
            }
            Text(StatsTexte.conseilPiliers(parts, total: total)).typo(.legende)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func ligne(_ p: PartPilier, teinte: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(teinte).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(j.trait, lineWidth: 0.5))
            Text(p.nom).typo(.corps).lineLimit(1)
            Spacer(minLength: 6)
            Text("\(p.nombre)").typo(.legende).monospacedDigit()
        }
    }
}

// MARK: - Publications récentes

private struct VignettePublication: View {
    let post: PostHistorique
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if post.couverture != nil {
                    ImageLocale(chemin: post.couverture, revelation: true)
                } else {
                    ZStack {
                        j.fondDoux
                        Image(systemName: StatsTexte.symboleFormat(post.format))
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(j.texteSecondaire)
                    }
                }
            }
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
            .survol(.photo)

            Text(StatsTexte.jourLong(post.date)).typo(.legende)
            if let t = post.titre, !t.isEmpty {
                Text(t).typo(.corpsFort).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let p = post.pilier, !p.isEmpty { Pastille(p, ton: .neutre) }
            if let l = post.permalink, let url = URL(string: l) {
                Link(destination: url) { Label("Voir sur Instagram", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.discret)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Mémoire modifiable

private struct CarteMemoire: View {
    let titre: String
    let symbole: String
    let aide: String
    let nom: String
    let texte: String
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var edition = false
    @Local private var brouillon = ""
    @Local private var enregistrement = false
    @Local private var enregistre = false

    var body: some View {
        Carte(titre: titre, symbole: symbole) {
            Text(aide).typo(.legende)
            if edition {
                ChampDoux(texte: $brouillon, exemple: "Une ligne par idée, commencée par « - ».", lignes: 10...26)
                HStack(spacing: 8) {
                    Button { enregistrer() } label: { Label("Enregistrer", systemImage: "checkmark") }
                        .buttonStyle(.pilule(.accent, taille: .petite, enCours: enregistrement))
                        .disabled(enregistrement || brouillon == texte)
                    Button("Annuler") { withAnimation(j.anim(.doux)) { edition = false } }
                        .buttonStyle(.pilule(.claire, taille: .petite))
                }
            } else {
                TexteMemoire(texte: texte)
                HStack(spacing: 10) {
                    Button {
                        brouillon = texte
                        withAnimation(j.anim(.doux)) { edition = true }
                    } label: { Label("Modifier", systemImage: "pencil.line") }
                        .buttonStyle(.pilule(.claire, taille: .petite))
                    if enregistre {
                        Label("Enregistré", systemImage: "checkmark.circle.fill")
                            .typo(.legende, couleur: j.succes)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func enregistrer() {
        let t = brouillon
        enregistrement = true
        Task {
            let ok = await etat.envoyerTexte(t, action: "enregistrer-memoire", avant: [nom])
            enregistrement = false
            if ok {
                await etat.chargerMemoire()
                withAnimation(j.anim(.doux)) {
                    edition = false
                    enregistre = true
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(j.anim(.doux)) { enregistre = false }
            }
        }
    }
}

/// Lecture douce d'un petit Markdown : titres de section, puces, paragraphes (le titre principal est omis).
private struct TexteMemoire: View {
    let texte: String
    @Environment(\.jetons) private var j

    private enum Bloc: Identifiable {
        case section(Int, String), puce(Int, String), paragraphe(Int, String)
        var id: Int {
            switch self { case .section(let i, _), .puce(let i, _), .paragraphe(let i, _): return i }
        }
    }

    private var blocs: [Bloc] {
        var r: [Bloc] = []
        for (i, brute) in texte.components(separatedBy: .newlines).enumerated() {
            let l = brute.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("# ") || l == "---" { continue }
            if l.hasPrefix("#") {
                r.append(.section(i, l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if l.hasPrefix("- ") || l.hasPrefix("* ") {
                r.append(.puce(i, String(l.dropFirst(2))))
            } else {
                r.append(.paragraphe(i, l))
            }
        }
        return r
    }

    var body: some View {
        let b = blocs
        VStack(alignment: .leading, spacing: 6) {
            if b.isEmpty {
                Text("Rien pour l'instant : le studio apprendra au fil de tes choix.").typo(.legende)
            }
            ForEach(b) { bloc in
                switch bloc {
                case .section(_, let t):
                    Text(t).typo(.corpsFort).padding(.top, 6)
                case .puce(_, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(j.accent).frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(enLigne(t)).typo(.corps).fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraphe(_, let t):
                    Text(enLigne(t)).typo(.legende).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func enLigne(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

// MARK: - Textes et calculs

private enum StatsTexte {
    static let dimensions = ["pilier": "Pilier", "format": "Format", "tonalite": "Couverture", "luminosite": "Luminosité",
                             "plan": "Plan de couverture", "sujet": "Sujet de couverture", "longueur_legende": "Légende",
                             "jour_semaine": "Jour", "heure": "Heure", "taille_carrousel": "Carrousel de",
                             "collaboration": "Collaboration"]

    static let piliersConnus = ["EDITORIAL": "Éditorial", "DOCUMENTARY": "Documentaire", "DETAILS": "Détails",
                                "PLACES": "Lieux", "PORTRAITS": "Portraits", "LOVE_STORY": "Love story",
                                "ATMOSPHERE": "Atmosphère", "ARTISTIC_VISION": "Vision artistique"]

    static let formats = ["carrousel": "Carrousel", "image": "Image seule", "reel": "Reel"]

    static func valeurLisible(_ dimension: String?, _ valeur: String?) -> String {
        let v = valeur ?? ""
        if dimension == "pilier", let p = piliersConnus[v] { return p }
        if dimension == "format", let f = formats[v] { return f }
        return v.replacingOccurrences(of: "_", with: " ")
    }

    static func libelle(_ c: Constat) -> String {
        let d = dimensions[c.dimension ?? ""] ?? (c.dimension ?? "")
        return "\(d) « \(valeurLisible(c.dimension, c.valeur)) »"
    }

    static func barres(fonctionne: [Constat], freine: [Constat]) -> [BarreConstat] {
        let tous = fonctionne.prefix(5) + freine.prefix(5)
        var vus = Set<String>()
        return tous.compactMap { c in
            let l = libelle(c)
            guard let e = c.ecart, vus.insert(l).inserted else { return nil }
            let n = c.n ?? 0
            return BarreConstat(libelle: l, ecart: e, detail: "\(n) post\(n > 1 ? "s" : "") · \(c.confiance ?? "")")
        }
        .sorted { $0.ecart > $1.ecart }
    }

    static func piliers(_ posts: [PostHistorique]) -> [PartPilier] {
        var compte: [String: Int] = [:]
        for p in posts {
            let brut = (p.pilier ?? "").trimmingCharacters(in: .whitespaces)
            let nom = brut.isEmpty ? "Sans pilier" : (piliersConnus[brut] ?? brut)
            compte[nom, default: 0] += 1
        }
        return compte.map { PartPilier(nom: $0.key, nombre: $0.value) }
            .sorted { $0.nombre != $1.nombre ? $0.nombre > $1.nombre : $0.nom < $1.nom }
    }

    static func conseilPiliers(_ parts: [PartPilier], total: Int) -> String {
        guard let premier = parts.first, total > 0 else { return "" }
        if parts.count == 1 { return "Un seul pilier pour l'instant : le feed gagnera à varier." }
        if Double(premier.nombre) / Double(total) > 0.5 {
            return "« \(premier.nom) » revient souvent : Claude variera davantage."
        }
        return "Un feed bien varié, sur \(total) publications."
    }

    static func pointsAbonnes(_ a: Abonnes?, instagram: InstagramEtat?) -> [PointAbonne] {
        var points: [PointAbonne] = []
        for p in [a?.debut, a?.fin] {
            if let p, let v = p.abonnes, let d = p.jour.flatMap(date) { points.append(PointAbonne(date: d, valeur: v)) }
        }
        if let i = instagram, i.connecte, let v = i.abonnes {
            let aujourdhui = Calendar.current.startOfDay(for: Date())
            if points.last.map({ $0.date < aujourdhui }) ?? true {
                points.append(PointAbonne(date: aujourdhui, valeur: v))
            }
        }
        var vus = Set<Date>()
        return points.filter { vus.insert($0.date).inserted }.sorted { $0.date < $1.date }
    }

    static func resume(_ m: Memoire, instagram: InstagramEtat?) -> String {
        let r = m.resume
        let n = r?.mesurees ?? 0
        let historique = m.historique ?? []
        if n == 0 {
            if instagram?.connecte == false {
                return "Je n'ai encore rien à mesurer : Instagram n'est pas relié au studio. Dès qu'il le sera, je relèverai les chiffres de chaque publication."
            }
            if historique.isEmpty {
                return "Rien à mesurer pour l'instant. Les chiffres arrivent quelques jours après ta première publication ; je te dirai alors ce qui porte et ce qui freine."
            }
            return r?.message ?? "Tes publications sont trop récentes pour être mesurées : j'observe encore."
        }
        if n < 3 {
            return r?.message ?? "\(n) publication\(n > 1 ? "s" : "") mesurée\(n > 1 ? "s" : ""), c'est encore peu pour comparer : j'observe."
        }
        var phrases = ["Sur \(n) publications mesurées,"]
        if let haut = r?.fonctionne?.first {
            phrases[0] += " ce qui porte le plus : \(libelle(haut).lowercasedPremier)."
        } else {
            phrases[0] += " rien ne ressort encore nettement."
        }
        if let bas = r?.a_ameliorer?.first {
            phrases.append("Ce qui freine : \(libelle(bas).lowercasedPremier).")
        }
        let points = pointsAbonnes(r?.abonnes, instagram: instagram)
        if points.count >= 2, let a = points.first, let b = points.last {
            let d = b.valeur - a.valeur
            if d > 0 { phrases.append("Tu as gagné \(d) abonné\(d > 1 ? "s" : "") depuis le \(jourCourt(a.date)).") }
            else if d < 0 { phrases.append("Tu as perdu \(-d) abonné\(d < -1 ? "s" : "") depuis le \(jourCourt(a.date)), rien d'alarmant.") }
        }
        phrases.append("Ce sont des pistes, pas des lois : ta charte passe avant.")
        return phrases.joined(separator: " ")
    }

    static func symboleFormat(_ f: String?) -> String {
        switch f {
        case "reel": return "play.rectangle"
        case "image": return "photo"
        default: return "square.on.square"
        }
    }

    private static let lecteur: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let court: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let long: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static func date(_ texte: String) -> Date? { lecteur.date(from: String(texte.prefix(10))) }

    static func jourCourt(_ d: Date) -> String { court.string(from: d) }

    static func jourLong(_ texte: String?) -> String {
        guard let t = texte, let d = date(t) else { return texte ?? "" }
        let s = long.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

private extension String {
    /// « Pilier « Lieux » » → « pilier « Lieux » » (seule la première lettre).
    var lowercasedPremier: String { prefix(1).lowercased() + dropFirst() }
}
