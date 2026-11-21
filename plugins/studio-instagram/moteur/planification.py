"""Planification par macOS (launchd) : idées du matin, publications aux créneaux, bilan.

Trois LaunchAgents, qui tournent même quand l'app et Claude sont fermés :

    fr.atelier-photo.studio-instagram.matin        <studio>/studio claude lancer matin --attendre --auto
    fr.atelier-photo.studio-instagram.publication  <studio>/studio publier-dus --auto
    fr.atelier-photo.studio-instagram.bilan        <studio>/studio claude lancer bilan --attendre --auto

`planification.active` (config/compte.yaml) dit si la photographe les veut ; `appliquer()` met le Mac
en accord avec les réglages (heure des idées, créneaux de publication, jour et heure du bilan).
Une tâche n'est rechargée que si son fichier change : une routine en cours n'est pas interrompue
pour rien. Quand la planification est désactivée, seules les tâches qui pointent vers CE studio
sont retirées (un autre dossier de studio sur le même Mac garde les siennes).

Tests : STUDIO_LAUNCHAGENTS_DIR (autre dossier que ~/Library/LaunchAgents) et STUDIO_SANS_LAUNCHCTL=1
(launchctl n'est jamais appelé ; une tâche est alors « chargée » dès que son fichier est en place).
STUDIO_SANS_NOTIFICATION=1 coupe les notifications macOS.
"""
import datetime as dt
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import yaml

from . import config
from .config import ErreurStudio

PREFIXE = "fr.atelier-photo.studio-instagram"
ID_APP = "fr.atelier-photo.studio-instagram"      # l'app apparaît comme propriétaire des tâches (Réglages Système)
TACHES = (("matin", "Idées du matin"), ("publication", "Publication"), ("bilan", "Bilan de la semaine"))
COMMANDES = {
    "matin": ["claude", "lancer", "matin", "--attendre", "--auto"],
    "publication": ["publier-dus", "--auto"],
    "bilan": ["claude", "lancer", "bilan", "--attendre", "--auto"],
}
JOURS = config.JOURS_FR
ABREGES = ("lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim.")
WEEKDAY = {j: (i + 1) % 7 for i, j in enumerate(JOURS)}      # launchd : 0 = dimanche, 1 = lundi…
PATH_TACHES = ("~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin")
HEURE = re.compile(r"^([01]?\d|2[0-3]):([0-5]\d)$")
ENTETE_COMPTE = ("# Paramètres du compte. Modifiables dans l'app Studio Instagram (Réglages).\n"
                 "# Tant qu'un champ contient [À COMPLÉTER], le studio le signale.")
CONSEIL = "Réessaie dans un instant ; si cela se répète, redémarre le Mac."


# =========================================================================== réglages

def est_active(cfg=None) -> bool:
    c = config.compte() if cfg is None else cfg
    p = c.get("planification") if isinstance(c, dict) else None
    if not isinstance(p, dict):
        return False
    v = p.get("active")
    return v is True or (isinstance(v, str) and v.strip().lower() in ("true", "oui", "yes"))


def _heure(valeur):
    """(h, m) d'une heure « HH:MM », ou None. Sans guillemets, YAML lit 18:30 comme 1110 (minutes)."""
    if valeur is None or isinstance(valeur, bool):
        return None
    if isinstance(valeur, int):
        return (valeur // 60, valeur % 60) if 0 <= valeur < 24 * 60 else None
    m = HEURE.match(str(valeur).strip())
    return (int(m.group(1)), int(m.group(2))) if m else None


def _section(c: dict, nom: str) -> dict:
    v = c.get(nom) if isinstance(c, dict) else None
    return v if isinstance(v, dict) else {}


def horaires(cfg=None) -> dict:
    """Les horaires voulus par les réglages : {"matin": (h, m), "creneaux": [(jour, (h, m))…], "bilan": (jour, (h, m))}."""
    c = config.compte() if cfg is None else cfg
    rou, pub = _section(c, "routine"), _section(c, "publication")
    creneaux = pub.get("creneaux") if isinstance(pub.get("creneaux"), dict) else {}
    jour_bilan = str(rou.get("jour_bilan") or "").strip().lower()
    return {
        "matin": _heure(rou.get("heure_idees")) or (8, 0),
        "creneaux": [(j, _heure(creneaux.get(j))) for j in JOURS if _heure(creneaux.get(j))],
        "bilan": (jour_bilan if jour_bilan in JOURS else "dimanche", _heure(rou.get("heure_bilan")) or (19, 0)),
    }


# =========================================================================== descriptions lisibles

def _hhmm(h) -> str:
    return "%02d:%02d" % (h[0], h[1])


def _enumerer(mots) -> str:
    return mots[0] if len(mots) == 1 else ", ".join(mots[:-1]) + " et " + mots[-1]


def decrire_creneaux(creneaux) -> str:
    """« lun., mar., mer. et jeu. à 18:30 · ven. à 12:30 » ; « chaque jour à 18:30 » si tous les jours se ressemblent."""
    if not creneaux:
        return "aucun créneau de publication"
    groupes = {}
    for jour, h in creneaux:
        groupes.setdefault(h, []).append(jour)
    if len(groupes) == 1 and len(creneaux) == 7:
        return "chaque jour à " + _hhmm(creneaux[0][1])
    return " · ".join(_enumerer([ABREGES[JOURS.index(j)] for j in jours]) + " à " + _hhmm(h)
                      for h, jours in groupes.items())


def quand(tache: str, h: dict) -> str:
    if tache == "matin":
        return "chaque jour à " + _hhmm(h["matin"])
    if tache == "publication":
        return decrire_creneaux(h["creneaux"])
    return h["bilan"][0] + " à " + _hhmm(h["bilan"][1])


def _declencheurs(tache: str, h: dict, jour_semaine: int) -> list:
    """Heures de déclenchement d'une tâche un jour donné (0 = lundi)."""
    if tache == "matin":
        return [h["matin"]]
    if tache == "publication":
        return [hm for j, hm in h["creneaux"] if JOURS.index(j) == jour_semaine]
    return [h["bilan"][1]] if JOURS.index(h["bilan"][0]) == jour_semaine else []


def prochaine(tache: str, h: dict, maintenant=None):
    """Prochain déclenchement (ISO, heure locale du studio), ou None."""
    maintenant = maintenant or config.maintenant()
    for decalage in range(8):
        d = maintenant.date() + dt.timedelta(days=decalage)
        for hh, mm in sorted(_declencheurs(tache, h, d.weekday())):
            moment = dt.datetime(d.year, d.month, d.day, hh, mm, tzinfo=maintenant.tzinfo)
            if moment > maintenant:
                return moment.isoformat(timespec="minutes")
    return None


# =========================================================================== fichiers des tâches

def libelle(tache: str) -> str:
    return PREFIXE + "." + tache


def dossier_agents() -> Path:
    d = os.environ.get("STUDIO_LAUNCHAGENTS_DIR")
    return Path(d).expanduser() if d else Path.home() / "Library" / "LaunchAgents"


def fichier(tache: str) -> Path:
    return dossier_agents() / (libelle(tache) + ".plist")


def _script() -> Path:
    return config.RACINE / "studio"


def _path() -> str:
    return ":".join(str(Path(p).expanduser()) for p in PATH_TACHES)


def _afficher(p: Path) -> str:
    maison, s = str(Path.home()), str(p)
    return "~" + s[len(maison):] if s == maison or s.startswith(maison + os.sep) else s


def contenu(tache: str, h: dict = None) -> dict:
    """Le LaunchAgent d'une tâche (dictionnaire écrit tel quel avec plistlib)."""
    h = horaires() if h is None else h
    if tache == "matin":
        intervalle = {"Hour": h["matin"][0], "Minute": h["matin"][1]}
    elif tache == "publication":
        intervalle = [{"Weekday": WEEKDAY[j], "Hour": hm[0], "Minute": hm[1]} for j, hm in h["creneaux"]]
    else:
        jour, hm = h["bilan"]
        intervalle = {"Weekday": WEEKDAY[jour], "Hour": hm[0], "Minute": hm[1]}
    logs = config.chemin(".ui", "logs")
    return {
        "Label": libelle(tache),
        "ProgramArguments": [str(_script())] + COMMANDES[tache],
        "WorkingDirectory": str(config.RACINE),
        "StartCalendarInterval": intervalle,
        "EnvironmentVariables": {"PATH": _path(), "LANG": "fr_FR.UTF-8"},
        "StandardOutPath": str(logs / ("planification-" + tache + ".log")),
        "StandardErrorPath": str(logs / ("planification-" + tache + "-erreurs.log")),
        "RunAtLoad": False,
        "AssociatedBundleIdentifiers": [ID_APP],
    }


def _ecrire_atomique(f: Path, data: bytes, mode: int = 0o644) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(f.parent), prefix=".studio-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, f)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _ecrire_plist(f: Path, donnees: dict) -> bool:
    """Écrit le fichier s'il a changé ; True si c'est le cas."""
    data = plistlib.dumps(donnees, fmt=plistlib.FMT_XML, sort_keys=True)
    try:
        if f.read_bytes() == data:
            return False
    except OSError:
        pass
    _ecrire_atomique(f, data)
    return True


def _a_ce_studio(f: Path) -> bool:
    """Le fichier de tâche lance-t-il le `studio` de ce dossier ?"""
    try:
        with f.open("rb") as fh:
            args = plistlib.load(fh).get("ProgramArguments") or []
    except Exception:
        return False
    return bool(args) and os.path.realpath(str(args[0])) == os.path.realpath(str(_script()))


# =========================================================================== launchctl

def _sans_launchctl() -> bool:
    return os.environ.get("STUDIO_SANS_LAUNCHCTL") == "1"


def _domaine() -> str:
    return "gui/%d" % os.getuid()


def _launchctl(*args):
    exe = shutil.which("launchctl") or "/bin/launchctl"
    cmd = [exe] + [str(a) for a in args]
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def _journal(texte: str) -> None:
    """Détail technique pour le dépannage (.ui/logs/planification.log), jamais montré tel quel."""
    try:
        f = config.chemin(".ui", "logs", "planification.log")
        f.parent.mkdir(parents=True, exist_ok=True)
        with f.open("a", encoding="utf-8") as fh:
            fh.write(config.maintenant().isoformat(timespec="seconds") + " " + texte.strip() + "\n")
    except Exception:
        pass


def chargee(tache: str) -> bool:
    f = fichier(tache)
    if not (f.exists() and _a_ce_studio(f)):
        return False
    if _sans_launchctl():
        return True
    return _launchctl("print", _domaine() + "/" + libelle(tache)).returncode == 0


def _decharger(tache: str) -> None:
    if not _sans_launchctl():
        _launchctl("bootout", _domaine() + "/" + libelle(tache))      # « pas chargée » n'est pas une erreur


def _charger(tache: str, f: Path) -> bool:
    """bootout puis bootstrap (deux nouvelles tentatives si macOS n'a pas fini de retirer l'ancienne)."""
    if _sans_launchctl():
        return True
    r = None
    for essai in range(3):
        _decharger(tache)
        if essai:
            time.sleep(essai)
        r = _launchctl("bootstrap", _domaine(), str(f))
        if r.returncode == 0:
            return True
    _journal("bootstrap %s refusé (%s) : %s" % (libelle(tache), r.returncode, (r.stderr or r.stdout or "").strip()))
    return False


def _retirer(tache: str, forcer: bool = False) -> None:
    """Décharge et supprime la tâche si elle lance ce studio (ou si `forcer`)."""
    f = fichier(tache)
    if not f.exists() or not (forcer or _a_ce_studio(f)):
        return
    _decharger(tache)
    try:
        f.unlink()
    except FileNotFoundError:
        pass


# =========================================================================== commandes

def etat(cfg=None) -> dict:
    """`./studio planifier --etat`."""
    c = config.compte() if cfg is None else cfg
    h, active = horaires(c), est_active(c)
    maintenant = config.maintenant()
    taches = []
    for tache, titre in TACHES:
        en_place = chargee(tache)
        taches.append({"id": tache, "titre": titre, "quand": quand(tache, h), "chargee": en_place,
                       "prochaine": prochaine(tache, h, maintenant) if active and en_place else None})
    return {"active": active, "taches": taches, "dossier_agents": _afficher(dossier_agents())}


def appliquer() -> dict:
    """Met le Mac en accord avec les réglages : tâches écrites et chargées si la planification est active,
    retirées sinon. Rend etat() ; ErreurStudio si macOS refuse une tâche."""
    cfg = config.compte()
    try:
        if not est_active(cfg):
            for tache, _ in TACHES:
                _retirer(tache)
            return etat(cfg)
        h = horaires(cfg)
        config.chemin(".ui", "logs").mkdir(parents=True, exist_ok=True)
        refusees = []
        for tache, titre in TACHES:
            if tache == "publication" and not h["creneaux"]:
                _retirer(tache, forcer=True)          # aucun créneau : pas de tâche de publication
                continue
            f = fichier(tache)
            change = _ecrire_plist(f, contenu(tache, h))
            if (change or not chargee(tache)) and not _charger(tache, f):
                refusees.append("« " + titre + " »")
    except OSError as e:
        _journal("dossier des tâches : %s" % e)
        raise ErreurStudio("Le dossier des tâches automatiques du Mac (" + _afficher(dossier_agents())
                           + ") n'est pas modifiable. " + CONSEIL)
    if refusees:
        raise ErreurStudio("Le Mac n'a pas pu programmer " + _enumerer(refusees) + ". " + CONSEIL)
    return etat(cfg)


def activer() -> dict:
    """Installe (ou réinstalle) les trois tâches d'après les réglages. En cas d'échec, rien ne reste activé."""
    enregistrer_active(True)
    try:
        return appliquer()
    except Exception as e:
        try:
            enregistrer_active(False)
        except Exception:
            pass
        for tache, _ in TACHES:
            try:
                _retirer(tache)
            except Exception:
                pass
        if isinstance(e, ErreurStudio):
            raise
        _journal("activation : %r" % e)
        raise ErreurStudio("Les tâches automatiques n'ont pas pu être activées. " + CONSEIL)


def desactiver() -> dict:
    enregistrer_active(False)
    try:
        for tache, _ in TACHES:
            _retirer(tache)
    except OSError as e:
        _journal("désactivation : %s" % e)
        raise ErreurStudio("Les tâches automatiques n'ont pas pu être retirées du Mac. " + CONSEIL)
    return etat()


# =========================================================================== planification.active dans config/compte.yaml

_BLOC = re.compile(r"^planification\s*:\s*(#.*)?$")
_ACTIVE = re.compile(r"^(\s+)active\s*:\s*[^#]*?(\s+#.*)?$")


def _texte_avec_active(texte: str, valeur: bool, cle_presente: bool):
    """Change seulement la ligne `active:` du bloc `planification:` (les commentaires restent)."""
    v = "true" if valeur else "false"
    lignes = texte.splitlines(True)
    debut = next((i for i, l in enumerate(lignes) if _BLOC.match(l.rstrip("\r\n"))), None)
    if debut is None:
        if cle_presente:
            return None                                   # forme inhabituelle : réécriture complète
        sep = "" if not texte or texte.endswith("\n") else "\n"
        return (texte + sep + "\n# Tâches automatiques du Mac (idées du matin, publications, bilan) :"
                " ./studio planifier --activer ou --desactiver\nplanification:\n  active: " + v + "\n")
    fin = debut + 1
    while fin < len(lignes) and (not lignes[fin].strip() or lignes[fin][0] in " \t"):
        fin += 1
    for i in range(debut + 1, fin):
        m = _ACTIVE.match(lignes[i].rstrip("\r\n"))
        if m:
            lignes[i] = m.group(1) + "active: " + v + (m.group(2) or "") + "\n"
            return "".join(lignes)
    retrait = next((re.match(r"^(\s+)", l).group(1) for l in lignes[debut + 1:fin]
                    if l.strip() and not l.lstrip().startswith("#")), "  ")
    lignes.insert(debut + 1, retrait + "active: " + v + "\n")
    return "".join(lignes)


def enregistrer_active(valeur: bool) -> None:
    """planification.active dans config/compte.yaml, en gardant les commentaires quand c'est possible."""
    f = config.chemin("config", "compte.yaml")
    texte = f.read_text(encoding="utf-8") if f.exists() else ""
    try:
        avant = yaml.safe_load(texte) if texte.strip() else {}
    except yaml.YAMLError:
        raise ErreurStudio("config/compte.yaml contient une erreur de mise en forme : corrige-la d'abord "
                           "(./studio verifier).")
    avant = avant or {}
    if not isinstance(avant, dict):
        raise ErreurStudio("config/compte.yaml n'a pas la forme attendue.")
    attendu = dict(avant)
    p = avant.get("planification")
    attendu["planification"] = dict(p, active=bool(valeur)) if isinstance(p, dict) else {"active": bool(valeur)}
    nouveau = _texte_avec_active(texte, bool(valeur), "planification" in avant)
    try:
        bon = nouveau is not None and yaml.safe_load(nouveau) == attendu
    except yaml.YAMLError:
        bon = False
    if not bon:
        nouveau = ENTETE_COMPTE + "\n\n" + yaml.safe_dump(attendu, allow_unicode=True, sort_keys=False, width=110)
    if nouveau != texte:
        mode = (f.stat().st_mode & 0o777) if f.exists() else 0o644
        _ecrire_atomique(f, nouveau.encode("utf-8"), mode)


# =========================================================================== notifications macOS

def _net(texte, longueur: int) -> str:
    t = " ".join(str(texte or "").split()).lstrip("- ")
    return t if len(t) <= longueur else t[:longueur - 1].rstrip() + "…"


def notifier(message: str, titre: str = "Studio Instagram", sous_titre: str = None) -> bool:
    """Notification du Centre de notifications. Les textes passent en arguments (argv) d'osascript,
    jamais dans le script lui-même : aucun guillemet ni caractère ne peut le casser."""
    if os.environ.get("STUDIO_SANS_NOTIFICATION") == "1":
        return False
    exe = shutil.which("osascript") or "/usr/bin/osascript"
    script = ["on run argv",
              "if (count of argv) > 2 then",
              "display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)",
              "else",
              "display notification (item 1 of argv) with title (item 2 of argv)",
              "end if",
              "end run"]
    cmd = [exe]
    for ligne in script:
        cmd += ["-e", ligne]
    cmd += [_net(message, 230) or "Studio Instagram", _net(titre, 60) or "Studio Instagram"]
    if sous_titre:
        cmd.append(_net(sous_titre, 80))
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _nom_post(jour) -> str:
    titre = None
    if jour:
        try:
            titre = (config.lire_json(config.chemin("jours", str(jour), "post.json"), {}) or {}).get("titre")
        except Exception:
            titre = None
    if titre and str(titre).strip():
        return "« " + str(titre).strip() + " »"
    try:
        return "Le post du " + config.date_longue(str(jour))
    except Exception:
        return "Le post du jour"


def notifier_publications(resultats) -> int:
    """`publier-dus --auto` : une notification par post publié ou en échec. Rend le nombre envoyé."""
    envoyees = 0
    for r in resultats or []:
        if not isinstance(r, dict) or r.get("etat") not in ("publie", "echec"):
            continue
        nom = _nom_post(r.get("jour"))
        if r["etat"] == "publie":
            message = nom + " est en ligne sur Instagram."
            if r.get("avertissements"):
                message += " Une remarque t'attend dans le Studio."
            ok = notifier(message, sous_titre="Post publié")
        else:
            raison = str(r.get("erreur") or "raison inconnue").strip().rstrip(". ")
            ok = notifier(nom + " n'a pas pu être publié : " + raison + ". Ouvre le Studio pour réessayer.",
                          sous_titre="Publication à reprendre")
        envoyees += 1 if ok else 0
    return envoyees


def notifier_echec_publication(erreur) -> bool:
    raison = str(erreur) if isinstance(erreur, ErreurStudio) else "un problème inattendu est survenu"
    return notifier("La publication automatique n'a pas pu se faire : " + raison.strip().rstrip(". ")
                    + ". Ouvre le Studio pour voir.", sous_titre="Publication à reprendre")
