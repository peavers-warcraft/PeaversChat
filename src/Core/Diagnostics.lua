--------------------------------------------------------------------------------
-- Diagnostics
--
-- Answers the one question that matters when chat stops working: did the
-- message arrive?
--
-- Everything else follows from that. If the client delivered a message and you
-- never saw it, something between the event and the screen ate it, and the list
-- of things that can do that is short and enumerable. If the client never
-- delivered it, no addon is responsible and the search has been in the wrong
-- place from the start.
--
-- The counting frame is deliberately its own CreateFrame with its own
-- RegisterEvent, not a message filter. A filter sits in the client's filter
-- table alongside every other addon's and is subject to the same ordering and
-- the same suspicion; a plain event frame sees what the client sent, whatever
-- the filters then do to it. That independence is the whole point.
--
-- It also counts how many filters are installed on each event, because "some
-- other addon has three filters on CHAT_MSG_PARTY" is the single most useful
-- sentence in a chat bug report and there is otherwise no way to find it out.
--
-- Off unless asked for. Nothing here runs until /pchat trace.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Diagnostics = {}
PC.Diagnostics = Diagnostics

-- The authored events - the ones that stopped arriving. CHAT_MSG_SYSTEM is
-- included precisely because it kept working: a report where it is the only
-- non-zero row says something very specific.
local WATCHED = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SYSTEM",
}

local IsSecret = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil

local watcher = nil
local counts = {}
local lastSeen = nil
local startedAt = nil

--------------------------------------------------------------------------------
-- Showing text safely
--------------------------------------------------------------------------------

--- Chat text is full of escape sequences, and this is a tool for looking at
--- them, so they are shown rather than rendered. A restricted value is named
--- rather than printed: passing one to string.format is a hard error, and an
--- error inside the diagnostic would be a poor joke.
local function Literal(text)
    if IsSecret and IsSecret(text) then return "<restricted by the client>" end
    if type(text) ~= "string" then return "<" .. type(text) .. ">" end

    local shown = text
    if #shown > 70 then shown = shown:sub(1, 70) .. "..." end
    return (shown:gsub("|", "||"))
end

--------------------------------------------------------------------------------
-- Watching
--------------------------------------------------------------------------------

function Diagnostics:IsActive()
    return watcher ~= nil and watcher:IsShown()
end

function Diagnostics:Start()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(_, event, message)
            counts[event] = (counts[event] or 0) + 1
            lastSeen = { event = event, text = message }
        end)
    end

    counts = {}
    lastSeen = nil
    startedAt = GetTime()

    -- Ask the URL hook to count the lines that reach it. The gap between that
    -- and the events counted here is the whole diagnosis: events with no passes
    -- means the client stopped before AddMessage and nothing in this addon can
    -- be responsible.
    PC.Links.passes = 0
    PC.Links.counting = true

    for i = 1, #WATCHED do
        pcall(watcher.RegisterEvent, watcher, WATCHED[i])
    end
    watcher:Show()

    print("|cff3abdf7PeaversChat|r: watching chat events. Run your key, then type "
        .. "/pchat trace again to see what arrived. /pchat trace off stops it.")
end

function Diagnostics:Stop()
    if watcher then
        watcher:UnregisterAllEvents()
        watcher:Hide()
    end
    PC.Links.counting = nil
    print("|cff3abdf7PeaversChat|r: stopped watching chat events.")
end

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

--- How many message filters are installed on an event. Anything above our own
--- count is another addon, which is worth knowing before somebody spends an
--- evening bisecting an addon list.
local function FilterCount(event)
    if type(_G.ChatFrame_GetMessageEventFilters) ~= "function" then return nil end

    local ok, filters = pcall(_G.ChatFrame_GetMessageEventFilters, event)
    if not ok or type(filters) ~= "table" then return 0 end

    local total = 0
    for _ in pairs(filters) do total = total + 1 end
    return total
end

function Diagnostics:Report()
    if not self:IsActive() then
        print("|cff3abdf7PeaversChat|r: not watching. /pchat trace starts it.")
        return
    end

    local elapsed = math.floor((GetTime() - (startedAt or GetTime())) + 0.5)
    print(("|cff3abdf7PeaversChat|r: %d seconds of chat events."):format(elapsed))

    local ours = PC.Links:IsInstalled() and 1 or 0
    local seenAny = false

    for i = 1, #WATCHED do
        local event = WATCHED[i]
        local count = counts[event]
        if count then
            seenAny = true
            local filters = FilterCount(event)
            local others = filters and math.max(0, filters - ours) or 0
            print(("  %s: %d arrived, %d filter(s) installed (%d not ours)")
                :format(event, count, filters or 0, others))
        end
    end

    if not seenAny then
        print("  nothing arrived at all. The client sent no chat messages in that "
            .. "time, so nothing between the event and the screen can be at fault.")
    end

    if lastSeen then
        print(("  last: %s  %s"):format(lastSeen.event, Literal(lastSeen.text)))
    end

    print(("  lines that reached our AddMessage hook: %d"):format(PC.Links.passes or 0))
    print("  --")
    print(("  chat handler replaced by this addon: %s"):format(
        PC.Links:IsInstalled() and "YES" or "no - the client's own is untouched"))
    print(("  PeaversChat URL hook: %s"):format(
        PC.Links:IsInstalled() and "installed"
        or (PC.Links:HasSurrendered() and "removed after repeated errors" or "not installed")))

    print("  A message counted above that you never saw on screen was delivered "
        .. "by the client and dropped after that.")
end

--------------------------------------------------------------------------------
-- Layout
--
-- Where the background is being drawn and what it hangs from. Written after a
-- tab-row background that stopped halfway across took two rounds to explain:
-- the tabs were parented into a scroll frame, and a scroll frame clips its
-- child, so the textures were cut off where the tabs were not. None of that is
-- visible from the outside, and all of it is one line of output.
--------------------------------------------------------------------------------

local function Named(widget)
    if not widget then return "none" end
    if type(widget.GetName) ~= "function" then return "unnamed" end
    return widget:GetName() or "unnamed"
end

function Diagnostics:Style()
    print("|cff3abdf7PeaversChat|r: chat window layout")

    local hosts = {}

    PC.Frames:Each(function(frame)
        local tab = PC.Frames:TabFor(frame)
        local parent = tab and type(tab.GetParent) == "function" and tab:GetParent() or nil
        local host = PC.Skin.StripHost(frame)

        if host then hosts[host] = true end

        local alpha = (host and type(host.GetAlpha) == "function" and host:GetAlpha()) or 1
        print(("  %s shown=%s strip=%dpx tab parent=%s host=%s alpha=%.2f drawn=%s"):format(
            Named(frame),
            tostring(frame:IsShown()),
            math.floor((PC.Skin.StripHeight and PC.Skin.StripHeight(frame) or 0) + 0.5),
            Named(parent),
            Named(host),
            alpha,
            (host and host.peaversStrip) and "yes" or "no"))
    end)

    local count = 0
    for _ in pairs(hosts) do count = count + 1 end
    print(("  %d distinct strip host(s). More than one means the background is "
        .. "drawn more than once and will look doubled where they overlap."):format(count))
end

function Diagnostics:Toggle(argument)
    argument = tostring(argument or ""):lower():gsub("%s", "")

    if argument == "off" then
        self:Stop()
    elseif self:IsActive() then
        self:Report()
    else
        self:Start()
    end
end

return Diagnostics
