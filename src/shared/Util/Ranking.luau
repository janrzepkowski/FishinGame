--!strict
--[[
	Ranking — składanie czołówki z dwóch źródeł.

	Ranking w grze ma dwa źródła i żadne z nich samo nie wystarcza:

	  * OrderedDataStore — globalny i trwały, ale spóźniony o cykl zapisu
	    i odczytu, a w Studio bez dostępu do API nie ma go wcale,
	  * gracze na tym serwerze — aktualni co do monety, ale tylko oni.

	Pokazując sam DataStore, gracz po sprzedaży połowu przez kilka minut nie
	widzi w rankingu ani siebie, ani kolegi stojącego obok. Dlatego łączymy
	oba: zapisana czołówka plus bieżące wyniki obecnych graczy.

	Czysta matematyka bez typów Robloxa — pilnuje jej `tests/run.luau`.
]]

local Ranking = {}

export type Row = {
	userId: number,
	name: string,
	value: number,
}

--[[
	Łączy zapisaną czołówkę z wynikami graczy na serwerze.

	Ten sam gracz zwykle jest w obu listach. Bierzemy WIĘKSZĄ wartość:
	`totalEarned` rośnie monotonicznie, więc mniejsza liczba to zawsze
	starszy odczyt, nigdy korekta w dół. Nazwę bierzemy z listy `live`,
	bo pochodzi od gracza, który właśnie tu jest, a nie z cache'u.

	Wyniki <= 0 odpadają: gracz, który nic nie zarobił, nie zajmuje miejsca.
	Przy remisie decyduje `userId` — bez tego kolejność zależałaby od
	kolejności iteracji i wiersze przeskakiwałyby przy każdym odświeżeniu.
]]
function Ranking.merge(stored: { Row }, live: { Row }, limit: number): { Row }
	local byUser: { [number]: Row } = {}

	for _, row in stored do
		if row.value > 0 then
			byUser[row.userId] = { userId = row.userId, name = row.name, value = row.value }
		end
	end

	for _, row in live do
		if row.value > 0 then
			local existing = byUser[row.userId]
			byUser[row.userId] = {
				userId = row.userId,
				name = row.name,
				value = if existing then math.max(existing.value, row.value) else row.value,
			}
		end
	end

	local merged: { Row } = {}
	for _, row in byUser do
		table.insert(merged, row)
	end

	table.sort(merged, function(a: Row, b: Row): boolean
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)

	local top: { Row } = {}
	for index = 1, math.min(limit, #merged) do
		top[index] = merged[index]
	end
	return top
end

return table.freeze(Ranking)
