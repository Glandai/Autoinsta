"""Traitement d'image : mesures, planches contact, mise en page 4:5, vignettes.

Aucune retouche créative : on recadre, on pose sur un fond, on redimensionne.
Jamais de génération ni d'extension d'image (la photo reste la photo).
"""
import base64
import io
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps, ImageStat

try:
    from PIL import ImageCms
except ImportError:  # pragma: no cover
    ImageCms = None

LARGEUR, HAUTEUR = 1080, 1350          # format de travail Instagram (4:5)
GRILLE_L, GRILLE_H = 1012, 1350        # ce que montre la grille du profil (3:4)
ANCRAGES = ("centre", "haut", "bas", "gauche", "droite")


# --------------------------------------------------------------------------- ouverture

def ouvrir(chemin) -> Image.Image:
    img = Image.open(chemin)
    img = ImageOps.exif_transpose(img)
    icc = img.info.get("icc_profile")
    if icc and ImageCms is not None:
        try:
            src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            dst = ImageCms.createProfile("sRGB")
            img = ImageCms.profileToProfile(img, src, dst, outputMode="RGB")
        except Exception:
            pass
    if img.mode != "RGB":
        img = img.convert("RGB")
    return img


# --------------------------------------------------------------------------- mesures

def dhash(img: Image.Image) -> str:
    g = img.convert("L").resize((9, 8), Image.LANCZOS)
    px = list(g.getdata())
    bits = 0
    for y in range(8):
        for x in range(8):
            bits = (bits << 1) | (1 if px[y * 9 + x] > px[y * 9 + x + 1] else 0)
    return f"{bits:016x}"


def distance(h1: str, h2: str) -> int:
    if not h1 or not h2:
        return 64
    return bin(int(h1, 16) ^ int(h2, 16)).count("1")


def mesurer(img: Image.Image) -> dict:
    """Tonalité, luminosité, orientation, netteté approximative, empreinte."""
    petit = img.copy()
    petit.thumbnail((256, 256))
    # tonalité : écart moyen entre canaux (un N&B légèrement viré reste N&B)
    r, g, b = petit.split()
    ecarts = [max(a, bb, c) - min(a, bb, c) for a, bb, c in zip(r.getdata(), g.getdata(), b.getdata())]
    chroma = sum(ecarts) / max(1, len(ecarts))
    tonalite = "nb" if chroma < 14 else "couleur"
    # luminosité
    gris = petit.convert("L")
    st = ImageStat.Stat(gris)
    moyenne, ecart = st.mean[0], st.stddev[0]
    if moyenne < 92:
        luminosite = "sombre"
    elif moyenne > 158:
        luminosite = "claire"
    elif ecart >= 64:
        luminosite = "contrastee"
    else:
        luminosite = "sombre" if moyenne < 125 else "claire"
    # netteté : énergie des contours (le flou voulu n'est pas un défaut, c'est un indice)
    contours = gris.filter(ImageFilter.FIND_EDGES)
    nettete = round(ImageStat.Stat(contours).var[0], 1)
    w, h = img.size
    prop = h / w
    orientation = "portrait" if prop > 1.05 else ("paysage" if prop < 0.95 else "carre")
    moy = ImageStat.Stat(petit).mean
    couleur = "#%02x%02x%02x" % tuple(int(c) for c in moy[:3])
    return {
        "largeur": w, "hauteur": h, "proportion": round(prop, 4), "orientation": orientation,
        "tonalite": tonalite, "chroma": round(chroma, 1),
        "luminosite": luminosite, "luminance": round(moyenne, 1), "contraste": round(ecart, 1),
        "nettete": nettete, "empreinte": dhash(img), "couleur_moyenne": couleur,
    }


# --------------------------------------------------------------------------- planches

def _police(taille: int):
    for nom in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Helvetica.ttc",
                "/Library/Fonts/Arial.ttf"):
        try:
            return ImageFont.truetype(nom, taille)
        except Exception:
            continue
    try:
        return ImageFont.load_default(size=taille)
    except TypeError:
        return ImageFont.load_default()


def planche_contact(elements, sortie, colonnes=5, cote=320, titre=None) -> Path:
    """elements : liste de (numero_affiche, chemin_image). Écrit une planche JPEG."""
    elements = list(elements)
    lignes = max(1, (len(elements) + colonnes - 1) // colonnes)
    marge, entete = 10, (56 if titre else 0)
    W = colonnes * (cote + marge) + marge
    H = lignes * (cote + marge) + marge + entete
    planche = Image.new("RGB", (W, H), (24, 24, 22))
    d = ImageDraw.Draw(planche)
    police = _police(26)
    if titre:
        d.text((marge + 4, 14), titre, fill=(235, 228, 216), font=_police(28))
    for i, (num, chemin) in enumerate(elements):
        x = marge + (i % colonnes) * (cote + marge)
        y = entete + marge + (i // colonnes) * (cote + marge)
        try:
            im = ouvrir(chemin)
            im.thumbnail((cote, cote), Image.LANCZOS)
            planche.paste(im, (x + (cote - im.width) // 2, y + (cote - im.height) // 2))
        except Exception:
            d.rectangle([x, y, x + cote, y + cote], outline=(120, 40, 40), width=3)
        etiquette = str(num)
        bx = d.textbbox((0, 0), etiquette, font=police)
        tw, th = bx[2] - bx[0], bx[3] - bx[1]
        d.rectangle([x, y, x + tw + 16, y + th + 14], fill=(0, 0, 0))
        d.text((x + 8, y + 5), etiquette, fill=(255, 255, 255), font=police)
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    planche.save(sortie, "JPEG", quality=86)
    return sortie


# --------------------------------------------------------------------------- mise en page 4:5

def _fenetre(w, h, cible_ratio, ancrage, point=None):
    """Plus grande fenêtre au ratio cible (l/h), placée selon l'ancrage."""
    if w / h > cible_ratio:      # image trop large : on coupe les côtés
        cw, ch = int(round(h * cible_ratio)), h
    else:                         # image trop haute : on coupe haut/bas
        cw, ch = w, int(round(w / cible_ratio))
    if point:
        cx, cy = point[0] * w, point[1] * h
    else:
        cx, cy = w / 2, h / 2
        if ancrage == "haut":
            cy = ch / 2
        elif ancrage == "bas":
            cy = h - ch / 2
        elif ancrage == "gauche":
            cx = cw / 2
        elif ancrage == "droite":
            cx = w - cw / 2
    x0 = int(min(max(0, cx - cw / 2), w - cw))
    y0 = int(min(max(0, cy - ch / 2), h - ch))
    return (x0, y0, x0 + cw, y0 + ch)


def couleur_fond(fond, img=None, defauts=None):
    defauts = defauts or {}
    if not fond:
        fond = "clair"
    if fond in defauts:
        fond = defauts[fond]
    if fond == "auto" and img is not None:
        moy = ImageStat.Stat(img.resize((32, 32))).mean
        lum = sum(moy[:3]) / 3
        return (246, 242, 236) if lum > 110 else (20, 20, 18)
    if isinstance(fond, str) and fond.startswith("#") and len(fond) == 7:
        return tuple(int(fond[i:i + 2], 16) for i in (1, 3, 5))
    return (246, 242, 236)


def tourner(img: Image.Image, rotation) -> Image.Image:
    """Remet droite une photo couchée (appareil sans orientation) : 90, 180 ou 270° dans le sens horaire."""
    rotation = int(rotation or 0) % 360
    return img.rotate(-rotation, expand=True) if rotation else img


def rendre_4x5(source, sortie, presentation="plein_cadre", ancrage="centre", point=None,
               fond=None, marge=None, defauts_fond=None, rotation=0) -> dict:
    """Produit un JPEG 1080x1350 prêt pour l'API. Renvoie un petit rapport."""
    img = tourner(ouvrir(source), rotation)
    w, h = img.size
    rapport = {"source": str(source), "presentation": presentation, "agrandissement": 1.0}
    if presentation == "marges":
        m = int(marge) if marge is not None else 64
        boite_w, boite_h = LARGEUR - 2 * m, HAUTEUR - 2 * m
        echelle = min(boite_w / w, boite_h / h)
        nw, nh = max(1, int(w * echelle)), max(1, int(h * echelle))
        dessin = img.resize((nw, nh), Image.LANCZOS)
        toile = Image.new("RGB", (LARGEUR, HAUTEUR), couleur_fond(fond, img, defauts_fond))
        toile.paste(dessin, ((LARGEUR - nw) // 2, (HAUTEUR - nh) // 2))
        rapport["agrandissement"] = round(echelle, 3)
        resultat = toile
    else:
        boite = _fenetre(w, h, LARGEUR / HAUTEUR, ancrage, point)
        recadree = img.crop(boite)
        echelle = LARGEUR / recadree.width
        rapport["agrandissement"] = round(echelle, 3)
        rapport["fenetre"] = boite
        resultat = recadree.resize((LARGEUR, HAUTEUR), Image.LANCZOS)
    if rapport["agrandissement"] < 0.9:
        resultat = resultat.filter(ImageFilter.UnsharpMask(radius=0.6, percent=35, threshold=2))
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    resultat.save(sortie, "JPEG", quality=92, optimize=True, progressive=True)  # sans EXIF ni GPS
    rapport["sortie"] = str(sortie)
    rapport["octets"] = sortie.stat().st_size
    return rapport


# --------------------------------------------------------------------------- modules (plusieurs photos)

# Un module pose plusieurs photos sur une même diapositive 4:5, sur un fond uni, avec des marges
# et une gouttière blanches, comme une page de magazine ou un tirage. Les photos sont seulement
# recadrées et réduites : jamais modifiées.
MODULES = {
    "diptyque":   {"photos": 2, "nom": "Deux côte à côte", "aide": "deux verticales qui se répondent"},
    "duo_empile": {"photos": 2, "nom": "Deux l'une sur l'autre", "aide": "deux horizontales"},
    "duo_decale": {"photos": 2, "nom": "Deux décalées", "aide": "une grande, une petite qui la chevauche"},
    "trio":       {"photos": 3, "nom": "Une grande et deux petites", "aide": "une scène et deux détails"},
    "grille":     {"photos": 4, "nom": "Grille de quatre", "aide": "quatre détails d'un même moment"},
    "tirage":     {"photos": 1, "nom": "Tirage", "aide": "une photo entière posée comme un tirage papier"},
}


def _cases(module, m, g):
    """Cases (x, y, l, h) du module dans la toile 1080x1350, marge m et gouttière g."""
    W, H = LARGEUR, HAUTEUR
    iw, ih = W - 2 * m, H - 2 * m
    if module == "diptyque":
        cw = (iw - g) // 2
        ch = min(ih, int(cw * 1.5))
        y = (H - ch) // 2
        return [(m, y, cw, ch), (m + cw + g, y, cw, ch)]
    if module == "duo_empile":
        ch = (ih - g) // 2
        return [(m, m, iw, ch), (m, m + ch + g, iw, ch)]
    if module == "duo_decale":
        w1 = int(iw * 0.64)
        h1 = int(w1 * 1.25)
        w2 = int(iw * 0.5)
        h2 = int(w2 * 1.25)
        return [(m, m, w1, h1), (W - m - w2, H - m - h2, w2, h2)]
    if module == "trio":
        h1 = int(ih * 0.46)
        cw = (iw - g) // 2
        h2 = ih - h1 - g
        return [(m, m, iw, h1), (m, m + h1 + g, cw, h2), (m + cw + g, m + h1 + g, cw, h2)]
    if module == "grille":
        cw, ch = (iw - g) // 2, (ih - g) // 2
        return [(m, m, cw, ch), (m + cw + g, m, cw, ch), (m, m + ch + g, cw, ch), (m + cw + g, m + ch + g, cw, ch)]
    if module == "tirage":
        return [(int(m * 1.4), int(m * 1.4), W - int(m * 2.8), H - int(m * 1.4) - int(m * 3))]
    raise ValueError(f"Module inconnu : {module}")


def rendre_module(sources_, sortie, module, ancrages=None, points=None, rotations=None,
                  fond=None, marge=None, gouttiere=None, defauts_fond=None) -> dict:
    """Pose plusieurs photos sur une diapositive 4:5 (JPEG 1080x1350). Renvoie un petit rapport."""
    if module not in MODULES:
        raise ValueError(f"Module inconnu : {module}")
    if len(sources_) != MODULES[module]["photos"]:
        raise ValueError(f"Le module {module} demande {MODULES[module]['photos']} photo(s)")
    m = int(marge) if marge is not None else 64
    g = int(gouttiere) if gouttiere is not None else 20
    imgs = [tourner(ouvrir(s), (rotations or [0] * 9)[i] if i < len(rotations or []) else 0)
            for i, s in enumerate(sources_)]
    toile = Image.new("RGB", (LARGEUR, HAUTEUR), couleur_fond(fond, imgs[0], defauts_fond))
    cadre = couleur_fond(fond, imgs[0], defauts_fond)
    echelle_max = 0.0
    for i, (img, (x, y, cw, ch)) in enumerate(zip(imgs, _cases(module, m, g))):
        w, h = img.size
        if module == "tirage":          # photo entière, sans recadrage
            e = min(cw / w, ch / h)
            nw, nh = max(1, int(w * e)), max(1, int(h * e))
            toile.paste(img.resize((nw, nh), Image.LANCZOS), (x + (cw - nw) // 2, y + (ch - nh) // 2))
            echelle_max = max(echelle_max, e)
            continue
        anc = (ancrages or [])[i] if i < len(ancrages or []) else "centre"
        pt = (points or [])[i] if i < len(points or []) else None
        boite = _fenetre(w, h, cw / ch, anc or "centre", pt)
        morceau = img.crop(boite)
        e = cw / morceau.width
        echelle_max = max(echelle_max, e)
        morceau = morceau.resize((cw, ch), Image.LANCZOS)
        if module == "duo_decale" and i == 1:   # la petite photo chevauche la grande, avec un liseré
            b = max(8, g // 2)
            toile.paste(Image.new("RGB", (cw + 2 * b, ch + 2 * b), cadre), (x - b, y - b))
        toile.paste(morceau, (x, y))
    if echelle_max < 0.9:
        toile = toile.filter(ImageFilter.UnsharpMask(radius=0.6, percent=35, threshold=2))
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    toile.save(sortie, "JPEG", quality=92, optimize=True, progressive=True)
    return {"presentation": "module:" + module, "agrandissement": round(echelle_max, 3),
            "sortie": str(sortie), "octets": sortie.stat().st_size}


def vue_grille(source_4x5, sortie) -> Path:
    """Simule la vignette 3:4 du profil (rognée sur les côtés)."""
    img = ouvrir(source_4x5)
    boite = _fenetre(img.width, img.height, 3 / 4, "centre")
    v = img.crop(boite).resize((450, 600), Image.LANCZOS)
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    v.save(sortie, "JPEG", quality=85)
    return sortie


# --------------------------------------------------------------------------- HTML

def data_uri(chemin, largeur_max=720, qualite=80, ratio=None, rotation=0) -> str:
    """Image en base64 pour des pages HTML autonomes (un seul fichier à partager)."""
    img = tourner(ouvrir(chemin), rotation)
    if ratio:
        boite = _fenetre(img.width, img.height, ratio, "centre")
        img = img.crop(boite)
    img.thumbnail((largeur_max, largeur_max * 2), Image.LANCZOS)
    tampon = io.BytesIO()
    img.save(tampon, "JPEG", quality=qualite, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(tampon.getvalue()).decode("ascii")


def vignette(source, sortie, cote=640) -> Path:
    img = ouvrir(source)
    img.thumbnail((cote, cote), Image.LANCZOS)
    sortie = Path(sortie)
    sortie.parent.mkdir(parents=True, exist_ok=True)
    img.save(sortie, "JPEG", quality=84)
    return sortie
