#!/bin/bash
# Instalador de Redshot en una línea. No requiere que la app esté notarizada:
# descarga el zip, lo copia a /Applications, quita la cuarentena y la abre.
#
#   curl -fsSL https://raw.githubusercontent.com/marcocarolasec/Redshot/main/Scripts/install.sh | bash
#
# Variables opcionales:
#   REDSHOT_URL   URL del zip (por defecto, el último release de GitHub)
#   REDSHOT_ZIP   ruta a un zip local (para instalar sin descargar)
set -euo pipefail

REPO="${REDSHOT_REPO:-marcocarolasec/Redshot}"
URL="${REDSHOT_URL:-https://github.com/$REPO/releases/latest/download/Redshot.zip}"
DEST="/Applications/Redshot.app"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Redshot solo funciona en macOS." >&2
  exit 1
fi
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
  echo "Redshot necesita macOS 14 (Sonoma) o superior." >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ -n "${REDSHOT_ZIP:-}" ]; then
  cp "$REDSHOT_ZIP" "$TMP/Redshot.zip"
else
  echo "Descargando Redshot…"
  curl -fsSL "$URL" -o "$TMP/Redshot.zip"
fi

ditto -x -k "$TMP/Redshot.zip" "$TMP/out"
APP=$(find "$TMP/out" -maxdepth 2 -name "Redshot.app" | head -1)
if [ -z "$APP" ]; then
  echo "El zip no contiene Redshot.app" >&2
  exit 1
fi

pkill -x Redshot 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
echo
echo "Redshot instalada en Aplicaciones y abierta: busca el icono de la cámara en la barra de menús."
echo "La primera vez te guiará para conceder el permiso de Grabación de pantalla."
