local wezterm = require("wezterm")
local Theme = {}

-- ============================================================================
-- HOW TO SWITCH YOUR DEFAULT THEME:
-- Change the string on the next line to one of the names in `Theme.schemes`
-- below, save, and WezTerm will hot-reload automatically.
-- ============================================================================
Theme.name = "Catppuccin Mocha"

-- You can also switch themes live (without editing this file) by pressing
-- Alt+t — it opens a fuzzy picker with all the themes below. That change
-- only lasts until you restart WezTerm; edit Theme.name above to make a
-- theme permanent.

-- Each entry has:
--   colors  -> full WezTerm color_scheme table (background/foreground/ansi/etc.)
--   accents -> a small set of consistently-named colors (red/green/blue/...)
--              used by the tab bar for per-process icon colors, so tab.lua
--              doesn't need to know which theme is active.
Theme.builtin_schemes = {
	["Catppuccin Mocha"] = {
		colors = {
			foreground = "#cdd6f4",
			background = "#1e1e2e",
			cursor_bg = "#f5e0dc",
			cursor_border = "#f5e0dc",
			cursor_fg = "#1e1e2e",
			selection_bg = "#585b70",
			selection_fg = "#cdd6f4",
			ansi = { "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#bac2de" },
			brights = { "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#a6adc8" },
		},
		accents = {
			red = "#f38ba8",
			green = "#a6e3a1",
			yellow = "#f9e2af",
			blue = "#89b4fa",
			purple = "#cba6f7",
			cyan = "#94e2d5",
			orange = "#fab387",
			pink = "#f5c2e7",
			gray = "#7f849c",
			base = "#1e1e2e",
			mantle = "#181825",
			text = "#cdd6f4",
		},
	},

	["Tokyo Night"] = {
		colors = {
			foreground = "#c0caf5",
			background = "#1a1b26",
			cursor_bg = "#c0caf5",
			cursor_border = "#c0caf5",
			cursor_fg = "#1a1b26",
			selection_bg = "#283457",
			selection_fg = "#c0caf5",
			ansi = { "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6" },
			brights = { "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" },
		},
		accents = {
			red = "#f7768e",
			green = "#9ece6a",
			yellow = "#e0af68",
			blue = "#7aa2f7",
			purple = "#bb9af7",
			cyan = "#7dcfff",
			orange = "#ff9e64",
			pink = "#bb9af7",
			gray = "#565f89",
			base = "#1a1b26",
			mantle = "#16161e",
			text = "#c0caf5",
		},
	},

	["Dracula"] = {
		colors = {
			foreground = "#f8f8f2",
			background = "#282a36",
			cursor_bg = "#f8f8f2",
			cursor_border = "#f8f8f2",
			cursor_fg = "#282a36",
			selection_bg = "#44475a",
			selection_fg = "#f8f8f2",
			ansi = { "#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2" },
			brights = { "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff" },
		},
		accents = {
			red = "#ff5555",
			green = "#50fa7b",
			yellow = "#f1fa8c",
			blue = "#bd93f9",
			purple = "#bd93f9",
			cyan = "#8be9fd",
			orange = "#ffb86c",
			pink = "#ff79c6",
			gray = "#6272a4",
			base = "#282a36",
			mantle = "#21222c",
			text = "#f8f8f2",
		},
	},

	["Nord"] = {
		colors = {
			foreground = "#d8dee9",
			background = "#2e3440",
			cursor_bg = "#d8dee9",
			cursor_border = "#d8dee9",
			cursor_fg = "#2e3440",
			selection_bg = "#434c5e",
			selection_fg = "#d8dee9",
			ansi = { "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0" },
			brights = { "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4" },
		},
		accents = {
			red = "#bf616a",
			green = "#a3be8c",
			yellow = "#ebcb8b",
			blue = "#81a1c1",
			purple = "#b48ead",
			cyan = "#88c0d0",
			orange = "#d08770",
			pink = "#b48ead",
			gray = "#4c566a",
			base = "#2e3440",
			mantle = "#242933",
			text = "#d8dee9",
		},
	},

	["Gruvbox Dark"] = {
		colors = {
			foreground = "#ebdbb2",
			background = "#282828",
			cursor_bg = "#ebdbb2",
			cursor_border = "#ebdbb2",
			cursor_fg = "#282828",
			selection_bg = "#504945",
			selection_fg = "#ebdbb2",
			ansi = { "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984" },
			brights = { "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" },
		},
		accents = {
			red = "#fb4934",
			green = "#b8bb26",
			yellow = "#fabd2f",
			blue = "#83a598",
			purple = "#d3869b",
			cyan = "#8ec07c",
			orange = "#fe8019",
			pink = "#d3869b",
			gray = "#928374",
			base = "#282828",
			mantle = "#1d2021",
			text = "#ebdbb2",
		},
	},

	["One Dark"] = {
		colors = {
			foreground = "#abb2bf",
			background = "#282c34",
			cursor_bg = "#528bff",
			cursor_border = "#528bff",
			cursor_fg = "#282c34",
			selection_bg = "#3e4451",
			selection_fg = "#abb2bf",
			ansi = { "#282c34", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf" },
			brights = { "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff" },
		},
		accents = {
			red = "#e06c75",
			green = "#98c379",
			yellow = "#e5c07b",
			blue = "#61afef",
			purple = "#c678dd",
			cyan = "#56b6c2",
			orange = "#d19a66",
			pink = "#c678dd",
			gray = "#5c6370",
			base = "#282c34",
			mantle = "#21252b",
			text = "#abb2bf",
		},
	},
}

local settings = require("settings")
Theme.schemes = settings.load_themes(Theme.builtin_schemes)
if not Theme.schemes or not next(Theme.schemes) then
	Theme.schemes = Theme.builtin_schemes
end

local saved_theme = settings.get_theme()
if saved_theme and Theme.schemes[saved_theme] then
	Theme.name = saved_theme
end

-- Active theme's accent colors, exposed for tab.lua to use directly.
local active_scheme = Theme.schemes[Theme.name] or Theme.schemes["Catppuccin Mocha"] or Theme.builtin_schemes["Catppuccin Mocha"]
Theme.accents = active_scheme and active_scheme.accents or Theme.builtin_schemes["Catppuccin Mocha"].accents

function Theme.setup(config)
	local color_schemes = {}
	for name, scheme in pairs(Theme.schemes) do
		color_schemes[name] = scheme.colors
	end

	config.color_schemes = color_schemes
	config.color_scheme = Theme.name

	local accents = Theme.accents
	config.colors = config.colors or {}
	config.colors.tab_bar = {
		background = accents.mantle,
		active_tab = {
			bg_color = "none",
			fg_color = accents.text,
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},
		inactive_tab = {
			bg_color = accents.mantle,
			fg_color = accents.gray,
		},
		inactive_tab_hover = {
			bg_color = accents.base,
			fg_color = accents.text,
		},
		new_tab = {
			bg_color = accents.base,
			fg_color = accents.gray,
		},
		new_tab_hover = {
			bg_color = accents.base,
			fg_color = accents.gray,
		},
	}

	local function window_button(text, foreground, background)
		return wezterm.format({
			{ Background = { Color = background } },
			{ Foreground = { Color = foreground } },
			{ Text = text },
		})
	end

	config.tab_bar_style = {
		window_hide = window_button(" ─ ", accents.gray, accents.mantle),
		window_hide_hover = window_button(" ─ ", accents.text, accents.base),
		window_maximize = window_button(" □ ", accents.gray, accents.mantle),
		window_maximize_hover = window_button(" □ ", accents.text, accents.base),
		window_close = window_button(" ✕ ", accents.gray, accents.mantle),
		window_close_hover = window_button(" ✕ ", "#ffffff", accents.red),
	}
end

return Theme
