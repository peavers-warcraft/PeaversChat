--------------------------------------------------------------------------------
-- Position
--
-- Puts the main chat window where the config says, and keeps it there without
-- ever being seen to move it.
--
-- ChatFrame1 is an Edit Mode system. FCF_RestorePositionAndDimensions returns
-- early for DEFAULT_CHAT_FRAME, so what places it at login is the active Edit
-- Mode layout - a record that knows nothing of this addon. Placing the window
-- afterwards, a frame later, is the jump people see: Edit Mode's spot, then
-- ours. Three things take the jump away.
--
-- 1. The layout is told. Once placed, our anchor and size are written into the
--    active Edit Mode layout (never a preset, never while Edit Mode is open or
--    in combat), so from the next login Edit Mode itself puts the window here
--    and there is nothing left to correct.
--
-- 2. Corrections land in the same frame. A hook on the window's own
--    ApplySystemAnchor (and UpdateClampOffsets) attaches a one-shot OnUpdate,
--    which runs after this frame's events and before it is drawn. A timer would
--    wait a frame, and that frame at Edit Mode's spot is the blink. The hook
--    itself only attaches the script: nothing of ours runs inside Edit Mode.
--
-- 3. No SetSize. The size rides as a second corner anchor, so the rect is set
--    entirely by anchors. SetSize on ChatFrame1 dispatches the dock's size
--    handler synchronously from addon code, which taints the dock.
--
-- Anchors are written through SetPointBase / ClearAllPointsBase where Edit Mode
-- has replaced the frame's own: the overrides would mark the layout as edited.
-- Every write is compare-gated, so a pass that finds the window in place does
-- nothing. A drag, a resize or an Edit Mode move is learned, not fought.
--
-- Only the dock leader is placed; docked windows follow it.
--------------------------------------------------------------------------------

local addonName, PC = ...

local PeaversCommons = _G.PeaversCommons

local Position = {}
PC.Position = Position

local Frames = PC.Frames

local abs, floor = math.abs, math.floor

local placed = false        -- placed this session; cleared to place again
local placing = false       -- we are moving it, so do not learn it back
local pendingCombat = false
local editing = false       -- Edit Mode is open; see LearnFromEditMode

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function DockLeader()
    if _G.GENERAL_CHAT_DOCK and _G.GENERAL_CHAT_DOCK.primary then
        return _G.GENERAL_CHAT_DOCK.primary
    end
    return _G.ChatFrame1
end

function Position:IsLeader(frame)
    return frame ~= nil and frame == DockLeader()
end

local function PlayerIsDragging()
    if editing or _G.MOVING_CHATFRAME then return true end
    local frame = DockLeader()
    local grabber = frame and frame.ResizeButton
    return grabber and grabber.GetButtonState and grabber:GetButtonState() == "PUSHED" or false
end

Position.PlayerIsDragging = PlayerIsDragging

--------------------------------------------------------------------------------
-- The target
--------------------------------------------------------------------------------

-- Each of the nine points as a share of a rect, from its left and its bottom.
local FRAC = {
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
}

-- A corner, the corner opposite it, and which way the size reaches it.
local OPPOSITE = {
    BOTTOMLEFT = { "TOPRIGHT", 1, 1 },
    TOPLEFT = { "BOTTOMRIGHT", 1, -1 },
    TOPRIGHT = { "BOTTOMLEFT", -1, -1 },
    BOTTOMRIGHT = { "TOPLEFT", -1, 1 },
}

-- { point, relativePoint, x, y } for each anchor; reused, never reallocated.
local target = { {}, {} }

local function SetTarget(i, point, rel, x, y)
    local t = target[i]
    t[1], t[2], t[3], t[4] = point, rel, x, y
end

--- Fill `target` from the config. Returns how many anchors it holds - one
--- when the size is left alone, two when it rides a second corner - or nil
--- for a config naming a point that does not exist.
local function BuildTarget(cfg)
    local point = cfg.chatPoint or "BOTTOMLEFT"
    local rel = cfg.chatRelativePoint or point
    local f = FRAC[point]
    if not f or not FRAC[rel] then return nil end

    local x, y = tonumber(cfg.chatX) or 0, tonumber(cfg.chatY) or 22
    local w, h = tonumber(cfg.chatWidth) or 0, tonumber(cfg.chatHeight) or 0

    if w <= 0 or h <= 0 then
        SetTarget(1, point, rel, x, y)
        return 1
    end

    local opp = OPPOSITE[point]
    if opp then
        SetTarget(1, point, rel, x, y)
        SetTarget(2, opp[1], rel, x + opp[2] * w, y + opp[3] * h)
    else
        -- An edge middle or the centre: the rect composed around it outright.
        SetTarget(1, "TOPLEFT", rel, x - f[1] * w, y + (1 - f[2]) * h)
        SetTarget(2, "BOTTOMRIGHT", rel, x + (1 - f[1]) * w, y - f[2] * h)
    end
    return 2
end

--- The frame already carries exactly these anchors. GetPoint reports the
--- anchor definitions, not a rect that might lag. A secret read is a miss.
local function AtTarget(frame, n)
    local secret = _G.issecretvalue
    local num = frame:GetNumPoints()
    if (secret and secret(num)) or num ~= n then return false end

    for i = 1, n do
        local point, relTo, relPoint, x, y = frame:GetPoint(i)
        if secret and (secret(point) or secret(relTo) or secret(relPoint)
            or secret(x) or secret(y)) then
            return false
        end
        if relTo ~= _G.UIParent or type(x) ~= "number" or type(y) ~= "number" then
            return false
        end

        local hit = false
        for j = 1, n do
            local t = target[j]
            if t[1] == point and t[2] == relPoint and abs(t[3] - x) < 0.1 and abs(t[4] - y) < 0.1 then
                hit = true
            end
        end
        if not hit then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Telling Edit Mode
--------------------------------------------------------------------------------

local function EditModeOpen()
    local manager = _G.EditModeManagerFrame
    if not manager then return false end
    return (manager.editModeActive or (manager.IsShown and manager:IsShown())) and true or false
end

--- Every layout, presets first, which is the list SaveLayouts takes and the
--- one activeLayout indexes. GetLayouts returns only the saved half, and
--- saving a short list would delete layouts. nil whenever that cannot be built.
local function LayoutsForSave()
    local ok, info = pcall(_G.C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return nil end

    local manager = _G.EditModePresetLayoutManager
    local presets = manager and manager.GetCopyOfPresetLayouts and manager:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return nil end

    local count = #presets
    for i = 1, #info.layouts do presets[count + i] = info.layouts[i] end
    info.layouts = presets
    return info, count
end

local function FindRow(sys, id)
    if type(sys.settings) ~= "table" then return nil end
    for _, row in ipairs(sys.settings) do
        if type(row) == "table" and row.setting == id then return row end
    end
end

-- What was last written this session. Once per target at most, so a layout
-- that will not take a value can never loop write, apply, write.
local lastStored

local function SyncStore()
    local cfg = PC.Config
    if not cfg.enabled or not cfg.positionEnabled then return end
    if InCombatLockdown() or EditModeOpen() or PlayerIsDragging() then return end

    local Enum, CEM = _G.Enum, _G.C_EditMode
    local systems = Enum and Enum.EditModeSystem
    local settings = Enum and Enum.EditModeChatFrameSetting
    local layoutTypes = Enum and Enum.EditModeLayoutType
    if not (CEM and CEM.GetLayouts and CEM.SaveLayouts and systems and systems.ChatFrame
        and settings and settings.WidthHundreds and settings.HeightTensAndOnes
        and layoutTypes and layoutTypes.Preset ~= nil) then
        return
    end

    local frame = _G.ChatFrame1
    if not frame or DockLeader() ~= frame or not BuildTarget(cfg) then return end

    -- Edit Mode keeps one anchor, in offsets at scale 1, plus a size.
    local t = target[1]
    local scale = frame:GetScale() or 1
    local x, y = t[3] * scale, t[4] * scale
    local w = floor((tonumber(cfg.chatWidth) or 0) + 0.5)
    local h = floor((tonumber(cfg.chatHeight) or 0) + 0.5)

    local key = table.concat({ t[1], t[2], x, y, w, h }, ":")
    if key == lastStored then return end
    lastStored = key

    local blob, presets = LayoutsForSave()
    local active = blob and blob.activeLayout
    if type(active) ~= "number" or active <= presets then return end
    local layout = blob.layouts[active]
    if type(layout) ~= "table" or layout.layoutType == layoutTypes.Preset then return end

    local sys
    for _, entry in ipairs(type(layout.systems) == "table" and layout.systems or {}) do
        if type(entry) == "table" and entry.system == systems.ChatFrame then sys = entry break end
    end
    if not sys then return end

    local changed = false

    local anchor = sys.anchorInfo
    if not (type(anchor) == "table" and sys.anchorInfo2 == nil
        and anchor.point == t[1] and anchor.relativeTo == "UIParent" and anchor.relativePoint == t[2]
        and type(anchor.offsetX) == "number" and type(anchor.offsetY) == "number"
        and abs(anchor.offsetX - x) < 0.1 and abs(anchor.offsetY - y) < 0.1) then
        if type(anchor) ~= "table" then
            anchor = {}
            sys.anchorInfo = anchor
        end
        anchor.point, anchor.relativeTo, anchor.relativePoint = t[1], "UIParent", t[2]
        anchor.offsetX, anchor.offsetY = x, y
        sys.anchorInfo2 = nil
        sys.isInDefaultPosition = false
        changed = true
    end

    -- Each dimension is stored as a hundreds row and a tens-and-ones row.
    if w > 0 and h > 0 then
        for _, pair in ipairs({
            { settings.WidthHundreds, floor(w / 100) }, { settings.WidthTensAndOnes, w % 100 },
            { settings.HeightHundreds, floor(h / 100) }, { settings.HeightTensAndOnes, h % 100 },
        }) do
            local row = FindRow(sys, pair[1])
            if not row then
                if type(sys.settings) ~= "table" then sys.settings = {} end
                sys.settings[#sys.settings + 1] = { setting = pair[1], value = pair[2] }
                changed = true
            elseif row.value ~= pair[2] then
                row.value = pair[2]
                changed = true
            end
        end
    end

    if changed then pcall(CEM.SaveLayouts, blob) end
end

local storeQueued = false

local function ScheduleStore()
    if storeQueued then return end
    storeQueued = true
    _G.C_Timer.After(0, function()
        storeQueued = false
        SyncStore()
    end)
end

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

local function Place(frame)
    local n = BuildTarget(PC.Config)
    if not n then return false end

    -- Before the anchors: a frame still clamped with an inset cannot sit
    -- against the screen edge, and the clamp shoves it back.
    if PC.Skin and PC.Skin.ClearClampFor then PC.Skin.ClearClampFor(frame) end

    if AtTarget(frame, n) then return true end

    local system = frame.SetPointBase ~= nil
    local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
    local setPoint = frame.SetPointBase or frame.SetPoint

    placing = true
    if not system then pcall(frame.SetUserPlaced, frame, true) end
    pcall(clear, frame)
    for i = 1, n do
        local t = target[i]
        pcall(setPoint, frame, t[1], _G.UIParent, t[2], t[3], t[4])
    end

    -- A window that is not an Edit Mode system is restored by the client's own
    -- chat geometry record, so it gets written there instead.
    if not system and type(_G.FCF_SavePositionAndDimensions) == "function" then
        pcall(_G.FCF_SavePositionAndDimensions, frame)
    end
    placing = false
    return true
end

local guarded = false
local InstallGuard

--- Place the window.
--- @param frame? table The frame being refreshed; ignored unless it is the leader.
--- @param force? boolean Place even if it has already been placed this session.
function Position:Apply(frame, force)
    local cfg = PC.Config
    if not cfg or not cfg.enabled or not cfg.positionEnabled then return end
    if placed and not force then return end
    if PlayerIsDragging() then return end

    frame = frame or DockLeader()
    if not frame or not self:IsLeader(frame) then return end

    if InCombatLockdown() then
        pendingCombat = true
        return
    end

    if not Place(frame) then return end
    placed = true

    InstallGuard()
    ScheduleStore()
end

-- What the settings button, /pchat move and a UI pack install want.
function Position:Reapply()
    placed = false
    lastStored = nil
    self:Apply(nil, true)
end

--------------------------------------------------------------------------------
-- Holding it, in the same frame
--------------------------------------------------------------------------------

local driver = CreateFrame("Frame")

-- Attached on request and removed as it runs, so nothing is installed while
-- there is nothing to do.
local function RunReassert(self)
    self:SetScript("OnUpdate", nil)
    if PlayerIsDragging() then return end
    Position:Apply(nil, true)
end

function Position:Reassert()
    local cfg = PC.Config
    if not cfg or not cfg.enabled or not cfg.positionEnabled then return end
    driver:SetScript("OnUpdate", RunReassert)
end

-- Installed the first time the window is placed, never at load: a hook cannot
-- be taken off, so it goes on only for somebody who asked to be positioned.
-- Never a hook on SetPoint, and the window is never reparented.
function InstallGuard()
    if guarded then return end
    local frame = _G.ChatFrame1
    if not frame then return end
    guarded = true

    for _, method in ipairs({ "ApplySystemAnchor", "UpdateClampOffsets" }) do
        if type(frame[method]) == "function" then
            hooksecurefunc(frame, method, function() Position:Reassert() end)
        end
    end
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

--- Read the window's current geometry back into the config.
--- @return boolean captured
function Position:CaptureCurrent()
    local frame = DockLeader()
    if not frame then return false end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if not point then return false end

    -- Anchored to something that is not the screen: an offset from UIParent
    -- would put the window somewhere it has never been.
    if relativeTo and relativeTo ~= _G.UIParent then return false end

    local cfg = PC.Config
    cfg.chatPoint = point
    cfg.chatRelativePoint = relativePoint
    cfg.chatX = floor(x + 0.5)
    cfg.chatY = floor(y + 0.5)
    cfg.chatWidth = floor((frame:GetWidth() or 0) + 0.5)
    cfg.chatHeight = floor((frame:GetHeight() or 0) + 0.5)
    cfg:Save()

    -- The layout follows, so the next login puts it here too.
    ScheduleStore()
    return true
end

-- Stop managing it. Left exactly where it is: switching this off means stop
-- deciding, not jump back to Blizzard's spot.
function Position:Restore()
    placed = false
    pendingCombat = false
end

function Position:Initialize()
    Frames:RegisterHandler("position", function(frame)
        Position:Apply(frame)
    end, function(frame)
        Position:Restore(frame)
    end)

    -- After a native drag or resize. Not only the leader: the grabber of a
    -- docked tab resizes the leader and then reports the child.
    if type(_G.FCF_SavePositionAndDimensions) == "function" then
        hooksecurefunc("FCF_SavePositionAndDimensions", function(frame)
            if placing or not PC.Config.positionEnabled or PlayerIsDragging() then return end
            if not (Position:IsLeader(frame) or (frame and frame.isDocked)) then return end
            Position:CaptureCurrent()
        end)
    end

    local function ClearClamps()
        if not PC.Config.enabled or not PC.Config.edgeToEdge then return end
        if not PC.Skin or not PC.Skin.ClearClampFor then return end
        Frames:Each(function(frame) PC.Skin.ClearClampFor(frame) end)
    end

    -- Leaving Edit Mode: learn where the window ended up, a frame later once it
    -- has settled. Edit Mode moves never pass through
    -- FCF_SavePositionAndDimensions. `editing` stays set until the read, so
    -- nothing re-asserts the old spot over the new one.
    local function LearnFromEditMode()
        _G.C_Timer.After(0, function()
            if PC.Config.enabled and PC.Config.positionEnabled then
                Position:CaptureCurrent()
            end
            editing = false
        end)
    end

    PeaversCommons.Events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        ClearClamps()
        Position:Reassert()
    end)

    if _G.EventRegistry and type(_G.EventRegistry.RegisterCallback) == "function" then
        for _, moment in ipairs({ "EditMode.Enter", "EditMode.Exit" }) do
            pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, moment, ClearClamps, Position)
        end
        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
            "EditMode.Enter", function() editing = true end, Position)
        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry,
            "EditMode.Exit", LearnFromEditMode, Position)
    end

    -- The moments the client re-lays its chat windows out.
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
        PeaversCommons.Events:RegisterEvent(event, function() Position:Reassert() end)
    end

    PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if not pendingCombat then return end
        pendingCombat = false
        Position:Apply(nil, true)
        ClearClamps()
    end)
end

return Position
