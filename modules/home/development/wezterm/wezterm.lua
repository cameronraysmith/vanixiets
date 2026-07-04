local wezterm = require("wezterm")

return {
	font = wezterm.font("MonaspiceNe Nerd Font"),
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
		-- Emit Alt/Meta+Enter (ESC+CR) so multiline TUI inputs such as Claude Code treat Shift+Enter as a soft newline rather than submit.
		{
			key = "Enter",
			mods = "SHIFT",
			action = wezterm.action.SendString("\x1b\r"),
		},
	},
	-- Workaround for https://github.com/NixOS/nixpkgs/issues/336069#issuecomment-2299008280
	-- front_end = "WebGpu"
}
