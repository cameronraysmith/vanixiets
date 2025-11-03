#!/usr/bin/env nu

# Format atuin history with beautiful table output showing command, time, directory, and duration
#
# This script pipes atuin history list output through nushell's table formatter
# to create a visually appealing display similar to the TUI interface.

# Catppuccin Mocha color palette
const CATPPUCCIN_MOCHA = {
  rosewater: "#f5e0dc"
  flamingo: "#f2cdcd"
  pink: "#f5c2e7"
  mauve: "#cba6f7"
  red: "#f38ba8"
  maroon: "#eba0ac"
  peach: "#fab387"
  yellow: "#f9e2af"
  green: "#a6e3a1"
  teal: "#94e2d5"
  sky: "#89dceb"
  sapphire: "#74c7ec"
  blue: "#89b4fa"
  lavender: "#b4befe"
  text: "#cdd6f4"
  subtext1: "#bac2de"
  subtext0: "#a6adc8"
  overlay2: "#9399b2"
  overlay1: "#7f849c"
  overlay0: "#6c7086"
  surface2: "#585b70"
  surface1: "#45475a"
  surface0: "#313244"
  base: "#1e1e2e"
  mantle: "#181825"
  crust: "#11111b"
}

# Colorize a value with Catppuccin Mocha colors
def colorize [value: string, color: string, --bold (-b)] {
    let color_code = if $bold {
        $"(ansi { fg: $color attr: b })"
    } else {
        $"(ansi { fg: $color })"
    }
    $"($color_code)($value)(ansi reset)"
}

def main [
    ...query: string                          # Search query (if provided, uses 'atuin search' instead of 'atuin history list')
    --limit (-l): int = 20                    # Number of history entries to show
    --reverse (-r)                            # Show oldest first instead of newest/most-relevant
    --wrap (-w)                               # Enable line wrapping for long commands
    --no-truncate (-n)                        # Don't truncate long values
    --row: int                                # Inspect a specific row number (0-indexed) with full details
    --cwd (-c)                                # Filter to current directory only
    --session (-s)                            # Filter to current session only
    --search-mode: string = "skim"            # Search algorithm: prefix, full-text, fuzzy, skim (skim is most advanced)
    --cmd-width: int = 0                      # Maximum width for command column (0 = auto-detect)
    --dir-width: int = 0                      # Maximum width for directory column (0 = auto-detect)
    --format (-f): string = "table"           # Output format: table, json, csv
] {
    # Calculate dynamic column widths based on terminal size
    let term_width = (term size).columns

    # Reserve space for: time(20) + duration(10) + borders(10) + index(5) = 45
    let reserved_space = 45
    let available_space = ($term_width - $reserved_space)

    # Allocate remaining space: 65% to command, 35% to directory
    let auto_cmd_width = if $available_space > 100 {
        ($available_space * 0.65 | math floor)
    } else {
        60  # fallback for narrow terminals
    }

    let auto_dir_width = if $available_space > 100 {
        ($available_space * 0.35 | math floor)
    } else {
        30  # fallback for narrow terminals
    }

    # Use provided widths or auto-calculated ones
    let final_cmd_width = if $cmd_width > 0 { $cmd_width } else { $auto_cmd_width }
    let final_dir_width = if $dir_width > 0 { $dir_width } else { $auto_dir_width }

    # Determine if we're searching or listing
    let is_search = ($query | length) > 0

    # Build atuin command arguments
    # atuin --reverse false = newest first (default), --reverse true = oldest first
    mut atuin_args = if $is_search {
        # Use 'atuin search' with query
        ["search" ...$query]
    } else {
        # Use 'atuin history list'
        ["history" "list"]
    }

    # Add common format argument
    $atuin_args = ($atuin_args | append ["--format" "{time}\t{command}\t{directory}\t{duration}"])

    # Handle reverse flag differently for list vs search
    if $is_search {
        # atuin search: no --reverse = most relevant first, --reverse = reverse order
        if $reverse {
            $atuin_args = ($atuin_args | append "--reverse")
        }
        # Add limit for search (it supports it)
        $atuin_args = ($atuin_args | append ["--limit" ($limit | into string)])
        # Add search mode for better fuzzy matching
        $atuin_args = ($atuin_args | append ["--search-mode" $search_mode])
    } else {
        # atuin history list: --reverse false = newest first, --reverse true = oldest first
        # We want newest first by default, so pass --reverse false unless user wants oldest
        $atuin_args = ($atuin_args | append ["--reverse" (if $reverse { "true" } else { "false" })])
        # Note: history list does NOT support --limit, we'll use nushell's `first` instead
    }

    # Handle filter flags
    if $is_search {
        # atuin search uses --filter-mode
        if $cwd {
            $atuin_args = ($atuin_args | append ["--filter-mode" "directory"])
        } else if $session {
            $atuin_args = ($atuin_args | append ["--filter-mode" "session"])
        }
    } else {
        # atuin history list uses separate flags
        if $cwd {
            $atuin_args = ($atuin_args | append "--cwd")
        }
        if $session {
            $atuin_args = ($atuin_args | append "--session")
        }
    }

    # Execute atuin and parse output
    let raw_output = (^atuin ...$atuin_args | lines)

    # Apply limit using nushell for history list (search already has --limit)
    let limited_output = if $is_search {
        $raw_output
    } else {
        $raw_output | first $limit
    }

    let history = (
        $limited_output
        | each { |line|
            let parts = ($line | split row "\t")
            if ($parts | length) == 4 {
                {
                    time: ($parts | get 0)
                    command: ($parts | get 1)
                    directory: ($parts | get 2 | str replace $env.HOME "~")
                    duration: ($parts | get 3)
                }
            }
        }
        | compact
    )

    # Handle row inspection mode (show single row with full details)
    if ($row != null) {
        let selected_row = $history | get $row --optional

        if ($selected_row == null) {
            print $"(ansi red)Error: Row ($row) not found. Query returned (ansi yellow)($history | length)(ansi red) rows.(ansi reset)"
            return
        }

        # Display the selected row with full details and colors
        print ""
        print $"(ansi { fg: ($CATPPUCCIN_MOCHA.mauve) attr: b })═══ Row ($row) Details ═══(ansi reset)"
        print ""
        print $"(ansi { fg: ($CATPPUCCIN_MOCHA.blue) attr: b })Time:(ansi reset)      (ansi { fg: ($CATPPUCCIN_MOCHA.sapphire) })($selected_row.time)(ansi reset)"
        print $"(ansi { fg: ($CATPPUCCIN_MOCHA.green) attr: b })Command:(ansi reset)   (ansi { fg: ($CATPPUCCIN_MOCHA.text) })($selected_row.command)(ansi reset)"
        print $"(ansi { fg: ($CATPPUCCIN_MOCHA.yellow) attr: b })Directory:(ansi reset) (ansi { fg: ($CATPPUCCIN_MOCHA.peach) })($selected_row.directory)(ansi reset)"
        print $"(ansi { fg: ($CATPPUCCIN_MOCHA.teal) attr: b })Duration:(ansi reset)  (ansi { fg: ($CATPPUCCIN_MOCHA.lavender) })($selected_row.duration)(ansi reset)"
        print ""
        return
    }

    # Apply truncation if not disabled (and not wrapping, which needs full text)
    let formatted = if ($no_truncate or $wrap) {
        $history
    } else {
        $history | each { |row|
            {
                time: $row.time
                command: (if $final_cmd_width > 0 {
                    $row.command | str substring 0..$final_cmd_width
                } else {
                    $row.command
                })
                directory: (if $final_dir_width > 0 {
                    $row.directory | str substring 0..$final_dir_width
                } else {
                    $row.directory
                })
                duration: $row.duration
            }
        }
    }

    # Output in requested format
    match $format {
        "json" => { $formatted | to json }
        "csv" => { $formatted | to csv }
        "table" => {
            if $wrap {
                # Custom wrapped format with Catppuccin Mocha colors
                $formatted | each { |entry|
                    print $"(ansi { fg: ($CATPPUCCIN_MOCHA.blue) attr: b })Time:(ansi reset)      (ansi { fg: ($CATPPUCCIN_MOCHA.sapphire) })($entry.time)(ansi reset)"
                    print $"(ansi { fg: ($CATPPUCCIN_MOCHA.green) attr: b })Command:(ansi reset)   (ansi { fg: ($CATPPUCCIN_MOCHA.text) })($entry.command)(ansi reset)"
                    print $"(ansi { fg: ($CATPPUCCIN_MOCHA.yellow) attr: b })Directory:(ansi reset) (ansi { fg: ($CATPPUCCIN_MOCHA.peach) })($entry.directory)(ansi reset)"
                    print $"(ansi { fg: ($CATPPUCCIN_MOCHA.teal) attr: b })Duration:(ansi reset)  (ansi { fg: ($CATPPUCCIN_MOCHA.lavender) })($entry.duration)(ansi reset)"
                    print $"(ansi { fg: ($CATPPUCCIN_MOCHA.surface0) })────────────────────────────────────────────────(ansi reset)"
                }
                null
            } else {
                # Apply Catppuccin Mocha colors to table output
                $formatted
                | each { |row|
                    {
                        time: (colorize $row.time $CATPPUCCIN_MOCHA.sapphire)
                        command: (colorize $row.command $CATPPUCCIN_MOCHA.green)
                        directory: (colorize $row.directory $CATPPUCCIN_MOCHA.peach)
                        duration: (colorize $row.duration $CATPPUCCIN_MOCHA.teal)
                    }
                }
                | rename --column {
                    "time": (colorize "time" $CATPPUCCIN_MOCHA.sapphire --bold)
                    "command": (colorize "command" $CATPPUCCIN_MOCHA.green --bold)
                    "directory": (colorize "directory" $CATPPUCCIN_MOCHA.peach --bold)
                    "duration": (colorize "duration" $CATPPUCCIN_MOCHA.teal --bold)
                }
                | table --theme rounded
            }
        }
        _ => {
            error make {
                msg: "Invalid format"
                label: {
                    text: $"Unknown format: ($format). Must be one of: table, json, csv"
                    span: (metadata $format).span
                }
            }
        }
    }
}
