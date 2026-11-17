local M = {}
M.loaded = {}
M.discovered = {} -- All mods found (enabled + disabled)
M.disabled = {} -- { [folder] = true }
M.overrides = {}
M.api = "1.2.2"

local DISABLED_FILE = "mods_disabled.txt"

function M.loadConfig()
    M.disabled = {}
    if not love.filesystem.getInfo(DISABLED_FILE) then return end
    local text = love.filesystem.read(DISABLED_FILE) or ""
    for line in (text .. "\n"):gmatch("([^\r\n]+)") do
        local folder = line:match("^%s*(.-)%s*$")
        if folder ~= "" and folder ~= "modview" then
            M.disabled[folder] = true
        end
    end
end

function M.saveConfig()
    local lines = {}
    for folder, off in pairs(M.disabled) do
        if off and folder ~= "modview" then lines[#lines + 1] = folder end
    end
    table.sort(lines)
    love.filesystem.write(DISABLED_FILE, table.concat(lines, "\n"))
end

-- Sequence 1: Runs at line 1 of main.lua
function M.applyOverrides()
    love.filesystem.createDirectory("mods")
    love.filesystem.createDirectory("overrides")

    local loaders = package.loaders or package.searchers
    table.insert(loaders, 1,
                 function(modName) return package.preload[modName] end)

    local root = "overrides"
    if not love.filesystem.getInfo(root) then return end

    local function scan(dir)
        local items = love.filesystem.getDirectoryItems(dir)
        if not items then return end
        table.sort(items)

        for _, item in ipairs(items) do
            local path = dir .. "/" .. item
            local info = love.filesystem.getInfo(path)

            if info and info.type == "directory" then
                scan(path)
            elseif item:match("%.lua$") then
                local modName = path:sub(#root + 2):gsub("%.lua$", ""):gsub("/",
                                                                            ".")

                if package.loaded[modName] then
                    print("[Substratum] WARNING: Override for '" .. modName ..
                              "' ignored (already loaded)")
                else
                    M.overrides[modName] = "preloaded"
                    package.loaded[modName] = nil
                    package.preload[modName] = function()
                        local chunk, err = love.filesystem.load(path)
                        if not chunk then
                            M.overrides[modName] = "syntax error"
                            print("[Substratum] Syntax error in override " ..
                                      path .. ": " .. tostring(err))
                            error(err)
                        end
                        local ok, res = pcall(chunk)
                        if not ok then
                            M.overrides[modName] = "runtime error"
                            print("[Substratum] Runtime error in override " ..
                                      path .. ": " .. tostring(res))
                            error(res)
                        end
                        if res == nil then
                            M.overrides[modName] = "nil return"
                            print("[Substratum] Override " .. path ..
                                      " returned nil (forgot `return`?)")
                            error("returned nil")
                        end
                        M.overrides[modName] = "applied"
                        return res
                    end
                    print("[Substratum] Preloaded override: " .. modName)
                end
            end
        end
    end

    scan(root)
    -- @ANDROID_OVERRIDES_START
    -- @ANDROID_OVERRIDES_END
end

-- Sequence 2: Runs before game:load()
function M.loadMods(game)
    M.loadConfig()
    local saveDir = love.filesystem.getSaveDirectory()
    print("[Substratum] Save/Mod directory: " .. saveDir)

    local apiChunk, apiErr = love.filesystem.load("mods/api.lua")
    if not apiChunk then
        print("[Substratum] FATAL: Could not load mods/api.lua: " ..
                  tostring(apiErr))
        game.mods = {
            version = "0.0",
            api = "0.0",
            loaded = {},
            discovered = {},
            overrides = {},
            get = function() end,
            openFolder = function() end
        }
        return
    end

    local okApi, Api = pcall(apiChunk)
    if not okApi or type(Api) ~= "table" then
        print("[Substratum] FATAL: Error running mods/api.lua: " ..
                  tostring(Api))
        game.mods = {
            version = "0.0",
            api = "0.0",
            loaded = {},
            discovered = {},
            overrides = {},
            get = function() end,
            openFolder = function() end
        }
        return
    end

    game.mods = Api.create(game, M)

    local modsDir = "mods"
    local dirInfo = love.filesystem.getInfo(modsDir)
    if not dirInfo or dirInfo.type ~= "directory" then return end

    local items = love.filesystem.getDirectoryItems(modsDir)
    table.sort(items)

    for _, folder in ipairs(items) do
        local modEntry = modsDir .. "/" .. folder .. "/mod.lua"
        local info = love.filesystem.getInfo(modEntry)

        if info and info.type == "file" then
            local isDisabled = (M.disabled[folder] == true)
            local isExternal = (love.filesystem.getRealDirectory(modEntry) ==
                                   saveDir)

            -- Record in discovered list even if disabled so GUI can toggle it back on
            local record = {
                name = folder,
                _folder = folder,
                _path = modsDir .. "/" .. folder,
                _external = isExternal,
                _enabled = not isDisabled,
                _core = (folder == "modview")
            }
            table.insert(M.discovered, record)

            if isDisabled then
                print("[Substratum] Skipped (disabled): " .. folder)
            else
                local chunk, loadErr = love.filesystem.load(modEntry)
                if chunk then
                    local ok, mod = pcall(chunk)
                    if ok and type(mod) == "table" then
                        mod._folder = folder
                        mod._path = modsDir .. "/" .. folder
                        mod._external = isExternal
                        mod._enabled = true
                        mod._core = (folder == "modview")

                        -- Replace placeholder record with full mod metadata
                        M.discovered[#M.discovered] = mod
                        table.insert(M.loaded, mod)
                        print("[Substratum] Loaded: " .. (mod.name or folder))

                        if mod.init then
                            local initOk, err =
                                pcall(mod.init, mod, game, folder)
                            if not initOk then
                                mod._error = tostring(err)
                                print(
                                    "[Substratum] Error in " .. folder .. ": " ..
                                        tostring(err))
                            end
                        end
                    else
                        record._error = tostring(mod)
                        print("[Substratum] Failed: " .. folder .. " (" ..
                                  tostring(mod) .. ")")
                    end
                else
                    record._error = tostring(loadErr)
                    print("[Substratum] Syntax error in " .. folder .. ": " ..
                              tostring(loadErr))
                end
            end
        end
    end
    -- @ANDROID_MODS_START
    -- @ANDROID_MODS_END
end

return M
