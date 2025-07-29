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

-- Oklab reference: https://bottosson.github.io/posts/oklab/

function Rgb.new(red, green, blue)
  assert(math.type(red) == 'integer' and math.type(green) == 'integer' and math.type(blue) == 'integer')
  if red < 0 or green < 0 or blue < 0 or red > 0xff or green > 0xff or blue > 0xff then
    error(('color outside gamut: %d %d %d'):format(red, green, blue))
  end
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

function Rgb.from_oklch(L, c, h, should_clip)
  h = math.rad(h)
  local a = c * math.cos(h)
  local b = c * math.sin(h)
  return Rgb.from_oklab(L, a, b, should_clip)
end

function Rgb.from_oklab(L, a, b, should_clip)
  local l = L + 0.3963377774 * a + 0.2158037573 * b
  local m = L - 0.1055613458 * a - 0.0638541728 * b
  local s = L - 0.0894841775 * a - 1.2914855480 * b
  l = l * l * l
  m = m * m * m
  s = s * s * s
  local r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
  local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
  local b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  if should_clip then
    r = math.max(0, math.min(1, r))
    g = math.max(0, math.min(1, g))
    b = math.max(0, math.min(1, b))
  end
  return Rgb.from_linear(r, g, b)
end

function Rgb.from_linear(r, g, b)
  return Rgb.new(
    math.floor(0.5 + 0xff * Rgb.gamma_compress(r)),
    math.floor(0.5 + 0xff * Rgb.gamma_compress(g)),
    math.floor(0.5 + 0xff * Rgb.gamma_compress(b))
  )
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

function Rgb:oklch()
  local L, a, b = self:oklab()
  local c = math.sqrt(a * a + b * b)
  local h = math.deg(math.atan(b, a))
  if h < 0 then
    h = h + 360
  end
  return L, c, h
end

function Rgb:oklab()
  local r, g, b = self:linear()
  local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
  local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
  local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
  l = l ^ (1 / 3)
  m = m ^ (1 / 3)
  s = s ^ (1 / 3)
  return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
         0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

function Rgb:linear()
  return Rgb.gamma_expand(self.red   / 0xff),
         Rgb.gamma_expand(self.green / 0xff),
         Rgb.gamma_expand(self.blue  / 0xff)
end

function Rgb:__eq(other)
  return self.red == other.red and self.green == other.green and self.blue == other.blue
end

function Rgb.gamma_compress(channel)
  if channel < 0.0031308 then
    return channel * 12.92
  else
    return channel ^ (1 / 2.4) * 1.055 - 0.055
  end
end

function Rgb.gamma_expand(channel)
  if channel < 0.04045 then
    return channel / 12.92
  else
    return ((channel + 0.055) / 1.055) ^ 2.4
  end
end

return Rgb
