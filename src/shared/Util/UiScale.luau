--!strict
--[[
	UiScale — mnożnik interfejsu i rozmiar korzenia UI dla danego viewportu.

	Siedzi w `shared/`, choć używa go tylko klient: to czysta matematyka bez
	typów Robloxa, więc `tests/run.luau` może jej pilnować. W `Theme` była
	nietestowalna i właśnie tam siedział błąd, którego nikt nie zauważył
	na ekranie 1366x768, bo przy skali 1 go nie widać.
]]

local UiScale = {}

-- Rozdzielczość, w której projektowaliśmy odstępy i rozmiary tekstu.
UiScale.DESIGN_WIDTH = 1366
UiScale.DESIGN_HEIGHT = 768

-- Dolne ograniczenie jest WAŻNIEJSZE niż wierność projektowi: na telefonie
-- proporcjonalne pomniejszenie dałoby przyciski poniżej progu trafialności
-- palcem. Lepiej, żeby UI zajmowało tam więcej ekranu.
UiScale.MIN = 0.82
-- Górne chroni przed olbrzymimi panelami na 4K.
UiScale.MAX = 1.3

--[[ Mnożnik interfejsu dla viewportu o podanych wymiarach w pikselach. ]]
function UiScale.scaleFor(width: number, height: number): number
	local raw = math.min(width / UiScale.DESIGN_WIDTH, height / UiScale.DESIGN_HEIGHT)
	return math.clamp(raw, UiScale.MIN, UiScale.MAX)
end

--[[
	Rozmiar korzenia UI jako ułamek ekranu (dla `UDim2.fromScale`).

	`UIScale` mnoży także rozmiar ramki, w której siedzi. Korzeń o rozmiarze
	1x1 przy skali 0,82 zajmuje więc 82% ekranu, a przy 1,3 wystaje poza
	niego — i wszystko zakotwiczone do prawej lub dolnej krawędzi ląduje
	nie tam, gdzie trzeba. Odwrotność skali znosi ten efekt: po przemnożeniu
	korzeń zawsze pokrywa dokładnie cały ekran.
]]
function UiScale.rootExtent(scale: number): number
	return 1 / scale
end

return table.freeze(UiScale)
