-- Mirra's Poisons - settings panel (Options -> AddOns -> Mirra's Poisons)

local addonName, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1.00, 0.78, 0.18 }

local panel
local controls = {}
local refreshing = false

---------------------------------------------------------------------------
-- Small UI helpers
---------------------------------------------------------------------------

local function AddBorder(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(FLAT)
    t:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
    t:SetAllPoints()
    return t
end

local function AddFill(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetTexture(FLAT)
    t:SetVertexColor(r, g, b, a)
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMRIGHT", -1, 1)
    return t
end

local function Changed()
    if refreshing then return end
    ns.ApplySettings()
end

local function SectionHeader(parent, text, anchor, y, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetText(string.upper(text))
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -18)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(FLAT)
    line:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetWidth((width or 300) - fs:GetStringWidth() - 8)
    return fs
end

-- Segmented control: a row of toggle buttons bound to one setting.
local function Segmented(parent, key, options, anchor, y)
    local group = { key = key, buttons = {} }
    local prev
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(opt.width or 96, 24)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -8)
        end
        b.border = AddBorder(b, 0, 0, 0, 1)
        b.fill = AddFill(b, 0.12, 0.12, 0.14, 0.95)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(opt.text)
        b.value = opt.value

        b:SetScript("OnEnter", function(self)
            if ns.db[key] ~= self.value then self.fill:SetVertexColor(0.18, 0.18, 0.21, 0.95) end
        end)
        b:SetScript("OnLeave", function(self) group:Refresh() end)
        b:SetScript("OnClick", function(self)
            ns.db[key] = self.value
            group:Refresh()
            if group.onChange then group.onChange() end
            Changed()
        end)

        group.buttons[i] = b
        prev = b
    end

    function group:Refresh()
        for _, b in ipairs(self.buttons) do
            if ns.db[self.key] == b.value then
                b.border:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
                b.fill:SetVertexColor(0.32, 0.24, 0.06, 0.95)
                b.label:SetTextColor(1, 0.92, 0.6)
            else
                b.border:SetVertexColor(0, 0, 0, 1)
                b.fill:SetVertexColor(0.12, 0.12, 0.14, 0.95)
                b.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end

    group.first = group.buttons[1]
    controls[#controls + 1] = group
    return group
end

-- `fmt` is a format string or a function(value) -> text
local function Slider(parent, key, label, minV, maxV, step, fmt, anchor, y, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 300, 34)
    holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -10)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local valueText = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", 0, 0)

    local s = CreateFrame("Slider", nil, holder)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    s:SetHeight(14)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(FLAT)
    track:SetVertexColor(0, 0, 0, 0.9)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)

    local trackFill = s:CreateTexture(nil, "BORDER")
    trackFill:SetTexture(FLAT)
    trackFill:SetVertexColor(0.16, 0.16, 0.19, 1)
    trackFill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    trackFill:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -1, 1)

    local progress = s:CreateTexture(nil, "ARTWORK")
    progress:SetTexture(FLAT)
    progress:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.55)
    progress:SetPoint("TOPLEFT", trackFill, "TOPLEFT")
    progress:SetPoint("BOTTOMLEFT", trackFill, "BOTTOMLEFT")

    s:SetThumbTexture(FLAT)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(8, 14)
    thumb:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local function UpdateVisual(v)
        if type(fmt) == "function" then
            valueText:SetText(fmt(v))
        else
            valueText:SetText(string.format(fmt, v))
        end
        local w = trackFill:GetWidth()
        if w and w > 0 then
            progress:SetWidth(math.max(1, w * (v - minV) / (maxV - minV)))
        end
    end

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        UpdateVisual(v)
        if refreshing or ns.db[key] == v then return end
        ns.db[key] = v
        Changed()
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(minV, math.min(maxV, self:GetValue() + delta * step)))
    end)
    s:SetScript("OnSizeChanged", function(self) UpdateVisual(self:GetValue()) end)

    local ctl = { holder = holder }
    function ctl:Refresh()
        s:SetValue(ns.db[key])
        UpdateVisual(ns.db[key])
    end
    controls[#controls + 1] = ctl
    return holder
end

local function Checkbox(parent, key, label, tooltip, anchor, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -3, y or -6)

    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    text:SetText(label)
    if cb.Text then cb.Text:SetText("") end
    if cb.text then cb.text:SetText("") end

    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        Changed()
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local ctl = {}
    function ctl:Refresh() cb:SetChecked(ns.db[key]) end
    controls[#controls + 1] = ctl

    -- return an anchor aligned with the section's left edge
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(1, 1)
    a:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 3, 2)
    return a
end

---------------------------------------------------------------------------
-- Preview: a tracker with sample weapons and poisons
---------------------------------------------------------------------------

local preview, previewBox, previewCaption

local SAMPLE_POISONS = {
    { type = 1, itemID = 8928,  rank = 6, count = 14 },   -- Instant Poison VI
    { type = 2, itemID = 20844, rank = 5, count = 9 },    -- Deadly Poison V
    { type = 4, itemID = 3776,  rank = 2, count = 5 },    -- Crippling Poison II
}

local function SamplePoisons()
    if #ns.bagPoisons > 0 then return ns.bagPoisons end
    for _, p in ipairs(SAMPLE_POISONS) do
        p.icon = ns.GetItemIcon(p.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    return SAMPLE_POISONS
end

function ns.RefreshPreview()
    if not panel or not panel:IsShown() or not preview then return end
    local db = ns.db
    local poisons = SamplePoisons()
    local mh, oh = ns.HANDS[1], ns.HANDS[2]
    local rows = {
        { hand = mh, weaponIcon = "Interface\\Icons\\INV_Sword_04", status = "missing",
          poisons = poisons, last = poisons[1] and poisons[1].type },
    }

    local deadly = ns.GetItemName(20844) or "Deadly Poison V"
    local caption
    if db.lowTime > 0 or db.lowCharges > 0 then
        local timeLeft = db.lowTime > 0 and math.max(30, db.lowTime * 60 - 60) or 24 * 60
        local charges = db.lowCharges > 0 and math.max(1, db.lowCharges - 3) or 38
        rows[2] = { hand = oh, weaponIcon = "Interface\\Icons\\INV_Weapon_ShortBlade_05", status = "low",
            name = deadly, timeLeft = timeLeft, charges = charges, poisons = poisons }
        caption = "Main hand: no poison  -  off hand: running low"
    elseif db.showMode == "always" then
        rows[2] = { hand = oh, weaponIcon = "Interface\\Icons\\INV_Weapon_ShortBlade_05", status = "ok",
            name = deadly, timeLeft = 24 * 60, charges = 38, poisons = poisons }
        caption = "Main hand: no poison  -  off hand: poisoned"
    else
        caption = "Only the hand without poison is shown"
    end

    ns.RenderTracker(preview, { rows = rows })

    -- fit the sample into the box
    local w, h = preview:GetWidth(), preview:GetHeight()
    local maxW, maxH = previewBox:GetWidth() - 20, previewBox:GetHeight() - 60
    local s = math.min(1, maxW / w, maxH / h)
    preview:SetScale(s)
    preview:ClearAllPoints()
    preview:SetPoint("TOP", previewBox, "TOP", 0, -32 / s)
    previewCaption:SetText(caption)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function RefreshAll()
    refreshing = true
    for _, c in ipairs(controls) do c:Refresh() end
    refreshing = false
    if controls.showHint then controls.showHint() end
    ns.RefreshPreview()
end

local function BuildPanel()
    panel = CreateFrame("Frame", "MirraPoisonsOptionsPanel")
    panel:Hide()
    panel.name = ns.title

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.title)

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Shows weapons without poison - one click applies a poison from your bags.")
    sub:SetTextColor(0.75, 0.75, 0.75)

    -- Left column ---------------------------------------------------------
    local h = SectionHeader(panel, "Show", sub, -20)
    local show = Segmented(panel, "showMode", {
        { text = "Only when needed", value = "missing", width = 148 },
        { text = "Always",           value = "always",  width = 148 },
    }, h, -8)

    local showHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    showHint:SetPoint("TOPLEFT", show.first, "BOTTOMLEFT", 0, -6)
    showHint:SetWidth(300)
    showHint:SetJustifyH("LEFT")
    controls.showHint = function()
        if ns.db.showMode == "always" then
            showHint:SetText("Both weapons are always shown with poison, time and charges.")
        else
            showHint:SetText("Appears as soon as a weapon has no poison (or is running low).")
        end
    end
    show.onChange = controls.showHint

    local a = Checkbox(panel, "hideNoPoisons", "Hide when you carry no poisons",
        "Keeps the tracker hidden while there is no poison in your bags, e.g. before you learned poisons.", showHint, -6)
    a = Checkbox(panel, "hideResting", "Hide in cities and inns",
        "Hides the tracker while you are resting.", a, -2)

    h = SectionHeader(panel, "Warn early", a, -14)
    a = Slider(panel, "lowTime", "Warn when less time is left", 0, 30, 1,
        function(v) return v == 0 and "Off" or string.format("%d min", v) end, h, -10)
    a = Slider(panel, "lowCharges", "Warn when fewer charges are left", 0, 60, 1,
        function(v) return v == 0 and "Off" or string.format("%d", v) end, a, -8)

    h = SectionHeader(panel, "Alerts", a, -16)
    a = Checkbox(panel, "alertSound", "Sound when a poison runs out",
        "Plays the raid warning sound when a poison on one of your weapons runs out.", h, -6)
    a = Checkbox(panel, "alertText", "Warning text when a poison runs out",
        "Shows \"No poison on your Main Hand!\" in the middle of the screen.", a, -2)
    a = Checkbox(panel, "pulse", "Pulse a weapon without poison",
        "The red frame around the weapon icon pulses while it has no poison.", a, -2)
    a = Checkbox(panel, "autoReplace", "Confirm replacing a poison",
        "When you click a poison while the weapon still has one, the \"replace\" question is answered for you.", a, -2)

    -- Right column: preview -----------------------------------------------
    previewBox = CreateFrame("Frame", nil, panel)
    previewBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 356, -62)
    previewBox:SetSize(270, 160)
    AddBorder(previewBox, 0, 0, 0, 1)
    AddFill(previewBox, 0.05, 0.05, 0.07, 0.9)

    local boxTitle = previewBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    boxTitle:SetPoint("TOPLEFT", 10, -10)
    boxTitle:SetText("PREVIEW")
    boxTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    preview = ns.CreateTracker(previewBox, false)
    previewCaption = previewBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    previewCaption:SetPoint("BOTTOM", 0, 10)

    -- Right column: look and position -------------------------------------
    local boxAnchor = CreateFrame("Frame", nil, panel)
    boxAnchor:SetSize(1, 1)
    boxAnchor:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", 0, 0)

    h = SectionHeader(panel, "Look", boxAnchor, -16, 270)
    local r = Slider(panel, "iconSize", "Icon size", 20, 48, 1, "%d px", h, -10, 270)
    r = Slider(panel, "scale", "Scale", 60, 150, 5, "%d %%", r, -8, 270)
    r = Checkbox(panel, "showStatus", "Show poison, time and charges",
        "Shows the current poison, remaining time and charges next to the weapon.", r, -6)
    r = Checkbox(panel, "showTitle", "Show title",
        "Shows the small \"Mirra's Poisons\" header above the weapons.", r, -2)

    h = SectionHeader(panel, "Position", r, -14, 270)
    r = Checkbox(panel, "locked", "Lock position",
        "Unlock to drag the tracker with the left mouse button. Also: /mpoison unlock", h, -6)
    local resetPos = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPos:SetSize(130, 22)
    resetPos:SetPoint("TOPLEFT", r, "BOTTOMLEFT", 0, -8)
    resetPos:SetText("Reset position")
    resetPos:SetScript("OnClick", function() ns.ResetPosition() end)

    -- Footer ------------------------------------------------------------
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -16)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        for k, v in pairs(ns.defaults) do ns.db[k] = v end
        ns.ApplySettings()
        RefreshAll()
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -10)
    hint:SetText("Commands: /mpoison unlock, /mpoison lock, /mpoison reset, /mpoison debug")

    panel:SetScript("OnShow", RefreshAll)
end

function ns.BuildOptions()
    if panel then return end
    BuildPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
        Settings.RegisterAddOnCategory(category)
        ns.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenOptions()
    if ns.category and Settings and Settings.OpenToCategory then
        local id = ns.category.GetID and ns.category:GetID() or ns.category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
