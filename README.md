# Substratum
**Substratum** is a non-destructive mod loader, unified Lua modding SDK, in-game GUI manager (`modview`), and Android LÖVE port builder for **Apotheosis Engine**.

> **Zero Copyrighted Game Assets:** This repository contains only original loader/SDK code and minimal unified diff patches. You must own a legitimate copy of *Apotheosis Engine* on Steam to build and run Substratum.

## Quick Start
> **Standalone Builders:** You do not need to download the entire repository, you only need `builder.sh` (Linux / macOS) or `builder.ps1` / `builder.bat` (Windows) placed next to `apotheosisEngine.exe`.

### Windows (Desktop or Android `.love`)

1. Download or clone this repository (or grab the latest release zip).
2. Copy the **Substratum** folder (`builder.bat`, `builder.ps1`, `mods/`, `patches/`, `androidlua/`) into your **Apotheosis Engine** game folder next to `apotheosisEngine.exe` *(or pass `-GameDir "C:\Path\To\Apotheosis Engine"` to `builder.ps1`)*.
3. Double-click **`builder.bat`** and select your target:
   * **`[1]` Windows Desktop:** Downloads and caches the official LÖVE 11.5 runtime in `%LOCALAPPDATA%\Substratum` and outputs a standalone **`out\Substratum\Substratum.exe`**.
   * **`[2]` Android LÖVE:** Applies `android.patch`, injects `android.lua` + a `luasteam` stub, and outputs **`out\game.love`**.
4. Run `out\Substratum\Substratum.exe` directly (your saves remain in `%APPDATA%\LOVE\apot01`).

### Android Installation

1. Build `out/game.love` using option `[2]` in `build.bat` or `./build.sh android`.
2. Either drop `game.love` into your `love-android` Gradle project at `app/src/main/assets/game.love` to compile an APK, or open `game.love` directly with the **LÖVE for Android (11.5)** app.
3. **Grant Storage Permissions:** On Android 11+, you **must** manually grant **All Files Access** (*Settings → Apps → LÖVE / Substratum → Permissions → Files and media → Allow management of all files*). Without this permission, the loader cannot read or create external folders on `/sdcard`.
4. Place custom Android mods and overrides on your device at:
   * `/sdcard/apotheosis/mods/<mod_folder>/mod.lua`
   * `/sdcard/apotheosis/overrides/<module/path>.lua`

### Linux / WSL
* **Linux (`builder.sh`):** Tested on custom Linux (`./builder.sh desktop` / `./builder.sh android`). Uses system `love` if installed or caches the official LÖVE 11.5 AppImage in `~/.cache/substratum`.
> **Note:** `builder.sh` mirrors the Windows builder logic for POSIX environments.
has been tested on: custom Linux

### macOS
* **Build (`builder.sh`):**
Copy `apotheosisEngine.exe` (from your Windows/Steam install) into the same folder as `builder.sh`.
Open **Terminal** in that folder and run:
 ```bash
 chmod +x builder.sh
./builder.sh desktop
 ```
This downloads LÖVE 11.5 and bundles `out/Substratum/Substratum.app` with `Substratum.love` inside `Contents/Resources/`.
Copy `out/Substratum/Substratum.app` into `/Applications` (or run it directly from `out/Substratum/`):
 ```bash
 cp -R out/Substratum/Substratum.app /Applications/
```
Double-click `Substratum.app` or launch from Terminal:
```bash
open /Applications/Substratum.app
 ```
*Note:* If macOS blocks the unnotarized app on first launch, right-click `Substratum.app` → **Open**, or run `xattr -cr /Applications/Substratum.app`.
* **Mods directory:** `~/Library/Application Support/apot01/mods`

*Tested on: Hackintosh VM (macOS 12 Monterey)*

---

## Creating Your First Mod
Mods live in `%APPDATA%\apot01\mods\` (`%APPDATA%\LOVE\apot01\mods\` if unfused) on Windows, `~/.local/share/love/apot01/mods/` on Linux, and `/sdcard/apotheosis/mods/` on Android. Each mod is a folder containing a `mod.lua` file that returns a table, for example:

```lua
local M = {
  id      = "example_mod",
  name    = "Example Mod",
  version = "1.0.0",
  author  = "YourName",
  desc    = "Adds a custom terminal command",
}

function M:init(game)
  -- Register a custom command in APOTHEOSIS SHELL
  game.mods:addTerminalCommand({
    name = "hello",
    desc = "Prints a greeting to the shell and logbook",
    fn = function(args, term)
      game.mods:pushLog("Hello from Substratum! ^_^", 0)
      return "pong (" .. table.concat(args, " ") .. ")"
    end
  })

  -- Run logic once the game scene and subsystems are initialized
  game.mods:onReady(function(g)
    g.mods:pushLog("Example Mod initialized!", 0)
  end)
end

return M
```
> See **[`API_REFERENCE.md`](docs/API_REFERENCE.md)** for the full `game.mods` SDK reference (apps, processes, themes, materials, powers, window management, mascots, pause/title buttons, crash hooks, and more).

---

## Security & Fair-Play Disclaimer

* **Unsandboxed Lua Execution:** Mods loaded through Substratum run with full LÖVE/Lua privileges (`io`, `os`, `ffi`). Only install mods and overrides from sources you trust.
* **Steam Competitive Guard:** Substratum keeps Steamworks online for Rich Presence and overlay support, while automatically guarding Steam leaderboards, achievements , and global scoreboards whenever any mod, override, or loader shadow is active (local records still save normally).

## License
Substratum is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See [`LICENSE`](LICENSE) for details.
