local wezterm = require("wezterm")
local settings = require("settings")
local tab = require("tab")
local theme = require("theme")
local keys = require("keys")
local fonts = require("fonts")
local startup = require("startup")

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Shell -----------------------------------------------------------------
config.default_prog = settings.get_shell_with_osc7()

-- Window ------------------------------------------------------------------
-- Integrated buttons in tab bar (Close, Maximize, Minimize) with resizable border
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_close_confirmation = "NeverPrompt"
config.window_padding = {
	left = 8,
	right = 8,
	top = 8,
	bottom = 8,
}
config.inactive_pane_hsb = {
	saturation = 1.0,
	brightness = 0.90,
}
config.enable_scroll_bar = false

-- Hovering over a pane focuses it (no click needed).
config.pane_focus_follows_mouse = true

-- Don't resize the window when you change font size with Ctrl+= / Ctrl+-;
-- keep the window's pixel size fixed and just fit more/fewer cells instead.
config.adjust_window_size_when_changing_font_size = false
config.default_cursor_style = settings.get_cursor_style()

config.warn_about_missing_glyphs = false
config.show_update_window = false
config.check_for_updates = false

-- Transparency / blur
config.window_background_opacity = settings.get_opacity()
config.win32_system_backdrop = settings.get_backdrop()

-- Mouse Bindings -----------------------------------------------------------
-- Ctrl+Shift + Left Click Drag moves the window
-- Links only open on CTRL + Click
config.mouse_bindings = {
	{
		event = { Drag = { streak = 1, button = "Left" } },
		mods = "CTRL|SHIFT",
		action = wezterm.action.StartWindowDrag,
	},
	-- Open hyperlink ONLY on Ctrl+Click
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "CTRL",
		action = wezterm.action.OpenLinkAtMouseCursor,
	},
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.CompleteSelection("ClipboardAndPrimarySelection"),
	},
}

-- Clickable links -----------------------------------------------------------
config.hyperlink_rules = {
	{ regex = [[\b\w+://[^\s<]+]], format = "$0" },
	{ regex = [[\b[\w.-]+@[\w.-]+\.[A-Za-z]{2,}\b]], format = "mailto:$0" },
}

-- Check for corruption warnings on load
wezterm.on("window-config-reloaded", function(window, pane)
	if #settings.corruption_warnings > 0 then
		window:toast_notification(
			"WezTerm Config Warning",
			"Corrupted config restored to default: " .. table.concat(settings.corruption_warnings, ", "),
			nil,
			8000
		)
		settings.corruption_warnings = {}
	end
end)

fonts.setup(config)
theme.setup(config)
keys.setup(config)
tab.setup(config)
startup.setup(config)

return config
