local M = {
  name = "Void Singularity Theme",
  version = "1.1.0",
  author = "nikere",
  desc = "Showcase theme with custom stripe, wallpaper, trail, cursor, and desktop toy.",
}

function M:init(game)
  -- 1. Custom animated stripe (window titlebars + taskbar)
  game.mods:registerStripe("pulse_bar", function(x, y, w, h, alpha)
    local lg = love.graphics
    local t = love.timer.getTime()
    lg.setColor(0.20, 0.05, 0.35, alpha)
    lg.rectangle("fill", x, y, w, h)
    local px = x + ((t * 140) % w)
    lg.setColor(1.0, 0.30, 0.55, alpha)
    lg.rectangle("fill", px, y, math.min(48, x + w - px), h)
  end)

  -- 2. Custom animated starfield wallpaper
  game.mods:registerWallpaper("cosmic_stars", function(w, h, workH, t, wp, fonts)
    local lg = love.graphics
    lg.setColor(0.03, 0.01, 0.07, 1)
    lg.rectangle("fill", 0, 0, w, h)
    for i = 1, 70 do
      local sx = (i * 197 + t * (12 + (i % 18))) % w
      local sy = (i * 89) % workH
      local a = 0.35 + 0.55 * math.abs(math.sin(t * 2 + i))
      lg.setColor(0.85, 0.65, 1.0, a)
      lg.circle("fill", sx, sy, (i % 4 == 0) and 2 or 1)
    end
  end)

  -- 3. Custom diamond cursor trail
  game.mods:registerTrail("diamond", function(x, y, r, rot, col, k)
    local lg = love.graphics
    lg.push()
    lg.translate(x, y)
    lg.rotate(rot)
    lg.polygon("fill", 0, -r * 1.4, r * 0.9, 0, 0, r * 1.4, -r * 0.9, 0)
    lg.pop()
  end)

  -- 4. Custom black-hole cursor
  game.mods:registerCursor("singularity", function(x, y, fill, outline)
    local lg = love.graphics
    lg.setColor(0.54, 0.31, 1.0, 0.45)
    lg.circle("line", x, y, 9)
    lg.setColor(1.0, 0.30, 0.55, 0.9)
    lg.circle("line", x, y, 5)
    lg.setColor(0.04, 0.02, 0.06, 1.0)
    lg.circle("fill", x, y, 4)
  end)

  -- 5. Custom toggleable desktop toy
  local flakes = {}
  for i = 1, 55 do
    flakes[i] = {
      x = love.math.random(0, 1920),
      y = love.math.random(0, 1080),
      sp = love.math.random(25, 55),
      r = love.math.random(1, 3),
    }
  end
  
  game.mods:registerToy({
    key = "void_snow",
    label = "Void Snow",
    tip = "Drifting cosmic embers across the desktop.",
    default = false,
    update = function(dt, g, desk)
      local sw, sh = love.graphics.getDimensions()
      for _, f in ipairs(flakes) do
        f.y = (f.y + f.sp * dt) % sh
        f.x = (f.x + math.sin(love.timer.getTime() + f.y * 0.02) * 18 * dt) % sw
      end
    end,
    draw = function(fonts, g, desk)
      local lg = love.graphics
      lg.setColor(1.0, 0.35, 0.65, 0.75)
      for _, f in ipairs(flakes) do
        lg.circle("fill", f.x, f.y, f.r)
      end
    end,
  })

  -- 6. Register the theme
  game.mods:addTheme({
    id = "void_singularity",
    name = "VOID SINGULARITY",
    tip = "Event horizon palette with crimson accents.",
    palette = {
      wallpaper = "#090410",
      fieldDark = "#120820",
      field = "#1A0D2E",
      fieldLight = "#271445",
      line = "#4D2680",
      lineBright = "#8A4FFF",
      cream = "#F3E8FF",
      creamDim = "#A78BFA",
      amber = "#FF4D8D",
      amberDim = "#9D174D",
      glowGood = "#34D399",
      bad = "#FB7185",
      titlebar = "#4C1D95",
      titlebar2 = "#831843",
      titlebarBlur = "#240E47",
      titlebarBlur2 = "#3B0B20",
      titlebarText = "#F3E8FF",
      titlebarTextBlur = "#A78BFA",
      shellFace = "#1A0D2E",
      shellFaceHi = "#2E1752",
      shellFaceLo = "#120820",
      shellEdge = "#6D28D9",
      shellEdgeHi = "#FF4D8D",
      shellLight = "#8A4FFF",
      shellDark = "#06020A",
      shellText = "#F3E8FF",
      shellTextDim = "#A78BFA",
      shellAccent = "#FF4D8D",
      shellTray = "#090410",
      iconText = "#F3E8FF",
      iconGlyph = "#FF4D8D",
      iconShadow = { 0.04, 0.02, 0.06, 0.9 },
    },
    chrome = { radius = 2, border = 1, gradDir = "v", buttons = "glyph", titleAlign = "left", stripe = "pulse_bar", tray = true },
    wallpaper = { kind = "cosmic_stars", base = "#090410" },
    cursor = "singularity",
    trail = "diamond",
    trailColors = { "#FF4D8D", "#A855F7", "#38BDF8" },
    crt = 0.85,
  })
end

return M
