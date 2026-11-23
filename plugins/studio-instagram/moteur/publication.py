"""Publication sur Instagram et import de l'historique du compte."""
import shutil

import requests

from . import config, images, journee, regles, sources
from .config import ErreurStudio
from .heberger import Hebergeur
from .instagram import ErreurAPI, Instagram


def _tags(media: dict) -> list:
    res = []
    for t in media.get("identifications") or []:
        if isinstance(t, dict):
            res.append({"username": str(t.get("compte", "")).lstrip("@"),
                        "x": float(t.get("x", 0.5)), "y": float(t.get("y", 0.85))})
        else:
            res.append({"username": str(t).lstrip("@"), "x": 0.5, "y": 0.85})
    return res


def publier(jour: str, simulation: bool = False, forcer: bool = False) -> dict:
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise ErreurStudio("post.json absent.")
    e = journee.etat(jour)
    if e.get("statut") == "publie" and not forcer:
        return {"etat": "deja_publie", "permalink": e.get("permalink")}
    if e.get("statut") != "approuve" and not (forcer or simulation):
        raise ErreurStudio("Ce post n'a pas été approuvé : rien n'est publié sans validation.")
    verdict = regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie")))
    if verdict["erreurs"]:
        raise ErreurStudio("Publication bloquée : " + " ; ".join(verdict["erreurs"][:5]))
    ig = Instagram(simulation=simulation)
    if not simulation and not ig.pret():
        raise ErreurStudio("Jeton Instagram absent : voir docs/connexion-instagram.md.")
    rendu = d / "rendu"
    medias = sorted(post.get("medias") or [], key=lambda m: m.get("ordre", 0))
    fmt = post.get("format")
    try:
        serie = config.serie(post.get("serie"))
    except ErreurStudio:
        serie = {}
    location_id = post.get("location_id") or serie.get("location_id")
    collab = [str(c).lstrip("@") for c in (post.get("collaborateurs") or [])]
    legende = post.get("legende") or ""
    avert = []
    with Hebergeur(simulation=simulation) as h:
        if fmt in ("carrousel", "image"):
            fichiers = [rendu / f"{i:02d}.jpg" for i in range(1, len(medias) + 1)]
            manquants = [f.name for f in fichiers if not f.exists()]
            if manquants:
                raise ErreurStudio("Images non rendues : lance ./studio rendre " + jour)
            if fmt == "carrousel":
                enfants = []
                for m, f in zip(medias, fichiers):
                    url = h.url(f)
                    try:
                        cid = ig.conteneur_image(url, alt=m.get("texte_alternatif"), tags=_tags(m), carrousel=True)
                    except ErreurAPI as err:
                        if m.get("identifications"):
                            avert.append(f"Identification refusée sur l'image {m.get('ordre')} ({err}) : publiée sans")
                            try:
                                cid = ig.conteneur_image(url, alt=m.get("texte_alternatif"), carrousel=True)
                            except ErreurAPI:
                                cid = ig.conteneur_image(url, carrousel=True)
                        else:
                            avert.append(f"Texte alternatif refusé sur l'image {m.get('ordre')} ({err}) : publiée sans")
                            cid = ig.conteneur_image(url, carrousel=True)
                    enfants.append(cid)
                for cid in enfants:
                    ig.attendre(cid)
                try:
                    parent = ig.conteneur_carrousel(enfants, legende, collab, location_id)
                except ErreurAPI as err:
                    if not (collab or location_id):
                        raise
                    avert.append(f"Collaborateurs ou lieu refusés ({err}) : publié sans")
                    parent = ig.conteneur_carrousel(enfants, legende)
            else:
                m = medias[0]
                url = h.url(fichiers[0])
                try:
                    parent = ig.conteneur_image(url, alt=m.get("texte_alternatif"), tags=_tags(m), legende=legende,
                                                collaborateurs=collab, location_id=location_id)
                except ErreurAPI as err:
                    avert.append(f"Options refusées ({err}) : publiée sans identifications, collaborateurs ni lieu")
                    try:
                        parent = ig.conteneur_image(url, alt=m.get("texte_alternatif"), legende=legende)
                    except ErreurAPI:
                        parent = ig.conteneur_image(url, legende=legende)
            ig.attendre(parent)
        else:
            raise ErreurStudio(f"Format inconnu : {fmt}")
        media_id = ig.publier(parent)
    info = ig.media(media_id)
    moment = config.maintenant().isoformat(timespec="minutes")
    resultat = {"etat": "simulation" if simulation else "publie", "media_id": media_id,
                "permalink": info.get("permalink"), "publie_le": moment, "avertissements": avert}
    if simulation:
        resultat["requetes"] = ig.journal
        config.ecrire_json(d / "simulation.json", resultat)
        return resultat
    config.ecrire_json(d / "publication.json", resultat)
    couv = rendu / "01.jpg"
    if couv.exists():
        (config.chemin("donnees", "couvertures")).mkdir(parents=True, exist_ok=True)
        shutil.copy2(couv, config.chemin("donnees", "couvertures", f"{jour}.jpg"))
    hist = config.historique()
    hist.append({
        "jour": jour, "date": moment[:10], "heure": moment[11:16], "format": fmt, "titre": post.get("titre"),
        "pilier": post.get("pilier"), "piliers_secondaires": post.get("piliers_secondaires"),
        "serie": post.get("serie"), "longueur_legende": post.get("longueur_legende"),
        "fiche_feed": post.get("fiche_feed"), "centree_couple": regles.centree_couple(post),
        "medias": [{"ordre": m.get("ordre"), "photo_id": config.ids_media(m)[0] if config.ids_media(m) else "",
                    **({"photos": config.ids_media(m), "module": m.get("module")} if m.get("module") else {})}
                   for m in medias],
        "collaborateurs": collab, "hashtags": post.get("hashtags"), "musique": (post.get("musique") or {}).get("titre"),
        "media_id": media_id, "permalink": info.get("permalink"), "publie_le": moment})
    config.enregistrer_historique(hist)
    cat = sources.lire_catalogue(post.get("serie"))
    ids = {x for m in medias for x in config.ids_media(m)}
    for p in cat.get("photos", []):
        if p["id"] in ids:
            p["publiee"] = jour
    if cat.get("photos"):
        sources.ecrire_catalogue(post.get("serie"), cat)
    journee.maj(jour, "publie", permalink=info.get("permalink"), media_id=media_id)
    return resultat


def publier_dus(simulation: bool = False) -> list:
    res = []
    for jour in journee.dus():
        try:
            r = publier(jour, simulation=simulation)
            res.append({"jour": jour, **r})
        except ErreurStudio as e:
            if not simulation:
                journee.maj(jour, "echec", erreur=str(e))
            res.append({"jour": jour, "etat": "echec", "erreur": str(e)})
    return res


# =========================================================================== historique

TYPES = {"CAROUSEL_ALBUM": "carrousel", "IMAGE": "image", "VIDEO": "reel"}


def importer_historique(limite: int = 30) -> dict:
    ig = Instagram()
    if not ig.pret():
        raise ErreurStudio("Jeton Instagram absent : voir docs/connexion-instagram.md.")
    hist = config.historique()
    connus = {str(h.get("media_id")) for h in hist}
    dossier = config.chemin("donnees", "couvertures")
    dossier.mkdir(parents=True, exist_ok=True)
    ajoutes = 0
    for m in ig.lister_medias(limite):
        if str(m["id"]) in connus:
            continue
        ts = m.get("timestamp", "")
        try:
            from .analyse import _date
            local = _date(ts).astimezone(config.fuseau()).isoformat(timespec="minutes")
        except ValueError:
            local = ts
        d = local[:10]
        corps = regles.decouper_legende(m.get("caption") or "")
        jour = f"ig-{m['id']}"
        empreintes = []
        enfants = (m.get("children") or {}).get("data") or [m]
        for k, enfant in enumerate(enfants[:10]):
            url = enfant.get("thumbnail_url") or enfant.get("media_url")
            if not url:
                continue
            try:
                r = requests.get(url, timeout=60)
                f = dossier / (f"{jour}.jpg" if k == 0 else f"{jour}-{k}.jpg")
                f.write_bytes(r.content)
                empreintes.append(images.dhash(images.ouvrir(f)))
                if k:
                    f.unlink()
            except Exception:
                continue
        hist.append({
            "jour": jour, "date": d, "heure": local[11:16], "importe": True,
            "format": "reel" if m.get("media_product_type") == "REELS" else TYPES.get(m.get("media_type"), "image"),
            "pilier": None, "fiche_feed": None, "serie": None, "legende": m.get("caption"),
            "longueur_legende": regles.classer_longueur(corps["corps"]) if m.get("caption") else "silencieuse",
            "hashtags": corps["tous_hashtags"], "media_id": m["id"], "permalink": m.get("permalink"),
            "publie_le": local, "empreintes": empreintes, "medias": []})
        ajoutes += 1
    config.enregistrer_historique(hist)
    a_classer = [h for h in hist if h.get("importe") and not h.get("fiche_feed")]
    return {"importes": ajoutes, "a_classer": len(a_classer)}


def planche_historique() -> dict:
    """Planche des couvertures importées à classer (pilier + fiche feed)."""
    hist = [h for h in config.historique() if h.get("importe") and not h.get("fiche_feed")]
    elements, corr = [], {}
    for i, h in enumerate(hist, 1):
        f = config.chemin("donnees", "couvertures", f"{h['jour']}.jpg")
        if f.exists():
            elements.append((i, f))
            corr[str(i)] = h["jour"]
    if not elements:
        return {"planche": None, "a_classer": 0}
    sortie = images.planche_contact(elements, config.chemin("donnees", "planche-historique.jpg"), colonnes=6, cote=260,
                                    titre="Couvertures à classer")
    config.ecrire_json(config.chemin("donnees", "planche-historique.json"), corr)
    return {"planche": str(sortie), "a_classer": len(elements)}


def noter_historique(fichier: str) -> dict:
    notes = config.lire_json(fichier, {})
    corr = config.lire_json(config.chemin("donnees", "planche-historique.json"), {}) or {}
    hist = config.historique()
    par_jour = {h.get("jour"): h for h in hist}
    faits = 0
    for cle, v in notes.items():
        h = par_jour.get(corr.get(str(cle), str(cle)))
        if not h:
            continue
        for champ in ("pilier", "fiche_feed", "centree_couple", "serie", "titre"):
            if champ in v:
                h[champ] = v[champ]
        faits += 1
    config.enregistrer_historique(hist)
    return {"classees": faits}


def deja_publiee_ressemblante(empreinte: str, seuil: int = 8) -> bool:
    for h in config.historique():
        for e in h.get("empreintes") or []:
            if images.distance(e, empreinte) <= seuil:
                return True
    return False
