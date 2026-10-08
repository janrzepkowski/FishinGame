--!strict
--[[
	Spatial — geometria używana przez walidację po stronie serwera.

	Mieszka w `shared`, bo klient używa tych samych funkcji do pokazywania
	podpowiedzi ("podejdź bliżej wody"). Jedna implementacja = brak sytuacji,
	w której UI mówi "możesz łowić", a serwer odrzuca zarzucenie.
]]

local Spatial = {}

--[[
	Odległość punktu od najbliższego punktu bryły danego Part (0 = w środku).

	Dlaczego nie `(position - part.Position).Magnitude`: woda to prostopadłościan
	180x180 studów. Liczone od środka, gracz stojący na pomoście byłby "90 studów
	od wody", mimo że stoi nad nią. Liczymy więc do najbliższej ściany bryły.

	Działa dla obróconych części — przechodzimy do układu lokalnego Part i tam
	przycinamy punkt do jego połówkowych wymiarów.
]]
function Spatial.distanceToPart(position: Vector3, part: BasePart): number
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2

	local closest = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)

	return (localPoint - closest).Magnitude
end

--[[
	Korzeń postaci gracza, albo nil gdy postać nie istnieje / jest martwa.

	Zwracamy nil zamiast rzucać, bo to normalny stan: gracz może kliknąć
	w momencie respawnu i serwer musi to spokojnie odrzucić.
]]
function Spatial.characterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end

	return root
end

function Spatial.characterPosition(player: Player): Vector3?
	local root = Spatial.characterRoot(player)
	return if root then root.Position else nil
end

--[[
	Punkt, w który leci spławik: `distance` studów przed postacią, rzutowane
	na płaszczyznę poziomą.

	Mieszka w `shared`, bo liczą to OBIE strony — klient, żeby postawić
	spławik, i serwer, żeby sprawdzić głębokość pod nim. Dwie implementacje
	rozjechałyby się i gracz widziałby spławik nad głębią, dostając ryby
	jak z płycizny.

	Patrzenie prosto w górę albo w dół daje wektor zerowy, a `.Unit` zwróciłby
	wtedy NaN — stąd awaryjny kierunek „przed siebie".
]]
function Spatial.castTarget(root: CFrame, distance: number): Vector3
	local forward = root.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)

	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end

	return root.Position + flat.Unit * distance
end

return table.freeze(Spatial)
