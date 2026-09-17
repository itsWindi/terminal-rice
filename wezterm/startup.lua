local wezterm = require("wezterm")
local mux = wezterm.mux
local settings = require("settings")

local Startup = {}

function Startup.setup(config)
	local cwd = settings.get_cwd()
	if cwd and cwd ~= "" then
		config.default_cwd = cwd
	end

	local size = settings.get_window_size()
	if size.type == "maximized" then
		wezterm.on("gui-startup", function(cmd)
			local _, _, window = mux.spawn_window(cmd or {})
			if window then
				pcall(function()
					window:gui_window():maximize()
				end)
			end
		end)
	elseif size.type == "custom" and size.cols and size.rows then
		config.initial_cols = size.cols
		config.initial_rows = size.rows
	end
end

return Startup
