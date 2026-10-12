--!strict
--[[
	NpcController — sprzedawcy mówią: dymek nad głową i krótki okrzyk.

	Dwa źródła kwestii:
	  * powitanie wybiera KLIENT, gdy gracz podejdzie do stoiska — to czysta
	    dekoracja i nie ma powodu pytać o nią serwera,
	  * reakcję na transakcję ogłasza SERWER (`Net.NpcLine`), bo tylko on wie,
	    czy sprzedaż albo zakup naprawdę przeszły.

	Dymek to wbudowany czat dymkowy Robloxa (`TextChatService:DisplayBubble`)
	— wygląda jak wypowiedź gracza i nie wymaga własnego UI. Głos generuje
	syntezator mowy (`AudioTextToSpeech`); bez żadnego pliku dźwiękowego.

	WSZYSTKO TU JEST OPCJONALNE. Syntezator ma limity zapytań i potrafi
	zawieść, czat dymkowy może być wyłączony w ustawieniach gry. Każde
	wywołanie jest w `pcall`: sprzedawca, który milczy, nie może zepsuć
	sklepu.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local Net = require(Shared.Net)
local NpcConfig = require(Shared.Config.Npc)
local Spatial = require(Shared.Util.Spatial)

local NpcController = {}

-- Z jakiej odległości sprzedawca zagaduje i jak często najwyżej.
local GREET_DISTANCE = 16
local GREET_COOLDOWN = 40
-- Dalej niż tyle okrzyku nie słychać wcale — głos nie jest przestrzenny,
-- więc bez tej granicy sprzedawca krzyczałby graczowi do ucha przez pół mapy.
local VOICE_DISTANCE = 30
local CHECK_INTERVAL = 0.5

local player = Players.LocalPlayer
local generator = Random.new()

local output: AudioDeviceOutput? = nil
-- standKind -> okrzyk -> gotowy syntezator. Każdy okrzyk generujemy raz
-- i odtwarzamy wielokrotnie: limit zapytań jest liczony od generowania.
local voices: { [string]: { [string]: AudioTextToSpeech } } = {}
local lastGreetAt: { [string]: number } = {}
local wasNear: { [string]: boolean } = {}
local voiceWarned = false

local function findNpc(standKind: string): Model?
	for _, tagged in CollectionService:GetTagged(GameConfig.NPC_TAG) do
		if tagged:IsA("Model") and tagged:GetAttribute(GameConfig.NPC_ATTRIBUTE) == standKind then
			return tagged
		end
	end
	return nil
end

local function distanceTo(model: Model): number?
	local position = Spatial.characterPosition(player)
	if not position then
		return nil
	end
	return (model:GetPivot().Position - position).Magnitude
end

local function getOutput(): AudioDeviceOutput
	local existing = output
	if existing and existing.Parent then
		return existing
	end

	local created = Instance.new("AudioDeviceOutput")
	created.Name = "NpcVoiceOutput"
	created.Parent = SoundService
	output = created
	return created
end

--[[ Odtwarza losowy okrzyk sprzedawcy. Pierwsze użycie danego okrzyku
     generuje go (wywołanie sieciowe), kolejne grają z pamięci. ]]
local function shout(standKind: string, definition: NpcConfig.Definition)
	if #definition.shouts == 0 then
		return
	end

	local text = definition.shouts[generator:NextInteger(1, #definition.shouts)]
	local cache = voices[standKind]
	if not cache then
		cache = {}
		voices[standKind] = cache
	end

	task.spawn(function()
		-- `xpcall` z handlerem, nie `pcall`: funkcja nic nie zwraca, więc
		-- `pcall` miałby typ `(boolean)` i nie byłoby skąd wziąć błędu.
		xpcall(function()
			local voice: AudioTextToSpeech? = cache[text]

			if not voice then
				local created = Instance.new("AudioTextToSpeech")
				created.Name = `Voice_{standKind}`
				created.Text = text
				created.VoiceId = definition.voiceId
				created.Pitch = definition.pitch
				-- Okrzyk ma brzmieć tak samo u każdego; tłumaczenie „Oho!"
				-- na język gracza nie ma sensu.
				created.AutoLocalize = false
				created.Volume = 0.8
				created.Parent = SoundService

				local wire = Instance.new("Wire")
				wire.SourceInstance = created
				wire.TargetInstance = getOutput()
				wire.Parent = created

				if created:LoadAsync() ~= Enum.AssetFetchStatus.Success then
					created:Destroy()
					return
				end

				cache[text] = created
				voice = created
			end

			if voice then
				voice.TimePosition = 0
				voice:Play()
			end
		end, function(err)
			-- Jedno ostrzeżenie na sesję: wyłączony syntezator zasypałby
			-- inaczej Output przy każdej sprzedaży.
			if not voiceWarned then
				voiceWarned = true
				warn(`[NpcController] głos sprzedawcy niedostępny: {tostring(err)}`)
			end
		end)
	end)
end

--[[ Sprzedawca mówi kwestię z danej sytuacji: dymek i okrzyk. ]]
local function say(standKind: string, key: string)
	local definition = NpcConfig.find(standKind)
	local model = findNpc(standKind)
	if not definition or not model then
		return
	end

	local options = NpcConfig.lines(standKind, key)
	if #options == 0 then
		return
	end

	local head = model:FindFirstChild("Head")
	if head then
		local line = options[generator:NextInteger(1, #options)]
		pcall(function()
			TextChatService:DisplayBubble(head, line)
		end)
	end

	local distance = distanceTo(model)
	if distance and distance <= VOICE_DISTANCE then
		shout(standKind, definition)
	end
end

local function checkGreetings()
	local now = os.clock()

	for _, tagged in CollectionService:GetTagged(GameConfig.NPC_TAG) do
		local standKind = tagged:GetAttribute(GameConfig.NPC_ATTRIBUTE)
		if tagged:IsA("Model") and typeof(standKind) == "string" then
			local distance = distanceTo(tagged)
			local near = distance ~= nil and distance <= GREET_DISTANCE

			-- Witamy przy WEJŚCIU w zasięg, nie przez cały czas stania przy
			-- ladzie — i nie częściej niż co `GREET_COOLDOWN`.
			if near and not wasNear[standKind] then
				if now - (lastGreetAt[standKind] or -math.huge) >= GREET_COOLDOWN then
					lastGreetAt[standKind] = now
					say(standKind, "greet")
				end
			end

			wasNear[standKind] = near
		end
	end
end

function NpcController.start()
	Net.NpcLine.OnClientEvent:Connect(function(standKind: unknown, key: unknown)
		if typeof(standKind) == "string" and typeof(key) == "string" then
			say(standKind, key)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			checkGreetings()
		end
	end)
end

return table.freeze(NpcController)
