local addonName, PC = ...

-- Access the PeaversCommons library
local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

-- Initialize addon namespace
PC.name = addonName
PC.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

local BUTTON_KEYS = {
    "showMenuButton", "showSocialButton", "showScrollButtons",
    "showBottomButton", "showVoiceButtons", "showCombatLogBar",
}

--- Every hook this addon puts on one of the client's chat functions. Idempotent,
--- so calling it again after /pchat enable is free.
local function InstallHooks()
    PC.Frames:InstallHooks()
    PC.Tabs:InstallHooks()
    PC.EditBox:InstallHooks()
end

--- The smallest thing this addon can be while still being itself: a flat
--- background and a font on the chat window, and nothing else whatsoever.
---
--- Everything switched off here is something that touches an object belonging
--- to the client - restyling its tabs, hiding its buttons, drawing on its dock,
--- rewording its channel strings, resizing its message buffer. What remains
--- touches only the chat frame it was given, and only to draw on it.
---
--- This exists because seven attempts to name the cause of chat failing in
--- Mythic+ by reasoning about it have been wrong, and bisecting is what should
--- have been done instead.
local MINIMAL = {
    styleTabs = false,          -- no restyling of the client's tabs
    tabsInside = false,         -- nothing drawn on the client's dock
    styleEditBox = false,       -- the edit box left where the client put it
    copyButton = false,         -- no button parented to the dock
    shortChannelNames = false,  -- the client's own channel wording
    maxLines = 0,               -- the message buffer never reallocated
    edgeToEdge = false,         -- no protected function called or hooked

    -- "Show" every button, which for this addon means "hide none of them".
    showMenuButton = true,
    showSocialButton = true,
    showScrollButtons = true,
    showBottomButton = true,
    showVoiceButtons = true,
    showCombatLogBar = true,
}

--- The groups /pchat try can hand back, one at a time, while minimal mode is on.
---
--- Ordered by suspicion rather than alphabetically: both of the per-message
--- storms found so far were in the tab code, and the tab code is also the only
--- part of this addon that hooks the client's chat functions or draws on its
--- dock. If there is a third, that is where it is.
local TRY_GROUPS = {
    tabs = { "styleTabs", "tabsInside" },
    copy = { "copyButton" },
    editbox = { "styleEditBox" },
    buttons = {
        "showMenuButton", "showSocialButton", "showScrollButtons",
        "showBottomButton", "showVoiceButtons", "showCombatLogBar",
    },
    channels = { "shortChannelNames" },
    buffer = { "maxLines" },
}

local TRY_ORDER = { "tabs", "buttons", "copy", "editbox", "channels", "buffer" }

--- Re-apply everything after a settings change. The bisect commands all end
--- here, so they cannot drift apart over which modules need telling.
local function Refresh()
    PC.Channels:Apply()
    PC.Buttons:Refresh()
    PC.Frames:Refresh()
    PC.Tabs:PaintAll()
end

-- Register slash commands
PeaversCommons.SlashCommands:Register(addonName, "pchat", {
    default = function()
        PC.ConfigUI:OpenOptions()
    end,
    enable = function()
        PC.Config.enabled = true
        PC.Config:Save()
        PC.Channels:Apply()
        InstallHooks()
        PC.Buttons:Refresh()
        PC.Frames:Refresh()
        Utils.Print(PC, "Chat skinned.")
    end,
    disable = function()
        PC.Config.enabled = false
        PC.Config:Save()
        PC.Channels:Restore()
        PC.Frames:Restore()
        PC.Buttons:Refresh()
        Utils.Print(PC, "Chat handed back to Blizzard. /pchat enable turns it back on. "
            .. "A hook cannot be uninstalled, so reload for this to be exactly "
            .. "the same as the addon not being loaded.")
    end,
    copy = function()
        PC.Copy:ShowChat()
    end,
    without = function(rest)
        -- Bisecting from the other end: everything on, then one group taken
        -- away at a time, cumulatively. Removals stack, so "without buttons"
        -- then "without tabs" leaves both off and everything else on.
        local cfg = PC.Config
        local group = tostring(rest or ""):lower():gsub("%s", "")

        -- Starting from full: if minimal mode is on, come out of it first.
        local minimalHeld = cfg.minimalBackup or {}
        if next(minimalHeld) ~= nil then
            for key, value in pairs(minimalHeld) do cfg[key] = value end
            cfg.minimalBackup = {}
        end

        local removed = cfg.withoutBackup or {}

        if group == "none" then
            for key, value in pairs(removed) do cfg[key] = value end
            cfg.withoutBackup = {}
            cfg:Save()
            Refresh()
            Utils.Print(PC, "Everything back on.")
            return
        end

        if group == "" or not TRY_GROUPS[group] then
            Utils.Print(PC, "Take one group away at a time, then test:")
            for _, name in ipairs(TRY_ORDER) do
                local gone = false
                for _, key in ipairs(TRY_GROUPS[name]) do
                    if removed[key] ~= nil then gone = true end
                end
                print(("  /pchat without %-9s %s"):format(name, gone and "- already removed" or ""))
            end
            print("  /pchat without none      - put everything back")
            return
        end

        for _, key in ipairs(TRY_GROUPS[group]) do
            if removed[key] == nil then removed[key] = cfg[key] end
            cfg[key] = MINIMAL[key]
        end
        cfg.withoutBackup = removed
        cfg:Save()
        Refresh()

        Utils.Print(PC, group .. " removed. Reload, then test. If chat still goes, "
            .. "/pchat without the next one - they stack.")
    end,
    try = function(rest)
        local cfg = PC.Config
        local backup = cfg.minimalBackup or {}

        if next(backup) == nil then
            Utils.Print(PC, "Not in minimal mode - there is nothing being held back. "
                .. "/pchat minimal first.")
            return
        end

        local group = tostring(rest or ""):lower():gsub("%s", "")

        if group == "" or not TRY_GROUPS[group] then
            Utils.Print(PC, "Hand one group back at a time, then test:")
            for _, name in ipairs(TRY_ORDER) do
                local held = false
                for _, key in ipairs(TRY_GROUPS[name]) do
                    if backup[key] ~= nil then held = true end
                end
                print(("  /pchat try %-9s %s"):format(name, held and "- still held back" or "- already back on"))
            end
            return
        end

        -- Taken out of the backup as it is handed back, so leaving minimal mode
        -- does not undo what has already been re-enabled.
        local restored = 0
        for _, key in ipairs(TRY_GROUPS[group]) do
            if backup[key] ~= nil then
                cfg[key] = backup[key]
                backup[key] = nil
                restored = restored + 1
            end
        end
        cfg.minimalBackup = backup
        cfg:Save()

        PC.Channels:Apply()
        PC.Buttons:Refresh()
        PC.Frames:Refresh()
        PC.Tabs:PaintAll()

        if restored == 0 then
            Utils.Print(PC, group .. " was already back on.")
        else
            Utils.Print(PC, group .. " is back on. Reload, then test. If chat holds, "
                .. "/pchat try the next one.")
        end
    end,
    minimal = function()
        local cfg = PC.Config
        local backup = cfg.minimalBackup or {}
        local leaving = next(backup) ~= nil

        if leaving then
            for key, value in pairs(backup) do cfg[key] = value end
            cfg.minimalBackup = {}
        else
            local saved = {}
            for key, value in pairs(MINIMAL) do
                saved[key] = cfg[key]
                cfg[key] = value
            end
            cfg.minimalBackup = saved
        end

        cfg:Save()

        PC.Channels:Apply()
        PC.Buttons:Refresh()
        PC.Frames:Refresh()
        PC.Tabs:PaintAll()

        Utils.Print(PC, leaving
            and "Everything back on."
            or "Minimal mode: a background and a font, and nothing else. "
                .. "Nothing here touches the client's tabs, buttons, dock, "
                .. "channel strings or message buffer. Reload, then test. "
                .. "/pchat minimal again puts it all back.")
    end,
    safe = function()
        -- Channel abbreviations are the only thing left that changes what a
        -- chat line says, so this is now the whole of "stop altering my chat".
        -- A toggle, because a diagnostic you cannot undo is a trap.
        local cfg = PC.Config
        cfg.shortChannelNames = not cfg.shortChannelNames
        cfg:Save()

        if cfg.shortChannelNames then PC.Channels:Apply() else PC.Channels:Restore() end

        Utils.Print(PC, cfg.shortChannelNames
            and "Channel abbreviations are back."
            or "Channel abbreviations off. Nothing this addon does now changes what a chat line says.")
    end,
    trace = function(rest)
        -- Counts chat events on a frame of our own, outside the filter system,
        -- so it reports what the client sent rather than what survived.
        PC.Diagnostics:Toggle(rest)
    end,
    style = function()
        -- Where the window background is drawn and what it hangs from.
        PC.Diagnostics:Style()
    end,
    channels = function()
        -- What was actually done to each channel format string, and why. This
        -- is the first question when a chat line comes out wrong, and it used
        -- to be unanswerable without reading the source and guessing at the
        -- player's locale.
        PC.Channels:Report()
    end,
    buttons = function()
        -- One switch for the lot: if anything is hidden, show everything;
        -- otherwise hide everything. Two presses gets you back where you were.
        local cfg = PC.Config
        local anyHidden = false
        for _, key in ipairs(BUTTON_KEYS) do
            if not cfg[key] then anyHidden = true end
        end

        for _, key in ipairs(BUTTON_KEYS) do
            cfg[key] = anyHidden
        end
        cfg:Save()

        PC.Buttons:Refresh()
        PC.Frames:Refresh()
        Utils.Print(PC, anyHidden and "Every chat button shown." or "Every chat button hidden.")
    end,
    defaults = function()
        -- Saved settings shadow the defaults forever, so somebody who installed
        -- an earlier build never sees a changed default however much better it
        -- is. This is the way to take the new ones.
        local cfg = PC.Config
        for key, value in pairs(cfg.defaults or {}) do
            if type(value) == "table" then
                -- A fresh table per key: assigning the defaults table itself
                -- would alias it, and the next edit would rewrite the defaults.
                local copy = {}
                for k, v in pairs(value) do copy[k] = v end
                cfg[key] = copy
            else
                cfg[key] = value
            end
        end
        cfg:Save()

        PC.Channels:Apply()
        PC.Channels:ApplyTimestamps()
        PC.Buttons:Refresh()
        PC.Frames:Refresh()
        PC.Tabs:PaintAll()

        Utils.Print(PC, "Every setting back to its shipped default.")
    end,
    reset = function()
        if type(_G.FCF_ResetChatWindows) ~= "function" then
            Utils.Print(PC, "This build has no chat reset to call.")
            return
        end
        pcall(_G.FCF_ResetChatWindows)
        PC.Frames:Refresh()
        Utils.Print(PC, "Chat windows reset to the client's own layout, then reskinned.")
    end,
    info = function()
        Utils.Print(PC, string.format("%d chat window(s) skinned. Channel abbreviations: %s. Copy button: %s.",
            PC.Frames:Count(),
            PC.Config.shortChannelNames and "on" or "off",
            PC.Config.copyButton and "on" or "off"))
    end,
    debug = function()
        PC.Config.debugMode = not PC.Config.debugMode
        PC.Config.DEBUG_ENABLED = PC.Config.debugMode
        PC.Config:Save()
        Utils.Print(PC, "Debug mode " .. (PC.Config.debugMode and "enabled" or "disabled"))
    end,
    help = function()
        Utils.Print(PC, "Commands:")
        print("  /pchat - Open settings")
        print("  /pchat copy - Copy the chat window on top")
        print("  /pchat buttons - Show or hide every button at once")
        print("  /pchat minimal - Toggle down to just a background and a font")
        print("  /pchat without <group> - Take one group away, cumulatively, to find a culprit")
        print("  /pchat try <group> - Hand one group back while minimal")
        print("  /pchat safe - Toggle the channel abbreviations off")
        print("  /pchat channels - Show what was changed in the channel formats")
        print("  /pchat trace - Count chat events as they arrive, then report")
        print("  /pchat style - Show where the window background is drawn")
        print("  /pchat enable - Skin the chat windows")
        print("  /pchat disable - Hand chat back to Blizzard")
        print("  /pchat defaults - Put every PeaversChat setting back to its default")
        print("  /pchat reset - Reset the chat layout, then reskin it")
        print("  /pchat info - Print what is currently skinned")
    end
})

-- Initialize the addon
PeaversCommons.Events:Init(addonName, function()
    PC.Config:Initialize()

    -- Padding used to be one number for all four sides. Anybody upgrading has
    -- that number saved and nothing in the four keys that replaced it, and a
    -- saved setting shadows a default forever - so without this their carefully
    -- chosen padding would silently become ours. Runs once.
    -- Forced off once. The screen-edge feature calls and hooks a protected
    -- function, it is the current suspect for chat failing in Mythic+, and
    -- changing its default does nothing for somebody who already has it saved
    -- as on. Being a suspect is reason enough not to wait for them to find the
    -- checkbox.
    -- Forced off once, for the same reason as the screen edge below: a saved
    -- setting would otherwise keep it on for everybody who already has it, and
    -- this one is the current suspect. Every channel it rewrites is one that
    -- stopped working; say, the only channel whose format string carries no
    -- hyperlink, is the only one that kept working.
    if not PC.Config.shortChannelNamesWithdrawn then
        PC.Config.shortChannelNames = false
        PC.Config.shortChannelNamesWithdrawn = true
        PC.Config:Save()
    end

    -- Given back. It was withdrawn on suspicion while chat was failing in
    -- Mythic+; the cause turned out to be the channel abbreviations, and the
    -- version that returns here does not hook the protected function that made
    -- it worth suspecting. Anybody whose setting was forced off gets it back
    -- once, because it was taken away without being asked.
    if PC.Config.edgeToEdgeWithdrawn then
        PC.Config.edgeToEdge = true
        PC.Config.edgeToEdgeWithdrawn = false
        PC.Config:Save()
    end

    if not PC.Config.paddingSplit then
        local legacy = tonumber(PC.Config.padding)
        if legacy then
            PC.Config.paddingLeft = legacy
            PC.Config.paddingRight = legacy
            PC.Config.paddingTop = legacy
            PC.Config.paddingBottom = legacy
        end
        PC.Config.paddingSplit = true
        PC.Config:Save()
    end

    -- Order matters in exactly one respect: every module installs itself as a
    -- Frames handler, and Frames runs them in registration order, so Skin has
    -- to be first - it is the one that takes Blizzard's textures down, and
    -- everything after it draws on the space that leaves. Frames itself is
    -- initialised last because that is what sweeps the windows and runs the
    -- handlers for the first time.
    PC.Skin:Initialize()
    PC.Tabs:Initialize()
    PC.EditBox:Initialize()
    PC.Buttons:Initialize()
    PC.Copy:Initialize()

    PC.Frames:Initialize()
    PC.Channels:Initialize()

    -- The hooks go on only when the addon is on. hooksecurefunc cannot be
    -- undone, so a hook installed at load is there for the session whatever the
    -- settings say afterwards - which is how /pchat disable ended up meaning
    -- something different from disabling the addon in the addon list. Loading
    -- with it switched off now installs nothing at all, and the two are the
    -- same thing.
    if PC.Config.enabled then InstallHooks() end

    if PC.ConfigUI and PC.ConfigUI.Initialize then
        PC.ConfigUI:Initialize()
    end

    if PC.Patrons and PC.Patrons.Initialize then
        PC.Patrons:Initialize()
    end

    -- A whisper tab opened during the loading screen, a chat window restored
    -- from saved layout, an addon that made its own: the sweep at login catches
    -- what exists then, and this catches what the world load brought with it.
    PeaversCommons.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if PC.Config.enabled then
            PC.Frames:Refresh()
            PC.Buttons:Refresh()
        end
    end)

    -- Use the centralized SettingsUI system from PeaversCommons
    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PC, "PeaversChat", "Peavers Chat")
    end)

    -- Register with PeaversConfig registry
    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversChat",
            displayName = "Chat",
            description = "A flat chat window with clickable URLs and a copy button",
            addonRef = PC,
            config = PC.Config,
            pages = PC.ConfigUI:GetPages(),
            order = 15,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversChat = PC
