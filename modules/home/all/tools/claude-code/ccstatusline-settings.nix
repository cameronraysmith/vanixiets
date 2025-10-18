{ ... }:
{
  # Declarative ccstatusline configuration
  # Manages ~/.config/ccstatusline/settings.json
  #
  # Settings:
  # - Multi-line statusline layout (3 lines)
  # - Powerline mode with minimal theme
  # - Git worktree and branch display
  # - Session metrics (clock, cost, tokens)
  # - Session ID via custom jq command
  # - Context and token tracking

  home.file.".config/ccstatusline/settings.json".text = builtins.toJSON {
    version = 3;

    # Three-line layout for comprehensive status display
    lines = [
      # Line 1: Project context
      [
        {
          id = "b0956de0-40eb-46f5-a94d-92f3d4045e61";
          type = "current-working-dir";
          backgroundColor = "bgBrightCyan";
          metadata = {
            segments = "2";
          };
        }
        {
          id = "1";
          type = "model";
          color = "cyan";
        }
        {
          id = "623e7826-c7a2-4ab5-949a-85959bd2c0cf";
          type = "git-worktree";
        }
        {
          id = "5";
          type = "git-branch";
          color = "magenta";
        }
        {
          id = "7";
          type = "git-changes";
          color = "yellow";
        }
      ]

      # Line 2: Session metrics
      [
        {
          id = "63749d7b-cbdc-4f4a-873b-2c5f3901b45f";
          type = "session-clock";
          backgroundColor = "bgRed";
        }
        {
          id = "ba421936-e8b7-4184-9574-32b4cddfcea8";
          type = "session-cost";
          backgroundColor = "bgBrightYellow";
        }
        {
          id = "639ae281-0919-4c49-9e52-6f24d534f2bd";
          type = "tokens-cached";
          backgroundColor = "bgGreen";
        }
        {
          id = "a19ecd03-5bbe-4545-97ba-3e624442ec7e";
          type = "tokens-total";
          backgroundColor = "bgCyan";
        }
        {
          id = "fe0ecc3f-aeff-4fa9-8fa2-4012a2494cb6";
          type = "custom-command";
          backgroundColor = "bgBrightRed";
          commandPath = "jq -r '.session_id // \"no-session\"'";
        }
      ]

      # Line 3: Detailed metrics
      [
        {
          id = "83061005-9f10-4a53-9a70-0efd60b55355";
          type = "context-percentage";
          backgroundColor = "bgGreen";
        }
        {
          id = "f8c7b0c2-d3c9-4487-ad32-056f04736c80";
          type = "context-length";
          backgroundColor = "bgMagenta";
        }
        {
          id = "bdd354ab-ff50-4a0e-aa17-3aa7069053bc";
          type = "tokens-input";
          backgroundColor = "bgBrightWhite";
        }
        {
          id = "30ae856f-684a-48c0-b924-bdc425c426cd";
          type = "tokens-output";
          backgroundColor = "bgBrightGreen";
        }
        {
          id = "6030a238-40a2-401d-9267-e14a18defa62";
          type = "block-timer";
          backgroundColor = "bgWhite";
        }
      ]
    ];

    # Global display settings
    flexMode = "full-minus-40";
    compactThreshold = 60;
    colorLevel = 3; # Truecolor mode

    # Formatting
    defaultPadding = " ";
    inheritSeparatorColors = false;
    globalBold = false;

    # Powerline configuration
    powerline = {
      enabled = true;
      separators = [ "" ]; # U+E0B0 powerline arrow
      separatorInvertBackground = [ false ];
      startCaps = [ "" ]; # U+E0B2 powerline start cap
      endCaps = [ "" ]; # U+E0B0 powerline end cap
      theme = "minimal"; # Clean monochrome theme
      autoAlign = false;
    };
  };
}
