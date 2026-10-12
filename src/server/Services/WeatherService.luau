--!strict
--[[
	WeatherService — pogoda: serwer losuje, wszyscy widzą to samo.

	Pogoda WPŁYWA NA ŁOWIENIE (w deszczu ryby biorą szybciej), więc musi
	być jedna dla całego serwera i nie może pochodzić od klienta. Stan to
	jeden atrybut na Workspace: gracz, który dołączy w środku ulewy, dostaje
	go razem ze światem, bez osobnego zdarzenia.

	Pory dnia tu NIE MA. Godzinę każdy liczy sam z zegara serwerów
	(`Environment.clockAt`) — nie ma czego replikować.

	Cały efekt wizualny i dźwiękowy robi klient (`EnvironmentController`).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Environment = require(ReplicatedStorage.Shared.Util.Environment)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Net)

local WeatherService = {}

local generator = Random.new()

local MESSAGES: { [string]: string } = {
	Rain = "Zaczyna padać — ryby biorą chętniej.",
	Clear = "Przejaśnia się.",
}

function WeatherService.current(): string
	local value = Workspace:GetAttribute(GameConfig.WEATHER_ATTRIBUTE)
	return if typeof(value) == "string" then value else "Clear"
end

--[[ Godzina w grze po stronie serwera. W Studio można ją zamrozić
     atrybutem — do zrzutów ekranu i testów nocy bez czekania. ]]
function WeatherService.clock(): number
	if RunService:IsStudio() then
		local frozen = Workspace:GetAttribute(GameConfig.DEV_CLOCK_ATTRIBUTE)
		if typeof(frozen) == "number" then
			return frozen % 24
		end
	end
	return Environment.clockAt(Workspace:GetServerTimeNow(), GameConfig.DAY_LENGTH_SECONDS)
end

local function set(weather: string)
	if WeatherService.current() == weather then
		return
	end

	Workspace:SetAttribute(GameConfig.WEATHER_ATTRIBUTE, weather)

	local message = MESSAGES[weather]
	if message then
		Net.Notify:FireAllClients(message, "Info")
	end
end

function WeatherService.start()
	Workspace:SetAttribute(GameConfig.WEATHER_ATTRIBUTE, "Clear")

	task.spawn(function()
		while true do
			task.wait(
				generator:NextNumber(
					GameConfig.WEATHER_INTERVAL_MIN,
					GameConfig.WEATHER_INTERVAL_MAX
				)
			)
			set(Environment.pickWeather(generator:NextNumber(), GameConfig.RAIN_CHANCE))
		end
	end)
end

return table.freeze(WeatherService)
