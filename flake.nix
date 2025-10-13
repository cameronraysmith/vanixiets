{
  description = "Nix configuration";

  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cameronraysmith.cachix.org"
      "https://poetry2nix.cachix.org"
      "https://pyproject-nix.cachix.org"
      "https://om.cachix.org"
      "https://catppuccin.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
      "poetry2nix.cachix.org-1:eXpeBJl0EQjO+vs9/1cUq19BH1LLKQT9HScbJDeeHaA="
      "pyproject-nix.cachix.org-1:UNzugsOlQIu2iOz0VyZNBQm2JSrL/kwxeCcFGw+jMe0="
      "om.cachix.org-1:ifal/RLZJKN4sbpScyPGqJ2+appCslzu7ZZF/C01f2Q="
      "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
    ];
  };

  inputs = {
    systems.url = "github:nix-systems/default";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";  # Fallback if nixpkgs-unstable breaks
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nixos-unified.url = "github:srid/nixos-unified";
    omnix.url = "github:juspay/omnix";

    flocken.url = "github:mirkolenz/flocken/v2";
    flocken.inputs.nixpkgs.follows = "nixpkgs";

    # Do not enable
    # nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";
    # It is pinned to the commit of nixpkgs e9f00bd8
    # used to build the cached bootstrap image at
    # /nix/store/c3bav8f2.../nixos.qcow2.
    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.url = "github:nixos/nixpkgs/e9f00bd893984bc8ce46c895c3bf7cac95331127";

    # TODO: error: darwin.apple_sdk_11_0 has been removed
    # <https://nixos.org/manual/nixpkgs/stable/#sec-darwin-legacy-frameworks>
    # omnix.inputs.nixpkgs.follows = "nixpkgs";
    # omnix.inputs.flake-parts.follows = "flake-parts";
    # omnix.inputs.git-hooks.follows = "git-hooks";
    omnix.inputs.systems.follows = "systems";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";
    agenix.inputs.systems.follows = "systems";
    sops-nix.url = "github:mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    lazyvim.url = "github:cameronraysmith/LazyVim-module/main";
    lazyvim.inputs.nixpkgs.follows = "nixpkgs";
    lazyvim.inputs.systems.follows = "systems";
    catppuccin.url = "github:catppuccin/nix";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.flake = false;
    nuenv.url = "github:hallettj/nuenv/writeShellApplication";
    nuenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self, ... }:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = builtins.filter (s: builtins.elem s (import inputs.systems)) [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports =
        with builtins;
        map (fn: ./modules/flake-parts/${fn}) (attrNames (readDir ./modules/flake-parts));

      perSystem =
        { lib, system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = lib.attrValues self.overlays ++ [ inputs.lazyvim.overlays.nvim-treesitter-main ];
            config.allowUnfree = true;
          };
        };

      flake.om.ci.default.ROOT = {
        dir = ".";
        steps.flake-check.enable = false;
        steps.custom = { };
      };
    };
}
