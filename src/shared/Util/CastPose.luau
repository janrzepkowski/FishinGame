--!strict
--[[
	CastPose — poza wędkarza jako cztery kąty w czasie.

	Animacje rzutu i holu są PROCEDURALNE: zamiast assetów animacji (binaria
	wgrywane na Roblox) liczymy kąty stawów z fazy łowienia, czasu, mocy
	rzutu i napięcia żyłki. Klient nakłada je na `Motor6D.Transform`.

	Ta sama funkcja animuje KAŻDĄ postać w zasięgu — własną i cudze — na
	podstawie atrybutów ustawianych przez serwer. Dlatego jest w `shared/`
	i nie zna ani gracza, ani silnika: dostaje liczby, oddaje liczby.

	Zwracane kąty (radiany), w tej kolejności:
	  shoulder — bark ręki z wędką, liczony OD RĘKI ZWISAJĄCEJ W DÓŁ:
	             0 = ręka wzdłuż ciała, pi/2 = wyciągnięta w przód,
	             powyżej pi/2 = uniesiona nad bark i w tył
	  elbow    — łokieć; dodatni = zgięcie
	  waist    — talia; ujemna = odchylenie tułowia w tył
	  wrist    — nadgarstek, czyli kij względem ręki; dodatni = czubek
	             dalej w kierunku unoszenia ręki (w górę i w tył)

	Kąt barku to pełna poza, a nie poprawka do animacji Robloxa: zapis do
	`Transform` ZASTĘPUJE to, co policzył Animator, więc zero oznacza rękę
	w dół, a nie „bez zmian". Pierwsza wersja traktowała ujemny kąt jako
	zamach — i ręka cofała się w dół za plecy zamiast unieść wędkę nad bark.

	Czysta matematyka — pilnuje jej `tests/run.luau`.
]]

local CastPose = {}

-- Ile trwa dojście do pozy zamachu po wciśnięciu przycisku.
local WINDUP_TIME = 0.22
-- Wymach: krótki i szybki. Różnica tempa między zamachem a wymachem jest
-- tym, co odróżnia „rzut" od „machnięcia ręką".
local WHIP_TIME = 0.14
-- Powrót z wymachu do spokojnego trzymania wędki.
local SETTLE_TIME = 0.34

--[[
	Moment puszczenia żyłki, liczony od początku wymachu. Celowo PRZED jego
	końcem: spławik ma wylecieć w trakcie ruchu ręki, a nie po nim.
]]
CastPose.RELEASE_DELAY = 0.09

-- Poza spokojnego trzymania wędki nad wodą: ręka wyciągnięta w przód,
-- nieco poniżej poziomu, kij przedłuża linię ręki.
local HOLD_SHOULDER = 1.25
local HOLD_ELBOW = 0.3
local HOLD_WRIST = 0

local function easeOut(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return 1 - (1 - clamped) * (1 - clamped)
end

local function easeIn(t: number): number
	local clamped = math.clamp(t, 0, 1)
	return clamped * clamped
end

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

--[[ Skrajna poza zamachu dla danej mocy. Mocniejszy rzut = głębszy zamach;
     bez tego pasek mocy i postać opowiadałyby dwie różne historie. ]]
local function windup(power: number): (number, number, number, number)
	local p = math.clamp(power, 0, 1)
	-- Ręka idzie nad bark i w tył (ponad pi/2), łokieć się zgina, a kij
	-- kładzie się jeszcze dalej za plecy.
	return 2.25 + 0.55 * p, 0.5 + 0.4 * p, -(0.1 + 0.22 * p), 0.2 + 0.3 * p
end

--[[ Koniec wymachu: ręka wyprostowana w przód, tułów pochylony za rzutem. ]]
local function followThrough(power: number): (number, number, number, number)
	local p = math.clamp(power, 0, 1)
	-- Ręka opada poniżej pozy trzymania, a nadgarstek dobija czubek w dół.
	return 0.95 - 0.2 * p, 0.05, 0.12 + 0.16 * p, -(0.25 + 0.25 * p)
end

--[[
	Zamach: przycisk wciśnięty, pasek mocy chodzi.

	`power` to BIEŻĄCA moc z paska — poza pogłębia się i spłyca razem
	z nim, więc gracz widzi moc także na postaci, nie tylko w rogu ekranu.
]]
function CastPose.charging(elapsed: number, power: number): (number, number, number, number)
	local reach = easeOut(elapsed / WINDUP_TIME)
	local shoulder, elbow, waist, wrist = windup(power)
	return shoulder * reach, elbow * reach, waist * reach, wrist * reach
end

--[[
	Rzut i to, co po nim: wymach, powrót, trzymanie wędki nad wodą.

	`elapsed` liczy się od puszczenia przycisku, `power` to moc rzutu.
	W chwili zero poza jest dokładnie skrajną pozą zamachu dla tej mocy —
	przejście z `charging` nie ma szarpnięcia.
]]
function CastPose.casting(elapsed: number, power: number): (number, number, number, number)
	local s0, e0, w0, r0 = windup(power)
	local s1, e1, w1, r1 = followThrough(power)

	if elapsed < WHIP_TIME then
		local t = easeIn(elapsed / WHIP_TIME)
		return lerp(s0, s1, t), lerp(e0, e1, t), lerp(w0, w1, t), lerp(r0, r1, t)
	end

	local t = easeOut((elapsed - WHIP_TIME) / SETTLE_TIME)
	return lerp(s1, HOLD_SHOULDER, t),
		lerp(e1, HOLD_ELBOW, t),
		lerp(w1, 0, t),
		lerp(r1, HOLD_WRIST, t)
end

--[[
	Branie: ręka STOI, drga tylko nadgarstek — i to ledwo.

	Pierwsza wersja kołysała barkiem o 0,12 rad z częstotliwością 22 rad/s.
	Bark niesie całą rękę i trzymetrowy kij, więc czubek wędki latał
	w górę i w dół o ponad stud, przez dwie sekundy. Wyglądało to jak błąd
	fizyki, nie jak ryba. Branie ma być widać po UGIĘCIU SZCZYTÓWKI
	(`bend`) i po spławiku; ręka zostaje w miejscu.
]]
function CastPose.biting(elapsed: number): (number, number, number, number)
	local twitch = math.sin(elapsed * 14) * 0.03 * math.exp(-elapsed * 2.5)
	return HOLD_SHOULDER, HOLD_ELBOW, 0, HOLD_WRIST - 0.1 + twitch
end

--[[
	Hol: im większe napięcie, tym wyżej wędka i mocniej odchylony tułów.

	Przy szarpnięciu ryby dochodzi szybkie drżenie — obserwator ma zobaczyć
	zryw na postaci, zanim przeczyta go z paska.
]]
function CastPose.fighting(
	elapsed: number,
	tension: number,
	surging: boolean
): (number, number, number, number)
	local pull = math.clamp(tension, 0, 1)
	-- Drżenie idzie w nadgarstek, nie w bark: z barku przenosi się na cały
	-- kij i zamienia zryw ryby w machanie wędką.
	local shake = if surging then math.sin(elapsed * 18) * 0.035 else 0

	return HOLD_SHOULDER + 0.55 * pull,
		HOLD_ELBOW + 0.5 * pull,
		-0.28 * pull,
		HOLD_WRIST + 0.35 * pull + shake
end

--[[
	Ugięcie szczytówki w radianach; dodatnie = czubek w dół, ku wodzie.

	Kij jest jedynym miejscem, w którym napięcie żyłki widać na samej
	postaci: prosty kij przy pełnym pasku napięcia wygląda jak zepsuta
	animacja. Przy szarpnięciu ryby czubek dodatkowo drga.

	`phase` to nazwa fazy jak w `Types.FishingPhase`; nieznana faza
	(w tym `Idle`) daje kij prosty.
]]
function CastPose.bend(
	phase: string,
	elapsed: number,
	power: number,
	tension: number,
	surging: boolean
): number
	if phase == "Fighting" then
		local pull = math.clamp(tension, 0, 1)
		local shake = if surging then math.sin(elapsed * 18) * 0.05 else 0
		return 0.12 + 0.5 * pull + shake
	elseif phase == "Biting" then
		-- Ryba ciągnie, ale żyłka nie jest jeszcze napięta: wyraźne
		-- przygięcie z gasnącym drganiem.
		return 0.22 + math.sin(elapsed * 14) * 0.06 * math.exp(-elapsed * 2.5)
	elseif phase == "Waiting" and elapsed < WHIP_TIME + SETTLE_TIME then
		-- Wymach: kij spóźnia się za ręką i odgina w tył, potem wraca.
		local t = elapsed / (WHIP_TIME + SETTLE_TIME)
		return -(0.25 + 0.2 * math.clamp(power, 0, 1)) * math.sin(t * math.pi) * (1 - t)
	end
	return 0
end

return table.freeze(CastPose)
