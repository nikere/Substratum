local Android = {}
function Android.apply(game, api, loaderState)
    local balance = require("src.data.balance")
    local UIScale = require("src.ui.uiscale")
    local HostFS = require("src.services.hostfs")
    --  Mobile UI Scaling
    if balance and balance.ui and balance.ui.scale then
        balance.ui.scale.steps = {0.65, 0.75, 0.85, 1, 1.25, 1.5, 1.75, 2}
        balance.ui.scale.minW = 480
        balance.ui.scale.minH = 270
    end
    function UIScale.effective(scale, pw, ph)
        local C = balance.ui.scale
        return math.max(0.5, math.min(scale, pw / C.minW, ph / C.minH))
    end
    local origRefresh = UIScale.refresh
    function UIScale.refresh()
        local was = UIScale.get()
        local res = origRefresh()
        return res or (UIScale.get() ~= was)
    end
    function game:applyFullscreen(on)
        self._borderless = false
        local dw, dh = love.window.getDesktopDimensions()
        local w = math.max(dw, dh)
        local h = math.min(dw, dh)
        love.window.setMode(w, h, {
            fullscreen = true,
            resizable = false,
            highdpi = true,
            usedpiscale = false
        })
        if self.crt then self:windowResized() end
    end
    api:onReady(function(g)
        love.window.setMode(0, 0, {
            fullscreen = true,
            highdpi = true,
            usedpiscale = false,
            resizable = false
        })
    end)
    -- Two-Finger Touch Scrolling
    local activeTouches = {}
    local touchCount = 0
    local scrollAcc = 0

    local origTouchPressed = love.touchpressed
    function love.touchpressed(id, x, y, dx, dy, pressure)
        if not activeTouches[id] then
            activeTouches[id] = true
            touchCount = touchCount + 1
        end
        scrollAcc = 0
        if origTouchPressed then
            return origTouchPressed(id, x, y, dx, dy, pressure)
        end
    end
    local origTouchReleased = love.touchreleased
    function love.touchreleased(id, x, y, dx, dy, pressure)
        if activeTouches[id] then
            activeTouches[id] = nil
            touchCount = math.max(0, touchCount - 1)
        end
        scrollAcc = 0
        if origTouchReleased then
            return origTouchReleased(id, x, y, dx, dy, pressure)
        end
    end
    local origTouchMoved = love.touchmoved
    function love.touchmoved(id, x, y, dx, dy, pressure)
        if touchCount >= 2 then
            scrollAcc = scrollAcc + (dy / touchCount)
            local step = 24
            if math.abs(scrollAcc) >= step then
                local ticks = math.modf(scrollAcc / step)
                scrollAcc = scrollAcc - ticks * step
                if love.wheelmoved then love.wheelmoved(0, ticks) end
            end
            return
        end
        if origTouchMoved then
            return origTouchMoved(id, x, y, dx, dy, pressure)
        end
    end
    local function sdW()
        local f = io.open("/sdcard/apotheosis/.probe", "w")
        if f then
            f:close()
            os.remove("/sdcard/apotheosis/.probe")
            return true
        end
        return false
    end
    local storageOK = sdW()
    local origTextInput = love.textinput
    love.textinput = function(t)
        if type(t) == "string" then
            t = t:gsub("\194\160", " ")
            if #t > 1 then
                for ch in t:gmatch("[%g ]") do
                    if origTextInput then origTextInput(ch) end
                end
                return
            end
        end
        if origTextInput then return origTextInput(t) end
    end
    local origFocus = game.focus
    function game:focus(f)
        if f and not storageOK then
            storageOK = sdW()
            if storageOK then
                print("[SubstratumA] external storage granted")
            end
        end
        if origFocus then return origFocus(self, f) end
    end
    if HostFS then
        function HostFS.pickFolder()
            local dir = "/sdcard/apotheosis/music"
            os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
            if love.system and love.system.setClipboardText then
                love.system.setClipboardText(dir)
            end
            local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
            local hasFiles = p and p:read("*l") ~= nil
            if p then p:close() end
            return hasFiles and dir or nil
        end
    end
    api.listDirs = function(self, dir)
        local out, p = {}, io.popen('ls -1 -p "' .. dir .. '" 2>/dev/null')
        if p then
            for line in p:lines() do
                if line:sub(-1) == "/" then
                    out[#out + 1] = line:sub(1, -2)
                end
            end
            p:close()
        end
        table.sort(out)
        return out
    end
    api.pickFolder = function(self, hint)
        hint = hint or "/sdcard/apotheosis"
        if not storageOK then
            return nil, "storage permission not granted"
        end
        return (#self:listDirs(hint) + 1 > 0) and hint or nil
    end
    api.openFolder = function(self, dir)
        if type(self) ~= "table" then self, dir = api, self end
        dir = dir or "/sdcard/apotheosis/mods"
        os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
        if love.system and love.system.setClipboardText then
            love.system.setClipboardText(dir)
        end
        print("[SubstratumA] Path copied to clipboard: " .. dir)
        return true
    end
    local lg = love.graphics    -- i hate this one ... i took me soo much time
    local origClear = lg.clear
    lg.clear = function(...)
        if lg.getCanvas() then
            local sx, sy, sw, sh = lg.getScissor()
            if sx then
                lg.setScissor()
                origClear(...)
                lg.setScissor(sx, sy, sw, sh)
                return
            end
        end
        return origClear(...)
    end
    -- Virtual Keyboard Auto-Toggle & Pause Menu Button
    local kbdApps = {terminal = true, notepad = true}
    local autoKeyboard = false
    local origMousePressed = game.mousepressed
    function game:mousepressed(x, y, button, istouch, presses)
        local res = origMousePressed(self, x, y, button, istouch, presses)
        if autoKeyboard then
            if self.crash then
                if love.keyboard.hasTextInput and love.keyboard.hasTextInput() then
                    love.keyboard.setTextInput(false)
                end
                return res
            end
            local cur = self.scenes and self.scenes:current()
            local inPause = cur and cur.pauseMenu and cur.pauseMenu.visible
            local activeWin = (not inPause) and cur and cur.wm and
                                  cur.wm:focusedWindow()
            local appId = activeWin and activeWin.app and activeWin.app.id
            if appId and kbdApps[appId] then
                love.keyboard.setTextInput(true)
            elseif love.keyboard.hasTextInput and love.keyboard.hasTextInput() then
                love.keyboard.setTextInput(false)
            end
        end
        return res
    end
    api:addPauseButton("kbd", "KEYBOARD: OFF", function(g, pauseMenu)
        autoKeyboard = not autoKeyboard
        api:addString("pause.mod_kbd",autoKeyboard and "KEYBOARD: ON" or "KEYBOARD: OFF")
        if not autoKeyboard then love.keyboard.setTextInput(false) end
    end)
end
return Android
