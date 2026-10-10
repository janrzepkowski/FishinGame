--!strict
--[[
	Analytics — cienka otulina na `AnalyticsService` Robloxa.

	=========================================================================
	DLACZEGO OTULINA, A NIE WOŁANIE WPROST
	=========================================================================
	1. `AnalyticsService` RZUCA BŁĘDEM w Studio bez włączonego dostępu do API.
	   Bez pcall każde złowienie ryby wywalałoby handler w trakcie testów —
	   czyli telemetria psułaby grę, zamiast ją mierzyć. To jest dokładnie
	   odwrotność tego, po co się ją wdraża.

	2. Jedno miejsce decyduje, CO logujemy. Roblox limituje liczbę zdarzeń,
	   więc logowanie każdego zarzucenia (kilkanaście na minutę na gracza)
	   wypełniłoby limit śmieciem i zgubiło to, co istotne. Logujemy
	   zdarzenia KOŃCZĄCE etap pętli: złowienie, sprzedaż, zakup wędki,
	   ukończone zadanie.

	Co to daje produktowo: odpowiedzi na „gdzie gracze odpadają". Lejek
	z krokami 1-4 pokazuje, ilu graczy zarzuca, ilu zacina, ilu wyholowuje
	i ilu sprzedaje. Jeśli walka zabija 60% sesji, widać to w danych,
	a nie w domysłach.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Analytics = {}

local FUNNEL = "FishingLoop"

-- W Studio nie zaśmiecamy produkcyjnych danych testami. Ostrzeżenie leci
-- raz, żeby nikt nie szukał, czemu w dashboardzie nic nie ma.
local enabled = not RunService:IsStudio()
local warned = false

local function guard(label: string, call: () -> ())
	if not enabled then
		if not warned then
			warned = true
			print("[Analytics] Studio — zdarzenia nie są wysyłane.")
		end
		return
	end

	-- `xpcall`, nie `pcall`: wołana funkcja nic nie zwraca, więc `pcall` ma
	-- typ `(boolean)` i `local ok, err = pcall(...)` nie przechodzi analizy.
	xpcall(call, function(err)
		-- `warn`, nie `error`: telemetria nigdy nie może przerwać rozgrywki.
		warn(`[Analytics] {label} nie przeszło: {tostring(err)}`)
	end)
end

--[[
	Krok lejka rozgrywki. Numery muszą być stabilne między wersjami,
	inaczej historyczne dane przestają się dać porównywać.

	  1 zarzucenie  2 zacięcie  3 wyholowanie  4 sprzedaż
]]
function Analytics.funnelStep(player: Player, stepNumber: number, stepName: string)
	guard(`funnel {stepName}`, function()
		AnalyticsService:LogFunnelStepEvent(player, FUNNEL, nil, stepNumber, stepName)
	end)
end

--[[ Monety wpływające do gospodarki (sprzedaż ryb, nagroda za zadanie). ]]
function Analytics.coinsEarned(player: Player, amount: number, balance: number, source: string)
	guard("economy source", function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Source,
			"Coins",
			amount,
			balance,
			source
		)
	end)
end

--[[ Monety wypływające (zakup wędki). ]]
function Analytics.coinsSpent(player: Player, amount: number, balance: number, item: string)
	guard("economy sink", function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Coins",
			amount,
			balance,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			item
		)
	end)
end

--[[ Dowolne zdarzenie własne — ukończone zadanie, zerwana żyłka. ]]
function Analytics.custom(player: Player, name: string, value: number?)
	guard(`custom {name}`, function()
		AnalyticsService:LogCustomEvent(player, name, value)
	end)
end

return table.freeze(Analytics)
