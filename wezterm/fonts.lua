local wezterm = require("wezterm")
local settings = require("settings")

local Fonts = {}

function Fonts.setup(config)
	-- Main font. Falls back to Segoe UI Emoji for emoji glyphs JetBrainsMono
	-- doesn't cover. If you install a different Nerd Font later, just change
	-- the family name on the next line.
	config.font = wezterm.font_with_fallback({
		{ family = "JetBrainsMono Nerd Font", weight = "Medium" },
		"Segoe UI Emoji",
	})

	config.font_size = settings.get_font_size()
	config.line_height = settings.get_line_height()
	config.cell_width = settings.get_cell_width()
	config.underline_thickness = "200%"
	config.underline_position = "-3pt"
end

return Fonts
