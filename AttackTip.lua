
--------------------------------------------------------------------------------
local function print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0.5)
end

local function SplitString(s,t)
	local l = {n=0}
	local f = function (s)
		l.n = l.n + 1
		l[l.n] = s
	end
	local p = "%s*(.-)%s*"..t.."%s*"
	s = string.gsub(s,"^%s+","")
	s = string.gsub(s,"%s+$","")
	s = string.gsub(s,p,f)
	l.n = l.n + 1
	l[l.n] = string.gsub(s,"(%s%s*)$","")
	return l
end

--------------------------------------------------------------------------------

function AttackTip_OnLoad()
	this:RegisterEvent("ADDON_LOADED")
end

local bonusHealing = 0
local applyBonusHealing = true

local maxCastTimeCoefficient = 3.5
local function applyBonusHealingValue(healValue, coeff, bonusHealing)
	local applied = bonusHealing*coeff
	return healValue + applied, applied
end

local rankMatch="Rank (%d+)"
local manaMatch="(%d+) Mana"
local rageMatch="(%d+) Rage"
local energyMatch="(%d+) Energy"
local castTimeMatch="(.+) sec cast"
local secCooldownMatch="(%d+) sec cooldown"
local weaponDamageMatch="(%d+)%% weapon damage"
local causingDamageMatch="causing (%d+) damage"
local causingRangeDamageMatch="causing (%d+) to (%d+) damage"
local causesDamageRangeMatch="Causes (%d+) to (%d+) .* damage"
local doingDamageMatch="doing (%d+) damage"
local meleeDamageMatch="melee damage"
local hotMatch="Heals .* for (%d+) over (%d+) .*"
local healMatch="Heals .* for (%d+) to (%d+).*"
local dotRangeMatch="for (%d+) to (%d+).* over (%d+)"
local healAndHotMatch="Heals .* for (%d+) to (%d+).* and another (%d+) over (%d+)"

local function getSpellRank()
	local spellRank = 0
	if _G["GameTooltipTextRight1"]:IsVisible() then
		local right1Text = _G["GameTooltipTextRight1"]:GetText()
		if right1Text ~= nil then
			spellRank = string.match(right1Text, rankMatch) or 0
		end
	end
	return spellRank
end

local function getSpellName()
	return _G["GameTooltipTextLeft1"]:GetText()
end

local function getPowerCost()
	local powerCost = 0
	manaCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), manaMatch) or 0
	rageCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), rageMatch) or 0
	energyCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), energyMatch) or 0
	powerCost = manaCost + rageCost + energyCost
	return powerCost
end

local function getMeleeDamageStats()
	local ud = GetUnitData("player")
	local minDmg = ud["minDamage"]
	local maxDmg = ud["maxDamage"]
	local attackPower = ud["attackPower"] + ud["attackPowerMods"]
	local attackSpeed = UnitAttackSpeed("player")
	local avgDamage = (minDmg + maxDmg)/2
	
	return avgDamage, attackPower, attackSpeed
end

local function getCastTime()
	local castTime = string.match(_G["GameTooltipTextLeft3"]:GetText(), castTimeMatch) or 0
	if castTime ~= nil then
		castTime = tonumber(castTime)
	else
		castTime = 0
	end
	if _G["GameTooltipTextLeft3"]:GetText()=="Instant" then
		castTime = 1.5
	elseif _G["GameTooltipTextLeft3"]:GetText()=="Next melee" then
		castTime = math.floor(UnitAttackSpeed("player")*100)/100
	end
	
	return castTime
end

local function getCooldown()
	local cdText = _G["GameTooltipTextRight3"]:GetText()
	local cooldownSec = 0
	if _G["GameTooltipTextRight3"]:IsVisible() then
		if cdText ~= nil then
			cooldownSec = string.match(_G["GameTooltipTextRight3"]:GetText(), secCooldownMatch) or 0
		end
		if cooldownSec ~= nil then
			cooldownSec = tonumber(cooldownSec)
		else
			cooldownSec = 0
		end
	end
	return cooldownSec
end

local function getCooldownOrCastTime(cooldownSec, castTime)
	if cooldownSec == 0 then
		cooldownSec = castTime
	end
	
	return cooldownSec
end

local elapsed = 0
function AttackTip_OnUpdate(delta)
	elapsed = elapsed + delta
	if elapsed >= 1.0 then
		if PlayerStatFrameRight4StatText ~= nil and PlayerStatFrameRight4StatText:GetText() ~= nil then
			local newBonusHealing = tonumber(PlayerStatFrameRight4StatText:GetText())
			if bonusHealing ~= newBonusHealing then
				bonusHealing = newBonusHealing
				print('AttackTip: Adjusted bonusHealing to '..bonusHealing)
			end
		end
	end
end

local function getLowLevelSpellCoefficient(spellLevel)
	--return (spellLevel * 3/20 + 1)/4
	return 1 - ((20-spellLevel)*3/80)
end

local belowLevel20Spells = {}
belowLevel20Spells["Holy Light(Rank 1)"]=1
belowLevel20Spells["Holy Light(Rank 2)"]=6
belowLevel20Spells["Holy Light(Rank 3)"]=14
belowLevel20Spells["Healing Touch(Rank 1)"]=1
belowLevel20Spells["Healing Touch(Rank 2)"]=8
belowLevel20Spells["Healing Touch(Rank 3)"]=14
belowLevel20Spells["Regrowth(Rank 1)"]=12
belowLevel20Spells["Regrowth(Rank 2)"]=18
belowLevel20Spells["Rejuvenation(Rank 1)"]=4
belowLevel20Spells["Rejuvenation(Rank 2)"]=10
belowLevel20Spells["Rejuvenation(Rank 3)"]=16
belowLevel20Spells["Lesser Heal(Rank 1)"]=1
belowLevel20Spells["Lesser Heal(Rank 2)"]=4
belowLevel20Spells["Lesser Heal(Rank 3)"]=10
belowLevel20Spells["Heal(Rank 1)"]=16
belowLevel20Spells["Healing Wave(Rank 1)"]=1
belowLevel20Spells["Healing Wave(Rank 2)"]=6
belowLevel20Spells["Healing Wave(Rank 3)"]=12
belowLevel20Spells["Healing Wave(Rank 4)"]=18

local function modifyCoeffForLowLevelSpell(spellName, spellRank, coeffHeal)
	local rankedSpell = spellName.."(Rank "..spellRank..")"
	if belowLevel20Spells[rankedSpell] == nil then
		return coeffHeal
	else
		local spellLevel = belowLevel20Spells[rankedSpell]
		return coeffHeal*getLowLevelSpellCoefficient(spellLevel)
	end
end


local function processTooltip()
	local hasImpHt = true
	local giftOfNatureRank = 5
	local outputFmt0 = "%.0f"
	local outputFmt2 = "%.2f"
	local outputFmt3 = "%.3f"
	local regrowthHot=0
	local rejuvHot=0
	local lastSwiftmendHot=0
	local lastSwiftmendHotName=''
	local lastSwiftmendFactor=1
	local swiftmendRegrowthFactor = 18/20
	local swiftmendRejuvFactor = 12/12
	local maxHotDuration = 15
	local nextMeleeRageCost = 16

	local lineCount=GameTooltip:NumLines()
	if lineCount == 4 then
		local hotValue = 0
		
		local healValueLow = 0
		local healValueHigh = 0
		local healValue = 0
		
		local healAndHotDirectLow = 0
		local healAndHotDirectHigh = 0
		local healAndHotOverTime = 0
		
		local totalHeal = 0
		
		local castTime = 0
		local hotDuration = 0
		
		local hasDirect = false
		local hasHot = false
		
		local spellName = getSpellName()
		local spellRank = getSpellRank()
		local powerCost = getPowerCost()
		hotValue, hotDuration = string.match(_G["GameTooltipTextLeft4"]:GetText(), hotMatch)
		local cooldownSec = getCooldown()
		castTime = getCastTime()
		
		if hotValue == nil then
			hotValue = 0
		end
		
		if spellName == "Healing Touch" then
			if hasImpHt then
				castTime = castTime + 0.5
			end
		end
		if castTime == nil or castTime <= 1.5 then
			--castTime = 1.5
		end
		if castTime > maxCastTimeCoefficient then
			castTime = maxCastTimeCoefficient
		end
		
		local healAndHotDuration = 0
		healAndHotDirectLow, healAndHotDirectHigh, healAndHotOverTime, healAndHotDuration = string.match(_G["GameTooltipTextLeft4"]:GetText(), healAndHotMatch)
		if healAndHotDirectLow ~= nil and healAndHotDirectHigh ~= nil then
			hotDuration = healAndHotDuration
			healValue = (healAndHotDirectLow + healAndHotDirectHigh)/2
			hotValue = healAndHotOverTime
		else
			healValueLow, healValueHigh = string.match(_G["GameTooltipTextLeft4"]:GetText(), healMatch)
			if healValueLow ~= nil and healValueHigh ~= nil then
				healValue = (healValueLow + healValueHigh)/2
			end
		end
		
		local causesDamageValue = 0
		local causesDamageMin, causesDamageMax = string.match(_G["GameTooltipTextLeft4"]:GetText(), causesDamageRangeMatch)
		if causesDamageMin ~= nil and causesDamageMax ~= nil then
			causesDamageValue = (causesDamageMin + causesDamageMax)/2
		end
		
		if hotValue ~= nil then
			hotValue = tonumber(hotValue)
		else
			hotValue = 0
		end
		
		if hotDuration ~= nil then
			hotDuration = tonumber(hotDuration)
		else
			hotDuration = 0
		end
		
		if hotDuration > maxHotDuration then
			hotDuration = maxHotDuration
		end
		
		totalHeal = hotValue + healValue
		
		if spellName == "Swiftmend" then
			healValue = lastSwiftmendHot*lastSwiftmendFactor
			totalHeal = healValue
		end
		
		if powerCost > 0 and causesDamageValue > 0 then
			local calcDamage = causesDamageValue
			local calcDpm = calcDamage/powerCost
			cooldownSec = getCooldownOrCastTime(cooldownSec, castTime)
			local calcDps = calcDamage/cooldownSec
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffff0088".."DPM: "..string.format(outputFmt2, calcDpm))
			GameTooltip:AddLine("|cffff0088".."DPS: "..string.format(outputFmt2, calcDps))
			GameTooltip:AddLine("|cffff0088".."Damage: "..calcDamage)
			GameTooltip:Show()
		end
		
		if powerCost > 0 and totalHeal > 0 then
			if healValue > 0 then
				hasDirect = true
			end
			if hotValue > 0 then
				hasHot = true
			end
		
			local coeffHeal = 0
			local coeffHot = 0
			local healApplied = 0
			local hotApplied = 0
			local bonusHealingApplied = 0
			if spellName ~= "Swiftmend" then
				if spellName == "Regrowth" then
					if applyBonusHealing then
						coeffHeal = 0.3
						coeffHot = 0.7
						coeffHeal = modifyCoeffForLowLevelSpell(spellName, spellRank, coeffHeal)
						coeffHot = modifyCoeffForLowLevelSpell(spellName, spellRank, coeffHot)
						healValue, healApplied = applyBonusHealingValue(healValue, coeffHeal, bonusHealing)
						hotValue, hotApplied = applyBonusHealingValue(hotValue, coeffHot, bonusHealing)
					end
				else
					if applyBonusHealing then
						if hasDirect then
							coeffHeal = castTime/maxCastTimeCoefficient
							coeffHeal = modifyCoeffForLowLevelSpell(spellName, spellRank, coeffHeal)
							healValue, healApplied = applyBonusHealingValue(healValue, coeffHeal, bonusHealing)
						end
						if hasHot then
							coeffHot = hotDuration/maxHotDuration
							coeffHot = modifyCoeffForLowLevelSpell(spellName, spellRank, coeffHot)
							hotValue, hotApplied = applyBonusHealingValue(hotValue, coeffHot, bonusHealing)
						end
					end
				end
				totalHeal = hotValue + healValue
				bonusHealingApplied = healApplied + hotApplied
			end
		
			if spellName == "Regrowth" then
				regrowthHot = hotValue
				lastSwiftmendHot = hotValue
				lastSwiftmendHotName = spellName
				lastSwiftmendFactor = swiftmendRegrowthFactor
			elseif spellName == "Rejuvenation" then
				rejuvFullHeal = hotValue
				lastSwiftmendHot = hotValue
				lastSwiftmendHotName = spellName
				lastSwiftmendFactor = swiftmendRejuvFactor
			end
		
			local hpm = totalHeal / powerCost
			local hps = healValue / castTime
			local hpmText = string.format(outputFmt2, hpm)
			local hpsText = string.format(outputFmt2, hps)
			
			local totalHealText = string.format(outputFmt0, totalHeal)
			local directHealText = string.format(outputFmt0, healValue)
			local hotHealText = string.format(outputFmt0, hotValue)
			--print(powerCost.. " Power")
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cff00ff00".."HPM: "..hpmText)
			GameTooltip:AddLine("|cff00ff00".."HPS: "..hpsText)
			if healValue > 0 and hotValue > 0 then
				GameTooltip:AddLine("|cff00ff00".."Healing: "..totalHealText)
			end
			if healValue > 0 then
				GameTooltip:AddLine("|cff00ff00".."Direct: "..directHealText)
			end
			if hotValue > 0 then
				GameTooltip:AddLine("|cff00ff00".."HoT: "..hotHealText)
			end
			if bonusHealingApplied > 0 then
				GameTooltip:AddLine("|cff00ff00".."+Heal: "..string.format(outputFmt0, bonusHealingApplied))
			end
			if coeffHeal > 0 then
				GameTooltip:AddLine("|cff00ff00".."coeffHeal: "..string.format(outputFmt3, coeffHeal))
			end
			if coeffHot > 0 then
				GameTooltip:AddLine("|cff00ff00".."coeffHot: "..string.format(outputFmt3, coeffHot))
			end
			--GameTooltip:AddLine("|cff00ff00".."Cast Time: "..castTime)
			--GameTooltip:AddLine("|cff00ff00".."Duration: "..hotDuration)
			if spellName == "Swiftmend" then
				GameTooltip:AddLine("|cff00ff00".."Swiftmend HoT: "..lastSwiftmendHotName)
			end
			GameTooltip:Show()
		end
		--print("|cff00ff00------")
		for i=1, GameTooltip:NumLines() do 
			--print(_G["GameTooltipTextLeft"..i]:GetText())
		end
	elseif lineCount == 5 or lineCount == 6 then
		local weaponDamagePct = 0
		
		weaponDamagePct = string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), weaponDamageMatch) or 0
		if weaponDamagePct ~= nil then
			weaponDamagePct = tonumber(weaponDamagePct)/100
		end
		if string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), meleeDamageMatch) then
			weaponDamagePct = 1
		end
		
		local spellName = getSpellName()
		local spellRank = getSpellRank()
		local powerCost = getPowerCost()
		local avgDamage, attackPower, attackSpeed = getMeleeDamageStats()
		
		local dotDamage = 0
		local dotMin, dotMax, dotDuration = string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), dotRangeMatch)
		if dotMin ~= nil and dotMax ~= nil and dotDuration ~= nil then
			dotDamage = (dotMin + dotMax)/2
		end

		local cooldownSec = getCooldown()
		local castTime = getCastTime()

		if powerCost > 0 and weaponDamagePct ~= 0 then
			local calcDamage = weaponDamagePct*avgDamage
			local calcDpr = calcDamage/powerCost
			cooldownSec = getCooldownOrCastTime(cooldownSec, castTime)
			local calcDps = calcDamage/cooldownSec
			local calcDamageText = string.format(outputFmt0, calcDamage)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffee1111".."DPR: "..string.format(outputFmt2,calcDpr))
			GameTooltip:AddLine("|cffee1111".."DPS: "..string.format(outputFmt2,calcDps))
			GameTooltip:AddLine("|cffee1111".."Damage: "..calcDamageText)
			GameTooltip:AddLine("|cffee1111".."Cooldown: "..cooldownSec)
			GameTooltip:Show()
		end
		
		causingDamageValue = string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), causingDamageMatch) or 0
		if causingDamageValue == 0 then
			causingDamageValue = string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), doingDamageMatch) or 0
		end
		if causingDamageValue ~= nil then
			causingDamageValue = tonumber(causingDamageValue)
		end
		
		if causingDamageValue == nil or causingDamageValue == 0 then
			causingMinDamage, causingMaxDamage = string.match(_G["GameTooltipTextLeft"..lineCount]:GetText(), causingRangeDamageMatch)
			if causingMinDamage ~= nil and causingMaxDamage ~= nil then
				causingDamageValue = (causingMinDamage + causingMaxDamage)/2
			end
			if causingDamageValue ~= nil then
				causingDamageValue = tonumber(causingDamageValue)
			end
		end
		
		if causingDamageValue == 0 and dotDamage > 0 then
			causingDamageValue = dotDamage
			castTime = dotDuration
		end
		
		if powerCost > 0 and causingDamageValue > 0 then		
			local calcDamage = causingDamageValue
			local calcDpr = calcDamage/powerCost
			cooldownSec = getCooldownOrCastTime(cooldownSec, castTime)
			local calcDps = calcDamage/cooldownSec
			local calcDamageText = string.format(outputFmt0, calcDamage)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cffee1111".."DPR: "..string.format(outputFmt2,calcDpr))
			GameTooltip:AddLine("|cffee1111".."DPS: "..string.format(outputFmt2,calcDps))
			GameTooltip:AddLine("|cffee1111".."Damage: "..calcDamage)
			GameTooltip:AddLine("|cffee1111".."Cooldown: "..cooldownSec)
			if spellName == "Cleave" then
				GameTooltip:AddLine("|cffee1111".."2x DPR: "..string.format(outputFmt2,2*calcDpr))
				GameTooltip:AddLine("|cffee1111".."2x DPS: "..string.format(outputFmt2,2*calcDps))
				GameTooltip:AddLine("|cffee1111".."2x Damage: "..2*calcDamage)
			end
			if spellName == "Execute" then
				local executeRageCost = 15
				local damage100Rage = calcDamage + 12*(100-executeRageCost)
				local dpr100Rage = damage100Rage/powerCost
				local damage130Rage = calcDamage + 12*(130-executeRageCost)
				local dpr130Rage = damage100Rage/powerCost
				GameTooltip:AddLine("|cffee1111".."100 Rage DPR: "..dpr100Rage)
				GameTooltip:AddLine("|cffee1111".."100 Rage Damage: "..damage100Rage)
				GameTooltip:AddLine("|cffee1111".."130 Rage DPR: "..dpr130Rage)
				GameTooltip:AddLine("|cffee1111".."130 Rage Damage: "..damage130Rage)
			end
			GameTooltip:Show()
		end
	end
end

function AttackTip_OnEvent()
	if event == "ADDON_LOADED" then
		if (string.lower(arg1) == "attacktip") then
			if AttackTip_GS ~= nil then
				if AttackTip_GS["bonusHealing"] ~= nil then
					bonusHealing = AttackTip_GS["bonusHealing"]
					print("Set bonus healing to: " .. bonusHealing)
				end
			end
		
			GameTooltip:HookScript("OnShow", function(self)
				processTooltip()
			end)
			
			print("AttackTip loaded")
		end
	end
end

SLASH_ATTACKTIP1 = "/at"
SLASH_ATTACKTIP2 = "/attacktip"

local function ChatHandler(msg)
	local vars = SplitString(msg, " ")
	for k,v in vars do
		if v == "" then
			v = nil
		end
	end

	local cmd, arg = vars[1], vars[2]
	if vars[1] ~= nil then
		bonusHealing = tonumber(vars[1])
		print("Set bonus healing to: " .. bonusHealing)
		if AttackTip_GS == nil then
			AttackTip_GS = {}
			AttackTip_GS["bonusHealing"] = bonusHealing
		end
	else
		print("Usage:")
		print("/at [number]: Set bonus healing")
	end
end

SlashCmdList["ATTACKTIP"] = ChatHandler
