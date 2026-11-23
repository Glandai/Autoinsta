import AppKit
import Combine
import CoreText
import SwiftUI

// Apparence de l'app, version 2 : tous les jetons de app/DESIGN.md §2, calculés depuis config/app.yaml (type `Apparence`).
//
//   Racine :  @StateObject private var theme = Theme.partage
//             VueRacine().themeStudio(theme).onAppear { theme.suivre(etat) }   (suit etat.apparence)
//   Vues :    @Environment(\.jetons) private var j     →  j.encre, j.esp.page, Text(…).typo(.titre1), j.anim(.doux)…
//
// Pas de macros (compilé sans Xcode) : clé d'environnement écrite à la main, ObservableObject + @Published.

// MARK: - Couleur sRGB (calculs)

struct RVB: Equatable {
    var r: Double
    var v: Double
    var b: Double

    init(_ r: Double, _ v: Double, _ b: Double) {
        self.r = min(1, max(0, r))
        self.v = min(1, max(0, v))
        self.b = min(1, max(0, b))
    }

    /// « #rrggbb » (ou « #rgb ») ; une valeur illisible donne `defaut`.
    init(hex: String, defaut: RVB) {
        var s = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { self = defaut; return }
        self.init(Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
    }

    /// Raccourci pour les tables écrites ici (valeurs sûres).
    init(_ hex: String) { self.init(hex: hex, defaut: .noir) }

    static let blanc = RVB(1, 1, 1)
    static let noir = RVB(0, 0, 0)

    /// m(a, b, t) = a + (b − a) × t
    func melange(_ autre: RVB, _ t: Double) -> RVB {
        RVB(r + (autre.r - r) * t, v + (autre.v - v) * t, b + (autre.b - b) * t)
    }

    /// Luminance relative WCAG.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(v) + 0.0722 * lin(b)
    }

    func contraste(_ autre: RVB) -> Double {
        let a = luminance, b = autre.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// tsl(c, L, ×S, Smax) : même teinte, luminosité `l`, saturation multipliée puis plafonnée.
    func tsl(l: Double, facteurS: Double = 1, sMax: Double = 1) -> RVB {
        let (h, _, s) = versTSL()
        return RVB.depuisTSL(h, l, min(s * facteurS, sMax))
    }

    /// Pousse la couleur vers le noir (fond clair) ou le blanc (fond sombre) jusqu'au contraste voulu.
    func assurer(_ minimum: Double, sur fond: RVB) -> RVB {
        let cible = fond.luminance > 0.18 ? RVB.noir : RVB.blanc
        var t = 0.0
        var r = self
        while r.contraste(fond) < minimum && t < 1 {
            t += 0.02
            r = melange(cible, t)
        }
        return r
    }

    var couleur: Color { Color(.sRGB, red: r, green: v, blue: b, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: v, blue: b, alpha: 1) }
    var hex: String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((v * 255).rounded()), Int((b * 255).rounded()))
    }

    private func versTSL() -> (Double, Double, Double) {
        let ma = max(r, v, b), mi = min(r, v, b)
        let l = (ma + mi) / 2
        guard ma != mi else { return (0, l, 0) }
        let d = ma - mi
        let s = l > 0.5 ? d / (2 - ma - mi) : d / (ma + mi)
        var h: Double
        if ma == r { h = (v - b) / d + (v < b ? 6 : 0) } else if ma == v { h = (b - r) / d + 2 } else { h = (r - v) / d + 4 }
        h /= 6
        return (h, l, s)
    }

    private static func depuisTSL(_ h: Double, _ l: Double, _ s: Double) -> RVB {
        guard s > 0 else { return RVB(l, l, l) }
        func f(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return RVB(f(p, q, h + 1 / 3), f(p, q, h), f(p, q, h - 1 / 3))
    }
}

// MARK: - Réglages du système (accessibilité)

struct OptionsSysteme: Equatable {
    var reduireAnimations = false
    var augmenterContraste = false
    var reduireTransparence = false

    static var actuelles: OptionsSysteme {
        let w = NSWorkspace.shared
        return OptionsSysteme(reduireAnimations: w.accessibilityDisplayShouldReduceMotion,
                              augmenterContraste: w.accessibilityDisplayShouldIncreaseContrast,
                              reduireTransparence: w.accessibilityDisplayShouldReduceTransparency)
    }
}

// MARK: - Choix de config/app.yaml

enum ModeApparence: String { case auto, clair, sombre
    init(_ texte: String) { self = ModeApparence(rawValue: Apparence.simplifier(texte)) ?? .auto }
}

/// `titres` : la police des titres. `police` = la même que le texte (par défaut).
enum StyleTitres: String { case police, serif, arrondi, standard
    init(_ texte: String) { self = StyleTitres(rawValue: Apparence.simplifier(texte)) ?? .police }
    var dessin: Font.Design {
        switch self {
        case .serif: return .serif
        case .arrondi: return .rounded
        case .standard, .police: return .default
        }
    }
}

/// `police` : la police de l'interface.
enum PoliceTexte: String { case jakarta, systeme, arrondie
    init(_ texte: String) {
        switch Apparence.simplifier(texte) {
        case "systeme", "sf", "sf pro", "system": self = .systeme
        case "arrondie", "arrondi", "rounded": self = .arrondie
        default: self = .jakarta
        }
    }
}

enum Densite: String { case compacte, confortable, aeree
    init(_ texte: String) { self = Densite(rawValue: Apparence.simplifier(texte)) ?? .confortable }
}

enum NiveauAnimations: Int, Comparable { case aucune, discretes, normales, riches
    init(_ texte: String) {
        switch Apparence.simplifier(texte) {
        case "aucune": self = .aucune
        case "discretes": self = .discretes
        case "riches": self = .riches
        default: self = .normales
        }
    }
    static func < (a: NiveauAnimations, b: NiveauAnimations) -> Bool { a.rawValue < b.rawValue }
}

/// Lecture souple de `points` (Bool, ou texte « oui », « non », « true »…) : compile quel que soit le type du modèle.
func lireOui(_ v: Bool) -> Bool { v }
func lireOui(_ v: Bool?) -> Bool { v ?? true }
func lireOui(_ v: String) -> Bool {
    !["non", "no", "false", "faux", "0", "aucun", "aucuns", "sans"].contains(Apparence.simplifier(v))
}
func lireOui(_ v: String?) -> Bool { v.map(lireOui) ?? true }

// MARK: - Ambiances (DESIGN.md §2.1)

/// `ambiance` : le dégradé de fond et les couleurs qui vont avec.
enum Ambiance: String, CaseIterable, Identifiable {
    case provence, lavande, aube, sauge, nuit
    var id: String { rawValue }

    init(_ texte: String) { self = Ambiance(rawValue: Apparence.simplifier(texte)) ?? .provence }

    var nom: String {
        switch self {
        case .provence: return "Provence"
        case .lavande: return "Lavande"
        case .aube: return "Aube"
        case .sauge: return "Sauge"
        case .nuit: return "Nuit"
        }
    }

    /// Une phrase pour Réglages › Apparence.
    var description: String {
        switch self {
        case .provence: return "Abricot, lavande et blé, comme un soir d'été."
        case .lavande: return "Pervenche et lavande, une lueur pêche."
        case .aube: return "Corail, or et rose, le ciel du matin."
        case .sauge: return "Sauge, tilleul et lin, très calme."
        case .nuit: return "Indigo et violet, une lumière de soirée."
        }
    }

    func definition(sombre: Bool) -> DefinitionAmbiance {
        switch (self, sombre) {
        case (.provence, false):
            return DefinitionAmbiance(fond: RVB("#f6f1eb"),
                                      taches: [RVB("#f5c39c"), RVB("#d2c6f0"), RVB("#f7e1b8"), RVB("#c6d6bd")],
                                      encre: RVB("#22201c"), accent: RVB("#5b6236"), accentDoux: RVB("#f1dccb"),
                                      trame: RVB("#3a2f25"))
        case (.provence, true):
            return DefinitionAmbiance(fond: RVB("#16130f"),
                                      taches: [RVB("#7a4124"), RVB("#40356e"), RVB("#5f4920"), RVB("#2c4331")],
                                      encre: RVB("#f4eee6"), accent: RVB("#c9cf9c"), accentDoux: RVB("#f1dccb"),
                                      trame: RVB("#ffffff"))
        case (.lavande, false):
            return DefinitionAmbiance(fond: RVB("#eff0f8"),
                                      taches: [RVB("#b5bdef"), RVB("#d9cdf6"), RVB("#f8d9c4"), RVB("#c2dbf8")],
                                      encre: RVB("#1b1c2c"), accent: RVB("#4c4fa6"), accentDoux: RVB("#e4e1f6"),
                                      trame: RVB("#2a2d55"))
        case (.lavande, true):
            return DefinitionAmbiance(fond: RVB("#0f1020"),
                                      taches: [RVB("#2b3580"), RVB("#47307f"), RVB("#633b42"), RVB("#1c4375")],
                                      encre: RVB("#eef0fa"), accent: RVB("#aeb2f2"), accentDoux: RVB("#e4e1f6"),
                                      trame: RVB("#ffffff"))
        case (.aube, false):
            return DefinitionAmbiance(fond: RVB("#faf1ed"),
                                      taches: [RVB("#f7bba5"), RVB("#f9d79c"), RVB("#ebbfd9"), RVB("#c8d8f1")],
                                      encre: RVB("#261b1c"), accent: RVB("#b0533a"), accentDoux: RVB("#f7dfd3"),
                                      trame: RVB("#4a2a22"))
        case (.aube, true):
            return DefinitionAmbiance(fond: RVB("#18100f"),
                                      taches: [RVB("#7c3329"), RVB("#744f1b"), RVB("#632a55"), RVB("#21365e")],
                                      encre: RVB("#f8ece6"), accent: RVB("#f0a487"), accentDoux: RVB("#f7dfd3"),
                                      trame: RVB("#ffffff"))
        case (.sauge, false):
            return DefinitionAmbiance(fond: RVB("#f0f3ed"),
                                      taches: [RVB("#bfd6b8"), RVB("#e3eac6"), RVB("#c8e1dc"), RVB("#f0e0c8")],
                                      encre: RVB("#1b221d"), accent: RVB("#3e6a4c"), accentDoux: RVB("#dfe9d8"),
                                      trame: RVB("#22352a"))
        case (.sauge, true):
            return DefinitionAmbiance(fond: RVB("#0f1411"),
                                      taches: [RVB("#2d4d35"), RVB("#454f24"), RVB("#1e4842"), RVB("#50412a")],
                                      encre: RVB("#edf3ec"), accent: RVB("#a3cdb0"), accentDoux: RVB("#dfe9d8"),
                                      trame: RVB("#ffffff"))
        case (.nuit, false):
            return DefinitionAmbiance(fond: RVB("#e9eaf4"),
                                      taches: [RVB("#a5aee4"), RVB("#c4b1e9"), RVB("#9ec4e8"), RVB("#e8c3d7")],
                                      encre: RVB("#13152a"), accent: RVB("#3d43a0"), accentDoux: RVB("#dcdcf3"),
                                      trame: RVB("#1c2050"))
        case (.nuit, true):
            return DefinitionAmbiance(fond: RVB("#0a0b16"),
                                      taches: [RVB("#1f2e7a"), RVB("#3f206e"), RVB("#0d4566"), RVB("#511f4b")],
                                      encre: RVB("#eceefb"), accent: RVB("#9ea6f5"), accentDoux: RVB("#dcdcf3"),
                                      trame: RVB("#ffffff"))
        }
    }
}

/// Les couleurs sources d'une ambiance pour un schéma.
struct DefinitionAmbiance: Equatable {
    /// Fond uni sous les taches.
    var fond: RVB
    /// Quatre taches de couleur qui dérivent (haut gauche, haut droite, bas droite, bas gauche au repos).
    var taches: [RVB]
    /// Encre : texte, pilules sombres, bouton « + » (claire en mode sombre : les pilules s'inversent).
    var encre: RVB
    /// Accent : sélection, liens, progression.
    var accent: RVB
    var accentDoux: RVB
    /// Couleur des points de la trame.
    var trame: RVB
}

// MARK: - Palette (DESIGN.md §2.1)

/// Les couleurs calculées, en sRGB, pour un schéma (clair ou sombre).
struct PaletteRVB: Equatable {
    var fond, surface, surfaceElevee, texte, texteSecondaire, texteTertiaire, trait, traitFort: RVB
    var accent, accentSurvol, accentTexte, surAccent, accentDoux, fondDoux, aToi: RVB
    var succes, alerte, fondSucces, fondAlerte, selection: RVB
    // v2
    var encre, encreSurvol, surEncre, carte, carteBord, trame: RVB
    var taches: [RVB]

    init(apparence a: Apparence, sombre: Bool, contraste: Bool) {
        let c = a.couleurs
        let d = CouleursApparence()
        let amb = Ambiance(a.ambiance).definition(sombre: sombre)
        // Une couleur de config/app.yaml remplace celle de l'ambiance seulement si elle a été changée.
        func choix(_ valeur: String, _ origine: String, _ ambiance: RVB) -> RVB {
            Apparence.simplifier(valeur) == Apparence.simplifier(origine) ? ambiance : RVB(hex: valeur, defaut: ambiance)
        }
        // L'apparence est fixée par le moteur (simplification du 22/11) : seules l'ambiance et le mode comptent ;
        // les couleurs fines de config/app.yaml sont ignorées (`choix` reste pour un retour éventuel).
        _ = choix
        let acc = amb.accent
        let doux = amb.accentDoux
        let f = amb.fond
        let suc = RVB(hex: c.succes, defaut: RVB(hex: d.succes, defaut: .noir))
        let ale = RVB(hex: c.alerte, defaut: RVB(hex: d.alerte, defaut: .noir))

        fond = f
        taches = amb.taches
        trame = amb.trame
        if !sombre {
            texte = amb.encre.assurer(contraste ? 15 : 12, sur: f)
            surface = f.melange(.blanc, 0.72)
            surfaceElevee = .blanc
            carte = f.melange(.blanc, 0.90)
            carteBord = contraste ? f.melange(texte, 0.30) : .blanc
            texteSecondaire = texte.melange(f, contraste ? 0.22 : 0.42).assurer(4.6, sur: f)
            texteTertiaire = texte.melange(f, 0.58)
            trait = f.melange(texte, contraste ? 0.26 : 0.10)
            traitFort = f.melange(texte, contraste ? 0.50 : 0.20)
            accent = acc.assurer(contraste ? 7 : 4.5, sur: f)
            accentSurvol = accent.melange(.noir, 0.15)
            accentDoux = doux
            fondDoux = f.melange(doux, 0.62).melange(.blanc, 0.25)
            aToi = doux.tsl(l: 0.36).assurer(4.5, sur: fondDoux)
            succes = suc.assurer(4.5, sur: f)
            alerte = ale.assurer(4.5, sur: f)
            fondSucces = f.melange(.blanc, 0.5).melange(suc, 0.10)
            fondAlerte = f.melange(.blanc, 0.5).melange(ale, 0.10)
            selection = f.melange(acc, 0.10)
            encre = texte
            encreSurvol = texte.melange(.blanc, 0.16)
            surEncre = f.melange(.blanc, 0.85)
        } else {
            texte = amb.encre.assurer(contraste ? 15 : 12, sur: f)
            surface = f.melange(.blanc, 0.05)
            surfaceElevee = f.melange(.blanc, 0.10)
            carte = f.melange(.blanc, 0.075)
            carteBord = f.melange(.blanc, contraste ? 0.35 : 0.13)
            texteSecondaire = texte.melange(f, contraste ? 0.22 : 0.40).assurer(4.6, sur: f)
            texteTertiaire = texte.melange(f, 0.58)
            trait = f.melange(texte, contraste ? 0.28 : 0.13)
            traitFort = f.melange(texte, contraste ? 0.50 : 0.24)
            accent = acc.assurer(contraste ? 7 : 4.5, sur: f)
            accentSurvol = accent.melange(.blanc, 0.15)
            accentDoux = doux
            fondDoux = f.melange(doux, 0.14)
            aToi = doux.assurer(4.5, sur: fondDoux)
            succes = suc.tsl(l: 0.62, facteurS: 1, sMax: 0.40)
            alerte = ale.tsl(l: 0.64, facteurS: 1, sMax: 0.75)
            fondSucces = f.melange(succes, 0.14)
            fondAlerte = f.melange(alerte, 0.14)
            selection = f.melange(accent, 0.16)
            encre = texte
            encreSurvol = texte.melange(.noir, 0.10)
            surEncre = f
        }
        surAccent = accent.contraste(.blanc) >= accent.contraste(f.luminance < 0.18 ? f : texte)
            ? (sombre ? f : .blanc) : (sombre ? f : texte)
        accentTexte = accent.contraste(fond) >= 4.5 ? accent : texte
    }
}

/// Les mêmes couleurs, prêtes pour SwiftUI. Lues par `j.encre`, `j.fond`… (voir `Jetons`).
struct Palette: Equatable {
    let rvb: PaletteRVB
    let fond, surface, surfaceElevee, texte, texteSecondaire, texteTertiaire, trait, traitFort: Color
    let accent, accentSurvol, accentTexte, surAccent, accentDoux, fondDoux, aToi: Color
    let succes, alerte, fondSucces, fondAlerte, selection: Color
    let encre, encreSurvol, surEncre, carte, carteBord, trame: Color
    let taches: [Color]

    init(_ p: PaletteRVB) {
        rvb = p
        fond = p.fond.couleur; surface = p.surface.couleur; surfaceElevee = p.surfaceElevee.couleur
        texte = p.texte.couleur; texteSecondaire = p.texteSecondaire.couleur; texteTertiaire = p.texteTertiaire.couleur
        trait = p.trait.couleur; traitFort = p.traitFort.couleur
        accent = p.accent.couleur; accentSurvol = p.accentSurvol.couleur; accentTexte = p.accentTexte.couleur
        surAccent = p.surAccent.couleur; accentDoux = p.accentDoux.couleur; fondDoux = p.fondDoux.couleur
        aToi = p.aToi.couleur; succes = p.succes.couleur; alerte = p.alerte.couleur
        fondSucces = p.fondSucces.couleur; fondAlerte = p.fondAlerte.couleur; selection = p.selection.couleur
        encre = p.encre.couleur; encreSurvol = p.encreSurvol.couleur; surEncre = p.surEncre.couleur
        carte = p.carte.couleur; carteBord = p.carteBord.couleur; trame = p.trame.couleur
        taches = p.taches.map(\.couleur)
    }

    init(apparence: Apparence, schema: ColorScheme, systeme: OptionsSysteme) {
        self.init(PaletteRVB(apparence: apparence, sombre: schema == .dark, contraste: systeme.augmenterContraste))
    }
}

/// Les couleurs d'Instagram dans le téléphone de l'Aperçu (fidèles à l'app, indépendantes du thème).
struct CouleursInstagram {
    let fond, texte, secondaire, lien, pointActif, pointInactif, separateur: Color

    init(sombre: Bool) {
        func c(_ h: String) -> Color { RVB(hex: h, defaut: .noir).couleur }
        fond = c(sombre ? "#000000" : "#ffffff")
        texte = c(sombre ? "#f5f5f5" : "#000000")
        secondaire = c(sombre ? "#a8a8a8" : "#737373")
        lien = c(sombre ? "#e0f1ff" : "#00376b")
        pointActif = c("#0095f6")
        pointInactif = c(sombre ? "#555555" : "#a8a8a8")
        separateur = c(sombre ? "#262626" : "#dbdbdb")
    }
}

// MARK: - Police Plus Jakarta Sans

/// Plus Jakarta Sans (fichier variable, graisses 200 à 800, OFL), dans app/Ressources/Polices.
/// `construire.sh` règle ATSApplicationFontsPath ; on enregistre aussi les fichiers au démarrage, par sécurité.
enum Typographie {
    static let famille = "Plus Jakarta Sans"
    private static let romaine = "PlusJakartaSans-Regular"
    private static let italique = "PlusJakartaSans-Italic"
    private static let axeGraisse = 0x7767_6874   // 'wght'
    private static let verrou = NSLock()
    nonisolated(unsafe) private static var dejaEnregistre = false
    nonisolated(unsafe) private static var disponible: Bool?
    nonisolated(unsafe) private static var cache: [String: CTFont] = [:]

    /// Enregistre les .ttf / .otf du paquet (Contents/Resources/Polices) ou d'un dossier donné. Sans effet la deuxième fois.
    static func enregistrerPolices(dossier: URL? = nil) {
        verrou.lock()
        defer { verrou.unlock() }
        if dossier == nil && dejaEnregistre { return }
        if dossier == nil { dejaEnregistre = true }
        var dossiers: [URL] = []
        if let d = dossier { dossiers.append(d) }
        if let r = Bundle.main.resourceURL {
            dossiers.append(r.appendingPathComponent("Polices"))
            dossiers.append(r)
        }
        let fm = FileManager.default
        for d in dossiers {
            guard let fichiers = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { continue }
            for f in fichiers where ["ttf", "otf", "ttc"].contains(f.pathExtension.lowercased())
                && f.lastPathComponent.lowercased().hasPrefix("plusjakarta") {
                var erreur: Unmanaged<CFError>?
                // Déjà actif (ATSApplicationFontsPath) : l'erreur est attendue et sans conséquence.
                _ = CTFontManagerRegisterFontsForURL(f as CFURL, .process, &erreur)
            }
        }
        disponible = nil
        cache = [:]
    }

    /// Vrai si Plus Jakarta Sans est utilisable (sinon : repli sur la police du système).
    static var jakartaDisponible: Bool {
        verrou.lock()
        defer { verrou.unlock() }
        if let d = disponible { return d }
        let f = CTFontCreateWithName(romaine as CFString, 12, nil)
        let ok = (CTFontCopyFamilyName(f) as String) == famille
        disponible = ok
        return ok
    }

    /// La police à une graisse précise de l'axe variable (200 à 800).
    static func ctFont(taille: CGFloat, graisse: CGFloat, italique estItalique: Bool) -> CTFont {
        let g = min(800, max(200, graisse))
        let cle = "\(taille)|\(g)|\(estItalique)"
        verrou.lock()
        if let f = cache[cle] { verrou.unlock(); return f }
        verrou.unlock()
        let attributs: [CFString: Any] = [
            kCTFontNameAttribute: (estItalique ? italique : romaine) as CFString,
            kCTFontVariationAttribute: [axeGraisse: g] as CFDictionary,
        ]
        let descripteur = CTFontDescriptorCreateWithAttributes(attributs as CFDictionary)
        let f = CTFontCreateWithFontDescriptor(descripteur, taille, nil)
        verrou.lock()
        cache[cle] = f
        verrou.unlock()
        return f
    }

    static func jakarta(_ taille: CGFloat, graisse: CGFloat, italique: Bool = false) -> Font {
        Font(ctFont(taille: taille, graisse: graisse, italique: italique))
    }

    /// Graisse numérique → graisse du système (replis).
    static func graisseSysteme(_ g: CGFloat) -> Font.Weight {
        switch g {
        case ..<250: return .ultraLight
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .heavy
        }
    }
}

// MARK: - Typographie, espacements, rayons, ombres, mouvement

/// Rôles typographiques (DESIGN.md §2.3).
enum RoleTexte: CaseIterable {
    case affiche, titre1, titre2, titre3, voix, voixCarte, reponse, chiffre, numero
    case chapo, corps, corpsFort, legende, surtitre, bouton, boutonSecondaire, champ, mono
}

/// Espacements selon la densité (DESIGN.md §2.4).
struct Espacements: Equatable {
    let page, sections, blocs, carte, gouttiere, pile, ligne, hauteurBouton, interligne, largeurTexte, largeurPage: CGFloat
    /// Diamètre des boutons ronds de la barre d'icônes.
    let icone: CGFloat
    let controle: ControlSize

    init(_ d: Densite) {
        switch d {
        case .compacte:
            page = 28; sections = 32; blocs = 12; carte = 18; gouttiere = 14; pile = 6; ligne = 30
            hauteurBouton = 34; interligne = 2; largeurTexte = 600; icone = 38; controle = .small
        case .confortable:
            page = 44; sections = 44; blocs = 16; carte = 24; gouttiere = 18; pile = 8; ligne = 34
            hauteurBouton = 40; interligne = 4; largeurTexte = 620; icone = 42; controle = .regular
        case .aeree:
            page = 60; sections = 60; blocs = 24; carte = 30; gouttiere = 26; pile = 12; ligne = 40
            hauteurBouton = 46; interligne = 6; largeurTexte = 640; icone = 46; controle = .large
        }
        largeurPage = 1180
    }
}

/// Rayons à partir de `arrondi` (DESIGN.md §2.5), toujours en `.continuous`.
/// `pilule` vaut 999 (capsule) dès que `arrondi` ≥ 6 : `RoundedRectangle` ramène le rayon à la demi-hauteur.
struct Rayons: Equatable {
    let carte, feuille, bouton, pilule, champ, photo, vignette: CGFloat
    let telephone: CGFloat = 54
    let ecranTelephone: CGFloat = 44

    init(arrondi: Int) {
        let r = CGFloat(min(28, max(0, arrondi)))
        carte = min(32, (r * 1.6).rounded())
        feuille = min(40, r * 2)
        pilule = r >= 6 ? 999 : r
        bouton = pilule
        champ = min(26, (r * 1.6).rounded())
        photo = min(12, (r * 0.6).rounded())
        vignette = min(4, (r * 0.3).rounded())
    }
}

enum NiveauOmbre { case repos, carte, survol, flottante, feuille }

struct Ombre: Equatable {
    let couleur: Color
    let rayon: CGFloat
    let y: CGFloat
}

/// Toutes les animations de l'app (DESIGN.md §2.7).
enum Mouvement {
    case appui, survol, selection, doux, page, cascade, bandeau, etape, frise, carrousel, compteur
    case theme, revelation, celebration, pulsation
}

enum TransitionStudio { case ecran, bandeau, etape, apparition, panneau, suivante, precedente }

// MARK: - Jetons

/// Tous les jetons pour une apparence et un schéma. Valeur légère, injectée dans l'environnement (`\.jetons`).
@dynamicMemberLookup
struct Jetons: Equatable {
    let apparence: Apparence
    let schema: ColorScheme
    let systeme: OptionsSysteme
    let couleurs: Palette
    let mode: ModeApparence
    let ambiance: Ambiance
    let police: PoliceTexte
    let titres: StyleTitres
    let densite: Densite
    /// Niveau demandé dans config/app.yaml.
    let niveauDemande: NiveauAnimations
    /// Niveau effectif : plafonné à `discretes` si « Réduire les animations » est actif.
    let niveau: NiveauAnimations
    let esp: Espacements
    let rayons: Rayons
    /// `points` demandé et « Augmenter le contraste » inactif.
    let trameActive: Bool

    init(apparence a0: Apparence, schema: ColorScheme, systeme: OptionsSysteme = .actuelles) {
        let a = a0.normalisee()
        apparence = a
        self.schema = schema
        self.systeme = systeme
        couleurs = Palette(apparence: a, schema: schema, systeme: systeme)
        mode = ModeApparence(a.mode)
        ambiance = Ambiance(a.ambiance)
        // Fixés (simplification du 22/11) : seuls `mode`, `ambiance`, `nom_affiche` et `salutation` se règlent.
        police = .jakarta
        titres = .police
        densite = .confortable
        niveauDemande = .normales
        niveau = systeme.reduireAnimations ? .discretes : .normales
        esp = Espacements(.confortable)
        rayons = Rayons(arrondi: 14)
        trameActive = false
    }

    static func defaut(_ schema: ColorScheme = .light) -> Jetons {
        Jetons(apparence: .defaut, schema: schema, systeme: OptionsSysteme())
    }

    static func == (a: Jetons, b: Jetons) -> Bool {
        a.apparence == b.apparence && a.schema == b.schema && a.systeme == b.systeme
    }

    /// `j.encre`, `j.fond`, `j.texteSecondaire`…
    subscript(dynamicMember chemin: KeyPath<Palette, Color>) -> Color { couleurs[keyPath: chemin] }

    // MARK: Fond animé

    /// Le dégradé ne bouge pas : animations « aucune » ou « Réduire les animations ».
    var fondFige: Bool { niveau == .aucune || systeme.reduireAnimations }

    /// Durée d'un aller de dérive des taches (secondes) : très lent, animé par Core Animation (hors de l'app).
    var periodeDerive: Double { 50 }

    /// Opacité des taches (moins fortes avec « Augmenter le contraste »).
    var opaciteTaches: Double {
        if systeme.augmenterContraste { return 0.35 }
        return schema == .dark ? 0.78 : 0.92
    }

    /// Compatibilité : la trame de points est retirée (toujours 0).
    var opaciteTrame: Double { 0 }

    // MARK: Couleurs dérivées

    /// L'accent contraste à moins de 3:1 avec le fond : Apparence le signale, les liens passent en texte.
    var accentPeuLisible: Bool { couleurs.rvb.accent.contraste(couleurs.rvb.fond) < 3 }

    /// Compatibilité 1.2 : il n'y a plus de grain (la trame de points le remplace).
    var opaciteGrain: Double { 0 }

    /// Ce qui flotte : matériau, ou surface élevée si la transparence est réduite.
    var materiauFlottant: AnyShapeStyle {
        systeme.reduireTransparence ? AnyShapeStyle(couleurs.surfaceElevee) : AnyShapeStyle(.regularMaterial)
    }

    /// Remplissage d'une carte posée sur le dégradé : blanc très doux, opaque si la transparence est réduite.
    var remplissageCarte: Color {
        if systeme.reduireTransparence || systeme.augmenterContraste { return couleurs.carte }
        return schema == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.80)
    }

    var varianteSymboles: SymbolVariants { .fill }

    // MARK: Typographie

    /// compacte ×0,92, confortable ×1, aérée ×1,08.
    var echelle: CGFloat {
        switch densite {
        case .compacte: return 0.92
        case .confortable: return 1
        case .aeree: return 1.08
        }
    }

    func taille(_ r: RoleTexte) -> CGFloat {
        let base: CGFloat
        switch r {
        case .affiche: base = 54
        case .titre1: base = 36
        case .titre2: base = 25
        case .titre3: base = 18
        case .voix: base = 17
        case .voixCarte, .reponse: base = 15
        case .chiffre: base = 40
        case .numero: base = 44
        case .chapo: base = 16
        case .corps, .corpsFort, .bouton: base = 14
        case .legende, .mono: base = 12
        case .surtitre: base = 12
        case .boutonSecondaire: base = 13.5
        case .champ: base = 15
        }
        return max(11, (base * echelle * 2).rounded() / 2)
    }

    /// Graisse sur l'axe variable de Plus Jakarta Sans (200 à 800). Gros titres légers, texte calme.
    func graisse(_ r: RoleTexte) -> CGFloat {
        switch r {
        case .affiche: return 330
        case .titre1: return 360
        case .titre2: return 430
        case .titre3: return 580
        case .chiffre: return 300
        case .numero: return 260
        case .voix, .voixCarte, .reponse, .chapo, .corps, .champ: return 400
        case .legende: return 450
        case .corpsFort, .surtitre, .bouton: return 600
        case .boutonSecondaire: return 520
        case .mono: return 400
        }
    }

    private var estTitre: (RoleTexte) -> Bool {
        { [.affiche, .titre1, .titre2, .titre3, .chiffre, .numero].contains($0) }
    }

    func police(_ r: RoleTexte) -> Font {
        let t = taille(r)
        let g = graisse(r)
        if r == .mono { return .system(size: t, design: .monospaced) }
        let italique = r == .voix || r == .voixCarte
        var f: Font
        if estTitre(r) && titres != .police {
            f = .system(size: t, weight: graisseTitreSysteme(r), design: titres.dessin)
        } else {
            switch police {
            case .jakarta where Typographie.jakartaDisponible:
                f = Typographie.jakarta(t, graisse: g, italique: italique)
            case .arrondie:
                f = .system(size: t, weight: Typographie.graisseSysteme(g + 40), design: .rounded)
            default:
                f = .system(size: t, weight: Typographie.graisseSysteme(g))
            }
            if italique && !(police == .jakarta && Typographie.jakartaDisponible) { f = f.italic() }
        }
        return r == .chiffre ? f.monospacedDigit() : f
    }

    /// Graisses quand les titres prennent une police du système (`titres: serif | arrondi | standard`).
    private func graisseTitreSysteme(_ r: RoleTexte) -> Font.Weight {
        switch (titres, r) {
        case (.serif, .titre3): return .medium
        case (.serif, .chiffre), (.serif, .numero): return .light
        case (.serif, _): return .regular
        case (.arrondi, .affiche), (.arrondi, .titre1): return .medium
        case (.arrondi, .chiffre): return .regular
        case (.arrondi, _): return .medium
        case (_, .titre3): return .semibold
        case (_, .titre2): return .medium
        default: return .light
        }
    }

    /// Approche (tracking) en points : les gros titres sont serrés.
    func approche(_ r: RoleTexte) -> CGFloat {
        let t = taille(r)
        switch r {
        case .affiche: return -0.032 * t
        case .titre1: return -0.026 * t
        case .titre2: return -0.018 * t
        case .titre3: return -0.006 * t
        case .chiffre, .numero: return -0.03 * t
        case .surtitre: return 0.2
        default: return 0
        }
    }

    /// Interligne ajouté.
    func interligne(_ r: RoleTexte) -> CGFloat {
        switch r {
        case .voix: return 5
        case .voixCarte, .reponse: return 3 + esp.interligne / 2
        case .chapo: return 6
        case .corps, .corpsFort, .champ: return esp.interligne + 1
        case .legende: return 2
        default: return 0
        }
    }

    func couleurParDefaut(_ r: RoleTexte) -> Color {
        switch r {
        case .chapo, .legende, .surtitre, .mono: return couleurs.texteSecondaire
        case .numero: return couleurs.accentTexte
        default: return couleurs.texte
        }
    }

    // MARK: Ombres

    func ombres(_ n: NiveauOmbre) -> [Ombre] {
        let sombre = schema == .dark
        // Teinte de l'ombre en clair : l'encre mêlée à la première tache (ombre colorée, jamais grise).
        let teinte = sombre ? Color.black : couleurs.rvb.encre.melange(couleurs.rvb.taches.first ?? .noir, 0.35).couleur
        switch n {
        case .repos:
            return []
        case .carte:
            return [Ombre(couleur: teinte.opacity(sombre ? 0.30 : 0.035), rayon: 1, y: 1),
                    Ombre(couleur: teinte.opacity(sombre ? 0.30 : 0.07), rayon: 28, y: 12)]
        case .survol:
            return [Ombre(couleur: teinte.opacity(sombre ? 0.35 : 0.05), rayon: 2, y: 1),
                    Ombre(couleur: teinte.opacity(sombre ? 0.45 : 0.12), rayon: 34, y: 18)]
        case .flottante:
            return [Ombre(couleur: teinte.opacity(sombre ? 0.45 : 0.05), rayon: 1, y: 1),
                    Ombre(couleur: teinte.opacity(sombre ? 0.40 : 0.14), rayon: 30, y: 14)]
        case .feuille:
            return [Ombre(couleur: teinte.opacity(sombre ? 0.55 : 0.18), rayon: 40, y: 22)]
        }
    }

    // MARK: Mouvement

    /// Faux si « Réduire les animations » est actif ou sous le niveau `normales` : tout devient fondu.
    var deplacements: Bool { niveau >= .normales && !systeme.reduireAnimations }

    /// `nil` au niveau `aucune` (et pour ce qui n'existe pas au niveau courant).
    func anim(_ m: Mouvement) -> Animation? {
        switch niveau {
        case .aucune:
            return nil
        case .discretes:
            switch m {
            case .appui, .cascade, .revelation, .celebration: return nil
            case .survol: return .easeOut(duration: 0.12)
            case .frise: return .easeInOut(duration: 0.3)
            case .carrousel: return .easeInOut(duration: 0.25)
            case .theme: return .easeInOut(duration: 0.25)
            case .pulsation: return Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            default: return .easeInOut(duration: 0.2)
            }
        case .normales, .riches:
            let riche = niveau == .riches
            switch m {
            case .appui: return .spring(response: 0.22, dampingFraction: 0.75)
            case .survol: return .easeOut(duration: 0.18)
            case .selection: return .spring(response: 0.35, dampingFraction: 0.80)
            case .doux: return .spring(response: 0.40, dampingFraction: 0.86)
            case .page: return riche ? .spring(response: 0.62, dampingFraction: 0.88) : .spring(response: 0.52, dampingFraction: 0.92)
            case .cascade: return .spring(response: 0.45, dampingFraction: 0.85)
            case .bandeau: return .spring(response: 0.40, dampingFraction: 0.80)
            case .etape: return .spring(response: 0.35, dampingFraction: 0.85)
            case .frise: return .easeInOut(duration: 0.5)
            case .carrousel: return .spring(response: 0.40, dampingFraction: 0.90)
            case .compteur: return .spring(response: 0.30, dampingFraction: 0.90)
            case .theme: return .easeInOut(duration: riche ? 0.6 : 0.45)
            case .revelation: return .easeOut(duration: riche ? 1.2 : 0.9)
            case .celebration: return riche ? .spring(response: 0.60, dampingFraction: 0.55) : .spring(response: 0.50, dampingFraction: 0.62)
            case .pulsation: return Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            }
        }
    }

    /// Délai d'un élément d'une entrée en cascade (8 éléments au plus).
    func delaiCascade(_ index: Int, pas: Double = 0.04) -> Double { Double(min(max(index, 0), 7)) * pas }

    func transition(_ t: TransitionStudio) -> AnyTransition {
        guard niveau > .aucune else { return .identity }
        guard deplacements else { return .opacity }
        switch t {
        case .ecran: return .asymmetric(insertion: AnyTransition.opacity.combined(with: .offset(y: 10)), removal: .opacity)
        case .bandeau: return AnyTransition.move(edge: .bottom).combined(with: .opacity)
        case .etape: return AnyTransition.move(edge: .top).combined(with: .opacity)
        case .apparition: return AnyTransition.scale(scale: 0.96).combined(with: .opacity)
        case .panneau: return AnyTransition.move(edge: .trailing).combined(with: .opacity)
        case .suivante:
            return .asymmetric(insertion: AnyTransition.offset(x: 48).combined(with: .opacity),
                               removal: AnyTransition.offset(x: -48).combined(with: .opacity))
        case .precedente:
            return .asymmetric(insertion: AnyTransition.offset(x: -48).combined(with: .opacity),
                               removal: AnyTransition.offset(x: 48).combined(with: .opacity))
        }
    }
}

// MARK: - Activité de l'app

/// L'app est-elle au premier plan ? Les animations permanentes (pulsations, filets, rotation, minuteurs, fond)
/// s'arrêtent quand elle passe en arrière-plan : `@ObservedObject private var app = ActiviteApp.partage` puis `app.active`.
@MainActor
final class ActiviteApp: ObservableObject {
    static let partage = ActiviteApp()
    @Published private(set) var active = true
    private var observateurs: [NSObjectProtocol] = []

    private init() {
        active = NSApp?.isActive ?? true
        let centre = NotificationCenter.default
        observateurs.append(centre.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = true }
        })
        observateurs.append(centre.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = false }
        })
    }
}

// MARK: - Environnement

private struct CleJetons: EnvironmentKey {
    /// Sans injection : les jetons courants du thème partagé (rien ne casse pendant la refonte des écrans).
    static var defaultValue: Jetons { ThemeCourant.partage.jetons() }
}

extension EnvironmentValues {
    var jetons: Jetons {
        get { self[CleJetons.self] }
        set { self[CleJetons.self] = newValue }
    }
}

/// Copie du thème courant lisible hors du fil principal (valeur par défaut de `\.jetons`,
/// couleurs de compatibilité `Color.olive`, `Color.surface`…, `Font.titre`).
final class ThemeCourant: @unchecked Sendable {
    static let partage = ThemeCourant()

    private let verrou = NSLock()
    private var apparence = Apparence.defaut
    private var systeme = OptionsSysteme()
    private var sombre = false
    private var clair = PaletteRVB(apparence: .defaut, sombre: false, contraste: false)
    private var fonce = PaletteRVB(apparence: .defaut, sombre: true, contraste: false)
    private var cache: Jetons?

    func mettreAJour(apparence a: Apparence, systeme s: OptionsSysteme, sombre z: Bool) {
        verrou.lock()
        defer { verrou.unlock() }
        if a != apparence || s != systeme {
            clair = PaletteRVB(apparence: a, sombre: false, contraste: s.augmenterContraste)
            fonce = PaletteRVB(apparence: a, sombre: true, contraste: s.augmenterContraste)
        }
        apparence = a
        systeme = s
        sombre = z
        cache = nil
    }

    func jetons() -> Jetons {
        verrou.lock()
        defer { verrou.unlock() }
        if let j = cache { return j }
        let j = Jetons(apparence: apparence, schema: sombre ? .dark : .light, systeme: systeme)
        cache = j
        return j
    }

    var styleTitres: StyleTitres {
        verrou.lock()
        defer { verrou.unlock() }
        return StyleTitres(apparence.titres)
    }

    func palette(sombre z: Bool) -> PaletteRVB {
        verrou.lock()
        defer { verrou.unlock() }
        return z ? fonce : clair
    }

    /// Couleur dynamique : suit le mode de la fenêtre et le thème courant au moment du dessin.
    func couleur(_ chemin: KeyPath<PaletteRVB, RVB>) -> Color {
        let nom = NSColor.Name("studio." + String(describing: chemin))
        let ns = NSColor(name: nom) { apparence in
            let z = apparence.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ThemeCourant.partage.palette(sombre: z)[keyPath: chemin].nsColor
        }
        return Color(nsColor: ns)
    }
}

// MARK: - Theme

/// Le thème de l'app : relit `Apparence` (config/app.yaml), suit le mode du système et ses réglages
/// d'accessibilité, et publie les jetons du schéma effectif.
@MainActor
@dynamicMemberLookup
final class Theme: ObservableObject {
    static let partage = Theme()

    @Published private(set) var apparence: Apparence
    @Published private(set) var systeme: OptionsSysteme
    /// Jetons du schéma effectif (clair ou sombre).
    @Published private(set) var jetons: Jetons

    private var systemeSombre: Bool
    private var observateurs: [NSObjectProtocol] = []
    private var observationApparence: NSKeyValueObservation?
    private var abonnement: AnyCancellable?

    init(apparence: Apparence = .defaut) {
        Typographie.enregistrerPolices()
        let a = apparence.normalisee()
        let s = OptionsSysteme.actuelles
        let z = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        self.apparence = a
        systeme = s
        systemeSombre = z
        let schema = Theme.schema(ModeApparence(a.mode), systemeSombre: z)
        jetons = Jetons(apparence: a, schema: schema, systeme: s)
        ThemeCourant.partage.mettreAJour(apparence: a, systeme: s, sombre: schema == .dark)
        // NSApp n'existe pas forcément encore : on s'abonne au premier tour de boucle.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.observerSysteme()
                self?.appliquerAuxFenetres()
            }
        }
    }

    subscript<T>(dynamicMember chemin: KeyPath<Jetons, T>) -> T { jetons[keyPath: chemin] }

    var mode: ModeApparence { ModeApparence(apparence.mode) }

    /// Schéma imposé par `mode` (nil en mode auto : celui du système).
    var schemaForce: ColorScheme? {
        switch mode {
        case .clair: return .light
        case .sombre: return .dark
        case .auto: return nil
        }
    }

    /// Schéma effectif.
    var schema: ColorScheme { jetons.schema }

    /// Applique une apparence (relue dans config/app.yaml ou en cours d'édition) : fondu `.theme`.
    func appliquer(_ a: Apparence) {
        let n = a.normalisee()
        guard n != apparence else { return }
        apparence = n
        appliquerAuxFenetres()
        recalculer(anime: true)
    }

    /// Jetons d'un autre schéma ou d'une apparence en brouillon (aperçu en direct de Réglages › Apparence).
    func jetons(pour schema: ColorScheme, apparence a: Apparence? = nil) -> Jetons {
        Jetons(apparence: a ?? apparence, schema: schema, systeme: systeme)
    }

    /// Suit `etat.apparence` (relue dès que config/app.yaml change) : à appeler une fois, à la racine.
    func suivre(_ etat: EtatApp) {
        appliquer(etat.apparence)
        abonnement = etat.$apparence
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] a in MainActor.assumeIsolated { self?.appliquer(a) } }
    }

    // MARK: Interne

    private static func schema(_ mode: ModeApparence, systemeSombre: Bool) -> ColorScheme {
        switch mode {
        case .clair: return .light
        case .sombre: return .dark
        case .auto: return systemeSombre ? .dark : .light
        }
    }

    private func recalculer(anime: Bool) {
        let schema = Theme.schema(mode, systemeSombre: systemeSombre)
        let nouveaux = Jetons(apparence: apparence, schema: schema, systeme: systeme)
        ThemeCourant.partage.mettreAJour(apparence: apparence, systeme: systeme, sombre: schema == .dark)
        guard nouveaux != jetons else { return }
        if anime, let a = nouveaux.anim(.theme) {
            withAnimation(a) { jetons = nouveaux }
        } else {
            jetons = nouveaux
        }
    }

    /// Fenêtres, feuilles et popovers suivent le mode choisi.
    private func appliquerAuxFenetres() {
        guard let app = NSApp else { return }
        switch mode {
        case .clair: app.appearance = NSAppearance(named: .aqua)
        case .sombre: app.appearance = NSAppearance(named: .darkAqua)
        case .auto: app.appearance = nil
        }
    }

    private func observerSysteme() {
        guard observateurs.isEmpty else { return }
        let centre = NSWorkspace.shared.notificationCenter
        observateurs.append(centre.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systeme = OptionsSysteme.actuelles
                self.recalculer(anime: false)
            }
        })
        // Mode clair/sombre du système (utile en mode auto).
        observateurs.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relireModeSysteme() }
        })
        if let app = NSApp {
            observationApparence = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.relireModeSysteme() } }
            }
        }
        relireModeSysteme()
    }

    private func relireModeSysteme() {
        let z: Bool
        if mode == .auto, let app = NSApp {
            z = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        } else {
            z = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        guard z != systemeSombre else { return }
        systemeSombre = z
        recalculer(anime: true)
    }
}

// MARK: - Modificateurs de thème

extension View {
    /// À la racine de chaque fenêtre : jetons, thème, schéma, teinte, variante des symboles, taille des contrôles, police.
    func themeStudio(_ theme: Theme) -> some View { modifier(AppliquerTheme(theme: theme)) }

    /// Police, approche, interligne et couleur d'un rôle typographique.
    func typo(_ role: RoleTexte, couleur: Color? = nil) -> some View { modifier(Typo(role: role, couleur: couleur)) }

    /// Ombre d'un niveau (DESIGN.md §2.6).
    func ombre(_ niveau: NiveauOmbre) -> some View { modifier(ModificateurOmbre(niveau: niveau)) }
}

private struct AppliquerTheme: ViewModifier {
    @ObservedObject var theme: Theme

    func body(content: Content) -> some View {
        let j = theme.jetons
        content
            .environment(\.jetons, j)
            .environmentObject(theme)
            .preferredColorScheme(theme.schemaForce)
            .tint(j.accent)
            .symbolVariant(j.varianteSymboles)
            .controlSize(j.esp.controle)
            .font(j.police(.corps))
    }
}

private struct Typo: ViewModifier {
    let role: RoleTexte
    let couleur: Color?
    @Environment(\.jetons) private var j

    func body(content: Content) -> some View {
        content
            .font(j.police(role))
            .tracking(j.approche(role))
            .lineSpacing(j.interligne(role))
            .foregroundStyle(couleur ?? j.couleurParDefaut(role))
    }
}

private struct ModificateurOmbre: ViewModifier {
    let niveau: NiveauOmbre
    @Environment(\.jetons) private var j

    func body(content: Content) -> some View {
        // Structure constante (deux ombres, transparentes au besoin) : changer de niveau au survol
        // ne recrée pas la vue.
        let o = j.ombres(niveau)
        let a = o.first
        let b = o.count > 1 ? o[1] : nil
        content
            .shadow(color: a?.couleur ?? .clear, radius: a?.rayon ?? 0, x: 0, y: a?.y ?? 0)
            .shadow(color: b?.couleur ?? .clear, radius: b?.rayon ?? 0, x: 0, y: b?.y ?? 0)
    }
}

/// Rend un contenu avec une apparence en brouillon et un schéma donné (aperçus de Réglages › Apparence).
struct ApercuTheme<Contenu: View>: View {
    let apparence: Apparence
    let schema: ColorScheme
    let contenu: Contenu
    @Environment(\.jetons) private var courant

    init(apparence: Apparence, schema: ColorScheme, @ViewBuilder contenu: () -> Contenu) {
        self.apparence = apparence
        self.schema = schema
        self.contenu = contenu()
    }

    var body: some View {
        let j = Jetons(apparence: apparence, schema: schema, systeme: courant.systeme)
        contenu
            .environment(\.jetons, j)
            .environment(\.colorScheme, schema)
            .tint(j.accent)
            .symbolVariant(j.varianteSymboles)
            .font(j.police(.corps))
    }
}

/// Liseré haut blanc des surfaces posées sur le dégradé (8 % en sombre, 70 % en clair : bord de verre).
struct LisereHaut: View {
    var rayon: CGFloat
    @Environment(\.jetons) private var j

    var body: some View {
        RoundedRectangle(cornerRadius: rayon, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color.white.opacity(j.schema == .dark ? 0.09 : 0.7), .clear],
                                         startPoint: .top, endPoint: .center), lineWidth: 1)
            .allowsHitTesting(false)
    }
}
