"""Ligne de commande du studio :  ./studio <commande> [options]

Les résultats sont imprimés en JSON (lisibles par Claude), sauf « verifier ».
"""
import argparse
import json
import shutil
import sys

from . import config
from .config import ErreurStudio


def sortie(obj):
    print(json.dumps(obj, ensure_ascii=False, indent=2, default=str))


# --------------------------------------------------------------------------- vérification

def cmd_verifier(args):
    ok, bloquant = "✓", "✗"
    lignes, probleme = [], False
    cfg = config.compte()
    if not cfg:
        lignes.append(f"{bloquant} config/compte.yaml introuvable ou vide")
        probleme = True
    else:
        trous = []

        def chercher(obj, chemin=""):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    chercher(v, f"{chemin}.{k}" if chemin else str(k))
            elif isinstance(obj, list):
                for i, v in enumerate(obj):
                    chercher(v, f"{chemin}[{i}]")
            elif isinstance(obj, str) and "[À COMPLÉTER" in obj:
                trous.append(chemin)

        chercher(cfg)
        if trous:
            lignes.append(f"! Paramètres à compléter dans config/compte.yaml : {', '.join(trous)}")
        else:
            lignes.append(f"{ok} Paramètres du compte complets")
    series = config.series()
    lignes.append(f"{ok if series else '!'} {len(series)} série(s) dans config/galeries.yaml")
    from . import sources
    for s in sources.etat_series():
        lignes.append(f"   · {s['serie']} : {s['photos']} photos, {s['analysees']} analysées, "
                      f"{s['fortes_disponibles']} fortes encore jamais publiées")
    from .instagram import Instagram
    ig = Instagram()
    if args.rapide and not ig.pret():
        lignes.append("! Instagram non connecté (docs/connexion-instagram.md)")
    else:
        v = ig.verifier_jeton()
        if v.get("etat") == "valide":
            reste = v.get("jours_restants")
            alerte = reste is not None and reste <= 10
            lignes.append(f"{'!' if alerte else ok} Instagram connecté : @{v.get('compte')} ({v.get('abonnes')} abonnés), "
                          f"route {v['mode']}" + (f", jeton valable encore {reste} jours" if reste is not None else ""))
        elif v.get("etat") == "absent":
            lignes.append("! Instagram non connecté (docs/connexion-instagram.md)")
        else:
            lignes.append(f"{bloquant} Jeton Instagram invalide : {v.get('erreur')}")
            probleme = True
    heb = (cfg.get("publication") or {}).get("hebergement", "tunnel")
    if heb == "tunnel":
        present = config.chemin("outils", "cloudflared").exists() or shutil.which("cloudflared")
        lignes.append(f"{ok if present else bloquant} Hébergement temporaire : cloudflared {'présent' if present else 'absent'}")
        probleme |= not present
    else:
        env = config.secrets()
        present = env.get("SUPABASE_URL") and env.get("SUPABASE_SERVICE_KEY")
        lignes.append(f"{ok if present else bloquant} Hébergement temporaire : Supabase {'configuré' if present else 'à configurer'}")
        probleme |= not present
    try:
        from .reel import ffmpeg
        ffmpeg()
        lignes.append(f"{ok} ffmpeg disponible (Reels)")
    except ErreurStudio:
        lignes.append("! ffmpeg absent : les Reels ne pourront pas être montés")
    print("\n".join(lignes))
    return 1 if probleme else 0


# --------------------------------------------------------------------------- commandes

def main(argv=None):
    p = argparse.ArgumentParser(prog="./studio", description="Studio Instagram")
    sp = p.add_subparsers(dest="cmd")

    v = sp.add_parser("verifier", help="état de l'installation")
    v.add_argument("--rapide", action="store_true")

    pt = sp.add_parser("pictime", help="sources de photos")
    ptsp = pt.add_subparsers(dest="action")
    a = ptsp.add_parser("indexer")
    a.add_argument("serie")
    a.add_argument("--limite", type=int)
    a.add_argument("--forcer", action="store_true")
    a = ptsp.add_parser("telecharger")
    a.add_argument("serie")
    a.add_argument("ids", nargs="+")
    ptsp.add_parser("etat")
    a = ptsp.add_parser("analyser-lien")
    a.add_argument("url")

    a = sp.add_parser("planches", help="planches contact à analyser")
    a.add_argument("serie")
    a.add_argument("--par", type=int, default=20)
    a.add_argument("--toutes", action="store_true")
    a = sp.add_parser("noter", help="enregistrer l'analyse visuelle d'une série")
    a.add_argument("serie")
    a.add_argument("fichier")
    a = sp.add_parser("candidats", help="meilleures photos jamais publiées")
    a.add_argument("--serie")
    a.add_argument("--note-min", type=int, default=4)
    a.add_argument("-n", type=int, default=60)
    sp.add_parser("etat", help="état du feed et contraintes pour le prochain post")

    a = sp.add_parser("idees", help="enregistrer les idées du jour et fabriquer la page")
    a.add_argument("jour")
    a = sp.add_parser("choix", help="enregistrer le choix de la photographe")
    a.add_argument("jour")
    a.add_argument("numero", nargs="?", type=int)
    a.add_argument("--libre")
    a = sp.add_parser("rendre", help="mise en page 4:5 des images du post")
    a.add_argument("jour")
    a = sp.add_parser("valider", help="contrôle final du post")
    a.add_argument("jour")
    a = sp.add_parser("apercu", help="fabriquer la page d'aperçu")
    a.add_argument("jour")
    a = sp.add_parser("retouche", help="journaliser une demande de retouche")
    a.add_argument("jour")
    a.add_argument("demande")
    a = sp.add_parser("approuver", help="valider le post (publication au créneau ou maintenant)")
    a.add_argument("jour")
    a.add_argument("--quand", default="creneau", help="creneau | maintenant | HH:MM")
    a = sp.add_parser("statut", help="changer le statut d'une journée (reporte, abandonne)")
    a.add_argument("jour")
    a.add_argument("statut")

    a = sp.add_parser("musique", help="musique Instagram (API Audio)")
    a.add_argument("action", choices=["chercher"])
    a.add_argument("requete", nargs="?")
    a = sp.add_parser("reel", help="montage du Reel")
    a.add_argument("action", choices=["monter", "infos"])
    a.add_argument("jour")

    a = sp.add_parser("publier", help="publier un post approuvé")
    a.add_argument("jour")
    a.add_argument("--simulation", action="store_true")
    a = sp.add_parser("publier-dus", help="publier tout ce qui est approuvé et dont l'heure est passée")
    a.add_argument("--simulation", action="store_true")
    sp.add_parser("en-attente", help="brouillons pas encore validés")

    sp.add_parser("releve", help="relever les statistiques Instagram")
    sp.add_parser("analyse", help="synthèse : ce qui fonctionne, ce qui est à améliorer")
    a = sp.add_parser("historique", help="importer et classer les anciens posts")
    a.add_argument("action", choices=["importer", "planche", "noter"])
    a.add_argument("fichier", nargs="?")
    a.add_argument("--limite", type=int, default=30)
    a = sp.add_parser("jeton", help="jeton Instagram")
    a.add_argument("action", choices=["verifier", "renouveler", "echanger"])
    sp.add_parser("demo", help="démonstration hors ligne de toute la chaîne")

    args = p.parse_args(argv)
    if not args.cmd:
        p.print_help()
        return 0
    try:
        return executer(args) or 0
    except ErreurStudio as e:
        sortie({"erreur": str(e)})
        return 2


def executer(args):
    c = args.cmd
    if c == "verifier":
        return cmd_verifier(args)
    if c == "pictime":
        from . import sources
        if args.action == "indexer":
            return sortie(sources.indexer(args.serie, args.limite, args.forcer))
        if args.action == "telecharger":
            return sortie(sources.telecharger_hd(args.serie, args.ids))
        if args.action == "etat":
            return sortie(sources.etat_series())
        if args.action == "analyser-lien":
            info = sources.analyser_page(args.url)
            photos = sources.lire_manifeste(info)
            scenes = {}
            for ph in photos:
                scenes[ph["scene"]] = scenes.get(ph["scene"], 0) + 1
            return sortie({"titre": info["titre"], "photos": len(photos), "scenes": scenes,
                           "mises_en_avant": sum(1 for ph in photos if ph["mise_en_avant"])})
    if c == "planches":
        from . import sources
        return sortie({"planches": sources.planches(args.serie, args.par, not args.toutes)})
    if c == "noter":
        from . import sources
        return sortie(sources.noter(args.serie, args.fichier))
    if c == "candidats":
        from . import rendu
        return sortie(rendu.candidats(args.serie, args.note_min, args.n))
    if c == "etat":
        from . import journee, regles
        e = regles.etat_feed()
        e["en_attente"] = journee.en_attente()
        e["prochain_creneau_aujourdhui"] = regles.creneau(config.aujourdhui())
        return sortie(e)
    if c == "idees":
        from . import journee, pages
        r = journee.enregistrer_idees(args.jour)
        if r["erreurs"]:
            return sortie(r)
        return sortie({"page": str(pages.page_idees(args.jour).relative_to(config.RACINE)), **r})
    if c == "choix":
        from . import journee
        return sortie(journee.enregistrer_choix(args.jour, args.numero, args.libre))
    if c == "rendre":
        from . import rendu
        return sortie(rendu.rendre(args.jour))
    if c == "valider":
        from . import regles, sources
        post = config.lire_json(config.dossier_jour(args.jour) / "post.json")
        if not post:
            raise ErreurStudio("post.json absent.")
        post.setdefault("jour", args.jour)
        return sortie(regles.valider_post(post, catalogue=sources.lire_catalogue(post.get("serie"))))
    if c == "apercu":
        from . import journee, pages
        page = pages.page_apercu(args.jour)
        journee.maj(args.jour, "brouillon_pret")
        return sortie({"page": str(page.relative_to(config.RACINE))})
    if c == "retouche":
        from . import journee
        return sortie(journee.enregistrer_retouche(args.jour, args.demande))
    if c == "approuver":
        from . import journee
        return sortie(journee.approuver(args.jour, args.quand))
    if c == "statut":
        from . import journee
        return sortie(journee.maj(args.jour, args.statut))
    if c == "musique":
        from .instagram import Instagram
        return sortie(Instagram().chercher_musique(args.requete))
    if c == "reel":
        from . import reel
        if args.action == "monter":
            return sortie(reel.monter(args.jour))
        return sortie(reel.infos_video(config.dossier_jour(args.jour) / "rendu" / "reel.mp4"))
    if c == "publier":
        from . import publication
        return sortie(publication.publier(args.jour, simulation=args.simulation))
    if c == "publier-dus":
        from . import publication
        return sortie(publication.publier_dus(simulation=args.simulation))
    if c == "en-attente":
        from . import journee
        return sortie(journee.en_attente())
    if c == "releve":
        from . import analyse
        return sortie(analyse.releve())
    if c == "analyse":
        from . import analyse
        r = analyse.synthese()
        resume = {k: v for k, v in r.items() if k not in ("constats", "meilleures", "moins_bonnes")}
        resume["fichier"] = "memoire/performance.md"
        return sortie(resume)
    if c == "historique":
        from . import publication
        if args.action == "importer":
            return sortie(publication.importer_historique(args.limite))
        if args.action == "planche":
            return sortie(publication.planche_historique())
        if not args.fichier:
            raise ErreurStudio("Indique le fichier JSON des classements.")
        return sortie(publication.noter_historique(args.fichier))
    if c == "jeton":
        from .instagram import Instagram
        ig = Instagram()
        if args.action == "verifier":
            return sortie(ig.verifier_jeton())
        if args.action == "renouveler":
            return sortie(ig.rafraichir_jeton())
        return sortie(ig.echanger_jeton())
    if c == "demo":
        from . import demo
        return sortie(demo.lancer())
    raise ErreurStudio(f"Commande inconnue : {c}")


if __name__ == "__main__":
    sys.exit(main())
