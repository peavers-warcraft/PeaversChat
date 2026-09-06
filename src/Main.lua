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

-- Register slash commands
PeaversCommons.SlashCommands:Register(addonName, "pchat", {
    default = function()
        PC.ConfigUI:OpenOptions()
    end,
    enable = function()
        PC.Config.enabled = true
        PC.Config:Save()
        PC.Channels:Apply()
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
        Utils.Print(PC, "Chat handed back to Blizzard. /pchat enable turns it back on.")
    end,
    copy = function()
        PC.Copy:ShowChat()
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
