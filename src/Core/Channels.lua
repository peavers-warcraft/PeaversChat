--------------------------------------------------------------------------------
-- Channels
--
-- "[Guild] Peavers: hello" becomes "[G] Peavers: hello".
--
-- Chat is a column of text roughly forty characters wide, and on a busy night a
-- third of those characters are the word "Instance" repeated down the left-hand
-- edge. Abbreviating the channel is the single largest readability win available
-- to a chat addon, and it costs nothing at runtime: these are format strings the
-- client reads when it builds a line, so replacing them once at login is the
-- whole implementation.
--
-- Scope, stated plainly: this covers the fixed channels - guild, officer, party,
-- raid, instance and their leader variants. Numbered public channels keep
-- Blizzard's own naming, because their bracket is assembled from the channel
-- list at message time rather than from a global, and rewriting that means
-- taking over ChatFrame_MessageEventHandler. Handing an addon the job of
-- formatting every chat line in the game is how a chat addon ends up needing a
-- fix on every patch, and the trade is not worth one more abbreviation.
--
-- Every original is kept, so switching this off restores exactly what the
-- client shipped, in the player's own locale, without a reload.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Channels = {}
PC.Channels = Channels

-- The abbreviation replaces the bracketed word, and only the bracketed word.
-- Everything else in each format string - the channel hyperlink, the trailing
-- separator, the argument order - is left exactly as the client wrote it, which
-- is what keeps this working in every locale.
local SHORT = {
    CHAT_GUILD_GET = "G",
    CHAT_OFFICER_GET = "O",
    CHAT_PARTY_GET = "P",
    CHAT_PARTY_LEADER_GET = "PL",
    CHAT_PARTY_GUIDE_GET = "PG",
    CHAT_RAID_GET = "R",
    CHAT_RAID_LEADER_GET = "RL",
    CHAT_RAID_WARNING_GET = "RW",
    CHAT_INSTANCE_CHAT_GET = "I",
    CHAT_INSTANCE_CHAT_LEADER_GET = "IL",
}

local originals = nil
local applied = false

--- How many format arguments a string consumes. Every % that is not an escaped
--- %% is a specifier; counting them conservatively is the point, because this is
--- a safety check and over-counting only ever refuses an abbreviation.
local function Specifiers(source)
    local literal = source:gsub("%%%%", "")
    local _, count = literal:gsub("%%", "")
    return count
end

--- Swap the bracketed channel word for its abbreviation.
---
--- Safe by construction rather than by inspection, because these strings are
--- consumed by string.format inside the client's own message handler and this
--- addon cannot see what the client shipped in any given locale. Three things
--- have to hold before a rewrite is allowed, and any one of them failing means
--- that channel simply keeps Blizzard's wording:
---
---  1. The bracket holds literal text. If it holds a format specifier then the
---     client is filling that bracket in at message time, and replacing it
---     deletes an argument the caller is still going to pass.
---  2. Nothing formatted comes before it. A bracket after the first specifier
---     is not the channel - it is something the client already substituted, a
---     bracketed player name in some locales - and rewriting it corrupts the
---     line.
---  3. The rewrite consumes exactly as many arguments as the original.
---
--- What happens when this is wrong is worth stating, because it is not a
--- cosmetic bug. string.format does not complain about a missing specifier: it
--- silently shifts every later argument one place left, so the name lands where
--- the channel went and the message is dropped off the end. And an argument
--- that shifts onto a %s can be a value the client will not let Lua stringify,
--- which throws inside the message handler before the line is added. From the
--- outside that looks like chat quietly not working - system messages, which
--- take none of this path, keep arriving as though nothing were wrong.
local function Abbreviate(source, short)
    if type(source) ~= "string" then return nil end

    local open, close, inner = source:find("%[([^%]]*)%]")
    if not open then return nil end

    if inner == "" or inner:find("%%") then return nil end

    local firstSpecifier = source:find("%%")
    if firstSpecifier and firstSpecifier < open then return nil end

    local rewritten = source:sub(1, open - 1) .. "[" .. short .. "]" .. source:sub(close + 1)
    if rewritten == source then return nil end
    if Specifiers(rewritten) ~= Specifiers(source) then return nil end

    return rewritten
end

function Channels:Apply()
    if not PC.Config.enabled or not PC.Config.shortChannelNames then
        self:Restore()
        return
    end

    if applied then return end

    originals = originals or {}

    for global, short in pairs(SHORT) do
        local current = _G[global]
        if type(current) == "string" then
            local rewritten = Abbreviate(current, short)
            if rewritten then
                if originals[global] == nil then originals[global] = current end
                _G[global] = rewritten
            end
        end
    end

    applied = true
end

function Channels:Restore()
    if not applied or not originals then return end

    for global, source in pairs(originals) do
        _G[global] = source
    end

    applied = false
end

--------------------------------------------------------------------------------
-- Showing your working
--
-- These rewrites happen once, at login, to globals nobody can see. When a chat
-- line comes out wrong the first question is "what did this addon actually
-- change?", and until there was a way to ask, the answer was to read the source
-- and guess at the locale. This prints it.
--------------------------------------------------------------------------------

--- Pipes have to be doubled or the chat frame renders the escape sequences in
--- the string we are trying to show somebody.
local function Literal(source)
    return (tostring(source):gsub("|", "||"))
end

function Channels:Report()
    print("|cff3abdf7PeaversChat|r channel formats:")

    for global, short in pairs(SHORT) do
        local current = _G[global]
        local original = (originals and originals[global]) or current

        if type(current) ~= "string" then
            print(("  %s - not present on this build"):format(global))
        elseif originals and originals[global] then
            print(("  %s -> %s"):format(global, Literal(current)))
        else
            local why = "unchanged"
            local open, _, inner = original:find("%%[([^%%]]*)%%]")
            if not open then
                why = "left alone: no bracket to replace"
            elseif inner == "" or inner:find("%%%%") then
                why = "left alone: the bracket holds a format specifier, not a word"
            elseif (original:find("%%%%") or math.huge) < open then
                why = "left alone: something formatted comes before the bracket"
            elseif not applied then
                why = "abbreviation is switched off"
            end
            print(("  %s [%s] would be [%s]  %s"):format(global, Literal(original), short, why))
        end
    end
end

--------------------------------------------------------------------------------
-- Timestamps
--
-- Blizzard already has this, driven by a CVar that its own options panel writes.
-- Exposing it here rather than reimplementing it means the setting survives this
-- addon being uninstalled, and that a player who set it in the game's own menu
-- is not overruled by a default of ours: "default" below means leave it alone.
--------------------------------------------------------------------------------

Channels.TIMESTAMP_OPTIONS = {
    { value = "default", label = "Leave the game's own setting alone" },
    { value = "none", label = "No timestamps" },
    { value = "%H:%M ", label = "14:32" },
    { value = "%H:%M:%S ", label = "14:32:45" },
    { value = "%I:%M ", label = "02:32" },
    { value = "%I:%M:%S ", label = "02:32:45" },
    { value = "%I:%M %p ", label = "02:32 PM" },
}

function Channels:ApplyTimestamps()
    local value = PC.Config.timestamps
    if not value or value == "default" then return end
    if not PC.Config.enabled then return end

    pcall(SetCVar, "showTimestamps", value)
end

function Channels:Initialize()
    self:Apply()
    self:ApplyTimestamps()
end

return Channels
