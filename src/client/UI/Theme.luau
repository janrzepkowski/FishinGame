--!strict
--[[
	Theme — kolory, czcionki i skrót do budowania instancji UI.

	Dwa powody, dla których to jest osobny moduł:
	  * zmiana palety to zmiana w jednym pliku, a nie szukanie
	    `Color3.fromRGB(26, 31, 40)` po siedmiu ekranach,
	  * `Theme.create` wycina z UI większość powtarzalnego `Instance.new` +
	    sześć linijek przypisań.

	Gdy UI urośnie ponad kilka ekranów, warto rozważyć Fusion
	(`wally add elttob/fusion`). Na tym etapie dodatkowa zależność kosztuje
	więcej, niż daje.
]]

local Theme = {}

Theme.COLOR = table.freeze({
	panel = Color3.fromRGB(24, 28, 36),
	panelAlt = Color3.fromRGB(34, 40, 51),
	stroke = Color3.fromRGB(58, 66, 80),
	text = Color3.fromRGB(236, 240, 246),
	textMuted = Color3.fromRGB(148, 158, 173),
	accent = Color3.fromRGB(86, 180, 255),
	success = Color3.fromRGB(96, 206, 128),
	warning = Color3.fromRGB(240, 176, 72),
	danger = Color3.fromRGB(232, 104, 104),
	coin = Color3.fromRGB(255, 205, 88),
})

Theme.FONT = Enum.Font.Gotham
Theme.FONT_BOLD = Enum.Font.GothamBold

--[[
	Instance.new z właściwościami i dziećmi w jednym wywołaniu.

	`Parent` jest przypisywany NA KOŃCU, po dzieciach i pozostałych
	właściwościach. Inaczej Roblox renderowałby element w trakcie składania
	i dałoby się złapać migotanie przy wejściu do gry.

	Zwracany typ to `Instance` — rzutuj w miejscu wywołania, gdy potrzebujesz
	konkretnej klasy:
	    local label = Theme.create("TextLabel", { ... }) :: TextLabel

	Dzieci przekazujemy jako VARARGS, a nie tablicę — i to jest istotne.
	Tablice w Luau są niezmiennicze (invariant): literał
	`{ Theme.corner(8), someTextLabel }` dostaje typ elementu z pierwszego
	wpisu, czyli `{UICorner}`, i analiza typów wywala resztę elementów.
	Obejścia są dwa: rzutować każdy literał (`:: { Instance }`) albo przejść
	na varargs. Varargs są sprawdzane element po elemencie, więc działają bez
	żadnego rzutowania — a tym samym nikt w zespole nie musi pamiętać o cast,
	którego brak odkryłby dopiero na CI.

	    Theme.create("Frame", { Size = ... }, Theme.corner(6), label, button)
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

--[[ Zaokrąglenie rogów — do wstawienia w listę dzieci. ]]
function Theme.corner(radius: number): UICorner
	return Theme.create("UICorner", { CornerRadius = UDim.new(0, radius) }) :: UICorner
end

--[[ Obramowanie. Domyślnie w kolorze `stroke`. ]]
function Theme.stroke(color: Color3?, thickness: number?): UIStroke
	return Theme.create("UIStroke", {
		Color = color or Theme.COLOR.stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
end

--[[ Jednakowy padding ze wszystkich stron. ]]
function Theme.padding(pixels: number): UIPadding
	local offset = UDim.new(0, pixels)
	return Theme.create("UIPadding", {
		PaddingTop = offset,
		PaddingBottom = offset,
		PaddingLeft = offset,
		PaddingRight = offset,
	}) :: UIPadding
end

--[[ Pionowa lista z odstępem. ]]
function Theme.verticalList(gap: number): UIListLayout
	return Theme.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
	}) :: UIListLayout
end

--[[ Panel: tło + zaokrąglenie + obramowanie. Baza pod każde okno w grze. ]]
function Theme.panel(props: { [string]: any }, ...: Instance): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Theme.COLOR.panel,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end

	-- Zaokrąglenie i obramowanie idą przed dziećmi wywołującego; `...` musi
	-- być ostatnie, bo rozwinięcie varargs w środku listy argumentów urwałoby
	-- się do jednej wartości.
	return Theme.create("Frame", merged, Theme.corner(8), Theme.stroke(), ...) :: Frame
end

--[[ Etykieta tekstowa z sensownymi domyślnymi (przezroczyste tło, nasz font). ]]
function Theme.label(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.FONT,
		TextColor3 = Theme.COLOR.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
	}
	for key, value in props do
		merged[key] = value
	end

	return Theme.create("TextLabel", merged) :: TextLabel
end

return Theme
