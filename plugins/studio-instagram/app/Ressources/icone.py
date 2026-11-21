#!/usr/bin/env python3
"""Icône de l'app Studio Instagram : « Le tirage au soleil » (voir app/DESIGN.md §7).

Deux tirages argentiques posés sur l'olive ; sur celui de devant, un soleil de Provence
se couche derrière deux collines et un cyprès. Dessinée avec Pillow seul, suréchantillonnée ×4.

    python3 icone.py                         → icone.png (1024 px) à côté de ce script
    python3 icone.py --accent "#7a4a2e" --doux "#ecdcc8" --sortie /tmp/icone.png
    python3 icone.py --jeu AppIcon.iconset   → aussi les tailles d'un .iconset (16 à 1024)
"""
import argparse
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ICI = os.path.dirname(os.path.abspath(__file__))
SUR = 4  # suréchantillonnage


# ---------------------------------------------------------------- couleurs

def rvb(hexa):
    h = hexa.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise argparse.ArgumentTypeError("couleur attendue au format #rrggbb : %r" % hexa)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def m(a, b, t):
    """Mélange sRGB, comme dans Theme.swift."""
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


BLANC, NOIR = (255, 255, 255), (0, 0, 0)


# ---------------------------------------------------------------- outils de dessin

def k(v):
    """Coordonnée de la toile de 1024 vers la toile suréchantillonnée."""
    return int(round(v * SUR))


def degrade_vertical(taille, haut, bas):
    l, h = taille
    masque = Image.linear_gradient("L").resize((l, h), Image.BICUBIC)
    return Image.composite(Image.new("RGB", taille, bas), Image.new("RGB", taille, haut), masque)


def degrade_radial(taille, centre, couleur_centre, couleur_bord, rayon):
    """Dégradé radial : couleur_centre au centre, couleur_bord à `rayon` et au-delà."""
    l, h = taille
    cote = int(rayon * 2)
    g = Image.radial_gradient("L").resize((cote, cote), Image.BICUBIC)  # 0 au centre, 255 au bord
    masque = Image.new("L", taille, 255)
    masque.paste(g, (int(centre[0] - rayon), int(centre[1] - rayon)))
    return Image.composite(Image.new("RGB", taille, couleur_bord), Image.new("RGB", taille, couleur_centre), masque)


def squircle(taille, exposant=5.0, points=720):
    """Masque de superellipse |x|^n + |y|^n = 1 inscrit dans `taille`."""
    l, h = taille
    a, b = l / 2.0, h / 2.0
    poly = []
    for i in range(points):
        t = 2 * math.pi * i / points
        c, s = math.cos(t), math.sin(t)
        x = a + a * math.copysign(abs(c) ** (2 / exposant), c)
        y = b + b * math.copysign(abs(s) ** (2 / exposant), s)
        poly.append((x, y))
    masque = Image.new("L", taille, 0)
    ImageDraw.Draw(masque).polygon(poly, fill=255)
    return masque


def rect_arrondi(taille, rayon):
    masque = Image.new("L", taille, 0)
    ImageDraw.Draw(masque).rounded_rectangle([0, 0, taille[0] - 1, taille[1] - 1], radius=rayon, fill=255)
    return masque


def ombre(masque, opacite, flou, decalage=(0, 0)):
    """Calque RGBA noir dont l'alpha est le masque flouté."""
    marge = int(flou * 3)
    l, h = masque.size
    grand = Image.new("L", (l + 2 * marge, h + 2 * marge), 0)
    grand.paste(masque, (marge, marge))
    grand = grand.filter(ImageFilter.GaussianBlur(flou)).point(lambda v: int(v * opacite))
    calque = Image.new("RGBA", grand.size, (0, 0, 0, 0))
    calque.putalpha(grand)
    return calque, (decalage[0] - marge, decalage[1] - marge)


def poser(toile, calque, centre, angle=0.0, ombre_spec=None):
    """Pose un calque RGBA tourné de `angle` degrés (sens trigonométrique) centré sur `centre`."""
    if angle:
        calque = calque.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(round(centre[0] - calque.width / 2))
    y = int(round(centre[1] - calque.height / 2))
    if ombre_spec:
        opacite, flou, (dx, dy) = ombre_spec
        o, (ox, oy) = ombre(calque.getchannel("A"), opacite, flou, (dx, dy))
        toile.alpha_composite(o, (x + ox, y + oy))
    toile.alpha_composite(calque, (x, y))


# ---------------------------------------------------------------- la photo du tirage avant

def photo(taille, c, simple):
    l, h = taille
    ciel = degrade_vertical(taille, m(c["fond"], c["doux"], 0.25), m(c["doux"], c["alerte"], 0.24))
    img = ciel.convert("RGBA")

    # Soleil couchant aux deux tiers de la hauteur : disque plat en terre cuite, halo de lumière
    d_soleil = k(210 if simple else 176)
    r = d_soleil / 2
    cx, cy = l * 0.46, h * 0.62
    halo_r = r * 2.1
    masque_halo = Image.new("L", taille, 0)
    ImageDraw.Draw(masque_halo).ellipse([cx - halo_r, cy - halo_r, cx + halo_r, cy + halo_r], fill=int(255 * 0.55))
    masque_halo = masque_halo.filter(ImageFilter.GaussianBlur(r * 0.55))
    img = Image.composite(Image.new("RGBA", taille, m(c["doux"], BLANC, 0.45) + (255,)), img, masque_halo)

    # le dégradé ne couvre que la hauteur du disque
    disque = degrade_vertical((l, int(d_soleil)), m(c["doux"], c["alerte"], 0.38), m(c["alerte"], c["doux"], 0.12))
    plein = Image.new("RGBA", taille, (0, 0, 0, 0))
    plein.paste(disque.convert("RGBA"), (0, int(cy - r)))
    masque_soleil = Image.new("L", taille, 0)
    ImageDraw.Draw(masque_soleil).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    img = Image.composite(plein, img, masque_soleil)

    def colline(points, couleur):
        masque = Image.new("L", taille, 0)
        ImageDraw.Draw(masque).polygon(points, fill=255)
        nonlocal img
        img = Image.composite(Image.new("RGBA", taille, couleur + (255,)), img, masque)

    def courbe(y_gauche, y_sommet, x_sommet, y_droite, n=80):
        """Profil de colline doux (cosinus) de gauche à droite."""
        pts = []
        for i in range(n + 1):
            x = l * i / n
            if x <= x_sommet:
                t = x / x_sommet if x_sommet else 1
                y = y_gauche + (y_sommet - y_gauche) * (1 - math.cos(math.pi * t)) / 2
            else:
                t = (x - x_sommet) / (l - x_sommet)
                y = y_sommet + (y_droite - y_sommet) * (1 - math.cos(math.pi * t)) / 2
            pts.append((x, y))
        return pts + [(l, h), (0, h)]

    if not simple:
        colline(courbe(h * 0.70, h * 0.63, l * 0.22, h * 0.74), m(c["accent"], c["fond"], 0.45))

    if not simple:
        # Cyprès : flamme sombre, pointue en haut, la plus large aux deux tiers, posée sur la colline proche
        cx2, base = l * 0.73, h * 0.80
        largeur, hauteur = k(36), k(196)

        def demi(t):  # t = 0 à la pointe, 1 au pied (enfoui dans la colline)
            return largeur / 2 * math.sin(math.pi * min(t * 0.64, 0.5)) ** 0.85

        cote_d = [(cx2 + demi(i / 60), base - hauteur + hauteur * i / 60) for i in range(61)]
        cote_g = [(cx2 - demi(i / 60), base - hauteur + hauteur * i / 60) for i in range(60, -1, -1)]
        pts = cote_d + cote_g
        colline(pts, m(c["accent"], NOIR, 0.28))
    # Colline proche en dernier : elle recouvre le pied du cyprès et le bas du soleil
    colline(courbe(h * 0.82, h * 0.70, l * 0.80, h * 0.74), c["accent"])
    return img


# ---------------------------------------------------------------- l'icône

def dessiner(c, simple=False):
    T = k(1024)
    toile = Image.new("RGBA", (T, T), (0, 0, 0, 0))

    # 1. Squircle olive, ombre portée, reflet, liseré
    cote = k(824)
    forme = squircle((cote, cote))
    o, (ox, oy) = ombre(forme, 0.32, k(22), (0, k(12)))
    toile.alpha_composite(o, (k(100) + ox, k(100) + oy))

    fond = degrade_vertical((cote, cote), m(c["accent"], BLANC, 0.14), m(c["accent"], NOIR, 0.22)).convert("RGBA")
    reflet = degrade_radial((cote, cote), (k(230), k(150)), BLANC, NOIR, k(520)).convert("L")
    reflet = ImageChops.invert(reflet).point(lambda v: int(v * 0.09))
    fond = Image.composite(Image.new("RGBA", (cote, cote), BLANC + (255,)), fond, reflet)
    # Liseré intérieur blanc à 7 %
    interieur = squircle((cote - k(4), cote - k(4)))
    bord = Image.new("L", (cote, cote), 0)
    bord.paste(forme, (0, 0))
    trou = Image.new("L", (cote, cote), 0)
    trou.paste(interieur, (k(2), k(2)))
    bord = ImageChops.subtract(bord, trou).point(lambda v: int(v * 0.07))
    fond = Image.composite(Image.new("RGBA", (cote, cote), BLANC + (255,)), fond, bord)
    fond.putalpha(forme)
    toile.alpha_composite(fond, (k(100), k(100)))

    # Les tirages sont dessinés sur un calque découpé par le squircle (rien ne déborde)
    calque = Image.new("RGBA", (T, T), (0, 0, 0, 0))

    # 2. Tirage arrière (pêche)
    if not simple:
        arriere = Image.new("RGBA", (k(400), k(500)), (0, 0, 0, 0))
        arriere.paste(Image.new("RGBA", arriere.size, c["doux"] + (255,)), (0, 0), rect_arrondi(arriere.size, k(10)))
        poser(calque, arriere, (k(548), k(500)), angle=-8, ombre_spec=(0.25, k(18), (0, k(6))))

    # 3. Tirage avant (papier) et sa photo
    l_t, h_t = k(440), k(550)
    avant = Image.new("RGBA", (l_t, h_t), (0, 0, 0, 0))
    avant.paste(Image.new("RGBA", (l_t, h_t), m(c["fond"], BLANC, 0.35) + (255,)), (0, 0), rect_arrondi((l_t, h_t), k(12)))
    b = k(36 if simple else 30)
    b_bas = k(36 if simple else 32)
    fen = (l_t - 2 * b, h_t - b - b_bas)
    img = photo(fen, c, simple)
    avant.paste(img, (b, b), rect_arrondi(fen, k(4)))
    centre_avant = (k(486), k(534)) if not simple else (k(512), k(520))
    poser(calque, avant, centre_avant, angle=5 if not simple else 3, ombre_spec=(0.35, k(26), (0, k(14))))

    masque_squircle = Image.new("L", (T, T), 0)
    masque_squircle.paste(forme, (k(100), k(100)))
    calque.putalpha(ImageChops.multiply(calque.getchannel("A"), masque_squircle))
    toile.alpha_composite(calque)
    return toile


def rendre(c, taille, simple=None):
    if simple is None:
        simple = taille <= 64
    grand = dessiner(c, simple)
    return grand.resize((taille, taille), Image.LANCZOS)


def main(argv=None):
    p = argparse.ArgumentParser(description="Dessine l'icône de l'app Studio Instagram.")
    p.add_argument("--accent", type=rvb, default=rvb("#3d4130"), help="couleur principale (olive)")
    p.add_argument("--doux", type=rvb, default=rvb("#efdccd"), help="couleur douce (pêche)")
    p.add_argument("--fond", type=rvb, default=rvb("#f7f3ed"), help="papier")
    p.add_argument("--alerte", type=rvb, default=rvb("#a8551c"), help="terre cuite (bord du soleil)")
    p.add_argument("--sortie", default=os.path.join(ICI, "icone.png"), help="fichier PNG produit")
    p.add_argument("--taille", type=int, default=1024, help="côté du PNG produit (1024 par défaut)")
    p.add_argument("--simple", action="store_true", help="version des petites tailles")
    p.add_argument("--jeu", help="dossier .iconset à remplir (16 à 512, @1x et @2x)")
    a = p.parse_args(argv)
    c = {"accent": a.accent, "doux": a.doux, "fond": a.fond, "alerte": a.alerte}

    rendre(c, a.taille, True if a.simple else None).save(a.sortie)
    print(a.sortie)
    if a.jeu:
        os.makedirs(a.jeu, exist_ok=True)
        cache = {}
        for t in (16, 32, 128, 256, 512):
            for f, suffixe in ((1, ""), (2, "@2x")):
                px = t * f
                if px not in cache:
                    cache[px] = rendre(c, px)
                cache[px].save(os.path.join(a.jeu, "icon_%dx%d%s.png" % (t, t, suffixe)))
        print(a.jeu)
    return 0


if __name__ == "__main__":
    sys.exit(main())
