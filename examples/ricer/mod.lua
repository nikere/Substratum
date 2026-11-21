local M = {
    name = "Desktop Rice Studio",
    version = "1.2.0",
    author = "nikere",
    desc = "The real rice, live RGB palette, chrome, wallpaper, stripe, cursor, trail, mascot, toy, and profile studio."
}

function M:init(game)
    local App = require("src.apps.app")
    local Theme = require("src.ui.theme")
    local Rect = require("src.core.rect")
    local Cursor = require("src.ui.cursor")
    local Aesthetics = require("src.data.aesthetics")
    local WallpaperOverlay = require("src.ui.wallpaperoverlay")
        local Aesthetic = require("src.services.aesthetic")
    local PROFILE_FILE = "rice_profiles.lua"

    local function loadProfileFile()
        if not love.filesystem.getInfo(PROFILE_FILE) then return {} end
        local chunk = love.filesystem.load(PROFILE_FILE)
        if not chunk then return {} end
        local ok, data = pcall(chunk)
        return (ok and type(data) == "table") and data or {}
    end

    local function applyProfileData(slot, p)
        local aes = game.aesthetic
        if not (p and aes) then return false end
        local id = "rice_profile_" .. slot
        game.mods:removeTheme(id)
        game.mods:addTheme({
            id = id,
            name = "PROFILE " .. slot,
            tip = "Saved Rice Studio profile.",
            palette = p.palette or {},
            chrome = p.chrome or {},
            wallpaper = p.wallpaper or {kind = "grid", base = "#0A2429"},
            cursor = p.cursor or "arrow",
            trail = p.trail or "sparkle",
            trailColors = p.trailColors or {"#E8C170", "#F4ECD8", "#9BE8C9"},
            crt = p.crt
        })
        if p.state then
            local st = {}
            for k, v in pairs(p.state) do st[k] = v end
            st.theme = id
            aes:set(st)
        else
            aes:set({theme = id})
        end
        return true
    end

        local origAesSet = Aesthetic.set
    local autoloadApplied = false
    function Aesthetic:set(tbl, ...)
        origAesSet(self, tbl, ...)
        if not autoloadApplied then
            autoloadApplied = true
            local data = loadProfileFile()
            local slot = data.autoload
            if slot and data[slot] then
                applyProfileData(slot, data[slot])
            end
        end
    end


    local lg = love.graphics
    local floor, max, min = math.floor, math.max, math.min

    local PALETTE_KEYS = {
        "wallpaper", "fieldDark", "field", "fieldLight", "line", "lineBright",
        "cream", "creamDim", "amber", "amberDim", "glowGood", "bad", "titlebar",
        "titlebar2", "titlebarText", "titlebarBlur", "titlebarBlur2",
        "titlebarTextBlur", "shellFace", "shellFaceHi", "shellFaceLo",
        "shellEdge", "shellEdgeHi", "shellLight", "shellDark", "shellText",
        "shellTextDim", "shellAccent", "shellTray", "iconText", "iconGlyph"
    }

    local function toHex(rgb)
        local r = floor(max(0, min(1, rgb[1] or 0)) * 255 + 0.5)
        local g = floor(max(0, min(1, rgb[2] or 0)) * 255 + 0.5)
        local b = floor(max(0, min(1, rgb[3] or 0)) * 255 + 0.5)
        return string.format("#%02X%02X%02X", r, g, b)
    end

    local function buildWallpaperForTheme(kind)
        local c = Theme.color
        local bg = toHex(c.wallpaper)
        local dark = toHex(c.fieldDark)
        local mid = toHex(c.field)
        local acc1 = toHex(c.amber)
        local acc2 = toHex(c.lineBright)
        local acc3 = toHex(c.glowGood)
        local tb1 = toHex(c.titlebar)
        local tb2 = toHex(c.titlebar2)

        local map = {
            grid = {kind = "grid", base = bg},
            solid = {kind = "solid", base = bg, color = bg},
            sky = {
                kind = "sky",
                base = tb1,
                sky1 = tb2,
                sky2 = acc2,
                hill = acc3,
                hill2 = mid,
                bubble = toHex(c.cream)
            },
            skyline = {
                kind = "skyline",
                base = bg,
                top = dark,
                mid = tb1,
                horizon = acc1,
                city = bg,
                lit = acc3
            },
            dots = {
                kind = "dots",
                base = bg,
                color = bg,
                dots = {acc1, acc2, acc3, tb1, tb2}
            },
            hex = {kind = "hex", base = bg, color = bg, ink = acc1},
            sunset = {
                kind = "sunset",
                base = bg,
                top = dark,
                horizon = tb1,
                sun1 = acc1,
                sun2 = tb2,
                floor = bg,
                grid = acc2
            },
            lcd = {
                kind = "lcd",
                base = mid,
                color = mid,
                ink = acc1,
                dark = dark
            },
            phosphor = {kind = "phosphor", base = bg, color = bg, ink = acc1},
            holo = {
                kind = "holo",
                base = bg,
                color = dark,
                blobs = {acc1, acc2, acc3, tb1}
            }
        }
        return map[kind] or {kind = kind, base = bg, color = bg, ink = acc1}
    end

    local function serializeVal(v, indent)
        local t = type(v)
        if t == "number" or t == "boolean" then return tostring(v) end
        if t == "string" then return string.format("%q", v) end
        if t == "table" then
            local pad = string.rep("  ", indent)
            local inner = string.rep("  ", indent + 1)
            local out = {"{"}
            for k, val in pairs(v) do
                local keyStr = type(k) == "number" and ("[" .. k .. "]") or
                                   ("[" .. string.format("%q", k) .. "]")
                out[#out + 1] = inner .. keyStr .. " = " ..
                                    serializeVal(val, indent + 1) .. ","
            end
            out[#out + 1] = pad .. "}"
            return table.concat(out, "\n")
        end
        return "nil"
    end

    local RiceApp = App:extend()
    RiceApp.windowW, RiceApp.windowH = 580, 470
    RiceApp.minW, RiceApp.minH = 480, 360

    function RiceApp:new(g)
        RiceApp.super.new(self, g)
        self.id = "rice_studio"
        self.title = {jp = "装飾", en = "RICE STUDIO"}
        self.constantText = true
        self.tab = "themes" -- "themes" | "palette" | "mix" | "mascot" | "toys" | "profiles"
        self.palKey = "amber"
        self.scroll = 0
        self.contentH = 0
        self._rects = {}
        self._nRects = 0
        self._dragSlider = nil
        self._toast = nil
        self._toastT = 0
        self._mascots = {}
        self._profiles = self:loadProfiles()
    end

    function RiceApp:loadProfiles()
        if not love.filesystem.getInfo(PROFILE_FILE) then return {} end
        local chunk = love.filesystem.load(PROFILE_FILE)
        if not chunk then return {} end
        local ok, data = pcall(chunk)
        return (ok and type(data) == "table") and data or {}
    end

    function RiceApp:writeProfiles()
        love.filesystem.write(PROFILE_FILE,
                              "return " .. serializeVal(self._profiles, 0))
    end

    function RiceApp:saveProfile(slot)
        local aes = self.game.aesthetic
        if not aes then return end
        local row = aes:row()
        local pal = {}
        for k, col in pairs(Theme.color) do
            if type(col) == "table" and col[1] and col[2] and col[3] then
                if col[4] and col[4] < 0.999 then
                    pal[k] = { col[1], col[2], col[3], col[4] }
                else
                    pal[k] = toHex(col)
                end
            end
        end
        self._profiles[slot] = {
            name = "SLOT " .. slot .. " (" .. tostring(row.id) .. ")",
            baseTheme = row.id,
            palette = pal,
            chrome = {
                radius = row.chrome.radius or 0,
                border = row.chrome.border or 1,
                gradDir = row.chrome.gradDir or "v",
                buttons = row.chrome.buttons or "glyph",
                titleAlign = row.chrome.titleAlign or "left",
                stripe = type(row.chrome.stripe) == "string" and row.chrome.stripe or nil,
                taskbarStripe = row.chrome.taskbarStripe,
                gloss = row.chrome.gloss == true,
                bevel = row.chrome.bevel == true,
                tray = row.chrome.tray ~= false
            },
            wallpaper = row.wallpaper,
            cursor = row.cursor,
            trail = row.trail,
            trailColors = row.trailColors,
            crt = row.crt,
            state = aes:serialize()
        }
        self:writeProfiles()
        self:toast("Saved profile to Slot " .. slot .. "!")
    end


    function RiceApp:applyProfile(slot)
        local p = self._profiles[slot]
        local aes = self.game.aesthetic
        if not (p and aes) then return end
        local id = "rice_profile_" .. slot
        game.mods:removeTheme(id)
        game.mods:addTheme({
            id = id,
            name = "PROFILE " .. slot,
            tip = "Saved Rice Studio profile.",
            palette = p.palette or {},
            chrome = p.chrome or {},
            wallpaper = p.wallpaper or {kind = "grid", base = "#0A2429"},
            cursor = p.cursor or "arrow",
            trail = p.trail or "sparkle",
            trailColors = p.trailColors or {"#E8C170", "#F4ECD8", "#9BE8C9"},
            crt = p.crt
        })
        if p.state then
            local st = {}
            for k, v in pairs(p.state) do st[k] = v end
            st.theme = id
            aes:set(st)
        else
            aes:set({theme = id})
        end
        self:toast("Loaded Profile Slot " .. slot .. "!")
    end

    function RiceApp:refreshMascots()
        local list = WallpaperOverlay.scan()
        for _, f in ipairs(Aesthetic.customMascots()) do
            list[#list + 1] = f
        end
        self._mascots = list
    end

    function RiceApp:open(window)
        RiceApp.super.open(self, window)
        self:refreshMascots()
    end

    function RiceApp:toast(msg)
        self._toast = msg
        self._toastT = 2.5
        if self.game.audio then self.game.audio:play("pop") end
    end

    function RiceApp:syncTrailColors()
        local aes = self.game.aesthetic
        local row = aes and aes:row()
        if not (aes and row) then return end
        local c = Theme.color
        local hexes = {
            toHex(c.amber), toHex(c.lineBright), toHex(c.glowGood),
            toHex(c.titlebar)
        }
        row.trailColors = hexes
        row.trailRGB = {
            {c.amber[1], c.amber[2], c.amber[3], 1},
            {c.lineBright[1], c.lineBright[2], c.lineBright[3], 1},
            {c.glowGood[1], c.glowGood[2], c.glowGood[3], 1},
            {c.titlebar[1], c.titlebar[2], c.titlebar[3], 1}
        }
        aes:apply()
        self:toast("Synced trail colors to active palette!")
    end

    function RiceApp:exportLua()
        local aes = self.game.aesthetic
        if not aes then return end
        local row = aes:row()
        local wp = row.wallpaper or {kind = "grid", base = "#0A2429"}
        local st = row.chrome and row.chrome.stripe
        local stripeStr = type(st) == "string" and string.format("%q", st) or
                              "nil"

        local palLines = {}
        for _, k in ipairs(PALETTE_KEYS) do
            local col = Theme.color[k]
            if col then
                palLines[#palLines + 1] =
                    string.format("    %s = %q,", k, toHex(col))
            end
        end

        local code = string.format([[game.mods:addTheme({
  id = "custom_rice",
  name = "CUSTOM RICE",
  tip = "Exported from Rice Studio.",
  palette = {
%s
  },
  chrome = {
    radius = %d, border = %d, gradDir = %q, buttons = %q, titleAlign = %q,
    stripe = %s, gloss = %s, bevel = %s, tray = %s,
  },
  wallpaper = %s,
  cursor = %q,
  trail = %q,
  trailColors = %s,
  crt = %s,
})]], table.concat(palLines, "\n"), row.chrome.radius or 0,
                                   row.chrome.border or 1,
                                   row.chrome.gradDir or "v",
                                   row.chrome.buttons or "glyph",
                                   row.chrome.titleAlign or "left", stripeStr,
                                   tostring(row.chrome.gloss == true),
                                   tostring(row.chrome.bevel == true),
                                   tostring(row.chrome.tray ~= false),
                                   serializeVal(wp, 1), row.cursor or "arrow",
                                   row.trail or "sparkle", serializeVal(
                                       row.trailColors or
                                           {"#E8C170", "#F4ECD8", "#9BE8C9"}, 1),
                                   tostring(row.crt or 0))
        if love.system and love.system.setClipboardText then
            love.system.setClipboardText(code)
            self:toast("Copied full Lua theme + chrome + palette to clipboard!")
        end
    end

    function RiceApp:applySliderValue(sl, norm)
        norm = max(0, min(1, norm))
        local val = sl.min + (sl.max - sl.min) * norm
        if sl.step then val = floor(val / sl.step + 0.5) * sl.step end
        local aes = self.game.aesthetic
        local row = aes and aes:row()
        if not (aes and row) then return end

        if sl.id == "crt" then
            row.crt = val > 0.01 and tonumber(string.format("%.2f", val)) or nil
        elseif sl.id == "radius" then
            row.chrome.radius = floor(val + 0.5)
            aes:apply()
        elseif sl.id == "border" then
            row.chrome.border = floor(val + 0.5)
            aes:apply()

        elseif sl.id == "mascotX" then
            aes:set({mascotX = val})
        elseif sl.id == "mascotY" then
            aes:set({mascotY = val})
        elseif sl.id == "mascotRot" then
            aes:set({mascotRot = val})
        elseif sl.id == "mascotSize" then
            aes:set({mascotSize = val})
        elseif sl.id == "palR" or sl.id == "palG" or sl.id == "palB" then
         local cur = Theme.color[self.palKey] or {1, 1, 1, 1}
         local nextCol = {cur[1], cur[2], cur[3], cur[4] or 1}
         if sl.id == "palR" then nextCol[1] = val
         elseif sl.id == "palG" then nextCol[2] = val
         elseif sl.id == "palB" then nextCol[3] = val end
         row.palette[self.palKey] = toHex(nextCol)
         if row.resolved then row.resolved[self.palKey] = nextCol end
         Theme.color[self.palKey] = nextCol
     end

    end
    function RiceApp:drawBody(x, y, w, h)
        local c = Theme.color
        local fonts = self.game.fonts
        local aes = self.game.aesthetic
        Theme.set(c.fieldDark)
        lg.rectangle("fill", x, y, w, h)
        if not aes then return end
        local n = 0
        local function addRect(rx, ry, rw, rh, kind, arg)
            n = n + 1
            local r = self._rects[n] or {}
            self._rects[n] = r
            r.x, r.y, r.w, r.h, r.kind, r.arg = rx, ry, rw, rh, kind, arg
        end
        local mx, my = self:localMouse()
        local inside = mx >= 0 and my >= 0 and mx <= w and my <= h
        local function hov(rx, ry, rw, rh)
            return inside and Rect.contains(rx, ry, rw, rh, mx, my)
        end
        local pad = 10
        local tabH = 26
        local tabs = {
            {id = "themes", label = "THEMES"},
            {id = "palette", label = "PALETTE"}, {id = "mix", label = "MIX"},
            {id = "mascot", label = "MASCOT"}, {id = "toys", label = "TOYS"},
            {id = "profiles", label = "SAVE"}
        }
        lg.setFont(fonts.small)
        local tx = x + pad
        local ty = y + pad
        for _, tb in ipairs(tabs) do
            local bw = fonts.small:getWidth(tb.label) + 12
            local active = self.tab == tb.id
            local hv = hov(tx, ty, bw, tabH)
            if hv then Cursor.hot() end
            Theme.set(active and c.fieldLight or (hv and c.field or c.fieldDark))
            lg.rectangle("fill", tx, ty, bw, tabH)
            Theme.set(active and c.amber or (hv and c.lineBright or c.line))
            lg.rectangle("line", tx + 0.5, ty + 0.5, bw - 1, tabH - 1)
            Theme.set(active and c.amber or (hv and c.cream or c.creamDim))
            lg.print(tb.label, tx + 6, ty + 6)
            addRect(tx, ty, bw, tabH, "tab", tb.id)
            tx = tx + bw + 4
        end
        local exLabel = "COPY LUA"
        local exW = fonts.small:getWidth(exLabel) + 12
        local exX = x + w - pad - exW
        local ehv = hov(exX, ty, exW, tabH)
        if ehv then Cursor.hot() end
        Theme.set(ehv and c.fieldLight or c.field)
        lg.rectangle("fill", exX, ty, exW, tabH)
        Theme.set(ehv and c.glowGood or c.lineBright)
        lg.rectangle("line", exX + 0.5, ty + 0.5, exW - 1, tabH - 1)
        Theme.set(ehv and c.glowGood or c.cream)
        lg.print(exLabel, exX + 6, ty + 6)
        addRect(exX, ty, exW, tabH, "export", nil)
        local bodyY = ty + tabH + 10
        local bodyH = h - (bodyY - y) - pad
        local sx, sy = lg.transformPoint(x + pad, bodyY)
        local sx2, sy2 = lg.transformPoint(x + w - pad, bodyY + bodyH)
        lg.push("all")
        lg.intersectScissor(sx, sy, sx2 - sx, sy2 - sy)
        local cy = bodyY - self.scroll
        local innerW = w - pad * 2
        local row = aes:row()
        local function section(title)
            Theme.set(c.amber)
            lg.print(title, x + pad, cy)
            Theme.set(c.line)
            lg.line(x + pad, cy + 16, x + w - pad, cy + 16)
            cy = cy + 24
        end
        local function slider(id, label, val, smin, smax, step, fmt)
            local sh = 24
            local labelW = 135
            local valStr = string.format(fmt or "%.2f", val)
            local valW = 58
            local trackX = x + pad + labelW
            local trackW = max(60, innerW - labelW - valW)
            local trackY = cy + 6
            local trackH = 12
            local norm = max(0, min(1, (val - smin) / max(0.0001, smax - smin)))
            local hv = hov(trackX - 4, cy, trackW + 8, sh) or
                           (self._dragSlider and self._dragSlider.id == id)
            if hv then Cursor.hot() end
            Theme.set(c.cream)
            lg.print(label, x + pad, cy + 4)
            Theme.set(c.field)
            lg.rectangle("fill", trackX, trackY, trackW, trackH)
            Theme.set(hv and c.lineBright or c.line)
            lg.rectangle("line", trackX + 0.5, trackY + 0.5, trackW - 1,
                         trackH - 1)
            Theme.set(hv and c.amber or c.amberDim)
            lg.rectangle("fill", trackX + 2, trackY + 2,
                         max(0, (trackW - 4) * norm), trackH - 4)
            local knobX = trackX + trackW * norm
            Theme.set(c.cream)
            lg.rectangle("fill", knobX - 3, trackY - 2, 6, trackH + 4)
            Theme.set(c.creamDim)
            lg.print(valStr, trackX + trackW + 8, cy + 4)
            addRect(trackX - 4, cy, trackW + 8, sh, "slider", {
                id = id,
                min = smin,
                max = smax,
                step = step,
                tx = trackX,
                tw = trackW
            })
            cy = cy + sh + 6
        end
        local function chipGrid(items, isSelectedFn, kind)
            local cx = x + pad
            local ch = 24
            for _, item in ipairs(items) do
                local label = type(item) == "table" and
                                  (item.nameId and
                                      self.game.strings:line(item.nameId) or
                                      item.label or item.name or item.id) or
                                  tostring(item)
                local val = type(item) == "table" and
                                (item.id or item.key or item.name) or item
                local cw = fonts.small:getWidth(label) + 18
                if cx + cw > x + w - pad and cx > x + pad then
                    cx = x + pad
                    cy = cy + ch + 6
                end
                local sel = isSelectedFn(val)
                local hv = hov(cx, cy, cw, ch)
                if hv then Cursor.hot() end
                Theme.set(sel and c.fieldLight or
                              (hv and c.field or c.fieldDark))
                lg.rectangle("fill", cx, cy, cw, ch)
                Theme.set(sel and c.amber or (hv and c.lineBright or c.line))
                lg.rectangle("line", cx + 0.5, cy + 0.5, cw - 1, ch - 1)
                Theme.set(sel and c.amber or (hv and c.cream or c.creamDim))
                lg.print(label, cx + 9, cy + 5)
                addRect(cx, cy, cw, ch, kind, val)
                cx = cx + cw + 6
            end
            cy = cy + ch + 14
        end
        if self.tab == "themes" then
            section("INSTALLED THEMES (" .. #Aesthetics.list .. ")")
            chipGrid(Aesthetics.list, function(id)
                return row.id == id
            end, "theme")
            section("DISPLAY & WINDOW CHROME")
            slider("crt", "CRT SHADER", row.crt or 0, 0, 1, 0.05, "%.2f")
            slider("radius", "CORNER RADIUS", row.chrome.radius or 0, 0, 16, 1,
                   "%d px")
            slider("border", "BORDER WIDTH", row.chrome.border or 1, 1, 6, 1,
                   "%d px")
            chipGrid({
                {id = "glyph", label = "BTN: GLYPH"},
                {id = "dots", label = "BTN: DOTS"},
                {id = "boxes", label = "BTN: BOXES"}
            }, function(v)
                return (row.chrome.buttons or "glyph") == v
            end, "buttons")
            chipGrid({
                {
                    id = "gradDir",
                    label = "GRADIENT: " ..
                        tostring(row.chrome.gradDir or "v"):upper()
                }, {
                    id = "titleAlign",
                    label = "TITLE: " ..
                        tostring(row.chrome.titleAlign or "left"):upper()
                },
                {
                    id = "gloss",
                    label = "GLOSS: " .. (row.chrome.gloss and "ON" or "OFF")
                },
                {
                    id = "bevel",
                    label = "BEVEL: " .. (row.chrome.bevel and "ON" or "OFF")
                },
                {
                    id = "tray",
                    label = "TRAY: " ..
                        (row.chrome.tray ~= false and "ON" or "OFF")
                }
            }, function(flag)
                if flag == "gloss" then
                    return row.chrome.gloss == true
                end
                if flag == "bevel" then
                    return row.chrome.bevel == true
                end
                if flag == "tray" then
                    return row.chrome.tray ~= false
                end
                return false
            end, "chromeFlag")
        elseif self.tab == "palette" then
            section("SELECT COLOR SLOT")
            chipGrid(PALETTE_KEYS, function(k)
                return self.palKey == k
            end, "palKey")
            local curCol = Theme.color[self.palKey] or {1, 1, 1, 1}
            section(
                "EDITING: " .. self.palKey:upper() .. " (" .. toHex(curCol) ..
                    ")")
            Theme.set(curCol)
            lg.rectangle("fill", x + pad, cy, innerW, 18)
            Theme.set(c.lineBright)
            lg.rectangle("line", x + pad + 0.5, cy + 0.5, innerW - 1, 17)
            cy = cy + 26
            slider("palR", "RED", curCol[1] or 0, 0, 1, 0.01, "%.2f")
            slider("palG", "GREEN", curCol[2] or 0, 0, 1, 0.01, "%.2f")
            slider("palB", "BLUE", curCol[3] or 0, 0, 1, 0.01, "%.2f")
        elseif self.tab == "mix" then
            section("WALLPAPER ENGINE (THEME-TINTED)")
            chipGrid(game.mods:listWallpapers(), function(k)
                return row.wallpaper and row.wallpaper.kind == k
            end, "wallpaper")
            section("TITLEBAR & TASKBAR STRIPE")
            local stripes = {"none"}
            for _, s in ipairs(game.mods:listStripes()) do
                stripes[#stripes + 1] = s
            end
            chipGrid(stripes,
                     function(s)
                return (row.chrome.stripe or "none") == s
            end, "stripe")
            local tbOn = (row.chrome.taskbarStripe ~= false)
            chipGrid({
                {
                    id = "taskbarStripe",
                    label = "TASKBAR STRIPE: " .. (tbOn and "ON" or "OFF")
                }
            }, function() return tbOn end, "taskbarStripe")

            section("CURSOR STYLE")
            chipGrid(Cursor.STYLES, function(cs)
                return row.cursor == cs
            end, "cursor")
            section("CURSOR TRAIL")
            chipGrid(game.mods:listTrails(),
                     function(tr) return row.trail == tr end, "trail")
            chipGrid({
                {id = "syncTrail", label = "SYNC TRAIL COLORS TO PALETTE"}
            }, function() return false end, "syncTrail")
        elseif self.tab == "mascot" then
            section("ACTIVE MASCOT")
            local mItems = {{id = Aesthetic.MASCOT_NONE, label = "NONE"}}
            for _, m in ipairs(self._mascots) do
                mItems[#mItems + 1] = {id = m.name, label = m.name}
            end
            chipGrid(mItems,
                     function(name) return aes:get("mascot") == name end,
                     "mascot")
            section("TRANSFORM SLIDERS")
            slider("mascotX", "POSITION X", aes:get("mascotX") or 1, 0, 1, 0.01,
                   "%.2f")
            slider("mascotY", "POSITION Y", aes:get("mascotY") or 1, 0, 1, 0.01,
                   "%.2f")
            slider("mascotRot", "ROTATION", aes:get("mascotRot") or 0, -180,
                   180, 1, "%d deg")
            slider("mascotSize", "SCALE", aes:get("mascotSize") or 1, 0.25, 2.5,
                   0.05, "%.2fx")
            chipGrid({
                {id = "flip", label = "FLIP X"},
                {
                    id = "blend",
                    label = "BLEND: " .. tostring(aes:get("blend")):upper()
                }, {id = "reset", label = "RESET TRANSFORM"}
            }, function() return false end, "preset")
        elseif self.tab == "toys" then
            section("DESKTOP TOYS & EFFECTS")
            chipGrid(game.mods:listToys(),
                     function(k) return aes:get(k) == true end, "toy")
        elseif self.tab == "profiles" then
            section("PERSISTENT RICE PROFILES (" .. PROFILE_FILE .. ")")
            for slot = 1, 4 do
                local p = self._profiles[slot]
                local title = p and p.name or ("SLOT " .. slot .. " (EMPTY)")
                Theme.set(c.cream)
                lg.print(title, x + pad, cy + 4)
                local bw = 54
                local autoX = x + w - pad - bw
                local loadX = autoX - bw - 5
                local saveX = loadX - bw - 5
                local isAuto = (self._profiles.autoload == slot)

                local shv = hov(saveX, cy, bw, 22)
                if shv then Cursor.hot() end
                Theme.set(shv and c.fieldLight or c.field)
                lg.rectangle("fill", saveX, cy, bw, 22)
                Theme.set(shv and c.amber or c.line)
                lg.rectangle("line", saveX + 0.5, cy + 0.5, bw - 1, 21)
                Theme.set(shv and c.amber or c.cream)
                lg.print("SAVE", saveX + 11, cy + 4)
                addRect(saveX, cy, bw, 22, "saveSlot", slot)

                local lhv = p and hov(loadX, cy, bw, 22)
                if lhv then Cursor.hot() end
                Theme.set(lhv and c.fieldLight or c.fieldDark)
                lg.rectangle("fill", loadX, cy, bw, 22)
                Theme.set(lhv and c.glowGood or c.line)
                lg.rectangle("line", loadX + 0.5, cy + 0.5, bw - 1, 21)
                Theme.set(p and (lhv and c.glowGood or c.cream) or c.creamDim)
                lg.print("LOAD", loadX + 11, cy + 4)
                local ahv = p and hov(autoX, cy, bw, 22)
                if ahv then Cursor.hot() end
                Theme.set(isAuto and c.fieldLight or
                              (ahv and c.field or c.fieldDark))
                lg.rectangle("fill", autoX, cy, bw, 22)
                Theme.set(isAuto and c.amber or (ahv and c.lineBright or c.line))
                lg.rectangle("line", autoX + 0.5, cy + 0.5, bw - 1, 21)
                Theme.set(isAuto and c.amber or (p and c.cream or c.creamDim))
                lg.print("AUTO", autoX + 11, cy + 4)
                if p then
                    addRect(autoX, cy, bw, 22, "autoSlot", slot)
                end

                if p then
                    addRect(loadX, cy, bw, 22, "loadSlot", slot)
                end
                cy = cy + 30
            end
        end
        lg.pop()
        self.contentH = (cy + self.scroll) - bodyY
        local maxScroll = max(0, self.contentH - bodyH)
        self.scroll = max(0, min(self.scroll, maxScroll))
        if self._toast and self._toastT > 0 then
            Theme.set(c.fieldLight)
            lg.rectangle("fill", x + pad, y + h - 30, innerW, 22)
            Theme.set(c.glowGood)
            lg.rectangle("line", x + pad + 0.5, y + h - 29.5, innerW - 1, 21)
            lg.print(self._toast, x + pad + 8, y + h - 25)
        end
        self._nRects = n
        for i = n + 1, #self._rects do self._rects[i].kind = nil end
    end
    function RiceApp:update(dt)
        if self._toastT > 0 then
            self._toastT = self._toastT - dt
            if self._toastT <= 0 then self._toast = nil end
        end
    end
    function RiceApp:mousepressed(lx, ly, b)
        if b ~= 1 then return end
        for i = 1, self._nRects do
            local r = self._rects[i]
            if r.kind and Rect.contains(r.x, r.y, r.w, r.h, lx, ly) then
                local aes = self.game.aesthetic
                local row = aes and aes:row()
                if r.kind == "slider" then
                    self._dragSlider = r.arg
                    self:applySliderValue(r.arg, (lx - r.arg.tx) / r.arg.tw)
                    return
                elseif r.kind == "autoSlot" then
                    self._profiles.autoload =
                        (self._profiles.autoload == r.arg) and nil or r.arg
                    self:writeProfiles()
                    self:toast(self._profiles.autoload and
                                   ("Autoload enabled for Slot " .. r.arg .. "!") or
                                   "Autoload disabled.")
                    return

                elseif r.kind == "tab" then
                    self.tab = r.arg
                    self.scroll = 0
                elseif r.kind == "export" then
                    self:exportLua()
                elseif r.kind == "palKey" then
                    self.palKey = r.arg
                elseif r.kind == "theme" and aes then
                    aes:set({theme = r.arg})
                elseif r.kind == "taskbarStripe" and row then
                    row.chrome.taskbarStripe =
                        (row.chrome.taskbarStripe == false)
                    aes:apply()

                elseif r.kind == "buttons" and row then
                    row.chrome.buttons = r.arg
                    aes:apply()
                elseif r.kind == "chromeFlag" and row then
                    if r.arg == "gradDir" then
                        row.chrome.gradDir =
                            (row.chrome.gradDir == "h") and "v" or "h"
                    elseif r.arg == "titleAlign" then
                        row.chrome.titleAlign =
                            (row.chrome.titleAlign == "center") and "left" or
                                "center"
                    elseif r.arg == "border" then
                        row.chrome.border = (row.chrome.border == 2) and 1 or 2
                    elseif r.arg == "gloss" then
                        row.chrome.gloss = not row.chrome.gloss
                    elseif r.arg == "bevel" then
                        row.chrome.bevel = not row.chrome.bevel
                    elseif r.arg == "tray" then
                        row.chrome.tray =
                            (row.chrome.tray == false) and true or false
                    end
                    aes:apply()
                elseif r.kind == "wallpaper" and row then
                    row.wallpaper = buildWallpaperForTheme(r.arg)
                elseif r.kind == "stripe" and row then
                    row.chrome.stripe = (r.arg ~= "none") and r.arg or nil
                    aes:apply()
                elseif r.kind == "cursor" and row then
                    row.cursor = r.arg
                    aes:apply()
                elseif r.kind == "trail" and row then
                    row.trail = r.arg
                    aes:apply()
                elseif r.kind == "syncTrail" then
                    self:syncTrailColors()
                    return
                elseif r.kind == "mascot" and aes then
                    aes:set({mascot = r.arg})
                elseif r.kind == "preset" and aes then
                    if r.arg == "flip" then
                        aes:set({flip = not aes:get("flip")})
                    elseif r.arg == "blend" then
                        aes:set({
                            blend = aes:get("blend") == "normal" and "overlay" or
                                "normal"
                        })
                    elseif r.arg == "reset" then
                        aes:resetPlacement()
                    end
                elseif r.kind == "toy" and aes then
                    aes:set({[r.arg] = not aes:get(r.arg)})
                elseif r.kind == "saveSlot" then
                    self:saveProfile(r.arg)
                    return
                elseif r.kind == "loadSlot" then
                    self:applyProfile(r.arg)
                    return
                end
                if self.game.audio then
                    self.game.audio:play("pop")
                end
                return
            end
        end
    end
    function RiceApp:mousemoved(lx, ly)
        if self._dragSlider then
            self:applySliderValue(self._dragSlider, (lx - self._dragSlider.tx) /
                                      self._dragSlider.tw)
        end
    end
    function RiceApp:mousereleased(lx, ly, b)
        if b == 1 then self._dragSlider = nil end
    end
    function RiceApp:wheelmoved(dx, dy)
        self.scroll = max(0, self.scroll - dy * 36)
    end
    game.mods:registerApp({
        id = "rice_studio",
        title = "RICE STUDIO",
        icon = "彩",
        unlock = {always = true}
    }, RiceApp)
    game.mods:addProcess({
        key = "ricer",
        name = "ricer.exe",
        ring = 2,
        apps = { "rice_studio" },
        present = { unlocked = "rice_studio" },
    })

    game.mods:onReady(function()
     local data = loadProfileFile()
     local slot = data.autoload
     if slot and data[slot] then
         applyProfileData(slot, data[slot])
     end
 end)
end
return M
