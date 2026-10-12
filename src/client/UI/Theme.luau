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

--[[
	STYL CUKIERKOWY. Gra jest dla dzieci, a referencją są topowe gry Robloxa
	(symulatory, „pet" UI): jasne karty z grubym granatowym obrysem,
	nasycone kolory, przyciski wyglądające jak wypukłe cukierki i tekst
	z obrysem, który czyta się na każdym tle.

	Ciemny, „profesjonalny" motyw, który był tu wcześniej, wyglądał jak
	narzędzie do pracy. Dziecko nie ma powodu kliknąć w szary prostokąt.

	Klucze palety zostały te same (`panel`, `text`, `accent`...), więc ekrany
	zmieniły wygląd bez przepisywania każdego przypisania koloru. Zmieniło się
	tylko to, że `panel` jest teraz JASNY — dlatego `text` jest ciemny,
	a `textInverse` (napis na kolorowym przycisku) jest biały.
]]
Theme.COLOR = table.freeze({
	screen = Color3.fromRGB(28, 34, 64),
	panel = Color3.fromRGB(255, 255, 255),
	panelAlt = Color3.fromRGB(236, 242, 255),
	panelHigh = Color3.fromRGB(206, 216, 242),
	-- Obrys wszystkiego. Gruby i ciemny jak kontur w kreskówce — to on robi
	-- z płaskich ramek „naklejki".
	stroke = Color3.fromRGB(40, 46, 84),

	text = Color3.fromRGB(40, 46, 84),
	textMuted = Color3.fromRGB(112, 122, 162),
	textInverse = Color3.fromRGB(255, 255, 255),

	accent = Color3.fromRGB(66, 164, 255),
	accentDeep = Color3.fromRGB(34, 112, 220),
	success = Color3.fromRGB(76, 214, 98),
	warning = Color3.fromRGB(255, 176, 32),
	danger = Color3.fromRGB(255, 84, 104),
	coin = Color3.fromRGB(255, 202, 40),
	-- Złoto jako TEKST na białej karcie ginie. Do napisów ciemniejszy odcień,
	-- a jasne `coin` zostaje na tła, pigułki i ikony.
	coinText = Color3.fromRGB(232, 146, 0),
	water = Color3.fromRGB(40, 196, 232),
	pink = Color3.fromRGB(255, 108, 172),
	purple = Color3.fromRGB(156, 100, 255),
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
Theme.CAST_BAND = table.freeze({ Desktop = 162, Tablet = 162, Phone = 148 })

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
-- Duże promienie: nic w tym interfejsie nie ma ostrego rogu.
Theme.RADIUS = table.freeze({ sm = 8, md = 12, lg = 18, pill = 999 })
Theme.TEXT = table.freeze({ micro = 12, small = 14, body = 16, lead = 19, title = 24, hero = 34 })

-- Grubość konturu. Jedna liczba dla wszystkich ram — gdy jedne mają 1 px,
-- a inne 3 px, interfejs wygląda na złożony z dwóch gier.
Theme.OUTLINE = 3

-- FredokaOne: zaokrąglona, gruba, „zabawkowa" — standard gier dla dzieci
-- na Robloxie. Do drobnego tekstu GothamBold, bo Fredoka przy 12 px się zlewa.
Theme.FONT = Enum.Font.GothamBold
Theme.FONT_BOLD = Enum.Font.FredokaOne
Theme.FONT_BLACK = Enum.Font.FredokaOne

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
		Thickness = thickness or Theme.OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}) :: UIStroke
end

--[[
	Obrys LITER — biały napis z granatowym konturem, jak w referencjach.

	`Contextual` sprawia, że UIStroke obrysowuje tekst, a nie ramkę. Dzięki
	temu napis czyta się i na złotej pigułce, i na wodzie, bez dobierania
	koloru tekstu do tła.
]]
function Theme.outline(label: TextLabel | TextButton, color: Color3?, thickness: number?)
	Theme.create("UIStroke", {
		Color = color or Theme.COLOR.stroke,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
end

--[[
	Pionowy gradient „cukierka": jaśniejsza góra, ciemniejsza dolna warga.

	UIGradient MNOŻY kolor tła, więc ten sam gradient działa na każdym
	kolorze przycisku — biały na górze nic nie zmienia, szary na dole
	przyciemnia. Ostry skok przy 0,72 daje wrażenie grubej, wypukłej
	krawędzi, czyli to, co w referencjach wygląda jak przycisk 3D.
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

--[[
	Kolorowy nagłówek okna z dużym, obrysowanym tytułem — „PETS" z referencji.

	Kładziemy go na górnej krawędzi panelu (pozycja 0,0 wewnątrz paddingu
	wywołującego). Kolor nagłówka mówi, CO to za okno, zanim gracz
	przeczyta tytuł: niebieski połów, zielony sklep, fioletowy dziennik.
]]
function Theme.header(title: string, color: Color3, props: { [string]: any }?): Frame
	local label = Theme.label({
		Name = "Title",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.title,
		TextColor3 = Theme.COLOR.textInverse,
		Text = title,
	})
	Theme.outline(label, Theme.COLOR.stroke, 2.5)

	local merged = merge({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, props or {})

	return Theme.create(
		"Frame",
		merged,
		Theme.corner(Theme.RADIUS.md),
		Theme.stroke(),
		Theme.candyGradient(0.18),
		label
	) :: Frame
end

--[[ Okrągła ikona z glifem — monety, torba, rybka w pigułkach HUD-u. ]]
function Theme.icon(
	glyph: string,
	color: Color3,
	size: number,
	props: { [string]: any }?
): TextLabel
	local merged = merge({
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		Font = Theme.FONT_BLACK,
		TextSize = math.floor(size * 0.55),
		TextColor3 = Theme.COLOR.textInverse,
		-- Obrys liter przez `TextStroke`: ikona ma już UIStroke na ramce,
		-- a drugi UIStroke na tym samym obiekcie nie byłby rysowany.
		TextStrokeColor3 = Theme.COLOR.stroke,
		TextStrokeTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = glyph,
	}, props or {})

	local icon = Theme.label(merged)
	Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = icon })
	Theme.create("UIStroke", {
		Color = Theme.COLOR.stroke,
		Thickness = Theme.OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = icon,
	})
	return icon
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
		TextSize = Theme.TEXT.lead,
		TextColor3 = Theme.COLOR.textInverse,
		-- Obrys liter starym `TextStroke`, nie UIStroke: przycisk ma już
		-- UIStroke na ramce, a drugi na tym samym obiekcie byłby pominięty.
		TextStrokeColor3 = Theme.COLOR.stroke,
		TextStrokeTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
	}, props)

	local button = Theme.create(
		"TextButton",
		merged,
		Theme.corner(Theme.RADIUS.md),
		Theme.candyGradient(),
		...
	) :: TextButton

	-- Ramka dokładana tylko, gdy wywołujący nie podał własnej — inaczej
	-- przycisk miałby dwa UIStroke i jeden z nich zostałby zignorowany.
	if not button:FindFirstChildOfClass("UIStroke") then
		Theme.stroke().Parent = button
	end

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

	-- Przycisk „ugina się" pod palcem: UIScale zamiast zmiany Size, bo Size
	-- przesunąłby sąsiadów w UIListLayout przy każdym kliknięciu.
	local squash = Theme.create("UIScale", { Scale = 1, Parent = button }) :: UIScale

	local function scaleTo(target: number, time: number, style: Enum.EasingStyle)
		TweenService
			:Create(
				squash,
				TweenInfo.new(time, style, Enum.EasingDirection.Out),
				{ Scale = target }
			)
			:Play()
	end

	-- Na dotyku `MouseEnter` nie istnieje, ale Down/Up działają pod palcem
	-- tak samo — reakcja na wciśnięcie jest więc wspólna dla obu wejść.
	button.MouseEnter:Connect(function()
		tint(base():Lerp(Color3.new(1, 1, 1), 0.18), 0.12)
		scaleTo(1.06, 0.15, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		tint(base(), 0.14)
		scaleTo(1, 0.15, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Down:Connect(function()
		tint(base():Lerp(Color3.new(0, 0, 0), 0.15), 0.06)
		scaleTo(0.92, 0.06, Enum.EasingStyle.Quad)
	end)
	button.MouseButton1Up:Connect(function()
		tint(base(), 0.12)
		scaleTo(1, 0.25, Enum.EasingStyle.Back)
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
	-- Pigułka z połyskiem: wypełnienie dostaje ten sam gradient co
	-- przyciski, więc pasek wygląda jak napełniająca się rurka cukierka.
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
	}, Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Theme.candyGradient(0.25)) :: Frame

	local merged = merge({
		BackgroundColor3 = Theme.COLOR.panelHigh,
		BorderSizePixel = 0,
	}, props)

	local track = Theme.create(
		"Frame",
		merged,
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.stroke, 2),
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
	local tint = color or Theme.COLOR.textMuted
	local bar = thickness or 2

	local function stroke(rotation: number): Frame
		return Theme.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.52, 0, 0, bar),
			Rotation = rotation,
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
		}, Theme.corner(1)) :: Frame
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
		-- 34 px to minimum, w które da się trafić palcem bez celowania.
		Size = UDim2.fromOffset(40, 40),
		-- Czerwony kwadracik z białym X — jak w każdej grze z referencji.
		-- Dziecko szuka zamknięcia po kolorze, nie po kształcie.
		BackgroundColor3 = Theme.COLOR.danger,
		Text = "",
	}, props)

	return Theme.button(merged, Theme.closeIcon(Theme.COLOR.textInverse, 5))
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
		-- Jasno i bez cieni: cukierkowy model ma być kolorowy, nie dramatyczny.
		Ambient = Color3.fromRGB(205, 205, 215),
		LightColor = Color3.fromRGB(255, 255, 255),
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

--[[ Kolorowa plakietka — rzadkość ryby, status wędki, etykieta głębokości. ]]
function Theme.badge(text: string, color: Color3, props: { [string]: any }?): Frame
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textInverse,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
	})
	Theme.outline(label, Theme.COLOR.stroke, 1.5)

	local merged = merge({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, props or {})

	return Theme.create(
		"Frame",
		merged,
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.stroke, 2),
		Theme.padding(1, 9),
		label
	) :: Frame
end

-- ---------------------------------------------------------------------------
-- Animacje „soczystości"
-- ---------------------------------------------------------------------------

local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChild("PopScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	return Theme.create("UIScale", { Name = "PopScale", Scale = 1, Parent = target }) :: UIScale
end

--[[
	Wyskok elementu: z małego do pełnego rozmiaru z przestrzeleniem.

	Każde otwarcie okna i każda nagroda w grach z referencji „wyskakuje".
	To jest najtańszy pojedynczy efekt, który zamienia statyczny interfejs
	w zabawkę — i dlatego jest w Theme, a nie skopiowany do każdego ekranu.

	Osobny UIScale (`PopScale`), a nie ten z `Theme.button`: inaczej
	najechanie myszą w trakcie wyskoku przerwałoby animację.
]]
function Theme.pop(target: GuiObject, from: number?, time: number?)
	local scale = scaleOf(target)
	scale.Scale = from or 0.6
	TweenService:Create(
		scale,
		TweenInfo.new(time or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--[[ Krótkie „bum" istniejącego elementu — licznik monet po sprzedaży. ]]
function Theme.bump(target: GuiObject, strength: number?)
	local scale = scaleOf(target)
	scale.Scale = 1 + (strength or 0.18)
	TweenService:Create(
		scale,
		TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

--[[
	Przesuwający się połysk po karcie — legendy i epickie w ekwipunku.

	UIGradient z przezroczystością: wąski jasny pas na przezroczystym tle,
	którego `Offset` jedzie w pętli przez kartę. Nakładka jest osobną ramką,
	bo gradient na samej karcie zabarwiłby jej kolor zamiast błyszczeć.
]]
function Theme.shine(target: GuiObject, period: number?)
	local gradient = Theme.create("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
	}) :: UIGradient

	local overlay = Theme.create("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = target,
	}, Theme.corner(Theme.RADIUS.md), gradient) :: Frame

	TweenService:Create(
		gradient,
		TweenInfo.new(
			period or 2.2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			false,
			0.8
		),
		{ Offset = Vector2.new(1, 0) }
	):Play()

	return overlay
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

--[[ Bieżący mnożnik UIScale korzenia. Potrzebny, gdy coś przelicza
     `AbsolutePosition` (piksele ekranu) na `Offset` (piksele projektu) —
     np. monety lecące do licznika. ]]
function Theme.scale(): number
	local scale = rootScale
	return if scale then scale.Scale else 1
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
