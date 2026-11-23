#!/bin/bash
# Installe ou met à jour le dossier de travail du Studio Instagram.
#
#   bash installer.sh [--si-besoin] [--sans-cloudflared] [--sans-app] [dossier]
#
# dossier            : dossier de travail (par défaut ~/Studio-Instagram)
# --si-besoin        : ne fait rien si le dossier est déjà à la version du plugin
# --sans-cloudflared : ne télécharge pas l'outil d'adresse temporaire
# --sans-app         : ne construit pas l'app Mac (les pages web prennent le relais)
# STUDIO_APP_DIR     : dossier où placer l'app (par défaut ~/Applications)
#
# Le moteur, la copie du plugin (.plugin), la charte d'origine, les docs et CLAUDE.md sont
# rafraîchis à chaque mise à jour. Les réglages et les données (config/, memoire/, catalogue/,
# jours/, donnees/, .env) ne sont jamais écrasés ; les sources de l'app personnalisées dans
# le studio (app/) sont conservées.
set -e
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SI_BESOIN=0; SANS_CF=0; SANS_APP=0; DOSSIER=""; EMBARQUE=""
for a in "$@"; do
  case "$a" in
    --embarque=*) EMBARQUE="${a#--embarque=}" ;;   # lancé par l'app installée (.pkg) : son Python, pas de compilation
    --si-besoin) SI_BESOIN=1 ;;
    --sans-cloudflared) SANS_CF=1 ;;
    --sans-app) SANS_APP=1 ;;
    *) DOSSIER="$a" ;;
  esac
done
DOSSIER="${DOSSIER:-$HOME/Studio-Instagram}"
VERSION="$(cat "$PLUGIN/moteur/VERSION")"

app_prete() {  # l'app indiquée dans .ui/app.json existe, ou l'app a été écartée volontairement
  [ -f "$DOSSIER/.ui/sans-app" ] && return 0
  "$DOSSIER/.venv/bin/python" -c 'import json,os,sys; p=json.load(open(sys.argv[1])).get("app") or ""; sys.exit(0 if os.path.isdir(p) else 1)' \
    "$DOSSIER/.ui/app.json" 2>/dev/null
}

if [ "$SI_BESOIN" = 1 ] && [ -x "$DOSSIER/.venv/bin/python" ] && \
   [ "$(cat "$DOSSIER/moteur/VERSION" 2>/dev/null)" = "$VERSION" ] && \
   [ -f "$DOSSIER/.plugin/.claude-plugin/plugin.json" ] && app_prete; then
  echo "Studio à jour (version $VERSION) : $DOSSIER"
  exit 0
fi

mkdir -p "$DOSSIER"
DOSSIER="$(cd "$DOSSIER" && pwd)"
echo "== Studio Instagram $VERSION : $DOSSIER =="

# 1. Moteur, charte d'origine, docs, instructions : toujours la version du plugin
rm -rf "$DOSSIER/moteur"
cp -R "$PLUGIN/moteur" "$DOSSIER/moteur"
find "$DOSSIER/moteur" -name "__pycache__" -type d -prune -exec rm -rf {} +
cp "$PLUGIN/studio" "$PLUGIN/requirements.txt" "$PLUGIN/METHODE.md" "$DOSSIER/"
chmod +x "$DOSSIER/studio"
mkdir -p "$DOSSIER/prompt" "$DOSSIER/docs"
cp "$PLUGIN/prompt/"*.md "$DOSSIER/prompt/"
cp "$PLUGIN/docs/"*.md "$DOSSIER/docs/"
cp "$PLUGIN/modeles/CLAUDE.md" "$DOSSIER/CLAUDE.md"
cp "$PLUGIN/modeles/.env.example" "$DOSSIER/.env.example"

# Copie du plugin dans le studio : Claude, lancé sans fenêtre par l'app, la charge avec --plugin-dir.
if [ "$PLUGIN" != "$DOSSIER/.plugin" ]; then
  rm -rf "$DOSSIER/.plugin.nouveau"
  mkdir -p "$DOSSIER/.plugin.nouveau"
  ( cd "$PLUGIN" && tar --exclude ".git" --exclude "__pycache__" --exclude ".DS_Store" -cf - . ) | \
    ( cd "$DOSSIER/.plugin.nouveau" && tar -xf - )
  rm -rf "$DOSSIER/.plugin"
  mv "$DOSSIER/.plugin.nouveau" "$DOSSIER/.plugin"
fi

# 2. Réglages et mémoire : seulement s'ils n'existent pas encore
copier_si_absent() {
  if [ ! -e "$DOSSIER/$1" ]; then
    mkdir -p "$(dirname "$DOSSIER/$1")"
    cp "$PLUGIN/modeles/$1" "$DOSSIER/$1"
  fi
}
for f in config/compte.yaml config/galeries.yaml config/app.yaml memoire/gouts.md memoire/apprentissages.md \
         musique/LISEZMOI.md .gitignore .claude/settings.json; do
  copier_si_absent "$f"
done
[ -f "$DOSSIER/.env" ] || cp "$PLUGIN/modeles/.env.example" "$DOSSIER/.env"
chmod 600 "$DOSSIER/.env"
mkdir -p "$DOSSIER/catalogue" "$DOSSIER/jours" "$DOSSIER/donnees" "$DOSSIER/outils" "$DOSSIER/.ui"

# 3. La charte que suit Claude : config/charte.md, modifiable dans l'app.
#    Tant que la photographe ne l'a pas modifiée, elle suit les mises à jour du plugin ;
#    une fois personnalisée, elle n'est plus jamais remplacée (l'app signale les nouveautés).
BASE="$DOSSIER/prompt/directeur-artistique.md"
CHARTE="$DOSSIER/config/charte.md"
REF="$DOSSIER/config/.charte-base.sha256"
empreinte() { shasum -a 256 "$1" | cut -d' ' -f1; }
if [ ! -f "$CHARTE" ] || { [ -f "$REF" ] && [ "$(empreinte "$CHARTE")" = "$(tr -d '[:space:]' < "$REF")" ]; }; then
  cp "$BASE" "$CHARTE"
  empreinte "$BASE" > "$REF"
fi

# 4. Python (Pillow, requests, PyYAML, ffmpeg) dans .venv
PY="$(command -v python3 || true)"
if [ -n "$EMBARQUE" ]; then
  PY="$EMBARQUE/Contents/Resources/python/bin/python3"     # Python livré dans l'app, avec ses paquets
fi
if [ -z "$PY" ]; then
  echo "Python 3 est introuvable. Lance d'abord : xcode-select --install"
  exit 1
fi
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' || {
  echo "Python 3.9 ou plus récent est nécessaire."; exit 1; }
if [ -n "$EMBARQUE" ]; then
  # Le Python de l'app contient déjà Pillow, requests, PyYAML et ffmpeg : rien à télécharger.
  if [ ! -x "$DOSSIER/.venv/bin/python" ] || ! "$DOSSIER/.venv/bin/python" -c 'import PIL, yaml' 2>/dev/null; then
    rm -rf "$DOSSIER/.venv"
    "$PY" -m venv --system-site-packages --without-pip "$DOSSIER/.venv"
  fi
else
  [ -x "$DOSSIER/.venv/bin/python" ] || "$PY" -m venv "$DOSSIER/.venv"
  "$DOSSIER/.venv/bin/python" -m pip install --quiet --upgrade pip
  "$DOSSIER/.venv/bin/python" -m pip install --quiet -r "$DOSSIER/requirements.txt"
fi

# Règles d'autorisation de Claude dans le studio : celles du plugin s'ajoutent à celles de la
# photographe (aucune n'est retirée).
"$DOSSIER/.venv/bin/python" - "$PLUGIN/modeles/.claude/settings.json" "$DOSSIER/.claude/settings.json" <<'FUSION'
import json, sys
modele, cible = sys.argv[1], sys.argv[2]
m = json.load(open(modele, encoding="utf-8"))
try:
    c = json.load(open(cible, encoding="utf-8"))
except (OSError, ValueError):
    c = {}
perm = c.setdefault("permissions", {})
change = False
for cle in ("allow", "deny"):
    liste = perm.setdefault(cle, [])
    for r in m.get("permissions", {}).get(cle, []):
        if r not in liste:
            liste.append(r)
            change = True
if change:
    with open(cible, "w", encoding="utf-8") as fh:
        json.dump(c, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
FUSION

# Sources de l'app propres à ce studio (personnalisables par Claude, skill studio-app).
if ! "$DOSSIER/studio" app synchroniser-sources "$PLUGIN/app" > "$DOSSIER/.ui/synchro-app.json"; then
  echo "(sources de l'app non synchronisées : voir .ui/synchro-app.json)"
fi
"$DOSSIER/.venv/bin/python" - "$DOSSIER/.ui/synchro-app.json" <<'CONFLITS'
import json, sys
try:
    r = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)
if r.get("conflits_en_attente"):
    print("! Personnalisations de l'app à fusionner avec la nouvelle version (demande à Claude : "
          "« fusionne les personnalisations de l'app ») : " + ", ".join(r["conflits_en_attente"]))
CONFLITS

# 5. cloudflared : adresse temporaire au moment de publier
if [ "$SANS_CF" = 0 ] && [ ! -x "$DOSSIER/outils/cloudflared" ]; then
  if [ "$(uname -m)" = "arm64" ]; then F=cloudflared-darwin-arm64.tgz; else F=cloudflared-darwin-amd64.tgz; fi
  if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$F" -o "$DOSSIER/outils/cloudflared.tgz"; then
    tar -xzf "$DOSSIER/outils/cloudflared.tgz" -C "$DOSSIER/outils" && rm -f "$DOSSIER/outils/cloudflared.tgz"
    chmod +x "$DOSSIER/outils/cloudflared"
  else
    echo "(cloudflared non téléchargé : la publication pourra passer par Supabase, voir docs/connexion-instagram.md)"
  fi
fi

# 6. L'app Mac « Studio Instagram », construite ici à partir des sources du plugin
if [ -n "$EMBARQUE" ] && [ -d "$EMBARQUE" ]; then
  APP="$EMBARQUE"                                      # l'app est déjà installée : on l'enregistre seulement
fi
if [ "$SANS_APP" = 1 ]; then
  touch "$DOSSIER/.ui/sans-app"
elif [ -n "$EMBARQUE" ] || { CONSTRUIRE="$DOSSIER/app/construire.sh"; { [ -f "$CONSTRUIRE" ] || CONSTRUIRE="$PLUGIN/app/construire.sh"; } && \
     APP="$(bash "$CONSTRUIRE" "${STUDIO_APP_DIR:-$HOME/Applications}" | tail -1)" && [ -d "$APP" ]; }; then
  rm -f "$DOSSIER/.ui/sans-app"
  # Le studio sait où est l'app ; l'app sait quel dossier afficher.
  "$DOSSIER/.venv/bin/python" - "$APP" "$DOSSIER" <<'PY'
import json, pathlib, sys
app, dossier = sys.argv[1], sys.argv[2]
pathlib.Path(dossier, ".ui", "app.json").write_text(json.dumps({"app": app}, ensure_ascii=False, indent=2))
f = pathlib.Path.home() / "Library" / "Application Support" / "Studio Instagram" / "reglages.json"
f.parent.mkdir(parents=True, exist_ok=True)
d = json.loads(f.read_text()) if f.exists() else {}
d["dossier"] = dossier
f.write_text(json.dumps(d, ensure_ascii=False, indent=2))
PY
  echo "App prête : $APP"
else
  echo "(app non construite : les idées et l'aperçu s'afficheront en pages web ; voir docs/depannage.md)"
fi

echo
"$DOSSIER/studio" verifier --rapide || true
echo
echo "Dossier prêt : $DOSSIER"
