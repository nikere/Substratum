local M = {
  name = "Void Singularity Theme",
  version = "1.0.0"
}

function M:init(game)
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
      shellText = "#F3E8FF",
      shellAccent = "#FF4D8D",
      shellTray = "#090410",
      iconText = "#F3E8FF",
      iconGlyph = "#FF4D8D",
    },
    chrome = { radius = 2, border = 1, gradDir = "h", buttons = "glyph", titleAlign = "left", tray = true },
    wallpaper = { kind = "hex", base = "#090410", color = "#090410", ink = "#6D28D9" },
    cursor = "wand",
    trail = "star",
    trailColors = { "#FF4D8D", "#A855F7", "#38BDF8" },
    crt = 0.85,
  })

  -- Also unlock AESTHETICS automatically if not unlocked yet
  game.mods:onReady(function(g)
    game.mods:unlockApp("aesthetics")
  end)
end

return M
