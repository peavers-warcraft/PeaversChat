--------------------------------------------------------------------------------
-- EditBox
--
-- The line you type into, given the same flat box as the window above it and
-- moved out from under the text.
--
-- Blizzard's edit box is a nine-slice strip drawn *inside* the chat frame's
-- bottom edge, which means the last line of chat is behind whatever you are
-- currently writing. Moving it outside the frame is most of what makes a chat
-- window feel like somebody designed it, and it costs one anchor.
--
-- The border is the one piece of live information here: it takes the colour of
-- the channel you are about to speak in, so /g and /w are different colours
-- before you have read the header. That is Blizzard's own ChatTypeInfo palette,
-- read through the hook the client already calls when the channel changes, so
-- it stays correct for custom channels and for languages nobody has thought of.
--
-- Nothing in this file runs per frame or on a timer.
--------------------------------------------------------------------------------

local addonName, PC = ...

local EditBox = {}
PC.EditBox = EditBox

local Frames = PC.Frames
local Skin = PC.Skin

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

local function EditBoxFor(frame)
    if frame.editBox then return frame.editBox end
    local name = frame:GetName()
    return name and _G[name .. "EditBox"] or nil
end

local function HeaderFor(editBox)
    if editBox.header then return editBox.header end
    local name = editBox:GetName()
    return name and _G[name .. "Header"] or nil
end

--------------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------------

--- The channel colour Blizzard would have used, or nil when it has no opinion.
local function ChannelColor(editBox)
    local info = _G.ChatTypeInfo
    if not info then return nil end

    local chatType = editBox:GetAttribute("chatType")
    if not chatType then return nil end

    -- Numbered channels carry their colour under CHANNEL1..CHANNEL10 rather
    -- than under CHANNEL itself.
    if chatType == "CHANNEL" then
        local target = editBox:GetAttribute("channelTarget")
        if target then
            local numbered = info["CHANNEL" .. target]
            if numbered then return numbered end
        end
    end

    return info[chatType]
end

--- Repaint one edit box's box. Split out from Apply because the channel changes
--- far more often than the settings do, and this is the cheap half.
function EditBox:Repaint(editBox)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.styleEditBox then return end
    if not editBox or not editBox.peaversBox then return end

    local border = cfg.borderColor
    if cfg.editBoxChannelColor then
        local color = ChannelColor(editBox)
        if color and color.r then border = color end
    end

    Skin:PaintBox(editBox, Skin.NO_PAD, cfg.bgColor, cfg.bgAlpha, border, cfg.background, cfg.border)
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

local function Position(editBox)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.styleEditBox then return end
    if cfg.editBoxPosition == "blizzard" then return end

    -- ChatEdit_OnLoad sets chatFrame, but an edit box that has never been
    -- activated may not have been through it yet; it is always its own frame's
    -- child either way.
    local frame = editBox.chatFrame or editBox:GetParent()
    if not frame or frame == _G.UIParent then return end

    -- Left and right come from the window, so the two boxes line up down their
    -- edges. The gap is measured off whichever side it sits on.
    local pad = Skin.Pad()
    local gap = (cfg.editBoxPosition == "top" and pad.top or pad.bottom) + 5

    editBox:ClearAllPoints()
    if cfg.editBoxPosition == "top" then
        editBox:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -pad.left, gap)
        editBox:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", pad.right, gap)
    else
        editBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -pad.left, -gap)
        editBox:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", pad.right, -gap)
    end
    editBox:SetHeight(cfg.editBoxHeight or 22)
end

--------------------------------------------------------------------------------
-- The handler
--------------------------------------------------------------------------------

local function Apply(frame)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.styleEditBox then return end

    local editBox = EditBoxFor(frame)
    if not editBox then return end

    local pad = Skin.Pad()
    local signature = table.concat({
        cfg.fontSize, cfg.editBoxPosition or "bottom", cfg.editBoxHeight or 22,
        pad.left, pad.right, pad.top, pad.bottom,
        cfg.altArrowKeys and 1 or 0, cfg.background and 1 or 0, cfg.border and 1 or 0,
        cfg.bgAlpha, cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b,
        cfg.editBoxChannelColor and 1 or 0,
    }, ":")
    if not Skin.Changed(editBox, "__pcApplied", signature) then return end

    -- The strip, its focus variant, and the little language tab are all chrome.
    -- Everything on this frame in BACKGROUND or BORDER is Blizzard's art.
    Skin.KillChrome(editBox)

    pcall(function()
        if editBox.SetBackdropColor then editBox:SetBackdropColor(0, 0, 0, 0) end
        if editBox.SetBackdropBorderColor then editBox:SetBackdropBorderColor(0, 0, 0, 0) end
    end)

    Skin:EnsureBox(editBox)
    EditBox:Repaint(editBox)

    if not editBox.__pcFont then
        local file, size, flags = editBox:GetFont()
        editBox.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 14, flags or "" }
    end
    pcall(editBox.SetFont, editBox, editBox.__pcFont[1], cfg.fontSize, "")

    local header = HeaderFor(editBox)
    if header then
        if not header.__pcFont then
            local file, size, flags = header:GetFont()
            header.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 14, flags or "" }
        end
        pcall(header.SetFont, header, header.__pcFont[1], cfg.fontSize, "")
    end

    -- Blizzard reserves the arrow keys for chat history unless Alt is held.
    -- Off means they move the cursor, which is what every other text field on
    -- the machine does and what people expect the first time they mistype.
    if editBox.SetAltArrowKeyMode then
        editBox:SetAltArrowKeyMode(cfg.altArrowKeys and true or false)
    end

    Position(editBox)
end

local function Restore(frame)
    local editBox = EditBoxFor(frame)
    if not editBox then return end

    editBox.__pcApplied = nil
    Skin:HideBox(editBox)
    Skin.ReviveChrome(editBox)

    if editBox.__pcFont then
        pcall(editBox.SetFont, editBox, editBox.__pcFont[1], editBox.__pcFont[2], editBox.__pcFont[3])
        editBox.__pcFont = nil
    end

    local header = HeaderFor(editBox)
    if header and header.__pcFont then
        pcall(header.SetFont, header, header.__pcFont[1], header.__pcFont[2], header.__pcFont[3])
        header.__pcFont = nil
    end

    if editBox.SetAltArrowKeyMode then editBox:SetAltArrowKeyMode(true) end
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

local hooksInstalled = false

--- Kept out of Initialize: see the note on Frames:InstallHooks.
function EditBox:InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- The channel changed, so the header and the border colour did too. This is
    -- the client's own call site, which is why custom channels work without a
    -- list of them here.
    if type(_G.ChatEdit_UpdateHeader) == "function" then
        hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
            if editBox then EditBox:Repaint(editBox) end
        end)
    end

    -- Opening the edit box is where Blizzard re-anchors it, so it is also where
    -- our anchor has to be re-asserted.
    if type(_G.ChatEdit_ActivateChat) == "function" then
        hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
            if editBox then Position(editBox) end
        end)
    end
end

function EditBox:Initialize()
    Frames:RegisterHandler("editbox", Apply, Restore)
end

return EditBox
