#!/usr/bin/env bash
set -euo pipefail

# Build the self-contained Linux x86_64 AppImage. linuxdeploy bundles the
# native shared-library dependencies; its official AppImage already includes
# the AppImage output plugin.

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$project_root/build/appimage/ESP_Loader.AppDir"
release_dir="$project_root/release"
bundled_esptool="$project_root/third_party/esptool/5.4.0/linux-x64/esptool"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Questa configurazione genera solo AppImage Linux x86_64." >&2
  exit 1
fi

if [[ ! -x "$bundled_esptool" ]]; then
  echo "esptool standalone non trovato o non eseguibile: $bundled_esptool" >&2
  exit 1
fi

if [[ -n "${LINUXDEPLOY_PATH:-}" ]]; then
  linuxdeploy="$LINUXDEPLOY_PATH"
elif command -v linuxdeploy >/dev/null 2>&1; then
  linuxdeploy="$(command -v linuxdeploy)"
else
  echo "linuxdeploy non trovato. Imposta LINUXDEPLOY_PATH con il percorso della sua AppImage." >&2
  exit 1
fi

version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$project_root/pubspec.yaml")"
output="$release_dir/ESP-Loader-$version-linux-x86_64.AppImage"

echo "Compilazione Linux Release..."
flutter build linux --release

rm -rf "$app_dir"
mkdir -p "$app_dir/usr/bin" "$release_dir"
cp -a "$project_root/build/linux/x64/release/bundle/." "$app_dir/usr/bin/"

"$app_dir/usr/bin/esptool" version

export APPIMAGE_EXTRACT_AND_RUN=1
export LDAI_OUTPUT="$output"
export LINUXDEPLOY_OUTPUT_VERSION="$version"

"$linuxdeploy" \
  --appdir "$app_dir" \
  --executable "$app_dir/usr/bin/esp_loader" \
  --desktop-file "$project_root/linux/com.ariosa.esp_loader.desktop" \
  --icon-file "$project_root/img/com.ariosa.esp_loader.png" \
  --custom-apprun "$project_root/scripts/appimage/AppRun" \
  --output appimage

if [[ ! -x "$output" ]]; then
  echo "AppImage non generata: $output" >&2
  exit 1
fi

echo "AppImage pronta: $output"
