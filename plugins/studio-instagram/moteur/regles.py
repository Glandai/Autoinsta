"""Règles du prompt traduites en contrôles automatiques.

Claude écrit, ce module vérifie : interdits de légende, limites techniques,
alternance du feed, prénoms, comptes inventés, images déjà publiées.
Une erreur bloque l'aperçu « prêt à publier » ; un avertissement s'affiche.
"""
import datetime as dt
import re
import unicodedata

from . import config

PILIERS = ["EDITORIAL", "DOCUMENTARY", "DETAILS", "PLACES", "PORTRAITS", "LOVE_STORY",
           "ATMOSPHERE", "ARTISTIC_VISION"]
VALEURS = {
    "tonalite": ["nb", "couleur"],
    "luminosite": ["claire", "sombre", "contrastee"],
    "plan": ["large", "moyen", "serre", "detail"],
    "sujet": ["couple", "mariee", "marie", "invites", "lieu", "objet", "nature", "autre"],
}
LONGUEURS = ["silencieuse", "courte", "recit"]
FORMATS = ["carrousel", "image", "reel"]
ROLES = ["ouverture", "progression", "respiration", "surprise", "cloture"]
PRESENTATIONS = ["plein_cadre", "marges"]
ANCRAGES = ["centre", "haut", "bas", "gauche", "droite"]
MODES_MUSIQUE = ["api_reel", "integree", "a_ajouter_dans_l_app", "aucune"]

MAX_MEDIAS_EDITORIAL, MAX_MEDIAS_API = 10, 20
MAX_LEGENDE, MAX_MENTIONS, MAX_HASHTAGS, MAX_COLLABORATEURS = 2200, 20, 5, 3


def sans_accents(t: str) -> str:
    t = t.replace("’", "'").replace("œ", "oe").replace("Œ", "OE")
    return "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn").lower()


# --------------------------------------------------------------------------- interdits

CLICHES = [
    "le plus beau jour de leur vie", "le plus beau jour de votre vie", "le plus beau jour de ma vie",
    "dire oui", "ont dit oui", "a dit oui", "conte de fees", "ames soeurs", "ame soeur", "magique",
    "magiques", "feerique", "feeriques", "parenthese enchantee", "mariage de reve",
    "des etoiles plein les yeux", "happily ever after", "love is in the air",
    "best day of their lives", "best day of your life", "fairytale", "fairy tale", "soulmate",
    "soulmates", "magical", "dream wedding", "said yes", "say yes",
]
COMMERCIAL = ["reservez", "reserve ta date", "reservez votre date", "dernieres dates", "derniere date",
              "contactez-moi", "contacte-moi", "n'hesitez pas", "n'hesite pas", "promotion", "promo ",
              "code promo", "book now", "dm me", "contact me", "last dates", "limited availability",
              "lien en bio", "link in bio"]
COMMERCIAL_DOUTEUX = ["offre", "offres", "tarif", "tarifs", "disponibilites", "disponible", "availability"]
INCITATIONS = ["dites-moi en commentaire", "dis-moi en commentaire", "en commentaire", "double tap",
               "team ", "enregistre ce post", "enregistrez ce post", "sauvegarde ce post",
               "tag someone", "identifie", "save this post", "comment below", "tell me in the comments"]
MOTS_DU_PROMPT = r"\b(elegant|elegante|elegants|elegantes|elegance|intemporel|intemporelle|intemporels|" \
                 r"intemporelles|editorial|editoriale|editoriales|editoriaux|authentique|authentiques|" \
                 r"authenticite|luxe|luxueux|luxueuse|luxueuses|bold|sophistique|sophistiquee|" \
                 r"sophistiques|sophistiquees|sophistication|timeless|authentic|authenticity|luxury|" \
                 r"luxurious|sophisticated)\b"
TICS = [
    (r"[—–]", "tiret cadratin ou demi-cadratin"),
    (r"plus qu'un mariage|more than a wedding", "« plus qu'un mariage »"),
    (r"\b(ce n'est pas|ce n'etait pas|it's not|it is not|it was not)\b[^.\n]{0,60}\b(c'est|c'etait|it's|it is|it was)\b",
     "tournure « ce n'est pas X, c'est Y »"),
    (r"il y a des moments qui|there are moments", "« il y a des moments qui… »"),
]
SUPERLATIFS = ["magnifique", "magnifiques", "sublime", "sublimes", "incroyable", "incroyables",
               "parfait", "parfaite", "parfaits", "exceptionnel", "exceptionnelle", "extraordinaire",
               "absolument", "tellement", "stunning", "breathtaking", "amazing", "incredible",
               "perfect", "gorgeous", "le plus beau", "la plus belle"]
HASHTAGS_GENERIQUES = {
    "#love", "#wedding", "#mariage", "#weddingphotographer", "#instawedding", "#bride", "#weddingday",
    "#weddinginspiration", "#photography", "#photooftheday", "#instagood", "#mariee", "#weddingphotography",
    "#photographe", "#photographer", "#couple", "#weddingdress", "#instalove", "#happy", "#beautiful",
    "#amour", "#photo", "#weddings", "#bridetobe", "#engaged", "#weddingideas",
}
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]")
LIGNE_CREDIT = re.compile(r"^[^@#\n]{1,40}\s@[A-Za-z0-9._]{1,30}\s*$")
HASHTAG = re.compile(r"#[^\s#@]+")
MENTION = re.compile(r"@([A-Za-z0-9._]{1,30})")


def decouper_legende(legende: str) -> dict:
    """Sépare corps, crédits et hashtags."""
    lignes = legende.split("\n")
    corps, credits, tags = [], [], []
    zone = "corps"
    for ligne in lignes:
        s = ligne.strip()
        if zone == "corps" and (LIGNE_CREDIT.match(s) or (s and HASHTAG.sub("", s).strip() == "")):
            zone = "fin"
        if zone == "corps":
            corps.append(ligne)
        elif s:
            if LIGNE_CREDIT.match(s):
                credits.append(s)
            else:
                tags.extend(HASHTAG.findall(s))
    texte = "\n".join(corps).strip()
    return {"corps": texte, "credits": credits, "hashtags": tags,
            "tous_hashtags": HASHTAG.findall(legende), "mentions": MENTION.findall(legende)}


def classer_longueur(corps: str) -> str:
    n = len(corps)
    phrases = len([p for p in re.split(r"[.!?…]+\s", corps + " ") if p.strip()])
    if n <= 90 and phrases <= 1:
        return "silencieuse"
    if n <= 650:
        return "courte"
    return "recit"


def analyser_legende(legende: str, longueur_declaree: str = None, langue: str = "fr") -> tuple:
    erreurs, avert = [], []
    parts = decouper_legende(legende)
    corps = parts["corps"]
    bas = sans_accents(corps)

    def chercher(liste, libelle, niveau):
        for terme in liste:
            if re.search(r"(?<![a-z])" + re.escape(terme.strip()) + r"(?![a-z])", bas):
                niveau.append(f"{libelle} : « {terme.strip()} »")

    chercher(CLICHES, "Cliché interdit", erreurs)
    chercher(COMMERCIAL, "Ton commercial", erreurs)
    chercher(COMMERCIAL_DOUTEUX, "Mot commercial possible (seulement si prévu dans les consignes)", avert)
    chercher(INCITATIONS, "Incitation artificielle", erreurs)
    chercher(SUPERLATIFS, "Superlatif (préférer la retenue)", avert)
    for m in sorted(set(re.findall(MOTS_DU_PROMPT, bas))):
        erreurs.append(f"Mot du prompt écrit tel quel : « {m} » (le faire ressentir, pas l'écrire)")
    for motif, libelle in TICS:
        if re.search(motif, bas if "[" not in motif else corps):
            erreurs.append(f"Tic d'écriture : {libelle}")
    if EMOJI.search(legende):
        erreurs.append("Emoji interdit")
    if "!!" in corps:
        erreurs.append("Points d'exclamation en série")
    elif "!" in corps:
        avert.append("Point d'exclamation : à garder seulement s'il est juste")
    hors_citations = re.sub(r"«[^»]*»|\"[^\"]*\"|“[^”]*”", "", corps)
    if "?" in hors_citations:
        erreurs.append("Question dans la légende (questions rhétoriques interdites)")
    if re.search(r"\bentre (l'|le |la |les |)\w+ et (l'|le |la |les |)\w+", bas):
        avert.append("Tournure « entre X et Y » : vérifier que ce n'est pas une opposition abstraite")
    if re.search(r" - ", corps):
        avert.append("Tiret isolé utilisé comme ponctuation : reformuler")
    capitales = [w for w in re.findall(r"\b[A-ZÀ-Ý]{4,}\b", corps)]
    if capitales:
        avert.append("Majuscules d'emphase : " + ", ".join(sorted(set(capitales))[:5]))
    if len(legende) > MAX_LEGENDE:
        erreurs.append(f"Légende trop longue : {len(legende)} caractères (max {MAX_LEGENDE})")
    if len(parts["mentions"]) > MAX_MENTIONS:
        erreurs.append(f"Trop de mentions @ : {len(parts['mentions'])} (max {MAX_MENTIONS})")
    tags = parts["tous_hashtags"]
    if len(tags) > MAX_HASHTAGS:
        erreurs.append(f"Trop de hashtags : {len(tags)} (max {MAX_HASHTAGS})")
    generiques = [t for t in tags if t.lower() in HASHTAGS_GENERIQUES]
    if generiques:
        erreurs.append("Hashtags génériques : " + ", ".join(generiques))
    if len(tags) != len(parts["hashtags"]):
        erreurs.append("Hashtags à placer tout à la fin, après les crédits")
    reel = classer_longueur(corps)
    if longueur_declaree and longueur_declaree != reel:
        avert.append(f"Longueur déclarée « {longueur_declaree} » mais le texte ressemble à « {reel} »")
    premiere = corps.split("\n")[0].strip()
    if len(premiere) > 140:
        avert.append("Première phrase longue : elle doit tenir seule (c'est souvent la seule lue)")
    return erreurs, avert, {**parts, "longueur_mesuree": reel, "caracteres": len(legende)}


# --------------------------------------------------------------------------- feed

def centree_couple(p: dict) -> bool:
    if "centree_couple" in p:
        return bool(p["centree_couple"])
    return p.get("pilier") == "LOVE_STORY" or (p.get("fiche_feed") or {}).get("sujet") == "couple"


def creneau(jour_iso: str, cfg: dict = None):
    cfg = cfg or config.compte()
    creneaux = (cfg.get("publication") or {}).get("creneaux") or {}
    nom = config.JOURS_FR[dt.date.fromisoformat(jour_iso).weekday()]
    return creneaux.get(nom)


def etat_feed(hist: list = None, cfg: dict = None) -> dict:
    hist = config.historique() if hist is None else hist
    cfg = cfg or config.compte()
    derniers = hist[-9:]
    dernier = hist[-1] if hist else None
    c = {}
    if dernier:
        c["pilier_interdit"] = dernier.get("pilier")
        c["serie_interdite"] = dernier.get("serie")
        c["couverture_precedente"] = dernier.get("fiche_feed")
        c["regle_couverture"] = "différer d'au moins 2 critères (tonalité, luminosité, plan, sujet)"
    tons = [(p.get("fiche_feed") or {}).get("tonalite") for p in hist[-2:]]
    if len(tons) == 2 and tons[0] and tons[0] == tons[1]:
        c["tonalite_imposee"] = "couleur" if tons[0] == "nb" else "nb"
    longs = [p.get("longueur_legende") for p in hist[-2:]]
    if len(longs) == 2 and longs[0] and longs[0] == longs[1]:
        c["longueur_interdite"] = longs[0]
    fenetre8 = hist[-7:]
    c["publications_couple_possibles"] = max(0, 3 - sum(1 for p in fenetre8 if centree_couple(p)))
    fenetre10 = hist[-9:]
    vus = {p.get("pilier") for p in fenetre10}
    c["piliers_absents_recemment"] = [x for x in PILIERS if x not in vus]
    reels = [i for i, p in enumerate(reversed(hist)) if p.get("format") == "reel"]
    ecart = reels[0] if reels else 99
    ratio = float((cfg.get("publication") or {}).get("part_reels", 0.25))
    if ecart == 0:
        c["reel"] = "a_eviter (le dernier post est un Reel)"
    elif ecart + 1 >= round(1 / max(ratio, 0.05)):
        c["reel"] = "conseille"
    else:
        c["reel"] = "possible"
    nb = sum(1 for p in hist[-10:] if (p.get("fiche_feed") or {}).get("tonalite") == "nb")
    c["equilibre_10_derniers"] = {"nb": nb, "couleur": len(hist[-10:]) - nb}
    return {
        "derniers": [{k: p.get(k) for k in ("date", "format", "pilier", "serie", "longueur_legende", "fiche_feed", "titre")}
                     for p in derniers],
        "contraintes": c,
    }


def _comparer_couverture(a: dict, b: dict) -> int:
    return sum(1 for k in VALEURS if (a or {}).get(k) != (b or {}).get(k))


def valider_post(post: dict, hist: list = None, cfg: dict = None, catalogue: dict = None) -> dict:
    """Contrôle final (point 12 du prompt) + limites techniques de l'API."""
    hist = config.historique() if hist is None else list(hist)
    # on ne se compare pas à soi-même si le post du jour est déjà dans l'historique
    hist = [h for h in hist if not (h.get("jour") and h.get("jour") == post.get("jour"))]
    cfg = cfg or config.compte()
    E, A = [], []
    fmt = post.get("format")
    if fmt not in FORMATS:
        E.append(f"Format inconnu : {fmt}")
    if post.get("pilier") not in PILIERS:
        E.append(f"Pilier inconnu : {post.get('pilier')}")
    for s in post.get("piliers_secondaires") or []:
        if s not in PILIERS or s == post.get("pilier"):
            E.append(f"Pilier secondaire invalide : {s}")
    fiche = post.get("fiche_feed") or {}
    for k, vals in VALEURS.items():
        if fiche.get(k) not in vals:
            E.append(f"fiche_feed.{k} invalide : {fiche.get(k)}")
    if post.get("longueur_legende") not in LONGUEURS:
        E.append("longueur_legende invalide")

    # ---- alternance avec l'historique
    precedent = hist[-1] if hist else None
    if precedent:
        if precedent.get("pilier") == post.get("pilier"):
            E.append(f"Même pilier que la publication précédente ({post.get('pilier')})")
        if precedent.get("serie") and precedent.get("serie") == post.get("serie"):
            E.append("Même série que la publication précédente")
        diff = _comparer_couverture(precedent.get("fiche_feed"), fiche)
        if diff < 2:
            E.append(f"Couverture trop proche de la précédente ({diff} critère(s) différent(s), 2 requis)")
    tons = [(p.get("fiche_feed") or {}).get("tonalite") for p in hist[-2:]] + [fiche.get("tonalite")]
    if len(tons) == 3 and len(set(tons)) == 1:
        E.append(f"Troisième couverture de suite en « {tons[0]} »")
    longs = [p.get("longueur_legende") for p in hist[-2:]] + [post.get("longueur_legende")]
    if len(longs) == 3 and len(set(longs)) == 1:
        E.append(f"Troisième légende « {longs[0]} » de suite")
    fen = hist[-7:] + [post]
    if sum(1 for p in fen if centree_couple(p)) > 3:
        A.append("Plus de 3 publications centrées sur le couple sur les 8 dernières")
    fen10 = hist[-9:] + [post]
    if len(fen10) >= 10 and len({p.get("pilier") for p in fen10}) < 5:
        A.append("Moins de 5 piliers différents sur les 10 dernières publications")
    nb = sum(1 for p in fen10 if (p.get("fiche_feed") or {}).get("tonalite") == "nb")
    if len(fen10) >= 8 and not (0.3 <= nb / len(fen10) <= 0.7):
        A.append(f"Équilibre N&B / couleur à surveiller ({nb} N&B sur {len(fen10)})")
    if fmt == "reel" and precedent and precedent.get("format") == "reel":
        A.append("Deux Reels de suite")

    # ---- médias
    medias = post.get("medias") or []
    deja = {m.get("photo_id") or m.get("fichier") for h in hist for m in h.get("medias", [])}
    deja |= set(cfg.get("images_deja_publiees") or [])
    if fmt == "carrousel":
        if len(medias) < 2:
            E.append("Un carrousel demande au moins 2 médias")
        if len(medias) > MAX_MEDIAS_EDITORIAL:
            E.append(f"{len(medias)} médias : la règle éditoriale fixe 10 au maximum")
        if 2 <= len(medias) < 6:
            A.append(f"Carrousel court ({len(medias)} images) : à justifier dans l'intention")
    if fmt == "image" and len(medias) != 1:
        E.append("Le format image demande exactement 1 média")
    if fmt == "reel":
        r = post.get("reel") or {}
        if not medias and not r.get("plan_de_montage"):
            E.append("Reel sans vidéo ni plan de montage")
        for plan in r.get("plan_de_montage") or []:
            if str(plan.get("fichier")) in deja:
                E.append(f"Plan {plan.get('ordre')} du Reel : image déjà publiée ({plan.get('fichier')})")
        duree = r.get("duree_totale_s") or 0
        if duree and not 15 <= duree <= 45:
            A.append(f"Durée de Reel inhabituelle : {duree} s (15 à 45 s conseillées)")
        if not r.get("direction_sonore"):
            E.append("Reel sans direction sonore")
    vues = set()
    par_id = {p["id"]: p for p in (catalogue or {}).get("photos", [])}
    empreinte_prec = None
    for i, m in enumerate(sorted(medias, key=lambda x: x.get("ordre", 0))):
        ident = str(m.get("photo_id") or m.get("fichier"))
        est_video = str(m.get("type", "")).lower() == "video" or ident.endswith(".mp4")
        if ident in vues:
            E.append(f"Média {i + 1} en double")
        vues.add(ident)
        if ident in deja and not est_video:
            E.append(f"Média {i + 1} déjà publié ({ident})")
        if m.get("role") not in ROLES:
            E.append(f"Média {i + 1} : rôle invalide ({m.get('role')})")
        if m.get("rotation") not in (None, 0, 90, 180, 270):
            E.append(f"Média {i + 1} : rotation à choisir parmi 0, 90, 180 ou 270")
        if not est_video:
            if m.get("presentation") not in PRESENTATIONS:
                E.append(f"Média {i + 1} : présentation à choisir (plein_cadre ou marges)")
            if m.get("presentation") == "plein_cadre" and m.get("ancrage") not in ANCRAGES:
                E.append(f"Média {i + 1} : ancrage invalide")
            if not m.get("texte_alternatif"):
                E.append(f"Média {i + 1} : texte alternatif manquant")
        p = par_id.get(ident)
        if p:
            if p.get("orientation") == "paysage" and m.get("presentation") == "plein_cadre":
                A.append(f"Média {i + 1} : image horizontale recadrée en 4:5, vérifier qu'elle garde ce qu'elle raconte")
            e = (p.get("mesures") or {}).get("empreinte")
            if empreinte_prec and e:
                from .images import distance
                if distance(e, empreinte_prec) <= 8:
                    A.append(f"Médias {i} et {i + 1} très proches (même scène, même cadrage)")
            empreinte_prec = e
    if medias:
        premier = sorted(medias, key=lambda x: x.get("ordre", 0))[0]
        if premier.get("role") != "ouverture":
            A.append("Le premier média devrait avoir le rôle « ouverture »")

    # ---- légende et comptes
    leg = post.get("legende") or ""
    e2, a2, info = analyser_legende(leg, post.get("longueur_legende"))
    E += e2
    A += a2
    declares = [h for h in (post.get("hashtags") or [])]
    if sorted(x.lower() for x in declares) != sorted(x.lower() for x in info["tous_hashtags"]):
        E.append("Le champ hashtags ne reprend pas exactement les hashtags de la légende")
    connus = set()
    try:
        s = config.serie(post.get("serie"))
        connus = {str(x.get("compte")).lstrip("@").lower() for x in s.get("prestataires", []) if x.get("compte")}
        maries = s.get("maries") or {}
        if maries.get("prenoms") and not maries.get("prenoms_publiables"):
            for prenom in re.split(r"\s*(?:&|,|\bet\b|\band\b)\s*", maries["prenoms"]):
                if prenom and re.search(r"\b" + re.escape(prenom.strip()) + r"\b", leg, re.I):
                    E.append(f"Prénom « {prenom.strip()} » non publiable")
        if post.get("localisation") and s.get("lieu") and post["localisation"] != s.get("lieu"):
            A.append("Localisation différente du lieu fourni pour la série")
    except Exception:
        A.append("Série introuvable dans config/galeries.yaml : comptes non vérifiables")
    connus |= {str(x).lstrip("@").lower() for x in (cfg.get("comptes_autorises") or [])}
    moi = str(cfg.get("compte_instagram", "")).lstrip("@").lower()
    connus.add(moi)
    for compte in info["mentions"]:
        if compte.lower() not in connus:
            E.append(f"Compte @{compte} absent des données (prestataires de la série)")
    collab = post.get("collaborateurs") or []
    if len(collab) > MAX_COLLABORATEURS:
        E.append(f"Trop de collaborateurs ({len(collab)}, max {MAX_COLLABORATEURS})")
    for c in collab:
        if str(c).lstrip("@").lower() not in connus:
            E.append(f"Collaborateur {c} absent des données")
    for i, m in enumerate(medias):
        for t in m.get("identifications") or []:
            compte = (t.get("compte") if isinstance(t, dict) else t) or ""
            if compte.lstrip("@").lower() not in connus:
                E.append(f"Média {i + 1} : identification {compte} absente des données")

    # ---- musique
    mus = post.get("musique") or {}
    if mus.get("mode") and mus["mode"] not in MODES_MUSIQUE:
        E.append(f"Mode musique inconnu : {mus.get('mode')}")
    if fmt == "reel" and mus.get("mode") == "a_ajouter_dans_l_app":
        A.append("Reel : la musique peut être ajoutée automatiquement (mode api_reel)")

    # ---- créneau
    if post.get("date"):
        prevu = creneau(post["date"], cfg)
        if prevu is None:
            A.append("Pas de créneau prévu ce jour-là dans config/compte.yaml")
        elif post.get("heure") and post["heure"] != prevu:
            A.append(f"Heure {post.get('heure')} différente du créneau prévu ({prevu})")
    alertes = post.get("alertes") or []
    return {"erreurs": E, "avertissements": A, "alertes": alertes,
            "conforme": not E, "legende": {k: info[k] for k in ("caracteres", "longueur_mesuree", "credits")}}
