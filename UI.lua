local _, ns = ...

local WIDTH, HEIGHT = 320, 440
local PADDING = 14
local ROW_HEIGHT = 22
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_SKILL_NEAR_CAP_MARGIN = 5
local MAX_SKILL = 300

local frame
local rows = {}

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
	GameTooltip:AddLine("Caught in:", 0.2, 0.73, 1)
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

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT")

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.count:SetPoint("RIGHT", -2, 0)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)

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

local function CreateWindow()
	frame = CreateFrame("Frame", "FishermansFriendFrame", UIParent)
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

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.08, 0.11, 0.95)

	local accent = frame:CreateTexture(nil, "BORDER")
	accent:SetPoint("TOPLEFT")
	accent:SetPoint("TOPRIGHT")
	accent:SetHeight(2)
	accent:SetColorTexture(0.2, 0.73, 1, 1)

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PADDING, -PADDING)
	title:SetText("Fishermans' Friend")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	frame.skillLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.skillLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)

	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetPoint("TOPLEFT", frame.skillLabel, "BOTTOMLEFT", 0, -6)
	bar:SetPoint("RIGHT", -PADDING, 0)
	bar:SetHeight(14)
	bar:SetStatusBarTexture(WHITE_TEXTURE)
	bar:SetStatusBarColor(0.2, 0.73, 1)
	local barBackground = bar:CreateTexture(nil, "BACKGROUND")
	barBackground:SetAllPoints()
	barBackground:SetColorTexture(1, 1, 1, 0.1)
	frame.skillBar = bar

	frame.skillNote = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.skillNote:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
	frame.skillNote:SetPoint("RIGHT", -PADDING, 0)
	frame.skillNote:SetJustifyH("LEFT")

	frame.equipKey = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.equipKey:SetPoint("TOPLEFT", frame.skillNote, "BOTTOMLEFT", 0, -10)

	frame.castKey = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.castKey:SetPoint("TOPLEFT", frame.equipKey, "BOTTOMLEFT", 0, -4)

	frame.caughtLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.caughtLabel:SetPoint("TOPLEFT", frame.castKey, "BOTTOMLEFT", 0, -14)

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", frame.caughtLabel, "BOTTOMLEFT", 0, -6)
	scroll:SetPoint("BOTTOMRIGHT", -30, PADDING)

	frame.listContent = CreateFrame("Frame", nil, scroll)
	frame.listContent:SetSize(WIDTH - PADDING - 30, 1)
	scroll:SetScrollChild(frame.listContent)

	frame.emptyText = frame.listContent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	frame.emptyText:SetPoint("TOPLEFT", 0, -4)
	frame.emptyText:SetText("Nothing caught yet.")

	frame:SetScript("OnShow", ns.Refresh)
end

local function RefreshSkill()
	local skill = ns.GetSkill()
	if not skill then
		frame.skillLabel:SetText("Fishing: not learned")
		frame.skillBar:SetMinMaxValues(0, 1)
		frame.skillBar:SetValue(0)
		frame.skillNote:SetText("Visit a Fishing trainer to get started.")
		return
	end

	local bonus = skill.modifier > 0 and (" (+%d)"):format(skill.modifier) or ""
	frame.skillLabel:SetText(("Fishing: %d / %d%s"):format(skill.level, skill.maxLevel, bonus))
	frame.skillBar:SetMinMaxValues(0, math.max(skill.maxLevel, 1))
	frame.skillBar:SetValue(skill.level)

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
