"""Démonstration hors ligne : fabrique une série fictive et parcourt toute la chaîne
(idées, mise en page, contrôle, aperçu) sans toucher à Instagram ni à l'historique."""
import random

from PIL import Image, ImageDraw, ImageFilter

from . import config, journee, pages, regles, rendu, sources

SPECS = [  # (largeur, hauteur, ciel haut, ciel bas, sol, nb)
    (1600, 2000, (214, 196, 170), (240, 226, 204), (86, 92, 70), False),
    (2400, 1600, (120, 140, 160), (226, 214, 196), (70, 74, 58), False),
    (1600, 2400, (40, 40, 40), (150, 150, 150), (20, 20, 20), True),
    (1600, 2000, (232, 210, 186), (246, 236, 222), (140, 120, 96), False),
    (2400, 1600, (60, 60, 60), (200, 200, 200), (30, 30, 30), True),
    (1600, 2000, (176, 152, 128), (230, 206, 176), (60, 50, 40), False),
    (1600, 2400, (200, 200, 200), (245, 245, 245), (90, 90, 90), True),
    (2000, 2000, (196, 172, 150), (236, 222, 206), (96, 82, 66), False),
]


def _image(i, spec, chemin):
    w, h, haut, bas, sol, nb = spec
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    horizon = int(h * (0.58 + 0.06 * (i % 3)))
    for y in range(horizon):
        t = y / max(1, horizon)
        d.line([(0, y), (w, y)], fill=tuple(int(haut[k] * (1 - t) + bas[k] * t) for k in range(3)))
    d.rectangle([0, horizon, w, h], fill=sol)
    rnd = random.Random(i)
    for _ in range(3):                         # arches et silhouettes simples
        x = rnd.randint(int(w * .1), int(w * .8))
        lw = rnd.randint(int(w * .08), int(w * .2))
        d.rectangle([x, horizon - lw * 2, x + lw, horizon], fill=tuple(max(0, c - 40) for c in sol))
        d.ellipse([x, horizon - lw * 2 - lw // 2, x + lw, horizon - lw * 2 + lw // 2], fill=tuple(max(0, c - 40) for c in sol))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    grain = Image.effect_noise((w // 4, h // 4), 22).resize((w, h)).convert("RGB")
    img = Image.blend(img, grain, 0.06)
    if nb:
        img = img.convert("L").convert("RGB")
    ImageDraw.Draw(img).text((40, h - 80), f"demo {i + 1}", fill=(255, 255, 255))
    chemin.parent.mkdir(parents=True, exist_ok=True)
    img.save(chemin, "JPEG", quality=90)


def lancer() -> dict:
    originaux = config.chemin("catalogue", "demo", "originaux")
    for i, spec in enumerate(SPECS):
        f = originaux / f"demo-{i + 1:02d}.jpg"
        if not f.exists():
            _image(i, spec, f)
    sources.indexer("demo")
    cat = sources.lire_catalogue("demo")
    analyses = ["PLACES", "ATMOSPHERE", "DOCUMENTARY", "DETAILS", "EDITORIAL", "PORTRAITS", "ARTISTIC_VISION", "PLACES"]
    for k, p in enumerate(cat["photos"]):
        p["analyse"] = {"note": 5 - (k % 3), "pilier": analyses[k % len(analyses)], "plan": "large",
                        "sujet": "lieu", "description": f"Image de démonstration n°{k + 1}.", "centree_couple": False}
    sources.ecrire_catalogue("demo", cat)
    ids = [p["id"] for p in cat["photos"]]
    date = config.aujourdhui()
    jour = "demo"
    d = config.dossier_jour(jour)
    for f in list(d.glob("*")):
        if f.is_file():
            f.unlink()
    config.ecrire_json(d / "idees.json", {
        "date": date,
        "lecture_du_feed": "Démonstration : après deux couvertures sombres, le feed appelle de la lumière et un plan large.",
        "idees": [
            {"titre": "Le domaine avant les invités", "pitch": "Huit images du lieu vide, de la lumière du matin aux tables dressées : une visite lente, sans personne.",
             "format": "carrousel", "nb_medias": 6, "pilier": "PLACES", "serie": "demo", "type": "valeur_sure",
             "couverture": ids[0], "photos": ids[1:4], "longueur_legende": "courte",
             "pourquoi": "Tes carrousels de lieux sont les plus enregistrés (démo).", "musique": "Piano lent, beaucoup d'air."},
            {"titre": "Trois noirs et blancs", "pitch": "Une image seule, en noir et blanc, qui laisse tout le silence à la scène.",
             "format": "image", "pilier": "ATMOSPHERE", "serie": "demo", "type": "valeur_sure", "couverture": ids[2],
             "photos": [], "longueur_legende": "silencieuse", "pourquoi": "Respiration après une semaine chargée (démo)."},
            {"titre": "Quinze secondes de vent", "pitch": "Un Reel très lent à partir de quatre images, comme un souvenir qui revient.",
             "format": "reel", "duree_s": 15, "pilier": "ARTISTIC_VISION", "serie": "demo", "type": "exploration",
             "couverture": ids[4], "photos": ids[5:8], "longueur_legende": "courte",
             "pourquoi": "Aucun Reel depuis 6 posts : on teste un format plus contemplatif.", "musique": "Cordes lointaines, tempo très lent."},
        ]})
    journee.enregistrer_idees(jour)
    page_idees = pages.page_idees(jour)
    ordre = ids[:6]
    roles = ["ouverture", "progression", "respiration", "progression", "surprise", "cloture"]
    post = {
        "mode": "publication", "jour": jour, "titre": "Le domaine avant les invités", "date": date,
        "heure": regles.creneau(date) or "18:30", "fuseau": "Europe/Paris", "format": "carrousel", "serie": "demo",
        "pilier": "PLACES", "piliers_secondaires": ["ATMOSPHERE"],
        "intention": "Montrer le lieu tel qu'il était à neuf heures, avant que la journée commence.",
        "medias": [{"ordre": i + 1, "fichier": pid, "photo_id": pid, "role": roles[i],
                    "presentation": "marges" if cat["photos"][i].get("orientation") == "paysage" else "plein_cadre",
                    "ancrage": "centre", "fond": "clair",
                    "texte_alternatif": f"Image de démonstration {i + 1} : un domaine, des arches, une lumière douce.",
                    "identifications": ["domaine.demo"] if i == 0 else []} for i, pid in enumerate(ordre)],
        "reel": None,
        "legende": ("À neuf heures, le domaine appartenait encore aux hirondelles.\n"
                    "Les tables attendaient sous les platanes, les chaises n'avaient pas encore bougé.\n\n"
                    "Lieu @domaine.demo\nFleurs @atelier.demo\n\n#mariagegard #domainedemo #provencewedding"),
        "longueur_legende": "courte", "hashtags": ["#mariagegard", "#domainedemo", "#provencewedding"],
        "collaborateurs": ["domaine.demo"], "localisation": "Domaine de démonstration, Gard, France",
        "musique": {"mode": "a_ajouter_dans_l_app", "titre": "(démo) piano lent", "direction_sonore": "Piano seul, tempo lent, beaucoup de silence"},
        "fiche_feed": {"tonalite": "couleur", "luminosite": "claire", "plan": "large", "sujet": "lieu"},
        "controle": {"conforme": True, "remarques": ""}, "alertes": ["Démonstration : rien ne sera publié."],
    }
    config.ecrire_json(d / "post.json", post)
    r = rendu.rendre(jour)
    verdict = regles.valider_post(post, hist=[], catalogue=sources.lire_catalogue("demo"))
    page_apercu = pages.page_apercu(jour, verdict)
    journee.maj(jour, "brouillon_pret")
    return {"idees": str(page_idees.relative_to(config.RACINE)), "apercu": str(page_apercu.relative_to(config.RACINE)),
            "rendu": r, "verdict": {k: verdict[k] for k in ("conforme", "erreurs", "avertissements")}}
