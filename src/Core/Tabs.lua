--------------------------------------------------------------------------------
-- Tabs
--
-- Blizzard's chat tab is nine textures and a gold blink. This turns it into a
-- flat box with a word in it (or, in the "text" style, just the word): grey when
-- it is not the tab you are reading, white with an accent line when it is.
--
-- Two things about chat tabs make them fiddlier than they look.
--
-- 1. They fade. The client dims a tab when the mouse is away from the dock,
--    which is why the default chat window looks like it has no tabs at all
--    until you go looking for them. Alpha is therefore pinned rather than set:
--    SetAlpha is shadowed with a no-op for as long as the addon is enabled, so
--    every fade the client starts lands on a tab that is already where we want
--    it. Setting the field back to nil restores the widget method, so this is
--    reversible.
--
-- 2. Their width is Blizzard's, and it was measured against Blizzard's text.
--    Changing the font size or the casing without re-measuring gives you
--    clipped tabs or a dock full of gaps, so the width is recomputed from the
--    string every time the tab is painted.
--
-- Selection is read from the dock rather than taken from FCFTab_UpdateColors's
-- argument. The hook is still installed - it is the cheapest signal that
-- selection changed - but it only triggers a repaint, and the repaint asks the
-- dock. That way a client that renames or retires the function costs a repaint
-- trigger, not a wrong-looking tab row.
--------------------------------------------------------------------------------

local addonName, PC = ...

local Tabs = {}
PC.Tabs = Tabs

local Frames = PC.Frames
local Skin = PC.Skin

local Kill = Skin.Kill

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

local function TabText(tab)
    if tab.Text then return tab.Text end
    local name = tab:GetName()
    if name and _G[name .. "Text"] then return _G[name .. "Text"] end
    if tab.GetFontString then return tab:GetFontString() end
    return nil
end

--- Public: Skin measures the strip from the tab's text, and this is how it
--- finds it without duplicating the three places Blizzard has kept that string.
Tabs.FontString = TabText

local function TabGlow(tab)
    if tab.glow then return tab.glow end
    local name = tab:GetName()
    return name and _G[name .. "Glow"] or nil
end

--- The chat frame a tab belongs to.
local function TabFrame(tab)
    local id = tab:GetID()
    return (id and id > 0 and _G["ChatFrame" .. id]) or nil
end

--------------------------------------------------------------------------------
-- Flash
--
-- The gold blink is taken down, so something has to replace it: an unread tab
-- turns accent-coloured. That only works if the client will tell us when the
-- flashing stops as well as when it starts - a tab stuck on accent for the rest
-- of the session is worse than the blob - so the colouring is installed only
-- when both ends of the pair resolve. When they do not, the glow is left alive
-- and merely tinted, and Blizzard keeps driving its own animation.
--------------------------------------------------------------------------------

local flashHooked = false

local function StartFn()
    return (type(_G.FCF_StartAlertFlash) == "function" and "FCF_StartAlertFlash")
        or (type(_G.FCF_FlashTab) == "function" and "FCF_FlashTab")
        or nil
end

local function CanColorFlash()
    return StartFn() ~= nil and type(_G.FCF_StopAlertFlash) == "function"
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

local function IsSelected(frame)
    if not frame then return false end
    -- An undocked window has a tab of its own and is always the tab you are
    -- looking at.
    if frame.isDocked == false or frame.isDocked == nil then
        if frame ~= _G.ChatFrame1 then return true end
    end
    return frame == Frames:Selected()
end

--------------------------------------------------------------------------------
-- Boxed tabs
--
-- Each tab is its own translucent box sitting on the window's top edge: the
-- tabs you are not reading are a lighter fill, the one you are reading has the
-- window's full opacity, a faint outline and the accent line along its foot.
--
-- Anchored edge by edge: sides to the tab, top to its word, foot to the chat
-- window. Where Blizzard's tab frame ends relative to the window is not ours to
-- know, so it is never measured; the layout engine works it out. A selection
-- change is two calls per tab - the fill, and one SetShown for the outline and
-- accent line, which share a child frame for that reason.
--------------------------------------------------------------------------------

local BOX_PADDING = 12      -- either side of the word
local BOX_SPACING = 1       -- between neighbouring tabs
local BOX_TEXT_MARGIN = 4   -- above the word
local INACTIVE_SHARE = 0.68 -- an unselected tab's fill, against the window's
local EDGE_BOOST = 1.8      -- the selected tab's outline, against the window's

--- The selected tab's line: the accent, your class colour, or one of your own.
--- The player's own class is never secret, so this is safe in any content.
local function UnderlineColor()
    local cfg = PC.Config
    local mode = cfg.tabUnderlineColorMode
    if mode == "custom" and cfg.tabUnderlineColor then return cfg.tabUnderlineColor end
    if mode == "class" then
        local _, class = UnitClass("player")
        local color = class and ((_G.C_ClassColor and _G.C_ClassColor.GetClassColor
            and _G.C_ClassColor.GetClassColor(class))
            or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]))
        if color then return color end
    end
    return cfg.accentColor
end

local function BoxSignature(tab)
    local cfg = PC.Config
    local bg, border, accent = cfg.bgColor, cfg.borderColor, UnderlineColor()
    return table.concat({
        bg.r, bg.g, bg.b, cfg.bgAlpha, border.r, border.g, border.b, cfg.borderAlpha or 1,
        accent.r, accent.g, accent.b,
        cfg.background and 1 or 0, cfg.border and 1 or 0, cfg.tabUnderline and 1 or 0,
        cfg.tabsInside and 1 or 0, cfg.paddingTop or 6, Skin.Hairline(tab),
    }, ",")
end

local function EnsureTabBox(tab)
    if tab.peaversTabBox then return tab.peaversTabBox end

    local box = {}
    box.bg = tab:CreateTexture(nil, "BACKGROUND", nil, -8)
    box.bg.__pcOwned = true

    local deco = CreateFrame("Frame", nil, tab)
    deco:SetAllPoints(tab)
    box.deco = deco

    for _, part in ipairs({ "top", "left", "right", "line" }) do
        box[part] = deco:CreateTexture(nil, "OVERLAY")
        box[part].__pcOwned = true
    end

    tab.peaversTabBox = box
    return box
end

local function LayoutTabBox(tab, frame, box)
    local cfg = PC.Config
    local px = Skin.Hairline(tab)
    local fs = TabText(tab)

    -- With the strip behind them the tabs stand on the line under the tab row,
    -- which is the frame's own top. Without it they stand on the window box,
    -- which the padding has pushed up above the frame.
    local base = cfg.tabsInside and 0 or (cfg.paddingTop or 6)

    local bg = box.bg
    bg:ClearAllPoints()
    bg:SetPoint("LEFT", tab, "LEFT", 0, 0)
    bg:SetPoint("RIGHT", tab, "RIGHT", -BOX_SPACING, 0)
    bg:SetPoint("TOP", fs, "TOP", 0, BOX_TEXT_MARGIN)
    if frame then
        bg:SetPoint("BOTTOM", frame, "TOP", 0, base)
    else
        bg:SetPoint("BOTTOM", tab, "BOTTOM", 0, 0)
    end
    bg:SetShown(cfg.background and true or false)

    local top, left, right, line = box.top, box.left, box.right, box.line

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
    top:SetHeight(px)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, -px)
    left:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
    left:SetWidth(px)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, -px)
    right:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(px)

    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", px, 0)
    line:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -px, 0)
    line:SetHeight(px * 2)

    local border = cfg.borderColor
    local edgeAlpha = math.min(1, (cfg.borderAlpha or 1) * EDGE_BOOST)
    for _, edge in ipairs({ top, left, right }) do
        edge:SetColorTexture(border.r, border.g, border.b, edgeAlpha)
        edge:SetShown(cfg.border and true or false)
    end

    local accent = UnderlineColor()
    line:SetColorTexture(accent.r, accent.g, accent.b, 1)
    line:SetShown(cfg.tabUnderline and true or false)
end

local function PaintBox(tab, frame, signature, selected)
    local box = EnsureTabBox(tab)

    if box.signature ~= signature or box.frame ~= frame then
        box.signature = signature
        box.frame = frame
        LayoutTabBox(tab, frame, box)
    end

    local cfg = PC.Config
    local bg = cfg.bgColor
    local alpha = cfg.bgAlpha * (selected and 1 or INACTIVE_SHARE)
    box.bg:SetColorTexture(bg.r, bg.g, bg.b, alpha)
    box.deco:SetShown(selected and true or false)
end

--- Colour, size and lay out one tab. Idempotent: this is the whole visual state
--- of a tab, recomputed, not a diff applied to it.
function Tabs:Paint(tab)
    if not tab then return end

    local cfg = PC.Config
    if not cfg.enabled or not cfg.styleTabs then return end

    local fs = TabText(tab)
    if not fs then return end

    local frame = TabFrame(tab)

    -- frame.name is Blizzard's own live copy of the window name, updated by
    -- FCF_SetWindowName, so it survives a rename without a hook of our own. The
    -- font string is the fallback for temporary windows, which have no entry in
    -- the saved window list.
    local name = (frame and frame.name) or tab.__pcName or fs:GetText()
    if name and name ~= "" then tab.__pcName = name end

    local selected = IsSelected(frame)
    local color = selected and cfg.tabSelectedColor or cfg.tabTextColor
    if tab.__pcFlashing and not selected then color = cfg.accentColor end

    local wanted = name
    if wanted and wanted ~= "" and cfg.tabUppercase then wanted = wanted:upper() end

    local boxed = Skin.BoxedTabs()
    local boxSig = boxed and BoxSignature(tab) or ""
    local line = UnderlineColor()

    -- Everything below this line is a client call, and clicking one tab
    -- repaints the whole row - four of five tabs looking exactly as they did.
    -- The two that changed, the one you left and the one you arrived at, are
    -- the only ones worth any work, and this is how they are told apart.
    local signature = table.concat({
        name or "", selected and 1 or 0, tab.__pcFlashing and 1 or 0,
        cfg.tabFontSize, cfg.tabUppercase and 1 or 0, cfg.tabUnderline and 1 or 0,
        cfg.tabFont or "", color.r, color.g, color.b,
        cfg.accentColor.r, cfg.accentColor.g, cfg.accentColor.b, boxSig,
        line.r, line.g, line.b,
    }, ":")

    -- The signature says what was last asked for. It cannot say what is
    -- actually on the tab, and those come apart: the client rewrites the tab
    -- text during its own dock setup, after we have painted, and a signature
    -- that only remembers our intent has no way to notice. The symptom was a
    -- tab that showed its ordinary name until it was clicked - clicking changes
    -- the selection, which changes the signature, which finally repaints it -
    -- and a width measured from a string that was no longer displayed.
    --
    -- So the displayed text is compared too. One read, and it is the difference
    -- between remembering what we asked for and knowing what is there.
    local displayed = fs:GetText()

    -- nil means "nothing to do here", which is different from false meaning
    -- "repainted, and the width did not change". The caller needs both.
    if tab.__pcPainted == signature and displayed == wanted then return nil end
    tab.__pcPainted = signature

    if wanted and wanted ~= "" and displayed ~= wanted then
        fs:SetText(wanted)
    end

    if not tab.__pcFont then
        local file, size, flags = fs:GetFont()
        tab.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 12, flags or "" }
    end

    -- A chosen face, or the one the tab arrived with; see Skin.Face.
    local original = tab.__pcFont[1]
    Skin.SetFace(fs, Skin.Face(cfg.tabFont, original), cfg.tabFontSize,
        tab.__pcFont[3], original)

    fs:SetTextColor(color.r, color.g, color.b)
    -- Blizzard drives the tab's colour through SetVertexColor on the font
    -- string's own highlight path too; clearing it keeps hover from washing the
    -- text out.
    if fs.SetAlpha then fs:SetAlpha(1) end

    -- Re-measure. The string is ours now - a different size, possibly a
    -- different casing - so the width Blizzard computed for its own text is no
    -- longer the right one. Whether it changed is returned to the caller,
    -- because a tab that changed width has moved every tab to the right of it
    -- and the dock has to be told.
    local resized = false
    local width = fs:GetStringWidth()
    if width and width > 0 then
        local target = width + (boxed and BOX_PADDING * 2 or 20)
        if tab.__pcWidth ~= target then
            tab.__pcWidth = target
            tab:SetWidth(target)
            resized = true
        end
    end

    if boxed then
        PaintBox(tab, frame, boxSig, selected)
        if tab.peaversUnderline then tab.peaversUnderline:Hide() end
        return resized
    end
    if tab.peaversTabBox then
        tab.peaversTabBox.bg:Hide()
        tab.peaversTabBox.deco:Hide()
        tab.peaversTabBox.signature = nil
    end

    -- The underline is the whole selected-state affordance, so it is the one
    -- texture on the tab we draw ourselves.
    if not tab.peaversUnderline then
        local underline = tab:CreateTexture(nil, "OVERLAY")
        underline.__pcOwned = true
        tab.peaversUnderline = underline
    end

    local underline = tab.peaversUnderline
    underline:ClearAllPoints()
    underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 2)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 2)
    underline:SetHeight(Skin.Hairline(tab))
    underline:SetColorTexture(line.r, line.g, line.b, 1)
    underline:SetShown(cfg.tabUnderline and selected)

    return resized
end

--- Ask the client to lay the tab row out again. Only called when a tab actually
--- changed width, because a dock update fires FCFTab_UpdateColors, which is one
--- of the hooks that calls PaintAll - hence the guard around the whole thing.
local function RelayoutDock()
    if type(_G.FCF_DockUpdate) == "function" then
        if pcall(_G.FCF_DockUpdate) then return end
    end
    if type(_G.FCFDock_UpdateTabs) == "function" and _G.GENERAL_CHAT_DOCK then
        pcall(_G.FCFDock_UpdateTabs, _G.GENERAL_CHAT_DOCK)
    end
end

local painting = false

--- Repaint every tab. Called on selection changes and on config changes; both
--- are user actions, neither is a per-frame path.
function Tabs:PaintAll()
    if painting then return end
    painting = true

    local resized = false
    Frames:Each(function(frame)
        local tab = Frames:TabFor(frame)
        if tab and Tabs:Paint(tab) then resized = true end
    end)

    if resized then RelayoutDock() end

    painting = false
end

--------------------------------------------------------------------------------
-- Alpha
--------------------------------------------------------------------------------

local function LockAlpha(tab)
    if tab.__pcAlphaLocked then return end
    tab:SetAlpha(1)
    tab.__pcAlphaLocked = true
    tab.SetAlpha = function() end
end

local function UnlockAlpha(tab)
    if not tab.__pcAlphaLocked then return end
    tab.SetAlpha = nil
    tab.__pcAlphaLocked = nil
end

--------------------------------------------------------------------------------
-- The handler
--------------------------------------------------------------------------------

local function Apply(frame)
    local cfg = PC.Config
    if not cfg.enabled or not cfg.styleTabs then return end

    local tab = Frames:TabFor(frame)
    if not tab then return end

    -- Every texture on a chat tab is chrome; the only content is the word. The
    -- glow is spared when we have no way of knowing the flashing has stopped.
    --
    -- Once per tab. A killed texture cannot come back - its Show is its Hide -
    -- so a second sweep finds nothing, and finding nothing costs two client
    -- calls a region every time the client asks us to re-apply.
    if not tab.__pcSwept then
        tab.__pcSwept = true

        local keepGlow = not CanColorFlash() and TabGlow(tab) or nil
        local regions = { tab:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "Texture"
                and region ~= keepGlow then
                Kill(region)
            end
        end

        if keepGlow and keepGlow.SetVertexColor then
            keepGlow:SetVertexColor(cfg.accentColor.r, cfg.accentColor.g, cfg.accentColor.b)
        end

        -- Highlight and pushed states are textures on the button rather than
        -- regions, so they need naming individually.
        for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture",
            "GetNormalTexture", "GetDisabledTexture" }) do
            if tab[getter] then
                local tex = tab[getter](tab)
                if tex and tex ~= keepGlow then Kill(tex) end
            end
        end
    end

    -- The strip the tabs sit in has art of its own, and now that the window's
    -- background reaches up behind it, anything left alive there shows. Guarded
    -- against UIParent: an undocked tab is parented to its own chat frame, and
    -- a stray dock arrangement must never have us sweeping the whole UI.
    -- Both the frame the tabs hang from and the one the strip is drawn on: the
    -- client nests a scroll frame between the two, and either can carry art or
    -- a fade. Alpha is inherited, so pinning the tab alone is not enough - a
    -- faded ancestor takes its tabs and the strip down with it however opaque
    -- they think they are.
    for _, ancestor in ipairs({ tab:GetParent(), Skin.StripHost(frame) }) do
        if ancestor and ancestor ~= frame and ancestor ~= _G.UIParent then
            Skin.KillChrome(ancestor)
            LockAlpha(ancestor)
        end
    end

    LockAlpha(tab)

    local resized = Tabs:Paint(tab)
    if resized ~= nil then
        if resized and not painting then RelayoutDock() end

        -- The strip above the window is measured from the tab's text, and that
        -- text has just become ours - a different size, possibly a different
        -- casing. Skin measured Blizzard's when it ran, so the cached number is
        -- stale and this is the one place that knows it.
        Skin.InvalidateMeasure(frame)
        if PC.Skin.RefreshStrip then PC.Skin:RefreshStrip(frame) end
    end
end

local function Restore(frame)
    local tab = Frames:TabFor(frame)
    if not tab then return end

    UnlockAlpha(tab)
    tab.__pcSwept = nil
    tab.__pcPainted = nil

    for _, ancestor in ipairs({ tab:GetParent(), Skin.StripHost(frame) }) do
        if ancestor and ancestor ~= frame and ancestor ~= _G.UIParent then
            UnlockAlpha(ancestor)
            Skin.ReviveChrome(ancestor)
        end
    end

    if tab.peaversUnderline then tab.peaversUnderline:Hide() end
    if tab.peaversTabBox then
        tab.peaversTabBox.bg:Hide()
        tab.peaversTabBox.deco:Hide()
        tab.peaversTabBox.signature = nil
    end

    local fs = TabText(tab)
    if fs and tab.__pcFont then
        pcall(fs.SetFont, fs, tab.__pcFont[1], tab.__pcFont[2], tab.__pcFont[3])
        if tab.__pcName then fs:SetText(tab.__pcName) end
        tab.__pcFont = nil
    end

    Skin.ReviveChrome(tab)
    for _, getter in ipairs({ "GetHighlightTexture", "GetPushedTexture",
        "GetNormalTexture", "GetDisabledTexture" }) do
        if tab[getter] then Skin.Revive(tab[getter](tab)) end
    end
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

local hooksInstalled = false

--- Kept out of Initialize: see the note on Frames:InstallHooks. A hook cannot
--- be uninstalled, so the only way for "off" to mean off is never to put one on.
function Tabs:InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- Selection changed: repaint. The important word is *changed*:
    -- FCFTab_UpdateColors runs from the dock's update path, which an arriving
    -- message dirties, so in a busy instance it runs constantly. One comparison
    -- decides there is nothing to do; renames, flashes and settings changes
    -- have triggers of their own.
    local lastSelected = nil

    for _, fname in ipairs({ "FCFTab_UpdateColors", "FCF_SelectDockFrame", "FCF_Tab_OnClick" }) do
        if type(_G[fname]) == "function" then
            hooksecurefunc(fname, function()
                if not PC.Config.enabled or not PC.Config.styleTabs then return end

                local selected = Frames:Selected()
                if selected == lastSelected then return end

                lastSelected = selected
                Tabs:PaintAll()
            end)
        end
    end

    -- The window was renamed, so the word on the tab changed.
    if type(_G.FCF_SetWindowName) == "function" then
        hooksecurefunc("FCF_SetWindowName", function(frame)
            local tab = Frames:TabFor(frame)
            if tab then
                tab.__pcName = nil
                Tabs:Paint(tab)
            end
        end)
    end

    local startFn = not flashHooked and StartFn()
    if startFn and CanColorFlash() then
        flashHooked = true

        -- The client calls this for every message arriving in a window that is
        -- not the one on screen. In a Mythic+ that is every line of the combat
        -- log, thousands of them on a big pull, and this hook is on the path of
        -- all of them.
        --
        -- So the first thing it does is notice it has nothing to do. A tab that
        -- is already flashing does not need to be told again, and the check is
        -- one field read against a repaint that could not help but allocate a
        -- string to work out it was going to change nothing.
        hooksecurefunc(startFn, function(frame)
            local tab = Frames:TabFor(frame)
            if not tab or tab.__pcFlashing then return end

            tab.__pcFlashing = true
            Tabs:Paint(tab)
        end)

        hooksecurefunc("FCF_StopAlertFlash", function(frame)
            local tab = Frames:TabFor(frame)
            if not tab or not tab.__pcFlashing then return end

            tab.__pcFlashing = nil
            Tabs:Paint(tab)
        end)
    end
end

function Tabs:Initialize()
    Frames:RegisterHandler("tabs", Apply, Restore)
end

return Tabs
