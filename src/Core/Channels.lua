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

--- Swap the text inside the first [...] for the abbreviation, leaving the
--- hyperlink wrapper and the %s placeholders untouched.
local function Abbreviate(source, short)
    if type(source) ~= "string" then return nil end
    if not source:find("%[") then return nil end

    local rewritten = source:gsub("%[[^%]]*%]", "[" .. short .. "]", 1)
    if rewritten == source then return nil end
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
