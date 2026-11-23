"""Sources de photos : galeries Pic-Time (lien de partage) ou dossier local.

Pic-Time n'a pas d'API publique. Une galerie s'ouvre comme dans un navigateur :
1. la page de la galerie (lien de partage contenant « sectoken2 ») donne
   projectId, projectPathToken, projectStorageId et la table des CDN ;
2. le manifeste  {cdn}/pictures/{a}/{b}/{projectId}/{token}/gallery.json.txt
   liste les scènes et les photos (identifiants compressés) ;
3. gallery_meta.json.txt donne l'heure de prise de vue, la palette et le nom
   de fichier d'origine ;
4. chaque photo se lit à  .../{token}/{thumbres|smallres|lowres}/{id}.jpg
   (lowres = 1600 px sur le grand côté).
Ce format est interne à Pic-Time : s'il change, la commande échoue proprement
et le studio bascule sur un dossier local (voir docs/pic-time.md).
"""
import datetime as dt
import json
import re
import shutil
from pathlib import Path

import requests

from . import config, images
from .config import ErreurStudio

UA = {"User-Agent": ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                     "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")}
RESOLUTIONS = ("thumbres", "smallres", "lowres")
ROTATION_CLIP, ROTATION_GIF = 200, 50
EXTENSIONS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}


# =========================================================================== Pic-Time

def id_vers_chemin(pid: int) -> str:
    a = pid // 1_000_000
    b = pid // 1000 - a * 1000
    return f"{a}/{b}/{pid}"


def _json_apres(html: str, marqueur: str):
    i = html.find(marqueur)
    if i < 0:
        return None
    j = html.find("[", i)
    try:
        valeur, _ = json.JSONDecoder().raw_decode(html, j)
        return valeur
    except ValueError:
        return None


def analyser_page(url: str) -> dict:
    r = requests.get(url, headers=UA, timeout=40)
    if r.status_code >= 400:
        raise ErreurStudio(f"Pic-Time répond {r.status_code} pour ce lien.")
    html = r.text

    def cherche(motif, conv=str):
        m = re.search(motif, html)
        return conv(m.group(1)) if m else None

    pid = cherche(r'"projectId"\s*:\s*(\d+)', int)
    token = cherche(r'"projectPathToken"\s*:\s*"([A-Za-z0-9]+)"')
    stockage = cherche(r'"projectStorageId"\s*:\s*(\d+)', int)
    horodatage = cherche(r'"galleryTimeStamp"\s*:\s*"?(\d+)"?') or "0"
    table = _json_apres(html, "_pictimeStorageMapping") or []
    cdn = secours = None
    for entree in table:
        if entree.get("storageId") == stockage:
            cdn, secours = entree.get("cdnDomain"), entree.get("cdnBackupDomain")
    if not (pid and token and cdn):
        raise ErreurStudio(
            "Pic-Time ne donne pas accès à cette galerie avec ce lien (code d'accès ou "
            "inscription demandés). Dans Pic-Time, ouvre la galerie, Partager, et copie le "
            "lien d'accès direct (il contient « sectoken2 »), puis colle-le dans "
            "config/galeries.yaml. À défaut, utilise une source « dossier » (docs/pic-time.md).")
    titre = cherche(r'<meta property="og:title" content="([^"]*)"') or ""
    return {"url": url, "projet": pid, "token": token, "cdn": cdn, "cdn_secours": secours,
            "horodatage": horodatage, "titre": titre}


def _get(url: str, secours_url: str = None, flux=False):
    for u in [url] + ([secours_url] if secours_url else []):
        try:
            r = requests.get(u, headers=UA, timeout=60, stream=flux)
            if r.status_code == 200:
                return r
        except requests.RequestException:
            continue
    raise ErreurStudio(f"Téléchargement impossible : {url.split('?')[0]}")


def _base(info: dict, cdn_cle="cdn") -> str:
    return f"{info[cdn_cle]}/pictures/{id_vers_chemin(info['projet'])}/{info['token']}"


def _ids(deltas, min_id, version):
    if version == 5:
        res, base = [], min_id
        for d in deltas:
            v = base + d
            res.append(v)
            base = v + 1
        return res
    return [min_id + d for d in deltas]


def lire_manifeste(info: dict) -> list:
    base, base2 = _base(info), (_base(info, "cdn_secours") if info.get("cdn_secours") else None)
    q = f"?ts={info['horodatage']}"
    g = _get(base + "/gallery.json.txt" + q, base2 and base2 + "/gallery.json.txt" + q).json()
    try:
        meta = _get(base + "/gallery_meta.json.txt" + q,
                    base2 and base2 + "/gallery_meta.json.txt" + q).json()
    except Exception:
        meta = {}
    # métadonnées par photo : [delta_id, delta_temps, palette, nom_origine]
    infos_meta = {}
    if meta.get("photos"):
        pas = 3 if meta.get("version") == 1 else 4
        p = meta["photos"]
        for i in range(0, len(p), pas):
            pid = meta["minId"] + p[i]
            instant = None
            try:   # selon les galeries : secondes depuis minDateTaken, ou date absolue
                brut = p[i + 1]
                for t in (brut, meta.get("minDateTaken", 0) + brut):
                    if 946684800 < t < 2524608000:          # entre 2000 et 2050
                        instant = dt.datetime.utcfromtimestamp(t).isoformat()
                        break
            except Exception:
                pass
            palette = p[i + 2] or []
            couleurs = [palette[k:k + 3] for k in range(0, len(palette), 4)]
            nb = bool(couleurs) and all(max(c) - min(c) < 16 for c in couleurs)
            infos_meta[pid] = {"heure": instant, "nb_palette": nb,
                               "fichier_origine": p[i + 3] if pas > 3 else ""}
    proportions = g.get("proportions") or []
    mises_en_avant = set(g.get("enlargedPhotoIds") or [])      # comparées à l'incrément d'id
    selection = set()                                            # scène « Highlights » de la photographe
    for scene in g.get("scenes", []):
        if scene.get("sharedPhotoIds"):
            selection.update(_ids(scene["sharedPhotoIds"], g["minId"], g.get("version", 4)))
    pas = 5 if g.get("version", 4) >= 3 else 4
    photos, ordre = [], 0
    for scene in g.get("scenes", []):
        brut = scene.get("photos") or []
        tuples = [brut[i:i + pas] for i in range(0, len(brut), pas)]
        ids = _ids([t[0] for t in tuples], g["minId"], g.get("version", 4))
        for rang, (pid, t) in enumerate(zip(ids, tuples)):
            rotation, revision = t[1], t[2]
            prop = proportions[t[3]] if len(t) > 3 and t[3] < len(proportions) else None
            fichier = f"{pid}_v{revision}.jpg" if revision else f"{pid}.jpg"
            if rotation == ROTATION_CLIP:
                genre = "clip"
            elif rotation == ROTATION_GIF:
                genre = "gif"
            else:
                genre = "photo"
            m = infos_meta.get(pid, {})
            photos.append({
                "id": str(pid), "scene": scene.get("nm") or "", "ordre": ordre, "rang_scene": rang,
                "type": genre, "proportion": round(prop, 4) if prop else None,
                "orientation": (None if not prop else
                                "portrait" if prop > 1.05 else "paysage" if prop < 0.95 else "carre"),
                "mise_en_avant": t[0] in mises_en_avant or pid in selection,
                "heure": m.get("heure"), "nb_palette": m.get("nb_palette"),
                "fichier_origine": m.get("fichier_origine", ""),
                "url": ({r: f"{base}/{r}/{fichier}" for r in RESOLUTIONS} if genre != "clip" else
                        {"video": f"{base}/video/low/{pid}/vid.m3u8"}),
            })
            ordre += 1
    return photos


# =========================================================================== dossier local

def _lire_heure_exif(chemin: Path):
    try:
        from PIL import Image
        exif = Image.open(chemin).getexif()
        brut = exif.get(36867) or exif.get(306)  # DateTimeOriginal ou DateTime
        if brut:
            return dt.datetime.strptime(str(brut), "%Y:%m:%d %H:%M:%S").isoformat()
    except Exception:
        pass
    return None


def lire_dossier(dossier: str) -> list:
    d = config.chemin_utilisateur(dossier)
    if not d.is_dir():
        raise ErreurStudio(f"Dossier introuvable : {d}")
    fichiers = sorted(f for f in d.rglob("*") if f.suffix.lower() in EXTENSIONS and not f.name.startswith("."))
    photos = []
    for ordre, f in enumerate(fichiers):
        ident = re.sub(r"[^A-Za-z0-9_-]+", "-", str(f.relative_to(d).with_suffix("")))[:80]
        photos.append({"id": ident, "scene": f.parent.name if f.parent != d else "", "ordre": ordre,
                       "type": "photo", "fichier_origine": f.stem, "heure": _lire_heure_exif(f),
                       "chemin_local": str(f), "mise_en_avant": False})
    return photos


# =========================================================================== catalogue

def fichier_catalogue(serie_id: str) -> Path:
    return config.dossier_serie(serie_id) / "photos.json"


def lire_catalogue(serie_id: str) -> dict:
    return config.lire_json(fichier_catalogue(serie_id), None) or {"serie": serie_id, "photos": []}


def ecrire_catalogue(serie_id: str, cat: dict) -> None:
    config.ecrire_json(fichier_catalogue(serie_id), cat)


def indexer(serie_id: str, limite: int = None, forcer: bool = False) -> dict:
    s = config.serie(serie_id)
    src = s.get("source") or {}
    ancien = lire_catalogue(serie_id)
    deja = {p["id"]: p for p in ancien.get("photos", [])}
    if src.get("type", "pictime") == "dossier":
        photos = lire_dossier(src.get("chemin", ""))
        info = {"type": "dossier", "chemin": src.get("chemin")}
    else:
        if not src.get("url"):
            raise ErreurStudio(f"Série {serie_id} : ajoute source.url (lien Pic-Time) dans config/galeries.yaml.")
        page = analyser_page(src["url"])
        photos = lire_manifeste(page)
        info = {"type": "pictime", "titre": page["titre"], "projet": page["projet"]}
    if limite:
        photos = photos[:limite]
    dossier = config.dossier_serie(serie_id)
    nouvelles = 0
    for p in photos:
        avant = deja.get(p["id"])
        if avant and not forcer:            # on garde mesures et analyses déjà faites
            for cle in ("vignette", "mesures", "analyse", "publiee"):
                if cle in avant:
                    p[cle] = avant[cle]
        if p.get("type") != "photo":
            continue
        vig = dossier / "vignettes" / f"{p['id']}.jpg"
        if forcer or not vig.exists():
            try:
                if p.get("chemin_local"):
                    images.vignette(p["chemin_local"], vig, cote=640)
                else:
                    r = _get(p["url"]["smallres"])
                    vig.parent.mkdir(parents=True, exist_ok=True)
                    vig.write_bytes(r.content)
                nouvelles += 1
            except Exception as e:  # une photo manquante ne bloque pas la série
                p["erreur"] = str(e)[:160]
                continue
        p["vignette"] = str(vig.relative_to(dossier))
        if forcer or not p.get("mesures"):
            m = images.mesurer(images.ouvrir(vig))
            if p.get("nb_palette") is True:
                m["tonalite"] = "nb"
            p["mesures"] = m
            p.setdefault("proportion", m["proportion"])
            p.setdefault("orientation", m["orientation"])
            if not p.get("proportion"):
                p["proportion"], p["orientation"] = m["proportion"], m["orientation"]
    cat = {"serie": serie_id, "source": {**info, "indexe_le": config.maintenant().isoformat(timespec="minutes")},
           "photos": photos}
    _marquer_doublons(cat)
    ecrire_catalogue(serie_id, cat)
    return {"serie": serie_id, "photos": len(photos), "nouvelles_vignettes": nouvelles,
            "clips": sum(1 for p in photos if p.get("type") == "clip")}


def _marquer_doublons(cat: dict, seuil: int = 9) -> None:
    """Regroupe les rafales (photos quasi identiques) : la meilleure note représentera le groupe."""
    vues = [p for p in cat["photos"] if p.get("mesures")]
    groupe = 0
    for p in vues:
        p.pop("groupe", None)
    for i, p in enumerate(vues):
        if "groupe" in p:
            continue
        groupe += 1
        p["groupe"] = groupe
        for q in vues[i + 1:i + 12]:       # rafales = photos voisines dans la galerie
            if "groupe" not in q and images.distance(p["mesures"]["empreinte"], q["mesures"]["empreinte"]) <= seuil:
                q["groupe"] = groupe


def telecharger_hd(serie_id: str, ids: list) -> dict:
    """Récupère la meilleure version disponible des photos choisies."""
    s = config.serie(serie_id)
    cat = lire_catalogue(serie_id)
    par_id = {p["id"]: p for p in cat["photos"]}
    exports = s.get("exports_hd")          # dossier local d'exports pleine définition (facultatif)
    index_exports = {}
    if exports and config.chemin_utilisateur(exports).is_dir():
        for f in config.chemin_utilisateur(exports).rglob("*"):
            if f.suffix.lower() in EXTENSIONS:
                index_exports[f.stem.lower()] = f
    dossier = config.dossier_serie(serie_id) / "hd"
    dossier.mkdir(parents=True, exist_ok=True)
    res = {}
    for ident in ids:
        p = par_id.get(str(ident))
        if not p:
            res[str(ident)] = {"erreur": "photo inconnue dans le catalogue"}
            continue
        if p.get("chemin_local"):
            res[p["id"]] = {"chemin": p["chemin_local"], "origine": "dossier"}
            continue
        locale = index_exports.get((p.get("fichier_origine") or "").lower())
        if locale:
            res[p["id"]] = {"chemin": str(locale), "origine": "export_hd"}
            continue
        cible = dossier / f"{p['id']}.jpg"
        if not cible.exists():
            r = _get(p["url"]["lowres"])
            cible.write_bytes(r.content)
        res[p["id"]] = {"chemin": str(cible), "origine": "pictime_1600px"}
    return res


def chemin_photo(serie_id: str, ident: str, hd: bool = True) -> Path:
    """Chemin local d'une photo (HD si téléchargée, sinon vignette)."""
    dossier = config.dossier_serie(serie_id)
    cat = lire_catalogue(serie_id)
    for p in cat["photos"]:
        if p["id"] == str(ident):
            if p.get("chemin_local"):
                return Path(p["chemin_local"])
            if hd and (dossier / "hd" / f"{p['id']}.jpg").exists():
                return dossier / "hd" / f"{p['id']}.jpg"
            if hd:
                return Path(telecharger_hd(serie_id, [p["id"]])[p["id"]]["chemin"])
            return dossier / p.get("vignette", f"vignettes/{p['id']}.jpg")
    raise ErreurStudio(f"Photo {ident} absente du catalogue de {serie_id}.")


# =========================================================================== planches et notes

def planches(serie_id: str, par: int = 20, seulement_non_notees: bool = True) -> list:
    """Planches contact numérotées pour l'analyse visuelle par Claude."""
    cat = lire_catalogue(serie_id)
    dossier = config.dossier_serie(serie_id)
    vues, deja = [], set()
    for p in cat["photos"]:
        if p.get("type") != "photo" or not p.get("vignette"):
            continue
        if seulement_non_notees and p.get("analyse"):
            continue
        g = p.get("groupe")
        if g in deja:          # une seule photo par rafale sur les planches
            continue
        deja.add(g)
        vues.append(p)
    sorties, correspondance = [], {}
    for k in range(0, len(vues), par):
        lot = vues[k:k + par]
        num = k // par + 1
        elements = []
        for j, p in enumerate(lot):
            etiquette = k + j + 1
            correspondance[str(etiquette)] = p["id"]
            elements.append((etiquette, dossier / p["vignette"]))
        f = images.planche_contact(elements, dossier / "planches" / f"planche-{num:02d}.jpg",
                                   titre=f"{serie_id} · planche {num}")
        sorties.append(str(f))
    config.ecrire_json(dossier / "planches" / "correspondance.json", correspondance)
    return sorties


CHAMPS_ANALYSE = {"note", "pilier", "plan", "sujet", "description", "centree_couple", "moment", "remarque",
                  "rotation"}


def rotation(serie_id: str, ident: str) -> int:
    """Rotation notée à l'analyse (photo couchée ou à l'envers), 0 sinon."""
    for p in lire_catalogue(serie_id).get("photos", []):
        if p["id"] == str(ident):
            return int((p.get("analyse") or {}).get("rotation") or 0)
    return 0


def noter(serie_id: str, fichier_notes: str) -> dict:
    """Fusionne les analyses écrites par Claude : {"12": {"note": 4, ...}, ...} (numéros de planche ou ids)."""
    notes = config.lire_json(fichier_notes, {})
    dossier = config.dossier_serie(serie_id)
    corr = config.lire_json(dossier / "planches" / "correspondance.json", {}) or {}
    cat = lire_catalogue(serie_id)
    par_id = {p["id"]: p for p in cat["photos"]}
    faites, inconnues = 0, []
    for cle, analyse in notes.items():
        ident = corr.get(str(cle), str(cle))
        p = par_id.get(ident)
        if not p:
            inconnues.append(cle)
            continue
        propre = {k: v for k, v in analyse.items() if k in CHAMPS_ANALYSE}
        p["analyse"] = propre
        faites += 1
        # la note se propage aux autres photos de la même rafale (sans écraser une note propre)
        for q in cat["photos"]:
            if q is not p and q.get("groupe") == p.get("groupe") and not q.get("analyse"):
                q["analyse"] = {**propre, "note": max(1, int(propre.get("note", 3)) - 1), "heritee_de": p["id"]}
    ecrire_catalogue(serie_id, cat)
    return {"analysees": faites, "inconnues": inconnues}


def etat_series() -> list:
    res = []
    publiees = {x for h in config.historique() for m in h.get("medias", []) for x in config.ids_media(m)}
    for s in config.series():
        cat = lire_catalogue(s["id"])
        photos = [p for p in cat.get("photos", []) if p.get("type") == "photo"]
        notees = [p for p in photos if p.get("analyse")]
        fortes = [p for p in notees if int(p["analyse"].get("note", 0)) >= 4 and p["id"] not in publiees]
        res.append({"serie": s["id"], "statut": s.get("statut", "active"), "photos": len(photos),
                    "analysees": len(notees), "fortes_disponibles": len(fortes),
                    "a_indexer": not photos, "a_analyser": len(photos) - len(notees)})
    return res
