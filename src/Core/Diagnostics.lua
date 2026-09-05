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

    print(("  PeaversChat URL filter: %s"):format(
        PC.Links:IsInstalled() and "installed"
        or (PC.Links:HasSurrendered() and "removed after repeated errors" or "not installed")))

    print("  A message counted above that you never saw on screen was delivered "
        .. "by the client and dropped after that.")
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
