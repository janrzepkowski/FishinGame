--!nonstrict
--[[
	harness — minimalny runner testów.

	Dlaczego własny, a nie TestEZ: TestEZ jest paczką Wally i wymaga Robloxa
	do uruchomienia (albo `run-in-roblox` i całego Studio w CI). Tutaj
	testujemy CZYSTĄ MATEMATYKĘ z `shared/`, która nie potrzebuje silnika —
	uruchamia ją samo `luau` w 50 ms. Sześćdziesiąt linijek runnera jest
	tańsze niż zależność, która ciągnie za sobą emulację Studio na CI.

	OGRANICZENIE, które trzeba znać: testujemy tylko moduły, które nie
	dotykają typów Robloxa NA POZIOMIE MODUŁU. Funkcje mogą wewnątrz używać
	`Vector3` — wystarczy ich nie wołać albo podać zwykłą tabelę z polami
	X/Y/Z. Dlatego `Lake.CENTER_X` jest liczbą, a nie Vector3.
]]

local harness = {}

local failures = {}
local passed = 0
local currentSuite = "?"

function harness.suite(name: string)
	currentSuite = name
	print(`\n— {name}`)
end

local function fail(label: string, detail: string)
	table.insert(failures, `[{currentSuite}] {label}: {detail}`)
	print(`  FAIL  {label}`)
	print(`        {detail}`)
end

local function pass(label: string)
	passed += 1
	print(`  ok    {label}`)
end

function harness.equal(label: string, actual: any, expected: any)
	if actual == expected then
		pass(label)
	else
		fail(label, `oczekiwano {tostring(expected)}, jest {tostring(actual)}`)
	end
end

--[[ Porównanie liczb z tolerancją — do wszystkiego, co przechodzi
     przez arytmetykę zmiennoprzecinkową. ]]
function harness.near(label: string, actual: number, expected: number, tolerance: number?)
	local limit = tolerance or 1e-6
	if math.abs(actual - expected) <= limit then
		pass(label)
	else
		fail(label, `oczekiwano {expected} (±{limit}), jest {actual}`)
	end
end

function harness.isTrue(label: string, value: boolean)
	if value then
		pass(label)
	else
		fail(label, "oczekiwano true")
	end
end

function harness.isFalse(label: string, value: boolean)
	if not value then
		pass(label)
	else
		fail(label, "oczekiwano false")
	end
end

--[[
	Kończy przebieg. Przy błędach rzuca, bo `luau` kończy się wtedy kodem
	niezerowym i CI to widzi.

	`os.exit` tu nie istnieje — sandbox CLI go nie wystawia. Gdybyśmy na nim
	polegali, runner wywaliłby się na samym końcu i czerwone testy
	zgłaszałyby błąd „attempt to call a nil value" zamiast swojej treści.
]]
function harness.finish()
	print(`\n{passed} przeszlo, {#failures} nie przeszlo`)

	if #failures == 0 then
		return
	end

	print("")
	for _, message in failures do
		print(`  {message}`)
	end

	-- Poziom 0: bez prefiksu z numerem linii runnera, bo interesuje nas
	-- treść niezaliczonych testów, a nie miejsce w harnessie.
	error(`testy nie przeszly: {#failures}`, 0)
end

return harness
