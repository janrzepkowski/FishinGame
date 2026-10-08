--!strict
--[[
	MobileControls — sterowanie dotykowe.

	Na telefonie domyślna ścieżka Robloxa to „stuknij w narzędzie na pasku,
	potem stuknij w ekran". Działa, ale uczy się tego metodą prób, a w grze,
	gdzie liczy się ułamek sekundy na podcięcie, stukanie w losowy punkt
	ekranu jest po prostu złe — trafia się w UI, w postać, w nic.

	Dlatego jeden duży przycisk, który ZMIENIA PODPIS razem ze stanem:
	„Zarzuć" -> „Czekaj" -> „PODETNIJ". Gracz nie musi niczego kojarzyć,
	przycisk sam mówi, co zrobić.

	Pokazujemy go tylko przy dotyku BEZ klawiatury. Na tablecie z podpiętą
	klawiaturą gracz i tak użyje klawiszy, a przycisk tylko zasłaniałby wodę.
]]

local Theme = require(script.Parent.Theme)

local MobileControls = {}

export type Phase = "Idle" | "Waiting" | "Biting"

local root: Frame? = nil
local actionButton: TextButton? = nil
local inventoryButton: TextButton? = nil

local primaryAction: (() -> ())? = nil
local inventoryAction: (() -> ())? = nil

local PHASES: { [string]: { text: string, color: Color3 } } = {
	Idle = { text = "ZARZUĆ", color = Theme.COLOR.accent },
	Waiting = { text = "czekaj…", color = Theme.COLOR.panelHigh },
	Biting = { text = "PODETNIJ!", color = Theme.COLOR.warning },
}

function MobileControls.mount(parent: Instance)
	local action = Theme.button({
		Name = "PrimaryAction",
		AnchorPoint = Vector2.new(1, 1),
		-- Nad przyciskiem skoku Robloxa, nie na nim. 92x92 to z zapasem
		-- powyżej progu, w który da się trafić kciukiem bez celowania.
		Position = UDim2.new(1, -Theme.SPACE.lg, 1, -180),
		Size = UDim2.fromOffset(104, 104),
		BackgroundColor3 = Theme.COLOR.accent,
		TextSize = Theme.TEXT.body,
		Text = "ZARZUĆ",
	}, Theme.stroke(Color3.fromRGB(255, 255, 255), 2))

	local corner = action:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end

	local inventory = Theme.button({
		Name = "InventoryToggle",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.SPACE.lg, 1, -300),
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = Theme.COLOR.panelAlt,
		TextColor3 = Theme.COLOR.text,
		TextSize = Theme.TEXT.lead,
		Text = "▦",
	}, Theme.stroke())

	local inventoryCorner = inventory:FindFirstChildOfClass("UICorner")
	if inventoryCorner then
		inventoryCorner.CornerRadius = UDim.new(0.5, 0)
	end

	action.MouseButton1Click:Connect(function()
		local handler = primaryAction
		if handler then
			handler()
		end
	end)

	inventory.MouseButton1Click:Connect(function()
		local handler = inventoryAction
		if handler then
			handler()
		end
	end)

	actionButton = action
	inventoryButton = inventory

	root = Theme.create("Frame", {
		Name = "MobileControls",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Przezroczysta ramka na cały ekran nie może łapać kliknięć —
		-- inaczej zablokowałaby obracanie kamery palcem.
		Active = false,
		Visible = false,
		Parent = parent,
	}, action, inventory) :: Frame

	Theme.onLayout(function()
		local panel = root
		if panel then
			panel.Visible = Theme.isTouchOnly()
		end
	end)
end

function MobileControls.setPrimaryAction(handler: () -> ())
	primaryAction = handler
end

function MobileControls.setInventoryAction(handler: () -> ())
	inventoryAction = handler
end

--[[ Podpis i kolor głównego przycisku idą za stanem łowienia. ]]
function MobileControls.setPhase(phase: Phase)
	local button = actionButton
	if not button then
		return
	end

	local style = PHASES[phase] or PHASES.Idle
	button.Text = style.text
	Theme.setButtonColor(button, style.color)
	button.TextColor3 = if phase == "Waiting"
		then Theme.COLOR.textMuted
		else Theme.COLOR.textInverse
end

function MobileControls.setInventoryHighlighted(highlighted: boolean)
	local button = inventoryButton
	if button then
		Theme.setButtonColor(
			button,
			if highlighted then Theme.COLOR.accent else Theme.COLOR.panelAlt
		)
	end
end

return MobileControls
