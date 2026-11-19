"""Statistiques : relevé quotidien et synthèse « ce qui fonctionne / à améliorer ».

Score d'une publication (0 à 1) = moyenne pondérée de ses rangs parmi les
publications mesurées : enregistrements 30 %, partages 25 %, portée rapportée
aux abonnés 25 %, engagement 10 %, abonnements gagnés 10 %. Les enregistrements
et partages pèsent le plus : ce sont les signaux d'un contenu qui compte
(inspiration des futurs mariés, partage entre professionnels).
"""
import datetime as dt
import re
import statistics

from . import config, instagram

POIDS = {"taux_enregistrement": 0.30, "taux_partage": 0.25, "portee_relative": 0.25,
         "taux_engagement": 0.10, "abonnements_1000": 0.10}
DIMENSIONS = {
    "pilier": lambda r: r.get("pilier"),
    "format": lambda r: r.get("format"),
    "tonalite": lambda r: (r.get("fiche_feed") or {}).get("tonalite"),
    "luminosite": lambda r: (r.get("fiche_feed") or {}).get("luminosite"),
    "plan": lambda r: (r.get("fiche_feed") or {}).get("plan"),
    "sujet": lambda r: (r.get("fiche_feed") or {}).get("sujet"),
    "longueur_legende": lambda r: r.get("longueur_legende"),
    "jour_semaine": lambda r: config.JOURS_FR[dt.date.fromisoformat(r["date"]).weekday()] if r.get("date") else None,
    "heure": lambda r: (r.get("heure") or "")[:2] + "h" if r.get("heure") else None,
    "taille_carrousel": lambda r: (None if r.get("format") != "carrousel" else
                                   "2-5 images" if r.get("nb_medias", 0) <= 5 else
                                   "6-8 images" if r.get("nb_medias", 0) <= 8 else "9-10 images"),
    "collaboration": lambda r: "avec collaborateurs" if r.get("collaborateurs") else "sans collaborateur",
}
LIBELLES = {"pilier": "Pilier", "format": "Format", "tonalite": "Couverture", "luminosite": "Luminosité",
            "plan": "Plan de couverture", "sujet": "Sujet de couverture", "longueur_legende": "Légende",
            "jour_semaine": "Jour", "heure": "Heure", "taille_carrousel": "Taille du carrousel",
            "collaboration": "Collaboration"}


def _date(texte: str) -> dt.datetime:
    """Accepte « 2026-11-18T18:30+01:00 », « …Z » et le format Instagram « …+0000 »."""
    texte = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", texte.replace("Z", "+00:00"))
    d = dt.datetime.fromisoformat(texte)
    if d.tzinfo is None:
        d = d.replace(tzinfo=config.fuseau())
    return d


def releve() -> dict:
    ig = instagram.Instagram()
    if not ig.pret():
        return {"etat": "jeton_absent"}
    perf_f = config.chemin("donnees", "performances.jsonl")
    dernier = {}
    for s in config.lire_jsonl(perf_f):
        dernier[s["media_id"]] = max(dernier.get(s["media_id"], ""), s.get("le", ""))
    maintenant = config.maintenant()
    faits, erreurs = 0, []
    for p in config.historique():
        mid = str(p.get("media_id") or "")
        if not mid or mid.startswith("SIMULATION"):
            continue
        pub = p.get("publie_le") or f"{p.get('date')}T{p.get('heure') or '12:00'}:00"
        try:
            age = (maintenant - _date(pub)).total_seconds() / 86400
        except ValueError:
            continue
        if age < 0.9 or age > 60:
            continue
        if dernier.get(mid) and (maintenant - _date(dernier[mid])).total_seconds() < 20 * 3600:
            continue
        try:
            stats = ig.statistiques(mid, "REELS" if p.get("format") == "reel" else "FEED")
        except config.ErreurStudio as e:
            erreurs.append(f"{p.get('date')} : {e}")
            continue
        config.ajouter_jsonl(perf_f, {"media_id": mid, "jour": p.get("jour") or p.get("date"),
                                      "le": maintenant.isoformat(timespec="minutes"), "age_j": round(age, 1), **stats})
        faits += 1
    abonnes = None
    try:
        abonnes = ig.profil().get("followers_count")
        ab_f = config.chemin("donnees", "abonnes.jsonl")
        jour = maintenant.date().isoformat()
        if not any(x.get("jour") == jour for x in config.lire_jsonl(ab_f)):
            config.ajouter_jsonl(ab_f, {"jour": jour, "abonnes": abonnes})
    except config.ErreurStudio as e:
        erreurs.append(str(e))
    return {"etat": "ok", "publications_relevees": faits, "abonnes": abonnes, "erreurs": erreurs}


def _rangs(valeurs: list) -> list:
    """Rang centile (0..1) de chaque valeur, ex aequo moyennés."""
    tri = sorted(v for v in valeurs if v is not None)
    if len(tri) < 2:
        return [0.5 if v is not None else None for v in valeurs]
    res = []
    for v in valeurs:
        if v is None:
            res.append(None)
            continue
        inf = sum(1 for x in tri if x < v)
        eg = sum(1 for x in tri if x == v)
        res.append((inf + (eg - 1) / 2) / (len(tri) - 1))
    return res


def _confiance(n: int) -> str:
    return "solide" if n >= 6 else ("à confirmer" if n >= 3 else "simple indice")


def synthese() -> dict:
    hist = config.historique()
    perfs = config.lire_jsonl(config.chemin("donnees", "performances.jsonl"))
    abonnes = config.lire_jsonl(config.chemin("donnees", "abonnes.jsonl"))
    mesure = {}
    for s in perfs:                       # on garde le relevé le plus tardif (≥ 3 jours si possible)
        m = mesure.get(s["media_id"])
        if not m or s.get("age_j", 0) > m.get("age_j", 0):
            mesure[s["media_id"]] = s

    def abonnes_au(date_iso):
        avant = [a for a in abonnes if a["jour"] <= date_iso]
        if avant:
            return avant[-1]["abonnes"]
        return abonnes[0]["abonnes"] if abonnes else None

    lignes = []
    for p in hist:
        s = mesure.get(str(p.get("media_id")))
        if not s or not s.get("reach"):
            continue
        portee = s["reach"]
        inter = s.get("total_interactions")
        if inter is None:
            inter = sum(s.get(k) or 0 for k in ("likes", "comments", "saved", "shares"))
        ab = abonnes_au(p.get("date", "")) or None
        lignes.append({
            **{k: p.get(k) for k in ("jour", "date", "heure", "format", "pilier", "serie", "titre",
                                     "longueur_legende", "fiche_feed", "permalink", "collaborateurs")},
            "nb_medias": len(p.get("medias") or []),
            "portee": portee, "vues": s.get("views"), "enregistrements": s.get("saved"),
            "partages": s.get("shares"), "age_j": s.get("age_j"),
            "taux_enregistrement": (s.get("saved") or 0) / portee,
            "taux_partage": (s.get("shares") or 0) / portee,
            "taux_engagement": inter / portee,
            "portee_relative": portee / ab if ab else None,
            "abonnements_1000": (s.get("follows") / portee * 1000) if s.get("follows") is not None else None,
        })
    res = {"maj": config.maintenant().isoformat(timespec="minutes"), "mesurees": len(lignes)}
    if len(lignes) < 3:
        res["message"] = "Pas encore assez de publications mesurées (3 minimum) : on observe."
        _ecrire(res, [], [], [])
        return res
    rangs = {k: _rangs([l[k] for l in lignes]) for k in POIDS}
    for i, l in enumerate(lignes):
        total = poids = 0.0
        for k, w in POIDS.items():
            if rangs[k][i] is not None:
                total += w * rangs[k][i]
                poids += w
        l["score"] = round(total / poids, 3) if poids else 0.5
    mediane = statistics.median(l["score"] for l in lignes)
    constats = []
    for dim, f in DIMENSIONS.items():
        groupes = {}
        for l in lignes:
            v = f(l)
            if v:
                groupes.setdefault(v, []).append(l["score"])
        if len(groupes) < 2:
            continue
        for v, scores in groupes.items():
            ecart = statistics.median(scores) - mediane
            constats.append({"dimension": dim, "valeur": v, "n": len(scores),
                             "score_median": round(statistics.median(scores), 3),
                             "ecart": round(ecart, 3), "confiance": _confiance(len(scores))})
    marche = sorted([c for c in constats if c["ecart"] >= 0.08 and c["n"] >= 2], key=lambda c: -c["ecart"])
    moins = sorted([c for c in constats if c["ecart"] <= -0.08 and c["n"] >= 2], key=lambda c: c["ecart"])
    tri = sorted(lignes, key=lambda l: -l["score"])
    res.update({"mediane": round(mediane, 3), "fonctionne": marche[:8], "a_ameliorer": moins[:8],
                "meilleures": tri[:3], "moins_bonnes": tri[-3:][::-1], "constats": constats,
                "moyennes": {"taux_enregistrement": round(statistics.mean(l["taux_enregistrement"] for l in lignes), 4),
                             "taux_partage": round(statistics.mean(l["taux_partage"] for l in lignes), 4)}})
    if abonnes:
        res["abonnes"] = {"debut": abonnes[0], "fin": abonnes[-1]}
    _ecrire(res, marche, moins, tri)
    return res


def _pct(x):
    return f"{x * 100:.1f} %".replace(".", ",") if x is not None else "n.d."


def _ecrire(res, marche, moins, tri):
    config.ecrire_json(config.chemin("donnees", "performance.json"), res)
    L = [f"# Performances (mis à jour le {res['maj'][:16].replace('T', ' à ')})", ""]
    L.append(f"Publications mesurées : {res['mesurees']}. Score de 0 à 1 : rang moyen sur les enregistrements "
             "(30 %), partages (25 %), portée rapportée aux abonnés (25 %), engagement (10 %), abonnements (10 %).")
    if res.get("message"):
        L += ["", res["message"]]
    else:
        L += ["", "## Ce qui fonctionne"]
        L += [f"- {LIBELLES[c['dimension']]} « {c['valeur']} » : score médian {c['score_median']} "
              f"({c['ecart']:+.2f} par rapport à la médiane), {c['n']} publications, {c['confiance']}"
              for c in marche] or ["- Rien de net pour l'instant."]
        L += ["", "## À améliorer"]
        L += [f"- {LIBELLES[c['dimension']]} « {c['valeur']} » : score médian {c['score_median']} "
              f"({c['ecart']:+.2f}), {c['n']} publications, {c['confiance']}" for c in moins] or ["- Rien de net pour l'instant."]
        def ligne(l):
            return (f"- {l['date']} · {l['pilier']} · {l['format']} · enregistrements {_pct(l['taux_enregistrement'])}"
                    f" · partages {_pct(l['taux_partage'])} · score {l['score']} · {l.get('permalink') or ''}")

        if len(tri) >= 6:
            L += ["", "## Meilleures publications"] + [ligne(l) for l in tri[:3]]
            L += ["", "## Moins bonnes"] + [ligne(l) for l in tri[-3:][::-1]]
        else:
            L += ["", "## Classement"] + [ligne(l) for l in tri]
        if res.get("abonnes"):
            a, b = res["abonnes"]["debut"], res["abonnes"]["fin"]
            L += ["", "## Abonnés", f"- {a['abonnes']} le {a['jour']} → {b['abonnes']} le {b['jour']} "
                                    f"({b['abonnes'] - a['abonnes']:+d})"]
        L += ["", "Rappel : avec peu de publications, ces écarts sont des pistes, pas des lois. "
                  "L'identité du compte passe toujours avant la portée."]
    config.chemin("memoire").mkdir(exist_ok=True)
    config.chemin("memoire", "performance.md").write_text("\n".join(L) + "\n", encoding="utf-8")
