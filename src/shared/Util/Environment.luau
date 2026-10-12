--!strict
--[[
	Environment — pora dnia i pogoda jako liczby.

	Dwie rzeczy liczą obie strony i muszą wyjść tak samo:
	  * GODZINĘ — klient ustawia z niej słońce, serwer sprawdza, czy jest noc,
	  * WPŁYW na łowienie — serwer go stosuje, klient o nim informuje.

	Godzina nie jest wysyłana przez sieć. Obie strony liczą ją z tego samego
	zsynchronizowanego zegara (`workspace:GetServerTimeNow()`), więc cykl
	dnia nie kosztuje ani jednego pakietu i jest płynny co do klatki.

	Czysta matematyka — pilnuje jej `tests/run.luau`.
]]

local Environment = {}

export type Weather = "Clear" | "Rain"

-- Noc trwa od zmierzchu do świtu. Przy szerokości geograficznej z
-- `default.project.json` słońce jest pod horyzontem mniej więcej wtedy.
local DUSK = 20
local DAWN = 5.5

--[[
	Godzina zegarowa 0..24 w chwili `serverTime`.

	Doba w grze trwa `dayLength` sekund. Liczymy ją od zera zegara serwerów,
	bez żadnego „momentu startu": każdy serwer i każdy klient dostaje tę samą
	godzinę, a gracz przeskakujący między serwerami nie cofa się w czasie.
]]
function Environment.clockAt(serverTime: number, dayLength: number): number
	if dayLength <= 0 then
		return 12
	end
	return (serverTime % dayLength) / dayLength * 24
end

function Environment.isNight(clock: number): boolean
	return clock >= DUSK or clock < DAWN
end

--[[
	Jak bardzo jest ciemno, 0..1 — do płynnego rozjaśniania obrazu nocą.

	Narasta i opada przez godzinę wokół zmierzchu i świtu, żeby korekta
	ekspozycji nie włączała się skokiem w jednej klatce.
]]
function Environment.darkness(clock: number): number
	local hour = clock % 24
	if hour >= DUSK then
		return math.clamp(hour - DUSK, 0, 1)
	elseif hour < DAWN - 1 then
		return 1
	elseif hour < DAWN then
		return math.clamp(DAWN - hour, 0, 1)
	end
	return 0
end

--[[ Mnożnik czasu oczekiwania na branie (mniej = szybciej). W deszczu
     ryby biorą chętniej — pogoda ma być powodem, żeby zostać nad wodą,
     a nie żeby się schować. ]]
function Environment.biteDelayMultiplier(weather: string): number
	return if weather == "Rain" then 0.75 else 1
end

--[[ Mnożnik szczęścia. Nocą łatwiej o rzadką rybę; skromnie, bo wchodzi
     w potęgę rzadkości razem z wędką i głębokością. ]]
function Environment.luckMultiplier(clock: number): number
	return if Environment.isNight(clock) then 1.1 else 1
end

--[[ Pogoda na następny okres. `roll` to liczba losowa 0..1 z zewnątrz,
     żeby test mógł sprawdzić oba wyniki. ]]
function Environment.pickWeather(roll: number, rainChance: number): Weather
	return if roll < rainChance then "Rain" else "Clear"
end

return table.freeze(Environment)
