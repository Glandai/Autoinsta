#!/usr/bin/env python3
"""Faux binaire Claude Code pour les tests du studio : aucun réseau, aucun compte.

Variables : FAUX_CONNECTE=0 (non connecté), FAUX_MODE=ok|non_connecte|limite|lent|session_inconnue,
FAUX_PAUSE (secondes entre deux événements), FAUX_TRACE (fichier où noter les appels).
"""
import json
import os
import sys
import time

args = sys.argv[1:]
trace = os.environ.get("FAUX_TRACE")
if trace:
    with open(trace, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(args, ensure_ascii=False) + "\n")

if args[:1] == ["--version"]:
    print("9.9.9 (Claude Code)")
    sys.exit(0)
if args[:2] == ["auth", "status"]:
    etat = os.environ.get("FAUX_ETAT")
    connecte = os.environ.get("FAUX_CONNECTE", "1") == "1" or bool(etat and os.path.exists(etat))
    print(json.dumps({"loggedIn": connecte, "authMethod": "claude.ai" if connecte else "none"}))
    sys.exit(0)
if args[:2] == ["auth", "login"]:
    print("Opening browser to sign in…", flush=True)
    print("If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?faux=1", flush=True)
    print("Paste code here if prompted > ", end="", flush=True)
    code = sys.stdin.readline().strip()
    if code == "bon-code#etat" and os.environ.get("FAUX_ETAT"):
        open(os.environ["FAUX_ETAT"], "w").close()
        print("Login successful.")
        sys.exit(0)
    print("OAuth error: Invalid code")
    sys.exit(1)
if args[:2] == ["auth", "logout"]:
    sys.exit(0)
if "-p" not in args:
    print("commande inconnue : " + " ".join(args), file=sys.stderr)
    sys.exit(2)

if any(k.upper().startswith("CLAUDE") for k in os.environ):
    print("variables CLAUDE héritées d'une session parente", file=sys.stderr)
    sys.exit(3)
for opt in ("--output-format", "--plugin-dir", "--permission-mode", "--append-system-prompt", "--allowedTools"):
    if opt not in args:
        print("option manquante : " + opt, file=sys.stderr)
        sys.exit(4)
if os.environ.get("STUDIO_APP") != "1":
    print("STUDIO_APP absent", file=sys.stderr)
    sys.exit(5)

prompt = sys.stdin.read()
mode = os.environ.get("FAUX_MODE", "ok")
pause = float(os.environ.get("FAUX_PAUSE", "0.02"))
session = args[args.index("--resume") + 1] if "--resume" in args else args[args.index("--session-id") + 1]


def emit(o):
    print(json.dumps(o, ensure_ascii=False), flush=True)
    time.sleep(pause)


if mode == "session_inconnue" and "--resume" in args:
    print("No conversation found with session ID: " + session, file=sys.stderr)
    sys.exit(1)
if mode == "non_connecte":
    emit({"type": "result", "subtype": "success", "is_error": True, "result": "Not logged in · Please run /login"})
    sys.exit(1)
if mode == "limite":
    emit({"type": "system", "subtype": "init", "session_id": session, "model": "faux"})
    emit({"type": "result", "subtype": "error_during_execution", "is_error": True,
          "result": "You've hit your usage limit · resets 6am"})
    sys.exit(1)

emit({"type": "system", "subtype": "init", "session_id": session, "model": "faux-modele"})
emit({"type": "assistant", "message": {"content": [
    {"type": "text", "text": "Je commence par relire la charte du studio. Ensuite les photos."},
    {"type": "tool_use", "name": "Read", "input": {"file_path": "config/charte.md"}}]}})
emit({"type": "user", "message": {"content": [{"type": "tool_result", "content": "texte", "is_error": False}]}})
for i in range(3):
    emit({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Read", "input": {"file_path": "catalogue/portfolio/vignettes/%d.jpg" % i}}]}})
emit({"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Bash", "input": {"command": "./studio planches portfolio"}}]}})
emit({"type": "user", "message": {"content": [
    {"type": "tool_result", "content": "Permission to use Bash has been denied", "is_error": True}]}})
if "studio-creation" in prompt:
    emit({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Write", "input": {"file_path": "jours/2026-11-19/post.json"}}]}})
    emit({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Bash", "input": {"command": "./studio valider 2026-11-19"}}]}})
if mode == "lent":
    time.sleep(60)
emit({"type": "assistant", "message": {"content": [{"type": "text", "text": "Le post est prêt. Il t'attend dans l'app."}]}})
emit({"type": "result", "subtype": "success", "is_error": False, "result": "Le post est prêt. Il t'attend dans l'app.",
      "total_cost_usd": 0.1234, "session_id": session})
sys.exit(0)
