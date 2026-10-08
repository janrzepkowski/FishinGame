--!strict
--[[
	Punkt wejścia serwera.

	Ten plik ma robić jedną rzecz: ustalać kolejność startu. Żadnej logiki gry.
	Gdy ktoś szuka "co się dzieje przy starcie serwera", ma to zobaczyć na
	jednym ekranie.

	Kolejność nie jest przypadkowa:
	  1. Net      — tworzy RemoteEventy. Musi być pierwsze, bo klient na nie
	                czeka z timeoutem, a serwisy zaraz się na nie podpinają.
	  2. World    — stawia mapę. FishingService i ShopService pytają go
	                o wodę i stoiska, więc muszą ją mieć gotową.
	  3. Data     — wczytuje profile. Każdy kolejny serwis z nich czyta.
	  4. Reszta   — kolejność między nimi nie ma znaczenia.
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
local RodService = require(script.Services.RodService)
local ShopService = require(script.Services.ShopService)

RodService.start()
FishingService.start()
ShopService.start()

print("[FishinGame] serwer gotowy")
