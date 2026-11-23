"""Pont entre l'app Mac « Studio Instagram » et le moteur.

L'app n'écrit jamais elle-même dans les fichiers du studio : elle appelle
`./studio app <action>` et reçoit du JSON. Ses décisions passent par les mêmes
fonctions que Claude (choix, approbation, retouche, report), avec les mêmes contrôles.

Quand une tâche Claude a besoin de la photographe, elle lance
`./studio ui <écran> --jour J --attendre` : l'app s'ouvre sur le bon écran et la
commande rend la décision (JSON) dès que la photographe l'a prise.
"""
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import time
import uuid
from pathlib import Path

import yaml

from . import config, images, journee, regles, sources
from .config import ErreurStudio

ECRANS = ("aujourdhui", "idees", "creation", "apercu", "galeries", "reglages", "charte", "regles", "statistiques")
JOURS = config.JOURS_FR
LIBELLE_PILIER = {"EDITORIAL": "Éditorial", "DOCUMENTARY": "Documentaire", "DETAILS": "Détails",
                  "PLACES": "Lieux", "PORTRAITS": "Portraits", "LOVE_STORY": "Love story",
                  "ATMOSPHERE": "Atmosphère", "ARTISTIC_VISION": "Vision artistique"}
LIBELLE_FORMAT = {"carrousel": "Carrousel", "image": "Image seule", "reel": "Vidéo"}
LIBELLE_STATUT = {"nouveau": "En préparation", "idees_proposees": "Idées à choisir",
                  "idee_choisie": "Post en préparation", "brouillon_pret": "Aperçu à valider",
                  "approuve": "Validé, publication prévue", "publie": "Publié", "reporte": "Reporté",
                  "abandonne": "Abandonné", "echec": "Échec de publication"}


def _maintenant() -> str:
    return config.maintenant().isoformat(timespec="seconds")


def _abs(p) -> str:
    return str(Path(p).resolve()) if p else None


def _lire_json_fichier(fichier: str):
    with open(fichier, encoding="utf-8") as fh:
        return json.load(fh)


# =========================================================================== ouverture de l'app

def chemin_app():
    info = config.lire_json(config.chemin(".ui", "app.json"), {}) or {}
    p = info.get("app")
    return Path(p) if p and Path(p).exists() else None


def _pointer_app():
    """L'app suit le dossier du studio qui la sollicite (utile s'il en existe plusieurs)."""
    f = Path.home() / "Library" / "Application Support" / "Studio Instagram" / "reglages.json"
    actuel = config.lire_json(f, {}) or {}
    if actuel.get("dossier") != str(config.RACINE):
        config.ecrire_json(f, {**actuel, "dossier": str(config.RACINE)})


def ouvrir(ecran: str, jour: str = None, forcer: bool = False) -> dict:
    """Montre un écran de l'app. Elle passe au premier plan si `interface.ouvrir_app` le permet
    (ou si `forcer`) ; sinon elle affichera cet écran quand la photographe l'ouvrira."""
    if ecran not in ECRANS:
        raise ErreurStudio(f"Écran inconnu : {ecran} ({', '.join(ECRANS)})")
    auto = forcer or reglages()["interface"]["ouvrir_app"]
    config.ecrire_json(config.chemin(".ui", "demande.json"),
                       {"id": uuid.uuid4().hex, "ecran": ecran, "jour": jour, "le": _maintenant(), "activer": auto})
    app = chemin_app()
    if not app:
        return {"etat": "app_absente", "conseil": "Relance l'installation pour construire l'app Studio Instagram."}
    _pointer_app()
    if not auto:
        return {"etat": "en_attente", "ecran": ecran, "jour": jour,
                "conseil": "Ouverture automatique désactivée : l'app montrera cet écran quand elle l'ouvrira."}
    subprocess.run(["open", "-a", str(app)], check=False, capture_output=True)
    return {"etat": "ouverte", "ecran": ecran, "jour": jour}


# =========================================================================== décisions

def _fichier_decision(jour: str) -> Path:
    return config.dossier_jour(jour) / "decision.json"


def _fichier_attente(jour: str) -> Path:
    return config.dossier_jour(jour) / ".attente.json"


def claude_attend(jour: str) -> bool:
    a = config.lire_json(_fichier_attente(jour), None)
    if not a:
        return False
    try:
        os.kill(int(a["pid"]), 0)
        return True
    except Exception:
        return False


def attendre(jour: str, delai: float = None) -> dict:
    """Bloque jusqu'à une nouvelle décision prise dans l'app (lancé en arrière-plan par Claude)."""
    avant = (config.lire_json(_fichier_decision(jour), {}) or {}).get("id")
    config.ecrire_json(_fichier_attente(jour), {"pid": os.getpid(), "le": _maintenant()})
    try:
        fin = time.time() + delai if delai else None
        while True:
            d = config.lire_json(_fichier_decision(jour), None)
            if d and d.get("id") != avant:
                return d
            if fin and time.time() > fin:
                return {"type": "delai_depasse"}
            time.sleep(1.5)
    finally:
        try:
            _fichier_attente(jour).unlink()
        except FileNotFoundError:
            pass


def _noter(jour: str, type_: str, **champs) -> dict:
    d = {"id": uuid.uuid4().hex, "type": type_, "le": _maintenant(), "traitee": False,
         "claude_attend": claude_attend(jour), **champs}
    config.ecrire_json(_fichier_decision(jour), d)
    config.ajouter_jsonl(config.chemin("donnees", "decisions.jsonl"), {"jour": jour, **d})
    return d


def decision_traitee(jour: str) -> dict:
    f = _fichier_decision(jour)
    d = config.lire_json(f, None)
    if d:
        d["traitee"] = True
        config.ecrire_json(f, d)
    return d or {}


def decider(jour: str, action: str, valeur: str = None) -> dict:
    if action == "choix":
        c = journee.enregistrer_choix(jour, numero=int(valeur))
        return _noter(jour, "choix", numero=int(valeur), titre=c.get("titre"))
    if action == "libre":
        if not (valeur or "").strip():
            raise ErreurStudio("Écris ton idée avant de l'envoyer.")
        journee.enregistrer_choix(jour, libre=valeur.strip())
        return _noter(jour, "libre", texte=valeur.strip())
    if action == "approuver":
        quand = valeur or "creneau"
        e = journee.approuver(jour, quand)
        if quand == "maintenant":
            from . import publication
            r = publication.publier(jour)
            return _noter(jour, "publie", permalink=r.get("permalink"), avertissements=r.get("avertissements"),
                          traitee=True)
        return _noter(jour, "approuve", publier_a=e.get("publier_a"), traitee=True)
    if action == "retouche":
        if not (valeur or "").strip():
            raise ErreurStudio("Décris la retouche avant de l'envoyer.")
        journee.enregistrer_retouche(jour, valeur.strip())
        return _noter(jour, "retouche", demande=valeur.strip())
    if action == "reporter":
        journee.maj(jour, "reporte")
        return _noter(jour, "reporte", traitee=True)
    raise ErreurStudio(f"Action inconnue : {action}")


# =========================================================================== vue d'une journée

def _vignette(serie: str, ident: str, sortie: Path, ratio=None, cote=640):
    if not ident:
        return None
    if sortie.exists():
        return _abs(sortie)
    try:
        src = sources.chemin_photo(serie, ident, hd=False)
        img = images.tourner(images.ouvrir(src), sources.rotation(serie, ident))
        if ratio:
            img = img.crop(images._fenetre(img.width, img.height, ratio, "centre"))
        img.thumbnail((cote, cote * 2))
        sortie.parent.mkdir(parents=True, exist_ok=True)
        img.save(sortie, "JPEG", quality=86)
        return _abs(sortie)
    except Exception:
        return None


def _couvertures(n=8) -> list:
    res = []
    for h in reversed(config.historique()):
        f = config.chemin("donnees", "couvertures", f"{h.get('jour') or h.get('date')}.jpg")
        res.append(_abs(f) if f.exists() else None)
        if len(res) >= n:
            break
    return res


def vue_jour(jour: str = None) -> dict:
    jour = jour or config.aujourdhui()
    d = config.chemin("jours", jour)
    res = {"jour": jour, "aujourdhui": config.aujourdhui(), "existe": d.exists()}
    try:
        res["date_longue"] = config.date_longue(jour)
        res["creneau"] = regles.creneau(jour)
    except ValueError:
        res["date_longue"], res["creneau"] = jour, None
    if not d.exists():
        res.update({"statut": "nouveau", "statut_libelle": "Rien de prévu pour l'instant", "idees": [],
                    "post": None, "grille": _couvertures()})
        return res
    e = journee.etat(jour)
    res["statut"] = e.get("statut", "nouveau")
    res["statut_libelle"] = LIBELLE_STATUT.get(res["statut"], res["statut"])
    res["publier_a"] = e.get("publier_a")
    res["permalink"] = e.get("permalink")
    res["erreur"] = e.get("erreur")
    res["claude_attend"] = claude_attend(jour)
    res["decision"] = config.lire_json(d / "decision.json", None)
    ui = d / "ui"
    data = config.lire_json(d / "idees.json", {}) or {}
    res["lecture_du_feed"] = data.get("lecture_du_feed")
    res["choix"] = data.get("choix")
    idees = []
    for n, idee in enumerate(data.get("idees") or [], 1):
        serie = idee.get("serie")
        photos = [v for v in (idee.get("photos") or []) if v != idee.get("couverture")][:3]
        idees.append({
            "brief": _brief(idee.get("brief") or idee.get("pitch") or idee.get("titre") or ""),
            **{k: idee.get(k) for k in ("titre", "pitch", "format", "nb_medias", "duree_s", "pilier", "serie", "type",
                                        "longueur_legende", "musique", "pourquoi")},
            "numero": n,
            "pilier_libelle": LIBELLE_PILIER.get(idee.get("pilier"), idee.get("pilier")),
            "format_libelle": LIBELLE_FORMAT.get(idee.get("format"), idee.get("format")),
            "couverture": _vignette(serie, idee.get("couverture"), ui / f"idee-{n}.jpg", ratio=4 / 5, cote=720),
            "vignettes": [x for x in (_vignette(serie, v, ui / f"idee-{n}-{k}.jpg", ratio=1, cote=320)
                                      for k, v in enumerate(photos, 1)) if x],
        })
    res["idees"] = idees
    post = config.lire_json(d / "post.json", None)
    res["post"] = None
    if post:
        rendu = d / "rendu"
        medias = sorted(post.get("medias") or [], key=lambda m: m.get("ordre", 0))
        cfg = config.compte()
        res["post"] = {
            **{k: post.get(k) for k in ("titre", "format", "pilier", "intention", "pourquoi", "legende",
                                        "longueur_legende", "hashtags", "collaborateurs", "localisation",
                                        "date", "heure", "serie", "alertes")},
            "pilier_libelle": LIBELLE_PILIER.get(post.get("pilier"), post.get("pilier")),
            "format_libelle": LIBELLE_FORMAT.get(post.get("format"), post.get("format")),
            "compte": str(cfg.get("compte_instagram") or "").lstrip("@"),
            "nom": cfg.get("nom") or "",
            "musique": post.get("musique") or {},
            "medias": [{"ordre": i, "role": m.get("role"), "presentation": m.get("presentation"),
                        "photo_id": (config.ids_media(m) or [""])[0], "fond": m.get("fond"),
                        "module": m.get("module"), "photos": config.ids_media(m),
                        "texte_alternatif": m.get("texte_alternatif"),
                        "identifications": [(t.get("compte") if isinstance(t, dict) else t)
                                            for t in (m.get("identifications") or [])],
                        "image": _abs(rendu / f"{i:02d}.jpg") if (rendu / f"{i:02d}.jpg").exists() else None}
                       for i, m in enumerate(medias, 1)],
            "video": None,
            "couverture": _abs(rendu / "01.jpg") if (rendu / "01.jpg").exists() else None,
        }
        v = regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie")))
        res["verdict"] = {"conforme": v["conforme"], "erreurs": v["erreurs"], "avertissements": v["avertissements"],
                          "alertes": v["alertes"], "caracteres": v["legende"]["caracteres"]}
    res["grille"] = _couvertures()
    return res


def vue_jours(n: int = 60) -> list:
    racine = config.chemin("jours")
    res = []
    if not racine.exists():
        return res
    for d in sorted((x for x in racine.iterdir() if x.is_dir() and x.name != "demo"), reverse=True)[:n]:
        e = config.lire_json(d / "etat.json", {}) or {}
        post = config.lire_json(d / "post.json", {}) or {}
        idees = config.lire_json(d / "idees.json", {}) or {}
        titre = post.get("titre") or (idees.get("choix") or {}).get("titre") or (idees.get("choix") or {}).get("libre")
        try:
            date_longue = config.date_longue(d.name)
        except ValueError:
            date_longue = d.name
        res.append({"jour": d.name, "date_longue": date_longue, "statut": e.get("statut", "nouveau"),
                    "statut_libelle": LIBELLE_STATUT.get(e.get("statut", "nouveau"), e.get("statut")),
                    "titre": titre})
    return res


# =========================================================================== réglages du compte

HEURE = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
COULEUR = re.compile(r"^#[0-9a-fA-F]{6}$")


def reglages() -> dict:
    c = config.compte()
    pub, rou = c.get("publication") or {}, c.get("routine") or {}
    ig, mep, itf = c.get("instagram") or {}, c.get("mise_en_page") or {}, c.get("interface") or {}
    fonds = {"clair": "#f6f2ec", "sombre": "#141412", "papier": "#efe6da", **(mep.get("fonds") or {})}
    return {
        "nom": c.get("nom") or "", "compte_instagram": c.get("compte_instagram") or "",
        "activite": str(c.get("activite") or "photographe de mariage"),
        "localisation": c.get("localisation") or "", "voix": c.get("voix") or "", "langue": c.get("langue") or "",
        "fuseau": c.get("fuseau") or "Europe/Paris", "approche": (c.get("approche") or "").rstrip(),
        "exemples_de_legendes": [str(x) for x in (c.get("exemples_de_legendes") or [])],
        "publication": {
            "creneaux": {j: str((pub.get("creneaux") or {}).get(j) or "") for j in JOURS},
            "hebergement": pub.get("hebergement", "tunnel"),
            "bucket_supabase": pub.get("bucket_supabase", "instagram-temp"),
        },
        "routine": {
            "heure_idees": str(rou.get("heure_idees", "08:00")), "nombre_idees": int(rou.get("nombre_idees", 3)),
            "idees_exploration": int(rou.get("idees_exploration", 1)),
            "jour_bilan": rou.get("jour_bilan", "dimanche"), "heure_bilan": str(rou.get("heure_bilan", "19:00")),
        },
        "instagram": {"api": ig.get("api", "facebook"), "version_api": ig.get("version_api", "v25.0")},
        "mise_en_page": {"marge_px": int(mep.get("marge_px", 64)), "fonds": fonds},
        "interface": {"artifact": bool(itf.get("artifact", False)),
                      "ouvrir_app": bool(itf.get("ouvrir_app", True))},
        "planification": {"active": bool((c.get("planification") or {}).get("active", False))},
        "creation": {"etapes_a_valider": _etapes_creation(c)},
        "claude": {"modele": str((c.get("claude") or {}).get("modele") or ""),
                   "effort": str((c.get("claude") or {}).get("effort") or "")},
        "comptes_autorises": [str(x).lstrip("@") for x in (c.get("comptes_autorises") or [])],
        "images_deja_publiees": [str(x) for x in (c.get("images_deja_publiees") or [])],
    }


ETAPES_CREATION = ("photos", "legende", "musique")      # l'aperçu final se valide toujours


def _etapes_creation(c: dict) -> list:
    v = (c.get("creation") or {}).get("etapes_a_valider")
    if not isinstance(v, list):
        return list(ETAPES_CREATION)
    return [e for e in ETAPES_CREATION if e in v]


def _ecrire_yaml(rel: str, data: dict, entete: str):
    f = config.chemin(rel)
    f.parent.mkdir(parents=True, exist_ok=True)
    texte = yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=110)
    f.write_text(entete.rstrip() + "\n\n" + texte, encoding="utf-8")


def enregistrer_reglages(fichier: str) -> dict:
    n = _lire_json_fichier(fichier)
    erreurs = []
    pub, rou = n.get("publication") or {}, n.get("routine") or {}
    creneaux = {j: h for j, h in (pub.get("creneaux") or {}).items() if j in JOURS and str(h).strip()}
    for j, h in creneaux.items():
        if not HEURE.match(str(h)):
            erreurs.append(f"Heure invalide pour {j} : {h}")
    for nom in ("heure_idees", "heure_bilan"):
        if rou.get(nom) and not HEURE.match(str(rou[nom])):
            erreurs.append(f"Heure invalide : {rou[nom]}")
    nb = int(rou.get("nombre_idees", 3))
    if not 1 <= nb <= 6:
        erreurs.append("Entre 1 et 6 idées par matin")
    if not 0 <= int(rou.get("idees_exploration", 1)) <= nb:
        erreurs.append("Plus d'idées d'exploration que d'idées")
    for nom, coul in ((n.get("mise_en_page") or {}).get("fonds") or {}).items():
        if not COULEUR.match(str(coul)):
            erreurs.append(f"Couleur invalide pour le fond {nom} : {coul}")
    if (n.get("instagram") or {}).get("api") not in ("facebook", "instagram"):
        erreurs.append("Route Instagram inconnue")
    if pub.get("hebergement") not in ("tunnel", "supabase"):
        erreurs.append("Hébergement inconnu")
    if erreurs:
        return {"etat": "refuse", "erreurs": erreurs}
    c = config.compte()
    for cle in ("nom", "compte_instagram", "activite", "localisation", "voix", "langue", "fuseau", "approche",
                "exemples_de_legendes", "comptes_autorises", "images_deja_publiees"):
        if cle in n:
            c[cle] = n[cle]
    c["compte_instagram"] = str(c.get("compte_instagram") or "").lstrip("@")
    c["publication"] = {**(c.get("publication") or {}), **{k: v for k, v in pub.items() if k != "creneaux"},
                        "creneaux": creneaux}
    c["routine"] = {**(c.get("routine") or {}), **rou}
    for sec in ("instagram", "mise_en_page", "interface", "claude"):
        if sec in n and isinstance(n[sec], dict):
            c[sec] = {**(c.get(sec) or {}), **n[sec]}
    if isinstance(n.get("creation"), dict) and "etapes_a_valider" in n["creation"]:
        c["creation"] = {**(c.get("creation") or {}),
                         "etapes_a_valider": [e for e in ETAPES_CREATION if e in (n["creation"]["etapes_a_valider"] or [])]}
    avant = bool((c.get("planification") or {}).get("active", False))
    voulu = bool(((n.get("planification") or {}).get("active", avant)))
    c["planification"] = {**(c.get("planification") or {}), "active": voulu}
    _ecrire_yaml("config/compte.yaml", c, "# Paramètres du compte. Modifiables dans l'app Studio Instagram (Réglages).\n"
                                          "# Tant qu'un champ contient [À COMPLÉTER], le studio le signale.")
    avertissements = []
    if voulu or avant:                     # heures changées ou planification (dés)activée : le Mac suit
        from . import planification
        try:
            planification.appliquer()
        except ErreurStudio as e:
            avertissements.append(str(e))
    return {"etat": "enregistre", "erreurs": [], "avertissements": avertissements}


# =========================================================================== apparence (config/app.yaml)

APPARENCE_DEFAUT = {
    "nom_affiche": "Studio Instagram",
    "salutation": "Bonjour",
    "mode": "auto",
    "couleurs": {"accent": "#3d4130", "accent_doux": "#efdccd", "fond_clair": "#f7f3ed",
                 "fond_sombre": "#17160f", "succes": "#3f6b45", "alerte": "#a8551c"},
    "ambiance": "provence",
    "police": "jakarta",
    "titres": "police",
    "points": False,
    "densite": "confortable",
    "arrondi": 14,
    "animations": "normales",
    "icones": "pleines",
    "ecrans": [e for e in ECRANS if e != "creation"],
}
CHOIX_APPARENCE = {"mode": ("auto", "clair", "sombre"), "titres": ("police", "serif", "arrondi", "standard"),
                   "ambiance": ("provence", "lavande", "aube", "sauge", "nuit"),
                   "police": ("jakarta", "systeme", "arrondie"),
                   "densite": ("compacte", "confortable", "aeree"),
                   "animations": ("aucune", "discretes", "normales", "riches"), "icones": ("pleines", "contours")}
ECRANS_FIXES = ("aujourdhui", "reglages")
# Ambiance libre, choisie sur le nuancier de Réglages › Apparence : « humeur:0.42,0.70 » (x, y entre 0 et 1).
HUMEUR = re.compile(r"^humeur:(0(\.\d{1,3})?|1(\.0{1,3})?),(0(\.\d{1,3})?|1(\.0{1,3})?)$")
APPARENCE_REGLABLE = ("nom_affiche", "salutation", "mode", "ambiance")
APPARENCE_FIXE = ("police", "titres", "points", "densite", "arrondi", "animations", "icones")
# Barre d'icônes : l'essentiel. Idées et aperçu passent par « + » et l'accueil ; charte et règles par les Réglages.
ECRANS_ESSENTIELS = ("aujourdhui", "galeries", "statistiques", "reglages")
ENTETE_APPARENCE = ("# Apparence de l'app Studio Instagram. Modifiable dans l'app (Réglages › Apparence)\n"
                    "# ou en le demandant à Claude. L'app se met à jour dès que ce fichier change.")


def _ecrans(liste) -> list:
    vus = [e for i, e in enumerate(liste or []) if e in ECRANS and e not in (liste or [])[:i]]
    for e in ECRANS_FIXES:
        if e not in vus:
            vus.insert(0 if e == "aujourdhui" else len(vus), e)
    return vus


def apparence() -> dict:
    """L'apparence normalisée : chaque valeur absente ou invalide reprend sa valeur par défaut."""
    f = config.chemin("config", "app.yaml")
    try:
        a = yaml.safe_load(f.read_text(encoding="utf-8")) if f.exists() else {}
    except (OSError, yaml.YAMLError):
        a = {}
    a = a if isinstance(a, dict) else {}
    if a and "ambiance" not in a:
        # Fichier d'avant les ambiances (style « papier ») : les titres serif y étaient la valeur par défaut,
        # pas un choix. On passe aux valeurs de la nouvelle apparence (Plus Jakarta Sans partout).
        a = {k: v for k, v in a.items() if k != "titres"}
    d = APPARENCE_DEFAUT
    couleurs = {k: (str(v) if COULEUR.match(str(v or "")) else d["couleurs"][k])
                for k, v in {**d["couleurs"], **(a.get("couleurs") or {})}.items() if k in d["couleurs"]}
    res = {
        "nom_affiche": str(a.get("nom_affiche") or d["nom_affiche"])[:40],
        "salutation": str(a.get("salutation") or d["salutation"])[:60],
        "couleurs": couleurs,
        "arrondi": max(0, min(28, int(a["arrondi"]))) if str(a.get("arrondi", "")).lstrip("-").isdigit() else d["arrondi"],
        "ecrans": _ecrans(a.get("ecrans") if isinstance(a.get("ecrans"), list) else d["ecrans"]),
    }
    for cle, choix in CHOIX_APPARENCE.items():
        res[cle] = a.get(cle) if a.get(cle) in choix else d[cle]
    if HUMEUR.match(str(a.get("ambiance") or "")):
        res["ambiance"] = a["ambiance"]
    res["points"] = bool(a.get("points", d["points"])) if isinstance(a.get("points", d["points"]), bool) else d["points"]
    # Seuls le mode, l'ambiance, le nom du studio et la salutation se règlent : le reste est fixé pour garder
    # une app simple et rapide (pas de trame de points, police et formes d'origine, écrans essentiels).
    res.update({k: APPARENCE_DEFAUT[k] for k in APPARENCE_FIXE})
    res["couleurs"] = dict(APPARENCE_DEFAUT["couleurs"])
    res["ecrans"] = list(ECRANS_ESSENTIELS)
    return res


def _valider_apparence(n: dict) -> list:
    erreurs = []
    for cle, v in (n.get("couleurs") or {}).items():
        if cle not in APPARENCE_DEFAUT["couleurs"]:
            erreurs.append(f"Couleur inconnue : {cle}")
        elif not COULEUR.match(str(v)):
            erreurs.append(f"Couleur invalide pour {cle} : {v} (format #rrggbb)")
    for cle, choix in CHOIX_APPARENCE.items():
        if cle == "ambiance" and HUMEUR.match(str(n.get(cle) or "")):
            continue
        if cle in n and n[cle] not in choix:
            erreurs.append(f"Valeur invalide pour {cle} : {n[cle]} ({', '.join(choix)})")
    if "points" in n and not isinstance(n["points"], bool):
        erreurs.append("La trame de points se règle par oui ou non")
    if "arrondi" in n:
        try:
            if not 0 <= int(n["arrondi"]) <= 28:
                erreurs.append("L'arrondi va de 0 à 28")
        except (TypeError, ValueError):
            erreurs.append("L'arrondi doit être un nombre de 0 à 28")
    if "ecrans" in n:
        inconnus = [e for e in (n["ecrans"] or []) if e not in ECRANS]
        if inconnus:
            erreurs.append("Écrans inconnus : " + ", ".join(map(str, inconnus)))
    for cle in ("nom_affiche", "salutation"):
        if cle in n and not str(n[cle] or "").strip():
            erreurs.append(f"Le champ {cle} ne peut pas être vide")
    return erreurs


def enregistrer_apparence(fichier: str) -> dict:
    n = _lire_json_fichier(fichier)
    if not isinstance(n, dict):
        return {"etat": "refuse", "erreurs": ["Format inattendu."]}
    erreurs = _valider_apparence(n)
    if erreurs:
        return {"etat": "refuse", "erreurs": erreurs}
    actuelle = apparence()
    fusion = {**actuelle, **{k: v for k, v in n.items() if k in APPARENCE_REGLABLE}}
    _ecrire_yaml("config/app.yaml", {k: fusion[k] for k in APPARENCE_REGLABLE}, ENTETE_APPARENCE)
    return {"etat": "enregistre", "erreurs": []}


def retablir_apparence() -> dict:
    _ecrire_yaml("config/app.yaml", {k: APPARENCE_DEFAUT[k] for k in APPARENCE_REGLABLE}, ENTETE_APPARENCE)
    return {"etat": "retablie"}


# =========================================================================== modifications du post (assistant de création)

PRESENTATIONS_MEDIA = ("plein_cadre", "marges")
FONDS_MEDIA = ("clair", "sombre", "papier")
MODES_MUSIQUE = ("api_reel", "integree", "a_ajouter_dans_l_app", "aucune")


def _nouveau_media(serie: str, ident: str) -> dict:
    from . import sources
    photo = next((p for p in sources.lire_catalogue(serie).get("photos", []) if p.get("id") == ident), None)
    if not photo:
        raise ErreurStudio(f"Photo inconnue dans la série {serie} : {ident}")
    paysage = (photo.get("orientation") or (photo.get("mesures") or {}).get("orientation")) == "paysage"
    description = ((photo.get("analyse") or {}).get("description") or "").strip()
    return {"fichier": ident, "photo_id": ident, "role": "progression",
            "presentation": "marges" if paysage else "plein_cadre", "ancrage": "centre", "point_focal": None,
            "rotation": None, "fond": "clair", "texte_alternatif": description or "Photo de la série.",
            "identifications": []}


def modifier_post(jour: str, fichier: str) -> dict:
    """Applique les choix faits dans l'assistant de création (photos et leur ordre, légende, musique),
    puis refait la mise en page, le contrôle et l'aperçu. Les photos ne sont jamais retouchées."""
    from . import journee, pages, regles, rendu, sources
    n = _lire_json_fichier(fichier)
    if not isinstance(n, dict):
        raise ErreurStudio("Format inattendu.")
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise ErreurStudio("Le post de ce jour n'est pas encore prêt.")
    statut = (journee.etat(jour) or {}).get("statut")
    if statut in ("approuve", "publie"):
        raise ErreurStudio("Ce post est déjà validé : reporte-le d'abord pour le modifier.")
    changements = []
    if "medias" in n:
        liste = n.get("medias") or []
        maxi = 1 if post.get("format") == "image" else int(regles.parametres()["limites"]["medias_carrousel"])
        if not 1 <= len(liste) <= maxi:
            raise ErreurStudio(f"Choisis entre 1 et {maxi} photo(s).")
        from .images import MODULES
        anciens, modules_anciens = {}, {}
        for m in post.get("medias") or []:
            ids = config.ids_media(m)
            if m.get("module"):
                modules_anciens[tuple(ids)] = m
            elif ids:
                anciens[ids[0]] = m
        nouveaux, vus = [], set()
        for i, x in enumerate(liste, 1):
            if isinstance(x, dict) and x.get("module"):          # plusieurs photos sur une même page
                mod, ids = str(x["module"]), [str(y) for y in (x.get("photos") or [])]
                if mod not in MODULES:
                    raise ErreurStudio(f"Mise en page inconnue : {mod}")
                if len(ids) != MODULES[mod]["photos"]:
                    raise ErreurStudio(f"« {MODULES[mod]['nom']} » demande {MODULES[mod]['photos']} photo(s).")
                if any(y in vus for y in ids):
                    raise ErreurStudio("Chaque photo ne peut apparaître qu'une fois.")
                vus.update(ids)
                m = modules_anciens.get(tuple(ids))
                if m:
                    m = dict(m)
                else:
                    bases = [anciens.get(y) or _nouveau_media(post.get("serie"), y) for y in ids]
                    m = {k: v for k, v in bases[0].items() if k not in ("presentation", "ancrage", "point_focal", "rotation")}
                    alts = [str(b.get("texte_alternatif") or "").strip().rstrip(".") for b in bases]
                    m["texte_alternatif"] = (alts[0] + ".") if len(ids) == 1 else \
                        f"{len(ids)} photos sur une page : " + " ; ".join(a for a in alts if a) + "."
                    m["identifications"] = []
                m.update(module=mod, photos=ids, fichier=ids[0], photo_id=ids[0])
                m.pop("presentation", None)
                if x.get("fond") in FONDS_MEDIA:
                    m["fond"] = x["fond"]
                if isinstance(x.get("texte_alternatif"), str) and x["texte_alternatif"].strip():
                    m["texte_alternatif"] = x["texte_alternatif"].strip()
                m["ordre"] = i
                nouveaux.append(m)
                continue
            ident = str(x if isinstance(x, str) else (x.get("photo_id") or x.get("fichier") or ""))
            if not ident or ident in vus:
                raise ErreurStudio("Chaque photo ne peut apparaître qu'une fois.")
            vus.add(ident)
            m = dict(anciens.get(ident) or _nouveau_media(post.get("serie"), ident))
            if isinstance(x, dict):
                if x.get("presentation") in PRESENTATIONS_MEDIA:
                    m["presentation"] = x["presentation"]
                if x.get("fond") in FONDS_MEDIA:
                    m["fond"] = x["fond"]
                if isinstance(x.get("texte_alternatif"), str) and x["texte_alternatif"].strip():
                    m["texte_alternatif"] = x["texte_alternatif"].strip()
            m.update(ordre=i, fichier=ident, photo_id=ident)
            nouveaux.append(m)
        for i, m in enumerate(nouveaux, 1):
            if i == 1:
                m["role"] = "ouverture"
            elif i == len(nouveaux) and len(nouveaux) > 2:
                m["role"] = "cloture"
            elif m.get("role") in ("ouverture", "cloture"):
                m["role"] = "progression"
        post["medias"] = nouveaux
        changements.append("photos")
    if "legende" in n:
        texte = str(n.get("legende") or "").strip()
        if not texte:
            raise ErreurStudio("La légende ne peut pas être vide.")
        post["legende"] = texte
        changements.append("legende")
    if "musique" in n:
        mu = n.get("musique") or {}
        if not isinstance(mu, dict) or mu.get("mode") not in MODES_MUSIQUE:
            raise ErreurStudio("Musique invalide.")
        garde = ("mode", "audio_id", "titre", "artiste", "apercu_url", "pochette", "source", "lien",
                 "volume_musique", "volume_video",
                 "direction_sonore", "requete")
        post["musique"] = {**(post.get("musique") or {}), **{k: mu.get(k) for k in garde if k in mu}}
        changements.append("musique")
    if not changements:
        return {"etat": "inchange", "changements": []}
    config.ecrire_json(d / "post.json", post)
    rendu_info = rendu.rendre(jour) if "photos" in changements else None
    post.setdefault("jour", jour)
    controle = regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie")))
    pages.page_apercu(jour)
    journee.maj(jour, "brouillon_pret")
    config.ajouter_jsonl(config.chemin("donnees", "retouches.jsonl"),
                         {"jour": jour, "le": _maintenant(), "type": "modification_dans_l_app",
                          "changements": changements})
    return {"etat": "enregistre", "changements": changements, "controle": controle,
            "avertissements": (rendu_info or {}).get("avertissements") or []}


def candidats_galerie(serie: str, n: int = 60) -> list:
    """Photos de la série à proposer dans l'assistant (vignette, note, description)."""
    from . import sources
    res = []
    for p in sources.lire_catalogue(serie).get("photos", []):
        if p.get("type", "photo") != "photo":
            continue
        a = p.get("analyse") or {}
        vignette = config.chemin("catalogue", serie, p.get("vignette") or f"vignettes/{p.get('id')}.jpg")
        res.append({"id": p.get("id"), "note": a.get("note"), "pilier": a.get("pilier"),
                    "description": a.get("description"), "orientation": p.get("orientation"),
                    "vignette": str(vignette) if vignette.exists() else None})
    res.sort(key=lambda x: -(x.get("note") or 0))
    return res[:n]


# =========================================================================== Instagram (onboarding de l'app)

def instagram() -> dict:
    """État de la connexion à Instagram, sans jamais montrer de jeton."""
    from .instagram import Instagram
    route = (config.compte().get("instagram") or {}).get("api", "facebook")
    try:
        v = Instagram().verifier_jeton()
    except ErreurStudio as e:
        return {"etat": "invalide", "route": route, "erreur": str(e)}
    return {"etat": v.get("etat", "absent"), "route": route, "compte": v.get("compte"), "abonnes": v.get("abonnes"),
            "expire_le": v.get("expire_le") or v.get("expire"), "erreur": v.get("erreur")}


def enregistrer_instagram(fichier: str) -> dict:
    """Identifiants collés par la photographe dans l'app → .env (jamais affichés), puis échange et vérification
    du jeton. Le fichier transmis par l'app est effacé dès sa lecture."""
    from .instagram import Instagram
    try:
        n = _lire_json_fichier(fichier)
    finally:
        try:
            os.remove(fichier)
        except OSError:
            pass
    route = n.get("route")
    if route not in ("facebook", "instagram"):
        return {"etat": "refuse", "erreurs": ["Choisis la route Facebook ou Instagram."]}
    valeurs = {k: "".join(str(n.get(k) or "").split()) for k in ("app_id", "app_secret", "jeton")}
    if route == "facebook":
        manque = [nom for cle, nom in (("app_id", "l'identifiant de l'app"), ("app_secret", "la clé secrète"),
                                       ("jeton", "le jeton")) if not valeurs[cle]]
        if manque:
            return {"etat": "refuse", "erreurs": ["Il manque " + ", ".join(manque) + "."]}
        config.ecrire_secret("FB_APP_ID", valeurs["app_id"])
        config.ecrire_secret("FB_APP_SECRET", valeurs["app_secret"])
        config.ecrire_secret("FB_SHORT_TOKEN", valeurs["jeton"])
    else:
        if not valeurs["jeton"]:
            return {"etat": "refuse", "erreurs": ["Colle le jeton Instagram."]}
        config.ecrire_secret("IG_ACCESS_TOKEN", valeurs["jeton"])
    c = config.compte()
    c["instagram"] = {**(c.get("instagram") or {}), "api": route}
    _ecrire_yaml("config/compte.yaml", c, "# Paramètres du compte. Modifiables dans l'app Studio Instagram (Réglages).\n"
                                          "# Tant qu'un champ contient [À COMPLÉTER], le studio le signale.")
    try:
        Instagram().echanger_jeton()
    except ErreurStudio as e:
        return {"etat": "echec", "erreurs": [str(e)]}
    r = instagram()
    if r.get("etat") != "valide":
        return {"etat": "echec", "erreurs": [r.get("erreur") or "Instagram n'a pas accepté ces identifiants."]}
    return {"etat": "connecte", "erreurs": [], "compte": r.get("compte"), "abonnes": r.get("abonnes")}


# =========================================================================== flux de l'accueil : source de photos, export

def _brief(texte: str) -> str:
    """Le brief d'une idée en une phrase (la première du pitch)."""
    t = " ".join(str(texte or "").split())
    m = re.match(r"(.+?[.!?…])(\s|$)", t)
    return (m.group(1) if m else t)[:220]


EXTENSIONS_PHOTOS = (".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff", ".webp")


def ajouter_source(fichier: str) -> dict:
    """Photos choisies pour UN post depuis l'accueil : des fichiers, un dossier ou un lien Pic-Time.
    Crée une série (galerie) dédiée, l'indexe et rend son identifiant, à passer à la création."""
    import shutil
    from . import sources
    n = _lire_json_fichier(fichier)
    t = n.get("type")
    ident = "post-" + config.maintenant().strftime("%Y%m%d-%H%M%S")
    titre = str(n.get("nom") or "").strip()
    if t == "pictime":
        url = str(n.get("url") or "").strip()
        if not url.startswith("https://") or "pic-time" not in url:
            return {"etat": "refuse", "erreurs": ["Colle le lien de partage Pic-Time complet (https://…pic-time.com/…)."]}
        source = {"type": "pictime", "url": url}
    elif t == "dossier":
        chemin = str(n.get("chemin") or "").strip()
        if not chemin or not Path(chemin).expanduser().is_dir():
            return {"etat": "refuse", "erreurs": ["Ce dossier est introuvable."]}
        source = {"type": "dossier", "chemin": chemin}
    elif t == "fichiers":
        liste = [Path(f).expanduser() for f in (n.get("fichiers") or [])]
        liste = [f for f in liste if f.is_file() and f.suffix.lower() in EXTENSIONS_PHOTOS]
        if not liste:
            return {"etat": "refuse", "erreurs": ["Choisis au moins une photo (JPEG, PNG, HEIC, TIFF ou WebP)."]}
        cible = config.chemin("sources", ident)
        cible.mkdir(parents=True, exist_ok=True)
        for f in liste:                           # copie : les originaux ne sont jamais touchés
            shutil.copy2(f, cible / f.name)
        source = {"type": "dossier", "chemin": str(cible)}
    else:
        return {"etat": "refuse", "erreurs": ["Choisis des photos, un dossier ou un lien Pic-Time."]}
    serie = {"id": ident, "type": n.get("type_serie") or "shooting", "lieu": None, "date": None,
             "maries": {"prenoms": None, "prenoms_publiables": False},
             "notes": titre or "Photos choisies pour un post depuis l'accueil de l'app.",
             "prestataires": [], "location_id": None, "source": source, "exports_hd": None,
             "consignes": "", "statut": "active"}
    _ecrire_series([s for s in config.series() if s.get("id") != ident] + [serie])
    try:
        r = sources.indexer(ident)
    except ErreurStudio as e:
        _ecrire_series([s for s in config.series() if s.get("id") != ident])
        return {"etat": "echec", "erreurs": [str(e)]}
    return {"etat": "ajoutee", "id": ident, "photos": r.get("photos", 0), "erreurs": []}


def exporter(jour: str, dossier: str = None) -> dict:
    """Le post prêt, à télécharger : images mises en page et légende complète."""
    import shutil
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise ErreurStudio("Le post de ce jour n'est pas encore prêt.")
    cible = Path(dossier).expanduser() if dossier else \
        pathlib.Path.home() / "Downloads" / "Studio Instagram" / (jour + " " + str(post.get("titre") or "post"))[:80]
    cible.mkdir(parents=True, exist_ok=True)
    fichiers = []
    rendu = d / "rendu"
    for f in sorted(rendu.glob("[0-9][0-9].jpg")):
        shutil.copy2(f, cible / f.name)
        fichiers.append(f.name)
    legende = str(post.get("legende") or "").strip()
    alt = "\n".join(f"{i:02d}. {m.get('texte_alternatif') or ''}" for i, m in
                     enumerate(sorted(post.get("medias") or [], key=lambda m: m.get("ordre", 0)), 1))
    (cible / "legende.txt").write_text(legende + "\n", encoding="utf-8")
    (cible / "textes-alternatifs.txt").write_text(alt + "\n", encoding="utf-8")
    fichiers += ["legende.txt", "textes-alternatifs.txt"]
    return {"etat": "exporte", "dossier": str(cible), "fichiers": fichiers}


# =========================================================================== archives des posts

def archiver(jour: str) -> dict:
    """Range le post du jour dans les archives (la galerie) : l'accueil repart sur un nouveau post."""
    import shutil
    d = config.chemin("jours", jour)
    if not (d / "post.json").exists() and not (d / "idees.json").exists():
        raise ErreurStudio("Rien à archiver pour ce jour.")
    ident = jour + "-" + config.maintenant().strftime("%H%M%S")
    cible = config.chemin("archives", ident)
    cible.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(d), str(cible))
    return {"etat": "archive", "id": ident}


def rouvrir_serie(serie: str) -> dict:
    """Le post fait avec les photos de cette série, remis dans son jour pour l'aperçu ou la modification."""
    import shutil
    for d in sorted(config.chemin("jours").glob("*/post.json")):
        if (config.lire_json(d, {}) or {}).get("serie") == serie:
            return {"etat": "ouvert", "jour": d.parent.name}
    archives = sorted(config.chemin("archives").glob("*/post.json"), reverse=True)
    a = next((d.parent for d in archives if (config.lire_json(d, {}) or {}).get("serie") == serie), None)
    if a is None:
        return {"etat": "aucun", "jour": None}
    jour = a.name[:10]
    if config.chemin("jours", jour).exists():
        archiver(jour)                            # le post en cours ce jour-là va d'abord aux archives
    shutil.move(str(a), str(config.chemin("jours", jour)))
    return {"etat": "ouvert", "jour": jour}


# =========================================================================== galeries

ID_SERIE = re.compile(r"^[a-z0-9][a-z0-9-]{1,60}$")


def galeries() -> list:
    stats = {s["serie"]: s for s in sources.etat_series()}
    res = []
    for s in config.series():
        st = stats.get(s.get("id"), {})
        res.append({
            "id": s.get("id"), "type": s.get("type", "mariage"), "lieu": s.get("lieu") or "",
            "date": str(s.get("date") or ""), "notes": s.get("notes") or "", "consignes": s.get("consignes") or "",
            "statut": s.get("statut", "active"), "location_id": str(s.get("location_id") or ""),
            "exports_hd": s.get("exports_hd") or "",
            "maries": {"prenoms": (s.get("maries") or {}).get("prenoms") or "",
                       "prenoms_publiables": bool((s.get("maries") or {}).get("prenoms_publiables"))},
            "prestataires": [{"role": p.get("role") or "", "nom": p.get("nom") or "", "compte": p.get("compte") or ""}
                             for p in (s.get("prestataires") or [])],
            "source": {"type": (s.get("source") or {}).get("type", "pictime"),
                       "url": (s.get("source") or {}).get("url") or "",
                       "chemin": (s.get("source") or {}).get("chemin") or ""},
            "photos": st.get("photos", 0), "analysees": st.get("analysees", 0),
            "fortes": st.get("fortes_disponibles", 0),
        })
    return res


def _ecrire_series(series: list):
    _ecrire_yaml("config/galeries.yaml", {"series": series},
                 "# Les galeries du studio. Modifiables dans l'app Studio Instagram (Galeries).\n"
                 "# Le studio ne raconte que ce qui est écrit ici (lieux, prestataires, anecdotes).")


def enregistrer_galerie(fichier: str) -> dict:
    g = _lire_json_fichier(fichier)
    ident = str(g.get("id") or "").strip()
    if not ID_SERIE.match(ident):
        return {"etat": "refuse", "erreurs": ["Identifiant : lettres minuscules, chiffres et tirets (ex. mas-uzes-2026)"]}
    src = g.get("source") or {}
    if src.get("type") == "pictime" and not src.get("url"):
        return {"etat": "refuse", "erreurs": ["Ajoute le lien de partage Pic-Time de la galerie."]}
    if src.get("type") == "dossier" and not src.get("chemin"):
        return {"etat": "refuse", "erreurs": ["Choisis le dossier des photos."]}
    serie = {
        "id": ident, "type": g.get("type") or "mariage", "lieu": g.get("lieu") or None,
        "date": g.get("date") or None,
        "maries": {"prenoms": (g.get("maries") or {}).get("prenoms") or None,
                   "prenoms_publiables": bool((g.get("maries") or {}).get("prenoms_publiables"))},
        "notes": g.get("notes") or "",
        "prestataires": [{"role": p.get("role", ""), "nom": p.get("nom", ""),
                          "compte": (str(p.get("compte") or "").lstrip("@") or None)}
                         for p in (g.get("prestataires") or []) if p.get("role") or p.get("nom")],
        "location_id": g.get("location_id") or None,
        "source": ({"type": "pictime", "url": src.get("url")} if src.get("type", "pictime") == "pictime"
                   else {"type": "dossier", "chemin": src.get("chemin")}),
        "exports_hd": g.get("exports_hd") or None,
        "consignes": g.get("consignes") or "",
        "statut": g.get("statut") or "active",
    }
    series = config.series()
    remplacee = False
    for i, s in enumerate(series):
        if s.get("id") == ident:
            series[i] = serie
            remplacee = True
    if not remplacee:
        series.append(serie)
    _ecrire_series(series)
    return {"etat": "enregistre", "erreurs": [], "nouvelle": not remplacee}


def supprimer_galerie(ident: str) -> dict:
    series = [s for s in config.series() if s.get("id") != ident]
    _ecrire_series(series)
    return {"etat": "supprimee", "id": ident}


# =========================================================================== charte et règles

def _sha(texte: str) -> str:
    return hashlib.sha256(texte.encode("utf-8")).hexdigest()


def charte() -> dict:
    base_f, perso_f = config.chemin("prompt", "directeur-artistique.md"), config.chemin("config", "charte.md")
    base = base_f.read_text(encoding="utf-8") if base_f.exists() else ""
    texte = perso_f.read_text(encoding="utf-8") if perso_f.exists() else base
    ref = config.chemin("config", ".charte-base.sha256")
    base_connue = ref.read_text().strip() if ref.exists() else _sha(base)
    return {"texte": texte, "personnalisee": perso_f.exists() and texte != base,
            "nouvelle_base": bool(base) and _sha(base) != base_connue, "base": base}


def enregistrer_charte(fichier: str) -> dict:
    texte = Path(fichier).read_text(encoding="utf-8")
    if len(texte.strip()) < 200:
        return {"etat": "refuse", "erreurs": ["La charte semble vide : rien n'a été enregistré."]}
    config.chemin("config", "charte.md").write_text(texte, encoding="utf-8")
    return {"etat": "enregistre", "erreurs": []}


def retablir_charte() -> dict:
    base = config.chemin("prompt", "directeur-artistique.md").read_text(encoding="utf-8")
    config.chemin("config", "charte.md").write_text(base, encoding="utf-8")
    config.chemin("config", ".charte-base.sha256").write_text(_sha(base), encoding="utf-8")
    return {"etat": "retablie"}


def regles_vue() -> dict:
    p = regles.parametres()
    p["legende"] = {k: list(v) for k, v in p["legende"].items()}
    return p


def enregistrer_regles(fichier: str) -> dict:
    n = _lire_json_fichier(fichier)
    propre = {}
    for section, defauts in regles.DEFAUTS.items():
        valeurs = n.get(section) or {}
        propre[section] = {}
        for k, defaut in defauts.items():
            if k not in valeurs:
                continue
            v = valeurs[k]
            if isinstance(defaut, bool):
                propre[section][k] = bool(v)
            elif isinstance(defaut, int):
                propre[section][k] = max(0, int(v))
            else:
                propre[section][k] = [str(x).strip() for x in (v or []) if str(x).strip()]
    _ecrire_yaml("config/regles.yaml", propre, "# Règles du studio : interdits de légende, limites, alternance du feed.\n"
                                               "# Modifiables dans l'app Studio Instagram (Règles).")
    return {"etat": "enregistre", "erreurs": []}


def retablir_regles() -> dict:
    f = config.chemin("config", "regles.yaml")
    if f.exists():
        f.unlink()
    return {"etat": "retablies"}


# =========================================================================== mémoire, statistiques, santé

def memoire() -> dict:
    def lire(rel):
        f = config.chemin(rel)
        return f.read_text(encoding="utf-8") if f.exists() else ""

    perf = config.lire_json(config.chemin("donnees", "performance.json"), {}) or {}
    hist = []
    for h in reversed(config.historique()[-30:]):
        f = config.chemin("donnees", "couvertures", f"{h.get('jour') or h.get('date')}.jpg")
        hist.append({"date": h.get("date"), "titre": h.get("titre") or "", "format": h.get("format"),
                     "pilier": LIBELLE_PILIER.get(h.get("pilier"), h.get("pilier") or ""),
                     "permalink": h.get("permalink"), "couverture": _abs(f) if f.exists() else None})
    resume = {"mesurees": perf.get("mesurees", 0), "message": perf.get("message"),
              "moyennes": perf.get("moyennes") or {}, "abonnes": perf.get("abonnes"),
              "fonctionne": perf.get("fonctionne") or [], "a_ameliorer": perf.get("a_ameliorer") or []}
    return {"apprentissages": lire("memoire/apprentissages.md"), "gouts": lire("memoire/gouts.md"),
            "performance": lire("memoire/performance.md"), "resume": resume, "historique": hist}


def enregistrer_memoire(nom: str, fichier: str) -> dict:
    if nom not in ("gouts", "apprentissages"):
        raise ErreurStudio("Seuls les goûts et les apprentissages se modifient ici.")
    texte = Path(fichier).read_text(encoding="utf-8")
    config.chemin("memoire", f"{nom}.md").write_text(texte, encoding="utf-8")
    return {"etat": "enregistre"}


def sante() -> dict:
    import shutil
    cfg = config.compte()
    trous = []

    def chercher(obj, chemin=""):
        if isinstance(obj, dict):
            for k, v in obj.items():
                chercher(v, f"{chemin}.{k}" if chemin else str(k))
        elif isinstance(obj, list):
            for v in obj:
                chercher(v, chemin)
        elif isinstance(obj, str) and "[À COMPLÉTER" in obj:
            trous.append(chemin)

    chercher(cfg)
    env = config.secrets()
    heb = (cfg.get("publication") or {}).get("hebergement", "tunnel")
    version = config.chemin("moteur", "VERSION")
    return {
        "version": version.read_text().strip() if version.exists() else "",
        "dossier": str(config.RACINE),
        "a_completer": trous,
        "instagram_connecte": bool(env.get("IG_ACCESS_TOKEN") and env.get("IG_USER_ID")),
        "jeton_expire_le": env.get("IG_TOKEN_EXPIRES") or None,
        "hebergement": heb,
        "hebergement_pret": (config.chemin("outils", "cloudflared").exists() or bool(shutil.which("cloudflared")))
        if heb == "tunnel" else bool(env.get("SUPABASE_URL") and env.get("SUPABASE_SERVICE_KEY")),
        "galeries": len(config.series()),
        "publications": len(config.historique()),
    }


# =========================================================================== tâches planifiées voulues

CRON_JOURS = {"lundi": 1, "mardi": 2, "mercredi": 3, "jeudi": 4, "vendredi": 5, "samedi": 6, "dimanche": 0}


def taches() -> list:
    """Les tâches planifiées que les réglages demandent (Claude les crée ou les met à jour)."""
    r = reglages()
    dossier = str(config.RACINE)
    entete = f"Tu es le Studio Instagram. Le dossier du studio est « {dossier} » : commence par `cd \"{dossier}\"`."
    res = []
    h, m = r["routine"]["heure_idees"].split(":")
    res.append({"taskId": "studio-instagram-matin", "title": "Studio Instagram · idées du matin",
                "cronExpression": f"{int(m)} {int(h)} * * *",
                "description": "Statistiques, apprentissages et idées de post du jour",
                "prompt": entete + " Lance le skill `studio-instagram:studio-matin` et suis-le exactement. Parle en "
                          "français, simplement. Rien n'est publié sans sa validation explicite (dans l'app ou ici)."})
    par_heure = {}
    for jour, heure in r["publication"]["creneaux"].items():
        if heure:
            par_heure.setdefault(heure, []).append(CRON_JOURS[jour])
    for i, (heure, jours) in enumerate(sorted(par_heure.items())):
        h, m = heure.split(":")
        jours_cron = "*" if len(jours) == 7 else ",".join(str(j) for j in sorted(jours))
        suffixe = "" if i == 0 else f"-{i + 1}"
        res.append({"taskId": f"studio-instagram-publication{suffixe}",
                    "title": f"Studio Instagram · publication {heure}",
                    "cronExpression": f"{int(m)} {int(h)} * * {jours_cron}",
                    "description": "Publie les posts validés dont l'heure est venue",
                    "prompt": entete + " Lance le skill `studio-instagram:studio-publication` et suis-le exactement. "
                              "Ne publie que les posts qu'elle a validés."})
    h, m = r["routine"]["heure_bilan"].split(":")
    res.append({"taskId": "studio-instagram-bilan", "title": "Studio Instagram · bilan de la semaine",
                "cronExpression": f"{int(m)} {int(h)} * * {CRON_JOURS.get(r['routine']['jour_bilan'], 0)}",
                "description": "Bilan hebdomadaire et mise à jour des apprentissages",
                "prompt": entete + " Lance le skill `studio-instagram:studio-bilan` et suis-le exactement."})
    return res
