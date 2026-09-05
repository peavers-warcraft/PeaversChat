--------------------------------------------------------------------------------
-- Ultra Performance case: what PeaversChat costs while you play.
--
-- A chat addon has two places it can go wrong, and they are not the same place.
--
--   1. The message path. Every line that arrives in chat goes through whatever
--      filters are installed on it, and on a busy raid night that is hundreds a
--      minute. An addon that reformats each one, or runs a dozen patterns over
--      it, is doing that work forever.
--   2. The frame path. Skinning a chat window is cheap if you do it once and
--      expensive if you do it on every event the client fires - and the client
--      fires several every time a window is docked, resized, or the options
--      panel is opened.
--
-- So the claim under test is in three parts:
--
--   * A chat message costs *zero* client calls. The URL filter is pure string
--     work with a plain-substring bail at the front; it never touches a widget.
--   * Nothing runs per frame. There is no OnUpdate anywhere in the addon, which
--     is the kind of negative claim that rots quietly, so it is hunted for
--     rather than asserted: every frame the addon created is searched for a
--     handler and ticked for a simulated second.
--   * The recurring frame-path cost is switching tabs, and it is bounded.
--
-- The one-off cost of skinning the windows at login is reported in the notes
-- rather than the headline, because dividing a login by a second is a number
-- that means nothing.
--
-- Main.lua is not loaded: it needs PeaversCommons, which is a different addon.
-- The case wires the modules together in the same order Main.lua does, and that
-- order is asserted below so the two cannot drift apart silently.
--------------------------------------------------------------------------------

-- Not addon code: this runs in the harness's fengari VM (Lua 5.3), outside WoW,
-- against globals the runner injects. Linting it as a WoW addon is a category
-- error - HARNESS_LIB and ADDON_DIR come from the runner, `unpack` is
-- deliberately reassigned because fengari is 5.3, and the case overwrites
-- Blizzard globals on purpose to drive the code under test.
---@diagnostic disable: undefined-global, deprecated, duplicate-set-field, missing-fields

local Stubs = dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()

_G.unpack = _G.unpack or table.unpack

local Count = Stubs.Count

--------------------------------------------------------------------------------
-- Widgets that answer the questions this addon actually asks
--
-- The shared stub turns an unknown method into an inert counted no-op, which is
-- right for SetColorTexture and wrong for GetDrawLayer: the skin decides what to
-- take down by asking each region which layer it is in, and a stub that answers
-- "a function" makes every region look like chrome. Everything added here is
-- either a real read the addon branches on, or state it writes and reads back.
--
-- The prefix guard is the trap the harness README warns about, in its second
-- form. This addon stores its own state on Blizzard's widgets under __pc and
-- peavers prefixes, and in the game those read back nil until they are set.
-- Under the bare catch-all they read back as a function, every "have I done this
-- yet?" check answers yes, and the addon skips the work the case exists to
-- measure.
--------------------------------------------------------------------------------

local function IsOurs(key)
    return type(key) == "string"
        and (key:sub(1, 1) == "_" or key:sub(1, 4) == "__pc" or key:sub(1, 7) == "peavers")
end

local TextureMT = {}
TextureMT.__index = function(_, key)
    if IsOurs(key) then return nil end

    if key == "GetObjectType" then return function(self) return self._type or "Texture" end end
    if key == "GetDrawLayer" then return function(self) return self._layer end end
    if key == "IsShown" then return function(self) return self._shown end end
    if key == "GetAlpha" then return function(self) return self._alpha or 1 end end
    if key == "GetText" then return function(self) return self._text end end
    if key == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
    if key == "GetStringWidth" then
        return function(self) Count("GetStringWidth") return #(self._text or "") * 6 end
    end

    return function(self, ...)
        Count(key)
        if key == "SetText" then
            self._text = ...
        elseif key == "Show" then
            self._shown = true
        elseif key == "Hide" then
            self._shown = false
        elseif key == "SetShown" then
            self._shown = (...) and true or false
        elseif key == "SetAlpha" then
            self._alpha = ...
        end
    end
end

local function NewTexture(layer, objectType)
    return setmetatable({
        _layer = layer or "ARTWORK",
        _type = objectType or "Texture",
        _shown = true,
        _alpha = 1,
    }, TextureMT)
end

local FrameMT = {}
FrameMT.__index = function(_, key)
    if IsOurs(key) then return nil end

    if key == "GetName" then return function(self) return self._name end end
    if key == "GetID" then return function(self) return self._id or 0 end end
    if key == "GetParent" then return function(self) return self._parent end end
    if key == "IsShown" then return function(self) return self._shown end end
    if key == "GetAlpha" then return function(self) return self._alpha or 1 end end
    if key == "GetEffectiveScale" then return function() return 1 end end
    if key == "GetWidth" then return function(self) Count("GetWidth") return self._width or 400 end end
    if key == "GetHeight" then return function(self) Count("GetHeight") return self._height or 180 end end
    if key == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 14, "" end end
    if key == "GetScript" then return function(self, s) return self._scripts[s] end end
    if key == "GetAttribute" then return function(self, a) return self._attributes[a] end end
    if key == "GetRegions" then
        return function(self) return unpack(self._regions) end
    end
    if key == "CreateTexture" then
        return function(self, _, layer)
            Count("CreateTexture")
            local tex = NewTexture(layer)
            self._regions[#self._regions + 1] = tex
            return tex
        end
    end
    if key == "CreateFontString" then
        return function(self, _, layer)
            Count("CreateFontString")
            local fs = NewTexture(layer, "FontString")
            self._regions[#self._regions + 1] = fs
            return fs
        end
    end
    if key == "GetHighlightTexture" or key == "GetPushedTexture"
        or key == "GetNormalTexture" or key == "GetDisabledTexture" then
        return function(self)
            self._buttonTextures[key] = self._buttonTextures[key] or NewTexture("ARTWORK")
            return self._buttonTextures[key]
        end
    end

    return function(self, ...)
        Count(key)
        if key == "Show" then
            self._shown = true
        elseif key == "Hide" then
            self._shown = false
        elseif key == "SetShown" then
            self._shown = (...) and true or false
        elseif key == "SetAlpha" then
            self._alpha = ...
        elseif key == "SetWidth" then
            self._width = ...
        elseif key == "SetHeight" then
            self._height = ...
        elseif key == "SetScript" or key == "HookScript" then
            local script, fn = ...
            self._scripts[script] = fn
        end
    end
end

local createdFrames = {}

local function NewFrame(name, id, parent)
    local frame = setmetatable({
        _name = name,
        _id = id,
        _parent = parent,
        _shown = true,
        _alpha = 1,
        _scripts = {},
        _regions = {},
        _attributes = {},
        _buttonTextures = {},
    }, FrameMT)

    createdFrames[#createdFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

-- Anything the addon builds itself goes through CreateFrame, and everything
-- that does is a candidate for an OnUpdate later on.
_G.CreateFrame = function(_, name, parent)
    return NewFrame(name, 0, parent)
end

--------------------------------------------------------------------------------
-- A chat window
--
-- Three of Blizzard's own background textures per frame, because taking those
-- down is real work the skin does and leaving them out would flatter it.
--------------------------------------------------------------------------------

local MESSAGES = {
    "|cff8787edPeavers|r: has anyone got a link for the weakaura",
    "|Hchannel:Guild|h[G]|h |cff8787edPeavers|r: https://wago.io/abcdef here you go",
    "|cffa335ee|Hitem:19019::::::::80:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
    "|TInterface\\Icons\\INV_Misc_Coin_01:14|t You receive loot: 12 gold.",
    "Peavers hits Training Dummy for 48,231 Fire damage.",
}

local function NewChatFrame(index, windowName)
    local frame = NewFrame("ChatFrame" .. index, index)
    frame.name = windowName
    frame.isDocked = true

    for _, layer in ipairs({ "BACKGROUND", "BACKGROUND", "BORDER" }) do
        frame._regions[#frame._regions + 1] = NewTexture(layer)
    end

    frame.GetNumMessages = function() return #MESSAGES end
    frame.GetMessageInfo = function(_, i) return MESSAGES[((i - 1) % #MESSAGES) + 1] end

    local tab = NewFrame("ChatFrame" .. index .. "Tab", index)
    for _, layer in ipairs({ "BACKGROUND", "BORDER", "BORDER", "ARTWORK" }) do
        tab._regions[#tab._regions + 1] = NewTexture(layer)
    end
    tab.Text = NewTexture("OVERLAY", "FontString")
    tab.Text._text = windowName

    local editBox = NewFrame("ChatFrame" .. index .. "EditBox", index, frame)
    editBox._attributes.chatType = "SAY"
    editBox.chatFrame = frame
    editBox.header = NewTexture("OVERLAY", "FontString")
    for _, layer in ipairs({ "BACKGROUND", "BACKGROUND", "BORDER" }) do
        editBox._regions[#editBox._regions + 1] = NewTexture(layer)
    end
    frame.editBox = editBox

    local buttonFrame = NewFrame("ChatFrame" .. index .. "ButtonFrame", index, frame)
    buttonFrame._regions[#buttonFrame._regions + 1] = NewTexture("BACKGROUND")
    NewFrame("ChatFrame" .. index .. "ButtonFrameUpButton", index, buttonFrame)
    NewFrame("ChatFrame" .. index .. "ButtonFrameDownButton", index, buttonFrame)
    NewFrame("ChatFrame" .. index .. "ButtonFrameBottomButton", index, buttonFrame)

    frame.ScrollBar = NewFrame(nil, index, frame)
    frame.ScrollToBottomButton = NewFrame(nil, index, frame)

    return frame, tab
end

--------------------------------------------------------------------------------
-- The rest of the client
--------------------------------------------------------------------------------

_G.hooksecurefunc = function(name, fn)
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        fn(...)
    end
end

_G.PixelUtil = { GetNearestPixelSize = function() return 1 end }
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.ChatFontNormal = {}
_G.SetCVar = function() Count("SetCVar") end

_G.NUM_CHAT_WINDOWS = 3

_G.ChatTypeInfo = {
    SAY = { r = 1, g = 1, b = 1 },
    GUILD = { r = 0.25, g = 1, b = 0.25 },
    WHISPER = { r = 1, g = 0.5, b = 1 },
}

-- The client's own entry points. The addon hooks rather than replaces every one
-- of these, so they have to exist and they have to be callable.
_G.FCFTab_UpdateColors = function() end
_G.FCF_SelectDockFrame = function() end
_G.FCF_Tab_OnClick = function() end
_G.FCF_SetWindowName = function() end
_G.FCF_StartAlertFlash = function() end
_G.FCF_StopAlertFlash = function() end
_G.FCF_OpenTemporaryWindow = function() end
_G.FCF_OpenNewWindow = function() end
_G.FCF_DockFrame = function() end
_G.ChatEdit_UpdateHeader = function() end
_G.ChatEdit_ActivateChat = function() end
_G.SetItemRef = function() end

local filters = {}
_G.ChatFrame_AddMessageEventFilter = function(event, fn)
    filters[event] = filters[event] or {}
    table.insert(filters[event], fn)
end

-- The buttons the addon hides.
for _, name in ipairs({
    "ChatFrameMenuButton", "QuickJoinToastButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "CombatLogQuickButtonFrame_Custom",
}) do
    NewFrame(name, 0)
end

_G.EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }

-- Channel format strings, in the shape the enUS client ships them.
_G.CHAT_GUILD_GET = "|Hchannel:Guild|h[Guild]|h %s: "
_G.CHAT_OFFICER_GET = "|Hchannel:o|h[Officer]|h %s: "
_G.CHAT_PARTY_GET = "|Hchannel:party|h[Party]|h %s: "
_G.CHAT_PARTY_LEADER_GET = "|Hchannel:party|h[Party Leader]|h %s: "
_G.CHAT_RAID_GET = "|Hchannel:raid|h[Raid]|h %s: "
_G.CHAT_RAID_LEADER_GET = "|Hchannel:raid|h[Raid Leader]|h %s: "
_G.CHAT_RAID_WARNING_GET = "[Raid Warning] %s: "
_G.CHAT_INSTANCE_CHAT_GET = "|Hchannel:Battleground|h[Instance]|h %s: "
_G.CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:Battleground|h[Instance Leader]|h %s: "

-- Only the pieces of PeaversCommons these modules reach for.
local events = {}
_G.PeaversCommons = {
    Events = {
        RegisterEvent = function(_, event, handler)
            events[event] = events[event] or {}
            table.insert(events[event], handler)
        end,
    },
    Utils = { Print = function() end },
    Theme = {
        Colors = {
            bgBase = { 0.086, 0.086, 0.086, 0.97 },
            bgNested = { 0.110, 0.110, 0.110, 1 },
            border = { 0.176, 0.176, 0.176, 1 },
            borderHover = { 0.290, 0.290, 0.290, 1 },
            accent = { 0.506, 0.549, 0.973, 1 },
            text = { 1, 1, 1, 1 },
            textSec = { 0.725, 0.725, 0.725, 1 },
            textMuted = { 0.580, 0.580, 0.580, 1 },
        },
        Hairline = function(parent) return parent:CreateTexture(nil, "ARTWORK") end,
    },
}

local chatFrames, chatTabs = {}, {}
for i, windowName in ipairs({ "General", "Combat Log", "Whisper" }) do
    chatFrames[i], chatTabs[i] = NewChatFrame(i, windowName)
end
_G.SELECTED_DOCK_FRAME = chatFrames[1]

--------------------------------------------------------------------------------
-- The addon
--------------------------------------------------------------------------------

local PC = {}

-- Config.lua is not loaded: it builds a real ConfigManager out of
-- PeaversCommons. These are the same defaults, with every optional feature ON,
-- because a budget written against the cheap configuration is not a budget.
PC.Config = {
    enabled = true,
    background = true,
    bgColor = { r = 0.086, g = 0.086, b = 0.086 },
    bgAlpha = 0.60,
    border = true,
    borderColor = { r = 0.176, g = 0.176, b = 0.176 },
    padding = 4,
    fontSize = 13,
    fontOutline = "NONE",
    shadow = true,
    fading = false,
    timeVisible = 120,
    maxLines = 1000,
    styleTabs = true,
    tabFontSize = 12,
    tabUppercase = true,
    tabUnderline = true,
    tabTextColor = { r = 0.580, g = 0.580, b = 0.580 },
    tabSelectedColor = { r = 1, g = 1, b = 1 },
    accentColor = { r = 0.506, g = 0.549, b = 0.973 },
    styleEditBox = true,
    editBoxPosition = "bottom",
    editBoxHeight = 22,
    altArrowKeys = false,
    editBoxChannelColor = true,
    showMenuButton = false,
    showSocialButton = false,
    showScrollButtons = false,
    showBottomButton = true,
    showVoiceButtons = false,
    showCombatLogBar = false,
    urlLinks = true,
    urlColor = { r = 0.506, g = 0.549, b = 0.973 },
    urlBrackets = true,
    copyButton = true,
    copyStripColors = true,
    shortChannelNames = true,
    timestamps = "%H:%M ",
    debugMode = false,
    Save = function() end,
}

local function Load(path)
    return assert(loadfile(ADDON_DIR .. "/src/" .. path))("PeaversChat", PC)
end

Load("Core/Frames.lua")
Load("Core/Skin.lua")
Load("Core/Tabs.lua")
Load("Core/EditBox.lua")
Load("Core/Buttons.lua")
Load("Core/Links.lua")
Load("Core/Copy.lua")
Load("Core/Channels.lua")

--------------------------------------------------------------------------------
-- Login
--
-- Same order as Main.lua: every module registers itself as a Frames handler,
-- Frames runs them in registration order, and Skin has to be first because it
-- is the one that takes Blizzard's textures down.
--------------------------------------------------------------------------------

Stubs.ResetCounts()

PC.Skin:Initialize()
PC.Tabs:Initialize()
PC.EditBox:Initialize()
PC.Buttons:Initialize()
PC.Links:Initialize()
PC.Copy:Initialize()

PC.Frames:Initialize()
PC.Channels:Initialize()

local loginCalls = Stubs.TotalCalls()

assert(PC.Frames:Count() == 3, "the sweep adopted " .. PC.Frames:Count() .. " windows, expected 3")
assert(chatFrames[1].peaversBox, "ChatFrame1 was never skinned")
assert(chatTabs[1].peaversUnderline, "the tab was never restyled")
assert(chatFrames[1].editBox.peaversBox, "the edit box was never skinned")
assert(chatFrames[1].peaversCopyButton, "the copy button was never built")
assert(filters.CHAT_MSG_SAY, "no URL filter was installed")
assert(_G.CHAT_GUILD_GET:find("%[G%]"), "channel names were not abbreviated")
assert(_G.ChatFrameMenuButton:IsShown() == false, "the menu button is still on screen")
assert(chatFrames[1].peaversCopyButton:IsShown(), "the copy button is hidden")

--------------------------------------------------------------------------------
-- A chat message
--
-- The claim is that this costs the client nothing at all, so it is driven
-- through the real registered filter rather than a copy of it. Half the sample
-- contains a URL and half does not, which is roughly what chat looks like and
-- keeps the cheap early-bail from flattering the number.
--------------------------------------------------------------------------------

local SAMPLE = {
    "has anyone got a link for the weakaura",
    "check https://wago.io/abcdef for the import string",
    "pull in 3",
    "the guide is at wowhead.com/guide/season-of-discovery, read it",
    "ok.thanks that worked",
    "nice one",
    "www.warcraftlogs.com/reports/abc123 if you want the parse",
    "brb 2 min",
}

local function DeliverMessage(i)
    local text = SAMPLE[((i - 1) % #SAMPLE) + 1]
    for _, fn in ipairs(filters.CHAT_MSG_CHANNEL) do
        fn(chatFrames[1], "CHAT_MSG_CHANNEL", text, "Peavers", "Common", "5. LookingForGroup")
    end
end

local MESSAGES_PER_SECOND = 10

Stubs.ResetCounts()
for i = 1, 400 do DeliverMessage(i) end
local perMessage = Stubs.TotalCalls() / 400

-- The filter has to actually be doing the work, or the zero above is a zero
-- because nothing ran.
do
    local _, rewritten = filters.CHAT_MSG_CHANNEL[1](
        chatFrames[1], "CHAT_MSG_CHANNEL", "see www.example.com", "Peavers")
    assert(rewritten and rewritten:find("|Hurl:", 1, true),
        "the filter is installed but is not linking anything")
end

--------------------------------------------------------------------------------
-- Switching tabs
--
-- The recurring frame-path cost. Clicking a tab repaints the whole tab row,
-- which is the most expensive thing this addon does in response to something
-- you do more than once.
--------------------------------------------------------------------------------

local function SwitchTab(i)
    _G.SELECTED_DOCK_FRAME = chatFrames[((i - 1) % 3) + 1]
    _G.FCF_Tab_OnClick(chatTabs[((i - 1) % 3) + 1])
end

SwitchTab(1)

local TAB_SWITCHES_PER_SECOND = 1

Stubs.ResetCounts()
for i = 1, 200 do SwitchTab(i) end
local perTabSwitch = Stubs.TotalCalls() / 200

--------------------------------------------------------------------------------
-- The idle claim
--
-- Every frame the addon created, hunted for an OnUpdate. WoW does not tick a
-- hidden frame, so a shown frame with a handler is the only thing that could
-- cost anything while nothing is happening.
--------------------------------------------------------------------------------

local function IdleCallsPerSecond()
    local handlers = {}
    for _, frame in ipairs(createdFrames) do
        local fn = frame:GetScript("OnUpdate")
        if fn and frame:IsShown() then
            handlers[#handlers + 1] = { frame = frame, fn = fn }
        end
    end

    if #handlers == 0 then return 0, 0 end

    Stubs.ResetCounts()
    local step = 1 / 144
    for _ = 1, 144 do
        Stubs.time = Stubs.time + step
        for _, handler in ipairs(handlers) do
            handler.fn(handler.frame, step)
        end
    end
    return Stubs.TotalCalls(), #handlers
end

local idleCalls, handlerCount = IdleCallsPerSecond()

return {
    {
        name = "chat flowing, 10 messages/sec",
        callsPerFrame = 0,
        callsPerSecond = perMessage * MESSAGES_PER_SECOND,
        idleCallsPerSecond = 0,
        notes = string.format(
            "%.2f client calls per message: the URL filter is pure string work and never touches a widget",
            perMessage),
    },
    {
        name = "switching tabs, 1/sec",
        callsPerFrame = 0,
        callsPerSecond = perTabSwitch * TAB_SWITCHES_PER_SECOND,
        idleCallsPerSecond = 0,
        notes = string.format(
            "%.0f calls to repaint the whole tab row; %d calls to skin every window at login, once",
            perTabSwitch, loginCalls),
    },
    {
        name = "idle, chat on screen",
        callsPerFrame = 0,
        idleCallsPerSecond = idleCalls,
        notes = string.format("%d OnUpdate handlers installed anywhere in the addon", handlerCount),
    },
}
