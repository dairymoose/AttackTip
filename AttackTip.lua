
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

local hasImpHt = true
local giftOfNatureRank = 5
local manaMatch="(%d+) Mana"
local rageMatch="(%d+) Rage"
local energyMatch="(%d+) Energy"
local hotMatch="Heals .* for (%d+) over (%d+) .*"
local healMatch="Heals .* for (%d+) to (%d+).*"
local healAndHotMatch="Heals .* for (%d+) to (%d+).* and another (%d+) over (%d+)"
local castTimeMatch="(.+) sec cast"
local outputFmt0 = "%.0f"
local outputFmt2 = "%.2f"
local regrowthHot=0
local rejuvHot=0
local lastSwiftmendHot=0
local lastSwiftmendHotName=''
local lastSwiftmendFactor=1
local swiftmendRegrowthFactor = 18/20
local swiftmendRejuvFactor = 12/12
local maxHotDuration = 15
local function processTooltip()
	local lineCount=GameTooltip:NumLines()
	if lineCount == 4 then
		local rageCost = 0
		local manaCost = 0
		local energyCost = 0
		local powerCost = 0
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
		
		local spellName = _G["GameTooltipTextLeft1"]:GetText()
		manaCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), manaMatch) or 0
		rageCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), rageMatch) or 0
		energyCost = string.match(_G["GameTooltipTextLeft2"]:GetText(), energyMatch) or 0
		hotValue, hotDuration = string.match(_G["GameTooltipTextLeft4"]:GetText(), hotMatch)
		castTime = string.match(_G["GameTooltipTextLeft3"]:GetText(), castTimeMatch) or 0
		
		if hotValue == nil then
			hotValue = 0
		end
		
		if castTime ~= nil then
			castTime = tonumber(castTime)
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
		powerCost = manaCost + rageCost + energyCost
		
		if spellName == "Swiftmend" then
			totalHeal = lastSwiftmendHot*lastSwiftmendFactor
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
						healValue, healApplied = applyBonusHealingValue(healValue, coeffHeal, bonusHealing)
						hotValue, hotApplied = applyBonusHealingValue(hotValue, coeffHot, bonusHealing)
					end
				else
					if applyBonusHealing then
						if hasDirect then
							coeffHeal = castTime/maxCastTimeCoefficient
							healValue, healApplied = applyBonusHealingValue(healValue, coeffHeal, bonusHealing)
						end
						if hasHot then
							coeffHot = hotDuration/maxHotDuration
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
			local hpmText = string.format(outputFmt2, hpm)
			
			local totalHealText = string.format(outputFmt0, totalHeal)
			local directHealText = string.format(outputFmt0, healValue)
			local hotHealText = string.format(outputFmt0, hotValue)
			--print(powerCost.. " Power")
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cff00ff00".."HPM: "..hpmText)
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
				GameTooltip:AddLine("|cff00ff00".."coeffHeal: "..string.format(outputFmt2, coeffHeal))
			end
			if coeffHot > 0 then
				GameTooltip:AddLine("|cff00ff00".."coeffHot: "..string.format(outputFmt2, coeffHot))
			end
			GameTooltip:AddLine("|cff00ff00".."Cast Time: "..castTime)
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
