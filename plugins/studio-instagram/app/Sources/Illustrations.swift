import AppKit
import SwiftUI

// Illustrations dessinées en code, façon carnet : traits d'encre à main levée (épaisseur qui vit, petits
// débordements), posés sur des formes arrondies très colorées remplies de motifs (quadrillage, vagues, points,
// gribouillis, boucles, confettis), avec un grain de pulvérisation. Aucune image externe.
//
//   Illustration(.bienvenue)                 // 280 pt
//   Illustration(.publication, taille: 200)  // de 160 à 360 pt
//
// Couleurs : dérivées de l'ambiance courante (`\.jetons` : taches du dégradé et accent), rendues plus vives pour
// le dessin, avec toujours une teinte de contraste ; l'encre est celle du thème (sombre en clair, claire en sombre).
// Mouvement : le tracé se dessine à l'apparition, puis la scène flotte doucement (ballons, étincelles, notes…).
// Rien ne bouge si « Réduire les animations » est actif (`j.deplacements` ou le réglage du système).
// Décoratif : masqué pour VoiceOver (le titre de l'écran porte le sens).

// MARK: - API

enum SujetIllustration: String, CaseIterable, Identifiable {
    case bienvenue, claude, instagram, rythme, pret, idee, photos, legende, musique, apercu, publication, attente, erreur

    var id: String { rawValue }
}

struct Illustration: View {
    let sujet: SujetIllustration
    let taille: CGFloat

    @Environment(\.jetons) private var j
    @Local private var debut: Date? = nil

    init(_ sujet: SujetIllustration, taille: CGFloat = 280) {
        self.sujet = sujet
        self.taille = taille
    }

    private var animee: Bool {
        j.deplacements && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        let palette = PaletteIllustration(j)
        let anime = animee
        return Group {
            if anime {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { contexte in
                    toile(palette, date: contexte.date)
                }
            } else {
                toile(palette, date: nil)
            }
        }
        .frame(width: taille, height: taille)
        .onAppear { if anime { debut = Date() } }
        .onChange(of: sujet) { _, _ in if animee { debut = Date() } }
        .accessibilityHidden(true)
    }

    private func toile(_ pal: PaletteIllustration, date: Date?) -> some View {
        let sujet = self.sujet
        let taille = self.taille
        let debut = self.debut
        return Canvas { ctx, dim in
            let u = min(dim.width, dim.height) / 100
            var c = ctx
            c.translateBy(x: (dim.width - 100 * u) / 2, y: (dim.height - 100 * u) / 2)
            c.scaleBy(x: u, y: u)
            var t = 0.0
            var trace = 1.0
            if let date {
                t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                if let debut { trace = min(1, max(0, date.timeIntervalSince(debut) / 1.7)) }
            }
            let epaisseur = (1.2 + taille * 0.0078) / u
            let p = Pinceau(ctx: c, pal: pal, w: epaisseur, grainR: max(0.28, 0.5 / u), trace: trace, t: t)
            Scenes.dessiner(sujet, p)
        }
    }
}

// MARK: - Couleurs

struct Teinte {
    let base: Color
    let clair: Color
    let fonce: Color
}

/// Couleurs du dessin, tirées de l'ambiance courante (taches du dégradé et accent) et poussées vers des tons vifs.
struct PaletteIllustration {
    let sombre: Bool
    let encre: Color
    let papier: Color
    /// Teinte principale de l'ambiance, vive (1re tache).
    let chaud: Teinte
    /// Teinte de contraste, profonde (la plus éloignée de la principale).
    let braise: Teinte
    /// Teinte principale, pâle.
    let peche: Teinte
    /// 4e tache, adoucie.
    let sauge: Teinte
    /// 3e tache, lumineuse (ou la teinte de contraste si elle se confond).
    let miel: Teinte
    /// 2e tache.
    let ciel: Teinte

    init(_ j: Jetons) {
        let z = j.schema == .dark
        sombre = z
        let rvb = j.couleurs.rvb
        encre = rvb.encre.couleur
        papier = z ? rvb.fond.melange(.blanc, 0.08).couleur : rvb.fond.melange(.blanc, 0.7).couleur

        // Teintes de l'ambiance courante (taches du dégradé, version claire : teintes nettes) et de l'accent.
        let taches = j.ambiance.definition(sombre: false).taches
        func teinte(_ c: RVB?, sinon h0: Double) -> Double {
            guard let c else { return h0 }
            let (h, s, _) = TSL.de(c)
            return s < 0.08 ? h0 : h
        }
        func ecart(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 1)
            return min(d, 1 - d)
        }
        let h0 = teinte(taches.first, sinon: 0.07)
        let h1 = teinte(taches.count > 1 ? taches[1] : nil, sinon: h0 + 0.5)
        let h2 = teinte(taches.count > 2 ? taches[2] : nil, sinon: h0 + 0.1)
        let h3 = teinte(taches.count > 3 ? taches[3] : nil, sinon: h0 + 0.3)
        let hAccent = teinte(rvb.accent, sinon: h0 + 0.5)
        // Teinte de contraste : la plus éloignée de la teinte principale (au moins deux teintes par scène).
        let hContraste = [h1, h2, h3, hAccent].max { ecart($0, h0) < ecart($1, h0) } ?? h0 + 0.5
        // Le miel s'écarte du ciel et du chaud ; sinon il prend la teinte de contraste.
        let hMiel = ecart(h2, h0) < 0.17 && ecart(h2, h1) < 0.17 ? hContraste : h2

        chaud = TSL.teinte(h0, 0.78, 0.58, sombre: z)
        braise = TSL.teinte(hContraste, 0.62, 0.46, sombre: z)
        peche = TSL.teinte(h0, 0.85, 0.77, sombre: z)
        sauge = TSL.teinte(h3, 0.40, 0.52, sombre: z)
        miel = TSL.teinte(hMiel, 0.78, 0.63, sombre: z)
        ciel = TSL.teinte(h1, 0.55, 0.62, sombre: z)
    }
}

private enum TSL {
    static func de(_ c: RVB) -> (Double, Double, Double) {
        let ma = max(c.r, c.v, c.b), mi = min(c.r, c.v, c.b)
        let l = (ma + mi) / 2
        guard ma != mi else { return (0, 0, l) }
        let d = ma - mi
        let s = l > 0.5 ? d / (2 - ma - mi) : d / (ma + mi)
        var h: Double
        if ma == c.r {
            h = (c.v - c.b) / d + (c.v < c.b ? 6 : 0)
        } else if ma == c.v {
            h = (c.b - c.r) / d + 2
        } else {
            h = (c.r - c.v) / d + 4
        }
        return (h / 6, s, l)
    }

    static func vers(_ h0: Double, _ s: Double, _ l: Double) -> Color {
        var h = h0.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        guard s > 0 else { return Color(.sRGB, red: l, green: l, blue: l, opacity: 1) }
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
        return Color(.sRGB, red: f(p, q, h + 1 / 3), green: f(p, q, h), blue: f(p, q, h - 1 / 3), opacity: 1)
    }

    static func teinte(_ h0: Double, _ s0: Double, _ l: Double, sombre: Bool) -> Teinte {
        var h = h0.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        // Les verts et les cyans criardent à saturation égale : on les adoucit.
        let s = h > 0.2 && h < 0.55 ? s0 * 0.62 : s0
        let lb = sombre ? l - 0.06 : l
        let sb = sombre ? s * 0.92 : s
        return Teinte(base: vers(h, sb, lb),
                      clair: vers(h, min(1, sb * 0.95), min(0.93, lb + 0.22)),
                      fonce: vers(h, sb, max(0.14, lb - 0.24)))
    }
}

// MARK: - Hasard et bruit (déterministes : le dessin ne change pas d'une image à l'autre)

private struct Graine {
    var x: UInt64

    init(_ s: Int) { x = UInt64(bitPattern: Int64(s)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }

    mutating func d() -> Double {
        x &+= 0x9E37_79B9_7F4A_7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    mutating func entre(_ a: Double, _ b: Double) -> Double { a + (b - a) * d() }
    mutating func cg(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(d()) }
}

private func hache(_ i: Int, _ g: Int) -> Double {
    var r = Graine(i &* 7919 &+ g &* 104_729)
    return r.d() * 2 - 1
}

/// Bruit doux dans [-1, 1].
private func bruit(_ x: Double, _ g: Int) -> Double {
    let i = floor(x)
    let f = x - i
    let a = hache(Int(i), g), b = hache(Int(i) + 1, g)
    let s = f * f * (3 - 2 * f)
    return a + (b - a) * s
}

// MARK: - Géométrie (unités : la scène fait 100 × 100)

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

private func rad(_ deg: Double) -> Double { deg * .pi / 180 }

private func tourner(_ pts: [CGPoint], _ deg: Double, autour c: CGPoint) -> [CGPoint] {
    guard deg != 0 else { return pts }
    let a = rad(deg)
    let co = CGFloat(cos(a)), si = CGFloat(sin(a))
    return pts.map { p in
        let x = p.x - c.x, y = p.y - c.y
        return CGPoint(x: c.x + x * co - y * si, y: c.y + x * si + y * co)
    }
}

/// Courbe de Catmull-Rom passant par les points de contrôle.
private func lisser(_ pts: [CGPoint], ferme: Bool = false, pas: Int = 8) -> [CGPoint] {
    let n = pts.count
    guard n > 2 else { return pts }
    func at(_ i: Int) -> CGPoint {
        if ferme { return pts[((i % n) + n) % n] }
        return pts[min(max(i, 0), n - 1)]
    }
    var res: [CGPoint] = []
    let segments = ferme ? n : n - 1
    for i in 0..<segments {
        let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
        for k in 0..<pas {
            let t = CGFloat(k) / CGFloat(pas)
            let t2 = t * t, t3 = t2 * t
            let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            res.append(CGPoint(x: x, y: y))
        }
    }
    res.append(ferme ? pts[0] : pts[n - 1])
    return res
}

/// Points régulièrement espacés le long de la ligne brisée.
private func reechantillonner(_ pts: [CGPoint], pas: CGFloat) -> [CGPoint] {
    guard pts.count > 1 else { return pts }
    var res = [pts[0]]
    var reste: CGFloat = 0
    for i in 1..<pts.count {
        let a = pts[i - 1], b = pts[i]
        let l = distance(a, b)
        guard l > 0 else { continue }
        var s = pas - reste
        while s <= l {
            let t = s / l
            res.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            s += pas
        }
        reste = l - (s - pas)
    }
    if let fin = pts.last, let dernier = res.last, distance(fin, dernier) > pas * 0.3 { res.append(fin) }
    return res
}

/// Petit tremblement perpendiculaire, comme une main qui trace.
private func trembler(_ pts: [CGPoint], amp: CGFloat, frequence: Double = 0.12, graine: Int) -> [CGPoint] {
    guard pts.count > 2, amp > 0 else { return pts }
    var res: [CGPoint] = []
    res.reserveCapacity(pts.count)
    var s: Double = 0
    for i in 0..<pts.count {
        if i > 0 { s += Double(distance(pts[i - 1], pts[i])) }
        let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
        let dx = b.x - a.x, dy = b.y - a.y
        let l = max(hypot(dx, dy), 0.0001)
        let o = amp * CGFloat(bruit(s * frequence, graine))
        res.append(CGPoint(x: pts[i].x - dy / l * o, y: pts[i].y + dx / l * o))
    }
    return res
}

private func ovale(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, rot: Double = 0, depart: Double = -100,
                   tours: Double = 1, n: Int = 64) -> [CGPoint] {
    let k = max(8, Int(Double(n) * tours))
    var pts: [CGPoint] = []
    for i in 0...k {
        let a = rad(depart) + 2 * .pi * tours * Double(i) / Double(k)
        pts.append(CGPoint(x: c.x + rx * CGFloat(cos(a)), y: c.y + ry * CGFloat(sin(a))))
    }
    return tourner(pts, rot, autour: c)
}

private func arcDe(_ c: CGPoint, _ r: CGFloat, de a: Double, a b: Double) -> [CGPoint] {
    let n = max(4, Int(abs(b - a) / 6))
    return (0...n).map { i in
        let x = rad(a + (b - a) * Double(i) / Double(n))
        return CGPoint(x: c.x + r * CGFloat(cos(x)), y: c.y + r * CGFloat(sin(x)))
    }
}

private func rectArrondi(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, r r0: CGFloat, rot: Double = 0) -> [CGPoint] {
    let r = min(r0, w / 2, h / 2)
    let x0 = c.x - w / 2 + r, x1 = c.x + w / 2 - r
    let y0 = c.y - h / 2 + r, y1 = c.y + h / 2 - r
    var pts: [CGPoint] = []
    pts += arcDe(pt(x1, y0), r, de: -90, a: 0)
    pts += arcDe(pt(x1, y1), r, de: 0, a: 90)
    pts += arcDe(pt(x0, y1), r, de: 90, a: 180)
    pts += arcDe(pt(x0, y0), r, de: 180, a: 270)
    pts.append(pts[0])
    return tourner(pts, rot, autour: c)
}

/// Bloc arrondi irrégulier (galet) : contour fermé.
private func caillou(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, rot: Double = 0, graine: Int) -> [CGPoint] {
    var g = Graine(graine)
    let n = 8
    var ctrl: [CGPoint] = []
    for i in 0..<n {
        let a = 2 * .pi * Double(i) / Double(n) + g.entre(-0.14, 0.14)
        let co = cos(a), si = sin(a)
        let e = 0.62
        let x = (co < 0 ? -1.0 : 1.0) * pow(abs(co), e)
        let y = (si < 0 ? -1.0 : 1.0) * pow(abs(si), e)
        let k = g.entre(0.86, 1.08)
        ctrl.append(CGPoint(x: c.x + w / 2 * CGFloat(x * k), y: c.y + h / 2 * CGFloat(y * k)))
    }
    return tourner(lisser(ctrl, ferme: true, pas: 8), rot, autour: c)
}

/// Nuage de pensée : bosses régulières.
private func nuage(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, bosses: Int) -> [CGPoint] {
    let n = 160
    return (0...n).map { i in
        let a = 2 * .pi * Double(i) / Double(n)
        let k = 1 + 0.16 * abs(sin(Double(bosses) * a / 2))
        return CGPoint(x: c.x + rx * CGFloat(cos(a) * k), y: c.y + ry * CGFloat(sin(a) * k))
    }
}

/// Étoile à branches incurvées (étincelle).
private func etoile(_ c: CGPoint, _ r: CGFloat, branches: Int = 4, creux: CGFloat = 0.22, rot: Double = 0) -> [CGPoint] {
    var pts: [CGPoint] = []
    for i in 0..<branches {
        let a0 = rad(rot - 90) + 2 * .pi * Double(i) / Double(branches)
        let a1 = a0 + 2 * .pi / Double(branches)
        let am = (a0 + a1) / 2
        let p0 = CGPoint(x: c.x + r * CGFloat(cos(a0)), y: c.y + r * CGFloat(sin(a0)))
        let p1 = CGPoint(x: c.x + r * CGFloat(cos(a1)), y: c.y + r * CGFloat(sin(a1)))
        let q = CGPoint(x: c.x + r * creux * CGFloat(cos(am)), y: c.y + r * creux * CGFloat(sin(am)))
        for k in 0..<12 {
            let t = CGFloat(k) / 12
            let x = (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * q.x + t * t * p1.x
            let y = (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * q.y + t * t * p1.y
            pts.append(CGPoint(x: x, y: y))
        }
    }
    pts.append(pts[0])
    return pts
}

private func coeur(_ c: CGPoint, _ taille: CGFloat, rot: Double = 0) -> [CGPoint] {
    let n = 72
    let k = taille / 17
    let pts: [CGPoint] = (0...n).map { i in
        let a = 2 * .pi * Double(i) / Double(n)
        let x = 16 * pow(sin(a), 3)
        let y = -(13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a))
        return CGPoint(x: c.x + CGFloat(x) * k, y: c.y + CGFloat(y) * k)
    }
    return tourner(pts, rot, autour: c)
}

/// Boucles d'écriture (« ℓℓℓ »).
private func boucles(_ depart: CGPoint, longueur: CGFloat, avance: CGFloat = 3.6, hauteur: CGFloat = 3.6,
                     graine: Int = 0) -> [CGPoint] {
    let tours = Double(longueur / avance)
    let n = max(12, Int(tours * 24))
    let c = Double(avance) * 0.38
    return (0...n).map { i in
        let th = 2 * .pi * tours * Double(i) / Double(n)
        let h = Double(hauteur) * (0.8 + 0.3 * bruit(th * 0.25, graine))
        let x = Double(depart.x) + Double(avance) * th / (2 * .pi) - c * sin(th)
        let y = Double(depart.y) - h * (1 - cos(th)) / 2
        return CGPoint(x: x, y: y)
    }
}

private func bornes(_ pts: [CGPoint]) -> CGRect {
    guard let p0 = pts.first else { return .zero }
    var r = CGRect(origin: p0, size: .zero)
    for p in pts { r = r.union(CGRect(origin: p, size: .zero)) }
    return r
}

private func chemin(_ pts: [CGPoint], ferme: Bool) -> Path {
    var c = Path()
    guard let p0 = pts.first else { return c }
    c.move(to: p0)
    for p in pts.dropFirst() { c.addLine(to: p) }
    if ferme { c.closeSubpath() }
    return c
}

// MARK: - Pinceau

private enum Motif { case quadrillage, vagues, points, gribouillis, boucles, confettis, rayures, uni }

private struct Pinceau {
    var ctx: GraphicsContext
    let pal: PaletteIllustration
    /// Épaisseur de l'encre (unités).
    let w: CGFloat
    let grainR: CGFloat
    /// Avancement du tracé d'apparition (0 → 1).
    let trace: Double
    /// Temps (s) pour le flottement ; 0 sans animation.
    let t: Double

    // Transformations
    func decale(_ dx: CGFloat, _ dy: CGFloat) -> Pinceau {
        var p = self
        p.ctx.translateBy(x: dx, y: dy)
        return p
    }

    func tourne(_ deg: Double, autour c: CGPoint) -> Pinceau {
        var p = self
        p.ctx.translateBy(x: c.x, y: c.y)
        p.ctx.rotate(by: .degrees(deg))
        p.ctx.translateBy(x: -c.x, y: -c.y)
        return p
    }

    func echelle(_ s: CGFloat, autour c: CGPoint) -> Pinceau {
        var p = self
        p.ctx.translateBy(x: c.x, y: c.y)
        p.ctx.scaleBy(x: s, y: s)
        p.ctx.translateBy(x: -c.x, y: -c.y)
        return p
    }

    func clippe(_ contour: [CGPoint]) -> Pinceau {
        var p = self
        p.ctx.clip(to: chemin(contour, ferme: true))
        return p
    }

    func opacite(_ o: Double) -> Pinceau {
        var p = self
        p.ctx.opacity *= o
        return p
    }

    /// Flottement (sinus) ; 0 sans animation.
    func onde(_ vitesse: Double, _ phase: Double = 0) -> CGFloat {
        t == 0 ? 0 : CGFloat(sin(t * vitesse + phase))
    }

    func avancement(_ debut: Double, _ duree: Double) -> Double {
        if trace >= 1 { return 1 }
        return min(1, max(0, (trace - debut) / duree))
    }

    /// Apparition d'une forme : petit rebond d'échelle et fondu.
    private func apparition(_ debut: Double, autour c: CGPoint) -> Pinceau? {
        let a = avancement(debut, 0.28)
        if a <= 0 { return nil }
        if a >= 1 { return self }
        let e = 1 - pow(1 - a, 3)
        return echelle(CGFloat(0.82 + 0.18 * e), autour: c).opacite(a)
    }

    // Encre

    /// Trait d'encre vivant : épaisseur qui varie, bouts un peu plus fins, tracé progressif.
    func trait(_ brut: [CGPoint], largeur: CGFloat = 1, debut: Double = 0.3, duree: Double = 0.3,
               tremble: CGFloat = 0.28, graine: Int = 0, couleur: Color? = nil) {
        let a = avancement(debut, duree)
        guard a > 0, brut.count > 1 else { return }
        var pts = reechantillonner(brut, pas: 0.6)
        pts = trembler(pts, amp: tremble, graine: graine &+ 31)
        let n = a >= 1 ? pts.count : max(2, Int(Double(pts.count) * a))
        let teinte = GraphicsContext.Shading.color(couleur ?? pal.encre)
        let k = 4
        var i = 0
        while i < n - 1 {
            let fin = min(i + k, n - 1)
            var c = Path()
            c.move(to: pts[i])
            for m in (i + 1)...fin { c.addLine(to: pts[m]) }
            var lw = w * largeur * CGFloat(0.9 + 0.3 * bruit(Double(i) * 0.07, graine))
            if i < 3 { lw *= 0.78 }
            if a >= 1 && fin >= pts.count - 3 { lw *= 0.78 }
            ctx.stroke(c, with: teinte, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            i = fin
        }
    }

    /// Contour fermé tracé d'un geste, avec un petit débordement à la fin.
    func contour(_ brut: [CGPoint], largeur: CGFloat = 1, debut: Double = 0.3, duree: Double = 0.35,
                 graine: Int = 0, couleur: Color? = nil) {
        let pts = reechantillonner(brut, pas: 0.6)
        guard pts.count > 4 else { return }
        let deb = max(2, pts.count / 14)
        var tout = pts
        let c = bornes(pts)
        let centre = CGPoint(x: c.midX, y: c.midY)
        for p in pts.prefix(deb).dropFirst() {
            tout.append(CGPoint(x: p.x + (p.x - centre.x) * 0.03, y: p.y + (p.y - centre.y) * 0.03))
        }
        trait(tout, largeur: largeur, debut: debut, duree: duree, graine: graine, couleur: couleur)
    }

    /// Ligne pointillée (traits successifs).
    func pointilles(_ brut: [CGPoint], plein: Int = 5, vide: Int = 4, largeur: CGFloat = 0.8, debut: Double = 0.4,
                    duree: Double = 0.4, graine: Int = 0) {
        let pts = reechantillonner(brut, pas: 0.6)
        let a = avancement(debut, duree)
        guard a > 0 else { return }
        let n = a >= 1 ? pts.count : Int(Double(pts.count) * a)
        var i = 0
        var k = 0
        while i < n - 1 {
            let fin = min(i + plein, n - 1)
            trait(Array(pts[i...fin]), largeur: largeur, debut: 0, duree: 0.01, tremble: 0.1, graine: graine &+ k)
            i = fin + vide
            k += 1
        }
    }

    // Remplissages

    /// Bloc coloré texturé : fond, motif, grain. Apparaît par un petit rebond.
    func forme(_ contour: [CGPoint], _ teinte: Teinte, motif: Motif, trame: Color? = nil, debut: Double = 0,
               graine: Int, contourEncre: Bool = false) {
        let r = bornes(contour)
        guard let p0 = apparition(debut, autour: CGPoint(x: r.midX, y: r.midY)) else { return }
        let fond = chemin(contour, ferme: true)
        p0.ctx.fill(fond, with: .color(teinte.base))
        let p = p0.clippe(contour)
        p.motif(motif, dans: r.insetBy(dx: -3, dy: -3), couleur: trame ?? teinte.clair, graine: graine)
        p.grain(dans: r, densite: 0.22, graine: graine &+ 7)
        if contourEncre { p0.contour(contour, debut: debut + 0.15, graine: graine) }
    }

    /// Aplat simple (sans motif).
    func plein(_ contour: [CGPoint], _ couleur: Color, debut: Double = 0) {
        let r = bornes(contour)
        guard let p = apparition(debut, autour: CGPoint(x: r.midX, y: r.midY)) else { return }
        p.ctx.fill(chemin(contour, ferme: true), with: .color(couleur))
    }

    /// Papier moucheté d'encre, plus dense d'un côté (ombre de pulvérisation).
    func papier(_ contour: [CGPoint], debut: Double = 0.15, graine: Int, cote: CGFloat = 1, densite: Double = 1) {
        let r = bornes(contour)
        guard let p0 = apparition(debut, autour: CGPoint(x: r.midX, y: r.midY)) else { return }
        p0.ctx.fill(chemin(contour, ferme: true), with: .color(pal.papier))
        let p = p0.clippe(contour)
        var g = Graine(graine)
        let nombre = Int(min(900, Double(r.width * r.height) * 0.30 * densite))
        var taches = Path()
        for _ in 0..<nombre {
            let x = g.cg(r.minX, r.maxX), y = g.cg(r.minY, r.maxY)
            let rel = (x - r.minX) / max(r.width, 1)
            let poids = cote > 0 ? rel : 1 - rel
            guard g.d() < Double(pow(poids, 2.2)) * 0.95 + 0.04 else { continue }
            let rr = grainR * g.cg(0.7, 1.5)
            taches.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }
        p.ctx.fill(taches, with: .color(pal.encre.opacity(0.55)))
    }

    /// Grain clair et foncé sur une forme colorée.
    func grain(dans r: CGRect, densite: Double, graine: Int) {
        var g = Graine(graine)
        let nombre = Int(min(1200, Double(r.width * r.height) * densite))
        var clair = Path(), fonce = Path()
        for i in 0..<nombre {
            let x = g.cg(r.minX, r.maxX), y = g.cg(r.minY, r.maxY)
            let rr = grainR * g.cg(0.5, 1.25)
            let e = CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)
            if i % 3 == 0 { fonce.addEllipse(in: e) } else { clair.addEllipse(in: e) }
        }
        ctx.fill(clair, with: .color(.white.opacity(pal.sombre ? 0.16 : 0.26)))
        ctx.fill(fonce, with: .color(.black.opacity(pal.sombre ? 0.22 : 0.14)))
    }

    func motif(_ m: Motif, dans r: CGRect, couleur: Color, graine: Int) {
        let lw = w * 0.5
        let style = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        let teinte = GraphicsContext.Shading.color(couleur)
        var g = Graine(graine)
        let c = CGPoint(x: r.midX, y: r.midY)
        let demi = hypot(r.width, r.height) / 2 + 2
        switch m {
        case .uni:
            return
        case .quadrillage:
            let angle = g.entre(10, 28)
            let ecart: CGFloat = 4.4
            var lignes = Path()
            var x = -demi
            var k = 0
            while x <= demi {
                let v = trembler(reechantillonner([pt(c.x + x, c.y - demi), pt(c.x + x, c.y + demi)], pas: 1.2),
                                 amp: 0.35, graine: graine &+ k)
                let h = trembler(reechantillonner([pt(c.x - demi, c.y + x), pt(c.x + demi, c.y + x)], pas: 1.2),
                                 amp: 0.35, graine: graine &+ 100 &+ k)
                lignes.addPath(chemin(tourner(v, angle, autour: c), ferme: false))
                lignes.addPath(chemin(tourner(h, angle, autour: c), ferme: false))
                x += ecart
                k += 1
            }
            ctx.stroke(lignes, with: teinte, style: style)
        case .vagues, .rayures:
            let angle = g.entre(-12, 6)
            let ecart: CGFloat = m == .vagues ? 4.2 : 5.2
            var lignes = Path()
            var y = -demi
            while y <= demi {
                var pts: [CGPoint] = []
                var x = -demi
                while x <= demi {
                    let dy: CGFloat = m == .vagues ? 1.1 * CGFloat(sin(Double(x) / 1.1)) : 0
                    pts.append(pt(c.x + x, c.y + y + dy))
                    x += 0.5
                }
                lignes.addPath(chemin(tourner(pts, angle + (m == .rayures ? 35 : 0), autour: c), ferme: false))
                y += ecart
            }
            ctx.stroke(lignes, with: teinte, style: StrokeStyle(lineWidth: m == .rayures ? lw * 2.4 : lw * 1.1,
                                                                lineCap: .round))
        case .points:
            let ecart: CGFloat = 4.6
            var taches = Path()
            var y = r.minY
            var rang = 0
            while y <= r.maxY {
                var x = r.minX + (rang % 2 == 0 ? 0 : ecart / 2)
                while x <= r.maxX {
                    let rr = 0.75 * g.cg(0.75, 1.25)
                    let px = x + g.cg(-0.5, 0.5), py = y + g.cg(-0.5, 0.5)
                    taches.addEllipse(in: CGRect(x: px - rr, y: py - rr, width: rr * 2, height: rr * 2))
                    x += ecart
                }
                y += ecart * 0.87
                rang += 1
            }
            ctx.fill(taches, with: teinte)
        case .gribouillis:
            var ctrl: [CGPoint] = []
            for _ in 0..<max(10, Int(r.width * r.height / 45)) {
                ctrl.append(pt(g.cg(r.minX, r.maxX), g.cg(r.minY, r.maxY)))
            }
            let pts = lisser(ctrl, pas: 10)
            ctx.stroke(chemin(pts, ferme: false), with: teinte, style: StrokeStyle(lineWidth: lw * 1.5, lineCap: .round,
                                                                                    lineJoin: .round))
        case .boucles:
            var lignes = Path()
            var y = r.minY + 5
            var k = 0
            while y <= r.maxY + 2 {
                let depart = pt(r.minX - CGFloat(k % 2) * 1.5, y)
                lignes.addPath(chemin(boucles(depart, longueur: r.width + 4, avance: 3.2, hauteur: 3.4, graine: k),
                                      ferme: false))
                y += 6
                k += 1
            }
            ctx.stroke(lignes, with: teinte, style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
        case .confettis:
            var traits = Path()
            let nombre = Int(r.width * r.height / 34)
            for _ in 0..<nombre {
                let x = g.cg(r.minX, r.maxX), y = g.cg(r.minY, r.maxY)
                let a = g.entre(0, 180)
                let l = g.cg(1.4, 2.6)
                let forme: [CGPoint]
                if g.d() < 0.5 {
                    forme = [pt(x - l, y), pt(x - l / 3, y - 0.9), pt(x + l / 3, y + 0.9), pt(x + l, y)]
                } else {
                    forme = [pt(x - l * 0.6, y), pt(x + l * 0.6, y)]
                }
                traits.addPath(chemin(tourner(forme, a, autour: pt(x, y)), ferme: false))
            }
            ctx.stroke(traits, with: teinte, style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    // Petits gribouillis du carnet

    func croix(_ c: CGPoint, _ r: CGFloat = 2.2, debut: Double = 0.8, graine: Int = 0) {
        trait([pt(c.x - r, c.y - r), pt(c.x + r, c.y + r)], largeur: 0.85, debut: debut, duree: 0.08, graine: graine)
        trait([pt(c.x + r, c.y - r * 0.9), pt(c.x - r * 0.9, c.y + r)], largeur: 0.85, debut: debut + 0.06,
              duree: 0.08, graine: graine &+ 1)
    }

    func rond(_ c: CGPoint, _ r: CGFloat = 2, debut: Double = 0.8, graine: Int = 0) {
        trait(ovale(c, r, r * 0.92, depart: -120, tours: 1.12, n: 40), largeur: 0.85, debut: debut, duree: 0.12,
              graine: graine)
    }

    func zigzag(_ a: CGPoint, _ b: CGPoint, dents: Int = 4, amp: CGFloat = 1.6, debut: Double = 0.8, graine: Int = 0) {
        var pts: [CGPoint] = []
        let dx = b.x - a.x, dy = b.y - a.y
        let l = max(hypot(dx, dy), 0.001)
        let nx = -dy / l, ny = dx / l
        for i in 0...(dents * 2) {
            let t = CGFloat(i) / CGFloat(dents * 2)
            let o = (i % 2 == 0 ? -amp : amp) * (i == 0 || i == dents * 2 ? 0.4 : 1)
            pts.append(pt(a.x + dx * t + nx * o, a.y + dy * t + ny * o))
        }
        trait(pts, largeur: 0.85, debut: debut, duree: 0.12, tremble: 0.1, graine: graine)
    }

    /// Vaguelette « ~ ».
    func vaguelette(_ a: CGPoint, longueur: CGFloat = 6, amp: CGFloat = 1, debut: Double = 0.8, graine: Int = 0) {
        let pts = (0...16).map { i -> CGPoint in
            let t = CGFloat(i) / 16
            return pt(a.x + longueur * t, a.y + amp * CGFloat(sin(Double(t) * 2 * .pi * 1.5)))
        }
        trait(pts, largeur: 0.85, debut: debut, duree: 0.12, graine: graine)
    }

    /// Traits de mouvement (petits arcs concentriques).
    func mouvement(_ c: CGPoint, _ r: CGFloat, de a: Double, a b: Double, nombre: Int = 2, debut: Double = 0.7) {
        for i in 0..<nombre {
            let rr = r + CGFloat(i) * 3.2
            trait(arcDe(c, rr, de: a + Double(i) * 4, a: b - Double(i) * 4), largeur: 0.8, debut: debut + Double(i) * 0.05,
                  duree: 0.1, graine: 90 &+ i)
        }
    }

    /// Étincelle d'encre : quatre petits rayons.
    func eclat(_ c: CGPoint, _ r: CGFloat, debut: Double = 0.8, graine: Int = 0) {
        for i in 0..<4 {
            let a = rad(Double(i) * 90 - 90)
            let p0 = pt(c.x + r * 0.35 * CGFloat(cos(a)), c.y + r * 0.35 * CGFloat(sin(a)))
            let p1 = pt(c.x + r * CGFloat(cos(a)), c.y + r * CGFloat(sin(a)))
            trait([p0, p1], largeur: 0.85, debut: debut + Double(i) * 0.02, duree: 0.06, tremble: 0.05,
                  graine: graine &+ i)
        }
    }

    /// Étoile pleine scintillante, contour à l'encre.
    func etincelle(_ c: CGPoint, _ r: CGFloat, _ teinte: Teinte, phase: Double = 0, debut: Double = 0.5, graine: Int = 0) {
        let s = 1 + 0.12 * onde(3.1, phase)
        let p = echelle(s, autour: c).tourne(Double(onde(1.3, phase)) * 8, autour: c)
        p.forme(etoile(c, r), teinte, motif: .uni, debut: debut, graine: graine)
        p.contour(etoile(c, r), largeur: 0.9, debut: debut + 0.08, duree: 0.2, graine: graine)
    }
}

// MARK: - Scènes

private enum Scenes {
    static func dessiner(_ sujet: SujetIllustration, _ p0: Pinceau) {
        let p = p0.decale(0, p0.onde(0.9) * 0.8)
        switch sujet {
        case .bienvenue: bienvenue(p)
        case .claude: claude(p)
        case .instagram: instagram(p)
        case .rythme: rythme(p)
        case .pret: pret(p)
        case .idee: idee(p)
        case .photos: photos(p)
        case .legende: legende(p)
        case .musique: musique(p)
        case .apercu: apercu(p)
        case .publication: publication(p)
        case .attente: attente(p)
        case .erreur: erreur(p)
        }
    }

    // MARK: Éléments partagés

    static func ballon(_ p: Pinceau, centre c: CGPoint, rx: CGFloat, ry: CGFloat, rot: Double, bout: CGPoint,
                       teinte: Teinte?, graine: Int, debut: Double) {
        let corps = ovale(c, rx, ry, rot: rot, n: 72)
        let a = rad(rot + 90)
        let noeud = pt(c.x + ry * CGFloat(cos(a)), c.y + ry * CGFloat(sin(a)))
        // ficelle ondulée
        var fil: [CGPoint] = []
        for i in 0...24 {
            let t = CGFloat(i) / 24
            let x = noeud.x + (bout.x - noeud.x) * t + 1.3 * CGFloat(sin(Double(t) * 3 * .pi))
            fil.append(pt(x, noeud.y + 1.6 + (bout.y - noeud.y - 1.6) * t))
        }
        p.trait(fil, largeur: 0.7, debut: debut + 0.2, duree: 0.25, graine: graine)
        if let teinte {
            p.forme(corps, teinte, motif: .points, debut: debut, graine: graine)
        } else {
            p.papier(corps, debut: debut, graine: graine, cote: rot < 0 ? -1 : 1)
        }
        p.contour(corps, debut: debut + 0.05, graine: graine)
        // noeud
        let nd = [pt(noeud.x - 1.4, noeud.y + 1.8), pt(noeud.x, noeud.y - 0.2), pt(noeud.x + 1.4, noeud.y + 1.8),
                  pt(noeud.x - 1.4, noeud.y + 1.8)]
        p.trait(nd, largeur: 0.8, debut: debut + 0.2, duree: 0.06, tremble: 0.05, graine: graine &+ 3)
        // reflet
        p.trait(tourner(arcDe(c, min(rx, ry) * 0.62, de: 200, a: 245), rot, autour: c), largeur: 0.8,
                debut: debut + 0.3, duree: 0.08, graine: graine &+ 4)
    }

    static func mainQuiSalue(_ p: Pinceau, debut: Double) {
        let ctrl: [CGPoint] = [
            pt(43, 91), pt(43, 80), pt(42.5, 65), pt(41, 57), pt(36, 51), pt(31, 45), pt(29.6, 40.6),
            pt(31.8, 38.8), pt(35.5, 41.5), pt(39.6, 46),
            pt(39.8, 36), pt(40, 26), pt(42.5, 22), pt(45, 25.5), pt(45.4, 33.5),
            pt(46.2, 22), pt(48.6, 17.6), pt(51, 21), pt(51.2, 32.5),
            pt(52.3, 23.5), pt(54.7, 20.6), pt(56.9, 23.6), pt(56.8, 33.5),
            pt(57.9, 29.2), pt(60.1, 27.6), pt(61.7, 30.2), pt(60.6, 44), pt(58.4, 54), pt(57.2, 65), pt(57, 80),
            pt(57, 91),
        ]
        let contour = lisser(ctrl, pas: 8)
        p.papier(contour, debut: debut, graine: 21, cote: 1, densite: 1.2)
        p.trait(contour, largeur: 1, debut: debut + 0.05, duree: 0.45, graine: 21)
        // plis de la paume et du poignet
        p.trait(lisser([pt(44.5, 47.5), pt(46.6, 50.6), pt(49.5, 53)], pas: 6), largeur: 0.6, debut: 0.62, duree: 0.08,
                graine: 22)
        p.trait([pt(45.2, 64), pt(52, 64.6)], largeur: 0.6, debut: 0.66, duree: 0.06, graine: 23)
        p.trait([pt(45.4, 67.2), pt(49.6, 67.5)], largeur: 0.6, debut: 0.68, duree: 0.06, graine: 24)
    }

    // MARK: Sujets

    static func bienvenue(_ p: Pinceau) {
        let pal = p.pal
        let b1 = p.decale(0, p.onde(1.3) * 1.8).tourne(Double(p.onde(1.05, 0.4)) * 3, autour: pt(30, 72))
        ballon(b1, centre: pt(23, 33), rx: 8, ry: 10, rot: -12, bout: pt(33, 74), teinte: nil, graine: 11, debut: 0.25)
        let b2 = p.decale(0, p.onde(1.2, 1.7) * 1.8).tourne(Double(p.onde(1.0, 2.2)) * 3, autour: pt(68, 72))
        ballon(b2, centre: pt(78, 36), rx: 7.5, ry: 9.5, rot: 10, bout: pt(67, 74), teinte: pal.miel, graine: 12,
               debut: 0.32)

        let m = p.tourne(Double(p.onde(2.4)) * 6, autour: pt(50, 76))
        mainQuiSalue(m, debut: 0.12)
        m.mouvement(pt(48, 32), 19, de: 196, a: 226, debut: 0.72)
        m.mouvement(pt(52, 32), 19, de: -46, a: -16, debut: 0.76)

        p.forme(caillou(pt(66, 70), 34, 22, rot: 9, graine: 3), pal.chaud, motif: .quadrillage, debut: 0.0, graine: 3)
        p.forme(caillou(pt(33, 79), 46, 26, rot: -5, graine: 4), pal.braise, motif: .confettis, trame: pal.peche.clair,
                debut: 0.04, graine: 4)
        p.forme(caillou(pt(72, 85), 30, 17, rot: -4, graine: 5), pal.peche, motif: .boucles, trame: pal.braise.base,
                debut: 0.08, graine: 5)

        p.rond(pt(22, 13), 2.2, debut: 0.8, graine: 1)
        p.croix(pt(66, 10), 1.9, debut: 0.84, graine: 2)
        p.croix(pt(89, 20), 1.5, debut: 0.88, graine: 3)
        p.zigzag(pt(10, 58), pt(17, 62), dents: 3, amp: 1.2, debut: 0.86, graine: 4)
        p.vaguelette(pt(84, 56), longueur: 6, debut: 0.9, graine: 5)
        p.rond(pt(10, 44), 1.1, debut: 0.92, graine: 6)
    }

    static func claude(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(32, 78), 46, 26, rot: -6, graine: 31), pal.sauge, motif: .points, debut: 0, graine: 31)
        p.forme(caillou(pt(68, 82), 36, 21, rot: 7, graine: 32), pal.peche, motif: .gribouillis, trame: pal.chaud.base,
                debut: 0.05, graine: 32)
        p.forme(caillou(pt(83, 66), 15, 12, rot: 0, graine: 33), pal.miel, motif: .vagues, trame: pal.miel.fonce,
                debut: 0.1, graine: 33)

        let bulle = p.decale(0, p.onde(1.1) * 1.4)
        let n = nuage(pt(55, 35), 25, 17, bosses: 9)
        bulle.papier(n, debut: 0.12, graine: 34, cote: 1, densite: 0.7)
        bulle.contour(n, debut: 0.16, duree: 0.4, graine: 34)
        for (i, b) in [(pt(31, 59), CGFloat(3.4)), (pt(23, 67), CGFloat(2.1))].enumerated() {
            let o = ovale(b.0, b.1, b.1 * 0.9, n: 36)
            bulle.papier(o, debut: 0.3 + Double(i) * 0.05, graine: 35 &+ i)
            bulle.contour(o, largeur: 0.9, debut: 0.32 + Double(i) * 0.05, duree: 0.08, graine: 35 &+ i)
        }
        bulle.etincelle(pt(54, 35), 11, pal.chaud, phase: 0, debut: 0.42, graine: 36)
        bulle.etincelle(pt(68, 26), 4.6, pal.braise, phase: 1.4, debut: 0.52, graine: 37)
        bulle.etincelle(pt(41, 26), 3.4, pal.miel, phase: 2.6, debut: 0.56, graine: 38)

        let e1 = p.echelle(1 + 0.15 * p.onde(2.6, 0.5), autour: pt(87, 17))
        e1.eclat(pt(87, 17), 4, debut: 0.8, graine: 39)
        let e2 = p.echelle(1 + 0.15 * p.onde(2.2, 2.0), autour: pt(14, 26))
        e2.eclat(pt(14, 26), 3.2, debut: 0.84, graine: 40)
        p.croix(pt(88, 45), 1.6, debut: 0.86, graine: 41)
        p.rond(pt(12, 46), 1.4, debut: 0.9, graine: 42)
        p.zigzag(pt(16, 10), pt(24, 8), dents: 3, amp: 1.1, debut: 0.92, graine: 43)
    }

    static func instagram(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(38, 76), 48, 30, rot: -4, graine: 51), pal.ciel, motif: .quadrillage, debut: 0, graine: 51)
        p.forme(caillou(pt(74, 70), 30, 26, rot: 12, graine: 52), pal.miel, motif: .points, trame: pal.chaud.base,
                debut: 0.05, graine: 52)
        p.forme(caillou(pt(18, 54), 13, 11, rot: 0, graine: 53), pal.braise, motif: .vagues, debut: 0.08, graine: 53)

        let c = pt(48, 48)
        let tel = p.tourne(-8 + Double(p.onde(1.0)) * 1.5, autour: c)
        let coque = rectArrondi(c, 32, 56, r: 6)
        tel.papier(coque, debut: 0.12, graine: 54, cote: -1, densite: 0.6)
        tel.contour(coque, debut: 0.15, duree: 0.4, graine: 54)
        tel.contour(rectArrondi(c, 25.5, 48, r: 3.4), largeur: 0.6, debut: 0.3, duree: 0.3, graine: 55)
        tel.trait([pt(45, 23.3), pt(51, 23.3)], largeur: 0.9, debut: 0.4, duree: 0.05, graine: 56)
        let photo = rectArrondi(pt(48, 40), 21, 18, r: 1.2)
        tel.forme(photo, pal.peche, motif: .uni, debut: 0.35, graine: 57)
        tel.clippe(photo).forme(caillou(pt(44, 51), 30, 14, graine: 58), pal.sauge, motif: .vagues, debut: 0.4,
                               graine: 58)
        tel.trait([pt(39, 46), pt(44, 39), pt(47, 43), pt(51, 36.5), pt(57.5, 46)], largeur: 0.75, debut: 0.48,
                  duree: 0.12, graine: 59)
        tel.forme(ovale(pt(53.5, 35), 2.2, 2.2), pal.chaud, motif: .uni, debut: 0.5, graine: 60)
        tel.contour(coeur(pt(40.5, 55.5), 2.6), largeur: 0.7, debut: 0.6, duree: 0.08, graine: 61)
        tel.trait([pt(45, 55.5), pt(57, 55.5)], largeur: 0.6, debut: 0.62, duree: 0.06, graine: 62)
        tel.trait([pt(38, 60), pt(55, 60)], largeur: 0.6, debut: 0.65, duree: 0.06, graine: 63)
        tel.trait([pt(38, 64), pt(49, 64)], largeur: 0.6, debut: 0.68, duree: 0.06, graine: 64)

        let hc = pt(76, 23)
        let h = p.decale(0, p.onde(1.4, 0.8) * 1.6).echelle(1 + 0.07 * max(0, p.onde(4.2)), autour: hc)
        h.forme(coeur(hc, 10, rot: 12), pal.braise, motif: .points, trame: pal.braise.clair, debut: 0.45, graine: 65)
        h.contour(coeur(hc, 10, rot: 12), debut: 0.5, duree: 0.2, graine: 65)
        h.mouvement(hc, 15, de: -150, a: -115, debut: 0.8)
        let petit = p.decale(0, p.onde(1.7, 2.1) * 1.4)
        petit.contour(coeur(pt(89, 41), 3.6, rot: 18), largeur: 0.8, debut: 0.84, duree: 0.08, graine: 66)
        petit.contour(coeur(pt(22, 22), 3, rot: -14), largeur: 0.8, debut: 0.88, duree: 0.08, graine: 67)
        p.croix(pt(14, 38), 1.6, debut: 0.9, graine: 68)
        p.rond(pt(88, 8), 1.5, debut: 0.92, graine: 69)
    }

    static func rythme(_ p: Pinceau) {
        let pal = p.pal
        let sc = pt(73, 37)
        let soleil = p.decale(0, -p.onde(0.7) * 1.6)
        soleil.forme(ovale(sc, 14, 14), pal.miel, motif: .points, trame: pal.chaud.base, debut: 0, graine: 71)
        for i in 0..<9 {
            let a = -160.0 + Double(i) * 22
            let r0: CGFloat = 17.5, r1: CGFloat = 23 + (i % 2 == 0 ? 2 : 0)
            let ra = rad(a)
            soleil.trait([pt(sc.x + r0 * CGFloat(cos(ra)), sc.y + r0 * CGFloat(sin(ra))),
                          pt(sc.x + r1 * CGFloat(cos(ra)), sc.y + r1 * CGFloat(sin(ra)))],
                         largeur: 0.85, debut: 0.6 + Double(i) * 0.025, duree: 0.06, tremble: 0.1, graine: 72 &+ i)
        }
        p.forme(caillou(pt(52, 82), 76, 22, rot: -2, graine: 73), pal.sauge, motif: .vagues, debut: 0.04, graine: 73)
        p.forme(caillou(pt(16, 72), 16, 13, rot: 0, graine: 74), pal.peche, motif: .points, trame: pal.braise.base,
                debut: 0.08, graine: 74)

        let cc = pt(42, 58)
        let cal = p.tourne(-6, autour: cc)
        let page = rectArrondi(cc, 46, 40, r: 3)
        cal.papier(page, debut: 0.12, graine: 75, cote: -1, densite: 0.5)
        cal.clippe(page).forme(rectArrondi(pt(42, 40), 50, 10, r: 0), pal.braise, motif: .rayures, debut: 0.2,
                              graine: 76)
        cal.contour(page, debut: 0.16, duree: 0.38, graine: 75)
        cal.trait([pt(19.4, 45.6), pt(64.6, 45.6)], largeur: 0.9, debut: 0.4, duree: 0.08, graine: 77)
        for (i, x) in [CGFloat(30), CGFloat(54)].enumerated() {
            cal.contour(ovale(pt(x, 37.6), 1.5, 3.4, n: 30), largeur: 0.9, debut: 0.45 + Double(i) * 0.04, duree: 0.06,
                        graine: 78 &+ i)
        }
        for ligne in 0..<3 {
            for col in 0..<5 {
                let k = ligne * 5 + col
                let x = 24.5 + CGFloat(col) * 8.8, y = 52.5 + CGFloat(ligne) * 7.6
                let d = 0.55 + Double(k) * 0.016
                if k < 5 {
                    cal.croix(pt(x, y), 1.4, debut: d, graine: 80 &+ k)
                } else if k == 7 {
                    let o = ovale(pt(x, y), 3.3, 3)
                    cal.forme(o, pal.chaud, motif: .uni, debut: d, graine: 95)
                    cal.contour(ovale(pt(x, y), 3.6, 3.3, depart: -140), largeur: 0.9, debut: d + 0.05, duree: 0.08,
                                graine: 96)
                } else {
                    cal.forme(ovale(pt(x, y), 0.9, 0.9, n: 16), Teinte(base: pal.encre, clair: pal.encre,
                                                                       fonce: pal.encre), motif: .uni, debut: d,
                              graine: 97 &+ k)
                }
            }
        }
        p.croix(pt(12, 20), 1.8, debut: 0.86, graine: 98)
        p.rond(pt(90, 72), 1.5, debut: 0.9, graine: 99)
        p.vaguelette(pt(8, 36), longueur: 7, debut: 0.92, graine: 100)
    }

    static func pret(_ p: Pinceau) {
        let pal = p.pal
        // fanions
        let gauche = p.tourne(Double(p.onde(1.6)) * 2.2, autour: pt(6, 15))
        fanions(gauche, de: pt(4, 15), a: pt(40, 7), creux: 6, n: 4, debut: 0.3, graine: 110)
        let droite = p.tourne(Double(p.onde(1.5, 1.3)) * 2.2, autour: pt(96, 16))
        fanions(droite, de: pt(60, 7), a: pt(96, 16), creux: 6, n: 4, debut: 0.4, graine: 120)

        let pouce = p.tourne(10 + Double(p.onde(1.8)) * 3, autour: pt(50, 88)).decale(0, -7)
        let ctrl: [CGPoint] = [
            pt(43, 100), pt(43.5, 80), pt(43, 72), pt(38, 70), pt(34.5, 65), pt(34, 58), pt(35, 51.5),
            pt(38.5, 47.5), pt(43, 46.5), pt(43.2, 40), pt(43.8, 34), pt(46, 30.5), pt(49.5, 30),
            pt(52.6, 32.5), pt(53.4, 38), pt(53.2, 45.6), pt(58.5, 46.4), pt(62.6, 49.6), pt(63.8, 55),
            pt(63.2, 62), pt(60.5, 67.5), pt(57, 71), pt(56.5, 80), pt(57, 100),
        ]
        let contour = lisser(ctrl, pas: 8)
        pouce.papier(contour, debut: 0.1, graine: 130, cote: 1, densite: 1.2)
        pouce.trait(contour, debut: 0.14, duree: 0.42, graine: 130)
        for (i, y) in [CGFloat(53), CGFloat(58.5), CGFloat(64)].enumerated() {
            pouce.trait(lisser([pt(34.8, y), pt(40.5, y + 0.9), pt(46.5, y + 0.2)], pas: 6), largeur: 0.75,
                        debut: 0.6 + Double(i) * 0.04, duree: 0.06, graine: 131 &+ i)
        }
        pouce.trait(lisser([pt(46.4, 34), pt(48.6, 32.8), pt(51, 34)], pas: 6), largeur: 0.6, debut: 0.72,
                    duree: 0.05, graine: 135)
        pouce.mouvement(pt(48.5, 31), 10, de: -40, a: -8, debut: 0.8)
        pouce.mouvement(pt(48.5, 31), 10, de: 188, a: 220, debut: 0.82)

        p.forme(caillou(pt(31, 79), 40, 28, rot: -9, graine: 136), pal.braise, motif: .gribouillis,
                trame: pal.chaud.base, debut: 0, graine: 136)
        p.forme(caillou(pt(63, 74), 30, 24, rot: 12, graine: 137), pal.chaud, motif: .quadrillage,
                trame: pal.braise.base, debut: 0.04, graine: 137)
        p.forme(caillou(pt(70, 88), 36, 17, rot: -5, graine: 138), pal.miel, motif: .vagues, trame: pal.braise.base,
                debut: 0.08, graine: 138)

        p.zigzag(pt(74, 40), pt(82, 36), dents: 2, amp: 1.4, debut: 0.86, graine: 139)
        p.rond(pt(84, 54), 1.6, debut: 0.88, graine: 140)
        p.rond(pt(16, 38), 1.2, debut: 0.9, graine: 141)
        p.croix(pt(20, 50), 1.5, debut: 0.92, graine: 142)
    }

    static func fanions(_ p: Pinceau, de a: CGPoint, a b: CGPoint, creux: CGFloat, n: Int, debut: Double, graine: Int) {
        func surCorde(_ t: CGFloat) -> CGPoint {
            pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t + creux * 4 * t * (1 - t))
        }
        let corde = (0...30).map { surCorde(CGFloat($0) / 30) }
        p.trait(corde, largeur: 0.8, debut: debut, duree: 0.2, graine: graine)
        for i in 0..<n {
            let t0 = (CGFloat(i) + 0.15) / CGFloat(n), t1 = (CGFloat(i) + 0.85) / CGFloat(n)
            let g = surCorde(t0), d = surCorde(t1)
            let m = surCorde((t0 + t1) / 2)
            let dx = d.x - g.x, dy = d.y - g.y
            let l = max(hypot(dx, dy), 0.001)
            let pointe = pt(m.x - dy / l * 8.5, m.y + dx / l * 8.5)
            let tri = [g, d, pointe, g]
            let di = debut + 0.12 + Double(i) * 0.05
            if i % 2 == 0 {
                p.plein(tri, p.pal.encre, debut: di + 0.04)
                p.contour(tri, largeur: 0.8, debut: di, duree: 0.08, graine: graine &+ i)
            } else {
                p.contour(tri, largeur: 0.8, debut: di, duree: 0.08, graine: graine &+ i)
                p.zigzag(pt(g.x + dx * 0.25, g.y + dy * 0.25 + 2.6), pt(g.x + dx * 0.75, g.y + dy * 0.75 + 2.6),
                         dents: 2, amp: 0.8, debut: di + 0.05, graine: graine &+ 10 &+ i)
            }
        }
    }

    static func idee(_ p: Pinceau) {
        let pal = p.pal
        let lueur = p.echelle(1 + 0.04 * p.onde(2.0), autour: pt(50, 38)).opacite(0.9 + 0.1 * Double(p.onde(2.0)))
        lueur.forme(caillou(pt(50, 37), 50, 46, rot: 8, graine: 151), pal.miel, motif: .points, trame: pal.peche.clair,
                    debut: 0, graine: 151)
        p.forme(caillou(pt(28, 82), 40, 22, rot: -6, graine: 152), pal.sauge, motif: .vagues, debut: 0.04, graine: 152)
        p.forme(caillou(pt(70, 84), 34, 20, rot: 7, graine: 153), pal.braise, motif: .confettis,
                trame: pal.peche.clair, debut: 0.08, graine: 153)

        let b = p.tourne(Double(p.onde(1.2)) * 3, autour: pt(50, 70))
        let verre = lisser([pt(43.5, 58), pt(42, 51), pt(36, 44), pt(34, 34), pt(38, 24), pt(46, 18.5), pt(54, 18.5),
                            pt(62, 24), pt(66, 34), pt(64, 44), pt(58, 51), pt(56.5, 58)], pas: 8)
        b.papier(verre + [pt(43.5, 58)], debut: 0.12, graine: 154, cote: 1, densite: 0.6)
        b.trait(verre, debut: 0.16, duree: 0.38, graine: 154)
        let culot = rectArrondi(pt(50, 62.5), 14, 9, r: 1.6)
        b.forme(culot, pal.chaud, motif: .rayures, trame: pal.chaud.fonce, debut: 0.3, graine: 155)
        b.contour(culot, largeur: 0.9, debut: 0.34, duree: 0.12, graine: 155)
        b.trait([pt(43.2, 61), pt(56.8, 61)], largeur: 0.7, debut: 0.46, duree: 0.05, graine: 156)
        b.trait([pt(43.2, 64), pt(56.8, 64)], largeur: 0.7, debut: 0.48, duree: 0.05, graine: 157)
        b.trait(lisser([pt(46.5, 67), pt(48, 69.6), pt(52, 69.6), pt(53.5, 67)], pas: 6), largeur: 0.9, debut: 0.5,
                duree: 0.06, graine: 158)
        let filament = lisser([pt(46, 57), pt(46.5, 46), pt(44, 40), pt(48, 37.5), pt(50, 41), pt(52, 37.5),
                               pt(56, 40), pt(53.5, 46), pt(54, 57)], pas: 8)
        b.trait(filament, largeur: 0.75, debut: 0.52, duree: 0.2, graine: 159)
        b.trait(arcDe(pt(50, 35), 11, de: 200, a: 240), largeur: 0.8, debut: 0.7, duree: 0.06, graine: 160)

        for i in 0..<7 {
            let a = -180.0 + Double(i) * 30
            let ra = rad(a)
            let vibre = CGFloat(i % 2 == 0 ? 1 : -1) * p.onde(5, Double(i)) * 0.8
            let r0: CGFloat = 22, r1: CGFloat = 27.5 + vibre
            let c = pt(50, 36)
            p.trait([pt(c.x + r0 * CGFloat(cos(ra)), c.y + r0 * CGFloat(sin(ra))),
                     pt(c.x + r1 * CGFloat(cos(ra)), c.y + r1 * CGFloat(sin(ra)))],
                    largeur: 0.9, debut: 0.7 + Double(i) * 0.025, duree: 0.06, tremble: 0.08, graine: 161 &+ i)
        }
        p.croix(pt(14, 54), 1.6, debut: 0.9, graine: 170)
        p.rond(pt(88, 58), 1.5, debut: 0.92, graine: 171)
    }

    static func polaroid(_ p: Pinceau, centre c: CGPoint, rot: Double, teinte: Teinte, motif: Motif, trame: Color?,
                         debut: Double, graine: Int) -> Pinceau {
        let q = p.tourne(rot, autour: c)
        let cadre = rectArrondi(c, 34, 40, r: 1.4)
        q.papier(cadre, debut: debut, graine: graine, cote: 1, densite: 0.35)
        let image = rectArrondi(pt(c.x, c.y - 4), 28, 26, r: 0.8)
        q.forme(image, teinte, motif: motif, trame: trame, debut: debut + 0.05, graine: graine &+ 1)
        q.contour(cadre, debut: debut + 0.06, duree: 0.25, graine: graine)
        q.contour(image, largeur: 0.6, debut: debut + 0.14, duree: 0.2, graine: graine &+ 2)
        return q
    }

    static func photos(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(30, 74), 46, 32, rot: -5, graine: 181), pal.ciel, motif: .vagues, debut: 0, graine: 181)
        p.forme(caillou(pt(74, 78), 34, 24, rot: 9, graine: 182), pal.chaud, motif: .quadrillage, debut: 0.04,
                graine: 182)
        _ = polaroid(p, centre: pt(38, 50), rot: -14, teinte: pal.peche, motif: .points, trame: pal.braise.base,
                     debut: 0.1, graine: 183)
        _ = polaroid(p, centre: pt(61, 46), rot: 11, teinte: pal.braise, motif: .gribouillis, trame: pal.chaud.base,
                     debut: 0.18, graine: 186)
        let c = pt(50, 54)
        let dessus = p.decale(0, p.onde(1.2) * 1.2).tourne(-2 + Double(p.onde(0.9, 1)) * 1.5, autour: c)
        let q = polaroid(dessus, centre: c, rot: 0, teinte: pal.ciel, motif: .uni, trame: nil, debut: 0.26,
                         graine: 189)
        let image = rectArrondi(pt(50, 50), 28, 26, r: 0.8)
        let dans = q.clippe(image)
        dans.forme(ovale(pt(56, 43), 4, 4), pal.miel, motif: .uni, debut: 0.42, graine: 192)
        dans.forme(lisser([pt(34, 64), pt(34, 56), pt(42, 47), pt(47, 53), pt(53, 46), pt(66, 58), pt(66, 64)],
                          ferme: true, pas: 6), pal.sauge, motif: .vagues, debut: 0.44, graine: 193)
        q.trait([pt(36.5, 57), pt(42, 47.5), pt(46.6, 53), pt(53, 46), pt(63.5, 57.5)], largeur: 0.75, debut: 0.5,
                duree: 0.12, graine: 194)
        q.trait(boucles(pt(40, 70.5), longueur: 14, avance: 2.6, hauteur: 2.2, graine: 3), largeur: 0.6, debut: 0.6,
                duree: 0.15, graine: 195)

        p.etincelle(pt(80, 22), 5, pal.miel, phase: 0.5, debut: 0.8, graine: 196)
        p.eclat(pt(18, 22), 3.4, debut: 0.84, graine: 197)
        p.croix(pt(88, 46), 1.5, debut: 0.88, graine: 198)
        p.rond(pt(12, 40), 1.4, debut: 0.9, graine: 199)
    }

    static func legende(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(24, 76), 36, 28, rot: -8, graine: 201), pal.sauge, motif: .points, debut: 0, graine: 201)
        p.forme(caillou(pt(78, 74), 26, 24, rot: 10, graine: 202), pal.braise, motif: .gribouillis,
                trame: pal.chaud.base, debut: 0.04, graine: 202)
        p.forme(caillou(pt(74, 16), 16, 12, graine: 203), pal.miel, motif: .points, trame: pal.chaud.base,
                debut: 0.08, graine: 203)

        let fc = pt(43, 54)
        let f = p.tourne(-6, autour: fc)
        let feuille = rectArrondi(fc, 46, 56, r: 2)
        f.papier(feuille, debut: 0.1, graine: 204, cote: -1, densite: 0.35)
        f.contour(feuille, debut: 0.14, duree: 0.35, graine: 204)
        let lignes: [(CGFloat, CGFloat)] = [(32, 34), (40, 32), (48, 34), (56, 30), (64, 18)]
        for (i, l) in lignes.enumerated() {
            f.trait(boucles(pt(26, l.0 + 3), longueur: l.1, avance: 3, hauteur: 3.3, graine: i), largeur: 0.7,
                    debut: 0.3 + Double(i) * 0.09, duree: 0.12, tremble: 0.15, graine: 205 &+ i)
        }
        f.forme(rectArrondi(pt(36, 70.5), 22, 3.4, r: 1.6), pal.peche, motif: .uni, debut: 0.75, graine: 211)
        f.trait(boucles(pt(26, 70.6 + 2.2), longueur: 17, avance: 3, hauteur: 3.3, graine: 9), largeur: 0.7,
                debut: 0.76, duree: 0.1, tremble: 0.15, graine: 212)

        // stylo
        let s = p.decale(p.onde(1.8) * 1.4, p.onde(3.6, 0.5) * 0.6)
        let pointe = pt(58, 66), bout = pt(84, 22)
        let dx = bout.x - pointe.x, dy = bout.y - pointe.y
        let l = hypot(dx, dy)
        let ux = dx / l, uy = dy / l
        let nx = -uy, ny = ux
        func le(_ a: CGFloat, _ b: CGFloat) -> CGPoint { pt(pointe.x + ux * a + nx * b, pointe.y + uy * a + ny * b) }
        let corps = [le(8, 3.6), le(l - 2, 3.6), le(l, 2.4), le(l + 0.6, 0), le(l, -2.4), le(l - 2, -3.6),
                     le(8, -3.6), le(8, 3.6)]
        s.forme(corps, pal.chaud, motif: .rayures, trame: pal.chaud.clair, debut: 0.4, graine: 213)
        s.forme([le(l - 11, 3.7), le(l - 2, 3.7), le(l, 2.4), le(l + 0.6, 0), le(l, -2.4), le(l - 2, -3.7),
                 le(l - 11, -3.7)], pal.braise, motif: .uni, debut: 0.44, graine: 214)
        let plume = [le(8, 3.6), le(0, 0), le(8, -3.6), le(8, 3.6)]
        s.papier(plume, debut: 0.44, graine: 215, cote: 1, densite: 0.5)
        s.contour(corps, debut: 0.48, duree: 0.2, graine: 216)
        s.contour(plume, largeur: 0.9, debut: 0.56, duree: 0.08, graine: 217)
        s.trait([le(l - 11, 3.6), le(l - 11, -3.6)], largeur: 0.8, debut: 0.6, duree: 0.04, graine: 218)
        s.trait([le(1.5, 0), le(5.5, 0)], largeur: 0.6, debut: 0.62, duree: 0.04, graine: 219)

        p.croix(pt(12, 16), 1.7, debut: 0.86, graine: 220)
        p.vaguelette(pt(84, 46), longueur: 7, debut: 0.9, graine: 221)
        p.rond(pt(92, 60), 1.3, debut: 0.92, graine: 222)
    }

    static func croche(_ p: Pinceau, tete c: CGPoint, hampe: CGFloat, teinte: Teinte?, debut: Double, graine: Int) {
        let o = ovale(c, 3.8, 2.7, rot: -24, n: 40)
        if let teinte {
            p.forme(o, teinte, motif: .uni, debut: debut, graine: graine)
            p.contour(o, largeur: 0.9, debut: debut + 0.04, duree: 0.08, graine: graine)
        } else {
            p.plein(o, p.pal.encre, debut: debut)
            p.contour(o, largeur: 0.9, debut: debut, duree: 0.08, graine: graine)
        }
        let h0 = pt(c.x + 3.3, c.y - 1.2), h1 = pt(c.x + 3.4, c.y - hampe)
        p.trait([h0, h1], largeur: 0.95, debut: debut + 0.06, duree: 0.08, tremble: 0.1, graine: graine &+ 1)
        p.trait(lisser([h1, pt(h1.x + 3, h1.y + 4), pt(h1.x + 5.5, h1.y + 6.5), pt(h1.x + 4.4, h1.y + 10.5)], pas: 6),
                largeur: 0.9, debut: debut + 0.12, duree: 0.08, graine: graine &+ 2)
    }

    static func musique(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(30, 76), 42, 30, rot: -6, graine: 231), pal.braise, motif: .quadrillage, debut: 0,
                graine: 231)
        p.forme(caillou(pt(68, 80), 40, 23, rot: 6, graine: 232), pal.ciel, motif: .vagues, debut: 0.04, graine: 232)
        p.forme(caillou(pt(80, 58), 17, 14, graine: 233), pal.miel, motif: .points, trame: pal.chaud.base,
                debut: 0.08, graine: 233)

        // portée qui ondule
        let portee = p.decale(0, p.onde(1.0) * 0.8)
        for i in 0..<3 {
            let pts = (0...40).map { k -> CGPoint in
                let x = 8 + CGFloat(k) * 2.1
                let y = 58 + CGFloat(i) * 3.4 - 10 * CGFloat(sin(Double(k) / 40 * .pi)) - CGFloat(k) * 0.4
                return pt(x, y)
            }
            portee.trait(pts, largeur: 0.55, debut: 0.12 + Double(i) * 0.05, duree: 0.3, graine: 234 &+ i)
        }

        let n1 = p.decale(0, p.onde(1.5) * 2.2).tourne(Double(p.onde(1.3)) * 6, autour: pt(30, 42))
        croche(n1, tete: pt(28, 48), hampe: 17, teinte: nil, debut: 0.35, graine: 240)
        let n2 = p.decale(0, p.onde(1.3, 1.6) * 2.4).tourne(Double(p.onde(1.1, 0.8)) * 6, autour: pt(60, 30))
        // double croche liée
        let ta = pt(53, 38), tb = pt(66, 34)
        for (i, c) in [ta, tb].enumerated() {
            let o = ovale(c, 3.8, 2.7, rot: -24, n: 40)
            if i == 0 {
                n2.forme(o, pal.chaud, motif: .uni, debut: 0.45, graine: 241)
                n2.contour(o, largeur: 0.9, debut: 0.48, duree: 0.08, graine: 241)
            } else {
                n2.plein(o, pal.encre, debut: 0.5)
                n2.contour(o, largeur: 0.9, debut: 0.5, duree: 0.08, graine: 242)
            }
        }
        n2.trait([pt(ta.x + 3.3, ta.y - 1.2), pt(ta.x + 3.4, 20)], largeur: 0.95, debut: 0.55, duree: 0.06,
                 tremble: 0.1, graine: 243)
        n2.trait([pt(tb.x + 3.3, tb.y - 1.2), pt(tb.x + 3.4, 16)], largeur: 0.95, debut: 0.57, duree: 0.06,
                 tremble: 0.1, graine: 244)
        n2.plein([pt(ta.x + 2.7, 19), pt(tb.x + 4, 14.4), pt(tb.x + 4, 18), pt(ta.x + 2.7, 22.6)], pal.encre,
                 debut: 0.6)
        n2.trait([pt(ta.x + 3, 20.5), pt(tb.x + 3.8, 16.2)], largeur: 1.1, debut: 0.6, duree: 0.06, graine: 245)

        let n3 = p.decale(p.onde(1.2, 3) * 1.2, p.onde(1.7, 2.5) * 2).tourne(Double(p.onde(1.4, 2)) * 8,
                                                                               autour: pt(84, 22))
        croche(n3, tete: pt(82, 30), hampe: 12, teinte: pal.braise, debut: 0.62, graine: 246)

        p.mouvement(pt(20, 30), 8, de: 160, a: 210, debut: 0.8)
        p.vaguelette(pt(40, 12), longueur: 7, debut: 0.84, graine: 247)
        p.croix(pt(90, 48), 1.5, debut: 0.88, graine: 248)
        p.rond(pt(12, 20), 1.6, debut: 0.9, graine: 249)
    }

    static func apercu(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(28, 74), 44, 32, rot: -7, graine: 261), pal.peche, motif: .points, trame: pal.braise.base,
                debut: 0, graine: 261)
        p.forme(caillou(pt(74, 70), 32, 32, rot: 9, graine: 262), pal.sauge, motif: .vagues, debut: 0.04, graine: 262)

        let ensemble = p.decale(0, p.onde(1.1) * 1.4).tourne(Double(p.onde(0.8, 1)) * 2, autour: pt(52, 80))
        let c = pt(52, 42)
        let tel = ensemble.tourne(6, autour: c)
        let coque = rectArrondi(c, 30, 54, r: 5.5)
        tel.papier(coque, debut: 0.1, graine: 263, cote: -1, densite: 0.5)
        tel.contour(coque, debut: 0.14, duree: 0.35, graine: 263)
        let ecran = rectArrondi(c, 24, 46, r: 3)
        tel.contour(ecran, largeur: 0.6, debut: 0.28, duree: 0.25, graine: 264)
        // mini publication
        tel.trait(ovale(pt(44.5, 24), 1.6, 1.6, n: 20), largeur: 0.6, debut: 0.4, duree: 0.05, graine: 265)
        tel.trait([pt(47.5, 24), pt(55, 24)], largeur: 0.55, debut: 0.42, duree: 0.04, graine: 266)
        let photo = rectArrondi(pt(52, 37), 24, 20, r: 0)
        tel.forme(photo, pal.braise, motif: .gribouillis, trame: pal.chaud.base, debut: 0.4, graine: 267)
        tel.etincelle(pt(52, 37), 5, pal.miel, phase: 0.3, debut: 0.5, graine: 268)
        tel.contour(coeur(pt(43.5, 51), 2.4), largeur: 0.65, debut: 0.55, duree: 0.06, graine: 269)
        tel.trait(ovale(pt(49, 51), 1.5, 1.4, depart: 60, tours: 0.85, n: 20), largeur: 0.65, debut: 0.57, duree: 0.05,
                  graine: 270)
        tel.trait([pt(42, 55.5), pt(60, 55.5)], largeur: 0.55, debut: 0.6, duree: 0.05, graine: 271)
        tel.trait([pt(42, 59), pt(54, 59)], largeur: 0.55, debut: 0.62, duree: 0.05, graine: 272)

        // main qui tient le téléphone (devant)
        let main: [CGPoint] = lisser([
            pt(41, 95), pt(40.5, 86), pt(37, 78), pt(34.5, 70), pt(34, 62), pt(35.4, 57.6), pt(38.2, 57.8),
            pt(40.2, 63), pt(43, 69.5), pt(48, 71.8), pt(56, 71.4), pt(62.4, 69.6),
            pt(66.4, 67.6), pt(69, 64.4), pt(67.6, 61.6), pt(64.6, 62.8),
            pt(67.4, 59.6), pt(68.6, 56.2), pt(66.6, 54.2), pt(63.6, 56.4),
            pt(66, 53), pt(66.4, 49.6), pt(64.2, 48.4), pt(61.8, 51),
            pt(63.6, 72), pt(63, 86), pt(62, 95),
        ], pas: 8)
        ensemble.papier(main, debut: 0.3, graine: 273, cote: 1, densite: 1.1)
        ensemble.trait(main, debut: 0.34, duree: 0.4, graine: 273)
        ensemble.trait(lisser([pt(40.4, 66), pt(39, 61.4), pt(37.2, 60)], pas: 6), largeur: 0.6, debut: 0.7,
                       duree: 0.05, graine: 274)

        p.forme(caillou(pt(52, 91), 46, 15, rot: 3, graine: 278), pal.miel, motif: .vagues, trame: pal.chaud.base,
                debut: 0.45, graine: 278)
        p.eclat(pt(84, 20), 4, debut: 0.82, graine: 275)
        p.mouvement(pt(52, 42), 34, de: -128, a: -100, debut: 0.85)
        p.croix(pt(14, 34), 1.6, debut: 0.88, graine: 276)
        p.rond(pt(88, 44), 1.4, debut: 0.9, graine: 277)
    }

    static func publication(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(36, 78), 56, 28, rot: -3, graine: 281), pal.ciel, motif: .vagues, debut: 0, graine: 281)
        p.forme(caillou(pt(78, 82), 28, 18, rot: 8, graine: 282), pal.peche, motif: .points, trame: pal.braise.base,
                debut: 0.04, graine: 282)
        let s = p.echelle(1 + 0.04 * p.onde(1.4), autour: pt(84, 56))
        s.forme(caillou(pt(84, 56), 15, 15, graine: 283), pal.miel, motif: .points, trame: pal.chaud.base,
                debut: 0.08, graine: 283)

        let sillage = lisser([pt(6, 62), pt(14, 52), pt(25, 51), pt(28, 59), pt(21, 64), pt(15, 57), pt(22, 45),
                              pt(34, 39), pt(47, 37)], pas: 10)
        p.pointilles(sillage, plein: 5, vide: 4, largeur: 0.8, debut: 0.2, duree: 0.45, graine: 284)

        let av = p.decale(p.onde(0.9) * 1.6, p.onde(1.4, 0.5) * 2.2).tourne(Double(p.onde(1.4)) * 4,
                                                                             autour: pt(66, 36))
        let nez = pt(88, 20), queueHaut = pt(46, 30), queueBas = pt(56, 52), pli = pt(61, 37), quille = pt(59, 45)
        av.papier([nez, queueHaut, pli, nez], debut: 0.3, graine: 285, cote: -1, densite: 0.4)
        av.forme([nez, pli, quille, queueBas, nez], pal.peche, motif: .points, trame: pal.chaud.base, debut: 0.32, graine: 286)
        av.forme([pli, queueBas, quille, pli], pal.chaud, motif: .rayures, trame: pal.chaud.fonce, debut: 0.34,
                 graine: 288)
        av.contour([nez, queueHaut, pli, nez], debut: 0.38, duree: 0.2, graine: 289)
        av.trait([nez, queueBas, pli], debut: 0.5, duree: 0.15, graine: 290)
        av.trait([pli, quille, queueBas], largeur: 0.8, debut: 0.6, duree: 0.1, graine: 291)

        p.croix(pt(16, 18), 1.8, debut: 0.84, graine: 292)
        p.trait(nuage(pt(30, 22), 7, 3.6, bosses: 5), largeur: 0.8, debut: 0.86, duree: 0.12, graine: 293)
        p.rond(pt(90, 40), 1.3, debut: 0.9, graine: 294)
        p.vaguelette(pt(66, 64), longueur: 6, debut: 0.92, graine: 295)
    }

    static func attente(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(28, 80), 40, 22, rot: -5, graine: 301), pal.sauge, motif: .quadrillage, debut: 0,
                graine: 301)
        p.forme(caillou(pt(72, 82), 34, 20, rot: 6, graine: 302), pal.braise, motif: .vagues, debut: 0.04, graine: 302)
        p.forme(caillou(pt(78, 36), 20, 16, rot: 0, graine: 303), pal.peche, motif: .points, trame: pal.braise.base,
                debut: 0.08, graine: 303)

        let c = pt(50, 47)
        let s = p.tourne(Double(p.onde(0.9)) * 4, autour: c)
        let gauche = lisser([pt(37.5, 22), pt(38.5, 32), pt(46.5, 45), pt(46.5, 49), pt(38.5, 62), pt(37.5, 72)],
                            pas: 8)
        let droite = lisser([pt(62.5, 22), pt(61.5, 32), pt(53.5, 45), pt(53.5, 49), pt(61.5, 62), pt(62.5, 72)],
                            pas: 8)
        let verre = gauche + droite.reversed()
        s.papier(verre, debut: 0.12, graine: 304, cote: 1, densite: 0.5)
        // sable
        s.forme(lisser([pt(40.6, 32), pt(59.4, 32), pt(55, 39), pt(50, 44), pt(45, 39)], ferme: true, pas: 6),
                pal.miel, motif: .points, trame: pal.chaud.base, debut: 0.3, graine: 305)
        s.forme(lisser([pt(39.2, 71.5), pt(42, 65), pt(50, 60.5), pt(58, 65), pt(60.8, 71.5)], ferme: true, pas: 6),
                pal.miel, motif: .points, trame: pal.chaud.base, debut: 0.34, graine: 306)
        var grains = Path()
        for k in 0..<5 {
            let y = 46 + CGFloat((p.t * 9 + Double(k) * 3.2).truncatingRemainder(dividingBy: 16))
            grains.addEllipse(in: CGRect(x: 49.4, y: y, width: 1.2, height: 1.2))
        }
        if p.avancement(0.5, 0.1) >= 1 { s.ctx.fill(grains, with: .color(pal.chaud.fonce)) }
        s.trait(gauche, debut: 0.16, duree: 0.3, graine: 307)
        s.trait(droite, debut: 0.2, duree: 0.3, graine: 308)
        for (i, y) in [CGFloat(19.5), CGFloat(74.5)].enumerated() {
            let barre = rectArrondi(pt(50, y), 34, 5.2, r: 2.2)
            s.forme(barre, pal.chaud, motif: .rayures, trame: pal.chaud.fonce, debut: 0.24 + Double(i) * 0.04,
                    graine: 309 &+ i)
            s.contour(barre, largeur: 0.9, debut: 0.4 + Double(i) * 0.04, duree: 0.1, graine: 311 &+ i)
        }

        p.etincelle(pt(20, 30), 4.4, pal.miel, phase: 0, debut: 0.75, graine: 313)
        p.etincelle(pt(82, 16), 3.2, pal.braise, phase: 1.7, debut: 0.8, graine: 314)
        p.eclat(pt(16, 54), 3, debut: 0.86, graine: 315)
        p.croix(pt(88, 58), 1.5, debut: 0.9, graine: 316)
    }

    static func erreur(_ p: Pinceau) {
        let pal = p.pal
        p.forme(caillou(pt(46, 84), 66, 18, rot: -2, graine: 321), pal.sauge, motif: .vagues, debut: 0, graine: 321)
        p.forme(caillou(pt(84, 70), 16, 14, graine: 322), pal.miel, motif: .points, trame: pal.chaud.base,
                debut: 0.06, graine: 322)

        let c = pt(42, 56)
        let pelote = p.tourne(Double(p.onde(0.8)) * 5, autour: c)
        let boule = ovale(c, 19, 18, n: 80)
        pelote.forme(boule, pal.peche, motif: .uni, debut: 0.08, graine: 323)
        let dedans = pelote.clippe(boule)
        let fils: [(Double, CGFloat, CGFloat)] = [(-30, 20, 9), (-24, 20, 4), (-36, 20, 14), (40, 20, 7), (48, 20, 12),
                                                  (95, 20, 6)]
        for (i, f) in fils.enumerated() {
            dedans.trait(ovale(pt(c.x, c.y), f.1, f.2, rot: f.0, n: 60), largeur: 0.6, debut: 0.3 + Double(i) * 0.04,
                         duree: 0.12, graine: 324 &+ i, couleur: pal.braise.base)
        }
        pelote.contour(boule, debut: 0.16, duree: 0.3, graine: 330)

        let ondule = p.onde(1.6)
        let fil = lisser([pt(58, 48), pt(66, 40), pt(76, 40), pt(78, 50), pt(70, 52), pt(70, 42),
                          pt(80, 34 + ondule), pt(89, 36 + ondule * 1.5), pt(88, 44 + ondule * 2)], pas: 10)
        p.trait(fil, largeur: 0.95, debut: 0.4, duree: 0.35, graine: 331)

        let h = p.decale(0, p.onde(1.3, 1) * 1.6)
        h.forme(coeur(pt(22, 26), 6, rot: -14), pal.braise, motif: .points, trame: pal.braise.clair, debut: 0.6,
                graine: 332)
        h.contour(coeur(pt(22, 26), 6, rot: -14), largeur: 0.9, debut: 0.64, duree: 0.1, graine: 332)
        p.rond(pt(72, 18), 1.6, debut: 0.85, graine: 333)
        p.croix(pt(12, 48), 1.5, debut: 0.88, graine: 334)
        p.vaguelette(pt(60, 70), longueur: 6, debut: 0.9, graine: 335)
    }
}
