--!strict
--[[
	Cast — matematyka rzutu: moc, odległość, czas lotu i rozkład skubnięć.

	Mieszka w `shared/`, bo liczą to obie strony. Klient rysuje pasek mocy
	i prowadzi spławik po łuku, serwer z tej samej mocy wyznacza punkt
	lądowania i głębokość. Dwie implementacje rozjechałyby się i spławik
	stałby gdzie indziej, niż naprawdę bierze ryba.

	Czysta matematyka bez typów Robloxa — pilnuje jej `tests/run.luau`.
	Specyfikacja: docs/design/FISHING_MECHANICS.md.
]]

local Cast = {}

-- Czas lotu spławika przy rzucie minimalnym i maksymalnym (sekundy).
-- Dłuższy rzut leci dłużej, inaczej daleki spławik wyglądałby jak pocisk.
local FLIGHT_MIN = 0.45
local FLIGHT_MAX = 0.9

-- Skubnięcie nie przychodzi od razu po lądowaniu (spławik jeszcze się
-- kołysze i gracz by go nie odróżnił) ani tuż przed braniem (zlałoby się
-- z nim w jedno zdarzenie).
local NIBBLE_AFTER_LANDING = 0.9
local NIBBLE_BEFORE_BITE = 0.8
-- Najkrótszy odstęp między skubnięciami, żeby każde było osobnym sygnałem.
local NIBBLE_SPACING = 0.6

--[[
	Moc w chwili `elapsed` sekund od rozpoczęcia zamachu.

	Pasek jest WAHADŁOWY: 0 -> 1 -> 0 -> 1... z pełnym okresem `period`.
	Gdyby rósł i zatrzymywał się na 100%, najlepszą strategią byłoby zawsze
	przetrzymać — czyli rzut znów nie zawierałby żadnej decyzji.
]]
function Cast.powerAt(elapsed: number, period: number): number
	if period <= 0 or elapsed <= 0 then
		return 0
	end

	local phase = (elapsed % period) / period
	return if phase <= 0.5 then phase * 2 else (1 - phase) * 2
end

--[[
	Sprowadza moc do zakresu 0..1.

	NaN sprawdzamy JAWNIE i przed `math.clamp`: NaN przegrywa każde
	porównanie, więc clamp przepuściłby go dalej i punkt lądowania
	wyszedłby jako NaN. To jest wartość przychodząca od klienta.
]]
function Cast.clampPower(power: number): number
	if power ~= power then
		return 0
	end
	return math.clamp(power, 0, 1)
end

--[[ Odległość rzutu dla danej mocy. Moc 0 to rzut minimalny, nie zerowy:
     szybkie kliknięcie ma nadal postawić spławik na wodzie. ]]
function Cast.distanceFor(power: number, minDistance: number, maxDistance: number): number
	local span = math.max(maxDistance - minDistance, 0)
	return minDistance + span * Cast.clampPower(power)
end

--[[ Czas lotu spławika dla rzutu na `distance` z `maxDistance` możliwych. ]]
function Cast.flightTime(distance: number, maxDistance: number): number
	if maxDistance <= 0 then
		return FLIGHT_MIN
	end
	local fraction = math.clamp(distance / maxDistance, 0, 1)
	return FLIGHT_MIN + (FLIGHT_MAX - FLIGHT_MIN) * fraction
end

--[[
	Momenty skubnięć (sekundy od lądowania) przed braniem po `biteDelay`.

	`rolls` to liczby losowe 0..1, po jednej na skubnięcie — ich liczba
	to liczba skubnięć, o jaką prosimy. Losowość przychodzi z zewnątrz,
	żeby test mógł podać konkretne wartości.

	Czas między lądowaniem a braniem dzielimy na równe przedziały i w każdym
	stawiamy jedno skubnięcie. Dzięki temu są posortowane i rozsunięte bez
	żadnego poprawiania po fakcie. Gdy czasu jest za mało, skubnięć jest
	mniej, niż proszono — krótkie czekanie nie ma być nimi zapchane.
]]
function Cast.nibbleTimes(biteDelay: number, rolls: { number }): { number }
	local window = biteDelay - NIBBLE_AFTER_LANDING - NIBBLE_BEFORE_BITE
	local count = math.min(#rolls, math.floor(window / NIBBLE_SPACING))
	if count <= 0 then
		return {}
	end

	local slot = window / count
	-- Skubnięcie zajmuje początek swojego przedziału, a reszta przedziału
	-- to gwarantowany odstęp od następnego.
	local jitter = slot - NIBBLE_SPACING

	local times = table.create(count)
	for index = 1, count do
		local roll = math.clamp(rolls[index], 0, 1)
		times[index] = NIBBLE_AFTER_LANDING + (index - 1) * slot + roll * jitter
	end
	return times
end

return table.freeze(Cast)
