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
-- 1. The box is drawn with textures created directly on the chat frame, in the
--    BACKGROUND draw layer, rather than with a backdrop frame behind it. A chat
--    window is dragged, docked, resized and reparented by Blizzard's own code;
--    a separate frame would have to chase all of that, while a region on the
--    frame moves with it for free and sits behind the message text by
--    definition.
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
-- Five textures: one fill and four edges. Built once per frame and afterwards
-- only recoloured and repositioned, so a settings change allocates nothing.
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
function Skin:PaintBox(frame, pad, bgColor, bgAlpha, borderColor, showBg, showBorder)
    local box = frame.peaversBox
    if not box then return end

    local px = Hairline(frame)
    pad = pad or 0

    box.bg:ClearAllPoints()
    box.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    box.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    box.bg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgAlpha)
    box.bg:SetShown(showBg and true or false)

    -- The four edges sit on the padded rect, not on the frame, so the border is
    -- the outline of what you can see rather than of where the text starts.
    box.top:ClearAllPoints()
    box.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    box.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", pad, pad)
    box.top:SetHeight(px)

    box.bottom:ClearAllPoints()
    box.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -pad, -pad)
    box.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    box.bottom:SetHeight(px)

    box.left:ClearAllPoints()
    box.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    box.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -pad, -pad)
    box.left:SetWidth(px)

    box.right:ClearAllPoints()
    box.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", pad, pad)
    box.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    box.right:SetWidth(px)

    for _, name in ipairs({ "top", "bottom", "left", "right" }) do
        box[name]:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        box[name]:SetShown(showBorder and true or false)
    end
end

function Skin:HideBox(frame)
    local box = frame and frame.peaversBox
    if not box then return end
    for _, tex in pairs(box) do tex:Hide() end
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

    Skin:EnsureBox(frame)
    Skin:PaintBox(frame, cfg.padding, cfg.bgColor, cfg.bgAlpha, cfg.borderColor,
        cfg.background, cfg.border)

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
    RestoreFont(frame)
    Skin.ReviveChrome(frame)

    if frame.SetFading then frame:SetFading(true) end
end

function Skin:Initialize()
    Frames:RegisterHandler("skin", Apply, Restore)
end

return Skin
