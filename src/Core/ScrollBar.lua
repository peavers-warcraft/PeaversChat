--------------------------------------------------------------------------------
-- Scroll Bar
--
-- A thin flat bar down the right edge of a chat window, showing where in the
-- backlog you are and letting you drag your way through it.
--
-- Blizzard already ships a scrollbar, and this is not it. Theirs is the bevelled
-- widget the rest of the addon spends its time taking down, and it is switched
-- off here with everything else around the frame. This draws two rectangles in
-- the window's own colours instead, which is the only way it can sit in a flat
-- black box without being the one piece of art on screen.
--
-- Off by default, and hover-only when it is on. That is the request it was
-- built for and it is also the honest default for a control like this: a
-- scrollbar is a position readout more than it is a button, and a chat window
-- you are not pointing at is one whose scroll position you are not asking
-- about. "Dimmed" and "Always" are there for anybody who disagrees, and in both
-- of those the bar is a visible, clickable control at all times.
--
-- Cost, because this addon publishes one:
--
--   * Nothing runs per frame. The thumb is moved from the client's own scroll
--     calls, which is a hook that fires when you scroll and never otherwise.
--     The single exception is while you are physically dragging the thumb, and
--     that handler is attached on mouse-down and taken off again on mouse-up.
--   * Nothing touches the message path. AddMessage is deliberately not hooked -
--     that is the one thing this addon will not put itself in front of - so a
--     message arriving while you sit scrolled up and hovering moves the thumb
--     on your next scroll rather than instantly. That is the trade, and it is
--     the right way round.
--   * Nothing is measured while the bar is hidden. Every update leaves in a
--     single field read unless the bar is actually on screen.
--
-- The hooks go on the first time the feature is switched on and stay for the
-- session: hooksecurefunc cannot be undone. Turning it off afterwards leaves
-- them in place, doing nothing but that one field read.
--------------------------------------------------------------------------------

local addonName, PC = ...

local ScrollBar = {}
PC.ScrollBar = ScrollBar

local Frames = PC.Frames
local Skin = PC.Skin

local floor, max = math.floor, math.max

--- Short of this the thumb stops being something you can pick up.
local MIN_THUMB = 16

--- How far in from the window's border the bar sits.
local INSET = 2

local DEFAULT_COLOR = { r = 0.400, g = 0.400, b = 0.400 }

--------------------------------------------------------------------------------
-- Reading a chat window's scroll position
--------------------------------------------------------------------------------

--- How many lines the window is showing. Asked of the client where it will
--- answer, and worked out from the frame's height and font where it will not -
--- a temporary window at login has a height before it has laid a single line
--- out, and a thumb the size of the whole track is worse than an estimate.
local function VisibleLines(frame)
    if type(frame.GetNumLinesDisplayed) == "function" then
        local ok, lines = pcall(frame.GetNumLinesDisplayed, frame)
        if ok and type(lines) == "number" and lines > 0 then return lines end
    end

    local height = frame:GetHeight() or 0
    local _, size = frame:GetFont()
    if type(size) ~= "number" or size <= 0 then size = 12 end

    return max(1, floor(height / (size + 2)))
end

--- Total, visible, current offset, and how far the offset can go. The offset is
--- counted in lines up from the bottom, so zero is the newest message and the
--- maximum is the oldest thing still in the buffer.
local function Metrics(frame)
    local total = frame:GetNumMessages() or 0
    local visible = VisibleLines(frame)
    local offset = frame:GetScrollOffset() or 0

    local maxOffset = max(total - visible, 0)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end

    return total, visible, offset, maxOffset
end

--------------------------------------------------------------------------------
-- Moving the thumb
--------------------------------------------------------------------------------

--- Every path that can change what the bar should look like ends here, and
--- every one of them leaves again immediately unless the bar is on screen.
--- `__pcLive` rather than IsShown() because this is called from a hook on the
--- client's scroll functions, and a field read is not a client call.
local function Update(bar)
    if not bar or not bar.__pcLive then return end

    local frame = bar.__pcFrame
    if not frame then return end

    local total, visible, offset, maxOffset = Metrics(frame)

    -- Nothing to scroll. A scrollbar over a log with no backlog is a decoration
    -- that says something untrue, so the track stays and the thumb goes.
    if maxOffset <= 0 then
        bar.__pcMaxOffset = 0
        bar.__pcTravel = 0
        bar.thumb:Hide()
        return
    end

    local track = bar:GetHeight() or 0
    if track <= 0 then return end

    -- The thumb is as much of the track as the window is of the buffer, which
    -- is what makes its size mean "how much of this you can see at once".
    local fraction = (total > 0) and (visible / total) or 1
    local thumbHeight = max(MIN_THUMB, floor(track * fraction + 0.5))
    if thumbHeight > track then thumbHeight = track end

    local travel = track - thumbHeight

    bar.thumb:SetHeight(thumbHeight)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.thumb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.thumb:SetPoint("BOTTOM", bar, "BOTTOM", 0, floor(travel * (offset / maxOffset) + 0.5))
    bar.thumb:Show()

    bar.__pcMaxOffset = maxOffset
    bar.__pcTravel = travel
end

ScrollBar.Update = Update

--------------------------------------------------------------------------------
-- Visibility
--
-- Two hover flags rather than one, because moving the pointer from the chat
-- window onto the bar fires the window's OnLeave: the bar would hide itself the
-- moment you reached for it. Dragging counts as hovering for the same reason -
-- a drag that carries the pointer off the window must not take the thumb out
-- from under it.
--------------------------------------------------------------------------------

local function ApplyVisibility(bar)
    if not bar then return end

    local cfg = PC.Config
    if not (cfg.enabled and cfg.scrollBar) then
        bar.__pcLive = false
        bar:Hide()
        return
    end

    local mode = cfg.scrollBarVisibility or "hover"
    local hovered = bar.__pcFrameHover or bar.__pcBarHover or bar.__pcDragging

    if mode == "hover" and not hovered then
        -- Hidden rather than transparent: an invisible bar with the mouse still
        -- enabled is a click target nobody can see, which is the one rule this
        -- suite holds to.
        bar.__pcLive = false
        bar:Hide()
        return
    end

    bar.__pcLive = true
    bar:Show()

    if mode == "always" then
        bar:SetAlpha(hovered and 1 or 0.85)
    elseif mode == "dim" then
        bar:SetAlpha(hovered and 1 or 0.35)
    else
        bar:SetAlpha(1)
    end

    Update(bar)
end

local function SetHover(bar, which, hovered)
    if not bar then return end

    local slot = (which == "bar") and "__pcBarHover" or "__pcFrameHover"
    hovered = hovered or nil
    if bar[slot] == hovered then return end

    bar[slot] = hovered
    ApplyVisibility(bar)
end

--------------------------------------------------------------------------------
-- Dragging
--
-- The one place in this addon with an OnUpdate, and it is attached on mouse-down
-- and removed on mouse-up. There is no other way to follow a pointer, and a
-- handler that only exists while a button is held is not a handler that runs
-- while you play.
--------------------------------------------------------------------------------

local function CursorY(bar)
    local _, y = GetCursorPosition()
    local scale = bar:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end
    return y / scale
end

local function DragUpdate(thumb)
    local bar = thumb.__pcBar
    local frame = bar.__pcFrame
    local travel = bar.__pcTravel or 0
    local maxOffset = bar.__pcMaxOffset or 0
    if travel <= 0 or maxOffset <= 0 then return end

    -- Dragging downwards moves towards the newest message, which is a smaller
    -- offset - hence the subtraction rather than the addition it looks like it
    -- should be.
    local moved = thumb.__pcDragY - CursorY(bar)
    local target = thumb.__pcDragOffset - floor((moved * maxOffset / travel) + 0.5)

    if target < 0 then target = 0 end
    if target > maxOffset then target = maxOffset end

    if target ~= (frame:GetScrollOffset() or 0) then
        -- The hook on SetScrollOffset is what then moves the thumb, so the
        -- thumb follows the window rather than the window following the thumb.
        frame:SetScrollOffset(target)
    end
end

local function StopDrag(thumb)
    if not thumb.__pcDragging then return end

    thumb.__pcDragging = nil
    thumb:SetScript("OnUpdate", nil)

    local bar = thumb.__pcBar
    bar.__pcDragging = nil
    ApplyVisibility(bar)
end

local function StartDrag(thumb)
    local bar = thumb.__pcBar
    if (bar.__pcMaxOffset or 0) <= 0 then return end

    thumb.__pcDragging = true
    thumb.__pcDragY = CursorY(bar)
    thumb.__pcDragOffset = select(3, Metrics(bar.__pcFrame))

    bar.__pcDragging = true
    thumb:SetScript("OnUpdate", DragUpdate)
end

--------------------------------------------------------------------------------
-- Building one
--------------------------------------------------------------------------------

--- Every client function that can move a chat window's scroll position. There is
--- no single seam behind them - they are separate methods on the widget, not
--- one implemented in terms of another - so they are hooked one at a time.
---
--- AddMessage is not on this list and is not going on it. See the header.
local SCROLL_METHODS = {
    "SetScrollOffset",
    "ScrollUp",
    "ScrollDown",
    "PageUp",
    "PageDown",
    "ScrollToTop",
    "ScrollToBottom",
}

local function InstallHooks(frame)
    if frame.__pcScrollHooked then return end
    frame.__pcScrollHooked = true

    if type(frame.HookScript) == "function" then
        frame:HookScript("OnEnter", function(self) SetHover(self.peaversScrollBar, "frame", true) end)
        frame:HookScript("OnLeave", function(self) SetHover(self.peaversScrollBar, "frame", false) end)
    end

    for i = 1, #SCROLL_METHODS do
        local method = SCROLL_METHODS[i]
        if type(frame[method]) == "function" then
            hooksecurefunc(frame, method, function(self)
                Update(self.peaversScrollBar)
            end)
        end
    end
end

local function Build(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetFrameLevel((frame:GetFrameLevel() or 1) + 4)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    bar:Hide()

    bar.__pcFrame = frame

    bar.track = bar:CreateTexture(nil, "ARTWORK")
    bar.track:SetAllPoints()
    bar.track.__pcOwned = true

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetFrameLevel(bar:GetFrameLevel() + 1)
    thumb:EnableMouse(true)
    thumb:SetHeight(MIN_THUMB)
    thumb.__pcBar = bar

    thumb.texture = thumb:CreateTexture(nil, "OVERLAY")
    thumb.texture:SetAllPoints()
    thumb.texture.__pcOwned = true

    bar.thumb = thumb

    -- The wheel works over the whole window already; it has to keep working over
    -- the four pixels of it the bar now covers.
    bar:SetScript("OnMouseWheel", function(self, delta)
        local target = self.__pcFrame
        if delta > 0 then target:ScrollUp() else target:ScrollDown() end
    end)

    -- A click on the track pages towards it, which is what every scrollbar has
    -- done for thirty years.
    bar:SetScript("OnMouseDown", function(self)
        local target = self.__pcFrame
        local thumbTop = self.thumb:IsShown() and self.thumb:GetTop()
        local thumbBottom = self.thumb:IsShown() and self.thumb:GetBottom()
        local y = CursorY(self)

        if thumbTop and y > thumbTop then
            target:PageUp()
        elseif thumbBottom and y < thumbBottom then
            target:PageDown()
        end
    end)

    bar:SetScript("OnEnter", function(self) SetHover(self, "bar", true) end)
    bar:SetScript("OnLeave", function(self) SetHover(self, "bar", false) end)

    thumb:SetScript("OnEnter", function(self) SetHover(self.__pcBar, "bar", true) end)
    thumb:SetScript("OnLeave", function(self) SetHover(self.__pcBar, "bar", false) end)
    thumb:SetScript("OnMouseDown", StartDrag)
    thumb:SetScript("OnMouseUp", StopDrag)
    thumb:SetScript("OnHide", StopDrag)

    frame.peaversScrollBar = bar
    InstallHooks(frame)

    return bar
end

--------------------------------------------------------------------------------
-- Per-frame work
--------------------------------------------------------------------------------

local function Apply(frame)
    local cfg = PC.Config
    local bar = frame.peaversScrollBar

    if not bar then
        -- Nothing is built and nothing is hooked until somebody asks for it,
        -- which is what makes a feature that is off by default genuinely free.
        if not cfg.enabled or not cfg.scrollBar then return end
        bar = Build(frame)
    end

    local pad = Skin.Pad()
    local width = cfg.scrollBarWidth or 4
    local color = cfg.scrollBarColor or DEFAULT_COLOR

    local signature = table.concat({
        cfg.enabled and 1 or 0,
        cfg.scrollBar and 1 or 0,
        cfg.scrollBarVisibility or "hover",
        width, pad.right,
        color.r, color.g, color.b,
    }, ":")
    if not Skin.Changed(bar, "__pcApplied", signature) then return end

    bar:SetWidth(width)
    bar:ClearAllPoints()
    -- The right edge of the visible box is the frame's rect plus its right
    -- padding, so the bar hangs off that rather than off the text.
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", pad.right - INSET, -INSET)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad.right - INSET, INSET)

    bar.track:SetColorTexture(color.r, color.g, color.b, 0.22)
    bar.thumb.texture:SetColorTexture(color.r, color.g, color.b, 1)

    ApplyVisibility(bar)
end

local function Restore(frame)
    local bar = frame.peaversScrollBar
    if not bar then return end

    bar.__pcApplied = nil
    bar.__pcLive = false
    bar:Hide()
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function ScrollBar:Initialize()
    Frames:RegisterHandler("scrollbar", Apply, Restore)
end

return ScrollBar
