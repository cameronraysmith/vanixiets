local wezterm = require("wezterm")

return {
	font = wezterm.font("Monaspace Neon Nerd Font"),
	color_scheme = "Catppuccin Mocha",
	window_decorations = "RESIZE",
	font_size = 14,
	line_height = 1.1,
	hide_tab_bar_if_only_one_tab = true,
	keys = {
		-- Emulate other programs (Zed, VSCode, ...)
		{
			key = "P",
			mods = "CTRL|SHIFT",
			action = wezterm.action.ActivateCommandPalette,
		},
	},
	-- Workaround for https://github.com/NixOS/nixpkgs/issues/336069#issuecomment-2299008280
	-- front_end = "WebGpu"
}
