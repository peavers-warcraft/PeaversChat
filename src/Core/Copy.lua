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
-- Anchored above the frame's top-right corner, which is the tab strip: the one
-- band of empty space around a chat window that never has text in it.
--------------------------------------------------------------------------------

local function Apply(frame)
    local cfg = PC.Config

    if not frame.peaversCopyButton then
        if not cfg.enabled or not cfg.copyButton then return end

        local button = FlatButton(frame, "COPY", 48, function()
            Copy:ShowChat(frame)
        end)
        button:SetHeight(18)
        button.chatFrame = frame
        frame.peaversCopyButton = button
    end

    -- Inside the tab strip when there is one, which is where the window's
    -- background now reaches; above the frame when there is not, because the
    -- alternative is sitting on top of the first line of chat.
    local host = PC.Skin.StripHost(frame)
    local strip = host and PC.Skin.StripHeight(frame) or 0
    local pad = cfg.padding or 0

    local button = frame.peaversCopyButton
    button:ClearAllPoints()
    if strip > 0 then
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, strip - 3)

        -- The strip's background is a texture on the dock, and this button is a
        -- child of the chat frame, so nothing about the parentage says which
        -- draws on top. Said explicitly here, in the dock's own strata, because
        -- assuming it is what made the tabs disappear once already.
        if host.GetFrameStrata then
            button:SetFrameStrata(host:GetFrameStrata())
            button:SetFrameLevel((host:GetFrameLevel() or 1) + 5)
        end
    else
        button:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", pad, pad + 3)
    end
    button:SetShown(cfg.enabled and cfg.copyButton and true or false)
end

local function Restore(frame)
    if frame.peaversCopyButton then frame.peaversCopyButton:Hide() end
end

function Copy:Initialize()
    Frames:RegisterHandler("copy", Apply, Restore)
end

return Copy
