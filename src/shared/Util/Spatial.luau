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
	Pozycja postaci gracza, albo nil gdy postać nie istnieje / jest martwa.

	Zwracamy nil zamiast rzucać, bo to normalny stan: gracz może kliknąć
	w momencie respawnu i serwer musi to spokojnie odrzucić.
]]
function Spatial.characterPosition(player: Player): Vector3?
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

	return root.Position
end

return table.freeze(Spatial)
