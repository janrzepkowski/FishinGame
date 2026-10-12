--!strict
--[[
	Punkt wejścia serwera.

	Ten plik ma robić jedną rzecz: ustalać kolejność startu. Żadnej logiki gry.
	Gdy ktoś szuka „co się dzieje przy starcie serwera", ma to zobaczyć na
	jednym ekranie.

	Kolejność nie jest przypadkowa:
	  1. Net      — tworzy RemoteEventy. Musi być pierwsze, bo klient na nie
	                czeka z timeoutem, a serwisy zaraz się na nie podpinają.
	  2. World    — stawia mapę. ShopService pyta go o stoiska,
	                a LeaderboardService o tablicę.
	  3. Data     — wczytuje profile i rozdaje `onProfileReady`. Każdy
	                kolejny serwis z tego korzysta.
	  4. Reszta   — kolejność między nimi nie ma znaczenia, bo komunikują
	                się przez Net i DataService, nie bezpośrednio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Samo wymaganie Net tworzy Remote'y. Wygląda jak nieużywana zmienna,
-- ale to jest ten efekt uboczny, na którym nam zależy.
require(ReplicatedStorage.Shared.Net)

local WorldBuilder = require(script.World.WorldBuilder)
WorldBuilder.build()

local DataService = require(script.Services.DataService)
DataService.start()

local FishingService = require(script.Services.FishingService)
local LeaderboardService = require(script.Services.LeaderboardService)
local RodService = require(script.Services.RodService)
local ShopService = require(script.Services.ShopService)
local WeatherService = require(script.Services.WeatherService)

-- Pogoda przed łowieniem: FishingService pyta o nią przy każdym rzucie.
WeatherService.start()
RodService.start()
FishingService.start()
ShopService.start()
LeaderboardService.start()

print("[FishinGame] serwer gotowy")
