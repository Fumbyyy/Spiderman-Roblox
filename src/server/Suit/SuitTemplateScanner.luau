--!strict
--[[
	SuitTemplateScanner.luau
	Intelligent Auto-Discovery & Caching of 3D Spider-Man suit models in Workspace and ReplicatedStorage.Suits.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SuitTemplateScanner = {}

local suitsFolder: Folder = (ReplicatedStorage:FindFirstChild("Suits") :: Folder?) or (function()
	local f = Instance.new("Folder")
	f.Name = "Suits"
	f.Parent = ReplicatedStorage
	return f
end)()

-- Identifies which canonical Spider-Man suit a model represents based on names, accessories, and parts
function SuitTemplateScanner.identifySuitIdForModel(model: Model): string?
	local mName = string.lower(model.Name)

	-- Direct name matching
	if string.find(mName, "symbiote") or string.find(mName, "venom") then return "SymbioteBlack" end
	if string.find(mName, "2099") or string.find(mName, "miguel") then return "Cyber2099" end
	if string.find(mName, "scarlet") then return "ScarletSpider" end
	if string.find(mName, "stark") or string.find(mName, "iron") then return "StarkTechSuit" end
	if string.find(mName, "miles") or string.find(mName, "spiderverse") or string.find(mName, "yugoxsf") then return "MilesSpiderVerse" end
	if string.find(mName, "classic") or string.find(mName, "wistumy") or string.find(mName, "peter") then return "ClassicSuit" end

	-- Deep inspection of accessories, parts, and clothing
	for _, child in model:GetDescendants() do
		local cName = string.lower(child.Name)
		if string.find(cName, "symbiote") then
			return "SymbioteBlack"
		elseif string.find(cName, "2099") or string.find(cName, "blade") then
			return "Cyber2099"
		elseif string.find(cName, "scarlet") or string.find(cName, "blue hoodie") then
			return "ScarletSpider"
		elseif string.find(cName, "extraredhead") or string.find(cName, "waldo") or string.find(cName, "iron") then
			return "StarkTechSuit"
		elseif string.find(cName, "darkhood") or string.find(cName, "sneaker") or string.find(cName, "comic eyes") then
			return "MilesSpiderVerse"
		elseif string.find(cName, "tight red web") or string.find(cName, "wistumy") then
			return "ClassicSuit"
		end
	end

	return nil
end

-- Scans Workspace showroom lineup and automatically registers templates into ReplicatedStorage.Suits
function SuitTemplateScanner.scanAndCacheTemplates()
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name ~= "Terrain" and not child:GetAttribute("IsPlayerCharacter") then
			local matchedSuitId = SuitTemplateScanner.identifySuitIdForModel(child)
			if matchedSuitId and not suitsFolder:FindFirstChild(matchedSuitId) then
				local clone = child:Clone()
				clone.Name = matchedSuitId

				-- Clean up scripts and humanoids inside the template so it acts as a clean static wardrobe asset
				for _, desc in clone:GetDescendants() do
					if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("Sound") then
						desc:Destroy()
					elseif desc:IsA("Humanoid") then
						desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
				end

				clone.Parent = suitsFolder
			end
		end
	end
end

-- Resolves the template model for a given suit ID
function SuitTemplateScanner.getSuitTemplate(suitId: string): Model?
	local template = suitsFolder:FindFirstChild(suitId) :: Model?
	if template then return template end

	-- Check if any model inside suitsFolder matches this suit ID via name/appearance
	for _, child in suitsFolder:GetChildren() do
		if child:IsA("Model") and SuitTemplateScanner.identifySuitIdForModel(child) == suitId then
			return child
		end
	end

	-- Re-scan Workspace if not cached yet
	SuitTemplateScanner.scanAndCacheTemplates()
	template = suitsFolder:FindFirstChild(suitId) :: Model?
	if template then return template end

	for _, child in suitsFolder:GetChildren() do
		if child:IsA("Model") and SuitTemplateScanner.identifySuitIdForModel(child) == suitId then
			return child
		end
	end

	-- Check direct Workspace children as fallback
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name ~= "Terrain" then
			if SuitTemplateScanner.identifySuitIdForModel(child) == suitId then
				return child
			end
		end
	end

	return nil
end

-- Run initial template discovery
SuitTemplateScanner.scanAndCacheTemplates()

return SuitTemplateScanner
