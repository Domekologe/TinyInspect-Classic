
local addon, ns = ...

local LibItemGem = LibStub:GetLibrary("LibItemGem.7000")
local LibSchedule = LibStub:GetLibrary("LibSchedule.7000")
local LibItemEnchant = LibStub:GetLibrary("LibItemEnchant.7000")

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
    local stats = (TI_GetItemStats or GetItemStats)(itemLink)
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


local function CheckExtraSocket(unit, slotId)
    local link = GetInventoryItemLink(unit, slotId)
    if not link then return true end -- leerer Slot -> keine Warnung
    -- Extra-Sockel-Erkennung: 100 % sicher nur über Tooltip/ItemStats
    local stats = GetItemStats(link)
    if not stats then return false end
    -- Wenn mehr als normaler Sockeltyp vorhanden → true
    -- Normalerweise prüft man hier auch Gems, aber wir gehen auf vorhandene Sockelanzahl
    local sockets = (stats["EMPTY_SOCKET_PRISMATIC"] or 0) +
                    (stats["EMPTY_SOCKET_RED"] or 0) +
                    (stats["EMPTY_SOCKET_YELLOW"] or 0) +
                    (stats["EMPTY_SOCKET_BLUE"] or 0)
    return sockets > 0
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

local function ShowGemAndEnchant(frame, ItemLink, anchorFrame, itemframe)
    if (not ItemLink) then return 0 end
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
	if itemframe and itemframe.index == 6 then -- 6 = Taille
        local sockets = TI_CountSockets(ItemLink)
        if sockets == 0 then
            -- keine Schnalle (kein zusätzlicher Sockel) -> Warn-Icon
            num = num + 1
            local icon = GetIconFrame(frame)
            icon.title = (GetLocale():sub(1,2) == "de") and "Gürtelschnalle fehlt" or "Belt Buckle missing"
            icon.bg:SetVertexColor(1, 0.2, 0.2, 0.6)
            icon.texture:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
            icon.itemLink = nil
            icon.spellID  = nil
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", anchorFrame, "RIGHT", num == 1 and 6 or 1, 0)
            icon:Show()
        end
        return num * 18
    end
	
	-- Ring Enchanting. If Profession not available = Ignore!
	if itemframe and (itemframe.index == 11 or itemframe.index == 12) then
        local unit = itemframe:GetParent() and itemframe:GetParent().unit or "player"
        if not TI_UnitHasEnchanting(unit) then
            return num * 18
        end
    end
	
	if itemframe and (itemframe.index == 9 or itemframe.index == 10) then -- 9 = Armschienen, 10 = Handschuhe
		local unit = itemframe:GetParent() and itemframe:GetParent().unit or "player"
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
