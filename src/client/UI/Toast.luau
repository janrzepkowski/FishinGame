--!strict
--[[
	Toast — komunikaty w LEWYM DOLNYM rogu.

	=========================================================================
	DLACZEGO TEN RÓG
	=========================================================================
	Roblox nie dokumentuje pozycji swojego CoreGui, więc zajętość ekranu
	trzeba zmapować ręcznie:

	  góra-lewo    czat Robloxa (pod topbarem)  +  nasz HUD
	  góra-prawo   lista graczy / leaderstats
	  dół-środek   pasek narzędzi  +  slot wędki
	  dół-prawo    przycisk skoku (mobile)  +  nasze sterowanie dotykowe
	  dół-lewo     WOLNE na desktopie; na telefonie drążek ruchu

	Cały nasz interfejs trzyma się LEWEJ KRAWĘDZI, żeby środek i prawa
	strona ekranu zostały dla rozgrywki. Komunikaty siedzą tuż nad paskiem
	łowienia i rosną w górę jak log — najświeższy najbliżej dołu, czyli tam,
	gdzie wzrok i tak wraca po każdym zarzuceniu.

	Wysokości NIE są tu zapisane: `Theme.toastBottom` liczy je z rozmiaru
	paska łowienia. Dwie stałe w dwóch plikach rozjechałyby się przy
	pierwszej zmianie rozmiaru paska i komunikaty weszłyby na niego.

	=========================================================================
	Treść przychodzi z serwera przez `Net.Notify`, bo to serwer wie, dlaczego
	akcja się nie udała. Klient nie zgaduje — inaczej pokazywałby „kupiono!"
	także wtedy, gdy serwer transakcję odrzucił.

	Toast NIE jest kanałem na błędy techniczne. Jeśli coś poszło nie tak
	z naszej winy, idzie to do `warn`, a gracz dostaje komunikat o tym,
	co ma zrobić.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Toast = {}

local LIFETIME = 3
local SLIDE = 0.18
local FADE = 0.28
-- Przy spamie (np. klikanie w pełną torbę) nie zasłaniamy pół ekranu.
local MAX_VISIBLE = 4
local WIDTH = 268
local WIDTH_PHONE = 200
local ROW = 44

local container: Frame? = nil
local active = 0
-- Rośnie z każdym komunikatem. Wyższy LayoutOrder = niżej w kolumnie,
-- czyli najnowszy toast ląduje przy samym rogu.
local sequence = 0

type Style = { color: Color3, icon: string }

local STYLES: { [string]: Style } = {
	Info = { color = Theme.COLOR.accent, icon = "i" },
	Success = { color = Theme.COLOR.success, icon = "✓" },
	Warning = { color = Theme.COLOR.warning, icon = "!" },
}

function Toast.mount(parent: Instance)
	local column = Theme.create(
		"Frame",
		{
			Name = "Toasts",
			-- Kotwica w LEWYM DOLNYM rogu samej kolumny: rośnie w górę,
			-- a nie w dół poza ekran.
			AnchorPoint = Vector2.new(0, 1),
			Size = UDim2.fromOffset(WIDTH, MAX_VISIBLE * (ROW + Theme.SPACE.sm)),
			BackgroundTransparency = 1,
			Parent = parent,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			-- Układanie od dołu: przy jednym komunikacie siedzi on w rogu,
			-- a nie w powietrzu na górze pustej kolumny.
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Theme.SPACE.sm),
		})
	) :: Frame

	container = column

	Theme.onLayout(function(device: Theme.Device)
		local width = if device == "Phone" then WIDTH_PHONE else WIDTH

		column.Size = UDim2.fromOffset(width, MAX_VISIBLE * (ROW + Theme.SPACE.sm))
		column.Position = UDim2.new(0, Theme.edgeMargin(device), 1, -Theme.toastBottom(device))
	end)
end

function Toast.show(message: string, kind: string?)
	local parent = container
	if not parent or active >= MAX_VISIBLE then
		return
	end
	active += 1
	sequence += 1

	local style = STYLES[kind or "Info"] or STYLES.Info

	local icon = Theme.label({
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(0, 0),
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textInverse,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = style.icon,
		BackgroundColor3 = style.color,
		BackgroundTransparency = 0,
	})
	Theme.corner(Theme.RADIUS.pill).Parent = icon

	-- Tekst zawija się zamiast rozpychać panel: kolumna ma stałą szerokość,
	-- żeby komunikaty układały się w równy słupek, a nie w schodki.
	local label = Theme.label({
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.text,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		Text = message,
	})

	local inner = Theme.create("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, icon, label) :: Frame

	local frame = Theme.panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, ROW),
		LayoutOrder = sequence,
		BackgroundTransparency = 0.04,
		Parent = parent,
	}, Theme.padding(Theme.SPACE.sm, Theme.SPACE.md), inner)

	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.color
		stroke.Thickness = 1.5
	end

	-- Wjazd od lewej krawędzi. Ruch przyciąga wzrok skuteczniej niż samo
	-- pojawienie się, a kierunek podpowiada, skąd komunikat „przyszedł".
	--
	-- Animujemy WNĘTRZE, nie sam panel: panel leży w UIListLayout, który
	-- nadpisuje jego `Position` w każdej klatce i zjadłby całą animację.
	inner.Position = UDim2.fromOffset(-WIDTH, 0)
	TweenService
		:Create(inner, TweenInfo.new(SLIDE, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(0, 0),
		})
		:Play()

	task.delay(LIFETIME, function()
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(icon, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end

		task.delay(FADE, function()
			frame:Destroy()
			active -= 1
		end)
	end)
end

return Toast
