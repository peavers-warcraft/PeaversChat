--------------------------------------------------------------------------------
-- Position
--
-- Puts the chat window where the config says, and nowhere near anything
-- protected.
--
-- This is the one thing people assume a chat addon already does and this one
-- did not. `edgeToEdge` is often mistaken for it: that setting removes the
-- clamping inset Blizzard applies, so the window *can* be dragged flush to the
-- screen edge - it has never moved anything on its own. Somebody who turns it
-- on and waits for the window to move is waiting for a feature that was not
-- there.
--
-- Off by default, and deliberately so. A chat window is the piece of the
-- interface people have most often already arranged to their own taste, and an
-- addon that moves it on upgrade because it now can is an addon that has taken
-- something away. It only moves when `positionEnabled` is switched on - by the
-- settings page, or by a UI pack layout that has been chosen on purpose.
--
-- Only the dock leader is moved. Docked windows follow their leader, and moving
-- a docked child individually is how you end up with two chat windows in two
-- corners and no way back.
--
-- What this does NOT do:
--
--   * It does not hook or call a protected function. The screen-edge feature
--     did, was suspected of breaking chat in Mythic+, and was withdrawn on that
--     suspicion - so nothing here goes anywhere near that. SetPoint, SetSize
--     and FCF_SavePositionAndDimensions on a chat frame are all ordinary calls.
--   * It does not fight Edit Mode. Blizzard reasserts window geometry on
--     UPDATE_FLOATING_CHAT_WINDOWS, which Frames already re-runs handlers on,
--     so a layout change is followed by a re-apply rather than by a war.
--------------------------------------------------------------------------------

local addonName, PC = ...

local PeaversCommons = _G.PeaversCommons

local Position = {}
PC.Position = Position

local Frames = PC.Frames

-- Blizzard's own store for chat geometry. Writing through it means the position
-- survives a reload the way a dragged window does, instead of being re-imposed
-- from scratch every login and fighting whatever the client remembered.
local function Persist(frame)
    if type(_G.FCF_SavePositionAndDimensions) == "function" then
        pcall(_G.FCF_SavePositionAndDimensions, frame)
    end
end

-- The frame everything else is docked to. ChatFrame1 in every normal setup;
-- asked for rather than assumed because a general chat window can be closed and
-- the dock re-led by another.
local function DockLeader()
    if _G.GENERAL_CHAT_DOCK and _G.GENERAL_CHAT_DOCK.primary then
        return _G.GENERAL_CHAT_DOCK.primary
    end
    return _G.ChatFrame1
end

function Position:IsLeader(frame)
    return frame ~= nil and frame == DockLeader()
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local pendingCombat = false

function Position:Apply(frame)
    local cfg = PC.Config
    if not cfg or not cfg.enabled or not cfg.positionEnabled then return end

    frame = frame or DockLeader()
    if not frame or not self:IsLeader(frame) then return end

    -- Moving a frame is not protected, but a chat window can be mid-animation
    -- during a fight and there is no reason at all this has to happen now.
    if InCombatLockdown() then
        pendingCombat = true
        return
    end

    local point = cfg.chatPoint or "BOTTOMLEFT"
    local x = tonumber(cfg.chatX) or 0
    local y = tonumber(cfg.chatY) or 22
    local width = tonumber(cfg.chatWidth) or 0
    local height = tonumber(cfg.chatHeight) or 0

    -- Clear the client's clamping margin before moving, not after. A frame that
    -- is clamped to the screen with a left inset cannot be placed against the
    -- left edge: SetPoint puts it there and the clamp shoves it back by the
    -- inset, which looks exactly like the position setting being ignored.
    if PC.Skin and PC.Skin.ClearClampFor then
        PC.Skin.ClearClampFor(frame)
    end

    -- Size first, then position: setting a size can nudge an anchored frame, so
    -- doing it the other way round leaves the window a few pixels out.
    if width > 0 and height > 0 then
        pcall(frame.SetSize, frame, width, height)
    end

    pcall(frame.SetUserPlaced, frame, true)
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, point, _G.UIParent, point, x, y)

    Persist(frame)
end

-- Read the window's current geometry back into the config. This is what makes
-- the feature usable rather than a coordinate-guessing game: drag the window
-- where you want it, press the button, and the numbers are filled in for you.
-- @return boolean captured
function Position:CaptureCurrent()
    local frame = DockLeader()
    if not frame then return false end

    local point, _, _, x, y = frame:GetPoint()
    if not point then return false end

    local cfg = PC.Config
    cfg.chatPoint = point
    cfg.chatX = math.floor(x + 0.5)
    cfg.chatY = math.floor(y + 0.5)
    cfg.chatWidth = math.floor((frame:GetWidth() or 0) + 0.5)
    cfg.chatHeight = math.floor((frame:GetHeight() or 0) + 0.5)
    cfg:Save()

    return true
end

-- Stop managing the position. The window is left exactly where it is rather
-- than sent back to Blizzard's default - somebody switching this off wants the
-- addon to stop deciding, not to have their chat jump.
function Position:Restore()
    pendingCombat = false
end

function Position:Initialize()
    Frames:RegisterHandler("position", function(frame)
        Position:Apply(frame)
    end, function(frame)
        Position:Restore(frame)
    end)

    -- Deferred work from a fight. Registered once, and cheap: the handler
    -- returns immediately unless something actually asked to be moved.
    PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if not pendingCombat then return end
        pendingCombat = false
        Position:Apply()
    end)
end

return Position
