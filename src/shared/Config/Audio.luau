--!strict
--[[
	Audio — identyfikatory dźwięków z Creator Store.

	Wszystkie pochodzą z jednej biblioteki (Pro Sound Effects, darmowe,
	udostępniane przez Roblox), wybrane po opisie i długości. Jedna
	biblioteka = spójne nagrania i jedna licencja do sprawdzenia.

	Dźwięk to asset na platformie, nie plik w repo — tu jest tylko numer.
	Gdy któryś przestanie się ładować, gra działa dalej bez niego
	(`Effects/Sfx` niczego nie zakłada).

	`volume` to głośność bazowa. Skubnięcie jest celowo dużo cichsze niż
	branie: gracz ma je odróżniać także na słuch (FISHING_MECHANICS.md).
]]

export type Clip = {
	id: string,
	volume: number,
}

local Audio: { [string]: Clip } = {
	-- Spławik ląduje na wodzie. „Small Splash Shallow Water", 2,8 s.
	cast = { id = "rbxassetid://9119293555", volume = 0.45 },
	-- Fałszywe skubnięcie. „Drip Plop", 0,6 s.
	nibble = { id = "rbxassetid://9114175929", volume = 0.35 },
	-- Prawdziwe branie. „Puddle Impact Big Puddle Splash", 2,0 s.
	bite = { id = "rbxassetid://9117941618", volume = 0.9 },
	-- Ryba wyholowana albo wyskakująca nad wodę. 2,5 s.
	splash = { id = "rbxassetid://9117940312", volume = 0.8 },
	-- Tło przy jeziorze. „Water Lap Small Waves", pętla 41 s.
	lake = { id = "rbxassetid://9120572579", volume = 0.3 },
	-- Deszcz. „Rain Continuous Drizzle", pętla 36 s.
	rain = { id = "rbxassetid://9112852671", volume = 0.5 },
}

return table.freeze(Audio)
