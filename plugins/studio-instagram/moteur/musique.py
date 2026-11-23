"""Choisir la musique d'un post, avec un extrait à écouter dans l'app.

Deux sources :
- la bibliothèque musicale d'Instagram (API Audio), quand le compte est connecté par la route Facebook ;
- sinon, et pour les tendances : le classement public « les plus écoutés » d'Apple Music (par pays) et la
  recherche d'iTunes, qui donnent un extrait de 30 secondes. Aucun compte, aucune donnée personnelle envoyée.

Instagram ne permet pas à une app d'ajouter la musique d'un carrousel : la piste choisie est notée dans le post
et rappelée au moment de publier, pour l'ajouter dans l'app Instagram (Modifier › Ajouter de la musique).
"""
import json
import time
import urllib.parse
import urllib.request

from . import config
from .config import ErreurStudio

CLASSEMENT = "https://rss.marketingtools.apple.com/api/v2/{pays}/music/most-played/{n}/songs.json"
RECHERCHE = "https://itunes.apple.com/search?{q}"
DETAILS = "https://itunes.apple.com/lookup?{q}"
DUREE_CACHE = 6 * 3600

# Raccourcis d'ambiance pour un photographe de mariage (recherches iTunes).
HUMEURS = {
    "romantique": "romantic love song",
    "piano": "piano solo calm",
    "acoustique": "acoustic love",
    "cinematique": "cinematic strings",
    "indie": "indie folk",
    "jazz": "jazz standards love",
    "francais": "chanson française amour",
    "joyeux": "feel good summer",
}


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "StudioInstagram/2.3"})
    derniere = None
    for essai in range(2):                     # un second essai : le service répond parfois lentement
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as err:               # réseau absent, service indisponible
            derniere = err
    raise ErreurStudio(f"Musique indisponible pour l'instant ({derniere.__class__.__name__}). Réessaie dans un moment.")


def _pays() -> str:
    c = config.compte() or {}
    langue = str(c.get("langue") or "fr").lower()
    return "fr" if langue.startswith("fr") else "us"


def _piste_itunes(r: dict, source: str) -> dict:
    pochette = str(r.get("artworkUrl100") or "").replace("100x100bb", "300x300bb")
    return {"audio_id": "itunes-" + str(r.get("trackId") or ""), "titre": r.get("trackName"),
            "artiste": r.get("artistName"), "duree_s": round((r.get("trackTimeMillis") or 0) / 1000),
            "apercu_url": r.get("previewUrl"), "pochette": pochette or None,
            "lien": r.get("trackViewUrl"), "source": source}


def _instagram_possible() -> bool:
    c = config.compte() or {}
    env = config.secrets()
    return (c.get("instagram") or {}).get("api", "facebook") == "facebook" and bool(env.get("IG_ACCESS_TOKEN"))


def tendances(n: int = 40) -> list:
    """Les morceaux les plus écoutés en ce moment (Apple Music, pays du compte), avec leur extrait."""
    pays = _pays()
    cache = config.chemin("donnees", f"musique-tendances-{pays}.json")
    memo = config.lire_json(cache, None)
    if memo and time.time() - memo.get("le", 0) < DUREE_CACHE and memo.get("pistes"):
        return memo["pistes"][:n]
    feed = _get(CLASSEMENT.format(pays=pays, n=min(100, max(10, n)))).get("feed") or {}
    ids = [str(x.get("id")) for x in feed.get("results") or [] if x.get("id")]
    if not ids:
        return []
    details = _get(DETAILS.format(q=urllib.parse.urlencode({"id": ",".join(ids), "country": pays, "entity": "song"})))
    par_id = {str(r.get("trackId")): r for r in details.get("results") or [] if r.get("kind") == "song"}
    pistes = [_piste_itunes(par_id[i], "tendances") for i in ids if i in par_id and par_id[i].get("previewUrl")]
    cache.parent.mkdir(parents=True, exist_ok=True)
    config.ecrire_json(cache, {"le": time.time(), "pays": pays, "pistes": pistes})
    return pistes[:n]


def chercher(requete: str, n: int = 30) -> list:
    """Bibliothèque Instagram si le compte y a accès, sinon recherche iTunes (titre, artiste ou ambiance)."""
    requete = (requete or "").strip()
    terme = HUMEURS.get(requete.lower(), requete)
    if not terme:
        return tendances(n)
    res = []
    if _instagram_possible():
        try:
            from .instagram import Instagram
            res = [dict(p, source="instagram") for p in Instagram().chercher_musique(terme, limite=n)]
        except ErreurStudio:
            res = []
    if not res:
        q = urllib.parse.urlencode({"term": terme, "entity": "song", "country": _pays(), "limit": n})
        res = [_piste_itunes(r, "recherche") for r in _get(RECHERCHE.format(q=q)).get("results") or []
               if r.get("previewUrl")]
    return res


def humeurs() -> list:
    return [{"cle": k, "recherche": v} for k, v in HUMEURS.items()]
