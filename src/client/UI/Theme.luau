--!strict
--[[
	Theme — system projektowy UI: paleta, skale, komponenty i responsywność.

	Trzy rzeczy, które ten plik wymusza na całym interfejsie:

	1. JEDNA PALETA. Kolor ma znaczenie, nie jest dekoracją — złoty to zawsze
	   pieniądze, zielony to zawsze sukces, kolor rzadkości jest ten sam
	   w ekwipunku, w pasku łowienia i w toaście. Gracz uczy się tego raz.

	2. SKALE ZAMIAST DOWOLNYCH LICZB. Odstępy z `SPACE`, zaokrąglenia
	   z `RADIUS`, rozmiary tekstu z `TEXT`. Gdy każdy ekran dobiera własne
	   13, 14 i 15 pikseli, interfejs wygląda na poskładany z kawałków,
	   choć nikt nie umie wskazać dlaczego.

	3. JEDEN UIScale NA WSZYSTKO. Responsywność nie polega na przeliczaniu
	   każdego panelu z osobna, tylko na jednym mnożniku na korzeniu plus
	   wariantach układu dla telefonu. Panele pozycjonujemy skalą (0..1),
	   a wymiary podajemy w pikselach — wtedy UIScale skaluje rozmiary,
	   a kotwice i tak trzymają się krawędzi ekranu.

	Dzieci przekazujemy jako VARARGS, nie tablicę. Tablice w Luau są
	niezmiennicze: literał `{ Theme.corner(8), label }` dostaje typ elementu
	z pierwszego wpisu (`{UICorner}`) i analiza wywala resztę. Varargs są
	sprawdzane element po elemencie i działają bez rzutowań.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = {}

export type Device = "Phone" | "Tablet" | "Desktop"

-- ---------------------------------------------------------------------------
-- Paleta
-- ---------------------------------------------------------------------------

Theme.COLOR = table.freeze({
	screen = Color3.fromRGB(17, 21, 28),
	panel = Color3.fromRGB(27, 32, 41),
	panelAlt = Color3.fromRGB(37, 44, 56),
	panelHigh = Color3.fromRGB(48, 57, 71),
	stroke = Color3.fromRGB(57, 66, 79),

	text = Color3.fromRGB(242, 245, 249),
	textMuted = Color3.fromRGB(150, 161, 178),
	textInverse = Color3.fromRGB(14, 18, 24),

	accent = Color3.fromRGB(79, 168, 255),
	accentDeep = Color3.fromRGB(47, 127, 212),
	success = Color3.fromRGB(95, 208, 138),
	warning = Color3.fromRGB(245, 183, 68),
	danger = Color3.fromRGB(240, 101, 110),
	coin = Color3.fromRGB(255, 206, 85),
	water = Color3.fromRGB(47, 168, 200),
})

Theme.SPACE = table.freeze({ xs = 4, sm = 8, md = 12, lg = 16, xl = 24 })

--[[
	Pionowy pas zarezerwowany w lewym górnym rogu na HUD.

	Istnieje, żeby HUD i toasty NIE MUSIAŁY o sobie wiedzieć. HUD wypełnia
	ten pas, toasty zaczynają się pod nim. Gdyby zamiast tego toasty czytały
	`AbsoluteSize` HUD-u, podskakiwałyby za każdym razem, gdy pojawia się
	wskaźnik głębokości — czyli przy każdym zarzuceniu.

	Dlatego też HUD ma STAŁĄ wysokość, a nie `AutomaticSize`: przewidywalny
	układ jest wart pustego paru pikseli, gdy wskaźnik głębokości jest ukryty.
]]
Theme.HUD_BAND = table.freeze({ Desktop = 196, Tablet = 196, Phone = 158 })
Theme.RADIUS = table.freeze({ sm = 6, md = 10, lg = 16, pill = 999 })
Theme.TEXT = table.freeze({ micro = 11, small = 13, body = 15, lead = 17, title = 21, hero = 30 })

Theme.FONT = Enum.Font.GothamMedium
Theme.FONT_BOLD = Enum.Font.GothamBold
Theme.FONT_BLACK = Enum.Font.GothamBlack

-- ---------------------------------------------------------------------------
-- Prymitywy
-- ---------------------------------------------------------------------------

--[[
	Instance.new z właściwościami i dziećmi w jednym wywołaniu.

	`Parent` przypisujemy NA KOŃCU, po właściwościach i dzieciach: element
	trafia na ekran gotowy, zamiast przechodzić przez stan pośredni, który
	widać jako mignięcie przy wejściu do gry.
]]
function Theme.create(className: string, props: { [string]: any }?, ...: Instance): Instance
	local instance = Instance.new(className)
	local target: any = instance
	local parent: Instance? = nil

	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				target[key] = value
			end
		end
	end

	for _, child in { ... } do
		child.Parent = instance
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

function Theme.corner(radius: number): UICorner
	return Theme.create("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
end

function Theme.stroke(color: Color3?, thickness: number?): UIStroke
	return Theme.create("UIStroke", {
		Color = color or Theme.COLOR.stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
end

function Theme.padding(pixels: number, horizontal: number?): UIPadding
	local vertical = UDim.new(0, pixels)
	local side = UDim.new(0, horizontal or pixels)
	return Theme.create("UIPadding", {
		PaddingTop = vertical,
		PaddingBottom = vertical,
		PaddingLeft = side,
		PaddingRight = side,
	}) :: UIPadding
end

function Theme.list(gap: number, direction: Enum.FillDirection?): UIListLayout
	return Theme.create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
	}) :: UIListLayout
end

-- ---------------------------------------------------------------------------
-- Komponenty
-- ---------------------------------------------------------------------------

local function merge(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local result = table.clone(base)
	for key, value in extra do
		result[key] = value
	end
	return result
end

function Theme.panel(props: { [string]: any }, ...: Instance): Frame
	local merged = merge({
		BackgroundColor3 = Theme.COLOR.panel,
		BorderSizePixel = 0,
	}, props)

	-- `...` musi być ostatnie: rozwinięcie varargs w środku listy argumentów
	-- urwałoby się do jednej wartości.
	return Theme.create(
			"Frame",
			merged,
			Theme.corner(Theme.RADIUS.lg),
			Theme.stroke(),
			...
		) :: Frame
end

function Theme.label(props: { [string]: any }): TextLabel
	local merged = merge({
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextColor3 = Theme.COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.TEXT.body,
		RichText = true,
	}, props)

	return Theme.create("TextLabel", merged) :: TextLabel
end

--[[
	Przycisk z reakcją na najechanie i wciśnięcie.

	Informacja zwrotna na hover/press to nie ozdoba: bez niej gracz nie wie,
	czy kliknięcie w ogóle zostało przyjęte, i klika drugi raz. Na dotyku
	hover nie istnieje, ale `MouseButton1Down` działa tak samo pod palcem.
]]
function Theme.button(props: { [string]: any }, ...: Instance): TextButton
	local baseColor: Color3 = props.BackgroundColor3 or Theme.COLOR.accent

	local merged = merge({
		BackgroundColor3 = baseColor,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.body,
		TextColor3 = Theme.COLOR.textInverse,
		AutoButtonColor = false,
		Text = "",
	}, props)

	local button =
		Theme.create("TextButton", merged, Theme.corner(Theme.RADIUS.md), ...) :: TextButton

	-- Kolor bazowy trzymamy w atrybucie, nie w domknięciu. Gdyby siedział
	-- w zmiennej lokalnej, każda późniejsza zmiana koloru przycisku
	-- (np. „stać cię" -> „nie stać cię") zostałaby cofnięta przy pierwszym
	-- najechaniu myszą, bo handler wracałby do wartości z momentu tworzenia.
	button:SetAttribute("BaseColor", baseColor)

	local function base(): Color3
		local stored = button:GetAttribute("BaseColor")
		return if typeof(stored) == "Color3" then stored else baseColor
	end

	local function tint(target: Color3, time: number)
		TweenService:Create(
			button,
			TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = target }
		):Play()
	end

	-- Na dotyku `MouseEnter` nie istnieje, ale Down/Up działają pod palcem
	-- tak samo — reakcja na wciśnięcie jest więc wspólna dla obu wejść.
	button.MouseEnter:Connect(function()
		tint(base():Lerp(Color3.new(1, 1, 1), 0.16), 0.12)
	end)
	button.MouseLeave:Connect(function()
		tint(base(), 0.14)
	end)
	button.MouseButton1Down:Connect(function()
		tint(base():Lerp(Color3.new(0, 0, 0), 0.18), 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		tint(base(), 0.12)
	end)

	return button
end

--[[
	Zmienia kolor bazowy przycisku. Używaj tego zamiast ustawiać
	`BackgroundColor3` wprost — inaczej hover cofnie zmianę.
]]
function Theme.setButtonColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

--[[ Pasek postępu. Zwraca ramkę wypełnienia, żeby wywołujący mógł ją animować. ]]
function Theme.progress(props: { [string]: any }, fillColor: Color3): (Frame, Frame)
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
	}, Theme.corner(Theme.RADIUS.sm)) :: Frame

	local merged = merge({
		BackgroundColor3 = Theme.COLOR.panelAlt,
		BorderSizePixel = 0,
	}, props)

	local track = Theme.create("Frame", merged, Theme.corner(Theme.RADIUS.sm), fill) :: Frame
	return track, fill
end

--[[ Kolorowa plakietka — rzadkość ryby, status wędki, etykieta głębokości. ]]
function Theme.badge(text: string, color: Color3, props: { [string]: any }?): Frame
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.micro,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
	})

	local merged = merge({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, props or {})

	return Theme.create(
		"Frame",
		merged,
		Theme.corner(Theme.RADIUS.sm),
		Theme.stroke(color, 1),
		Theme.padding(2, 8),
		label
	) :: Frame
end

-- ---------------------------------------------------------------------------
-- Responsywność
-- ---------------------------------------------------------------------------

-- Rozdzielczość, w której projektowaliśmy odstępy i rozmiary tekstu.
local DESIGN = Vector2.new(1366, 768)

local layoutListeners: { (Device, Vector2) -> () } = {}
local currentDevice: Device = "Desktop"
local currentViewport = DESIGN
local rootScale: UIScale? = nil

local function classify(viewport: Vector2): Device
	if viewport.X < 700 then
		return "Phone"
	end
	if viewport.X < 1150 then
		return "Tablet"
	end
	return "Desktop"
end

--[[
	Mnożnik interfejsu dla danego viewportu.

	Dolne ograniczenie (0.82) jest WAŻNIEJSZE niż wierność projektowi:
	na telefonie proporcjonalne pomniejszenie dałoby przyciski poniżej
	progu trafialności palcem. Lepiej, żeby UI zajmowało tam więcej ekranu.
	Górne (1.3) chroni przed olbrzymimi panelami na 4K.
]]
local function scaleFor(viewport: Vector2): number
	local raw = math.min(viewport.X / DESIGN.X, viewport.Y / DESIGN.Y)
	return math.clamp(raw, 0.82, 1.3)
end

function Theme.device(): Device
	return currentDevice
end

function Theme.viewport(): Vector2
	return currentViewport
end

function Theme.isPhone(): boolean
	return currentDevice == "Phone"
end

--[[ Czy pokazywać sterowanie dotykowe. Klawiatura wygrywa: na tablecie
     z podpiętą klawiaturą gracz woli klawisze. ]]
function Theme.isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function refresh()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	currentViewport = camera.ViewportSize
	currentDevice = classify(currentViewport)

	local scale = rootScale
	if scale then
		scale.Scale = scaleFor(currentViewport)
	end

	for _, listener in table.clone(layoutListeners) do
		-- Jeden wywrócony ekran nie może zabrać ze sobą pozostałych ani
		-- zablokować przeliczenia skali.
		xpcall(listener, function(err)
			warn(`[Theme] listener układu rzucił błędem: {tostring(err)}`)
		end, currentDevice, currentViewport)
	end
end

--[[
	Tworzy korzeń interfejsu: przezroczystą ramkę na cały ekran z jednym
	UIScale. Wszystkie panele montujemy w niej, nie wprost w ScreenGui.
]]
function Theme.mountRoot(screen: ScreenGui): Frame
	local scale = Theme.create("UIScale", { Scale = 1 }) :: UIScale
	rootScale = scale

	local root = Theme.create("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screen,
	}, scale) :: Frame

	local function bindCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
		refresh()
	end

	-- CurrentCamera potrafi się podmienić (np. przy przejściu do trybu
	-- widza), a wtedy stare połączenie przestaje cokolwiek raportować.
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	return root
end

--[[
	Rejestruje reakcję na zmianę układu. Callback leci OD RAZU, więc ekran
	nie musi osobno obsługiwać „jeszcze nie znam rozmiaru okna".
]]
function Theme.onLayout(listener: (Device, Vector2) -> ())
	table.insert(layoutListeners, listener)
	listener(currentDevice, currentViewport)
end

return Theme
