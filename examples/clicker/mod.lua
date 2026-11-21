local App = require("src.apps.app")
local Theme = require("src.ui.theme")
local Rect = require("src.core.rect")
local Cursor = require("src.ui.cursor")
local Format = require("src.core.format")

local lg = love.graphics

-- 1. Define the custom App window class
local QuantumApp = App:extend()
QuantumApp.windowW, QuantumApp.windowH = 380, 368
QuantumApp.minW, QuantumApp.minH = 340, 340

function QuantumApp:new(game)
  QuantumApp.super.new(self, game)
  self.pulse = 0
  self.clickLevel = 1
  self.autoLevel = 0
  self.synthesized = 0
  self.popups = {}
  self.btnCore = { x = 0, y = 0, w = 0, h = 0 }
  self.btnClickUpg = { x = 0, y = 0, w = 0, h = 0 }
  self.btnAutoUpg = { x = 0, y = 0, w = 0, h = 0 }
  self.btnSynth = { x = 0, y = 0, w = 0, h = 0 }
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

function QuantumApp:synthCost()
  return math.floor(100 * (1.6 ^ self.synthesized))
end

-- Runs every frame even when window is minimized or closed (once unlocked)
function QuantumApp:fixedUpdate(dt)
  if self.pulse > 0 then
    self.pulse = math.max(0, self.pulse - dt * 3.5)
  end
  for i = #self.popups, 1, -1 do
    local p = self.popups[i]
    p.y = p.y - 28 * dt
    p.life = p.life - dt
    if p.life <= 0 then table.remove(self.popups, i) end
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

  -- 1. Harvest button
  if Rect.contains(self.btnCore.x, self.btnCore.y, self.btnCore.w, self.btnCore.h, lx, ly) then
    local gain = self:clickPower()
    res:add("mat.qflux", gain)
    self.pulse = 1
    self.popups[#self.popups + 1] = {
      x = lx + love.math.random(-12, 12),
      y = ly - 6,
      text = "+" .. Format.number(gain),
      life = 0.75,
    }
    if self.game.audio then self.game.audio:play("tick") end
    return
  end

  -- 2. Upgrade Click Power
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

  -- 3. Upgrade Auto Collector
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

  -- 4. Condense Q-Flux into base-game Dust
  local sCost = self:synthCost()
  if Rect.contains(self.btnSynth.x, self.btnSynth.y, self.btnSynth.w, self.btnSynth.h, lx, ly) then
    if cur >= sCost then
      res:add("mat.qflux", -sCost)
      local dustGain = 10 * (self.synthesized + 1)
      res:add("mat.dust", dustGain)
      self.synthesized = self.synthesized + 1
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
  local small, body, large = fonts.small, fonts.body, fonts.large

  local flux = self.game.resources:get("mat.qflux") or 0
  local mx, my = self:localMouse()

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
  local cw, ch = w - 32, 64
  local cx, cy = x + 16, y + 76
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
  lg.print(title, cx + math.floor((cw - body:getWidth(title)) / 2), cy + 12)

  lg.setFont(small)
  Theme.set(c.amber, 1)
  local sub = string.format("+%s QF PER PULSE", Format.number(self:clickPower()))
  lg.print(sub, cx + math.floor((cw - small:getWidth(sub)) / 2), cy + 36)

  -- Helper to draw upgrade / action rows with progress fill
  local function drawActionRow(ry, rh, titleText, subText, cost, canAfford, accentCol)
    local hover = Rect.contains(cx, ry, cw, rh, mx, my)
    if hover and canAfford then Cursor.hot() end

    Theme.set(hover and c.fieldLight or c.field, 1)
    lg.rectangle("fill", cx, ry, cw, rh)

    local pct = math.min(1, flux / math.max(1, cost))
    Theme.set(accentCol, canAfford and 0.22 or 0.10)
    lg.rectangle("fill", cx + 1, ry + 1, math.floor((cw - 2) * pct), rh - 2)

    Theme.set(canAfford and accentCol or c.line, 1)
    lg.rectangle("line", cx + 0.5, ry + 0.5, cw - 1, rh - 1)

    lg.setFont(small)
    Theme.set(c.cream, 1)
    lg.print(titleText, cx + 10, ry + 6)
    Theme.set(canAfford and accentCol or c.creamDim, 1)
    lg.print(subText, cx + 10, ry + 24)
  end

  local uh = 44
  local u1y = cy + ch + 14
  self.btnClickUpg = { x = cx, y = u1y, w = cw, h = uh }
  local cCost = self:clickCost()
  drawActionRow(
    u1y, uh,
    string.format("PULSE AMPLIFIER [LV.%d]", self.clickLevel),
    string.format("COST: %s QF  (2x every 5 lv)", Format.number(cCost)),
    cCost, flux >= cCost, c.glowGood
  )

  local u2y = u1y + uh + 8
  self.btnAutoUpg = { x = cx, y = u2y, w = cw, h = uh }
  local aCost = self:autoCost()
  drawActionRow(
    u2y, uh,
    string.format("ORBITAL SIPHON [LV.%d]", self.autoLevel),
    string.format("COST: %s QF  (Auto-generates)", Format.number(aCost)),
    aCost, flux >= aCost, c.glowGood
  )

  local u3y = u2y + uh + 8
  self.btnSynth = { x = cx, y = u3y, w = cw, h = uh }
  local sCost = self:synthCost()
  local dustGain = 10 * (self.synthesized + 1)
  drawActionRow(
    u3y, uh,
    string.format("CONDENSE MATTER [x%d]", self.synthesized),
    string.format("COST: %s QF -> +%s DUST", Format.number(sCost), Format.number(dustGain)),
    sCost, flux >= sCost, c.amber
  )

  -- Floating click popups
  lg.setFont(small)
  for _, p in ipairs(self.popups) do
    Theme.set(c.amber, math.min(1, p.life * 2))
    lg.print(p.text, p.x, p.y)
  end
end

-- Persist upgrade levels inside the game's save slot automatically
function QuantumApp:serialize()
  return {
    clickLevel = self.clickLevel,
    autoLevel = self.autoLevel,
    synthesized = self.synthesized,
  }
end

function QuantumApp:restore(data)
  if type(data) == "table" then
    self.clickLevel = data.clickLevel or 1
    self.autoLevel = data.autoLevel or 0
    self.synthesized = data.synthesized or 0
  end
end

-- 2. Register the mod via Modding API
return {
  name = "Quantum Clicker",
  version = "1.1.0",
  author = "example",
  desc = "Secret idle clicker app unlocked via the QUANTUM terminal command.",
  init = function(self, game)
    game.mods:addMaterial("qflux", "Q-Flux", "量子束", { 0.45, 0.85, 1.0 }, 5)

    -- 1. Register as a hidden secret app (persists in save once unlocked)
    game.mods:registerApp({
      id = "quantum_clicker",
      title = "QUANTUM CLICKER",
      title_jp = "量子",
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
