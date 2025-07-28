-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local Rgb = {}
Rgb.__index = Rgb

function Rgb.new(red, green, blue)
  return setmetatable({
    red = red,
    green = green,
    blue = blue,
  }, Rgb)
end

function Rgb.from_hex(string)
  return Rgb.new(
    tonumber(string:sub(1, 2), 16),
    tonumber(string:sub(3, 4), 16),
    tonumber(string:sub(5, 6), 16)
  )
end

function Rgb.from_hsv(hue, saturation, value)
  hue = hue / 60
  local chroma = value * saturation
  local x = chroma * (1 - math.abs(hue % 2 - 1))
  local r, g, b
      if hue < 1 then r, g, b = chroma, x, 0
  elseif hue < 2 then r, g, b = x, chroma, 0
  elseif hue < 3 then r, g, b = 0, chroma, x
  elseif hue < 4 then r, g, b = 0, x, chroma
  elseif hue < 5 then r, g, b = x, 0, chroma
  else                r, g, b = chroma, 0, x end
  local m = value - chroma
  return Rgb.new(
    math.floor(0.5 + 0xff * (r + m)),
    math.floor(0.5 + 0xff * (g + m)),
    math.floor(0.5 + 0xff * (b + m))
  )
end

function Rgb:__eq(other)
  return self.red == other.red and self.green == other.green and self.blue == other.blue
end

function Rgb:hex()
  return ('%02x%02x%02x'):format(self.red, self.green, self.blue)
end

function Rgb:hsv()
  local max = math.max(self.red, self.green, self.blue)
  local min = math.min(self.red, self.green, self.blue)
  local delta = max - min
  local hue
  if delta == 0 then
    hue = 0
  elseif max == self.red then
    hue = ((self.green - self.blue) / delta) * 60
  elseif max == self.green then
    hue = ((self.blue - self.red) / delta + 2) * 60
  else
    hue = ((self.red - self.green) / delta + 4) * 60
  end
  if hue < 0 then
    hue = hue + 360
  end
  local saturation = max ~= 0 and delta / max or 0
  local value = max / 0xff
  return hue, saturation, value
end

return Rgb
