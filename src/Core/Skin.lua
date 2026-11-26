--------------------------------------------------------------------------------
-- Skin
--
-- Turns a chat window into the flat dark box the rest of the Peavers suite is
-- drawn in: a single translucent field with a faint 1px hairline and nothing
-- else. No gradients, no bevel, no gold.
--
-- Three decisions here are worth explaining, because each looks like the harder
-- option until you try the easy one.
--
-- 1. The box is drawn with textures created directly on the frame they belong
--    to, in the BACKGROUND draw layer, rather than with a backdrop frame behind
--    it. A chat window is dragged, docked, resized and reparented by Blizzard's
--    own code; a region on the frame follows all of that for free and sits
--    behind the message text by definition. The band above the window that the
--    tabs sit in is the same idea applied to the tabs' own parent - see the
--    note on the strip below, and the paragraph there about what happens when
--    you try to solve that one with frame strata instead.
--
-- 2. Blizzard's own chrome is hidden rather than recoloured, and hidden by
--    shadowing each texture's Show with its Hide. Chat frames are restyled by
--    the client on half a dozen occasions - docking, undocking, the interface
--    options, some loading screens - and a texture that cannot be shown again
--    survives all of them without this addon running anything to check.
--
-- 3. The window's own backdrop colour is zeroed through the API rather than
--    torn out. Removing a backdrop that Blizzard's code still expects to find
--    is how a chat addon breaks on a patch; setting it transparent is
--    reversible, cannot error, and reaches the same pixel.
--
-- The hairline is measured in real screen pixels via PixelUtil. A "1" in frame
-- units is not one pixel once the UI scale is anything but 1, and a border that
-- lands between pixels is the difference between a crisp box and a grey smear.
--
-- Nothing in this file runs per frame or on a timer.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Skin = {}
PC.Skin = Skin

local Frames = PC.Frames

--------------------------------------------------------------------------------
-- Pixel-exact hairlines
--------------------------------------------------------------------------------

local function Hairline(frame)
    local pixelUtil = _G.PixelUtil
    if pixelUtil and pixelUtil.GetNearestPixelSize and frame.GetEffectiveScale then
        local ok, size = pcall(pixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
        if ok and size and size > 0 then return size end
    end
    return 1
end

Skin.Hairline = Hairline

--------------------------------------------------------------------------------
-- Padding
--------------------------------------------------------------------------------

--- The four insets, as one table, so the painters can pass them around without
--- four parameters becoming eight. Built fresh each call: this runs on a
--- settings change, not on a message.
--- @return table pad { left, right, top, bottom }
function Skin.Pad()
    local cfg = PC.Config
    return {
        left = cfg.paddingLeft or 6,
        right = cfg.paddingRight or 6,
        top = cfg.paddingTop or 6,
        bottom = cfg.paddingBottom or 6,
    }
end

local NO_PAD = { left = 0, right = 0, top = 0, bottom = 0 }
Skin.NO_PAD = NO_PAD

--------------------------------------------------------------------------------
-- Doing nothing well
--
-- The client asks this addon to re-apply itself far more often than anything
-- has changed (options panel, dock and undock, loading screens); measured, that
-- cost 260 client calls a time to arrive back where it started. So every module
-- records a signature of what it last applied and compares first. Safe because
-- nothing the client resets is left to a refresh: hidden textures cannot come
-- back, tab alpha is pinned, the edit box anchor is re-asserted from the
-- client's own call site.
--------------------------------------------------------------------------------

--- True when `signature` differs from what was last recorded, and records it.
--- @param owner table Anything we may store state on - a frame, a tab, a button.
--- @param slot string Field to keep the previous signature in.
--- @param signature string
function Skin.Changed(owner, slot, signature)
    if owner[slot] == signature then return false end
    owner[slot] = signature
    return true
end

--------------------------------------------------------------------------------
-- Hiding Blizzard's art
--
-- Shared with Tabs and EditBox, which have far more of it to take down.
--------------------------------------------------------------------------------

--- Hide a texture in a way the client cannot undo, remembering enough to put it
--- back if the addon is switched off.
function Skin.Kill(tex)
    if not tex or tex.__pcOwned then return end
    if tex.__pcKilled then return end

    tex.__pcKilled = true
    tex.__pcAlpha = tex.GetAlpha and tex:GetAlpha() or 1
    tex.__pcWasShown = tex.IsShown and tex:IsShown() or false

    if tex.SetAlpha then tex:SetAlpha(0) end
    tex:Hide()
    -- Shadows the widget method with an instance field; setting it back to nil
    -- restores the original, so this is fully reversible.
    tex.Show = tex.Hide
end

function Skin.Revive(tex)
    if not tex or not tex.__pcKilled then return end

    tex.Show = nil
    tex.__pcKilled = nil
    if tex.SetAlpha then tex:SetAlpha(tex.__pcAlpha or 1) end
    if tex.__pcWasShown then tex:Show() end
end

local Kill, Revive = Skin.Kill, Skin.Revive

--- Take down every background and border texture a frame owns. Deliberately
--- leaves ARTWORK and OVERLAY alone: chrome lives underneath the content, and
--- anything drawn above it is content somebody wants to see.
---
--- Swept once per frame. A killed texture cannot be shown again - its Show is
--- its Hide - so there is nothing for a second sweep to find, and sweeping is
--- not free: it is two client calls per region to ask what layer it is in, on
--- every frame, every time the client asks us to re-apply. ReviveChrome clears
--- the mark, so switching off and on again sweeps properly.
function Skin.KillChrome(frame)
    if not frame or not frame.GetRegions then return end
    if frame.__pcChromeSwept then return end
    frame.__pcChromeSwept = true

    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "Texture"
            and not region.__pcOwned then
            local layer = region:GetDrawLayer()
            if layer == "BACKGROUND" or layer == "BORDER" then
                Kill(region)
            end
        end
    end
end

--- Put back what KillChrome took down.
function Skin.ReviveChrome(frame)
    if not frame or not frame.GetRegions then return end
    frame.__pcChromeSwept = nil

    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        Revive(regions[i])
    end
end

--------------------------------------------------------------------------------
-- The box
--
-- Five textures: one fill and four edges, drawn straight onto the frame they
-- belong to. Built once and afterwards only recoloured and repositioned, so a
-- settings change allocates nothing.
--
-- Used for the edit box, which has nothing overlapping it and so needs no frame
-- of its own. The chat window uses the panel below instead; see the note there
-- for why the two are not the same thing.
--------------------------------------------------------------------------------

--- @param frame table Anything that can own textures.
--- @return table|nil box
function Skin:EnsureBox(frame)
    if frame.peaversBox then return frame.peaversBox end
    if type(frame.CreateTexture) ~= "function" then return nil end

    local box = {}

    box.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    box.top = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    box.bottom = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    box.left = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    box.right = frame:CreateTexture(nil, "BACKGROUND", nil, -7)

    for _, tex in pairs(box) do
        -- KillChrome sweeps BACKGROUND textures; this is how it knows to leave
        -- ours alone.
        tex.__pcOwned = true
    end

    frame.peaversBox = box
    return box
end

--- The fill behind the window and the tab strip.
---
--- Painted with the collection's bundled bar texture - Peavers Flat - rather
--- than a plain colour, so the chat box is the same surface the unit frames and
--- every Peavers bar are drawn with rather than a rectangle that merely happens
--- to be the same colour. The texture is tinted, so bgColor still decides the
--- colour and bgAlpha still decides how much of the world shows through.
---
--- Falls back to a colour fill where there is no texture to use or the file will
--- not load: a chat window with no background at all is a worse answer than a
--- plain one.
local function FillTexture()
    local cfg = PC.Config
    if cfg.barTexture and cfg.barTexture ~= "" then return cfg.barTexture end
    local Theme = _G.PeaversCommons and _G.PeaversCommons.Theme
    return Theme and Theme.DefaultBarTexture or nil
end

local function Fill(texture, bgColor, bgAlpha)
    local path = FillTexture()
    if path then
        texture:SetTexture(path)
        if texture:GetTexture() then
            texture:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgAlpha)
            return
        end
    end
    texture:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgAlpha)
end

--- Colour and place a box. `pad` pushes it out beyond the frame's own rect, so
--- the message text gets some air rather than sitting against the border.
---
--- `opts` (all optional):
---   flushTop  the box stops at the frame's top edge instead of growing upwards
---             with the padding. The tab strip owns everything above that edge:
---             padding is room around the text, and above the text there is a
---             tab row, drawn on the dock and so underneath the tabs. The box is
---             drawn on the chat frame and is not, so it has no business there.
---   skipTop   no top edge; the sides run to the very top and meet whatever is
---             drawn above.
---   seamTop   the top row of the rect is somebody else's line - the window's
---             bottom edge, when the edit box is attached under it. Nothing of
---             ours is drawn on that row unless topColor asks for it.
---   topColor  the top edge in this colour, fully opaque.
---
--- The sides stop short of the top and bottom edges rather than crossing them.
--- At full opacity that makes no difference; with a translucent border the
--- crossing pixel is drawn twice and every corner shows a brighter dot.
local NO_OPTS = {}

function Skin:PaintBox(frame, pad, bgColor, bgAlpha, borderColor, showBg, showBorder, opts)
    local box = frame.peaversBox
    if not box then return end

    opts = opts or NO_OPTS
    local px = Hairline(frame)
    pad = pad or NO_PAD

    local left, right = -pad.left, pad.right
    local bottom = -pad.bottom
    local top = opts.flushTop and 0 or pad.top
    local seam = opts.seamTop
    local showTop = showBorder and not opts.skipTop and (not seam or opts.topColor ~= nil)
    local sideTop = (showTop or seam) and (top - px) or top
    local alpha = PC.Config.borderAlpha or 1

    box.bg:ClearAllPoints()
    box.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", left, seam and (top - px) or top)
    box.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    Fill(box.bg, bgColor, bgAlpha)
    box.bg:SetShown(showBg and true or false)

    -- The four edges sit on the padded rect, not on the frame, so the border is
    -- the outline of what you can see rather than of where the text starts.
    box.top:ClearAllPoints()
    box.top:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    box.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, top)
    box.top:SetHeight(px)

    box.bottom:ClearAllPoints()
    box.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom)
    box.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    box.bottom:SetHeight(px)

    box.left:ClearAllPoints()
    box.left:SetPoint("TOPLEFT", frame, "TOPLEFT", left, sideTop)
    box.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom + px)
    box.left:SetWidth(px)

    box.right:ClearAllPoints()
    box.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, sideTop)
    box.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom + px)
    box.right:SetWidth(px)

    for _, name in ipairs({ "bottom", "left", "right" }) do
        box[name]:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, alpha)
        box[name]:SetShown(showBorder and true or false)
    end

    local topColor = opts.topColor
    if topColor then
        box.top:SetColorTexture(topColor.r, topColor.g, topColor.b, 1)
    else
        box.top:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, alpha)
    end
    box.top:SetShown(showTop and true or false)
end

function Skin:HideBox(frame)
    local box = frame and frame.peaversBox
    if not box then return end
    for _, tex in pairs(box) do tex:Hide() end
end

--------------------------------------------------------------------------------
-- The tab strip
--
-- The band above the chat window that the tabs sit in, given the same
-- background so the tabs read as part of the window rather than balanced on
-- top of it.
--
-- Never a frame ordered against the tabs by strata: a BACKGROUND-strata child
-- once drew over them, because where the client puts the dock in that ordering
-- is not knowable. Drawn instead as textures on an ancestor of the tabs, whose
-- regions are beneath its child frames by definition, anchored to the chat
-- frame. Docked windows share one dock and one rect, so they share one strip.
--------------------------------------------------------------------------------

--- Is `ancestor` somewhere above `widget` in the parent chain?
local function IsAncestorOf(ancestor, widget)
    local depth = 0
    local node = widget

    while node and depth < 12 do
        if node == ancestor then return true end
        if type(node.GetParent) ~= "function" then return false end
        node = node:GetParent()
        depth = depth + 1
    end

    return false
end

function Skin.StripHost(frame)
    local tab = PC.Frames:TabFor(frame)
    if not tab or type(tab.GetParent) ~= "function" then return nil end

    local host = tab:GetParent()
    if not host or host == _G.UIParent then return nil end

    -- The dock, not the scroll frame child the client parents docked tabs into:
    -- a scroll frame clips its child, which cut the strip off halfway across
    -- the tab row. The dock is still an ancestor, and clips nothing.
    local dock = _G.GeneralDockManager
    if dock and dock ~= _G.UIParent and IsAncestorOf(dock, tab) then
        return dock
    end

    return host
end

--- Breathing room above the tab text, in pixels.
local TEXT_MARGIN = 5

--- How far above the chat frame the tab strip reaches.
---
--- Measured off the tab rather than assumed, because where Blizzard puts the
--- dock is Blizzard's business and it has moved before: the honest question is
--- "how far above this window is the top of its tab", and GetTop answers it
--- whatever the anchoring underneath. The fallbacks exist because GetTop is nil
--- until the frame has been laid out once, which at login it has not; the next
--- refresh gets the real number. The sanity bounds catch the case where the two
--- frames turn out to be in different coordinate spaces, where subtracting one
--- from the other is meaningless rather than merely wrong.
--- Forget a frame's cached measurement, for when something we did has changed
--- it - restyling the tab text, most of all.
function Skin.InvalidateMeasure(frame)
    frame.__pcMeasureGen = nil
end

local function MeasureStrip(frame)
    local tab = PC.Frames:TabFor(frame)
    if not tab then return 0 end

    local frameTop = frame:GetTop()

    -- Measure to the top of the word, not the top of the tab. Blizzard's tab
    -- frame carries a good deal of dead space above its text, and a strip drawn
    -- to cover the frame covers that dead space too - which is exactly what
    -- reads as too much padding above the tabs. TEXT_MARGIN is the breathing
    -- room the word gets, and it is the only number here that is a taste
    -- judgement rather than a measurement.
    local fontString = PC.Tabs and PC.Tabs.FontString and PC.Tabs.FontString(tab)
    local textTop = fontString and fontString.GetTop and fontString:GetTop()
    if textTop and frameTop then
        local reach = textTop - frameTop + TEXT_MARGIN
        if reach >= 8 and reach <= 80 then return reach end
    end

    -- The tab frame, for a build where the font string cannot be found.
    local tabTop = tab:GetTop()
    if tabTop and frameTop then
        local reach = tabTop - frameTop
        if reach >= 8 and reach <= 80 then return reach end
    end

    local height = tab.GetHeight and tab:GetHeight()
    if height and height >= 8 and height <= 80 then return height end

    return 22
end

--- Cached for the life of one sweep. Three modules want this number and each of
--- them used to go and read it off the frames again: measured, that was eleven
--- geometry reads per window on every refresh, and geometry reads are the sort
--- the client resolves a layout to answer.
local function StripHeight(frame)
    -- The two answers that need no measuring are given before the cache, so a
    -- setting change takes effect the moment it is made rather than waiting for
    -- the next sweep to invalidate something.
    local cfg = PC.Config
    if not cfg.tabsInside then return 0 end
    if cfg.tabStripHeight and cfg.tabStripHeight > 0 then return cfg.tabStripHeight end

    local generation = PC.Frames.generation

    if frame.__pcMeasureGen == generation and frame.__pcStripHeight then
        return frame.__pcStripHeight
    end

    local height = MeasureStrip(frame)
    frame.__pcMeasureGen = generation
    frame.__pcStripHeight = height
    return height
end

Skin.StripHeight = StripHeight

function Skin:EnsureStrip(host)
    if host.peaversStrip then return host.peaversStrip end
    if type(host.CreateTexture) ~= "function" then return nil end

    local strip = {}
    strip.bg = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    strip.top = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    strip.left = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    strip.right = host:CreateTexture(nil, "BACKGROUND", nil, -7)

    for _, tex in pairs(strip) do tex.__pcOwned = true end

    host.peaversStrip = strip
    return strip
end

--- No bottom edge: the strip and the window below it are meant to read as one
--- box, and a hairline across the middle of it would say otherwise.
function Skin:PaintStrip(host, frame, pad, height, bgColor, bgAlpha, borderColor, showBg, showBorder)
    local strip = host.peaversStrip
    if not strip then return end

    local px = Hairline(frame)
    pad = pad or NO_PAD
    local alpha = PC.Config.borderAlpha or 1

    local left, right = -pad.left, pad.right

    -- Bottom flush with the frame's top edge, where the box now stops, so the
    -- two meet exactly and neither reaches into the other's territory. The top
    -- padding is spent upwards, above the tab text, which is the only direction
    -- there is room to spend it in.
    local top = height + pad.top

    strip.bg:ClearAllPoints()
    strip.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    strip.bg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", right, 0)
    Fill(strip.bg, bgColor, bgAlpha)
    strip.bg:SetShown(showBg and true or false)

    strip.top:ClearAllPoints()
    strip.top:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    strip.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, top)
    strip.top:SetHeight(px)

    -- Below the top edge, not across it; see PaintBox on translucent corners.
    strip.left:ClearAllPoints()
    strip.left:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top - px)
    strip.left:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", left, 0)
    strip.left:SetWidth(px)

    strip.right:ClearAllPoints()
    strip.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, top - px)
    strip.right:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", right, 0)
    strip.right:SetWidth(px)

    for _, name in ipairs({ "top", "left", "right" }) do
        strip[name]:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, alpha)
        strip[name]:SetShown(showBorder and true or false)
    end
end

function Skin:HideStrip(frame)
    local host = Skin.StripHost(frame)
    local strip = host and host.peaversStrip
    if not strip then return end
    for _, tex in pairs(strip) do tex:Hide() end
end

--- Draw the window box and the strip above it as one shape.
---
--- Public because Tabs has to call it: the strip is measured from the tab's
--- text, and Tabs is what changes that text's size and casing. Skin's handler
--- runs first, so the measurement it takes at login is of Blizzard's font.
--- Tabs calls this again once the tab is its own, and the number is right.
--- What the painted result depends on. Repainting is idempotent, so doing it
--- twice is harmless - but it is not free, and it happens far more often than
--- anything actually changes: the client fires UPDATE_CHAT_WINDOWS on every
--- options visit, dock, undock and some loading screens, and every one of those
--- repainted five textures per window for no reason. Comparing a signature
--- turns those into a string compare.
local function PaintSignature(frame, pad, strip)
    local cfg = PC.Config
    local bg, border = cfg.bgColor, cfg.borderColor

    return table.concat({
        strip, pad.left, pad.right, pad.top, pad.bottom,
        bg.r, bg.g, bg.b, cfg.bgAlpha, tostring(FillTexture()),
        border.r, border.g, border.b, cfg.borderAlpha or 1,
        cfg.background and 1 or 0, cfg.border and 1 or 0,
        Skin.BoxedTabs() and 1 or 0,
        Hairline(frame),
    }, ":")
end

--- Tabs drawn as boxes of their own rather than as words on the strip. With
--- the strip behind them the window box keeps its top edge, which becomes the
--- line under the tab row.
function Skin.BoxedTabs()
    local cfg = PC.Config
    return cfg.styleTabs and cfg.tabStyle == "boxed" or false
end

function Skin:RefreshStrip(frame, force)
    local cfg = PC.Config
    if not cfg.enabled then return end

    -- The strip is only drawn when there is somewhere safe to draw it. Without
    -- a host the window keeps its own top edge and looks like it did before the
    -- tabs were brought inside: a worse look, but a working one.
    local host = Skin.StripHost(frame)
    local strip = host and StripHeight(frame) or 0

    local pad = Skin.Pad()

    local signature = PaintSignature(frame, pad, strip)
    if not force and frame.__pcPainted == signature then return end
    frame.__pcPainted = signature

    Skin:EnsureBox(frame)
    local inside = strip > 0
    Skin:PaintBox(frame, pad, cfg.bgColor, cfg.bgAlpha, cfg.borderColor,
        cfg.background, cfg.border,
        { flushTop = inside, skipTop = inside and not Skin.BoxedTabs() })

    if host then
        Skin:EnsureStrip(host)
        Skin:PaintStrip(host, frame, pad, strip, cfg.bgColor, cfg.bgAlpha,
            cfg.borderColor, cfg.background and strip > 0, cfg.border and strip > 0)
    end
end

--------------------------------------------------------------------------------
-- Reaching the screen edge
--
-- Blizzard gives every chat window a clamping inset, which is why dragging one
-- to the left of the screen stops short against nothing you can see.
--
-- Never hooked: a hook on SetClampRectInsets, a protected function, cannot be
-- taken off again and was a suspect when chat broke in Mythic+. Never latched
-- either: Edit Mode re-asserts a margin without a reload, and a once-a-session
-- clear left the window stuck short of the edge. Each refresh reads the insets
-- back and clears them only if a margin has come back. Skipped in combat; the
-- client's own insets are remembered so switching off gives them back.
--------------------------------------------------------------------------------

-- The insets the client currently has on this frame, or nil if it will not say.
local function CurrentClamp(frame)
    if type(frame.GetClampRectInsets) ~= "function" then return nil end
    local ok, left, right, top, bottom = pcall(frame.GetClampRectInsets, frame)
    if not ok or left == nil then return nil end
    return left, right, top, bottom
end

Skin.CurrentClamp = CurrentClamp

local function ClearClamp(frame)
    if not PC.Config.enabled or not PC.Config.edgeToEdge then return end
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then return end
    if type(frame.SetClampRectInsets) ~= "function" then return end

    -- Clamping off entirely, not just clamped by nothing. The client puts its
    -- own insets back (FloatingChatFrame_UpdateBackgroundAnchors, on leaving
    -- Edit Mode among others), and the moment it does, a window against the
    -- edge is outside its allowed rect and gets moved; clearing afterwards
    -- cannot undo the jump. ElvUI does the same. Only under edgeToEdge, since
    -- an unclamped window can be dragged off screen (Position re-asserts the
    -- saved spot). Latched: nothing in the chat code turns it back on.
    if frame.__pcClamped == nil and type(frame.SetClampedToScreen) == "function" then
        frame.__pcClamped = true
        pcall(frame.SetClampedToScreen, frame, false)
    end

    local left, right, top, bottom = CurrentClamp(frame)

    -- The client's own margin, recorded once and never overwritten, or the
    -- "original" would become our own zeroes.
    if frame.__pcClamp == nil then
        frame.__pcClamp = left and { left, right, top, bottom } or false
    end

    if left == nil then
        -- The client will not report them; fall back to clearing once, which is
        -- what the previous version did in every case.
        if frame.__pcClampCleared then return end
        frame.__pcClampCleared = true
        pcall(frame.SetClampRectInsets, frame, 0, 0, 0, 0)
        return
    end

    if left == 0 and right == 0 and top == 0 and bottom == 0 then
        frame.__pcClampCleared = true
        return
    end

    frame.__pcClampCleared = true
    pcall(frame.SetClampRectInsets, frame, 0, 0, 0, 0)
end

-- Exposed for Position, which has to clear the margin before it places a window
-- against the screen edge - otherwise the clamp shoves it straight back.
Skin.ClearClampFor = ClearClamp

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

--- The face to draw with: the chosen one, or the one the widget arrived with.
--- Empty means Blizzard's, which is correct in every locale. The locale check is
--- the reason this is not just a string swap: none of the Latin faces carry CJK
--- glyphs, and applying one to a Chinese client renders empty boxes.
function Skin.Face(chosen, original)
    if chosen == nil or chosen == "" then return original end
    local ConfigManager = _G.PeaversCommons and _G.PeaversCommons.ConfigManager
    if ConfigManager and ConfigManager.IsFontCompatibleWithLocale
        and not ConfigManager.IsFontCompatibleWithLocale(chosen) then
        return original
    end
    return chosen
end

--- SetFont with a way back. A LibSharedMedia path for an addon that has since
--- been uninstalled either throws or returns false depending on the build, and
--- the false case leaves a blank line rather than an error - so both are read
--- and the original face is put back at the requested size.
function Skin.SetFace(widget, face, size, flags, original)
    local ok, set = pcall(widget.SetFont, widget, face, size, flags)
    if (not ok or set == false) and face ~= original then
        pcall(widget.SetFont, widget, original, size, flags)
    end
end

local function ApplyFont(frame)
    local cfg = PC.Config

    if not frame.__pcFont then
        local file, size, flags = frame:GetFont()
        frame.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 14, flags or "" }
    end

    local flags = cfg.fontOutline
    if flags == "NONE" or flags == nil then flags = "" end

    local original = frame.__pcFont[1]
    Skin.SetFace(frame, Skin.Face(cfg.fontFace, original), cfg.fontSize, flags, original)

    if frame.SetShadowColor then
        frame:SetShadowColor(0, 0, 0, cfg.shadow and 1 or 0)
        frame:SetShadowOffset(1, -1)
    end
end

local function RestoreFont(frame)
    if not frame.__pcFont then return end
    pcall(frame.SetFont, frame, frame.__pcFont[1], frame.__pcFont[2], frame.__pcFont[3])
    frame.__pcFont = nil
end

--------------------------------------------------------------------------------
-- The handler
--------------------------------------------------------------------------------

local function Apply(frame)
    local cfg = PC.Config
    if not cfg.enabled then return end

    -- The strip keeps its own signature: it depends on measurements as well as
    -- settings, so it has to be asked separately.
    Skin:RefreshStrip(frame)
    ClearClamp(frame)

    local signature = table.concat({
        cfg.fontSize, cfg.fontFace or "", cfg.fontOutline or "", cfg.shadow and 1 or 0,
        cfg.fading and 1 or 0, cfg.timeVisible, cfg.maxLines or 0,
        cfg.edgeToEdge and 1 or 0,
    }, ":")
    if not Skin.Changed(frame, "__pcSkinState", signature) then return end

    Skin.KillChrome(frame)

    -- Zeroing rather than removing: see the header note. Wrapped because a frame
    -- without a backdrop refuses both calls on some builds.
    pcall(function()
        if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
    end)

    ApplyFont(frame)

    if frame.SetFading then frame:SetFading(cfg.fading and true or false) end
    if frame.SetTimeVisible then frame:SetTimeVisible(cfg.timeVisible or 120) end

    -- Guarded on the value: SetMaxLines discards the buffer, so calling it every
    -- refresh would wipe the history whenever a slider moved. 0 means never call
    -- it at all - the one thing here that touches where messages are kept, so it
    -- has to be eliminable.
    if frame.SetMaxLines and cfg.maxLines and cfg.maxLines > 0
        and frame.__pcMaxLines ~= cfg.maxLines then
        -- Remembered, so switching the addon off really does put it back.
        if frame.__pcOrigMaxLines == nil and frame.GetMaxLines then
            local ok, lines = pcall(frame.GetMaxLines, frame)
            frame.__pcOrigMaxLines = (ok and lines) or false
        end

        frame.__pcMaxLines = cfg.maxLines
        pcall(frame.SetMaxLines, frame, cfg.maxLines)
    end
end

local function Restore(frame)
    -- Forget what was applied, so switching back on re-applies it all.
    frame.__pcSkinState = nil
    frame.__pcPainted = nil

    -- Hand the scrollback size back too. It empties the window, which is a
    -- shame, but leaving it changed would mean the addon was still doing
    -- something after being told to stop.
    if frame.__pcOrigMaxLines and frame.SetMaxLines then
        pcall(frame.SetMaxLines, frame, frame.__pcOrigMaxLines)
        frame.__pcMaxLines = nil
        frame.__pcOrigMaxLines = nil
    end

    Skin:HideBox(frame)
    Skin:HideStrip(frame)
    RestoreFont(frame)

    local clamp = frame.__pcClamp
    if clamp and frame.SetClampRectInsets
        and not (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) then
        pcall(frame.SetClampRectInsets, frame, clamp[1], clamp[2], clamp[3], clamp[4])
        frame.__pcClampCleared = nil
        frame.__pcClamp = nil
    end

    -- And clamping itself back on, if it was on before we switched it off.
    -- Handing back the insets without this leaves a window that can still be
    -- dragged off the screen and lost, which is not a state the client ever
    -- puts a chat window in.
    if frame.__pcClamped ~= nil then
        if type(frame.SetClampedToScreen) == "function" then
            pcall(frame.SetClampedToScreen, frame, frame.__pcClamped and true or false)
        end
        frame.__pcClamped = nil
    end
    Skin.ReviveChrome(frame)

    if frame.SetFading then frame:SetFading(true) end
end

function Skin:Initialize()
    Frames:RegisterHandler("skin", Apply, Restore)
end

return Skin
