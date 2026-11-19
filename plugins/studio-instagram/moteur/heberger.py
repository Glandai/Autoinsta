"""Hébergement temporaire des fichiers au moment de publier.

L'API Instagram ne reçoit pas les images directement : elle va les chercher à une
adresse publique. On ouvre donc une adresse le temps de la publication (1 à 3 min),
puis on la ferme et on efface. Seuls les fichiers du post approuvé sont exposés,
sous un chemin aléatoire.

- "tunnel"   : cloudflared (Cloudflare Quick Tunnel), aucun compte nécessaire.
- "supabase" : un bucket public Supabase (plus robuste, compte gratuit requis).
"""
import functools
import http.server
import mimetypes
import queue
import re
import secrets
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

import requests

from . import config
from .config import ErreurStudio


class _Discret(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class Hebergeur:
    def __init__(self, simulation: bool = False):
        cfg = config.compte().get("publication") or {}
        self.mode = cfg.get("hebergement", "tunnel")
        self.bucket = cfg.get("bucket_supabase", "instagram-temp")
        self.simulation = simulation
        self.jeton = secrets.token_urlsafe(12)
        self.envoyes = []
        self.base = None

    # ------------------------------------------------------------------ cycle de vie
    def __enter__(self):
        if self.simulation:
            self.base = f"https://exemple.invalid/{self.jeton}"
            return self
        if self.mode == "supabase":
            env = config.secrets()
            self.sb_url, self.sb_cle = env.get("SUPABASE_URL", "").rstrip("/"), env.get("SUPABASE_SERVICE_KEY", "")
            if not (self.sb_url and self.sb_cle):
                raise ErreurStudio("SUPABASE_URL et SUPABASE_SERVICE_KEY manquent dans .env.")
            return self
        self._ouvrir_tunnel()
        return self

    def __exit__(self, *exc):
        if self.simulation:
            return False
        if self.mode == "supabase":
            if self.envoyes:
                try:
                    requests.delete(f"{self.sb_url}/storage/v1/object/{self.bucket}", timeout=30,
                                    headers=self._entetes_sb(), json={"prefixes": self.envoyes})
                except requests.RequestException:
                    pass
            return False
        try:
            if getattr(self, "proc", None):
                self.proc.terminate()
                self.proc.wait(timeout=10)
        except Exception:
            pass
        try:
            self.httpd.shutdown()
        except Exception:
            pass
        shutil.rmtree(getattr(self, "dossier", ""), ignore_errors=True)
        return False

    # ------------------------------------------------------------------ publication d'un fichier
    def url(self, chemin_local) -> str:
        chemin_local = Path(chemin_local)
        nom = f"{secrets.token_hex(6)}{chemin_local.suffix.lower()}"
        if self.simulation:
            return f"{self.base}/{nom}"
        if self.mode == "supabase":
            cle = f"{self.jeton}/{nom}"
            ctype = mimetypes.guess_type(nom)[0] or "application/octet-stream"
            r = requests.post(f"{self.sb_url}/storage/v1/object/{self.bucket}/{cle}", timeout=120,
                              headers={**self._entetes_sb(), "Content-Type": ctype, "x-upsert": "true"},
                              data=chemin_local.read_bytes())
            if r.status_code >= 300:
                raise ErreurStudio(f"Supabase refuse l'envoi ({r.status_code}). Vérifie le bucket « {self.bucket} » (public).")
            self.envoyes.append(cle)
            return f"{self.sb_url}/storage/v1/object/public/{self.bucket}/{cle}"
        cible = Path(self.dossier) / self.jeton / nom
        shutil.copy2(chemin_local, cible)
        url = f"{self.base}/{self.jeton}/{nom}"
        self._attendre_disponible(url)
        return url

    # ------------------------------------------------------------------ interne
    def _entetes_sb(self):
        return {"Authorization": f"Bearer {self.sb_cle}", "apikey": self.sb_cle}

    def _executable(self) -> str:
        local = config.chemin("outils", "cloudflared")
        if local.exists():
            return str(local)
        trouve = shutil.which("cloudflared")
        if trouve:
            return trouve
        raise ErreurStudio("cloudflared est absent : relance l'installation (/studio-instagram:studio-installation), ou passe "
                           "publication.hebergement à « supabase » dans config/compte.yaml.")

    def _ouvrir_tunnel(self):
        self.dossier = tempfile.mkdtemp(prefix="studio-publication-")
        (Path(self.dossier) / self.jeton).mkdir()
        gestionnaire = functools.partial(_Discret, directory=self.dossier)
        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), gestionnaire)
        port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.proc = subprocess.Popen([self._executable(), "tunnel", "--no-autoupdate", "--url",
                                      f"http://127.0.0.1:{port}"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lignes = queue.Queue()

        def lire():
            for ligne in self.proc.stdout:
                lignes.put(ligne)

        threading.Thread(target=lire, daemon=True).start()
        fin = time.time() + 60
        while time.time() < fin:
            try:
                ligne = lignes.get(timeout=1)
            except queue.Empty:
                if self.proc.poll() is not None:
                    break
                continue
            m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", ligne)
            if m:
                self.base = m.group(0)
                break
        if not self.base:
            self.__exit__()
            raise ErreurStudio("Impossible d'ouvrir l'adresse temporaire (cloudflared). Vérifie la connexion internet.")
        sonde = Path(self.dossier) / self.jeton / "sonde.txt"
        sonde.write_text("ok", encoding="utf-8")
        self._attendre_disponible(f"{self.base}/{self.jeton}/sonde.txt", delai=90)

    def _attendre_disponible(self, url: str, delai: int = 45):
        fin = time.time() + delai
        while time.time() < fin:
            try:
                r = requests.get(url, timeout=10)
                if r.status_code == 200:
                    return
            except requests.RequestException:
                pass
            time.sleep(2)
        raise ErreurStudio("L'adresse temporaire ne répond pas : la publication est annulée, rien n'a été posté.")
