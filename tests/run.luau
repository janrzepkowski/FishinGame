--!nonstrict
--[[
	Testy jednostkowe czystej matematyki z `shared/`.

	Uruchomienie:  luau tests/run.luau     (z katalogu repo)

	Co tu jest i dlaczego akurat to:

	* `Lake` — kształt jeziora. Ta matematyka raz już wygenerowała bagno
	  zamiast jeziora i kosztowała trzy nieudane podejścia. Test sprawdza
	  ZGODNOŚĆ Z BUDOWNICZYM TERENU, czyli to, czego w Studio nie widać
	  gołym okiem.
	* `Rng` — losowanie ryb. Przyjmuje generator jako argument, więc da się
	  podstawić atrapę i sprawdzić rozkład deterministycznie.
	* `Format` — teksty dla gracza. Tanie w teście, a literówka w separatorze
	  tysięcy jest widoczna dla każdego gracza w grze.

	Nie testujemy serwisów ani UI: wymagają silnika. Od tego jest ręczny
	przebieg w Studio i checklista w szablonie PR-a.
]]

local t = require("./harness")

local Cast = require("../src/shared/Util/Cast")
local CastPose = require("../src/shared/Util/CastPose")
local Fight = require("../src/shared/Util/Fight")
local Format = require("../src/shared/Util/Format")
local Lake = require("../src/shared/Config/Lake")
local Rng = require("../src/shared/Util/Rng")
local UiScale = require("../src/shared/Util/UiScale")

--[[ Atrapa `Random` — oddaje z góry ustaloną sekwencję. Dzięki temu test
     sprawdza LOGIKĘ wyboru, a nie jakość generatora Robloxa. ]]
local function fakeGenerator(values: { number })
	local index = 0
	return {
		NextNumber = function(): number
			index += 1
			return values[math.min(index, #values)]
		end,
	}
end

local function point(x: number, z: number)
	return { X = x, Y = 0, Z = z }
end

-- ---------------------------------------------------------------------------
t.suite("Lake — kształt jeziora")

t.equal("srodek ma maksymalna glebokosc", Lake.depthAt(point(0, -140)), Lake.MAX_DEPTH)
t.equal("daleko na ladzie jest 0", Lake.depthAt(point(0, 200)), 0)
t.isTrue("srodek jest nad woda", Lake.isOverWater(point(0, -140)))
t.isFalse("plac nie jest nad woda", Lake.isOverWater(point(0, 20)))

--[[
	KSZTAŁT. Jezioro to zaokrąglona, trójpłatowa zatoka opisana promieniem
	zależnym od kierunku. Teren powstaje wprost z `depthAt` (builder pyta tę
	funkcję o każdy woksel), więc nie ma już drugiej definicji, z którą
	trzeba by ją porównywać — sprawdzamy własności samego kształtu.
]]
local shoreZ = Lake.CENTER_Z + Lake.radiusAt(Lake.SHORE_ANGLE)

t.near(
	"brzeg przy placu lezy dokladnie BASE_RADIUS od srodka",
	shoreZ,
	Lake.CENTER_Z + Lake.BASE_RADIUS
)
t.near("punkt na brzegu ma odleglosc zero", Lake.edgeDistance(point(Lake.CENTER_X, shoreZ)), 0)
t.isTrue("tuz za brzegiem jest woda", Lake.isOverWater(point(Lake.CENTER_X, shoreZ - 1)))
t.isFalse("tuz przed brzegiem jest lad", Lake.isOverWater(point(Lake.CENTER_X, shoreZ + 1)))

--[[ Obrys nie może się zapętlać ani wychodzić poza obszar roboczy buildera:
     poza `HALF_SIZE` teren w ogóle nie jest przepisywany na jezioro. ]]
local minRadius, maxRadius = math.huge, 0
for step = 0, 719 do
	local radius = Lake.radiusAt(step / 720 * math.pi * 2)
	minRadius = math.min(minRadius, radius)
	maxRadius = math.max(maxRadius, radius)
end
t.isTrue("jezioro miesci sie w obszarze roboczym buildera", maxRadius <= Lake.HALF_SIZE)
t.isTrue("zadne wciecie nie siega najglebszej polki", minRadius > 56 + 8)
t.isTrue("obrys nie jest kolem", maxRadius - minRadius > 20)

--[[ Dno ma schodzić w dół w stronę środka w KAŻDYM kierunku. Gdyby gdzieś
     płyciało, półki przestałyby być pomniejszonymi kopiami brzegu. ]]
local monotonic = true
for step = 0, 71 do
	local angle = step / 72 * math.pi * 2
	local previous = 0
	for distance = Lake.radiusAt(angle), 0, -2 do
		local depth = Lake.depthAt(
			point(
				Lake.CENTER_X + math.cos(angle) * distance,
				Lake.CENTER_Z + math.sin(angle) * distance
			)
		)
		if depth < previous then
			monotonic = false
		end
		previous = depth
	end
end
t.isTrue("dno poglebia sie ku srodkowi w kazdym kierunku", monotonic)

--[[ Pomost biegnie od brzegu przy placu prosto do środka. Jego koniec
     (64 study od brzegu) musi stać nad najgłębszą półką — inaczej bonus
     za głębokość jest pieszo nieosiągalny. ]]
t.equal(
	"koniec pomostu stoi nad najglebsza woda",
	Lake.depthAt(point(Lake.CENTER_X, shoreZ - 64)),
	Lake.MAX_DEPTH
)

--[[ Dociąganie spławika do wody. ]]
local function clampedEdge(x: number, z: number, margin: number): number
	local cx, cz = Lake.clampXZ(x, z, margin)
	return Lake.edgeDistance(point(cx, cz))
end

local unchangedX, unchangedZ = Lake.clampXZ(10, -140, 4)
t.near("punkt gleboko nad woda zostaje na miejscu (X)", unchangedX, 10)
t.near("punkt gleboko nad woda zostaje na miejscu (Z)", unchangedZ, -140)
t.near("punkt z ladu trafia na wode z zapasem", clampedEdge(0, 40, 4), 4, 1e-6)
t.near("punkt z plazy trafia na wode z zapasem", clampedEdge(150, -100, 4), 4, 1e-6)
t.near("ujemny zapas liczy sie jak zero", clampedEdge(0, 40, -9), 0, 1e-6)

local clampOk = true
for step = 0, 35 do
	local angle = step / 36 * math.pi * 2
	local x = Lake.CENTER_X + math.cos(angle) * 300
	local z = Lake.CENTER_Z + math.sin(angle) * 300
	if math.abs(clampedEdge(x, z, 4) - 4) > 1e-6 then
		clampOk = false
	end
end
t.isTrue("dociaganie dziala z kazdej strony jeziora", clampOk)

--[[ Każda półka musi być głębsza niż ~5 studów, bo tyle ma postać gracza.
     Płytsza woda oznacza chodzenie po dnie — dokładnie efekt bagna. ]]
local shallowest = math.huge
for _, shelf in Lake.SHELVES do
	shallowest = math.min(shallowest, shelf.depth)
end
t.isTrue("najplytsza polka pozwala plywac (>5 studow)", shallowest > 5)

--[[ Półki muszą rosnąć w obie strony — na tej kolejności polega builder. ]]
local ordered = true
for index = 2, #Lake.SHELVES do
	local previous = Lake.SHELVES[index - 1]
	local shelf = Lake.SHELVES[index]
	if shelf.inset <= previous.inset or shelf.depth <= previous.depth then
		ordered = false
	end
end
t.isTrue("polki sa posortowane rosnaco po inset i depth", ordered)

t.near("depthFactor w srodku wynosi 1", Lake.depthFactor(point(0, -140)), 1)
t.near("depthFactor na ladzie wynosi 0", Lake.depthFactor(point(0, 200)), 0)

-- ---------------------------------------------------------------------------
t.suite("Rng — losowanie wazone")

t.equal("zero przy pustych wagach", Rng.weightedIndex(fakeGenerator({ 0.5 }), {}), 0)
t.equal("pomija wpisy o wadze zero", Rng.weightedIndex(fakeGenerator({ 0.99 }), { 0, 0, 5 }), 3)
t.equal(
	"pierwszy wpis przy losowaniu bliskim zeru",
	Rng.weightedIndex(fakeGenerator({ 0 }), { 10, 10, 10 }),
	1
)
t.equal(
	"ostatni wpis przy losowaniu bliskim jedynki",
	Rng.weightedIndex(fakeGenerator({ 0.999999 }), { 10, 10, 10 }),
	3
)

--[[ Krzywa masy: skew > 1 musi ściągać wynik w stronę minimum.
     Gdyby działała odwrotnie, każda ryba byłaby rekordem. ]]
t.near("skew nie wychodzi ponizej minimum", Rng.skewedNumber(fakeGenerator({ 0 }), 2, 10, 2.2), 2)
t.near("skew nie przekracza maksimum", Rng.skewedNumber(fakeGenerator({ 1 }), 2, 10, 2.2), 10)
t.isTrue(
	"skew 2.2 ciagnie srodek w strone minimum",
	Rng.skewedNumber(fakeGenerator({ 0.5 }), 0, 100, 2.2) < 50
)

-- ---------------------------------------------------------------------------
t.suite("Format — teksty dla gracza")

t.equal("male liczby bez separatora", Format.coins(999), "999")
t.equal("tysiace ze spacja", Format.coins(1234), "1 234")
t.equal("miliony z dwoma separatorami", Format.coins(1234567), "1 234 567")
t.equal("zero", Format.coins(0), "0")
t.equal("liczba ujemna zachowuje znak", Format.coins(-1234), "-1 234")

t.equal("masa z przecinkiem dziesietnym", Format.mass(3.4217), "3,42 kg")
t.equal("masa zaokraglona w gore", Format.mass(0.999), "1,00 kg")
t.equal("sekundy z jednym miejscem", Format.seconds(1.26), "1,3 s")
-- Dokumentujemy realne zachowanie, a nie intuicję: `%.1f` zaokrągla
-- dokładne połówki do parzystej, więc 1,25 daje 1,2 — nie 1,3.
-- Ten test istnieje po to, żeby ktoś „nie naprawił" tego przez pomyłkę.
t.equal("dokladna polowka idzie do parzystej", Format.seconds(1.25), "1,2 s")
t.equal("metry bez czesci dziesietnych", Format.meters(11.6), "12 m")

-- ---------------------------------------------------------------------------
t.suite("Fight — hol")

--[[
	Strojenie z GameConfig. Powtórzone tutaj CELOWO: test ma pilnować
	konkretnych liczb, a nie tego, że funkcja zgadza się sama ze sobą.
	Zmiana balansu w configu ma ZŁAMAĆ ten test i zmusić do świadomego
	przeliczenia, czy walka nadal jest wykonalna.
]]
local function params(strength: number, stamina: number, lineStrength: number)
	return {
		strength = strength,
		stamina = stamina,
		lineStrength = lineStrength,
		progressGain = 0.42,
		tensionGain = 0.22,
		surgeTension = 3.0,
		surgeProgress = 0.35,
		slackLoss = 0.12,
		tensionRecovery = 0.5,
	}
end

-- Najsłabsza ryba (płoć) i najsilniejsza (Złota Rybka) na startowej wędce.
local weakest = params(0.55, 0.5, 1.0)
local fiercest = params(1.9, 0.55, 1.0)
local endurance = params(1.05, 1.75, 1.0) -- sum
local tournament = params(1.9, 0.55, 1.8) -- Złota Rybka na wędce turniejowej

local idle = { progress = 0.5, tension = 0.5 }

t.isTrue("holowanie zwieksza postep", Fight.step(idle, weakest, 1, true, false).progress > 0.5)
t.isTrue("holowanie zwieksza napiecie", Fight.step(idle, weakest, 1, true, false).tension > 0.5)
t.isTrue("puszczenie zmniejsza postep", Fight.step(idle, weakest, 1, false, false).progress < 0.5)
t.isTrue("puszczenie zmniejsza napiecie", Fight.step(idle, weakest, 1, false, false).tension < 0.5)

t.isTrue(
	"szarpniecie przyspiesza napiecie",
	Fight.step(idle, weakest, 1, true, true).tension
		> Fight.step(idle, weakest, 1, true, false).tension
)
t.isTrue(
	"szarpniecie spowalnia postep",
	Fight.step(idle, weakest, 1, true, true).progress
		< Fight.step(idle, weakest, 1, true, false).progress
)

t.near(
	"postep nie schodzi ponizej zera",
	Fight.step({ progress = 0, tension = 0 }, weakest, 10, false, false).progress,
	0
)
t.near(
	"napiecie nie schodzi ponizej zera",
	Fight.step({ progress = 0, tension = 0 }, weakest, 10, false, false).tension,
	0
)
t.near(
	"postep nie przekracza jedynki",
	Fight.step({ progress = 1, tension = 0 }, weakest, 10, true, false).progress,
	1
)

--[[
	NAJWAŻNIEJSZE TESTY BALANSU.

	Gra jest grywalna tylko wtedy, gdy okno na reakcję jest dłuższe niż
	ludzki czas reakcji (~0,25 s), a walka krótsza niż cierpliwość gracza.
	Obie granice łatwo przekroczyć jedną zmianą w configu i żadna z nich
	nie objawia się jako błąd — tylko jako „gra jest zła".
]]
t.isTrue(
	"najsilniejsza ryba daje czas na reakcje przy szarpnieciu",
	Fight.timeToSnap(fiercest, true) > 0.45
)
t.isTrue("najslabsza ryba wybacza dlugie holowanie", Fight.timeToSnap(weakest, true) > 2.0)
t.isTrue(
	"mocniejsza zylka realnie wydluza czas do zerwania",
	Fight.timeToSnap(tournament, true) > Fight.timeToSnap(fiercest, true) * 1.5
)
t.isTrue("najdluzsza walka miesci sie w 10 s czystego holu", Fight.minimumDuration(endurance) < 10)
t.isTrue("najkrotsza walka trwa dluzej niz sekunde", Fight.minimumDuration(weakest) > 1)

-- ---------------------------------------------------------------------------
t.suite("UiScale — skala interfejsu")

t.near("rozdzielczosc projektowa daje skale 1", UiScale.scaleFor(1366, 768), 1)
t.near("male okno zatrzymuje sie na dolnym progu", UiScale.scaleFor(1013, 432), UiScale.MIN)
t.near("4K zatrzymuje sie na gornym progu", UiScale.scaleFor(3840, 2160), UiScale.MAX)
t.near("decyduje ciasniejszy wymiar", UiScale.scaleFor(1366 * 2, 768 * 1.1), 1.1)

--[[
	Korzeń UI po przemnożeniu przez UIScale ma pokrywać DOKŁADNIE cały ekran.
	Gdy tak nie jest, wszystko zakotwiczone do prawej lub dolnej krawędzi
	ląduje w złym miejscu — a na 1366x768 tego nie widać, bo skala wynosi 1.
]]
local coversScreen = true
for _, viewport in { { 640, 360 }, { 1013, 432 }, { 1366, 768 }, { 1920, 1080 }, { 3840, 2160 } } do
	local scale = UiScale.scaleFor(viewport[1], viewport[2])
	if math.abs(scale * UiScale.rootExtent(scale) - 1) > 1e-9 then
		coversScreen = false
	end
end
t.isTrue("korzen pokrywa caly ekran przy kazdej skali", coversScreen)

-- ---------------------------------------------------------------------------
t.suite("Cast — rzut z sila")

--[[ Pasek wahadłowy: okres 1,3 s, szczyt w połowie okresu. ]]
t.near("moc startuje od zera", Cast.powerAt(0, 1.3), 0)
t.near("szczyt wypada w polowie okresu", Cast.powerAt(0.65, 1.3), 1)
t.near("po pelnym okresie moc wraca do zera", Cast.powerAt(1.3, 1.3), 0, 1e-6)
t.near("cwierc okresu to polowa mocy", Cast.powerAt(0.325, 1.3), 0.5)
t.near("pasek wraca: trzy czwarte okresu to znow polowa", Cast.powerAt(0.975, 1.3), 0.5)
t.near("drugi okres powtarza pierwszy", Cast.powerAt(1.3 + 0.65, 1.3), 1)
t.isTrue(
	"przetrzymanie nie daje wiecej niz trafienie w szczyt",
	Cast.powerAt(0.9, 1.3) < Cast.powerAt(0.65, 1.3)
)

--[[ Moc przychodzi od klienta. Każda z tych wartości musi dać poprawny
     dystans — NaN w szczególności, bo przechodzi przez `math.clamp`. ]]
t.near("moc ponad zakres jest przycinana", Cast.clampPower(7), 1)
t.near("moc ujemna jest przycinana", Cast.clampPower(-3), 0)
t.near("nieskonczonosc jest przycinana", Cast.clampPower(math.huge), 1)
t.near("NaN staje sie zerem", Cast.clampPower(0 / 0), 0)

t.near("moc zero to rzut minimalny, nie zerowy", Cast.distanceFor(0, 8, 30), 8)
t.near("pelna moc to zasieg wedki", Cast.distanceFor(1, 8, 30), 30)
t.near("polowa mocy to srodek zakresu", Cast.distanceFor(0.5, 8, 30), 19)
t.near("podrobiona moc nie wydluza rzutu", Cast.distanceFor(50, 8, 30), 30)
t.near("NaN nie psuje dystansu", Cast.distanceFor(0 / 0, 8, 30), 8)

--[[
	Sens całej mechaniki: mocny rzut z brzegu sięga głębszej półki niż
	słaby. Jeśli zmiana zasięgu albo półek to zepsuje, rzut znów staje się
	formalnością i ten test ma o tym powiedzieć.
]]
local function shelfFromShore(distance: number): number
	local shore = Lake.CENTER_Z + Lake.radiusAt(Lake.SHORE_ANGLE)
	return Lake.depthAt(point(Lake.CENTER_X, shore - distance))
end
t.isTrue(
	"mocny rzut z brzegu trafia w glebsza wode niz slaby",
	shelfFromShore(Cast.distanceFor(1, 8, 30)) > shelfFromShore(Cast.distanceFor(0, 8, 30))
)
-- 30 i 54 to zasięgi startowej i najlepszej wędki (Config/Rods). Ten plik nie może wczytać
-- Rods (Color3 na poziomie modułu), więc liczby są powtórzone — zmiana
-- zasięgu w configu wymaga świadomego poprawienia ich tutaj.
t.isTrue(
	"najglebsza polka zostaje poza zasiegiem z brzegu nawet najlepsza wedka",
	shelfFromShore(Cast.distanceFor(1, 8, 54)) < Lake.MAX_DEPTH
)
t.isTrue(
	"lepsza wedka siega z brzegu glebiej niz startowa",
	shelfFromShore(Cast.distanceFor(1, 8, 54)) > shelfFromShore(Cast.distanceFor(1, 8, 30))
)

t.isTrue("daleki rzut leci dluzej", Cast.flightTime(30, 30) > Cast.flightTime(8, 30))
t.isTrue("najkrotszy lot jest widoczny golym okiem", Cast.flightTime(0, 30) > 0.3)
t.isTrue("najdluzszy lot nie nudzi", Cast.flightTime(999, 30) < 1.2)

--[[ Skubnięcia: posortowane, rozsunięte, z dala od lądowania i od brania. ]]
local function nibblesValid(biteDelay: number, times: { number }): boolean
	local previous = 0.9 - 0.6
	for _, moment in times do
		if moment < 0.9 or moment > biteDelay - 0.8 or moment - previous < 0.6 - 1e-9 then
			return false
		end
		previous = moment
	end
	return true
end

t.equal("bez losow nie ma skubniec", #Cast.nibbleTimes(5, {}), 0)
t.equal("krotkie czekanie nie miesci zadnego", #Cast.nibbleTimes(1.4, { 0.5, 0.5, 0.5 }), 0)
t.equal("dlugie czekanie miesci trzy", #Cast.nibbleTimes(5, { 0.5, 0.5, 0.5 }), 3)
t.isTrue(
	"srednie czekanie obcina liczbe, zamiast je scisnac",
	#Cast.nibbleTimes(3, { 0.5, 0.5, 0.5 }) < 3
)

local nibblesOk = true
for _, biteDelay in { 1.4, 2, 2.75, 3.3, 4, 5 } do
	for _, roll in { 0, 0.5, 1 } do
		if not nibblesValid(biteDelay, Cast.nibbleTimes(biteDelay, { roll, roll, roll })) then
			nibblesOk = false
		end
	end
end
t.isTrue("skubniecia sa rozsuniete i nie zlewaja sie z braniem", nibblesOk)

-- ---------------------------------------------------------------------------
t.suite("CastPose — poza wedkarza")

--[[ Kolejność zwracanych kątów: bark, łokieć, talia, nadgarstek.
     Bark liczony od ręki zwisającej w dół: pi/2 to ręka w przód, więcej to
     ręka nad barkiem i w tył. Talia ujemna = tułów odchylony w tył. ]]
local holdShoulder = CastPose.casting(5, 0)
local weakShoulder = CastPose.charging(1, 0)
local strongShoulder, _, strongWaist = CastPose.charging(1, 1)
t.isTrue(
	"trzymanie wedki to reka w przodzie, ponizej poziomu",
	holdShoulder > 0.9 and holdShoulder < math.pi / 2
)
t.isTrue("zamach unosi reke nad bark i w tyl", weakShoulder > math.pi / 2)
t.isTrue("mocniejszy rzut to glebszy zamach", strongShoulder > weakShoulder)
t.isTrue("mocny zamach odchyla tulow w tyl", strongWaist < 0)
t.near("zamach zaczyna sie od reki w dol", (CastPose.charging(0, 1)), 0)

--[[ Przejście zamach -> wymach nie może szarpnąć: w chwili zero wymach
     stoi dokładnie w skrajnej pozie zamachu dla tej samej mocy. ]]
local continuous = true
for _, power in { 0, 0.3, 0.7, 1 } do
	local a1, a2, a3, a4 = CastPose.charging(10, power)
	local b1, b2, b3, b4 = CastPose.casting(0, power)
	if
		math.abs(a1 - b1) > 1e-9
		or math.abs(a2 - b2) > 1e-9
		or math.abs(a3 - b3) > 1e-9
		or math.abs(a4 - b4) > 1e-9
	then
		continuous = false
	end
end
t.isTrue("wymach zaczyna sie tam, gdzie konczy sie zamach", continuous)

local releaseShoulder = CastPose.casting(CastPose.RELEASE_DELAY, 1)
local windupShoulder = CastPose.casting(0, 1)
local peakShoulder, _, peakWaist = CastPose.casting(0.14, 1)
t.isTrue("w chwili puszczenia zylki reka juz idzie w przod", releaseShoulder < windupShoulder)
t.isTrue("puszczenie wypada przed koncem wymachu", releaseShoulder > peakShoulder)
t.isTrue("wymach konczy sie reka ponizej pozy trzymania", peakShoulder < holdShoulder)
t.isTrue("wymach pochyla tulow za rzutem", peakWaist > 0)
t.isTrue(
	"mocniejszy rzut to nizszy wymach",
	(CastPose.casting(0.14, 1)) < (CastPose.casting(0.14, 0))
)
t.near(
	"po wymachu poza uspokaja sie niezaleznie od mocy",
	(CastPose.casting(5, 1)),
	(CastPose.casting(5, 0))
)

local slackShoulder, _, slackWaist = CastPose.fighting(0, 0, false)
local tightShoulder, _, tightWaist = CastPose.fighting(0, 1, false)
t.isTrue("napieta zylka podnosi wedke", tightShoulder > slackShoulder)
t.isTrue("napieta zylka odchyla tulow", tightWaist < slackWaist)
t.isTrue("najmocniejszy hol nie przekracza zamachu", tightShoulder < weakShoulder)
t.near("hol bez napiecia to spokojne trzymanie", slackShoulder, holdShoulder)

--[[ Żaden staw nie może wyjść poza zakres, w którym ręka wygląda jak ręka.
     Sprawdzamy całą przestrzeń wejść, łącznie z wartościami spoza 0..1. ]]
local sane = true
local function check(a: number, b: number, c: number, d: number)
	for _, angle in { a, b, c, d } do
		if angle ~= angle or angle < -1 or angle > 3 then
			sane = false
		end
	end
end
for step = 0, 40 do
	local time = step * 0.05
	for _, value in { -1, 0, 0.5, 1, 9 } do
		check(CastPose.charging(time, value))
		check(CastPose.casting(time, value))
		check(CastPose.fighting(time, value, true))
	end
	check(CastPose.biting(time))
end
t.isTrue("katy stawow zostaja w rozsadnym zakresie", sane)

t.finish()
