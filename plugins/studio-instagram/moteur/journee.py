"""Cycle d'une journée : idées → choix → brouillon → retouches → approbation → publication.

Chaque journée vit dans jours/AAAA-MM-JJ/ :
  idees.json, idees.html, post.json, rendu/, apercu.html, etat.json, publication.json
Les choix et retouches sont aussi journalisés dans donnees/ pour apprendre les goûts.
"""
import datetime as dt

from . import config, regles, sources
from .config import ErreurStudio

STATUTS = ("idees_proposees", "idee_choisie", "brouillon_pret", "approuve", "publie", "reporte",
           "abandonne", "echec")


def etat(jour: str) -> dict:
    return config.lire_json(config.dossier_jour(jour) / "etat.json", None) or {
        "jour": jour, "statut": "nouveau", "journal": []}


def maj(jour: str, statut: str = None, **champs) -> dict:
    e = etat(jour)
    if statut:
        if statut not in STATUTS:
            raise ErreurStudio(f"Statut inconnu : {statut}")
        e["statut"] = statut
        e["journal"].append({"statut": statut, "le": config.maintenant().isoformat(timespec="seconds")})
    e.update(champs)
    config.ecrire_json(config.dossier_jour(jour) / "etat.json", e)
    return e


def enregistrer_idees(jour: str) -> dict:
    data = config.lire_json(config.dossier_jour(jour) / "idees.json")
    if not data or not data.get("idees"):
        raise ErreurStudio("idees.json vide ou absent.")
    erreurs = []
    for i, idee in enumerate(data["idees"], 1):
        for champ in ("titre", "pitch", "format", "pilier", "serie"):
            if not idee.get(champ):
                erreurs.append(f"Idée {i} : champ « {champ} » manquant")
        if idee.get("pilier") and idee["pilier"] not in regles.PILIERS:
            erreurs.append(f"Idée {i} : pilier inconnu {idee['pilier']}")
        if idee.get("format") and idee["format"] not in regles.FORMATS:
            erreurs.append(f"Idée {i} : format inconnu {idee['format']}")
    if erreurs:
        return {"erreurs": erreurs}
    maj(jour, "idees_proposees", nb_idees=len(data["idees"]))
    return {"erreurs": [], "idees": len(data["idees"])}


def enregistrer_choix(jour: str, numero: int = None, libre: str = None) -> dict:
    d = config.dossier_jour(jour)
    data = config.lire_json(d / "idees.json", {}) or {}
    proposees = [{k: i.get(k) for k in ("titre", "pilier", "format", "serie", "type")} for i in data.get("idees", [])]
    if numero:
        if not 1 <= numero <= len(data.get("idees", [])):
            raise ErreurStudio(f"Il n'y a pas d'idée n°{numero}.")
        choix = {"numero": numero, **data["idees"][numero - 1]}
    elif libre:
        choix = {"numero": None, "libre": libre}
    else:
        raise ErreurStudio("Indique un numéro d'idée ou une idée libre.")
    data["choix"] = choix
    config.ecrire_json(d / "idees.json", data)
    config.ajouter_jsonl(config.chemin("donnees", "choix.jsonl"), {
        "jour": jour, "le": config.maintenant().isoformat(timespec="minutes"), "proposees": proposees,
        "choisie": numero or "libre", "texte_libre": libre})
    maj(jour, "idee_choisie", choix={k: choix.get(k) for k in ("numero", "titre", "libre")})
    return choix


def enregistrer_retouche(jour: str, demande: str) -> dict:
    post = config.lire_json(config.dossier_jour(jour) / "post.json", {}) or {}
    config.ajouter_jsonl(config.chemin("donnees", "retouches.jsonl"), {
        "jour": jour, "le": config.maintenant().isoformat(timespec="minutes"), "demande": demande,
        "legende_avant": post.get("legende"),
        "medias_avant": [m.get("photo_id") or m.get("fichier") for m in post.get("medias", [])]})
    e = etat(jour)
    return maj(jour, "brouillon_pret", retouches=int(e.get("retouches", 0)) + 1)


def heure_de_publication(jour: str, quand: str) -> dt.datetime:
    """quand : 'creneau' | 'maintenant' | 'HH:MM'."""
    tz = config.fuseau()
    if quand == "maintenant":
        return config.maintenant()
    if quand == "creneau":
        post = config.lire_json(config.dossier_jour(jour) / "post.json", {}) or {}
        quand = post.get("heure") or regles.creneau(post.get("date", jour)) or "18:30"
    h, m = [int(x) for x in quand.split(":")[:2]]
    post = config.lire_json(config.dossier_jour(jour) / "post.json", {}) or {}
    date = dt.date.fromisoformat(post.get("date") or jour)
    moment = dt.datetime(date.year, date.month, date.day, h, m, tzinfo=tz)
    if moment < config.maintenant():
        moment = config.maintenant()
    return moment


def approuver(jour: str, quand: str = "creneau") -> dict:
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise ErreurStudio("post.json absent.")
    verdict = regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie")))
    if verdict["erreurs"]:
        raise ErreurStudio("Le post a encore des erreurs : " + " ; ".join(verdict["erreurs"][:5]))
    moment = heure_de_publication(jour, quand)
    config.ajouter_jsonl(config.chemin("donnees", "validations.jsonl"), {
        "jour": jour, "le": config.maintenant().isoformat(timespec="minutes"),
        "legende_finale": post.get("legende"), "retouches": etat(jour).get("retouches", 0),
        "pilier": post.get("pilier"), "format": post.get("format")})
    return maj(jour, "approuve", publier_a=moment.isoformat(timespec="minutes"))


def dus() -> list:
    res = []
    racine = config.chemin("jours")
    if not racine.exists():
        return res
    for d in sorted(racine.iterdir()):
        if not d.is_dir() or d.name == "demo":
            continue
        e = config.lire_json(d / "etat.json", {}) or {}
        if e.get("statut") == "approuve" and e.get("publier_a"):
            try:
                moment = dt.datetime.fromisoformat(e["publier_a"])
            except ValueError:
                continue
            if moment <= config.maintenant():
                res.append(d.name)
    return res


def en_attente() -> list:
    """Brouillons prêts mais pas encore validés (pour un rappel)."""
    res = []
    racine = config.chemin("jours")
    if racine.exists():
        for d in sorted(racine.iterdir()):
            e = config.lire_json(d / "etat.json", {}) or {}
            if d.name != "demo" and e.get("statut") in ("idees_proposees", "idee_choisie", "brouillon_pret"):
                res.append({"jour": d.name, "statut": e["statut"]})
    return res
