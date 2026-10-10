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

local HANDLE_SIZE = Vector3.new(0.34, 0.34, 1.3)
local GRIP_COLOR = Color3.fromRGB(78, 56, 38)
local METAL = Color3.fromRGB(196, 200, 208)
local DARK = Color3.fromRGB(44, 48, 56)

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

	Czubek kija jest w okolicy z = -6.5; tam konsument wiesza Attachment
	o nazwie "Tip", od którego klient rysuje żyłkę.
]]
function RodModel.pieces(definition: Types.RodDefinition): { Piece }
	local pieces: { Piece } = {
		{
			name = "Shaft",
			size = Vector3.new(0.17, 0.17, 4.2),
			cframe = CFrame.new(0, 0, -2.75),
			color = definition.color,
			material = Enum.Material.Wood,
		},
		{
			name = "TipSection",
			size = Vector3.new(0.09, 0.09, 1.7),
			cframe = CFrame.new(0, 0, -5.7),
			color = definition.color,
			material = Enum.Material.Wood,
		},
		{
			name = "Reel",
			-- Walec leży wzdłuż osi X, więc domyślna orientacja od razu daje
			-- bęben ustawiony w poprzek kija. Nic nie trzeba obracać.
			size = Vector3.new(0.5, 0.78, 0.78),
			cframe = CFrame.new(0, -0.36, -0.95),
			color = METAL,
			material = Enum.Material.Metal,
			shape = Enum.PartType.Cylinder,
		},
		{
			name = "ReelKnob",
			size = Vector3.new(0.14, 0.14, 0.34),
			cframe = CFrame.new(0.3, -0.36, -0.95),
			color = DARK,
			material = Enum.Material.SmoothPlastic,
		},
	}

	-- Przelotki — drobiazg, ale to one sprawiają, że kij czyta się jako
	-- wędka, a nie jako kij.
	for index = 1, 3 do
		table.insert(pieces, {
			name = `Guide{index}`,
			size = Vector3.new(0.22, 0.22, 0.07),
			cframe = CFrame.new(0, -0.09, -1.5 - index * 1.45),
			color = Color3.fromRGB(212, 216, 222),
			material = Enum.Material.Metal,
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
	handle.Material = Enum.Material.Wood
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
