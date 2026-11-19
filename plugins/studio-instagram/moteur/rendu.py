"""Rendu des images d'un post (4:5) et choix des photos candidates."""
from . import config, images, sources
from .config import ErreurStudio


def rendre(jour: str) -> dict:
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise ErreurStudio("post.json absent.")
    if post.get("format") == "reel":
        return {"info": "Reel : utilise ./studio reel monter " + jour}
    cfg = config.compte()
    fonds = (cfg.get("mise_en_page") or {}).get("fonds") or {}
    marge_defaut = (cfg.get("mise_en_page") or {}).get("marge_px", 64)
    serie = post.get("serie")
    medias = sorted(post.get("medias") or [], key=lambda m: m.get("ordre", 0))
    sortie = d / "rendu"
    if sortie.exists():
        for f in sortie.glob("*.jpg"):
            f.unlink()
    rapports, avert = [], []
    for i, m in enumerate(medias, 1):
        ident = str(m.get("photo_id") or m.get("fichier"))
        src = sources.chemin_photo(serie, ident, hd=True)
        rot = m.get("rotation")
        if rot is None:
            rot = sources.rotation(serie, ident)
        r = images.rendre_4x5(src, sortie / f"{i:02d}.jpg", m.get("presentation", "plein_cadre"),
                              m.get("ancrage", "centre"), m.get("point_focal"), m.get("fond"),
                              m.get("marge", marge_defaut), fonds, rotation=rot)
        if r["agrandissement"] > 1.2:
            avert.append(f"Image {i} agrandie ×{r['agrandissement']} : préférer « marges » ou un export HD "
                         "(exports_hd dans config/galeries.yaml)")
        if r["octets"] > 8_000_000:
            avert.append(f"Image {i} trop lourde pour l'API ({r['octets']} octets)")
        rapports.append({"ordre": i, "photo": ident, **{k: r[k] for k in ("presentation", "agrandissement", "octets")}})
    images.vue_grille(sortie / "01.jpg", sortie / "grille.jpg")
    return {"rendus": len(rapports), "details": rapports, "avertissements": avert,
            "dossier": str(sortie.relative_to(config.RACINE))}


def candidats(serie_id: str = None, note_min: int = 4, n: int = 60) -> list:
    """Meilleures photos encore jamais publiées, une par rafale."""
    from .publication import deja_publiee_ressemblante
    publiees = {m.get("photo_id") for h in config.historique() for m in h.get("medias", [])}
    res = []
    for s in config.series():
        if serie_id and s["id"] != serie_id:
            continue
        if s.get("statut", "active") not in ("active",):
            continue
        cat = sources.lire_catalogue(s["id"])
        meilleur_du_groupe = {}
        for p in cat.get("photos", []):
            a = p.get("analyse") or {}
            if p.get("type") != "photo" or not a or int(a.get("note", 0)) < note_min:
                continue
            if p["id"] in publiees or p.get("publiee"):
                continue
            emp = (p.get("mesures") or {}).get("empreinte")
            if emp and deja_publiee_ressemblante(emp):
                continue
            g = p.get("groupe", p["id"])
            prec = meilleur_du_groupe.get(g)
            if not prec or int(a.get("note", 0)) > int(prec["analyse"].get("note", 0)):
                meilleur_du_groupe[g] = p
        for p in meilleur_du_groupe.values():
            a, m = p["analyse"], p.get("mesures") or {}
            res.append({"serie": s["id"], "id": p["id"], "note": a.get("note"), "pilier": a.get("pilier"),
                        "plan": a.get("plan"), "sujet": a.get("sujet"), "moment": a.get("moment"),
                        "description": a.get("description"), "tonalite": m.get("tonalite"),
                        "luminosite": m.get("luminosite"), "orientation": p.get("orientation"),
                        "mise_en_avant": p.get("mise_en_avant"), "scene": p.get("scene"),
                        "heure": p.get("heure"), "couple": a.get("centree_couple")})
    res.sort(key=lambda x: (-(x["note"] or 0), not x.get("mise_en_avant")))
    return res[:n]
