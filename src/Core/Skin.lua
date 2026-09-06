--------------------------------------------------------------------------------
-- Skin
--
-- Turns a chat window into the flat black box the rest of the Peavers suite is
-- drawn in: a single #161616 field with a 1px hairline border and nothing else.
-- No gradients, no bevel, no gold.
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
function Skin.KillChrome(frame)
    if not frame or not frame.GetRegions then return end

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

--- Colour and place a box. `pad` pushes it out beyond the frame's own rect, so
--- the message text gets some air rather than sitting against the border.
---
--- `skipTop` says the tab strip is drawn above this and the two are meant to
--- read as one box. It drops the top edge, and - the part that matters - stops
--- the box growing upwards with the padding.
---
--- That upward growth is what put the background over the bottom half of the
--- tabs: padding is room around the *text*, and above the text there is no text
--- to give room to, there is a tab row. Everything above the frame's top edge
--- belongs to the strip, which is drawn on the dock and therefore underneath
--- the tabs. The box is drawn on the chat frame and is not, so it has no
--- business up there at any padding.
function Skin:PaintBox(frame, pad, bgColor, bgAlpha, borderColor, showBg, showBorder, skipTop)
    local box = frame.peaversBox
    if not box then return end

    local px = Hairline(frame)
    pad = pad or NO_PAD

    local left, right = -pad.left, pad.right
    local bottom = -pad.bottom
    local topPad = skipTop and 0 or pad.top

    box.bg:ClearAllPoints()
    box.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", left, topPad)
    box.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    box.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgAlpha)
    box.bg:SetShown(showBg and true or false)

    -- The four edges sit on the padded rect, not on the frame, so the border is
    -- the outline of what you can see rather than of where the text starts.
    box.top:ClearAllPoints()
    box.top:SetPoint("TOPLEFT", frame, "TOPLEFT", left, topPad)
    box.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, topPad)
    box.top:SetHeight(px)

    box.bottom:ClearAllPoints()
    box.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom)
    box.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    box.bottom:SetHeight(px)

    box.left:ClearAllPoints()
    box.left:SetPoint("TOPLEFT", frame, "TOPLEFT", left, topPad)
    box.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom)
    box.left:SetWidth(px)

    box.right:ClearAllPoints()
    box.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, topPad)
    box.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    box.right:SetWidth(px)

    for _, name in ipairs({ "top", "bottom", "left", "right" }) do
        box[name]:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        box[name]:SetShown(showBorder and not (skipTop and name == "top") and true or false)
    end
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
-- This was a child frame in the BACKGROUND strata once. It drew over the tabs,
-- and the reason is worth writing down: strata only orders frames against other
-- frames, and where the client puts the tab dock in that ordering is not
-- something an addon can know. Guessing produced invisible tabs.
--
-- So the strip is not ordered against the tabs at all. It is drawn as textures
-- on the tabs' own parent, and a frame's regions are always beneath its child
-- frames - not usually, not depending on level, but by definition. The textures
-- are anchored to the chat frame rather than to the frame that owns them, so
-- they line up with the window while inheriting the dock's z-order and the
-- dock's visibility.
--
-- Docked windows share one dock, so they share one strip, keyed off the host.
-- They also share a rect, so whichever of them anchored it last is right for
-- all of them.
--------------------------------------------------------------------------------

--- The frame the tabs are children of: the dock when docked, the chat frame
--- itself when not. Returns nil when it is neither - UIParent, say - because
--- putting our textures there would leak them into a frame that outlives chat.
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

    -- Prefer the dock itself over whatever inner frame the tabs happen to hang
    -- from. The client parents docked tabs into a scroll frame's child so the
    -- row can overflow, and a scroll frame clips its child - so textures drawn
    -- there are cut off at the scroll rect while the tabs, being frames, carry
    -- on past it. That is a background that stops halfway across the tab row.
    --
    -- The dock is an ancestor of the tabs either way, so hosting the strip
    -- there keeps the whole point of hosting it on an ancestor: a frame's
    -- regions are beneath its child frames by definition. It simply is not
    -- inside anything that clips.
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
local function StripHeight(frame)
    local cfg = PC.Config
    if not cfg.tabsInside then return 0 end

    local tab = PC.Frames:TabFor(frame)
    if not tab then return 0 end

    if cfg.tabStripHeight and cfg.tabStripHeight > 0 then return cfg.tabStripHeight end

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

    local left, right = -pad.left, pad.right

    -- Bottom flush with the frame's top edge, where the box now stops, so the
    -- two meet exactly and neither reaches into the other's territory. The top
    -- padding is spent upwards, above the tab text, which is the only direction
    -- there is room to spend it in.
    local top = height + pad.top

    strip.bg:ClearAllPoints()
    strip.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    strip.bg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", right, 0)
    strip.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgAlpha)
    strip.bg:SetShown(showBg and true or false)

    strip.top:ClearAllPoints()
    strip.top:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    strip.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, top)
    strip.top:SetHeight(px)

    strip.left:ClearAllPoints()
    strip.left:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    strip.left:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", left, 0)
    strip.left:SetWidth(px)

    strip.right:ClearAllPoints()
    strip.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", right, top)
    strip.right:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", right, 0)
    strip.right:SetWidth(px)

    for _, name in ipairs({ "top", "left", "right" }) do
        strip[name]:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
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
function Skin:RefreshStrip(frame)
    local cfg = PC.Config
    if not cfg.enabled then return end

    -- The strip is only drawn when there is somewhere safe to draw it. Without
    -- a host the window keeps its own top edge and looks like it did before the
    -- tabs were brought inside: a worse look, but a working one.
    local host = Skin.StripHost(frame)
    local strip = host and StripHeight(frame) or 0

    local pad = Skin.Pad()

    Skin:EnsureBox(frame)
    Skin:PaintBox(frame, pad, cfg.bgColor, cfg.bgAlpha, cfg.borderColor,
        cfg.background, cfg.border, strip > 0)

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
-- to the left of the screen stops short against nothing you can see. Zeroing
-- the insets lets the window sit against the edge, which is where a lot of
-- people want it.
--
-- Two things this has to respect. SetClampRectInsets is protected in combat, so
-- the attempt is skipped there rather than throwing - the client reasserts the
-- insets on its own schedule and the hook below catches the next one. And the
-- hook calls the widget method captured before the hook was installed, so
-- re-zeroing from inside the hook does not re-enter it.
--------------------------------------------------------------------------------

local rawSetClamp = nil

local function ClearClamp(frame)
    if not PC.Config.enabled or not PC.Config.edgeToEdge then return end
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then return end

    local setter = rawSetClamp or frame.SetClampRectInsets
    if type(setter) ~= "function" then return end
    pcall(setter, frame, 0, 0, 0, 0)
end

local function HookClamp(frame)
    if frame.__pcClampHooked then return end
    if type(frame.SetClampRectInsets) ~= "function" then return end

    frame.__pcClampHooked = true
    rawSetClamp = rawSetClamp or frame.SetClampRectInsets

    -- Remember what the client wanted, so switching the addon off can give it
    -- back. Wrapped because the getter is not on every build.
    local ok, left, right, top, bottom = pcall(frame.GetClampRectInsets, frame)
    if ok and left then frame.__pcClamp = { left, right, top, bottom } end

    hooksecurefunc(frame, "SetClampRectInsets", function(self)
        ClearClamp(self)
    end)
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function ApplyFont(frame)
    local cfg = PC.Config

    if not frame.__pcFont then
        local file, size, flags = frame:GetFont()
        frame.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 14, flags or "" }
    end

    local flags = cfg.fontOutline
    if flags == "NONE" or flags == nil then flags = "" end

    -- SetFont is refused for a font file the client cannot resolve; keeping the
    -- original around means a bad path costs the font change, not the frame.
    pcall(frame.SetFont, frame, frame.__pcFont[1], cfg.fontSize, flags)

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

    Skin.KillChrome(frame)

    -- Zeroing rather than removing: see the header note. Wrapped because a frame
    -- without a backdrop refuses both calls on some builds.
    pcall(function()
        if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
    end)

    Skin:RefreshStrip(frame)

    HookClamp(frame)
    ClearClamp(frame)

    ApplyFont(frame)

    if frame.SetFading then frame:SetFading(cfg.fading and true or false) end
    if frame.SetTimeVisible then frame:SetTimeVisible(cfg.timeVisible or 120) end

    -- Guarded on the value rather than called every time: SetMaxLines discards
    -- the buffer, so calling it on every refresh would quietly wipe the history
    -- every time somebody moved a slider.
    if frame.SetMaxLines and cfg.maxLines and frame.__pcMaxLines ~= cfg.maxLines then
        frame.__pcMaxLines = cfg.maxLines
        pcall(frame.SetMaxLines, frame, cfg.maxLines)
    end
end

local function Restore(frame)
    Skin:HideBox(frame)
    Skin:HideStrip(frame)
    RestoreFont(frame)

    local clamp = frame.__pcClamp
    if clamp and rawSetClamp and not (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) then
        pcall(rawSetClamp, frame, clamp[1], clamp[2], clamp[3], clamp[4])
    end
    Skin.ReviveChrome(frame)

    if frame.SetFading then frame:SetFading(true) end
end

function Skin:Initialize()
    Frames:RegisterHandler("skin", Apply, Restore)
end

return Skin
