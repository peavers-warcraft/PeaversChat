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
-- On the way to the screen, not on the way in.
--
-- This used to be a ChatFrame_AddMessageEventFilter on every chat event, which
-- is the documented way to alter a chat message and is what most addons reach
-- for. In instanced content it stopped chat working: authored messages never
-- appeared while system messages, which take a different path, arrived
-- normally. Removing the filters fixed it, with the client happily delivering
-- 36 party messages over a key that showed none of them.
--
-- The event path is where the client is doing its restricted-data handling, and
-- an addon standing in the middle of it is standing somewhere it now has no
-- business being. Prat - which has done clickable URLs for fifteen years and
-- does not have this problem - does not call ChatFrame_AddMessageEventFilter
-- once in its entire source. It works on the line after the client has finished
-- building it, and so does this now.
--
-- So the hook is on each chat frame's own AddMessage. By then the message is a
-- finished string: the name is coloured, the channel is bracketed, every
-- restricted value has already been resolved by code allowed to resolve it, and
-- what arrives here is text. Anything containing a pipe is skipped, which is
-- every link the client just built, so none of that work can be damaged.
--
-- Uninstalling restores the original method only when nothing has hooked on top
-- of ours. If something has, unwinding would throw away their hook with ours,
-- so the wrapper is left in place as a pass-through instead. That is the one
-- place in this addon where "off" does not mean "gone", and it is because the
-- alternative is breaking somebody else's addon.
--------------------------------------------------------------------------------

local active = false

local function HookFrame(frame)
    if frame.__pcAddMessage then return end
    if type(frame.AddMessage) ~= "function" then return end

    local original = frame.AddMessage
    frame.__pcAddMessage = original

    local wrapper = function(self, text, ...)
        if active and type(text) == "string" then
            local ok, rewritten = pcall(Rewrite, text)
            if not ok then
                NoteFailure(rewritten)
            elseif rewritten then
                text = rewritten
            end
        end
        return original(self, text, ...)
    end

    frame.AddMessage = wrapper
    frame.__pcWrapper = wrapper
end

local function UnhookFrame(frame)
    local original = frame.__pcAddMessage
    if not original then return end

    -- Only unwind if we are still the outermost hook.
    if frame.AddMessage == frame.__pcWrapper then
        frame.AddMessage = original
        frame.__pcAddMessage = nil
        frame.__pcWrapper = nil
    end
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
    -- A window adopted after Sync ran - a whisper tab, a temporary window - has
    -- to be wrapped as it appears, or links work everywhere except the tab that
    -- opened last.
    if PC.Config.enabled and PC.Config.urlLinks and not Links:HasSurrendered() then
        HookFrame(frame)
    end

    if frame.__pcHyperlinkHooked then return end
    if type(frame.HookScript) ~= "function" then return end

    frame.__pcHyperlinkHooked = true
    frame:HookScript("OnHyperlinkEnter", OnHyperlinkEnter)
    frame:HookScript("OnHyperlinkLeave", OnHyperlinkLeave)
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Registration
--
-- Turning the feature off has to mean the hook stops acting, not that it acts
-- and hopes. "Off" that leaves a live hook cannot answer the only question
-- anybody asks it - is this addon what is wrong with my chat - so `active`
-- gates the rewrite and Unwrap removes the wrapper outright wherever it safely
-- can.
--------------------------------------------------------------------------------

function Links:IsInstalled()
    return active
end

--- Match the hooks to the current settings. Idempotent; called on every config
--- change and every time a chat window is adopted.
function Links:Sync()
    active = (PC.Config.enabled and PC.Config.urlLinks and not surrendered) and true or false

    Frames:Each(function(frame)
        if active then HookFrame(frame) else UnhookFrame(frame) end
    end)
end

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
