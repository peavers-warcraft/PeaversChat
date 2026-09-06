local _, PC = ...

local ConfigUI = {}
PC.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets

local function ResolveWidth(parentFrame, indent)
    local parentWidth = parentFrame:GetWidth() or 0
    if parentWidth > 100 then
        return parentWidth - (indent * 2) - 10
    end
    return 360
end

-- Every setting on every page ends here: save, then repaint what is already on
-- screen so the change is visible without typing a line of chat.
local function Apply()
    PC.Config:Save()

    PC.Links:Refresh()
    PC.Channels:Apply()
    PC.Channels:ApplyTimestamps()
    PC.Buttons:Refresh()
    PC.Frames:Refresh()
    PC.Tabs:PaintAll()
end

ConfigUI.Apply = Apply

--- The commonest shape on these pages: a checkbox that writes one key and
--- repaints. Saves eight lines a time and keeps every toggle behaving alike.
local function Toggle(parent, label, key, y, indent, width, default)
    local current = PC.Config[key]
    if current == nil then current = default end

    local box = W:CreateCheckbox(parent, label, {
        checked = current == true,
        width = width,
        onChange = function(checked)
            PC.Config[key] = checked
            Apply()
        end,
    })
    box:SetPoint("TOPLEFT", indent, y)
    return box, y - 30
end

--- The font list, as dropdown options. Built fresh each time the page is
--- opened rather than cached, because LibSharedMedia gains faces as other
--- addons load and a cached list would be a list of whatever happened to be
--- loaded first.
local function FontOptions()
    local Theme = PeaversCommons.Theme
    local options = {
        { value = "", label = "Leave the game's own tab font" },
    }

    -- The suite's own face first, where the client can render it. Not offered
    -- on CJK clients, which it has no glyphs for.
    if Theme and Theme.Fonts and (not Theme.UsesCustomFonts or Theme.UsesCustomFonts()) then
        options[#options + 1] = { value = Theme.Fonts.monoSemiBold, label = "IBM Plex Mono SemiBold" }
        options[#options + 1] = { value = Theme.Fonts.monoMedium, label = "IBM Plex Mono Medium" }
        options[#options + 1] = { value = Theme.Fonts.monoRegular, label = "IBM Plex Mono" }
    end

    local fonts = PeaversCommons.ConfigManager.GetFonts() or {}
    local sorted = {}
    for path, name in pairs(fonts) do
        sorted[#sorted + 1] = { path = path, name = name }
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, font in ipairs(sorted) do
        options[#options + 1] = { value = font.path, label = font.name }
    end

    return options
end

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

function ConfigUI:BuildAppearancePage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Chat window", indent, y)
    y = newY - 8

    local toggle = W:CreateCheckbox(parentFrame, "Enable PeaversChat", {
        checked = PC.Config.enabled == true,
        width = width,
        onChange = function(checked)
            PC.Config.enabled = checked
            PC.Config:Save()
            if checked then
                PC.Frames:Refresh()
                PC.Buttons:Refresh()
                PC.Channels:Apply()
            else
                PC.Channels:Restore()
                PC.Frames:Restore()
                PC.Buttons:Refresh()
            end
        end,
    })
    toggle:SetPoint("TOPLEFT", indent, y)
    y = y - 36

    local _, boxY = W:CreateSectionHeader(parentFrame, "The box", indent, y)
    y = boxY - 8

    local _, afterBg = Toggle(parentFrame, "Draw a background behind the chat", "background", y, indent, width, true)
    y = afterBg

    local bg = PC.Config.bgColor or {}
    local bgPicker = W:CreateColorPicker(parentFrame, "Background", {
        r = bg.r or 0.086, g = bg.g or 0.086, b = bg.b or 0.086,
        width = width,
        onChange = function(r, g, b)
            PC.Config.bgColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    bgPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 32

    local alpha = W:CreateSlider(parentFrame, "Background opacity", {
        min = 0, max = 1, step = 0.02,
        value = PC.Config.bgAlpha or 0.6,
        width = width,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        onChange = function(value)
            PC.Config.bgAlpha = value
            Apply()
        end,
    })
    alpha:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local _, afterBorder = Toggle(parentFrame, "Draw a 1px border around it", "border", y, indent, width, true)
    y = afterBorder

    local border = PC.Config.borderColor or {}
    local borderPicker = W:CreateColorPicker(parentFrame, "Border", {
        r = border.r or 0.176, g = border.g or 0.176, b = border.b or 0.176,
        width = width,
        onChange = function(r, g, b)
            PC.Config.borderColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    borderPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 36

    -- Four sliders rather than one, because how much room the text wants from
    -- the border genuinely differs by edge - the left is the one every line
    -- starts against and is read against, and it usually wants a little more
    -- than the other three.
    for _, side in ipairs({
        { key = "paddingLeft", label = "Padding left", default = 8 },
        { key = "paddingRight", label = "Padding right", default = 6 },
        { key = "paddingTop", label = "Padding top", default = 6 },
        { key = "paddingBottom", label = "Padding bottom", default = 6 },
    }) do
        local slider = W:CreateSlider(parentFrame, side.label, {
            min = 0, max = 24, step = 1,
            value = PC.Config[side.key] or side.default,
            width = width,
            onChange = function(value)
                PC.Config[side.key] = value
                Apply()
            end,
        })
        slider:SetPoint("TOPLEFT", indent, y)
        y = y - 56
    end

    y = y - 6

    local _, afterEdge = Toggle(parentFrame, "Let the window reach the screen edge",
        "edgeToEdge", y, indent, width, true)
    y = afterEdge - 4

    local edgeNote = W:CreateLabel(parentFrame,
        "Blizzard reserves a margin around every chat window, which is why "
            .. "dragging one to the left of the screen stops short against "
            .. "nothing you can see. This clears it. The client will not allow "
            .. "the change during combat, so it takes effect once you are out.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    edgeNote:SetPoint("TOPLEFT", indent, y)
    edgeNote:SetWidth(width)
    y = y - 52

    local _, textY = W:CreateSectionHeader(parentFrame, "Text", indent, y)
    y = textY - 8

    local fontSize = W:CreateSlider(parentFrame, "Font size", {
        min = 8, max = 24, step = 1,
        value = PC.Config.fontSize or 13,
        width = width,
        onChange = function(value)
            PC.Config.fontSize = value
            Apply()
        end,
    })
    fontSize:SetPoint("TOPLEFT", indent, y)
    y = y - 62

    local outline = W:CreateDropdown(parentFrame, "Outline", {
        width = width,
        selected = PC.Config.fontOutline or "NONE",
        options = {
            { value = "NONE", label = "None" },
            { value = "OUTLINE", label = "Thin outline" },
            { value = "THICKOUTLINE", label = "Thick outline" },
        },
        onChange = function(value)
            PC.Config.fontOutline = value
            Apply()
        end,
    })
    outline:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local _, afterShadow = Toggle(parentFrame, "Drop shadow behind the text", "shadow", y, indent, width, true)
    y = afterShadow - 8

    local _, fadeY = W:CreateSectionHeader(parentFrame, "History", indent, y)
    y = fadeY - 8

    local _, afterFade = Toggle(parentFrame, "Fade old messages out", "fading", y, indent, width, false)
    y = afterFade

    local timeVisible = W:CreateSlider(parentFrame, "Seconds before fading", {
        min = 10, max = 600, step = 10,
        value = PC.Config.timeVisible or 120,
        width = width,
        onChange = function(value)
            PC.Config.timeVisible = value
            Apply()
        end,
    })
    timeVisible:SetPoint("TOPLEFT", indent, y)
    y = y - 62

    local maxLines = W:CreateSlider(parentFrame, "Lines of history kept", {
        min = 0, max = 5000, step = 128,
        format = function(v)
            if v <= 0 then return "Leave the game's own" end
            return tostring(v)
        end,
        value = PC.Config.maxLines or 1000,
        width = width,
        onChange = function(value)
            PC.Config.maxLines = value
            Apply()
        end,
    })
    maxLines:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local note = W:CreateLabel(parentFrame,
        "Changing the number of lines kept empties the window it applies to - " ..
            "the client reallocates the buffer rather than resizing it. New " ..
            "messages arrive normally afterwards. At the far left the " ..
            "addon does not touch the buffer at all, which is worth knowing " ..
            "because it is the only thing here that goes near where messages " ..
            "are kept.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    note:SetPoint("TOPLEFT", indent, y)
    note:SetWidth(width)
    y = y - 48

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

function ConfigUI:BuildTabsPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Tabs", indent, y)
    y = newY - 8

    local _, afterStyle = Toggle(parentFrame, "Restyle the tabs", "styleTabs", y, indent, width, true)
    y = afterStyle

    local _, afterCase = Toggle(parentFrame, "Uppercase the tab names", "tabUppercase", y, indent, width, true)
    y = afterCase

    local _, afterUnderline = Toggle(parentFrame, "Underline the tab you are reading", "tabUnderline", y, indent, width, true)
    y = afterUnderline

    local _, afterInside = Toggle(parentFrame, "Draw the background behind the tabs", "tabsInside", y, indent, width, true)
    y = afterInside - 4

    local stripHeight = W:CreateSlider(parentFrame, "Tab strip height", {
        min = 0, max = 48, step = 1,
        value = PC.Config.tabStripHeight or 0,
        width = width,
        format = function(v)
            if v <= 0 then return "Auto" end
            return string.format("%dpx", v)
        end,
        onChange = function(value)
            PC.Config.tabStripHeight = value
            Apply()
        end,
    })
    stripHeight:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local insideNote = W:CreateLabel(parentFrame,
        "Auto measures how far the tabs actually reach above the window, which " ..
            "is the right answer unless Blizzard has moved the dock. Nudge it if " ..
            "the box sits proud of the tabs or clips them.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    insideNote:SetPoint("TOPLEFT", indent, y)
    insideNote:SetWidth(width)
    y = y - 44

    local tabFont = W:CreateDropdown(parentFrame, "Tab font", {
        width = width,
        selected = PC.Config.tabFont or "",
        options = FontOptions(),
        onChange = function(value)
            PC.Config.tabFont = value
            Apply()
        end,
    })
    tabFont:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local tabFontSize = W:CreateSlider(parentFrame, "Tab font size", {
        min = 8, max = 20, step = 1,
        value = PC.Config.tabFontSize or 12,
        width = width,
        onChange = function(value)
            PC.Config.tabFontSize = value
            Apply()
        end,
    })
    tabFontSize:SetPoint("TOPLEFT", indent, y)
    y = y - 62

    local _, colorY = W:CreateSectionHeader(parentFrame, "Colours", indent, y)
    y = colorY - 8

    local selected = PC.Config.tabSelectedColor or {}
    local selectedPicker = W:CreateColorPicker(parentFrame, "Selected tab", {
        r = selected.r or 1, g = selected.g or 1, b = selected.b or 1,
        width = width,
        onChange = function(r, g, b)
            PC.Config.tabSelectedColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    selectedPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 32

    local rest = PC.Config.tabTextColor or {}
    local restPicker = W:CreateColorPicker(parentFrame, "Other tabs", {
        r = rest.r or 0.58, g = rest.g or 0.58, b = rest.b or 0.58,
        width = width,
        onChange = function(r, g, b)
            PC.Config.tabTextColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    restPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 32

    local accent = PC.Config.accentColor or {}
    local accentPicker = W:CreateColorPicker(parentFrame, "Underline and unread", {
        r = accent.r or 0.506, g = accent.g or 0.549, b = accent.b or 0.973,
        width = width,
        onChange = function(r, g, b)
            PC.Config.accentColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    accentPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 40

    local note = W:CreateLabel(parentFrame,
        "Blizzard dims a tab when the mouse is somewhere else, which is why the " ..
            "default chat window looks like it has no tabs at all. Restyled " ..
            "tabs stay at full opacity, and a tab with something unread in it " ..
            "turns the accent colour rather than growing a gold blink.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    note:SetPoint("TOPLEFT", indent, y)
    note:SetWidth(width)
    y = y - 60

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Edit box
--------------------------------------------------------------------------------

function ConfigUI:BuildEditBoxPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Where you type", indent, y)
    y = newY - 8

    local _, afterStyle = Toggle(parentFrame, "Restyle the edit box", "styleEditBox", y, indent, width, true)
    y = afterStyle - 4

    local position = W:CreateDropdown(parentFrame, "Position", {
        width = width,
        selected = PC.Config.editBoxPosition or "bottom",
        options = {
            { value = "bottom", label = "Below the chat window" },
            { value = "top", label = "Above the chat window" },
            { value = "blizzard", label = "Inside it, where Blizzard puts it" },
        },
        onChange = function(value)
            PC.Config.editBoxPosition = value
            Apply()
        end,
    })
    position:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local height = W:CreateSlider(parentFrame, "Height", {
        min = 16, max = 40, step = 1,
        value = PC.Config.editBoxHeight or 22,
        width = width,
        onChange = function(value)
            PC.Config.editBoxHeight = value
            Apply()
        end,
    })
    height:SetPoint("TOPLEFT", indent, y)
    y = y - 62

    local _, behaviourY = W:CreateSectionHeader(parentFrame, "Behaviour", indent, y)
    y = behaviourY - 8

    local _, afterChannel = Toggle(parentFrame, "Colour the border by channel", "editBoxChannelColor", y, indent, width, true)
    y = afterChannel

    local _, afterArrows = Toggle(parentFrame, "Arrow keys scroll chat history (hold Alt to move the cursor)",
        "altArrowKeys", y, indent, width, false)
    y = afterArrows - 4

    local note = W:CreateLabel(parentFrame,
        "Off - the default here - means the arrow keys move the cursor, the way " ..
            "they do in every other text field on the machine. Blizzard ships " ..
            "it the other way round.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    note:SetPoint("TOPLEFT", indent, y)
    note:SetWidth(width)
    y = y - 48

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

function ConfigUI:BuildButtonsPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "What sits around the frame", indent, y)
    y = newY - 8

    local entries = {
        { key = "showMenuButton", label = "Chat menu button", default = false },
        { key = "showSocialButton", label = "Group finder toast (the eye, top right)", default = false },
        { key = "showScrollButtons", label = "Scroll up and down arrows", default = false },
        { key = "showBottomButton", label = "Jump to the newest message", default = true },
        { key = "showVoiceButtons", label = "Voice channel, microphone and headset", default = false },
        { key = "showCombatLogBar", label = "Combat log quick-filter bar", default = false },
    }

    for _, entry in ipairs(entries) do
        local _, nextY = Toggle(parentFrame, entry.label, entry.key, y, indent, width, entry.default)
        y = nextY
    end

    y = y - 8

    local note = W:CreateLabel(parentFrame,
        "Everything above has a keybind, a slash command or a menu behind it, " ..
            "which is why it all starts hidden. The exception is jumping to the " ..
            "newest message: there is no other way to do that, so it stays.\n\n" ..
            "Turning one back on restores what the client had, not what it did " ..
            "not: a microphone reappears when you are in a voice channel, and a " ..
            "scroll arrow when there is something to scroll.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    note:SetPoint("TOPLEFT", indent, y)
    note:SetWidth(width)
    y = y - 96

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Links and copy
--------------------------------------------------------------------------------

function ConfigUI:BuildLinksPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Links", indent, y)
    y = newY - 8

    local _, afterLinks = Toggle(parentFrame, "Make URLs clickable", "urlLinks", y, indent, width, false)
    y = afterLinks

    local _, afterBrackets = Toggle(parentFrame, "Put them in brackets", "urlBrackets", y, indent, width, true)
    y = afterBrackets - 4

    local url = PC.Config.urlColor or {}
    local urlPicker = W:CreateColorPicker(parentFrame, "Link colour", {
        r = url.r or 0.506, g = url.g or 0.549, b = url.b or 0.973,
        width = width,
        onChange = function(r, g, b)
            PC.Config.urlColor = { r = r, g = g, b = b }
            Apply()
        end,
    })
    urlPicker:SetPoint("TOPLEFT", indent, y)
    y = y - 40

    local linkNote = W:CreateLabel(parentFrame,
        "Clicking one opens the copy window with the address selected: an addon " ..
            "cannot open a browser, so click, Ctrl+C, Escape is as close as the " ..
            "game gets. This is the only part of the addon that alters a chat " ..
            "message, and it is off until the cause of chat failing in Mythic+ " ..
            "is known rather than guessed at. Three ways of doing it have been " ..
            "tried and all three were followed by the same report. Off means " ..
            "the game's chat handler is never replaced at all - not idled, not " ..
            "bypassed, never touched. Everything else in this addon draws a " ..
            "background, moves a button or changes a font, and none of it can " ..
            "affect a message.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    linkNote:SetPoint("TOPLEFT", indent, y)
    linkNote:SetWidth(width)
    y = y - 46

    local _, copyY = W:CreateSectionHeader(parentFrame, "Copy", indent, y)
    y = copyY - 8

    local _, afterCopy = Toggle(parentFrame, "Show a copy button on each chat window", "copyButton", y, indent, width, true)
    y = afterCopy

    local visibility = W:CreateDropdown(parentFrame, "Copy icon", {
        width = width,
        selected = PC.Config.copyButtonVisibility or "dim",
        options = {
            { value = "dim", label = "Faint, and bright when you hover the window" },
            { value = "always", label = "Always visible" },
            { value = "hover", label = "Only when you hover the window" },
        },
        onChange = function(value)
            PC.Config.copyButtonVisibility = value
            Apply()
        end,
    })
    visibility:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local iconSize = W:CreateSlider(parentFrame, "Copy icon size", {
        min = 8, max = 20, step = 1,
        value = PC.Config.copyIconSize or 11,
        width = width,
        format = function(v) return string.format("%dpx", v) end,
        onChange = function(value)
            PC.Config.copyIconSize = value
            Apply()
        end,
    })
    iconSize:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local _, afterStrip = Toggle(parentFrame, "Strip colours and icons out of copied text",
        "copyStripColors", y, indent, width, true)
    y = afterStrip - 4

    local copyNow = W:CreateButton(parentFrame, "Copy this chat window now", {
        width = width,
        variant = "primary",
        onClick = function() PC.Copy:ShowChat() end,
    })
    copyNow:SetPoint("TOPLEFT", indent, y)
    y = y - 42

    local _, channelY = W:CreateSectionHeader(parentFrame, "Channels", indent, y)
    y = channelY - 8

    local _, afterShort = Toggle(parentFrame, "Abbreviate channel names", "shortChannelNames", y, indent, width, true)
    y = afterShort - 4

    local timestamps = W:CreateDropdown(parentFrame, "Timestamps", {
        width = width,
        selected = PC.Config.timestamps or "default",
        options = PC.Channels.TIMESTAMP_OPTIONS,
        onChange = function(value)
            PC.Config.timestamps = value
            Apply()
        end,
    })
    timestamps:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local note = W:CreateLabel(parentFrame,
        "Guild, officer, party, raid and instance become [G], [O], [P], [R] and " ..
            "[I]. Numbered public channels keep Blizzard's own naming - their " ..
            "bracket is assembled per message rather than read from a format " ..
            "string, and taking that over means reformatting every line in the " ..
            "game.\n\nTimestamps are the game's own setting, written to the same " ..
            "CVar its options panel uses, so they survive this addon.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    note:SetPoint("TOPLEFT", indent, y)
    note:SetWidth(width)
    y = y - 108

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Information
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    PeaversCommons.ConfigUIUtils.BuildInfoPage(parentFrame, "Chat", {
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
    })
end

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
        { key = "appearance", label = "Appearance", builder = function(f) ConfigUI:BuildAppearancePage(f) end },
        { key = "tabs", label = "Tabs", builder = function(f) ConfigUI:BuildTabsPage(f) end },
        { key = "editbox", label = "Edit box", builder = function(f) ConfigUI:BuildEditBoxPage(f) end },
        { key = "buttons", label = "Buttons", builder = function(f) ConfigUI:BuildButtonsPage(f) end },
        { key = "links", label = "Links and copy", builder = function(f) ConfigUI:BuildLinksPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildAppearancePage(parentFrame)
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
