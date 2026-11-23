"""Tests de bout en bout du moteur 2.0, avec un faux Claude (aucun réseau, aucun compte, aucune tâche du Mac).

    python3 tests/test_moteur.py            (installe un studio jetable : environ 30 secondes)
    STUDIO_TEST_DOSSIER=/chemin python3 tests/test_moteur.py   (réutilise un studio déjà installé)
"""
import json
import os
import shutil
import subprocess
import tempfile
import time
import sys
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent
FAUX = PLUGIN / "tests" / "faux_claude.py"


class TestMoteur(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="studio-test-"))
        cls.dossier = Path(os.environ.get("STUDIO_TEST_DOSSIER") or cls.tmp / "studio")
        if not (cls.dossier / "studio").exists():
            subprocess.run(["bash", str(PLUGIN / "installer.sh"), "--sans-cloudflared", "--sans-app", str(cls.dossier)],
                           check=True, capture_output=True)
        os.chmod(FAUX, 0o755)
        compte = cls.dossier / "config" / "compte.yaml"
        texte = compte.read_text(encoding="utf-8")
        if "faux_claude" not in texte:
            compte.write_text(texte + '\nclaude:\n  chemin: "%s"\n' % FAUX, encoding="utf-8")
        cls.env = {k: v for k, v in os.environ.items() if not k.startswith("FAUX_")}
        cls.env.update(STUDIO_LAUNCHAGENTS_DIR=str(cls.tmp / "agents"), STUDIO_SANS_LAUNCHCTL="1",
                       STUDIO_SANS_NOTIFICATION="1", FAUX_PAUSE="0", FAUX_TRACE=str(cls.tmp / "trace.jsonl"))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def studio(self, *args, env=None):
        e = dict(self.env, **(env or {}))
        r = subprocess.run([str(self.dossier / "studio")] + list(args), cwd=str(self.dossier), env=e,
                           capture_output=True, text=True, timeout=120)
        return json.loads(r.stdout), r.returncode

    def appels(self):
        f = self.tmp / "trace.jsonl"
        return [json.loads(l) for l in f.read_text().splitlines()] if f.exists() else []

    # ------------------------------------------------------------------ installation

    def test_installation(self):
        for rel in (".plugin/.claude-plugin/plugin.json", "app/.base.json", "config/app.yaml", "config/charte.md"):
            self.assertTrue((self.dossier / rel).exists(), rel)
        regles = json.loads((self.dossier / ".claude" / "settings.json").read_text())["permissions"]
        self.assertIn("Edit(./.plugin/**)", regles["deny"])
        self.assertIn("Bash(./studio:*)", regles["allow"])

    # ------------------------------------------------------------------ Claude

    def test_statut(self):
        s, _ = self.studio("claude", "statut")
        self.assertTrue(s["installe"] and s["connecte"] and s["plugin_present"])
        s, _ = self.studio("claude", "statut", env={"FAUX_CONNECTE": "0"})
        self.assertFalse(s["connecte"])
        self.assertIn("Se connecter", s["conseil"])

    def test_tache_complete_et_reprise_de_session(self):
        e, code = self.studio("claude", "lancer", "matin", "--jour", "2030-01-02", "--attendre")
        self.assertEqual((e["etat"], code), ("termine", 0))
        textes = [d["texte"] for d in e["etapes"]]
        self.assertIn("Je regarde les photos (3)", textes)
        self.assertTrue(all(d["fait"] for d in e["etapes"]))
        self.assertEqual(e["cout_usd"], 0.1234)
        e, _ = self.studio("claude", "lancer", "creation", "--jour", "2030-01-02", "--attendre")
        self.assertEqual(e["etat"], "termine")
        derniers = [a for a in self.appels() if "-p" in a][-2:]
        self.assertIn("--session-id", derniers[0])
        self.assertIn("--resume", derniers[1])
        self.assertEqual(derniers[0][derniers[0].index("--session-id") + 1],
                         derniers[1][derniers[1].index("--resume") + 1])

    def test_execution_detachee_et_verrou(self):
        r, _ = self.studio("claude", "lancer", "bilan", env={"FAUX_PAUSE": "0.3"})
        self.assertEqual(r["etat"], "lance")
        r2, _ = self.studio("claude", "lancer", "bilan")
        self.assertEqual(r2["etat"], "deja_en_cours")
        for _ in range(40):
            e, _ = self.studio("claude", "etat", "--id", r["id"])
            if e["etat"] not in ("en_attente", "en_cours"):
                break
            time.sleep(0.5)
        self.assertEqual(e["etat"], "termine")
        self.assertEqual(e["ecran_suivant"], "statistiques")

    def test_erreurs_traduites(self):
        e, _ = self.studio("claude", "lancer", "bilan", "--attendre", env={"FAUX_MODE": "limite"})
        self.assertEqual(e["etat"], "erreur")
        self.assertIn("limite d'utilisation", e["erreur"])
        r, code = self.studio("claude", "lancer", "matin", env={"FAUX_CONNECTE": "0"})
        self.assertEqual((r["etat"], code), ("non_connecte", 4))

    def test_reprise_impossible(self):
        self.studio("claude", "lancer", "matin", "--jour", "2030-01-03", "--attendre")
        e, _ = self.studio("claude", "lancer", "retouche", "--jour", "2030-01-03", "--consigne", "Plus court",
                           "--attendre", env={"FAUX_MODE": "session_inconnue"})
        self.assertEqual(e["etat"], "termine")

    def test_annulation(self):
        r, _ = self.studio("claude", "lancer", "galerie", "--serie", "x", env={"FAUX_MODE": "lent"})
        time.sleep(2)
        a, _ = self.studio("claude", "annuler")
        self.assertEqual(a["etat"], "annule")
        for _ in range(20):
            e, _ = self.studio("claude", "etat", "--id", r["id"])
            if e["etat"] != "en_cours":
                break
            time.sleep(0.5)
        self.assertEqual(e["etat"], "annule")

    def test_connexion_par_code(self):
        etat = str(self.tmp / "connecte")
        env = {"FAUX_CONNECTE": "0", "FAUX_ETAT": etat}
        r, _ = self.studio("claude", "connecter", env=env)
        self.assertEqual((r["etat"], r["code_attendu"]), ("navigateur_ouvert", True))
        r, _ = self.studio("claude", "code", "pas un code !", env=env)
        self.assertEqual(r["etat"], "refuse")
        r, _ = self.studio("claude", "code", "mauvais", env=env)
        self.assertEqual(r["etat"], "echec")
        r, _ = self.studio("claude", "code", "bon-code#etat", env=env)
        self.assertEqual(r["etat"], "expire")          # la tentative précédente est terminée
        self.studio("claude", "connecter", env=env)
        r, _ = self.studio("claude", "code", "bon-code#etat", env=env)
        self.assertEqual(r["etat"], "connecte")
        s, _ = self.studio("claude", "statut", env=env)
        self.assertTrue(s["connecte"])

    # ------------------------------------------------------------------ planification et apparence

    def test_planification(self):
        d, _ = self.studio("planifier", "--activer")
        self.assertTrue(d["active"])
        plists = sorted((self.tmp / "agents").glob("*.plist"))
        self.assertEqual(len(plists), 3)
        for p in plists:
            self.assertEqual(subprocess.run(["plutil", "-lint", str(p)], capture_output=True).returncode, 0)
        d, _ = self.studio("planifier", "--desactiver")
        self.assertFalse(d["active"])
        self.assertEqual(list((self.tmp / "agents").glob("*.plist")), [])

    def test_apparence(self):
        f = self.tmp / "a.json"
        f.write_text(json.dumps({"couleurs": {"accent": "#123"}, "arrondi": 99}))
        r, _ = self.studio("app", "enregistrer-apparence", str(f))
        self.assertEqual(r["etat"], "refuse")
        f.write_text(json.dumps({"mode": "sombre", "ecrans": ["idees"]}))
        r, _ = self.studio("app", "enregistrer-apparence", str(f))
        self.assertEqual(r["etat"], "enregistre")
        a, _ = self.studio("app", "apparence")
        self.assertEqual(a["mode"], "sombre")
        self.assertEqual(a["ecrans"], ["aujourdhui", "galeries", "statistiques", "reglages"])   # écrans essentiels fixes
        self.assertFalse(a["points"])                                                          # trame toujours coupée
        f.write_text(json.dumps({"ambiance": "humeur:0.250,0.800"}))           # nuancier d'humeur
        r, _ = self.studio("app", "enregistrer-apparence", str(f))
        self.assertEqual(r["etat"], "enregistre")
        a, _ = self.studio("app", "apparence")
        self.assertEqual(a["ambiance"], "humeur:0.250,0.800")
        f.write_text(json.dumps({"ambiance": "humeur:3,9"}))
        r, _ = self.studio("app", "enregistrer-apparence", str(f))
        self.assertEqual(r["etat"], "refuse")
        self.studio("app", "retablir-apparence")

    def test_modele_selon_la_tache(self):
        sys.path.insert(0, str(PLUGIN))
        from moteur import claude
        self.assertEqual(claude.modele_pour("creation", {}), "opus")
        self.assertEqual(claude.modele_pour("idees", {}), "opus")
        self.assertEqual(claude.modele_pour("retouche", {}), "sonnet")
        self.assertEqual(claude.modele_pour("galerie", {}), "sonnet")
        self.assertEqual(claude.modele_pour("galerie", {"modele": "opus"}), "opus")    # choix explicite

    # ------------------------------------------------------------------ mise en page

    def test_modules_plusieurs_photos(self):
        r, code = self.studio("demo")
        self.assertEqual(code, 0, r)
        self.assertTrue(r["verdict"]["conforme"], r["verdict"])
        self.assertTrue(any(d.get("photos") for d in r["rendu"]["details"]))      # la page en diptyque
        jour = Path(r["apercu"]).parent.name
        post = json.loads((self.dossier / "jours" / jour / "post.json").read_text())
        ids = [m["photo_id"] for m in sorted(post["medias"], key=lambda m: m["ordre"]) if not m.get("module")]
        f = self.tmp / "m.json"
        # réunir les pages 2 et 3 sur une même page, côte à côte
        f.write_text(json.dumps({"medias": [ids[0], {"photo_id": ids[1], "module": "diptyque", "photos": ids[1:3]}]
                                 + ids[3:6]}))
        r, code = self.studio("app", "modifier-post", jour, str(f))
        self.assertEqual(code, 0, r)
        post = json.loads((self.dossier / "jours" / jour / "post.json").read_text())
        self.assertEqual(len(post["medias"]), 5)
        self.assertEqual(post["medias"][1]["module"], "diptyque")
        self.assertEqual(post["medias"][-1]["role"], "cloture")
        self.assertTrue((self.dossier / "jours" / jour / "rendu" / "05.jpg").exists())
        # un module au mauvais nombre de photos est refusé
        f.write_text(json.dumps({"medias": [ids[0], {"photo_id": ids[1], "module": "grille", "photos": ids[1:3]}]}))
        r, code = self.studio("app", "modifier-post", jour, str(f))
        self.assertNotEqual(code, 0)
        # séparer : chaque photo redevient une page
        f.write_text(json.dumps({"medias": ids[:6]}))
        r, code = self.studio("app", "modifier-post", jour, str(f))
        post = json.loads((self.dossier / "jours" / jour / "post.json").read_text())
        self.assertEqual(len(post["medias"]), 6)
        self.assertFalse(any(m.get("module") for m in post["medias"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
