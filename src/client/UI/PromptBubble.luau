--!strict
--[[
	PromptBubble — własny wygląd podpowiedzi „naciśnij E" przy stoiskach.

	Wbudowana podpowiedź Robloxa jest szarym, półprzezroczystym prostokątem
	i przy naszym interfejsie wygląda jak okienko z innej gry. Stoiska
	ustawiają `ProximityPrompt.Style = Custom` (patrz `World/Market`),
	a my rysujemy w tym miejscu cukierkową pigułkę: plakietka z klawiszem
	i nazwa akcji.

	Zmienia się TYLKO wygląd. Zasięg, klawisz i samo wyzwolenie zostają po
	stronie `ProximityPrompt` — kliknięcie w pigułkę woła `InputHoldBegin`,
	czyli dokładnie to, co robi klawisz. Dzięki temu dotyk, mysz i klawiatura
	nie mają osobnych ścieżek, które mogłyby się rozjechać.

	To UI w świecie gry (`BillboardGui`), więc nie przechodzi przez
	`Theme.mountRoot` — ale kolory i czcionki bierze z `Theme`.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local PromptBubble = {}

local player = Players.LocalPlayer
local active: { [ProximityPrompt]: BillboardGui } = {}

local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return "X"
	end
	return prompt.KeyboardKeyCode.Name
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local previous = active[prompt]
	if previous then
		previous:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PromptBubble"
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(220, 44)
	-- Nisko, na froncie lady: pigułka nie może zasłaniać sprzedawcy.
	-- Bez `StudsOffset` ku kamerze — z nim podpowiedź nie rysowała się wcale.
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.ResetOnSpawn = false
	-- Bez tego kliknięcie w pigułkę trafiałoby w świat pod nią.
	billboard.Active = true

	local key = Theme.icon(keyLabel(prompt, inputType), Theme.COLOR.coin, 26, {
		Name = "Key",
		LayoutOrder = 1,
	})

	local action = Theme.label({
		Name = "Action",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.body,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = prompt.ActionText,
	})
	Theme.outline(action, Theme.COLOR.outline, 2)

	local button = Theme.create(
		"TextButton",
		{
			Name = "Pill",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.COLOR.success,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = billboard,
		},
		Theme.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE),
		Theme.candyGradient(0.18),
		Theme.create("UIPadding", {
			PaddingLeft = UDim.new(0, 5),
			PaddingRight = UDim.new(0, 14),
		}),
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 7),
		}),
		key,
		action
	) :: TextButton

	button.MouseButton1Down:Connect(function()
		prompt:InputHoldBegin()
	end)
	button.MouseButton1Up:Connect(function()
		prompt:InputHoldEnd()
	end)

	-- Wyskoczenie, a potem łagodne „oddychanie": pigułka ma zapraszać
	-- do naciśnięcia, nie tylko informować.
	local scale = Theme.create("UIScale", { Scale = 0.3, Parent = button }) :: UIScale
	local appear = TweenService:Create(
		scale,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	appear.Completed:Once(function()
		if billboard.Parent then
			TweenService:Create(
				scale,
				TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.05 }
			):Play()
		end
	end)
	appear:Play()

	-- Rodzicem jest PlayerGui (z `Adornee` na ladzie), nie sama lada:
	-- przyciski w BillboardGui reagują na kliknięcia tylko stamtąd.
	billboard.Parent = player:WaitForChild("PlayerGui")
	active[prompt] = billboard
end

local function hide(prompt: ProximityPrompt)
	local billboard = active[prompt]
	if billboard then
		active[prompt] = nil
		billboard:Destroy()
	end
end

function PromptBubble.start()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
end

return table.freeze(PromptBubble)
