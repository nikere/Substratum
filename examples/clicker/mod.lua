local App = require("src.apps.app")
local Theme = require("src.ui.theme")
local Rect = require("src.core.rect")
local Cursor = require("src.ui.cursor")
local Format = require("src.core.format")

local lg = love.graphics

-- 1. Define the custom App window class
local QuantumApp = App:extend()

function QuantumApp:new(game)
  QuantumApp.super.new(self, game)
  self.windowW = 380
  self.windowH = 310
  self.pulse = 0
  self.clickLevel = 1
  self.autoLevel = 0
  self.btnCore = { x = 0, y = 0, w = 0, h = 0 }
  self.btnClickUpg = { x = 0, y = 0, w = 0, h = 0 }
  self.btnAutoUpg = { x = 0, y = 0, w = 0, h = 0 }
end

function QuantumApp:clickPower()
  return self.clickLevel * (2 ^ math.floor((self.clickLevel - 1) / 5))
end

function QuantumApp:autoRate()
  return self.autoLevel * 2.5 * (1.5 ^ math.floor(self.autoLevel / 5))
end

function QuantumApp:clickCost()
  return math.floor(15 * (1.45 ^ (self.clickLevel - 1)))
end

function QuantumApp:autoCost()
  return math.floor(25 * (1.55 ^ self.autoLevel))
end

-- Runs every frame even when window is minimized or closed (once unlocked)
function QuantumApp:fixedUpdate(dt)
  if self.pulse > 0 then
    self.pulse = math.max(0, self.pulse - dt * 3.5)
  end
  local rate = self:autoRate()
  if rate > 0 and self.game and self.game.resources then
    self.game.resources:add("mat.qflux", rate * dt)
  end
end

function QuantumApp:mousepressed(lx, ly, b)
  if b ~= 1 then return end
  local res = self.game.resources
  local cur = res:get("mat.qflux") or 0

  -- Harvest button
  if Rect.contains(self.btnCore.x, self.btnCore.y, self.btnCore.w, self.btnCore.h, lx, ly) then
    res:add("mat.qflux", self:clickPower())
    self.pulse = 1
    if self.game.audio then self.game.audio:play("tick") end
    return
  end

  -- Upgrade Click Power
  local cCost = self:clickCost()
  if Rect.contains(self.btnClickUpg.x, self.btnClickUpg.y, self.btnClickUpg.w, self.btnClickUpg.h, lx, ly) then
    if cur >= cCost then
      res:add("mat.qflux", -cCost)
      self.clickLevel = self.clickLevel + 1
      if self.game.audio then self.game.audio:play("upgrade") end
    elseif self.game.audio then
      self.game.audio:play("deny")
    end
    return
  end

  -- Upgrade Auto Collector
  local aCost = self:autoCost()
  if Rect.contains(self.btnAutoUpg.x, self.btnAutoUpg.y, self.btnAutoUpg.w, self.btnAutoUpg.h, lx, ly) then
    if cur >= aCost then
      res:add("mat.qflux", -aCost)
      self.autoLevel = self.autoLevel + 1
      if self.game.audio then self.game.audio:play("upgrade") end
    elseif self.game.audio then
      self.game.audio:play("deny")
    end
    return
  end
end

function QuantumApp:drawBody(x, y, w, h)
  local c = Theme.color
  local fonts = self.game.fonts
  local small = fonts.small
  local body = fonts.body
  local large = fonts.large

  local flux = self.game.resources:get("mat.qflux") or 0
  local mx, my = 0, 0
  if self.window and self.window.toLocal then
    mx, my = self.window:toLocal(love.mouse.getPosition())
  end

  -- Header stats
  lg.setFont(small)
  Theme.set(c.creamDim, 1)
  lg.print("QUANTUM FLUX STORED", x + 16, y + 12)

  lg.setFont(large)
  Theme.set(c.amber, 1)
  lg.print(Format.number(flux) .. " QF", x + 16, y + 28)

  lg.setFont(small)
  Theme.set(c.glowGood, 1)
  lg.print(string.format("+%s QF/s", Format.number(self:autoRate())), x + 16, y + 54)

  -- Main Clicker Core Button
  local cw, ch = w - 32, 68
  local cx, cy = x + 16, y + 78
  self.btnCore = { x = cx, y = cy, w = cw, h = ch }
  local hoverCore = Rect.contains(cx, cy, cw, ch, mx, my)
  if hoverCore then Cursor.hot() end

  local expand = math.floor(self.pulse * 4)
  Theme.set(hoverCore and c.fieldLight or c.field, 1)
  lg.rectangle("fill", cx - expand, cy - expand, cw + expand * 2, ch + expand * 2)
  Theme.set(hoverCore and c.amber or c.lineBright, 1)
  lg.rectangle("line", cx - expand + 0.5, cy - expand + 0.5, cw + expand * 2 - 1, ch + expand * 2 - 1)

  lg.setFont(body)
  Theme.set(c.cream, 1)
  local title = "[ HARVEST SINGULARITY ]"
  lg.print(title, cx + math.floor((cw - body:getWidth(title)) / 2), cy + 14)

  lg.setFont(small)
  Theme.set(c.amber, 1)
  local sub = string.format("+%s QF PER PULSE", Format.number(self:clickPower()))
  lg.print(sub, cx + math.floor((cw - small:getWidth(sub)) / 2), cy + 38)

  -- Upgrade 1: Click Amplifier
  local u1y = cy + ch + 16
  local uh = 44
  self.btnClickUpg = { x = cx, y = u1y, w = cw, h = uh }
  local cCost = self:clickCost()
  local canClick = flux >= cCost
  local hoverU1 = Rect.contains(cx, u1y, cw, uh, mx, my)
  if hoverU1 and canClick then Cursor.hot() end

  Theme.set(hoverU1 and c.fieldLight or c.field, 1)
  lg.rectangle("fill", cx, u1y, cw, uh)
  Theme.set(canClick and c.glowGood or c.line, 1)
  lg.rectangle("line", cx + 0.5, u1y + 0.5, cw - 1, uh - 1)

  lg.setFont(small)
  Theme.set(c.cream, 1)
  lg.print(string.format("PULSE AMPLIFIER [LV.%d]", self.clickLevel), cx + 10, u1y + 6)
  Theme.set(canClick and c.glowGood or c.creamDim, 1)
  lg.print(string.format("COST: %s QF  (2x every 5 lv)", Format.number(cCost)), cx + 10, u1y + 24)

  -- Upgrade 2: Auto Collector
  local u2y = u1y + uh + 10
  self.btnAutoUpg = { x = cx, y = u2y, w = cw, h = uh }
  local aCost = self:autoCost()
  local canAuto = flux >= aCost
  local hoverU2 = Rect.contains(cx, u2y, cw, uh, mx, my)
  if hoverU2 and canAuto then Cursor.hot() end

  Theme.set(hoverU2 and c.fieldLight or c.field, 1)
  lg.rectangle("fill", cx, u2y, cw, uh)
  Theme.set(canAuto and c.glowGood or c.line, 1)
  lg.rectangle("line", cx + 0.5, u2y + 0.5, cw - 1, uh - 1)

  Theme.set(c.cream, 1)
  lg.print(string.format("ORBITAL SIPHON [LV.%d]", self.autoLevel), cx + 10, u2y + 6)
  Theme.set(canAuto and c.glowGood or c.creamDim, 1)
  lg.print(string.format("COST: %s QF  (Auto-generates)", Format.number(aCost)), cx + 10, u2y + 24)
end

-- Persist upgrade levels inside the game's save slot automatically!
function QuantumApp:serialize()
  return { clickLevel = self.clickLevel, autoLevel = self.autoLevel }
end

function QuantumApp:restore(data)
  if type(data) == "table" then
    self.clickLevel = data.clickLevel or 1
    self.autoLevel = data.autoLevel or 0
  end
end

-- 2. Register the mod via Modding API
return {
  name = "Quantum Clicker",
  version = "1.0.0",
  author = "example",
  init = function(self, game)
    game.mods:addMaterial("qflux", "Q-Flux", "量子束", { 0.45, 0.85, 1.0 }, 5)

    -- 1. Register as a hidden secret app (persists in save once unlocked)
    game.mods:registerApp({
      id = "quantum_clicker",
      title = "QUANTUM",
      sub = "CLICKER",
      icon = "量",
      eager = true,
      unlock = { flag = "secret.quantum_clicker" }
    }, QuantumApp)
    game.mods:addProcess({
      key = "quantum",
      name = "quantum.exe",
      ring = 2,
      apps = { "quantum_clicker" },
      present = { unlocked = "quantum_clicker" },
    })

    -- 2. Register the TERMINAL command that unlocks it
    game.mods:addTerminalCommand({
      name = "quantum",
      secret = "quantum_clicker",
      lore = {
        en = "A sub-process folded into the vacuum state. Type QUANTUM, and it begins to count."
      }
    })
  end
}
