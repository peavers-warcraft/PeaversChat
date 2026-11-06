--------------------------------------------------------------------------------
-- Guild adverts
--
-- Hides guild recruitment: the "<Ascend> is recruiting for Mythic progression,
-- raid times Tue/Thu 8-11 ST, /w for info" that fills Trade, General and
-- LookingForGroup, the charter signature requests on Classic, and the invite
-- whispers strangers send to every new character.
--
-- Off by default. A filter that hides other people's messages has to be
-- chosen; a line that never arrives cannot tell you it was hidden.
--
-- Two ways a line goes:
--
--  1. A word on the list. Out of the box that is "recruit", which catches
--     recruiting and recruitment, and "<*>", which is any name in angle
--     brackets - the way every guild writes its own name. Either one hides the
--     line by itself. The list is the player's: /pchat ads add and remove edit
--     it, and a * matches anything, so "lf* raiders" is one entry.
--
--  2. Enough evidence. An advert does not have to use a listed word - "Semi-
--     hardcore guild LF dps for Mythic, raid times Tue/Thu, Discord required"
--     has none - so a line is also read for different kinds of evidence: the
--     word guild, asking for members, a weekly raid schedule, progression, the
--     guild talking about itself as "we". Each kind is counted once however
--     often it repeats, and the line goes only when enough kinds turn up
--     together, because any one of them alone is ordinary chat: "guild" is in
--     "my guild killed Queen", and a pug LFM carries a start time. A Guild
--     Finder link and a request to sign a charter are decisive on their own.
--
-- Somebody looking for a guild ("LF guild, 640 resto shaman") scores as a
-- person talking and is left alone by the second route - what gives an advert
-- away is a guild describing itself: "we", "our", a name in brackets, a link.
-- A listed word still hides it; that is what the list is for.
--
-- Never hidden, whatever it says:
--
--  * Anything from yourself, a friend, a Battle.net friend, a guildmate or
--    somebody in your group. Your own guild's recruiter posting in Trade is
--    somebody you know.
--  * A GM.
--  * Anything in a channel whose name says it is for recruitment - Classic's
--    GuildRecruitment - because joining that channel is asking for exactly this.
--  * Guild, officer, party, raid, instance, community and Battle.net chat, which
--    are not filtered at all.
--  * A whisper while whispers open in their own tab. The client opens that tab
--    before any filter runs, so hiding the line would leave an empty tab named
--    after a stranger, which is worse than the advert.
--
-- Nothing disappears unseen. Every hidden line is kept for the session, with
-- the evidence that hid it, and /pchat ads opens them in the copy window - so a
-- line hidden by mistake is something you can find, not a message that never
-- arrived.
--
-- Cost: a line that mentions no guild, no recruiting, no charter, no listed
-- word and carries no angle bracket or club link costs one lower() and a
-- handful of plain finds.
-- The client is asked who the sender is to you only once a line has already
-- read as an advert, and each line is judged once however many chat windows it
-- is delivered to.
--------------------------------------------------------------------------------

local _, PC = ...

local GuildAds = {}
PC.GuildAds = GuildAds

local PeaversCommons = _G.PeaversCommons

local find, match, gmatch, gsub, lower = string.find, string.match, string.gmatch, string.gsub, string.lower

local IsSecret = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil

--------------------------------------------------------------------------------
-- The word list
--------------------------------------------------------------------------------

local function Trim(text)
    return match(tostring(text or ""), "^%s*(.-)%s*$")
end

-- Every pattern character but *, which is the one wildcard the list offers.
local function Escape(text)
    return (gsub(text, "[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"))
end

local compiled, compiledFrom = {}, nil

--- The saved list, turned into something cheap to search with. Rebuilt when
--- the list is edited, or replaced wholesale by /pchat defaults or a reset.
local function Words()
    local words = PC.Config.guildAdWords
    if words == compiledFrom then return compiled end

    compiled, compiledFrom = {}, words
    if type(words) ~= "table" then return compiled end

    for _, word in ipairs(words) do
        local entry = lower(Trim(word))
        if entry ~= "" then
            local star = find(entry, "*", 1, true)
            compiled[#compiled + 1] = {
                label = entry,
                plain = not star and entry or nil,
                pattern = star and (gsub(Escape(entry), "%*", ".-")) or nil,
                -- The literal text before the first *, which the cheap bail can
                -- look for. Empty means the entry starts with a wildcard and
                -- every line has to be read.
                lead = star and entry:sub(1, star - 1) or entry,
            }
        end
    end
    return compiled
end

function GuildAds:ListWords()
    local labels = {}
    for _, entry in ipairs(Words()) do labels[#labels + 1] = entry.label end

    PeaversCommons.Utils.Print(PC, #labels == 0
        and "No words on the list - only the evidence rules are hiding adverts."
        or ("Hidden on sight: %s"):format(table.concat(labels, "  ")))
    print("  /pchat ads add <word>  /pchat ads remove <word>  - a * matches anything, so <*> is any name in angle brackets")
end

function GuildAds:AddWord(word)
    word = lower(Trim(word))
    -- Nothing but wildcards would match every line in every filtered channel.
    if gsub(word, "[%*%s]", "") == "" then
        PeaversCommons.Utils.Print(PC, "Usage: /pchat ads add <word or phrase>, with * for anything")
        return
    end

    local words = PC.Config.guildAdWords
    if type(words) ~= "table" then words = {} end
    for _, existing in ipairs(words) do
        if lower(Trim(existing)) == word then
            PeaversCommons.Utils.Print(PC, ('"%s" is already on the list.'):format(word))
            return
        end
    end

    -- A new table rather than an insert, so Words() sees a different list and
    -- rebuilds, and so a list still shared with the defaults is never edited.
    local copy = {}
    for i, existing in ipairs(words) do copy[i] = existing end
    copy[#copy + 1] = word
    PC.Config.guildAdWords = copy
    if PC.Config.Save then PC.Config:Save() end

    PeaversCommons.Utils.Print(PC, ('Lines containing "%s" are hidden from now on.'):format(word))
end

function GuildAds:RemoveWord(word)
    word = lower(Trim(word))
    local copy, removed = {}, false
    for _, existing in ipairs(PC.Config.guildAdWords or {}) do
        if lower(Trim(existing)) == word then
            removed = true
        else
            copy[#copy + 1] = existing
        end
    end

    if not removed then
        PeaversCommons.Utils.Print(PC, ('"%s" is not on the list. /pchat ads words shows it.'):format(word))
        return
    end

    PC.Config.guildAdWords = copy
    if PC.Config.Save then PC.Config:Save() end
    PeaversCommons.Utils.Print(PC, ('"%s" taken off the list.'):format(word))
end

--------------------------------------------------------------------------------
-- Reading a line
--------------------------------------------------------------------------------

-- Hidden at this score or above. A listed word, a Guild Finder link or a
-- charter request scores 10 by itself; everything else has to add up.
local THRESHOLD = 6

-- Something has to be one of these before any other work is done. Lowercase,
-- searched plainly. The words for guild and recruiting are here in the main EU
-- languages too, so a German or French advert is caught by the same rules,
-- though the supporting evidence below is read in English.
local TRIGGERS = {
    "guild", "gilde", "gilda", "hermandad", "ильди",
    "recruit", "recrut", "rekrut", "reclut", "набор", "Набор",
    "charter", "<", "|hclub", "inviting",
    -- An advert for a raid team rather than a guild can mention neither, but it
    -- always asks for raiders or members, or gives its days.
    "raiders", "members", "raid times", "raid days", "raid nights", "aotc",
}

-- The client's own link types: a Guild Finder posting, and a community invite.
local FINDER_LINK = "|hclubfinder:"
local TICKET_LINK = "|hclubticket:"

local GUILD_WORDS = { "guild", "gilde", "gilda", "hermandad", "ильди" }
-- "Inviting" is how an advert is written when it is not written as
-- "recruiting"; a pug says "inv" or "LF", not "inviting new and returning".
local RECRUIT_WORDS = { "recruit", "recrut", "rekrut", "reclut", "набор", "Набор", "inviting" }

-- The word after "looking for", "lf" or "seeking" that makes it a call for
-- members rather than for a tank for tonight. Roles are deliberately absent:
-- "LF tank" is how every pug is written.
local MEMBER_WORDS = {
    more = true, new = true, active = true, few = true, some = true,
    like = true, players = true, members = true, people = true, raiders = true,
    folks = true, friends = true, chill = true, friendly = true, casual = true,
    social = true, experienced = true, dedicated = true, skilled = true,
    mature = true, adult = true, adults = true, fun = true, good = true,
}

local ASKING = {
    "accepting", "open spots", "spots open", "spots available",
    "taking applications", "applications open", "apply",
}

local JOINING = {
    "/w ", "whisper", "/msg", "msg me", "pm me", "dm me", "pst",
    "invit", "join us", "join our", "come join", "join now", "%f[%a]inv%f[%A]",
}

local SCHEDULE = { "raid times", "raid days", "raid nights", "raid schedule", "raiding days", "server time" }

local DAYS = {
    mon = true, monday = true, tue = true, tues = true, tuesday = true,
    wed = true, weds = true, wednesday = true, thu = true, thur = true,
    thurs = true, thursday = true, fri = true, friday = true,
    sat = true, saturday = true, sunday = true,
}

local PROGRESS = {
    "aotc", "cutting edge", "%f[%a]ce%f[%A]", "progression", "%f[%a]prog%f[%A]",
    "%d+/%d+%s*[nhm]%f[%A]", "mythic raid", "raiding", "raid team", "core team",
    "roster", "m%+ team", "push keys", "key push",
}

local SOCIAL = {
    "discord", "guild bank", "repairs", "perks", "leveling", "levelling",
    "social", "family", "all levels", "all classes", "welcome", "returning",
    "new home", "community", "events", "casual", "hardcore", "friendly",
    "chill", "vibes", "18+",
}

local WE = { "%f[%a]we%f[%A]", "%f[%a]we're%f[%A]", "%f[%a]our%f[%A]", "%f[%a]us%f[%A]" }

-- Somebody asking for a guild rather than offering one.
local SEEKING = {
    "%f[%a]lf%s+guild", "%f[%a]lf%s+%a+%s+guild",
    "looking for%s+guild", "looking for%s+%a+%s+guild",
    "seeking%s+guild", "seeking%s+%a+%s+guild",
    "any%s+guilds?%s+recruit", "need%s+guild", "need%s+%a+%s+guild",
}

local function AnyPlain(text, list)
    for i = 1, #list do
        if find(text, list[i], 1, true) then return true end
    end
    return false
end

local function AnyPattern(text, list)
    for i = 1, #list do
        if find(text, list[i]) then return true end
    end
    return false
end

--- The line as it reads on screen: colours, textures, atlas markup and raid
--- target icons taken out, and every hyperlink replaced by its display text, so
--- "[Guild: Ascend]" is read as words and an item link is read as its name.
local function Readable(msg)
    local text = gsub(msg, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    text = gsub(text, "|H.-|h(.-)|h", "%1")
    text = gsub(text, "|T.-|t", "")
    text = gsub(text, "|A.-|a", "")
    text = gsub(text, "{.-}", " ")
    return text
end

GuildAds.Readable = Readable

local function HasGuildName(text)
    for name in gmatch(text, "<([^<>]+)>") do
        if #name <= 32 and find(name, "%a") then return true end
    end
    return false
end

local function HasWeeklySchedule(text)
    if AnyPlain(text, SCHEDULE) then return true end

    local first
    for word in gmatch(text, "%a+") do
        if DAYS[word] then
            if first and first ~= word then return true end
            first = first or word
        end
    end
    return false
end

local function AsksForMembers(text)
    for _, lead in ipairs({ "looking for%s+(%a+)", "%f[%a]lf%s+(%a+)", "seeking%s+(%a+)" }) do
        for word in gmatch(text, lead) do
            if MEMBER_WORDS[word] then return true end
        end
    end
    return AnyPlain(text, ASKING)
end

--- Every kind of evidence the line carries, in the order the log prints them,
--- and the score they add up to. Nil when the line mentions nothing that could
--- make it an advert, which is nearly every line.
---
--- Pure string work: never touches a widget or asks the client anything.
local function Evidence(msg)
    local raw = lower(msg)
    local words = Words()

    local triggered = false
    for i = 1, #TRIGGERS do
        if find(raw, TRIGGERS[i], 1, true) then triggered = true break end
    end
    if not triggered then
        for i = 1, #words do
            local lead = words[i].lead
            if lead == "" or find(raw, lead, 1, true) then triggered = true break end
        end
    end
    if not triggered then return nil, 0 end

    -- Recruit-a-Friend is a game system, not a guild.
    local said = " " .. gsub(lower(Readable(msg)), "recruit[%s%-]*a[%s%-]*friend", "raf") .. " "

    local found, score = {}, 0
    local function Note(label, weight)
        found[#found + 1] = label
        score = score + weight
    end

    -- Against the line as written, before the articles come out below, so a
    -- listed phrase matches what somebody would actually type.
    for i = 1, #words do
        local entry = words[i]
        if (entry.plain and find(said, entry.plain, 1, true))
            or (entry.pattern and find(said, entry.pattern)) then
            Note(('"%s" from your word list'):format(entry.label), 10)
            break
        end
    end

    -- Articles out, so "looking for a few" and "LF a guild" read the same as
    -- the version without one.
    local text = gsub(said, "%f[%a]an?%f[%A]", "")
    text = gsub(text, "%f[%a]the%f[%A]", "")
    text = gsub(text, "%s+", " ")

    local link = false
    if find(raw, FINDER_LINK, 1, true) then Note("a Guild Finder link", 10) link = true end
    if find(raw, TICKET_LINK, 1, true) then Note("a community invite link", 4) link = true end
    if find(text, "charter", 1, true) and find(text, "sign", 1, true) then
        Note("asking for charter signatures", 10)
    end
    if AnyPlain(text, RECRUIT_WORDS) then Note("recruiting", 3) end

    local named = HasGuildName(text)
    if named then Note("a <guild name>", 2) end
    local guild = AnyPlain(text, GUILD_WORDS)
    if guild then Note("the word guild", 2) end
    if AsksForMembers(text) then
        -- A guild asking for members is very nearly the definition, so the
        -- pair is worth more than the two apart.
        Note("asking for members", (guild or named) and 3 or 2)
    end
    if HasWeeklySchedule(text) then Note("a weekly raid schedule", 2) end
    if AnyPattern(text, JOINING) then Note("how to join", 1) end
    if AnyPattern(text, PROGRESS) then Note("progression", 1) end
    if AnyPlain(text, SOCIAL) then Note("selling the guild", 1) end

    local we = AnyPattern(text, WE)
    if we then Note("the guild as we/our", 1) end

    -- Somebody looking for a guild, with nothing about the line that sounds
    -- like a guild describing itself.
    if score < 10 and not (we or named or link) and AnyPattern(text, SEEKING) then
        return found, 0
    end

    return found, score
end

GuildAds.Evidence = Evidence

--- Whether the text alone reads as an advert. For the case and for anybody
--- asking why a line went.
function GuildAds:IsAdvert(msg)
    if type(msg) ~= "string" then return false end
    local _, score = Evidence(msg)
    return score >= THRESHOLD
end

--------------------------------------------------------------------------------
-- Who sent it
--
-- Only asked once the text has already read as an advert, so an ordinary line
-- costs no client calls at all.
--------------------------------------------------------------------------------

local playerGUID

local function KnownSender(guid)
    if type(guid) ~= "string" or guid == "" then return false end

    if not playerGUID and type(_G.UnitGUID) == "function" then
        playerGUID = _G.UnitGUID("player")
    end
    if guid == playerGUID then return true end

    local friends = _G.C_FriendList
    if friends and type(friends.IsFriend) == "function" and friends.IsFriend(guid) then return true end

    if type(_G.IsGuildMember) == "function" and _G.IsGuildMember(guid) then return true end

    local bnet = _G.C_BattleNet
    if bnet and type(bnet.GetGameAccountInfoByGUID) == "function"
        and bnet.GetGameAccountInfoByGUID(guid) then
        return true
    end

    if type(_G.IsGUIDInGroup) == "function" and _G.IsGUIDInGroup(guid) then return true end

    return false
end

local function WhispersInline()
    local getter = _G.GetCVar or (_G.C_CVar and _G.C_CVar.GetCVar)
    if type(getter) ~= "function" then return true end
    local mode = getter("whisperMode")
    return mode == nil or mode == "inline"
end

--------------------------------------------------------------------------------
-- What was hidden
--------------------------------------------------------------------------------

local KEPT = 100
local hidden = {}
local hiddenCount = 0

local WHERE = {
    CHAT_MSG_SAY = "Say",
    CHAT_MSG_YELL = "Yell",
    CHAT_MSG_WHISPER = "Whisper",
}

local function Remember(event, author, channelName, msg, found)
    hiddenCount = hiddenCount + 1

    local where = WHERE[event]
        or (type(channelName) == "string" and channelName ~= "" and channelName)
        or "Channel"

    hidden[#hidden + 1] = {
        at = type(_G.date) == "function" and _G.date("%H:%M") or "",
        where = where,
        who = type(author) == "string" and author or "?",
        text = Readable(msg),
        why = table.concat(found, ", "),
    }
    if #hidden > KEPT then table.remove(hidden, 1) end

    -- Told once, ever, the first time it matters: at the moment a line has gone
    -- missing is when somebody needs to know where it went. Deferred, so the
    -- notice is not written into a chat frame from inside another frame's
    -- message filter.
    local cfg = PC.Config
    if not cfg.guildAdsNoticed then
        cfg.guildAdsNoticed = true
        if cfg.Save then cfg:Save() end
        local say = function()
            print("|cff3abdf7PeaversChat|r hid a guild advert in " .. where
                .. ". |cffffffff/pchat ads|r shows everything it hides and why; "
                .. "|cffffffff/pchat ads off|r turns it off.")
        end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, say) else say() end
    end
end

function GuildAds:Count()
    return hiddenCount
end

function GuildAds:Show()
    if #hidden == 0 then
        PeaversCommons.Utils.Print(PC, PC.Config.hideGuildAds
            and "No guild adverts hidden since you logged in."
            or "Guild adverts are not being hidden. /pchat ads on starts.")
        return
    end

    local lines = {}
    for i = #hidden, 1, -1 do
        local entry = hidden[i]
        lines[#lines + 1] = ("%s [%s] %s: %s"):format(entry.at, entry.where, entry.who, entry.text)
        lines[#lines + 1] = "    hidden for: " .. entry.why
    end

    local title = hiddenCount > #hidden
        and ("Hidden guild adverts - newest %d of %d"):format(#hidden, hiddenCount)
        or ("Hidden guild adverts - %d"):format(#hidden)

    PC.Copy:Show(title, table.concat(lines, "\n"))
end

--------------------------------------------------------------------------------
-- The filter
--
-- The same discipline as the URL filter: called through pcall, counting its own
-- failures, and switching itself off after a handful. An advert left on screen
-- is a nuisance; a message filter that throws costs the message.
--------------------------------------------------------------------------------

local EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER",
}

local failures = 0
local FAILURE_LIMIT = 5
local surrendered = false

local function NoteFailure(err)
    failures = failures + 1

    if PC.Config.debugMode then
        print("|cff3abdf7PeaversChat|r: guild advert filter error: " .. tostring(err))
    end

    if failures >= FAILURE_LIMIT and not surrendered then
        surrendered = true
        GuildAds:Sync()
        print("|cff3abdf7PeaversChat|r: no longer hiding guild adverts - the filter "
            .. "errored " .. FAILURE_LIMIT .. " times and chat matters more. "
            .. "/pchat ads on tries again.")
    end
end

local function Judge(event, msg, author, channelName, flags, channelBase, guid)
    -- Retail never passes a filter a value it cannot read; this is for a client
    -- that does, where comparing a secret is an error rather than a miss.
    if IsSecret and (IsSecret(msg) or IsSecret(author) or IsSecret(flags)
        or IsSecret(channelBase) or IsSecret(channelName) or IsSecret(guid)) then
        return false
    end

    local found, score = Evidence(msg)
    if score < THRESHOLD then return false end

    if flags == "GM" or flags == "DEV" then return false end
    if event == "CHAT_MSG_CHANNEL" and type(channelBase) == "string"
        and find(lower(channelBase), "recruit", 1, true) then
        return false
    end
    if event == "CHAT_MSG_WHISPER" and not WhispersInline() then return false end
    if KnownSender(guid) then return false end

    Remember(event, author, channelName, msg, found)
    return true
end

-- The client delivers each line once per chat window showing that channel. The
-- line is judged on the first delivery and the verdict reused for the rest, so
-- it is neither worked out nor logged twice.
local lastLine, lastMsg, lastAuthor, lastVerdict = nil, nil, nil, false

local function Filter(_, event, msg, author, _, channelName, _, flags, _, _, channelBase, _, lineID, guid)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.hideGuildAds or surrendered then return false end
    if type(msg) ~= "string" then return false end
    if IsSecret and (IsSecret(msg) or IsSecret(lineID) or IsSecret(author)) then return false end

    if type(lineID) == "number" then
        if lineID == lastLine then return lastVerdict end
    elseif msg == lastMsg and author == lastAuthor then
        return lastVerdict
    end

    local ok, hide = pcall(Judge, event, msg, author, channelName, flags, channelBase, guid)
    if not ok then
        NoteFailure(hide)
        hide = false
    end

    lastLine = type(lineID) == "number" and lineID or nil
    lastMsg, lastAuthor, lastVerdict = msg, author, hide and true or false
    return lastVerdict
end

--------------------------------------------------------------------------------
-- Registration
--
-- Off means the filter is gone from the client's table, not that it runs and
-- declines - for the same reason as the URL filter: "is this addon what is
-- wrong with my chat?" cannot be answered while it is still being called.
--------------------------------------------------------------------------------

local installed = false

function GuildAds:IsInstalled()
    return installed
end

function GuildAds:Sync()
    local wanted = PC.Config.enabled and PC.Config.hideGuildAds and not surrendered

    if wanted and not installed then
        if type(_G.ChatFrame_AddMessageEventFilter) ~= "function" then return end
        for i = 1, #EVENTS do
            _G.ChatFrame_AddMessageEventFilter(EVENTS[i], Filter)
        end
        installed = true
    elseif not wanted and installed then
        if type(_G.ChatFrame_RemoveMessageEventFilter) ~= "function" then return end
        for i = 1, #EVENTS do
            _G.ChatFrame_RemoveMessageEventFilter(EVENTS[i], Filter)
        end
        installed = false
    end
end

--- Switched on by hand, which is also the way back from having surrendered.
function GuildAds:SetEnabled(on)
    PC.Config.hideGuildAds = on and true or false
    if PC.Config.Save then PC.Config:Save() end
    if on then failures, surrendered = 0, false end
    self:Sync()
end

function GuildAds:Initialize()
    self:Sync()
end

return GuildAds
