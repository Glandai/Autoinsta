#!/bin/bash
# Construit l'app Mac « Studio Instagram » à partir des sources voisines (app/Sources).
#
#   bash app/construire.sh              → ~/Applications/Studio Instagram.app
#   bash app/construire.sh <dossier>    → <dossier>/Studio Instagram.app
#
# Marche depuis le plugin comme depuis le dossier du studio (<studio>/app/construire.sh),
# quel que soit le dossier courant. Ne demande que les outils de développement d'Apple
# (ceux qui fournissent déjà python3) : xcode-select --install. Rien n'est téléchargé.
# Affiche le chemin de l'app construite sur la dernière ligne.
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RACINE="$(cd "$ICI/.." && pwd)"
DESTINATION="${1:-$HOME/Applications}"
NOM="Studio Instagram.app"
EXECUTABLE="StudioInstagram"
CIBLE_MACOS="14.0"

premier_fichier() {
  for f in "$@"; do
    if [ -f "$f" ]; then echo "$f"; return 0; fi
  done
  return 1
}

VERSION="$(tr -d '[:space:]' < "$(premier_fichier "$RACINE/moteur/VERSION" "$RACINE/.plugin/moteur/VERSION" || echo /dev/null)" 2>/dev/null || true)"
VERSION="${VERSION:-2.0.0}"

if ! ls "$ICI"/Sources/*.swift >/dev/null 2>&1; then
  echo "Sources de l'app introuvables dans $ICI/Sources." >&2
  exit 2
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Compilateur Swift introuvable : lance « xcode-select --install » puis recommence." >&2
  exit 3
fi

TRAVAIL="$(mktemp -d)"
trap 'rm -rf "$TRAVAIL"' EXIT
PAQUET="$TRAVAIL/$NOM"
mkdir -p "$PAQUET/Contents/MacOS" "$PAQUET/Contents/Resources"

# --------------------------------------------------------------------------- compilation
# SDK par défaut d'abord ; s'il échoue, les autres SDK installés, du plus récent au plus ancien.
compiler() {   # $1 : chemin d'un SDK, ou vide pour celui par défaut
  local sdk=()
  [ -n "$1" ] && sdk=(-sdk "$1")
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    ${sdk[@]+"${sdk[@]}"} \
    -target "$(uname -m)-apple-macos$CIBLE_MACOS" \
    -module-name StudioInstagram \
    "$ICI"/Sources/*.swift \
    -framework SwiftUI -framework AppKit -framework AVKit -framework Charts -framework UserNotifications \
    -o "$PAQUET/Contents/MacOS/$EXECUTABLE"
}

echo "Compilation de l'app (une à deux minutes)…" >&2
JOURNAL="$TRAVAIL/compilation.log"
if ! compiler "" >"$JOURNAL" 2>&1; then
  reussi=0
  ESSAYES="$(cd "$(xcrun --show-sdk-path 2>/dev/null || echo /)" 2>/dev/null && pwd -P || true)"
  # « 27.0 /chemin/MacOSX27.0.sdk » … trié par version décroissante ; chaque SDK réel n'est essayé qu'une fois.
  while IFS= read -r ligne; do
    sdk="${ligne#* }"
    reel="$(cd "$sdk" 2>/dev/null && pwd -P || true)"
    [ -z "$reel" ] && continue
    case $'\n'"$ESSAYES"$'\n' in *$'\n'"$reel"$'\n'*) continue ;; esac
    ESSAYES="$ESSAYES"$'\n'"$reel"
    echo "Nouvel essai avec $(basename "$reel")…" >&2
    if compiler "$reel" >"$TRAVAIL/essai.log" 2>&1; then reussi=1; break; fi
  done < <(for s in /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk \
                    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX[0-9]*.sdk; do
             [ -d "$s" ] || continue
             v="$(basename "$s" .sdk)"
             echo "${v#MacOSX} $s"
           done | sort -V -r)
  if [ "$reussi" = 0 ]; then
    echo "La compilation a échoué :" >&2
    grep -E "error:" "$JOURNAL" | head -20 >&2 || tail -30 "$JOURNAL" >&2
    exit 1
  fi
fi

# --------------------------------------------------------------------------- paquet
cp "$ICI/Info.plist" "$PAQUET/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PAQUET/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$PAQUET/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$CIBLE_MACOS" "$PAQUET/Contents/Info.plist"

# Ressources de l'app (images, polices…) : copiées dans Contents/Resources, sans les scripts ni les notes
# qui servent à les fabriquer. Les polices de app/Ressources/Polices (ou posées à la racine de
# Ressources) sont activées pour l'app.
if [ -d "$ICI/Ressources" ]; then
  ditto --norsrc "$ICI/Ressources" "$PAQUET/Contents/Resources"
  find "$PAQUET/Contents/Resources" \( -name .DS_Store -o -name '*.py' -o -name '*.sh' -o -name '*.md' \
       -o -name '*.swift' -o -name '__pycache__' \) -prune -exec rm -rf {} + 2>/dev/null || true
  if ls "$PAQUET/Contents/Resources/Polices/"*.[otOT][tT][fFcC] >/dev/null 2>&1; then
    plutil -replace ATSApplicationFontsPath -string "Polices" "$PAQUET/Contents/Info.plist"
  elif ls "$PAQUET/Contents/Resources/"*.[otOT][tT][fFcC] >/dev/null 2>&1; then
    plutil -replace ATSApplicationFontsPath -string "." "$PAQUET/Contents/Info.plist"
  fi
fi

# Icône : celle de l'app, sinon celle du plugin (dans le plugin, ou sa copie dans le studio).
ICONE="$(premier_fichier "$ICI/Ressources/icone.png" "$RACINE/.claude-plugin/icon.png" \
                         "$RACINE/.plugin/.claude-plugin/icon.png" || true)"
if [ -n "$ICONE" ]; then
  JEU="$TRAVAIL/AppIcon.iconset"
  mkdir -p "$JEU"
  for t in 16 32 128 256 512; do
    sips -s format png -z "$t" "$t" "$ICONE" --out "$JEU/icon_${t}x${t}.png" >/dev/null 2>&1 || true
    sips -s format png -z "$((t * 2))" "$((t * 2))" "$ICONE" --out "$JEU/icon_${t}x${t}@2x.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$JEU" -o "$PAQUET/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || echo "(icône non convertie : l'app gardera l'icône générique)" >&2
fi

# Signature locale (ad hoc) : suffisante pour une app construite sur ce Mac.
codesign --force --deep --sign - "$PAQUET" >/dev/null 2>&1 || true

# --------------------------------------------------------------------------- installation
mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd)"
# Seule l'app remplacée est fermée (pas une autre copie ouverte ailleurs) ; elle est rouverte après.
EN_COURS="$DESTINATION/$NOM/Contents/MacOS/$EXECUTABLE"
ROUVRIR=0
if pgrep -f "^$EN_COURS( |$)" >/dev/null 2>&1; then
  ROUVRIR=1
  pkill -f "^$EN_COURS( |$)" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do
    pgrep -f "^$EN_COURS( |$)" >/dev/null 2>&1 || break
    sleep 0.5
  done
  pkill -9 -f "^$EN_COURS( |$)" >/dev/null 2>&1 || true
fi
rm -rf "${DESTINATION:?}/$NOM"
ditto "$PAQUET" "$DESTINATION/$NOM"
# Fait connaître la nouvelle version au Finder et à « open -a ».
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION/$NOM" >/dev/null 2>&1 || true
if [ "$ROUVRIR" = 1 ]; then
  open "$DESTINATION/$NOM" >/dev/null 2>&1 || true
fi
echo "$DESTINATION/$NOM"
