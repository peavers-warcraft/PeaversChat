--------------------------------------------------------------------------------
-- Buttons
--
-- Everything Blizzard hangs around the outside of a chat window, made optional.
--
-- The default chat frame is ringed with icons - a menu, a group-finder toast, a
-- voice channel, a microphone, a headset, two scroll arrows and a jump-to-bottom
-- - and between them they are most of the reason the default chat window looks
-- like the default chat window. Every one of them has a keybind, a slash command
-- or a menu behind it, so they all start hidden here except the one that does
-- something you cannot do another way: jump to the newest message.
--
-- Hiding is done with an OnShow hook rather than by shadowing Show, because a
-- button has to be able to come back. The client shows these on its own schedule
-- - the scroll arrows on mouse-over, the voice icons when you join a channel -
-- so "hidden" has to mean "hide it again whenever it appears", and that is one
-- event handler per button that fires only when the client was going to show it
-- anyway.
--
-- Whether a button was on screen when it was first hidden is remembered, so
-- turning it back on restores what the client had rather than conjuring a voice
-- icon for a channel you are not in.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Buttons = {}
PC.Buttons = Buttons

local Frames = PC.Frames
local Skin = PC.Skin

--------------------------------------------------------------------------------
-- Hiding
--------------------------------------------------------------------------------

local function SetHidden(widget, hidden)
    if type(widget) ~= "table" or type(widget.Hide) ~= "function" then return end

    if not widget.__pcOnShowHooked then
        widget.__pcOnShowHooked = true
        widget:HookScript("OnShow", function(self)
            if self.__pcHidden then self:Hide() end
        end)
    end

    if hidden then
        if widget.__pcWasShown == nil then
            widget.__pcWasShown = widget:IsShown() and true or false
        end
        widget.__pcHidden = true
        widget:Hide()
    else
        widget.__pcHidden = nil
        -- Only put back what was there. The client owns when a scroll arrow or
        -- a microphone is appropriate; we only ever owned whether it was
        -- allowed to be.
        if widget.__pcWasShown then widget:Show() end
        widget.__pcWasShown = nil
    end
end

Buttons.SetHidden = SetHidden

local function Resolve(name)
    return _G[name]
end

--------------------------------------------------------------------------------
-- The buttons that live outside any one chat frame
--------------------------------------------------------------------------------

local GLOBAL_GROUPS = {
    showMenuButton = { "ChatFrameMenuButton" },
    showSocialButton = { "QuickJoinToastButton" },
    showVoiceButtons = {
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    },
}

local function ApplyGlobals()
    local cfg = PC.Config

    for key, names in pairs(GLOBAL_GROUPS) do
        local hidden = cfg.enabled and not cfg[key]
        for i = 1, #names do
            SetHidden(Resolve(names[i]), hidden)
        end
    end

    -- Blizzard_CombatLog's quick-filter bar: a gold strip that sits on top of
    -- the combat log tab and belongs to a different decade.
    SetHidden(Resolve("CombatLogQuickButtonFrame_Custom"),
        cfg.enabled and not cfg.showCombatLogBar)
end

Buttons.ApplyGlobals = ApplyGlobals

--------------------------------------------------------------------------------
-- The buttons that belong to one chat frame
--------------------------------------------------------------------------------

--- Blizzard has moved the scroll affordances twice: the old three-button strip
--- named off the frame, and the newer ScrollBar / ScrollToBottomButton fields.
--- Both are looked for, and whichever exists is what gets managed.
local function ScrollParts(frame)
    local name = frame:GetName()
    local scroll, bottom = {}, {}

    if name then
        local buttonFrame = _G[name .. "ButtonFrame"]
        if buttonFrame then
            scroll[#scroll + 1] = _G[name .. "ButtonFrameUpButton"] or buttonFrame.UpButton
            scroll[#scroll + 1] = _G[name .. "ButtonFrameDownButton"] or buttonFrame.DownButton
            bottom[#bottom + 1] = _G[name .. "ButtonFrameBottomButton"] or buttonFrame.BottomButton
            scroll[#scroll + 1] = _G[name .. "ButtonFrameMinimizeButton"] or buttonFrame.MinimizeButton
        end
    end

    if frame.ScrollBar then scroll[#scroll + 1] = frame.ScrollBar end
    if frame.ScrollToBottomButton then bottom[#bottom + 1] = frame.ScrollToBottomButton end

    return scroll, bottom
end

local function ButtonFrameFor(frame)
    local name = frame:GetName()
    return name and _G[name .. "ButtonFrame"] or nil
end

local function Apply(frame)
    local cfg = PC.Config

    local scroll, bottom = ScrollParts(frame)

    for i = 1, #scroll do
        SetHidden(scroll[i], cfg.enabled and not cfg.showScrollButtons)
    end
    for i = 1, #bottom do
        SetHidden(bottom[i], cfg.enabled and not cfg.showBottomButton)
    end

    -- With nothing left inside it, the container is just a gold-edged rectangle.
    local buttonFrame = ButtonFrameFor(frame)
    if buttonFrame then
        Skin.KillChrome(buttonFrame)
        SetHidden(buttonFrame,
            cfg.enabled and not cfg.showScrollButtons and not cfg.showBottomButton)
    end
end

local function Restore(frame)
    local scroll, bottom = ScrollParts(frame)
    for i = 1, #scroll do SetHidden(scroll[i], false) end
    for i = 1, #bottom do SetHidden(bottom[i], false) end

    local buttonFrame = ButtonFrameFor(frame)
    if buttonFrame then
        SetHidden(buttonFrame, false)
        Skin.ReviveChrome(buttonFrame)
    end
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function Buttons:Initialize()
    Frames:RegisterHandler("buttons", Apply, Restore)
    ApplyGlobals()

    -- The combat log's button bar arrives with Blizzard_CombatLog, which is
    -- load-on-demand. EventUtil is used rather than an ADDON_LOADED handler
    -- because PeaversCommons.Events:Init clears those out from under us.
    if _G.EventUtil and _G.EventUtil.ContinueOnAddOnLoaded then
        _G.EventUtil.ContinueOnAddOnLoaded("Blizzard_CombatLog", function()
            ApplyGlobals()
        end)
    end
end

function Buttons:Refresh()
    ApplyGlobals()
end

return Buttons
