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
-- installed - and a window that is yours the rest of the time.
--
-- THE PART THAT IS NOT TRUE, and worth recording because the design above rested
-- on it: "Blizzard persists chat geometry, so a position set once survives
-- reloads on its own." Not for the one window this file moves.
-- FCF_RestorePositionAndDimensions opens with
--
--     if (chatFrame == DEFAULT_CHAT_FRAME) then return end
--
-- on Mainline and Classic alike, so the client saves ChatFrame1's geometry and
-- never puts it back. This file is the only thing restoring the window.
--
-- The two records do not agree on units either: the client stores a fraction of
-- the screen, from a corner it picks by which half the window's centre is in,
-- and this addon stores absolute offsets from a corner the player chose.
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

-- Forward declaration. Defined under "Holding the position against the client",
-- below, but Apply above it has to be able to ask - and a local only exists for
-- the code written after it.
local PlayerIsDragging

-- Set while Edit Mode is open: nothing here puts a window back while the player
-- is deliberately arranging it. Cleared once the new position has been read,
-- not the moment Edit Mode closes - see LearnFromEditMode.
local editing = false

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

    -- Never while the player has hold of it. Reassert checks this too; Apply
    -- checks it again because /pchat move, the settings button and a UI pack
    -- install all arrive here directly, and none of them is worth yanking a
    -- window out of somebody's hand for.
    if PlayerIsDragging() then return end

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
    --
    -- This used to prefer FCF_SetWindowSize over SetSize, to keep the client's
    -- own record of the size in step. There is no FCF_SetWindowSize in FrameXML
    -- on any client, so that check never passed and every install has taken this
    -- branch anyway. The record is written by SetChatWindowSavedDimensions,
    -- which FCF_SavePositionAndDimensions calls and Persist below goes through.
    if width > 0 and height > 0 then
        pcall(frame.SetSize, frame, width, height)
    end

    pcall(frame.SetUserPlaced, frame, true)
    pcall(frame.ClearAllPoints, frame)
    -- The recorded relative corner, falling back to the same corner for every
    -- position written before that was stored - which is what the old code
    -- assumed unconditionally, and what the settings page still means.
    pcall(frame.SetPoint, frame, point, _G.UIParent, cfg.chatRelativePoint or point, x, y)

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
-- Holding the position against the client
--
-- The client re-lays its chat windows out several times during a login and on
-- every dock change, so a placement that happens once is a race against the last
-- of them. It used to be placed at login and then again a second later if the
-- size did not match, which is both a guess at when the client has finished and
-- the visible jump people describe as the chat snapping about after loading.
--
-- So it re-asserts, on the events that do the re-laying, which is what ElvUI
-- does and the only thing that holds.
--
-- Re-asserting from a STALE config is how an addon takes away your ability to
-- move your own chat, by snapping every drag back as you release it. Three
-- things stop that here.
--
-- The config learns first. A drag or resize ends in
-- FCF_SavePositionAndDimensions, which is hooked, so what gets re-asserted IS
-- where you just put the window.
--
-- Nothing is applied mid-drag. MOVING_CHATFRAME and the grabber's button state
-- both mean the geometry on screen is the player's hand - not something to
-- enforce, and not something to learn from either. A re-assert landing mid-drag
-- would snap the window back and then be captured as intentional, losing the
-- drag for good.
--
-- And it is deferred a frame, which is what orders the two halves. Letting go
-- runs FCF_StopDragging, which docks the frame - firing
-- UPDATE_FLOATING_CHAT_WINDOWS synchronously, before anything is saved - and
-- only then calls FCF_SavePositionAndDimensions. An undeferred re-assert would
-- run off that event against the old position. A frame later, the save has been
-- and the config already holds the new one.
--------------------------------------------------------------------------------

-- True while the player has hold of the window. Checked rather than tracked: the
-- client owns both of these and there is no event for either.
function PlayerIsDragging()
    -- Edit Mode counts. It is a longer drag with a panel attached, and the same
    -- rule applies: what is on screen is the player's doing.
    if editing then return true end

    if _G.MOVING_CHATFRAME then return true end

    local frame = DockLeader()
    local grabber = frame and frame.ResizeButton
    if grabber and grabber.GetButtonState and grabber:GetButtonState() == "PUSHED" then
        return true
    end

    return false
end

Position.PlayerIsDragging = PlayerIsDragging

local reassertQueued = false

-- Put the window back where the config says, however many times the client
-- disturbs it. Safe to call on every event that might have: it coalesces to one
-- pass per frame, does nothing while the window is being dragged, and re-applies
-- the geometry the hook has already learned.
function Position:Reassert()
    local cfg = PC.Config
    if not cfg or not cfg.enabled or not cfg.positionEnabled then return end
    if reassertQueued then return end

    reassertQueued = true

    local function run()
        reassertQueued = false
        if PlayerIsDragging() then return end
        if not PC.Config.enabled or not PC.Config.positionEnabled then return end

        Position:Apply(nil, true)
    end

    if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, run)
    else
        run()
    end
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

    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if not point then return false end

    -- Anchored to something that is not the screen - a dock, a temporary window,
    -- another addon's holder. Replaying that as an offset from UIParent would put
    -- the window somewhere it has never been, so the safe answer is to keep what
    -- was already recorded rather than learn a position we cannot reproduce.
    if relativeTo and relativeTo ~= _G.UIParent then return false end

    local cfg = PC.Config
    cfg.chatPoint = point
    cfg.chatRelativePoint = relativePoint
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

            -- Never learn from a window that is still being held. The client
            -- calls this from the drag and resize handlers after it has let go,
            -- so in the normal case nothing is moving by now - but a third addon
            -- calling it mid-drag would otherwise write a half-finished position
            -- into the config as though it were intended.
            if PlayerIsDragging() then return end

            -- Deliberately NOT "only if this is the dock leader", which is what
            -- it used to say and which quietly dropped most resizes. The resize
            -- grabber's OnMouseUp in FloatingChatFrame.xml sizes the leader when
            -- the window is docked and then reports the *child* whose grabber
            -- was dragged - so resizing with any tab but the first selected
            -- arrived here as a non-leader, got dropped, and the next login put
            -- the old size back. A docked frame's geometry is the leader's, so
            -- either one is a reason to go and read the leader.
            if not (Position:IsLeader(frame) or (frame and frame.isDocked)) then
                return
            end

            Position:CaptureCurrent()
        end)
    end

    ----------------------------------------------------------------------------
    -- Edit Mode
    --
    -- Edit Mode reasserts chat window geometry, clamping margin included, when
    -- it opens and when a layout is applied. Clearing on the way in matters
    -- most: it means the drag itself is unclamped, so the window goes where you
    -- want it rather than where the margin allows.
    ----------------------------------------------------------------------------
    local function ClearClamps()
        if not PC.Config.enabled then return end
        if not PC.Config.edgeToEdge then return end
        if not PC.Skin or not PC.Skin.ClearClampFor then return end

        Frames:Each(function(frame)
            PC.Skin.ClearClampFor(frame)
        end)
    end

    ----------------------------------------------------------------------------
    -- Leaving Edit Mode
    --
    -- Learn where the window ended up. Not put it back: that was tried, and it
    -- re-applied a config that had never heard about the move, which is exactly
    -- how a window arranged in Edit Mode snapped home as you closed it.
    --
    -- The gap is that Edit Mode does not go through
    -- FCF_SavePositionAndDimensions. FrameXML calls that from two places, both
    -- of them the native drag, so the hook keeping this config in step never
    -- hears about an Edit Mode move and every later re-assert is stale.
    --
    -- On the way out only: Edit Mode moves chat windows to its own layout when
    -- it opens and when a layout is applied, and capturing those would overwrite
    -- the player's position with one Edit Mode chose.
    ----------------------------------------------------------------------------
    local function LearnFromEditMode()
        -- A frame later, so the geometry has settled out of whatever Edit Mode
        -- does on its way down before it is read.
        --
        -- `editing` is cleared here rather than the instant Edit Mode closed,
        -- which is what keeps the two halves in order: until the new position
        -- has been read, PlayerIsDragging still answers yes and nothing can
        -- re-assert the old one over it.
        local function finish()
            if PC.Config.enabled and PC.Config.positionEnabled then
                Position:CaptureCurrent()
            end
            editing = false
        end

        if type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(0, finish)
        else
            finish()
        end
    end

    PeaversCommons.Events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", ClearClamps)

    if _G.EventRegistry and type(_G.EventRegistry.RegisterCallback) == "function" then
        for _, moment in ipairs({ "EditMode.Enter", "EditMode.Exit" }) do
            pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
                moment, ClearClamps, Position)
        end

        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
            "EditMode.Enter", function() editing = true end, Position)

        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
            "EditMode.Exit", LearnFromEditMode, Position)
    end

    ----------------------------------------------------------------------------
    -- The events the client re-lays its chat windows on
    --
    -- This replaces a single look a second after login, which was a guess at
    -- when the client would have finished and was visible as the window jumping
    -- about once the world had loaded. These are the moments it actually moves
    -- things, so the window is put back as part of the same frame rather than a
    -- second later where somebody can watch it happen.
    --
    -- UPDATE_CHAT_WINDOWS and UPDATE_FLOATING_CHAT_WINDOWS are the client
    -- re-reading its own chat settings, at login and whenever they change.
    -- PLAYER_ENTERING_WORLD covers a reload and every zone in after it.
    --
    -- All three go through Reassert, which coalesces them to one pass, does
    -- nothing while the window is in the player's hand, and re-applies what the
    -- config has already learned rather than anything older.
    ----------------------------------------------------------------------------
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "UPDATE_CHAT_WINDOWS",
        "UPDATE_FLOATING_CHAT_WINDOWS",
    }) do
        PeaversCommons.Events:RegisterEvent(event, function()
            Position:Reassert()
        end)
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
