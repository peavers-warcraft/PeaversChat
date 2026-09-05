--------------------------------------------------------------------------------
-- Links
--
-- Makes a URL somebody typed in chat clickable, which the game has never done.
--
-- The interesting problem is not finding URLs, it is not finding things that
-- are not URLs. Chat is full of text that looks like a domain if you squint -
-- "ok.thanks", "3.5", "wtf.no" - and a chat window that turns every sentence
-- into blue brackets is worse than one that does nothing. So:
--
--  * The message is walked one whitespace-separated token at a time rather than
--    with a pattern applied to the whole string. Overlapping patterns on a
--    whole message is where every homegrown URL matcher eventually eats an item
--    link, and it is impossible to review.
--  * A token containing a pipe is skipped outright. That is every item link,
--    achievement, spell, colour run and texture escape the client can emit, in
--    one test, and it means this code can never damage one.
--  * A bare host with no scheme, no www. and no path has to end in a top-level
--    domain from the list below. That is the only rule that stops "ok.thanks"
--    while still catching "wowhead.com".
--  * Trailing punctuation is peeled off the end and put back after the link, so
--    "have you seen www.example.com?" links the site and not the question mark.
--
-- Clicking one opens the copy window rather than the browser, because an addon
-- cannot open a browser. The URL comes back selected, so the click-to-paste is
-- click, Ctrl+C, Escape.
--
-- Cost: one plain find on every chat message, which bails immediately unless
-- the message contains a dot or an at-sign. Nothing runs per frame.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Links = {}
PC.Links = Links

local Frames = PC.Frames

local format, find, match, gsub = string.format, string.find, string.match, string.gsub

-- issecretvalue only exists from 12.0. Chat text is not restricted data today,
-- but a string that turns out to be secret would make find() a hard error inside
-- a message filter, which takes the message with it.
local IsSecret = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil

--------------------------------------------------------------------------------
-- What counts as a URL
--------------------------------------------------------------------------------

-- Only consulted for a bare host - "example.com" with no scheme, no www. and no
-- path. Anything with a scheme, a www., an @ or a slash is already unambiguous.
--
-- Deliberately short, and deliberately missing some real ones. A country code
-- that is also an English word turns ordinary chat into links: ".no" makes
-- "yeah.no" a website, and ".me", ".it" and ".us" do the same to "trust.me",
-- "do.it" and "join.us". Those are left out on purpose. The cost is that a bare
-- "example.me" has to be selected by hand; the cost of the other choice is
-- every third sentence in guild chat turning blue.
--
-- The ones that matter and are missing here are still caught by the rules
-- above: "discord.gg/abc" has a path, "eu.forums.blizzard.com/x" has a path,
-- anything typed with https:// or www. has a scheme.
local TLDS = {
    com = true, net = true, org = true, edu = true, gov = true, info = true,
    io = true, co = true, tv = true,
    dev = true, app = true, xyz = true, link = true, wiki = true, blog = true,
    uk = true, ca = true, au = true, nz = true, de = true, fr = true,
    es = true, nl = true, se = true, dk = true, fi = true,
    pl = true, ru = true, eu = true, br = true, jp = true, kr = true, cn = true,
}

local function LooksLikeUrl(body)
    -- scheme://rest
    if match(body, "^%a[%w%+%-%.]*://%S+$") then return true end

    -- www.anything
    if match(body, "^www%.[%w_%-]+%.%a") then return true end

    -- somebody@somewhere.tld
    if match(body, "^[%w%._%%%+%-]+@[%w%.%-]+%.%a%a+$") then return true end

    -- 10.0.0.1, optionally with a port
    if match(body, "^%d+%.%d+%.%d+%.%d+$") then return true end
    if match(body, "^%d+%.%d+%.%d+%.%d+:%d+$") then return true end

    -- host.tld/path - the slash is what makes this unambiguous
    if match(body, "^[%w%-%_%.]+%.%a%a+/") then return true end

    -- Bare host. The TLD has to be one we recognise.
    local tld = match(body, "^[%w%-%_%.]+%.(%a%a+)$")
    if tld and TLDS[tld:lower()] then return true end

    return false
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

-- Rebuilt by Refresh rather than computed per URL, so a message with five links
-- in it does no string.format work at all.
local colorPrefix = "|cff818cf8"
local useBrackets = true

function Links:Refresh()
    local c = PC.Config.urlColor or { r = 0.506, g = 0.549, b = 0.973 }
    colorPrefix = format("|cff%02x%02x%02x",
        math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
    useBrackets = PC.Config.urlBrackets ~= false
end

local function Wrap(url)
    local display = useBrackets and ("[" .. url .. "]") or url
    return colorPrefix .. "|Hurl:" .. url .. "|h" .. display .. "|h|r"
end

--- Returns a replacement for one whitespace-delimited token, or nil to leave it
--- exactly as it was.
local function Linkify(token)
    -- Any pipe means the client put this here: an item link, a colour run, a
    -- texture escape. Never ours to touch.
    if find(token, "|", 1, true) then return nil end

    -- Peel the punctuation off both ends and put it back afterwards, so
    -- "(www.example.com)" links the site rather than the brackets, and "seen
    -- www.example.com?" does not link the question mark. The pattern takes the
    -- longest run of opening punctuation, then the shortest body whose
    -- remainder is closing punctuation all the way to the end of the token.
    local lead, body, trail = match(token, "^([%(%[%{\"']*)(.-)([%.%,%;%:%!%?%)%]%}\"']*)$")
    if not body or body == "" then return nil end

    if not LooksLikeUrl(body) then return nil end

    return lead .. Wrap(body) .. trail
end

--------------------------------------------------------------------------------
-- The filter
--------------------------------------------------------------------------------

local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_AFK", "CHAT_MSG_DND",
    "CHAT_MSG_SYSTEM",
}

local function Filter(_, _, msg, ...)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.urlLinks then return false end
    if type(msg) ~= "string" then return false end
    if IsSecret and IsSecret(msg) then return false end

    -- Cheap bail. A URL has to contain a dot or an at-sign, and a plain find is
    -- a memchr rather than a pattern match.
    if not find(msg, ".", 1, true) and not find(msg, "@", 1, true) then
        return false
    end

    local rewritten = gsub(msg, "%S+", Linkify)
    if rewritten ~= msg then
        return false, rewritten, ...
    end

    return false
end

--------------------------------------------------------------------------------
-- Clicking one
--------------------------------------------------------------------------------

local function OnHyperlinkEnter(self, link)
    if type(link) ~= "string" then return end
    local url = match(link, "^url:(.+)$")
    if not url then return end

    local tooltip = _G.GameTooltip
    if not tooltip then return end

    tooltip:SetOwner(self, "ANCHOR_CURSOR")
    tooltip:ClearLines()
    tooltip:AddLine(url, 1, 1, 1, true)
    tooltip:AddLine("Click to copy", 0.58, 0.58, 0.58)
    tooltip:Show()
end

local function OnHyperlinkLeave(_, link)
    if type(link) == "string" and match(link, "^url:") and _G.GameTooltip then
        _G.GameTooltip:Hide()
    end
end

local function Apply(frame)
    if frame.__pcHyperlinkHooked then return end
    if type(frame.HookScript) ~= "function" then return end

    frame.__pcHyperlinkHooked = true
    frame:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
    frame:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function Links:Initialize()
    self:Refresh()

    Frames:RegisterHandler("links", Apply)

    for i = 1, #EVENTS do
        ChatFrame_AddMessageEventFilter(EVENTS[i], Filter)
    end

    -- Clicking the link. The client routes every hyperlink in a chat frame
    -- through SetItemRef, including types it has never heard of, which is what
    -- makes a custom link type work at all.
    hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then return end
        local url = match(link, "^url:(.+)$")
        if url and PC.Copy then
            PC.Copy:Show("Link", url)
        end
    end)
end

return Links
