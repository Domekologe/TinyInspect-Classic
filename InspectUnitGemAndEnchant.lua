
local addon, ns = ...

local LibItemGem = LibStub:GetLibrary("LibItemGem.7000")
local LibSchedule = LibStub:GetLibrary("LibSchedule.7000")
local LibItemEnchant = LibStub:GetLibrary("LibItemEnchant.7000")

ns = ns or {}
local L = ns.L
if not L then
    local ok, ace = pcall(LibStub, "AceLocale-3.0")
    if ok and ace then
        local locale = ace:GetLocale(addon, true) -- true = silent
        if locale then
            L = locale
        end
    end
end
if not L then
    -- Fallback passthrough (returns the key)
    L = setmetatable({}, { __index = function(t, k) return k end })
end
ns.L = L

local function TI_StripColorCodes(s)
    if not s then return s end
    -- remove |cAARRGGBB and |r
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

-- [ADD][FIND THIS: TI_SCANNER_BLOCK]
-- Passive tooltip scanner to read item tooltips when LibItemEnchant fails.
local TI_SCAN_TT = CreateFrame("GameTooltip", "TinyInspect_ScanTooltip", UIParent, "GameTooltipTemplate")
TI_SCAN_TT:SetOwner(UIParent, "ANCHOR_NONE")

-- [REPLACE][FIND THIS: TI_SCANNER_BLOCK]
local function TI_ScanEnchantFromTooltip(itemLink)
    -- Returns: found(boolean), text(string or nil), isLW(boolean)
    if not itemLink then return false, nil, false end
    TI_SCAN_TT:ClearLines()
    TI_SCAN_TT:SetHyperlink(itemLink)

    local foundText, isLW = nil, false
    local n = TI_SCAN_TT:NumLines() or 0
    for i = 2, n do
        local line = _G["TinyInspect_ScanTooltipTextLeft"..i]
        local raw = line and line:GetText()
        if raw and raw ~= "" then
            -- strip WoW color codes
            local cleaned = TI_StripColorCodes(raw)
            local lower = cleaned:lower()

            -- Leatherworking requirement?
            -- L["REQ_LEATHERWORKING_LWR"] must be a lowercase needle (see Locales).
            local lw_need = L["REQ_LEATHERWORKING_LWR"]
            if type(lw_need) == "string" and lw_need ~= "" and lower:find(lw_need, 1, true) then
                isLW = true
            end
			
			local lw_need = L["REQ_LEATHERWORKING_ING"]
            if type(lw_need) == "string" and lw_need ~= "" and lower:find(lw_need, 1, true) then
                isLW = true
            end

            -- Enchant line?
            local m
            -- Patterns come pre-lowercased and should start with ^(
            local p_de = L["ENCHANT_PREFIX_DE_MATCH"]
            local p_en = L["ENCHANT_PREFIX_EN_MATCH"]
            if type(p_de) == "string" and p_de ~= "" then
                m = lower:match(p_de)
            end
            if not m and type(p_en) == "string" and p_en ~= "" then
                m = lower:match(p_en)
            end
            if m then
                -- keep cleaned (but original-cased) text for display
                foundText = cleaned
            end
        end
    end
    return (foundText ~= nil) or isLW, foundText, isLW
end



local ED_BASE_SOCKET_KEYS = {
  "EMPTY_SOCKET_RED",
  "EMPTY_SOCKET_YELLOW",
  "EMPTY_SOCKET_BLUE",
  "EMPTY_SOCKET_META",
}

local function CreateIconFrame(frame, index)
    local icon = CreateFrame("Button", nil, frame)
    icon.index = index
    icon:Hide()
    icon:SetSize(16, 16)
    icon:SetScript("OnEnter", function(self)
        if (self.itemLink) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        elseif (self.spellID) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        elseif (self.title) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title)
            GameTooltip:Show()
        end
    end)
    icon:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    icon:SetScript("OnDoubleClick", function(self)
        if (self.itemLink or self.title) then
            ChatEdit_ActivateChat(ChatEdit_ChooseBoxForSend())
            ChatEdit_InsertLink(self.itemLink or self.title)
        end
    end)
    icon.bg = icon:CreateTexture(nil, "BACKGROUND")
    icon.bg:SetSize(16, 16)
    icon.bg:SetPoint("CENTER")
    icon.bg:SetTexture("Interface\\AddOns\\"..addon.."\\texture\\GemBg")
    icon.texture = icon:CreateTexture(nil, "BORDER")
    icon.texture:SetSize(12, 12)
    icon.texture:SetPoint("CENTER")
    icon.texture:SetMask("Interface\\FriendsFrame\\Battlenet-Portrait")
    frame["xicon"..index] = icon
    return frame["xicon"..index]
end

local function HideAllIconFrame(frame)
    local index = 1 
    while (frame["xicon"..index]) do
        frame["xicon"..index].title = nil
        frame["xicon"..index].itemLink = nil
        frame["xicon"..index].spellID = nil
        frame["xicon"..index]:Hide()
        index = index + 1
    end
    LibSchedule:RemoveTask("InspectGemAndEnchant", true)
end

local function TI_CountSockets(itemLink)
    local stats = (TI_GetItemStats or C_Item.GetItemStats)(itemLink)
    local n = 0
    if stats then
        for k, v in pairs(stats) do
            if type(k) == "string" and k:find("EMPTY_SOCKET_") then
                n = n + (tonumber(v) or 0)
            end
        end
    end
    return n
end

local function TI_UnitHasEnchanting(unit)
    if unit ~= "player" then
        -- Bei anderen Einheiten kennen wir die Berufe nicht -> nicht prüfen
        return false
    end
    local function hasEnchanting(profId)
        if not profId then return false end
        local _, _, _, _, _, _, skillLine = GetProfessionInfo(profId)
        return skillLine == 333 -- 333 = Verzauberkunst / Enchanting
    end
    local p1, p2 = GetProfessions()
    return hasEnchanting(p1) or hasEnchanting(p2)
end


local function TI_UnitHasBlacksmithing(unit)
    if unit ~= "player" then
        return false
    end
    local function hasBS(profId)
        if not profId then return false end
        local _, _, _, _, _, _, skillLine = GetProfessionInfo(profId)
        return skillLine == 164 -- 164 = Schmiedekunst
    end
    local p1, p2 = GetProfessions()
    return hasBS(p1) or hasBS(p2)
end



local function GetIconFrame(frame)
    local index = 1
    while (frame["xicon"..index]) do
        if (not frame["xicon"..index]:IsShown()) then
            return frame["xicon"..index]
        end
        index = index + 1
    end
    return CreateIconFrame(frame, index)
end

local function onExecute(self)
    if (self.dataType == "item") then
        local _, itemLink, quality, _, _, _, _, _, _, texture = GetItemInfo(self.data)
        if (texture) then
            local r, g, b = GetItemQualityColor(quality or 0)
            self.icon.bg:SetVertexColor(r, g, b)
            self.icon.texture:SetTexture(texture)
            if (not self.icon.itemLink) then
                self.icon.itemLink = itemLink
            end
            return true
        end
    elseif (self.dataType == "spell") then
        local _, _, texture = C_Spell.GetSpellInfo(self.data)
        if (texture) then
            self.icon.texture:SetTexture(texture)
            return true
        end
    end
end

local function UpdateIconTexture(icon, texture, data, dataType)
    if (not texture) then
        LibSchedule:AddTask({
            identity  = "InspectGemAndEnchant" .. icon.index,
            timer     = 0.1,
            elasped   = 0.5,
            expired   = GetTime() + 3,
            onExecute = onExecute,
            icon      = icon,
            data      = data,
            dataType  = dataType,
        })
    end
end

local function TI_GetEnchantIdFromItemLink(link)
    if type(link) ~= "string" then return nil end
    -- Extract the colon-separated payload right after "item:"
    local payload = link:match("item:([^|]+)")
    if not payload then return nil end
    -- ENCHANT is the 2nd field in the payload
    local first, enchant = payload:match("^([^:]*):([^:]*)")
    if enchant and enchant ~= "" then
        local eid = tonumber(enchant)
        return eid
    end
    return nil
end

-- [FIX] Belt Buckle detection:
-- Count base sockets (colored/meta) vs TOTAL sockets (all EMPTY_SOCKET_*).
-- A buckle adds exactly +1 socket; even if empty we still see TOTAL > BASE.
local function ED_HasBuckle_ByGems(unit, slot)
  unit = unit or "player"
  slot = slot or INVSLOT_WAIST

  local link = GetInventoryItemLink(unit, slot)
  if not link then
    return false, 0, 0, nil -- hasBuckle, baseCount, lastGemIndex, link
  end

  local stats = GetItemStats(link) or {}
  local baseCount, totalCount = 0, 0

  -- BASE = only the native colored/meta sockets (no buckle)
  for _, key in ipairs(ED_BASE_SOCKET_KEYS) do
    local n = stats[key]
    if n and n > 0 then baseCount = baseCount + n end
  end

  -- TOTAL = every empty socket stat found on the item
  for k, v in pairs(stats) do
    if type(k) == "string" and k:find("^EMPTY_SOCKET_") then
      totalCount = totalCount + (tonumber(v) or 0)
    end
  end

  -- Legacy heuristic: look at gems actually inserted
  local lastGemIndex = 0
  for i = 1, 4 do
    local _, gemLink = GetItemGem(link, i)
    if gemLink then lastGemIndex = i end
  end

  -- Prefer stat-based detection: buckle adds exactly +1 socket on belts
  local hasBuckle = (totalCount > baseCount) or (lastGemIndex > baseCount)

  return hasBuckle, baseCount, lastGemIndex, link
end



local function TI_ResolveUnitFromItemFrame(itemframe)
    -- Inspect path: parent usually has .unit
    if itemframe and itemframe.GetParent then
        local p = itemframe:GetParent()
        if p and p.unit then
            return p.unit
        end
    end
    -- Fallback: InspectFrame knows the inspected unit if open
    if _G.InspectFrame and InspectFrame.unit then
        return InspectFrame.unit
    end
    -- Default to player when nothing else is known (PaperDoll)
    return "player"
end

local function TI_FindItemListFrameFromArgs(...)
    for i = 1, select("#", ...) do
        local arg = select(i, ...)
        if type(arg) == "table" then
            -- Heuristic: TinyInspect list frames expose "item1", "item2", ...
            if rawget(arg, "item1") or rawget(arg, "item2") then
                return arg
            end
            -- Some builds attach it as ".characterFrame" or ".inspectFrame"
            if arg.characterFrame and (rawget(arg.characterFrame, "item1") or rawget(arg.characterFrame, "item2")) then
                return arg.characterFrame
            end
            if arg.inspectFrame and (rawget(arg.inspectFrame, "item1") or rawget(arg.inspectFrame, "item2")) then
                return arg.inspectFrame
            end
        end
    end
    -- Last resort: try well-known globals if present
    if _G.TinyInspectItemListFrame and (rawget(_G.TinyInspectItemListFrame, "item1") or rawget(_G.TinyInspectItemListFrame, "item2")) then
        return _G.TinyInspectItemListFrame
    end
    return nil
end

local function ShowGemAndEnchant(frame, ItemLink, anchorFrame, itemframe)
    -- Always try to recover a missing link on the player's PaperDoll
    if (not ItemLink) and itemframe then
        local unit = TI_ResolveUnitFromItemFrame(itemframe)
        if unit and itemframe.index then
            ItemLink = GetInventoryItemLink(unit, itemframe.index)
        end
    end
    if (not ItemLink) then
        return 0
    end
    local num, info, qty = LibItemGem:GetItemGemInfo(ItemLink)
    local _, quality, texture, icon, r, g, b
    for i, v in ipairs(info) do
        icon = GetIconFrame(frame)
        if (v.link) then
            _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(v.link)
            r, g, b = GetItemQualityColor(quality or 0)
            icon.bg:SetVertexColor(r, g, b)
            icon.texture:SetTexture(texture or "Interface\\Cursor\\Quest")
            UpdateIconTexture(icon, texture, v.link, "item")
        else
            icon.bg:SetVertexColor(1, 0.82, 0, 0.5)
            icon.texture:SetTexture("Interface\\Cursor\\Quest")
        end
        icon.title = v.name
        icon.itemLink = v.link
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", anchorFrame, "RIGHT", i == 1 and 6 or 1, 0)
        icon:Show()
        anchorFrame = icon
    end
	-- Belt Buckle Check (MoP)
	if itemframe and itemframe.index == INVSLOT_WAIST then
		local unit = TI_ResolveUnitFromItemFrame(itemframe)
		local waistLink = GetInventoryItemLink(unit, INVSLOT_WAIST) or ItemLink

		local hasBuckle, baseSockets, gemSlots, _ = ED_HasBuckle_ByGems(unit, INVSLOT_WAIST)

		-- Fallback ONLY for yourself: a belt enchant id implies buckle present (older clients)
		if unit == "player" and waistLink and not hasBuckle then
			local enchantId = TI_GetEnchantIdFromItemLink(waistLink)
			local eItemID, eID = LibItemEnchant:GetEnchantItemID(waistLink)
			local eSpellID    = LibItemEnchant:GetEnchantSpellID(waistLink)
			local hasEnchant  = (enchantId and enchantId > 0)
							 or (eItemID and eItemID ~= 0)
							 or (eSpellID and eSpellID ~= 0)
							 or (eID and eID ~= 0)
			if hasEnchant then
				hasBuckle = true
			end
		end

		-- Extra fallback ONLY for yourself: a belt enchant implies buckle present (legacy behavior)
		if unit == "player" and waistLink and not hasBuckle then
			local enchantId = TI_GetEnchantIdFromItemLink(waistLink)
			local eItemID, eID = LibItemEnchant:GetEnchantItemID(waistLink)
			local eSpellID    = LibItemEnchant:GetEnchantSpellID(waistLink)
			local hasEnchant  = (enchantId and enchantId > 0)
							 or (eItemID and eItemID ~= 0)
							 or (eSpellID and eSpellID ~= 0)
							 or (eID and eID ~= 0)
			if hasEnchant then
				hasBuckle = true
			end
		end

		if not hasBuckle then
			num = num + 1
			local icon = GetIconFrame(frame)
			icon.title = (GetLocale():sub(1,2) == "de") and "Gürtelschnalle fehlt" or "Belt Buckle missing"
			icon.bg:SetVertexColor(1, 0.2, 0.2, 0.6)
			icon.texture:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
			icon.itemLink, icon.spellID = nil, nil
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
			icon:Show()
		end

		return num * 18
	end


	
	-- Ring Enchanting. If Profession not available = Ignore!
	if itemframe and (itemframe.index == 11 or itemframe.index == 12) then
        --local unit = itemframe:GetParent() and itemframe:GetParent().unit or "player"
		local unit = TI_ResolveUnitFromItemFrame(itemframe)
        if not TI_UnitHasEnchanting(unit) then
            return num * 18
        end
    end
	
	if itemframe and (itemframe.index == 9 or itemframe.index == 10) then -- 9 = Armschienen, 10 = Handschuhe
		--local unit = itemframe:GetParent() and itemframe:GetParent().unit or "player"
		local unit = TI_ResolveUnitFromItemFrame(itemframe)
		if TI_UnitHasBlacksmithing(unit) then
			local sockets = TI_CountSockets(ItemLink)
			if sockets == 0 then
				-- Kein Extra-Sockel -> Warn-Icon
				num = num + 1
				local icon = GetIconFrame(frame)
				icon.title = (GetLocale():sub(1,2) == "de") 
					and "Extra-Sockel fehlt (Beruf: Schmiedekunst)" 
					or "Extra Socket missing (Profession: Blacksmithing)"
				icon.bg:SetVertexColor(1, 0.2, 0.2, 0.6)
				icon.texture:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
				icon.itemLink = nil
				icon.spellID  = nil
				icon:ClearAllPoints()
				icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
				icon:Show()
			end
		end
		-- return num * 18
	end

	
    local enchantItemID, enchantID = LibItemEnchant:GetEnchantItemID(ItemLink)
    local enchantSpellID = LibItemEnchant:GetEnchantSpellID(ItemLink)
    local EnchantParts = TinyInspectClassicDB.EnchantParts or {}
    if (enchantItemID) then
        num = num + 1
        icon = GetIconFrame(frame)
        _, ItemLink, quality, _, _, _, _, _, _, texture = GetItemInfo(enchantItemID)
        r, g, b = GetItemQualityColor(quality or 0)
        icon.bg:SetVertexColor(r, g, b)
        icon.texture:SetTexture(texture)
        UpdateIconTexture(icon, texture, enchantItemID, "item")
        icon.itemLink = ItemLink
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
        icon:Show()
        anchorFrame = icon
    elseif (enchantSpellID) then
        num = num + 1
        icon = GetIconFrame(frame)
        _, _, texture = C_Spell.GetSpellInfo(enchantSpellID)
        icon.bg:SetVertexColor(1,0.82,0)
        icon.texture:SetTexture(texture)
        UpdateIconTexture(icon, texture, enchantSpellID, "spell")
        icon.spellID = enchantSpellID
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
        icon:Show()
        anchorFrame = icon
    elseif (enchantID) then
        num = num + 1
        icon = GetIconFrame(frame)
        icon.title = "#" .. enchantID
        icon.bg:SetVertexColor(0.1, 0.1, 0.1)
        icon.texture:SetTexture("Interface\\FriendsFrame\\InformationIcon")
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
        icon:Show()
        anchorFrame = icon
    elseif (not enchantID and EnchantParts[itemframe.index] and EnchantParts[itemframe.index][1]) then
        if (qty == 6 and (itemframe.index==2 or itemframe.index==16 or itemframe.index==17)) then else
            num = num + 1
            icon = GetIconFrame(frame)
            icon.title = ENCHANTS .. ": " .. (_G[EnchantParts[itemframe.index][2]] or EnchantParts[itemframe.index][2])
            icon.bg:SetVertexColor(1, 0.2, 0.2, 0.6)
            icon.texture:SetTexture("Interface\\Cursor\\Quest") --QuestRepeatable
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
            icon:Show()
            anchorFrame = icon
        end
    end
	-- [ADD][FIND THIS: TI_TOOLTIP_FALLBACK]
    if not (enchantItemID or enchantSpellID or enchantID) then
        local ok, text, isLW = TI_ScanEnchantFromTooltip(ItemLink)
        if ok then
            num = num + 1
            local icon2 = GetIconFrame(frame)
            icon2.itemLink, icon2.spellID = nil, nil

            if isLW then
                -- We detected a Leatherworking-only enchant (via requirement line).
                icon2.title = ns.L["LW_ENCHANT_DETECTED"]
                icon2.bg:SetVertexColor(0.2, 0.8, 0.2, 0.7)
                icon2.texture:SetTexture("Interface\\ICONS\\Trade_LeatherWorking")
            else
                -- We found an "Enchanted: ..." line; show the extracted text.
                icon2.title = string.format("%s: %s", ENCHANTS, text or "?")
                icon2.bg:SetVertexColor(1, 0.82, 0, 0.5)
                icon2.texture:SetTexture("Interface\\FriendsFrame\\InformationIcon")
            end

            icon2:ClearAllPoints()
            icon2:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
            icon2:Show()
            anchorFrame = icon2
        end
    end
    return num * 18
end

hooksecurefunc("ShowInspectItemListFrame", function(unit, parent, itemLevel, maxLevel)
    local frame = parent.inspectFrame
    if (not frame) then return end
    if (TinyInspectClassicDB and TinyInspectClassicDB.ShowGemAndEnchant) then
        local i = 1
        local itemframe
        local width, iconWidth = frame:GetWidth(), 0
        HideAllIconFrame(frame)
        while (frame["item"..i]) do
            itemframe = frame["item"..i]
            iconWidth = ShowGemAndEnchant(frame, itemframe.link, itemframe.itemString, itemframe)
            if (width < itemframe.width + iconWidth + 36) then
                width = itemframe.width + iconWidth + 36
            end
            i = i + 1
        end
        if (width > frame:GetWidth()) then
            frame:SetWidth(width)
        end
    else
        HideAllIconFrame(frame)
    end
end)

-- [FALLBACK] When PaperDoll updates, re-decorate the TinyInspect list directly
hooksecurefunc("PaperDollItemSlotButton_Update", function()
    if not (TinyInspectClassicDB and TinyInspectClassicDB.ShowGemAndEnchant) then return end

    -- Try to locate the TinyInspect list frame tied to the character
    local frame = TI_FindItemListFrameFromArgs(CharacterFrame)
                  or (CharacterFrame and CharacterFrame.characterFrame)
                  or (CharacterFrame and CharacterFrame.inspectFrame)

    if not frame then return end

    local i, width = 1, frame:GetWidth()
    HideAllIconFrame(frame)
    while (frame["item"..i]) do
        local itemframe = frame["item"..i]
        local iconWidth = ShowGemAndEnchant(frame, itemframe.link, itemframe.itemString, itemframe)
        if (width < (itemframe.width or 0) + iconWidth + 36) then
            width = (itemframe.width or 0) + iconWidth + 36
        end
        i = i + 1
    end
    if (width > frame:GetWidth()) then
        frame:SetWidth(width)
    end
end)




