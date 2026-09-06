--------------------------------------------------------------------------------
-- Copy
--
-- One window, two jobs: the whole chat log, and a single URL somebody clicked.
-- They are the same window because they are the same problem - text the game
-- will not let you select - and one implementation means one set of bugs.
--
-- WoW has no clipboard API. The only way to get text out of the game is to put
-- it in an EditBox and let the operating system take it, so this is an EditBox
-- with the log poured into it, already selected, waiting for Ctrl+C.
--
-- The button that opens it is a visible, labelled control in the tab strip
-- rather than a hidden click target on the chat frame. A secondary action you
-- cannot see is a secondary action nobody uses.
--
-- Cost: the window is built the first time it is opened and reused afterwards.
-- Reading the log is a loop over the frame's own message buffer, which happens
-- when you press the button and never otherwise.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Copy = {}
PC.Copy = Copy

local Frames = PC.Frames

local PeaversCommons = _G.PeaversCommons
local Theme = PeaversCommons.Theme

local gsub = string.gsub

--------------------------------------------------------------------------------
-- Reading a chat frame
--------------------------------------------------------------------------------

--- Take the client's own escape sequences back out, keeping what they were
--- standing in for. An item link becomes its name, a colour run becomes the text
--- it was colouring, a texture becomes nothing at all.
---
--- A doubled || is a literal pipe somebody wanted to show, not the start of an
--- escape, and it has to be got out of the way before anything else runs. Leave
--- it in and the second pipe of a || pairs up with whatever follows: a message
--- containing ||h closes a hyperlink that was never opened, and the |H...|h(.-)|h
--- pattern then eats a span of text that had nothing to do with a link. That is
--- not hypothetical - it is what mangled the output of /pchat channels, whose
--- whole job is to print escape sequences literally.
local PIPE = ""

local function Strip(text)
    text = gsub(text, "||", PIPE)
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    text = gsub(text, "|H.-|h(.-)|h", "%1")
    text = gsub(text, "|T.-|t", "")
    text = gsub(text, "|A.-|a", "")
    text = gsub(text, PIPE, "|")
    return text
end

--- Every message currently in a chat window's buffer, oldest first.
function Copy:ReadFrame(frame)
    if not frame or type(frame.GetNumMessages) ~= "function" then
        return nil
    end

    local strip = PC.Config.copyStripColors ~= false
    local count = frame:GetNumMessages() or 0
    local lines = {}

    for i = 1, count do
        local text = frame:GetMessageInfo(i)
        if type(text) == "string" and text ~= "" then
            lines[#lines + 1] = strip and Strip(text) or text
        end
    end

    return table.concat(lines, "\n"), count
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function FlatButton(parent, label, width, onClick)
    local C = Theme.Colors

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 20)

    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(C.bgNested[1], C.bgNested[2], C.bgNested[3], 1)

    local edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        edge[#edge + 1] = Theme.Hairline(button, side, { color = C.border })
    end

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    text:SetTextColor(C.textSec[1], C.textSec[2], C.textSec[3])

    button:SetScript("OnEnter", function()
        text:SetTextColor(C.text[1], C.text[2], C.text[3])
        for i = 1, #edge do
            edge[i]:SetColorTexture(C.borderHover[1], C.borderHover[2], C.borderHover[3], 1)
        end
    end)
    button:SetScript("OnLeave", function()
        text:SetTextColor(C.textSec[1], C.textSec[2], C.textSec[3])
        for i = 1, #edge do
            edge[i]:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        end
    end)
    button:SetScript("OnClick", onClick)

    button.text = text
    return button
end

Copy.FlatButton = FlatButton

local function BuildWindow()
    if Copy.window then return Copy.window end

    local C = Theme.Colors

    local window = CreateFrame("Frame", "PeaversChatCopyFrame", UIParent)
    window:SetSize(720, 460)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()

    local bg = window:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(C.bgBase[1], C.bgBase[2], C.bgBase[3], 0.98)

    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        Theme.Hairline(window, side, { color = C.border })
    end

    -- The eyebrow motif from the rest of the suite: a small uppercase indigo
    -- label over a hairline rule.
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    window.title = title

    local rule = window:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 14, -30)
    rule:SetPoint("TOPRIGHT", -14, -30)
    rule:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)

    local close = FlatButton(window, "CLOSE", 64, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -8)

    -- Scroll area. Deliberately no scrollbar widget: Blizzard's is a piece of
    -- art that would be the only bevelled thing on screen, and a wheel handler
    -- is both flatter and less code.
    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", 14, -42)
    scroll:SetPoint("BOTTOMRIGHT", -14, 44)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local target = self:GetVerticalScroll() - (delta * 40)
        if target < 0 then target = 0 end
        if target > range then target = range end
        self:SetVerticalScroll(target)
    end)

    -- The EditBox is the scroll child directly rather than sitting inside a
    -- sizing frame. A multiline EditBox of fixed width grows its own height to
    -- fit its text, which is exactly the number the ScrollFrame needs to work
    -- out how far it can scroll - and it is a number nothing here has to
    -- estimate from line counts and guessed wrapping.
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    edit:SetTextColor(C.text[1], C.text[2], C.text[3])
    edit:SetScript("OnEscapePressed", function() window:Hide() end)

    scroll:SetScrollChild(edit)

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 16)
    hint:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
    hint:SetText("Ctrl+C copies the selection. Esc closes.")

    local selectAll = FlatButton(window, "SELECT ALL", 90, function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    selectAll:SetPoint("BOTTOMRIGHT", -14, 12)

    -- Without this the edit box keeps keyboard focus after the window is
    -- closed, and the next thing typed goes into a frame nobody can see.
    window:SetScript("OnHide", function() edit:ClearFocus() end)

    window.scroll = scroll
    window.edit = edit

    Copy.window = window
    return window
end

--------------------------------------------------------------------------------
-- Opening it
--------------------------------------------------------------------------------

--- @param title string Shown as the eyebrow label.
--- @param text string What to put in the box.
function Copy:Show(title, text)
    local window = BuildWindow()

    window.title:SetText((title or "COPY"):upper())

    -- Shown before the text goes in: the ScrollFrame has no width until it has
    -- been laid out once, and an EditBox of width nil wraps every line to
    -- nothing.
    window:Show()

    -- Taken from the window rather than the scroll frame: the window has an
    -- explicit width, while an anchored child reports zero until the layout
    -- pass has run, and an EditBox of width zero wraps every line to nothing.
    window.edit:SetWidth(window:GetWidth() - 28)
    window.edit:SetText(text or "")

    window.scroll:SetVerticalScroll(0)
    window.edit:SetFocus()
    window.edit:HighlightText()
end

--- Copy the log of one chat window, or of whichever tab is currently on top.
function Copy:ShowChat(frame)
    frame = frame or Frames:Selected()

    local text, count = self:ReadFrame(frame)
    if not text then
        PeaversCommons.Utils.Print(PC, "This chat window will not give up its history on this build.")
        return
    end

    if text == "" then
        PeaversCommons.Utils.Print(PC, "Nothing in that window to copy yet.")
        return
    end

    local name = (frame and frame.name) or "Chat"
    self:Show(name .. "  -  " .. count .. " lines", text)
end

--------------------------------------------------------------------------------
-- The button on each chat frame
--
-- A 14px copy mark in the top-right corner of the chat text, costing no layout
-- at all: it sits over the message area rather than beside it, in the corner
-- that holds the oldest visible line and is almost always empty.
--
-- The mark is drawn rather than shipped - two offset squares, each an outer
-- rectangle in the icon colour with an inner one punched out in the window's
-- own background. That is what reads as an outline at this size, where the
-- rounded border art the rest of the suite uses reads as a blob, and it means
-- no new file in the package and a glyph that recolours with the theme.
--
-- On visibility there is a real tension. An icon that appears only on hover is
-- a click target nobody can see, which is the one interface rule this suite
-- holds to. So the default is neither: the mark sits at a quarter opacity, out
-- of the way but plainly there, and comes up to full when the pointer is over
-- the window. "Only on hover" is available for anybody who wants it, and is
-- the one setting here that does hide a control.
--
-- Hover is read from the chat frame's own OnEnter, and re-asserted from the
-- button's, because moving the pointer onto a child fires the parent's OnLeave.
--------------------------------------------------------------------------------

local ICON_SIZE = 14

local function CopyGlyph(button)
    local square = 9
    local parts = {}

    for index = 1, 2 do
        -- The front square draws in OVERLAY so it covers the back one where
        -- they overlap; the punched-out inner sits a sublevel above its own
        -- outer.
        local layer = (index == 1) and "ARTWORK" or "OVERLAY"
        local outer = button:CreateTexture(nil, layer, nil, 0)
        local inner = button:CreateTexture(nil, layer, nil, 1)

        outer:SetSize(square, square)
        inner:SetSize(square - 2, square - 2)

        if index == 1 then
            outer:SetPoint("BOTTOMLEFT")
        else
            outer:SetPoint("TOPRIGHT")
        end
        inner:SetPoint("CENTER", outer, "CENTER")

        parts[#parts + 1] = { outer = outer, inner = inner }
    end

    return parts
end

local function PaintGlyph(button, bright)
    local C = Theme.Colors
    local cfg = PC.Config
    local ink = bright and C.text or C.textSec
    local bg = cfg.bgColor or { r = 0.086, g = 0.086, b = 0.086 }

    for _, part in ipairs(button.glyph) do
        part.outer:SetColorTexture(ink[1], ink[2], ink[3], 1)
        part.inner:SetColorTexture(bg.r, bg.g, bg.b, 1)
    end
end

--- Alpha for the current setting and hover state. Kept in one place because
--- three scripts and a settings change all need to agree on it.
local function ApplyVisibility(frame)
    local button = frame.peaversCopyButton
    if not button then return end

    local cfg = PC.Config
    local shown = cfg.enabled and cfg.copyButton
    button:SetShown(shown and true or false)
    if not shown then return end

    local hovered = frame.__pcHovered and true or false
    local mode = cfg.copyButtonVisibility or "dim"

    if mode == "always" then
        button:SetAlpha(hovered and 1 or 0.85)
    elseif mode == "hover" then
        button:SetAlpha(hovered and 1 or 0)
    else
        button:SetAlpha(hovered and 1 or 0.25)
    end

    PaintGlyph(button, hovered)
end

local function SetHovered(frame, hovered)
    frame.__pcHovered = hovered or nil
    ApplyVisibility(frame)
end

local function HookHover(frame)
    if frame.__pcHoverHooked then return end
    if type(frame.HookScript) ~= "function" then return end

    frame.__pcHoverHooked = true
    frame:HookScript("OnEnter", function(self) SetHovered(self, true) end)
    frame:HookScript("OnLeave", function(self) SetHovered(self, false) end)
end

local function BuildButton(frame)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button.glyph = CopyGlyph(button)

    button:SetScript("OnClick", function() Copy:ShowChat(frame) end)

    -- The mark carries no label, so it has to say what it is on hover.
    button:SetScript("OnEnter", function(self)
        SetHovered(frame, true)
        local tooltip = _G.GameTooltip
        if not tooltip then return end
        tooltip:SetOwner(self, "ANCHOR_LEFT")
        tooltip:ClearLines()
        tooltip:AddLine("Copy this chat window")
        tooltip:AddLine("Everything in the buffer, ready for Ctrl+C.", 0.58, 0.58, 0.58, true)
        tooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        SetHovered(frame, false)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    frame.peaversCopyButton = button
    return button
end

local function Apply(frame)
    local cfg = PC.Config

    if not frame.peaversCopyButton then
        if not cfg.enabled or not cfg.copyButton then return end
        BuildButton(frame)
    end

    HookHover(frame)

    local button = frame.peaversCopyButton
    button:ClearAllPoints()
    -- Tucked inside the window's own right and top insets, so it moves with
    -- the padding rather than sitting on the border at one setting and over the
    -- text at another.
    local pad = PC.Skin.Pad()
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(pad.right + 2), -(pad.top + 2))

    ApplyVisibility(frame)
end

local function Restore(frame)
    if frame.peaversCopyButton then frame.peaversCopyButton:Hide() end
end

function Copy:Initialize()
    Frames:RegisterHandler("copy", Apply, Restore)
end

return Copy
