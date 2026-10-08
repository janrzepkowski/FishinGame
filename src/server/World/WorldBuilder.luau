--!strict
--[[
	WorldBuilder — składa mapę z modułów i wystawia punkty zaczepienia.

	Ten plik nie buduje niczego sam. Ustala kolejność i oddaje serwisom to,
	czego potrzebują. Każdy kawałek świata ma własny plik:

	  Ground   — teren: ląd, plaża, misa jeziora z prawdziwą wodą Robloxa
	  Dock     — pomost nad głęboką wodę
	  Market   — plac, spawn, skup ryb, sklep wędkarski
	  Scenery  — drzewa, kamienie, trzciny

	Dlaczego mapa jest w kodzie, a nie plikiem .rbxl:
	plik miejsca jest binarny, więc git go nie zmerguje. Gdy dwie osoby
	zmienią mapę w Studio, jedna odtwarza swoją pracę ręcznie. Kod merguje
	się jak tekst i widać go na PR-ze.

	Gdy dojdzie do prawdziwego level designu:
	  1. zbuduj mapę w Studio,
	  2. File -> Export Selection -> assets/Map.rbxm,
	  3. w default.project.json, pod "Workspace": "Map": { "$path": "assets/Map.rbxm" },
	  4. ten moduł zostaw do wystawiania punktów zaczepienia — niech szuka
	     ich po nazwie w zaimportowanym modelu.
	Plik .rbxm ma jednego właściciela i zmienia się rzadko, więc jest OK w repo.

	UWAGA: geometrii jeziora NIE ma tutaj. Siedzi w `shared/Config/Lake`,
	bo liczą z niej obie strony — serwer bonus za głębokość, klient pozycję
	spławika i wskaźnik w HUD-zie.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LakeConfig = require(ReplicatedStorage.Shared.Config.Lake)

local Dock = require(script.Parent.Dock)
local Ground = require(script.Parent.Ground)
local Market = require(script.Parent.Market)
local Scenery = require(script.Parent.Scenery)

local WorldBuilder = {}

local CONTAINER_NAME = "World"

-- Resztki po szablonie miejsca, które Rojo zostawia w spokoju, bo nie ma ich
-- w default.project.json.
local TEMPLATE_LEFTOVERS = { "Baseplate", "SpawnLocation" }

local fishBuyer: BasePart? = nil
local rodShop: BasePart? = nil

--[[
	Usuwa Baseplate i spawn z szablonu Studio.

	To nie jest sprzątanie dla porządku, tylko naprawa konkretnego, bardzo
	mylącego błędu. Rojo synchronizuje wyłącznie gałęzie opisane w projekcie,
	więc gdy ktoś podłączy się do świeżego szablonu „Baseplate", oryginalna
	płyta ZOSTAJE. Jej górna powierzchnia jest na y = 0 — dokładnie na
	poziomie lustra wody. Gracz chodzi wtedy po niewidzialnej podłodze nad
	całym jeziorem i wygląda to tak, jakby woda była trawą.

	Drugi spawn z szablonu jest łagodniejszy, ale równie upierdliwy: Roblox
	losuje między nim a naszym, więc co drugie wejście ląduje się gdzie indziej.

	Ruszamy tylko to, co leży bezpośrednio w Workspace i nie należy do nas.
]]
local function removeTemplateLeftovers()
	for _, name in TEMPLATE_LEFTOVERS do
		local leftover = Workspace:FindFirstChild(name)
		if leftover then
			leftover:Destroy()
			warn(
				`[WorldBuilder] usunięto "{name}" z szablonu Studio. `
					.. "Mapę buduje kod — zawartość szablonu kolidowała z terenem."
			)
		end
	end
end

--[[
	Szuka czegokolwiek, po czym dałoby się chodzić nad taflą jeziora.

	Objaw „woda jest, ale chodzę po niej" prawie nigdy nie wynika z samej
	wody — pod stopami leży jakaś kolidująca część na poziomie y = 0.
	Najczęściej Baseplate z szablonu, ale równie dobrze może to być czyjaś
	platforma testowa albo model wklejony ręcznie w Studio, którego Rojo
	nie widzi i nie usunie.

	Zamiast kasować cudze rzeczy w ciemno, wypisujemy pełne ścieżki.
	Autor zmiany od razu wie, co usunąć, i nie traci wieczoru na zgadywanie.
]]
local function reportFloorsOverWater(ours: Instance)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Pomijamy własny świat i Terrain: woda JEST terenem, więc bez tego
	-- wyłapalibyśmy sami siebie.
	params.FilterDescendantsInstances = { ours, Workspace.Terrain }
	params.MaxParts = 24

	local probe = CFrame.new(LakeConfig.CENTER.X, LakeConfig.SURFACE_Y, LakeConfig.CENTER.Z)
	local size = Vector3.new(LakeConfig.HALF_SIZE * 2, 3, LakeConfig.HALF_SIZE * 2)

	for _, part in Workspace:GetPartBoundsInBox(probe, size, params) do
		if part.CanCollide then
			warn(
				`[WorldBuilder] "{part:GetFullName()}" koliduje na poziomie lustra wody `
					.. "— gracz będzie po niej chodził. Usuń tę część z Workspace."
			)
		end
	end
end

--[[
	Buduje świat od zera. Idempotentne: kasuje poprzedni i czyści teren,
	więc Rojo może wgrać zmianę w którymkolwiek pliku World/ bez restartu
	serwera gry.
]]
function WorldBuilder.build()
	local existing = Workspace:FindFirstChild(CONTAINER_NAME)
	if existing then
		existing:Destroy()
	end

	removeTemplateLeftovers()

	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = Workspace

	-- Teren pierwszy: reszta stoi na nim i opiera się o poziom lustra wody.
	Ground.build()

	local stands = Market.build(container)
	fishBuyer = stands.fishBuyer
	rodShop = stands.rodShop

	Dock.build(container)
	Scenery.build(container)

	reportFloorsOverWater(container)
end

-- ---------------------------------------------------------------------------
-- Punkty zaczepienia dla serwisów
-- ---------------------------------------------------------------------------
-- Zwracają `nil` przed `build()`. Wywołujący MUSI to obsłużyć — serwis nie ma
-- prawa wywalić serwera dlatego, że ktoś pozmieniał kolejność startu.

function WorldBuilder.getFishBuyer(): BasePart?
	return fishBuyer
end

function WorldBuilder.getRodShop(): BasePart?
	return rodShop
end

--[[ Koniec pomostu — najgłębsza woda w zasięgu pieszego. ]]
function WorldBuilder.deepSpot(): Vector3
	return Dock.deepSpot()
end

return WorldBuilder
