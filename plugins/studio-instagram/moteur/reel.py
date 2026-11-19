"""Montage des Reels avec ffmpeg (fourni par imageio-ffmpeg, aucune installation système).

Plans possibles dans reel.plan_de_montage :
- une vidéo (clip Pic-Time ou rush local) : {"fichier": "...", "debut_s": 2.0, "duree_s": 3}
- une photo de la série : {"fichier": "<id photo>", "duree_s": 3, "presentation": "plein_cadre|marges"}
  (lent mouvement d'approche, jamais d'effet appuyé)
Transitions : fondu discret au noir entre les plans. Musique : intégrée seulement si
musique.mode == "integree" (fichier libre de droits du dossier musique/). En mode
"api_reel", la musique Instagram est ajoutée par l'API au moment de publier.
"""
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import config, sources
from .config import ErreurStudio

W, H, FPS = 1080, 1920, 30


def ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        exe = shutil.which("ffmpeg")
        if exe:
            return exe
    raise ErreurStudio("ffmpeg indisponible : relance l'installation (/studio-instagram:studio-installation).")


def _lancer(args: list):
    r = subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y"] + args,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise ErreurStudio("Montage impossible : " + (r.stderr or "")[-400:])


def _couleur(fond: str) -> str:
    fond = fond or "#f6f2ec"
    return "0x" + fond.lstrip("#") if fond.startswith("#") else fond


def _source(serie_id: str, fichier: str):
    """Renvoie (chemin, 'image'|'video')."""
    p = Path(str(fichier)).expanduser()
    if p.exists():
        return p, ("video" if p.suffix.lower() in (".mp4", ".mov", ".m4v") else "image")
    cat = sources.lire_catalogue(serie_id)
    for ph in cat.get("photos", []):
        if ph["id"] == str(fichier):
            if ph.get("type") == "clip":
                cache = config.dossier_serie(serie_id) / "clips" / f"{ph['id']}.mp4"
                if not cache.exists():
                    cache.parent.mkdir(parents=True, exist_ok=True)
                    _lancer(["-i", ph["url"]["video"], "-c", "copy", str(cache)])
                return cache, "video"
            return sources.chemin_photo(serie_id, ph["id"], hd=True), "image"
    raise ErreurStudio(f"Plan introuvable : {fichier}")


def _segment(src: Path, genre: str, plan: dict, sortie: Path, fondu: float = 0.3):
    duree = float(plan.get("duree_s", 3))
    fin = max(0.0, duree - fondu)
    fondus = f"fade=t=in:st=0:d={fondu},fade=t=out:st={fin}:d={fondu}"
    if genre == "video":
        vf = (f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},fps={FPS},"
              f"{fondus},format=yuv420p")
        _lancer(["-ss", str(plan.get("debut_s", 0)), "-t", str(duree), "-i", str(src), "-an",
                 "-vf", vf, "-c:v", "libx264", "-preset", "medium", "-crf", "18", str(sortie)])
        return
    images = int(duree * FPS)
    zoom = float(plan.get("zoom", 1.06))
    pas = (zoom - 1) / max(1, images)
    if plan.get("presentation") == "marges":
        base = (f"scale={W - 120}:{H - 400}:force_original_aspect_ratio=decrease,"
                f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color={_couleur(plan.get('fond'))},scale={W * 2}:{H * 2}")
    else:
        base = f"scale={W * 2}:{H * 2}:force_original_aspect_ratio=increase,crop={W * 2}:{H * 2}"
    vf = (f"{base},zoompan=z='min(1+{pas:.6f}*on,{zoom})':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'"
          f":d={images}:s={W}x{H}:fps={FPS},{fondus},format=yuv420p")
    _lancer(["-loop", "1", "-i", str(src), "-t", str(duree), "-vf", vf, "-c:v", "libx264",
             "-preset", "medium", "-crf", "18", "-r", str(FPS), str(sortie)])


def monter(jour: str) -> dict:
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post or post.get("format") != "reel":
        raise ErreurStudio("post.json absent ou ce n'est pas un Reel.")
    reel = post.get("reel") or {}
    plan = reel.get("plan_de_montage") or []
    if not plan:
        raise ErreurStudio("Reel déjà monté (pas de plan de montage) : rien à faire.")
    rendu = d / "rendu"
    rendu.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="studio-reel-"))
    try:
        liste = []
        for i, p in enumerate(sorted(plan, key=lambda x: x.get("ordre", 0))):
            src, genre = _source(post["serie"], p["fichier"])
            seg = tmp / f"plan{i:02d}.mp4"
            _segment(src, genre, p, seg)
            liste.append(seg)
        (tmp / "liste.txt").write_text("".join(f"file '{s}'\n" for s in liste), encoding="utf-8")
        muet = tmp / "muet.mp4"
        _lancer(["-f", "concat", "-safe", "0", "-i", str(tmp / "liste.txt"), "-c", "copy", str(muet)])
        duree = sum(float(p.get("duree_s", 3)) for p in plan)
        sortie = rendu / "reel.mp4"
        mus = post.get("musique") or {}
        piste = mus.get("fichier_local")
        if mus.get("mode") == "integree" and piste and Path(config.chemin(piste)).exists():
            af = f"afade=t=in:st=0:d=1,afade=t=out:st={max(0, duree - 2.5)}:d=2.5"
            _lancer(["-i", str(muet), "-i", str(config.chemin(piste)), "-map", "0:v", "-map", "1:a",
                     "-af", af, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
                     "-movflags", "+faststart", str(sortie)])
        else:   # piste silencieuse : la musique Instagram sera posée par l'API
            _lancer(["-i", str(muet), "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-map", "0:v",
                     "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest",
                     "-movflags", "+faststart", str(sortie)])
        couverture = rendu / "couverture.jpg"
        repere = str(reel.get("couverture") or "")
        if ":" in repere:
            mm, ss = repere.split(":")[:2]
            t = int(mm) * 60 + float(ss)
            _lancer(["-ss", str(t), "-i", str(sortie), "-frames:v", "1", "-q:v", "2", str(couverture)])
        elif repere:
            src, _ = _source(post["serie"], repere)
            from . import images
            img = images.ouvrir(src)
            boite = images._fenetre(img.width, img.height, W / H, "centre")
            img.crop(boite).resize((W, H)).save(couverture, "JPEG", quality=92)
        else:
            _lancer(["-ss", "1", "-i", str(sortie), "-frames:v", "1", "-q:v", "2", str(couverture)])
        return {"video": str(sortie), "couverture": str(couverture), "duree_s": round(duree, 1),
                "plans": len(plan), "octets": sortie.stat().st_size}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def infos_video(chemin) -> dict:
    """Durée et dimensions d'une vidéo (pour vérifier un Reel déjà monté)."""
    r = subprocess.run([ffmpeg(), "-hide_banner", "-i", str(chemin)], capture_output=True, text=True)
    import re
    texte = r.stderr
    duree = re.search(r"Duration: (\d+):(\d+):([\d.]+)", texte)
    taille = re.search(r", (\d{3,5})x(\d{3,5})", texte)
    res = {}
    if duree:
        h, m, s = duree.groups()
        res["duree_s"] = round(int(h) * 3600 + int(m) * 60 + float(s), 1)
    if taille:
        res["largeur"], res["hauteur"] = int(taille.group(1)), int(taille.group(2))
    return res


if __name__ == "__main__":  # pragma: no cover
    print(json.dumps({"ffmpeg": ffmpeg()}))
