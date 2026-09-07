local addonName, PC = ...

--------------------------------------------------------------------------------
-- Edit Mode
--
-- This addon does not own a frame - it restyles Blizzard's chat, which is
-- already a system in Edit Mode with its own position and size. So the settings
-- attach to that system rather than registering a frame of our own.
--
-- Position is the one place the two overlap. Edit Mode moves and sizes the chat
-- frame; positionEnabled below decides whether this addon overrides that with a
-- fixed spot instead, and the rest of the Position group only appears when it
-- does.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local EditMode = {}
PC.EditMode = EditMode

--------------------------------------------------------------------------------
-- Applying a change
--
-- Every setting ends here: repaint what is already on screen so the change is
-- visible without typing a line of chat.
--------------------------------------------------------------------------------

function PC.ApplySetting()
    if PC.Channels then
        PC.Channels:Apply()
        PC.Channels:ApplyTimestamps()
    end
    if PC.Buttons then PC.Buttons:Refresh() end
    if PC.Frames then PC.Frames:Refresh() end
    if PC.Tabs then PC.Tabs:PaintAll() end
end

--------------------------------------------------------------------------------
-- Groups
--------------------------------------------------------------------------------

EditMode.SECTIONS = {
    { key = "frame", label = "Frame" },
    { key = "position", label = "Position" },
    { key = "padding", label = "Padding" },
    { key = "text", label = "Text" },
    { key = "tabs", label = "Tabs" },
    { key = "editbox", label = "Edit Box" },
    { key = "buttons", label = "Buttons" },
    { key = "links", label = "Links And Copy" },
}

local function OnlyWhenPositioned(cfg) return not cfg.positionEnabled end

EditMode.ENTRIES = {
    ----------------------------------------------------------------- frame ---
    {
        key = "enabled", label = "Enabled", kind = "checkbox", section = "frame",
        default = true,
        desc = "Off gives the chat frame back to Blizzard.",
    },
    {
        key = "background", label = "Show A Background", kind = "checkbox",
        section = "frame", default = true, revealsOthers = true,
    },
    {
        key = "bgColor", label = "Background Colour", kind = "color", section = "frame",
        default = { r = 0.086, g = 0.086, b = 0.086 },
        hidden = function(cfg) return not cfg.background end,
    },
    {
        key = "bgAlpha", label = "Background Opacity", kind = "slider", section = "frame",
        min = 0, max = 1, step = 0.02, unit = "percent", default = 0.60,
        hidden = function(cfg) return not cfg.background end,
    },
    {
        key = "border", label = "Show A Border", kind = "checkbox", section = "frame",
        default = true, revealsOthers = true,
    },
    {
        key = "borderColor", label = "Border Colour", kind = "color", section = "frame",
        default = { r = 0.176, g = 0.176, b = 0.176 },
        hidden = function(cfg) return not cfg.border end,
    },
    {
        key = "edgeToEdge", label = "Fill To The Edges", kind = "checkbox",
        section = "frame", default = true,
    },
    {
        key = "edgeToEdgeWithdrawn", label = "Fill To The Edges When Withdrawn",
        kind = "checkbox", section = "frame", default = false,
    },

    -------------------------------------------------------------- position ---
    {
        key = "positionEnabled", label = "Pin To A Fixed Spot", kind = "checkbox",
        section = "position", default = false, revealsOthers = true,
        desc = "Off leaves the chat frame to Edit Mode, which then moves and "
            .. "sizes it like any other frame.",
    },
    {
        key = "chatPoint", label = "Corner", kind = "dropdown", section = "position",
        fallback = "BOTTOMLEFT", hidden = OnlyWhenPositioned,
        values = {
            { value = "TOPLEFT", label = "Top left" },
            { value = "TOPRIGHT", label = "Top right" },
            { value = "BOTTOMLEFT", label = "Bottom left" },
            { value = "BOTTOMRIGHT", label = "Bottom right" },
        },
    },
    { key = "chatX", label = "X Offset", kind = "number", section = "position",
      default = 0, hidden = OnlyWhenPositioned },
    { key = "chatY", label = "Y Offset", kind = "number", section = "position",
      default = 22, hidden = OnlyWhenPositioned },
    {
        key = "chatWidth", label = "Width", kind = "number", section = "position",
        default = 0, hidden = OnlyWhenPositioned,
        desc = "Zero keeps whatever width the frame already has.",
    },
    {
        key = "chatHeight", label = "Height", kind = "number", section = "position",
        default = 0, hidden = OnlyWhenPositioned,
        desc = "Zero keeps whatever height the frame already has.",
    },

    --------------------------------------------------------------- padding ---
    {
        key = "paddingSplit", label = "Set Each Edge Separately", kind = "checkbox",
        section = "padding", default = false, revealsOthers = true,
    },
    {
        key = "padding", label = "Padding", kind = "slider", section = "padding",
        min = 0, max = 30, step = 1, unit = "px", default = 6,
        hidden = function(cfg) return cfg.paddingSplit end,
    },
    {
        key = "paddingLeft", label = "Left", kind = "slider", section = "padding",
        min = 0, max = 30, step = 1, unit = "px", default = 8,
        hidden = function(cfg) return not cfg.paddingSplit end,
    },
    {
        key = "paddingRight", label = "Right", kind = "slider", section = "padding",
        min = 0, max = 30, step = 1, unit = "px", default = 6,
        hidden = function(cfg) return not cfg.paddingSplit end,
    },
    {
        key = "paddingTop", label = "Top", kind = "slider", section = "padding",
        min = 0, max = 30, step = 1, unit = "px", default = 6,
        hidden = function(cfg) return not cfg.paddingSplit end,
    },
    {
        key = "paddingBottom", label = "Bottom", kind = "slider", section = "padding",
        min = 0, max = 30, step = 1, unit = "px", default = 6,
        hidden = function(cfg) return not cfg.paddingSplit end,
    },

    ------------------------------------------------------------------ text ---
    {
        key = "fontSize", label = "Font Size", kind = "slider", section = "text",
        min = 8, max = 24, step = 1, unit = "pt", default = 13,
    },
    {
        -- Three-way here, not the tick most addons store, so the outline is
        -- spelled out rather than left to the common schema.
        key = "fontOutline", label = "Font Outline", kind = "dropdown",
        section = "text", fallback = "NONE",
        values = {
            { value = "NONE", label = "None" },
            { value = "OUTLINE", label = "Outline" },
            { value = "THICKOUTLINE", label = "Thick outline" },
        },
    },
    { key = "shadow", label = "Text Shadow", kind = "checkbox", section = "text", default = true },
    {
        key = "fading", label = "Fade Old Messages", kind = "checkbox",
        section = "text", default = false, revealsOthers = true,
    },
    {
        key = "timeVisible", label = "Fade After", kind = "slider", section = "text",
        min = 10, max = 600, step = 10, default = 120,
        hidden = function(cfg) return not cfg.fading end,
    },
    {
        key = "maxLines", label = "Scrollback Lines", kind = "slider", section = "text",
        min = 100, max = 5000, step = 100, default = 1000,
    },
    {
        key = "timestamps", label = "Timestamps", kind = "dropdown", section = "text",
        fallback = "default",
        values = {
            { value = "default", label = "Leave Blizzard's setting alone" },
            { value = "none", label = "None" },
            { value = "hm", label = "13:45" },
            { value = "hms", label = "13:45:07" },
        },
    },
    {
        key = "shortChannelNames", label = "Short Channel Names", kind = "checkbox",
        section = "text", default = false,
    },
    {
        key = "shortChannelNamesWithdrawn", label = "Short Names When Withdrawn",
        kind = "checkbox", section = "text", default = false,
    },

    ------------------------------------------------------------------ tabs ---
    {
        key = "styleTabs", label = "Restyle The Tabs", kind = "checkbox",
        section = "tabs", default = true, revealsOthers = true,
    },
    {
        key = "tabFontSize", label = "Tab Font Size", kind = "slider", section = "tabs",
        min = 8, max = 20, step = 1, unit = "pt", default = 12,
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabsInside", label = "Tabs Inside The Frame", kind = "checkbox",
        section = "tabs", default = true,
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabStripHeight", label = "Tab Strip Height", kind = "slider",
        section = "tabs", min = 0, max = 40, step = 1, unit = "px", default = 0,
        desc = "Zero sizes the strip to the tab text.",
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabUppercase", label = "Uppercase Tab Names", kind = "checkbox",
        section = "tabs", default = true,
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabUnderline", label = "Underline The Selected Tab", kind = "checkbox",
        section = "tabs", default = true,
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabTextColor", label = "Tab Text Colour", kind = "color", section = "tabs",
        default = { r = 0.580, g = 0.580, b = 0.580 },
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "tabSelectedColor", label = "Selected Tab Colour", kind = "color",
        section = "tabs", default = { r = 1, g = 1, b = 1 },
        hidden = function(cfg) return not cfg.styleTabs end,
    },
    {
        key = "accentColor", label = "Accent Colour", kind = "color", section = "tabs",
        default = { r = 0.506, g = 0.549, b = 0.973 },
        hidden = function(cfg) return not cfg.styleTabs end,
    },

    --------------------------------------------------------------- editbox ---
    {
        key = "styleEditBox", label = "Restyle The Edit Box", kind = "checkbox",
        section = "editbox", default = true, revealsOthers = true,
    },
    {
        key = "editBoxPosition", label = "Position", kind = "dropdown", section = "editbox",
        fallback = "bottom", hidden = function(cfg) return not cfg.styleEditBox end,
        values = {
            { value = "bottom", label = "Below the chat frame" },
            { value = "top", label = "Above the chat frame" },
            { value = "blizzard", label = "Where Blizzard puts it" },
        },
    },
    {
        key = "editBoxHeight", label = "Height", kind = "slider", section = "editbox",
        min = 14, max = 40, step = 1, unit = "px", default = 22,
        hidden = function(cfg) return not cfg.styleEditBox end,
    },
    {
        key = "editBoxChannelColor", label = "Colour By Channel", kind = "checkbox",
        section = "editbox", default = true,
        hidden = function(cfg) return not cfg.styleEditBox end,
    },
    {
        key = "altArrowKeys", label = "Alt With Arrow Keys Moves The Cursor",
        kind = "checkbox", section = "editbox", default = false,
    },

    --------------------------------------------------------------- buttons ---
    -- All off by default bar one: everything here duplicates something reachable
    -- elsewhere, which is why the frame is cleaner without them.
    { key = "showMenuButton", label = "Chat Menu", kind = "checkbox", section = "buttons", default = false },
    { key = "showSocialButton", label = "Group Finder Toast", kind = "checkbox", section = "buttons", default = false },
    { key = "showScrollButtons", label = "Scroll Buttons", kind = "checkbox", section = "buttons", default = false },
    {
        key = "showBottomButton", label = "Jump To Newest", kind = "checkbox",
        section = "buttons", default = true,
        desc = "The one that earns its place: nothing else tells you there is "
            .. "unread chat below.",
    },
    { key = "showVoiceButtons", label = "Voice Buttons", kind = "checkbox", section = "buttons", default = false },
    { key = "showCombatLogBar", label = "Combat Log Filter Bar", kind = "checkbox", section = "buttons", default = false },

    ----------------------------------------------------------------- links ---
    {
        key = "urlLinks", label = "Make URLs Clickable", kind = "checkbox",
        section = "links", default = true, revealsOthers = true,
    },
    {
        key = "urlColor", label = "Link Colour", kind = "color", section = "links",
        default = { r = 0.506, g = 0.549, b = 0.973 },
        hidden = function(cfg) return not cfg.urlLinks end,
    },
    {
        key = "urlBrackets", label = "Wrap Links In Brackets", kind = "checkbox",
        section = "links", default = true,
        hidden = function(cfg) return not cfg.urlLinks end,
    },
    {
        key = "copyButton", label = "Show A Copy Button", kind = "checkbox",
        section = "links", default = true, revealsOthers = true,
    },
    {
        key = "copyStripColors", label = "Copy Without Colours", kind = "checkbox",
        section = "links", default = true,
        hidden = function(cfg) return not cfg.copyButton end,
    },
    {
        key = "copyButtonVisibility", label = "Copy Button Shows", kind = "dropdown",
        section = "links", fallback = "dim",
        hidden = function(cfg) return not cfg.copyButton end,
        values = {
            { value = "dim", label = "Dimmed until hovered" },
            { value = "always", label = "Always" },
            { value = "hover", label = "Only while hovered" },
        },
    },
    {
        key = "copyIconSize", label = "Copy Icon Size", kind = "slider", section = "links",
        min = 8, max = 20, step = 1, unit = "px", default = 11,
        hidden = function(cfg) return not cfg.copyButton end,
    },
}

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function EditMode:BuildSchema()
    if self.schema then return self.schema end

    self.schema = PeaversCommons.SettingsSchema:New({
        config = PC.Config,
        sections = self.SECTIONS,
        entries = self.ENTRIES,
        apply = function() PC.ApplySetting() end,
    })

    return self.schema
end

function EditMode:Register()
    if not PeaversCommons.EditMode or not PeaversCommons.EditMode.available then
        return false
    end
    if not (Enum and Enum.EditModeSystem and Enum.EditModeSystem.ChatFrame) then
        return false
    end

    PeaversCommons.EditMode:RegisterSystem({
        systemID = Enum.EditModeSystem.ChatFrame,
        name = "Peavers Chat",
        schema = self:BuildSchema(),
    })

    return true
end

return EditMode
