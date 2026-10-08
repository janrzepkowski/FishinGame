--!strict
--[[
	Format — teksty widoczne dla gracza.

	Trzymamy to w jednym module, bo formatowanie ma być spójne w HUD-zie,
	w ekwipunku, w toastach i w sklepie. Gdy każdy ekran formatuje po swojemu,
	zawsze kończy się tym, że w jednym miejscu jest "1234", a w drugim "1 234".

	Konwencja polska: przecinek jako separator dziesiętny, spacja jako
	separator tysięcy.
]]

local Format = {}

--[[ 1234567 -> "1 234 567" ]]
function Format.coins(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local grouped = ""

	while #digits > 3 do
		grouped = ` {string.sub(digits, -3)}{grouped}`
		digits = string.sub(digits, 1, -4)
	end

	grouped = digits .. grouped

	if amount < 0 then
		return `-{grouped}`
	end
	return grouped
end

-- `string.gsub` zwraca dwie wartości (tekst, liczba podmian). Przypisanie do
-- jednej zmiennej odcina licznik — gdybyśmy wstawili wywołanie wprost do
-- interpolacji, trafiłby do tekstu.
local function withDecimalComma(text: string): string
	local replaced = string.gsub(text, "%.", ",")
	return replaced
end

--[[ 3.4217 -> "3,42 kg" ]]
function Format.mass(kilograms: number): string
	return `{withDecimalComma(string.format("%.2f", kilograms))} kg`
end

--[[ 12.5 -> "12,5 s" — do pasków postępu i cooldownów. ]]
function Format.seconds(value: number): string
	return `{withDecimalComma(string.format("%.1f", value))} s`
end

--[[ 11.0 -> "11 m" — głębokość wody. Bez części dziesiętnych, bo dno
     jest schodkowe i ułamki sugerowałyby precyzję, której nie ma. ]]
function Format.meters(value: number): string
	return `{math.floor(value + 0.5)} m`
end

return table.freeze(Format)
