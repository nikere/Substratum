local M = {
  id      = "dark_matter",
  name    = "Dark Matter Expansion",
  version = "1.0.0",
  author  = "example",
}

function M:init(game)
  -- 1. Add the resource
  game.mods:addMaterial("darkmatter", "Dark Matter", "暗黒物質", {0.2, 0.0, 0.5}, 5)

  -- 2. Add the fleet power
  game.mods:addPower({
    id = "singularity", glyph = "黑洞", cd = 120, dur = 5, auto = "fightStart",
    name = { en = "Singularity", jp = "特異点" },
    desc = { en = "Crushes all enemies in a small radius.", jp = "狭い範囲の全敵を圧壊する。" }
  })

  -- 3. Add terminal commands (note: fn receives (args, term), so use `game` from closure)
  game.mods:addTerminalCommand({
    name = "spawn_dm",
    desc = { en = "spawn 10k dark matter", jp = "暗黒物質を1万生成" },
    fn = function(args, term)
      game.resources:add("mat.darkmatter", 10000)
      return "Singularity stabilized."
    end
  })
  game.mods:addTerminalCommand({
    name = "bsod",
    desc = { en = "trigger system fault", jp = "システム障害を発生" },
    fn = function(args, term)
      game.mods:triggerCrash(false)
      return "CRITICAL_PROCESS_DIED"
    end
  })
end

return M
