local UIScale = require("src.ui.uiscale")
local Theme = require("src.ui.theme")
local Rect = require("src.core.rect")
local Cursor = require("src.ui.cursor")

local M = {
  name = "Mod Manager GUI",
  version = "1.1.0",
  author = "Community"
}

function M:init(game)
  local open = false
  local dirty = false
  local scroll = 0
  local maxScroll = 0

  local btnRect = { x = 0, y = 0, w = 0, h = 0 }
  local restartRect = { x = 0, y = 0, w = 0, h = 0 }
  local closeRect = { x = 0, y = 0, w = 0, h = 0 }
  local modalRect = { x = 0, y = 0, w = 0, h = 0 }
  local rowHitboxes = {}
  local function isReleased()
  return game.machine and game.machine:isDead("modloader")
  end
  -- Core kernel layer in RELEASE (Ring 5 = MONADIC, Ring 6 = ADI)
  game.mods:addProcess({
    key = "modloader",
    name = "modloader.sys",
    ring = 5,
    present = { unlocked = "release" },
  })
  game.mods:addBootModule("modloader.sys")
  game.mods:addPauseButton("mods", "MODS", function(g, pauseMenu)
    if isReleased() then return end
    pauseMenu:hide()
    open = true
  end)
  if game.mods.addTitleButton then
    game.mods:addTitleButton("mods", "MODS", function(g, titleScene)
      if isReleased() then return end
      open = true
    end)
  end

  game.mods:onReady(function(g)
    if g.machine and g.machine.kill then
      local origKill = g.machine.kill
      function g.machine:kill(key, ...)
        local res = origKill(self, key, ...)
        if res and key == "modloader" then
          game.mods:triggerCrash(true)
        end
        return res
      end
    end
        local modsWithAuthors = {}
    for _, m in ipairs(g.mods.loaded) do
      if not m._core then
        modsWithAuthors[#modsWithAuthors + 1] = m
      end
    end
    if #modsWithAuthors > 0 and g.mods.addCreditRow then
      g.mods:addCreditRow("gap")
      g.mods:addCreditRow("head", "USER MODS")
      for _, m in ipairs(modsWithAuthors) do
        local line = (m.name or m._folder) .. (m.author and (" — " .. m.author) or "")
        g.mods:addCreditRow("text", line)
      end
    end
  end)
    local dropStatus = nil
  local function copyTre(srcVirtual, dstVirtual)
    local info = love.filesystem.getInfo(srcVirtual)
    if not info then return end
    if info.type == "directory" then
      love.filesystem.createDirectory(dstVirtual)
      for _, item in ipairs(love.filesystem.getDirectoryItems(srcVirtual)) do
        copyTre(srcVirtual .. "/" .. item, dstVirtual .. "/" .. item)
      end
    elseif info.type == "file" then
      local data = love.filesystem.read(srcVirtual)
      if data then love.filesystem.write(dstVirtual, data) end
    end
  end
  local function removeTree(dstVirtual) local info = love.filesystem.getInfo(dstVirtual)
    if not info then return end
    if info.type == "directory" then
      for _, item in ipairs(love.filesystem.getDirectoryItems(dstVirtual)) do removeTree(dstVirtual .. "/" .. item)
      end
    end love.filesystem.remove(dstVirtual)
  end
  local function installMountedMod(mountRoot, fallbackName)
    local srcDir, folderName = nil, nil
    if love.filesystem.getInfo(mountRoot .. "/mod.lua") then
      srcDir = mountRoot
      folderName = fallbackName:gsub("[^%w_%-]", "_")
    else
      for _, item in ipairs(love.filesystem.getDirectoryItems(mountRoot)) do
        if love.filesystem.getInfo(mountRoot .. "/" .. item .. "/mod.lua") then
          srcDir = mountRoot .. "/" .. item
          folderName = item
          break
        end
      end
    end
    if not srcDir or not folderName or folderName == "" or folderName == "modview" then
      return nil
    end
    love.filesystem.createDirectory("mods")
    local dstDir = "mods/" .. folderName
    removeTree(dstDir)
    copyTre(srcDir, dstDir)
    return folderName
  end
  local oldFileDropped = love.filedropped
    function love.filedropped(file)
    if not open or isReleased() then
      if oldFileDropped then return oldFileDropped(file) end
      return
    end
    local rawName = (file:getFilename() or ""):gsub("\\", "/")
    local baseName = rawName:match("([^/]+)$") or ""
    if baseName:lower():match("%.zip$") or baseName:lower():match("%.love$") then
      local mountPoint = "_substratum_drop"
      if love.filesystem.mount(file, mountPoint) then
        local stem = baseName:gsub("%.[^%.]+$", "")
        local installed = installMountedMod(mountPoint, stem)
        love.filesystem.unmount(file:getFilename())
        pcall(function() file:close() end)
        if installed then
          open = true
          dirty = true
          dropStatus = "INSTALLED: " .. installed .. " (CLICK APPLY & RESTART)"
          if game.audio then game.audio:play("complete") end
          return
        end
      end
    end
    if oldFileDropped then return oldFileDropped(file) end
  end
  local oldKeyPressed = game.keypressed
  function game:keypressed(key, scancode, isrepeat)
    if isReleased() then
      open = false
      return oldKeyPressed(self, key, scancode, isrepeat)
    end
    if key == "f4" then
      open = not open
      return
    end
    if open then
      if key == "escape" then open = false end
      return
    end
    return oldKeyPressed(self, key, scancode, isrepeat)
  end

  local oldTextInput = game.textinput
  function game:textinput(text)
    if open then return end
    if oldTextInput then return oldTextInput(self, text) end
  end

  local oldWheelMoved = game.wheelmoved
  function game:wheelmoved(dx, dy)
    if open then
      if maxScroll > 0 then
        scroll = math.max(0, math.min(maxScroll, scroll - dy * 36))
      end
      return
    end
    if oldWheelMoved then return oldWheelMoved(self, dx, dy) end
  end

  local oldMousePressed = game.mousepressed
  function game:mousepressed(x, y, b)
    if open then
      if b == 1 then
        if Rect.contains(btnRect.x, btnRect.y, btnRect.w, btnRect.h, x, y) then
          game.mods.openFolder()
          return
        end
        if dirty and Rect.contains(restartRect.x, restartRect.y, restartRect.w, restartRect.h, x, y) then
          game.mods:restart()
          return
        end
        for _, hb in ipairs(rowHitboxes) do
          if Rect.contains(hb.x, hb.y, hb.w, hb.h, x, y) then
            if game.mods:toggleMod(hb.folder) ~= nil then
              dirty = true
              if game.audio then game.audio:play("tick") end
            end
            return
          end
        end
        if Rect.contains(closeRect.x, closeRect.y, closeRect.w, closeRect.h, x, y)
           or not Rect.contains(modalRect.x, modalRect.y, modalRect.w, modalRect.h, x, y) then
          open = false
          return
        end
      end
      return
    end
    return oldMousePressed(self, x, y, b)
  end

  local oldMouseReleased = game.mousereleased
  function game:mousereleased(x, y, b)
    if open then return end
    if oldMouseReleased then return oldMouseReleased(self, x, y, b) end
  end

  local oldDraw = game.draw
  function game:draw()
    oldDraw(self)

    if isReleased() then
      open = false
      return
    end

    local lg = love.graphics
    local c = Theme.color
    local scale = (UIScale and UIScale.get) and UIScale.get() or 1
    local font = (self.fonts and self.fonts.small) or lg.getFont()
    local list = game.mods.discovered or game.mods.loaded

    lg.push("all")
    lg.scale(scale)
    lg.setFont(font)

    local sw, sh = lg.getDimensions()



    -- Upper-right corner badge when closed
    if not open then
      local badge = string.format("[F4] MODS (%d/%d)", #game.mods.loaded, #list)
      Theme.set(c.amber, 0.65)
      lg.print(badge, sw - font:getWidth(badge) - 12, 10)
      lg.pop()
      return
    end

    local mx, my = UIScale.toLogical(love.mouse.getPosition())
    local hot = false

    -- Dim backdrop
    lg.setColor(0, 0, 0, 0.55)
    lg.rectangle("fill", 0, 0, sw, sh)

    -- Modal frame
    local w, h = math.min(660, sw - 48), math.min(500, sh - 48)
    local x, y = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
    modalRect.x, modalRect.y, modalRect.w, modalRect.h = x, y, w, h

    Theme.set(c.fieldDark, 0.96)
    lg.rectangle("fill", x, y, w, h)
    Theme.set(c.amber, 1)
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)

    -- Header bar
    local cy = y + 12
    Theme.set(c.substrate, 1)
    lg.print("SUBSTRATUM // v" .. tostring(game.mods.version or game.mods.api), x + 16, cy)

    local closeTxt = "[ESC / CLOSE]"
    closeRect.w = font:getWidth(closeTxt)
    closeRect.h = font:getHeight()
    closeRect.x = x + w - closeRect.w - 16
    closeRect.y = cy
    local hoverClose = Rect.contains(closeRect.x, closeRect.y, closeRect.w, closeRect.h, mx, my)
    if hoverClose then hot = true end
    Theme.set(hoverClose and c.amber or c.creamDim, 1)
    lg.print(closeTxt, closeRect.x, closeRect.y)

    cy = cy + font:getHeight() + 10
    Theme.set(c.line, 1)
    lg.line(x + 16, cy, x + w - 16, cy)
    cy = cy + 10

    -- Action buttons row
    local btnLabel = "[ OPEN MODS FOLDER ]"
    btnRect.w = font:getWidth(btnLabel) + 16
    btnRect.h = font:getHeight() + 8
    btnRect.x = x + 16
    btnRect.y = cy
    local hoverBtn = Rect.contains(btnRect.x, btnRect.y, btnRect.w, btnRect.h, mx, my)
    if hoverBtn then hot = true end

    Theme.set(hoverBtn and c.fieldLight or c.field, 1)
    lg.rectangle("fill", btnRect.x, btnRect.y, btnRect.w, btnRect.h)
    Theme.set(hoverBtn and c.amber or c.glowGood, 1)
    lg.rectangle("line", btnRect.x + 0.5, btnRect.y + 0.5, btnRect.w - 1, btnRect.h - 1)
    lg.print(btnLabel, btnRect.x + 8, btnRect.y + 4)

    -- Apply & Restart button when toggles changed
    if dirty then
      local rLabel = "[ APPLY & RESTART ]"
      restartRect.w = font:getWidth(rLabel) + 16
      restartRect.h = btnRect.h
      restartRect.x = btnRect.x + btnRect.w + 10
      restartRect.y = cy
      local hoverR = Rect.contains(restartRect.x, restartRect.y, restartRect.w, restartRect.h, mx, my)
      if hoverR then hot = true end

      Theme.set(hoverR and c.amber or c.fieldLight, 1)
      lg.rectangle("fill", restartRect.x, restartRect.y, restartRect.w, restartRect.h)
      Theme.set(c.amber, 1)
      lg.rectangle("line", restartRect.x + 0.5, restartRect.y + 0.5, restartRect.w - 1, restartRect.h - 1)
      Theme.set(hoverR and c.fieldDark or c.amber, 1)
      lg.print(rLabel, restartRect.x + 8, restartRect.y + 4)
    else
      restartRect.w = 0
    end

    cy = cy + btnRect.h + 14

    -- Scrollable content region
    local listTop = cy
    local listH = (y + h - 14) - listTop
    lg.setScissor(x * scale, listTop * scale, w * scale, listH * scale)

    rowHitboxes = {}
    local drawY = listTop - scroll

    Theme.set(c.amber, 1)
    lg.print(string.format("MODS (%d/%d ACTIVE — CLICK TO TOGGLE)", #game.mods.loaded, #list), x + 16, drawY)
    drawY = drawY + font:getHeight() + 8

       local hoveredMod = nil
 for _, mod in ipairs(list) do
   local rowX, rowW = x + 16, w - 32
   local lineH = font:getHeight()
   local rowH = lineH + 6
   if mod._error then rowH = rowH + lineH + 2 end

   local inView = (drawY + rowH >= listTop) and (drawY <= listTop + listH)
   local hovered = inView and Rect.contains(rowX, drawY, rowW, rowH, mx, my)
   if hovered then hoveredMod = mod end

   if not mod._core then
     if hovered then hot = true end
     table.insert(rowHitboxes, { x = rowX, y = drawY, w = rowW, h = rowH, folder = mod._folder })
   end

   if hovered then
     Theme.set(c.fieldLight, 0.7)
     lg.rectangle("fill", rowX, drawY, rowW, rowH)
   end

   local stateTag = mod._core and "[*]" or (mod._enabled and "[✓]" or "[ ]")
   local srcTag = mod._external and "USER" or "BUILT-IN"
   local authorTag = mod.author and (" by " .. tostring(mod.author)) or ""
   local title = string.format("%s  %s %s%s (%s • %s)",
     stateTag,
     mod.name or mod._folder,
     mod.version and ("v" .. mod.version) or "",
     authorTag,
     mod._folder,
     srcTag)

   if mod._error then
     Theme.set(c.bad, 1)
     lg.print(title .. " [ERROR]", rowX + 6, drawY + 3)
     lg.print("       " .. mod._error, rowX + 6, drawY + lineH + 5)
   else
     if mod._core then
       Theme.set(c.amber, 1)
     elseif mod._enabled then
       Theme.set(c.glowGood, 1)
     else
       Theme.set(c.creamDim, 0.55)
     end
     lg.print(title, rowX + 6, drawY + 3)
   end

   drawY = drawY + rowH + 2
 end



    -- Overrides Section
    drawY = drawY + 10
    Theme.set(c.amber, 1)
    lg.print("MODULE OVERRIDES", x + 16, drawY)
    drawY = drawY + font:getHeight() + 6

    local keys = {}
    if game.mods.overrides then
      for k in pairs(game.mods.overrides) do keys[#keys + 1] = k end
      table.sort(keys)
    end

    if #keys == 0 then
      Theme.set(c.creamDim, 0.7)
      lg.print("(none)", x + 22, drawY)
      drawY = drawY + font:getHeight() + 4
    else
      for _, modName in ipairs(keys) do
        local status = game.mods.overrides[modName]
        Theme.set(status == "applied" and c.glowGood or c.creamDim, 1)
        lg.print(string.format("• %s [%s]", modName, status:upper()), x + 22, drawY)
        drawY = drawY + font:getHeight() + 4
      end
    end

    local totalContentH = (drawY + scroll) - listTop
    maxScroll = math.max(0, totalContentH - listH)
    scroll = math.min(scroll, maxScroll)

    lg.setScissor()
     if hoveredMod and hoveredMod.desc and hoveredMod.desc ~= "" then
   local descStr = tostring(hoveredMod.desc)
   local tipMaxW = math.min(340, sw - 24)
   local _, wrapped = font:getWrap(descStr, tipMaxW - 16)
   local textW = 0
   for _, line in ipairs(wrapped) do
     textW = math.max(textW, font:getWidth(line))
   end
   local tipW = textW + 16
   local tipH = (#wrapped * font:getHeight()) + 12
   local tx = math.min(mx + 14, sw - tipW - 8)
   local ty = math.min(my + 16, sh - tipH - 8)

   Theme.set(c.fieldDark, 0.98)
   lg.rectangle("fill", tx, ty, tipW, tipH)
   Theme.set(c.amber, 1)
   lg.rectangle("line", tx + 0.5, ty + 0.5, tipW - 1, tipH - 1)
   Theme.set(c.cream, 1)
   lg.printf(descStr, tx + 8, ty + 6, tipW - 16, "left")
 end
    lg.pop()

    if hot and Cursor and Cursor.hot then Cursor.hot() end
    if Cursor and Cursor.draw then Cursor.draw() end
  end
end

return M
