--!strict
--[[
	Hotbar — własny pasek z jednym slotem na wędkę.

	=========================================================================
	DLACZEGO WŁASNY, A NIE WBUDOWANY
	=========================================================================
	Wbudowany pasek Robloxa rysuje slot jako `Tool.TextureId` — czyli obrazek
	wgrany na platformę. Nie mamy takiego obrazka i nie chcemy go mieć:
	każda wędka to byłby osobny asset do wyrenderowania, wgrania i trzymania
	po ID w kodzie, a przy pierwszej zmianie kształtu modelu wszystkie cztery
	rozjechałyby się z rzeczywistością. Bez obrazka wbudowany slot pokazuje
	samą nazwę — i stąd „wędka w ekwipunku nie wygląda jak ta w ręce".

	Nasz slot renderuje `ViewportFrame` z TYM SAMYM modelem, który gracz
	trzyma (patrz `shared/Util/RodModel`). Nie da się ich rozjechać, bo to
	jeden opis geometrii.

	Wyłączamy wbudowany pasek całkowicie. Mamy jedno narzędzie, więc nie
	tracimy niczego poza miejscem na ekranie.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RodModel = require(Shared.Util.RodModel)
local Rods = require(Shared.Config.Rods)
local Types = require(Shared.Types)

local Theme = require(script.Parent.Theme)

local Hotbar = {}

local SLOT = 76
local SLOT_PHONE = 64

local root: Frame? = nil
local slot: TextButton? = nil
local preview: ViewportFrame? = nil
local nameLabel: TextLabel? = nil
local renderedRodId: string? = nil
local action: (() -> ())? = nil

--[[ Wyłącza wbudowany plecak. Przy starcie CoreGui bywa jeszcze nieaktywne,
     więc ponawiamy — inaczej jeden na kilka wejść zostaje z dwoma paskami. ]]
local function disableCoreBackpack()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.2)
	end
	warn("[Hotbar] nie udało się wyłączyć wbudowanego plecaka")
end

--[[ Przerysowuje podgląd tylko przy ZMIANIE wędki. ViewportFrame renderuje
     się co klatkę, więc tworzenie nowego modelu przy każdym snapshocie
     profilu (czyli przy każdej monecie) byłoby czystym marnotrawstwem. ]]
local function renderRod(definition: Types.RodDefinition)
	if renderedRodId == definition.id then
		return
	end
	renderedRodId = definition.id

	local holder = slot
	if not holder then
		return
	end

	if preview then
		preview:Destroy()
	end

	preview = Theme.modelPreview({
		Name = "Preview",
		Size = UDim2.new(1, -8, 1, -20),
		Position = UDim2.fromOffset(4, 2),
		Parent = holder,
	}, RodModel.toPreview(definition), 7.5)

	if nameLabel then
		nameLabel.Text = definition.displayName
	end
end

function Hotbar.mount(parent: Instance)
	task.spawn(disableCoreBackpack)

	local label = Theme.label({
		Name = "RodName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -6, 0, 14),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.micro,
		TextColor3 = Theme.COLOR.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})

	local button = Theme.button({
		Name = "Slot",
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundColor3 = Theme.COLOR.panel,
		Text = "",
	}, Theme.stroke(Theme.COLOR.accent, 2), label)

	-- Kliknięcie w slot robi dokładnie to samo, co klawisz `1`. Logika
	-- siedzi w `FishingController` — tutaj byłaby jej drugą kopią, która
	-- przy pierwszej zmianie zachowałaby się inaczej niż klawisz.
	button.MouseButton1Click:Connect(function()
		local handler = action
		if handler then
			handler()
		end
	end)

	slot = button
	nameLabel = label

	root = Theme.create("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.SPACE.md),
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundTransparency = 1,
		Parent = parent,
	}, button) :: Frame

	-- Slot stoi na DOLE POŚRODKU na każdym urządzeniu. Lewa krawędź należy
	-- do paska łowienia i komunikatów, prawy dolny róg do sterowania
	-- dotykowego — środek jest jedynym miejscem, gdzie nie wchodzi nikomu
	-- w drogę, a przy okazji to tam gracze szukają paska narzędzi odruchowo.
	Theme.onLayout(function(device: Theme.Device)
		local panel = root
		local holder = slot
		if not (panel and holder) then
			return
		end

		local size = if device == "Phone" then SLOT_PHONE else SLOT
		panel.Size = UDim2.fromOffset(size, size)
		holder.Size = UDim2.fromOffset(size, size)
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, -Theme.edgeMargin(device))
	end)
end

--[[ Co robi kliknięcie w slot. Wstrzykiwane, żeby pasek nie musiał znać
     logiki zakładania wędki — ta sama funkcja siedzi pod klawiszem `1`. ]]
function Hotbar.setAction(handler: () -> ())
	action = handler
end

function Hotbar.update(profile: Types.Profile)
	local definition = Rods.find(profile.equippedRod)
	if definition then
		renderRod(definition)
	end
end

--[[ Podświetla slot, gdy wędka jest w ręce. ]]
function Hotbar.setEquipped(equipped: boolean)
	local holder = slot
	if not holder then
		return
	end

	local outline = holder:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = if equipped then Theme.COLOR.accent else Theme.COLOR.stroke
		outline.Thickness = if equipped then 2 else 1
	end
end

return Hotbar
