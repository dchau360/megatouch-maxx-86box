#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

download_86box() {
    echo "86Box not found. Downloading latest release..."

    ARCH=$(uname -m)  # arm64 or x86_64

    API=$(curl -sf https://api.github.com/repos/86Box/86Box/releases/latest) || {
        echo "Failed to reach GitHub API. Download manually: https://github.com/86Box/86Box/releases"
        exit 1
    }

    URL=$(echo "$API" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
arch = '$ARCH'
for a in assets:
    n = a['name'].lower()
    if 'macos' in n and arch in n and n.endswith('.dmg'):
        print(a['browser_download_url']); exit()
for a in assets:
    n = a['name'].lower()
    if 'macos' in n and n.endswith('.dmg'):
        print(a['browser_download_url']); exit()
" 2>/dev/null)

    if [ -z "$URL" ]; then
        echo "Could not find a macOS release asset. Download manually: https://github.com/86Box/86Box/releases"
        exit 1
    fi

    echo "Downloading: $URL"
    DMG="$SCRIPT_DIR/_86box_tmp.dmg"
    curl -L --progress-bar -o "$DMG" "$URL"

    echo "Installing 86Box.app..."
    MOUNT_POINT="/tmp/86box_mount_$$"
    mkdir -p "$MOUNT_POINT"
    hdiutil attach "$DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
    cp -R "$MOUNT_POINT/86Box.app" "$SCRIPT_DIR/"
    hdiutil detach "$MOUNT_POINT" -quiet
    rmdir "$MOUNT_POINT"
    rm "$DMG"

    # Remove quarantine so Gatekeeper doesn't block launch
    xattr -dr com.apple.quarantine "$SCRIPT_DIR/86Box.app" 2>/dev/null || true

    patch_app "$SCRIPT_DIR/86Box.app"
    echo "Done."
}

patch_app() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local flag="$app/Contents/.patched"

    [ -f "$flag" ] && return  # already patched

    echo "Patching 86Box.app for macOS touchscreen support..."
    codesign --remove-signature "$app" 2>/dev/null || true

    # Fix 1: Disable HiDPI — prevents coordinate scaling issues on Retina displays
    /usr/libexec/PlistBuddy -c "Delete :NSHighResolutionCapable" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool false" "$plist"

    # Fix 2: Patch mousePressEvent/mouseReleaseEvent — 86Box has a macOS-specific
    # bug where absolute mouse button events (needed for MicroTouch touchscreen)
    # are silently dropped on the primary monitor. The code checks
    # (m_monitor_index >= 1 && mouse_tablet_in_proximity) which is always false
    # for single-monitor setups without tablet hardware. We NOP out these checks.
    local binary="$app/Contents/MacOS/86Box"
    if [ -f "$binary" ]; then
        python3 -c "
import struct
with open('$binary', 'rb') as f:
    data = bytearray(f.read())

nop = bytes([0x1f, 0x20, 0x03, 0xd5])
slice_off = None

# Find arm64 slice offset in universal binary
import subprocess
info = subprocess.check_output(['lipo', '-detailed_info', '$binary'], text=True)
for line in info.split('\n'):
    if 'arm64' in line and 'architecture' in line:
        in_arm64 = True
    elif in_arm64 and 'offset' in line:
        slice_off = int(line.split()[-1])
        break

if slice_off is None:
    # Try as a thin binary (offset 0)
    slice_off = 0

patches = [
    # mousePressEvent: NOP the b.lt (m_monitor_index check) and tbz (tablet check)
    (slice_off + 0x76c970, b'\x2b\x01\x00\x54'),
    (slice_off + 0x76c980, b'\xa8\x00\x00\x36'),
    # mouseReleaseEvent: NOP the b.eq and tbz
    (slice_off + 0x76c88c, b'\x20\x01\x00\x54'),
    (slice_off + 0x76c89c, b'\xa8\x00\x00\x36'),
]

applied = 0
for offset, expected in patches:
    if bytes(data[offset:offset+4]) == expected:
        data[offset:offset+4] = nop
        applied += 1

if applied > 0:
    with open('$binary', 'wb') as f:
        f.write(data)
    print(f'Applied {applied} binary patches')
else:
    print('No matching bytes found (binary may be a different version)')
" 2>/dev/null && echo "Binary patches applied." || echo "Binary patch skipped (non-matching version)."
    fi

    codesign --sign - --force --deep "$app" 2>/dev/null || true
    touch "$flag"
    echo "Patch complete."
}

# Find 86Box .app bundle
if [ -f "$SCRIPT_DIR/86Box.app/Contents/MacOS/86Box" ]; then
    EMU_APP="$SCRIPT_DIR/86Box.app"
elif [ -f "/Applications/86Box.app/Contents/MacOS/86Box" ]; then
    EMU_APP="/Applications/86Box.app"
else
    download_86box
    EMU_APP="$SCRIPT_DIR/86Box.app"
fi

patch_app "$EMU_APP"

CFG="$SCRIPT_DIR/86box.cfg"

# Apply settings 86Box normally reverts on exit, then lock the file
# read-only so 86Box can't overwrite them when it closes.
chmod 644 "$CFG" 2>/dev/null || true
sed -i '' 's/crosshair = 0/crosshair = 1/' "$CFG" 2>/dev/null || true
sed -i '' 's/identity = [0-9]/identity = 0/' "$CFG" 2>/dev/null || true
# Ensure qt_software renderer (most compatible)
sed -i '' 's/vid_renderer = sdl_hardware/vid_renderer = qt_software/' "$CFG" 2>/dev/null || true
chmod 444 "$CFG"

# Run the binary directly, activate via AppleScript after it opens.
"$EMU_APP/Contents/MacOS/86Box" -P "$SCRIPT_DIR" &
EMU_PID=$!

sleep 3
osascript -e 'tell application "86Box" to activate' 2>/dev/null || true

# Restore write permissions after 86Box exits
wait $EMU_PID
chmod 644 "$CFG"
