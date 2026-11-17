-- god forgive me if someone will read this
local Api = {}
function Api.create(game, loaderState)
  local saveDir = love.filesystem.getSaveDirectory()
  local StringStore = require("src.services.strings")
  local PauseMenu = require("src.ui.pausemenu")
  local OptionsPanel = require("src.ui.options_panel")
  local Taskbar = require("src.ui.taskbar")
  local AppRegistry = require("src.services.apps")

  local modLabels = {}
  local modBilingual = {}
  local keyHandlers = {}
  local readyQueue = {}
  local modPools = {}
  local pauseButtons = {}
  local modOptions = {}
  local headlineQueue = {}
  local forcedApps = {}
  local isReady = false

  if not StringStore._modPatched then
    StringStore._modPatched = true

    local origLine = StringStore.line
    function StringStore:line(key, ...)
      if modLabels[key] then return modLabels[key] end
      return origLine(self, key, ...)
    end

    local origBi = StringStore.bilingual
    function StringStore:bilingual(key, ...)
      if modBilingual[key] then
        local entry = modBilingual[key]
        return entry.jp, entry.en
      end
      return origBi(self, key, ...)
    end
  

  local origActivate = PauseMenu.activate
  function PauseMenu:activate(id, ...)
    for _, btn in ipairs(pauseButtons) do
      if btn.id == id then
        if btn.fn then btn.fn(self.game, self) end
        return
      end
    end
    return origActivate(self, id, ...)
  end

  local origMainItems = PauseMenu.mainItems
  function PauseMenu:mainItems(...)
    local items = origMainItems(self, ...)
    if #pauseButtons > 0 then
      local w, h = love.graphics.getDimensions()
      local bw, bh, gap = 300, 44, 12
      -- Insert custom buttons right before "quitMenu"
      local insertAt = math.max(1, #items - 1)
      for _, btn in ipairs(pauseButtons) do
        table.insert(items, insertAt, {
          id = btn.id,
          labelId = btn.labelId,
          danger = btn.danger,
        })
        insertAt = insertAt + 1
      end
      local listH = #items * bh + (#items - 1) * gap
      local x, y = (w - bw) / 2, (h - listH) / 2 + 20
      for i, it in ipairs(items) do
        it.x, it.y, it.w, it.h = x, y + (i - 1) * (bh + gap), bw, bh
      end
    end
    return items
  end
  local origModel = OptionsPanel.model
  function OptionsPanel:model(...)
    local tabs = origModel(self, ...)
    for _, opt in ipairs(modOptions) do
      local tab = tabs[opt.tab or 3]
      if tab and tab.rows then
        table.insert(tab.rows, opt.row)
      end
    end
    return tabs
  end

  end
  local origDefine = game.defineSharedPools
  if origDefine then
    function game:defineSharedPools(...)
      origDefine(self, ...)
      for _, k in ipairs(modPools) do
        if self.resources and self.resources.pools and self.resources.pools[k] == nil then
          self.resources.pools[k] = 0
        end
      end
    end
  end
  local function onReady(fn)
    if isReady then
      fn(game)
    else
      table.insert(readyQueue, fn)
    end
  end

  local origAppsReset = AppRegistry.reset
  function AppRegistry:reset(...)
    origAppsReset(self, ...)
    for id in pairs(forcedApps) do
      self:unlock(id)
    end
  end

  local origAppsRestore = AppRegistry.restore
  function AppRegistry:restore(...)
    origAppsRestore(self, ...)
    for id in pairs(forcedApps) do
      self:unlock(id)
    end
  end
  -- Wrap game:load so deferred hooks + mod:onLoad(game) run once all services are alive
  local origGameLoad = game.load
  function game:load(...)
    origGameLoad(self, ...)
    isReady = true

    for _, fn in ipairs(readyQueue) do
      local ok, err = pcall(fn, self)
      if not ok then print("[ModAPI] Deferred hook error: " .. tostring(err)) end
    end
    readyQueue = {}

    for _, mod in ipairs(loaderState.loaded) do
      if mod.onLoad then
        local ok, err = pcall(mod.onLoad, mod, self, mod._folder)
        if not ok then
          mod._error = tostring(err)
          print("[ModLoader] onLoad error in " .. tostring(mod._folder) .. ": " .. tostring(err))
        end
      end
    end
  end

  -- Chainable hotkey dispatcher
  local origKeyPressed = game.keypressed
  function game:keypressed(key, scancode, isrepeat)
    local list = keyHandlers[key]
    if list then
      for _, fn in ipairs(list) do
        if fn(self, key, scancode, isrepeat) == true then return end
      end
    end
    return origKeyPressed(self, key, scancode, isrepeat)
  end
  
  local origTaskbarNew = Taskbar.new
  function Taskbar:new(g, desktop)
    origTaskbarNew(self, g, desktop)
    for _, item in ipairs(headlineQueue) do
      table.insert(self.headline, item)
    end
  end

  local api = {
    version = loaderState.api,
    api = loaderState.api,
    loaded = loaderState.loaded,
    overrides = loaderState.overrides,
    onReady = function(self, fn) onReady(fn) end,

    openFolder = function()
      local path = saveDir:gsub("\\", "/"):gsub(" ", "%%20")
      local url = "file://" .. (path:sub(1, 1) == "/" and "" or "/") .. path
      return love.system.openURL(url)
    end,

    get = function(self, name)
      for _, m in ipairs(loaderState.loaded) do
        if (m.name or m._folder) == name then return m end
      end
    end,

    onKey = function(self, key, fn)
      keyHandlers[key] = keyHandlers[key] or {}
      table.insert(keyHandlers[key], fn)
    end,

    -- TERMINAL & LOGBOOK
    addTerminalCommand = function(self, def)
      local secrets = require("src.data.terminal_secrets")
      table.insert(secrets, def)
      
      -- FIX 1: Prevent double-insertion race condition
      if package.loaded["src.data.terminal"] then
        table.insert(package.loaded["src.data.terminal"].commands, def)
      end
    end,

    addLog = function(self, key, text, kao, glitch)
      local logs = require("src.data.logs")
      table.insert(logs, { key = key, en = text, kao = kao, glitch = glitch })
    end,

    pushLog = function(self, text, glitch)
      if game.logbook then game.logbook:push(text, glitch or 0) end
    end,

    -- LOCALIZATION
      addString = function(self, key, translations)
    modLabels[key] = type(translations) == "table"
      and (translations.en or select(2, next(translations)))
      or tostring(translations)
    onReady(function(g)
      if g.strings and g.strings.registry then
        g.strings.registry[key] = translations
      end
    end)
  end,

    addHeadlineResource = function(self, key, label, color, owner, gate)
        local labelId = "res." .. key:gsub("%.", "_")
  
        -- HUD
        onReady(function(g)
            if g.strings and g.strings.registry then
                g.strings.registry[labelId] = { en = label, jp = label }
            end
        end)

        local entry = {
            key = key,
            color = color or Theme.color.amber,
            labelId = labelId,
            owner = owner,
            gate = gate
        }
        table.insert(headlineQueue, entry)

        -- if created
        local cur = game.scenes and game.scenes:current()
        if cur and cur.taskbar and cur.taskbar.headline then
            table.insert(cur.taskbar.headline, entry)
        end
    end,
    -- APPS & MANIFEST
    registerApp = function(self, def, AppClass)
      assert(def and def.id, "registerApp requires def.id")
      local modPath = "mods.virtual_app_" .. def.id
      def.module = modPath
      def.titleId = def.titleId or ("app." .. def.id)
      def.icon = def.icon or "量"
      def.unlock = def.unlock or { always = true }

      package.preload[modPath] = function() return AppClass end

      local manifest = require("src.data.apps")
      table.insert(manifest, def)

      -- Inject directly into the already-constructed AppRegistry!
      if game and game.apps then
        game.apps.defs[def.id] = def
        table.insert(game.apps.order, def.id)
      end

      -- Register bilingual title & subtitle in StringStore:line
          if type(def.title) == "string" then
      modLabels[def.titleId] = def.title
      modBilingual[def.titleId] = {
        jp = def.title_jp or def.sub or def.title,
        en = def.title
      }
    end


    end,

    unlockApp = function(self, id)
      forcedApps[id] = true
      local manifest = require("src.data.apps")
      for _, appDef in ipairs(manifest) do
        if appDef.id == id then
          appDef.unlock = { always = true }
          appDef.demoHidden = nil
        end
      end
      if game and game.apps then
        game.apps:unlock(id)
      end
      return true
    end,


    unlockLegacyApp = function(self, id)
      local manifest = require("src.data.apps")
      for _, appDef in ipairs(manifest) do
        if appDef.id == id then
          appDef.unlock = { always = true }
          appDef.demoHidden = nil
          return true
        end
      end
      return false
    end,

    -- DATA TABLES
    addMaterial = function(self, id, name_en, name_jp, color, weight)
      local materials = require("src.data.materials")
      local matKey = materials.key(id)
      local labelId = "res.mod_" .. id
      local c = color or { 0.85, 0.65, 1.0 }
      local matColor = { c[1] or 0.85, c[2] or 0.65, c[3] or 1.0, c[4] or 1 }
      table.insert(modPools, matKey)
        if game.resources and game.resources.pools and game.resources.pools[matKey] == nil then
        game.resources.pools[matKey] = 0
        end


      local mat = {
        id = id,
        name = { en = name_en, jp = name_jp or name_en },
        color = matColor,
        weight = weight or 10
      }
      table.insert(materials.list, mat)
      materials.byId[id] = mat

      -- Ensure StringStore:line(labelId) always resolves cleanly
          modLabels[labelId] = name_en:upper()
    onReady(function(g)
      if g.resources and g.resources.pools and g.resources.pools[matKey] == nil then
        g.resources.pools[matKey] = 0
      end
    end)


      local hudEntry = {
        key = matKey,
        color = matColor,
        labelId = labelId,
        gate = function(g)
          return (g.resources:get(matKey) or 0) > 0
        end
      }

      table.insert(headlineQueue, hudEntry)
      local cur = game.scenes and game.scenes:current()
      if cur and cur.taskbar and cur.taskbar.headline then
        table.insert(cur.taskbar.headline, hudEntry)
      end
    end,

    discovered = loaderState.discovered,
    disabled = loaderState.disabled,

    toggleMod = function(self, folder)
      if folder == "modviewr" then return false end
      local nextState = not (loaderState.disabled[folder] == true)
      loaderState.disabled[folder] = nextState or nil
      loaderState.saveConfig()
      for _, m in ipairs(loaderState.discovered) do
        if m._folder == folder then
          m._enabled = not nextState
        end
      end
      return not nextState
    end,

    restart = function(self)
      love.event.quit("restart")
    end,

    ui = setmetatable({}, {
    __index = function(t, k)
      local map = {
        Widgets = "src.ui.widgets",
        Theme   = "src.ui.theme",
        Cursor  = "src.ui.cursor",
        Rect    = "src.core.rect",
        Format  = "src.core.format",
      }
      if map[k] then
        t[k] = require(map[k])
        return t[k]
      end
    end
  }),

  addBootModule = function(self, moduleName)
    local Script = require("src.data.boot")
    if Script and Script.modules then
      table.insert(Script.modules, moduleName)
    end
  end,
  
    removeBootModule = function(self, moduleName)
      local Script = require("src.data.boot")
      if Script and Script.modules then
        for i = #Script.modules, 1, -1 do
          if Script.modules[i] == moduleName then
            table.remove(Script.modules, i)
            return true
          end
        end
      end
      return false
    end,

    listBootModules = function(self)
      local Script = require("src.data.boot")
      local out = {}
      if Script and Script.modules then
        for _, m in ipairs(Script.modules) do out[#out + 1] = m end
      end
      return out
    end,

  playBoot = function(self, mode)
    local BootScene = require("src.scenes.boot")
    if game and game.scenes then
      game.scenes:push(BootScene(game, { mode = mode or "reboot" }))
    end
  end,

  addPauseButton = function(self, id, label, fn, danger)
    local labelId = "pause.mod_" .. id
    modLabels[labelId] = label
    table.insert(pauseButtons, { id = id, labelId = labelId, fn = fn, danger = danger })
  end,

  addOption = function(self, tabIndex, label, rowDef)
    local labelId = "opt.mod_" .. rowDef.key
    modLabels[labelId] = label
    rowDef.labelId = labelId
    if rowDef.default ~= nil and game.settings and game.settings[rowDef.key] == nil then
      game.settings[rowDef.key] = rowDef.default
    end
    table.insert(modOptions, { tab = tabIndex or 3, row = rowDef })
  end,

    triggerCrash = function(self, skipBoost)
      local Crash = require("src.ui.crash")
      if game and not game.crash then
        game.crash = Crash(game)
        if skipBoost then
          game.crash:advance()
        end
      end
    end,

    addPower = function(self, def)
      local Powers = require("src.data.powers")
      local balance = require("src.data.balance")
      assert(def and def.id, "addPower requires def.id")

      def.index = #Powers.list + 1
      table.insert(Powers.list, def)
      Powers.byId[def.id] = def

      if balance and balance.engage then
        balance.engage.powerCost = balance.engage.powerCost or {}
        balance.engage.powerCost[def.id] = balance.engage.powerCost[def.id] or def.cost or 250
        balance.engage.powerRequires = balance.engage.powerRequires or {}
        balance.engage.powerRequires[def.id] = balance.engage.powerRequires[def.id] or def.requires or {}
      end
    end,

     addProcess = function(self, def)
   local P = require("src.data.processes")
   assert(def and def.key, "addProcess requires def.key")
   def.deps = def.deps or {}
   def.index = #P.list + 1
   table.insert(P.list, def)

   P.byKey[def.key] = def
   if P.byRing[def.ring] then table.insert(P.byRing[def.ring], def) end
   if def.takes then
     P.byEffect[def.takes] = def
     table.insert(P.EFFECTS, def.takes)
     table.sort(P.EFFECTS)
   end
   if def.apps then
     for _, app_id in ipairs(def.apps) do P.byApp[app_id] = def end
   end
   if def.watch then
     for _, w in ipairs(def.watch) do P.watchedBy[w] = def.key end
   end
 end,
      -- INSPECTION (LIST VANILLA + MODDED ENTRIES)
    listApps = function(self)
      local out = {}
      for _, def in ipairs(require("src.data.apps")) do out[#out + 1] = def.id end
      return out
    end,
     
    removeApp = function(self, id)
  forcedApps[id] = nil
  local manifest = require("src.data.apps")
  for i = #manifest, 1, -1 do
    if manifest[i].id == id then table.remove(manifest, i) end
  end
  if game and game.apps then
    game.apps.defs[id] = nil
    if game.apps.unlocked then game.apps.unlocked[id] = nil end
    for i = #game.apps.order, 1, -1 do
      if game.apps.order[i] == id then table.remove(game.apps.order, i) end
    end
  end
  local scene = game and game.runScene and game:runScene()
  if scene and scene.wm and scene.wm.windowForApp then
    local win = scene.wm:windowForApp(id)
    if win then scene.wm:close(win) end
  end
end,

    listProcesses = function(self)
      local out = {}
      for _, def in ipairs(require("src.data.processes").list) do
        out[#out + 1] = { key = def.key, name = def.name, ring = def.ring }
      end
      return out
    end,

    removeProcess = function(self, key)
  local P = require("src.data.processes")
  local def = P.byKey[key]
  if not def then return false end
  P.byKey[key] = nil
  for i = #P.list, 1, -1 do
    if P.list[i].key == key then table.remove(P.list, i) end
  end
  if P.byRing[def.ring] then
    for i = #P.byRing[def.ring], 1, -1 do
      if P.byRing[def.ring][i].key == key then table.remove(P.byRing[def.ring], i) end
    end
  end
  if def.takes then P.byEffect[def.takes] = nil end
  if def.apps then
    for _, app_id in ipairs(def.apps) do P.byApp[app_id] = nil end
  end
  return true
end,


    listMaterials = function(self)
      local out = {}
      for _, mat in ipairs(require("src.data.materials").list) do out[#out + 1] = mat.id end
      return out
    end,

    listPowers = function(self)
      local out = {}
      for _, p in ipairs(require("src.data.powers").list) do out[#out + 1] = p.id end
      return out
    end,

    listThemes = function(self)
      local out = {}
      for _, t in ipairs(require("src.data.aesthetics").list) do out[#out + 1] = t.id end
      return out
    end,

    removeTheme = function(self, id)
  local Aesthetics = require("src.data.aesthetics")
  Aesthetics.byId[id] = nil
  for i = #Aesthetics.list, 1, -1 do
    if Aesthetics.list[i].id == id then table.remove(Aesthetics.list, i) end
  end
end,


    listTerminalCommands = function(self)
      local out = {}
      for _, cmd in ipairs(require("src.data.terminal_secrets")) do out[#out + 1] = cmd.name end
      return out
    end,

    removeTerminalCommand = function(self, name)
  local secrets = require("src.data.terminal_secrets")
  for i = #secrets, 1, -1 do
    if secrets[i].name == name then table.remove(secrets, i) end
  end
  if package.loaded["src.data.terminal"] then
    local cmds = package.loaded["src.data.terminal"].commands
    for i = #cmds, 1, -1 do
      if cmds[i].name == name then table.remove(cmds, i) end
    end
  end
end,

removePauseButton = function(self, id)
  for i = #pauseButtons, 1, -1 do
    if pauseButtons[i].id == id then table.remove(pauseButtons, i) end
  end
end,

removeOption = function(self, key)
  for i = #modOptions, 1, -1 do
    if modOptions[i].row and modOptions[i].row.key == key then table.remove(modOptions, i) end
  end
end,

removeMaterial = function(self, id)
  local materials = require("src.data.materials")
  local matKey = materials.key(id)
  materials.byId[id] = nil
  for i = #materials.list, 1, -1 do
    if materials.list[i].id == id then table.remove(materials.list, i) end
  end
  for i = #headlineQueue, 1, -1 do
    if headlineQueue[i].key == matKey then table.remove(headlineQueue, i) end
  end
end,

removePower = function(self, id)
  local Powers = require("src.data.powers")
  local balance = require("src.data.balance")
  Powers.byId[id] = nil
  for i = #Powers.list, 1, -1 do
    if Powers.list[i].id == id then table.remove(Powers.list, i) end
  end
  if balance and balance.engage then
    if balance.engage.powerCost then balance.engage.powerCost[id] = nil end
    if balance.engage.powerRequires then balance.engage.powerRequires[id] = nil end
  end
end,

    
    -- MUSIC & AUDIO
    -- Add a custom audio file (from your mod folder or %APPDATA%) to the LLAMA playlist
    addMusicTrack = function(self, filePath)
      onReady(function(g)
        if g.audio and g.audio.tracks then
          table.insert(g.audio.tracks, filePath)
        end
      end)
    end,

    -- Play a sound effect or control music playback cleanly
    playSound = function(self, name, pitch)
      if game and game.audio then
        game.audio:play(name, pitch)
      end
    end,

    -- AESTHETICS
    addTheme = function(self, row)
      local Theme = require("src.ui.theme")
      local Aesthetics = require("src.data.aesthetics")
      row.index = #Aesthetics.list + 1
      row.nameId = row.nameId or ("aesthetics.theme." .. row.id)
      row.tipId = row.tipId or ("aesthetics.tip." .. row.id)
      row.palette = row.palette or {}
      row.chrome = row.chrome or { radius = 0, border = 1, buttons = "glyph", titleAlign = "left" }
      row.wallpaper = row.wallpaper or { kind = "grid", base = "#0A2429" }
      row.cursor = row.cursor or "arrow"
      row.trail = row.trail or "sparkle"
      row.trailColors = row.trailColors or { "#E8C170", "#F4ECD8", "#9BE8C9" }

      -- Register display name & description in StringStore
      if row.name then modLabels[row.nameId] = row.name end
      if row.tip then modLabels[row.tipId] = row.tip end


      local res = {}
      for k, v in pairs(Theme.stock) do res[k] = { v[1], v[2], v[3], v[4] } end
      for k, v in pairs(row.palette) do

          res[k] = type(v) == "string" and Theme.hex(v) or { v[1], v[2], v[3], v[4] or 1 }

      end

      -- Auto-derive inactive window titlebar colors when not explicitly specified
      if not row.palette.titlebarBlur and res.titlebar then
        res.titlebarBlur = { res.titlebar[1] * 0.45, res.titlebar[2] * 0.45, res.titlebar[3] * 0.45, res.titlebar[4] or 1 }
      end
      if not row.palette.titlebarBlur2 and res.titlebar2 then
        res.titlebarBlur2 = { res.titlebar2[1] * 0.45, res.titlebar2[2] * 0.45, res.titlebar2[3] * 0.45, res.titlebar2[4] or 1 }
      end
      if not row.palette.titlebarTextBlur and res.titlebarText then
        res.titlebarTextBlur = { res.titlebarText[1] * 0.65, res.titlebarText[2] * 0.65, res.titlebarText[3] * 0.65, res.titlebarText[4] or 1 }
      end

      row.resolved = res
      local cols = {}
      for j, h in ipairs(row.trailColors) do cols[j] = Theme.hex(h) end
      row.trailRGB = cols

      table.insert(Aesthetics.list, row)
      Aesthetics.byId[row.id] = row
    end,

  }
  local androidChunk = love.filesystem.load("mods/android.lua")
  if androidChunk then
    local ok, Android = pcall(androidChunk)
    if ok and type(Android) == "table" and Android.apply then
      Android.apply(game, api, loaderState)
    end
  end
  return api
end

return Api