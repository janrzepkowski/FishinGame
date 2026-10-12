--!strict
--[[
	SpeechBubble — dymek z kwestią nad głową sprzedawcy.

	Własny, a nie wbudowany czat dymkowy Robloxa
	(`TextChatService:DisplayBubble`). Tamten rysuje się w świecie i znikał
	za szyldem oraz markizą stoiska — sprzedawca stoi pod daszkiem, więc
	z większości kątów dymek był zasłonięty. Ten ma `AlwaysOnTop`: widać go
	zawsze, gdy widać miejsce, w którym stoi postać.

	To UI w świecie gry (`BillboardGui`), więc nie przechodzi przez
	`Theme.mountRoot` — ale kolory, odstępy i rozmiary tekstu bierze z `Theme`
	jak każdy inny ekran.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local SpeechBubble = {}

local GUI_NAME = "SpeechBubbles"
-- Dalej dymek byłby nieczytelną plamką przesłaniającą mapę.
local MAX_DISTANCE = 70
local WIDTH = 250
local FADE = 0.25

local container: Folder? = nil
-- Jeden dymek na postać: nowa kwestia zastępuje poprzednią, zamiast
-- układać się w stos nad głową.
local active: { [Instance]: BillboardGui } = {}

--[[
	Zwykły Folder w PlayerGui, NIE ScreenGui. `BillboardGui` zagnieżdżony
	w `ScreenGui` po prostu się nie rysuje — bez błędu i bez ostrzeżenia;
	dymek istniał w drzewie, miał tekst i nie było go na ekranie.
]]
local function getContainer(): Folder
	local existing = container
	if existing and existing.Parent then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = GUI_NAME
	folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	container = folder
	return folder
end

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
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Size = UDim2.fromOffset(WIDTH, 96)
	-- Nad głową i kapeluszem, z zapasem na sam dymek.
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local name = Theme.label({
		Name = "Speaker",
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.small,
		TextColor3 = Theme.COLOR.coin,
		Text = speaker,
	})

	local line = Theme.label({
		Name = "Line",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextSize = Theme.TEXT.body,
		TextWrapped = true,
		-- Kwestie są nasze, ale RichText i tak zinterpretowałby znaki `<`.
		RichText = false,
		Text = text,
	})

	local panel = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.08,
	}, Theme.padding(Theme.SPACE.sm, Theme.SPACE.md), Theme.list(Theme.SPACE.xs), name, line)
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

	billboard.Parent = getContainer()
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
