#!/bin/bash
# Genera los artefactos de distribución en build/:
#   Redshot-<versión>.dmg   imagen con la app y acceso directo a Aplicaciones (arrastrar y soltar)
#   Redshot-<versión>.zip   zip para el instalador de una línea (Scripts/install.sh)
#   Redshot.zip             copia sin versión, para enlazar siempre a la última
#
# Uso:  Scripts/make_release.sh            (compila si hace falta)
#       CODESIGN_IDENTITY="Apple Development: …" Scripts/make_release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build/Redshot.app"
STAGE="build/dmg-stage"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"
cat > "$STAGE/LÉEME.txt" <<'EOF'
Redshot: instalación

1. Arrastra Redshot a la carpeta Aplicaciones.
2. Abre Redshot desde Aplicaciones.

Si macOS dice que no puede verificar la app (no está notarizada por Apple):
   Ajustes del Sistema → Privacidad y seguridad → baja hasta el aviso → "Abrir de todos modos".
   Solo hace falta la primera vez.

Alternativa sin avisos, desde Terminal:
   xattr -dr com.apple.quarantine /Applications/Redshot.app
EOF

DMG="build/Redshot-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Redshot $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

ZIP="build/Redshot-$VERSION.zip"
rm -f "$ZIP" build/Redshot.zip
ditto -c -k --keepParent "$APP" "$ZIP"
cp "$ZIP" build/Redshot.zip

rm -rf "$STAGE"
echo "Listo:"
echo "  $DMG"
echo "  $ZIP  (y build/Redshot.zip)"
echo
echo "Sube el zip a un release de GitHub y la gente instala con:"
echo "  curl -fsSL https://raw.githubusercontent.com/marcocarolasec/Redshot/main/Scripts/install.sh | bash"
