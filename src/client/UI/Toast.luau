--!strict
--[[
	Toast — krótkie komunikaty w lewej kolumnie, pod HUD-em.

	=========================================================================
	DLACZEGO AKURAT TAM
	=========================================================================
	Roblox nie dokumentuje pozycji swojego CoreGui, więc trzeba to zmapować
	ręcznie. Zajętość ekranu wygląda tak:

	  góra-lewo    czat Robloxa (pod topbarem)  +  nasz HUD
	  góra-prawo   lista graczy / leaderstats
	  dół-środek   pasek narzędzi  +  nasz pasek łowienia
	  dół-prawo    przycisk skoku (mobile)  +  nasze sterowanie dotykowe
	  dół-lewo     drążek ruchu (mobile)

	Na desktopie wolny jest dół-lewo, ale na telefonie siedzi tam drążek.
	Lewa kolumna pod HUD-em jest jedynym miejscem wolnym na WSZYSTKICH
	klasach urządzeń — i nie wymaga wariantu per urządzenie, czyli nie
	dokłada kolejnego sposobu na zepsucie układu.

	Drugi powód jest projektowy: komunikat „Brakuje 200 monet" ląduje
	bezpośrednio pod licznikiem monet. Informacja i jej kontekst są obok
	siebie, a gracz ma jedno miejsce, w które patrzy.

	Pionowy pas na HUD rezerwuje `Theme.HUD_BAND`. Dzięki temu toasty nie
	muszą znać wysokości HUD-u ani na nią reagować.

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

local container: Frame? = nil
local active = 0

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
			Size = UDim2.fromOffset(WIDTH, 260),
			BackgroundTransparency = 1,
			Parent = parent,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Theme.SPACE.sm),
		})
	) :: Frame

	container = column

	Theme.onLayout(function(device: Theme.Device)
		local margin = if device == "Phone" then Theme.SPACE.sm else Theme.SPACE.lg
		local width = if device == "Phone" then 196 else WIDTH

		column.Position = UDim2.fromOffset(margin, Theme.HUD_BAND[device])
		column.Size = UDim2.fromOffset(width, 260)
	end)
end

function Toast.show(message: string, kind: string?)
	local parent = container
	if not parent or active >= MAX_VISIBLE then
		return
	end
	active += 1

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
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
	}, icon, label) :: Frame

	local frame = Theme.panel({
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 44),
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
