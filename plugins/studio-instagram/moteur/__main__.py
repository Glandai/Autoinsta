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

    a = sp.add_parser("musique", help="musique du post : tendances, recherche (avec extraits)")
    a.add_argument("action", choices=["chercher", "tendances", "humeurs"])
    a.add_argument("requete", nargs="?")

    a = sp.add_parser("publier", help="publier un post approuvé")
    a.add_argument("jour")
    a.add_argument("--simulation", action="store_true")
    a = sp.add_parser("publier-dus", help="publier tout ce qui est approuvé et dont l'heure est passée")
    a.add_argument("--simulation", action="store_true")
    a.add_argument("--auto", action="store_true", help="lancé par la planification : notifications macOS")
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
    a = sp.add_parser("ui", help="ouvrir l'app Studio Instagram sur un écran (et attendre la décision)")
    a.add_argument("ecran")
    a.add_argument("--jour")
    a.add_argument("--attendre", action="store_true")
    a.add_argument("--delai", type=float)
    a.add_argument("--forcer", action="store_true", help="passer au premier plan même si l'ouverture automatique est désactivée")
    a = sp.add_parser("app", help="échanges avec l'app Studio Instagram (JSON)")
    a.add_argument("action")
    a.add_argument("arguments", nargs="*")
    sp.add_parser("taches", help="(1.x) tâches planifiées de l'app Claude demandées par les réglages")
    a = sp.add_parser("claude", help="Claude Code sans fenêtre : statut, connexion, exécutions")
    a.add_argument("action", choices=["statut", "installer", "connecter", "code", "deconnecter", "lancer", "executer",
                                      "etat", "annuler", "historique", "nouvelle-conversation"])
    a.add_argument("cible", nargs="?", help="tâche à lancer (matin, creation, retouche, galerie, bilan, demande) "
                                            "ou identifiant d'exécution")
    a.add_argument("--jour")
    a.add_argument("--serie")
    a.add_argument("--consigne")
    a.add_argument("--id")
    a.add_argument("--console", action="store_true", help="connexion par la Console Anthropic (facturation API)")
    a.add_argument("--attendre", action="store_true")
    a.add_argument("--auto", action="store_true")
    a = sp.add_parser("planifier", help="tâches automatiques du Mac (launchd)")
    g = a.add_mutually_exclusive_group()
    g.add_argument("--etat", action="store_true")
    g.add_argument("--activer", action="store_true")
    g.add_argument("--desactiver", action="store_true")
    g.add_argument("--appliquer", action="store_true")

    args = p.parse_args(argv)
    if not args.cmd:
        p.print_help()
        return 0
    try:
        return executer(args) or 0
    except ErreurStudio as e:
        sortie({"erreur": str(e)})
        return 2
    except Exception as e:  # l'app attend toujours une réponse JSON
        sortie({"erreur": f"Erreur interne ({e.__class__.__name__}) : {e}"})
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
        from . import musique
        if args.action == "tendances":
            return sortie(musique.tendances())
        if args.action == "humeurs":
            return sortie(musique.humeurs())
        return sortie(musique.chercher(args.requete or ""))
    if c == "publier":
        from . import publication
        return sortie(publication.publier(args.jour, simulation=args.simulation))
    if c == "publier-dus":
        from . import publication
        if not args.auto:
            return sortie(publication.publier_dus(simulation=args.simulation))
        from . import planification
        try:
            r = publication.publier_dus(simulation=args.simulation)
        except Exception as e:
            planification.notifier_echec_publication(e)
            raise
        planification.notifier_publications(r if isinstance(r, list) else (r or {}).get("resultats"))
        return sortie(r)
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
    if c == "ui":
        from . import app
        jour = args.jour or config.aujourdhui()
        r = app.ouvrir(args.ecran, jour, forcer=args.forcer)
        if not args.attendre:
            return sortie(r)
        if r["etat"] == "app_absente":
            sortie(r)
            return 4
        return sortie({"ouverture": r, "decision": app.attendre(jour, args.delai)})
    if c == "taches":
        from . import app
        return sortie(app.taches())
    if c == "claude":
        from . import claude
        a, cible = args.action, args.cible
        if a == "statut":
            return sortie(claude.statut())
        if a == "installer":
            return sortie(claude.installer())
        if a == "connecter":
            return sortie(claude.connecter(console=args.console))
        if a == "code":
            return sortie(claude.envoyer_code(cible or ""))
        if a == "deconnecter":
            return sortie(claude.deconnecter())
        if a == "lancer":
            if not cible:
                raise ErreurStudio("Indique la tâche : matin, creation, retouche, galerie, bilan ou demande.")
            r = claude.lancer(cible, jour=args.jour, serie=args.serie, consigne=args.consigne,
                              attendre=args.attendre, auto=args.auto)
            sortie(r)
            return 0 if r.get("etat") in ("lance", "termine") else (4 if r.get("etat") in ("absent", "non_connecte") else 1)
        if a == "executer":
            return sortie(claude.executer(cible or args.id))
        if a == "etat":
            return sortie(claude.etat(args.id or cible))
        if a == "annuler":
            return sortie(claude.annuler())
        if a == "historique":
            return sortie(claude.historique())
        return sortie(claude.nouvelle_conversation())
    if c == "planifier":
        from . import planification
        if args.activer:
            return sortie(planification.activer())
        if args.desactiver:
            return sortie(planification.desactiver())
        if args.appliquer:
            return sortie(planification.appliquer())
        return sortie(planification.etat())
    if c == "app":
        from . import app, sources
        x = args.arguments

        def arg(i, nom):
            if len(x) <= i:
                raise ErreurStudio(f"Argument manquant : {nom}")
            return x[i]

        table = {
            "jour": lambda: app.vue_jour(x[0] if x else None),
            "jours": app.vue_jours,
            "reglages": app.reglages,
            "enregistrer-reglages": lambda: app.enregistrer_reglages(arg(0, "fichier")),
            "galeries": app.galeries,
            "enregistrer-galerie": lambda: app.enregistrer_galerie(arg(0, "fichier")),
            "supprimer-galerie": lambda: app.supprimer_galerie(arg(0, "id")),
            "indexer-galerie": lambda: sources.indexer(arg(0, "id")),
            "charte": app.charte,
            "enregistrer-charte": lambda: app.enregistrer_charte(arg(0, "fichier")),
            "retablir-charte": app.retablir_charte,
            "regles": app.regles_vue,
            "enregistrer-regles": lambda: app.enregistrer_regles(arg(0, "fichier")),
            "retablir-regles": app.retablir_regles,
            "memoire": app.memoire,
            "enregistrer-memoire": lambda: app.enregistrer_memoire(arg(0, "nom"), arg(1, "fichier")),
            "sante": app.sante,
            "decider": lambda: app.decider(arg(0, "jour"), arg(1, "action"), x[2] if len(x) > 2 else None),
            "decision-traitee": lambda: app.decision_traitee(arg(0, "jour")),
            "attente": lambda: {"claude_attend": app.claude_attend(arg(0, "jour"))},
            "apparence": app.apparence,
            "archiver": lambda: app.archiver(arg(0, "jour")),
            "rouvrir-serie": lambda: app.rouvrir_serie(arg(0, "serie")),
            "ajouter-source": lambda: app.ajouter_source(arg(0, "fichier")),
            "exporter": lambda: app.exporter(arg(0, "jour"), x[1] if len(x) > 1 else None),
            "modifier-post": lambda: app.modifier_post(arg(0, "jour"), arg(1, "fichier")),
            "candidats": lambda: app.candidats_galerie(arg(0, "serie")),
            "instagram": app.instagram,
            "enregistrer-instagram": lambda: app.enregistrer_instagram(arg(0, "fichier")),
            "enregistrer-apparence": lambda: app.enregistrer_apparence(arg(0, "fichier")),
            "retablir-apparence": app.retablir_apparence,
            "synchroniser-sources": lambda: __import__("moteur.synchro", fromlist=["synchro"]).synchroniser_app(
                arg(0, "dossier"), config.chemin("app")),
        }
        if args.action not in table:
            raise ErreurStudio(f"Action inconnue pour l'app : {args.action}")
        return sortie(table[args.action]())
    raise ErreurStudio(f"Commande inconnue : {c}")


if __name__ == "__main__":
    sys.exit(main())
