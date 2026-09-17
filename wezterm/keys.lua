local wezterm = require("wezterm")
local act = wezterm.action
local settings = require("settings")

local Keys = {}

-- Detects whether the active pane is running (n)vim
local function is_vi_process(pane)
	local ok, process = pcall(function()
		return pane and pane:get_foreground_process_name() or ""
	end)
	if not ok or type(process) ~= "string" then
		return false
	end
	return process:lower():find("n?vim", 1, false) ~= nil
end

-- Extracts real filesystem path from active pane for CWD inheritance.
--
-- Modern WezTerm (20240127+) returns a parsed Url object here, and
-- `.file_path` already gives back a clean, decoded path -- that branch just
-- works. Older WezTerm versions return a raw URI string instead, of the
-- form "file://HOSTNAME/C:/Users/name" (note: a *hostname*, not a third
-- slash). The previous implementation only recognised the host-less
-- "file:///C:/..." shape, so on an older build it would leave the hostname
-- stuck onto the front of the path -- producing a bogus, non-existent
-- directory and silently falling back to the default (home) directory,
-- which is exactly the "always opens at home" symptom this fixes.
--
-- A leading "/" in front of a drive letter is a URL-path artifact, not part
-- of a real Windows path -- e.g. "/E:/" should be "E:/". If it survives,
-- launch_default_file_manager's later "/" -> "\\" conversion turns it into
-- "\E:\", which is exactly the invalid path Windows complains about
-- ("Windows cannot find '\E:\'"). The old code only stripped this in the
-- legacy string-URI branch below, on the assumption that the modern
-- Url-object's `.file_path` always comes back already clean. In practice
-- `.file_path` can still return "/E:/" for the *root* of a drive (e.g.
-- `cd E:\`), so this cleanup now runs unconditionally on whatever path we
-- end up with, regardless of which branch produced it.
local function strip_leading_drive_slash(path)
	if type(path) ~= "string" then
		return path
	end
	return (path:gsub("^/(%a:)", "%1"))
end

local function get_pane_cwd(pane)
	if not pane then
		return nil
	end
	local ok, cwd_uri = pcall(function()
		return pane:get_current_working_dir()
	end)
	if not ok or not cwd_uri then
		return nil
	end
	-- Url objects are normally userdata, but using a protected field read also
	-- handles builds that expose the object as a table.
	local has_file_path, file_path = pcall(function()
		return cwd_uri.file_path
	end)
	if has_file_path and type(file_path) == "string" and file_path ~= "" then
		return strip_leading_drive_slash(file_path)
	elseif type(cwd_uri) == "string" then
		-- Strip "scheme://host" (host may be empty), leaving a path that
		-- starts with "/". e.g. "file://DESKTOP-ABC/C:/Users/x" -> "/C:/Users/x"
		-- and "file:///C:/Users/x" -> "/C:/Users/x".
		local path = cwd_uri:gsub("^%a[%w+.-]*://[^/]*", "")
		path = strip_leading_drive_slash(path)
		path = path:gsub("%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16))
		end)
		if path == "" then
			return nil
		end
		return path
	end
	return nil
end

local function powershell_literal(value)
	return "'" .. tostring(value):gsub("'", "''") .. "'"
end

local function resolve_gui_executable()
	local dir
	if type(wezterm.executable_path) == "string" and wezterm.executable_path ~= "" then
		dir = wezterm.executable_path:match("^(.*)[\\/][^\\/]+$")
	end
	if not dir and type(wezterm.executable_dir) == "string" and wezterm.executable_dir ~= "" then
		dir = wezterm.executable_dir
	end
	if dir then
		return dir .. "\\wezterm-gui.exe"
	end
	return "wezterm-gui.exe" -- last resort, relies on PATH
end

local function open_admin_terminal(win, pane)
	local cwd = get_pane_cwd(pane) or settings.get_cwd() or wezterm.home_dir
	cwd = tostring(cwd):gsub("/", "\\")
	-- Start-Process joins ArgumentList items into one command line. Keep the
	-- explicit --cwd value quoted, and use forward slashes so a drive-root
	-- path cannot consume its closing quote as a trailing backslash.
	local cwd_argument = cwd:gsub("\\", "/")

	local executable = resolve_gui_executable()

	local command = string.format(
		"$cwd=%s; $exe=%s; $cwd_arg=%s; $arguments=@('start','--always-new-process','--cwd',$cwd_arg); "
			.. "Start-Process -FilePath $exe -Verb RunAs -WorkingDirectory $cwd -ArgumentList $arguments",
		powershell_literal(cwd),
		powershell_literal(executable),
		powershell_literal('"' .. cwd_argument .. '"')
	)
	local args = { "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", command }
	local ok, launched = pcall(function()
		if type(wezterm.background_child_process) == "function" then
			wezterm.background_child_process(args)
			return true
		end
		return wezterm.run_child_process(args)
	end)
	if not ok or not launched then
		settings.toast(win, "Administrator Terminal", "Could not start the elevated terminal.", nil, 5000)
	end
end

-- Arrow key name -> WezTerm pane direction name
local direction_for_key = {
	LeftArrow = "Left",
	DownArrow = "Down",
	UpArrow = "Up",
	RightArrow = "Right",
}

local function pane_nav(kind, key, mods, direction)
	local binding_mods = mods or (kind == "resize" and "SHIFT|ALT" or "ALT")
	local pane_direction = direction or direction_for_key[key]
	return {
		key = key,
		mods = binding_mods,
		action = wezterm.action_callback(function(win, pane)
			if is_vi_process(pane) then
				win:perform_action({
					SendKey = { key = key, mods = binding_mods },
				}, pane)
			else
				if kind == "resize" then
					win:perform_action({ AdjustPaneSize = { pane_direction, 3 } }, pane)
				else
					win:perform_action({ ActivatePaneDirection = pane_direction }, pane)
				end
			end
		end),
	}
end

-- Ctrl+C: smart copy or interrupt
local function smart_copy_or_interrupt(win, pane)
	local has_selection = win:get_selection_text_for_pane(pane) ~= ""
	if has_selection then
		win:perform_action(act.CopyTo("Clipboard"), pane)
		win:perform_action(act.ClearSelection, pane)
	else
		win:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
	end
end

-- Hyprland dwindle auto-split.
--
-- Both Alt+P and Alt+Shift+P go through the same direction logic and
-- differ only in CWD handling. With OSC 7 active, the pane domain
-- already knows the current working directory, so:
--   inherit_cwd = true  → don't set command (domain inherits CWD)
--   inherit_cwd = false → set explicit default CWD to prevent inheritance
local function auto_tile_split(win, pane, inherit_cwd)
	local dims = pane:get_dimensions()
	local width, height

	if dims.pixel_width and dims.pixel_width > 0 and dims.pixel_height and dims.pixel_height > 0 then
		width = dims.pixel_width
		height = dims.pixel_height
	else
		width = dims.cols * 10
		height = dims.viewport_rows * 22
	end

	local split_args = {
		direction = (width >= height) and "Right" or "Down",
		size = { Percent = 50 },
	}

	if not inherit_cwd then
		-- Explicitly set default directory so the split doesn't inherit
		-- the current pane's CWD from OSC 7.
		local cwd = settings.get_cwd() or wezterm.home_dir
		split_args.command = { cwd = cwd }
	end
	-- When inherit_cwd is true, we leave command unset — SplitPane
	-- inherits CWD from the current pane domain (OSC 7 provides it).

	win:perform_action(act.SplitPane(split_args), pane)
end

local function adjust_font_size(win, pane, delta)
	-- settings.get_font_size() reads the in-memory cache, which
	-- Settings.set_font_size() updates synchronously on every call -- so
	-- it's always accurate even while the actual visual apply is being
	-- throttled during a fast burst of keypresses (see settings.lua). The
	-- window's live config override is *not* used here anymore: it can
	-- briefly lag behind the cache during that throttle window, which
	-- would make rapid repeated presses fail to accumulate correctly.
	local current = settings.get_font_size()
	local value = current + delta
	value = math.max(6, math.min(72, value))
	if value == current then
		return
	end
	if not settings.set_font_size(value, win) then
		settings.toast(win, "Font Size", "Could not apply the new font size.", nil, 4000)
	end
end

local function launch_default_file_manager(path)
	local target = tostring(wezterm.target_triple or ""):lower()
	local function spawn_default(args)
		if type(wezterm.background_child_process) == "function" then
			return pcall(wezterm.background_child_process, args)
		end
		return pcall(wezterm.open_with, path)
	end
	if target:find("windows", 1, true) then
		local win_path = path:gsub("/", "\\")
		-- Belt-and-suspenders: drop a stray leading separator in front of a
		-- drive letter (see strip_leading_drive_slash above for why this can
		-- happen) so we never hand `start` something like "\E:\".
		win_path = win_path:gsub("^\\(%a:)", "%1")
		-- Drive roots need special-casing: handing `start` a bare drive
		-- root like "E:\" (or "E:") can open "This PC" (the all-drives
		-- view) instead of drilling into that drive -- a long-standing
		-- ShellExecute/Explorer quirk that some registered default file
		-- managers, File Pilot included, inherit. Appending "\." makes the
		-- path unambiguously "this exact folder" rather than "this drive
		-- as an entry under This PC", and reliably opens the drive itself.
		local drive_only = win_path:match("^(%a:)\\?$")
		if drive_only then
			win_path = drive_only .. "\\."
		end
		-- `start` delegates folder handling to Windows, so File Pilot or any
		-- other registered default file manager can handle the directory.
		return spawn_default({
			"cmd.exe",
			"/d",
			"/c",
			"start",
			"",
			win_path,
		})
	elseif target:find("darwin", 1, true) then
		return spawn_default({ "open", path })
	elseif target:find("linux", 1, true) then
		return spawn_default({ "xdg-open", path })
	end
	return pcall(wezterm.open_with, path)
end

local function open_file_manager(win, pane)
	local cwd = get_pane_cwd(pane)
	local used_fallback = false
	if not cwd or cwd == "" then
		cwd = settings.get_cwd() or wezterm.home_dir
		used_fallback = true
	end

	-- Let the operating system choose the registered file manager. This keeps
	-- the shortcut compatible with File Pilot and other default-folder handlers.
	local ok = launch_default_file_manager(cwd)
	if not ok then
		settings.toast(win, "File Manager", "Could not open the active directory.", nil, 4000)
	elseif used_fallback then
		settings.toast(win, "File Manager", "Active pane CWD unavailable; opened the configured default directory.", nil, 4000)
	end
end

function Keys.setup(config)
	config.disable_default_key_bindings = true

	local kb = settings.load_keybinds()
	local navigation = settings.get_pane_navigation()

	local action_map = {
		settings_menu = wezterm.action_callback(settings.open_settings_menu),
		auto_split = wezterm.action_callback(function(win, pane)
			auto_tile_split(win, pane, false)
		end),
		auto_split_cwd = wezterm.action_callback(function(win, pane)
			auto_tile_split(win, pane, true)
		end),
		split_horizontal = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
		split_vertical = act.SplitVertical({ domain = "CurrentPaneDomain" }),
		split_full_right = act.SplitPane({ top_level = true, direction = "Right", size = { Percent = 50 } }),
		split_full_down = act.SplitPane({ top_level = true, direction = "Down", size = { Percent = 50 } }),
		-- Ctrl+T: new tab in the configured default directory (NOT inherited CWD)
		new_tab = wezterm.action_callback(function(win, pane)
			local cwd = settings.get_cwd() or wezterm.home_dir
			win:perform_action(act.SpawnCommandInNewTab({ cwd = cwd }), pane)
		end),
		-- Ctrl+Shift+T: new tab inheriting the current pane's CWD.
		-- OSC 7 tells the domain what the CWD is, so CurrentPaneDomain
		-- inherits it automatically — no manual get_pane_cwd() needed.
		new_tab_cwd = act.SpawnTab("CurrentPaneDomain"),
		open_file_manager = wezterm.action_callback(open_file_manager),
		open_admin_terminal = wezterm.action_callback(open_admin_terminal),
		close_tab = act.CloseCurrentTab({ confirm = false }),
		close_pane = act.CloseCurrentPane({ confirm = false }),
		zoom_pane = act.TogglePaneZoomState,
		fullscreen = act.ToggleFullScreen,
		prev_tab = act.ActivateTabRelative(-1),
		next_tab = act.ActivateTabRelative(1),
		move_tab_prev = act.MoveTabRelative(-1),
		move_tab_next = act.MoveTabRelative(1),
		copy = wezterm.action_callback(smart_copy_or_interrupt),
		font_increase = wezterm.action_callback(function(win, pane)
			adjust_font_size(win, pane, 1)
		end),
		font_decrease = wezterm.action_callback(function(win, pane)
			adjust_font_size(win, pane, -1)
		end),
		command_palette = act.ActivateCommandPalette,
	}

	local key_list = {
		-- Pane navigation (configurable, vi-aware)
		pane_nav("move", navigation.left.key, navigation.left.mods, "Left"),
		pane_nav("move", navigation.down.key, navigation.down.mods, "Down"),
		pane_nav("move", navigation.up.key, navigation.up.mods, "Up"),
		pane_nav("move", navigation.right.key, navigation.right.mods, "Right"),
		pane_nav("resize", "LeftArrow"),
		pane_nav("resize", "DownArrow"),
		pane_nav("resize", "UpArrow"),
		pane_nav("resize", "RightArrow"),

		-- Direct Tab Switching 1-9
		{ key = "1", mods = "CTRL", action = act.ActivateTab(0) },
		{ key = "2", mods = "CTRL", action = act.ActivateTab(1) },
		{ key = "3", mods = "CTRL", action = act.ActivateTab(2) },
		{ key = "4", mods = "CTRL", action = act.ActivateTab(3) },
		{ key = "5", mods = "CTRL", action = act.ActivateTab(4) },
		{ key = "6", mods = "CTRL", action = act.ActivateTab(5) },
		{ key = "7", mods = "CTRL", action = act.ActivateTab(6) },
		{ key = "8", mods = "CTRL", action = act.ActivateTab(7) },
		{ key = "9", mods = "CTRL", action = act.ActivateTab(8) },
		{ key = "v", mods = "CTRL", action = act.PasteFrom("Clipboard") },
	}

	-- Dynamically register configurable actions from keybinds.json
	for id, entry in pairs(kb) do
		if action_map[id] and entry.key and entry.key ~= "" then
			table.insert(key_list, {
				key = entry.key,
				mods = entry.mods or "",
				action = action_map[id],
			})
		end
	end

	-- Windows reports a letter as uppercase while Caps Lock is active. Keep
	-- Close Pane usable in that state without changing the displayed shortcut.
	local close_pane = kb.close_pane
	if close_pane
		and type(close_pane.key) == "string"
		and close_pane.key:match("^[a-z]$")
		and tostring(close_pane.mods or ""):find("CTRL", 1, true)
		and not tostring(close_pane.mods or ""):find("SHIFT", 1, true) then
		table.insert(key_list, {
			key = close_pane.key:upper(),
			mods = close_pane.mods or "",
			action = action_map.close_pane,
		})
	end

	config.keys = key_list
end

return Keys
