import AppKit
import ImageIO
import SwiftUI

// Composants de l'app, version 2 (app/DESIGN.md §3.2). Tous lisent `@Environment(\.jetons)` :
// ambiance, couleurs, typographie, espacements, rayons et animations suivent config/app.yaml.

// MARK: - Compatibilité 1.2 (couleurs dynamiques, polices)

extension Color {
    /// Accent de l'ambiance. Couleur dynamique : suit le thème et le mode.
    static var olive: Color { ThemeCourant.partage.couleur(\.accent) }
    /// Accent doux.
    static var peche: Color { ThemeCourant.partage.couleur(\.accentDoux) }
    static var alerte: Color { ThemeCourant.partage.couleur(\.alerte) }
    static var succes: Color { ThemeCourant.partage.couleur(\.succes) }
    static var surface: Color { ThemeCourant.partage.couleur(\.surface) }
    static var fond: Color { ThemeCourant.partage.couleur(\.fond) }
    static var trait: Color { ThemeCourant.partage.couleur(\.trait) }
    /// Encre : texte et pilules sombres.
    static var encre: Color { ThemeCourant.partage.couleur(\.encre) }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

extension Font {
    /// Police des titres choisie (`titres` de config/app.yaml) à une taille donnée.
    static func titre(_ taille: CGFloat) -> Font {
        switch ThemeCourant.partage.styleTitres {
        case .serif: return .system(size: taille, weight: .regular, design: .serif)
        case .arrondi: return .system(size: taille, weight: .medium, design: .rounded)
        case .standard: return .system(size: taille, weight: .light, design: .default)
        case .police:
            return Typographie.jakartaDisponible ? Typographie.jakarta(taille, graisse: taille >= 24 ? 360 : 560)
                : .system(size: taille, weight: taille >= 24 ? .light : .semibold)
        }
    }

    /// Plus Jakarta Sans à une graisse de l'axe variable (200 à 800), repli sur la police du système.
    static func jakarta(_ taille: CGFloat, graisse: CGFloat = 400, italique: Bool = false) -> Font {
        guard Typographie.jakartaDisponible else {
            let f = Font.system(size: taille, weight: Typographie.graisseSysteme(graisse))
            return italique ? f.italic() : f
        }
        return Typographie.jakarta(taille, graisse: graisse, italique: italique)
    }
}

// MARK: - Images locales (chargées hors du fil principal, avec cache)


final class CacheImages: @unchecked Sendable {
    static let partage = CacheImages()

    private final class Entree {
        let image: NSImage
        let date: Date?
        init(_ image: NSImage, _ date: Date?) {
            self.image = image
            self.date = date
        }
    }

    private let cache = NSCache<NSString, Entree>()

    init() { cache.countLimit = 400 }

    /// Image entière, lue tout de suite (compatibilité 1.2 ; préférer `ImageLocale`).
    func image(_ chemin: String) -> NSImage? {
        let date = CacheImages.dateModification(chemin)
        let cle = "\(chemin)|plein" as NSString
        if let e = cache.object(forKey: cle), e.date == date { return e.image }
        guard let i = NSImage(contentsOfFile: chemin) else { return nil }
        cache.setObject(Entree(i, date), forKey: cle)
        return i
    }

    /// Taille de décodage arrondie au palier supérieur (les vues de tailles voisines partagent l'image).
    static func palier(_ pixels: CGFloat) -> Int {
        for p in [128, 256, 512, 1024, 2048] where CGFloat(p) >= pixels { return p }
        return 4096
    }

    /// Ce qui est déjà en mémoire, sans vérifier le fichier.
    func enCache(_ chemin: String, pixels: Int) -> NSImage? {
        cache.object(forKey: CacheImages.cle(chemin, pixels))?.image
    }

    /// Vignette décodée hors du fil principal ; rechargée si le fichier a changé.
    func charger(_ chemin: String, pixels: Int) async -> NSImage? {
        let cle = CacheImages.cle(chemin, pixels)
        let date = await Task.detached(priority: .userInitiated) { CacheImages.dateModification(chemin) }.value
        if let e = cache.object(forKey: cle), e.date == date { return e.image }
        let cg = await Task.detached(priority: .userInitiated) { CacheImages.vignette(chemin, pixels: pixels) }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(Entree(image, date), forKey: cle)
        return image
    }

    private static func cle(_ chemin: String, _ pixels: Int) -> NSString { "\(chemin)|\(pixels)" as NSString }

    private static func dateModification(_ chemin: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: chemin))?[.modificationDate] as? Date
    }

    private static func vignette(_ chemin: String, pixels: Int) -> CGImage? {
        let url = URL(fileURLWithPath: chemin) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Une photo du studio : chargée hors du fil principal à la taille affichée, puis révélée en fondu
/// (ou « comme un tirage dans le bain » avec `revelation`).
struct ImageLocale: View {
    let chemin: String?
    var remplir: Bool
    var revelation: Bool

    @Environment(\.jetons) private var j
    @Environment(\.displayScale) private var echelleEcran
    @Local private var image: NSImage?
    @Local private var visible = false
    @Local private var echec = false

    init(chemin: String?, remplir: Bool = true, revelation: Bool = false) {
        self.chemin = chemin
        self.remplir = remplir
        self.revelation = revelation
    }

    var body: some View {
        GeometryReader { geo in
            let px = CacheImages.palier(max(geo.size.width, geo.size.height) * max(1, echelleEcran))
            ZStack {
                Rectangle().fill(j.selection)
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: remplir ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .brightness(revelation && !visible ? 0.25 : 0)
                        .saturation(revelation && !visible ? 0.2 : 1)
                        .opacity(visible ? 1 : 0)
                } else if chemin == nil || echec {
                    Image(systemName: "photo")
                        .font(.system(size: min(28, max(12, geo.size.width / 6)), weight: .light))
                        .foregroundStyle(j.texteTertiaire)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: CleImage(chemin: chemin, pixels: px, vide: geo.size.width < 1)) {
                guard geo.size.width >= 1 else { return }
                await charger(px)
            }
        }
        .accessibilityHidden(true)
    }

    private func charger(_ px: Int) async {
        guard let c = chemin, !c.isEmpty else {
            image = nil
            echec = false
            return
        }
        if let deja = CacheImages.partage.enCache(c, pixels: px) {
            if image !== deja {
                image = deja
                visible = true
            }
        } else if image == nil || !visible {
            visible = false
        }
        let img = await CacheImages.partage.charger(c, pixels: px)
        guard !Task.isCancelled else { return }
        guard let img else {
            image = nil
            echec = true
            return
        }
        echec = false
        guard img !== image || !visible else { return }
        let dejaVisible = visible && image != nil
        image = img
        if dejaVisible { return }
        let a: Animation? = revelation ? j.anim(.revelation) : (j.niveau == .aucune ? nil : .easeOut(duration: 0.25))
        withAnimation(a) { visible = true }
    }
}

private struct CleImage: Equatable {
    let chemin: String?
    let pixels: Int
    let vide: Bool
}


// MARK: - Boutons pilules

/// `.sombre` : encre pleine (le bouton d'action). `.claire` : blanc doux et filet. `.accent` : couleur de l'ambiance.
enum VariantePilule { case sombre, claire, accent }

/// `.petite` (raccourcis, 30 pt), `.normale` (`esp.hauteurBouton`), `.grande` (action principale, +8 pt).
enum TaillePilule { case petite, normale, grande }

/// Pilule avec icône, comme « Deep Research » : `Button { … } label: { Label("Créer", systemImage: "wand.and.stars") }`.
struct BoutonPilule: ButtonStyle {
    var variante: VariantePilule = .sombre
    var taille: TaillePilule = .normale
    var pleineLargeur = false
    /// Petite roue et « Un instant… » pendant l'action.
    var enCours = false

    init(_ variante: VariantePilule = .sombre, taille: TaillePilule = .normale, pleineLargeur: Bool = false, enCours: Bool = false) {
        self.variante = variante
        self.taille = taille
        self.pleineLargeur = pleineLargeur
        self.enCours = enCours
    }

    func makeBody(configuration: Configuration) -> some View {
        CorpsPilule(configuration: configuration, variante: variante, taille: taille, pleineLargeur: pleineLargeur,
                    enCours: enCours, illumine: false)
    }
}

/// Bouton principal : une grande pilule sombre, une seule par écran, avec `.keyboardShortcut(.defaultAction)`.
struct BoutonPrincipal: ButtonStyle {
    var pleineLargeur = false
    /// Petite roue et « Un instant… » pendant l'action.
    var enCours = false
    /// Un halo passe une fois (l'app s'est ouverte pour une décision).
    var illumine = false

    func makeBody(configuration: Configuration) -> some View {
        CorpsPilule(configuration: configuration, variante: .sombre, taille: .grande, pleineLargeur: pleineLargeur,
                    enCours: enCours, illumine: illumine)
    }
}

/// Bouton secondaire : pilule claire.
struct BoutonSecondaire: ButtonStyle {
    var pleineLargeur = false

    func makeBody(configuration: Configuration) -> some View {
        CorpsPilule(configuration: configuration, variante: .claire, taille: .normale, pleineLargeur: pleineLargeur,
                    enCours: false, illumine: false)
    }
}

private struct CorpsPilule: View {
    let configuration: ButtonStyleConfiguration
    let variante: VariantePilule
    let taille: TaillePilule
    let pleineLargeur: Bool
    let enCours: Bool
    let illumine: Bool
    @Environment(\.jetons) private var j
    @Environment(\.isEnabled) private var actif
    @Local private var survol = false
    @Local private var lueur = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        HStack(spacing: taille == .petite ? 6 : 8) {
            if enCours {
                ProgressView()
                    .controlSize(.small)
                    .environment(\.colorScheme, variante == .claire ? j.schema : (j.schema == .light ? .dark : .light))
                Text("Un instant…")
            } else {
                configuration.label
            }
        }
        .typo(taille == .grande ? .bouton : .boutonSecondaire, couleur: couleurTexte)
        .imageScale(taille == .petite ? .small : .medium)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, taille == .petite ? 13 : (taille == .normale ? 18 : 24))
        .frame(minHeight: hauteur)
        .frame(maxWidth: pleineLargeur ? .infinity : nil)
        .background(forme.fill(fond))
        .overlay(forme.strokeBorder(variante == .claire ? j.trait : Color.clear, lineWidth: 1))
        .overlay(
            forme.stroke(j.accentDoux, lineWidth: 3)
                .scaleEffect(lueur ? 1.25 : 1)
                .opacity(lueur ? 0 : (illumine ? 0.9 : 0))
        )
        .contentShape(forme)
        .opacity(actif ? 1 : 0.38)
        .scaleEffect(configuration.isPressed && j.niveau >= .normales ? 0.97 : 1)
        .animation(j.anim(.appui), value: configuration.isPressed)
        .animation(j.anim(.survol), value: survol)
        .onHover { survol = $0 }
        .onAppear {
            guard illumine, let a = j.anim(.revelation) else { return }
            withAnimation(a.delay(0.3)) { lueur = true }
        }
        .allowsHitTesting(!enCours)
    }

    private var hauteur: CGFloat {
        switch taille {
        case .petite: return max(28, j.esp.hauteurBouton - 10)
        case .normale: return j.esp.hauteurBouton
        case .grande: return j.esp.hauteurBouton + 8
        }
    }

    private var enSurvol: Bool { survol && actif && !enCours }

    private var fond: Color {
        switch variante {
        case .sombre: return enSurvol ? j.encreSurvol : j.encre
        case .accent: return enSurvol ? j.accentSurvol : j.accent
        case .claire:
            if j.schema == .dark { return Color.white.opacity(enSurvol ? 0.14 : 0.08) }
            return enSurvol ? j.surfaceElevee : j.remplissageCarte
        }
    }

    private var couleurTexte: Color {
        switch variante {
        case .sombre: return j.surEncre
        case .accent: return j.surAccent
        case .claire: return j.texte
        }
    }
}

/// Bouton discret : texte accent, voile au survol ; `fleche` ajoute une flèche qui glisse.
struct BoutonDiscret: ButtonStyle {
    var fleche = false

    func makeBody(configuration: Configuration) -> some View {
        CorpsBoutonSimple(configuration: configuration, destructif: false, fleche: fleche)
    }
}

/// Bouton destructif : texte couleur alerte, jamais rempli de rouge ; toujours confirmé (`.confirmationDialog`).
struct BoutonDestructif: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CorpsBoutonSimple(configuration: configuration, destructif: true, fleche: false)
    }
}

private struct CorpsBoutonSimple: View {
    let configuration: ButtonStyleConfiguration
    let destructif: Bool
    let fleche: Bool
    @Environment(\.jetons) private var j
    @Environment(\.isEnabled) private var actif
    @Local private var survol = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        HStack(spacing: 6) {
            configuration.label
            if fleche {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(x: survol && j.deplacements ? 3 : 0)
            }
        }
        .typo(.boutonSecondaire, couleur: destructif ? j.alerte : j.accentTexte)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minHeight: max(26, j.esp.hauteurBouton - 10))
        .background(forme.fill(survol && actif ? j.selection : Color.clear))
        .contentShape(forme)
        .opacity(actif ? (configuration.isPressed ? 0.7 : 1) : 0.4)
        .animation(j.anim(.survol), value: survol)
        .onHover { survol = $0 }
    }
}

/// `.claire` : disque blanc doux ; `.sombre` : disque d'encre (« + », envoyer) ; `.transparente` : rien au repos.
enum VarianteRond { case sombre, claire, transparente }

/// Bouton rond d'icône : « + » de la barre, envoyer, retour, fermer.
struct BoutonRond: ButtonStyle {
    var variante: VarianteRond = .claire
    var diametre: CGFloat = 40

    init(_ variante: VarianteRond = .claire, diametre: CGFloat = 40) {
        self.variante = variante
        self.diametre = diametre
    }

    func makeBody(configuration: Configuration) -> some View {
        CorpsBoutonRond(configuration: configuration, variante: variante, diametre: diametre)
    }
}

/// Bouton icône 1.2 (fermer, flèches, nouvelle conversation) : un `BoutonRond(.transparente)`.
struct BoutonIcone: ButtonStyle {
    var diametre: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        CorpsBoutonRond(configuration: configuration, variante: .transparente, diametre: diametre)
    }
}

private struct CorpsBoutonRond: View {
    let configuration: ButtonStyleConfiguration
    let variante: VarianteRond
    let diametre: CGFloat
    @Environment(\.jetons) private var j
    @Environment(\.isEnabled) private var actif
    @Local private var survol = false

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        configuration.label
            .font(.system(size: diametre * (variante == .transparente ? 0.46 : 0.40), weight: .medium))
            .foregroundStyle(variante == .sombre ? j.surEncre : (variante == .claire ? j.texte : j.texteSecondaire))
            .frame(width: diametre, height: diametre)
            .background(forme.fill(fond))
            .overlay(forme.strokeBorder(variante == .claire ? (j.schema == .dark ? j.traitFort : j.trait.opacity(0.7)) : Color.clear, lineWidth: 1))
            .contentShape(forme)
            .opacity(actif ? (configuration.isPressed ? 0.7 : 1) : 0.38)
            .scaleEffect(configuration.isPressed && j.niveau >= .normales ? 0.94 : 1)
            .animation(j.anim(.appui), value: configuration.isPressed)
            .animation(j.anim(.survol), value: survol)
            .onHover { survol = $0 }
    }

    private var fond: Color {
        let s = survol && actif
        switch variante {
        case .sombre: return s ? j.encreSurvol : j.encre
        case .claire:
            if j.schema == .dark { return Color.white.opacity(s ? 0.20 : 0.13) }
            return s ? j.surfaceElevee : j.remplissageCarte
        case .transparente: return s ? j.selection : .clear
        }
    }
}

extension ButtonStyle where Self == BoutonPrincipal {
    static var principal: BoutonPrincipal { BoutonPrincipal() }
}

extension ButtonStyle where Self == BoutonSecondaire {
    static var secondaire: BoutonSecondaire { BoutonSecondaire() }
}

extension ButtonStyle where Self == BoutonDiscret {
    static var discret: BoutonDiscret { BoutonDiscret() }
}

extension ButtonStyle where Self == BoutonDestructif {
    static var destructif: BoutonDestructif { BoutonDestructif() }
}

extension ButtonStyle where Self == BoutonIcone {
    static var icone: BoutonIcone { BoutonIcone() }
}

extension ButtonStyle where Self == BoutonPilule {
    /// Pilule sombre de taille normale.
    static var pilule: BoutonPilule { BoutonPilule() }
    static func pilule(_ variante: VariantePilule, taille: TaillePilule = .normale, pleineLargeur: Bool = false,
                       enCours: Bool = false) -> BoutonPilule {
        BoutonPilule(variante, taille: taille, pleineLargeur: pleineLargeur, enCours: enCours)
    }
}

extension ButtonStyle where Self == BoutonRond {
    /// Disque blanc doux de 40 pt.
    static var rond: BoutonRond { BoutonRond() }
    static func rond(_ variante: VarianteRond, diametre: CGFloat = 40) -> BoutonRond { BoutonRond(variante, diametre: diametre) }
}

// MARK: - Survol et entrée en cascade

enum EffetSurvol { case carte, photo, ligne }

extension View {
    /// `.carte` : +2 pt et ombre ; `.photo` : léger zoom dans son cadre ; `.ligne` : fond de sélection.
    func survol(_ effet: EffetSurvol = .carte) -> some View { modifier(Survol(effet: effet)) }

    /// Fondu et montée de 8 pt au premier affichage, décalé de `index × pas` (8 éléments au plus).
    func entreeEnCascade(_ index: Int, pas: Double = 0.04) -> some View { modifier(EntreeEnCascade(index: index, pas: pas)) }

    /// Fond de l'app : dégradé de l'ambiance (taches qui dérivent lentement, animées par Core Animation).
    func fondAmbiance(anime: Bool = true) -> some View { background(FondAmbiance(anime: anime)) }

    /// Compatibilité 1.2 : le papier est devenu le fond d'ambiance.
    func fondPapier() -> some View { background(FondAmbiance()) }
}

private struct Survol: ViewModifier {
    let effet: EffetSurvol
    @Environment(\.jetons) private var j
    @Local private var actif = false

    func body(content: Content) -> some View {
        let zoom: CGFloat = effet == .photo && actif && j.niveau >= .normales ? (j.niveau == .riches ? 1.03 : 1.015) : 1
        content
            .scaleEffect(zoom)
            .clipped(antialiased: effet == .photo)
            .offset(y: effet == .carte && actif && j.deplacements ? -2 : 0)
            .ombre(effet == .carte && actif ? .survol : .repos)
            .background {
                RoundedRectangle(cornerRadius: j.rayons.champ * 0.6, style: .continuous)
                    .fill(effet == .ligne && actif ? j.selection : Color.clear)
            }
            .animation(j.anim(.survol), value: actif)
            .onHover { dedans in
                guard dedans != actif else { return }
                actif = dedans
                if effet == .carte { dedans ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            .onDisappear {
                if actif && effet == .carte { NSCursor.pop() }
                actif = false
            }
    }
}

private struct EntreeEnCascade: ViewModifier {
    let index: Int
    let pas: Double
    @Environment(\.jetons) private var j
    @Local private var visible = false

    func body(content: Content) -> some View {
        let actif = j.deplacements && j.anim(.cascade) != nil
        content
            .opacity(!actif || visible ? 1 : 0)
            .offset(y: !actif || visible ? 0 : 8)
            .onAppear {
                guard actif, !visible, let a = j.anim(.cascade) else { return }
                withAnimation(a.delay(j.delaiCascade(index, pas: pas))) { visible = true }
            }
    }
}

// MARK: - Fond d'ambiance (dégradé animé par Core Animation)

/// Le fond de l'app : `fond` uni et quatre taches de couleur de l'ambiance (plus une lueur claire au centre en mode
/// clair). Les taches sont des calques `CAGradientLayer` radiaux dessinés **une fois** ; leur lente dérive
/// (50 s par aller, aller-retour sans fin) est jouée par le serveur de rendu : l'app ne redessine rien, ~0 % de
/// processeur. Figé si « Réduire les animations » (ou `anime: false`) ; en pause quand l'app passe en arrière-plan.
struct FondAmbiance: View {
    var anime = true
    @Environment(\.jetons) private var j
    @ObservedObject private var app = ActiviteApp.partage

    var body: some View {
        ZStack {
            j.fond
            if anime && !j.fondFige {
                CalquesTaches(taches: j.couleurs.rvb.taches, opacite: j.opaciteTaches, lueur: j.schema != .dark,
                              periode: j.periodeDerive, enPause: !app.active)
            } else {
                TachesAmbiance(temps: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Position de repos (fraction de la vue), rayon (fraction du grand côté), amplitude de dérive et décalage.
    static let placements: [(x: CGFloat, y: CGFloat, r: CGFloat, dx: CGFloat, dy: CGFloat, retard: Double)] = [
        (0.04, 0.10, 0.62, 0.10, 0.08, 0.0),
        (0.96, 0.04, 0.56, -0.08, 0.09, 0.27),
        (0.94, 0.96, 0.66, -0.10, -0.07, 0.55),
        (0.06, 0.94, 0.54, 0.09, -0.08, 0.80),
    ]
}

/// Les taches au repos, dessinées une fois (vignettes, `anime: false`, rendus hors écran).
struct TachesAmbiance: View {
    /// Gardé pour compatibilité : seule la position de repos est dessinée.
    var temps: Double = 0
    @Environment(\.jetons) private var j

    var body: some View {
        let couleurs = j.couleurs.taches
        let opacite = j.opaciteTaches
        let sombre = j.schema == .dark
        Canvas { ctx, taille in
            let grand = max(taille.width, taille.height)
            for (i, p) in FondAmbiance.placements.enumerated() where i < couleurs.count {
                let centre = CGPoint(x: taille.width * p.x, y: taille.height * p.y)
                let r = grand * p.r
                let c = couleurs[i]
                let degrade = Gradient(stops: [
                    .init(color: c.opacity(opacite), location: 0),
                    .init(color: c.opacity(opacite * 0.72), location: 0.32),
                    .init(color: c.opacity(opacite * 0.28), location: 0.62),
                    .init(color: c.opacity(0), location: 1),
                ])
                ctx.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(degrade, center: centre, startRadius: 0, endRadius: r))
            }
            if !sombre {
                let centre = CGPoint(x: taille.width * 0.52, y: taille.height * 0.46)
                let r = grand * 0.42
                let blanc = Gradient(stops: [
                    .init(color: Color.white.opacity(0.75), location: 0),
                    .init(color: Color.white.opacity(0.35), location: 0.5),
                    .init(color: Color.white.opacity(0), location: 1),
                ])
                ctx.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(blanc, center: centre, startRadius: 0, endRadius: r))
            }
        }
        .drawingGroup()
    }
}

/// Les taches en calques Core Animation (dérive hors de l'app).
private struct CalquesTaches: NSViewRepresentable {
    let taches: [RVB]
    let opacite: Double
    let lueur: Bool
    let periode: Double
    let enPause: Bool

    func makeNSView(context: Context) -> VueTaches { VueTaches() }

    func updateNSView(_ v: VueTaches, context: Context) {
        v.configurer(taches: taches, opacite: opacite, lueur: lueur, periode: periode)
        v.mettreEnPause(enPause)
    }
}

final class VueTaches: NSView {
    private var calques: [CAGradientLayer] = []
    private let calqueLueur = CAGradientLayer()
    private var periode: Double = 50
    private var tailleAnimee: CGSize = .zero
    private var enPause = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for _ in FondAmbiance.placements {
            let g = CAGradientLayer()
            g.type = .radial
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.locations = [0, 0.32, 0.62, 1]
            layer?.addSublayer(g)
            calques.append(g)
        }
        calqueLueur.type = .radial
        calqueLueur.startPoint = CGPoint(x: 0.5, y: 0.5)
        calqueLueur.endPoint = CGPoint(x: 1, y: 1)
        calqueLueur.locations = [0, 0.5, 1]
        calqueLueur.colors = [NSColor.white.withAlphaComponent(0.75).cgColor, NSColor.white.withAlphaComponent(0.35).cgColor,
                              NSColor.white.withAlphaComponent(0).cgColor]
        layer?.addSublayer(calqueLueur)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    override var isFlipped: Bool { true }

    func configurer(taches: [RVB], opacite: Double, lueur: Bool, periode p: Double) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)   // changement d'ambiance : fondu des couleurs
        for (i, g) in calques.enumerated() {
            let c = i < taches.count ? taches[i].nsColor : NSColor.clear
            g.colors = [c.withAlphaComponent(opacite), c.withAlphaComponent(opacite * 0.72),
                        c.withAlphaComponent(opacite * 0.28), c.withAlphaComponent(0)].map(\.cgColor)
        }
        calqueLueur.opacity = lueur ? 1 : 0
        CATransaction.commit()
        if p != periode {
            periode = p
            tailleAnimee = .zero
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let t = bounds.size
        guard t.width > 0, t.height > 0 else { return }
        let grand = max(t.width, t.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, p) in FondAmbiance.placements.enumerated() {
            let r = grand * p.r
            calques[i].bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
            calques[i].position = CGPoint(x: t.width * p.x, y: t.height * p.y)
        }
        let rl = grand * 0.42
        calqueLueur.bounds = CGRect(x: 0, y: 0, width: 2 * rl, height: 2 * rl)
        calqueLueur.position = CGPoint(x: t.width * 0.52, y: t.height * 0.46)
        CATransaction.commit()
        // Les amplitudes dépendent de la taille : on relance la dérive seulement si elle a beaucoup changé.
        if abs(t.width - tailleAnimee.width) > 80 || abs(t.height - tailleAnimee.height) > 80 {
            tailleAnimee = t
            animer(taille: t)
        }
    }

    private func animer(taille t: CGSize) {
        let debut = CACurrentMediaTime()
        for (i, p) in FondAmbiance.placements.enumerated() {
            let g = calques[i]
            g.removeAllAnimations()
            let duree = periode * (0.85 + 0.1 * Double(i))
            let decalage = duree * p.retard
            func aller(_ chemin: String, _ de: CGFloat, _ a: CGFloat, _ d: Double) -> CABasicAnimation {
                let anim = CABasicAnimation(keyPath: chemin)
                anim.fromValue = de
                anim.toValue = a
                anim.duration = d
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                anim.beginTime = debut - decalage
                anim.isRemovedOnCompletion = false
                return anim
            }
            g.add(aller("transform.translation.x", -t.width * p.dx, t.width * p.dx, duree), forKey: "x")
            g.add(aller("transform.translation.y", -t.height * p.dy, t.height * p.dy, duree * 1.27), forKey: "y")
            g.add(aller("transform.scale", 0.95, 1.06, duree * 0.8), forKey: "echelle")
        }
        calqueLueur.removeAllAnimations()
        let l = CABasicAnimation(keyPath: "transform.translation.x")
        l.fromValue = -t.width * 0.04
        l.toValue = t.width * 0.04
        l.duration = periode * 1.4
        l.autoreverses = true
        l.repeatCount = .infinity
        l.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        calqueLueur.add(l, forKey: "x")
        if enPause { geler() }
    }

    func mettreEnPause(_ p: Bool) {
        guard p != enPause, let calque = layer else { return }
        enPause = p
        if p {
            geler()
        } else {
            let pause = calque.timeOffset
            calque.speed = 1
            calque.timeOffset = 0
            calque.beginTime = 0
            calque.beginTime = calque.convertTime(CACurrentMediaTime(), from: nil) - pause
        }
    }

    private func geler() {
        guard let calque = layer, calque.speed != 0 else { return }
        let t = calque.convertTime(CACurrentMediaTime(), from: nil)
        calque.speed = 0
        calque.timeOffset = t
    }
}

/// Retirée (simplification du 22/11) : la trame de points n'est plus dessinée. Gardée pour compatibilité.
struct TrameDePoints: View {
    var pas: CGFloat = 15
    var diametre: CGFloat = 1.5

    var body: some View { EmptyView() }
}

/// Compatibilité 1.2 : le papier est devenu le fond d'ambiance.
struct FondPapier: View {
    var body: some View { FondAmbiance() }
}

/// Fond de ce qui flotte (bandeau, capsule de Claude, barre collante) : verre blanc doux sur le dégradé,
/// opaque si la transparence est réduite.
struct FondFlottant<Forme: Shape>: View {
    let forme: Forme
    var survol = false
    @Environment(\.jetons) private var j

    var body: some View {
        ZStack {
            if !j.systeme.reduireTransparence {
                forme.fill(.ultraThinMaterial)
            }
            forme.fill(survol ? j.surfaceElevee : j.remplissageCarte)
        }
    }
}

/// La grande page claire posée sur le dégradé (comme le panneau central de l'inspiration) : verre blanc,
/// rayon `feuille` + 8, liseré. La barre d'icônes reste dehors, à gauche.
struct PanneauPage<Contenu: View>: View {
    let contenu: Contenu
    @Environment(\.jetons) private var j

    init(@ViewBuilder contenu: () -> Contenu) { self.contenu = contenu() }

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.feuille + 8, style: .continuous)
        contenu
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if j.systeme.reduireTransparence {
                        forme.fill(j.carte)
                    } else {
                        forme.fill(LinearGradient(
                            colors: j.schema == .dark
                                ? [Color.white.opacity(0.06), Color.white.opacity(0.025)]
                                : [Color.white.opacity(0.72), Color.white.opacity(0.42)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
            .overlay(forme.strokeBorder(Color.white.opacity(j.schema == .dark ? 0.08 : 0.65), lineWidth: 1))
            .clipShape(forme)
            .ombre(.carte)
    }
}

/// Filet de 1 pt (couleur `trait`).
struct Filet: View {
    var vertical = false
    @Environment(\.jetons) private var j

    var body: some View {
        Rectangle()
            .fill(j.trait)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

/// Rectangle pointillé avec traits de coupe aux angles (états vides, « Ton idée »).
struct CadreTraitsDeCoupe: View {
    var rayon: CGFloat = 0
    @Environment(\.jetons) private var j

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: rayon, style: .continuous)
                .strokeBorder(j.traitFort, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            TraitsDeCoupe()
                .stroke(j.texteSecondaire, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct TraitsDeCoupe: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let ecart: CGFloat = 5, long: CGFloat = 10
        for (x, sx) in [(r.minX, -1.0), (r.maxX, 1.0)] {
            for (y, sy) in [(r.minY, -1.0), (r.maxY, 1.0)] {
                p.move(to: CGPoint(x: x + sx * ecart, y: y))
                p.addLine(to: CGPoint(x: x + sx * (ecart + long), y: y))
                p.move(to: CGPoint(x: x, y: y + sy * ecart))
                p.addLine(to: CGPoint(x: x, y: y + sy * (ecart + long)))
            }
        }
        return p
    }
}

// MARK: - Textes

struct SurTitre: View {
    let texte: String

    var body: some View {
        Text(texte).typo(.surtitre)
    }
}

/// Titre en deux tons, comme « Bonjour Gabriella, prête pour la journée ? » : le début en secondaire.
struct TitreDeuxTons: View {
    let debut: String
    let suite: String
    var role: RoleTexte = .affiche
    var alignement: TextAlignment = .leading
    @Environment(\.jetons) private var j

    var body: some View {
        (Text(debut).foregroundStyle(j.texteSecondaire) + Text(suite).foregroundStyle(j.texte))
            .font(j.police(role))
            .tracking(j.approche(role))
            .multilineTextAlignment(alignement)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// La voix de Claude : italique de la police, filet vertical accent.
struct VoixDeClaude: View {
    let texte: String
    var filet: Bool
    var compacte: Bool
    @Environment(\.jetons) private var j

    init(_ texte: String, filet: Bool = true, compacte: Bool = false) {
        self.texte = texte
        self.filet = filet
        self.compacte = compacte
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if filet {
                Capsule().fill(j.accent).frame(width: 2)
            }
            Text(texte)
                .typo(compacte ? .voixCarte : .voix)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ListePoints: View {
    let elements: [String]
    var couleur: Color = .primary
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(couleur == .primary ? j.texteSecondaire : couleur).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                    Text(e).typo(.corps)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Carte, pastille, point d'état

enum StyleCarte { case simple, cliquable, heros }

/// Carte blanche très douce posée sur le dégradé : blanc à 80 %, liseré de verre, ombre colorée diffuse,
/// rayon `carte`. `.cliquable` se soulève au survol, `.heros` a le rayon `feuille` et flotte, `choisie` s'entoure d'accent.
struct Carte<Contenu: View>: View {
    var titre: String?
    var symbole: String?
    var style: StyleCarte
    var choisie: Bool
    let contenu: Contenu
    @Environment(\.jetons) private var j

    init(titre: String? = nil, symbole: String? = nil, style: StyleCarte = .simple, choisie: Bool = false,
         @ViewBuilder contenu: () -> Contenu) {
        self.titre = titre
        self.symbole = symbole
        self.style = style
        self.choisie = choisie
        self.contenu = contenu()
    }

    var body: some View {
        let rayon = style == .heros ? j.rayons.feuille : j.rayons.carte
        let forme = RoundedRectangle(cornerRadius: rayon, style: .continuous)
        let corps = VStack(alignment: .leading, spacing: j.esp.pile + 4) {
            if titre != nil || symbole != nil {
                HStack(spacing: 10) {
                    if let s = symbole {
                        Image(systemName: s)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(j.texte)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(j.fondDoux))
                    }
                    if let t = titre { Text(t).typo(.titre3) }
                    Spacer(minLength: 0)
                    if choisie {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(j.accent)
                            .transition(j.transition(.apparition))
                    }
                }
            }
            contenu
        }
        .padding(j.esp.carte)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if choisie && titre == nil && symbole == nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(j.accent)
                    .padding(j.esp.carte * 0.6)
                    .transition(j.transition(.apparition))
            }
        }
        .background(forme.fill(j.remplissageCarte))
        .background(choisie ? forme.fill(j.fondDoux) : nil)
        .overlay(LisereHaut(rayon: rayon))
        .overlay(forme.strokeBorder(choisie ? j.accent : (j.systeme.augmenterContraste ? j.traitFort : Color.clear),
                                    lineWidth: choisie ? 2 : 1))
        .contentShape(forme)
        .ombre(style == .heros ? .flottante : .carte)
        .animation(j.anim(.selection), value: choisie)

        switch style {
        case .simple, .heros: corps
        case .cliquable: corps.survol(.carte)
        }
    }
}

enum TonPastille { case neutre, douce, forte, aToi, succes, alerte }

/// Pastille : un mot (et un symbole), jamais la couleur seule.
struct Pastille: View {
    let texte: String
    var symbole: String?
    var ton: TonPastille
    @Environment(\.jetons) private var j

    init(_ texte: String, symbole: String? = nil, ton: TonPastille = .neutre) {
        self.texte = texte
        self.symbole = symbole
        self.ton = ton
    }

    var body: some View {
        HStack(spacing: 5) {
            if let s = symbole {
                Image(systemName: s).foregroundStyle(couleurIcone).imageScale(.small)
            }
            Text(texte).lineLimit(1)
        }
        .font(Font.jakarta(max(11, j.taille(.legende)), graisse: 540))
        .foregroundStyle(couleurTexte)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(fond))
        .overlay(Capsule().strokeBorder(ton == .neutre ? j.trait : Color.clear, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var fond: Color {
        switch ton {
        case .neutre: return j.schema == .dark ? Color.white.opacity(0.06) : j.remplissageCarte
        case .douce, .aToi: return j.fondDoux
        case .forte: return j.encre
        case .succes: return j.fondSucces
        case .alerte: return j.fondAlerte
        }
    }

    private var couleurTexte: Color {
        switch ton {
        case .neutre: return j.texteSecondaire
        case .forte: return j.surEncre
        case .aToi: return j.aToi
        case .douce, .succes, .alerte: return j.texte
        }
    }

    private var couleurIcone: Color {
        switch ton {
        case .succes: return j.succes
        case .alerte: return j.alerte
        case .douce: return j.aToi
        default: return couleurTexte
        }
    }
}

/// Pastille 1.2 (compatibilité) : préférer `Pastille`.
struct Puce: View {
    let texte: String
    var forte = false
    var couleur: Color? = nil
    @Environment(\.jetons) private var j

    var body: some View {
        if let c = couleur {
            HStack(spacing: 5) {
                Circle().fill(c).frame(width: 6, height: 6)
                Text(texte).lineLimit(1)
            }
            .font(Font.jakarta(max(11, j.taille(.legende)), graisse: 540))
            .foregroundStyle(j.texte)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(c.opacity(0.14)))
            .fixedSize()
        } else {
            Pastille(texte, ton: forte ? .forte : .neutre)
        }
    }
}

/// Point d'état (Claude prêt, au travail, déconnecté ; statut d'un jour). `pulse` : respiration lente.
struct PointEtat: View {
    let couleur: Color
    var pulse = false
    var diametre: CGFloat = 8
    @Environment(\.jetons) private var j
    @Local private var phase = false

    var body: some View {
        Circle()
            .fill(couleur)
            .frame(width: diametre, height: diametre)
            .opacity(pulse && phase ? 0.4 : 1)
            .background(Circle().fill(couleur.opacity(pulse ? 0.25 : 0)).scaleEffect(pulse && phase ? 2 : 1.2))
            .onAppear { demarrer() }
            .onChange(of: pulse) { _, _ in demarrer() }
            .accessibilityHidden(true)
    }

    private func demarrer() {
        if pulse, let a = j.anim(.pulsation) {
            phase = false
            withAnimation(a) { phase = true }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { phase = false }
        }
    }
}

// MARK: - En-têtes, état vide

/// En-tête d'écran : petit libellé, grand titre léger et serré, chapô (ou voix de Claude) ; une action à droite.
struct EnTeteEcran<Action: View>: View {
    let surTitre: String
    let titre: String
    var chapo: String?
    var voixDeClaude: Bool
    let action: Action
    @Environment(\.jetons) private var j

    init(surTitre: String, titre: String, chapo: String? = nil, voixDeClaude: Bool = false,
         @ViewBuilder action: () -> Action) {
        self.surTitre = surTitre
        self.titre = titre
        self.chapo = chapo
        self.voixDeClaude = voixDeClaude
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: j.esp.blocs) {
            HStack(alignment: .bottom, spacing: j.esp.blocs) {
                VStack(alignment: .leading, spacing: j.esp.pile) {
                    Text(surTitre).typo(.surtitre).entreeEnCascade(0)
                    Text(titre)
                        .typo(.titre1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .entreeEnCascade(1)
                }
                Spacer(minLength: 0)
                action.entreeEnCascade(3)
            }
            if let c = chapo {
                Group {
                    if voixDeClaude {
                        VoixDeClaude(c)
                    } else {
                        Text(c).typo(.chapo).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: j.esp.largeurTexte, alignment: .leading)
                .entreeEnCascade(2)
            }
        }
        .padding(.bottom, j.esp.pile)
    }
}

extension EnTeteEcran where Action == EmptyView {
    init(surTitre: String, titre: String, chapo: String? = nil, voixDeClaude: Bool = false) {
        self.init(surTitre: surTitre, titre: titre, chapo: chapo, voixDeClaude: voixDeClaude) { EmptyView() }
    }
}

/// En-tête 1.2 (compatibilité) : préférer `EnTeteEcran`.
struct EnTete: View {
    let surTitre: String
    let titre: String
    var sousTitre: String? = nil

    var body: some View {
        EnTeteEcran(surTitre: surTitre, titre: titre, chapo: sousTitre)
    }
}

/// État vide : cadre 4:5 à traits de coupe sur un disque doux, titre, phrase, action discrète.
struct EtatVide: View {
    var symbole: String? = nil
    let titre: String
    let phrase: String
    var actionTitre: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(spacing: j.esp.blocs) {
            ZStack {
                Circle().fill(j.remplissageCarte).frame(width: 180, height: 180).ombre(.carte)
                CadreTraitsDeCoupe(rayon: j.rayons.photo).frame(width: 96, height: 120)
                if let s = symbole {
                    Image(systemName: s)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(j.texteSecondaire)
                        .symbolVariant(.none)
                }
            }
            .padding(.bottom, j.esp.pile)
            .entreeEnCascade(0)
            Text(titre).typo(.titre2).multilineTextAlignment(.center).entreeEnCascade(1)
            Text(phrase)
                .typo(.chapo)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .entreeEnCascade(2)
            if let t = actionTitre, let a = action {
                Button(t, action: a).buttonStyle(BoutonPilule(.claire)).entreeEnCascade(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(j.esp.sections)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Bandeau

enum TonBandeau { case info, succes, alerte, claude }

struct MessageBandeau: Identifiable, Equatable {
    var id: String
    var ton: TonBandeau
    var texte: String
    var symbole: String?
    var actionTitre: String?
    var action: (() -> Void)?

    init(id: String = UUID().uuidString, ton: TonBandeau = .info, texte: String, symbole: String? = nil,
         actionTitre: String? = nil, action: (() -> Void)? = nil) {
        self.id = id
        self.ton = ton
        self.texte = texte
        self.symbole = symbole
        self.actionTitre = actionTitre
        self.action = action
    }

    static func == (a: MessageBandeau, b: MessageBandeau) -> Bool { a.id == b.id && a.texte == b.texte }
}

/// Capsule flottante en bas de la fenêtre. Succès et infos s'effacent seuls (5 s, 8 s avec une action,
/// pas pendant le survol) ; une alerte reste jusqu'à ce qu'on la ferme.
struct BandeauMessage: View {
    let message: MessageBandeau
    let fermer: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    init(_ message: MessageBandeau, fermer: @escaping () -> Void) {
        self.message = message
        self.fermer = fermer
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbole)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(couleurIcone)
                .symbolVariant(.fill)
            Text(message.texte)
                .font(j.police(.corps))
                .foregroundStyle(j.texte)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if let t = message.actionTitre, let a = message.action {
                Button(t) { a() }.buttonStyle(.discret)
            }
            Button(action: fermer) { Image(systemName: "xmark") }
                .buttonStyle(BoutonIcone(diametre: 22))
                .help("Fermer")
                .keyboardShortcut(.cancelAction)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .background(FondFlottant(forme: RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(j.trait, lineWidth: 1))
        .overlay(LisereHaut(rayon: 22))
        .ombre(.flottante)
        .onHover { survol = $0 }
        .task(id: survol) {
            guard message.ton != .alerte, !survol else { return }
            let secondes: UInt64 = message.action != nil ? 8 : 5
            try? await Task.sleep(nanoseconds: secondes * 1_000_000_000)
            if !Task.isCancelled { fermer() }
        }
        .onAppear { AccessibilityNotification.Announcement(message.texte).post() }
        .accessibilityElement(children: .contain)
    }

    private var symbole: String {
        if let s = message.symbole { return s }
        switch message.ton {
        case .info: return "info.circle"
        case .succes: return "checkmark.circle"
        case .alerte: return "exclamationmark.triangle"
        case .claude: return "sparkles"
        }
    }

    private var couleurIcone: Color {
        switch message.ton {
        case .info: return j.texteSecondaire
        case .succes: return j.succes
        case .alerte: return j.alerte
        case .claude: return j.accentTexte
        }
    }
}

extension View {
    /// Bandeau en bas de la vue : `message = MessageBandeau(…)` pour l'afficher, `nil` pour le fermer.
    func bandeau(_ message: Binding<MessageBandeau?>) -> some View { modifier(ModificateurBandeau(message: message)) }
}

private struct ModificateurBandeau: ViewModifier {
    @Binding var message: MessageBandeau?
    @Environment(\.jetons) private var j

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let m = message {
                    BandeauMessage(m) { message = nil }
                        .id(m.id)
                        .transition(j.transition(.bandeau))
                }
            }
            .padding(20)
            .animation(j.anim(.bandeau), value: message)
        }
    }
}

/// Bandeau de l'app (lit `EtatApp`) : invitation à installer ou connecter Claude, puis erreur, puis message.
struct Bandeau: View {
    @EnvironmentObject var etat: EtatApp
    @Environment(\.jetons) private var j

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
        .padding(20)
        .allowsHitTesting(courant != nil)
    }

    private var courant: MessageBandeau? {
        if let i = etat.invitationClaude {
            return MessageBandeau(id: "invitation|\(i.texte)", ton: .claude, texte: i.texte, symbole: i.symbole,
                                  actionTitre: i.libelleBouton, action: { Task { await etat.accepterInvitation() } })
        }
        if let e = etat.erreur { return MessageBandeau(id: "erreur|\(e)", ton: .alerte, texte: e) }
        if let m = etat.message { return MessageBandeau(id: "message|\(m)", ton: .succes, texte: m) }
        return nil
    }

    private func fermer(_ m: MessageBandeau) {
        if m.id.hasPrefix("invitation|") {
            etat.invitationClaude = nil
        } else if m.id.hasPrefix("erreur|") {
            etat.erreur = nil
        } else {
            etat.message = nil
        }
    }
}


// MARK: - Champs

/// Champ doux : ce qu'elle écrit librement (son nom, son idée, une retouche, une demande à Claude).
/// Blanc, très arrondi, filet léger ; au focus, filet d'encre et halo d'accent. ⏎ appelle `envoyer` (s'il existe).
struct ChampDoux: View {
    @Binding var texte: String
    let exemple: String
    var lignes: ClosedRange<Int> = 1...6
    var envoyer: (() -> Void)? = nil
    @Environment(\.jetons) private var j
    @FocusState private var focus: Bool

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: lignes.upperBound <= 1 ? j.rayons.pilule : j.rayons.champ, style: .continuous)
        TextField(exemple, text: $texte, axis: .vertical)
            .textFieldStyle(.plain)
            .typo(.champ)
            .lineLimit(lignes)
            .focused($focus)
            .focusEffectDisabled()
            .onSubmit { envoyer?() }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(forme.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
            .overlay(forme.strokeBorder(focus ? j.encre.opacity(0.75) : j.traitFort.opacity(0.8), lineWidth: focus ? 1.5 : 1))
            .background(forme.stroke(j.accent.opacity(focus ? 0.16 : 0), lineWidth: 8))
            .animation(j.anim(.survol), value: focus)
    }
}

/// Une liste modifiable, un élément par ligne.
struct EditeurLignes: View {
    let titre: String
    var aide: String? = nil
    @Binding var valeurs: [String]
    @Environment(\.jetons) private var j
    @Local private var texte = ""
    @Local private var pret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).typo(.corpsFort)
            if let a = aide { Text(a).typo(.legende) }
            TextEditor(text: $texte)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90, maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous).fill(j.surfaceElevee))
                .overlay(RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous).strokeBorder(j.traitFort))
                .onChange(of: texte) { _, nouveau in
                    guard pret else { return }
                    valeurs = nouveau.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
        }
        .onAppear {
            texte = valeurs.joined(separator: "\n")
            DispatchQueue.main.async { pret = true }
        }
    }
}

/// Une heure « HH:MM » réglée avec le sélecteur du système.
struct ChampHeure: View {
    @Binding var heure: String

    private var date: Binding<Date> {
        Binding(get: {
            let morceaux = heure.split(separator: ":").compactMap { Int($0) }
            var c = DateComponents()
            c.hour = morceaux.first ?? 18
            c.minute = morceaux.count > 1 ? morceaux[1] : 30
            return Calendar.current.date(from: c) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            heure = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }

    var body: some View {
        DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .frame(width: 90)
    }
}

// MARK: - Chiffre clé, symboles, cercles d'étape

/// Chiffre clé des Statistiques : surtitre, chiffre animé, écart.
struct ChiffreCle: View {
    let valeur: Double
    let libelle: String
    var texte: String? = nil
    var format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0))
    var ecart: String? = nil
    var ecartPositif = true
    @Environment(\.jetons) private var j

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(libelle).typo(.surtitre)
            Group {
                if let t = texte { Text(t) } else { Text(valeur, format: format) }
            }
            .typo(.chiffre)
            .contentTransition(.numericText(value: valeur))
            .animation(j.anim(.compteur), value: valeur)
            if let e = ecart {
                Label(e, systemImage: ecartPositif ? "arrow.up.right" : "arrow.down.right")
                    .typo(.legende, couleur: ecartPositif ? j.succes : j.alerte)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum SymboleEtape {
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var connus: [String: Bool] = [:]

    /// Le nom s'il existe dans SF Symbols sur ce Mac, sinon `circle.dotted`.
    static func valide(_ nom: String?) -> String {
        guard let n = nom, !n.isEmpty else { return "circle.dotted" }
        verrou.lock()
        defer { verrou.unlock() }
        if let ok = connus[n] { return ok ? n : "circle.dotted" }
        let ok = NSImage(systemSymbolName: n, accessibilityDescription: nil) != nil
        connus[n] = ok
        return ok ? n : "circle.dotted"
    }
}

enum EtatCercle { case aVenir, actuel, enAttente, fait }

/// Cercle « à la une », comme ses stories : étapes de connexion à Claude, palettes d'Apparence.
struct CercleEtape: View {
    let symbole: String
    let titre: String
    let etat: EtatCercle
    var diametre: CGFloat = 64
    @Environment(\.jetons) private var j
    @Local private var rotation = 0.0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(etat == .fait ? j.accent : j.surfaceElevee)
                    .padding(5)
                Image(systemName: etat == .fait ? "checkmark" : symbole)
                    .font(.system(size: diametre * 0.32, weight: etat == .fait ? .semibold : .regular))
                    .foregroundStyle(etat == .fait ? j.surAccent : (etat == .aVenir ? j.texteSecondaire : j.accentTexte))
                    .symbolVariant(.none)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: etat == .fait)
                anneau
            }
            .frame(width: diametre, height: diametre)
            Text(titre)
                .typo(.legende, couleur: etat == .aVenir ? j.texteSecondaire : j.texte)
                .multilineTextAlignment(.center)
        }
        .symbolEffectsRemoved(j.niveau == .aucune)
        .animation(j.anim(.selection), value: etat)
        .onAppear { tourner() }
        .onChange(of: etat) { _, _ in tourner() }
        .accessibilityElement(children: .combine)
        .accessibilityValue(libelleEtat)
    }

    @ViewBuilder private var anneau: some View {
        switch etat {
        case .aVenir:
            Circle().strokeBorder(j.schema == .dark ? j.texteTertiaire : j.traitFort, lineWidth: 1)
        case .actuel:
            Circle().strokeBorder(AngularGradient(colors: [j.accent, j.accentDoux, j.accent], center: .center), lineWidth: 3)
        case .enAttente:
            Circle()
                .strokeBorder(j.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
                .rotationEffect(.degrees(rotation))
        case .fait:
            Circle().strokeBorder(j.accent, lineWidth: 3)
        }
    }

    private func tourner() {
        guard etat == .enAttente, j.deplacements else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { rotation = 360 }
    }

    private var libelleEtat: String {
        switch etat {
        case .aVenir: return "à venir"
        case .actuel: return "étape en cours"
        case .enAttente: return "en attente"
        case .fait: return "fait"
        }
    }
}

// MARK: - Frise du jour

enum Acteur {
    case claude, toi, studio

    var libelle: String {
        switch self {
        case .claude: return "Claude"
        case .toi: return "Toi"
        case .studio: return "Le studio"
        }
    }
}

struct EtapeFrise: Identifiable {
    let id: Int
    let titre: String
    let acteur: Acteur
}

/// Les cinq temps de la journée, en disant à chaque fois qui agit.
struct FriseDuJour: View {
    /// 0 Idées · 1 Ton choix · 2 Création · 3 Ta validation · 4 Publication · 5 tout est fait.
    let courante: Int
    var claudeTravaille = false
    var heurePublication: String? = nil
    @Environment(\.jetons) private var j
    @Namespace private var espace

    static let etapes = [
        EtapeFrise(id: 0, titre: "Idées", acteur: .claude),
        EtapeFrise(id: 1, titre: "Ton choix", acteur: .toi),
        EtapeFrise(id: 2, titre: "Création", acteur: .claude),
        EtapeFrise(id: 3, titre: "Ta validation", acteur: .toi),
        EtapeFrise(id: 4, titre: "Publication", acteur: .studio),
    ]

    /// Index de l'étape courante d'après le statut du jour (`VueJour.statut`).
    static func index(statut: String?) -> Int {
        switch statut {
        case "idees_proposees": return 1
        case "idee_choisie": return 2
        case "brouillon_pret": return 3
        case "approuve": return 4
        case "publie": return 5
        default: return 0
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(FriseDuJour.etapes) { e in
                colonne(e)
            }
        }
        .animation(j.anim(.frise), value: courante)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelleAccessible)
    }

    private func colonne(_ e: EtapeFrise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                marque(e)
                Text(e.titre)
                    .typo(.surtitre, couleur: e.id <= courante ? j.texte : j.texteSecondaire)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Group {
                if e.id == courante && e.acteur == .toi {
                    Pastille("À toi", ton: .aToi)
                } else {
                    Text(e.acteur == .studio && heurePublication != nil ? "Le studio · \(heurePublication ?? "")" : e.acteur.libelle)
                        .typo(.legende)
                        .lineLimit(1)
                }
            }
            .frame(height: 20, alignment: .leading)
            ZStack(alignment: .leading) {
                Rectangle().fill(e.id < courante ? j.accent.opacity(0.35) : j.trait).frame(height: 2)
                if e.id == courante {
                    Rectangle().fill(j.accent).frame(height: 2).matchedGeometryEffect(id: "trait", in: espace)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func marque(_ e: EtapeFrise) -> some View {
        if e.id < courante {
            ZStack {
                Circle().fill(j.accent)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(j.surAccent)
            }
            .frame(width: 16, height: 16)
            .transition(j.transition(.apparition))
        } else if e.id == courante {
            switch e.acteur {
            case .claude:
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(j.accentTexte)
                    .symbolEffect(.pulse, isActive: claudeTravaille && j.niveau > .aucune)
                    .frame(width: 16, height: 16)
            case .toi:
                Circle().fill(j.aToi).frame(width: 10, height: 10).frame(width: 16, height: 16)
            case .studio:
                Image(systemName: "clock.fill").font(.system(size: 12)).foregroundStyle(j.accentTexte).frame(width: 16, height: 16)
            }
        } else {
            Circle().strokeBorder(j.traitFort, lineWidth: 1).frame(width: 12, height: 12).frame(width: 16, height: 16)
        }
    }

    private var libelleAccessible: String {
        guard courante < FriseDuJour.etapes.count else { return "Journée terminée : le post est en ligne." }
        let e = FriseDuJour.etapes[courante]
        let qui = e.acteur == .toi ? "à toi" : (e.acteur == .claude ? "Claude s'en occupe" : "le studio s'en occupe")
        return "Étape \(courante + 1) sur 5, \(e.titre), \(qui)."
    }
}

// MARK: - Téléphone Instagram

enum FormatInstagram: Equatable {
    case carrousel, image, reel

    init(_ texte: String?) {
        switch texte?.lowercased() {
        case "reel": self = .reel
        case "image": self = .image
        default: self = .carrousel
        }
    }
}

/// Ce que montre le téléphone de l'Aperçu.
struct ContenuInstagram: Equatable {
    var compte: String
    var collaborateurs: [String] = []
    var lieu: String? = nil
    /// « Titre · Artiste ».
    var musique: String? = nil
    /// Chemins des images, dans l'ordre (la couverture d'un Reel en premier).
    var medias: [String] = []
    var format: FormatInstagram = .carrousel
    var legende: String = ""
    /// « 19 novembre ».
    var date: String? = nil
    /// Heure de la barre d'état (le créneau).
    var heure: String = "18:30"

    var compteCourt: String { compte.hasPrefix("@") ? String(compte.dropFirst()) : compte }

    var initiales: String {
        let morceaux = compteCourt.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " })
        let lettres = morceaux.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return (lettres.isEmpty ? String(compteCourt.prefix(2)) : lettres).uppercased()
    }
}

/// Maquette fidèle d'un post Instagram dans un téléphone. S'adapte à la place disponible (rapport 395:832).
struct TelephoneInstagram: View {
    let contenu: ContenuInstagram
    var sombre: Bool
    private let indexExterne: Binding<Int>?
    @Environment(\.jetons) private var j
    @Local private var indexInterne = 0
    @Local private var legendeDepliee = false
    @Local private var survolMedia = false
    @Local private var ligneMusique = false

    static let largeur: CGFloat = 395
    static let hauteur: CGFloat = 832
    private let largeurEcran: CGFloat = 375
    private let hauteurEcran: CGFloat = 812

    init(contenu: ContenuInstagram, sombre: Bool = false, index: Binding<Int>? = nil) {
        self.contenu = contenu
        self.sombre = sombre
        self.indexExterne = index
    }

    private var index: Int { min(max(0, indexExterne?.wrappedValue ?? indexInterne), max(0, nombre - 1)) }
    private var nombre: Int { contenu.format == .reel ? 1 : max(1, contenu.medias.count) }

    private func aller(_ i: Int) {
        let n = min(max(0, i), nombre - 1)
        withAnimation(j.anim(.carrousel)) {
            if let b = indexExterne { b.wrappedValue = n } else { indexInterne = n }
        }
    }

    private var position: Binding<Int?> {
        Binding(get: { index }, set: { v in
            guard let v else { return }
            if let b = indexExterne { b.wrappedValue = v } else { indexInterne = v }
        })
    }

    var body: some View {
        GeometryReader { geo in
            let e = min(geo.size.width / TelephoneInstagram.largeur, geo.size.height / TelephoneInstagram.hauteur)
            boitier
                .frame(width: TelephoneInstagram.largeur, height: TelephoneInstagram.hauteur)
                .scaleEffect(e)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(TelephoneInstagram.largeur / TelephoneInstagram.hauteur, contentMode: .fit)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            aller(index - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            aller(index + 1)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu Instagram, image \(index + 1) sur \(nombre)")
        .accessibilityAdjustableAction { sens in
            switch sens {
            case .increment: aller(index + 1)
            case .decrement: aller(index - 1)
            @unknown default: break
            }
        }
    }

    private var boitier: some View {
        let ig = CouleursInstagram(sombre: sombre)
        return ZStack {
            RoundedRectangle(cornerRadius: j.rayons.telephone, style: .continuous)
                .fill(Color(red: 0.106, green: 0.106, blue: 0.114))
                .overlay(RoundedRectangle(cornerRadius: j.rayons.telephone, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5))
            ZStack(alignment: .top) {
                ig.fond
                if contenu.format == .reel { reel(ig) } else { publication(ig) }
                barreEtat(ig)
            }
            .frame(width: largeurEcran, height: hauteurEcran)
            .clipShape(RoundedRectangle(cornerRadius: j.rayons.ecranTelephone, style: .continuous))
            .environment(\.colorScheme, sombre ? .dark : .light)
            .symbolVariant(.none)
        }
        .ombre(.feuille)
    }

    private func barreEtat(_ ig: CouleursInstagram) -> some View {
        let couleur = contenu.format == .reel ? Color.white : ig.texte
        return ZStack(alignment: .top) {
            HStack {
                Text(contenu.heure).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(couleur)
            .padding(.horizontal, 30)
            .padding(.top, 17)
            Capsule().fill(Color.black).frame(width: 120, height: 34).padding(.top, 11)
        }
        .frame(height: 54, alignment: .top)
        .accessibilityHidden(true)
    }

    private func avatar(_ d: CGFloat) -> some View {
        ZStack {
            Circle().fill(j.accent)
            Text(contenu.initiales).font(.system(size: d * 0.38, weight: .semibold)).foregroundStyle(j.surAccent)
        }
        .frame(width: d, height: d)
    }

    private var nomAffiche: String {
        switch contenu.collaborateurs.count {
        case 0: return contenu.compteCourt
        case 1: return "\(contenu.compteCourt) et \(contenu.collaborateurs[0])"
        default: return "\(contenu.compteCourt) et \(contenu.collaborateurs.count) autres"
        }
    }

    private var sousLigne: String? {
        let musique = contenu.musique.map { "♫ \($0)" }
        if let l = contenu.lieu, let m = musique { return ligneMusique ? m : l }
        return contenu.lieu ?? musique
    }

    private func publication(_ ig: CouleursInstagram) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 54)
            HStack {
                Image(systemName: "chevron.left")
                Spacer()
                Text("Publications").font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.left").hidden()
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(ig.texte)
            .padding(.horizontal, 14)
            .frame(height: 40)
            // En-tête du post
            HStack(spacing: 10) {
                avatar(32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nomAffiche).font(.system(size: 14, weight: .semibold)).foregroundStyle(ig.texte).lineLimit(1)
                    if let s = sousLigne {
                        Text(s).font(.system(size: 12)).foregroundStyle(ig.texte).lineLimit(1)
                            .id(s)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(ig.texte)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .task(id: contenu) {
                guard contenu.lieu != nil, contenu.musique != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if Task.isCancelled { break }
                    withAnimation(j.anim(.doux)) { ligneMusique.toggle() }
                }
            }
            media(ig)
            actions(ig)
            legende(ig)
            Spacer(minLength: 0)
        }
    }

    private func media(_ ig: CouleursInstagram) -> some View {
        let n = nombre
        let hauteurMedia = largeurEcran * 5 / 4
        return ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in
                        ImageLocale(chemin: i < contenu.medias.count ? contenu.medias[i] : nil)
                            .frame(width: largeurEcran, height: hauteurMedia)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: position)
            .frame(width: largeurEcran, height: hauteurMedia)
            if n > 1 {
                Text("\(index + 1)/\(n)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(12)
                    .contentTransition(.numericText(value: Double(index)))
            }
        }
        .overlay {
            if n > 1 && survolMedia {
                HStack {
                    if index > 0 { fleche("chevron.left") { aller(index - 1) } }
                    Spacer()
                    if index < n - 1 { fleche("chevron.right") { aller(index + 1) } }
                }
                .padding(.horizontal, 10)
                .transition(.opacity)
            }
        }
        .onHover { dedans in withAnimation(j.anim(.survol)) { survolMedia = dedans } }
    }

    private func fleche(_ symbole: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.9)))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func actions(_ ig: CouleursInstagram) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "heart")
                Image(systemName: "bubble.right")
                Image(systemName: "paperplane")
            }
            Spacer()
            Image(systemName: "bookmark")
        }
        .font(.system(size: 21))
        .foregroundStyle(ig.texte)
        .overlay { points(ig) }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func points(_ ig: CouleursInstagram) -> some View {
        let n = nombre
        if n > 1 {
            let debut = n <= 5 ? 0 : min(max(0, index - 2), n - 5)
            let fin = n <= 5 ? n : debut + 5
            HStack(spacing: 4) {
                ForEach(debut..<fin, id: \.self) { i in
                    let bord = n > 5 && ((i == debut && debut > 0) || (i == fin - 1 && fin < n))
                    Circle()
                        .fill(i == index ? ig.pointActif : ig.pointInactif)
                        .frame(width: bord ? 4 : 6, height: bord ? 4 : 6)
                }
            }
            .animation(j.anim(.carrousel), value: index)
        }
    }

    private func legendeAttribuee(_ ig: CouleursInstagram) -> AttributedString {
        var nom = AttributedString(contenu.compteCourt)
        nom.font = .system(size: 14, weight: .semibold)
        var resultat = nom + AttributedString(" ")
        var mot = ""
        func vider() {
            guard !mot.isEmpty else { return }
            var m = AttributedString(mot)
            if mot.hasPrefix("#") || mot.hasPrefix("@") { m.foregroundColor = ig.lien }
            resultat += m
            mot = ""
        }
        for c in contenu.legende {
            if c == " " || c == "\n" {
                vider()
                resultat += AttributedString(String(c))
            } else {
                mot.append(c)
            }
        }
        vider()
        return resultat
    }

    private func legende(_ ig: CouleursInstagram) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(legendeAttribuee(ig))
                .font(.system(size: 14))
                .foregroundStyle(ig.texte)
                .lineLimit(legendeDepliee ? 12 : 2)
                .fixedSize(horizontal: false, vertical: true)
            if !legendeDepliee && contenu.legende.count > 80 {
                Button {
                    withAnimation(j.anim(.doux)) { legendeDepliee = true }
                } label: {
                    Text("… plus").font(.system(size: 14)).foregroundStyle(ig.secondaire)
                }
                .buttonStyle(.plain)
            }
            if let d = contenu.date {
                Text(d).font(.system(size: 12)).foregroundStyle(ig.secondaire)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private func reel(_ ig: CouleursInstagram) -> some View {
        ZStack(alignment: .bottomLeading) {
            ImageLocale(chemin: contenu.medias.first)
                .frame(width: largeurEcran, height: hauteurEcran)
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    avatar(28)
                    Text(contenu.compteCourt).font(.system(size: 14, weight: .semibold))
                    Text("Suivre")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.7)))
                }
                Text(contenu.legende).font(.system(size: 14)).lineLimit(2)
                if let m = contenu.musique {
                    Label(m, systemImage: "music.note").font(.system(size: 12)).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 14)
            .padding(.trailing, 72)
            .padding(.bottom, 34)
            VStack(spacing: 22) {
                Image(systemName: "heart")
                Image(systemName: "bubble.right")
                Image(systemName: "paperplane")
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 24))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
            .padding(.bottom, 44)
        }
        .frame(width: largeurEcran, height: hauteurEcran)
    }
}

// MARK: - Claude en direct

/// Capsule de la barre d'outils : ce que fait Claude, en une ligne. Passer `execution: nil` une fois le résultat vu.
struct IndicateurClaude: View {
    let execution: ExecutionClaude?
    let statut: ClaudeStatut?
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    private enum Etat { case inconnu, absent, pret, travail, fini, erreur }

    private var etat: Etat {
        if let e = execution, e.enCours { return .travail }
        if let s = statut, !s.pret { return .absent }
        if let e = execution, e.reussie { return .fini }
        if let e = execution, e.etat == "erreur" { return .erreur }
        return statut == nil ? .inconnu : .pret
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icone
                ZStack(alignment: .leading) {
                    Text(texteCourt)
                        .lineLimit(1)
                        .fixedSize()
                        .id(texte)
                        .transition(j.transition(.etape))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(j.texte)
                .clipped()
                if etat == .travail, let e = execution {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(e.libelleDuree(a: ctx.date) ?? "")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(j.texteSecondaire)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .fixedSize()
            .background(FondFlottant(forme: Capsule(), survol: survol))
            .overlay(Capsule().strokeBorder(j.trait, lineWidth: 1))
            .overlay(alignment: .bottom) {
                if etat == .travail { FiletProgression().frame(height: 2).padding(.horizontal, 10) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(j.anim(.etape), value: texte)
        .help(aide)
        .accessibilityLabel(texte)
    }

    @ViewBuilder private var icone: some View {
        switch etat {
        case .travail:
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(j.accentTexte)
                .symbolEffect(.pulse, isActive: j.niveau > .aucune)
        case .fini:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(j.succes)
                .symbolEffect(.bounce, value: execution?.id)
        case .erreur:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(j.alerte)
        case .absent:
            PointEtat(couleur: j.alerte)
        case .pret:
            PointEtat(couleur: j.succes)
        case .inconnu:
            PointEtat(couleur: j.texteTertiaire)
        }
    }

    private var texte: String {
        switch etat {
        case .travail: return execution?.etapeCourante?.texte ?? execution?.titreAffiche ?? "Claude travaille"
        case .fini: return "C'est prêt, voir"
        case .erreur: return "Claude s'est arrêté · pourquoi ?"
        case .absent: return statut?.installe == false ? "Installer Claude" : "Connecter Claude"
        case .pret: return "Claude est prêt"
        case .inconnu: return "Claude"
        }
    }

    /// 40 caractères au plus : la capsule garde la taille de son texte sans s'étirer.
    private var texteCourt: String { texte.count > 40 ? String(texte.prefix(39)) + "…" : texte }

    private var aide: String {
        switch etat {
        case .travail: return execution?.titreAffiche ?? "Claude travaille"
        case .absent: return statut?.conseil ?? "Claude n'est pas connecté"
        default: return "Ce que fait Claude"
        }
    }
}

/// Filet de 2 pt parcouru d'un reflet lent (Claude travaille).
struct FiletProgression: View {
    @Environment(\.jetons) private var j
    @Local private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(j.accent.opacity(0.25))
                if j.deplacements {
                    Capsule()
                        .fill(LinearGradient(colors: [j.accent.opacity(0), j.accent, j.accent.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: geo.size.width * phase)
                }
            }
            .clipShape(Capsule())
        }
        .onAppear {
            guard j.deplacements else { return }
            phase = -0.3
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// « Claude en coulisses » : titre, durée, étapes, dernier message ; à la fin, le résultat et la suite.
struct CarteActiviteClaude: View {
    let execution: ExecutionClaude
    var compacte = false
    /// Faux dans un popover (pas de carte dans la carte).
    var cadre = true
    var arreter: (() -> Void)? = nil
    var ouvrir: ((Ecran) -> Void)? = nil
    var reessayer: (() -> Void)? = nil
    var reconnecter: (() -> Void)? = nil
    @Environment(\.jetons) private var j
    @Local private var toutVoir = false

    private var maxVisibles: Int { compacte ? 3 : 5 }

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: j.rayons.feuille, style: .continuous)
        VStack(alignment: .leading, spacing: compacte ? j.esp.pile + 2 : j.esp.blocs) {
            enTete
            if !execution.etapes.isEmpty { etapes }
            if execution.enCours, let m = execution.message {
                VoixDeClaude("« \(m) »", filet: false, compacte: true)
                    .lineLimit(compacte ? 2 : 4)
                    .transition(.opacity)
            }
            fin
            if execution.enCours {
                Text("Tu peux fermer l'app : elle se rouvrira quand ce sera prêt.").typo(.legende)
            }
        }
        .padding(cadre ? (compacte ? j.esp.carte * 0.8 : j.esp.carte) : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forme.fill(cadre ? j.remplissageCarte : Color.clear))
        .overlay(forme.strokeBorder(cadre && j.systeme.augmenterContraste ? j.traitFort : Color.clear, lineWidth: 1))
        .overlay(cadre ? LisereHaut(rayon: j.rayons.feuille) : nil)
        .ombre(cadre ? .carte : .repos)
        .animation(j.anim(.etape), value: execution.etapes.count)
        .animation(j.anim(.doux), value: execution.etat)
        .accessibilityElement(children: .contain)
    }

    private var enTete: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Claude en coulisses").typo(.surtitre).lineLimit(1)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(execution.libelleDuree(a: ctx.date) ?? "")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(j.texteSecondaire)
                        .lineLimit(1)
                        .fixedSize()
                }
                if execution.enCours, let a = arreter {
                    Button("Arrêter", action: a)
                        .buttonStyle(.destructif)
                        .fixedSize()
                        .help("Arrêter le travail de Claude")
                }
            }
            Text(execution.titreAffiche)
                .typo(compacte ? .corpsFort : .titre3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var etapes: some View {
        let toutes = execution.etapes
        let cachees = toutVoir ? 0 : max(0, toutes.count - maxVisibles)
        let visibles = Array(toutes.suffix(toutes.count - cachees))
        return VStack(alignment: .leading, spacing: compacte ? 6 : 8) {
            if cachees > 0 {
                Button {
                    withAnimation(j.anim(.doux)) { toutVoir = true }
                } label: {
                    Text(cachees == 1 ? "1 étape faite" : "\(cachees) étapes faites")
                }
                .buttonStyle(.discret)
            }
            ForEach(visibles) { e in
                ligne(e)
                    .transition(j.transition(.etape))
            }
        }
        .background(alignment: .leading) {
            Rectangle().fill(j.trait).frame(width: 1).padding(.leading, 9.5).padding(.vertical, 10)
        }
    }

    private func ligne(_ e: EtapeClaude) -> some View {
        let courante = !e.fait && execution.enCours
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: e.fait || execution.reussie ? "checkmark.circle.fill" : SymboleEtape.valide(e.icone))
                .font(.system(size: 14))
                .foregroundStyle(e.fait || execution.reussie ? j.succes : j.accentTexte)
                .symbolVariant(.none)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: courante && j.niveau > .aucune)
                .frame(width: 20)
                .background(j.carte.opacity(cadre ? 1 : 0))
            Text(e.texte)
                .typo(.voixCarte, couleur: courante ? j.texte : j.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var fin: some View {
        if execution.reussie {
            VStack(alignment: .leading, spacing: j.esp.pile) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(j.succes)
                        .symbolEffect(.bounce, value: execution.reussie)
                    Text("C'est prêt.").typo(.titre3)
                }
                if let r = execution.resultat {
                    Text(r).typo(.voixCarte).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let e = execution.ecranSuivant, let o = ouvrir {
                    Button(CarteActiviteClaude.libelleOuvrir(e)) { o(e) }
                        .buttonStyle(.principal)
                        .padding(.top, 4)
                }
            }
            .transition(j.transition(.apparition))
        } else if execution.etat == "erreur" {
            VStack(alignment: .leading, spacing: j.esp.pile) {
                Label {
                    Text(execution.erreur ?? "Claude s'est arrêté avant la fin.").typo(.corps)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(j.alerte)
                }
                if let r = reconnecter, (execution.erreur ?? "").localizedCaseInsensitiveContains("connect") {
                    Button("Me reconnecter", action: r).buttonStyle(.secondaire)
                } else if let r = reessayer {
                    Button("Réessayer", action: r).buttonStyle(.secondaire)
                }
            }
            .transition(.opacity)
        } else if execution.etat == "annule" {
            Text("Arrêté. Rien n'a été publié.").typo(.corps, couleur: j.texteSecondaire)
        }
    }

    static func libelleOuvrir(_ e: Ecran) -> String {
        switch e {
        case .apercu: return "Voir l'aperçu"
        case .idees: return "Voir les idées"
        case .galeries: return "Voir les galeries"
        case .statistiques: return "Voir le bilan"
        case .aujourdhui: return "Voir la journée"
        default: return "Ouvrir"
        }
    }
}

// MARK: - Panneau « Demander à Claude »

struct MessagePanneau: Identifiable, Equatable {
    var id: String
    var deClaude: Bool
    var texte: String
    var le: Date? = nil
}

/// Panneau latéral (`.inspector`, 340 pt) : conversation libre avec Claude.
struct PanneauDemandeClaude: View {
    let messages: [MessagePanneau]
    let execution: ExecutionClaude?
    var contexte: String? = nil
    var suggestions: [String] = PanneauDemandeClaude.suggestionsParDefaut
    let envoyer: (String) -> Void
    let nouvelleConversation: () -> Void
    var retirerContexte: (() -> Void)? = nil
    @Environment(\.jetons) private var j
    @Local private var brouillon = ""

    static let suggestionsParDefaut = [
        "Passe l'app en mode sombre",
        "Des titres plus sobres",
        "Ajoute un créneau le samedi à 11 h",
        "Pourquoi l'idée 2 ?",
    ]

    private var occupe: Bool { execution?.enCours == true }
    private var brouillonPropre: String { brouillon.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(j.accentTexte)
                Text("Claude").typo(.titre3)
                Spacer()
                Button(action: nouvelleConversation) { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.icone)
                    .help("Nouvelle conversation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Filet()
            ScrollViewReader { lecteur in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { vide }
                        ForEach(messages) { m in
                            bulle(m).id(m.id).transition(j.transition(.etape))
                        }
                        if let e = execution, e.enCours {
                            CarteActiviteClaude(execution: e, compacte: true).id("activite")
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(j.anim(.doux)) { lecteur.scrollTo("fin", anchor: .bottom) }
                }
                .onChange(of: execution?.etapes.count) { _, _ in
                    withAnimation(j.anim(.doux)) { lecteur.scrollTo("fin", anchor: .bottom) }
                }
            }
            Filet()
            VStack(alignment: .leading, spacing: 8) {
                if let c = contexte {
                    HStack(spacing: 6) {
                        Pastille("À propos de : \(c)", symbole: "scope", ton: .douce)
                        if let r = retirerContexte {
                            Button(action: r) { Image(systemName: "xmark") }
                                .buttonStyle(BoutonIcone(diametre: 20))
                                .help("Ne plus parler de cet écran")
                        }
                    }
                }
                HStack(alignment: .bottom, spacing: 8) {
                    ChampDoux(texte: $brouillon, exemple: "Demande à Claude…", lignes: 1...6, envoyer: envoyerBrouillon)
                    Button(action: envoyerBrouillon) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(BoutonRond(.sombre, diametre: 36))
                    .disabled(brouillonPropre.isEmpty)
                    .help("Envoyer (⏎)")
                    .padding(.bottom, 3)
                }
                if occupe {
                    Text("Claude travaille : ton message partira dès qu'il aura fini.").typo(.legende)
                }
            }
            .padding(16)
        }
        .background(FondAmbiance(anime: false))
        .animation(j.anim(.doux), value: messages)
    }

    private func envoyerBrouillon() {
        let t = brouillonPropre
        guard !t.isEmpty else { return }
        envoyer(t)
        brouillon = ""
    }

    private var vide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Demande ce que tu veux : une autre idée, un changement d'apparence, une explication.")
                .typo(.chapo)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                Button { envoyer(s) } label: { Pastille(s, ton: .douce) }
                    .buttonStyle(.plain)
                    .survol(.ligne)
                    .entreeEnCascade(i)
            }
        }
    }

    @ViewBuilder private func bulle(_ m: MessagePanneau) -> some View {
        if m.deClaude {
            Text(m.texte)
                .typo(.reponse)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Spacer(minLength: 40)
                Text(m.texte)
                    .typo(.corps)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: j.rayons.feuille, style: .continuous).fill(j.fondDoux))
            }
        }
    }
}

// MARK: - Barre d'icônes (v2)

/// Un écran de la barre d'icônes.
struct ElementBarre<ID: Hashable>: Identifiable {
    let id: ID
    let titre: String
    let symbole: String
    /// Petit nombre sur l'icône (idées qui attendent, post à valider).
    var badge: Int? = nil

    init(id: ID, titre: String, symbole: String, badge: Int? = nil) {
        self.id = id
        self.titre = titre
        self.symbole = symbole
        self.badge = badge
    }
}

/// La barre à gauche, comme l'inspiration : le « + » rond et sombre en haut (créer un post, ⌘N), puis une
/// icône ronde par écran (nom au survol dans une bulle, ⌘1 à ⌘9), et un pied (état de Claude, compte).
/// À placer au-dessus du contenu (`.zIndex(1)`) : la bulle déborde à droite.
struct BarreIcones<ID: Hashable, Pied: View>: View {
    let elements: [ElementBarre<ID>]
    @Binding var selection: ID
    var nouveau: (() -> Void)?
    var titreNouveau: String
    let pied: Pied
    @Environment(\.jetons) private var j

    init(elements: [ElementBarre<ID>], selection: Binding<ID>, nouveau: (() -> Void)? = nil,
         titreNouveau: String = "Créer un post", @ViewBuilder pied: () -> Pied) {
        self.elements = elements
        _selection = selection
        self.nouveau = nouveau
        self.titreNouveau = titreNouveau
        self.pied = pied()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let n = nouveau {
                BulleSurvol(titre: titreNouveau) {
                    Button(action: n) { Image(systemName: "plus") }
                        .buttonStyle(BoutonRond(.sombre, diametre: j.esp.icone + 4))
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityLabel(titreNouveau)
                }
                .padding(.bottom, 8)
            }
            ForEach(Array(elements.enumerated()), id: \.element.id) { i, e in
                IconeBarre(element: e, choisi: e.id == selection, raccourci: i < 9 ? i + 1 : nil) {
                    withAnimation(j.anim(.selection)) { selection = e.id }
                }
                .entreeEnCascade(i, pas: 0.03)
            }
            Spacer(minLength: 12)
            pied
        }
        .padding(.vertical, 22)
        .frame(width: j.esp.icone + 32)
        .frame(maxHeight: .infinity)
    }
}

extension BarreIcones where Pied == EmptyView {
    init(elements: [ElementBarre<ID>], selection: Binding<ID>, nouveau: (() -> Void)? = nil,
         titreNouveau: String = "Créer un post") {
        self.init(elements: elements, selection: selection, nouveau: nouveau, titreNouveau: titreNouveau) { EmptyView() }
    }
}

extension BarreIcones where ID == Ecran {
    /// Les écrans de l'app (titre et symbole de `Ecran`), avec leurs badges.
    init(ecrans: [Ecran], selection: Binding<Ecran>, badges: [Ecran: Int] = [:], nouveau: (() -> Void)? = nil,
         @ViewBuilder pied: () -> Pied) {
        self.init(elements: ecrans.map { ElementBarre(id: $0, titre: $0.titre, symbole: $0.symbole, badge: badges[$0]) },
                  selection: selection, nouveau: nouveau, pied: pied)
    }
}

extension BarreIcones where ID == Ecran, Pied == EmptyView {
    init(ecrans: [Ecran], selection: Binding<Ecran>, badges: [Ecran: Int] = [:], nouveau: (() -> Void)? = nil) {
        self.init(ecrans: ecrans, selection: selection, badges: badges, nouveau: nouveau) { EmptyView() }
    }
}

private struct IconeBarre<ID: Hashable>: View {
    let element: ElementBarre<ID>
    let choisi: Bool
    let raccourci: Int?
    let action: () -> Void
    @Environment(\.jetons) private var j
    @Local private var survol = false

    var body: some View {
        let d = j.esp.icone
        let forme = RoundedRectangle(cornerRadius: j.rayons.pilule, style: .continuous)
        BulleSurvol(titre: element.titre) {
            Button(action: action) {
                Image(systemName: element.symbole)
                    .font(.system(size: d * 0.40, weight: choisi ? .semibold : .regular))
                    .symbolVariant(choisi ? .fill : j.varianteSymboles)
                    .foregroundStyle(choisi ? j.texte : j.texte.opacity(survol ? 0.9 : 0.62))
                    .frame(width: d, height: d)
                    .background(forme.fill(fond))
                    .overlay(forme.strokeBorder(Color.white.opacity(j.schema == .dark ? (choisi ? 0.16 : 0.06) : (choisi ? 0.9 : 0.5)),
                                                lineWidth: 1))
                    .overlay(alignment: .topTrailing) { badge }
                    .contentShape(forme)
                    .ombre(choisi ? .carte : .repos)
            }
            .buttonStyle(.plain)
            .modifier(Raccourci(numero: raccourci))
            .onHover { survol = $0 }
        }
        .overlay(alignment: .leading) {
            // Repère de l'écran courant, collé au bord de la barre.
            Capsule()
                .fill(j.encre)
                .frame(width: 3, height: choisi ? 18 : 0)
                .offset(x: -16)
                .opacity(choisi ? 1 : 0)
        }
        .animation(j.anim(.survol), value: survol)
        .animation(j.anim(.selection), value: choisi)
        .accessibilityLabel(element.titre)
        .accessibilityValue(element.badge.map { "\($0) en attente" } ?? "")
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
    }

    private var fond: Color {
        if j.schema == .dark { return Color.white.opacity(choisi ? 0.16 : (survol ? 0.11 : 0.06)) }
        return Color.white.opacity(choisi ? 1 : (survol ? 0.85 : 0.55))
    }

    @ViewBuilder private var badge: some View {
        if let b = element.badge, b > 0 {
            Text("\(b)")
                .font(Font.jakarta(10, graisse: 700))
                .foregroundStyle(j.surAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(j.accent))
                .overlay(Capsule().strokeBorder(j.fond, lineWidth: 2))
                .offset(x: 4, y: -3)
                .transition(j.transition(.apparition))
        }
    }
}

private struct Raccourci: ViewModifier {
    let numero: Int?

    func body(content: Content) -> some View {
        if let n = numero, let c = "\(n)".first {
            content.keyboardShortcut(KeyEquivalent(c), modifiers: .command)
        } else {
            content
        }
    }
}

/// Bulle sombre qui donne le nom d'une icône au survol, à sa droite (sans délai, contrairement à `.help`).
struct BulleSurvol<Contenu: View>: View {
    let titre: String
    let contenu: Contenu
    @Environment(\.jetons) private var j
    @Local private var survol = false

    init(titre: String, @ViewBuilder contenu: () -> Contenu) {
        self.titre = titre
        self.contenu = contenu()
    }

    var body: some View {
        contenu
            .onHover { dedans in withAnimation(j.anim(.survol)) { survol = dedans } }
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    if survol {
                        Text(titre)
                            .font(Font.jakarta(12.5, graisse: 560))
                            .foregroundStyle(j.surEncre)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(j.encre))
                            .ombre(.flottante)
                            .offset(x: geo.size.width + 12, y: (geo.size.height - 28) / 2)
                            .transition(j.deplacements
                                ? AnyTransition.opacity.combined(with: .offset(x: -6)) : .opacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
    }
}

// MARK: - Points de progression

/// Points en bas des pages d'onboarding : le courant est plein, les autres en contour. `aller` les rend cliquables
/// (jamais vers une étape à venir).
struct PointsProgression: View {
    let total: Int
    let courant: Int
    var aller: ((Int) -> Void)? = nil
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                let plein = i == courant
                let point = Capsule()
                    .fill(plein ? j.encre : Color.clear)
                    .overlay(Capsule().strokeBorder(j.encre.opacity(plein ? 1 : 0.55), lineWidth: 1.2))
                    .frame(width: plein && j.deplacements ? 20 : 8, height: 8)
                    .padding(4)
                    .contentShape(Rectangle())
                if let a = aller, i < courant {
                    Button { a(i) } label: { point }.buttonStyle(.plain)
                } else {
                    point
                }
            }
        }
        .animation(j.anim(.selection), value: courant)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(courant + 1) sur \(total)")
    }
}

// MARK: - Page d'onboarding (plein écran, sans carte)

/// Une étape de l'onboarding, plein écran sur le dégradé, sans boîte : illustration, titre, texte, contenu
/// (champs, choix), action principale, points de progression en bas. Pas de « Passer » : seulement `retour`.
/// Pour changer d'étape : `.id(etape)` + `.transition(j.transition(.suivante))` + `withAnimation(j.anim(.page))`.
struct PageOnboarding<Illustration: View, Contenu: View, Action: View>: View {
    let etape: Int
    let total: Int
    let titre: String
    var texte: String?
    var retour: (() -> Void)?
    var fond: Bool
    let illustration: Illustration
    let contenu: Contenu
    let action: Action
    @Environment(\.jetons) private var j

    init(etape: Int, total: Int, titre: String, texte: String? = nil, retour: (() -> Void)? = nil, fond: Bool = true,
         @ViewBuilder illustration: () -> Illustration,
         @ViewBuilder contenu: () -> Contenu,
         @ViewBuilder action: () -> Action) {
        self.etape = etape
        self.total = total
        self.titre = titre
        self.texte = texte
        self.retour = retour
        self.fond = fond
        self.illustration = illustration()
        self.contenu = contenu()
        self.action = action()
    }

    /// Marge haute qui laisse les feux tricolores libres (barre de titre cachée).
    static var margeFeux: CGFloat { 44 }

    var body: some View {
        GeometryReader { geo in
            let compacte = geo.size.height < 780
            VStack(spacing: 0) {
                HStack {
                    if let r = retour {
                        Button(action: r) { Image(systemName: "chevron.left") }
                            .buttonStyle(BoutonRond(.claire, diametre: 38))
                            .keyboardShortcut(.leftArrow, modifiers: .command)
                            .help("Revenir")
                            .accessibilityLabel("Revenir")
                    }
                    Spacer()
                }
                .frame(height: 38)
                .padding(.horizontal, j.esp.page)
                .padding(.top, PageOnboarding.margeFeux)

                // Le milieu défile quand il est plus haut que la fenêtre ; « ‹ » et les points restent visibles.
                GeometryReader { zone in
                    ScrollView(.vertical, showsIndicators: false) {
                        colonne(compacte: compacte)
                            .padding(.vertical, compacte ? 8 : 16)
                            .frame(maxWidth: .infinity, minHeight: zone.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                PointsProgression(total: total, courant: etape)
                    .padding(.top, compacte ? 8 : 14)
                    .padding(.bottom, compacte ? 18 : 30)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { if fond { FondAmbiance() } }
    }

    private func colonne(compacte: Bool) -> some View {
        VStack(spacing: 0) {
            illustration
                .frame(maxWidth: compacte ? 240 : 380, maxHeight: compacte ? 150 : 280)
                .entreeEnCascade(0, pas: 0.07)
                .padding(.bottom, compacte ? j.esp.blocs + 4 : j.esp.sections)
            Text(titre)
                .typo(compacte ? .titre1 : .affiche)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .entreeEnCascade(1, pas: 0.07)
            if let t = texte {
                Text(t)
                    .typo(.chapo)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, compacte ? j.esp.pile + 2 : j.esp.blocs)
                    .entreeEnCascade(2, pas: 0.07)
            }
            contenu
                .frame(maxWidth: 440)
                .padding(.top, compacte ? j.esp.blocs + 4 : j.esp.sections * 0.75)
                .entreeEnCascade(3, pas: 0.07)
            action
                .padding(.top, compacte ? j.esp.blocs + 4 : j.esp.sections * 0.75)
                .entreeEnCascade(4, pas: 0.07)
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, j.esp.page)
    }
}

extension PageOnboarding where Contenu == EmptyView {
    init(etape: Int, total: Int, titre: String, texte: String? = nil, retour: (() -> Void)? = nil, fond: Bool = true,
         @ViewBuilder illustration: () -> Illustration, @ViewBuilder action: () -> Action) {
        self.init(etape: etape, total: total, titre: titre, texte: texte, retour: retour, fond: fond,
                  illustration: illustration, contenu: { EmptyView() }, action: action)
    }
}

// MARK: - Étape de l'assistant de création

/// Une étape de la création d'un post. `aValider` : elle attend son accord (sinon Claude enchaîne).
struct EtapeCreation: Identifiable, Equatable {
    let id: String
    let titre: String
    let symbole: String
    var aValider: Bool

    /// Les six étapes : idée, Claude au travail, photos, légende, musique, aperçu.
    /// `aValider` : les clés de `creation.etapes_a_valider` (photos, legende, musique) ; l'aperçu se valide toujours.
    static func etapes(aValider: [String] = ["photos", "legende", "musique"]) -> [EtapeCreation] {
        let v = Set(aValider.map { Apparence.simplifier($0) })
        return [
            EtapeCreation(id: "idee", titre: "Idée", symbole: "lightbulb", aValider: true),
            EtapeCreation(id: "claude", titre: "Claude au travail", symbole: "sparkles", aValider: false),
            EtapeCreation(id: "photos", titre: "Photos", symbole: "photo.on.rectangle", aValider: v.contains("photos")),
            EtapeCreation(id: "legende", titre: "Légende", symbole: "text.quote", aValider: v.contains("legende")),
            EtapeCreation(id: "musique", titre: "Musique", symbole: "music.note", aValider: v.contains("musique")),
            EtapeCreation(id: "apercu", titre: "Aperçu", symbole: "iphone", aValider: true),
        ]
    }
}

/// Rappel des étapes en haut de l'assistant : faites (coche), en cours (pilule blanche), à venir (point) ;
/// un petit point « à toi » marque celles qu'elle valide.
struct RappelEtapes: View {
    let etapes: [EtapeCreation]
    let courante: Int
    @Environment(\.jetons) private var j

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(etapes.enumerated()), id: \.element.id) { i, e in
                if i > 0 {
                    Capsule()
                        .fill(i <= courante ? j.encre.opacity(0.45) : j.traitFort)
                        .frame(width: 18, height: 1.5)
                }
                marque(e, i)
            }
        }
        .animation(j.anim(.selection), value: courante)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libelle)
    }

    @ViewBuilder private func marque(_ e: EtapeCreation, _ i: Int) -> some View {
        if i == courante {
            HStack(spacing: 7) {
                Image(systemName: e.symbole)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolVariant(.none)
                    .symbolEffect(.pulse, isActive: e.id == "claude" && j.niveau > .aucune)
                Text(e.titre).font(Font.jakarta(13, graisse: 600))
            }
            .foregroundStyle(j.texte)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(j.schema == .dark ? Color.white.opacity(0.12) : Color.white))
            .overlay(alignment: .topTrailing) { if e.aValider { pointAToi.offset(x: 1, y: -1) } }
            .ombre(.carte)
            .transition(j.transition(.apparition))
        } else {
            HStack(spacing: 6) {
                ZStack {
                    if i < courante {
                        Circle().fill(j.encre)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(j.surEncre)
                    } else {
                        Circle().strokeBorder(j.traitFort, lineWidth: 1.2)
                    }
                }
                .frame(width: 16, height: 16)
                .overlay(alignment: .topTrailing) { if e.aValider && i > courante { pointAToi.offset(x: 3, y: -3) } }
                Text(e.titre)
                    .font(Font.jakarta(12.5, graisse: 500))
                    .foregroundStyle(i < courante ? j.texteSecondaire : j.texteTertiaire)
                    .lineLimit(1)
            }
            .help(e.aValider ? "\(e.titre) : à toi de valider" : "\(e.titre) : Claude s'en occupe")
        }
    }

    private var pointAToi: some View {
        Circle().fill(j.aToi).frame(width: 7, height: 7).overlay(Circle().strokeBorder(j.fond, lineWidth: 1.5))
    }

    private var libelle: String {
        guard etapes.indices.contains(courante) else { return "Création terminée" }
        let e = etapes[courante]
        return "Étape \(courante + 1) sur \(etapes.count) : \(e.titre)\(e.aValider ? ", à toi de valider" : "")"
    }
}

/// Gabarit d'une étape de l'assistant de création (même style que l'onboarding, une étape à la fois) :
/// en haut, fermer (×) et le rappel des étapes ; au centre, titre, texte et contenu (photos, légende…) ;
/// en bas, « Retour » (pilule claire) à gauche et les actions (pilule sombre principale) à droite.
struct EtapeAssistant<Contenu: View, Actions: View>: View {
    let etapes: [EtapeCreation]
    let courante: Int
    let titre: String
    var texte: String?
    var retour: (() -> Void)?
    var fermer: (() -> Void)?
    var fond: Bool
    let contenu: Contenu
    let actions: Actions
    @Environment(\.jetons) private var j

    init(etapes: [EtapeCreation], courante: Int, titre: String, texte: String? = nil,
         retour: (() -> Void)? = nil, fermer: (() -> Void)? = nil, fond: Bool = true,
         @ViewBuilder contenu: () -> Contenu, @ViewBuilder actions: () -> Actions) {
        self.etapes = etapes
        self.courante = courante
        self.titre = titre
        self.texte = texte
        self.retour = retour
        self.fermer = fermer
        self.fond = fond
        self.contenu = contenu()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RappelEtapes(etapes: etapes, courante: courante)
                HStack {
                    if let f = fermer {
                        Button(action: f) { Image(systemName: "xmark") }
                            .buttonStyle(BoutonRond(.claire, diametre: 36))
                            .keyboardShortcut(.cancelAction)
                            .help("Fermer : le brouillon est gardé")
                            .accessibilityLabel("Fermer")
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, j.esp.page)
            .padding(.top, PageOnboarding<EmptyView, EmptyView, EmptyView>.margeFeux)

            VStack(spacing: j.esp.blocs) {
                Text(titre)
                    .typo(.titre1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .entreeEnCascade(0, pas: 0.06)
                if let t = texte {
                    Text(t)
                        .typo(.chapo)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                        .entreeEnCascade(1, pas: 0.06)
                }
            }
            .padding(.top, j.esp.blocs + 8)
            .padding(.horizontal, j.esp.page)

            // Le contenu prend sa hauteur naturelle, centré ; il défile s'il dépasse (jamais coupé net).
            GeometryReader { zone in
                ScrollView(.vertical, showsIndicators: true) {
                    contenu
                        .frame(maxWidth: 1000)
                        .padding(.horizontal, j.esp.page)
                        .padding(.vertical, j.esp.sections * 0.6)
                        .frame(maxWidth: .infinity, minHeight: zone.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .entreeEnCascade(2, pas: 0.06)

            HStack(spacing: j.esp.blocs) {
                if let r = retour {
                    Button(action: r) { Label("Retour", systemImage: "chevron.left") }
                        .buttonStyle(BoutonPilule(.claire))
                }
                Spacer(minLength: j.esp.blocs)
                actions
            }
            .padding(.horizontal, j.esp.page)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { if fond { FondAmbiance() } }
    }
}

// MARK: - Barre « Demande à Claude »

/// Un raccourci en pilule sous le champ : un clic envoie `demande` telle quelle.
struct RaccourciClaude: Identifiable, Equatable {
    let id: String
    let titre: String
    let symbole: String
    let demande: String

    init(_ titre: String, symbole: String, demande: String) {
        id = titre
        self.titre = titre
        self.symbole = symbole
        self.demande = demande
    }

    static let parDefaut = [
        RaccourciClaude("Une idée de post", symbole: "lightbulb", demande: "Propose-moi une idée de post pour cette semaine."),
        RaccourciClaude("Écrire une légende", symbole: "text.quote", demande: "Aide-moi à écrire la légende du prochain post."),
        RaccourciClaude("Choisir des photos", symbole: "photo.on.rectangle", demande: "Choisis les plus belles photos de ma dernière galerie."),
        RaccourciClaude("Changer l'apparence", symbole: "paintpalette", demande: "J'aimerais changer l'apparence de l'app."),
    ]
}

/// La barre en bas de l'accueil, comme l'inspiration : une note au-dessus (à gauche) et l'état de Claude
/// (à droite), un grand champ blanc avec le bouton rond d'envoi, puis les raccourcis en pilules sombres et « … ».
/// ⏎ envoie ; un raccourci envoie sa demande.
struct BarreDemandeClaude: View {
    @Binding var texte: String
    var exemple: String = "Demande à Claude… par exemple « une idée pour samedi »"
    var raccourcis: [RaccourciClaude] = RaccourciClaude.parDefaut
    var note: String? = "Claude connaît ta charte, tes galeries et tes statistiques"
    var etat: String? = nil
    /// Claude travaille : le message attendra qu'il ait fini.
    var occupe = false
    /// « … » au bout des raccourcis (ouvre le panneau Claude).
    var plus: (() -> Void)? = nil
    let envoyer: (String) -> Void
    @Environment(\.jetons) private var j
    @FocusState private var focus: Bool

    private var propre: String { texte.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let externe = RoundedRectangle(cornerRadius: j.rayons.champ + 8, style: .continuous)
        let interne = RoundedRectangle(cornerRadius: j.rayons.champ, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if note != nil || etat != nil {
                HStack(spacing: 8) {
                    if let n = note {
                        Label(n, systemImage: "sparkles").labelStyle(LabelLegende())
                    }
                    Spacer(minLength: 8)
                    if let e = etat {
                        HStack(spacing: 6) {
                            PointEtat(couleur: occupe ? j.accent : j.succes, pulse: occupe, diametre: 7)
                            Text(e).typo(.legende)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    TextField(exemple, text: $texte, axis: .vertical)
                        .textFieldStyle(.plain)
                        .typo(.champ)
                        .lineLimit(1...4)
                        .focused($focus)
                        .focusEffectDisabled()
                        .onSubmit(envoyerTexte)
                    Button(action: envoyerTexte) { Image(systemName: "arrow.up") }
                        .buttonStyle(BoutonRond(.sombre, diametre: 40))
                        .disabled(propre.isEmpty)
                        .help(occupe ? "Envoyer : partira quand Claude aura fini" : "Envoyer (⏎)")
                        .accessibilityLabel("Envoyer à Claude")
                }
                if !raccourcis.isEmpty || plus != nil {
                    // Toute la rangée si elle tient, sinon elle défile de côté (pilules jamais tronquées).
                    ViewThatFits(in: .horizontal) {
                        rangeeRaccourcis
                        ScrollView(.horizontal, showsIndicators: false) { rangeeRaccourcis }
                    }
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
            .background(interne.fill(j.schema == .dark ? j.surfaceElevee : Color.white))
            .overlay(interne.strokeBorder(focus ? j.encre.opacity(0.5) : j.trait.opacity(0.8), lineWidth: 1))
        }
        .padding(8)
        // Fond givré presque opaque : rien de ce qui passe dessous ne se lit à travers.
        .background {
            ZStack {
                if !j.systeme.reduireTransparence { externe.fill(.regularMaterial) }
                externe.fill(j.carte.opacity(j.systeme.reduireTransparence ? 1 : 0.86))
            }
        }
        .overlay(externe.strokeBorder(Color.white.opacity(j.schema == .dark ? 0.08 : 0.7), lineWidth: 1))
        .ombre(.flottante)
        .animation(j.anim(.survol), value: focus)
    }

    private var rangeeRaccourcis: some View {
        HStack(spacing: 8) {
            ForEach(raccourcis) { r in
                Button { envoyer(r.demande) } label: { Label(r.titre, systemImage: r.symbole) }
                    .buttonStyle(BoutonPilule(.sombre, taille: .petite))
            }
            if let p = plus {
                Button(action: p) { Image(systemName: "ellipsis") }
                    .buttonStyle(BoutonRond(.sombre, diametre: max(28, j.esp.hauteurBouton - 10)))
                    .help("Plus de demandes")
                    .accessibilityLabel("Plus de demandes")
            }
            Spacer(minLength: 0)
        }
    }

    /// Hauteur de la barre (champ d'une ligne), pour réserver la place en bas d'un écran :
    /// `.safeAreaInset(edge: .bottom) { BarreDemandeClaude(…) }` ou `.padding(.bottom, BarreDemandeClaude.hauteur(j) + marge)`.
    static func hauteur(_ j: Jetons, note: Bool = true, raccourcis: Bool = true) -> CGFloat {
        let ligneNote: CGFloat = note ? 4 + ceil(j.taille(.legende) * 1.35) + 8 : 0
        let champ: CGFloat = 14 + 40 + 14
        let rangee: CGFloat = raccourcis ? 14 + max(28, j.esp.hauteurBouton - 10) : 0
        return 8 + ligneNote + champ + rangee + 8
    }

    private func envoyerTexte() {
        let t = propre
        guard !t.isEmpty else { return }
        envoyer(t)
        texte = ""
    }
}

/// Libellé discret : icône et texte en légende.
private struct LabelLegende: LabelStyle {
    @Environment(\.jetons) private var j

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.font(.system(size: 12, weight: .medium)).foregroundStyle(j.texteSecondaire)
            configuration.title.typo(.legende)
        }
    }
}


// MARK: - Verre liquide (macOS 26) avec repli

extension View {
    /// Le verre liquide d'Apple (macOS 26 et plus) ; avant, une matière translucide de même forme.
    @ViewBuilder func verreLiquide<S: Shape>(_ forme: S, interactif: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactif ? .regular.interactive() : .regular, in: forme)
        } else {
            self.background(.ultraThinMaterial, in: forme)
                .overlay(forme.stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}
