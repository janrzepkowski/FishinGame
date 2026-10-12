--!strict
--[[
	SpeechBubble — dymek z kwestią nad głową sprzedawcy.

	Własny, a nie wbudowany czat dymkowy Robloxa
	(`TextChatService:DisplayBubble`). Tamten rysuje się nad głową i znikał
	za szyldem oraz markizą stoiska — sprzedawca stoi pod daszkiem. Ten jest
	wysunięty ku kamerze, przed stoisko.

	To UI w świecie gry (`BillboardGui`), więc nie przechodzi przez
	`Theme.mountRoot` — ale kolory, odstępy i rozmiary tekstu bierze z `Theme`
	jak każdy inny ekran.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local SpeechBubble = {}

-- Dalej dymek byłby nieczytelną plamką przesłaniającą mapę.
local MAX_DISTANCE = 70
local WIDTH = 270
local FADE = 0.25
-- O ile studów dymek jest wysunięty ku kamerze. Lada z markizą wystaje
-- ok. 4 study przed sprzedawcę; przy 6 markiza ucinała jeszcze górę dymka.
local FORWARD = 9

-- Jeden dymek na postać: nowa kwestia zastępuje poprzednią, zamiast
-- układać się w stos nad głową.
local active: { [Instance]: BillboardGui } = {}

--[[
	Pokazuje kwestię nad `adornee` (zwykle głowa) na `duration` sekund.
	`speaker` to podpis nad tekstem — gracz ma wiedzieć, kto mówi, zanim
	nauczy się rozpoznawać sprzedawców po wyglądzie.
]]
function SpeechBubble.show(adornee: BasePart, speaker: string, text: string, duration: number)
	local previous = active[adornee]
	if previous then
		previous:Destroy()
		active[adornee] = nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Bubble"
	billboard.Adornee = adornee
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(WIDTH, 130)
	-- Dymek jest wysunięty W STRONĘ KAMERY (oś Z w `StudsOffset` liczy się
	-- w układzie kamery), więc rysuje się przed ladą, szyldem i markizą,
	-- pod którymi stoi sprzedawca — z każdej strony, z której patrzy gracz.
	-- `AlwaysOnTop` nie używamy: w testach takie dymki nie pojawiały się
	-- na zrzutach wcale, a zwykłe — tak.
	billboard.StudsOffset = Vector3.new(0, -0.4, FORWARD)
	billboard.LightInfluence = 0
	-- `Sibling`: dziecko rysuje się NAD rodzicem. Przy domyślnym `Global`
	-- tekst (ZIndex 1) lądował pod białym tłem dymka (ZIndex 2) — było
	-- widać sam pusty dymek.
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.ResetOnSpawn = false

	-- Imię na kolorowej plakietce wystającej z górnej krawędzi dymka —
	-- jak podpis postaci w komiksie.
	local name = Theme.badge(speaker, Theme.COLOR.pink, {
		Name = "Speaker",
		Size = UDim2.fromOffset(0, 24),
		Position = UDim2.fromOffset(14, -14),
		ZIndex = 3,
	})

	local line = Theme.label({
		Name = "Line",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.lead,
		-- Ciemny tekst na białym dymku: najwyższy kontrast, jaki mamy,
		-- a dymek czyta się w biegu.
		TextColor3 = Theme.COLOR.ink,
		TextWrapped = true,
		-- Kwestie są nasze, ale RichText i tak zinterpretowałby znaki `<`.
		RichText = false,
		Text = text,
	})

	-- „Ogonek" dymka: obrócony kwadrat wystający spod dolnej krawędzi.
	local tail = Theme.create("Frame", {
		Name = "Tail",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(20, 20),
		Rotation = 45,
		BackgroundColor3 = Theme.COLOR.white,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, Theme.corner(4), Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE)) :: Frame

	local bubble = Theme.create(
		"Frame",
		{
			Name = "Bubble",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.COLOR.white,
			BorderSizePixel = 0,
			ZIndex = 2,
		},
		Theme.corner(Theme.RADIUS.lg),
		Theme.stroke(Theme.COLOR.outline, Theme.OUTLINE),
		Theme.create("UIPadding", {
			PaddingTop = UDim.new(0, Theme.SPACE.lg),
			PaddingBottom = UDim.new(0, Theme.SPACE.md),
			PaddingLeft = UDim.new(0, Theme.SPACE.lg),
			PaddingRight = UDim.new(0, Theme.SPACE.lg),
		}),
		line
	) :: Frame

	-- Plakietka i ogonek są rodzeństwem dymka, nie jego dziećmi: dymek ma
	-- padding, który przesunąłby je razem z tekstem.
	local panel = Theme.create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, tail, bubble, name) :: Frame

	-- Łatka zasłania kontur dymka w miejscu, gdzie wychodzi z niego ogonek —
	-- bez niej przez ogonek biegłaby granatowa kreska.
	Theme.create("Frame", {
		Name = "TailPatch",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 1),
		Size = UDim2.fromOffset(21, 6),
		BackgroundColor3 = Theme.COLOR.white,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = panel,
	})

	panel.Parent = billboard

	-- Wyskoczenie: ruch przyciąga wzrok skuteczniej niż samo pojawienie się.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = panel
	TweenService:Create(
		scale,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	-- Rodzicem jest sama część w świecie (głowa sprzedawcy), tak jak przy
	-- tabliczce nad złowioną rybą: najprostszy układ, który rysuje się
	-- zawsze, i dymek znika razem z postacią.
	billboard.Parent = adornee
	active[adornee] = billboard

	task.delay(duration, function()
		if active[adornee] ~= billboard then
			return -- zastąpiony nowszą kwestią
		end
		active[adornee] = nil

		TweenService:Create(scale, TweenInfo.new(FADE), { Scale = 0 }):Play()
		task.delay(FADE, function()
			billboard:Destroy()
		end)
	end)
end

return table.freeze(SpeechBubble)
