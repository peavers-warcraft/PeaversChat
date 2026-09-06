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

    -- A method call rather than a direct one: Sync is defined further down,
    -- below the state it reads.
    self:Sync()
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

--- The rewrite, on its own so the hook has something to pcall that is not a
--- closure. Returns nil when the line is to be left exactly as it arrived.
local function Rewrite(text)
    -- A secret string can be stored and passed on but not searched, and find()
    -- on one is a hard error rather than a miss. By this point the client has
    -- resolved everything it was going to; this is the belt to that braces.
    if IsSecret and IsSecret(text) then return nil end

    -- Cheap bail. A URL has to contain a dot or an at-sign, and a plain find is
    -- a memchr rather than a pattern match.
    if not find(text, ".", 1, true) and not find(text, "@", 1, true) then
        return nil
    end

    local rewritten = gsub(text, "%S+", Linkify)
    if rewritten == text then return nil end
    return rewritten
end

--------------------------------------------------------------------------------
-- Failing safe
--
-- This runs on the way to the screen, so an error here would cost the line it
-- was called for. It is called through pcall and, more importantly, it counts
-- its own failures and switches itself off after a handful. A feature that has
-- proven it cannot run is worth less than chat, every time, and the player is
-- told once in plain words rather than left with silently degraded chat.
--------------------------------------------------------------------------------

local failures = 0
local FAILURE_LIMIT = 5
local surrendered = false

local function NoteFailure(err)
    failures = failures + 1

    if PC.Config.debugMode then
        print("|cff3abdf7PeaversChat|r: URL matcher error: " .. tostring(err))
    end

    if failures >= FAILURE_LIMIT and not surrendered then
        surrendered = true
        Links:Sync()
        print("|cff3abdf7PeaversChat|r: turning clickable URLs off - the link "
            .. "matcher errored " .. FAILURE_LIMIT .. " times and chat matters more. "
            .. "Re-enable it under /pchat once you have reported this.")
    end
end

--- Whether the matcher has given up on itself.
function Links:HasSurrendered()
    return surrendered
end

function Links:Resume()
    failures, surrendered = 0, false
    self:Sync()
end
--------------------------------------------------------------------------------
-- Where the rewrite happens
--
-- Beside the client's message path, not inside it.
--
-- Making a URL clickable means altering the chat line, and there are only three
-- places to do that. Two have been tried here and both stopped chat working in
-- instanced content: a ChatFrame_AddMessageEventFilter, and a wrapper on the
-- chat frame's own AddMessage. The second was worse, because a wrapped method
-- cannot be reliably unwrapped once another addon has hooked it too - so
-- turning the feature off did not undo it.
--
-- The third is the one Prat has used for fifteen years without this problem:
--
--   * We own a ScrollingMessageFrame of our own.
--   * We replace the global ChatFrame_MessageEventHandler, and when a message
--     arrives we call the client's original handler with our frame standing in
--     for the real one.
--   * Blizzard composes the line exactly as it always does and calls AddMessage
--     on our frame, which is ours to intercept because we made it.
--   * We rewrite the text and call the real frame's AddMessage ourselves.
--
-- No method on a Blizzard chat frame is ever replaced. The real frame is called
-- the way print() calls it - insecure addon code handing a string to a widget
-- method - which is a path that demonstrably works everywhere, including the
-- keys where the other two approaches did not.
--
-- The other property that matters is what "off" means. When the feature is off
-- this calls the client's original handler with the client's own frame and
-- returns its result, so the addon is not merely inert, it is absent. The
-- AddMessage wrapper could never promise that, and it is why this can be
-- trusted where that one could not.
--
-- Standing in for another frame has one visible cost, paid below: the client
-- decides whether to flash an unread tab by asking the frame it was given
-- whether it is shown, and the frame it was given is ours. See FlashIfUnread.
--------------------------------------------------------------------------------

local active = false
local installed = false
local originalHandler = nil

local proxy = nil
local captured = {}

-- Fields that must not be copied onto the proxy: the C-backed internals of a
-- ScrollingMessageFrame - its font string pool, its layout bookkeeping - which
-- corrupt the frame receiving them. The list is Prat's, which is where this was
-- found out the hard way.
local PROXY_FIELD_BLACKLIST = {
    fontStringPool = true,
    highlightTexturePool = true,
    visibleLines = true,
    isLayoutDirty = true,
    isDisplayDirty = true,
    scrollOffset = true,
    onDisplayRefreshedCallback = true,
    onScrollChangedCallback = true,
    onTextCopiedCallback = true,
    historyBuffer = true,
    messageInfoBuffer = true,
}

local function EnsureProxy()
    if proxy then return proxy end

    proxy = CreateFrame("ScrollingMessageFrame")
    if _G.Mixin and _G.ChatFrameMixin then
        pcall(_G.Mixin, proxy, _G.ChatFrameMixin)
    end
    proxy:Hide()

    -- Our frame, so this is ours to replace. Every line the client composes
    -- lands here instead of on screen.
    proxy.AddMessage = function(_, text, ...)
        captured[#captured + 1] = { text = text, count = select("#", ...), ... }
    end

    -- Always "shown", which suppresses the client's own unread-tab flash: it
    -- would otherwise flash this frame, which has no tab. FlashIfUnread puts it
    -- back for the real one.
    proxy.IsShown = function() return true end

    return proxy
end

--------------------------------------------------------------------------------
-- Standing in for a chat frame
--------------------------------------------------------------------------------

local mirrored = {}

--- Copy the real frame's own state onto the proxy, so the client's handler -
--- which reads things like messageTypeList and defaultLanguage off the frame it
--- is given - makes the same decisions it would have made for the real one.
local function Mirror(frame)
    for key in pairs(mirrored) do mirrored[key] = nil end

    for key, value in pairs(frame) do
        if type(value) ~= "function" and not PROXY_FIELD_BLACKLIST[key] then
            mirrored[key] = { had = proxy[key] ~= nil, value = proxy[key] }
            proxy[key] = value
        end
    end
end

local function Unmirror()
    for key, saved in pairs(mirrored) do
        if saved.had then proxy[key] = saved.value else proxy[key] = nil end
    end
    for key in pairs(mirrored) do mirrored[key] = nil end
end

--- The unread flash, put back. The client skipped its own because our stand-in
--- claims to be on screen, and a window that is genuinely not on screen still
--- wants its tab to say something arrived.
---
--- Deliberately simpler than the client's rule, which also weighs the message
--- type and the player's alert settings. Erring towards flashing is the right
--- way to be wrong about an unread indicator.
local function FlashIfUnread(frame)
    if frame:IsShown() then return end
    if type(_G.FCF_StartAlertFlash) ~= "function" then return end
    pcall(_G.FCF_StartAlertFlash, frame)
end

--------------------------------------------------------------------------------
-- The interception
--------------------------------------------------------------------------------

--- Run the client's own handler against the proxy, rewrite what it produced,
--- deliver it to the real frame.
---
--- Ordering is load-bearing: nothing is delivered until every line has been
--- captured and rewritten, so a failure anywhere before delivery leaves the
--- event wholly undelivered and the caller can hand it back to the client
--- safely. There is no half-delivered state to double up.
local function Intercept(frame, event, ...)
    EnsureProxy()

    for index = #captured, 1, -1 do captured[index] = nil end

    Mirror(frame)
    local ok, blocked = pcall(originalHandler, proxy, event, ...)
    Unmirror()

    if not ok then
        -- The client's handler threw while writing to our stand-in. Nothing was
        -- delivered, so let the caller run it again properly.
        error(blocked, 0)
    end

    if #captured == 0 then
        -- Filtered, or not destined for this window. Either way the client has
        -- said what it wanted to happen.
        return blocked
    end

    for index = 1, #captured do
        local line = captured[index]
        if type(line.text) == "string" then
            local rewritten = Rewrite(line.text)
            if rewritten then line.text = rewritten end
        end
    end

    for index = 1, #captured do
        local line = captured[index]
        frame:AddMessage(line.text, unpack(line, 1, line.count))
    end

    FlashIfUnread(frame)

    return blocked
end

--- Every chat message in the game passes through here, so the failure path
--- matters more than the happy one. Anything going wrong hands the event
--- straight back to the client's own handler, with the client's own frame, and
--- the player sees the message they were always going to see.
local function Dispatch(frame, event, ...)
    if not active then
        return originalHandler(frame, event, ...)
    end

    if Links.counting then Links.passes = (Links.passes or 0) + 1 end

    local ok, result = pcall(Intercept, frame, event, ...)
    if ok then return result end

    NoteFailure(result)
    return originalHandler(frame, event, ...)
end

--------------------------------------------------------------------------------
-- Registration
--
-- Installed once and never removed. Removing a hook from a chain is the trap
-- that made the last approach untrustworthy: another addon hooking after us
-- captures ours, and then neither of us can get out cleanly. So this goes in
-- once and answers the question honestly instead - with the feature off,
-- Dispatch calls the client's original handler with the client's own frame and
-- returns its result, which is not "inert", it is indistinguishable from never
-- having been here.
--------------------------------------------------------------------------------

function Links:IsInstalled()
    return active
end

local function Install()
    if installed then return end
    if type(_G.ChatFrame_MessageEventHandler) ~= "function" then return end

    installed = true
    originalHandler = _G.ChatFrame_MessageEventHandler
    _G.ChatFrame_MessageEventHandler = function(frame, event, ...)
        return Dispatch(frame, event, ...)
    end
end

--- Match behaviour to the settings. Idempotent, and cheap: the hook is already
--- where it needs to be, so this only ever moves a boolean.
function Links:Sync()
    active = (PC.Config.enabled and PC.Config.urlLinks and not surrendered) and true or false
    if active then Install() end
end

--- Per-window work, and note what is not here any more: nothing that touches a
--- message. The rewrite is installed once, globally, and a window being adopted
--- has no bearing on it. Only the hover tooltip for a link is per-frame.
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
    Frames:RegisterHandler("links", Apply)

    -- After the handler, so Sync sees the windows it has just been given.
    self:Refresh()

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
