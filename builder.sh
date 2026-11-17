#!/usr/bin/env bash
# SUBSTRATUM drop-in builder (Linux / macOS).
# Put this folder next to apotheosisEngine.exe (or a .love, or unpacked tree).
# Usage:
#   ./build.sh desktop
#   ./build.sh android
#   ./build.sh              # (prompts for target)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL_DIR="$SCRIPT_DIR"
OUT_DIR="$SCRIPT_DIR/out"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/substratum"
REPO="nikere/Substratum"
BRANCH="main"
REPO_ZIP="https://codeload.github.com/$REPO/zip/refs/heads/$BRANCH"

TARGET="${1:-ask}"
UPDATE="${UPDATE:-0}"
FETCH_ANDROID="${FETCH_ANDROID:-0}"
ANDROID_SRC="${ANDROID_SRC:-}"

say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\n[BUILD FAILED] %s\nNothing outside out/ and the cache was written.\n' "$*" >&2; exit 1; }

for cmd in curl unzip zip patch; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required tool: $cmd. Please install it."
done

echo "=============="
echo "  SUBSTRATUM  "
echo "=============="

if [[ "$TARGET" == "ask" ]]; then
    echo "Select build target:"
    echo "  [1] Desktop (standalone fused Substratum)"
    echo "  [2] Android (game.love for your android project)"
    read -rp "Enter 1 or 2: " choice
    [[ "$choice" == "2" ]] && TARGET="android" || TARGET="desktop"
fi

mkdir -p "$CACHE" "$OUT_DIR"
WORK="$(mktemp -d)"
GAME="$WORK/game"
mkdir -p "$GAME"
trap 'rm -rf "$WORK"' EXIT
if [[ ! -f "$REL_DIR/mods/init.lua" ]] || [[ ! -f "$REL_DIR/patches/main.lua.patch" ]] || [[ "$UPDATE" == "1" ]]; then
    say "Fetching loader + patches from GitHub ($REPO)..."
    curl -fL "$REPO_ZIP" -o "$WORK/repo.zip"
    unzip -q "$WORK/repo.zip" -d "$WORK/repo"
    REL_DIR="$(find "$WORK/repo" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$REL_DIR" ]] || die "Repo archive contained no folders."
    say "Loader fetched: $(basename "$REL_DIR")"
fi
SRC=""
for c in "$SCRIPT_DIR/apotheosisEngine.exe" "$SCRIPT_DIR"/*.love "$SCRIPT_DIR/main.lua"; do
    if [[ -e "$c" ]]; then
        if [[ "$c" == */main.lua ]]; then SRC="$(dirname "$c")"; else SRC="$c"; fi
        break
    fi
done
[[ -n "$SRC" ]] || die "No apotheosisEngine.exe / .love / main.lua found next to this script."
say "Game source: $SRC"
# unzip natively handles prepended PE headers (fused exes) without custom parsers!
if [[ -d "$SRC" ]]; then
    cp -R "$SRC/." "$GAME/"
elif [[ "$SRC" == *.love ]] || [[ "$SRC" == *.exe ]]; then
    set +e
    unzip -q "$SRC" -d "$GAME" 2>/dev/null
    UNZIP_RC=$?
    set -e
    # unzip returns 1 for warnings (like "extra junk at start"), >1 for actual errors
    if [[ $UNZIP_RC -gt 1 ]]; then
        die "Failed to extract $SRC (unzip exit code $UNZIP_RC). Is it a valid LÖVE game?"
    fi
else
    die "Unknown source type: $SRC"
fi
say "Game tree extracted."
apply_patch() {
    local p="$1"
    [[ -f "$p" ]] || die "Missing patch: $p"
    # --forward skips already-applied hunks. 
    if ! patch -p1 --forward --batch -d "$GAME" < "$p" >/dev/null 2>&1; then
        if patch -p1 --reverse --check -d "$GAME" < "$p" >/dev/null 2>&1; then
            say "  $(basename "$p") already applied."
        else
            die "Patch failed: $(basename "$p"). Game version changed?"
        fi
    else
        say "Applied $(basename "$p")"
    fi
}

apply_patch "$REL_DIR/patches/main.lua.patch"

# Clean slate for mods, then copy baseline
rm -rf "$GAME/mods"
mkdir -p "$GAME/mods"
cp -R "$REL_DIR/mods/." "$GAME/mods/"

if [[ "$TARGET" == "android" ]]; then
    if [[ -d "$REL_DIR/androidlua/mods" ]]; then
        cp -R "$REL_DIR/androidlua/mods/." "$GAME/mods/"
        say "Android overlay copied."
    fi
    
    if [[ -f "$REL_DIR/androidlua/patches/android.patch" ]]; then
        apply_patch "$REL_DIR/androidlua/patches/android.patch"
    elif [[ -f "$REL_DIR/patches/android.patch" ]]; then
        apply_patch "$REL_DIR/patches/android.patch"
    fi
    
    cat <<'EOF' > "$GAME/luasteam.lua"
local noop = setmetatable({}, { __index = function() return function() return false end end })
return noop
EOF
    say "luasteam stub written."
fi
LOVE_OUT="$WORK/patched.love"
(cd "$GAME" && zip -q -r -X "$LOVE_OUT" .)

unzip -l "$LOVE_OUT" | grep -q 'mods/init.lua' || die "Verify failed: mods/init.lua missing"
unzip -p "$LOVE_OUT" main.lua | grep -qF '[SUBSTRATUM]' || die "Verify failed: main.lua lacks [SUBSTRATUM]"
if [[ "$TARGET" == "android" ]]; then
    unzip -l "$LOVE_OUT" | grep -q 'luasteam.lua' || die "Verify failed: luasteam stub missing"
fi
say "Patched archive verified."
if [[ "$TARGET" == "android" ]]; then
    OUT_LOVE="$OUT_DIR/game.love"
    cp "$LOVE_OUT" "$OUT_LOVE"
    echo
    echo "[SUCCESS] Android package: $OUT_LOVE"
    
    if [[ "$FETCH_ANDROID" == "1" ]] && [[ -z "$ANDROID_SRC" ]]; then
        say "Downloading LÖVE 11.5 Android source..."
        ANDROID_ZIP="$CACHE/love-11.5-android.zip"
        curl -fL "https://github.com/love2d/love/archive/refs/tags/11.5.zip" -o "$ANDROID_ZIP"
        mkdir -p "$CACHE/android-src"
        unzip -q "$ANDROID_ZIP" -d "$CACHE/android-src"
        ANDROID_SRC="$(find "$CACHE/android-src" -maxdepth 1 -mindepth 1 -type d | head -1)"
    fi
    
    if [[ -n "$ANDROID_SRC" ]]; then
        ASSETS="$ANDROID_SRC/app/src/main/assets"
        mkdir -p "$ASSETS"
        cp "$OUT_LOVE" "$ASSETS/game.love"
        echo "Copied to $ASSETS/game.love"
    else
        echo "Drop game.love into your android project's app/src/main/assets/ or load via LÖVE for Android (11.5)" 
    fi
else
    DEST="$OUT_DIR/Substratum"
    mkdir -p "$DEST"
    
    LOVE_BIN="$(command -v love || true)"
    if [[ -z "$LOVE_BIN" ]]; then
        say "System 'love' not found. Downloading LÖVE 11.5..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            LOVE_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage"
            LOVE_DL="$CACHE/love-11.5.AppImage"
            curl -fL "$LOVE_URL" -o "$LOVE_DL"
            chmod +x "$LOVE_DL"
            "$LOVE_DL" --appimage-extract >/dev/null 2>&1
            LOVE_BIN="$PWD/squashfs-root/usr/bin/love"
            cp -R squashfs-root/. "$DEST/"
            rm -rf squashfs-root
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            LOVE_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip"
            LOVE_DL="$CACHE/love-11.5-macos.zip"
            curl -fL "$LOVE_URL" -o "$LOVE_DL"
            unzip -q "$LOVE_DL" -d "$DEST"
            LOVE_BIN="$(find "$DEST" -name "love" -type f | head -1)"
        else
            die "Unsupported OS for automatic LÖVE download. Please install LÖVE 11.5 manually."
        fi
    else
        say "Using system love: $LOVE_BIN"
    fi

    FUSED="$DEST/Substratum"
    cat "$LOVE_BIN" "$LOVE_OUT" > "$FUSED"
    chmod +x "$FUSED"
    
    cp "$LOVE_OUT" "$DEST/Substratum.love"
    
    echo
    echo "[SUCCESS] Standalone build: $FUSED"
    echo "Run ./Substratum (or ./Substratum.love via system love)."
fi