"""Pages HTML de l'interface : « Idées du jour » et « Aperçu du post ».

Pages autonomes (images intégrées) : elles s'ouvrent dans le panneau de Claude,
dans un navigateur, ou se publient en Artifact privé pour les voir sur téléphone.
Les décisions se prennent dans Claude (boutons de choix) : la page sert à voir.
"""
import html
import re
from pathlib import Path

from . import config, images, regles, sources

E = html.escape

STYLE = """
:root{--papier:#f6f2ec;--surface:#fffdf9;--encre:#23251c;--doux:#6f6a60;--ligne:#e3dcd2;--olive:#3d4130;
--peche:#efdccd;--alerte:#a8551c;--alerte-fond:#fbeee2;--ok:#3f6b45;--ok-fond:#e8f0e6;--ombre:0 1px 2px rgba(35,37,28,.06),0 8px 24px rgba(35,37,28,.06)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--papier:#161613;--surface:#1f1f1b;--encre:#ece6dc;
--doux:#a49d90;--ligne:#34332d;--olive:#c9c2a3;--peche:#3a2f27;--alerte:#f0a066;--alerte-fond:#3a2a1f;--ok:#9cc59f;--ok-fond:#1f2c21;--ombre:none}}
:root[data-theme="dark"]{--papier:#161613;--surface:#1f1f1b;--encre:#ece6dc;--doux:#a49d90;--ligne:#34332d;--olive:#c9c2a3;
--peche:#3a2f27;--alerte:#f0a066;--alerte-fond:#3a2a1f;--ok:#9cc59f;--ok-fond:#1f2c21;--ombre:none}
*{box-sizing:border-box}html,body{margin:0}
body{background:var(--papier);color:var(--encre);font:15px/1.55 Inter,-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;
-webkit-font-smoothing:antialiased;padding:28px 16px 48px}
.cadre{max-width:1120px;margin:0 auto}
h1,h2,h3{font-family:"Cormorant Garamond","Cormorant",Garamond,"Times New Roman",serif;font-weight:500;letter-spacing:.01em;margin:0}
h1{font-size:40px;line-height:1.1}h2{font-size:27px;line-height:1.15}h3{font-size:19px;margin-bottom:10px}
.sur-titre{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--doux);margin-bottom:10px}
.chapo{color:var(--doux);max-width:640px;margin:10px 0 0}
img{display:block;max-width:100%}
.etiquettes{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 12px}
.etiquette{font-size:12px;padding:3px 9px;border:1px solid var(--ligne);border-radius:999px;color:var(--doux);background:var(--surface)}
.etiquette.forte{background:var(--olive);color:var(--papier);border-color:var(--olive)}
.etiquette.explo{background:var(--peche);color:var(--encre);border-color:transparent}
footer.pied{margin-top:28px;padding-top:18px;border-top:1px solid var(--ligne);color:var(--doux);font-size:14px}
.feed{display:flex;gap:6px;margin-top:18px;align-items:flex-end}
.feed img{width:54px;aspect-ratio:3/4;object-fit:cover;border-radius:2px}
.feed .leg{font-size:12px;color:var(--doux);margin-left:8px}
.contraintes{font-size:14px;color:var(--doux);margin:12px 0 0;max-width:720px}
/* idées */
.idees{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:20px;margin-top:28px}
.idee{background:var(--surface);border:1px solid var(--ligne);border-radius:6px;overflow:hidden;box-shadow:var(--ombre);display:flex;flex-direction:column;position:relative}
.idee .num{position:absolute;top:12px;left:12px;width:38px;height:38px;border-radius:50%;background:var(--surface);color:var(--encre);
display:grid;place-items:center;font:600 17px/1 Inter,-apple-system,sans-serif;box-shadow:0 1px 4px rgba(0,0,0,.18)}
@media (max-width:520px){h1{font-size:32px}h2{font-size:24px}body{padding:20px 16px 40px}}
.idee .couv{aspect-ratio:4/5;object-fit:cover;width:100%}
.vignettes{display:grid;grid-template-columns:repeat(3,1fr);gap:3px;padding:3px 3px 0}
.vignettes img{aspect-ratio:1;object-fit:cover;width:100%}
.idee .corps{padding:16px 18px 20px}
.idee h2{margin-bottom:8px}
.pitch{margin:0 0 12px}
.pourquoi,.son{font-size:13.5px;color:var(--doux);margin:6px 0 0}
.pourquoi b,.son b{color:var(--encre);font-weight:600}
.idee.libre{justify-content:center;padding:28px 22px;background:transparent;border-style:dashed;box-shadow:none}
.idee.libre .num{position:static;margin-bottom:14px}
/* aperçu */
.statut{display:inline-block;font-size:13px;font-weight:600;padding:4px 12px;border-radius:999px;margin-top:12px}
.statut.ok{background:var(--ok-fond);color:var(--ok)}.statut.ko{background:var(--alerte-fond);color:var(--alerte)}
.apercu{display:grid;grid-template-columns:minmax(300px,400px) 1fr;gap:32px;margin-top:26px;align-items:start}
@media (max-width:820px){.apercu{grid-template-columns:1fr}}
.tel{background:#fff;color:#0f0f0f;border:1px solid #dbdbdb;border-radius:14px;overflow:hidden;box-shadow:var(--ombre);
font:14px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif;max-width:400px;width:100%;margin:0 auto}
.tel .haut{display:flex;align-items:center;gap:10px;padding:10px 12px}
.avatar{width:34px;height:34px;border-radius:50%;background:#23251c;color:#f6f2ec;display:grid;place-items:center;font:600 12px/1 Inter,sans-serif;flex:none}
.tel .compte{font-weight:600}.tel .lieu{font-size:12px;color:#555}
.piste{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;background:#000}
.piste::-webkit-scrollbar{display:none}
.diapo{flex:0 0 100%;scroll-snap-align:center;margin:0;position:relative}
.diapo img{width:100%;aspect-ratio:4/5;object-fit:cover}
.diapo .compteur{position:absolute;top:10px;right:10px;background:rgba(0,0,0,.6);color:#fff;font-size:12px;padding:2px 8px;border-radius:999px}
.diapo video{width:100%;aspect-ratio:9/16;object-fit:cover;background:#000}
.tel .actions{display:flex;gap:14px;padding:10px 12px 4px}
.tel .actions svg{width:24px;height:24px}
.tel .musique{font-size:12.5px;color:#333;padding:2px 12px 6px}
.tel .legende{padding:4px 12px 14px;white-space:pre-wrap;word-wrap:break-word}
.tel details summary{color:#737373;cursor:pointer;list-style:none;display:inline}
.tel details summary::-webkit-details-marker{display:none}
.tel details[open] summary{display:none}
.bloc{background:var(--surface);border:1px solid var(--ligne);border-radius:6px;padding:16px 18px;margin-bottom:16px}
.bloc p{margin:0 0 8px}
.alertes li{color:var(--alerte)}.erreurs li{color:var(--alerte);font-weight:600}
.alertes ul,.erreurs ul{margin:0;padding-left:18px}
.grille{display:grid;grid-template-columns:repeat(3,1fr);gap:2px;max-width:330px}
.grille .case{aspect-ratio:3/4;background:var(--ligne);overflow:hidden;position:relative}
.grille .case img{width:100%;height:100%;object-fit:cover}
.grille .case.nouveau{outline:2px solid var(--olive);outline-offset:-2px}
.grille .case.nouveau span{position:absolute;bottom:4px;left:4px;background:var(--olive);color:var(--papier);font-size:10px;padding:1px 6px;border-radius:999px}
.sequence{list-style:none;margin:0;padding:0}
.sequence li{display:grid;grid-template-columns:52px 1fr;gap:12px;padding:8px 0;border-top:1px solid var(--ligne);font-size:13.5px}
.sequence li:first-child{border-top:0}
.sequence img{width:52px;aspect-ratio:4/5;object-fit:cover;border-radius:2px}
.sequence .role{font-weight:600}.sequence .alt{color:var(--doux)}
.fiche{display:grid;grid-template-columns:auto 1fr;gap:4px 14px;font-size:14px;margin:0}
.fiche dt{color:var(--doux)}.fiche dd{margin:0}
audio{width:100%;margin-top:6px}
"""

ICONES = """<div class="actions" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="#0f0f0f" stroke-width="1.8"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/></svg>
<svg viewBox="0 0 24 24" fill="none" stroke="#0f0f0f" stroke-width="1.8"><path d="M20 12a8 8 0 1 1-3.2-6.4L20 4v4.5"/></svg>
<svg viewBox="0 0 24 24" fill="none" stroke="#0f0f0f" stroke-width="1.8"><path d="M21 3 3 10l7 3 3 7 8-17z"/></svg>
<span style="flex:1"></span>
<svg viewBox="0 0 24 24" fill="none" stroke="#0f0f0f" stroke-width="1.8"><path d="M6 3h12v18l-6-4-6 4z"/></svg></div>"""

LIBELLE_PILIER = {"EDITORIAL": "Éditorial", "DOCUMENTARY": "Documentaire", "DETAILS": "Détails",
                  "PLACES": "Lieux", "PORTRAITS": "Portraits", "LOVE_STORY": "Love story",
                  "ATMOSPHERE": "Atmosphère", "ARTISTIC_VISION": "Vision artistique"}
LIBELLE_FORMAT = {"carrousel": "Carrousel", "image": "Image seule", "reel": "Reel"}
LIBELLE_ROLE = {"ouverture": "Ouverture", "progression": "Progression", "respiration": "Respiration",
                "surprise": "Surprise", "cloture": "Clôture"}


def _tete(titre: str) -> str:
    return ("<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            f"<title>{E(titre)}</title>"
            "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">"
            "<link href=\"https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;500;600&family=Inter:wght@400;500;600&display=swap\" rel=\"stylesheet\">"
            f"<style>{STYLE}</style></head><body><div class=\"cadre\">")


def _image_photo(serie_id: str, ident: str, largeur=640, ratio=None) -> str:
    try:
        p = sources.chemin_photo(serie_id, ident, hd=False)
        return images.data_uri(p, largeur_max=largeur, ratio=ratio, rotation=sources.rotation(serie_id, ident))
    except Exception:
        return ""


def _couvertures_recentes(n=8) -> list:
    res = []
    for h in reversed(config.historique()):
        f = config.chemin("donnees", "couvertures", f"{h.get('jour') or h.get('date')}.jpg")
        if f.exists():
            res.append((h, images.data_uri(f, largeur_max=240, ratio=3 / 4)))
        else:
            res.append((h, ""))
        if len(res) >= n:
            break
    return res


def _phrase_contraintes(etat: dict) -> str:
    c = etat.get("contraintes") or {}
    morceaux = []
    if c.get("couverture_precedente"):
        f = c["couverture_precedente"]
        morceaux.append(f"Dernier post : {LIBELLE_PILIER.get(c.get('pilier_interdit'), c.get('pilier_interdit'))}, "
                        f"couverture {f.get('tonalite')} · {f.get('luminosite')} · {f.get('plan')} · {f.get('sujet')}.")
    if c.get("tonalite_imposee"):
        morceaux.append(f"La prochaine couverture sera en {'noir et blanc' if c['tonalite_imposee'] == 'nb' else 'couleur'}.")
    return " ".join(morceaux)


# =========================================================================== idées du jour

def page_idees(jour: str) -> Path:
    d = config.dossier_jour(jour)
    data = config.lire_json(d / "idees.json")
    if not data:
        raise config.ErreurStudio("jours/%s/idees.json introuvable." % jour)
    cfg = config.compte()
    date = data.get("date") or jour
    heure = regles.creneau(date, cfg) or ""
    etat = regles.etat_feed()
    o = [_tete("Idées du jour")]
    o.append(f"<header><div class=\"sur-titre\">Studio Instagram · @{E(str(cfg.get('compte_instagram', '')).lstrip('@'))}</div>")
    o.append(f"<h1>{E(config.date_longue(date).capitalize())}</h1>")
    nb = len(data.get("idees", []))
    o.append(f"<p class=\"chapo\">{nb} idées pour le post{(' de ' + E(heure)) if heure else ''}. "
             "Choisis-en une dans Claude, ou décris la tienne : le post complet arrive ensuite, prêt à valider.</p>")
    recentes = _couvertures_recentes(6)
    if recentes:
        o.append("<div class=\"feed\">")
        for h, uri in reversed(recentes):
            o.append(f"<img src=\"{uri}\" alt=\"\" title=\"{E(h.get('date', ''))}\">" if uri else "")
        o.append("<span class=\"leg\">les derniers posts</span></div>")
    phrase = data.get("lecture_du_feed") or _phrase_contraintes(etat)
    if phrase:
        o.append(f"<p class=\"contraintes\">{E(phrase)}</p>")
    o.append("</header><main class=\"idees\">")
    for i, idee in enumerate(data.get("idees", []), 1):
        serie = idee.get("serie")
        couv = _image_photo(serie, idee.get("couverture"), 720, ratio=4 / 5) if idee.get("couverture") else ""
        o.append("<article class=\"idee\">")
        o.append(f"<div class=\"num\">{i}</div>")
        if couv:
            o.append(f"<img class=\"couv\" src=\"{couv}\" alt=\"Couverture envisagée\">")
        vign = [u for u in (_image_photo(serie, v, 300) for v in (idee.get("photos") or [])
                            if v != idee.get("couverture")) if u][:3]
        if vign:
            o.append("<div class=\"vignettes\">" + "".join(f"<img src=\"{u}\" alt=\"\">" for u in vign) + "</div>")
        o.append("<div class=\"corps\"><div class=\"etiquettes\">")
        fmt = LIBELLE_FORMAT.get(idee.get("format"), idee.get("format", ""))
        if idee.get("nb_medias"):
            fmt += f" · {idee['nb_medias']} photos"
        o.append(f"<span class=\"etiquette forte\">{E(fmt)}</span>")
        o.append(f"<span class=\"etiquette\">{E(LIBELLE_PILIER.get(idee.get('pilier'), idee.get('pilier', '')))}</span>")
        if idee.get("longueur_legende"):
            o.append(f"<span class=\"etiquette\">Légende {E(idee['longueur_legende'])}</span>")
        if idee.get("type") == "exploration":
            o.append("<span class=\"etiquette explo\">Exploration</span>")
        o.append("</div>")
        o.append(f"<h2>{E(idee.get('titre', ''))}</h2><p class=\"pitch\">{E(idee.get('pitch', ''))}</p>")
        if idee.get("pourquoi"):
            o.append(f"<p class=\"pourquoi\"><b>Pourquoi aujourd'hui.</b> {E(idee['pourquoi'])}</p>")
        if idee.get("musique"):
            o.append(f"<p class=\"son\"><b>Son.</b> {E(idee['musique'])}</p>")
        o.append("</div></article>")
    o.append("<article class=\"idee libre\"><div class=\"num\">+</div><h2>Ton idée</h2>"
             "<p class=\"pitch\">Écris-la simplement dans Claude : « les mains pendant les discours », "
             "« le carrousel de Barcelone », « plus de noir et blanc cette semaine »… Le studio s'occupe du reste.</p></article>")
    o.append("</main><footer class=\"pied\">Réponds dans Claude avec le numéro de l'idée ou ta propre idée. "
             "Rien n'est publié sans ton accord.</footer></div></body></html>")
    sortie = d / "idees.html"
    sortie.write_text("".join(o), encoding="utf-8")
    return sortie


# =========================================================================== aperçu du post

def _legende_html(legende: str) -> str:
    parts = legende.split("\n")
    tete = parts[0]
    reste = "\n".join(parts[1:])
    if len(tete) > 125:
        tete, reste = tete[:125], tete[125:] + ("\n" + reste if reste else "")
    corps = E(tete)
    if reste.strip():
        corps += f"<details><summary>… plus</summary>{E(reste)}</details>"
    return re.sub(r"(@[A-Za-z0-9._]+|#[^\s#<]+)", r'<span style="color:#00376b">\1</span>', corps)


def page_apercu(jour: str, verdict: dict = None) -> Path:
    d = config.dossier_jour(jour)
    post = config.lire_json(d / "post.json")
    if not post:
        raise config.ErreurStudio(f"jours/{jour}/post.json introuvable.")
    cfg = config.compte()
    verdict = verdict or regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie")))
    compte = str(cfg.get("compte_instagram", "")).lstrip("@") or "compte"
    medias = sorted(post.get("medias") or [], key=lambda m: m.get("ordre", 0))
    rendu = d / "rendu"
    o = [_tete("Aperçu du post")]
    prete = verdict["conforme"]
    o.append(f"<header><div class=\"sur-titre\">Studio Instagram · aperçu</div>"
             f"<h1>{E(post.get('titre') or config.date_longue(post.get('date') or jour).capitalize())}</h1>"
             f"<p class=\"chapo\">{E(config.date_longue(post.get('date', jour)).capitalize())}"
             f"{(' à ' + E(post['heure'])) if post.get('heure') else ''} · "
             f"{E(LIBELLE_FORMAT.get(post.get('format'), ''))} · {E(LIBELLE_PILIER.get(post.get('pilier'), ''))}</p>"
             f"<span class=\"statut {'ok' if prete else 'ko'}\">"
             f"{'Prêt à publier' if prete and not verdict.get('alertes') else 'Prêt, avec des points à vérifier' if prete else 'À corriger avant publication'}"
             f"</span></header>")
    o.append("<main class=\"apercu\"><section class=\"tel\">")
    collab = post.get("collaborateurs") or []
    ligne_compte = E(compte) + (f" <span style=\"font-weight:400\">et {E(', '.join(collab))}</span>" if collab else "")
    nom = str(cfg.get("nom") or compte)
    initiales = "".join(w[0] for w in re.split(r"[\s._-]+", nom) if w)[:2].upper()
    o.append(f"<div class=\"haut\"><div class=\"avatar\">{E(initiales)}</div>"
             f"<div><div class=\"compte\">{ligne_compte}</div>"
             f"<div class=\"lieu\">{E(post.get('localisation') or '')}</div></div></div>")
    o.append("<div class=\"piste\">")
    for i, m in enumerate(medias, 1):
        f = rendu / f"{i:02d}.jpg"
        uri = images.data_uri(f, 900, 82) if f.exists() else ""
        o.append(f"<figure class=\"diapo\"><img src=\"{uri}\" alt=\"{E(m.get('texte_alternatif') or '')}\">"
                 f"<span class=\"compteur\">{i}/{len(medias)}</span></figure>")
    o.append("</div>" + ICONES)
    mus = post.get("musique") or {}
    if mus.get("titre"):
        note = {"api_reel": "ajoutée automatiquement", "integree": "intégrée à la vidéo",
                "a_ajouter_dans_l_app": "à ajouter dans l'app après publication"}.get(mus.get("mode"), "")
        o.append(f"<div class=\"musique\">♫ {E(mus['titre'])}{(' · ' + E(mus['artiste'])) if mus.get('artiste') else ''}"
                 f"{(' (' + note + ')') if note else ''}</div>")
    o.append(f"<div class=\"legende\"><b>{E(compte)}</b> {_legende_html(post.get('legende') or '')}</div></section>")

    # ---------------------------------------------------------- colonne d'informations
    o.append("<aside>")
    if verdict["erreurs"]:
        o.append("<section class=\"bloc erreurs\"><h3>À corriger</h3><ul>" +
                 "".join(f"<li>{E(x)}</li>" for x in verdict["erreurs"]) + "</ul></section>")
    vigilance = list(verdict.get("alertes") or []) + list(verdict.get("avertissements") or [])
    if vigilance:
        o.append("<section class=\"bloc alertes\"><h3>À vérifier</h3><ul>" +
                 "".join(f"<li>{E(x)}</li>" for x in vigilance) + "</ul></section>")
    o.append(f"<section class=\"bloc\"><h3>L'intention</h3><p>{E(post.get('intention') or '')}</p>")
    if post.get("pourquoi"):
        o.append(f"<p style=\"color:var(--doux)\">{E(post['pourquoi'])}</p>")
    o.append("</section>")
    # grille
    o.append("<section class=\"bloc\"><h3>Dans la grille</h3><div class=\"grille\">")
    premiere = rendu / "01.jpg"
    uri = images.data_uri(premiere, 300, 80, ratio=3 / 4) if premiere.exists() else ""
    o.append(f"<div class=\"case nouveau\"><img src=\"{uri}\" alt=\"\"><span>nouveau</span></div>")
    recentes = _couvertures_recentes(8)
    for _, u in recentes:
        o.append(f'<div class="case"><img src="{u}" alt=""></div>' if u else '<div class="case"></div>')
    o.append('<div class="case"></div>' * (8 - len(recentes)))
    o.append("</div></section>")
    # fiche
    f = post.get("fiche_feed") or {}
    tags = ", ".join(post.get("hashtags") or []) or "aucun"
    o.append("<section class=\"bloc\"><h3>Fiche</h3><dl class=\"fiche\">"
             f"<dt>Couverture</dt><dd>{E(' · '.join(str(f.get(k, '')) for k in ('tonalite', 'luminosite', 'plan', 'sujet')))}</dd>"
             f"<dt>Légende</dt><dd>{E(post.get('longueur_legende') or '')} · {verdict['legende']['caracteres']} caractères</dd>"
             f"<dt>Hashtags</dt><dd>{E(tags)}</dd>"
             f"<dt>Collaborateurs</dt><dd>{E(', '.join(collab) or 'aucun')}</dd>"
             f"<dt>Série</dt><dd>{E(post.get('serie') or '')}</dd></dl></section>")
    # séquence
    o.append("<section class=\"bloc\"><h3>Séquence</h3><ol class=\"sequence\">")
    for i, m in enumerate(medias, 1):
        f2 = rendu / f"{i:02d}.jpg"
        u = images.data_uri(f2, 120, 70) if f2.exists() else ""
        ids = ", ".join((t.get("compte") if isinstance(t, dict) else t) for t in (m.get("identifications") or []))
        role = LIBELLE_ROLE.get(m.get("role"), m.get("role", ""))
        pres = ("module · " + str(m.get("module")).replace("_", " ")) if m.get("module") else \
            "plein cadre" if m.get("presentation") == "plein_cadre" else "sur fond" if m.get("presentation") == "marges" else ""
        o.append(f"<li><img src=\"{u}\" alt=\"\"><div><span class=\"role\">{i}. {E(role)}</span> · "
                 f"{E(pres)}{(' · identifie @' + E(ids)) if ids else ''}"
                 f"<div class=\"alt\">{E(m.get('texte_alternatif') or '')}</div></div></li>")
    o.append("</ol></section>")
    if mus:
        o.append("<section class=\"bloc\"><h3>Musique</h3>")
        if mus.get("titre"):
            o.append(f"<p>{E(mus['titre'])}{(' · ' + E(mus['artiste'])) if mus.get('artiste') else ''}</p>")
        if mus.get("direction_sonore"):
            o.append(f"<p style=\"color:var(--doux)\">{E(mus['direction_sonore'])}</p>")
        if mus.get("apercu_url"):
            o.append(f"<audio controls preload=\"none\" src=\"{E(mus['apercu_url'])}\"></audio>")
        if mus.get("mode") == "a_ajouter_dans_l_app":
            o.append("<p style=\"color:var(--doux);margin-top:8px\">L'API d'Instagram n'ajoute pas de musique aux "
                     "carrousels. Après publication : ouvre le post, ••• puis Modifier, puis Ajouter de la musique, "
                     "et cherche ce titre.</p>")
        o.append("</section>")
    o.append("</aside></main>")
    o.append("<footer class=\"pied\">Pour publier, réponds « Publier » dans Claude (au créneau prévu ou tout de suite). "
             "Pour changer quelque chose, décris-le simplement : une photo, l'ordre, la légende, la musique.</footer>")
    o.append("</div></body></html>")
    sortie = d / "apercu.html"
    sortie.write_text("".join(o), encoding="utf-8")
    return sortie
