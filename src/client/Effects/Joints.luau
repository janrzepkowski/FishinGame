--!strict
--[[
	Joints — zapis pozy do stawu postaci, niezależnie od jego rodzaju.

	Roblox przenosi awatary z klasycznych `Motor6D` na stawy oparte o więzy
	(`AnimationConstraint` + `BallSocketConstraint`) i część postaci NIE MA
	już `Motor6D` w rękach, szyi ani talii. Oba typy mają tę samą właściwość
	`Transform`, więc pozę nakładamy tak samo. Kod szukający wyłącznie
	`Motor6D` po cichu nie animuje na takich awatarach nic — tak właśnie
	przez długi czas „działał" pierwszy zamach wędką.

	KIEDY PISAĆ: z `RunService.PreSimulation`, nie z `RenderStepped`.
	Animator zapisuje `Transform` w kroku animacji tuż przed symulacją,
	a nowe stawy są rozwiązywane w samej symulacji. Zapis z `RenderStepped`
	widać w odczycie, ale Animator nadpisuje go, zanim trafi na ekran.
]]

local Joints = {}

--[[ Ustawia `Transform` stawu `name` w części `parent`. Zwraca false,
     gdy takiego stawu nie ma (np. R6 nie ma łokcia ani nadgarstka). ]]
function Joints.pose(parent: Instance?, name: string, transform: CFrame): boolean
	local found = parent and parent:FindFirstChild(name)
	if not found then
		return false
	end

	-- Dwie gałęzie zamiast unii typów: analiza zawęża wtedy `found` do
	-- konkretnej klasy i pozwala pisać do `Transform` bez rzutowania.
	if found:IsA("Motor6D") then
		found.Transform = transform
		return true
	end

	local constraint = if found:IsA("AnimationConstraint") then found else nil
	if constraint then
		constraint.Transform = transform
	end
	return constraint ~= nil
end

return table.freeze(Joints)
