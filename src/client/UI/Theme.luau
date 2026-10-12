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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiScale = require(Shared.Util.UiScale)

local Theme = {}

export type Device = "Phone" | "Tablet" | "Desktop"

-- ---------------------------------------------------------------------------
-- Paleta
-- ---------------------------------------------------------------------------

--[[
	STYL „CUKIERKOWY". Gra jest dla dzieci: panele są nasycone i jasne,
	wszystko ma gruby granatowy kontur jak naklejka, a napisy są białe
	z obrysem. Szarości nie ma tu wcale — szary panel czyta się jak
	arkusz kalkulacyjny, nie jak zabawka.

	Znaczenie kolorów zostaje stałe: żółty to pieniądze, zielony to sukces,
	czerwony to „uwaga / zamknij", kolor rzadkości jest ten sam wszędzie.
]]
Theme.COLOR = table.freeze({
	screen = Color3.fromRGB(18, 24, 64),
	panel = Color3.fromRGB(66, 142, 255),
	-- „Studnie" wewnątrz paneli: wiersze list, kafelki.
	panelAlt = Color3.fromRGB(38, 96, 214),
	panelHigh = Color3.fromRGB(120, 182, 255),
	-- Tor paska postępu i tło nieaktywnych elementów.
	well = Color3.fromRGB(22, 44, 122),
	stroke = Color3.fromRGB(24, 32, 84),

	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(208, 228, 255),
	-- Napis na kolorowym przycisku: biały, bo przycisk dokłada mu obrys.
	textInverse = Color3.fromRGB(255, 255, 255),
	-- Ciemny tekst na białym tle (dymki sprzedawców).
	ink = Color3.fromRGB(34, 40, 92),

	accent = Color3.fromRGB(64, 208, 255),
	accentDeep = Color3.fromRGB(30, 150, 240),
	success = Color3.fromRGB(96, 222, 74),
	warning = Color3.fromRGB(255, 158, 44),
	danger = Color3.fromRGB(255, 82, 98),
	coin = Color3.fromRGB(255, 206, 48),
	water = Color3.fromRGB(40, 200, 226),

	-- Granatowy kontur jak w kreskówce — na WSZYSTKIM, co jest elementem UI.
	outline = Color3.fromRGB(24, 32, 84),
	pink = Color3.fromRGB(255, 104, 182),
	purple = Color3.fromRGB(170, 104, 255),
	orange = Color3.fromRGB(255, 142, 48),
	white = Color3.fromRGB(255, 255, 255),
})

Theme.SPACE = table.freeze({ xs = 4, sm = 8, md = 12, lg = 16, xl = 24 })

--[[
	=========================================================================
	LEWA KRAWĘDŹ — jeden stos, jedno źródło wymiarów
	=========================================================================
	Cały interfejs siedzi przy lewej krawędzi, żeby środek i prawa strona
	ekranu zostały dla rozgrywki. Od góry do dołu:

	    HUD_BAND      monety, torba, wędka, głębokość   (góra)
	    ...wolne...
	    komunikaty    rosną w górę
	    CAST_BAND     pasek łowienia i walki
	    BOTTOM_SAFE   drążek ruchu Robloxa (tylko telefon)

	Te liczby są TUTAJ, a nie w panelach, bo panele muszą się zgadzać co
	do piksela. Gdyby każdy trzymał własną stałą, pierwsza zmiana rozmiaru
	paska walki nasunęłaby na niego komunikaty i nikt by nie wiedział,
	który plik poprawić.

	Alternatywą byłoby czytanie `AbsoluteSize` sąsiada, ale wtedy komunikaty
	podskakiwałyby za każdym razem, gdy pasek zmienia stan — czyli przy
	każdym zarzuceniu.
]]

-- Wysokość HUD-u. STAŁA, nie `AutomaticSize`: wskaźnik głębokości pojawia się
-- i znika przy każdym zarzuceniu, a panel zmieniający wtedy rozmiar skakałby
-- graczowi przed oczami w najgorszym momencie.
Theme.HUD_BAND = table.freeze({ Desktop = 236, Tablet = 236, Phone = 222 })

-- Miejsce zajęte przez pasek łowienia, licząc od dolnej krawędzi stosu.
Theme.CAST_BAND = table.freeze({ Desktop = 170, Tablet = 170, Phone = 162 })

-- Pas oddany systemowi: na telefonie dolny lewy róg to drążek ruchu Robloxa
-- i nie da się go odzyskać. Na desktopie róg jest wolny.
Theme.BOTTOM_SAFE = table.freeze({ Desktop = 0, Tablet = 0, Phone = 186 })

--[[ Odstęp od krawędzi ekranu — mniejszy na telefonie, bo tam każdy
     piksel szerokości jest w cenie. ]]
function Theme.edgeMargin(device: Device): number
	return if device == "Phone" then Theme.SPACE.sm else Theme.SPACE.lg
end

--[[ Dolna krawędź paska łowienia (offset od dołu ekranu). ]]
function Theme.castBottom(device: Device): number
	return Theme.BOTTOM_SAFE[device] + Theme.edgeMargin(device)
end

--[[ Dolna krawędź kolumny komunikatów: nad paskiem łowienia. ]]
function Theme.toastBottom(device: Device): number
	return Theme.castBottom(device) + Theme.CAST_BAND[device] + Theme.SPACE.sm
end
Theme.RADIUS = table.freeze({ sm = 8, md = 14, lg = 22, pill = 999 })
Theme.TEXT = table.freeze({ micro = 12, small = 14, body = 16, lead = 19, title = 24, hero = 34 })

--[[
	Cały interfejs jest w Nunito: zaokrąglona, gruba i — co tu najważniejsze —
	z KOMPLETEM POLSKICH ZNAKÓW.

	Wcześniej nagłówki szły FredokaOne, która w Robloxie nie ma liter
	ę, ą, ś, ć, ł, ż, ź, ń (ó ma, bo należy do podstawowego zestawu
	łacińskiego). Silnik podmieniał brakujące litery czcionką zastępczą
	i „Wędka" wychodziła w dwóch krojach naraz. Sprawdzone na zrzucie
	z każdym kandydatem; nie wracaj do FredokaOne ani LuckiestGuy bez
	tej samej próby.

	To obiekty `Font`, nie `Enum.Font` — Nunito w wadze Heavy nie ma swojego
	enuma. `Theme.create` sam zamienia `Font = <Font>` na `FontFace`.
]]
local NUNITO = "rbxasset://fonts/families/Nunito.json"
Theme.FONT = Font.new(NUNITO, Enum.FontWeight.ExtraBold)
Theme.FONT_BOLD = Font.new(NUNITO, Enum.FontWeight.Heavy)
Theme.FONT_BLACK = Font.new(NUNITO, Enum.FontWeight.Heavy)
-- Liczby w HUD-zie, tytuły okien, banery.
Theme.FONT_DISPLAY = Font.new(NUNITO, Enum.FontWeight.Heavy)

-- Grubość konturu „naklejkowych" elementów (pigułki HUD-u, ikony).
Theme.OUTLINE = 3

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
			elseif key == "Font" and typeof(value) == "Font" then
				-- Patrz komentarz przy `Theme.FONT`.
				target.FontFace = value
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
		Color = color or Theme.COLOR.outline,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}) :: UIStroke
end

--[[
	Obrys LITER — biały napis z granatowym konturem.

	`Contextual` sprawia, że UIStroke obrysowuje tekst, a nie ramkę. Napis
	czyta się wtedy na każdym tle (złota pigułka, woda, niebo) bez dobierania
	koloru tekstu. Tylko dla etykiet BEZ UIStroke na ramce — drugi UIStroke
	na tym samym obiekcie nie zostałby narysowany.
]]
function Theme.outline(label: TextLabel | TextButton, color: Color3?, thickness: number?)
	Theme.create("UIStroke", {
		Name = "TextOutline",
		Color = color or Theme.COLOR.outline,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
end

--[[
	Pionowy gradient „cukierka": jasna góra, ciemniejsza dolna warga.

	UIGradient MNOŻY kolor tła, więc jeden gradient działa na każdym
	kolorze — biel nic nie zmienia, szarość przyciemnia. Ostry skok przy
	0,72 wygląda jak gruba, wypukła krawędź.
]]
function Theme.candyGradient(lip: number?): UIGradient
	local shade = 1 - (lip or 0.22)
	return Theme.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.7, Color3.new(0.93, 0.93, 0.93)),
			ColorSequenceKeypoint.new(0.72, Color3.new(shade, shade, shade)),
			ColorSequenceKeypoint.new(1, Color3.new(shade, shade, shade)),
		}),
	}) :: UIGradient
end

--[[ Okrągła ikona z glifem i granatowym konturem — monety, torba, rybka. ]]
function Theme.icon(
	glyph: string,
	color: Color3,
	size: number,
	props: { [string]: any }?
): TextLabel
	local merged: { [string]: any } = {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = Theme.FONT_DISPLAY,
		TextSize = math.floor(size * 0.55),
		TextColor3 = Color3.new(1, 1, 1),
		-- Obrys liter przez `TextStroke`: ramka ma już UIStroke, a drugi
		-- UIStroke na tym samym obiekcie nie byłby rysowany.
		TextStrokeColor3 = Theme.COLOR.outline,
		TextStrokeTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = glyph,
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end

	return Theme.create(
		"TextLabel",
		merged,
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE)
	) :: TextLabel
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

--[[
	Połysk: jasny pasek przy górnej krawędzi. To on robi z płaskiego
	prostokąta „żelka" — ten sam chwyt, co białe refleksy na przyciskach
	w grach dla dzieci.
]]
function Theme.gloss(radius: number?): Frame
	return Theme.create("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -10, 0.34, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		-- Połysk nie może zjadać kliknięć przycisku, na którym leży.
		Active = false,
		ZIndex = 2,
	}, Theme.create("UICorner", { CornerRadius = UDim.new(0, radius or Theme.RADIUS.sm) })) :: Frame
end

--[[ Panel: nasycone tło, gruby kontur i łagodny gradient w dół. ]]
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
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE + 1),
		Theme.create("UIGradient", {
			Name = "PanelGradient",
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.78, 0.82, 0.95)),
		}),
		...
	) :: Frame
end

--[[ Karta wewnątrz panelu: wiersz listy, kafelek siatki. ]]
function Theme.card(props: { [string]: any }, ...: Instance): Frame
	local merged = merge({
		BackgroundColor3 = Theme.COLOR.panelAlt,
		BorderSizePixel = 0,
	}, props)

	return Theme.create(
		"Frame",
		merged,
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(Theme.COLOR.outline, 2),
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

	local button = Theme.create(
		"TextButton",
		merged,
		Theme.corner(Theme.RADIUS.md),
		Theme.candyGradient(0.2),
		...
	) :: TextButton

	-- Kontur dostaje każdy przycisk, o ile wywołujący nie podał własnego.
	if not button:FindFirstChildOfClass("UIStroke") then
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE).Parent = button
	end
	-- Biały napis z granatowym obrysem czyta się na każdym kolorze
	-- przycisku — nie trzeba dobierać koloru tekstu do tła.
	Theme.outline(button, Theme.COLOR.outline, 2)

	-- Kolor bazowy trzymamy w atrybucie, nie w domknięciu. Gdyby siedział
	-- w zmiennej lokalnej, każda późniejsza zmiana koloru przycisku
	-- (np. „stać cię" -> „nie stać cię") zostałaby cofnięta przy pierwszym
	-- najechaniu myszą, bo handler wracałby do wartości z momentu tworzenia.
	button:SetAttribute("BaseColor", baseColor)

	local function base(): Color3
		local stored = button:GetAttribute("BaseColor")
		return if typeof(stored) == "Color3" then stored else baseColor
	end

	local scale =
		Theme.create("UIScale", { Name = "PopScale", Scale = 1, Parent = button }) :: UIScale

	local function react(target: Color3, size: number, time: number, style: Enum.EasingStyle)
		TweenService:Create(
			button,
			TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = target }
		):Play()
		TweenService
			:Create(scale, TweenInfo.new(time, style, Enum.EasingDirection.Out), { Scale = size })
			:Play()
	end

	-- Przycisk „ugina się" pod palcem i odbija po puszczeniu. Na dotyku
	-- `MouseEnter` nie istnieje, ale Down/Up działają pod palcem tak samo —
	-- reakcja na wciśnięcie jest więc wspólna dla obu wejść.
	button.MouseEnter:Connect(function()
		react(base():Lerp(Color3.new(1, 1, 1), 0.18), 1.05, 0.12, Enum.EasingStyle.Quad)
	end)
	button.MouseLeave:Connect(function()
		react(base(), 1, 0.14, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Down:Connect(function()
		react(base():Lerp(Color3.new(0, 0, 0), 0.16), 0.92, 0.06, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Up:Connect(function()
		react(base(), 1, 0.3, Enum.EasingStyle.Back)
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

--[[ Pasek postępu: ciemny tor z konturem i „żelkowe" wypełnienie.
     Zwraca ramkę wypełnienia, żeby wywołujący mógł ją animować. ]]
function Theme.progress(props: { [string]: any }, fillColor: Color3): (Frame, Frame)
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
	}, Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Theme.candyGradient(0.18)) :: Frame

	local merged = merge({
		BackgroundColor3 = Theme.COLOR.well,
		BorderSizePixel = 0,
	}, props)

	local track = Theme.create(
		"Frame",
		merged,
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, 2),
		fill
	) :: Frame
	return track, fill
end

--[[
	Ikona zamknięcia: dwie obrócone belki zamiast znaku „✕".

	Glif z czcionki wygląda inaczej na każdej platformie i potrafi być
	nieosiowany w pionie. Dwie ramki obrócone o ±45° dają zawsze ten sam,
	równy krzyżyk i nie wymagają wgrywania obrazka.
]]
function Theme.closeIcon(color: Color3?, thickness: number?): Frame
	local tint = color or Theme.COLOR.white
	local bar = thickness or 4

	local function stroke(rotation: number): Frame
		return Theme.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.52, 0, 0, bar),
			Rotation = rotation,
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
		}, Theme.corner(2)) :: Frame
	end

	return Theme.create("Frame", {
		Name = "CloseIcon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, stroke(45), stroke(-45)) :: Frame
end

--[[
	Przycisk zamknięcia z ikoną X. Zwraca gotowy przycisk — wywołujący
	podpina tylko `MouseButton1Click`.
]]
function Theme.closeButton(props: { [string]: any }): TextButton
	local merged = merge({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		-- 38 px: w mniejszy nie da się trafić palcem bez celowania.
		Size = UDim2.fromOffset(38, 38),
		-- Czerwony = zamknij, zawsze i wszędzie.
		BackgroundColor3 = Theme.COLOR.danger,
		Text = "",
	}, props)

	return Theme.button(merged, Theme.closeIcon(Theme.COLOR.white, 5))
end

--[[
	Podgląd 3D modelu w UI.

	Używamy ViewportFrame, a nie obrazka, z jednego powodu: obrazek trzeba
	wyrenderować, wgrać na Roblox i trzymać jego ID w kodzie. Przy czterech
	wędkach to cztery assety do utrzymania, które rozjadą się z modelem
	przy pierwszej zmianie kształtu. ViewportFrame pokazuje DOKŁADNIE ten
	model, który gracz trzyma w ręce — i aktualizuje się sam.

	`model` musi mieć ustawiony PrimaryPart i stać w okolicy początku układu.

	Nazwa `modelPreview`, a nie `viewport`, bo `Theme.viewport()` już istnieje
	i zwraca rozmiar okna gry. Dwie różne rzeczy pod jedną nazwą to pewny błąd
	przy pierwszym autouzupełnieniu.
]]
function Theme.modelPreview(props: { [string]: any }, model: Model, distance: number): ViewportFrame
	local merged = merge({
		BackgroundTransparency = 1,
		-- Lekkie podświetlenie od frontu, żeby model nie był płaską sylwetką.
		Ambient = Color3.fromRGB(214, 218, 230),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
	}, props)

	local frame = Theme.create("ViewportFrame", merged) :: ViewportFrame

	-- Obrót modelu, nie kamery: łatwiej dobrać jeden kąt pod wszystkie
	-- podglądy niż osobną pozycję kamery dla każdego.
	model:PivotTo(CFrame.Angles(0, math.rad(-28), math.rad(14)))
	model.Parent = frame

	local camera = Instance.new("Camera")
	camera.FieldOfView = 36
	-- Patrzymy na ŚRODEK bryły modelu, nie na jego pivot: pivot wędki jest
	-- w rączce, więc kamera wycelowana w niego ucięłaby pół kija.
	local center = model:GetBoundingBox()
	camera.CFrame =
		CFrame.lookAt(center.Position + Vector3.new(0, distance * 0.3, distance), center.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera

	return frame
end

--[[ Kolorowa plakietka — rzadkość ryby, status wędki, klawisz skrótu. ]]
function Theme.badge(text: string, color: Color3, props: { [string]: any }?): Frame
	local label = Theme.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.micro,
		TextColor3 = Theme.COLOR.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
	})
	Theme.outline(label, Theme.COLOR.outline, 1.5)

	local merged = merge({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, props or {})

	return Theme.create(
		"Frame",
		merged,
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, 2),
		Theme.padding(1, 8),
		label
	) :: Frame
end

--[[
	Okno: panel z kolorową belką tytułu i czerwonym przyciskiem zamknięcia
	wystającym z rogu. Zwraca okno i jego WNĘTRZE — treść montujemy we
	wnętrzu, żeby żaden ekran nie musiał znać wysokości belki.

	Każde okno ma własny kolor belki (torba różowa, sklep pomarańczowy,
	dziennik fioletowy): dziecko rozpoznaje okno po kolorze, zanim
	przeczyta tytuł.
]]
function Theme.window(
	props: { [string]: any },
	title: string,
	accent: Color3,
	onClose: () -> ()
): (Frame, Frame)
	local headerHeight = 44

	local titleLabel = Theme.label({
		Name = "Title",
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.fromOffset(Theme.SPACE.lg, 0),
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.title,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Text = title,
	})
	Theme.outline(titleLabel, Theme.COLOR.outline, 2.5)

	local header = Theme.create(
		"Frame",
		{
			Name = "Header",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, headerHeight),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
		},
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE),
		Theme.candyGradient(0.18),
		Theme.gloss(Theme.RADIUS.sm),
		titleLabel
	) :: Frame

	local close = Theme.closeButton({
		Position = UDim2.new(1, 10, 0, -10),
		ZIndex = 5,
	})
	close.MouseButton1Click:Connect(onClose)

	local body = Theme.create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(Theme.SPACE.md, headerHeight + 16),
		Size = UDim2.new(1, -Theme.SPACE.md * 2, 1, -(headerHeight + 16 + Theme.SPACE.md)),
		BackgroundTransparency = 1,
	}) :: Frame

	local window = Theme.panel(props, header, close, body)
	return window, body
end

--[[
	Promienie „jackpota": wachlarz jasnych smug obracający się wokół środka.
	Tło nagrody w każdej grze dla dzieci — mówi „to jest ważne" bez słowa.

	Każda smuga siedzi we własnej ramce obróconej wokół środka: `Rotation`
	obraca element wokół JEGO środka, więc sama smuga zakotwiczona w środku
	wachlarza kręciłaby się w miejscu, zamiast rozchodzić promieniście.
]]
function Theme.sunburst(props: { [string]: any }, color: Color3, rays: number?): Frame
	local count = rays or 12

	local merged = merge({
		Name = "Sunburst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
	}, props)

	local burst = Theme.create("Frame", merged) :: Frame

	for index = 1, count do
		Theme.create(
			"Frame",
			{
				Name = "Ray",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Rotation = (index - 1) * (360 / count),
				Parent = burst,
			},
			Theme.create(
				"Frame",
				{
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1.6 / count, 0.5),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
				},
				-- Smuga gaśnie ku krawędzi wachlarza.
				Theme.create("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.6, 0.5),
						NumberSequenceKeypoint.new(1, 0.3),
					}),
				})
			)
		)
	end

	TweenService:Create(
		burst,
		TweenInfo.new(9, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 }
	):Play()

	return burst
end

-- ---------------------------------------------------------------------------
-- Animacje „soczystości"
-- ---------------------------------------------------------------------------

local function popScale(target: GuiObject): UIScale
	local existing = target:FindFirstChild("PopScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	return Theme.create("UIScale", { Name = "PopScale", Scale = 1, Parent = target }) :: UIScale
end

--[[ Wyskok elementu: z małego do pełnego rozmiaru z przestrzeleniem. ]]
function Theme.pop(target: GuiObject, from: number?, time: number?)
	local scale = popScale(target)
	scale.Scale = from or 0.6
	TweenService:Create(
		scale,
		TweenInfo.new(time or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--[[ Krótkie „bum" istniejącego elementu — np. licznik monet po sprzedaży.
     Osobny UIScale (`PopScale`), a nie zmiana Size: Size przesunąłby
     sąsiadów w UIListLayout przy każdym podskoku. ]]
function Theme.bump(target: GuiObject, strength: number?)
	local scale = popScale(target)
	scale.Scale = 1 + (strength or 0.18)
	TweenService:Create(
		scale,
		TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--[[
	Pokazuje albo chowa okno. Okno „wyskakuje", zamiast po prostu się
	pojawić — każde otwarcie ma być małą nagrodą za kliknięcie.
]]
function Theme.setVisible(target: GuiObject, visible: boolean)
	if visible and not target.Visible then
		target.Visible = true
		Theme.pop(target, 0.82, 0.28)
	elseif not visible then
		target.Visible = false
	end
end

-- ---------------------------------------------------------------------------
-- Responsywność
-- ---------------------------------------------------------------------------

local DESIGN = Vector2.new(UiScale.DESIGN_WIDTH, UiScale.DESIGN_HEIGHT)

local layoutListeners: { (Device, Vector2) -> () } = {}
local currentDevice: Device = "Desktop"
local currentViewport = DESIGN
local rootScale: UIScale? = nil
local rootFrame: Frame? = nil

local function classify(viewport: Vector2): Device
	if viewport.X < 700 then
		return "Phone"
	end
	if viewport.X < 1150 then
		return "Tablet"
	end
	return "Desktop"
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

	local scale, frame = rootScale, rootFrame
	if scale and frame then
		local factor = UiScale.scaleFor(currentViewport.X, currentViewport.Y)
		scale.Scale = factor
		-- UIScale mnoży też rozmiar samego korzenia; bez tej poprawki korzeń
		-- nie pokrywa ekranu przy skali innej niż 1 (patrz UiScale.rootExtent).
		local extent = UiScale.rootExtent(factor)
		frame.Size = UDim2.fromScale(extent, extent)
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
	rootFrame = root

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
