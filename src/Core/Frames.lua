--------------------------------------------------------------------------------
-- Frames
--
-- The one place that knows which chat windows exist and when they need looking
-- at again. Every other module registers a handler here and stops caring about
-- discovery, ordering, or Blizzard putting a window back the way it was.
--
-- Three things make this less trivial than "loop 1 to 10":
--
-- 1. A whisper or a pet-battle log opens a *temporary* window, which is a real
--    ChatFrame that did not exist at login. FCF_OpenTemporaryWindow is hooked so
--    those get adopted the moment they appear rather than on the next event.
--
-- 2. Blizzard reasserts window state on UPDATE_CHAT_WINDOWS and friends, which
--    fire when the interface options are touched, when a window is docked or
--    undocked, and on some loading screens. Handlers are therefore required to
--    be idempotent - "make this frame correct", not "change this frame" - so a
--    reassert is a re-run rather than a special case.
--
-- 3. A module can register after frames have already been adopted. Registration
--    replays the handler over everything known so far, which makes load order
--    inside Main.lua a matter of taste rather than of correctness.
--
-- Nothing here runs per frame or on a timer. Discovery happens at login, on the
-- handful of events above, and when a temporary window opens.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Frames = {}
PC.Frames = Frames

-- Ordered, because "kill Blizzard's textures" has to happen before "draw ours"
-- and registration order in Main.lua is how that is expressed.
local handlers = {}

-- Insertion-ordered list plus a set, so replay is deterministic and adoption is
-- still an O(1) test.
local frames = {}
local isAdopted = {}

local NUM_WINDOWS = _G.NUM_CHAT_WINDOWS or 10

--------------------------------------------------------------------------------
-- Handlers
--------------------------------------------------------------------------------

--- Register a module's per-frame work.
--- @param name string Identifier, for debugging only.
--- @param apply function(frame) Idempotent. Called for every frame, now and later.
--- @param restore? function(frame) Called by Frames:Restore() when the addon is disabled.
function Frames:RegisterHandler(name, apply, restore)
    handlers[#handlers + 1] = { name = name, apply = apply, restore = restore }

    for i = 1, #frames do
        pcall(apply, frames[i])
    end
end

--------------------------------------------------------------------------------
-- Adoption
--------------------------------------------------------------------------------

local function RunHandlers(frame)
    for i = 1, #handlers do
        -- A handler that throws must not take the rest of the chat window with
        -- it: a single missing Blizzard global in a future patch should cost one
        -- feature, not the whole addon.
        local ok, err = pcall(handlers[i].apply, frame)
        if not ok and PC.Config and PC.Config.debugMode then
            print(("|cff3abdf7PeaversChat|r: handler '%s' failed on %s: %s")
                :format(handlers[i].name, frame:GetName() or "?", tostring(err)))
        end
    end
end

--- Take ownership of a chat frame, or refresh one already owned.
function Frames:Adopt(frame)
    if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return end

    if not isAdopted[frame] then
        isAdopted[frame] = true
        frames[#frames + 1] = frame
    end

    RunHandlers(frame)
end

--- Every chat frame the client currently has, adopted or not.
function Frames:Sweep()
    for i = 1, NUM_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then self:Adopt(frame) end
    end
end

--- Re-run every handler over every adopted frame. This is what a settings change
--- calls: handlers are idempotent, so "apply the new config" and "adopt for the
--- first time" are the same code path.
function Frames:Refresh()
    self:Sweep()
end

--- Hand every frame back to Blizzard, as far as an addon can.
function Frames:Restore()
    for i = 1, #frames do
        for h = 1, #handlers do
            local restore = handlers[h].restore
            if restore then pcall(restore, frames[i]) end
        end
    end
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function Frames:Each(fn)
    for i = 1, #frames do fn(frames[i]) end
end

function Frames:Count()
    return #frames
end

--- The docked window currently on top - the one a copy or a scroll should act on
--- when the caller has no frame of its own in hand.
function Frames:Selected()
    if _G.SELECTED_DOCK_FRAME then return _G.SELECTED_DOCK_FRAME end
    if _G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK then
        local ok, frame = pcall(_G.FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
        if ok and frame then return frame end
    end
    return _G.ChatFrame1
end

--- The tab belonging to a chat frame, under either the modern field or the
--- legacy global name.
function Frames:TabFor(frame)
    if not frame then return nil end
    local id = frame:GetID()
    return (id and id > 0 and _G["ChatFrame" .. id .. "Tab"]) or frame.tab or nil
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function Frames:Initialize()
    self:Sweep()

    -- A temporary window (whisper, pet battle, instance chat) is a chat frame
    -- that did not exist a moment ago. Adopting it here rather than waiting for
    -- an event is what stops a new whisper tab flashing up in Blizzard's gold.
    if type(_G.FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            Frames:Sweep()
        end)
    end

    if type(_G.FCF_OpenNewWindow) == "function" then
        hooksecurefunc("FCF_OpenNewWindow", function()
            Frames:Sweep()
        end)
    end

    -- Docking moves a frame and rebuilds the tab row, which undoes tab layout.
    if type(_G.FCF_DockFrame) == "function" then
        hooksecurefunc("FCF_DockFrame", function()
            Frames:Refresh()
        end)
    end

    local Events = _G.PeaversCommons.Events
    for _, event in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
        Events:RegisterEvent(event, function()
            if PC.Config.enabled then Frames:Refresh() end
        end)
    end
end

return Frames
