local _, ns = ...

local WIDTH, HEIGHT = 340, 470
local PADDING = 10
local ROW_HEIGHT = 26
local ICON_SIZE = 20
local MAX_SKILL = 300
local MAX_SKILL_NEAR_CAP_MARGIN = 5

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local frame
local rows = {}

-- Builds the frame from a Blizzard template, and from a plain one with the
-- same pieces drawn by hand if that template is missing on this client.
local function CreateStandardFrame()
	local ok, created = pcall(CreateFrame, "Frame", "FishermansFriendFrame", UIParent, "BasicFrameTemplateWithInset")
	if ok then
		return created
	end

	local plain = CreateFrame("Frame", "FishermansFriendFrame", UIParent)
	local background = plain:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.05, 0.95)

	plain.Inset = CreateFrame("Frame", nil, plain)
	plain.Inset:SetPoint("TOPLEFT", 4, -24)
	plain.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
	local insetBackground = plain.Inset:CreateTexture(nil, "BACKGROUND")
	insetBackground:SetAllPoints()
	insetBackground:SetColorTexture(0, 0, 0, 0.5)

	plain.TitleText = plain:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	plain.TitleText:SetPoint("TOP", 0, -6)

	plain.CloseButton = CreateFrame("Button", nil, plain, "UIPanelCloseButton")
	plain.CloseButton:SetPoint("TOPRIGHT", 2, 2)
	return plain
end

local function SetQualityColor(fontString, quality)
	local r, g, b = C_Item.GetItemQualityColor(quality or 1)
	fontString:SetTextColor(r or 1, g or 1, b or 1)
end

local function ShowRowTooltip(row)
	local entry = row.entry
	if not entry then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(entry.link)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Caught in:", 1, 0.82, 0)
	local zones = {}
	for zone in pairs(entry.zones) do
		table.insert(zones, zone)
	end
	table.sort(zones, function(a, b)
		return entry.zones[a] > entry.zones[b]
	end)
	for _, zone in ipairs(zones) do
		GameTooltip:AddDoubleLine(zone, entry.zones[zone], 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function GetRow(index)
	local row = rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, frame.listContent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT")

	if index % 2 == 0 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.04)
	end

	-- Quality-colored frame around the icon, like an item slot.
	row.border = row:CreateTexture(nil, "BORDER")
	row.border:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
	row.border:SetPoint("LEFT", 2, 0)
	row.border:SetColorTexture(1, 1, 1, 1)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("CENTER", row.border)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.count:SetPoint("RIGHT", -4, 0)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", row.border, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.12)

	row:SetScript("OnEnter", ShowRowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	rows[index] = row
	return row
end

local function GetBindingLabel(action)
	local key = GetBindingKey(action)
	return key and GetBindingText(key) or "Not bound"
end

local function PlayWindowSound(opening)
	if PlaySound and SOUNDKIT then
		PlaySound(opening and SOUNDKIT.IG_CHARACTER_INFO_OPEN or SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end
end

local function CreateSkillBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(18)
	bar:SetStatusBarTexture(BAR_TEXTURE)
	bar:SetStatusBarColor(0.1, 0.4, 0.9)

	local border = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0, 0, 0, 0.9)

	local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
	trough:SetAllPoints()
	trough:SetColorTexture(0.12, 0.12, 0.14, 1)

	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("CENTER")
	return bar
end

local function CreateWindow()
	frame = CreateStandardFrame()
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	table.insert(UISpecialFrames, "FishermansFriendFrame")

	frame.TitleText:SetText("Fishermans' Friend")

	-- Anchored directly to the window: the template's own Inset has no
	-- position on every client, which left the contents at the screen corner.
	local inset = CreateFrame("Frame", nil, frame)
	inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
	inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

	frame.skillLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.skillLabel:SetPoint("TOPLEFT", inset, "TOPLEFT", PADDING, -PADDING)

	frame.skillBar = CreateSkillBar(frame)
	frame.skillBar:SetPoint("TOPLEFT", frame.skillLabel, "BOTTOMLEFT", 0, -6)
	frame.skillBar:SetPoint("RIGHT", inset, "RIGHT", -PADDING, 0)

	frame.skillNote = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.skillNote:SetPoint("TOPLEFT", frame.skillBar, "BOTTOMLEFT", 0, -6)
	frame.skillNote:SetPoint("RIGHT", inset, "RIGHT", -PADDING, 0)
	frame.skillNote:SetJustifyH("LEFT")
	frame.skillNote:SetTextColor(0.7, 0.7, 0.7)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", frame.skillNote, "BOTTOMLEFT", 0, -10)
	divider:SetPoint("RIGHT", inset, "RIGHT", -PADDING, 0)
	divider:SetColorTexture(1, 0.82, 0, 0.35)

	frame.equipKey = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.equipKey:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -10)

	frame.castKey = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.castKey:SetPoint("TOPLEFT", frame.equipKey, "BOTTOMLEFT", 0, -4)

	frame.equipButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.equipButton:SetSize(110, 22)
	frame.equipButton:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 0, -8)
	frame.equipButton:SetText("Equip Pole")
	frame.equipButton:SetScript("OnClick", function()
		FishermansFriend_EquipPole()
	end)

	frame.caughtLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.caughtLabel:SetPoint("TOPLEFT", frame.castKey, "BOTTOMLEFT", 0, -16)

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", frame.caughtLabel, "BOTTOMLEFT", 0, -6)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, PADDING)

	frame.listContent = CreateFrame("Frame", nil, scroll)
	frame.listContent:SetSize(WIDTH - PADDING * 2 - 40, 1)
	scroll:SetScrollChild(frame.listContent)

	frame.emptyText = frame.listContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.emptyText:SetPoint("TOPLEFT", 4, -4)
	frame.emptyText:SetText("Nothing caught yet.")

	frame:SetScript("OnShow", function()
		PlayWindowSound(true)
		ns.Refresh()
	end)
	frame:SetScript("OnHide", function()
		PlayWindowSound(false)
	end)
end

local function RefreshSkill()
	local skill = ns.GetSkill()
	if not skill then
		frame.skillLabel:SetText("Fishing: not learned")
		frame.skillBar:SetMinMaxValues(0, 1)
		frame.skillBar:SetValue(0)
		frame.skillBar.text:SetText("")
		frame.skillNote:SetText("Visit a Fishing trainer to get started.")
		return
	end

	local bonus = skill.modifier > 0 and (" (+%d)"):format(skill.modifier) or ""
	frame.skillLabel:SetText(("Fishing: %d / %d%s"):format(skill.level, skill.maxLevel, bonus))
	frame.skillBar:SetMinMaxValues(0, math.max(skill.maxLevel, 1))
	frame.skillBar:SetValue(skill.level)
	frame.skillBar.text:SetText(("%d / %d"):format(skill.level, skill.maxLevel))

	local note = ("+%d skill this session"):format(ns.session.skillGain)
	if skill.maxLevel < MAX_SKILL and skill.level >= skill.maxLevel - MAX_SKILL_NEAR_CAP_MARGIN then
		note = note .. " - train the next rank soon"
	end
	frame.skillNote:SetText(note)
end

local function RefreshCatches()
	local sorted = {}
	for _, entry in pairs(ns.GetCatches()) do
		table.insert(sorted, entry)
	end
	table.sort(sorted, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.name < b.name
	end)

	local totalItems = ns.GetTotals()
	frame.caughtLabel:SetText(("Caught: %d (%d this session)"):format(totalItems, ns.session.items))
	frame.emptyText:SetShown(#sorted == 0)

	for index, entry in ipairs(sorted) do
		local row = GetRow(index)
		row.entry = entry
		row.icon:SetTexture(entry.icon)
		row.name:SetText(entry.name)
		SetQualityColor(row.name, entry.quality)
		local r, g, b = C_Item.GetItemQualityColor(entry.quality or 1)
		row.border:SetColorTexture(r or 1, g or 1, b or 1, 1)
		row.count:SetText(entry.count)
		row:Show()
	end
	for index = #sorted + 1, #rows do
		rows[index].entry = nil
		rows[index]:Hide()
	end
	frame.listContent:SetHeight(math.max(#sorted * ROW_HEIGHT, 1))
end

function ns.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	RefreshSkill()
	frame.equipKey:SetText("Equip pole hotkey: " .. GetBindingLabel(ns.EQUIP_BINDING))
	frame.castKey:SetText("Cast hotkey: " .. GetBindingLabel(ns.CAST_BINDING))
	RefreshCatches()
end

function ns.ToggleWindow()
	if not frame then
		CreateWindow()
	end
	frame:SetShown(not frame:IsShown())
end
