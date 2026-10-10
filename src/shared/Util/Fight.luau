--!strict
--[[
	Fight — matematyka holu. Czysta funkcja, bez typów Robloxa.

	Wydzielona z `FishingService` z dwóch powodów:

	1. DA SIĘ TO PRZETESTOWAĆ. To jest rdzeń rozgrywki — jeśli balans
	   jest zły, gra jest zła, a w Studio sprawdza się to metodą „pograj
	   dwadzieścia minut i powiedz, czy fajnie". Test liczbowy odpowiada
	   na pytania typu „czy startową wędką DA SIĘ wyholować szczupaka"
	   w kilka milisekund.

	2. Czytelność. Pętla serwera zostaje tym, czym ma być — pętlą —
	   a reguły siedzą tutaj.

	Samo planowanie szarpnięć (kiedy, jak długo) zostaje w serwisie, bo
	potrzebuje zegara i generatora losowego.
]]

local Fight = {}

export type Params = {
	-- Z profilu ryby.
	strength: number,
	stamina: number,
	-- Z wędki.
	lineStrength: number,
	-- Strojenie globalne (GameConfig).
	progressGain: number,
	tensionGain: number,
	surgeTension: number,
	surgeProgress: number,
	slackLoss: number,
	tensionRecovery: number,
}

export type State = {
	progress: number,
	tension: number,
}

--[[
	Jeden krok symulacji.

	`reeling` to intencja gracza, `surging` to stan ryby. Cztery kombinacje
	dają całą rozgrywkę:

	  holuje + spokój    -> postęp szybko, napięcie wolno      (idealnie)
	  holuje + szarpie   -> postęp prawie zero, napięcie szybko (zerwiesz)
	  puścił + spokój    -> postęp powoli spada, napięcie spada (marnujesz czas)
	  puścił + szarpie   -> postęp powoli spada, napięcie spada (prawidłowo)

	Zwraca nowy stan. Nie mutuje wejścia — wywołujący decyduje, co z tym zrobi.
]]
function Fight.step(
	state: State,
	params: Params,
	dt: number,
	reeling: boolean,
	surging: boolean
): State
	local progress = state.progress
	local tension = state.tension

	if reeling then
		local progressRate = params.progressGain / math.max(params.stamina, 0.01)
		local tensionRate = params.tensionGain
			* params.strength
			/ math.max(params.lineStrength, 0.01)

		if surging then
			progressRate *= params.surgeProgress
			tensionRate *= params.surgeTension
		end

		progress += progressRate * dt
		tension += tensionRate * dt
	else
		progress -= params.slackLoss * dt
		tension -= params.tensionRecovery * dt
	end

	return {
		progress = math.clamp(progress, 0, 1),
		-- Napięcie NIE jest przycinane od góry do 1: wywołujący sprawdza
		-- `>= 1` jako warunek zerwania, a przycięcie z góry ukryłoby
		-- przekroczenie w pojedynczym kroku przy bardzo silnej rybie.
		tension = math.max(tension, 0),
	}
end

--[[
	Ile sekund czystego holowania potrzeba na wyciągnięcie ryby.

	Nie uwzględnia szarpnięć ani przerw — to dolna granica, przydatna
	do balansu i do testów („czy ta ryba nie zajmuje pół minuty").
]]
function Fight.minimumDuration(params: Params): number
	local rate = params.progressGain / math.max(params.stamina, 0.01)
	return 1 / rate
end

--[[
	Ile sekund ciągłego holowania wytrzyma żyłka od zera do zerwania.

	Druga połowa tego samego pytania o balans: jeśli ta liczba jest mniejsza
	niż czas reakcji człowieka (~0,25 s), walka jest nie do wygrania
	i żadna ilość umiejętności tego nie zmieni.
]]
function Fight.timeToSnap(params: Params, surging: boolean): number
	local rate = params.tensionGain * params.strength / math.max(params.lineStrength, 0.01)
	if surging then
		rate *= params.surgeTension
	end
	if rate <= 0 then
		return math.huge
	end
	return 1 / rate
end

return table.freeze(Fight)
