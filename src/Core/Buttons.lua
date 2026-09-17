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
        -- Already hidden and already ours: nothing to say. Being asked to
        -- re-apply is common; hiding something twice is only a client call.
        if widget.__pcHidden and not widget:IsShown() then return end
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

--- Names that do not exist on a given client resolve to nil and are skipped by
--- SetHidden without a word. That is deliberate rather than lucky: the Classic
--- clients have no voice mute or deafen button at all, and a missing button is
--- a button that is already not on screen.
local GLOBAL_GROUPS = {
    showMenuButton = { "ChatFrameMenuButton" },
    showVoiceButtons = {
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    },
}

--- The social button beside the chat window, which is a different widget
--- depending on which client this is.
---
--- Retail has QuickJoinToastButton. Classic never got it and still has
--- FriendsMicroButton in the same spot doing the same job. Strictly a fallback:
--- FriendsMicroButton is only touched on a client with no toast to manage, so
--- retail never has it hidden.
local function SocialButton()
    return Resolve("QuickJoinToastButton") or Resolve("FriendsMicroButton")
end

local function ApplyGlobals()
    local cfg = PC.Config

    for key, names in pairs(GLOBAL_GROUPS) do
        local hidden = cfg.enabled and not cfg[key]
        for i = 1, #names do
            SetHidden(Resolve(names[i]), hidden)
        end
    end

    SetHidden(SocialButton(), cfg.enabled and not cfg.showSocialButton)

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
---
--- The Classic clients sit in between, and that decides which jump-to-newest
--- button is the real one. They have the old strip AND the frame's own
--- ScrollToBottomButton, but no ScrollBar. The strip stands in a column to the
--- LEFT of the window, so answering "Jump To Newest" with the strip's copy
--- leaves an arrow floating beside the chat box while the modern button sits
--- where it belongs. Where the frame has its own, that is the setting's button
--- and the strip's copy is hidden outright.
---
--- Minimize is in the scroll group on purpose, on every client. It lives in the
--- same strip as the arrows, only appears beside an undocked window, and would
--- be the last gold bevel on a flat box. "Scroll Buttons" on brings the whole
--- strip back as the client drew it.
---
--- @return table scroll    hidden unless Scroll Buttons is on
--- @return table bottom    hidden unless Jump To Newest is on
--- @return table replaced  always hidden: a strip button the frame supersedes
local function ScrollParts(frame)
    local name = frame:GetName()
    local scroll, bottom, replaced = {}, {}, {}

    local stripBottom
    if name then
        local buttonFrame = _G[name .. "ButtonFrame"]
        if buttonFrame then
            scroll[#scroll + 1] = _G[name .. "ButtonFrameUpButton"] or buttonFrame.UpButton
            scroll[#scroll + 1] = _G[name .. "ButtonFrameDownButton"] or buttonFrame.DownButton
            stripBottom = _G[name .. "ButtonFrameBottomButton"] or buttonFrame.BottomButton
            scroll[#scroll + 1] = _G[name .. "ButtonFrameMinimizeButton"] or buttonFrame.MinimizeButton
        end
    end

    if frame.ScrollBar then scroll[#scroll + 1] = frame.ScrollBar end

    if frame.ScrollToBottomButton then
        bottom[#bottom + 1] = frame.ScrollToBottomButton
        if stripBottom then replaced[#replaced + 1] = stripBottom end
    elseif stripBottom then
        bottom[#bottom + 1] = stripBottom
    end

    return scroll, bottom, replaced
end

local function ButtonFrameFor(frame)
    local name = frame:GetName()
    return name and _G[name .. "ButtonFrame"] or nil
end

--------------------------------------------------------------------------------
-- The gap a hidden scroll bar leaves behind
--
-- Hiding a frame does not make it narrow, and the client measures this one:
--
--     function FloatingChatFrame_UpdateBackgroundAnchors(self)
--         local scrollbarWidth = 0
--         if self.ScrollBar then scrollbarWidth = self.ScrollBar:GetWidth() end
--         ...
--         self.Background:SetPoint("TOPRIGHT", self, "TOPRIGHT", 2 + scrollbarWidth, ...)
--         self:SetClampRectInsets(-35, 35 + scrollbarWidth, 38, -50)
--
-- So a scroll bar that is hidden but still its old width leaves the window's
-- background reaching past its right edge by that much, and the clamp reserving
-- the same strip again. Up against the right of the screen that is visible as
-- the window sitting a scroll bar's width in from the edge - and as it jumping
-- by that much whenever the client re-runs the function, which it does on
-- leaving Edit Mode.
--
-- Zeroing the width is what makes the client's own arithmetic come out right,
-- rather than another thing fighting it afterwards. The original is kept so
-- switching the addon off gives the bar its size back along with its visibility.
--------------------------------------------------------------------------------
local COLLAPSED = 0.001

local function SetScrollBarWidth(frame, collapsed)
    local bar = frame.ScrollBar
    if type(bar) ~= "table" or type(bar.SetWidth) ~= "function" then return end

    -- Nothing to do is the common case by a long way: this runs on every
    -- refresh, and the width only changes when the setting does. Returning here
    -- keeps a steady state free rather than re-running the client's background
    -- and clamp arithmetic once a second to arrive at the same numbers.
    local width = tonumber(bar:GetWidth()) or 0
    if collapsed then
        if width <= COLLAPSED then return end
    elseif bar.__pcWidth == nil then
        return
    end

    if collapsed then
        if bar.__pcWidth == nil then
            bar.__pcWidth = width > 0 and width or false
        end
        -- Not zero: a frame with no width falls back to whatever its anchors
        -- imply, which for this one is the height of the chat window. A hair
        -- over nothing measures as nothing everywhere it matters.
        pcall(bar.SetWidth, bar, COLLAPSED)
    elseif bar.__pcWidth then
        pcall(bar.SetWidth, bar, bar.__pcWidth)
        bar.__pcWidth = nil
    else
        bar.__pcWidth = nil
    end

    -- Let the client redo its own background and clamp from the new width. Its
    -- function, so the numbers stay Blizzard's and only the input changed.
    if type(_G.FloatingChatFrame_UpdateBackgroundAnchors) == "function" then
        pcall(_G.FloatingChatFrame_UpdateBackgroundAnchors, frame)

        -- That call ends in SetClampRectInsets(-35, 35 + scrollbarWidth, ...),
        -- so it puts a margin back even with the width down to nothing - the
        -- 35 is there for the button strip whether or not the strip is shown.
        -- Clearing it here rather than waiting for the next refresh is what
        -- stops the window stepping away from the edge in between.
        if Skin and Skin.ClearClampFor then
            Skin.ClearClampFor(frame)
        end
    end
end

local function Apply(frame)
    local cfg = PC.Config

    local scroll, bottom, replaced = ScrollParts(frame)

    for i = 1, #scroll do
        SetHidden(scroll[i], cfg.enabled and not cfg.showScrollButtons)
    end
    for i = 1, #bottom do
        SetHidden(bottom[i], cfg.enabled and not cfg.showBottomButton)
    end
    for i = 1, #replaced do
        SetHidden(replaced[i], cfg.enabled and true or false)
    end

    -- With nothing left inside it, the container is just a gold-edged rectangle.
    -- Its own jump-to-newest button only keeps it alive where it is the button
    -- the setting controls: where the frame has a modern one, the strip is empty
    -- the moment the arrows go, which is the default.
    local keepsBottom = #replaced == 0 and cfg.showBottomButton
    local buttonFrame = ButtonFrameFor(frame)
    if buttonFrame then
        Skin.KillChrome(buttonFrame)
        SetHidden(buttonFrame,
            cfg.enabled and not cfg.showScrollButtons and not keepsBottom)
    end

    -- After the hiding, so the width matches what is on screen.
    SetScrollBarWidth(frame, cfg.enabled and not cfg.showScrollButtons)
end

local function Restore(frame)
    local scroll, bottom, replaced = ScrollParts(frame)
    for i = 1, #scroll do SetHidden(scroll[i], false) end
    for i = 1, #bottom do SetHidden(bottom[i], false) end
    for i = 1, #replaced do SetHidden(replaced[i], false) end

    local buttonFrame = ButtonFrameFor(frame)
    if buttonFrame then
        SetHidden(buttonFrame, false)
        Skin.ReviveChrome(buttonFrame)
    end

    SetScrollBarWidth(frame, false)
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
