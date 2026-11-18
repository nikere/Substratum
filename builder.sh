#!/usr/bin/env bash
# SUBSTRATUM drop-in builder (Linux / macOS).
# Put this script next to apotheosisEngine.exe (or a .love, or unpacked tree).
# Usage:
#   ./builder.sh desktop
#   ./builder.sh android
#   ./builder.sh              # (prompts for target)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL_DIR="$SCRIPT_DIR"
OUT_DIR="$SCRIPT_DIR/out"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/substratum"
REPO="nikere/Substratum"
BRANCH="main"
REPO_ZIP="https://github.com/nikere/Substratum/archive/refs/heads/main.zip"

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
    echo "  [1] Desktop (standalone Substratum)"
    echo "  [2] Android (game.love for your android project)"
    read -rp "Enter 1 or 2: " choice
    [[ "$choice" == "2" ]] && TARGET="android" || TARGET="desktop"
fi

mkdir -p "$CACHE" "$OUT_DIR"
WORK="$(mktemp -d)"
GAME="$WORK/game"
mkdir -p "$GAME"

cleanup() {
    if [[ -n "${WORK:-}" && -d "$WORK" ]]; then
        chmod -R u+rwX "$WORK" 2>/dev/null || true
        rm -rf "$WORK"
    fi
}

trap cleanup EXIT

if [[ ! -f "$REL_DIR/mods/init.lua" ]] || [[ ! -f "$REL_DIR/patches/main.lua.patch" ]] || [[ "$UPDATE" == "1" ]]; then
    say "Fetching loader + patches from GitHub ($REPO)..."
    curl -fL -A "Substratum-Builder/1.0" "$REPO_ZIP" -o "$WORK/repo.zip"
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

if [[ -d "$SRC" ]]; then
    cp -R "$SRC/." "$GAME/"
elif [[ "$SRC" == *.love ]] || [[ "$SRC" == *.exe ]]; then
    set +e
    unzip -q "$SRC" -d "$GAME" 2>/dev/null
    UNZIP_RC=$?
    chmod -R u+rwX "$GAME" 2>/dev/null || true
    set -e
    if [[ $UNZIP_RC -gt 1 ]]; then
        die "Failed to extract $SRC (unzip exit code $UNZIP_RC). Is it a valid LÖVE game?"
    fi
else
    die "Unknown source type: $SRC"
fi
chmod -R u+w "$GAME"
say "Game tree extracted."
say "Normalizing line endings (CRLF -> LF)..."
find "$GAME" -type f -name "*.lua" -exec sed -i 's/\r$//' {} + 2>/dev/null || true

apply_patch() {
    local p="$1"
    [[ -f "$p" ]] || die "Missing patch: $p"
    for target in main.lua conf.lua mods/init.lua; do
        if [[ -f "$GAME/$target" ]]; then
            tr -d '\r' < "$GAME/$target" > "$GAME/$target.lf" && mv "$GAME/$target.lf" "$GAME/$target"
        fi
    done
    local split_dir="$WORK/patch_splits_$(basename "$p")"
    mkdir -p "$split_dir"
    tr -d '\r' < "$p" | awk -v dir="$split_dir" '
        function flush() {
            if (in_hunk && outfile != "") {
                printf "@@ -%d,%d +%d,%d @@%s\n", old_s, old_c, new_s, new_c, tail > outfile
                printf "%s", buf > outfile
                in_hunk = 0; buf = ""
            }
        }
        /^diff --git / {
            flush()
            if (outfile != "") close(outfile)
            file_num++
            outfile = dir "/part_" file_num ".patch"
            print $0 > outfile
            next
        }
        /^--- / {
            flush()
            if (outfile == "") {
                file_num++
                outfile = dir "/part_" file_num ".patch"
            }
            print $0 > outfile
            next
        }
        /^\+\+\+ / {
            flush()
            print $0 > outfile
            next
        }
        /^@@ / {
            flush()
            match($0, /^@@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@(.*)$/, m)
            old_s = m[1]; new_s = m[3]; tail = m[5]
            old_c = 0; new_c = 0; in_hunk = 1; buf = ""
            next
        }
        in_hunk {
            c = substr($0, 1, 1)
            if (c == "-") { old_c++ }
            else if (c == "+") { new_c++ }
            else { old_c++; new_c++ }
            buf = buf $0 "\n"
            next
        }
        outfile != "" { print $0 > outfile }
        END { flush(); if (outfile != "") close(outfile) }
    '
    local applied=0
    for part in "$split_dir"/*.patch; do
        [[ -f "$part" ]] || continue
        if ! patch -p1 --forward --batch -d "$GAME" < "$part" >/dev/null 2>&1; then
            if patch -p1 --reverse --check -d "$GAME" < "$part" >/dev/null 2>&1; then
                : # already applied
            elif ! patch -p1 --forward --batch --ignore-whitespace -d "$GAME" < "$part" >/dev/null 2>&1; then
                patch -p1 --forward --batch -d "$GAME" < "$part" || true
                die "Patch failed on chunk: $(basename "$part") in $(basename "$p")."
            fi
        fi
        applied=1
    done

    if [[ "$applied" -eq 1 ]]; then
        say "Applied $(basename "$p")"
    else
        die "No valid patch blocks found in $(basename "$p")"
    fi
}

apply_patch "$REL_DIR/patches/main.lua.patch"

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

LISTING="$(unzip -l "$LOVE_OUT")"
grep -q 'mods/init.lua' <<< "$LISTING" || die "Verify failed: mods/init.lua missing"
unzip -p "$LOVE_OUT" main.lua | grep -F '[SUBSTRATUM]' >/dev/null || die "Verify failed: main.lua lacks [SUBSTRATUM]"
if [[ "$TARGET" == "android" ]]; then
    grep -q 'luasteam.lua' <<< "$LISTING" || die "Verify failed: luasteam stub missing"
fi
say "Patched archive verified."

if [[ "$TARGET" == "android" ]]; then
    OUT_LOVE="$OUT_DIR/game.love"
    cp "$LOVE_OUT" "$OUT_LOVE"
    echo
    echo "[SUCCESS] Android package: $OUT_LOVE"

    if [[ "$FETCH_ANDROID" == "1" ]] && [[ -z "$ANDROID_SRC" ]]; then
        say "Downloading LÖVE Android project..."
        ANDROID_ZIP="$CACHE/love-android.zip"
        curl -fL -A "Substratum-Builder/1.0" "https://github.com" -o "$ANDROID_ZIP"
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
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp "$LOVE_OUT" "$DEST/Substratum.love"

    LOVE_BIN="$(command -v love || true)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        LOVE_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip"
        LOVE_DL="$CACHE/love-11.5-macos.zip"
        [[ -f "$LOVE_DL" ]] || curl -fL -A "Substratum-Builder/1.0" "$LOVE_URL" -o "$LOVE_DL"
        unzip -q "$LOVE_DL" -d "$WORK/macos"
        mv "$WORK/macos/love.app" "$DEST/Substratum.app"
        cp "$LOVE_OUT" "$DEST/Substratum.app/Contents/Resources/Substratum.love"
        echo
        echo "[SUCCESS] macOS bundle: $DEST/Substratum.app"
    elif [[ -n "$LOVE_BIN" ]]; then
        say "Using system love: $LOVE_BIN"
        FUSED="$DEST/Substratum"
        cat "$LOVE_BIN" "$LOVE_OUT" > "$FUSED"
        chmod +x "$FUSED"
        echo
        echo "[SUCCESS] Standalone build: $FUSED"
    else
        say "System 'love' not found. Caching LÖVE 11.5 AppImage..."
        LOVE_URL="https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage"
        LOVE_DL="$CACHE/love-11.5-x86_64.AppImage"
        [[ -f "$LOVE_DL" ]] || curl -fL -A "Substratum-Builder/1.0" "$LOVE_URL" -o "$LOVE_DL"
        cp "$LOVE_DL" "$DEST/love-11.5-x86_64.AppImage"
        chmod +x "$DEST/love-11.5-x86_64.AppImage"
        cat <<'EOF' > "$DEST/Substratum"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/love-11.5-x86_64.AppImage" "$DIR/Substratum.love" "$@"
EOF
        chmod +x "$DEST/Substratum"
        echo
        echo "[SUCCESS] Standalone Linux build: $DEST/Substratum"
    fi
fi
