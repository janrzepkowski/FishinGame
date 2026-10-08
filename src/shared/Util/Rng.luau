--!strict
--[[
	Rng — losowanie oparte na przekazanym `Random`, nie na globalnym `math.random`.

	Dlaczego przekazujemy generator zamiast używać globalnego: dzięki temu
	da się odtworzyć konkretny przebieg w teście (`Random.new(1234)`).
	Globalny `math.random` jest wspólny dla całego serwera, więc jeden test
	zmienia wyniki drugiego.
]]

local Rng = {}

--[[
	Losuje indeks proporcjonalnie do wag.

	Wagi NIE muszą sumować się do 1 ani do 100 — to celowe. Dodanie nowej ryby
	do katalogu nie wymaga wtedy przeliczania wszystkich pozostałych wpisów.

	Wagi <= 0 są pomijane (wygodny sposób na czasowe wyłączenie wpisu).
	Zwraca 0, jeśli nie ma z czego wybierać.
]]
function Rng.weightedIndex(generator: Random, weights: { number }): number
	local total = 0
	for _, weight in weights do
		if weight > 0 then
			total += weight
		end
	end

	if total <= 0 then
		return 0
	end

	local roll = generator:NextNumber() * total
	local lastValid = 0

	for index, weight in weights do
		if weight <= 0 then
			continue
		end

		lastValid = index
		roll -= weight
		if roll <= 0 then
			return index
		end
	end

	-- Dotarcie tutaj oznacza błąd zaokrąglenia zmiennoprzecinkowego przy
	-- ostatnim wpisie. Zwracamy ostatni poprawny indeks zamiast 0.
	return lastValid
end

--[[
	Liczba z przedziału [min, max], ale z krzywą.

	`skew` > 1 ściąga wyniki w stronę `min`, `skew` < 1 w stronę `max`,
	`skew` = 1 daje rozkład równomierny.

	Używamy tego do masy ryby: przy skew = 2.2 większość egzemplarzy jest
	drobna, a okazowa sztuka jest realnie rzadka. Rozkład równomierny dawałby
	rekordy co trzeci rzut i nic by nie znaczyły.
]]
function Rng.skewedNumber(generator: Random, min: number, max: number, skew: number): number
	local roll = generator:NextNumber() ^ skew
	return min + (max - min) * roll
end

return table.freeze(Rng)
