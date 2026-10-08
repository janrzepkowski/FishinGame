--!strict
--[[
	Rods — drabinka wędek.

	Każdy kolejny tier poprawia trzy rzeczy naraz: szansę na rzadkie ryby
	(`luck`), tempo brań (`biteSpeed`) i okno na podcięcie (`reelWindow`).
	To daje wyraźnie wyczuwalny skok po zakupie — jeden parametr by nie wystarczył.
]]

local Types = require(script.Parent.Parent.Types)

type RodDefinition = Types.RodDefinition

local Rods = {}

local DEFINITIONS: { RodDefinition } = {
	{
		id = "wooden",
		displayName = "Wędka drewniana",
		order = 1,
		price = 0,
		luck = 1.0,
		biteSpeed = 1.0,
		reelWindow = 1.5,
		color = Color3.fromRGB(141, 102, 60),
	},
	{
		id = "fiber",
		displayName = "Wędka kompozytowa",
		order = 2,
		price = 400,
		luck = 1.12,
		biteSpeed = 0.85,
		reelWindow = 1.7,
		color = Color3.fromRGB(72, 86, 102),
	},
	{
		id = "carbon",
		displayName = "Wędka karbonowa",
		order = 3,
		price = 2200,
		luck = 1.25,
		biteSpeed = 0.7,
		reelWindow = 1.9,
		color = Color3.fromRGB(38, 40, 46),
	},
	{
		id = "tournament",
		displayName = "Wędka turniejowa",
		order = 4,
		price = 9000,
		luck = 1.42,
		biteSpeed = 0.55,
		reelWindow = 2.2,
		color = Color3.fromRGB(196, 158, 72),
	},
}

table.sort(DEFINITIONS, function(a, b)
	return a.order < b.order
end)

local byId: { [string]: RodDefinition } = {}
for _, definition in DEFINITIONS do
	assert(byId[definition.id] == nil, `zduplikowane id wędki: {definition.id}`)
	byId[definition.id] = table.freeze(definition)
end

table.freeze(DEFINITIONS)
table.freeze(byId)

--[[ Wędki posortowane po `order` — gotowe do wyrzucenia w UI sklepu. ]]
function Rods.all(): { RodDefinition }
	return DEFINITIONS
end

function Rods.find(id: string): RodDefinition?
	return byId[id]
end

function Rods.expect(id: string): RodDefinition
	local definition = byId[id]
	if definition == nil then
		error(`nieznane id wędki: {id}`, 2)
	end
	return definition
end

return table.freeze(Rods)
