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

--[[
	OBRYS JEZIORA: zaokrąglona, trójpłatowa zatoka — nie kwadrat.

	Brzeg opisuje promień zależny od kierunku:

	    r(kąt) = BASE_RADIUS * (1 + LOBE_2 * sin(2 kąt) - LOBE_3 * cos(3 kąt))

	Dwie harmoniczne o różnej częstotliwości dają kształt bez żadnej osi
	symetrii: jedną szeroką zatokę, jeden cypel i łagodne wcięcia. Kwadrat
	z prostymi brzegami czytał się jak basen, nie jak jezioro.

	Fazy są dobrane tak, żeby w kierunku placu (kąt = pi/2, czyli +Z)
	oba składniki się ZEROWAŁY. Brzeg od strony placu wypada więc dokładnie
	`BASE_RADIUS` od środka — tam, gdzie zaczynają się ścieżka i pomost.
	Zmiana amplitud przekształca jezioro, ale nie odsuwa go od pomostu.

	Amplitudy muszą zostać małe (suma wyraźnie poniżej 1/3): przy większych
	obrys zaczyna się zapętlać i „odległość od brzegu" traci sens.
]]
Lake.BASE_RADIUS = 100
Lake.LOBE_2 = 0.10
Lake.LOBE_3 = 0.08

-- Kąt, pod którym leży plac i pomost (kierunek +Z od środka jeziora).
Lake.SHORE_ANGLE = math.pi / 2

-- Połowa boku kwadratu, w którym jezioro mieści się w całości. Używają jej
-- builder terenu i diagnostyka do wyznaczenia obszaru roboczego — to NIE
-- jest już rozmiar lustra wody. Musi być >= największego promienia obrysu
-- i być wielokrotnością 4 (woksel terenu).
Lake.HALF_SIZE = 120

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

--[[ Promień obrysu w danym kierunku (kąt jak w `math.atan2(dz, dx)`). ]]
function Lake.radiusAt(angle: number): number
	return Lake.BASE_RADIUS
		* (1 + Lake.LOBE_2 * math.sin(2 * angle) - Lake.LOBE_3 * math.cos(3 * angle))
end

--[[
	Odległość punktu od krawędzi lustra wody, w studach.
	Dodatnia = nad wodą, ujemna = na lądzie.

	Mierzona WZDŁUŻ PROMIENIA od środka jeziora, nie do najbliższego punktu
	brzegu. Dla tak łagodnego obrysu różnica to ułamki studa, a metryka
	promieniowa ma dwie zalety: liczy się w jednej linijce i jest dokładnie
	tą samą liczbą dla terenu, serwera i klienta. Półki dna są dzięki temu
	pomniejszonymi kopiami brzegu, a nie osobnymi figurami.
]]
function Lake.edgeDistance(position: Vector3): number
	local dx = position.X - Lake.CENTER_X
	local dz = position.Z - Lake.CENTER_Z
	return Lake.radiusAt(math.atan2(dz, dx)) - math.sqrt(dx * dx + dz * dz)
end

function Lake.isOverWater(position: Vector3): boolean
	return Lake.edgeDistance(position) > 0
end

--[[
	Głębokość wody pod danym punktem. 0 na lądzie.

	Warunek to `edge < 0`, a nie `edge <= 0`: punkt dokładnie na linii
	brzegowej ma już pod sobą wodę. Builder terenu pyta TĘ funkcję o każdy
	woksel, więc teren i ta definicja nie mogą się rozjechać.
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
	Współrzędne punktu po dociągnięciu do wody, z zapasem `margin` od brzegu.

	Osobno od `clampToWater`, bo operuje na samych liczbach — test może ją
	wywołać bez silnika. Punkt już leżący wystarczająco głęboko nad wodą
	wraca bez zmian; pozostałe przesuwamy wzdłuż promienia do środka.
]]
function Lake.clampXZ(x: number, z: number, margin: number): (number, number)
	local dx = x - Lake.CENTER_X
	local dz = z - Lake.CENTER_Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local limit = math.max(Lake.radiusAt(math.atan2(dz, dx)) - math.max(margin, 0), 0)

	if distance <= limit then
		return x, z
	end

	-- `distance > limit >= 0`, więc dzielenie jest bezpieczne.
	local scale = limit / distance
	return Lake.CENTER_X + dx * scale, Lake.CENTER_Z + dz * scale
end

--[[
	Przyciąga punkt do lustra wody, gdy wypadł poza zbiornik.

	Używane do spławika: gracz może stać na brzegu i patrzeć wzdłuż niego,
	a wtedy wyliczony punkt zarzucenia ląduje na trawie. Zamiast odrzucać
	zarzucenie, przesuwamy go na najbliższy sensowny kawałek wody.
]]
function Lake.clampToWater(position: Vector3, margin: number): Vector3
	local x, z = Lake.clampXZ(position.X, position.Z, margin)
	return Vector3.new(x, Lake.SURFACE_Y, z)
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
