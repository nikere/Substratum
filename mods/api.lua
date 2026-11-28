-- god forgive me if someone will read this
local Api = {}
function Api.create(game, loaderState, getCleanState)
  local rearmGuards = function() end
  local checkClean = getCleanState or function() return false, "unverified_caller" end
  local saveDir = love.filesystem.getSaveDirectory()
  local StringStore = require("src.services.strings")
  local PauseMenu = require("src.ui.pausemenu")
  local OptionsPanel = require("src.ui.options_panel")
  local Taskbar = require("src.ui.taskbar")
  local AppRegistry = require("src.services.apps")
  local Theme = require("src.ui.theme")

  local ok_wo, WallpaperOverlay = pcall(require, "src.ui.wallpaperoverlay")
if not ok_wo then
    ok_wo, WallpaperOverlay = pcall(require, "src.ui.wallpaper_overlay")
end
if not ok_wo then WallpaperOverlay = nil end

  local customMascots = {}
  local customStripes = {}
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
  local customTrails = {}
  local customToys = {}
  local sceneHandlers = {}
  local saveCallbacks, loadCallbacks = {}, {}
  local slotCache, globalCache = {}, nil

  
  local origMascotScan = nil
  local gameLogoPath, logoPatched = nil, false
  local chromePatched = false
  local isReady = false
  local titlePatched = false
  local origCreditsParse = nil
  local trailPatched = false
  local toysPatched = false
  local scenesPatched = false
  do
    local seen = {}
    local guardedMeta, guardedSteam, guardedBoard = false, false, false
    local installedSubmit = nil

    local function note(kind, id)
      local k = kind .. ":" .. tostring(id)
      if seen[k] then return end
      seen[k] = true
      local _, why = checkClean()
      print(("[Substratum] guard: %s '%s' refused (%s)"):format(
        kind, tostring(id), tostring(why or "tainted")
      ))
    end

    local function applyGuards()
      local okM, Meta = pcall(require, "src.services.meta")
      if okM and Meta and Meta.submitScore and Meta.submitScore ~= installedSubmit then
        if guardedMeta then
          print("[Substratum] guard: score funnel replaced post-boot - re-arming")
        end
        guardedMeta = true
        local origSubmit = Meta.submitScore
        function Meta:submitScore(board, score, length)
          if type(board) ~= "string" or not board:match("^[%w%.%-_]+$") or #board > 40 then return nil end
          if type(score) ~= "number" or score ~= score or score == math.huge or score <= 0 then return nil end
          local steam = self.game and self.game.steam
          local clean = checkClean()
          if steam and steam.available and not clean then
            note("board", board)
            return self:record(board, score, length)
          end
          return origSubmit(self, board, score, length)
        end
        installedSubmit = Meta.submitScore
        print("[Substratum] guard: competitive funnel on")
      end
      local okS, Svc = pcall(require, "src.services.steam")
      if okS and Svc and not guardedSteam then
          guardedSteam = true
      local origUnlock, origSweep, origSteamSubmit, origRefresh =
          Svc.unlockAchievement, Svc.sweep, Svc.submitScore, Svc.refreshBoard
        function Svc:unlockAchievement(id)
          local clean = checkClean()
          if not clean then note("achievement", id) return end
          return origUnlock(self, id)
        end
        function Svc:sweep()
          local clean = checkClean()
          if not clean then return end
          return origSweep(self)
        end
        if origSteamSubmit then
          function Svc:submitScore(board, score)
            local clean = checkClean()
            if not clean then note("board", board) return false end
            return origSteamSubmit(self, board, score)
          end
        end
        if origRefresh then
          function Svc:refreshBoard(board, force)
            local clean = checkClean()
            if not clean then return false end
            return origRefresh(self, board, force)
          end
        end

end
rearmGuards = applyGuards


      local okB, SB = pcall(require, "src.ui.scoreboard")
      if okB and SB and not guardedBoard then
        guardedBoard = true
        local origView = SB.view
        function SB.view(g, board)
          local clean = checkClean()
          if not clean then return nil end
          return origView(g, board)
        end
      end
    end
    applyGuards()
    table.insert(readyQueue, applyGuards)
  end


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
        if self.lang == "jp" or self.bilingualMode then
          return entry.jp, entry.en
        end
        return nil, entry.en
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

  local function balanceParts(path)
  local parts = {}
  for seg in path:gmatch("[^%.]+") do parts[#parts + 1] = seg end
  return parts
end
local function ensureScenesPatched()
  if scenesPatched then return end
  scenesPatched = true

  local function fireSceneEnter(scene, prev)
    local name = scene and scene.name
    if not name or not sceneHandlers[name] then return end
    for _, fn in ipairs(sceneHandlers[name]) do
      local ok, err = pcall(fn, game, scene, prev)
      if not ok then print("[ModAPI] onSceneEnter error: " .. tostring(err)) end
    end
  end

  local function wrapEnter(fn)
    return function(self, prev, ...)
      local res = fn(self, prev, ...)
      fireSceneEnter(self, prev)
      return res
    end
  end

  local SceneMod = require("src.core.scene")
  local BaseScene = SceneMod.Scene
  BaseScene.enter = wrapEnter(BaseScene.enter or function() end)

  for _, file in ipairs(love.filesystem.getDirectoryItems("src/scenes") or {}) do
    local stem = file:match("^(.+)%.lua$")
    if stem then
      local ok, Cls = pcall(require, "src.scenes." .. stem)
      local ownEnter = ok and type(Cls) == "table" and rawget(Cls, "enter")
      if type(ownEnter) == "function" then
        rawset(Cls, "enter", wrapEnter(ownEnter))
      end
    end
  end
end


local function ensureLogoPatched()
  if logoPatched then return end
  logoPatched = true
  for _, m in ipairs({ "src.scenes.title", "src.scenes.boot",
                       "src.scenes.credits", "src.scenes.ending" }) do
    local ok, Scene = pcall(require, m)
    if ok and Scene and Scene.new then
      local origNew = Scene.new
      Scene.new = function(self, g, ...)
        local r = origNew(self, g, ...)
        if gameLogoPath then
          local ok2, img = pcall(love.graphics.newImage, gameLogoPath)
          if ok2 and img then img:setFilter("linear", "linear"); self.logo = img end
        end
        return r
      end
    end
  end
end
local function ensureTrailPatched()
  if trailPatched then return end
  trailPatched = true
  local Trail = require("src.ui.toys.trail")
  local origDraw = Trail.draw
  function Trail:draw(...)
    local fn = customTrails[self.shape]
    if not fn then return origDraw(self, ...) end
    for i = 1, #self.p do
      local q = self.p[i]
      if q.alive then
        local k = 1 - q.age / q.life
        local col = self.colors[(q.ci - 1) % #self.colors + 1]
        local r = q.size * (0.4 + 0.6 * k)
        Theme.set(col, k)
        fn(q.x, q.y, r, q.rot, col, k)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

  local function ensureChromePatched()
    if chromePatched then return end
    chromePatched = true
    local Chrome = require("src.ui.chrome")
        local Window = require("src.ui.window")
    local origContentRect = Window.contentRect
    function Window:contentRect(...)
      if not self:framed() then return origContentRect(self, ...) end
      local b = math.max(1, Chrome.style and Chrome.style.border or 1)
      return self.x + b, self.y + self.titlebarH, self.w - b * 2, self.h - self.titlebarH - b
    end


    local lg = love.graphics

    local function drawCustomStripe(stripe, x, y, w, h, alpha)
      if type(stripe) == "table" and #stripe > 0 then
        local sw = w / #stripe
        for i, col in ipairs(stripe) do
          local c = type(col) == "string" and Theme.hex(col) or col
          lg.setColor(c[1], c[2], c[3], (c[4] or 1) * (alpha or 1))
          lg.rectangle("fill", x + (i - 1) * sw, y, sw + 1, h)
        end
        lg.setColor(1, 1, 1, 1)
        return true
      end
      local fn = customStripes[stripe]
      if fn then
        fn(x, y, w, h, alpha or 1)
        lg.setColor(1, 1, 1, 1)
        return true
      end
      return false
    end

    local origWindowFrame = Chrome.windowFrame
    function Chrome.windowFrame(win, ...)
      origWindowFrame(win, ...)
      local st = Chrome.style
      local b = st and st.border or 1
      if b > 1 then
        Theme.set(win.focused and Theme.color.shellEdgeHi or Theme.color.shellEdge)
        Chrome.lineTop(win.x, win.y, win.w, win.h, st.radius or 0, b)
        lg.setColor(1, 1, 1, 1)
      end
      if st and st.stripe and st.stripe ~= "rainbow" and st.stripe ~= "hazard" and st.stripe ~= "rule" then
        local tx, ty, tw, tht = win.x + b, win.y + b, win.w - b * 2, win.titlebarH - b
        drawCustomStripe(st.stripe, tx, ty + tht - 3, tw, 3, win.focused and 1 or 0.55)
      end
    end


        local origTaskbarFace = Chrome.taskbarFace
    function Chrome.taskbarFace(x, y, w, h, ...)
      origTaskbarFace(x, y, w, h, ...)
      local st = Chrome.style
      if not (st and st.stripe and st.taskbarStripe ~= false) then return end
      if st.stripe == "rule" then
        Theme.set(Theme.color.shellEdgeHi, 0.9)
        lg.rectangle("fill", x, y, w, 2)
      elseif st.stripe == "hazard" then
        Theme.set(Theme.color.titlebar)
        lg.rectangle("fill", x, y, w, 2)
        lg.setColor(0, 0, 0, 1)
        for sx = x, x + w, 10 do
          lg.rectangle("fill", sx, y, 5, 2)
        end
        lg.setColor(1, 1, 1, 1)
      elseif st.stripe ~= "rainbow" then
        drawCustomStripe(st.stripe, x, y, w, 2, 1)
      end
    end
  end



  local function ensureMascotPatched()
    if origMascotScan then return end
    local WO = WallpaperOverlay
    if not WO then
      local ok, mod = pcall(require, "src.ui.wallpaperoverlay")
      if not ok then ok, mod = pcall(require, "src.ui.wallpaper_overlay") end
      if ok and mod then WO = mod; WallpaperOverlay = mod end
    end
    if not WO then return end

    origMascotScan = WO.scan
    function WO.scan(items, dir, ...)
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

    local Aesthetic = require("src.services.aesthetic")
    local origMascotPath = Aesthetic.mascotPath
    function Aesthetic:mascotPath(...)
      local cur = self.s and self.s.mascot
      for _, m in ipairs(customMascots) do
        if cur == m.name or cur == m.id or cur == m.path then
          return m.path
        end
      end
      return origMascotPath(self, ...)
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
local function ensureToysPatched()
    if toysPatched then return end
    toysPatched = true
    local Aesthetic = require("src.services.aesthetic")

    local origUpdate = Aesthetic.update
    function Aesthetic:update(dt, ...)
      origUpdate(self, dt, ...)
      local desk = self:desktop()
      if not desk then return end
      for _, toy in ipairs(customToys) do
        if self:on(toy.key) and toy.update then
          toy.update(dt, self.game, desk)
        end
      end
    end

    local origDrawDesktop = Aesthetic.drawDesktop
    function Aesthetic:drawDesktop(fonts, ...)
      origDrawDesktop(self, fonts, ...)
      local desk = self:desktop()
      if not desk then return end
      for _, toy in ipairs(customToys) do
        if self:on(toy.key) and toy.draw and toy.layer ~= "top" then
          toy.draw(fonts, self.game, desk)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
    end

    local origDrawTop = Aesthetic.drawTop
    function Aesthetic:drawTop(fonts, ...)
      origDrawTop(self, fonts, ...)
      local desk = self:desktop()
      if not desk then return end
      for _, toy in ipairs(customToys) do
        if self:on(toy.key) and toy.draw and toy.layer == "top" then
          toy.draw(fonts, self.game, desk)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
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
    rearmGuards()
  end

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
      local TerminalApp = require("src.apps.terminal.terminal")
      if not TerminalApp._modArgsPatched then
        TerminalApp._modArgsPatched = true
        local origSubmit = TerminalApp.submit
        function TerminalApp:submit(...)
          local trimmed = (self.input or ""):gsub("^%s+", ""):gsub("%s+$", "")
          local rest = trimmed:match("^%S+%s+(.+)$") or ""
          local args = {}
          for tok in rest:gmatch("%S+") do
            args[#args + 1] = tok
          end
          self._modArgs = args
          self._modRawArgs = rest
          local res = origSubmit(self, ...)
          self._modArgs = nil
          self._modRawArgs = nil
          return res
        end

        local origRun = TerminalApp.runCommand
        function TerminalApp:runCommand(cmd, ...)
          if cmd and cmd._modFn then
            local S = self.game.strings
            local c = Theme.color
            if cmd.lore then
              if cmd.pace then
                self:stream(S:localize(cmd.lore), c.cream, cmd.pace)
              else
                self:print(S:localize(cmd.lore), c.cream)
              end
            end
            local ok, out = pcall(cmd._modFn, self._modArgs or {}, self, self._modRawArgs or "")
            self:print(ok and (out or "") or S:line("terminal.streamCorrupted"), ok and c.cream or c.bad)
            if cmd.reward and not self.done[cmd.name] then
              self.done[cmd.name] = true
              self:applyReward(cmd.reward)
            end
            if cmd.secret then self:grantSecret(cmd.secret) end
            return
          end
          return origRun(self, cmd, ...)
        end
      end

      if def and type(def.fn) == "function" then
        def._modFn = def.fn
      end

      local secrets = require("src.data.terminal_secrets")
      table.insert(secrets, def)

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
        registerMinigame = function(self, id, autoFound)
      local Meta = require("src.services.meta")
      for _, m in ipairs(Meta.MINIGAMES) do if m == id then return false end end

      local stdPath = "src.apps." .. id .. "." .. id
      if not package.preload[stdPath] and not package.loaded[stdPath] then
        package.preload[stdPath] = function()
          local modPath = "mods.virtual_app_" .. id
          local def = game.apps and game.apps.defs and game.apps.defs[id]
          if not def then
            for _, d in ipairs(require("src.data.apps")) do
              if d.id == id then def = d; break end
            end
          end
          if def and def.module then modPath = def.module end
          if package.loaded[modPath] then return package.loaded[modPath] end
          if package.preload[modPath] then return package.preload[modPath]() end
          error("Mod minigame module not found for id: " .. tostring(id))
        end
      end

      table.insert(Meta.MINIGAMES, id)
      if autoFound and game.meta and game.meta.markMinigame then
        game.meta:markMinigame(id)
      end
      return true
    end,
setNewsEnabled = function(self, on)
  game.noNews = not on
  local news = game.news
  if on and news and not news.started then news:start() end 
  return not game.noNews
end,
setNewsPosts = function(self, rows)   -- { {title=, text=, date=epoch, url=""}, ... }; nil restores
  onReady(function(g)
    local news = g.news; if not news then return end
    if rows == nil and news._modOrig then
      news.start, news.poll, news.status = news._modOrig.start, news._modOrig.poll, news._modOrig.status
      news._modOrig = nil; return
    end
    if not news._modOrig then
      news._modOrig = { start = news.start, poll = news.poll, status = news.status }
      news.start = function() end
      news.poll  = function() end
      news.status = function() return #news.items > 0 and "ready" or "none" end
    end
    news.items = rows
    g.noNews = false   
  end)
  return true
end,

    registerApp = function(self, def, AppClass)
      assert(def and def.id, "registerApp requires def.id")
      local modPath = "mods.virtual_app_" .. def.id
      def.module = modPath
      def.titleId = def.titleId or ("app." .. def.id)
      def.icon = def.icon or "量"
      def.unlock = def.unlock or { always = true }
      if def.resizable   ~= nil then AppClass.resizable   = def.resizable end
      if def.closable    ~= nil then AppClass.closable    = def.closable end
      if def.maximizable ~= nil then AppClass.maximizable = def.maximizable end
      if def.minimizable ~= nil then AppClass.minimizable = def.minimizable end

      local Window = require("src.ui.window")
      if not Window._modOffersPatched then
        Window._modOffersPatched = true
        local origOffers = Window.offers
        function Window:offers(tag)
          local app = self.app
          if tag == "close" and (self.closable == false or (app and app.closable == false)) then return false end
          if tag == "max"   and (self.maximizable == false or (app and app.maximizable == false)) then return false end
          if tag == "min"   and (self.minimizable == false or (app and app.minimizable == false)) then return false end
          return origOffers(self, tag)
        end
      end


      package.preload[modPath] = function() return AppClass end

      local manifest = require("src.data.apps")
      table.insert(manifest, def)

      -- Inject directly into the already-constructed AppRegistry
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
    setGameLogo = function(self, path)
  ensureLogoPatched(); gameLogoPath = path
  local cur = game.scenes and game.scenes:current()
  if cur and cur.logo then
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then img:setFilter("linear", "linear"); cur.logo = img end
  end
  return true
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
      local Desktop = require("src.scenes.desktop")
      Desktop._modAscStrength = strength
      if not Desktop._modAscPatched then
        Desktop._modAscPatched = true
        local origAsc = Desktop.ascension
        function Desktop:ascension(...)
          if Desktop._modAscStrength ~= nil then
            return math.max(0, math.min(1, Desktop._modAscStrength))
          end
          return origAsc(self, ...)
        end
        local origDrawScene = Desktop.drawScene
        function Desktop:drawScene(...)
          if Desktop._modAscStrength ~= nil and self.game and self.game.unlocks and not self.game.unlocks:flag("stage2") then
            local Ascension = require("src.ui.ascension")
            local asc = math.max(0, math.min(1, Desktop._modAscStrength))
            local res = origDrawScene(self, ...)
            if asc > 0 then
              Ascension.drawOver(asc, self:wallpaperClock(), self.w, self.h)
            end
            return res
          end
          return origDrawScene(self, ...)
        end
      end
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
   onEvent = function(self, name, fn)
  if not (game.events and game.events.on) then return function() end end
  return game.events:on(name, fn)     -- returns the unsubscribe closure
end,
addAchievement = function(self, def)
  assert(def and def.id and type(def.check) == "function", "addAchievement needs id + check(game)")
  local A = require("src.data.achievements")
  def.name, def.desc = def.name or { en = def.id }, def.desc or { en = "" }
  for i = #A.list, 1, -1 do if A.list[i].id == def.id then table.remove(A.list, i) end end
  table.insert(A.list, def)
  return true
end,
  removeAchievement = function(self, id)
    local A = require("src.data.achievements")
    for i = #A.list, 1, -1 do
      if A.list[i].id == id then table.remove(A.list, i) return true end
    end
    for i = #(A.planned or {}), 1, -1 do
      if A.planned[i].id == id then table.remove(A.planned, i) return true end
    end
    return false
  end,
  onSceneEnter = function(self, name, fn)
  assert(type(name) == "string" and type(fn) == "function", "onSceneEnter(name, fn) invalid args")
  ensureScenesPatched()
  sceneHandlers[name] = sceneHandlers[name] or {}
  table.insert(sceneHandlers[name], fn)
  return true
end,

  currentScene = function(self)
    local cur = game.scenes and game.scenes:current()
    return cur and cur.name or nil
  end,
listAchievements = function(self) local A = require("src.data.achievements")
  local out = {}; for _, a in ipairs(A.list) do out[#out+1] = a.id end; return out end,
isAchievementUnlocked = function(self, id)
  local A = require("src.data.achievements")
  for _, a in ipairs(A.list) do
    if a.id == id then local ok, r = pcall(a.check, game); return (ok and r == true) or false end
  end
  return false
end,
enablePlannedAchievement = function(self, id)   
  local A = require("src.data.achievements")
  for i, a in ipairs(A.planned or {}) do
    if a.id == id then table.remove(A.planned, i); table.insert(A.list, a); return true end
  end
  return false
end,
getStat = function(self, k) return game.stats and game.stats:get(k) or 0 end,
bumpStat = function(self, k, n) if game.stats then game.stats:bump(k, n or 1) end end,
getUpgradeLevel = function(self, id) return game.upgrades and game.upgrades:level(id) or 0 end,
isUpgradeMaxed = function(self, id)
  local up = game.upgrades; if not up then return false end
  local d = up:def(id); return d ~= nil and d.maxLevel ~= nil and up:level(id) >= d.maxLevel
end,
listUpgradeIds = function(self, setId) return game.upgrades and game.upgrades:ids(setId) or {} end,
isRunCompleted = function(self) return (game.meta and game.meta.completed) or false end,
markRunCompleted = function(self) if game.meta then game.meta:markCompleted() end end,
listMinigames = function(self)
  local Meta = require("src.services.meta")
  local out = {}; for _, id in ipairs(Meta.MINIGAMES) do out[#out+1] = id end; return out
end,
isMinigameFound = function(self, id)
  return (game.meta and game.meta.foundMinigame and game.meta:foundMinigame(id)) or false
end,
markMinigameFound = function(self, id) if game.meta then game.meta:markMinigame(id) end end,

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

    setFlag = function(self, flag, val)
      if game.unlocks then game.unlocks:setFlag(flag, val == nil and true or val) end
    end,

    getFlag = function(self, flag)
      return game.unlocks and (game.unlocks:has(flag) or false) or false
    end,

    completeApp = function(self, appId)
      if game.apps then game.apps:markCompleted(appId) end
    end,

    isAppCompleted = function(self, appId)
      if not game.apps then return false end
      for _, id in ipairs(game.apps:completedIds()) do
        if id == appId then return true end
      end
      return false
    end,

    getCompletedApps = function(self)
      return game.apps and game.apps:completedIds() or {}
    end,

    addSentience = function(self, amount)
      if not game.sentience then return 0 end
      game.sentience:add(amount or 0)
      if game.unlocks and game.unlocks.update then game.unlocks:update(0) end
      return game.sentience:get()
    end,



    getSentience = function(self)
      return game.sentience and (game.sentience.value or (game.sentience.get and game.sentience:get())) or 0
    end,

    addResource = function(self, pool, amount)
      if game.resources then game.resources:add(pool, amount) end
    end,

    getResource = function(self, pool)
      return game.resources and (game.resources:get(pool) or 0) or 0
    end,

    fireLog = function(self, key)
      if game.logbook then game.logbook:fire(key) end
    end,

    emitEvent = function(self, name, payload)
      if game.events then game.events:emit(name, payload) end
    end,

    shake = function(self, amount)
      if not game.juice then return end
      local Game = require("src.game")
      if not Game._modShakePatched then
        Game._modShakePatched = true
        local origDrawWorld = Game.drawWorld
        function Game:drawWorld(...)
          local j = self.juice
          if j and (j.shakeX ~= 0 or j.shakeY ~= 0) then
            love.graphics.push()
            j:applyShake()
            local res = origDrawWorld(self, ...)
            love.graphics.pop()
            return res
          end
          return origDrawWorld(self, ...)
        end
      end
      game.juice:shake(amount or 12)
    end,




    getSetting = function(self, key)
      return game.settings and game.settings[key]
    end,

    setSetting = function(self, key, val)
      if game.settings then
        game.settings[key] = val
        if game.save and game.save.writeSettings then game.save:writeSettings() end
      end
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
      ensureMascotPatched()
      if path then
        local targetName = path
        local found = false
        for _, m in ipairs(customMascots) do
          if m.path == path or m.id == path or m.name == path then
            targetName = m.name or m.id
            found = true
            break
          end
        end
        if not found then
          local autoId = "mod_mascot_" .. tostring(path)
          self:registerMascot(autoId, autoId, path)
          targetName = autoId
        end
        if game and game.aesthetic then
          game.aesthetic:set({ mascot = targetName })
        end
      end
      if opts and game and game.aesthetic then
        local patch = {}
        if opts.blend then patch.blend = opts.blend end
        if opts.flip ~= nil then patch.flip = opts.flip end
        if opts.x ~= nil then patch.mascotX = opts.x end
        if opts.y ~= nil then patch.mascotY = opts.y end
        if opts.deg ~= nil then patch.mascotRot = opts.deg end
        if opts.size ~= nil then patch.mascotSize = opts.size end
        game.aesthetic:set(patch)
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

    registerStripe = function(self, id, drawFn)
    assert(type(id) == "string" and type(drawFn) == "function", "registerStripe(id, drawFn) invalid args")
    ensureChromePatched()
    customStripes[id] = drawFn
    return true
  end,
      listStripes = function(self)
      local out = { "rule", "rainbow", "hazard" }
      for id in pairs(customStripes) do
        out[#out + 1] = id
      end
      return out
    end,


        registerWallpaper = function(self, id, drawFn)
      assert(type(id) == "string" and type(drawFn) == "function", "registerWallpaper(id, drawFn) invalid args")
      local Wallpapers = require("src.ui.wallpapers")
      Wallpapers.painters[id] = function(w, h, workH, t, wp, fonts)
        drawFn(w, h, workH, t, wp, fonts)
        love.graphics.setColor(1, 1, 1, 1)
      end
      return true
    end,

    listWallpapers = function(self)
      local Wallpapers = require("src.ui.wallpapers")
      local out = {}
      for k in pairs(Wallpapers.painters) do
        out[#out + 1] = k
      end
      table.sort(out)
      return out
    end,

    registerToy = function(self, def)
    assert(type(def) == "table" and type(def.key) == "string", "registerToy requires def.key")
    ensureToysPatched()
    local labelId = "aesthetics.mod_toy." .. def.key
    local tipId = "aesthetics.mod_toyTip." .. def.key
    modLabels[labelId] = def.label or def.name or def.key
    modLabels[tipId] = def.tip or ""
    if def.default ~= nil and game.aesthetic and game.aesthetic.s and game.aesthetic.s[def.key] == nil then
      game.aesthetic.s[def.key] = def.default == true
    end
    local Aesthetic = require("src.services.aesthetic")
    table.insert(Aesthetic.TOYS, def.key)
    local AestheticsApp = require("src.apps.aesthetics.aesthetics")
    table.insert(AestheticsApp.TOYS, { key = def.key, labelId = labelId, tipId = tipId })
    table.insert(customToys, def)
    return true
  end,

  listToys = function(self)
    local out = {}
    local AestheticsApp = require("src.apps.aesthetics.aesthetics")
    for _, t in ipairs(AestheticsApp.TOYS) do out[#out + 1] = t.key end
    return out
  end,

   spawnVirusPopup = function(self, adIndex)
      local cur = game.scenes and game.scenes:current()
      local vfx = cur and (cur.virusFx or cur.virus)
      if not vfx or not vfx.spawnPopup then return nil end

      local VirusAds = require("src.data.virusads")
      local idx = adIndex
      local tempAdded = false

      if type(adIndex) == "table" then
        local norm = function(v, fb)
          if type(v) == "table" then return v end
          local s = tostring(v or fb)
          return { en = s, jp = s }
        end
        table.insert(VirusAds.list, {
          title = norm(adIndex.title, "ANOMALY"),
          body = norm(adIndex.body, "SIGNAL CORRUPTED"),
          button = norm(adIndex.button, "OK"),
        })
        idx = #VirusAds.list
        tempAdded = true
      end

       if idx and VirusAds.list[idx] then
        vfx.serial = (vfx.serial or 0) + 1
        local Popup = require("src.ui.viruspopup")
        local adRef = VirusAds.list[idx]
        local app = Popup(game, vfx.serial, idx)
        if tempAdded then
          table.remove(VirusAds.list, idx)
          app.advert = function() return adRef end
        end
        local wa = cur:workArea()
        local P = require("src.data.balance").virus.popup
        local x = wa.x + love.math.random(0, math.max(0, wa.w - P.w))
        local y = wa.y + love.math.random(0, math.max(0, wa.h - P.h))
        return cur:openWindow(app, { titleText = app:titleText(), x = x, y = y })
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
        for k, gh in ipairs(vfx.ghosts) do
          if k <= Virus._modGhostMin then
            if not gh.on then vfx:wake(gh) end
          elseif not vfx:active() then
            gh.on = false
            gh.job = nil
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

    setWindowProps = function(self, appId, props)
      local cur = game.scenes and game.scenes:current()
      local win = cur and cur.wm and cur.wm:windowForApp(appId)
      if not win or type(props) ~= "table" then return false end

      local Window = require("src.ui.window")
      if not Window._modOffersPatched then
        Window._modOffersPatched = true
        local origOffers = Window.offers
        function Window:offers(tag)
          local app = self.app
          if tag == "close" and (self.closable == false or (app and app.closable == false)) then return false end
          if tag == "max"   and (self.maximizable == false or (app and app.maximizable == false)) then return false end
          if tag == "min"   and (self.minimizable == false or (app and app.minimizable == false)) then return false end
          return origOffers(self, tag)
        end
      end

      if props.x           ~= nil then win.x = props.x end
      if props.y           ~= nil then win.y = props.y end
      if props.w           ~= nil then win.w = props.w end
      if props.h           ~= nil then win.h = props.h end
      if props.minW        ~= nil then win.minW = props.minW end
      if props.minH        ~= nil then win.minH = props.minH end
      if props.resizable   ~= nil then win.resizable = props.resizable end
      if props.closable    ~= nil then win.closable = props.closable end
      if props.maximizable ~= nil then win.maximizable = props.maximizable end
      if props.minimizable ~= nil then win.minimizable = props.minimizable end
      if props.title       ~= nil then win.titleText = tostring(props.title) end
      if props.state == "minimized" and win.minimize then
        win:minimize()
      elseif props.state == "maximized" and cur.workArea and win.maximize and win.state ~= "maximized" then
        win:maximize(cur:workArea())
      elseif props.state == "normal" then
        if win.state == "minimized" and win.unminimize then win:unminimize()
        elseif win.state == "maximized" and cur.workArea and win.maximize then win:maximize(cur:workArea()) end
      end
      return true
    end,

    getBalance = function(self, path)
  local node = require("src.data.balance")
  for _, seg in ipairs(balanceParts(path)) do
    if type(node) ~= "table" then return nil end
    node = node[seg]
  end
  return node
end,
setBalance = function(self, path, value)
  local parts = balanceParts(path)
  if #parts == 0 then return false end
  local node = require("src.data.balance")
  for i = 1, #parts - 1 do
    if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
    node = node[parts[i]]
  end
  node[parts[#parts]] = value
  return true
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
      local m = mode or "reboot"
      local scene = BootScene(game, { mode = m })
      if m == "reboot" then
        local origFinish = scene.finish
        function scene:finish(...)
          origFinish(self, ...)
          if game.scenes and game.scenes:current() == self then
            game.scenes:pop()
          end
        end
      end
      game.scenes:push(scene)
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

      local list = Powers.POWERS or Powers.list
      local byId = Powers.POWER_BY_ID or Powers.byId
      def.row = def.row or ("engage.power." .. def.id)
      def.index = #list + 1
      table.insert(list, def)
      byId[def.id] = def

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
      local Powers = require("src.data.powers")
      local out = {}
      for _, p in ipairs(Powers.POWERS or Powers.list) do out[#out + 1] = p.id end
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

  registerTrail = function(self, id, drawFn)
    assert(type(id) == "string" and type(drawFn) == "function", "registerTrail(id, drawFn) invalid args")
    ensureTrailPatched()
    customTrails[id] = drawFn
    return true
  end,

  listTrails = function(self)
    local out = { "sparkle", "bubble", "pixel", "heart", "star" }
    for id in pairs(customTrails) do out[#out + 1] = id end
    return out
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
      local list = Powers.POWERS or Powers.list
      local byId = Powers.POWER_BY_ID or Powers.byId
      byId[id] = nil
      for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
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
      Aesthetics.list = Aesthetics.list or {}
      Aesthetics.byId = Aesthetics.byId or {}

      row.index = #Aesthetics.list + 1
      row.nameId = row.nameId or ("aesthetics.theme." .. row.id)
      row.tipId = row.tipId or ("aesthetics.tip." .. row.id)
      row.palette = row.palette or {}
      row.chrome = row.chrome or { radius = 0, border = 1, buttons = "glyph", titleAlign = "left" }
      row.wallpaper = row.wallpaper or { kind = "grid", base = "#0A2429" }
      row.wallpaper.base = row.wallpaper.base or "#0A2429"
      row.cursor = row.cursor or "arrow"
      row.trail = row.trail or "sparkle"
      row.trailColors = row.trailColors or { "#E8C170", "#F4ECD8", "#9BE8C9" }
      if row.chrome and (row.chrome.stripe or (row.chrome.border or 1) > 1) then
        ensureChromePatched()
      end
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
      local existing = Aesthetics.byId[row.id]
      if existing then
        row.index = existing.index
        Aesthetics.list[existing.index] = row
      else
        row.index = #Aesthetics.list + 1
        table.insert(Aesthetics.list, row)
      end
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
  return setmetatable({}, {
    __index = api,
    __newindex = function(_, k)
      error("[Substratum] Attempt to modify read-only Mod API field: " .. tostring(k), 2)
    end,
    __metatable = false
  })
end
return Api