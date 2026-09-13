#!/bin/bash
# Compila Redshot en release y monta el bundle Redshot.app en build/.
# Uso:
#   Scripts/build_app.sh                 # firma ad-hoc
#   CODESIGN_IDENTITY="Apple Development: Tu Nombre (TEAMID)" Scripts/build_app.sh
#
# Con firma ad-hoc, cada recompilación cambia la firma y macOS puede volver a pedir
# el permiso de Grabación de pantalla. Con una identidad estable el permiso se conserva.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Redshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Redshot" "$APP/Contents/MacOS/Redshot"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
echo "APPL????" > "$APP/Contents/PkgInfo"

IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --options runtime --sign "$IDENTITY" "$APP" 2>/dev/null || codesign --force --sign "$IDENTITY" "$APP"

echo "Listo: $APP"
echo "Instalar: cp -R $APP /Applications/"
