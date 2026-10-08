--!strict
--[[
	Toast — krótkie komunikaty u góry ekranu (sprzedaż, brak monet, "podejdź
	bliżej wody").

	Komunikaty przychodzą z serwera przez `Net.Notify`, bo to serwer wie,
	dlaczego akcja się nie udała. Klient nie zgaduje treści — inaczej
	pokazywałby "kupiono!" także wtedy, gdy serwer transakcję odrzucił.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Toast = {}

local LIFETIME = 3
local FADE = 0.25
local MAX_VISIBLE = 4

local container: Frame? = nil
local active = 0

local COLORS: { [string]: Color3 } = {
	Info = Theme.COLOR.accent,
	Success = Theme.COLOR.success,
	Warning = Theme.COLOR.warning,
}

function Toast.mount(parent: Instance)
	container = Theme.create(
		"Frame",
		{
			Name = "Toasts",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16),
			Size = UDim2.fromOffset(420, 200),
			BackgroundTransparency = 1,
			Parent = parent,
		},
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		})
	) :: Frame
end

function Toast.show(message: string, kind: string?)
	local parent = container
	if not parent then
		return
	end

	-- Przy zalewie komunikatów (np. spam klikaniem w pełny ekwipunek)
	-- nie zasłaniamy pół ekranu.
	if active >= MAX_VISIBLE then
		return
	end
	active += 1

	local accent = COLORS[kind or "Info"] or Theme.COLOR.accent

	-- Uwaga na pętlę rozmiarów: panel ma AutomaticSize.X, więc etykieta NIE może
	-- mieć szerokości 1 (skali rodzica) — wyszłoby "rodzic liczy się z dziecka,
	-- dziecko z rodzica" i oba skończyłyby na zerze. Etykieta też mierzy się
	-- z tekstu, a panel dolicza padding.
	local label = Theme.label({
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.FONT_BOLD,
		TextSize = 15,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = message,
	})

	local frame = Theme.panel({
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.08,
		Parent = parent,
	}, Theme.padding(8), label)

	local function fadeOut()
		local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()

		task.delay(FADE, function()
			frame:Destroy()
			active -= 1
		end)
	end

	task.delay(LIFETIME, fadeOut)
end

return Toast
