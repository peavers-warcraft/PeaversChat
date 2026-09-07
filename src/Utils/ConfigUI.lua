local _, PC = ...

local ConfigUI = {}
PC.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local ConfigUIUtils = PeaversCommons.ConfigUIUtils

-- Applying a setting lives with the addon's schema now, in EditMode.lua, so the
-- settings page and the Edit Mode panel cannot disagree about what a change
-- should do.

function ConfigUI:BuildInfoPage(parentFrame)
    ConfigUIUtils.BuildInfoPageWithEditMode(parentFrame, "Chat", {
        "Redraws the chat window as a flat black box with clean text tabs, turns " ..
            "URLs into something you can click, puts a copy button where you can " ..
            "see it, and hides every piece of chrome Blizzard hangs around the " ..
            "frame.",
        { command = "/pchat", desc = "open the settings" },
        { command = "/pchat copy", desc = "copy the chat window on top" },
        { command = "/pchat buttons", desc = "show or hide every button at once" },
        { command = "/pchat disable", desc = "hand chat back to Blizzard" },

        { header = "Clickable URLs" },
        "The hard part is not finding URLs, it is not finding things that are " ..
            "not URLs. Messages are walked one word at a time; anything " ..
            "containing a pipe is skipped, which is every item link, spell, " ..
            "achievement and colour run the client can emit; and a bare host " ..
            "with no scheme and no path has to end in a top-level domain the " ..
            "addon recognises. That is what stops \"ok.thanks\" turning blue.",

        { header = "Copying" },
        "The game has no clipboard API. The only way text leaves WoW is through " ..
            "an edit box, so the copy window is one, filled with the window's " ..
            "own message buffer and already selected. Colours, icons and link " ..
            "wrappers are taken back out; what a link was standing in for stays.",

        { header = "What it deliberately does not do" },
        "It does not take over how a chat line is built. Numbered channels keep " ..
            "Blizzard's naming, class colouring stays the client's own, and no " ..
            "message is rewritten beyond the URLs in it. A chat addon that " ..
            "formats every line is a chat addon that needs a patch every time " ..
            "Blizzard touches ChatFrame.lua, and the abbreviation it buys is not " ..
            "worth the outage.",

        { header = "Performance" },
        "Nothing here runs per frame and nothing runs on a timer. The skin is " ..
            "built once per window and afterwards only recoloured; hidden " ..
            "buttons cost one OnShow handler that fires when the client was " ..
            "going to show them anyway; and a chat message costs one plain " ..
            "string search, which bails before doing any pattern work unless the " ..
            "message contains a dot or an at-sign.",
    }, {
        title = "the chat frame",
        select = "the chat frame",
        reset = function()
            PC.Config:Reset()
            if PC.ApplySetting then PC.ApplySetting() end
            if PeaversCommons.EditModePanel then
                PeaversCommons.EditModePanel:Refresh()
            end
        end,
    })
end

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildInfoPage(parentFrame)
    return parentFrame
end

function ConfigUI:OpenOptions()
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversChat")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PC.directSettingsCategoryID then
            local success = pcall(Settings.OpenToCategory, PC.directSettingsCategoryID)
            if success then return end
        end
        if PC.directCategoryID then
            local success = pcall(Settings.OpenToCategory, PC.directCategoryID)
            if success then return end
        end
    end

    if SettingsPanel then
        SettingsPanel:Open()
    end
end

function ConfigUI:Initialize()
end

return ConfigUI
