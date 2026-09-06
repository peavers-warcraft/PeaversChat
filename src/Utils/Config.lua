--------------------------------------------------------------------------------
-- PeaversChat Configuration
--
-- Account-wide by design. What the chat window looks like and which buttons sit
-- around it are properties of the screen rather than of the character, so this
-- uses the flat (non-profile) ConfigManager variant, exactly as PeaversToolTip
-- and PeaversMiniMap do.
--
-- The defaults are the product. The brief for this addon was "out of the box
-- quality with a few tweak points", so a fresh install is already the finished
-- look: a flat #161616 box, text tabs with an accent underline, every piece of
-- Blizzard's chrome around the frame gone, URLs clickable, and a copy button
-- where you can see it. Nothing below needs touching to get there.
--------------------------------------------------------------------------------

local addonName, PC = ...

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager

PC.name = PC.name or addonName

local PC_DEFAULTS = {
    -- Master toggle. Off restores Blizzard's own chat, live, without a reload.
    enabled = true,

    ----------------------------------------------------------------------------
    -- The box
    --
    -- Colours are spelled out rather than read from PeaversCommons.Theme so that
    -- a future reskin of the config UI does not silently restyle everybody's
    -- chat window. They are the same values: #161616 paper, #2d2d2d hairline.
    --
    -- 0.6 alpha rather than the config UI's 0.97: chat sits over the world for
    -- hours at a time, and a fully opaque slab in the corner of the screen is a
    -- different thing from an opaque settings panel you open for a minute.
    ----------------------------------------------------------------------------
    background = true,
    bgColor = { r = 0.086, g = 0.086, b = 0.086 },
    bgAlpha = 0.60,
    border = true,
    borderColor = { r = 0.176, g = 0.176, b = 0.176 },
    -- Padding is per side. How much room the text wants from the border differs
    -- by edge: the left is where every line starts and is the one you actually
    -- read against, the right is ragged, the top sits under a tab row and the
    -- bottom over an edit box.
    paddingLeft = 8,
    paddingRight = 6,
    paddingTop = 6,
    paddingBottom = 6,

    -- Legacy. Read once to seed the four above for anybody upgrading, then
    -- never again. Kept in the defaults so migration has something to read on a
    -- profile that predates the split.
    padding = 6,
    paddingSplit = false,

    -- Blizzard gives every chat window a clamping inset, which is why dragging
    -- one to the left of the screen stops short against nothing you can see.
    edgeToEdge = true,

    ----------------------------------------------------------------------------
    -- Text
    ----------------------------------------------------------------------------
    fontSize = 13,
    fontOutline = "NONE",       -- "NONE" | "OUTLINE" | "THICKOUTLINE"
    shadow = true,

    -- Blizzard fades chat out after two minutes. Off by default: the whole point
    -- of a chat log is that it is still there when you look back at it.
    fading = false,
    timeVisible = 120,

    -- Blizzard keeps 128 lines. A copy button is worth much more against a
    -- buffer you can actually scroll back through, and the cost of a longer one
    -- is memory the client was going to allocate lazily anyway.
    maxLines = 1000,

    ----------------------------------------------------------------------------
    -- Tabs
    ----------------------------------------------------------------------------
    styleTabs = true,
    tabFontSize = 12,

    -- Empty means "whatever font the tab already had", which is Blizzard's and
    -- is correct in every locale. A chosen font is only applied when the client
    -- can render the locale with it.
    tabFont = "",

    -- The window's background reaches up over the tab strip, so the tabs sit
    -- inside the box rather than balanced on top of it. 0 measures how far the
    -- tabs actually reach; anything else overrides that measurement.
    tabsInside = true,
    tabStripHeight = 0,
    tabUppercase = true,
    tabUnderline = true,
    tabTextColor = { r = 0.580, g = 0.580, b = 0.580 },
    tabSelectedColor = { r = 1.000, g = 1.000, b = 1.000 },
    accentColor = { r = 0.506, g = 0.549, b = 0.973 },

    ----------------------------------------------------------------------------
    -- Edit box
    ----------------------------------------------------------------------------
    styleEditBox = true,
    editBoxPosition = "bottom",     -- "bottom" | "top" | "blizzard"
    editBoxHeight = 22,

    -- Blizzard binds the arrow keys to chat history unless Alt is held. Off here
    -- means the arrows move the cursor, like every other text field on the
    -- machine, which is what people expect the first time they mistype a word.
    altArrowKeys = false,

    -- The edit box border takes the colour of the channel you are about to
    -- speak in, so /g and /w look different before you have read the header.
    editBoxChannelColor = true,

    ----------------------------------------------------------------------------
    -- Buttons
    --
    -- All off by default. Everything they do has a keybind, a slash command or a
    -- menu behind it, and the row of gold icons round the frame is most of what
    -- makes the default chat window look like the default chat window.
    ----------------------------------------------------------------------------
    showMenuButton = false,     -- the chat menu, bottom-left
    showSocialButton = false,   -- QuickJoinToast, the group finder toast
    showScrollButtons = false,  -- page up / page down
    showBottomButton = true,    -- jump to the newest message (earns its place)
    showVoiceButtons = false,   -- channel, mute, deafen
    showCombatLogBar = false,   -- Blizzard_CombatLog's gold quick-filter strip

    ----------------------------------------------------------------------------
    -- Links
    ----------------------------------------------------------------------------
    -- Off, and staying off until the cause of chat failing in Mythic+ is known
    -- rather than guessed at.
    --
    -- Three ways of altering a chat line have now been tried and all three were
    -- followed by the same report. Each time the reasoning for the new one was
    -- sound and each time it was beside the point, because the reasoning rested
    -- on a single observation - chat working once with the hook removed - that
    -- was never repeated. Off means the global chat handler is never replaced
    -- at all, which is the only version of this feature that can be ruled out
    -- by ruling it out.
    urlLinks = false,
    urlColor = { r = 0.506, g = 0.549, b = 0.973 },
    urlBrackets = true,


    ----------------------------------------------------------------------------
    -- Copy
    ----------------------------------------------------------------------------
    copyButton = true,
    copyStripColors = true,

    -- "dim" keeps the mark faintly visible at all times, which is the rule this
    -- suite holds to: no click target you cannot see. "hover" is the exception,
    -- for anybody who would rather have nothing there at all.
    copyButtonVisibility = "dim",   -- "dim" | "always" | "hover"
    copyIconSize = 11,

    ----------------------------------------------------------------------------
    -- Channels
    ----------------------------------------------------------------------------
    shortChannelNames = true,
    -- A Blizzard CVar value, "none", or "default" meaning leave whatever the
    -- player already set in the game's own options.
    timestamps = "default",

    debugMode = false,
    DEBUG_ENABLED = false,
}

PC.Config = ConfigManager:New(PC, PC_DEFAULTS, {
    savedVariablesName = "PeaversChatDB",
})

return PC.Config
