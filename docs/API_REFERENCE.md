# SUBSTRATUM SDK — Unified API Reference

**Tested against:** Apotheosis Engine **1.5** · LÖVE **11.5** · Windows / Linux / macOS / Android
**License:** GPL-3.0 · **Requires:** a legitimate Steam copy of the game

One API (`game.mods`) on every platform. Platform differences live in §2 and §15 only.

**Notation.** `fn(a, b[, c])` — `[, c]` optional. Types: `string`, `number`,
`integer`, `boolean`, `table`, `function`, `nil`. Ranges `0..1`; enums `"a" | "b"`.
Colors as tables are `{r, g, b[, a]}` floats `0..1`; as strings `"#RRGGBB"`.

---

## 1. Mod anatomy & lifecycle

Folder with `mod.lua` returning a table:

| Field | Type | Notes |
|---|---|---|
| name | string | display name |
| version | string | e.g. `"1.0.0"` |
| author | string | |
| desc | string | |

| Callback | Signature | When |
|---|---|---|
| `M.init` | `(mod, game, folder)` | during load; **register only** (scenes/audio absent); `pcall`ed, error → `mod._error` |
| `M.onLoad` | `(mod, game, folder)` | after `game:load()`; live objects safe; `pcall`ed |

Order: overrides → chunk → `init` → `game:load()` → `onReady` queue → `onLoad`.
`game.mods:restart()` re-runs everything with current toggle config.

Mod record fields: `_folder` string, `_path` string, `_external` boolean,
`_enabled` boolean, `_core` boolean, `_error` string|nil.

## 2. Install paths

| Platform | User mods | Overrides |
|---|---|---|
| Windows fused | `%APPDATA%\apot01\mods\` | `%APPDATA%\apot01\overrides\` |
| Windows unfused | `%APPDATA%\LOVE\apot01\…` | same root |
| Linux | `~/.local/share/love/apot01/…` | same root |
| macOS | `~/Library/Application Support/love/apot01/…` | same root |
| Android | built-in **plus** `/sdcard/apotheosis/mods/` | **plus** `/sdcard/apotheosis/overrides/` |

Android sdcard needs **All Files Access**; grant detected live on focus.
Music: `/sdcard/apotheosis/music/`.

## 3. Core handle
Accessed via game.mods (e.g. game.mods:onReady(fn)):
- `onReady(fn)` — `fn(game)`; runs now if loaded else queued.
- `onKey(key, fn)` — `key`: string love keyconstant (`"f4"`, `"escape"`…). `fn(game, key, scancode, isrepeat)`; **return `true` to consume**.
- `get(name)` — `name`: string (`name` or `_folder`) → mod table|nil.
- `restart()` — none.
- `toggleMod(folder)` — `folder`: string folder name → new enabled boolean; `false` if `_core`; persists; **full effect after restart**.
- `openFolder([dir])` — `dir`: string path (Android; default `"/sdcard/apotheosis/mods"`). Desktop: ignores arg, opens save dir.
- `version` / `api` — integer. `loaded` / `discovered` / `disabled` / `overrides` — tables.
- `ui.X` — lazy module: `Widgets | Theme | Cursor | Rect | Format | MatrixRain | Ascension | Kit3D`.

## 4. Terminal & logbook

- `addTerminalCommand(def)` — `def`: table
  - `name`: string (**required**) — command word.
  - `help`: `{en=string[, jp=string]}` | nil — help listing text.
  - `fn`: `function(args, term)` → string|nil — `args`: array of strings (split args); `term`: terminal app. Returned string is printed. **Need `game`? use an upvalue — first param is `args`, not the game.**
  - `secret`: string | nil — unlock id; typing sets the flag instead of running `fn`.
  - `lore`: `{en=string}` | nil — one-time flavor printed with `secret`.
- `removeTerminalCommand(name)` / `listTerminalCommands()` — string / → array of strings.
- `addLog(key, text[, kao[, glitch]])`
  - `key`: string — unique entry id.
  - `text`: string — the line (en).
  - `kao`: string|nil — portrait/face id (valid ids: see `src/data/logs.lua`); nil = none.
  - `glitch`: **number 0..1** | nil (default nil) — corruption intensity; 0 clean → 1 fully glitched. Same scale as `pushLog` and virus log lines.
- `pushLog(text[, glitch])` — `text`: string; `glitch`: **number 0..1** (default 0).

## 5. Localization

- `addString(key, translations)` — `key`: string; `translations`: string | `{en=…, jp=…}`.
  Auto-namespaces used by: pause/title/option/theme/app labels.

## 6. Apps

- `registerApp(def, AppClass)`
  - `def.id`: string (**required**, unique).
  - `def.title` / `def.title_jp` / `def.sub`: string | nil.
  - `def.icon`: string | nil (default `"量"`) — one glyph.
  - `def.eager`: boolean | nil — `fixedUpdate` runs while closed.
  - `def.unlock`: table | nil (default `{always=true}`); e.g. `{flag="secret.x"}`.
  - `AppClass`: table — `require("src.apps.app"):extend()` subclass:
    - numbers (pixels): `windowW, windowH, minW, minH`.
    - booleans: `transient`, `resizable`.
    - `new(game)` — call `Class.super.new(self, game)` first.
    - `drawBody(x, y, w, h)` — numbers, client area.
    - `mousepressed(lx, ly, b)` / `mousereleased` / `mousemoved` / `wheelmoved(dx, dy)` — local coords; `b`: integer button (1 left).
    - `update(dt)` / `fixedUpdate(dt)` — `dt`: number seconds.
    - `serialize()` → table | `restore(data)` — save-slot persistence.
    - helpers: `localMouse()`, `layout()`, `print/printWrap/printFit`, `textScale()`.
- `unlockApp(id)` / `unlockLegacyApp(id)` / `removeApp(id)` — `id`: string.
- `listApps()` → array of strings.

## 7. Processes

- `addProcess(def)` — `def`: table
  - `key`: string (**required**); `name`: string; `ring`: **integer 0..6** (vanilla rings; 5 = MONADIC, 6 = ADI).
  - `deps`: array of key strings | nil; `apps`: array of app-id strings | nil.
  - `takes`: string effect id | nil; `watch`: array of strings | nil.
  - `present`: table | nil, e.g. `{unlocked="<id>"}`.
- `removeProcess(key)`, `killProcess(key)`, `reviveProcess(key)`, `isProcessDead(key)` — `key`: string → boolean (kill/revive/dead).
- `isEffectAlive(effect)` — `effect`: string effect id → boolean.
- `getKilledProcesses()` → table snapshot. `listProcesses()` → array of `{key,name,ring}`.

## 8. Materials & powers

- `addMaterial(id, name_en, name_jp, color, weight)`
  - `id`: string; names: strings (`name_jp` may equal en).
  - `color`: table `{r,g,b[,a]}` 0..1.
  - `weight`: number (default 10) — drop weight.
  - Creates pool `mat.<id>` (number, starts 0, re-seeded each run) + HUD chip gated `> 0`.
- `removeMaterial(id)` / `listMaterials()` — string / → array of strings.
- `addPower(def)` — `def.id`: string (**required**); `def.cost`: number (default 250); `def.requires`: table of ids (default {}).
- `removePower(id)` / `listPowers()`.

## 9. UI injection
- `openApp(appId)` — programmatically opens or focuses a registered desktop app window (`appId: string`). Returns the window object or `nil`.
- `closeApp(appId)` — closes an open app window by `id`. Returns `true` if closed, `false` if not currently open.
- `focusApp(appId)` — restores (if minimized) and brings an open app window to the front. Returns `true` on success.
- `getOpenApps()` — returns an array of `app.id` strings for all currently open desktop windows.
- `addPauseButton(id, label, fn[, danger])` — `fn(game, pauseMenu)`; `danger`: boolean|nil (red style).
- `addTitleButton(id, label, fn)` — `fn(game, titleScene)`.
- `removePauseButton(id)` / `removeTitleButton(id)` — string.
- `addOption(tab, label, rowDef)` — `tab`: **integer 1..3** (audio/display/game); `rowDef`: table
  - `key`: string (**required**, unique; value persists in `game.settings[key]`).
  - `kind`: `"toggle" | "slider" | "cycle" | "stepper"` (mod-safe). (`"wide"|"action"|"folder"` exist but bind panel-internal methods — avoid.)
  - `default`: boolean (toggle) | number (slider/stepper) | option `v` (cycle).
  - `min`,`max`: numbers (slider). `options`: array of `{v=any, label=string|labelId=string}` (cycle/stepper).
- `removeOption(key)` — string.
- `addCreditRow(kind, text)` — `kind`: `"gap" | "title" | "head" | "text"`; `text`: string|nil (nil for gap).
- `setStudioLogo(path)` — `path`: string image path (love-fs or absolute) → true; live-swaps current scene.
- `addHeadlineResource(key, label, color, owner, gate)`
  - `key`,`label`: strings; `color`: table `{r,g,b[,a]}` | nil (default amber).
  - `owner`: string app-id | nil; `gate`: `function(game)` → boolean | nil.
- `triggerCrash([skipBoost])` — `skipBoost`: boolean|nil; true = jump straight into the fault sequence.
- `playBoot([mode])` — `mode`: string|nil (default `"reboot"`; other modes per boot scene).
- `addBootModule(name)` / `removeBootModule(name)` / `listBootModules()` — string / → array of strings.

### 10. Cosmetics

* **`addTheme(row)`** — `row`: table
  * **`id`, `name`, `tip`**: strings (`id` is unique slug; `name` & `tip` are displayed in the Aesthetics app).
  * **`palette`**: table of `key → "#RRGGBB"` | `{r, g, b[, a]}` (all optional, fall back to `stock`):
    * **Core UI:** `wallpaper`, `fieldDark`, `field`, `fieldLight`, `line`, `lineBright`, `cream`, `creamDim`, `amber`, `amberDim`, `glowGood`, `bad`
    * **Window & Shell:** `titlebar`, `titlebar2`, `titlebarText`, `titlebarBlur`, `titlebarBlur2`, `titlebarTextBlur` *(inactive titlebar colors auto-derived if omitted)*, `shellFace`, `shellFaceHi`, `shellFaceLo`, `shellEdge`, `shellEdgeHi`, `shellLight`, `shellDark`, `shellText`, `shellTextDim`, `shellAccent`, `shellTray`, `iconText`, `iconGlyph`, `iconShadow`
  * **`chrome`**: table of window styling options:
    * `radius`: integer px (e.g. `0`, `2`, `7`, `8`, `10`)
    * `border`: integer px (`1` or `2`)
    * `gradDir`: `"h"` | `"v"` (titlebar gradient direction)
    * `buttons`: `"glyph"` | `"dots"` | `"boxes"`
    * `titleAlign`: `"left"` | `"center"`
    * `stripe`: `"rule"` | `"rainbow"` | `"hazard"` *(optional titlebar accent stripe)*
    * `gloss`: boolean *(optional glossy top highlight)*
    * `bevel`: boolean *(optional classic 3D bevel edge)*
    * `tray`: boolean *(system tray styling)*
  * **`wallpaper`**: table (`kind` + kind-specific hex colors):
    * `"grid"`: `{ kind = "grid", base = "#RRGGBB" }`
    * `"solid"`: `{ kind = "solid", base = "#RRGGBB", color = "#RRGGBB"[, dither = "#RRGGBB"] }` *(Note: `dither` may cause lag on some Windows OpenGL drivers)*
    * `"sky"`: `{ kind = "sky", base, sky1, sky2, hill, hill2, bubble }`
    * `"skyline"`: `{ kind = "skyline", base, top, mid, horizon, city, lit }`
    * `"dots"`: `{ kind = "dots", base, color, dots = { "#...", ... } }`
    * `"hex"`: `{ kind = "hex", base, color, ink }`
    * `"sunset"`: `{ kind = "sunset", base, top, horizon, sun1, sun2, floor, grid }`
    * `"lcd"`: `{ kind = "lcd", base, color, ink, dark }`
    * `"phosphor"`: `{ kind = "phosphor", base, color, ink }`
    * `"holo"`: `{ kind = "holo", base, color, blobs = { "#...", ... } }`
  * **`cursor`**: `"arrow"` | `"pixel"` | `"heart"` | `"cross"` | `"wand"` *(or any custom ID from `registerCursor`; default `"arrow"`)*
  * **`trail`**: `"sparkle"` | `"bubble"` | `"pixel"` | `"heart"` | `"star"` *(default `"sparkle"`)*
  * **`trailColors`**: array of `"#RRGGBB"` strings (e.g. `{ "#E8C170", "#F4ECD8", "#9BE8C9" }`)
  * **`crt`**: number `0..1` *(optional CRT scanline/curvature intensity, e.g. `1.0`)*

- `removeTheme(id)` / `listThemes()`.
- `registerCursor(id, drawFn)` — `id`: string; `drawFn(x, y, fill, outline)` numbers/colors, origin at hotspot, scale pre-applied.
- `registerFlag(lang, drawFn)` — `lang`: string code; `drawFn(x, y, w, h, alpha)` numbers + alpha 0..1.
- `registerMascot(id, name, path)` — injects a custom mascot image (`path` relative to game/save root, e.g. `"mods/mymod/mascot.png"`) into the **Aesthetics** app selector without requiring `animegirlN.png` naming.
- `setMascot(path[, opts])` — immediately sets the active desktop mascot image. Optional `opts`: `{ blend?: "overlay" | "normal", flip?: boolean, x?: number 0..1, y?: number 0..1, deg?: number, size?: number }`.

## 11. Audio

- `addMusicTrack(filePath)` — `filePath`: string (absolute OS path or love-fs path); appended to playlist on ready.
- `playSound(name[, pitch])` — `name`: string bank id (observed: `"tick" "deny" "upgrade" "explode" "static" "collapse" "complete" "virusPopup"`); `pitch`: number|nil.

## 12. Virus & guests

- `Virusinfect()` / `Viruscure()` / `isInfected()` → boolean.
- `addVirusAd(ad)` → integer index — `ad`: `{name=string|nil, title, body, button}`; each of title/body/button: string | `{en=…[, jp=…]}`. Survives ad reloads.
- `removeVirusAd(nameOrIndex)` — string name | integer index → boolean.
- `spawnVirusPopup([adIndex])` — `adIndex`: **integer 1..#ads** | nil (random) → window|nil.
- `setGhostCount(count)` → integer applied — `count`: **integer 0..4** (clamped to ghost pool; vanilla max 4). Sets a *floor*; single global value, last caller wins.
- `getGhosts()` → array of ghost records.

## 13. Transmissions

- `setTransmission(stage, lines)` — `stage`: integer; `lines`: array of string | `{en=…}`.
- `playTransmission(stageOrLines)` — integer existing stage **or** table lines (auto-stage 99) → boolean.

## 14. Endgame

- `setAscensionStrength(s)` — `s`: **number 0..1** | nil (nil restores) → true.
- `drawAscensionEye(k[, cx[, cy[, ew[, open]]]])` — `k`: **number 0..1**; `cx,cy`: numbers px (default screen center); `ew`: number px (default 240); `open`: **number 0..1** (default 1).
- `addDeliriumLine(tier, line)` — `tier`: **integer 1..4** (clamped to bucket count; vanilla 4); `line`: string | `{en=…}` → boolean.
- `setDeadLogActive(state)` — `state`: boolean | nil → true.
- `setDeadLogStrength(s)` — `s`: **number 0..1** (clamped) | nil.
- `pushDeadLog(text[, kind])` — `text`: string; `kind`: string tag (default `"voice"`) → boolean.

## 15. Platform adapter (Android slab)

Loaded only when `mods/android.lua` exists (never copied into desktop builds):
`listDirs(dir)` → array of strings; `pickFolder([hint])` → string|nil, err string;
`openFolder(dir)` mkdir+clipboard; `HostFS.pickFolder()` music convention;
two-finger drag ⇒ wheel; per-app IME focus + pause **KEYBOARD** button;
landscape native fullscreen + extra UIScale steps; storage re-probe on focus.

## 16. Overrides

`overrides/<module/path>.lua` returning a table replaces that module.
Statuses: `preloaded → applied | syntax error | runtime error | nil return`.
Already-loaded modules refused (Android) with a warning.

## 17. Worked examples

See repo `examples/` samples: *Void Singularity* (theme + `onReady` unlock),
*Quantum Clicker* (material + app + process + secret command + save persistence),
*modview* (core GUI: input/draw chains — **always call the wrapped original**).

## 18. Downsides

- `init` = register; `onReady`/`onLoad` = touch live objects.
- Terminal `fn` first param is **args**, not game — capture `game` as upvalue.
- `setGhostCount` is a floor; one global; last call wins.
- `toggleMod` needs restart for full effect.
- Mods run **unsandboxed** (`io`, `os`, `ffi`). Trust what you install.
- Builds set `game.noSteam = true`: leaderboards/cloud untouched by design.
