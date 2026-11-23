"""Pont entre le studio et Claude Code : trouver Claude, s'y connecter, le faire travailler sans fenêtre.

L'app Studio Instagram (et la planification du Mac) lancent Claude Code en mode « print » :

    claude -p --output-format stream-json --verbose --plugin-dir <studio>/.plugin …

Le moteur lit son flux d'événements et écrit l'avancement, lisible par l'app, dans .ui/claude/<id>.json.
Contrats : app/ARCHITECTURE.md §4.1.
"""
import datetime as dt
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

from . import config
from .config import ErreurStudio

TACHES = {
    "matin": "Claude prépare les idées du jour",
    "creation": "Claude prépare ton post",
    "retouche": "Claude retouche ton post",
    "galerie": "Claude analyse la galerie",
    "bilan": "Claude fait le bilan de la semaine",
    "demande": "Claude s'occupe de ta demande",
    "charte": "Claude adapte ta charte à ton activité",
    "idees": "Claude cherche de nouvelles idées",
}
TACHES_DU_JOUR = ("matin", "creation", "retouche")
CHEMINS_PATH = ("~/.local/bin", "~/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                "/usr/bin", "/bin", "/usr/sbin", "/sbin")
APP_CLAUDE = "~/Library/Application Support/Claude/claude-code/*/*/claude.app/Contents/MacOS/claude"
OUTILS = ("Bash(./studio:*)", "Bash(bash app/construire.sh:*)", "Read", "Write", "Edit", "Glob", "Grep")
GARDER = 60                      # exécutions conservées dans .ui/claude
JOUR = re.compile(r"^[0-9A-Za-z_-]{1,40}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

MODE_APP = (
    "Tu es lancé par l'app Mac Studio Instagram, sans personne devant la conversation (mode app autonome). "
    "Règles de ce mode : n'utilise ni AskUserQuestion, ni SendUserFile, ni PushNotification, ni TaskStop, "
    "ni aucune commande en arrière-plan ; ne lance pas installer.sh (l'app gère les mises à jour) ; ne lance "
    "jamais « ./studio ui … --attendre ». Le dossier courant est déjà le studio : lance directement "
    "« ./studio … », sans cd. Pour lire ou chercher des fichiers, utilise Read, Glob et Grep (les commandes "
    "Bash autres que ./studio sont refusées). Pour montrer un écran à la photographe : "
    "« ./studio ui <écran> --jour <jour> », puis termine. Elle décide dans l'app, qui te relancera avec sa "
    "décision ; rien n'est publié sans son clic. Termine par un résumé de deux phrases au plus, en français "
    "simple, sans jargon ni chemin de fichier : il s'affiche dans l'app."
)

CONSEIL_ABSENT = ("Claude Code n'est pas installé sur ce Mac. Clique sur « Installer Claude Code » : "
                  "c'est gratuit et prend une minute.")
CONSEIL_CONNEXION = ("Claude Code est installé mais pas connecté. Clique sur « Se connecter » : la page de "
                     "connexion d'Anthropic s'ouvre dans ton navigateur.")


# =========================================================================== outils

def _maintenant() -> str:
    return config.maintenant().isoformat(timespec="seconds")


def _dossier() -> Path:
    d = config.chemin(".ui", "claude")
    d.mkdir(parents=True, exist_ok=True)
    return d


def _logs() -> Path:
    d = config.chemin(".ui", "logs")
    d.mkdir(parents=True, exist_ok=True)
    return d


def _path_augmente() -> str:
    vus, morceaux = set(), []
    for d in [os.path.expanduser(x) for x in CHEMINS_PATH] + os.environ.get("PATH", "").split(os.pathsep):
        if d and d not in vus:
            vus.add(d)
            morceaux.append(d)
    return os.pathsep.join(morceaux)


def environnement() -> dict:
    """L'environnement de Claude : celui de l'utilisateur, sans les variables d'une éventuelle session
    Claude parente (elles feraient croire au binaire qu'il tourne dans une autre session)."""
    env = {k: v for k, v in os.environ.items()
           if not k.upper().startswith("CLAUDE") and k != "ANTHROPIC_BASE_URL"}
    env["PATH"] = _path_augmente()
    env["STUDIO_APP"] = "1"
    env.setdefault("HOME", str(Path.home()))
    return env


def _vivant(pid) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def _reglages() -> dict:
    return (config.compte() or {}).get("claude") or {}


def _version_dossier(p: str):
    m = re.search(r"claude-code/(\d+(?:\.\d+)*)/", p)
    return tuple(int(x) for x in m.group(1).split(".")) if m else ()


# =========================================================================== trouver et connecter

def trouver():
    """(chemin, source) du binaire Claude Code, ou (None, None)."""
    reglage = str(_reglages().get("chemin") or "").strip()
    if reglage:
        p = os.path.expanduser(reglage)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p, "reglage"
    p = shutil.which("claude", path=_path_augmente())
    if p:
        return p, "path"
    for c in sorted(glob.glob(os.path.expanduser(APP_CLAUDE)), key=_version_dossier, reverse=True):
        if os.access(c, os.X_OK):
            return c, "app_claude"
    return None, None


def _executer(cmd, delai=30):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=delai, env=environnement(),
                              cwd=str(config.RACINE), stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return None


def _version(binaire):
    r = _executer([binaire, "--version"], 20)
    if not r or r.returncode != 0:
        return None
    m = re.search(r"\d+(?:\.\d+)+", r.stdout or "")
    return m.group(0) if m else None


def _auth(binaire) -> dict:
    r = _executer([binaire, "auth", "status", "--json"], 30)
    if not r:
        return {}
    try:
        d = json.loads(r.stdout or "{}")
        return d if isinstance(d, dict) else {}
    except ValueError:
        return {}


def _methode(a: dict) -> str:
    if not a.get("loggedIn"):
        return "aucune"
    m = str(a.get("authMethod") or "").lower()
    if "console" in m:
        return "console"
    if "api" in m and "key" in m.replace("_", ""):
        return "cle_api"
    return "claude.ai"


def _execution_active():
    v = config.lire_json(_dossier() / "verrou", None)
    if not isinstance(v, dict):
        return None
    pid = v.get("pid")
    if pid and _vivant(pid):
        return v
    if not pid:                                   # verrou pris par « lancer », exécution pas encore démarrée
        try:
            age = time.time() - (_dossier() / "verrou").stat().st_mtime
        except OSError:
            return None
        if age < 90:
            return v
    return None


def statut() -> dict:
    binaire, source = trouver()
    plugin = config.chemin(".plugin", ".claude-plugin", "plugin.json").exists()
    actif = _execution_active()
    base = {"plugin_present": plugin, "en_cours": actif.get("id") if actif else None}
    if not binaire:
        return {"installe": False, "chemin": None, "source": None, "version": None, "connecte": False,
                "methode": "aucune", "conseil": CONSEIL_ABSENT, **base}
    a = _auth(binaire)
    connecte = bool(a.get("loggedIn"))
    conseil = None
    if not connecte:
        conseil = CONSEIL_CONNEXION
    elif not plugin:
        conseil = "Le studio n'a pas sa copie du plugin : relance l'installation du studio."
    return {"installe": True, "chemin": binaire, "source": source, "version": _version(binaire),
            "connecte": connecte, "methode": _methode(a), "conseil": conseil, **base}


def installer() -> dict:
    """Installe Claude Code (version autonome, mise à jour automatique) : seulement sur un clic de la photographe."""
    binaire, source = trouver()
    if binaire:
        return {"etat": "deja_installe", "chemin": binaire, "journal": None}
    journal = _logs() / "installation-claude.log"
    cmd = ["/bin/bash", "-c", "curl -fsSL https://claude.ai/install.sh | bash"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900, env=environnement(),
                           cwd=str(Path.home()), stdin=subprocess.DEVNULL)
        texte, code = (r.stdout or "") + (r.stderr or ""), r.returncode
    except (OSError, subprocess.SubprocessError) as e:
        texte, code = str(e), 1
    journal.write_text(texte, encoding="utf-8")
    fin = "\n".join(texte.strip().splitlines()[-6:])
    binaire, _ = trouver()
    if binaire:
        return {"etat": "installe", "chemin": binaire, "journal": fin}
    return {"etat": "echec", "chemin": None, "journal": fin,
            "conseil": "L'installation n'a pas abouti (connexion Internet ?). Réessaie, ou installe Claude Code "
                       "depuis claude.com/product/claude-code."} if code else \
        {"etat": "echec", "chemin": None, "journal": fin, "conseil": "Claude Code reste introuvable après l'installation."}


def connecter(console: bool = False) -> dict:
    """Ouvre la page de connexion d'Anthropic dans le navigateur (le mot de passe ne passe jamais par ici)."""
    binaire, _ = trouver()
    if not binaire:
        return {"etat": "absent", "url": None, "conseil": CONSEIL_ABSENT}
    if _auth(binaire).get("loggedIn"):
        return {"etat": "deja_connecte", "url": None, "conseil": None}
    _arreter_connexion()
    journal = _logs() / "connexion-claude.log"
    cmd = [binaire, "auth", "login", "--console" if console else "--claudeai"]
    # La page de connexion affiche un code à recopier : Claude Code l'attend sur son entrée standard.
    # Une file nommée (FIFO) la relie à « ./studio claude code <code> », que l'app appelle quand la
    # photographe colle le code. Ouverte en lecture et écriture, elle ne se ferme jamais d'elle-même.
    fifo = _dossier() / "connexion.fifo"
    os.mkfifo(str(fifo), 0o600)
    fd = os.open(str(fifo), os.O_RDWR)
    try:
        with open(journal, "w", encoding="utf-8") as fh:
            p = subprocess.Popen(cmd, stdin=fd, stdout=fh, stderr=subprocess.STDOUT,
                                 env=environnement(), cwd=str(config.RACINE), start_new_session=True)
    finally:
        os.close(fd)
    config.ecrire_json(_dossier() / "connexion.json", {"pid": p.pid, "le": _maintenant()})
    url = None
    for _ in range(40):
        time.sleep(0.25)
        texte = journal.read_text(encoding="utf-8", errors="replace") if journal.exists() else ""
        m = re.search(r"https://[^\s\"'<>]+", texte)
        if m:
            url = m.group(0).rstrip(").,;")
        if p.poll() is not None or url:
            break
    if p.poll() is not None and p.returncode:
        texte = journal.read_text(encoding="utf-8", errors="replace") if journal.exists() else ""
        if re.search(r"tty|raw mode|interactive|stdin", texte, re.I):
            return _connecter_terminal(binaire, console)
        return {"etat": "echec", "url": url,
                "conseil": "La connexion n'a pas pu démarrer : " + _resume_texte(texte)}
    return {"etat": "navigateur_ouvert", "url": url, "code_attendu": True,
            "conseil": "Connecte-toi dans la page qui vient de s'ouvrir dans ton navigateur. Elle affiche ensuite "
                       "un code : copie-le et colle-le dans le Studio."}


def _arreter_connexion() -> None:
    c = config.lire_json(_dossier() / "connexion.json", None)
    if isinstance(c, dict) and c.get("pid") and _vivant(c["pid"]):
        _tuer(c["pid"])
    try:
        (_dossier() / "connexion.fifo").unlink()
    except FileNotFoundError:
        pass


def envoyer_code(code: str) -> dict:
    """Transmet à Claude Code le code affiché par la page de connexion, puis attend la connexion."""
    code = "".join(str(code or "").split())
    if not code or len(code) > 600 or not re.match(r"^[A-Za-z0-9#_.~+/=-]+$", code):
        return {"etat": "refuse", "conseil": "Ce code ne ressemble pas à celui de la page de connexion : recopie-le en entier."}
    c = config.lire_json(_dossier() / "connexion.json", None)
    fifo = _dossier() / "connexion.fifo"
    if not (isinstance(c, dict) and _vivant(c.get("pid")) and fifo.exists()):
        return {"etat": "expire", "conseil": "La connexion a expiré : clique de nouveau sur « Se connecter »."}
    fd = os.open(str(fifo), os.O_WRONLY | os.O_NONBLOCK)
    try:
        os.write(fd, (code + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    binaire, _ = trouver()
    for _ in range(40):
        time.sleep(0.5)
        if binaire and _auth(binaire).get("loggedIn"):
            _arreter_connexion()
            return {"etat": "connecte", "conseil": None}
        if not _vivant(c["pid"]):
            break
    texte = (_logs() / "connexion-claude.log").read_text(encoding="utf-8", errors="replace")
    if binaire and _auth(binaire).get("loggedIn"):
        _arreter_connexion()
        return {"etat": "connecte", "conseil": None}
    expire = re.search(r"expired|expiré", texte, re.I)
    return {"etat": "echec", "conseil": ("Ce code a expiré" if expire else "Le code n'a pas été accepté")
            + ". Clique de nouveau sur « Se connecter », puis recopie en entier le nouveau code affiché."}


def _connecter_terminal(binaire, console) -> dict:
    """Repli : la connexion demande un vrai terminal. On ouvre Terminal avec la seule commande utile."""
    f = _dossier() / "connexion.command"
    option = "--console" if console else "--claudeai"
    f.write_text("#!/bin/bash\nclear\necho 'Connexion de Claude pour le Studio Instagram'\n"
                 + json.dumps(binaire) + " auth login " + option
                 + "\necho\necho 'C’est fait : tu peux fermer cette fenêtre et revenir dans le Studio.'\n",
                 encoding="utf-8")
    f.chmod(0o700)
    subprocess.run(["open", str(f)], check=False, capture_output=True)
    return {"etat": "terminal_ouvert", "url": None,
            "conseil": "Une petite fenêtre Terminal s'est ouverte : suis ses indications (le navigateur s'ouvre), "
                       "puis reviens ici."}


def deconnecter() -> dict:
    binaire, _ = trouver()
    if not binaire:
        return {"etat": "absent"}
    r = _executer([binaire, "auth", "logout"], 30)
    return {"etat": "deconnecte" if r and r.returncode == 0 else "echec"}


# =========================================================================== exécutions

def _fichier(ident: str) -> Path:
    if not re.match(r"^[0-9A-Za-z_-]{1,80}$", str(ident or "")):
        raise ErreurStudio("Identifiant d'exécution invalide.")
    return _dossier() / (ident + ".json")


def _ecrire(e: dict) -> None:
    config.ecrire_json(_fichier(e["id"]), e)


def _prendre_verrou(ident: str) -> bool:
    f = _dossier() / "verrou"
    for _ in range(2):
        try:
            fd = os.open(str(f), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            if _execution_active():
                return False
            try:
                f.unlink()                         # verrou abandonné (exécution morte)
            except FileNotFoundError:
                pass
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"id": ident, "pid": None, "le": _maintenant()}, fh)
        return True
    return False


def _rendre_verrou(ident: str) -> None:
    f = _dossier() / "verrou"
    v = config.lire_json(f, None)
    if isinstance(v, dict) and v.get("id") == ident:
        try:
            f.unlink()
        except FileNotFoundError:
            pass


def _menage() -> None:
    fichiers = sorted(p for p in _dossier().glob("*.json")
                      if p.stem not in ("actuel", "connexion", "conversation", "verrou"))
    for p in fichiers[:-GARDER]:
        for q in (p, p.with_suffix(".jsonl"), p.with_suffix(".annuler")):
            try:
                q.unlink()
            except FileNotFoundError:
                pass


def lancer(tache: str, jour: str = None, serie: str = None, consigne: str = None,
           attendre: bool = False, auto: bool = False) -> dict:
    if tache not in TACHES:
        raise ErreurStudio("Tâche inconnue : " + str(tache) + " (" + ", ".join(TACHES) + ")")
    jour = jour or config.aujourdhui()
    if not JOUR.match(jour):
        raise ErreurStudio("Jour invalide : " + str(jour))
    if tache == "galerie" and not (serie or "").strip():
        raise ErreurStudio("Indique la galerie à analyser.")
    if tache in ("retouche", "demande") and not (consigne or "").strip():
        raise ErreurStudio("Écris ta demande avant de l'envoyer à Claude.")
    binaire, _ = trouver()
    if not binaire:
        return {"etat": "absent", "conseil": CONSEIL_ABSENT}
    if not _auth(binaire).get("loggedIn"):
        return {"etat": "non_connecte", "conseil": CONSEIL_CONNEXION}
    if not config.chemin(".plugin", ".claude-plugin", "plugin.json").exists():
        return {"etat": "absent", "conseil": "Le studio n'a pas sa copie du plugin : relance l'installation du studio."}
    ident = config.maintenant().strftime("%Y%m%d-%H%M%S") + "-" + tache
    if not _prendre_verrou(ident):
        actif = _execution_active() or {}
        return {"etat": "deja_en_cours", "id": actif.get("id")}
    e = {"id": ident, "tache": tache, "jour": jour, "serie": (serie or "").strip() or None,
         "consigne": (consigne or "").strip() or None, "auto": bool(auto), "titre": TACHES[tache],
         "etat": "en_attente", "cree_le": _maintenant(), "debut": None, "fin": None, "duree_s": 0,
         "etapes": [], "message": None, "resultat": None, "erreur": None, "ecran_suivant": None,
         "session": None, "cout_usd": None}
    _ecrire(e)
    config.ecrire_json(_dossier() / "actuel.json", {"id": ident})
    _menage()
    if attendre:
        return executer(ident)
    journal = open(_logs() / ("claude-" + ident + ".log"), "w", encoding="utf-8")
    try:
        subprocess.Popen([sys.executable, "-m", "moteur", "claude", "executer", ident], cwd=str(config.RACINE),
                         stdin=subprocess.DEVNULL, stdout=journal, stderr=subprocess.STDOUT,
                         start_new_session=True)
    except OSError as err:
        _rendre_verrou(ident)
        e.update(etat="erreur", erreur="Claude n'a pas pu démarrer : " + str(err), fin=_maintenant())
        _ecrire(e)
        return {"etat": "erreur", "id": ident, "conseil": e["erreur"]}
    finally:
        journal.close()
    return {"etat": "lance", "id": ident}


# --------------------------------------------------------------------------- texte de la demande

def _prompt(e: dict) -> str:
    t, j = e["tache"], e["jour"]
    if t == "matin":
        return "/studio-instagram:studio-matin\n\nJour : " + j + "."
    if t == "creation":
        serie = ""
        if e.get("serie"):
            serie = (" Utilise les photos de la série « " + e["serie"] + " » (choisies par la photographe pour ce "
                     "post, à la place de la série de l'idée). Si elles ne sont pas encore analysées, fais d'abord "
                     "l'analyse visuelle (./studio planches, regarde les planches, ./studio noter), puis construis.")
        return ("/studio-instagram:studio-creation\n\nJour : " + j + ". L'idée choisie par la photographe est "
                "enregistrée dans jours/" + j + "/idees.json (champ « choix »)." + serie + " Construis le post "
                "complet, contrôle-le et fabrique l'aperçu.")
    if t == "retouche":
        return ("/studio-instagram:studio-creation\n\nJour : " + j + ". Retouche demandée par la photographe sur "
                "le post du jour : « " + e["consigne"] + " ». Applique exactement cette demande sans tout refaire "
                "(retouche relancée par l'app), puis refais le contrôle et l'aperçu.")
    if t == "galerie":
        return ("/studio-instagram:studio-galerie\n\nLa galerie « " + e["serie"] + " » est déjà enregistrée dans "
                "config/galeries.yaml : passe directement à l'indexation et à l'analyse visuelle.")
    if t == "bilan":
        return "/studio-instagram:studio-bilan"
    if t == "idees":
        return ("/studio-instagram:studio-matin\n\nJour : " + j + ". La photographe veut de NOUVELLES idées depuis "
                "le bouton « + » de l'app : saute les étapes 1 et 2 (vérifications, statistiques), garde l'étape 3 "
                "si une galerie attend son analyse, puis propose 3 idées vraiment différentes de celles déjà dans "
                "jours/" + j + "/idees.json (s'il existe), écris-les à la place des anciennes et lance "
                "« ./studio idees " + j + " ». " + (("Consigne de la photographe : « " + e["consigne"] + " ». ")
                                                     if e.get("consigne") else "") + "Termine sans lancer la création.")
    if t == "charte":
        return ("Adapte la charte du studio (config/charte.md) au compte décrit dans config/compte.yaml : "
                "activité (champ activite), nom, compte, localisation, voix, langue et approche. La charte d'origine "
                "est écrite pour une photographe de mariage : réécris ce qui en dépend (rôle, identité, piliers "
                "racontés, vocabulaire, exemples, interdits propres au mariage) pour cette activité, avec le même "
                "niveau d'exigence. Garde intacts la structure numérotée, les règles de sécurité et de vérité "
                "(rien d'inventé, aucune validation implicite, photos non modifiées), les codes de piliers "
                "(EDITORIAL, DOCUMENTARY, DETAILS, PLACES, PORTRAITS, LOVE_STORY, ATMOSPHERE, ARTISTIC_VISION : "
                "redéfinis seulement leur sens si besoin), les valeurs codées et les formats JSON du point 11, que "
                "le moteur contrôle. N'invente aucun fait sur la personne : ce qui manque reste général. Écris le "
                "résultat dans config/charte.md, puis vérifie avec « ./studio app charte ».")
    return (e["consigne"] + "\n\n(Demande écrite par la photographe dans le panneau « Demander à Claude » de "
            "l'app, le " + j + ". Si elle concerne l'apparence ou le fonctionnement de l'app, suis le skill "
            "studio-instagram:studio-app.)")


def _session(e: dict, nouvelle: bool = False):
    """(uuid, reprise) : les tâches d'une même journée partagent une conversation."""
    if e["tache"] in TACHES_DU_JOUR:
        f = config.dossier_jour(e["jour"]) / "claude.json"
    elif e["tache"] == "demande":
        f = _dossier() / "conversation.json"
    else:
        return str(uuid.uuid4()), False
    d = config.lire_json(f, {}) or {}
    s = str(d.get("session") or "")
    if s and UUID.match(s) and not nouvelle:
        return s, True
    s = str(uuid.uuid4())
    config.ecrire_json(f, {"session": s, "cree_le": _maintenant()})
    return s, False


def nouvelle_conversation() -> dict:
    try:
        (_dossier() / "conversation.json").unlink()
    except FileNotFoundError:
        pass
    return {"etat": "nouvelle"}


# --------------------------------------------------------------------------- étapes lisibles

ETAPES_STUDIO = {
    "verifier": ("Je vérifie que tout est en place", "checkmark.shield"),
    "releve": ("Je relève les statistiques Instagram", "chart.line.uptrend.xyaxis"),
    "analyse": ("J'analyse ce qui a fonctionné", "chart.bar.xaxis"),
    "jeton": ("Je vérifie la connexion à Instagram", "key"),
    "pictime etat": ("Je regarde où en sont les galeries", "photo.stack"),
    "pictime indexer": ("Je lis la galerie", "photo.stack"),
    "pictime telecharger": ("Je récupère les photos en haute définition", "arrow.down.circle"),
    "pictime analyser-lien": ("Je vérifie le lien de la galerie", "link"),
    "planches": ("Je prépare les planches contact", "square.grid.3x3"),
    "noter": ("J'enregistre mon analyse des photos", "star"),
    "etat": ("Je regarde l'équilibre du feed", "square.grid.3x2"),
    "candidats": ("Je cherche les meilleures photos", "sparkle.magnifyingglass"),
    "idees": ("J'enregistre les idées du jour", "lightbulb"),
    "choix": ("J'enregistre ton choix", "hand.tap"),
    "rendre": ("Je mets les images en page", "rectangle.portrait.on.rectangle.portrait"),
    "valider": ("Je vérifie le post : règles, légende, crédits", "checkmark.seal"),
    "apercu": ("Je prépare l'aperçu", "iphone"),
    "retouche": ("Je note ta retouche", "pencil"),
    "musique": ("Je cherche une musique", "music.note"),
    "reel": ("Je monte le Reel", "film"),
    "ui": ("J'ouvre le bon écran dans l'app", "macwindow"),
    "app": ("Je mets l'app à jour", "macwindow"),
    "historique": ("Je relis l'historique du compte", "clock.arrow.circlepath"),
    "en-attente": ("Je regarde les posts en attente", "tray"),
    "statut": ("Je mets à jour le statut du jour", "flag"),
}


def _decrire(nom: str, entree: dict):
    """(texte, icône, clé de regroupement) pour un appel d'outil, ou None s'il ne mérite pas d'étape."""
    nom = str(nom or "")
    if nom == "Bash":
        cmd = str(entree.get("command") or "").strip()
        m = re.search(r"(?:^|&&\s*|;\s*)\./studio\s+([a-z-]+)(?:\s+([a-z-]+))?", cmd)
        if m:
            sous, sous2 = m.group(1), m.group(2) or ""
            texte, icone = ETAPES_STUDIO.get(sous + " " + sous2) or ETAPES_STUDIO.get(sous) \
                or ("Je travaille dans le studio", "gearshape")
            return texte, icone, "studio:" + texte
        if "construire.sh" in cmd:
            return "Je reconstruis l'app", "hammer", "construire"
        return "Je travaille dans le studio", "gearshape", "bash"
    chemin = str(entree.get("file_path") or entree.get("path") or "").replace("\\", "/")
    bas = chemin.lower()
    if nom == "Read":
        if bas.endswith((".jpg", ".jpeg", ".png", ".heic", ".webp")):
            return "Je regarde les photos", "eye", "photos"
        if bas.endswith(("config/charte.md", "directeur-artistique.md")):
            return "Je relis ta charte", "text.book.closed", "lire:charte"
        if "/memoire/" in bas or bas.startswith("memoire/"):
            return "Je relis ce que j'ai appris de tes goûts", "brain", "lire:memoire"
        if bas.endswith("galeries.yaml"):
            return "Je relis la fiche de la galerie", "photo.on.rectangle", "lire:galeries"
        if bas.endswith("compte.yaml"):
            return "Je relis les réglages du compte", "slider.horizontal.3", "lire:compte"
        if bas.endswith("idees.json"):
            return "Je relis les idées", "lightbulb", "lire:idees"
        if bas.endswith("post.json"):
            return "Je relis le post", "doc.text", "lire:post"
        if bas.endswith("skill.md"):
            return "J'ouvre la méthode du studio", "book", "lire:methode"
        return "Je consulte le studio", "doc", "lire"
    if nom in ("Write", "Edit", "MultiEdit"):
        if bas.endswith("idees.json"):
            return "J'écris les idées", "lightbulb", "ecrire:idees"
        if bas.endswith("post.json"):
            return "J'écris le post : ordre, légende, crédits", "square.and.pencil", "ecrire:post"
        if bas.endswith("notes.json"):
            return "Je note les photos", "star.leadinghalf.filled", "ecrire:notes"
        if bas.endswith("app.yaml"):
            return "Je change l'apparence de l'app", "paintpalette", "ecrire:apparence"
        if "/app/" in bas or bas.startswith("app/"):
            return "Je modifie l'app", "hammer", "ecrire:app"
        if bas.endswith("gouts.md"):
            return "Je retiens tes goûts", "heart", "ecrire:gouts"
        if bas.endswith("apprentissages.md"):
            return "Je mets à jour les apprentissages", "brain.head.profile", "ecrire:apprentissages"
        if "/config/" in bas or bas.startswith("config/"):
            return "Je mets à jour les réglages", "slider.horizontal.3", "ecrire:config"
        return "J'écris dans le studio", "square.and.pencil", "ecrire"
    if nom == "Skill":
        return "J'ouvre la méthode du studio", "book", "lire:methode"
    if nom in ("Glob", "Grep"):
        return "Je cherche dans le studio", "magnifyingglass", "chercher"
    return None


def _phrase(texte, longueur: int = 160):
    t = " ".join(str(texte or "").split())
    t = re.sub(r"[*_`#>]+", "", t).strip()
    if not t:
        return None
    m = re.match(r"(.+?[.!?…])(\s|$)", t)
    if m and len(m.group(1)) >= 12:
        t = m.group(1)
    return t if len(t) <= longueur else t[:longueur - 1].rstrip() + "…"


class Lecteur:
    """Transforme le flux stream-json de Claude en avancement lisible (étapes, message, résultat)."""

    def __init__(self, e: dict):
        self.e = e
        self.init = False
        self.resultat = None
        self.refus = 0

    def _etape(self, texte, icone, cle):
        etapes = self.e["etapes"]
        if etapes and etapes[-1].get("cle") == cle:
            d = etapes[-1]
            d["n"] = int(d.get("n") or 1) + 1
            if cle == "photos":
                d["texte"] = "Je regarde les photos (" + str(d["n"]) + ")"
            return
        for d in etapes:
            d["fait"] = True
        etapes.append({"le": _maintenant(), "texte": texte, "icone": icone, "fait": False, "cle": cle, "n": 1})
        del etapes[:-40]

    def traiter(self, evt: dict) -> bool:
        typ = evt.get("type")
        if typ == "system" and evt.get("subtype") == "init":
            self.init = True
            self.e["session"] = evt.get("session_id") or self.e.get("session")
            self.e["modele"] = evt.get("model")
            return True
        if typ == "assistant":
            change = False
            for bloc in (evt.get("message") or {}).get("content") or []:
                if not isinstance(bloc, dict):
                    continue
                if bloc.get("type") == "text":
                    p = _phrase(bloc.get("text"))
                    if p:
                        self.e["message"] = p
                        change = True
                elif bloc.get("type") == "tool_use":
                    d = _decrire(bloc.get("name"), bloc.get("input") or {})
                    if d:
                        self._etape(*d)
                        change = True
            return change
        if typ == "user":
            for bloc in (evt.get("message") or {}).get("content") or []:
                if isinstance(bloc, dict) and bloc.get("type") == "tool_result" and bloc.get("is_error"):
                    contenu = json.dumps(bloc.get("content"), ensure_ascii=False)[:400].lower()
                    if "permission" in contenu or "denied" in contenu or "not allowed" in contenu:
                        self.refus += 1
            return False
        if typ == "result":
            self.resultat = evt
            self.e["session"] = evt.get("session_id") or self.e.get("session")
            if evt.get("total_cost_usd") is not None:
                self.e["cout_usd"] = round(float(evt.get("total_cost_usd") or 0), 4)
            return True
        return False


def _compact(evt: dict) -> dict:
    """Version allégée d'un événement pour le journal (sans images ni gros contenus)."""
    if evt.get("type") == "user":
        res = []
        for b in (evt.get("message") or {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                texte = b.get("content")
                if not isinstance(texte, str):
                    texte = json.dumps(texte, ensure_ascii=False)
                res.append({"erreur": bool(b.get("is_error")), "texte": texte[:300]})
        return {"type": "user", "resultats": res}
    brut = json.dumps(evt, ensure_ascii=False)
    if len(brut) <= 4000:
        return evt
    return {"type": evt.get("type"), "subtype": evt.get("subtype"), "tronque": brut[:4000]}


# --------------------------------------------------------------------------- erreurs lisibles

def _resume_texte(texte, n: int = 220) -> str:
    lignes = [l.strip() for l in str(texte or "").splitlines() if l.strip()]
    t = " ".join(lignes[-3:])
    return t[:n] if t else "raison inconnue"


def _traduire(texte):
    t = str(texte or "").lower()
    if re.search(r"not logged in|please run /login|invalid api key|authentication|unauthori[sz]ed|\b401\b|"
                 r"oauth token|credentials", t):
        return "Claude n'est plus connecté. Ouvre Réglages › Claude et clique sur « Se connecter »."
    if re.search(r"usage limit|rate limit|limit reached|\b429\b|quota|hit your|limite", t):
        return ("La limite d'utilisation de Claude est atteinte pour le moment. Réessaie plus tard : "
                "elle se renouvelle au bout de quelques heures.")
    if re.search(r"overloaded|\b529\b|\b503\b", t):
        return "Les serveurs de Claude sont surchargés. Réessaie dans quelques minutes."
    if re.search(r"enotfound|econnrefused|econnreset|network|getaddrinfo|socket hang up|timed out|timeout", t):
        return "Claude n'arrive pas à joindre Internet. Vérifie la connexion du Mac, puis réessaie."
    return None


def _ecran_suivant(e: dict):
    t, j = e["tache"], e["jour"]
    statut = (config.lire_json(config.dossier_jour(j) / "etat.json", {}) or {}).get("statut")
    if t == "matin":
        return "idees" if statut == "idees_proposees" else "aujourdhui"
    if t == "idees":
        return "creation"
    if t in ("creation", "retouche"):
        return "creation" if statut == "brouillon_pret" else "aujourdhui"
    return {"galerie": "galeries", "bilan": "statistiques", "charte": "charte"}.get(t)


# --------------------------------------------------------------------------- exécution

def _commande(binaire: str, e: dict, session: str, reprise: bool) -> list:
    cmd = [binaire, "-p", "--output-format", "stream-json", "--verbose",
           "--plugin-dir", str(config.chemin(".plugin")),
           "--setting-sources", "project,local", "--strict-mcp-config",
           "--permission-mode", "acceptEdits", "--permission-prompts", "none",
           "--append-system-prompt", MODE_APP,
           "-n", "Studio · " + e["tache"] + " · " + e["jour"]]
    cmd += ["--resume", session] if reprise else ["--session-id", session]
    r = _reglages()
    if r.get("modele"):
        cmd += ["--model", str(r["modele"])]
    if r.get("effort") in ("low", "medium", "high", "xhigh", "max"):
        cmd += ["--effort", str(r["effort"])]
    cmd += ["--allowedTools"] + list(OUTILS)          # en dernier : l'option accepte plusieurs valeurs
    return cmd


def _lancer_claude(binaire, e, session, reprise, brut, delai_s):
    """Lance Claude et lit son flux jusqu'au bout. Rend (code, stderr, lecteur)."""
    lecteur = Lecteur(e)
    erreurs = open(_logs() / ("claude-" + e["id"] + ".stderr"), "w+", encoding="utf-8")
    proc = subprocess.Popen(_commande(binaire, e, session, reprise), cwd=str(config.RACINE),
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=erreurs,
                            env=environnement(), text=True, encoding="utf-8", errors="replace",
                            bufsize=1, start_new_session=True)
    e["pid_claude"] = proc.pid
    _ecrire(e)
    arret = {"delai": False}

    def trop_long():
        arret["delai"] = True
        _tuer(proc.pid)

    minuteur = threading.Timer(delai_s, trop_long)
    minuteur.daemon = True
    minuteur.start()
    try:
        proc.stdin.write(_prompt(e))
        proc.stdin.close()
    except (BrokenPipeError, OSError):
        pass
    dernier = 0.0
    try:
        for ligne in proc.stdout:
            ligne = ligne.strip()
            if not ligne:
                continue
            try:
                evt = json.loads(ligne)
            except ValueError:
                continue
            if not isinstance(evt, dict):
                continue
            brut.write(json.dumps(_compact(evt), ensure_ascii=False) + "\n")
            if lecteur.traiter(evt) and (time.time() - dernier > 0.3 or evt.get("type") == "result"):
                e["duree_s"] = _duree(e)
                _ecrire(e)
                dernier = time.time()
        proc.wait()
    finally:
        minuteur.cancel()
    erreurs.seek(0)
    texte = erreurs.read()
    erreurs.close()
    if arret["delai"]:
        texte += "\n[délai dépassé]"
    return proc.returncode, texte, lecteur, arret["delai"]


def _tuer(pid) -> None:
    try:
        os.killpg(int(pid), signal.SIGTERM)
    except (OSError, TypeError, ValueError):
        pass


def _duree(e: dict) -> int:
    try:
        debut = dt.datetime.fromisoformat(e["debut"])
        return max(0, int((config.maintenant() - debut).total_seconds()))
    except (TypeError, ValueError, KeyError):
        return 0


def executer(ident: str) -> dict:
    """Exécute une tâche préparée par lancer() (au premier plan) et rend son état final."""
    f = _fichier(ident)
    e = config.lire_json(f, None)
    if not isinstance(e, dict):
        raise ErreurStudio("Exécution inconnue : " + ident)
    if e.get("etat") not in ("en_attente",):
        return e
    config.ecrire_json(_dossier() / "verrou", {"id": ident, "pid": os.getpid(), "le": _maintenant()})
    e.update(etat="en_cours", debut=_maintenant(), pid=os.getpid())
    _ecrire(e)
    annulation = f.with_suffix(".annuler")
    try:
        binaire, _ = trouver()
        if not binaire:
            raise ErreurStudio(CONSEIL_ABSENT)
        delai_s = 60 * float(_reglages().get("delai_max_min") or 45)
        with open(f.with_suffix(".jsonl"), "w", encoding="utf-8") as brut:
            session, reprise = _session(e)
            code, texte, lecteur, delai = _lancer_claude(binaire, e, session, reprise, brut, delai_s)
            # Reprise impossible (conversation introuvable) ou identifiant déjà pris : un seul nouvel essai.
            if code and not lecteur.init and not annulation.exists() and not delai \
                    and re.search(r"session|conversation|already in use", texte, re.I):
                session, reprise = (_session(e, nouvelle=True)) if reprise else (session, True)
                code, texte, lecteur, delai = _lancer_claude(binaire, e, session, reprise, brut, delai_s)
        r = lecteur.resultat or {}
        e["fin"], e["duree_s"] = _maintenant(), _duree(e)
        if annulation.exists():
            e.update(etat="annule", erreur=None, message="Arrêté à ta demande.")
        elif delai:
            e.update(etat="erreur", erreur="Claude a mis trop de temps et a été arrêté. Réessaie, ou demande-lui "
                                           "quelque chose de plus court.")
        elif r and not r.get("is_error") and r.get("subtype", "success") == "success" and code == 0:
            for d in e["etapes"]:
                d["fait"] = True
            e.update(etat="termine", resultat=str(r.get("result") or "").strip() or None,
                     ecran_suivant=_ecran_suivant(e))
            if lecteur.refus:
                e["avertissement"] = ("Claude a dû renoncer à " + str(lecteur.refus) + " action(s) non autorisée(s) "
                                      "dans le studio.")
        else:
            brut_erreur = " ".join([str(r.get("result") or ""), str(r.get("subtype") or ""), texte])
            e.update(etat="erreur", erreur=_traduire(brut_erreur) or (
                "Claude s'est arrêté avant la fin : " + _resume_texte(r.get("result") or texte)))
    except ErreurStudio as err:
        e.update(etat="erreur", erreur=str(err), fin=_maintenant(), duree_s=_duree(e))
    except Exception as err:   # l'app doit toujours voir une fin
        e.update(etat="erreur", erreur="Erreur inattendue : " + err.__class__.__name__ + " : " + str(err),
                 fin=_maintenant(), duree_s=_duree(e))
    finally:
        e.pop("pid", None)
        e.pop("pid_claude", None)
        _ecrire(e)
        _rendre_verrou(ident)
        try:
            annulation.unlink()
        except FileNotFoundError:
            pass
    _apres(e)
    return e


def _apres(e: dict) -> None:
    """Montre le bon écran et, pour une tâche automatique, prévient la photographe."""
    from . import app as app_mod
    if e.get("etat") == "termine" and e.get("ecran_suivant") and e["tache"] != "demande":
        try:
            app_mod.ouvrir(e["ecran_suivant"], e["jour"])
        except Exception:
            pass
    if e.get("auto"):
        from . import planification
        if e.get("etat") == "termine":
            textes = {"matin": "Tes idées du jour sont prêtes : choisis celle que tu préfères.",
                      "bilan": "Ton bilan de la semaine est prêt."}
            planification.notifier(textes.get(e["tache"], "C'est prêt."), sous_titre=e.get("titre"))
        elif e.get("etat") == "erreur":
            planification.notifier(str(e.get("erreur") or "Claude n'a pas pu terminer."),
                                   sous_titre=str(e.get("titre") or "Studio Instagram"))


def etat(ident: str = None) -> dict:
    if not ident:
        ident = (config.lire_json(_dossier() / "actuel.json", {}) or {}).get("id")
        if not ident:
            return {"id": None, "etat": "aucune"}
    e = config.lire_json(_fichier(ident), None)
    if not isinstance(e, dict):
        return {"id": ident, "etat": "aucune"}
    if e.get("etat") in ("en_attente", "en_cours"):
        e["duree_s"] = _duree(e) if e.get("debut") else 0
        v = config.lire_json(_dossier() / "verrou", None)
        vivant = isinstance(v, dict) and v.get("id") == ident and (
            _vivant(v.get("pid")) if v.get("pid") else _execution_active() is not None)
        if not vivant:
            e.update(etat="erreur", fin=_maintenant(),
                     erreur="Claude a été interrompu (Mac éteint ou mis en veille ?). Relance la tâche.")
            _ecrire(e)
    return e


def annuler() -> dict:
    v = config.lire_json(_dossier() / "verrou", None)
    if not isinstance(v, dict) or not v.get("id"):
        return {"etat": "rien_en_cours"}
    ident = v["id"]
    f = _fichier(ident)
    f.with_suffix(".annuler").write_text(_maintenant(), encoding="utf-8")
    e = config.lire_json(f, {}) or {}
    if e.get("pid_claude"):
        _tuer(e["pid_claude"])
    if not (v.get("pid") and _vivant(v["pid"])):          # l'exécutant n'existe plus : on clôt nous-mêmes
        e.update(etat="annule", fin=_maintenant(), message="Arrêté à ta demande.")
        if e.get("id"):
            _ecrire(e)
        _rendre_verrou(ident)
    return {"etat": "annule", "id": ident}


def historique(n: int = 20) -> list:
    res = []
    for p in sorted(_dossier().glob("*.json"), reverse=True):
        if p.stem in ("actuel", "connexion", "conversation", "verrou"):
            continue
        e = config.lire_json(p, None)
        if isinstance(e, dict) and e.get("id"):
            res.append({k: v for k, v in e.items() if k != "etapes"})
        if len(res) >= n:
            break
    return res
