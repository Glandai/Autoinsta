"""Chemins, configuration, secrets et petites aides de lecture/écriture.

Tout le studio vit dans un seul dossier (RACINE). Rien n'est écrit ailleurs.
"""
import datetime as dt
import json
import os
import tempfile
from pathlib import Path

import yaml

try:  # Python 3.9+
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

RACINE = Path(__file__).resolve().parent.parent
FUSEAU_DEFAUT = "Europe/Paris"


class ErreurStudio(Exception):
    """Erreur lisible par la photographe (message en français, sans jargon)."""


def chemin(*morceaux) -> Path:
    return RACINE.joinpath(*morceaux)


# --------------------------------------------------------------------------- YAML

def lire_yaml(rel: str) -> dict:
    f = chemin(rel)
    if not f.exists():
        return {}
    with f.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def compte() -> dict:
    return lire_yaml("config/compte.yaml")


def series() -> list:
    return lire_yaml("config/galeries.yaml").get("series") or []


SERIE_DEMO = {
    "id": "demo", "type": "mariage", "lieu": "Domaine de démonstration, Gard, France", "date": "2026-06-14",
    "maries": {"prenoms": "Alice & Paul", "prenoms_publiables": False},
    "notes": "Série fictive générée par ./studio demo pour vérifier l'installation.",
    "prestataires": [{"role": "Fleurs", "nom": "Atelier Démo", "compte": "atelier.demo"},
                     {"role": "Lieu", "nom": "Domaine Démo", "compte": "domaine.demo"}],
    "source": {"type": "dossier", "chemin": "catalogue/demo/originaux"},
    "statut": "demo",
}


def serie(serie_id: str) -> dict:
    for s in series():
        if str(s.get("id")) == str(serie_id):
            return s
    if str(serie_id) == "demo":
        return SERIE_DEMO
    raise ErreurStudio(f"Série « {serie_id} » absente de config/galeries.yaml.")


def chemin_utilisateur(texte: str) -> Path:
    """Chemin saisi dans la config : absolu, ~/…, ou relatif au dossier du studio."""
    p = Path(str(texte)).expanduser()
    return p if p.is_absolute() else RACINE / p


# --------------------------------------------------------------------------- secrets

def secrets() -> dict:
    """Lit .env (jamais affiché). Les variables d'environnement ont priorité."""
    env = {}
    f = chemin(".env")
    if f.exists():
        for ligne in f.read_text(encoding="utf-8").splitlines():
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            k, v = ligne.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    for k in list(env):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def ecrire_secret(cle: str, valeur: str) -> None:
    """Met à jour une ligne de .env sans jamais afficher la valeur."""
    f = chemin(".env")
    lignes = f.read_text(encoding="utf-8").splitlines() if f.exists() else []
    trouve = False
    for i, ligne in enumerate(lignes):
        if ligne.split("=", 1)[0].strip() == cle:
            lignes[i] = f"{cle}={valeur}"
            trouve = True
    if not trouve:
        lignes.append(f"{cle}={valeur}")
    f.write_text("\n".join(lignes) + "\n", encoding="utf-8")
    try:
        os.chmod(f, 0o600)
    except OSError:
        pass


def masquer(valeur) -> str:
    if not valeur:
        return "(vide)"
    v = str(valeur)
    return v[:4] + "…" + v[-3:] if len(v) > 10 else "***"


# --------------------------------------------------------------------------- temps

def fuseau():
    nom = compte().get("fuseau") or FUSEAU_DEFAUT
    return ZoneInfo(nom) if ZoneInfo else None


def maintenant() -> dt.datetime:
    return dt.datetime.now(fuseau())


def aujourdhui() -> str:
    return maintenant().date().isoformat()


JOURS_FR = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
MOIS_FR = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
           "septembre", "octobre", "novembre", "décembre"]


def date_longue(iso: str) -> str:
    d = dt.date.fromisoformat(iso[:10])
    return f"{JOURS_FR[d.weekday()]} {d.day} {MOIS_FR[d.month - 1]}"


# --------------------------------------------------------------------------- JSON

def lire_json(f, defaut=None):
    f = Path(f)
    if not f.exists():
        return defaut
    with f.open(encoding="utf-8") as fh:
        return json.load(fh)


def ecrire_json(f, data) -> None:
    f = Path(f)
    f.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(f.parent), suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, f)


def ajouter_jsonl(f, obj) -> None:
    f = Path(f)
    f.parent.mkdir(parents=True, exist_ok=True)
    with f.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def lire_jsonl(f) -> list:
    f = Path(f)
    if not f.exists():
        return []
    res = []
    for ligne in f.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if ligne:
            try:
                res.append(json.loads(ligne))
            except json.JSONDecodeError:
                continue
    return res


# --------------------------------------------------------------------------- dossiers

def dossier_jour(jour: str) -> Path:
    d = chemin("jours", jour)
    d.mkdir(parents=True, exist_ok=True)
    return d


def dossier_serie(serie_id: str) -> Path:
    d = chemin("catalogue", str(serie_id))
    d.mkdir(parents=True, exist_ok=True)
    return d


def historique() -> list:
    """Publications passées, de la plus ancienne à la plus récente."""
    h = lire_json(chemin("donnees", "historique.json"), []) or []
    return sorted(h, key=lambda p: (p.get("date", ""), p.get("heure", "")))


def enregistrer_historique(h: list) -> None:
    h = sorted(h, key=lambda p: (p.get("date", ""), p.get("heure", "")))
    ecrire_json(chemin("donnees", "historique.json"), h)


def ids_media(m: dict) -> list:
    """Identifiants des photos d'une diapositive : une seule, ou plusieurs pour un module."""
    if isinstance(m.get("photos"), list) and m["photos"]:
        return [str(x) for x in m["photos"]]
    ident = m.get("photo_id") or m.get("fichier")
    return [str(ident)] if ident else []
