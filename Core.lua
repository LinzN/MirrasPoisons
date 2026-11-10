-- Mirra's Poisons
-- Rogue poison tracker: shows which weapons have no poison and applies a poison
-- from your bags to the main hand or off hand with a single click.
-- Written for WoW Forever (Interface 16001), where many API results can be
-- "secret values" in combat: they may be passed to widgets, but must never be
-- compared, used in arithmetic or tested for truthiness from addon code.

local addonName, ns = ...

ns.title = "Mirra's Poisons"

ns.defaults = {
    showMode      = "missing", -- "missing": only when a weapon needs poison, "always"
    lowTime       = 0,         -- also warn when less than N minutes are left (0 = off)
    lowCharges    = 0,         -- also warn when less than N charges are left (0 = off)
    iconSize      = 32,
    scale         = 100,       -- %
    showStatus    = true,      -- poison name, time and charges next to the weapon
    showTitle     = true,      -- small "Mirra's Poisons" header
    pulse         = true,      -- pulsing red frame around a weapon without poison
    alertSound    = true,      -- sound when a poison runs out
    alertText     = true,      -- raid warning text when a poison runs out
    hideResting   = false,     -- hide in cities and inns
    hideNoPoisons = true,      -- hide while you carry no poisons at all
    autoReplace   = true,      -- confirm "replace enchant" after clicking one of our buttons
    locked        = true,
}

ns.colors = {
    good = { 0.30, 0.85, 0.40 },
    warn = { 1.00, 0.78, 0.18 },
    bad  = { 0.95, 0.26, 0.22 },
    gold = { 1.00, 0.78, 0.18 },
    dim  = { 0.60, 0.60, 0.60 },
}

ns.lastError = nil

local FLAT     = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local GOLD     = ns.colors.gold

---------------------------------------------------------------------------
-- Compatibility and secret value helpers
---------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns the value when it may be inspected, otherwise nil ("unknown").
local function Known(v)
    if IsSecret(v) then return nil end
    return v
end

local function NoteError(where, err)
    ns.lastError = where .. ": " .. tostring(err)
end

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo        = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestItemData    = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

local function GetItemName(id)
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(id)
        if name then return name end
    end
    return (GetItemInfo(id))
end

local function GetItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(id)
        if icon then return icon end
    end
    return select(5, GetItemInfoInstant(id))
end

ns.GetItemName = GetItemName
ns.GetItemIcon = GetItemIcon

local function NumBagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- itemID and stack count of a bag slot
local function BagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        if not id and link then id = tonumber(link:match("item:(%d+)")) end
        return id, count
    end
end

---------------------------------------------------------------------------
-- Poison data
---------------------------------------------------------------------------

-- Every poison type with its items from rank 1 to the highest rank.
-- Unknown (new) ranks are recognised by name, see Classify().
local POISONS = {
    { key = "instant",   ids = { 6947, 6949, 6950, 8926, 8927, 8928 } },
    { key = "deadly",    ids = { 2892, 2893, 8984, 8985, 20844 } },
    { key = "wound",     ids = { 10918, 10920, 10921, 10922 } },
    { key = "crippling", ids = { 3775, 3776 } },
    { key = "mind",      ids = { 5237, 6951, 9186 } },
}
ns.POISONS = POISONS

local ITEM_TO_POISON = {}   -- itemID -> { type = index, rank = n }
for t, p in ipairs(POISONS) do
    for rank, id in ipairs(p.ids) do
        ITEM_TO_POISON[id] = { type = t, rank = rank }
    end
end

local ROMAN = { I = 1, V = 5, X = 10 }
local function RomanToInt(s)
    local total, prev = 0, 0
    for i = #s, 1, -1 do
        local v = ROMAN[s:sub(i, i)] or 0
        if v < prev then total = total - v else total = total + v; prev = v end
    end
    return total
end

-- "Instant Poison VI" -> "Instant Poison", 6
local function SplitRank(name)
    local base, numeral = name:match("^(.-)%s+([IVX]+)$")
    if base then return base, RomanToInt(numeral) end
    return name, 1
end

-- Localized base names ("Instant Poison", "Sofort wirkendes Gift", ...),
-- read from the rank 1 items so the addon works in every client language.
local baseNames = {}
local poisonWord        -- last word of a base name ("Poison", "Gift"), fallback for tooltip lines

local function LoadBaseNames()
    local missing = false
    for t, p in ipairs(POISONS) do
        if not baseNames[t] then
            local name = GetItemName(p.ids[1])
            if name then
                baseNames[t] = (SplitRank(name))
            else
                RequestItemData(p.ids[1])
                missing = true
            end
        end
    end
    if not poisonWord and baseNames[1] then
        poisonWord = baseNames[1]:match("(%S+)$")
    end
    return not missing
end

local classifyCache = {}

-- Returns poison type index and rank for an item, or nil.
local function Classify(id)
    local known = ITEM_TO_POISON[id]
    if known then return known.type, known.rank end
    local cached = classifyCache[id]
    if cached ~= nil then
        if cached then return cached.type, cached.rank end
        return nil
    end
    local name = GetItemName(id)
    if not name then return nil end             -- not cached yet, try again later
    local base, rank = SplitRank(name)
    for t = 1, #POISONS do
        if baseNames[t] and base == baseNames[t] then
            classifyCache[id] = { type = t, rank = rank }
            return t, rank
        end
    end
    -- only remember "not a poison" once all poison names are known
    local allNames = true
    for t = 1, #POISONS do
        if not baseNames[t] then allNames = false end
    end
    if allNames then classifyCache[id] = false end
    return nil
end

---------------------------------------------------------------------------
-- Bag scan: best poison of every type in your bags
---------------------------------------------------------------------------

ns.bagPoisons = {}    -- ordered list of { type, itemID, rank, count, icon }

local function ScanBags()
    local best = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local counts = {}
    for bag = 0, lastBag do
        for slot = 1, NumBagSlots(bag) do
            local id, count = BagItem(bag, slot)
            if id then
                local t, rank = Classify(id)
                if t then
                    counts[id] = (counts[id] or 0) + (count or 1)
                    local b = best[t]
                    if not b or rank > b.rank or (rank == b.rank and id > b.itemID) then
                        best[t] = { type = t, itemID = id, rank = rank }
                    end
                end
            end
        end
    end
    local list = {}
    for t = 1, #POISONS do
        local b = best[t]
        if b then
            b.count = counts[b.itemID] or 0
            b.icon = GetItemIcon(b.itemID) or QUESTION
            list[#list + 1] = b
        end
    end
    ns.bagPoisons = list
end

---------------------------------------------------------------------------
-- Weapon state
---------------------------------------------------------------------------

ns.HANDS = {
    { key = "MH", slot = 16, label = "Main Hand", lastKey = "lastMH" },
    { key = "OH", slot = 17, label = "Off Hand",  lastKey = "lastOH" },
}
local HANDS = ns.HANDS

ns.states = { MH = { status = "none" }, OH = { status = "none" } }

-- true when the slot holds a real weapon (no shield, held-in-off-hand item or fishing pole)
local function WeaponInSlot(slot)
    local id = GetInventoryItemID("player", slot)
    if not id then return nil end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
    if classID == 2 and subclassID ~= 20 then return id end
    return nil
end

-- GetWeaponEnchantInfo for one hand: has, seconds left, charges (nil = unknown)
local function EnchantInfo(index)
    local ok, hasMH, mhExp, mhCharges, _, hasOH, ohExp, ohCharges = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    local has, exp, charges
    if index == 1 then
        has, exp, charges = hasMH, mhExp, mhCharges
    else
        has, exp, charges = hasOH, ohExp, ohCharges
    end
    if IsSecret(has) then return nil end
    has = has and true or false
    exp = Known(exp)
    charges = Known(charges)
    return has, (has and type(exp) == "number") and exp / 1000 or nil,
        (has and type(charges) == "number" and charges > 0) and charges or nil
end

-- Tooltip lines of an equipped item, or nil when they can't be read.
local scanTip
local function TooltipLines(slot)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            local out = {}
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if IsSecret(text) then return nil end
                if type(text) == "string" then out[#out + 1] = text end
            end
            return out
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "MirraPoisonsScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slot)
    local out = {}
    for i = 1, scanTip:NumLines() do
        local fs = _G["MirraPoisonsScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if IsSecret(text) then return nil end
        if type(text) == "string" then out[#out + 1] = text end
    end
    scanTip:Hide()
    return out
end

-- Looks for a poison line ("Instant Poison VI (29 min)") in the weapon tooltip.
-- Returns found, poison name, reliable. Unreliable when the tooltip or the
-- localized poison names are not available yet.
local function TooltipPoison(slot)
    local lines = TooltipLines(slot)
    if not lines or not baseNames[1] then return false, nil, false end
    for i = 2, #lines do               -- line 1 is the weapon name
        local line = lines[i]
        for t = 1, #POISONS do
            local base = baseNames[t]
            if base and line:find(base, 1, true) then
                return true, strtrim((line:gsub("%s*%b()", ""))), true
            end
        end
        -- poison types this addon does not know yet: "<...Poison...> (30 min)"
        if poisonWord and line:lower():find(poisonWord:lower(), 1, true) and line:find("%(%d") then
            return true, strtrim((line:gsub("%s*%b()", ""))), true
        end
    end
    return false, nil, true
end

local function ReadHand(hand, index)
    local prev = ns.states[hand.key]
    local st = { weaponID = WeaponInSlot(hand.slot) }
    if not st.weaponID then
        st.status = "none"
        return st
    end

    local has, timeLeft, charges = EnchantInfo(index)
    local ok, tipFound, tipName, reliable = pcall(TooltipPoison, hand.slot)
    if not ok then
        NoteError("Tooltip", tipFound)
        tipFound, tipName, reliable = false, nil, false
    end

    local poisoned
    if reliable then
        poisoned = tipFound
    elseif has ~= nil then
        poisoned = has
    end

    if poisoned == nil then
        -- values are secret right now (combat): keep the last known state
        if prev and prev.weaponID == st.weaponID and prev.status ~= "none" then
            for k, v in pairs(prev) do st[k] = v end
            return st
        end
        st.status = "unknown"
        return st
    end

    if not poisoned then
        st.status = "missing"
        return st
    end

    st.name = tipName
    st.timeLeft = timeLeft
    st.charges = charges
    st.status = "ok"
    local db = ns.db
    if (db.lowTime > 0 and timeLeft and timeLeft < db.lowTime * 60)
        or (db.lowCharges > 0 and charges and charges < db.lowCharges) then
        st.status = "low"
    end
    return st
end

---------------------------------------------------------------------------
-- Tracker widget (also used for the preview in the settings)
---------------------------------------------------------------------------

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"

local TINT = {
    frame     = { 0.30, 0.29, 0.34 },   -- neutral icon frame
    frameLast = { 1.00, 0.78, 0.18 },   -- last poison used on this hand
    frameHover = { 1.00, 0.92, 0.62 },
}

-- Nine-slice from a square texture: corners keep their size, edges stretch.
local function NineSlice(f, file, texSize, corner, layer, sub, outset)
    local o = outset or 0
    local c = corner / texSize
    local coords = {
        { 0, c, 0, c }, { c, 1 - c, 0, c }, { 1 - c, 1, 0, c },
        { 0, c, c, 1 - c }, { c, 1 - c, c, 1 - c }, { 1 - c, 1, c, 1 - c },
        { 0, c, 1 - c, 1 }, { c, 1 - c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 },
    }
    local p = {}
    for i = 1, 9 do
        local t = f:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(file)
        t:SetTexCoord(coords[i][1], coords[i][2], coords[i][3], coords[i][4])
        p[i] = t
    end
    for _, i in ipairs({ 1, 3, 7, 9 }) do p[i]:SetSize(corner, corner) end
    p[1]:SetPoint("TOPLEFT", -o, o)
    p[3]:SetPoint("TOPRIGHT", o, o)
    p[7]:SetPoint("BOTTOMLEFT", -o, -o)
    p[9]:SetPoint("BOTTOMRIGHT", o, -o)
    p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT");     p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
    p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT");     p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
    p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT");   p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
    p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT");   p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
    p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT");  p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
    return {
        parts = p,
        SetVertexColor = function(self, r, g, b, a)
            for _, t in ipairs(self.parts) do t:SetVertexColor(r, g, b, a) end
        end,
    }
end

-- Rounded icon: mask texture when the client supports it, small inset otherwise.
local function RoundIcon(owner, tex)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if owner.CreateMaskTexture and tex.AddMaskTexture then
        local ok = pcall(function()
            local m = owner:CreateMaskTexture()
            m:SetTexture(MEDIA .. "iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(owner)
            tex:AddMaskTexture(m)
            owner.iconMask = m
        end)
        if ok then
            tex:SetAllPoints(owner)
            return
        end
    end
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
end

-- Black vertical gradient (bottom alpha -> top alpha)
local function ShadeGradient(tex, bottom, top)
    tex:SetTexture(FLAT)
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(0, 0, 0, bottom), CreateColor(0, 0, 0, top)) then return end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", 0, 0, 0, bottom, 0, 0, 0, top)
        return
    end
    tex:SetVertexColor(0, 0, 0, bottom * 0.6)
end

local function HGradient(tex, r, g, b, left, right)
    tex:SetTexture(FLAT)
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, left), CreateColor(r, g, b, right)) then return end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "HORIZONTAL", r, g, b, left, r, g, b, right)
        return
    end
    tex:SetVertexColor(r, g, b, left * 0.5)
end

local function FormatTime(sec)
    if sec >= 3600 then return string.format("%d h", math.floor(sec / 3600)) end
    if sec >= 60 then return string.format("%d min", math.floor(sec / 60 + 0.5)) end
    return string.format("%d s", math.floor(sec))
end
ns.FormatTime = FormatTime

local function SetFrameTint(b)
    local c = TINT.frame
    if b.hovered then c = TINT.frameHover elseif b.isLast then c = TINT.frameLast end
    b.frame:SetVertexColor(c[1], c[2], c[3], 1)
    b.glow:SetShown(b.isLast or b.hovered)
    b.glow:SetAlpha(b.hovered and 0.55 or 0.35)
end

local function PoisonButton_OnEnter(self)
    self.hovered = true
    SetFrameTint(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: apply to your " .. (self.hand and self.hand.label or "weapon"),
        GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:Show()
end

local function PoisonButton_OnLeave(self)
    self.hovered = false
    SetFrameTint(self)
    self.icon:SetVertexColor(1, 1, 1)
    GameTooltip:Hide()
end

local function PoisonButton_PreClick(self)
    if not self.hand or not self.poisonType then return end
    ns.db[self.hand.lastKey] = self.poisonType
    ns.lastClick = GetTime()
end

local function CreatePoisonButton(parent, secure)
    local b
    if secure then
        b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        b:HookScript("PreClick", PoisonButton_PreClick)
    else
        b = CreateFrame("Button", nil, parent)
    end

    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(MEDIA .. "glow")
    b.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    b.glow:SetBlendMode("ADD")
    b.glow:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    RoundIcon(b, b.icon)

    -- dark fade at the bottom so the count stays readable
    b.shade = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.shade:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMLEFT")
    b.shade:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT")
    ShadeGradient(b.shade, 0.85, 0)
    if b.iconMask then b.shade:AddMaskTexture(b.iconMask) end

    b.frame = b:CreateTexture(nil, "OVERLAY")
    b.frame:SetTexture(MEDIA .. "iconframe")
    b.frame:SetAllPoints()

    b.count = b:CreateFontString(nil, "OVERLAY", nil, 2)
    b.count:SetJustifyH("RIGHT")

    b:SetScript("OnEnter", PoisonButton_OnEnter)
    b:SetScript("OnLeave", PoisonButton_OnLeave)
    b:SetScript("OnMouseDown", function(self) self.icon:SetVertexColor(0.7, 0.7, 0.7) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetVertexColor(1, 1, 1) end)
    b.secure = secure
    SetFrameTint(b)
    return b
end

local function CreateRow(tracker)
    local row = CreateFrame("Frame", nil, tracker)

    -- card background and a colored status accent on the left
    row.card = NineSlice(row, MEDIA .. "card", 32, 8, "BACKGROUND", 1)
    row.accent = row:CreateTexture(nil, "BORDER")
    row.accent:SetTexture(FLAT)
    row.accent:SetWidth(2)
    row.accent:SetPoint("TOPLEFT", 1, -6)
    row.accent:SetPoint("BOTTOMLEFT", 1, 6)
    row.tint = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.tint:SetPoint("TOPLEFT", 3, -1)
    row.tint:SetPoint("BOTTOMLEFT", 3, 1)
    row.tint:SetWidth(90)

    local w = CreateFrame("Frame", nil, row)
    w.glow = w:CreateTexture(nil, "BACKGROUND")
    w.glow:SetTexture(MEDIA .. "glow")
    w.glow:SetBlendMode("ADD")
    w.glow:Hide()
    w.icon = w:CreateTexture(nil, "ARTWORK")
    RoundIcon(w, w.icon)
    w.frame = w:CreateTexture(nil, "OVERLAY")
    w.frame:SetTexture(MEDIA .. "iconframe")
    w.frame:SetAllPoints()
    w.pulse = w.glow:CreateAnimationGroup()
    w.pulse:SetLooping("BOUNCE")
    local a = w.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.2)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    row.weapon = w

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFont(STANDARD_TEXT_FONT, 9, "")
    row.label:SetShadowOffset(1, -1)
    row.label:SetJustifyH("LEFT")
    row.status = row:CreateFontString(nil, "OVERLAY")
    row.status:SetFont(STANDARD_TEXT_FONT, 11, "")
    row.status:SetShadowOffset(1, -1)
    row.status:SetJustifyH("LEFT")
    row.status:SetWordWrap(false)

    row.divider = row:CreateTexture(nil, "BORDER")
    row.divider:SetTexture(FLAT)
    row.divider:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.16)
    row.divider:SetWidth(1)

    row.empty = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.empty:SetText("No poisons in your bags")
    row.empty:Hide()

    row.buttons = {}
    return row
end

function ns.CreateTracker(parent, secure, name)
    local t = CreateFrame("Frame", name, parent)
    t:SetSize(200, 50)
    t.secure = secure
    t.rows = {}
    -- rounded panel with gold rim and soft shadow (texture body starts 10 px in)
    t.bg = NineSlice(t, MEDIA .. "panel", 64, 20, "BACKGROUND", -8, 10)

    t.logo = t:CreateTexture(nil, "ARTWORK")
    t.logo:SetTexture(MEDIA .. "icon")
    t.logo:SetSize(14, 14)
    t.logo:SetPoint("TOPLEFT", 8, -6)
    t.title = t:CreateFontString(nil, "OVERLAY")
    t.title:SetFont(STANDARD_TEXT_FONT, 9, "")
    t.title:SetShadowOffset(1, -1)
    t.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    t.title:SetPoint("LEFT", t.logo, "RIGHT", 5, 0)
    t.titleLine = t:CreateTexture(nil, "ARTWORK")
    t.titleLine:SetHeight(1)
    t.titleLine:SetPoint("LEFT", t.title, "RIGHT", 8, 0)
    t.titleLine:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    HGradient(t.titleLine, GOLD[1], GOLD[2], GOLD[3], 0.45, 0)

    t.placeholder = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t.placeholder:Hide()
    return t
end

local function StatusColor(status)
    local c = ns.colors
    if status == "missing" then return c.bad end
    if status == "low" then return c.warn end
    if status == "unknown" then return c.dim end
    return c.good
end

-- Text and colors of one row. Safe in combat.
local function RenderRowStatus(row, rm)
    local db = ns.db
    local col = StatusColor(rm.status)
    local text
    if rm.status == "missing" then
        text = "No poison"
    elseif rm.status == "unknown" then
        text = "..."
    else
        local parts = {}
        if rm.name then parts[#parts + 1] = rm.name end
        if rm.timeLeft then parts[#parts + 1] = FormatTime(rm.timeLeft) end
        if rm.charges then parts[#parts + 1] = rm.charges .. "x" end
        if #parts == 0 then parts[1] = "Poisoned" end
        text = table.concat(parts, "  |cff8c8c8c·|r  ")
    end
    row.label:SetText(string.upper(rm.hand.label))
    row.label:SetTextColor(0.78, 0.70, 0.52)
    row.status:SetText(text)
    row.status:SetTextColor(col[1], col[2], col[3])

    local alarm = rm.status == "missing" or rm.status == "low"
    local ok = rm.status == "ok"
    row.accent:SetVertexColor(col[1], col[2], col[3], ok and 0.55 or 0.95)
    HGradient(row.tint, col[1], col[2], col[3], alarm and 0.16 or 0.05, 0)
    if rm.status == "missing" then
        row.card:SetVertexColor(1, 0.55, 0.50, 0.10)
    else
        row.card:SetVertexColor(1, 1, 1, 0.06)
    end

    local w = row.weapon
    local missing = rm.status == "missing"
    w.icon:SetDesaturated(missing)
    w.icon:SetVertexColor(missing and 0.75 or 1, missing and 0.62 or 1, missing and 0.62 or 1)
    if alarm then
        w.frame:SetVertexColor(col[1], col[2], col[3], 1)
        w.glow:SetVertexColor(col[1], col[2], col[3])
        w.glow:Show()
    else
        w.frame:SetVertexColor(TINT.frame[1], TINT.frame[2], TINT.frame[3], 1)
        w.glow:Hide()
    end
    if missing and db.pulse then
        if not w.pulse:IsPlaying() then w.pulse:Play() end
    else
        w.pulse:Stop()
        w.glow:SetAlpha(0.6)
    end

    for _, b in ipairs(row.buttons) do
        if b:IsShown() and b.itemID then
            b.isLast = rm.last ~= nil and rm.last == b.poisonType
            SetFrameTint(b)
            local n = rm.countByItem and rm.countByItem[b.itemID]
            if n then b.count:SetText(n) end
        end
    end
end

-- Full layout: rows, buttons, sizes and secure attributes. Out of combat only
-- for the real tracker (secure buttons can't be changed in combat).
function ns.RenderTracker(t, model)
    local db = ns.db
    local size = db.iconSize
    local pad = 8
    local gap = 5
    local rowH = size + 10
    local glowOut = math.floor(size * 0.45)

    -- header
    local showTitle = db.showTitle or not db.locked
    local top = pad
    t.logo:SetShown(showTitle)
    t.title:SetShown(showTitle)
    t.titleLine:SetShown(showTitle)
    if showTitle then
        t.title:SetText(db.locked and "MIRRA'S POISONS" or "MIRRA'S POISONS  |cffbbbbbb- drag to move|r")
        top = 26
    end

    -- pass 1: rows and texts, so the text column can be measured
    local textW = 0
    for i, rm in ipairs(model.rows) do
        local row = t.rows[i]
        if not row then
            row = CreateRow(t)
            t.rows[i] = row
        end
        row.handKey = rm.hand.key
        rm.countByItem = {}
        for _, p in ipairs(rm.poisons) do rm.countByItem[p.itemID] = p.count end
        RenderRowStatus(row, rm)
        textW = math.max(textW, row.label:GetStringWidth())
        if db.showStatus then textW = math.max(textW, row.status:GetStringWidth()) end
    end
    textW = math.min(180, math.max(56, math.ceil(textW) + 12))

    -- pass 2: positions
    local maxW = 0
    local y = -top
    for i, rm in ipairs(model.rows) do
        local row = t.rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", pad, y)
        row:SetHeight(rowH)

        local w = row.weapon
        w:SetSize(size, size)
        w:ClearAllPoints()
        w:SetPoint("LEFT", row, "LEFT", 8, 0)
        w.icon:SetTexture(rm.weaponIcon or QUESTION)
        w.glow:ClearAllPoints()
        w.glow:SetPoint("TOPLEFT", -glowOut, glowOut)
        w.glow:SetPoint("BOTTOMRIGHT", glowOut, -glowOut)

        row.label:ClearAllPoints()
        row.status:ClearAllPoints()
        row.status:SetWidth(textW)
        if db.showStatus then
            row.label:SetPoint("BOTTOMLEFT", w, "RIGHT", 9, 2)
            row.status:SetPoint("TOPLEFT", w, "RIGHT", 9, -1)
            row.status:Show()
        else
            row.label:SetPoint("LEFT", w, "RIGHT", 9, 0)
            row.status:Hide()
        end

        local x = 8 + size + 9 + textW + 4
        row.divider:ClearAllPoints()
        row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", x, -7)
        row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 7)
        x = x + 9

        local fontSize = math.max(9, math.floor(size * 0.34))
        for j, p in ipairs(rm.poisons) do
            local b = row.buttons[j]
            if not b then
                b = CreatePoisonButton(row, t.secure)
                row.buttons[j] = b
            end
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", row, "LEFT", x, 0)
            b.glow:ClearAllPoints()
            b.glow:SetPoint("TOPLEFT", -glowOut, glowOut)
            b.glow:SetPoint("BOTTOMRIGHT", glowOut, -glowOut)
            b.shade:SetHeight(size * 0.5)
            b.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
            b.count:ClearAllPoints()
            b.count:SetPoint("BOTTOMRIGHT", -3, 3)
            b.icon:SetTexture(p.icon)
            b.count:SetText(p.count)
            b.itemID = p.itemID
            b.poisonType = p.type
            b.hand = rm.hand
            b.isLast = rm.last ~= nil and rm.last == p.type
            SetFrameTint(b)
            if b.secure then
                b:SetAttribute("macrotext", string.format("/use item:%d\n/use %d", p.itemID, rm.hand.slot))
            end
            b:Show()
            x = x + size + gap
        end
        for j = #rm.poisons + 1, #row.buttons do
            local b = row.buttons[j]
            b:Hide()
            b.itemID = nil
            if b.secure then b:SetAttribute("macrotext", nil) end
        end
        row.empty:ClearAllPoints()
        row.empty:SetPoint("LEFT", row, "LEFT", x, 0)
        row.empty:SetShown(#rm.poisons == 0)
        if #rm.poisons == 0 then x = x + row.empty:GetStringWidth() + gap end

        local rw = x - gap + 8
        if rw > maxW then maxW = rw end
        row:Show()
        y = y - rowH - 5
    end
    -- all cards share one width
    for i = 1, #model.rows do t.rows[i]:SetWidth(maxW) end
    for i = #model.rows + 1, #t.rows do
        t.rows[i]:Hide()
        t.rows[i].handKey = nil
    end

    if #model.rows == 0 then
        t.placeholder:SetText(model.placeholder or "")
        t.placeholder:ClearAllPoints()
        t.placeholder:SetPoint("TOPLEFT", pad + 2, -(top + 4))
        t.placeholder:Show()
        t:SetSize(math.max(200, t.placeholder:GetStringWidth() + 2 * pad + 8), top + 26)
    else
        t.placeholder:Hide()
        t:SetSize(math.max(maxW + 2 * pad, showTitle and 170 or 0), -y + pad - 5)
    end
end

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------

local function NeedsAttention(st)
    return st.status == "missing" or st.status == "low"
end

local function RowModel(hand)
    local st = ns.states[hand.key]
    return {
        hand = hand,
        weaponIcon = GetInventoryItemTexture("player", hand.slot),
        status = st.status,
        name = st.name,
        timeLeft = st.timeLeft,
        charges = st.charges,
        poisons = ns.bagPoisons,
        last = ns.db[hand.lastKey],
    }
end

local function BuildModel()
    local db = ns.db
    local rows = {}
    for _, hand in ipairs(HANDS) do
        local st = ns.states[hand.key]
        if st.status ~= "none" and (db.showMode == "always" or not db.locked or NeedsAttention(st)) then
            rows[#rows + 1] = RowModel(hand)
        end
    end
    return { rows = rows, placeholder = ns.title .. " - drag to move" }
end

local function ShouldShow(model)
    local db = ns.db
    if not ns.isRogue then return false end
    if not db.locked then return true end
    if db.hideResting and IsResting() then return false end
    if db.hideNoPoisons and #ns.bagPoisons == 0 then return false end
    return #model.rows > 0
end

---------------------------------------------------------------------------
-- Real tracker, combat alert and updates
---------------------------------------------------------------------------

local tracker, alert
local pendingLayout = false

local function SavePosition()
    local p, _, rp, x, y = tracker:GetPoint(1)
    ns.db.point = { p, rp, x, y }
end

local function ApplyPosition()
    tracker:ClearAllPoints()
    local pt = ns.db.point
    if pt then
        tracker:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        tracker:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function CreateMainFrames()
    tracker = ns.CreateTracker(UIParent, true, "MirraPoisonsTracker")
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", function(self)
        if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    tracker:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    tracker:Hide()
    ns.tracker = tracker

    -- In combat the secure buttons can't appear; this plain text takes over.
    alert = CreateFrame("Frame", nil, UIParent)
    alert:SetSize(240, 24)
    alert:SetPoint("CENTER", tracker, "CENTER")
    alert:SetFrameStrata("MEDIUM")
    alert.text = alert:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alert.text:SetPoint("CENTER")
    alert.text:SetTextColor(ns.colors.bad[1], ns.colors.bad[2], ns.colors.bad[3])
    alert.anim = alert:CreateAnimationGroup()
    alert.anim:SetLooping("BOUNCE")
    local a = alert.anim:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.6)
    alert:Hide()
    ns.alert = alert
end

-- texts in the visible rows and the combat alert
local function UpdateDynamic()
    if tracker:IsShown() then
        for _, row in ipairs(tracker.rows) do
            if row:IsShown() and row.handKey then
                for _, hand in ipairs(HANDS) do
                    if hand.key == row.handKey then RenderRowStatus(row, RowModel(hand)) end
                end
            end
        end
    end

    local missing = {}
    if InCombatLockdown() and ns.isRogue and not (ns.db.hideNoPoisons and #ns.bagPoisons == 0) then
        for _, hand in ipairs(HANDS) do
            if ns.states[hand.key].status == "missing" then
                local visible = false
                if tracker:IsShown() then
                    for _, row in ipairs(tracker.rows) do
                        if row:IsShown() and row.handKey == hand.key then visible = true end
                    end
                end
                if not visible then missing[#missing + 1] = hand.label end
            end
        end
    end
    if #missing > 0 then
        alert.text:SetText("No poison: " .. table.concat(missing, ", "))
        if not alert:IsShown() then
            alert:Show()
            alert.anim:Play()
        end
    elseif alert:IsShown() then
        alert.anim:Stop()
        alert:Hide()
    end
end

local function Layout()
    if InCombatLockdown() then
        pendingLayout = true
        UpdateDynamic()
        return
    end
    pendingLayout = false
    tracker:SetScale((ns.db.scale or 100) / 100)
    local model = BuildModel()
    if ShouldShow(model) then
        ns.RenderTracker(tracker, model)
        tracker:Show()
    else
        tracker:Hide()
    end
    UpdateDynamic()
end

local function AnnounceExpired(hand)
    local db = ns.db
    if db.alertSound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
    if db.alertText and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, "No poison on your " .. hand.label .. "!",
            ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.2 })
    end
end

-- Signature of everything that changes the layout (not timers).
local lastSignature
local function Signature()
    local parts = {}
    for _, hand in ipairs(HANDS) do
        local st = ns.states[hand.key]
        parts[#parts + 1] = hand.key .. ":" .. tostring(st.status) .. ":" .. tostring(st.weaponID)
    end
    for _, p in ipairs(ns.bagPoisons) do
        parts[#parts + 1] = p.itemID .. "x" .. p.count
    end
    parts[#parts + 1] = tostring(IsResting())
    return table.concat(parts, "|")
end

local function Recompute(force)
    if not ns.db or not tracker then return end
    if not ns.isRogue then
        if tracker:IsShown() and not InCombatLockdown() then tracker:Hide() end
        return
    end
    LoadBaseNames()
    for i, hand in ipairs(HANDS) do
        local prev = ns.states[hand.key]
        local ok, st = pcall(ReadHand, hand, i)
        if ok then
            if st.status == "missing" and (prev.status == "ok" or prev.status == "low")
                and prev.weaponID == st.weaponID then
                AnnounceExpired(hand)
            end
            ns.states[hand.key] = st
        else
            NoteError("ReadHand", st)
        end
    end
    local sig = Signature()
    if force or sig ~= lastSignature or pendingLayout then
        lastSignature = sig
        Layout()
    else
        UpdateDynamic()
    end
end
ns.Recompute = Recompute

-- Called by the settings panel.
function ns.ApplySettings()
    if not tracker then return end
    Recompute(true)
    if ns.RefreshPreview then ns.RefreshPreview() end
end

function ns.ResetPosition()
    ns.db.point = nil
    if not InCombatLockdown() then ApplyPosition() end
end

---------------------------------------------------------------------------
-- "Replace enchant?" confirmation after clicking one of our buttons
---------------------------------------------------------------------------

local function HookReplacePopup()
    if not StaticPopup_Show then return end
    hooksecurefunc("StaticPopup_Show", function(which)
        if which ~= "REPLACE_ENCHANT" or not ns.db or not ns.db.autoReplace then return end
        if not ns.lastClick or GetTime() - ns.lastClick > 3 then return end
        ns.lastClick = nil
        if ReplaceEnchant then
            local ok, err = pcall(ReplaceEnchant)
            if not ok then NoteError("ReplaceEnchant", err) return end
        end
        pcall(StaticPopup_Hide, "REPLACE_ENCHANT")
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local bagsDirty = true
local elapsedTotal = 0

-- timers and states are polled twice a second (cheap: two tooltips)
events:SetScript("OnUpdate", function(self, elapsed)
    if not ns.db then return end
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.5 then return end
    elapsedTotal = 0
    if bagsDirty then
        bagsDirty = false
        ScanBags()
    end
    Recompute(false)
end)

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        MirraPoisonsDB = MirraPoisonsDB or {}
        for k, v in pairs(ns.defaults) do
            if MirraPoisonsDB[k] == nil then MirraPoisonsDB[k] = v end
        end
        ns.db = MirraPoisonsDB
        ns.isRogue = select(2, UnitClass("player")) == "ROGUE"
        CreateMainFrames()
        ApplyPosition()
        HookReplacePopup()
        LoadBaseNames()
        if ns.BuildOptions then ns.BuildOptions() end
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not ns.db then return end

    if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED"
        or event == "ITEM_DATA_LOAD_RESULT" or event == "PLAYER_ENTERING_WORLD" then
        if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            wipe(classifyCache)
        end
        bagsDirty = true
        elapsedTotal = 0.5     -- update on the next frame
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then elapsedTotal = 0.5 end
    elseif event == "PLAYER_REGEN_ENABLED" then
        Recompute(true)
    else
        elapsedTotal = 0.5
    end
end)

events:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({
    "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_UPDATE_RESTING", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    "WEAPON_ENCHANT_CHANGED",
}) do
    pcall(events.RegisterEvent, events, e)   -- not every client knows every event
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Print(msg)
    print("|cffe0a040Mirra's Poisons|r: " .. msg)
end

SLASH_MIRRAPOISONS1 = "/mpoison"
SLASH_MIRRAPOISONS2 = "/mpoisons"
SlashCmdList["MIRRAPOISONS"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if not ns.db then return end

    if msg == "unlock" or msg == "lock" then
        if InCombatLockdown() then
            Print("not possible in combat.")
            return
        end
        ns.db.locked = (msg == "lock")
        ns.ApplySettings()
        Print(ns.db.locked and "locked." or "unlocked - drag the tracker to move it, /mpoison lock when done.")
    elseif msg == "reset" then
        ns.ResetPosition()
        Print("position reset.")
    elseif msg == "debug" then
        Print("debug")
        print("  Interface: " .. tostring(select(4, GetBuildInfo())))
        print("  Secret values: " .. tostring(issecretvalue ~= nil))
        print("  Rogue: " .. tostring(ns.isRogue) .. ", in combat: " .. tostring(InCombatLockdown()))
        local names = {}
        for t = 1, #POISONS do names[#names + 1] = tostring(baseNames[t]) end
        print("  Poison names: " .. table.concat(names, ", "))
        local bag = {}
        for _, p in ipairs(ns.bagPoisons) do
            bag[#bag + 1] = (GetItemName(p.itemID) or p.itemID) .. " x" .. p.count
        end
        print("  In bags: " .. (#bag > 0 and table.concat(bag, ", ") or "-"))
        for i, hand in ipairs(HANDS) do
            local st = ns.states[hand.key]
            local has, timeLeft, charges = EnchantInfo(i)
            print(string.format("  %s: %s, name %s, time %s, charges %s | API: enchant %s, time %s, charges %s",
                hand.label, tostring(st.status), tostring(st.name), tostring(st.timeLeft),
                tostring(st.charges), tostring(has), tostring(timeLeft), tostring(charges)))
            local lines = TooltipLines(hand.slot)
            if lines then
                for l = 2, #lines do print("      " .. lines[l]) end
            else
                print("      (tooltip not readable)")
            end
        end
        print("  Last error: " .. tostring(ns.lastError))
    elseif msg == "" or msg == "options" or msg == "config" then
        if ns.OpenOptions then ns.OpenOptions() end
    else
        Print("commands: /mpoison (options), /mpoison unlock, /mpoison lock, /mpoison reset, /mpoison debug")
    end
end
