local wezterm = require("wezterm")
local theme = require("theme")

local Tab = {}

local PROCESS_LABELS = {
	cmd = "CMD",
	powershell = "PS",
	pwsh = "PS",
	bash = "SH",
	zsh = "SH",
	fish = "SH",
	nu = "NU",
	wsl = "WSL",
	nvim = "NVIM",
	vim = "VIM",
}

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function detect_privilege_status()
	if wezterm.target_triple:find("windows") then
		local windir = os.getenv("SystemRoot") or os.getenv("WINDIR") or "C:\\Windows"
		local probe_path = windir .. "\\System32\\wezterm_admin_probe_" .. tostring(os.time()) .. ".tmp"

		local f = io.open(probe_path, "w")
		if f then
			f:close()
			os.remove(probe_path)
			return "ADMIN"
		end

		return "STANDARD"
	end

	local ok, success, stdout = pcall(wezterm.run_child_process, { "id", "-u" })
	if ok and success and stdout then
		return stdout:match("^%s*0%s*$") and "ROOT" or "STANDARD"
	end

	return "UNKNOWN"
end

local PRIVILEGE_STATUS = detect_privilege_status()

local function basename(value)
	local name = tostring(value or ""):gsub("\\", "/"):match("[^/]+$") or ""
	return name:gsub("%.exe$", "")
end

function Tab.setup(config)
	config.use_fancy_tab_bar = false
	config.tab_max_width = 32
	config.status_update_interval = 1000

	wezterm.on("update-status", function(window)
		local accents = theme.accents or {}
		local color = accents.gray or "#808080"
		if PRIVILEGE_STATUS == "ADMIN" or PRIVILEGE_STATUS == "ROOT" then
			color = accents.red or "#ff5555"
		elseif PRIVILEGE_STATUS == "STANDARD" then
			color = accents.green or "#50fa7b"
		end
		window:set_right_status(wezterm.format({
			{ Foreground = { Color = color } },
			{ Text = " PRIV: " .. PRIVILEGE_STATUS .. " " },
		}))
	end)

	wezterm.on("format-tab-title", function(tab, tabs, panes, tab_config, hover, max_width)
		local pane = tab.active_pane or {}
		local process = basename(pane.foreground_process_name)
		local process_label = PROCESS_LABELS[process:lower()] or process
		local title = tostring(pane.title or process_label or "Shell")
		local zoom = pane.is_zoomed and " [Z]" or ""
		local label = string.format(" %d %s %s%s ", tab.tab_index + 1, process_label, title, zoom)

		if max_width and #label > max_width then
			local limit = math.max(1, max_width - 3)
			label = label:sub(1, limit) .. "..."
		end

		return { { Text = label } }
	end)
end

return Tab
