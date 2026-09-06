--------------------------------------------------------------------------------
-- Position
--
-- Puts the chat window where the config says, once, and then hands it back.
--
-- "Once" is the whole design, and the first version got it wrong. Applying the
-- position from the Frames handler meant re-applying it on every refresh -
-- login, docking, and every UPDATE_FLOATING_CHAT_WINDOWS, which is exactly what
-- fires after somebody drags the window in Edit Mode. So the window was yanked
-- back the moment it was released, and the addon had quietly taken away the
-- ability to move your own chat. A UI pack places things; it does not hold them
-- down.
--
-- What that leaves is a placement that happens at login and when something asks
-- for it explicitly - the settings button, /pchat move, a UI pack layout being
-- installed - and a window that is yours the rest of the time. Blizzard already
-- persists chat geometry through FCF_SavePositionAndDimensions, so a position
-- set once survives reloads on its own without being re-imposed.
--
-- And when you do move it, the config follows rather than fights: Blizzard calls
-- FCF_SavePositionAndDimensions after a user move, and that is hooked to learn
-- the new spot. Hooking it is safe - it is an ordinary function in
-- FloatingChatFrame.lua, not one of the protected ones this addon stays away
-- from.
--
-- Only the dock leader is moved. Docked windows follow their leader, and moving
-- a docked child individually is how you end up with two chat windows in two
-- corners and no way back.
--------------------------------------------------------------------------------

local addonName, PC = ...

local PeaversCommons = _G.PeaversCommons

local Position = {}
PC.Position = Position

local Frames = PC.Frames

-- Placed for this session. Cleared whenever something changes the intended
-- position, which is what makes "apply again" mean something.
local placed = false

-- Set while we are the ones moving the window, so the hook that learns a user's
-- position does not learn our own placement back again.
local placing = false

local pendingCombat = false

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

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

-- Blizzard's own store for chat geometry. Writing through it means the position
-- survives a reload the way a dragged window does, instead of being re-imposed
-- from scratch every login.
local function Persist(frame)
    if type(_G.FCF_SavePositionAndDimensions) == "function" then
        pcall(_G.FCF_SavePositionAndDimensions, frame)
    end
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Place the window.
--- @param frame? table The frame being refreshed; ignored unless it is the leader.
--- @param force? boolean Place even if it has already been placed this session.
function Position:Apply(frame, force)
    local cfg = PC.Config
    if not cfg or not cfg.enabled or not cfg.positionEnabled then return end

    if placed and not force then return end

    frame = frame or DockLeader()
    if not frame or not self:IsLeader(frame) then return end

    -- Moving a frame is not protected, but a chat window can be mid-anything
    -- during a fight and there is no reason at all this has to happen now.
    if InCombatLockdown() then
        pendingCombat = true
        return
    end

    -- The clamping margin has to go before the move, not after. A frame clamped
    -- to the screen with a left inset cannot be placed against the left edge:
    -- SetPoint puts it there and the clamp shoves it back by the inset, which
    -- looks exactly like the position setting being ignored.
    if PC.Skin and PC.Skin.ClearClampFor then
        PC.Skin.ClearClampFor(frame)
    end

    local point = cfg.chatPoint or "BOTTOMLEFT"
    local x = tonumber(cfg.chatX) or 0
    local y = tonumber(cfg.chatY) or 22
    local width = tonumber(cfg.chatWidth) or 0
    local height = tonumber(cfg.chatHeight) or 0

    placing = true

    -- Size first, then position: setting a size can nudge an anchored frame, so
    -- doing it the other way round leaves the window a few pixels out.
    if width > 0 and height > 0 then
        pcall(frame.SetSize, frame, width, height)
    end

    pcall(frame.SetUserPlaced, frame, true)
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, point, _G.UIParent, point, x, y)

    Persist(frame)

    placing = false
    placed = true
end

-- Place it again even though it has already been placed. What the settings
-- button, /pchat move and a UI pack install all want.
function Position:Reapply()
    placed = false
    self:Apply(nil, true)
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

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
    placed = false
    pendingCombat = false
end

function Position:Initialize()
    -- Placement, not enforcement: the handler runs on every refresh, and Apply
    -- returns immediately once the window has been placed for the session.
    Frames:RegisterHandler("position", function(frame)
        Position:Apply(frame)
    end, function(frame)
        Position:Restore(frame)
    end)

    ----------------------------------------------------------------------------
    -- Follow the player rather than fight them
    --
    -- Blizzard calls this after a user finishes moving or resizing a chat
    -- window, including from Edit Mode. Taking the new geometry as the intended
    -- one means dragging the window is how you move it, and the setting simply
    -- remembers where you put it.
    ----------------------------------------------------------------------------
    if type(_G.FCF_SavePositionAndDimensions) == "function" then
        hooksecurefunc("FCF_SavePositionAndDimensions", function(frame)
            if placing then return end
            if not PC.Config.positionEnabled then return end
            if not Position:IsLeader(frame) then return end

            Position:CaptureCurrent()
        end)
    end

    ----------------------------------------------------------------------------
    -- Edit Mode
    --
    -- Edit Mode reasserts chat window geometry, clamping margin included, when
    -- it opens and when a layout is applied. With a margin back in place the
    -- window jumps away from the screen edge and refuses to be dragged to it
    -- again - which is the bug this is here to stop.
    --
    -- Clearing on the way in matters most: it means the drag itself is
    -- unclamped, so the window can be put where you actually want it rather
    -- than where the margin allows.
    ----------------------------------------------------------------------------
    local function ClearClamps()
        if not PC.Config.enabled or not PC.Config.edgeToEdge then return end
        if not PC.Skin or not PC.Skin.ClearClampFor then return end
        Frames:Each(function(frame)
            PC.Skin.ClearClampFor(frame)
        end)
    end

    PeaversCommons.Events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ClearClamps)

    if _G.EventRegistry and type(_G.EventRegistry.RegisterCallback) == "function" then
        for _, moment in ipairs({ "EditMode.Enter", "EditMode.Exit" }) do
            pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
                moment, ClearClamps, Position)
        end
    end

    -- Deferred work from a fight. Cheap: returns immediately unless something
    -- actually asked to be moved.
    PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if not pendingCombat then return end
        pendingCombat = false
        Position:Apply()
        ClearClamps()
    end)
end

return Position
