-- god forgive me if someone will read this
local Api = {}
function Api.create(game, loaderState)
  local saveDir = love.filesystem.getSaveDirectory()
  local StringStore = require("src.services.strings")
  local PauseMenu = require("src.ui.pausemenu")
  local OptionsPanel = require("src.ui.options_panel")
  local Taskbar = require("src.ui.taskbar")
  local AppRegistry = require("src.services.apps")
  local Theme = require("src.ui.theme")
  local WallpaperOverlay = require("src.ui.wallpaper_overlay")

  local customMascots = {}
  local creditInjections = {}
  local titleButtons = {}
  local modLabels = {}
  local modBilingual = {}
  local keyHandlers = {}
  local readyQueue = {}
  local modPools = {}
  local pauseButtons = {}
  local modOptions = {}
  local headlineQueue = {}
  local forcedApps = {}
  
  local origMascotScan = nil
  local isReady = false
  local titlePatched = false
  local origCreditsParse = nil

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
   
local function ensureMascotPatched()
  if origMascotScan then return end
  origMascotScan = WallpaperOverlay.scan
  function WallpaperOverlay.scan(items, dir, ...)
    local found = origMascotScan(items, dir, ...)
    local baseN = #found
    for i, m in ipairs(customMascots) do
      found[#found + 1] = {
        n = baseN + i,
        path = m.path,
        name = m.name or m.id,
      }
    end
    return found
  end
end

   local function ensureCreditsPatched()
    if origCreditsParse then return end
    local Credits = require("src.scenes.credits")
    origCreditsParse = Credits.parse
    function Credits.parse(text, ...)
      local rows = origCreditsParse(text, ...)
      for _, row in ipairs(creditInjections) do
        table.insert(rows, row)
      end
      return rows
    end
  end

  local function ensureTitlePatched()
    if titlePatched then return end
    titlePatched = true
    local Title = require("src.scenes.title")
    local Rect = require("src.core.rect")
    local balance = require("src.data.balance")

    local origMainItems = Title.mainItems
    function Title:mainItems(...)
      local items = origMainItems(self, ...)
      if #titleButtons == 0 then return items end

      local w, h = love.graphics.getDimensions()
      local cfg = balance.titleLayout
      local bw = 280
      local x = (w - bw) / 2

      local mainCol, barCol = {}, {}
      for _, it in ipairs(items) do
        if it.column == "bar" then barCol[#barCol + 1] = it else mainCol[#mainCol + 1] = it end
      end

      local insertAt = math.max(1, #mainCol)
      for _, btn in ipairs(titleButtons) do
        table.insert(mainCol, insertAt, {
          id = btn.id,
          labelId = btn.labelId,
          enabled = true,
        })
        insertAt = insertAt + 1
      end

      local extra = self.recent and 24 or 0
      local n = #mainCol
      local floorY, bottomY = h * 0.46, self:barTop() - cfg.barClear
      local avail = math.max(140, bottomY - floorY)
      local rowMax = math.max(46, h * cfg.rowShare)
      local bh = math.max(26, math.min(rowMax, (avail - extra - 14 * (n - 1)) / n))
      local gap = math.max(6, math.min(14, (avail - extra - bh * n) / math.max(1, n - 1)))
      local blockH = bh * n + extra + gap * (n - 1)
      local masthead = self:mastheadBottom()
      local y = math.max(floorY, masthead + (bottomY - masthead - blockH) / 2)

      local out = {}
      for _, it in ipairs(mainCol) do
        it.x, it.y, it.w = x, y, bw
        it.h = bh + (it.tall and extra or 0)
        y = y + it.h + gap
        out[#out + 1] = it
      end
      for _, it in ipairs(barCol) do out[#out + 1] = it end
      return out
    end

    local origMouse = Title.mousepressed
    function Title:mousepressed(mx, my, b, ...)
      if b == 1 and not self.confirm and self.page == "main" and #titleButtons > 0 then
        for _, it in ipairs(self:mainItems()) do
          if it.enabled and Rect.contains(it.x, it.y, it.w, it.h, mx, my) then
            for _, btn in ipairs(titleButtons) do
              if btn.id == it.id then
                if btn.fn then btn.fn(self.game, self) end
                return
              end
            end
          end
        end
      end
      return origMouse(self, mx, my, b, ...)
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

    addCreditRow = function(self, kind, text)
  ensureCreditsPatched()
  -- kind: "gap", "title", "head", or "text"
  table.insert(creditInjections, {
    kind = kind or "text",
    text = text ~= nil and tostring(text) or nil,
  })
end,

    setStudioLogo = function(self, path)
      local balance = require("src.data.balance")
      balance.studio.logo = path
      local cur = game and game.scenes and game.scenes:current()
      if cur and cur.studioLogo then
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
          img:setFilter("linear", "linear")
          cur.studioLogo = img
        end
      end
      return true
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

    setAscensionStrength = function(self, strength)
   local Ascension = require("src.ui.ascension")
   if not Ascension._modPatched then
     Ascension._modPatched = true
     Ascension._modForceK = nil
     local origUnder = Ascension.drawUnder
     function Ascension.drawUnder(k, ...)
       return origUnder(Ascension._modForceK ~= nil and Ascension._modForceK or k, ...)
     end
     local origOver = Ascension.drawOver
     function Ascension.drawOver(k, ...)
       return origOver(Ascension._modForceK ~= nil and Ascension._modForceK or k, ...)
     end
     local origJitter = Ascension.jitter
     function Ascension.jitter(k, ...)
       return origJitter(Ascension._modForceK ~= nil and Ascension._modForceK or k, ...)
     end
     local origLabel = Ascension.labelStrength
     function Ascension.labelStrength(k)
       return origLabel(Ascension._modForceK ~= nil and Ascension._modForceK or k)
     end
   end
   Ascension._modForceK = strength and math.max(0, math.min(1, strength)) or nil
   return true
 end,

     registerFlag = function(self, lang, drawFn)
      assert(type(lang) == "string" and type(drawFn) == "function", "registerFlag(lang, drawFn) invalid args")
      local Flags = require("src.ui.flags")
      if not Flags._modFlags then
        Flags._modFlags = {}
        local origDraw = Flags.draw
        function Flags.draw(l, x, y, w, h, alpha)
          if Flags._modFlags[l] then
            Flags._modFlags[l](x, y, w, h, alpha or 1)
            love.graphics.setColor(1, 1, 1, 1)
            return
          end
          return origDraw(l, x, y, w, h, alpha)
        end
      end
      Flags._modFlags[lang] = drawFn
      return true
    end,

 drawAscensionEye = function(self, k, cx, cy, ew, open)
   local Ascension = require("src.ui.ascension")
   local w, h = love.graphics.getDimensions()
   local mx, my = love.mouse.getPosition()
   Ascension.drawEye(k or 1, love.timer.getTime(), w, h, mx, my, cx or w / 2, cy or h / 2, ew or 240, open or 1)
 end,

    -- DEADLOG
    addDeliriumLine = function(self, tier, line)
      local Delirium = require("src.data.delirium")
      local idx = math.max(1, math.min(#Delirium, tonumber(tier) or 1))
      local bucket = Delirium[idx]
      if not bucket then return false end
      local entry = type(line) == "table" and line or { en = tostring(line) }
      table.insert(bucket, entry)
      return true
    end,

    setDeadLogActive = function(self, state)
      local DeadLog = require("src.ui.deadlog")
      if not DeadLog._origActive then
        DeadLog._origActive = DeadLog.active
        DeadLog._modForceActive = nil
        function DeadLog.active(g)
          if DeadLog._modForceActive ~= nil then
            return DeadLog._modForceActive
          end
          return DeadLog._origActive(g)
        end
      end
      DeadLog._modForceActive = state
      return true
    end,

    setDeadLogStrength = function(self, strength)
      local DeadLog = require("src.ui.deadlog")
      if not DeadLog._origStrength then
        DeadLog._origStrength = DeadLog.strength
        DeadLog._modForceStrength = nil
        function DeadLog.strength(g)
          if DeadLog._modForceStrength ~= nil then
            return math.max(0, math.min(1, DeadLog._modForceStrength))
          end
          return DeadLog._origStrength(g)
        end
      end
      DeadLog._modForceStrength = strength
      return true
    end,

    pushDeadLog = function(self, text, kind)
      local cur = game.scenes and game.scenes:current()
      local dl = cur and (cur.deadLog or cur.deadlog)
      if not dl or not dl.push then return false end
      local ms = game.runtimer and game.runtimer.cumulativeMs or 0
      dl:push({ text = tostring(text), kind = kind or "voice", atMs = ms })
      return true
    end,
    

     registerMascot = function(self, id, name, path)
   ensureMascotPatched()
   for i = #customMascots, 1, -1 do
     if customMascots[i].id == id then table.remove(customMascots, i) end
   end
   table.insert(customMascots, { id = id, name = name or id, path = path })
   return true
 end,

 setMascot = function(self, path, opts)
   local overlay = game and game.desktop and game.desktop.overlay
   if not overlay then return false end
   if path then overlay:setImage(path) end
   if opts then
     if opts.blend then overlay:setBlend(opts.blend) end
     if opts.flip ~= nil then overlay:setFlip(opts.flip) end
     if opts.x or opts.y or opts.deg or opts.size then
       overlay:setPlacement(
         opts.x ~= nil and opts.x or overlay.posX,
         opts.y ~= nil and opts.y or overlay.posY,
         opts.deg ~= nil and opts.deg or math.deg(overlay.rot or 0),
         opts.size ~= nil and opts.size or overlay.size
       )
     end
   end
   return true
 end,

    -- VIRUS, POPUPS & GUEST CURSORS
    Virusinfect = function(self)
      local Virus = require("src.services.virus")
      return Virus.infect(game)
    end,

    Viruscure = function(self)
      local Virus = require("src.services.virus")
      return Virus.cure(game)
    end,

    isInfected = function(self)
      local Virus = require("src.services.virus")
      return Virus.active(game)
    end,

    addVirusAd = function(self, ad)
      assert(type(ad) == "table", "addVirusAd requires a table")
      local VirusAds = require("src.data.virusads")
      local row = {
        name = ad.name or ("mod_ad_" .. (#VirusAds.list + 1)),
        title = type(ad.title) == "table" and ad.title or { en = tostring(ad.title or "!!") },
        body = type(ad.body) == "table" and ad.body or { en = tostring(ad.body or "") },
        button = type(ad.button) == "table" and ad.button or { en = tostring(ad.button or "OK") },
      }
      if not VirusAds._modAds then
        VirusAds._modAds = {}
        local origReload = VirusAds.reload
        function VirusAds.reload()
          local list = origReload()
          for _, m in ipairs(VirusAds._modAds) do
            table.insert(list, m)
          end
          return list
        end
      end
      table.insert(VirusAds._modAds, row)
      table.insert(VirusAds.list, row)
      return #VirusAds.list
    end,
    
    removeVirusAd = function(self, nameOrIndex)
      local VirusAds = require("src.data.virusads")
      if VirusAds._modAds then
        for i = #VirusAds._modAds, 1, -1 do
          if i == nameOrIndex or VirusAds._modAds[i].name == nameOrIndex then
            table.remove(VirusAds._modAds, i)
          end
        end
      end
      for i = #VirusAds.list, 1, -1 do
        if i == nameOrIndex or VirusAds.list[i].name == nameOrIndex then
          table.remove(VirusAds.list, i)
          return true
        end
      end
      return false
    end,

    spawnVirusPopup = function(self, adIndex)
      local cur = game.scenes and game.scenes:current()
      local vfx = cur and (cur.virusFx or cur.virus)
      if not vfx or not vfx.spawnPopup then return nil end
      if adIndex then
        local VirusAds = require("src.data.virusads")
        if VirusAds.list[adIndex] then
          vfx.serial = (vfx.serial or 0) + 1
          local Popup = require("src.ui.viruspopup")
          local app = Popup(game, vfx.serial, adIndex)
          local wa = cur:workArea()
          local P = require("src.data.balance").virus.popup
          local x = wa.x + love.math.random(0, math.max(0, wa.w - P.w))
          local y = wa.y + love.math.random(0, math.max(0, wa.h - P.h))
          return cur:openWindow(app, { titleText = app:titleText(), x = x, y = y })
        end
      end
      return vfx:spawnPopup()
    end,

    setGhostCount = function(self, count)
      local Virus = require("src.services.virus")
      local VirusFx = require("src.ui.virusfx")
      if not Virus._origGhostCount then
        Virus._origGhostCount = Virus.ghostCount
        Virus._modGhostMin = 0
        function Virus.ghostCount(p)
          return math.max(Virus._modGhostMin or 0, Virus._origGhostCount(p))
        end
      end
      if not VirusFx._modUpdatePatched then
        VirusFx._modUpdatePatched = true
        local origUpdate = VirusFx.update
        function VirusFx:update(dt)
          origUpdate(self, dt)
          if not self:active() and (Virus._modGhostMin or 0) > 0 and not self.game.paused then
            local d = self.desktop
            if d and not d:isModalOpen() and d:has("icons") then
              local want = Virus._modGhostMin
              for k, gh in ipairs(self.ghosts) do
                if k <= want and not gh.on then self:wake(gh)
                elseif k > want and gh.on and not gh.job then gh.on = false end
                if gh.on then self:drive(gh, dt) end
              end
              self.logT = math.max(0, self.logT - dt)
            end
          end
        end
      end
      local cur = game.scenes and game.scenes:current()
      local vfx = cur and (cur.virusFx or cur.virus)
      local maxG = vfx and vfx.ghosts and #vfx.ghosts or 4
      Virus._modGhostMin = math.max(0, math.min(maxG, count or 0))
      if vfx and vfx.ghosts then
        for k = 1, Virus._modGhostMin do
          if vfx.ghosts[k] and not vfx.ghosts[k].on then
            vfx:wake(vfx.ghosts[k])
          end
        end
      end
      return Virus._modGhostMin
    end,

    getGhosts = function(self)
      local cur = game.scenes and game.scenes:current()
      local vfx = cur and (cur.virusFx or cur.virus)
      return vfx and vfx.ghosts or {}
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

    openApp = function(self, appId)
      local scene = (game and game.runScene and game:runScene()) or (game and game.scenes and game.scenes:current())
      if not scene then return nil end
      if scene.openApp then return scene:openApp(appId) end
      if scene.launch then return scene:launch(appId) end
      if scene.launchApp then return scene:launchApp(appId) end
      return nil
    end,


    closeApp = function(self, appId)
      local scene = game and game.runScene and game:runScene()
      local wm = scene and scene.wm
      if not wm then return false end
      local w = wm:windowForApp(appId)
      if not w then return false end
      if w.close then w:close() else wm:close(w) end
      return true
    end,

    focusApp = function(self, appId)
      local scene = game and game.runScene and game:runScene()
      local wm = scene and scene.wm
      if not wm then return false end
      local w = wm:windowForApp(appId)
      if not w then return false end
      if w.state == "minimized" and w.restore then w:restore() end
      wm:bringToFront(w)
      return true
    end,

    getOpenApps = function(self)
      local scene = game and game.runScene and game:runScene()
      local wm = scene and scene.wm
      local out = {}
      if not wm or not wm.windows then return out end
      for _, w in ipairs(wm.windows) do
        if w.app and w.app.id then
          out[#out + 1] = w.app.id
        end
      end
      return out
    end,

    -- TRANSMISSIONS
    setTransmission = function(self, stage, lines)
      assert(type(stage) == "number" and type(lines) == "table", "setTransmission(stage, lines) invalid args")
      local Transmission = require("src.ui.transmission")
      local ids = {}
      for i, text in ipairs(lines) do
        local key = ("tx.stage%d.%d"):format(stage, i)
        self:addString(key, text)
        ids[i] = key
      end
      Transmission.SCRIPT[stage] = ids
      return true
    end,

    playTransmission = function(self, stageOrLines)
      local Transmission = require("src.ui.transmission")
      local cur = game.scenes and game.scenes:current()
      if not cur then return false end
      local stage = stageOrLines
      if type(stageOrLines) == "table" then
        stage = 99
        self:setTransmission(stage, stageOrLines)
      end
      if not Transmission.has(stage) then return false end
      cur.transmission = Transmission(game, stage)
      return true
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
      if folder == "modview" then return false end
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
        MatrixRain = "src.ui.matrixrain",
        Ascension  = "src.ui.ascension",
        Widgets = "src.ui.widgets",
        Theme   = "src.ui.theme",
        Cursor  = "src.ui.cursor",
        Rect    = "src.core.rect",
        Format  = "src.core.format",
        Kit3D   = "src.ui.wirekit",
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

  addTitleButton = function(self, id, label, fn)
  ensureTitlePatched()
  local labelId = "title.mod_" .. id
  modLabels[labelId] = label
  table.insert(titleButtons, { id = id, labelId = labelId, fn = fn })
end,

removeTitleButton = function(self, id)
  for i = #titleButtons, 1, -1 do
    if titleButtons[i].id == id then table.remove(titleButtons, i) end
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

    -- kill and revice (yes they differ lol)
     killProcess = function(self, key)
      return game.machine ~= nil and game.machine:kill(key) or false
    end,

    reviveProcess = function(self, key)
      return game.machine ~= nil and game.machine:revive(key) or false
    end,

    isProcessDead = function(self, key)
      return game.machine ~= nil and game.machine:isDead(key) or false
    end,

    isEffectAlive = function(self, effect)
      if not game.machine then return true end
      return game.machine:alive(effect)
    end,

    getKilledProcesses = function(self)
      return game.machine and game.machine:snapshot() or {}
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
    registerCursor = function(self, id, drawFn)
      assert(type(id) == "string" and type(drawFn) == "function", "registerCursor(id, drawFn) invalid args")
      local Cursor = require("src.ui.cursor")
      if not Cursor._modCursors then
        Cursor._modCursors = {}
        local origDrawAt = Cursor.drawAt
        function Cursor.drawAt(x, y, fill, outline)
          local fn = Cursor._modCursors[Cursor.style]
          if fn then
            love.graphics.push()
            love.graphics.translate(x, y)
            if Cursor.scale ~= 1 then love.graphics.scale(Cursor.scale, Cursor.scale) end
            fn(0, 0, fill, outline)
            love.graphics.pop()
            love.graphics.setColor(1, 1, 1, 1)
            return
          end
          return origDrawAt(x, y, fill, outline)
        end
        local origDraw = Cursor.draw
        function Cursor.draw()
          local fn = Cursor._modCursors[Cursor.style]
          if fn and not Cursor.system and not Cursor.hidden and love.mouse then
            if not (love.window and love.window.hasMouseFocus and not love.window.hasMouseFocus()) then
              local mx, my = love.mouse.getPosition()
              local c = Theme.color
              love.graphics.push()
              love.graphics.translate(mx, my)
              if Cursor.scale ~= 1 then love.graphics.scale(Cursor.scale, Cursor.scale) end
              fn(0, 0, c.cream, c.fieldDark)
              love.graphics.pop()
              love.graphics.setColor(1, 1, 1, 1)
              return
            end
          end
          return origDraw()
        end
      end
      if not Cursor._modCursors[id] then
        table.insert(Cursor.STYLES, id)
      end
      Cursor._modCursors[id] = drawFn
      return true
    end,

    -- AESTHETICS
    addTheme = function(self, row)
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