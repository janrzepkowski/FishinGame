--!strict
--[[
	Sfx — odtwarzanie dźwięków z `Config/Audio`.

	Dwa rodzaje:
	  * `playAt` — jednorazowy dźwięk W MIEJSCU (plusk przy spławiku). Jest
	    przestrzenny, więc cudze zarzucenie słychać z właściwej strony
	    i ciszej z daleka, bez żadnego liczenia po naszej stronie.
	  * `loop` — pętla tła bez pozycji (szum jeziora, deszcz), której
	    głośnością steruje wywołujący.

	Wszystko gra LOKALNIE. Dźwięk uruchomiony na serwerze replikowałby się
	do wszystkich i nie dałoby się go ściszyć jednemu graczowi.

	Brak klipu albo nieudane ładowanie to cisza, nie błąd: dźwięk jest
	assetem na platformie i może zniknąć niezależnie od kodu.
]]

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Audio = require(Shared.Config.Audio)

local Sfx = {}

-- Poza tym promieniem jednorazowego dźwięku nie słychać wcale.
local MAX_DISTANCE = 110
local MIN_DISTANCE = 10

--[[ Jednorazowy dźwięk w punkcie świata. `scale` mnoży głośność bazową. ]]
function Sfx.playAt(name: string, position: Vector3, scale: number?)
	local clip = Audio[name]
	if not clip then
		return
	end

	-- Attachment pod Terrain: najtańszy nośnik pozycji, bez części i kolizji.
	local anchor = Instance.new("Attachment")
	anchor.Name = `Sfx_{name}`
	anchor.WorldPosition = position
	anchor.Parent = Workspace.Terrain

	local sound = Instance.new("Sound")
	sound.SoundId = clip.id
	sound.Volume = clip.volume * (scale or 1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = MIN_DISTANCE
	sound.RollOffMaxDistance = MAX_DISTANCE
	sound.Parent = anchor
	sound:Play()

	sound.Ended:Once(function()
		anchor:Destroy()
	end)
	-- Gdyby dźwięk się nie załadował, `Ended` nie przyjdzie nigdy.
	task.delay(8, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

--[[
	Pętla tła. Startuje wyciszona — głośność ustawia wywołujący
	(`Sound.Volume`), zwykle płynnie, w zależności od odległości albo pogody.
	Zwraca nil, gdy klipu nie ma.
]]
function Sfx.loop(name: string): Sound?
	local clip = Audio[name]
	if not clip then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = `Loop_{name}`
	sound.SoundId = clip.id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	return sound
end

--[[ Głośność bazowa klipu — punkt odniesienia dla pętli. ]]
function Sfx.baseVolume(name: string): number
	local clip = Audio[name]
	return if clip then clip.volume else 0
end

return table.freeze(Sfx)
