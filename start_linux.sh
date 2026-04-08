#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

download_86box() {
    echo "86Box not found. Downloading latest release..."

    ARCH=$(uname -m)              # x86_64 or aarch64
    ARCH_ALT="${ARCH/aarch64/arm64}"  # GitHub may label ARM as arm64

    API=$(curl -sf https://api.github.com/repos/86Box/86Box/releases/latest) || {
        echo "Failed to reach GitHub API. Download manually: https://github.com/86Box/86Box/releases"
        exit 1
    }

    URL=$(echo "$API" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
arch = '$ARCH'.lower()
arch_alt = '$ARCH_ALT'.lower()
for a in assets:
    n = a['name'].lower()
    if 'linux' in n and (arch in n or arch_alt in n) and n.endswith('.appimage'):
        print(a['browser_download_url']); exit()
for a in assets:
    n = a['name'].lower()
    if 'linux' in n and n.endswith('.appimage'):
        print(a['browser_download_url']); exit()
" 2>/dev/null)

    if [ -z "$URL" ]; then
        echo "Could not find a Linux AppImage. Options:"
        echo "  Flatpak: flatpak install flathub net.86box.86Box"
        echo "  Manual:  https://github.com/86Box/86Box/releases"
        exit 1
    fi

    echo "Downloading: $URL"
    curl -L --progress-bar -o "$SCRIPT_DIR/86Box.AppImage" "$URL"
    chmod +x "$SCRIPT_DIR/86Box.AppImage"
    echo "Done."
}

# Find 86Box binary
if [ -f "$SCRIPT_DIR/86Box.AppImage" ]; then
    exec "$SCRIPT_DIR/86Box.AppImage" -P "$SCRIPT_DIR"
elif command -v 86box &>/dev/null; then
    exec 86box -P "$SCRIPT_DIR"
elif command -v 86Box &>/dev/null; then
    exec 86Box -P "$SCRIPT_DIR"
elif flatpak list 2>/dev/null | grep -q "net.86box.86Box"; then
    exec flatpak run net.86box.86Box -P "$SCRIPT_DIR"
else
    download_86box
    exec "$SCRIPT_DIR/86Box.AppImage" -P "$SCRIPT_DIR"
fi
