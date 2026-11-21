"""Sources de l'app propres à chaque studio : première copie, puis mises à jour depuis le plugin.

<studio>/app contient les sources de l'app de CE studio, que Claude peut personnaliser.
app/.base.json garde, pour chaque fichier, l'empreinte sha256 de la version du plugin dont il est issu.
À chaque mise à jour (installer.sh → ./studio app synchroniser-sources <dossier app du plugin>) :

- fichier jamais modifié (empreinte = base) → remplacé par la nouvelle version du plugin ;
- fichier personnalisé → conservé. Si le plugin l'a aussi changé, il est ajouté à app/.conflits.json
  (empreintes d'origine, du plugin et locale, chemin de la nouvelle version) et sa base passe à la
  nouvelle version : le conflit est signalé une seule fois et reste dans .conflits.json jusqu'à ce
  qu'on retire l'entrée, une fois la nouvelle version fusionnée (skill studio-app) ;
- nouveau fichier du plugin → copié ;
- fichier retiré du plugin → supprimé s'il n'avait pas été modifié, sinon conservé et signalé ;
- fichier supprimé exprès dans app/ → pas recréé (signalé si le plugin l'a changé entre-temps).

Les fichiers créés dans app/ (PERSONNALISATIONS.md, nouveaux écrans…) ne sont jamais touchés ;
.DS_Store et les produits de compilation sont ignorés. Pour repartir des sources d'origine :
supprimer le dossier app/ (avec .base.json), puis relancer l'installation.
"""
import hashlib
import os
import shutil
import tempfile
from pathlib import Path

from . import config
from .config import ErreurStudio

BASE = ".base.json"
CONFLITS = ".conflits.json"
NOMS_IGNORES = {".DS_Store", "Thumbs.db", BASE, CONFLITS}
DOSSIERS_IGNORES = {".build", "build", "DerivedData", "__pycache__", ".git", ".swiftpm", "xcuserdata"}
SUFFIXES_DOSSIERS_IGNORES = (".app", ".dSYM", ".xcarchive")
SUFFIXES_FICHIERS_IGNORES = (".o", ".pyc", ".pyo", ".swiftmodule", ".swiftdoc", ".swiftsourceinfo", ".swiftdeps",
                             ".dia", ".tmp", ".swp", ".swo", "~")
EXPLICATION = ("Ces fichiers de l'app ont été personnalisés dans ce studio et ont aussi changé dans une nouvelle "
               "version du plugin : la version personnalisée a été gardée. Pour fusionner : comparer app/<fichier> "
               "avec « nouvelle_version », y reporter les améliorations utiles, reconstruire (bash app/construire.sh), "
               "puis retirer l'entrée de cette liste. « nouvelle_version » vide : le plugin a retiré ce fichier.")


def empreinte(f) -> str:
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for bloc in iter(lambda: fh.read(1 << 16), b""):
            h.update(bloc)
    return h.hexdigest()


def _ignore_dossier(nom: str) -> bool:
    return nom in DOSSIERS_IGNORES or nom.endswith(SUFFIXES_DOSSIERS_IGNORES)


def _ignore_fichier(nom: str) -> bool:
    return nom in NOMS_IGNORES or nom.endswith(SUFFIXES_FICHIERS_IGNORES)


def fichiers(racine: Path) -> dict:
    """Fichiers suivis d'un dossier d'app : {chemin relatif (avec /) : Path}."""
    res = {}
    for dossier, sous, noms in os.walk(str(racine)):
        sous[:] = sorted(d for d in sous if not _ignore_dossier(d))
        for nom in sorted(noms):
            p = Path(dossier) / nom
            if not _ignore_fichier(nom) and p.is_file():
                res[p.relative_to(racine).as_posix()] = p
    return res


def _lire(f: Path) -> dict:
    try:
        v = config.lire_json(f, {})
    except (ValueError, OSError):
        return {}
    return v if isinstance(v, dict) else {}


def _copier(source: Path, cible: Path) -> None:
    """Copie atomique : un fichier n'est jamais laissé à moitié écrit."""
    cible.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(cible.parent), prefix=".sync-", suffix=".tmp")
    os.close(fd)
    try:
        shutil.copy2(str(source), tmp)
        os.replace(tmp, str(cible))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _retirer_dossiers_vides(dossier: Path, racine: Path) -> None:
    while dossier != racine and racine in dossier.parents:
        try:
            dossier.rmdir()
        except OSError:
            return
        dossier = dossier.parent


def _version(source: Path):
    f = source.parent / "moteur" / "VERSION"
    try:
        return f.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def synchroniser_app(source, cible) -> dict:
    """Copie ou met à jour les sources de l'app du plugin (`source`) dans celles du studio (`cible`)."""
    src = Path(str(source)).expanduser().resolve()
    dst = Path(str(cible)).expanduser()
    if not src.is_dir():
        raise ErreurStudio("Sources de l'app introuvables : " + str(src))
    if not ((src / "Sources").is_dir() or (src / "construire.sh").is_file()):
        raise ErreurStudio("Ce dossier ne contient pas les sources de l'app Studio Instagram : " + str(src))
    dst.mkdir(parents=True, exist_ok=True)
    dst = dst.resolve()
    if src == dst:
        raise ErreurStudio("Les sources du plugin et celles du studio sont le même dossier : rien à synchroniser.")

    info = _lire(dst / BASE)
    base = {str(k): str(v) for k, v in (info.get("fichiers") or {}).items()} \
        if isinstance(info.get("fichiers"), dict) else {}
    nouvelle_base = dict(base)
    sources = fichiers(src)
    copie_plugin = dst.parent / ".plugin" / "app"
    le = config.maintenant().isoformat(timespec="seconds")
    copies, conserves, supprimes, erreurs, conflits = [], [], [], [], []
    inchanges = 0
    h_sources = {}

    def reference(rel, h_src):
        """Où lire la nouvelle version : la copie du plugin dans le studio (durable) si elle est identique."""
        f = copie_plugin / rel
        try:
            if f.is_file() and empreinte(f) == h_src:
                return ".plugin/app/" + rel
        except OSError:
            pass
        return str(src / rel)

    def conflit(rel, origine, plugin, locale):
        conflits.append({"fichier": rel, "empreinte_origine": origine, "empreinte_plugin": plugin,
                         "empreinte_locale": locale,
                         "nouvelle_version": reference(rel, plugin) if plugin else None, "le": le})

    for rel, f_src in sources.items():
        f_loc = dst / rel
        h_base = base.get(rel)
        try:
            h_src = h_sources[rel] = empreinte(f_src)
            if not f_loc.exists():
                if h_base is None:                         # nouveau fichier du plugin
                    _copier(f_src, f_loc)
                    nouvelle_base[rel] = h_src
                    copies.append(rel)
                else:                                      # supprimé exprès dans le studio : on respecte
                    conserves.append(rel)
                    if h_src != h_base:
                        conflit(rel, h_base, h_src, None)
                        nouvelle_base[rel] = h_src
                continue
            h_loc = empreinte(f_loc)
            if h_loc == h_src:                             # déjà à jour
                nouvelle_base[rel] = h_src
                inchanges += 1
            elif h_base is not None and h_loc == h_base:   # jamais modifié : suit le plugin
                _copier(f_src, f_loc)
                nouvelle_base[rel] = h_src
                copies.append(rel)
            else:                                          # personnalisé (ou d'origine inconnue) : gardé
                conserves.append(rel)
                if h_base != h_src:
                    conflit(rel, h_base, h_src, h_loc)
                    nouvelle_base[rel] = h_src
        except OSError as e:
            erreurs.append(rel + " : " + (e.strerror or str(e)))

    for rel in sorted(set(base) - set(sources)):           # retirés du plugin
        f_loc = dst / rel
        try:
            if f_loc.is_file():
                h_loc = empreinte(f_loc)
                if h_loc == base[rel]:
                    f_loc.unlink()
                    _retirer_dossiers_vides(f_loc.parent, dst)
                    supprimes.append(rel)
                else:
                    conserves.append(rel)
                    conflit(rel, base[rel], None, h_loc)
        except OSError as e:
            erreurs.append(rel + " : " + (e.strerror or str(e)))
            continue
        nouvelle_base.pop(rel, None)

    version = _version(src)
    if nouvelle_base != base or info.get("plugin") != version or not (dst / BASE).exists():
        config.ecrire_json(dst / BASE, {"plugin": version, "synchronise_le": le,
                                        "fichiers": dict(sorted(nouvelle_base.items()))})

    # Conflits en attente : ceux d'avant (pas encore fusionnés) + les nouveaux ; un conflit dont le
    # fichier est redevenu identique à la version du plugin est réglé de lui-même.
    anciens = _lire(dst / CONFLITS).get("conflits")
    par_fichier = {c["fichier"]: c for c in (anciens if isinstance(anciens, list) else [])
                   if isinstance(c, dict) and isinstance(c.get("fichier"), str)}
    avant = dict(par_fichier)
    for c in conflits:
        par_fichier[c["fichier"]] = c
    for rel in list(par_fichier):
        f_loc = dst / rel
        try:
            if rel in h_sources and f_loc.is_file() and empreinte(f_loc) == h_sources[rel]:
                del par_fichier[rel]
        except OSError:
            pass
    en_attente = [par_fichier[k] for k in sorted(par_fichier)]
    if par_fichier != avant:
        config.ecrire_json(dst / CONFLITS, {"explication": EXPLICATION, "conflits": en_attente})

    return {"copies": copies, "conserves": sorted(set(conserves)), "conflits": sorted(c["fichier"] for c in conflits),
            "supprimes": supprimes, "inchanges": inchanges, "conflits_en_attente": [c["fichier"] for c in en_attente],
            "erreurs": erreurs}
