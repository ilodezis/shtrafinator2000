#!/usr/bin/env bash
# Сборка «Штрафинатор 2000» для macOS: универсальный бинарник (arm64 + x86_64),
# бандл dist/Shtrafinator_2000.app и (с флагом --pkg) установщик dist/Shtrafinator_2000_macOS.pkg.
#
#   scripts/build-app.sh                 # только .app
#   scripts/build-app.sh --pkg           # .app и .pkg
#   VERSION=2.1.0 scripts/build-app.sh   # версия из окружения (по умолчанию 2.0.0)
set -euo pipefail

PRODUCT="Shtrafinator"
APP_NAME="Shtrafinator_2000"
BUNDLE_ID="com.cloudpayments.shtrafinator2000"
VERSION="${VERSION:-2.0.0}"
TRIPLES=(arm64-apple-macosx14.0 x86_64-apple-macosx14.0)

build_pkg=false
for arg in "$@"; do
    case "$arg" in
        --pkg) build_pkg=true ;;
        -h | --help)
            sed -n '2,7p' "$0"
            exit 0
            ;;
        *)
            echo "Неизвестный аргумент: $arg" >&2
            exit 2
            ;;
    esac
done

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Каждая архитектура собирается отдельно и склеивается lipo: при нескольких --arch SwiftPM
# переключается на xcbuild, который не понимает swiftLanguageMode из Package.swift.
# Новые SwiftPM кладут все триплеты в один каталог продуктов, поэтому каждый срез
# копируется сразу после сборки, пока следующая архитектура его не перезаписала.
SLICES=()
BIN_DIR=""
SLICE_DIR="$(mktemp -d)"
for triple in "${TRIPLES[@]}"; do
    swift build -c release --triple "$triple" --product "$PRODUCT"
    BIN_DIR="$(swift build -c release --triple "$triple" --show-bin-path)"
    if [[ ! -x "$BIN_DIR/$PRODUCT" ]]; then
        echo "Не найден собранный бинарник: $BIN_DIR/$PRODUCT" >&2
        exit 1
    fi
    cp "$BIN_DIR/$PRODUCT" "$SLICE_DIR/$PRODUCT-${triple%%-*}"
    SLICES+=("$SLICE_DIR/$PRODUCT-${triple%%-*}")
done
BINARY="$(mktemp -d)/$PRODUCT"
lipo -create "${SLICES[@]}" -output "$BINARY"
lipo -info "$BINARY"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT"

cp "$ROOT/app.icns" "$APP/Contents/Resources/app.icns"
cp "$ROOT/Resources/template.docx" "$APP/Contents/Resources/template.docx"
cp "$ROOT/Resources/logo.png" "$APP/Contents/Resources/logo.png"

# SwiftPM кладёт ресурсы пакетов в *.bundle рядом с бинарником; их тоже нужно положить в бандл.
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Штрафинатор 2000</string>
    <key>CFBundleDisplayName</key>
    <string>Штрафинатор 2000</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${PRODUCT}</string>
    <key>CFBundleIconFile</key>
    <string>app</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.business</string>
    <key>NSHumanReadableCopyright</key>
    <string>CloudPayments</string>
</dict>
</plist>
EOF

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist"
fi

# Ad-hoc подпись: сертификата разработчика нет, но бандл должен быть подписан целиком.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Собрано: $APP (версия $VERSION)"

if $build_pkg; then
    PKG="$DIST/${APP_NAME}_macOS.pkg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT

    mkdir -p "$STAGE/root" "$STAGE/scripts"
    # postinstall снимает карантин с установленного приложения, иначе Gatekeeper блокирует запуск.
    cat > "$STAGE/scripts/postinstall" <<'EOF'
#!/bin/bash
# Automatically strip quarantine from the installed application
xattr -cr /Applications/Shtrafinator_2000.app 2>/dev/null || true
chmod -R 755 /Applications/Shtrafinator_2000.app 2>/dev/null || true
exit 0
EOF
    chmod +x "$STAGE/scripts/postinstall"

    cp -R "$APP" "$STAGE/root/"
    rm -f "$PKG"
    pkgbuild \
        --root "$STAGE/root" \
        --install-location "/Applications" \
        --scripts "$STAGE/scripts" \
        --identifier "$BUNDLE_ID" \
        --version "$VERSION" \
        "$PKG"
    echo "Собрано: $PKG"
fi
