--!strict
--[[
	ProfileCache — ostatni snapshot profilu otrzymany z serwera.

	Po co warstwa pośrednia zamiast podpinania się przez każdy ekran UI
	bezpośrednio pod `Net.ProfileUpdated`:

	  * ekran, który zamontował się po przyjściu snapshotu (np. sklep otwarty
	    w trakcie gry), dostaje aktualne dane od razu — `onChanged` woła
	    callback natychmiast, jeśli profil już jest. Bez tego sklep otwierałby
	    się pusty do pierwszej zmiany monet,
	  * jest jedno miejsce, w którym widać, że to tylko KOPIA. Serwer może
	    przysłać nowszą w każdej chwili i nadpisać lokalne zmiany.

	Nigdy nie modyfikuj zawartości zwróconego profilu. To nie jest stan gry,
	tylko jego odbicie — zmiana tutaj nie zmienia niczego na serwerze,
	a rozjedzie UI z rzeczywistością.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

type Profile = Types.Profile
type Listener = (Profile) -> ()

local ProfileCache = {}

local current: Profile? = nil
local listeners: { Listener } = {}

function ProfileCache.get(): Profile?
	return current
end

--[[
	Rejestruje callback na każdą zmianę profilu.

	Jeśli snapshot już dotarł, callback leci OD RAZU — dzięki temu ekrany nie
	muszą osobno obsługiwać "jeszcze nie mam danych".

	Zwraca funkcję odpinającą.
]]
function ProfileCache.onChanged(listener: Listener): () -> ()
	table.insert(listeners, listener)

	if current then
		listener(current)
	end

	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function ProfileCache.start()
	Net.ProfileUpdated.OnClientEvent:Connect(function(profile: Profile)
		current = profile

		-- Kopia listy przed iteracją: callback może się odpiąć w trakcie
		-- (np. zamykający się panel), a to przestawiłoby indeksy pod nogami.
		for _, listener in table.clone(listeners) do
			-- xpcall, nie pcall: listener nic nie zwraca, więc `pcall` ma typ
			-- `(boolean)` i `local ok, err = pcall(...)` nie przechodzi analizy.
			-- Przy okazji dostajemy traceback, czyli wiadomo KTÓRY ekran padł.
			-- Jeden wywrócony ekran nie może zabrać ze sobą pozostałych.
			xpcall(listener, function(err)
				warn(`[ProfileCache] listener rzucił błędem: {tostring(err)}`)
				warn(debug.traceback(nil, 2))
			end, profile)
		end
	end)
end

return ProfileCache
