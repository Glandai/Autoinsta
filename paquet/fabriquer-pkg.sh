#!/bin/bash
# Fabrique l'installateur Mac « Studio Instagram » (.pkg) : un double-clic l'installe dans Applications,
# sans Claude, sans commande et sans outils de développement sur le Mac de destination.
#
#   bash paquet/fabriquer-pkg.sh [dossier de sortie]     (défaut : paquet/sortie)
#
# Ce qu'il faut sur le Mac qui FABRIQUE le paquet : les outils de développement d'Apple (swiftc,
# pkgbuild, productbuild) et Internet (Python autonome et paquets PyPI, vérifiés par empreinte).
# L'app embarque : son moteur (le plugin), un Python 3.12 autonome avec Pillow, requests, PyYAML et
# ffmpeg. Au premier lancement, elle crée elle-même le dossier de travail ~/Studio-Instagram.
set -euo pipefail
export COPYFILE_DISABLE=1          # pas de fichiers « ._* » (attributs étendus) dans les copies

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$ICI/../plugins/studio-instagram" && pwd)"
SORTIE="${1:-$ICI/sortie}"
VERSION="$(tr -d '[:space:]' < "$PLUGIN/moteur/VERSION")"
IDENT="fr.atelier-photo.studio-instagram"
NOM="Studio Instagram.app"

# Python autonome (Apple Silicon) : astral-sh/python-build-standalone, vérifié par SHA256.
PY_VERSION="3.12.16"
PY_DATE="20261110"
PY_FICHIER="cpython-${PY_VERSION}+${PY_DATE}-aarch64-apple-darwin-install_only.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_DATE}/cpython-${PY_VERSION}%2B${PY_DATE}-aarch64-apple-darwin-install_only.tar.gz"
# Empreinte officielle (fichier SHA256SUMS de la publication 20261110), recopiée ici : la vérification ne dépend pas du réseau.
PY_SHA256="e956e60bc9465d577ef8062059aa05cd3a2665b4b8678a2ed24e432368330b8f"

if [ "$(uname -m)" != "arm64" ]; then
  echo "Ce paquet vise les Mac Apple Silicon : fabrique-le sur un Mac Apple Silicon." >&2
  exit 2
fi

TRAVAIL="$(mktemp -d)"
trap 'rm -rf "$TRAVAIL"' EXIT
RACINE="$TRAVAIL/racine"
mkdir -p "$RACINE" "$SORTIE"

echo "1/5 Compilation de l'app…" >&2
APP="$(bash "$PLUGIN/app/construire.sh" "$RACINE" | tail -1)"
[ -d "$APP" ] || { echo "La compilation de l'app a échoué." >&2; exit 1; }
RES="$APP/Contents/Resources"

echo "2/5 Python autonome et paquets…" >&2
CACHE="$ICI/.cache"
mkdir -p "$CACHE"
if [ ! -f "$CACHE/$PY_FICHIER" ]; then
  curl -fsSL -o "$CACHE/$PY_FICHIER.part" "$PY_URL"
  mv "$CACHE/$PY_FICHIER.part" "$CACHE/$PY_FICHIER"
fi
ATTENDU="$PY_SHA256"
OBTENU="$(shasum -a 256 "$CACHE/$PY_FICHIER" | awk '{print $1}')"
if [ -z "$ATTENDU" ] || [ "$ATTENDU" != "$OBTENU" ]; then
  echo "Empreinte du Python téléchargé incorrecte : fabrication arrêtée." >&2
  exit 1
fi
tar -xzf "$CACHE/$PY_FICHIER" -C "$RES"                 # → Contents/Resources/python
"$RES/python/bin/python3" -I -m pip install --quiet --disable-pip-version-check --no-warn-script-location \
  -r "$PLUGIN/requirements.txt"
# Allègement : tests, IDLE, Tk et caches ne servent pas au studio.
rm -rf "$RES/python/lib/python3.12/test" "$RES/python/lib/python3.12/idlelib" \
       "$RES/python/lib/python3.12/tkinter" "$RES/python/lib/python3.12/turtledemo" \
       "$RES/python/lib/tcl"* "$RES/python/lib/tk"* "$RES/python/share"
find "$RES/python" -name "__pycache__" -type d -prune -exec rm -rf {} +
"$RES/python/bin/python3" -I -c "import PIL, yaml, requests, imageio_ffmpeg" \
  || { echo "Le Python embarqué est incomplet." >&2; exit 1; }

echo "3/5 Moteur du studio (plugin)…" >&2
mkdir -p "$RES/plugin"
( cd "$PLUGIN" && tar --exclude ".git" --exclude "__pycache__" --exclude ".DS_Store" --exclude "tests" -cf - . ) \
  | ( cd "$RES/plugin" && tar -xf - )

echo "4/5 Signature locale…" >&2
# Copie propre, sans attributs étendus ni quarantaine (sinon des fichiers « ._* » entrent dans le paquet).
PROPRE="$TRAVAIL/propre"
mkdir -p "$PROPRE"
ditto --norsrc --noextattr --noqtn "$APP" "$PROPRE/$NOM"
chmod -R u+w "$PROPRE"
codesign --force --deep --sign - "$PROPRE/$NOM" >/dev/null 2>&1 || true
RACINE="$PROPRE"

echo "5/5 Paquet d'installation…" >&2
# L'app s'installe toujours dans /Applications (jamais « déplacée » vers une ancienne copie ailleurs).
cat > "$TRAVAIL/composants.plist" <<COMPOSANTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
  <key>BundleHasStrictIdentifier</key><true/>
  <key>BundleIsRelocatable</key><false/>
  <key>BundleIsVersionChecked</key><false/>
  <key>BundleOverwriteAction</key><string>upgrade</string>
  <key>RootRelativeBundlePath</key><string>$NOM</string>
</dict></array></plist>
COMPOSANTS
pkgbuild --root "$RACINE" --component-plist "$TRAVAIL/composants.plist" --install-location /Applications \
  --identifier "$IDENT" --version "$VERSION" "$TRAVAIL/studio-app.pkg" >"$TRAVAIL/pkgbuild.log" 2>&1 \
  || { cat "$TRAVAIL/pkgbuild.log" >&2; exit 1; }
mkdir -p "$TRAVAIL/ressources"
cp "$ICI/bienvenue.html" "$ICI/conclusion.html" "$TRAVAIL/ressources/"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@IDENT@/$IDENT/g" "$ICI/distribution.xml" > "$TRAVAIL/distribution.xml"
FINAL="$SORTIE/Studio-Instagram-$VERSION.pkg"
productbuild --distribution "$TRAVAIL/distribution.xml" --resources "$TRAVAIL/ressources" \
  --package-path "$TRAVAIL" "$FINAL" >"$TRAVAIL/productbuild.log" 2>&1 \
  || { cat "$TRAVAIL/productbuild.log" >&2; exit 1; }
echo "$FINAL"
