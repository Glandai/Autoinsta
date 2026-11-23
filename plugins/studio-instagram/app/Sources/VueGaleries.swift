import AppKit
import SwiftUI

// Écran « Galeries » (DESIGN.md §4.7) : grand titre léger, pilule « Ajouter une galerie » (⇧⌘N : ⌘N reste le « + »),
// grille de séries en cartes douces (mosaïque de vignettes, lieu, type et date, progression de la lecture par Claude,
// photos fortes, état), actions (Analyser avec Claude, Modifier, Relire les photos, Retirer du studio…),
// une seule pilule sombre par écran (celle de l'en-tête) : dans les cartes, pilule claire et lien discret,
// fiche d'ajout ou d'édition en feuille, une étape à la fois.

struct VueGaleries: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var fiche: FicheOuverte?
    @Local private var aRetirer: Galerie?
    @Local private var charge = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: j.esp.sections) {
                EnTeteEcran(surTitre: "Le studio", titre: "Galeries",
                            chapo: "Chaque galerie est une série : un mariage, un shooting. Claude ne raconte que ce qui est écrit ici.") {
                    if !etat.galeries.isEmpty {
                        Button { ouvrir(Galerie.nouvelle(), nouvelle: true) } label: {
                            Label("Ajouter une galerie", systemImage: "plus")
                        }
                        .buttonStyle(.pilule)
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                        .help("Ajouter une galerie (⇧⌘N)")
                    }
                }
                contenu
            }
            .frame(maxWidth: j.esp.largeurPage, alignment: .leading)
            .padding(j.esp.page)
            .frame(maxWidth: .infinity)
        }
        .task {
            await etat.chargerGaleries()
            withAnimation(j.anim(.doux)) { charge = true }
        }
        .sheet(item: $fiche) { f in
            FicheGalerie(galerie: f.galerie, nouvelle: f.nouvelle) { fiche = nil }
                .environmentObject(etat)
        }
        .alert("Retirer cette galerie du studio ?",
               isPresented: Binding(get: { aRetirer != nil }, set: { if !$0 { aRetirer = nil } })) {
            Button("Retirer du studio", role: .destructive) {
                if let g = aRetirer { Task { await etat.supprimerGalerie(g.id) } }
                aRetirer = nil
            }
            Button("Annuler", role: .cancel) { aRetirer = nil }
        } message: {
            Text("Claude ne s'en servira plus pour tes posts. Tes photos d'origine ne sont pas touchées, et tu pourras la rajouter plus tard.")
        }
    }

    @ViewBuilder private var contenu: some View {
        if etat.galeries.isEmpty {
            if charge {
                videAccueillant
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(j.esp.sections)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: j.esp.gouttiere, alignment: .top)],
                      alignment: .leading, spacing: j.esp.gouttiere) {
                ForEach(Array(etat.galeries.enumerated()), id: \.element.id) { i, g in
                    CarteGalerie(galerie: g,
                                 modifier: { ouvrir(g, nouvelle: false) },
                                 retirer: { aRetirer = g })
                        .entreeEnCascade(i + 3)
                }
            }
        }
    }

    /// État vide accueillant : illustration, texte 8, une seule action.
    private var videAccueillant: some View {
        VStack(spacing: j.esp.blocs) {
            Illustration(.photos, taille: 230)
                .entreeEnCascade(0)
            Text("Aucune galerie pour l'instant")
                .typo(.titre2)
                .multilineTextAlignment(.center)
                .entreeEnCascade(1)
            Text("Colle un lien Pic-Time ou glisse un dossier : Claude s'occupe du reste.")
                .typo(.chapo)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .entreeEnCascade(2)
            Button { ouvrir(Galerie.nouvelle(), nouvelle: true) } label: {
                Label("Ajouter une galerie", systemImage: "plus")
            }
            .buttonStyle(.principal)
            .keyboardShortcut(.defaultAction)
            .padding(.top, j.esp.pile)
            .entreeEnCascade(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, j.esp.sections)
    }

    private func ouvrir(_ g: Galerie, nouvelle: Bool) {
        fiche = FicheOuverte(galerie: g, nouvelle: nouvelle)
    }
}

/// Une feuille ouverte (la galerie nouvelle a un identifiant vide : elle ne peut pas servir d'`id`).
private struct FicheOuverte: Identifiable {
    let id = UUID()
    let galerie: Galerie
    let nouvelle: Bool
}

// MARK: - Carte d'une série

private struct CarteGalerie: View {
    let galerie: Galerie
    let modifier: () -> Void
    let retirer: () -> Void
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local private var vignettes: [String] = []
    @Local private var survol = false

    private var photos: Int { galerie.photos ?? 0 }
    private var lues: Int { min(galerie.analysees ?? 0, max(photos, galerie.analysees ?? 0)) }
    private var resteALire: Bool { photos > 0 && lues < photos }

    /// L'exécution de Claude qui concerne cette série (en cours, ou finie il y a moins d'un quart d'heure).
    private var activite: ExecutionClaude? {
        guard let e = etat.execution, e.tacheClaude == .galerie, e.serie == galerie.id else { return nil }
        if e.enCours { return e }
        if e.terminee, let fin = e.dateFin, Date().timeIntervalSince(fin) < 15 * 60 { return e }
        return nil
    }

    var body: some View {
        Carte(style: .cliquable) {
            VStack(alignment: .leading, spacing: j.esp.blocs) {
                MosaiqueGalerie(chemins: vignettes, symbole: GalerieTexte.symboleType(galerie.type))
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await etat.ouvrirPostDeSerie(galerie.id) } }
                    .help("Voir l'aperçu du post fait avec ces photos")
                enTete
                progression
                pastilles
                if let e = activite {
                    CarteActiviteClaude(execution: e, compacte: true, cadre: false,
                                        arreter: { Task { await etat.annulerClaude() } })
                        .padding(.top, 2)
                        .transition(j.transition(.apparition))
                } else {
                    actions
                }
            }
            .animation(j.anim(.doux), value: activite?.etat)
        }
        .onHover { s in withAnimation(j.anim(.survol)) { survol = s } }
        .onTapGesture(count: 2) { modifier() }
        .contextMenu { menuActions }
        .task(id: "\(galerie.id)·\(photos)·\(lues)") {
            let lus = await LecteurVignettes.lire(dossier: etat.dossier, serie: galerie.id)
            if lus != vignettes { withAnimation(j.anim(.doux)) { vignettes = lus } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GalerieTexte.titre(galerie))
    }

    private var enTete: some View {
        HStack(alignment: .top, spacing: j.esp.pile) {
            VStack(alignment: .leading, spacing: 3) {
                Text(GalerieTexte.titre(galerie))
                    .typo(.titre2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(GalerieTexte.sousTitre(galerie)).typo(.legende).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu { menuActions } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(j.texte)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(survol ? j.surfaceElevee : Color.clear))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(survol ? 1 : 0)
            .allowsHitTesting(survol)
            .help("Plus d'actions")
            .accessibilityLabel("Plus d'actions")
        }
    }

    @ViewBuilder private var progression: some View {
        if photos > 0 {
            VStack(alignment: .leading, spacing: 6) {
                BarreLecture(fraction: Double(lues) / Double(max(photos, 1)))
                    .frame(height: 5)
                Text("\(lues) sur \(photos) photos lues par Claude").typo(.legende)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Photos pas encore lues : « Relire les photos » les fait apparaître.").typo(.legende)
        }
    }

    private var pastilles: some View {
        HStack(spacing: 6) {
            let e = GalerieTexte.etat(galerie)
            Pastille(e.texte, symbole: e.symbole, ton: e.ton)
            if resteALire {
                Pastille("À analyser", symbole: "exclamationmark.circle.fill", ton: .aToi)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: modifier) { Label("Modifier", systemImage: "pencil.line") }
                .buttonStyle(.discret)
                .fixedSize()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var menuActions: some View {
        Button { modifier() } label: { Label("Modifier", systemImage: "pencil.line") }
        Button { Task { await etat.indexerGalerie(galerie.id) } } label: {
            Label("Relire les photos", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(etat.occupe)
        Divider()
        Button(role: .destructive) { retirer() } label: { Label("Retirer du studio…", systemImage: "trash") }
    }
}

/// Barre fine d'accent : la part des photos lues par Claude.
private struct BarreLecture: View {
    let fraction: Double
    @Environment(\.jetons) private var j

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(j.accent.opacity(0.16))
                Capsule()
                    .fill(j.accent)
                    .frame(width: max(fraction > 0 ? 5 : 0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .animation(j.anim(.compteur), value: fraction)
        .accessibilityHidden(true)
    }
}

/// Mosaïque 3:2 : une grande vignette et deux petites (ou ce qu'il y a), coins `rayons.photo`.
private struct MosaiqueGalerie: View {
    let chemins: [String]
    let symbole: String
    @Environment(\.jetons) private var j

    var body: some View {
        let ecart: CGFloat = 3
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Group {
                switch chemins.count {
                case 0:
                    vide
                case 1:
                    ImageLocale(chemin: chemins[0], revelation: true)
                case 2:
                    HStack(spacing: ecart) {
                        ImageLocale(chemin: chemins[0], revelation: true).frame(width: (w - ecart) / 2, height: h)
                        ImageLocale(chemin: chemins[1], revelation: true).frame(width: (w - ecart) / 2, height: h)
                    }
                default:
                    HStack(spacing: ecart) {
                        ImageLocale(chemin: chemins[0], revelation: true)
                            .frame(width: (w - ecart) * 0.62, height: h)
                            .clipped()
                        VStack(spacing: ecart) {
                            ImageLocale(chemin: chemins[1], revelation: true).frame(height: (h - ecart) / 2).clipped()
                            ImageLocale(chemin: chemins[2], revelation: true).frame(height: (h - ecart) / 2).clipped()
                        }
                        .frame(width: (w - ecart) * 0.38, height: h)
                    }
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: j.rayons.photo, style: .continuous))
        .accessibilityHidden(true)
    }

    private var vide: some View {
        ZStack {
            j.fondDoux
            Image(systemName: symbole)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(j.texteSecondaire)
        }
    }
}

/// Lit (sans rien écrire) les vignettes d'une série dans `catalogue/<série>/photos.json` : les mieux notées d'abord.
private enum LecteurVignettes {
    private struct Fichier: Decodable { let photos: [Photo]? }
    private struct Photo: Decodable {
        let vignette: String?
        let mise_en_avant: Bool?
        let analyse: Analyse?
    }
    private struct Analyse: Decodable {
        let note: Double?
        enum CodingKeys: String, CodingKey { case note }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            note = (try? c.decode(Double.self, forKey: .note)) ?? (try? c.decode(String.self, forKey: .note)).flatMap(Double.init)
        }
    }

    static func lire(dossier: URL, serie: String, nombre: Int = 3) async -> [String] {
        guard !serie.isEmpty else { return [] }
        return await Task.detached(priority: .utility) { () -> [String] in
            let fm = FileManager.default
            let base = dossier.appendingPathComponent("catalogue", isDirectory: true)
                .appendingPathComponent(serie, isDirectory: true)
            var chemins: [String] = []
            if let data = try? Data(contentsOf: base.appendingPathComponent("photos.json")),
               let f = try? JSONDecoder().decode(Fichier.self, from: data), let photos = f.photos {
                let triees = photos.enumerated().sorted { a, b in
                    let ma = a.element.mise_en_avant == true, mb = b.element.mise_en_avant == true
                    if ma != mb { return ma }
                    let na = a.element.analyse?.note ?? 0, nb = b.element.analyse?.note ?? 0
                    if na != nb { return na > nb }
                    return a.offset < b.offset
                }
                for p in triees {
                    guard let v = p.element.vignette, !v.isEmpty else { continue }
                    let chemin = v.hasPrefix("/") ? v : base.appendingPathComponent(v).path
                    if fm.fileExists(atPath: chemin) { chemins.append(chemin) }
                    if chemins.count >= nombre { break }
                }
            }
            if chemins.isEmpty {
                let dossierVignettes = base.appendingPathComponent("vignettes", isDirectory: true)
                let noms = (try? fm.contentsOfDirectory(atPath: dossierVignettes.path)) ?? []
                chemins = noms.filter { $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".jpeg") }
                    .sorted()
                    .prefix(nombre)
                    .map { dossierVignettes.appendingPathComponent($0).path }
            }
            return chemins
        }.value
    }
}

/// Textes d'une galerie, en français simple.
private enum GalerieTexte {
    static func libelleType(_ t: String) -> String {
        switch t {
        case "mariage": return "Mariage"
        case "shooting": return "Shooting"
        case "editorial": return "Éditorial"
        default: return t.isEmpty ? "Série" : t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    static func symboleType(_ t: String) -> String {
        switch t {
        case "mariage": return "heart"
        case "editorial": return "newspaper"
        default: return "camera"
        }
    }

    static func titre(_ g: Galerie) -> String {
        if !g.lieu.trimmingCharacters(in: .whitespaces).isEmpty { return g.lieu }
        if !g.maries.prenoms.trimmingCharacters(in: .whitespaces).isEmpty { return g.maries.prenoms }
        let mots = g.id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return mots.isEmpty ? "Nouvelle galerie" : mots.prefix(1).uppercased() + mots.dropFirst()
    }

    static func sousTitre(_ g: Galerie) -> String {
        var morceaux = [libelleType(g.type)]
        if let d = dateLisible(g.date) { morceaux.append(d) } else { morceaux.append("date à préciser") }
        if !g.lieu.isEmpty, !g.maries.prenoms.isEmpty { morceaux.append(g.maries.prenoms) }
        return morceaux.joined(separator: " · ")
    }

    static func etat(_ g: Galerie) -> (texte: String, symbole: String, ton: TonPastille) {
        switch g.statut {
        case "pause": return ("En pause", "pause.circle.fill", .neutre)
        case "epuisee": return ("Tout est publié", "moon.zzz", .neutre)
        default: return ("Active", "checkmark.circle.fill", .succes)
        }
    }

    static let lecteurDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let afficheurDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static func date(_ texte: String) -> Date? { lecteurDate.date(from: String(texte.prefix(10))) }

    static func dateLisible(_ texte: String) -> String? { date(texte).map { afficheurDate.string(from: $0) } }

    /// « Mas de la Rose, Uzès » + 2026 → « mas-de-la-rose-uzes-2026 ».
    static func nomCourt(lieu: String, prenoms: String, date: String) -> String {
        let base = lieu.isEmpty ? prenoms : lieu
        let plie = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        var r = ""
        for c in plie.unicodeScalars {
            if CharacterSet.alphanumerics.contains(c) && c.isASCII { r.unicodeScalars.append(c) } else if !r.hasSuffix("-") { r += "-" }
        }
        r = r.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let mots = r.split(separator: "-").prefix(5).joined(separator: "-")
        let annee = String(date.prefix(4))
        if mots.isEmpty { return "" }
        return Int(annee) != nil ? "\(mots)-\(annee)" : mots
    }
}

// MARK: - Fiche d'ajout ou d'édition (feuille, une étape à la fois)

private enum EtapeFiche: Int, CaseIterable {
    case photos, serie, maries, recit, prestataires

    var titre: String {
        switch self {
        case .photos: return "Où sont les photos ?"
        case .serie: return "La série"
        case .maries: return "Les mariés"
        case .recit: return "Ce que tu veux raconter"
        case .prestataires: return "Les prestataires"
        }
    }

    var texte: String {
        switch self {
        case .photos: return "Colle le lien de la galerie Pic-Time, ou glisse le dossier des photos ici."
        case .serie: return "Le lieu, le type et la date : Claude les reprend tels quels, sans rien inventer."
        case .maries: return "Leurs prénoms n'apparaissent dans une légende que s'ils sont d'accord."
        case .recit: return "Le contexte et les anecdotes, avec tes mots : c'est la seule matière des récits."
        case .prestataires: return "Ceux que Claude peut citer et identifier. Seulement les comptes que tu connais."
        }
    }
}

private struct FicheGalerie: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j
    @Local var galerie: Galerie
    let nouvelle: Bool
    let fermer: () -> Void

    @Local private var etape: EtapeFiche = .photos
    @Local private var sens: Bool = true
    @Local private var nomTouche = false
    @Local private var changerNom = false
    @Local private var avance = false
    @Local private var enregistrement = false
    @Local private var survolDepot = false

    init(galerie: Galerie, nouvelle: Bool, fermer: @escaping () -> Void) {
        self._galerie = Local(initialValue: galerie)
        self.nouvelle = nouvelle
        self.fermer = fermer
    }

    private var derniere: Bool { etape == EtapeFiche.allCases.last }

    var body: some View {
        VStack(spacing: 0) {
            barreHaut
            ScrollView {
                VStack(alignment: .leading, spacing: j.esp.blocs + 4) {
                    VStack(alignment: .leading, spacing: j.esp.pile) {
                        Text("\(etape.rawValue + 1)").typo(.numero)
                        Text(titreEtape).typo(.titre2).accessibilityAddTraits(.isHeader)
                        Text(etape.texte).typo(.chapo).fixedSize(horizontal: false, vertical: true)
                    }
                    contenuEtape
                }
                .id(etape)
                .transition(j.transition(sens ? .suivante : .precedente))
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, j.esp.page)
                .padding(.vertical, j.esp.blocs)
                .frame(maxWidth: .infinity)
            }
            barreBas
        }
        .frame(width: 760, height: 680)
        .background(FondAmbiance(anime: false))
        .dropDestination(for: URL.self) { urls, _ in deposer(urls) } isTargeted: { survolDepot = $0 }
    }

    private var titreEtape: String {
        if etape == .maries && galerie.type != "mariage" { return "Les personnes photographiées" }
        return etape.titre
    }

    // MARK: Haut et bas

    private var barreHaut: some View {
        HStack(spacing: j.esp.blocs) {
            Button(action: fermer) { Image(systemName: "xmark") }
                .buttonStyle(.rond(.claire, diametre: 36))
                .keyboardShortcut(.cancelAction)
                .help("Fermer sans enregistrer (Échap)")
                .accessibilityLabel("Fermer")
            VStack(alignment: .leading, spacing: 2) {
                Text(nouvelle ? "Nouvelle galerie" : "Modifier la galerie").typo(.surtitre)
                Text(GalerieTexte.titre(galerie)).typo(.corpsFort).lineLimit(1)
            }
            Spacer()
            if !nouvelle {
                Button { enregistrer() } label: { Label("Enregistrer", systemImage: "checkmark") }
                    .buttonStyle(.pilule(.claire, taille: .petite, enCours: enregistrement))
                    .disabled(!valide || enregistrement)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var barreBas: some View {
        ZStack {
            PointsProgression(total: EtapeFiche.allCases.count, courant: etape.rawValue,
                              aller: { i in aller(EtapeFiche(rawValue: i) ?? .photos) })
            HStack {
                if etape != .photos {
                    Button { aller(EtapeFiche(rawValue: etape.rawValue - 1) ?? .photos) } label: {
                        Label("Retour", systemImage: "chevron.left")
                    }
                    .buttonStyle(.pilule(.claire))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if derniere {
                        Button { enregistrer() } label: {
                            Label(nouvelle ? "Ajouter la galerie" : "Enregistrer", systemImage: nouvelle ? "plus" : "checkmark")
                        }
                        .buttonStyle(.pilule(.sombre, taille: .grande, enCours: enregistrement))
                        .disabled(!valide || enregistrement)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button { aller(EtapeFiche(rawValue: etape.rawValue + 1) ?? .prestataires) } label: {
                            Label("Continuer", systemImage: "chevron.right")
                        }
                        .buttonStyle(.pilule(.sombre, taille: .grande))
                        .disabled(blocage != nil)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let b = blocage ?? (derniere && !valide ? "Il manque encore les photos ou le nom de la série." : nil) {
                Text(b).typo(.legende, couleur: j.texteSecondaire).offset(y: -22)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: Contenu des étapes

    @ViewBuilder private var contenuEtape: some View {
        switch etape {
        case .photos: etapePhotos
        case .serie: etapeSerie
        case .maries: etapeMaries
        case .recit: etapeRecit
        case .prestataires: etapePrestataires
        }
    }

    private var etapePhotos: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            HStack(spacing: j.esp.gouttiere) {
                choixSource("pictime", titre: "Un lien Pic-Time", symbole: "link", phrase: "La galerie client, en ligne.")
                choixSource("dossier", titre: "Un dossier sur ce Mac", symbole: "folder", phrase: "Des photos déjà exportées.")
            }
            if galerie.source.type == "pictime" {
                VStack(alignment: .leading, spacing: 6) {
                    ChampDoux(texte: $galerie.source.url, exemple: "https://….pic-time.com/…", lignes: 1...1)
                    Text("Le lien de partage de la galerie (celui qui contient « sectoken2 »). Claude ne voit que ce que tes clients voient.")
                        .typo(.legende)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                zoneDossier
            }
        }
    }

    private func choixSource(_ type: String, titre: String, symbole: String, phrase: String) -> some View {
        Button {
            withAnimation(j.anim(.selection)) { galerie.source.type = type }
        } label: {
            Carte(titre: titre, symbole: symbole, style: .cliquable, choisie: galerie.source.type == type) {
                Text(phrase).typo(.legende)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(galerie.source.type == type ? .isSelected : [])
    }

    private var zoneDossier: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.carte, style: .continuous)
        let chemin = galerie.source.chemin
        return VStack(spacing: j.esp.pile + 2) {
            Image(systemName: chemin.isEmpty ? "folder.badge.plus" : "folder.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(chemin.isEmpty ? j.texteSecondaire : j.accent)
            if chemin.isEmpty {
                Text("Glisse le dossier des photos ici").typo(.corpsFort)
                Text("ou choisis-le dans le Finder.").typo(.legende)
            } else {
                Text(URL(fileURLWithPath: chemin).lastPathComponent).typo(.corpsFort).lineLimit(1)
                Text(chemin).typo(.legende).lineLimit(1).truncationMode(.middle)
            }
            Button { if let p = choisirDossier() { galerie.source.chemin = p } } label: {
                Label(chemin.isEmpty ? "Choisir le dossier…" : "Changer de dossier…", systemImage: "folder")
            }
            .buttonStyle(.pilule(.claire, taille: .petite))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(j.esp.carte)
        .background(forme.fill(survolDepot ? j.fondDoux : j.remplissageCarte))
        .overlay(forme.strokeBorder(survolDepot ? j.accent : j.traitFort,
                                    style: StrokeStyle(lineWidth: survolDepot ? 2 : 1.2, dash: [6, 5])))
        .animation(j.anim(.survol), value: survolDepot)
    }

    private var etapeSerie: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs + 2) {
            ligne("Type") {
                HStack(spacing: 8) {
                    ForEach([("mariage", "Mariage"), ("shooting", "Shooting"), ("editorial", "Éditorial")], id: \.0) { t in
                        bascule(t.1, choisi: galerie.type == t.0) { galerie.type = t.0 }
                    }
                }
            }
            ligne("Lieu exact") {
                ChampDoux(texte: $galerie.lieu, exemple: "Mas de la Rose, Uzès", lignes: 1...1)
            }
            ligne("Date") { champDate }
            if nouvelle { nomCourt }
        }
        .onChange(of: galerie.lieu) { _, _ in nommer() }
        .onChange(of: galerie.date) { _, _ in nommer() }
    }

    @ViewBuilder private var champDate: some View {
        if let d = GalerieTexte.date(galerie.date) {
            HStack(spacing: 10) {
                DatePicker("", selection: Binding(get: { d }, set: { galerie.date = GalerieTexte.lecteurDate.string(from: $0) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                    .fixedSize()
                Text(GalerieTexte.dateLisible(galerie.date) ?? "").typo(.legende)
                Spacer(minLength: 0)
                Button("Retirer la date") { galerie.date = "" }.buttonStyle(.discret)
            }
        } else {
            Button { galerie.date = GalerieTexte.lecteurDate.string(from: Date()) } label: {
                Label("Ajouter la date", systemImage: "calendar")
            }
            .buttonStyle(.pilule(.claire, taille: .petite))
        }
    }

    private var nomCourt: some View {
        VStack(alignment: .leading, spacing: 6) {
            if changerNom {
                ligne("Nom court dans le studio") {
                    ChampDoux(texte: Binding(get: { galerie.id }, set: { galerie.id = $0; nomTouche = true }),
                              exemple: "mas-de-la-rose-2026", lignes: 1...1)
                }
            } else {
                HStack(spacing: 6) {
                    Text("Nom court dans le studio :").typo(.legende)
                    Text(galerie.id.isEmpty ? "il se remplit avec le lieu" : galerie.id)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(j.texteSecondaire)
                    Button("Changer") { changerNom = true }.buttonStyle(.discret)
                }
            }
        }
    }

    private var etapeMaries: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs + 2) {
            ligne(galerie.type == "mariage" ? "Leurs prénoms" : "Prénoms") {
                ChampDoux(texte: $galerie.maries.prenoms, exemple: "Léa & Hugo", lignes: 1...1)
            }
            Carte {
                Toggle(isOn: $galerie.maries.prenoms_publiables) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ils sont d'accord pour que leurs prénoms apparaissent dans les légendes").typo(.corpsFort)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(galerie.maries.prenoms_publiables
                             ? "Claude pourra écrire leurs prénoms."
                             : "Sans leur accord, Claude écrit « les mariés », jamais leurs prénoms.")
                            .typo(.legende)
                    }
                }
                .toggleStyle(.switch)
                .tint(j.accent)
            }
            if galerie.type != "mariage" {
                Text("Pas de mariés dans cette série ? Laisse vide et continue.").typo(.legende)
            }
        }
    }

    private var etapeRecit: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChampDoux(texte: $galerie.notes,
                      exemple: "Une cérémonie laïque sous les platanes, la grand-mère qui a cousu le voile, l'orage juste après le dîner…",
                      lignes: 7...14)
            Text("Claude n'invente rien d'autre : ce qui n'est pas écrit ici ne sera pas raconté.").typo(.legende)
        }
    }

    private var etapePrestataires: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            if galerie.prestataires.isEmpty {
                Text("Aucun prestataire pour l'instant.").typo(.legende)
            }
            ForEach($galerie.prestataires) { $p in
                HStack(spacing: 8) {
                    ChampDoux(texte: $p.role, exemple: "Fleuriste", lignes: 1...1).frame(width: 130)
                    ChampDoux(texte: $p.nom, exemple: "Nom", lignes: 1...1)
                    ChampDoux(texte: $p.compte, exemple: "compte (sans @)", lignes: 1...1)
                    Button {
                        withAnimation(j.anim(.doux)) { galerie.prestataires.removeAll { $0.id == p.id } }
                    } label: { Image(systemName: "minus") }
                        .buttonStyle(.rond(.claire, diametre: 30))
                        .help("Retirer ce prestataire")
                        .accessibilityLabel("Retirer \(p.nom.isEmpty ? "ce prestataire" : p.nom)")
                }
                .transition(j.transition(.apparition))
            }
            Button {
                withAnimation(j.anim(.doux)) { galerie.prestataires.append(Prestataire(role: "", nom: "", compte: "")) }
            } label: { Label("Ajouter un prestataire", systemImage: "plus") }
                .buttonStyle(.pilule(.claire, taille: .petite))

            avanceReplie.padding(.top, j.esp.blocs)
        }
    }

    private var avanceReplie: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            Button {
                withAnimation(j.anim(.doux)) { avance.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(avance ? 90 : 0))
                    Text("Réglages avancés").typo(.corpsFort)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(avance ? "ouvert" : "replié")

            if avance {
                VStack(alignment: .leading, spacing: j.esp.blocs) {
                    ligne("Consignes pour Claude") {
                        ChampDoux(texte: $galerie.consignes, exemple: "Thème, priorité, ce qu'il faut éviter…", lignes: 1...3)
                    }
                    ligne("État de la série") {
                        HStack(spacing: 8) {
                            ForEach([("active", "Active"), ("pause", "En pause"), ("epuisee", "Tout est publié")], id: \.0) { s in
                                bascule(s.1, choisi: galerie.statut == s.0) { galerie.statut = s.0 }
                            }
                        }
                    }
                    ligne("Exports pleine définition (facultatif)") {
                        HStack(spacing: 8) {
                            ChampDoux(texte: $galerie.exports_hd, exemple: "Dossier des exports", lignes: 1...1)
                            Button("Choisir…") { if let p = choisirDossier() { galerie.exports_hd = p } }
                                .buttonStyle(.pilule(.claire, taille: .petite))
                        }
                    }
                    ligne("Identifiant de lieu Facebook (facultatif)") {
                        ChampDoux(texte: $galerie.location_id, exemple: "110774245616525", lignes: 1...1)
                    }
                }
                .transition(j.transition(.apparition))
            }
        }
    }

    // MARK: Petites pièces

    private func ligne<C: View>(_ titre: String, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre).typo(.surtitre)
            contenu()
        }
    }

    private func bascule(_ titre: String, choisi: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(j.anim(.selection)) { action() }
        } label: {
            Text(titre)
        }
        .buttonStyle(.pilule(choisi ? .sombre : .claire, taille: .petite))
        .accessibilityAddTraits(choisi ? .isSelected : [])
    }

    // MARK: Logique

    /// Ce qui empêche de passer à l'étape suivante (en une phrase), ou nil.
    private var blocage: String? {
        switch etape {
        case .photos:
            if galerie.source.type == "pictime" {
                let u = galerie.source.url.trimmingCharacters(in: .whitespaces)
                if u.isEmpty { return "Colle le lien de la galerie pour continuer." }
                if !u.lowercased().hasPrefix("http") { return "Le lien doit commencer par https://" }
            } else if galerie.source.chemin.isEmpty {
                return "Choisis le dossier des photos pour continuer."
            }
            return nil
        case .serie:
            return galerie.id.trimmingCharacters(in: .whitespaces).isEmpty ? "Indique le lieu pour nommer la série." : nil
        default:
            return nil
        }
    }

    private var valide: Bool {
        let source = galerie.source.type == "pictime" ? !galerie.source.url.trimmingCharacters(in: .whitespaces).isEmpty
                                                      : !galerie.source.chemin.isEmpty
        return source && !galerie.id.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func aller(_ e: EtapeFiche) {
        guard e != etape else { return }
        sens = e.rawValue > etape.rawValue
        withAnimation(j.anim(.page)) { etape = e }
    }

    private func nommer() {
        guard nouvelle, !nomTouche else { return }
        galerie.id = GalerieTexte.nomCourt(lieu: galerie.lieu, prenoms: galerie.maries.prenoms, date: galerie.date)
    }

    private func deposer(_ urls: [URL]) -> Bool {
        guard let u = urls.first else { return false }
        if u.isFileURL {
            var dossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &dossier) else { return false }
            galerie.source.type = "dossier"
            galerie.source.chemin = dossier.boolValue ? u.path : u.deletingLastPathComponent().path
        } else {
            galerie.source.type = "pictime"
            galerie.source.url = u.absoluteString
        }
        if etape != .photos { aller(.photos) }
        return true
    }

    private func enregistrer() {
        guard valide, !enregistrement else { return }
        var g = galerie
        g.id = g.id.trimmingCharacters(in: .whitespaces)
        g.source.url = g.source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        g.prestataires = g.prestataires.filter { !($0.nom.isEmpty && $0.compte.isEmpty && $0.role.isEmpty) }
            .map { var p = $0; p.compte = p.compte.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")); return p }
        enregistrement = true
        Task {
            let ok = await etat.envoyer(g, action: "enregistrer-galerie")
            enregistrement = false
            if ok {
                await etat.chargerGaleries()
                if nouvelle { etat.message = "Galerie ajoutée. « Relire les photos », puis « Faire analyser par Claude »." }
                fermer()
            }
        }
    }

    private func choisirDossier() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choisir"
        return p.runModal() == .OK ? p.url?.path : nil
    }
}
