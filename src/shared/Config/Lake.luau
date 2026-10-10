--!strict
--[[
	Lake — kształt zbiornika: gdzie jest woda i jak głęboka.

	Mieszka w `shared`, bo głębokość liczą OBIE strony:
	  * serwer — bo głębokość podbija szansę na rzadkie ryby,
	  * klient — bo pokazuje ją w HUD-zie i stawia spławik na lustrze wody.
	Dwie implementacje tej samej matematyki rozjechałyby się przy pierwszej
	zmianie układu dna, a gracz zobaczyłby „17 m" nad płycizną.

	`server/World/Lake.luau` buduje z tych liczb teren. To znaczy, że tutaj
	jest JEDNO źródło prawdy o kształcie jeziora — nie da się przesunąć wody
	w terenie, zapominając o walidacji odległości.
]]

local Lake = {}

-- Lustro wody na poziomie gruntu. Teren wokół jest wypełniony do y = 0,
-- więc brzeg schodzi płasko do wody.
Lake.SURFACE_Y = 0

-- Środek jako dwie liczby, nie Vector3 — celowo.
--
-- `Vector3` jest typem Robloxa i istnieje tylko wewnątrz silnika. Gdyby
-- stał tutaj na poziomie modułu, tego pliku nie dałoby się wczytać poza grą,
-- a więc nie dałoby się napisać do niego testów jednostkowych. Cała reszta
-- modułu odwołuje się do `position.X` / `position.Z`, czyli zwykłych pól —
-- test może podać `{ X = 0, Z = -140 }` i nie potrzebuje silnika.
--
-- Ta matematyka raz już wygenerowała bagno zamiast jeziora. Jest warta tego,
-- żeby dało się ją sprawdzić na CI w 50 ms zamiast w Studio po pięciu minutach.
Lake.CENTER_X = 0
Lake.CENTER_Z = -140
-- Połowa boku lustra wody: zbiornik ma 200 x 200 studów.
Lake.HALF_SIZE = 100

--[[
	Półki dna, od brzegu do środka.

	`inset` — ile studów od krawędzi lustra wody zaczyna się dana półka.
	`depth` — głębokość na tej półce.

	Schodkowe dno, nie gładka misa: teren w Robloxie i tak jest wokselowy
	(4 study), więc gładkie zbocze zostałoby zaokrąglone do tych samych
	schodków, tylko po drodze zjadłoby dużo więcej czasu budowania.

	Wszystkie liczby są WIELOKROTNOŚCIAMI 4 — dokładnie tyle ma woksel
	terenu. Przy 2,5 czy 11 silnik i tak zaokrągliłby wypełnienie, a wtedy
	`depthAt` pokazywałoby głębokość, której w terenie nie ma.

	GŁĘBOKOŚCI SĄ DOBRANE POD PŁYWANIE, nie pod estetykę.

	Postać w Robloxie ma ~5 studów, a jej HumanoidRootPart siedzi jakieś 3
	study nad stopami. Pływanie włącza się dopiero, gdy root jest pod wodą —
	czyli przy 4 studach głębokości gracz stoi na dnie z korpusem na granicy
	powierzchni. Wygląda to jak brodzenie w bagnie i dokładnie tak było
	odbierane w testach.

	Dlatego NAJPŁYTSZA półka ma 8 studów: nawet tuż przy brzegu wchodzi się
	do wody, a nie po wodzie. Świadomie rezygnujemy z brodzenia — jezioro
	ma być jeziorem, a nie rozlewiskiem.

	Kolejność od najpłytszej do najgłębszej jest WYMAGANA — polegają na niej
	zarówno `depthAt`, jak i builder terenu.
]]
Lake.SHELVES = table.freeze({
	table.freeze({ inset = 0, depth = 8 }),
	table.freeze({ inset = 12, depth = 16 }),
	table.freeze({ inset = 32, depth = 24 }),
	table.freeze({ inset = 56, depth = 32 }),
})

Lake.MAX_DEPTH = 32

--[[
	Odległość punktu od krawędzi lustra wody, w studach.
	Dodatnia = nad wodą, ujemna = na lądzie.

	Metryka Czebyszewa (`max` z osi), a nie euklidesowa: półki są kwadratowymi
	blokami terenu, więc ich krawędzie też są kwadratami. Liczenie po okręgu
	dałoby w narożnikach głębokość niezgodną z tym, co widać.
]]
function Lake.edgeDistance(position: Vector3): number
	local dx = math.abs(position.X - Lake.CENTER_X)
	local dz = math.abs(position.Z - Lake.CENTER_Z)
	return Lake.HALF_SIZE - math.max(dx, dz)
end

function Lake.isOverWater(position: Vector3): boolean
	return Lake.edgeDistance(position) > 0
end

--[[
	Głębokość wody pod danym punktem. 0 na lądzie.

	Warunek to `edge < 0`, a nie `edge <= 0` — i to nie jest czepialstwo.
	Builder terenu zalewa wodą obrys do `HALF_SIZE` WŁĄCZNIE, więc punkt
	dokładnie na linii brzegowej ma już pod sobą wodę. Przy `<= 0` ta jedna
	linia raportowałaby głębokość 0 mimo wody w terenie i `verifyWater`
	w Ground nie miałby jak tego wyłapać.
]]
function Lake.depthAt(position: Vector3): number
	local edge = Lake.edgeDistance(position)
	if edge < 0 then
		return 0
	end

	local depth = 0
	for _, shelf in Lake.SHELVES do
		if edge >= shelf.inset then
			depth = shelf.depth
		end
	end
	return depth
end

--[[
	Przyciąga punkt do lustra wody, gdy wypadł poza zbiornik.

	Używane do spławika: gracz może stać na brzegu i patrzeć wzdłuż niego,
	a wtedy wyliczony punkt zarzucenia ląduje na trawie. Zamiast odrzucać
	zarzucenie, przesuwamy go na najbliższy sensowny kawałek wody.
]]
function Lake.clampToWater(position: Vector3, margin: number): Vector3
	local limit = Lake.HALF_SIZE - math.max(margin, 0)
	return Vector3.new(
		math.clamp(position.X, Lake.CENTER_X - limit, Lake.CENTER_X + limit),
		Lake.SURFACE_Y,
		math.clamp(position.Z, Lake.CENTER_Z - limit, Lake.CENTER_Z + limit)
	)
end

--[[
	Ułamek 0..1 mówiący, jak głęboko względem najgłębszego miejsca.
	Tego używa ekonomia — surowe metry rozjechałyby balans przy każdej
	zmianie układu dna.
]]
function Lake.depthFactor(position: Vector3): number
	return math.clamp(Lake.depthAt(position) / Lake.MAX_DEPTH, 0, 1)
end

return table.freeze(Lake)
