local _, ns = ...

BINDING_HEADER_FISHERMANSFRIEND = "Fishermans' Friend"
BINDING_NAME_FISHERMANSFRIEND_EQUIPPOLE = "Equip fishing pole"
_G["BINDING_NAME_CLICK FishermansFriendCastButton:LeftButton"] = "Cast Fishing"

ns.EQUIP_BINDING = "FISHERMANSFRIEND_EQUIPPOLE"
ns.CAST_BINDING = "CLICK FishermansFriendCastButton:LeftButton"
ns.session = { catches = 0, items = 0, skillGain = 0 }

local MAX_SKILL = 300
local EQUIP_VERIFY_DELAY = 0.7

local ITEM_CLASS_WEAPON = 2
local WEAPON_SUBCLASS_FISHING_POLE = 20
local ITEM_CLASS_PROFESSION = 19
local PROFESSION_SUBCLASS_FISHING = 9

local SLOT_MAIN_HAND = 16
local SLOT_FISHING_TOOL = 28

-- Fishing bonus of the known poles, used to pick the best one in the bags.
local POLE_BONUS = {
	[6256] = 0, -- Fishing Pole
	[12225] = 3, -- Blump Family Fishing Pole
	[6365] = 5, -- Strong Fishing Pole
	[6366] = 15, -- Darkwood Fishing Pole
	[6367] = 20, -- Big Iron Fishing Pole
	[19022] = 25, -- Nat Pagle's Extreme Angler FC-5000
	[19970] = 35, -- Arcanite Fishing Pole
}

-- Highest rank first; the first one the character knows is the one cast.
local FISHING_SPELLS = { 131474, 18248, 7732, 7731, 7620 }

local db
local castPending = false

function ns.Print(message)
	print("|cff33bbffFishermans' Friend:|r " .. message)
end

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

----------------------------------------------------------------------
-- Fishing skill
----------------------------------------------------------------------

local function GetFishingProfession()
	local fishingIndex = select(4, GetProfessions())
	if not fishingIndex then
		return nil
	end
	local name, icon, level, maxLevel, numAbilities, spellOffset, _, modifier = GetProfessionInfo(fishingIndex)
	return {
		name = name,
		icon = icon,
		level = level,
		maxLevel = maxLevel,
		numAbilities = numAbilities or 0,
		spellOffset = spellOffset or 0,
		modifier = modifier or 0,
	}
end

local function UpdateSkill()
	local profession = GetFishingProfession()
	if not profession then
		db.skill = nil
		return
	end

	local previous = db.skill and db.skill.level
	if previous and profession.level > previous then
		local gained = profession.level - previous
		ns.session.skillGain = ns.session.skillGain + gained
		table.insert(db.skillHistory, { level = profession.level, time = time() })
		ns.Print(("Fishing skill is now %d / %d."):format(profession.level, profession.maxLevel))
		if profession.level >= profession.maxLevel and profession.maxLevel < MAX_SKILL then
			ns.Print("You have reached your cap. Visit a trainer to learn the next rank.")
		end
	elseif not previous then
		local latest = db.skillHistory[#db.skillHistory]
		if not latest or latest.level ~= profession.level then
			table.insert(db.skillHistory, { level = profession.level, time = time() })
		end
	end

	db.skill = {
		name = profession.name,
		level = profession.level,
		maxLevel = profession.maxLevel,
		modifier = profession.modifier,
	}
end

function ns.GetSkill()
	return db and db.skill
end

function ns.GetSkillHistory()
	return db and db.skillHistory or {}
end

----------------------------------------------------------------------
-- Casting
----------------------------------------------------------------------

local castButton = CreateFrame("Button", "FishermansFriendCastButton", UIParent, "SecureActionButtonTemplate")
-- Both are needed so that the binding fires whichever way the player's
-- ActionButtonUseKeyDown setting is configured.
castButton:RegisterForClicks("AnyUp", "AnyDown")
castButton:SetAttribute("type", "spell")

castButton:HookScript("PostClick", function(_, _, down)
	if down and not ns.castSpell then
		ns.Print("Could not find your Fishing spell. Learn Fishing from a trainer, or type /ff status.")
	end
end)

local function IsSpellKnownByPlayer(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then
		return true
	end
	if IsPlayerSpell and IsPlayerSpell(spellID) then
		return true
	end
	return IsSpellKnown ~= nil and IsSpellKnown(spellID)
end

local function FindSpellFromProfession(profession)
	if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank) then
		return nil
	end
	for i = 1, profession.numAbilities do
		local info = C_SpellBook.GetSpellBookItemInfo(profession.spellOffset + i, Enum.SpellBookSpellBank.Player)
		if info and info.spellID and not info.isPassive then
			return info.spellID
		end
	end
	return nil
end

local function ResolveFishingSpell()
	for _, spellID in ipairs(FISHING_SPELLS) do
		if IsSpellKnownByPlayer(spellID) then
			return spellID
		end
	end
	-- Fall back on the profession itself in case the spell has a different ID
	-- on this client. Its localized name is a valid spell attribute too.
	local profession = GetFishingProfession()
	if profession then
		return FindSpellFromProfession(profession) or profession.name
	end
	return nil
end

local function UpdateCastSpell()
	if InCombatLockdown() then
		castPending = true
		return
	end
	castPending = false
	ns.castSpell = ResolveFishingSpell()
	castButton:SetAttribute("spell", ns.castSpell)
end

----------------------------------------------------------------------
-- Equipping a pole
----------------------------------------------------------------------

local function GetProfessionFishingSubclass()
	if Enum and Enum.ItemProfessionSubclass and Enum.ItemProfessionSubclass.Fishing then
		return Enum.ItemProfessionSubclass.Fishing
	end
	return PROFESSION_SUBCLASS_FISHING
end

-- Returns isPole, isProfessionTool. Poles are weapons on some clients and
-- profession tools on others, so both forms are recognised.
local function ClassifyPole(item)
	local itemID, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	if not itemID then
		return false, false
	end
	if classID == ITEM_CLASS_PROFESSION and subclassID == GetProfessionFishingSubclass() then
		return true, true
	end
	if (classID == ITEM_CLASS_WEAPON and subclassID == WEAPON_SUBCLASS_FISHING_POLE) or POLE_BONUS[itemID] then
		return true, false
	end
	return false, false
end

local function GetEquippedPole()
	for _, slot in ipairs({ SLOT_MAIN_HAND, SLOT_FISHING_TOOL }) do
		local link = GetInventoryItemLink("player", slot)
		if link and ClassifyPole(link) then
			return link
		end
	end
	return nil
end

local function FindPolesInBags()
	local poles = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local link = C_Container.GetContainerItemLink(bag, slot)
			if link then
				local isPole, isTool = ClassifyPole(link)
				if isPole then
					local itemID = C_Item.GetItemInfoInstant(link)
					local itemLevel = select(4, C_Item.GetItemInfo(link)) or 0
					table.insert(poles, {
						bag = bag,
						slot = slot,
						link = link,
						isTool = isTool,
						bonus = POLE_BONUS[itemID] or 0,
						itemLevel = itemLevel,
					})
				end
			end
		end
	end
	table.sort(poles, function(a, b)
		if a.bonus ~= b.bonus then
			return a.bonus > b.bonus
		end
		return a.itemLevel > b.itemLevel
	end)
	return poles
end

local function EquipPole(pole)
	if pole.isTool then
		-- The profession slot can't be reached through EquipItemByName.
		ClearCursor()
		C_Container.PickupContainerItem(pole.bag, pole.slot)
		EquipCursorItem(SLOT_FISHING_TOOL)
	else
		C_Item.EquipItemByName(pole.link)
	end
end

-- Tries each pole in turn, because the best one may have a skill requirement
-- the character doesn't meet yet.
local function TryEquip(poles, index)
	local pole = poles[index]
	EquipPole(pole)
	C_Timer.After(EQUIP_VERIFY_DELAY, function()
		local equipped = GetEquippedPole()
		if equipped then
			ns.Print("Equipped " .. equipped .. ".")
		elseif poles[index + 1] and not InCombatLockdown() then
			TryEquip(poles, index + 1)
		else
			ns.Print("Could not equip " .. pole.link .. ". Check for a confirmation prompt or a full bag.")
		end
	end)
end

function FishermansFriend_EquipPole()
	if InCombatLockdown() then
		ns.Print("You can't equip a fishing pole during combat.")
		return
	end
	local equipped = GetEquippedPole()
	if equipped then
		ns.Print(equipped .. " is already equipped.")
		return
	end
	local poles = FindPolesInBags()
	if #poles == 0 then
		ns.Print("No fishing pole found in your bags.")
		return
	end
	TryEquip(poles, 1)
end

----------------------------------------------------------------------
-- Catch tracking
----------------------------------------------------------------------

-- Loot on offer in the open fishing loot window, by slot. Items are counted
-- when their slot clears, so loot left behind by a full bag isn't counted.
local pendingLoot = {}
local catchCounted = false

local function SnapshotLoot()
	if not IsFishingLoot() then
		return
	end
	local itemSlotType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or LOOT_SLOT_ITEM
	for slot = 1, GetNumLootItems() do
		if not pendingLoot[slot] and GetLootSlotType(slot) == itemSlotType then
			local link = GetLootSlotLink(slot)
			local icon, name, quantity, _, quality = GetLootSlotInfo(slot)
			if link and not IsSecret(link) and not IsSecret(quantity) then
				pendingLoot[slot] = { link = link, icon = icon, name = name, quantity = quantity or 1, quality = quality }
			end
		end
	end
end

local function RecordCatch(loot)
	local itemID = tonumber(loot.link:match("item:(%d+)"))
	if not itemID then
		return
	end

	local now = time()
	local entry = db.catches[itemID]
	if not entry then
		entry = { count = 0, zones = {}, first = now }
		db.catches[itemID] = entry
	end
	entry.name = loot.name
	entry.link = loot.link
	entry.icon = loot.icon
	entry.quality = loot.quality
	entry.count = entry.count + loot.quantity
	entry.last = now

	local zone = GetRealZoneText()
	if not zone or zone == "" then
		zone = "Unknown"
	end
	entry.zones[zone] = (entry.zones[zone] or 0) + loot.quantity

	db.totalItems = db.totalItems + loot.quantity
	ns.session.items = ns.session.items + loot.quantity
	if not catchCounted then
		catchCounted = true
		db.totalCatches = db.totalCatches + 1
		ns.session.catches = ns.session.catches + 1
	end
end

function ns.GetCatches()
	return db and db.catches or {}
end

function ns.GetTotals()
	return db and db.totalItems or 0, db and db.totalCatches or 0
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

local function PrintStatus()
	local skill = ns.GetSkill()
	if skill then
		ns.Print(("Skill: %d / %d (lure bonus +%d)"):format(skill.level, skill.maxLevel, skill.modifier))
	else
		ns.Print("Skill: Fishing not learned")
	end
	ns.Print("Cast spell: " .. tostring(ns.castSpell or "not found"))
	ns.Print("Equipped pole: " .. (GetEquippedPole() or "none"))
	ns.Print("Poles in bags: " .. #FindPolesInBags())
	local items, catches = ns.GetTotals()
	ns.Print(("Caught: %d items from %d catches"):format(items, catches))
end

local function PrintSkillHistory()
	local history = ns.GetSkillHistory()
	if #history == 0 then
		ns.Print("No skill history yet.")
		return
	end
	ns.Print("Latest Fishing skill changes:")
	for i = #history, math.max(1, #history - 9), -1 do
		print(("  %s  skill %d"):format(date("%Y-%m-%d %H:%M", history[i].time), history[i].level))
	end
end

SLASH_FISHERMANSFRIEND1 = "/ff"
SLASH_FISHERMANSFRIEND2 = "/fishermansfriend"
SlashCmdList.FISHERMANSFRIEND = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "" then
		ns.ToggleWindow()
	elseif command == "status" then
		PrintStatus()
	elseif command == "skill" then
		PrintSkillHistory()
	else
		ns.Print("/ff opens the window, /ff status shows diagnostics, /ff skill shows skill history.")
	end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local events = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(addonName)
	if addonName ~= "FishermansFriend" then
		return
	end
	events:UnregisterEvent("ADDON_LOADED")
	FishermansFriendDB = FishermansFriendDB or {}
	db = FishermansFriendDB
	db.catches = db.catches or {}
	db.skillHistory = db.skillHistory or {}
	db.totalItems = db.totalItems or 0
	db.totalCatches = db.totalCatches or 0
end

function handlers.PLAYER_LOGIN()
	-- Profession data isn't dependable until now, so nothing else listens earlier.
	for event in pairs(handlers) do
		if event ~= "ADDON_LOADED" then
			events:RegisterEvent(event)
		end
	end
	UpdateSkill()
	UpdateCastSpell()
	if not GetBindingKey(ns.EQUIP_BINDING) or not GetBindingKey(ns.CAST_BINDING) then
		ns.Print("Set your hotkeys under Options > Keybindings > AddOns. Type /ff to open the window.")
	end
end

function handlers.SPELLS_CHANGED()
	UpdateSkill()
	UpdateCastSpell()
	ns.Refresh()
end

function handlers.SKILL_LINES_CHANGED()
	UpdateSkill()
	ns.Refresh()
end
handlers.CHAT_MSG_SKILL = handlers.SKILL_LINES_CHANGED

function handlers.PLAYER_REGEN_ENABLED()
	if castPending then
		UpdateCastSpell()
	end
end

handlers.LOOT_READY = SnapshotLoot
handlers.LOOT_OPENED = SnapshotLoot

function handlers.LOOT_SLOT_CLEARED(slot)
	local loot = pendingLoot[slot]
	if loot then
		pendingLoot[slot] = nil
		RecordCatch(loot)
		ns.Refresh()
	end
end

function handlers.LOOT_CLOSED()
	wipe(pendingLoot)
	catchCounted = false
	UpdateSkill()
	ns.Refresh()
end

function handlers.UPDATE_BINDINGS()
	ns.Refresh()
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
