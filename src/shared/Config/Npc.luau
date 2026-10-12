--!strict
--[[
	Npc — sprzedawcy przy stoiskach: wygląd, głos i kwestie.

	Jeden wpis na stoisko, kluczem jest `standKind` z `GameConfig`. Serwer
	czyta stąd wygląd (stawia postać), klient — kwestie i głos (pokazuje
	dymek i odtwarza okrzyk). Dlatego plik jest w `shared/`.

	KWESTIE SĄ KRÓTKIE I JEST ICH KILKA NA SYTUACJĘ. Sprzedawca, który przy
	każdej sprzedaży mówi to samo zdanie, po trzecim razie brzmi jak automat.

	GŁOS TO OKRZYKI, NIE ZDANIA. Syntezator mowy Robloxa
	(`AudioTextToSpeech`) nie obsługuje polskiego, więc pełne kwestie
	brzmiałyby jak czytane przez cudzoziemca. Dymek niesie treść po polsku,
	a głos dokłada krótki, niezależny od języka okrzyk („Oho!", „Ha ha!").
]]

local GameConfig = require(script.Parent.Game)

local Npc = {}

--[[ Sytuacje, w których sprzedawca się odzywa. `greet` wybiera klient,
     gdy gracz podejdzie; pozostałe ogłasza serwer po rozstrzygnięciu
     transakcji (`Net.NpcLine`). ]]
export type LineKey = "greet" | "sold" | "empty" | "bought" | "poor" | "owned"

export type Definition = {
	displayName: string,
	skin: Color3,
	shirt: Color3,
	pants: Color3,
	hat: Color3,
	-- Głos syntezatora i przesunięcie wysokości w półtonach.
	voiceId: string,
	pitch: number,
	-- Okrzyki do losowania; krótkie i bez znaczenia w żadnym języku.
	shouts: { string },
	lines: { [string]: { string } },
}

local DEFINITIONS: { [string]: Definition } = {
	[GameConfig.STAND_FISH_BUYER] = {
		displayName = "Stary Bronek",
		skin = Color3.fromRGB(226, 178, 140),
		shirt = Color3.fromRGB(86, 164, 128),
		pants = Color3.fromRGB(104, 76, 50),
		hat = Color3.fromRGB(216, 190, 120),
		-- Lista głosów: docs Robloxa „List of artificial voices".
		-- 5 = męski, 2 = żeński.
		voiceId = "5",
		pitch = -3,
		shouts = { "Oho!", "Ha ha!", "Mhm.", "No no!" },
		lines = {
			greet = {
				"Co tam dziś w siatce?",
				"Bierze coś, czy same patyki?",
				"Podejdź, podejdź, zważymy.",
			},
			sold = {
				"Ładna sztuka! Dzięki.",
				"Dziękuję, zapraszam znowu.",
				"Świeżutkie, od razu pójdą.",
				"No, to się nazywa połów!",
			},
			empty = {
				"Pusta torba? Leć nad wodę.",
				"Najpierw złów, potem handlujemy.",
			},
		},
	},
	[GameConfig.STAND_ROD_SHOP] = {
		displayName = "Pani Halina",
		skin = Color3.fromRGB(240, 196, 160),
		shirt = Color3.fromRGB(206, 152, 74),
		pants = Color3.fromRGB(78, 84, 96),
		hat = Color3.fromRGB(154, 114, 74),
		voiceId = "2",
		pitch = 2,
		shouts = { "Aha!", "O!", "Mhm, mhm.", "Ho ho!" },
		lines = {
			greet = {
				"Lepsza wędka, grubsza ryba.",
				"Szukasz czegoś mocniejszego?",
				"Zapraszam, wszystko sprawdzone.",
			},
			bought = {
				"Dobry wybór! Połamania kija.",
				"Dziękuję, niech dobrze służy.",
				"Tą to i suma wyciągniesz.",
			},
			poor = {
				"Jeszcze trochę brakuje. Wróć z połowem.",
				"Na tę musisz jeszcze połowić.",
			},
			owned = {
				"Tę już przecież masz.",
			},
		},
	},
}

for _, definition in DEFINITIONS do
	table.freeze(definition)
end
table.freeze(DEFINITIONS)

function Npc.find(standKind: string): Definition?
	return DEFINITIONS[standKind]
end

--[[ Kwestie na daną sytuację; pusta tablica, gdy sprzedawca nie ma nic
     do powiedzenia (np. skup nie komentuje zakupu wędki). ]]
function Npc.lines(standKind: string, key: string): { string }
	local definition = DEFINITIONS[standKind]
	if not definition then
		return {}
	end
	return definition.lines[key] or {}
end

return table.freeze(Npc)
