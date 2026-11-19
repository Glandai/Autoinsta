#!/bin/bash
# Installe ou met à jour le dossier de travail du Studio Instagram.
#
#   bash installer.sh [--si-besoin] [--sans-cloudflared] [dossier]
#
# dossier            : dossier de travail (par défaut ~/Studio-Instagram)
# --si-besoin        : ne fait rien si le dossier est déjà à la version du plugin
# --sans-cloudflared : ne télécharge pas l'outil d'adresse temporaire
#
# Le moteur, la charte, les docs et CLAUDE.md sont rafraîchis à chaque mise à jour.
# Les réglages et les données (config/, memoire/, catalogue/, jours/, donnees/, .env)
# ne sont jamais écrasés.
set -e
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SI_BESOIN=0; SANS_CF=0; DOSSIER=""
for a in "$@"; do
  case "$a" in
    --si-besoin) SI_BESOIN=1 ;;
    --sans-cloudflared) SANS_CF=1 ;;
    *) DOSSIER="$a" ;;
  esac
done
DOSSIER="${DOSSIER:-$HOME/Studio-Instagram}"
VERSION="$(cat "$PLUGIN/moteur/VERSION")"

if [ "$SI_BESOIN" = 1 ] && [ -x "$DOSSIER/.venv/bin/python" ] && \
   [ "$(cat "$DOSSIER/moteur/VERSION" 2>/dev/null)" = "$VERSION" ]; then
  echo "Studio à jour (version $VERSION) : $DOSSIER"
  exit 0
fi

mkdir -p "$DOSSIER"
DOSSIER="$(cd "$DOSSIER" && pwd)"
echo "== Studio Instagram $VERSION : $DOSSIER =="

# 1. Moteur, charte, docs, instructions : toujours la version du plugin
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

# 2. Réglages et mémoire : seulement s'ils n'existent pas encore
copier_si_absent() {
  if [ ! -e "$DOSSIER/$1" ]; then
    mkdir -p "$(dirname "$DOSSIER/$1")"
    cp "$PLUGIN/modeles/$1" "$DOSSIER/$1"
  fi
}
for f in config/compte.yaml config/galeries.yaml memoire/gouts.md memoire/apprentissages.md \
         musique/LISEZMOI.md .gitignore .claude/settings.json; do
  copier_si_absent "$f"
done
[ -f "$DOSSIER/.env" ] || cp "$PLUGIN/modeles/.env.example" "$DOSSIER/.env"
chmod 600 "$DOSSIER/.env"
mkdir -p "$DOSSIER/catalogue" "$DOSSIER/jours" "$DOSSIER/donnees" "$DOSSIER/outils"

# 3. Python (Pillow, requests, PyYAML, ffmpeg) dans .venv
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "Python 3 est introuvable. Lance d'abord : xcode-select --install"
  exit 1
fi
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' || {
  echo "Python 3.9 ou plus récent est nécessaire."; exit 1; }
[ -x "$DOSSIER/.venv/bin/python" ] || "$PY" -m venv "$DOSSIER/.venv"
"$DOSSIER/.venv/bin/python" -m pip install --quiet --upgrade pip
"$DOSSIER/.venv/bin/python" -m pip install --quiet -r "$DOSSIER/requirements.txt"

# 4. cloudflared : adresse temporaire au moment de publier
if [ "$SANS_CF" = 0 ] && [ ! -x "$DOSSIER/outils/cloudflared" ]; then
  if [ "$(uname -m)" = "arm64" ]; then F=cloudflared-darwin-arm64.tgz; else F=cloudflared-darwin-amd64.tgz; fi
  if curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/$F" -o "$DOSSIER/outils/cloudflared.tgz"; then
    tar -xzf "$DOSSIER/outils/cloudflared.tgz" -C "$DOSSIER/outils" && rm -f "$DOSSIER/outils/cloudflared.tgz"
    chmod +x "$DOSSIER/outils/cloudflared"
  else
    echo "(cloudflared non téléchargé : la publication pourra passer par Supabase, voir docs/connexion-instagram.md)"
  fi
fi

echo
"$DOSSIER/studio" verifier --rapide || true
echo
echo "Dossier prêt : $DOSSIER"
