--!strict
--[[
	Rods — drabinka wędek.

	Każdy kolejny tier poprawia cztery rzeczy naraz: szansę na rzadkie ryby
	(`luck`), tempo brań (`biteSpeed`), okno na podcięcie (`reelWindow`)
	i wytrzymałość żyłki (`lineStrength`). To daje wyraźnie wyczuwalny skok
	po zakupie — jeden parametr by nie wystarczył.

	`lineStrength` jest tu najważniejszy dla ODCZUCIA: pozostałe trzy zmieniają
	statystyki, ta jedna zmienia to, co gracz robi rękami. Na startowej wędce
	szczupak zrywa żyłkę, jeśli nie puścisz przy szarpnięciu; na turniejowej
	można go przeholować siłą. To jest realna nagroda za zakup, a nie
	kolejny procent w tabelce.
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
		lineStrength = 1.0,
		color = Color3.fromRGB(240, 150, 80),
	},
	{
		id = "fiber",
		displayName = "Wędka kompozytowa",
		order = 2,
		price = 400,
		luck = 1.12,
		biteSpeed = 0.85,
		reelWindow = 1.7,
		lineStrength = 1.2,
		color = Color3.fromRGB(60, 200, 210),
	},
	{
		id = "carbon",
		displayName = "Wędka karbonowa",
		order = 3,
		price = 2200,
		luck = 1.25,
		biteSpeed = 0.7,
		reelWindow = 1.9,
		lineStrength = 1.45,
		color = Color3.fromRGB(150, 100, 240),
	},
	{
		id = "tournament",
		displayName = "Wędka turniejowa",
		order = 4,
		price = 9000,
		luck = 1.42,
		biteSpeed = 0.55,
		reelWindow = 2.2,
		lineStrength = 1.8,
		color = Color3.fromRGB(255, 196, 40),
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
