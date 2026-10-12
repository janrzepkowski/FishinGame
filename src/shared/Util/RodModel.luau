--!strict
--[[
	RodModel — geometria wędki jako DANE, nie jako kod budujący.

	=========================================================================
	DLACZEGO DANE
	=========================================================================
	Ten sam kształt jest potrzebny w trzech miejscach:

	  1. w dłoni gracza   — części spawane do Handle (serwer)
	  2. w sklepie        — podgląd 3D w ViewportFrame (klient)
	  3. na pasku         — ikona slotu, też ViewportFrame (klient)

	Gdyby każde miejsce budowało model po swojemu, prędzej czy później
	wędka w sklepie przestałaby wyglądać jak ta w ręce — a to jest dokładnie
	ten rodzaj rozjazdu, którego nikt nie zauważa do premiery.

	Tutaj jest jedna lista brył. Konsument decyduje tylko, czy sklei je
	spawami (Tool) czy zostawi zakotwiczone (podgląd).

	=========================================================================
	ORIENTACJA
	=========================================================================
	Kij biegnie wzdłuż LOKALNEGO -Z, czyli w stronę `LookVector`. To nie jest
	dowolny wybór: Roblox ustawia Handle narzędzia zgodnie z orientacją dłoni,
	a `Tool.GripForward` jest z definicji LookVectorem grip-CFrame'a, czyli
	właśnie -Z. Budowanie kija wzdłuż innej osi oznacza walkę z silnikiem
	przy każdej zmianie chwytu.
]]

local Types = require(script.Parent.Parent.Types)

local RodModel = {}

export type Piece = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
}

local HANDLE_SIZE = Vector3.new(0.38, 0.38, 1.3)
-- Rączka w kolorze gumy do żucia, a nie ciemnego drewna. Cała wędka jest
-- cukierkowa: gra jest dla dzieci i ma wyglądać jak zabawka, nie jak sprzęt.
local GRIP_COLOR = Color3.fromRGB(255, 110, 150)
local METAL = Color3.fromRGB(236, 240, 250)
local KNOB = Color3.fromRGB(255, 214, 64)

-- Walec w Robloxie leży wzdłuż osi X. Obrót o 90° wokół Y kładzie go
-- wzdłuż -Z, czyli wzdłuż kija.
local ALONG_ROD = CFrame.Angles(0, math.rad(90), 0)

--[[ Rozmiar rączki. Handle tworzą konsumenci osobno, bo w Toolu musi
     nazywać się dokładnie "Handle", a w podglądzie to zwykła bryła. ]]
function RodModel.handleSize(): Vector3
	return HANDLE_SIZE
end

function RodModel.handleColor(): Color3
	return GRIP_COLOR
end

--[[
	Wszystkie bryły wędki POZA rączką, w układzie lokalnym rączki.

	Kij to walce, a końcówki to kulki — żadnych ostrych krawędzi. Kanciasty
	klocek w dłoni postaci był jedyną rzeczą w grze, która wyglądała
	„technicznie" zamiast zabawkowo.

	Czubek kija jest w okolicy z = -6.5; tam konsument wiesza Attachment
	o nazwie "Tip", od którego klient rysuje żyłkę.
]]
function RodModel.pieces(definition: Types.RodDefinition): { Piece }
	local pieces: { Piece } = {
		{
			name = "Pommel",
			size = Vector3.new(0.5, 0.5, 0.5),
			cframe = CFrame.new(0, 0, 0.68),
			color = definition.color,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
		},
		{
			name = "Shaft",
			size = Vector3.new(4.2, 0.2, 0.2),
			cframe = CFrame.new(0, 0, -2.75) * ALONG_ROD,
			color = definition.color,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
		},
		{
			name = "TipSection",
			size = Vector3.new(1.7, 0.12, 0.12),
			cframe = CFrame.new(0, 0, -5.7) * ALONG_ROD,
			color = definition.color:Lerp(Color3.new(1, 1, 1), 0.35),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
		},
		{
			-- Kulka na czubku: w ruchu to ona rysuje łuk zamachu i od niej
			-- odchodzi żyłka, więc musi być widoczna z daleka.
			name = "TipBall",
			size = Vector3.new(0.22, 0.22, 0.22),
			cframe = CFrame.new(0, 0, -6.55),
			color = Color3.fromRGB(255, 80, 110),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
		},
		{
			name = "Reel",
			-- Walec leży wzdłuż osi X, więc domyślna orientacja od razu daje
			-- bęben ustawiony w poprzek kija. Nic nie trzeba obracać.
			size = Vector3.new(0.5, 0.82, 0.82),
			cframe = CFrame.new(0, -0.38, -0.95),
			color = METAL,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
		},
		{
			name = "ReelKnob",
			size = Vector3.new(0.26, 0.26, 0.26),
			cframe = CFrame.new(0.34, -0.38, -0.95),
			color = KNOB,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
		},
	}

	-- Przelotki — drobiazg, ale to one sprawiają, że kij czyta się jako
	-- wędka, a nie jako kij. Kulki zamiast płytek: z każdej strony okrągłe.
	for index = 1, 3 do
		table.insert(pieces, {
			name = `Guide{index}`,
			size = Vector3.new(0.24, 0.24, 0.24),
			cframe = CFrame.new(0, -0.1, -1.5 - index * 1.45),
			color = METAL,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
		})
	end

	return pieces
end

--[[ Pozycja czubka w układzie rączki — tam idzie Attachment "Tip". ]]
function RodModel.tipOffset(): Vector3
	return Vector3.new(0, 0, -6.55)
end

--[[
	Zakotwiczony model do podglądu w ViewportFrame.

	Wszystko `Anchored`, bo w ViewportFrame nie ma fizyki — nieukotwione
	części po prostu nie wiedzą, gdzie stać.
]]
function RodModel.toPreview(definition: Types.RodDefinition): Model
	local model = Instance.new("Model")
	model.Name = definition.id

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = HANDLE_SIZE
	handle.CFrame = CFrame.identity
	handle.Color = GRIP_COLOR
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = true
	handle.CanCollide = false
	handle.Parent = model
	model.PrimaryPart = handle

	for _, piece in RodModel.pieces(definition) do
		local part = Instance.new("Part")
		part.Name = piece.name
		part.Size = piece.size
		part.CFrame = piece.cframe
		part.Color = piece.color
		part.Material = piece.material
		part.Anchored = true
		part.CanCollide = false
		if piece.shape then
			part.Shape = piece.shape
		end
		part.Parent = model
	end

	return model
end

return table.freeze(RodModel)
