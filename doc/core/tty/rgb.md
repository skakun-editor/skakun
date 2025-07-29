# core.tty.rgb

    Rgb = require('core.tty.rgb')
    color = Rgb.new(red, green, blue)
    color.red, color.green, color.blue

The standard way to store color values from the sRGB color space.

    color = Rgb.from_hex(string)
    string = color:hex()

Converts from and to hexadecimal triplets, e.g. `'22552e'`.

    color = Rgb.from_hsv(hue, saturation, value)
    hue, saturation, value = color:hsv()

Converts from and to the HSV color space, useful for handcrafting color schemes.

    color = Rgb.from_oklch(L, c, h, [should_clip])
    L, c, h = color:oklch()

Converts from and to the Oklch color space, useful for perceptually correct
linear hue gradients, measuring the relative lightness and saturation of colors,
and porting color schemes from dark to light and vice versa. If `should_clip` is
`true`, then the result is naively clamped to the sRGB gamut.

    color = Rgb.from_oklab(L, a, b, [should_clip])
    L, a, b = color:oklab()

Converts from and to the Oklab color space, used for perceptually correct linear
color gradients, and calculating the lightness of colors. If `should_clip` is
`true`, then the result is naively clamped to the sRGB gamut.

    color = Rgb.from_linear(r, g, b)
    r, g, b = color:linear()

Converts from and to the linear sRGB color space, used for realistic light
calculations. Each channel's value is directly proportional to the physical
light intensity.
