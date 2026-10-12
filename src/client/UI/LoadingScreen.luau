--!strict
--[[
	LoadingScreen — zasłona na czas, gdy świat jeszcze się składa.

	Mapa powstaje z kodu na starcie serwera, a potem dojeżdża do klienta
	strumieniowo; chmury, pora dnia i profil dochodzą osobno. Bez zasłony
	gracz widzi to wszystko po kawałku: pustą trawę, wyskakujące stoiska,
	światło przeskakujące z domyślnego na docelowe. Zasłona stoi, dopóki
	KAŻDY z tych elementów nie jest na miejscu, i dopiero wtedy odsłania
	gotowy obraz.

	Każdy krok ma LIMIT CZASU. Zasłona, która nie znika, jest gorsza niż
	świat, który doładowuje się na oczach gracza — jeśli coś nie dojedzie
	(wolne łącze, profil w drodze), po limicie idziemy dalej.

	Własny `ScreenGui`, a nie korzeń z `Theme.mountRoot`: musi przykryć
	także HUD i pas pod górną belką Robloxa.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EnvironmentController = require(script.Parent.Parent.Controllers.EnvironmentController)
local FishIcon = require(script.Parent.FishIcon)
local ProfileCache = require(script.Parent.Parent.ProfileCache)
local Theme = require(script.Parent.Theme)

local LoadingScreen = {}

local FADE = 0.45
-- Najszybciej tak pasek może rosnąć (ułamek na sekundę). Gdy wszystko jest
-- gotowe od razu — a w Studio i na szybkim łączu zwykle jest — pasek i tak
-- wypełnia się przez ~2,5 s: gracz WIDZI ładowanie, zamiast mignięcia
-- zasłony, które wygląda jak błąd.
local FILL_SPEED = 0.4
-- Gdy etap się przeciąga, pasek dalej powoli pełznie w stronę następnego
-- progu. Stojący w miejscu pasek czyta się jako „zawiesiło się".
local CREEP_SPEED = 0.025

-- Okolice spawnu — o ten obszar prosimy strumieniowanie na starcie.
local SPAWN_AREA = Vector3.new(0, 5, 14)
-- Mapa „stoi", gdy przez tyle sekund nie doszła żadna nowa część.
local STREAM_SETTLE = 0.6
-- Ile czekamy na przeliczenie cieni i świateł po dojechaniu mapy.
local LIGHT_SETTLE = 1.2

-- Etapy: do jakiego ułamka paska sięga każdy i co wtedy piszemy.
local STAGES = {
	{ upTo = 0.4, text = "Napełniamy jezioro…" },
	{ upTo = 0.65, text = "Sadzimy lizaki…" },
	{ upTo = 0.85, text = "Liczymy ryby…" },
	{ upTo = 1, text = "Wpuszczamy słońce…" },
}

local TIPS = {
	"Im głębsza woda, tym rzadsze ryby!",
	"Niektóre ryby biorą tylko nocą.",
	"Puść przycisk, gdy ryba szarpie!",
	"Zielona strefa przy podcięciu = więcej monet.",
	"W deszczu ryby biorą szybciej.",
}

local player = Players.LocalPlayer

local screen: ScreenGui? = nil
local fill: Frame? = nil
local status: TextLabel? = nil
local percent: TextLabel? = nil

-- `reached` to ile NAPRAWDĘ jest gotowe (próg ukończonego etapu),
-- `shown` to ile pokazuje pasek. Pasek goni prawdę z ograniczoną prędkością.
local reached = 0
local shown = 0

local function render()
	local bar, label, number = fill, status, percent
	if bar then
		bar.Size = UDim2.fromScale(math.clamp(shown, 0.03, 1), 1)
	end
	if number then
		number.Text = `{math.floor(shown * 100 + 0.5)}%`
	end
	if label then
		for _, stage in STAGES do
			if shown < stage.upTo then
				label.Text = stage.text
				return
			end
		end
		label.Text = "Gotowe!"
	end
end

--[[ Jedna klatka animacji paska. ]]
local function advance(delta: number)
	if shown < reached then
		shown = math.min(shown + FILL_SPEED * delta, reached)
	else
		-- Dogoniliśmy prawdę, a etap jeszcze trwa: pełzniemy pod następny
		-- próg, ale nigdy go nie przekraczamy — 100% znaczy „gotowe".
		for _, stage in STAGES do
			if stage.upTo > reached then
				shown = math.min(shown + CREEP_SPEED * delta, stage.upTo - 0.04)
				break
			end
		end
	end
	render()
end

--[[ Czeka, aż `ready` zwróci prawdę, ale nie dłużej niż `limit` sekund. ]]
local function waitFor(limit: number, ready: () -> boolean)
	local deadline = os.clock() + limit
	while not ready() and os.clock() < deadline do
		task.wait(0.1)
	end
end

--[[ Pokazuje zasłonę. Wołane jako PIERWSZA rzecz po starcie klienta. ]]
function LoadingScreen.show()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local title = Theme.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.new(1, 0, 0, 52),
		Font = Theme.FONT_DISPLAY,
		TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Text = "FishinGame",
	})
	Theme.outline(title, Theme.COLOR.outline, 4)

	local track, bar = Theme.progress({
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.56, 66),
		Size = UDim2.fromOffset(340, 26),
		ZIndex = 3,
	}, Theme.COLOR.success)

	local percentLabel = Theme.label({
		Name = "Percent",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_DISPLAY,
		TextSize = Theme.TEXT.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Text = "0%",
		Parent = track,
	})
	Theme.outline(percentLabel, Theme.COLOR.outline, 2)

	local statusLabel = Theme.label({
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.56, 100),
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.lead,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Text = "",
	})
	Theme.outline(statusLabel, Theme.COLOR.outline, 2)

	local tip = Theme.label({
		Name = "Tip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.new(1, -40, 0, 22),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT.lead,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Text = TIPS[Random.new():NextInteger(1, #TIPS)],
	})
	Theme.outline(tip, Theme.COLOR.outline, 2)

	-- Maskotka: Złota Rybka na kafelku, kołysząca się nad paskiem.
	local mascot = FishIcon.create("golden_fish", {
		Name = "Mascot",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.56, -18),
		Size = UDim2.fromOffset(150, 120),
		ZIndex = 3,
	})
	local mascotStroke = mascot:FindFirstChildOfClass("UIStroke")
	if mascotStroke then
		mascotStroke.Thickness = Theme.OUTLINE + 1
	end

	Theme.create(
		"Frame",
		{
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.COLOR.panel,
			BorderSizePixel = 0,
			-- Zasłona zjada kliknięcia: gracz nie zarzuca wędki w ciemno.
			Active = true,
			Parent = gui,
		},
		Theme.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Theme.COLOR.accent, Theme.COLOR.purple),
		}),
		Theme.sunburst({
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromScale(1.6, 1.6),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			ZIndex = 1,
			-- Promienie tylko o ton jaśniejsze od tła: mają dawać ruch,
			-- a nie zasłaniać napisy.
		}, Theme.COLOR.panelHigh, 16),
		mascot,
		title,
		track,
		statusLabel,
		tip
	)

	TweenService:Create(
		mascot,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(0.5, 0, 0.56, -32), Rotation = 4 }
	):Play()

	gui.Parent = player:WaitForChild("PlayerGui")

	screen = gui
	fill = bar
	status = statusLabel
	percent = percentLabel
	reached = 0
	shown = 0
	render()
end

--[[
	Czeka na świat, światło, postać i profil, a potem odsłania grę.
	Blokuje — wołaj w `task.spawn`.
]]
function LoadingScreen.finishWhenReady()
	local gui = screen
	if not gui then
		return
	end

	local animation = RunService.RenderStepped:Connect(advance)

	-- 1. Mapa: folder świata z trzema częściami zbudowanymi przez serwer.
	waitFor(30, function()
		local world = Workspace:FindFirstChild("World")
		return world ~= nil
			and world:FindFirstChild("Market") ~= nil
			and world:FindFirstChild("Dock") ~= nil
			and world:FindFirstChild("Scenery") ~= nil
	end)

	-- Sam folder to za mało: mapa dojeżdża STRUMIENIOWO, część po części.
	-- Prosimy o obszar wokół spawnu i czekamy, aż liczba części przestanie
	-- rosnąć — dopiero wtedy stoiska, latarnie i pomost naprawdę stoją.
	xpcall(function()
		player:RequestStreamAroundAsync(SPAWN_AREA, 10)
	end, function() end)

	local world = Workspace:FindFirstChild("World")
	if world then
		local lastCount = -1
		local stableSince = os.clock()
		waitFor(15, function()
			local count = #world:GetDescendants()
			if count ~= lastCount then
				lastCount = count
				stableSince = os.clock()
			end
			return count > 0 and os.clock() - stableSince >= STREAM_SETTLE
		end)
	end
	reached = STAGES[1].upTo

	-- 2. Niebo i postać. Chmury powstają na końcu budowy terenu, więc ich
	--    obecność znaczy, że teren, woda i kolory są już ustawione.
	waitFor(15, function()
		return Workspace.Terrain:FindFirstChildOfClass("Clouds") ~= nil
			and player.Character ~= nil
			and player.Character:FindFirstChild("HumanoidRootPart") ~= nil
	end)
	reached = STAGES[2].upTo

	-- 3. Profil: bez niego HUD pokazywałby zera, które po chwili przeskoczą.
	waitFor(10, function()
		return ProfileCache.get() ~= nil
	end)
	reached = STAGES[3].upTo

	-- 4. Kolejka zasobów (siatki, dźwięki, czcionki) i oświetlenie.
	waitFor(6, function()
		return ContentProvider.RequestQueueSize == 0
	end)
	-- Pora dnia, ekspozycja, mgła i chmury mają docelowe wartości…
	waitFor(10, EnvironmentController.isReady)
	-- …a silnik potrzebuje jeszcze chwili, żeby przeliczyć cienie i światła
	-- lamp dla świeżo dostarczonych części. Bez tego odstępu gracz widzi
	-- „zapalające się" oświetlenie tuż po podniesieniu kurtyny.
	task.wait(LIGHT_SETTLE)
	reached = 1

	-- Kurtyna idzie w górę dopiero, gdy PASEK dojdzie do końca — nie wtedy,
	-- gdy skończyło się samo ładowanie. Inaczej znikałby w połowie drogi.
	waitFor(8, function()
		return shown >= 0.999
	end)
	animation:Disconnect()
	shown = 1
	render()

	-- Chwila na „Gotowe! 100%" i podskok paska.
	local bar = fill
	local track = bar and bar.Parent
	if track and track:IsA("GuiObject") then
		Theme.bump(track, 0.12)
	end
	task.wait(0.55)

	-- Zasłona odjeżdża w górę jak kurtyna.
	local backdrop = gui:FindFirstChild("Backdrop")
	if backdrop and backdrop:IsA("Frame") then
		TweenService:Create(
			backdrop,
			TweenInfo.new(FADE, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0, -1.15) }
		):Play()
	end
	task.wait(FADE + 0.05)

	gui:Destroy()
	screen = nil
	fill = nil
	status = nil
	percent = nil
end

return LoadingScreen
