--!strict
--[[
	Toast — krótkie komunikaty u góry ekranu.

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
local FADE = 0.28
-- Przy spamie (np. klikanie w pełną torbę) nie zasłaniamy pół ekranu.
local MAX_VISIBLE = 4

local container: Frame? = nil
local active = 0

type Style = { color: Color3, icon: string }

local STYLES: { [string]: Style } = {
	Info = { color = Theme.COLOR.accent, icon = "i" },
	Success = { color = Theme.COLOR.success, icon = "✓" },
	Warning = { color = Theme.COLOR.warning, icon = "!" },
}

function Toast.mount(parent: Instance)
	container = Theme.create(
		"Frame",
		{
			Name = "Toasts",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, Theme.SPACE.lg),
			Size = UDim2.fromOffset(480, 220),
			BackgroundTransparency = 1,
			Parent = parent,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Theme.SPACE.sm),
		})
	) :: Frame
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
		Position = UDim2.fromOffset(0, 1),
		Font = Theme.FONT_BLACK,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.textInverse,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = style.icon,
		BackgroundColor3 = style.color,
		BackgroundTransparency = 0,
	})
	Theme.corner(Theme.RADIUS.pill).Parent = icon

	-- Uwaga na pętlę rozmiarów: panel ma AutomaticSize.X, więc etykieta NIE
	-- może mieć szerokości w skali rodzica — wyszłoby „rodzic liczy się
	-- z dziecka, dziecko z rodzica" i oba skończyłyby na zerze.
	local label = Theme.label({
		Size = UDim2.fromOffset(0, 24),
		Position = UDim2.fromOffset(30, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.text,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = message,
	})

	local inner = Theme.create("Frame", {
		Name = "Inner",
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, icon, label) :: Frame

	local frame = Theme.panel({
		Name = "Toast",
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.04,
		Parent = parent,
	}, Theme.padding(Theme.SPACE.sm, Theme.SPACE.md), inner)

	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.color
		stroke.Thickness = 1.5
	end

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
