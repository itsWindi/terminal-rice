local wezterm = require("wezterm")
local act = wezterm.action

local Settings = {}

Settings.corruption_warnings = {}

-- Keep disk-backed settings out of the hot path after the first read.
local CACHED_SETTINGS = nil
local CACHED_KEYBINDS = nil
local CACHED_THEMES = nil
local CACHED_SHELLS = nil
local DIRECTORY_CACHE = {}

local DEFAULT_SETTINGS = {
	theme = "Catppuccin Mocha",
	default_cwd = nil,
	default_prog = { "cmd.exe" },
	window_size = { type = "custom", cols = 120, rows = 20 },
	font_size = 12,
	line_height = 1.5,
	cell_width = 1.0,
	cursor_style = "SteadyBar",
	pane_navigation = { mode = "arrows" },
	toast_notifications = true,
	window_opacity = 1.0,
	win32_system_backdrop = "Disable",
}

local DEFAULT_KEYBINDS = {
	settings_menu = { key = ",", mods = "ALT", desc = "Open Unified Settings Hub" },
	auto_split = { key = "p", mods = "ALT", desc = "Hyprland Auto Split" },
	auto_split_cwd = { key = "P", mods = "ALT|SHIFT", desc = "Hyprland Auto Split (Inherit CWD)" },
	split_horizontal = { key = "\\", mods = "ALT", desc = "Split Pane Horizontal" },
	split_vertical = { key = "-", mods = "ALT", desc = "Split Pane Vertical" },
	split_full_right = { key = "|", mods = "ALT|SHIFT", desc = "Split Full Window Right" },
	split_full_down = { key = "_", mods = "ALT|SHIFT", desc = "Split Full Window Down" },
	new_tab = { key = "t", mods = "CTRL", desc = "New Tab (Default Directory)" },
	new_tab_cwd = { key = "T", mods = "CTRL|SHIFT", desc = "New Tab (Inherit Current CWD)" },
	open_file_manager = { key = "e", mods = "ALT", desc = "Open File Manager at Active CWD" },
	close_tab = { key = "q", mods = "ALT", desc = "Close Tab" },
	close_pane = { key = "w", mods = "CTRL", desc = "Close Pane" },
	zoom_pane = { key = "z", mods = "ALT", desc = "Zoom/Unzoom Pane" },
	fullscreen = { key = "F11", mods = "", desc = "Toggle Fullscreen" },
	prev_tab = { key = "[", mods = "ALT", desc = "Previous Tab" },
	next_tab = { key = "]", mods = "ALT", desc = "Next Tab" },
	move_tab_prev = { key = "{", mods = "SHIFT|ALT", desc = "Move Tab Left" },
	move_tab_next = { key = "}", mods = "SHIFT|ALT", desc = "Move Tab Right" },
	copy = { key = "c", mods = "CTRL", desc = "Smart Copy / Interrupt" },
	font_increase = { key = "=", mods = "CTRL", desc = "Increase Font Size" },
	font_decrease = { key = "-", mods = "CTRL", desc = "Decrease Font Size" },
	command_palette = { key = "P", mods = "CTRL|SHIFT", desc = "Command Palette" },
	open_admin_terminal = { key = "a", mods = "ALT|SHIFT", desc = "Open Administrator Terminal (Inherit CWD)" },
}

local function copy_table(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and copy_table(v) or v
	end
	return copy
end

local function clamp_number(value, default, minimum, maximum)
	if type(value) ~= "number" then
		return default
	end
	return math.max(minimum, math.min(maximum, value))
end

local function apply_config_override(window, overrides)
	if not window then
		return true
	end
	local ok = pcall(function()
		local current = {}
		local got_overrides, existing = pcall(function()
			return window:get_config_overrides()
		end)
		if got_overrides and type(existing) == "table" then
			current = existing
		end
		for key, value in pairs(overrides) do
			current[key] = value
		end
		window:set_config_overrides(current)
	end)
	return ok
end

-- Keep stored single-letter keys lowercase so the displayed and actual
-- shortcuts do not silently diverge because WezTerm adds SHIFT to uppercase letters.
local function normalize_key_string(key)
	if type(key) == "string" and #key == 1 and key:match("%a") then
		return key:lower()
	end
	return key
end

local function navigation_preset(mode)
	if mode == "hjkl" then
		return {
			mode = "hjkl",
			left = { key = "h", mods = "ALT" },
			down = { key = "j", mods = "ALT" },
			up = { key = "k", mods = "ALT" },
			right = { key = "l", mods = "ALT" },
		}
	end
	return {
		mode = "arrows",
		left = { key = "LeftArrow", mods = "ALT" },
		down = { key = "DownArrow", mods = "ALT" },
		up = { key = "UpArrow", mods = "ALT" },
		right = { key = "RightArrow", mods = "ALT" },
	}
end

local function normalize_pane_navigation(value)
	local mode = type(value) == "string" and value or type(value) == "table" and value.mode
	if mode == "arrows" or mode == "hjkl" then
		return navigation_preset(mode)
	end
	if mode ~= "custom" or type(value) ~= "table" then
		return navigation_preset("arrows")
	end

	local navigation = { mode = "custom" }
	for _, direction in ipairs({ "left", "down", "up", "right" }) do
		local entry = value[direction]
		if type(entry) ~= "table"
			or type(entry.key) ~= "string"
			or entry.key == ""
			or type(entry.mods) ~= "string" then
			return navigation_preset("arrows")
		end
		navigation[direction] = {
			key = normalize_key_string(entry.key),
			mods = entry.mods,
		}
	end
	return navigation
end

local function normalize_settings(value)
	local settings = type(value) == "table" and value or {}

	if type(settings.theme) ~= "string" or settings.theme == "" then
		settings.theme = DEFAULT_SETTINGS.theme
	end

	if type(settings.default_prog) ~= "table" or #settings.default_prog == 0 then
		settings.default_prog = copy_table(DEFAULT_SETTINGS.default_prog)
	else
		local program = {}
		for _, part in ipairs(settings.default_prog) do
			if type(part) == "string" and part ~= "" then
				table.insert(program, part)
			end
		end
		settings.default_prog = #program > 0 and program or copy_table(DEFAULT_SETTINGS.default_prog)
	end

	if settings.default_cwd ~= nil and type(settings.default_cwd) ~= "string" then
		settings.default_cwd = nil
	end

	settings.font_size = clamp_number(settings.font_size, DEFAULT_SETTINGS.font_size, 6, 72)
	settings.line_height = clamp_number(settings.line_height, DEFAULT_SETTINGS.line_height, 0.5, 3.0)
	settings.cell_width = clamp_number(settings.cell_width, DEFAULT_SETTINGS.cell_width, 0.5, 2.0)
	if settings.cursor_style ~= "SteadyBar"
		and settings.cursor_style ~= "SteadyUnderline"
		and settings.cursor_style ~= "SteadyBlock" then
		settings.cursor_style = DEFAULT_SETTINGS.cursor_style
	end
	settings.pane_navigation = normalize_pane_navigation(settings.pane_navigation)
	if type(settings.toast_notifications) ~= "boolean" then
		settings.toast_notifications = DEFAULT_SETTINGS.toast_notifications
	end

	if type(settings.window_size) ~= "table" then
		settings.window_size = copy_table(DEFAULT_SETTINGS.window_size)
	elseif settings.window_size.type == "custom" then
		local cols = tonumber(settings.window_size.cols)
		local rows = tonumber(settings.window_size.rows)
		if not cols or not rows or cols < 1 or rows < 1 then
			settings.window_size = copy_table(DEFAULT_SETTINGS.window_size)
		else
			settings.window_size.cols = math.floor(cols)
			settings.window_size.rows = math.floor(rows)
		end
	elseif settings.window_size.type ~= "maximized" then
		settings.window_size = copy_table(DEFAULT_SETTINGS.window_size)
	end

	if type(settings.window_opacity) ~= "number" then
		settings.window_opacity = DEFAULT_SETTINGS.window_opacity
	else
		-- 0.0 is a valid, and often *recommended*, value: WezTerm's own docs
		-- say to set opacity to 0 for the best Mica/Tabbed backdrop result,
		-- so this must not be floored above zero.
		settings.window_opacity = math.max(0.0, math.min(1.0, settings.window_opacity))
	end

	if settings.win32_system_backdrop ~= "Acrylic"
		and settings.win32_system_backdrop ~= "Mica"
		and settings.win32_system_backdrop ~= "Tabbed"
		and settings.win32_system_backdrop ~= "Disable" then
		settings.win32_system_backdrop = DEFAULT_SETTINGS.win32_system_backdrop
	end

	return settings
end

local function normalize_keybinds(value)
	local keybinds = {}
	if type(value) == "table" then
		for id, entry in pairs(value) do
			if type(id) == "string" and type(entry) == "table" and type(entry.key) == "string" then
				keybinds[id] = {
					key = normalize_key_string(entry.key),
					mods = type(entry.mods) == "string" and entry.mods or "",
					desc = type(entry.desc) == "string" and entry.desc or id,
				}
			end
		end
	end
	for id, default in pairs(DEFAULT_KEYBINDS) do
		if not keybinds[id] then
			local d = copy_table(default)
			d.key = normalize_key_string(d.key)
			keybinds[id] = d
		end
	end
	return keybinds
end

local function normalize_themes(value, fallback)
	local themes = {}
	if type(value) == "table" then
		for name, scheme in pairs(value) do
			if type(name) == "string"
				and type(scheme) == "table"
				and type(scheme.colors) == "table"
				and type(scheme.accents) == "table"
				and type(scheme.accents.base) == "string"
				and type(scheme.accents.mantle) == "string"
				and type(scheme.accents.text) == "string"
				and type(scheme.accents.gray) == "string" then
				themes[name] = scheme
			end
		end
	end
	if next(themes) == nil and type(fallback) == "table" then
		return copy_table(fallback)
	end
	return themes
end

local function normalize_path(p)
	if not p then
		return nil
	end
	p = p:gsub("/", "\\")
	if #p > 3 and p:sub(-1) == "\\" then
		p = p:sub(1, -2)
	end
	return p
end

local function config_path(filename)
	return wezterm.config_dir .. "/" .. filename
end

local function safe_json_save(filepath, data)
	local ok, encoded = pcall(wezterm.json_encode, data)
	if not ok or not encoded then
		return false
	end

	-- Write beside the target first so a reload cannot observe a half-written JSON file.
	local temp_path = filepath .. ".tmp"
	local f = io.open(temp_path, "w")
	if not f then
		return false
	end
	f:write(encoded)
	local closed = f:close()
	if not closed then
		os.remove(temp_path)
		return false
	end

	if os.rename(temp_path, filepath) then
		return true
	end

	-- Windows may refuse to replace an existing file with os.rename. Keep a safe
	-- fallback for that case rather than deleting the user's current settings.
	local fallback = io.open(filepath, "w")
	if not fallback then
		os.remove(temp_path)
		return false
	end
	fallback:write(encoded)
	local fallback_closed = fallback:close()
	os.remove(temp_path)
	return fallback_closed
end

local function safe_json_load(filepath, default_data, file_label)
	local f = io.open(filepath, "r")
	if not f then
		safe_json_save(filepath, default_data)
		return copy_table(default_data)
	end

	local content = f:read("*a")
	f:close()

	if not content or content:match("^%s*$") then
		safe_json_save(filepath, default_data)
		return copy_table(default_data)
	end

	local ok, parsed = pcall(wezterm.json_parse, content)
	if not ok or type(parsed) ~= "table" then
		local timestamp = os.date("%Y%m%d_%H%M%S")
		local backup_path = filepath:gsub("%.json$", "") .. "_corrupted_" .. timestamp .. ".json"
		local bf = io.open(backup_path, "w")
		if bf then
			bf:write(content)
			bf:close()
		end
		safe_json_save(filepath, default_data)
		table.insert(Settings.corruption_warnings, file_label or filepath)
		return copy_table(default_data)
	end

	return parsed
end

-- Fast In-Memory Settings operations
function Settings.load()
	if CACHED_SETTINGS then
		return CACHED_SETTINGS
	end
	local s = normalize_settings(safe_json_load(config_path("settings.json"), DEFAULT_SETTINGS, "settings.json"))
	CACHED_SETTINGS = s
	return CACHED_SETTINGS
end

function Settings.save(data)
	local normalized = normalize_settings(data)
	CACHED_SETTINGS = copy_table(normalized)
	return safe_json_save(config_path("settings.json"), normalized)
end

-- Fast In-Memory Keybinds operations
function Settings.load_keybinds()
	if CACHED_KEYBINDS then
		return CACHED_KEYBINDS
	end
	local kb = normalize_keybinds(safe_json_load(config_path("keybinds.json"), DEFAULT_KEYBINDS, "keybinds.json"))
	CACHED_KEYBINDS = kb
	return CACHED_KEYBINDS
end

function Settings.save_keybinds(data)
	local normalized = normalize_keybinds(data)
	CACHED_KEYBINDS = copy_table(normalized)
	return safe_json_save(config_path("keybinds.json"), normalized)
end

-- Fast In-Memory Themes operations
function Settings.load_themes(default_themes)
	if CACHED_THEMES then
		return CACHED_THEMES
	end
	local fallback = type(default_themes) == "table" and default_themes or {}
	local loaded = safe_json_load(config_path("themes.json"), fallback, "themes.json")
	CACHED_THEMES = normalize_themes(loaded, fallback)
	return CACHED_THEMES
end

function Settings.save_themes(data)
	local normalized = normalize_themes(data, CACHED_THEMES or {})
	CACHED_THEMES = copy_table(normalized)
	return safe_json_save(config_path("themes.json"), normalized)
end

-- Zero-delay In-Memory Getters
function Settings.get_theme()
	local s = Settings.load()
	return s.theme or DEFAULT_SETTINGS.theme
end

function Settings.get_cwd()
	local s = Settings.load()
	return s.default_cwd
end

function Settings.get_shell()
	local s = Settings.load()
	return s.default_prog or DEFAULT_SETTINGS.default_prog
end

function Settings.get_font_size()
	return Settings.load().font_size or DEFAULT_SETTINGS.font_size
end

function Settings.get_line_height()
	return Settings.load().line_height or DEFAULT_SETTINGS.line_height
end

function Settings.get_cell_width()
	return Settings.load().cell_width or DEFAULT_SETTINGS.cell_width
end

function Settings.get_cursor_style()
	return Settings.load().cursor_style or DEFAULT_SETTINGS.cursor_style
end

function Settings.get_pane_navigation()
	return copy_table(Settings.load().pane_navigation or navigation_preset("arrows"))
end

function Settings.get_toast_notifications()
	return Settings.load().toast_notifications ~= false
end

function Settings.set_pane_navigation(value)
	if type(value) ~= "table" or (value.mode ~= "arrows" and value.mode ~= "hjkl" and value.mode ~= "custom") then
		return false
	end
	local s = Settings.load()
	s.pane_navigation = normalize_pane_navigation(value)
	CACHED_SETTINGS = s
	local saved = safe_json_save(config_path("settings.json"), s)
	if saved then
		wezterm.reload_configuration()
	end
	return saved
end

function Settings.set_toast_notifications(enabled)
	if type(enabled) ~= "boolean" then
		return false
	end
	local s = Settings.load()
	s.toast_notifications = enabled
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.toast(window, title, message, icon, timeout)
	if window and Settings.get_toast_notifications() then
		window:toast_notification(title, message, icon, timeout)
	end
end

-- Returns the shell command wrapped with automatic OSC 7 CWD reporting
-- for PowerShell variants. This makes Ctrl+Shift+T and Alt+Shift+P
-- reliably inherit the current working directory without needing a
-- separate .ps1 file or manual $PROFILE edits.
--
-- For non-PowerShell shells the prog is returned unchanged — bash/zsh
-- typically handle OSC 7 natively, and cmd has no mechanism for it.
--
-- Uses [char]27 instead of `e for PS 5.1 compatibility, and explicitly
-- loads $PROFILE with a guard so it isn't loaded twice on pwsh 7.4+
-- (which auto-loads $PROFILE before -Command when -NoExit is present).
local OSC7_PWSH_SNIPPET = [[
$ESC=[char]27; if(-not $__wez_profile_loaded -and (Test-Path $PROFILE)){$global:__wez_profile_loaded=$true; . $PROFILE}; if(-not $__wez_prev){$global:__wez_prev = $function:prompt; function global:prompt { $r = & $__wez_prev; if($PWD.Provider.Name -eq 'FileSystem'){ $p=$PWD.ProviderPath -replace '\\','/'; [Console]::Write("$ESC]7;file://$([System.Net.Dns]::GetHostName())/$p$ESC\") }; return $r }}
]]

function Settings.get_shell_with_osc7()
	local prog = Settings.get_shell()
	local exe = (prog[1] or ""):lower():gsub("%.exe$", "")
	-- Match pwsh, powershell, or full paths ending in those
	local basename = exe:match("[/\\]([^/\\]+)$") or exe
	if basename == "pwsh" or basename == "powershell" then
		-- Launch PowerShell in interactive mode with a tiny inline
		-- script that wraps the existing prompt to emit OSC 7.
		-- -NoExit keeps it interactive. The snippet explicitly
		-- dot-sources $PROFILE first (harmless if already loaded),
		-- then wraps the prompt function to emit OSC 7 on every
		-- prompt render.
		local snippet = OSC7_PWSH_SNIPPET:gsub("\n", " "):gsub("%s+", " ")
		local new_prog = { prog[1], "-NoLogo", "-NoExit", "-Command", snippet }
		-- Preserve any extra args from the original prog (e.g. -NoProfile)
		for i = 2, #prog do
			-- Skip if we've already added these flags
			local arg_lower = prog[i]:lower()
			if arg_lower ~= "-noexit" and arg_lower ~= "-nologo" then
				table.insert(new_prog, 3, prog[i])
			end
		end
		return new_prog
	end
	return prog
end

function Settings.get_window_size()
	local s = Settings.load()
	return s.window_size or DEFAULT_SETTINGS.window_size
end

function Settings.get_opacity()
	local s = Settings.load()
	return s.window_opacity or DEFAULT_SETTINGS.window_opacity
end

function Settings.get_backdrop()
	local s = Settings.load()
	return s.win32_system_backdrop or DEFAULT_SETTINGS.win32_system_backdrop
end

-- Instant Setters with zero-delay live visual update
function Settings.set_theme(name, window)
	local ok_theme, theme_mod = pcall(require, "theme")
	local schemes = (ok_theme and theme_mod.schemes) or CACHED_THEMES or {}
	local scheme = schemes[name]
	if not scheme then
		return false
	end
	local accents = scheme.accents

	-- 1. INSTANT visual update on current window with ZERO delay
	if window then
		local overrides = {
			color_scheme = name,
		}
		if accents then
			overrides.colors = {
				tab_bar = {
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
				},
			}
		end
		apply_config_override(window, overrides)
	end

	-- 2. Update in-memory state
	if ok_theme and theme_mod then
		theme_mod.name = name
		if accents then
			theme_mod.accents = accents
		end
	end

	local s = Settings.load()
	s.theme = name
	CACHED_SETTINGS = s

	-- 3. Save to disk
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_cwd(dir_path)
	local s = Settings.load()
	s.default_cwd = type(dir_path) == "string" and normalize_path(dir_path) or nil
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_shell(prog_table)
	if type(prog_table) ~= "table" or #prog_table == 0 then
		return false
	end
	local s = Settings.load()
	s.default_prog = normalize_settings({ default_prog = prog_table }).default_prog
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_opacity(val, window)
	if type(val) ~= "number" then
		return false
	end
	val = math.max(0.0, math.min(1.0, val))
	apply_config_override(window, { window_background_opacity = val })
	local s = Settings.load()
	s.window_opacity = val
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

-- Throttled apply + debounced disk-write for rapid-fire settings changes ---
--
-- Ctrl+=/Ctrl+- can fire many times a second via OS key autorepeat. Two
-- separate things used to happen on *every single one* of those events:
--   1. window:set_config_overrides() -- which makes WezTerm re-shape and
--      redraw with the new font metrics. This alone is enough work that a
--      fast run of autorepeat events can arrive faster than WezTerm can
--      process them, backing up the input queue -- that's the
--      freeze-then-catch-up.
--   2. A synchronous settings.json write (temp file, rename, and on
--      Windows typically a fallback rewrite since os.rename won't replace
--      an existing file) -- extra blocking work on top of (1).
--
-- `schedule` below wraps wezterm.time.call_after with a synchronous
-- fallback (so this still works, just without the smoothing, on older
-- WezTerm builds that lack the timer API).
local function schedule(delay, callback)
	local ok = pcall(function()
		wezterm.time.call_after(delay, callback)
	end)
	if not ok then
		callback()
	end
end

-- Leading + trailing throttle for the visual apply: a single keypress still
-- applies instantly (nothing to throttle), but once a burst starts, further
-- presses within the cooldown window only update the cheap in-memory cache
-- -- the renderer is touched at most once more, after the cooldown, with
-- whatever the final value turned out to be.
local FONT_APPLY_COOLDOWN = 0.08
local font_apply_cooldown_active = false

local function apply_font_size_throttled(window, val)
	if font_apply_cooldown_active then
		-- Already mid-cooldown: the value is cached (see set_font_size)
		-- and will be picked up by the trailing apply below.
		return true
	end
	font_apply_cooldown_active = true
	local applied = apply_config_override(window, { font_size = val })
	schedule(FONT_APPLY_COOLDOWN, function()
		font_apply_cooldown_active = false
		local latest = Settings.load().font_size
		if latest ~= val then
			if not apply_config_override(window, { font_size = latest }) then
				Settings.toast(window, "Font Size", "Could not apply the new font size.", nil, 4000)
			end
		end
	end)
	return applied
end

-- Trailing-edge debounce for the disk write: never runs mid-burst, only a
-- little while after activity stops (or periodically during a very long
-- hold), and always writes whatever CACHED_SETTINGS holds at the time it
-- fires -- so the final value is always the one that lands on disk.
local FONT_SAVE_DEBOUNCE = 0.4
local font_save_scheduled = false

local function schedule_font_save()
	if font_save_scheduled then
		return
	end
	font_save_scheduled = true
	schedule(FONT_SAVE_DEBOUNCE, function()
		font_save_scheduled = false
		safe_json_save(config_path("settings.json"), CACHED_SETTINGS)
	end)
end

function Settings.set_font_size(val, window)
	val = tonumber(val)
	if not val then
		return false
	end
	val = clamp_number(val, DEFAULT_SETTINGS.font_size, 6, 72)
	local s = Settings.load()
	s.font_size = val
	-- Updating the cache is cheap and instant, regardless of throttling --
	-- this is what adjust_font_size() reads to compute the next step, so
	-- rapid repeated presses always accumulate correctly even while the
	-- visual apply and disk write are being throttled/debounced.
	CACHED_SETTINGS = s

	local applied = apply_font_size_throttled(window, val)
	schedule_font_save()

	return applied
end

function Settings.set_line_height(val, window)
	val = tonumber(val)
	if not val then
		return false
	end
	val = clamp_number(val, DEFAULT_SETTINGS.line_height, 0.5, 3.0)
	apply_config_override(window, { line_height = val })
	local s = Settings.load()
	s.line_height = val
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_cell_width(val, window)
	val = tonumber(val)
	if not val then
		return false
	end
	val = clamp_number(val, DEFAULT_SETTINGS.cell_width, 0.5, 2.0)
	apply_config_override(window, { cell_width = val })
	local s = Settings.load()
	s.cell_width = val
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_cursor_style(value, window)
	if value ~= "SteadyBar" and value ~= "SteadyUnderline" and value ~= "SteadyBlock" then
		return false
	end
	apply_config_override(window, { default_cursor_style = value })
	local s = Settings.load()
	s.cursor_style = value
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.update_font_size_cache(val)
	val = tonumber(val)
	if not val then
		return false
	end
	local s = Settings.load()
	s.font_size = clamp_number(val, DEFAULT_SETTINGS.font_size, 6, 72)
	CACHED_SETTINGS = s
	return s.font_size
end

-- On Windows, win32_system_backdrop only becomes visible once
-- window_background_opacity is pulled below 1.0 -- at full opacity the
-- terminal's own background layer is fully opaque and completely hides the
-- OS blur/backdrop underneath it. WezTerm's docs recommend opacity = 0 for
-- Mica/Tabbed, and "lower than 1.0" for Acrylic. If someone turns a backdrop
-- on while still sitting at (near-)full opacity, nothing will visibly
-- change and it will look "not implemented" -- so nudge the opacity down
-- automatically the first time a backdrop is enabled from an opaque state.
function Settings.set_backdrop(val, window)
	if val ~= "Acrylic" and val ~= "Mica" and val ~= "Tabbed" and val ~= "Disable" then
		return false
	end
	local s = Settings.load()
	local opacity_changed = false
	if val ~= "Disable" and s.window_opacity >= 0.9 then
		s.window_opacity = (val == "Acrylic") and 0.5 or 0.0
		opacity_changed = true
	end
	if window then
		local overrides = { win32_system_backdrop = val }
		if opacity_changed then
			overrides.window_background_opacity = s.window_opacity
		end
		apply_config_override(window, overrides)
		if opacity_changed then
			Settings.toast(
				window,
				"Opacity & Blur",
				string.format(
					"%s needs opacity below 100%% to be visible, so it was lowered to %d%%.",
					val,
					math.floor(s.window_opacity * 100)
				),
				nil,
				5000
			)
		end
	end
	s.win32_system_backdrop = val
	CACHED_SETTINGS = s
	return safe_json_save(config_path("settings.json"), s)
end

function Settings.set_window_size(spec, window, pane)
	if type(spec) ~= "table" then
		return false
	end
	if spec.type == "custom" then
		local cols = tonumber(spec.cols)
		local rows = tonumber(spec.rows)
		if not cols or not rows or cols < 1 or rows < 1 then
			return false
		end
		spec = { type = "custom", cols = math.floor(cols), rows = math.floor(rows) }
	elseif spec.type == "maximized" then
		spec = { type = "maximized" }
	else
		return false
	end
	local s = Settings.load()
	s.window_size = spec
	Settings.save(s)

	if window then
		if spec.type == "maximized" then
			pcall(function()
				window:gui_window():maximize()
			end)
		elseif spec.type == "custom" and spec.cols and spec.rows and pane then
			pcall(function()
				window:gui_window():restore()
				local dims = pane:get_dimensions()
				local cell_w = (dims.pixel_width > 0 and dims.cols > 0) and (dims.pixel_width / dims.cols) or 9.6
				local cell_h = (dims.pixel_height > 0 and dims.viewport_rows > 0) and (dims.pixel_height / dims.viewport_rows) or 24.0
				local target_w = math.floor(spec.cols * cell_w + 16)
				local target_h = math.floor(spec.rows * cell_h + 16)
				window:gui_window():set_inner_size(target_w, target_h)
			end)
		end
	end
end

-- Path helpers
local function get_parent_dir(p)
	p = normalize_path(p)
	if not p or p:match("^%a:$") or p:match("^%a:\\$") then
		return nil
	end
	local parent = p:match("^(.*)\\[^\\]+$")
	if parent and parent:match("^%a:$") then
		parent = parent .. "\\"
	end
	return parent
end

local function list_subdirectories(dir)
	local cache_key = normalize_path(dir):lower()
	if DIRECTORY_CACHE[cache_key] then
		return DIRECTORY_CACHE[cache_key]
	end

	local subdirs = {}
	local ok, entries = pcall(wezterm.read_dir, dir)
	if ok and entries then
		-- Avoid probing every item on very large or slow directories. The menu
		-- remains usable and manual path entry is always available.
		for _, entry in ipairs(entries) do
			if #subdirs >= 200 then
				break
			end
			local is_ok, sub_entries = pcall(wezterm.read_dir, entry)
			if is_ok and sub_entries ~= nil then
				local folder_name = entry:gsub("/", "\\"):match("[^\\]+$") or entry
				if not folder_name:match("^%$") and folder_name ~= "System Volume Information" then
					table.insert(subdirs, {
						name = folder_name,
						path = normalize_path(entry),
					})
				end
			end
		end
	end
	table.sort(subdirs, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	DIRECTORY_CACHE[cache_key] = subdirs
	return subdirs
end

local function get_available_drives()
	local drives = {}
	for _, letter in ipairs({ "C", "D", "E", "F", "G", "H", "Z" }) do
		local root = letter .. ":\\"
		local ok, entries = pcall(wezterm.read_dir, root)
		if ok and entries ~= nil then
			table.insert(drives, root)
		end
	end
	return drives
end

-- Directory Autocomplete Navigator
function Settings.browse_directory(window, pane, current_dir)
	current_dir = normalize_path(current_dir or Settings.get_cwd() or wezterm.home_dir)

	local choices = {
		{ id = "CHOOSE:" .. current_dir, label = "> Set as default directory: " .. current_dir },
	}

	local parent = get_parent_dir(current_dir)
	if parent then
		table.insert(choices, { id = "UP:" .. parent, label = ".. (Parent: " .. parent .. ")" })
	else
		local drives = get_available_drives()
		for _, drive in ipairs(drives) do
			if drive:upper() ~= current_dir:upper() and drive:upper() ~= (current_dir .. "\\"):upper() then
				table.insert(choices, { id = "NAV:" .. drive, label = "Switch drive: " .. drive })
			end
		end
	end

	table.insert(choices, { id = "MANUAL", label = "Type directory path manually..." })
	table.insert(choices, { id = "WIN_PICKER", label = "Choose folder via Windows file dialog..." })
	table.insert(choices, { id = "RESET_HOME", label = "Reset to Home (" .. wezterm.home_dir .. ")" })

	local subdirs = list_subdirectories(current_dir)
	for _, sub in ipairs(subdirs) do
		table.insert(choices, {
			id = "NAV:" .. sub.path,
			label = sub.name .. "\\",
		})
	end

	window:perform_action(
		act.InputSelector({
			title = "Default Directory Autocomplete — " .. current_dir,
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end

				if id:match("^CHOOSE:(.+)") then
					local target = id:match("^CHOOSE:(.+)")
					Settings.set_cwd(target)
				elseif id:match("^UP:(.+)") then
					local target = id:match("^UP:(.+)")
					Settings.browse_directory(win, p, target)
				elseif id:match("^NAV:(.+)") then
					local target = id:match("^NAV:(.+)")
					Settings.browse_directory(win, p, target)
				elseif id == "MANUAL" then
					win:perform_action(
						act.PromptInputLine({
							description = "Enter full folder path:",
							action = wezterm.action_callback(function(w, pn, line)
								if line and line ~= "" then
									line = line:gsub("^%s+", ""):gsub("%s+$", "")
									Settings.set_cwd(normalize_path(line))
								end
							end),
						}),
						p
					)
				elseif id == "WIN_PICKER" then
					local cmd = {
						"powershell.exe",
						"-NoProfile",
						"-Command",
						"Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Out.Write($d.SelectedPath) }",
					}
					local ok, stdout = wezterm.run_child_process(cmd)
					if ok and stdout and stdout ~= "" then
						local trimmed = stdout:gsub("^%s+", ""):gsub("%s+$", "")
						if trimmed ~= "" then
							Settings.set_cwd(normalize_path(trimmed))
						end
					end
				elseif id == "RESET_HOME" then
					Settings.set_cwd(nil)
				end
			end),
		}),
		pane
	)
end

-- Instant Shell Detection (Zero Child Processes on GUI Thread)
--
-- Every candidate below is checked two ways: a handful of well-known
-- install locations (fast_paths), AND a scan of the user's PATH for its
-- executable name. The old version only ever checked fast_paths, and some
-- shells (Nushell in particular) had an empty fast_paths list -- meaning
-- they could never be detected at all, no matter how they were installed.
-- Package managers (scoop, cargo, chocolatey, winget) each put things in a
-- different folder, so relying on PATH as the primary source and
-- fast_paths as a supplement covers far more real setups than either alone.
local function env(name)
	local v = os.getenv(name)
	return (type(v) == "string" and v ~= "") and v or nil
end

local USERPROFILE = env("USERPROFILE") or "C:\\Users\\Default"
local LOCALAPPDATA = env("LOCALAPPDATA") or (USERPROFILE .. "\\AppData\\Local")
local PROGRAMFILES = env("ProgramFiles") or "C:\\Program Files"
local PROGRAMFILES_X86 = env("ProgramFiles(x86)") or "C:\\Program Files (x86)"
local PROGRAMDATA = env("ProgramData") or "C:\\ProgramData"
local SYSTEMROOT = env("SystemRoot") or "C:\\Windows"

local function path_exists(p)
	if type(p) ~= "string" or p == "" then
		return false
	end
	local f = io.open(p, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local PATH_DIRS = nil
local function get_path_dirs()
	if PATH_DIRS then
		return PATH_DIRS
	end
	PATH_DIRS = {}
	local raw = env("PATH") or env("Path") or ""
	for dir in raw:gmatch("[^;]+") do
		dir = dir:gsub('^"', ""):gsub('"$', ""):gsub("\\+$", "")
		if dir ~= "" then
			table.insert(PATH_DIRS, dir)
		end
	end
	return PATH_DIRS
end

-- Finds exe_name on PATH via io.open and returns its full path, or nil.
local function find_on_path(exe_name)
	for _, dir in ipairs(get_path_dirs()) do
		local candidate = dir .. "\\" .. exe_name
		if path_exists(candidate) then
			return candidate
		end
	end
	return nil
end

-- Resolve a single candidate via fast_paths, then PATH scan.
-- Returns the resolved path or nil if not found by either method.
local function resolve_candidate_local(c)
	for _, p in ipairs(c.fast_paths or {}) do
		if path_exists(p) then
			return p
		end
	end
	if c.exe then
		return find_on_path(c.exe)
	end
	return nil
end

-- Batch-resolve a list of exe names via a single `where.exe` invocation.
-- Returns a table mapping lowercase exe name -> first resolved path.
-- `where.exe` correctly handles WindowsApps app-execution aliases, Scoop
-- shims, and any other PATH entries that io.open() can't probe.
-- Note: where.exe returns exit code 1 if ANY name wasn't found, but it
-- still prints the ones it DID find — so we ignore the success flag.
local BATCH_WHERE_RESULT = nil
local function batch_where_resolve(exe_names)
	if BATCH_WHERE_RESULT then
		return BATCH_WHERE_RESULT
	end
	BATCH_WHERE_RESULT = {}
	if #exe_names == 0 then
		return BATCH_WHERE_RESULT
	end
	local args = { "where.exe" }
	for _, name in ipairs(exe_names) do
		table.insert(args, name)
	end
	-- wezterm.run_child_process returns (success, stdout, stderr).
	-- pcall prepends its own bool, giving (pcall_ok, success, stdout, stderr).
	local pcall_ok, _, stdout = pcall(wezterm.run_child_process, args)
	if not pcall_ok or type(stdout) ~= "string" then
		return BATCH_WHERE_RESULT
	end
	for line in stdout:gmatch("([^\r\n]+)") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			local basename = line:lower():match("([^/\\]+)$")
			if basename and not BATCH_WHERE_RESULT[basename] then
				BATCH_WHERE_RESULT[basename] = line
			end
		end
	end
	return BATCH_WHERE_RESULT
end

local SHELL_CANDIDATES = {
	{
		name = "PowerShell 7 (pwsh)",
		exe = "pwsh.exe",
		prog = { "pwsh" },
		fast_paths = {
			PROGRAMFILES .. "\\PowerShell\\7\\pwsh.exe",
			PROGRAMFILES .. "\\PowerShell\\7-preview\\pwsh.exe",
			LOCALAPPDATA .. "\\Microsoft\\WindowsApps\\pwsh.exe",
			USERPROFILE .. "\\scoop\\shims\\pwsh.exe",
		},
	},
	{
		name = "Windows PowerShell 5.1",
		exe = "powershell.exe",
		prog = { "powershell.exe" },
		fast_paths = { SYSTEMROOT .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" },
	},
	{
		name = "Command Prompt (cmd.exe)",
		exe = "cmd.exe",
		prog = { "cmd.exe" },
		fast_paths = { SYSTEMROOT .. "\\System32\\cmd.exe" },
	},
	{
		name = "Git Bash",
		exe = "bash.exe",
		-- bash.exe's own folder usually isn't on PATH (by design, to
		-- avoid shadowing WSL's bash), so this one is always launched
		-- via its resolved absolute path rather than a bare command.
		use_resolved_path = true,
		extra_args = { "-l" },
		fast_paths = {
			PROGRAMFILES .. "\\Git\\bin\\bash.exe",
			PROGRAMFILES_X86 .. "\\Git\\bin\\bash.exe",
			LOCALAPPDATA .. "\\Programs\\Git\\bin\\bash.exe",
			USERPROFILE .. "\\scoop\\apps\\git\\current\\bin\\bash.exe",
		},
	},
	{
		name = "WSL (Default Linux)",
		exe = "wsl.exe",
		prog = { "wsl.exe" },
		fast_paths = { SYSTEMROOT .. "\\System32\\wsl.exe" },
	},
	{
		name = "Nushell (nu)",
		exe = "nu.exe",
		prog = { "nu" },
		fast_paths = {
			USERPROFILE .. "\\.cargo\\bin\\nu.exe",
			USERPROFILE .. "\\scoop\\shims\\nu.exe",
			LOCALAPPDATA .. "\\Microsoft\\WindowsApps\\nu.exe",
			PROGRAMDATA .. "\\chocolatey\\bin\\nu.exe",
			PROGRAMFILES .. "\\Nu\\bin\\nu.exe",
		},
	},
}

local function build_shell_entry(c, resolved)
	local prog
	if c.use_resolved_path then
		prog = { resolved }
	else
		prog = copy_table(c.prog)
	end
	if c.extra_args then
		for _, a in ipairs(c.extra_args) do
			table.insert(prog, a)
		end
	end
	return { name = c.name, prog = prog }
end

function Settings.detect_available_shells()
	if CACHED_SHELLS then
		return CACHED_SHELLS
	end

	local shells = {}
	local unresolved_exes = {}    -- exe names not found by fast_paths/PATH
	local unresolved_indices = {} -- which candidate indices they map to

	-- Pass 1: fast_paths + PATH scan (zero child processes)
	for i, c in ipairs(SHELL_CANDIDATES) do
		local resolved = resolve_candidate_local(c)
		if resolved then
			table.insert(shells, build_shell_entry(c, resolved))
		elseif c.exe then
			table.insert(unresolved_exes, c.exe)
			table.insert(unresolved_indices, i)
		end
	end

	-- Pass 2: single `where.exe` call for everything still missing
	if #unresolved_exes > 0 then
		local where_map = batch_where_resolve(unresolved_exes)
		for idx, ci in ipairs(unresolved_indices) do
			local c = SHELL_CANDIDATES[ci]
			local resolved = where_map[c.exe:lower()]
			if resolved then
				table.insert(shells, build_shell_entry(c, resolved))
			end
		end
	end

	CACHED_SHELLS = shells
	return CACHED_SHELLS
end

function Settings.open_shell_picker(window, pane)
	local shells = Settings.detect_available_shells()
	local cur_shell = table.concat(Settings.get_shell(), " ")
	local choices = {}
	for i, sh in ipairs(shells) do
		local mark = (table.concat(sh.prog, " ") == cur_shell) and " (Active)" or ""
		table.insert(choices, {
			id = tostring(i),
			label = sh.name .. mark,
		})
	end
	table.insert(choices, { id = "CUSTOM", label = "Enter custom shell command..." })

	window:perform_action(
		act.InputSelector({
			title = "Choose Default Shell",
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end
				if id == "CUSTOM" then
					win:perform_action(
						act.PromptInputLine({
							description = "Enter shell executable / args (e.g. pwsh or nu -l):",
							action = wezterm.action_callback(function(w, pn, line)
								if line and line ~= "" then
									local parts = {}
									for word in line:gmatch("%S+") do
										table.insert(parts, word)
									end
									Settings.set_shell(parts)
								end
							end),
						}),
						p
					)
				else
					local idx = tonumber(id)
					if idx and shells[idx] then
						Settings.set_shell(shells[idx].prog)
					end
				end
			end),
		}),
		pane
	)
end

-- Opacity and Blur Submenu
function Settings.open_opacity_blur_menu(window, pane)
	local cur_opacity = Settings.get_opacity()
	local cur_backdrop = Settings.get_backdrop()

	local choices = {
		{ id = "OPAC:1.0", label = "100% Opacity (Opaque / Default)" },
		{ id = "OPAC:0.95", label = "95% Opacity" },
		{ id = "OPAC:0.90", label = "90% Opacity" },
		{ id = "OPAC:0.80", label = "80% Opacity" },
		{ id = "OPAC:0.70", label = "70% Opacity" },
		{ id = "OPAC:0.60", label = "60% Opacity" },
		{ id = "OPAC:0.50", label = "50% Opacity" },
		{ id = "OPAC:0.40", label = "40% Opacity" },
		{ id = "OPAC:0.30", label = "30% Opacity" },
		{ id = "OPAC:0.20", label = "20% Opacity" },
		{ id = "OPAC:0.10", label = "10% Opacity" },
		{ id = "OPAC:0.0", label = "0% Opacity (best with Mica / Tabbed)" },
		{ id = "OPAC:CUSTOM", label = "Custom Opacity percentage..." },
		{ id = "BLUR:Acrylic", label = "Backdrop Blur: Acrylic (Windows 11) — needs opacity < 100%" },
		{ id = "BLUR:Mica", label = "Backdrop Blur: Mica — best with 0% opacity" },
		{ id = "BLUR:Tabbed", label = "Backdrop Blur: Tabbed — best with 0% opacity" },
		{ id = "BLUR:Disable", label = "Backdrop Blur: Disabled" },
	}

	window:perform_action(
		act.InputSelector({
			title = string.format(
				"Opacity & Blur — Current: %d%%, %s. Opacity is the terminal's own layer, drawn on top of the OS blur, so lower it to actually see a backdrop.",
				math.floor(cur_opacity * 100),
				cur_backdrop
			),
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end
				if id:match("^OPAC:(.+)") then
					local val_str = id:match("^OPAC:(.+)")
					if val_str == "CUSTOM" then
						win:perform_action(
							act.PromptInputLine({
								description = "Enter opacity, 0 to 100 (0 = fully see-through terminal layer):",
								action = wezterm.action_callback(function(w, pn, line)
									local num = tonumber(line)
									if num then
										if num > 1 then
											num = num / 100
										end
										num = math.max(0.0, math.min(1.0, num))
										Settings.set_opacity(num, w)
									end
								end),
							}),
							p
						)
					else
						local num = tonumber(val_str)
						if num then
							Settings.set_opacity(num, win)
						end
					end
				elseif id:match("^BLUR:(.+)") then
					local b = id:match("^BLUR:(.+)")
					Settings.set_backdrop(b, win)
				end
			end),
		}),
		pane
	)
end

-- Font, line height, and cell width submenu
function Settings.open_font_spacing_menu(window, pane)
	local choices = {
		{
			id = "FONT",
			label = string.format("Custom Font Size (current: %gpt)...", Settings.get_font_size()),
		},
		{
			id = "LINE",
			label = string.format("Custom Line Height (current: %.1f)...", Settings.get_line_height()),
		},
		{
			id = "CELL",
			label = string.format("Custom Cell Width (current: %.1f)...", Settings.get_cell_width()),
		},
	}

	local setting_details = {
		FONT = {
			setter = Settings.set_font_size,
			description = "Enter font size in points (6-72):",
		},
		LINE = {
			setter = Settings.set_line_height,
			description = "Enter line height (0.5-3.0):",
		},
		CELL = {
			setter = Settings.set_cell_width,
			description = "Enter cell width (0.5-2.0):",
		},
	}

	window:perform_action(
		act.InputSelector({
			title = string.format(
				"Font & Spacing — %gpt / %.1f / %.1f",
				Settings.get_font_size(),
				Settings.get_line_height(),
				Settings.get_cell_width()
			),
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				local detail = id and setting_details[id]
				if not detail then
					return
				end
				win:perform_action(
					act.PromptInputLine({
						description = detail.description,
						action = wezterm.action_callback(function(w, pn, line)
							local input = line or ""
							input = input:gsub("^%s+", ""):gsub("%s+$", "")
							local number = tonumber(input)
							if number then
								if not detail.setter(number, w) then
									Settings.toast(w, "Font & Spacing", "Could not apply that value.", nil, 3000)
								end
							else
								Settings.toast(w, "Font & Spacing", "Enter a numeric value.", nil, 3000)
							end
						end),
					}),
					p
				)
			end),
		}),
		pane
	)
end

local CURSOR_STYLES = {
	{ id = "SteadyBar", label = "| Bar" },
	{ id = "SteadyUnderline", label = "_ Underline" },
	{ id = "SteadyBlock", label = "Block" },
}

local function cursor_style_label(style)
	for _, choice in ipairs(CURSOR_STYLES) do
		if choice.id == style then
			return choice.label
		end
	end
	return "| Bar"
end

function Settings.open_cursor_style_menu(window, pane)
	local current = Settings.get_cursor_style()
	local choices = {}
	for _, choice in ipairs(CURSOR_STYLES) do
		table.insert(choices, {
			id = choice.id,
			label = choice.label .. (choice.id == current and " (Active)" or ""),
		})
	end

	window:perform_action(
		act.InputSelector({
			title = "Typing Indicator",
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if id then
					Settings.set_cursor_style(id, win)
				end
			end),
		}),
		pane
	)
end

-- Renders a keybind as a plain, unenclosed string like "ALT + SHIFT + q"
-- instead of bracket-wrapped mods codes, so it reads like the physical
-- keypress rather than internal config syntax.
local function format_key_combo(item)
	if not item.key or item.key == "" then
		return "UNBOUND"
	end
	local mods = item.mods and item.mods ~= "" and item.mods:gsub("|", " + ") or ""
	if mods ~= "" then
		return mods .. " + " .. tostring(item.key)
	end
	return tostring(item.key)
end

local KEYBIND_ORDER = {
	settings_menu = 10,
	new_tab = 20,
	new_tab_cwd = 21,
	open_file_manager = 22,
	close_tab = 30,
	close_pane = 31,
	split_horizontal = 40,
	split_vertical = 41,
	split_full_right = 42,
	split_full_down = 43,
	auto_split = 50,
	auto_split_cwd = 51,
	zoom_pane = 60,
	fullscreen = 61,
	prev_tab = 70,
	next_tab = 71,
	move_tab_prev = 72,
	move_tab_next = 73,
	copy = 80,
	font_increase = 90,
	font_decrease = 91,
	command_palette = 100,
	open_admin_terminal = 110,
}

local NAVIGATION_DIRECTIONS = {
	{ id = "left", label = "Left" },
	{ id = "down", label = "Down" },
	{ id = "up", label = "Up" },
	{ id = "right", label = "Right" },
}

local function canonical_mods(mods)
	local order = { CTRL = 1, ALT = 2, SHIFT = 3, SUPER = 4 }
	local found = {}
	for part in tostring(mods or ""):gmatch("[^|%s]+") do
		part = part:upper()
		if part == "WIN" then
			part = "SUPER"
		end
		if not order[part] then
			return nil
		end
		found[part] = true
	end
	local mods_list = {}
	for part in pairs(found) do
		table.insert(mods_list, part)
	end
	table.sort(mods_list, function(a, b)
		return order[a] < order[b]
	end)
	return table.concat(mods_list, "|")
end

local NAMED_KEYS = {
	Backspace = true,
	CapsLock = true,
	Delete = true,
	DownArrow = true,
	End = true,
	Enter = true,
	Escape = true,
	Home = true,
	Insert = true,
	LeftArrow = true,
	Menu = true,
	PageDown = true,
	PageUp = true,
	Pause = true,
	PrintScreen = true,
	RightArrow = true,
	ScrollLock = true,
	Space = true,
	Tab = true,
	UpArrow = true,
}

local function valid_key_name(key)
	if #key == 1 or NAMED_KEYS[key] then
		return true
	end
	local function_key = key:match("^F(%d+)$")
	return function_key ~= nil and tonumber(function_key) >= 1 and tonumber(function_key) <= 24
end

local function canonical_combo(entry)
	if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" or entry.key:find("%s") then
		return nil
	end
	if not valid_key_name(entry.key) then
		return nil
	end
	local mods = canonical_mods(entry.mods)
	if not mods then
		return nil
	end
	return mods .. "|" .. normalize_key_string(entry.key):lower()
end

local function navigation_keybind_entries(navigation)
	local entries = {}
	for _, direction in ipairs(NAVIGATION_DIRECTIONS) do
		local binding = navigation[direction.id]
		table.insert(entries, {
			id = "pane_navigation_" .. direction.id,
			desc = "Pane Navigation " .. direction.label,
			key = binding.key,
			mods = binding.mods,
		})
	end
	return entries
end

local function fixed_keybind_entries()
	local entries = {}
	for index = 1, 9 do
		table.insert(entries, {
			id = "tab_" .. index,
			desc = "Jump to Tab " .. index,
			key = tostring(index),
			mods = "CTRL",
		})
	end
	table.insert(entries, {
		id = "edit_paste",
		desc = "Paste into Microsoft Edit with Ctrl+V",
		key = "v",
		mods = "CTRL",
	})
	for _, direction in ipairs({ "LeftArrow", "DownArrow", "UpArrow", "RightArrow" }) do
		table.insert(entries, {
			id = "resize_" .. direction,
			desc = "Resize Pane " .. direction,
			key = direction,
			mods = "SHIFT|ALT",
		})
	end
	return entries
end

local function find_combo_conflict(candidate, entries, ignored_id)
	local candidate_combo = canonical_combo(candidate)
	if not candidate_combo then
		return "Invalid keybind. Enter one key without spaces and use a supported modifier."
	end
	for _, existing in ipairs(entries) do
		if existing.id ~= ignored_id and canonical_combo(existing) == candidate_combo then
			return string.format(
				"%s overlaps with %s (%s).",
				format_key_combo(candidate),
				existing.desc or existing.id,
				format_key_combo(existing)
			)
		end
	end
	return nil
end

local function validate_navigation(navigation, keybinds)
	local entries = fixed_keybind_entries()
	for id, item in pairs(keybinds) do
		table.insert(entries, {
			id = id,
			desc = item.desc or id,
			key = item.key,
			mods = item.mods,
		})
	end
	for _, candidate in ipairs(navigation_keybind_entries(navigation)) do
		local conflict = find_combo_conflict(candidate, entries)
		if conflict then
			return conflict
		end
		table.insert(entries, candidate)
	end
	return nil
end

local function error_choice(message)
	return wezterm.format({
		{ Foreground = { Color = "#f38ba8" } },
		{ Text = "ERROR: " .. message },
	})
end

local function pane_navigation_label(navigation)
	if navigation.mode == "hjkl" then
		return "Pane Navigation: ALT + HJKL"
	elseif navigation.mode == "custom" then
		return "Pane Navigation: Custom"
	end
	return "Pane Navigation: ALT + Arrow Keys"
end

local NAVIGATION_MODIFIERS = {
	{ id = "ALT", label = "ALT" },
	{ id = "CTRL", label = "CTRL" },
	{ id = "SHIFT|ALT", label = "SHIFT + ALT" },
	{ id = "CTRL|SHIFT", label = "CTRL + SHIFT" },
	{ id = "CTRL|ALT", label = "CTRL + ALT" },
	{ id = "", label = "None" },
}

local function open_custom_navigation_step(window, pane, index, bindings)
	if index > #NAVIGATION_DIRECTIONS then
		local navigation = { mode = "custom" }
		for _, direction in ipairs(NAVIGATION_DIRECTIONS) do
			navigation[direction.id] = bindings[direction.id]
		end
		local conflict = validate_navigation(navigation, Settings.load_keybinds())
		if conflict then
			Settings.open_keybinds_menu(window, pane, conflict)
		else
			Settings.set_pane_navigation(navigation)
		end
		return
	end

	local direction = NAVIGATION_DIRECTIONS[index]
	window:perform_action(
		act.InputSelector({
			title = string.format("Custom Pane Navigation (%d/%d): %s", index, #NAVIGATION_DIRECTIONS, direction.label),
			choices = NAVIGATION_MODIFIERS,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, mod_id, mod_label)
				if mod_id == nil then
					return
				end
				win:perform_action(
					act.PromptInputLine({
						description = "Enter one key for " .. direction.label .. " pane navigation:",
						action = wezterm.action_callback(function(w, pn, key_name)
							local key = key_name or ""
							key = key:gsub("^%s+", ""):gsub("%s+$", "")
							bindings[direction.id] = { key = normalize_key_string(key), mods = mod_id }
							open_custom_navigation_step(w, pn, index + 1, bindings)
						end),
					}),
					p
				)
			end),
		}),
		pane
	)
end

function Settings.open_pane_navigation_menu(window, pane)
	local choices = {
		{ id = "NAV:arrows", label = "ALT + Arrow Keys" },
		{ id = "NAV:hjkl", label = "ALT + HJKL" },
		{ id = "NAV:custom", label = "Custom (configure each direction)..." },
	}

	window:perform_action(
		act.InputSelector({
			title = "Choose Pane Navigation",
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end
				local mode = id:match("^NAV:(.+)$")
				if mode == "custom" then
					open_custom_navigation_step(win, p, 1, {})
					return
				end
				local navigation = navigation_preset(mode)
				local conflict = validate_navigation(navigation, Settings.load_keybinds())
				if conflict then
					Settings.open_keybinds_menu(win, p, conflict)
				else
					Settings.set_pane_navigation(navigation)
				end
			end),
		}),
		pane
	)
end

-- Keybind Customization & Recording
function Settings.open_keybinds_menu(window, pane, error_message)
	local kb = Settings.load_keybinds()
	local navigation = Settings.get_pane_navigation()
	local choices = {}
	local max_desc = 0
	for _, item in pairs(kb) do
		local desc = item.desc or ""
		if #desc > max_desc then
			max_desc = #desc
		end
	end

	for id, item in pairs(kb) do
		local desc = item.desc or id
		local combo = format_key_combo(item)
		local pad = string.rep(" ", max_desc - #desc + 4)
		table.insert(choices, {
			id = id,
			label = "  " .. desc .. pad .. "| " .. combo,
		})
	end

	table.sort(choices, function(a, b)
		local a_order = KEYBIND_ORDER[a.id] or math.huge
		local b_order = KEYBIND_ORDER[b.id] or math.huge
		if a_order ~= b_order then
			return a_order < b_order
		end
		return a.label < b.label
	end)
	table.insert(choices, 1, { id = "RESET_ALL", label = "Reset All Keybinds to Defaults" })
	table.insert(choices, 1, { id = "PANE_NAVIGATION", label = pane_navigation_label(navigation) })
	if error_message then
		table.insert(choices, 1, { id = "KEYBIND_ERROR", label = error_choice(error_message) })
	end

	window:perform_action(
		act.InputSelector({
			title = "Customize Keybindings",
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end
				if id == "KEYBIND_ERROR" then
					return
				elseif id == "PANE_NAVIGATION" then
					Settings.open_pane_navigation_menu(win, p)
				elseif id == "RESET_ALL" then
					Settings.save_keybinds(DEFAULT_KEYBINDS)
					Settings.toast(win, "Keybindings", "Keybindings reset to defaults!", nil, 3000)
					Settings.set_pane_navigation(navigation_preset("arrows"))
				else
					Settings.record_key_press(win, p, id, kb[id] and kb[id].desc or id)
				end
			end),
		}),
		pane
	)
end

local function save_recorded_keybind(window, pane, action_id, desc, key, mods)
	local candidate = { key = normalize_key_string(key or ""), mods = mods or "" }
	local kb = Settings.load_keybinds()
	if candidate.key == "" then
		if action_id == "settings_menu" then
			Settings.open_keybinds_menu(window, pane, "The Settings Hub shortcut cannot be unbound.")
			return
		end
		kb[action_id] = { key = "", mods = "", desc = desc }
		Settings.save_keybinds(kb)
		Settings.toast(window, "Keybind Updated", desc .. " is now unbound.", nil, 4000)
		return
	end

	local entries = fixed_keybind_entries()
	for id, item in pairs(kb) do
		if id ~= action_id then
			table.insert(entries, {
				id = id,
				desc = item.desc or id,
				key = item.key,
				mods = item.mods,
			})
		end
	end
	for _, navigation_entry in ipairs(navigation_keybind_entries(Settings.get_pane_navigation())) do
		table.insert(entries, navigation_entry)
	end

	local conflict = find_combo_conflict(candidate, entries)
	if conflict then
		Settings.open_keybinds_menu(window, pane, conflict)
		return
	end

	kb[action_id] = { key = candidate.key, mods = candidate.mods, desc = desc }
	Settings.save_keybinds(kb)
	Settings.toast(
		window,
		"Keybind Updated",
		string.format("%s set to: %s", desc, format_key_combo(candidate)),
		nil,
		4000
	)
end

local function parse_unmodified_key(input)
	if input == "" then
		return ""
	end
	local number = input:match("^(%d+)$") or input:match("^[fF](%d%d?)$")
	local value = number and tonumber(number)
	if value and value >= 1 and value <= 12 then
		return "F" .. value
	end
	return nil
end

function Settings.record_key_press(window, pane, action_id, desc)
	local mod_choices = {
		{ id = "ALT", label = "ALT" },
		{ id = "CTRL", label = "CTRL" },
		{ id = "SHIFT|ALT", label = "SHIFT + ALT" },
		{ id = "CTRL|SHIFT", label = "CTRL + SHIFT" },
		{ id = "CTRL|ALT", label = "CTRL + ALT" },
		{ id = "", label = "None (F1-F12 or Unbind)" },
	}

	window:perform_action(
		act.InputSelector({
			title = "Step 1: Choose Modifier for " .. desc,
			choices = mod_choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, mod_id, mod_label)
				if mod_id == nil then
					return
				end
				if mod_id == "" then
					win:perform_action(
						act.PromptInputLine({
							description = "Type F1-F12 or 1-12; press Enter empty to unbind:",
							action = wezterm.action_callback(function(w, pn, key_name)
								if key_name == nil then
									return
								end
								local key = key_name:gsub("^%s+", ""):gsub("%s+$", "")
								local normalized = parse_unmodified_key(key)
								if normalized == nil then
									Settings.open_keybinds_menu(
										w,
										pn,
										"Invalid unmodified key. Use 1-12, F1-F12, or leave it empty to unbind."
									)
									return
								end
								save_recorded_keybind(w, pn, action_id, desc, normalized, "")
							end),
						}),
						p
					)
					return
				end

				win:perform_action(
					act.PromptInputLine({
						description = string.format("Step 2: Press/Type Key name for %s + ...:", mod_id),
						action = wezterm.action_callback(function(w, pn, key_name)
							local key = key_name or ""
							key = key:gsub("^%s+", ""):gsub("%s+$", "")
							if key == "" then
								Settings.open_keybinds_menu(w, pn, "A modified keybind must include a key.")
								return
							end
							save_recorded_keybind(w, pn, action_id, desc, key, mod_id)
						end),
					}),
					p
				)
			end),
		}),
		pane
	)
end

-- Custom Window Size Prompt
function Settings.open_window_size_prompt(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter window size: 'max' / 'maximized' or '<cols>x<rows>' (e.g. 120x35):",
			action = wezterm.action_callback(function(win, p, line)
				if not line or line == "" then
					return
				end
				line = line:gsub("^%s+", ""):gsub("%s+$", "")
				if line:lower():match("^max") then
					Settings.set_window_size({ type = "maximized" }, win, p)
				else
					local cols, rows = line:match("(%d+)[%s*xX,]%s*(%d+)")
					if cols and rows then
						Settings.set_window_size({
							type = "custom",
							cols = tonumber(cols),
							rows = tonumber(rows),
						}, win, p)
					end
				end
			end),
		}),
		pane
	)
end

-- Theme Picker
function Settings.open_theme_picker(window, pane)
	local themes = Settings.load_themes()
	local choices = {}
	for name, _ in pairs(themes) do
		table.insert(choices, { label = name, id = name })
	end
	table.sort(choices, function(a, b)
		return a.label < b.label
	end)

	window:perform_action(
		act.InputSelector({
			title = "Choose Color Theme",
			choices = choices,
			fuzzy = true,
			action = wezterm.action_callback(function(win, p, id, label)
				if id then
					Settings.set_theme(id, win)
				end
			end),
		}),
		pane
	)
end

function Settings.open_toast_notifications_menu(window, pane)
	local enabled = Settings.get_toast_notifications()
	local choices = {
		{ id = "ON", label = "Enable Toast Notifications" .. (enabled and " (Active)" or "") },
		{ id = "OFF", label = "Disable Toast Notifications" .. (not enabled and " (Active)" or "") },
	}

	window:perform_action(
		act.InputSelector({
			title = "Toast Notifications",
			choices = choices,
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if id == "ON" then
					Settings.set_toast_notifications(true)
				elseif id == "OFF" then
					Settings.set_toast_notifications(false)
				end
			end),
		}),
		pane
	)
end

-- Unified Settings Menu
function Settings.open_settings_menu(window, pane)
	local cur_theme = Settings.get_theme()
	local cur_cwd = Settings.get_cwd() or ("Default (~" .. wezterm.home_dir .. ")")
	local cur_size = Settings.get_window_size()
	local cur_shell = table.concat(Settings.get_shell(), " ")
	local cur_opacity = Settings.get_opacity()
	local cur_font_size = Settings.get_font_size()
	local cur_line_height = Settings.get_line_height()
	local cur_cell_width = Settings.get_cell_width()
	local cur_cursor_style = Settings.get_cursor_style()
	local cur_toasts = Settings.get_toast_notifications()

	local size_label = "Maximized"
	if cur_size.type == "custom" and cur_size.cols and cur_size.rows then
		size_label = string.format("%dx%d cells", cur_size.cols, cur_size.rows)
	end

	window:perform_action(
		act.InputSelector({
			title = "WezTerm Settings",
			choices = {
				{ id = "theme", label = "Color Theme: " .. cur_theme },
				{ id = "window_size", label = "Window Size: " .. size_label },
				{ id = "default_cwd", label = "Default Directory: " .. cur_cwd },
				{ id = "shell", label = "Default Shell: " .. cur_shell },
				{ id = "opacity_blur", label = "Opacity & Blur: " .. math.floor(cur_opacity * 100) .. "%" },
				{ id = "font_spacing", label = string.format("Font & Spacing: %gpt / %.1f / %.1f", cur_font_size, cur_line_height, cur_cell_width) },
				{ id = "cursor_style", label = "Typing Indicator: " .. cursor_style_label(cur_cursor_style) },
				{ id = "keybinds", label = "Keybindings: Configure" },
				{ id = "toast_notifications", label = "Toast Notifications: " .. (cur_toasts and "On" or "Off") },
			},
			fuzzy = false,
			action = wezterm.action_callback(function(win, p, id, label)
				if id == "theme" then
					Settings.open_theme_picker(win, p)
				elseif id == "window_size" then
					Settings.open_window_size_prompt(win, p)
				elseif id == "default_cwd" then
					Settings.browse_directory(win, p)
				elseif id == "shell" then
					Settings.open_shell_picker(win, p)
				elseif id == "opacity_blur" then
					Settings.open_opacity_blur_menu(win, p)
				elseif id == "font_spacing" then
					Settings.open_font_spacing_menu(win, p)
				elseif id == "cursor_style" then
					Settings.open_cursor_style_menu(win, p)
				elseif id == "keybinds" then
					Settings.open_keybinds_menu(win, p)
				elseif id == "toast_notifications" then
					Settings.open_toast_notifications_menu(win, p)
				end
			end),
		}),
		pane
	)
end

return Settings
