--!strict
--[[
	Net — jedyne miejsce w projekcie, gdzie powstają RemoteEventy.

	Dlaczego tak, a nie `Instance.new("RemoteEvent")` tam, gdzie potrzebne:
	  * literówka w nazwie jest błędem kompilacji (`Net.RequestCat`), a nie
	    cichym `nil` w runtime,
	  * widać na jednym ekranie całą powierzchnię klient <-> serwer,
	    czyli całą powierzchnię ataku,
	  * serwer tworzy Remote'y w momencie `require`, klient na nie czeka —
	    nie ma wyścigu "klient wystartował szybciej".

	ŻELAZNA ZASADA: wszystko, co przychodzi z klienta, jest nieufne.
	Klient mówi "chcę zarzucić", nigdy "złowiłem jesiotra za 20k".
	Walidacja zawsze po stronie serwera — patrz FishingService / ShopService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local CONTAINER_NAME = "Net"
-- Jeśli klient czeka dłużej, to nie jest lag — to znaczy, że serwer nie
-- zarekwirował Net na starcie. Lepiej krzyknąć niż wisieć w nieskończoność.
local WAIT_TIMEOUT = 15

local function resolveContainer(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)
		if existing then
			return existing :: Folder
		end

		local folder = Instance.new("Folder")
		folder.Name = CONTAINER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	local found = ReplicatedStorage:WaitForChild(CONTAINER_NAME, WAIT_TIMEOUT)
	if not found then
		error(`Net: brak folderu "{CONTAINER_NAME}" po {WAIT_TIMEOUT}s`)
	end
	return found :: Folder
end

local container = resolveContainer()

local function remote(name: string): RemoteEvent
	if IS_SERVER then
		local existing = container:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end

		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = container
		return event
	end

	local found = container:WaitForChild(name, WAIT_TIMEOUT)
	if not found then
		error(`Net: brak Remote'a "{name}" po {WAIT_TIMEOUT}s`)
	end
	return found :: RemoteEvent
end

local Net = {}

-- =========================================================================
-- Klient -> Serwer
-- Payloady są celowo minimalne: im mniej klient przesyła, tym mniej
-- serwer musi walidować i tym mniej da się oszukać.
-- =========================================================================

--[[ () — "chcę zarzucić". Serwer sam sprawdza wędkę, cooldown i odległość od wody. ]]
Net.RequestCast = remote("RequestCast")

--[[ () — "podcinam teraz". Serwer sam mierzy czas reakcji; klient nie podaje wyniku. ]]
Net.RequestReel = remote("RequestReel")

--[[ (rodId: string) — zakup wędki. Serwer sprawdza cenę, stan konta i posiadanie. ]]
Net.RequestBuyRod = remote("RequestBuyRod")

--[[ (rodId: string) — zmiana wędki na posiadaną. ]]
Net.RequestEquipRod = remote("RequestEquipRod")

--[[ () — sprzedaż całego ekwipunku. Serwer sprawdza odległość od skupu. ]]
Net.RequestSellAll = remote("RequestSellAll")

--[[
	() — "jestem gotowy, wyślij profil".

	Potrzebne, bo serwer robi pierwszy `push` w `PlayerAdded`, a to może się
	zdarzyć PRZED podłączeniem handlera przez klienta. Roblox owszem kolejkuje
	nieodebrane wywołania Remote'ów, ale opieranie startu UI na szczegółach
	tej kolejki to proszenie się o pusty HUD u jednego gracza na dziesięciu.
	Klient woła to raz, po zamontowaniu UI.
]]
Net.RequestProfile = remote("RequestProfile")

-- =========================================================================
-- Serwer -> Klient
-- =========================================================================

--[[ (profile: Types.Profile) — pełny snapshot po każdej zmianie. Profil jest
     mały (kilka KB), więc nie komplikujemy tego diffami. ]]
Net.ProfileUpdated = remote("ProfileUpdated")

--[[ (depth: number) — zarzucenie przyjęte, wraz z głębokością wody pod
     spławikiem (w studach). Klient pokazuje ją w HUD-zie, bo to jedyna
     informacja zwrotna o tym, że dalsze wyjście na pomost ma sens. ]]
Net.CastStarted = remote("CastStarted")

--[[ (reelWindow: number) — ryba bierze, masz tyle sekund na podcięcie.
     Gatunek jest już wylosowany na serwerze, ale go NIE wysyłamy —
     inaczej klient wiedziałby, kiedy warto podciąć. ]]
Net.BiteStarted = remote("BiteStarted")

--[[ (result: Types.CastResult) — koniec zarzucenia, z wynikiem. ]]
Net.CastResolved = remote("CastResolved")

--[[ (message: string, kind: Types.NotifyKind) — toast w UI. ]]
Net.Notify = remote("Notify")

return table.freeze(Net)
