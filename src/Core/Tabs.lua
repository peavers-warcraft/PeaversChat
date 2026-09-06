--------------------------------------------------------------------------------
-- Tabs
--
-- Blizzard's chat tab is nine textures and a gold blink. This turns it into a
-- word: uppercase, grey when it is not the tab you are reading, white with an
-- accent underline when it is.
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

local PeaversCommons = _G.PeaversCommons

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
    if name and name ~= "" then
        tab.__pcName = name
        fs:SetText(cfg.tabUppercase and name:upper() or name)
    end

    if not tab.__pcFont then
        local file, size, flags = fs:GetFont()
        tab.__pcFont = { file or _G.STANDARD_TEXT_FONT, size or 12, flags or "" }
    end

    -- A chosen face, or the one the tab arrived with. The locale check is the
    -- reason this is not just a string swap: none of the Latin faces carry CJK
    -- glyphs, and applying one to a Chinese client renders empty boxes. The
    -- pcall then covers the other failure - a LibSharedMedia path for an addon
    -- that has since been uninstalled - by leaving the font alone.
    local face = cfg.tabFont
    if face == "" or face == nil then
        face = tab.__pcFont[1]
    elseif PeaversCommons.ConfigManager.IsFontCompatibleWithLocale
        and not PeaversCommons.ConfigManager.IsFontCompatibleWithLocale(face) then
        face = tab.__pcFont[1]
    end

    if not pcall(fs.SetFont, fs, face, cfg.tabFontSize, tab.__pcFont[3]) then
        pcall(fs.SetFont, fs, tab.__pcFont[1], cfg.tabFontSize, tab.__pcFont[3])
    end

    local selected = IsSelected(frame)
    local color = selected and cfg.tabSelectedColor or cfg.tabTextColor
    if tab.__pcFlashing and not selected then color = cfg.accentColor end

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
        local target = width + 20
        if tab.__pcWidth ~= target then
            tab.__pcWidth = target
            tab:SetWidth(target)
            resized = true
        end
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
    underline:SetColorTexture(cfg.accentColor.r, cfg.accentColor.g, cfg.accentColor.b, 1)
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
    if Tabs:Paint(tab) and not painting then RelayoutDock() end

    -- The strip above the window is measured from the tab's text, and the text
    -- has only just become ours - a different size, possibly a different casing.
    -- Skin measured Blizzard's when it ran; this is the corrected number.
    if PC.Skin.RefreshStrip then PC.Skin:RefreshStrip(frame) end
end

local function Restore(frame)
    local tab = Frames:TabFor(frame)
    if not tab then return end

    UnlockAlpha(tab)

    for _, ancestor in ipairs({ tab:GetParent(), Skin.StripHost(frame) }) do
        if ancestor and ancestor ~= frame and ancestor ~= _G.UIParent then
            UnlockAlpha(ancestor)
            Skin.ReviveChrome(ancestor)
        end
    end

    if tab.peaversUnderline then tab.peaversUnderline:Hide() end

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

function Tabs:Initialize()
    Frames:RegisterHandler("tabs", Apply, Restore)

    -- Selection changed: repaint. Each of these is guarded because chat is one
    -- of the areas Blizzard reworks, and a missing global should cost the
    -- repaint trigger rather than the addon.
    for _, fname in ipairs({ "FCFTab_UpdateColors", "FCF_SelectDockFrame", "FCF_Tab_OnClick" }) do
        if type(_G[fname]) == "function" then
            hooksecurefunc(fname, function()
                if PC.Config.enabled and PC.Config.styleTabs then Tabs:PaintAll() end
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

    if not flashHooked and CanColorFlash() then
        flashHooked = true

        hooksecurefunc(StartFn(), function(frame)
            local tab = Frames:TabFor(frame)
            if tab then
                tab.__pcFlashing = true
                Tabs:Paint(tab)
            end
        end)

        hooksecurefunc("FCF_StopAlertFlash", function(frame)
            local tab = Frames:TabFor(frame)
            if tab then
                tab.__pcFlashing = nil
                Tabs:Paint(tab)
            end
        end)
    end
end

return Tabs
