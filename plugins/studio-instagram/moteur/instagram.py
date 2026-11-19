"""Client de l'API Instagram (Graph API officielle de Meta).

Deux routes possibles (config/compte.yaml → instagram.api) :
- "facebook"  : compte pro relié à une Page Facebook, hôte graph.facebook.com.
                Seule route qui donne accès à l'API Audio (musique Instagram sur les Reels).
- "instagram" : connexion Instagram seule, hôte graph.instagram.com. Plus simple,
                jeton renouvelable automatiquement, mais pas de musique par l'API.
Le jeton n'est jamais affiché : il reste dans .env.
"""
import datetime as dt
import json
import time

import requests

from . import config
from .config import ErreurStudio

CHAMPS_MEDIA = ("id,caption,media_type,media_product_type,timestamp,permalink,media_url,thumbnail_url,"
                "children{media_url,media_type,thumbnail_url}")
METRIQUES = {
    "FEED": ["views", "reach", "saved", "shares", "likes", "comments", "total_interactions", "follows",
             "profile_visits"],
    "REELS": ["views", "reach", "saved", "shares", "likes", "comments", "total_interactions",
              "ig_reels_avg_watch_time"],
}


class ErreurAPI(ErreurStudio):
    def __init__(self, message, code=None, sous_code=None):
        super().__init__(message)
        self.code, self.sous_code = code, sous_code


class Instagram:
    def __init__(self, simulation: bool = False):
        cfg = config.compte().get("instagram") or {}
        env = config.secrets()
        self.mode = cfg.get("api", "facebook")
        self.version = cfg.get("version_api", "v24.0")
        self.hote = "https://graph.facebook.com" if self.mode == "facebook" else "https://graph.instagram.com"
        self.jeton = env.get("IG_ACCESS_TOKEN", "")
        self.ig_id = env.get("IG_USER_ID", "")
        self.simulation = simulation
        self.journal = []
        if simulation and not self.ig_id:
            self.ig_id = "IG_USER_ID"

    # ------------------------------------------------------------------ bas niveau
    def pret(self) -> bool:
        return bool(self.jeton and self.ig_id)

    def _url(self, chemin: str) -> str:
        return chemin if chemin.startswith("http") else f"{self.hote}/{self.version}/{chemin.lstrip('/')}"

    def _appel(self, methode: str, chemin: str, params: dict = None, data: dict = None, jeton=True):
        url = self._url(chemin)
        params, data = dict(params or {}), dict(data or {})
        if self.simulation and methode == "POST":
            self.journal.append({"requete": f"POST {url.split('?')[0]}", "donnees": data})
            if chemin.endswith("media_publish"):
                return {"id": "SIMULATION-MEDIA"}
            return {"id": f"SIMULATION-{len(self.journal)}"}
        if jeton:
            if not self.jeton:
                raise ErreurStudio("Jeton Instagram absent de .env (voir docs/connexion-instagram.md).")
            (params if methode == "GET" else data)["access_token"] = self.jeton
        for essai in range(3):
            try:
                r = requests.request(methode, url, params=params if methode == "GET" else None,
                                     data=data if methode != "GET" else None, timeout=120)
            except requests.RequestException as e:
                if essai == 2:
                    raise ErreurStudio(f"Instagram injoignable : {e.__class__.__name__}")
                time.sleep(4 * (essai + 1))
                continue
            try:
                corps = r.json()
            except ValueError:
                corps = {"texte": r.text[:300]}
            if r.status_code >= 500 and essai < 2:
                time.sleep(5 * (essai + 1))
                continue
            if r.status_code >= 400 or "error" in corps:
                err = corps.get("error") or {}
                msg = err.get("error_user_msg") or err.get("message") or str(corps)[:300]
                raise ErreurAPI(f"Instagram a refusé : {msg}", err.get("code"), err.get("error_subcode"))
            return corps
        raise ErreurStudio("Instagram ne répond pas correctement.")

    def get(self, chemin, **params):
        return self._appel("GET", chemin, params=params)

    def post(self, chemin, **data):
        data = {k: (json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v)
                for k, v in data.items() if v is not None}
        return self._appel("POST", chemin, data=data)

    # ------------------------------------------------------------------ compte
    def profil(self) -> dict:
        return self.get(self.ig_id, fields="username,name,followers_count,media_count")

    def limite_publication(self) -> dict:
        try:
            r = self.get(f"{self.ig_id}/content_publishing_limit", fields="config,quota_usage")
            return (r.get("data") or [{}])[0]
        except ErreurAPI:
            return {}

    # ------------------------------------------------------------------ jeton
    def verifier_jeton(self) -> dict:
        res = {"mode": self.mode, "jeton": config.masquer(self.jeton), "ig_user_id": self.ig_id or "(vide)"}
        if not self.pret():
            res["etat"] = "absent"
            return res
        try:
            p = self.profil()
            res.update({"etat": "valide", "compte": p.get("username"), "abonnes": p.get("followers_count")})
        except ErreurStudio as e:
            res.update({"etat": "invalide", "erreur": str(e)})
            return res
        expire = config.secrets().get("IG_TOKEN_EXPIRES")
        if self.mode == "facebook":
            try:
                d = self.get("debug_token", input_token=self.jeton).get("data", {})
                if d.get("expires_at"):
                    expire = dt.datetime.utcfromtimestamp(d["expires_at"]).date().isoformat()
                elif d.get("expires_at") == 0:
                    expire = "jamais"
                res["permissions"] = d.get("scopes")
            except ErreurStudio:
                pass
        if expire:
            res["expire_le"] = expire
            if expire != "jamais":
                reste = (dt.date.fromisoformat(expire) - dt.date.today()).days
                res["jours_restants"] = reste
        return res

    def rafraichir_jeton(self) -> dict:
        """Route Instagram : prolonge le jeton de 60 jours (à faire au moins tous les 50 jours)."""
        if self.mode != "instagram":
            return {"etat": "non_applicable",
                    "conseil": "Route Facebook : régénère le jeton (docs/connexion-instagram.md) puis ./studio jeton echanger"}
        r = self._appel("GET", "https://graph.instagram.com/refresh_access_token",
                        params={"grant_type": "ig_refresh_token"})
        config.ecrire_secret("IG_ACCESS_TOKEN", r["access_token"])
        fin = (dt.date.today() + dt.timedelta(seconds=int(r.get("expires_in", 5184000)))).isoformat()
        config.ecrire_secret("IG_TOKEN_EXPIRES", fin)
        return {"etat": "renouvele", "expire_le": fin}

    def echanger_jeton(self) -> dict:
        """Prépare le jeton et trouve l'identifiant du compte.

        Route Facebook : jeton court (Explorateur Graph API) → jeton long (60 jours), ou jeton
        d'utilisateur système déjà collé dans IG_ACCESS_TOKEN. Route Instagram : identifiant seulement.
        """
        env = config.secrets()
        if self.mode == "instagram":
            if not self.jeton:
                raise ErreurStudio("Colle le jeton Instagram dans IG_ACCESS_TOKEN (.env), puis recommence.")
            moi = self._appel("GET", "https://graph.instagram.com/me", params={"fields": "user_id,username"})
            config.ecrire_secret("IG_USER_ID", str(moi.get("user_id") or moi.get("id")))
            if not env.get("IG_TOKEN_EXPIRES"):
                config.ecrire_secret("IG_TOKEN_EXPIRES", (dt.date.today() + dt.timedelta(days=60)).isoformat())
            return {"etat": "ok", "compte": moi.get("username"), "route": "instagram"}
        app, secret, court = env.get("FB_APP_ID"), env.get("FB_APP_SECRET"), env.get("FB_SHORT_TOKEN")
        fin = env.get("IG_TOKEN_EXPIRES") or ""
        if court:
            if not (app and secret):
                raise ErreurStudio("Renseigne aussi FB_APP_ID et FB_APP_SECRET dans .env (docs/connexion-instagram.md).")
            r = self._appel("GET", "https://graph.facebook.com/oauth/access_token", jeton=False, params={
                "grant_type": "fb_exchange_token", "client_id": app, "client_secret": secret,
                "fb_exchange_token": court})
            long_jeton = r["access_token"]
            fin = (dt.date.today() + dt.timedelta(seconds=int(r.get("expires_in", 5184000)))).isoformat()
        elif self.jeton:
            long_jeton = self.jeton                 # jeton d'utilisateur système (n'expire pas)
            fin = fin or "jamais"
        else:
            raise ErreurStudio("Colle le jeton de l'Explorateur dans FB_SHORT_TOKEN (.env), puis recommence.")
        self.jeton = long_jeton
        pages = self.get("me/accounts", fields="name,instagram_business_account{id,username}").get("data", [])
        voulu = str(config.compte().get("compte_instagram", "")).lstrip("@").lower()
        choix = None
        for p in pages:
            iba = p.get("instagram_business_account") or {}
            if iba.get("id") and (not voulu or iba.get("username", "").lower() == voulu):
                choix = iba
        if not choix:
            raise ErreurStudio("Aucun compte Instagram professionnel relié aux Pages de ce jeton. "
                               "Relie le compte à la Page Facebook puis recommence.")
        config.ecrire_secret("IG_ACCESS_TOKEN", long_jeton)
        config.ecrire_secret("IG_USER_ID", choix["id"])
        config.ecrire_secret("IG_TOKEN_EXPIRES", fin)
        config.ecrire_secret("FB_SHORT_TOKEN", "")
        return {"etat": "ok", "compte": choix.get("username"), "expire_le": fin, "route": "facebook"}

    # ------------------------------------------------------------------ publication
    def conteneur_image(self, image_url, alt=None, tags=None, carrousel=False, legende=None,
                        collaborateurs=None, location_id=None) -> str:
        data = {"image_url": image_url}
        if carrousel:
            data["is_carousel_item"] = "true"
        else:
            data.update({"caption": legende, "collaborators": collaborateurs or None, "location_id": location_id})
        if alt:
            data["alt_text"] = alt
        if tags:
            data["user_tags"] = tags
        return self.post(f"{self.ig_id}/media", **data)["id"]

    def conteneur_carrousel(self, enfants, legende, collaborateurs=None, location_id=None) -> str:
        return self.post(f"{self.ig_id}/media", media_type="CAROUSEL", children=",".join(enfants),
                         caption=legende, collaborators=collaborateurs or None, location_id=location_id)["id"]

    def conteneur_reel(self, video_url, legende, cover_url=None, thumb_offset=None, collaborateurs=None,
                       location_id=None, audio=None, nom_audio=None) -> str:
        data = {"media_type": "REELS", "video_url": video_url, "caption": legende, "share_to_feed": "true",
                "cover_url": cover_url, "thumb_offset": thumb_offset, "collaborators": collaborateurs or None,
                "location_id": location_id, "audio_name": nom_audio}
        if audio and self.mode == "facebook":
            data["audio_configuration"] = audio
        return self.post(f"{self.ig_id}/media", **data)["id"]

    def attendre(self, conteneur: str, delai_max: int = 600) -> str:
        if self.simulation:
            return "FINISHED"
        debut, pause = time.time(), 4
        while time.time() - debut < delai_max:
            st = self.get(conteneur, fields="status_code,status")
            code = st.get("status_code")
            if code in ("FINISHED", "PUBLISHED"):
                return code
            if code in ("ERROR", "EXPIRED"):
                raise ErreurStudio(f"Instagram n'a pas pu traiter le média : {st.get('status') or code}")
            time.sleep(pause)
            pause = min(pause * 1.5, 30)
        raise ErreurStudio("Instagram met trop de temps à traiter le média (plus de 10 minutes).")

    def publier(self, conteneur: str) -> str:
        return self.post(f"{self.ig_id}/media_publish", creation_id=conteneur)["id"]

    def media(self, media_id: str) -> dict:
        if self.simulation:
            return {"id": media_id, "permalink": "https://www.instagram.com/p/SIMULATION/"}
        return self.get(media_id, fields="id,permalink,timestamp,media_type,media_product_type,thumbnail_url,media_url")

    def lister_medias(self, limite: int = 30) -> list:
        res, page = [], self.get(f"{self.ig_id}/media", fields=CHAMPS_MEDIA, limit=min(limite, 50))
        while True:
            res.extend(page.get("data", []))
            suivant = (page.get("paging") or {}).get("next")
            if len(res) >= limite or not suivant:
                break
            page = self._appel("GET", suivant, jeton=False)
        return res[:limite]

    # ------------------------------------------------------------------ statistiques
    def statistiques(self, media_id: str, produit: str = "FEED") -> dict:
        metriques = METRIQUES.get("REELS" if produit == "REELS" else "FEED")

        def lire(liste):
            r = self.get(f"{media_id}/insights", metric=",".join(liste))
            out = {}
            for m in r.get("data", []):
                v = (m.get("values") or [{}])[0].get("value")
                if v is None:
                    v = (m.get("total_value") or {}).get("value")
                out[m.get("name")] = v
            return out

        try:
            return lire(metriques)
        except ErreurAPI:
            out = {}
            for m in metriques:          # une métrique refusée ne doit pas tout bloquer
                try:
                    out.update(lire([m]))
                except ErreurAPI:
                    continue
            return out

    # ------------------------------------------------------------------ musique (API Audio)
    def chercher_musique(self, requete: str = None, limite: int = 8) -> list:
        if self.mode != "facebook":
            raise ErreurStudio("La recherche de musique Instagram demande la route Facebook (instagram.api: facebook).")
        params = {"audio_type": "music", "user_id": self.ig_id}
        if requete:
            params["search_query"] = requete
        r = self.get("ig_audio", **params)
        res = []
        for a in (r.get("data") or [])[:limite]:
            res.append({"audio_id": a.get("audio_id") or a.get("id"), "titre": a.get("title"),
                        "artiste": a.get("display_artist"),
                        "duree_s": round((a.get("duration_in_ms") or 0) / 1000),
                        "apercu_url": a.get("download_url"),
                        "lien_instagram": a.get("on_platform_audio_preview_link"),
                        "pochette": a.get("cover_artwork_thumbnail_uri") or a.get("cover_artwork_thumbnail_url")})
        return res
