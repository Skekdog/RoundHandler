-- Includes useful functions for common tasks in the library.

local module = {}

function module.ShuffleInPlace(t)
    math.randomseed(os.clock())
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function module.Color3ToHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R*0xFF, color.G*0xFF, color.B*0xFF)
end

return module