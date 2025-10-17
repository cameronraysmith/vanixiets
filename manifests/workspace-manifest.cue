package manifest

manifest: {
	version:      "1.0"
	generated_at: "2025-10-17T18:39:33Z"
	source_host:  "stibnite"
	workspaces: "nix-workspace": {
		path: "nix-workspace"
		repos: [{
			path:           "arnarg-nilla-config"
			default_branch: "main"
			remotes: origin: "https://github.com/arnarg/config.git"
		}, {
			path:           "atuin"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/atuin.git"
				upstream: "https://github.com/atuinsh/atuin.git"
			}
		}, {
			path:           "bioconda-recipes"
			default_branch: "master"
			remotes: origin: "https://github.com/bioconda/bioconda-recipes.git"
		}, {
			path:           "budimanjojo-nix-config"
			default_branch: "main"
			remotes: origin: "https://github.com/budimanjojo/nix-config.git"
		}, {
			path:           "bun2nix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/bun2nix.git"
				upstream: "https://github.com/baileyluTCD/bun2nix.git"
			}
		}, {
			path:           "cache-nix-action"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/cache-nix-action.git"
				upstream: "https://github.com/nix-community/cache-nix-action.git"
			}
		}, {
			path:           "cachix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/cachix.git"
				upstream: "https://github.com/cachix/cachix.git"
			}
		}, {
			path:           "cachix-action"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/cachix-action.git"
				upstream: "https://github.com/cachix/cachix-action.git"
			}
		}, {
			path:           "catppuccin-nix"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/catppuccin-nix.git"
				upstream: "https://github.com/catppuccin/nix.git"
			}
		}, {
			path:           "catppuccin-nushell"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/catppuccin-nushell.git"
				upstream: "https://github.com/catppuccin/nushell.git"
			}
		}, {
			path:           "catppuccin-tmux"
			default_branch: "main"
			remotes: origin: "https://github.com/catppuccin/tmux.git"
		}, {
			path:           "ccstatusline"
			default_branch: "main"
			remotes: origin: "https://github.com/sirmalloc/ccstatusline.git"
		}, {
			path:           "colmena"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/colmena.git"
				upstream: "https://github.com/zhaofengli/colmena.git"
			}
		}, {
			path:           "deadnix"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/deadnix.git"
				upstream: "https://github.com/astro/deadnix.git"
			}
		}, {
			path:           "defelo-nixos"
			default_branch: "main"
			remotes: origin: "https://radicle.defelo.de/zwsYj9vbBLhdSgnRYKKQEE9yG5PU.git"
		}, {
			path:           "deploy-rs"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/deploy-rs.git"
				upstream: "https://github.com/serokell/deploy-rs.git"
			}
		}, {
			path:           "devour-flake"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/devour-flake.git"
				upstream: "https://github.com/srid/devour-flake.git"
			}
		}, {
			path:           "fenix"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/fenix.git"
				upstream: "https://github.com/nix-community/fenix.git"
			}
		}, {
			path:           "flake-parts"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/flake-parts.git"
				upstream: "https://github.com/hercules-ci/flake-parts.git"
			}
		}, {
			path:           "flocken"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/flocken.git"
				upstream: "https://github.com/mirkolenz/flocken.git"
			}
		}, {
			path:           "fred-drake-nix-claude-mcp-sops-ccstatusline"
			default_branch: "main"
			remotes: origin: "https://github.com/fred-drake/nix.git"
		}, {
			path:           "fsharpforfunandprofit.com"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/fsharpforfunandprofit.com.git"
				upstream: "https://github.com/swlaschin/fsharpforfunandprofit.com.git"
			}
		}, {
			path:           "gitleaks-action"
			default_branch: "master"
			remotes: origin: "https://github.com/gitleaks/gitleaks-action.git"
		}, {
			path:           "gitmux"
			default_branch: "main"
			remotes: origin: "https://github.com/arl/gitmux.git"
		}, {
			path:           "haskell-flake"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/haskell-flake.git"
				upstream: "https://github.com/srid/haskell-flake.git"
			}
		}, {
			path:           "haskell-template"
			default_branch: "master"
			remotes: origin: "https://github.com/srid/haskell-template.git"
		}, {
			path:           "home-manager"
			default_branch: "master"
			remotes: {
				lorenzleutgeb: "https://github.com/lorenzleutgeb/home-manager.git"
				origin:        "https://github.com/cameronraysmith/home-manager.git"
				upstream:      "https://github.com/nix-community/home-manager.git"
			}
		}, {
			path:           "import-tree"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/import-tree.git"
				upstream: "https://github.com/vic/import-tree.git"
			}
		}, {
			path:           "incus"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/incus.git"
				upstream: "https://github.com/lxc/incus.git"
			}
		}, {
			path:           "just"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/just.git"
				upstream: "https://github.com/casey/just.git"
			}
		}, {
			path:           "LazyVim"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/LazyVim.git"
				upstream: "https://github.com/LazyVim/LazyVim.git"
			}
		}, {
			path:           "LazyVim-module"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/LazyVim-module.git"
				upstream: "https://github.com/matadaniel/LazyVim-module.git"
			}
		}, {
			path:           "mirkolenz-nixos"
			default_branch: "main"
			remotes: origin: "https://github.com/mirkolenz/nixos.git"
		}, {
			path:           "natsukium-dotfiles-nix"
			default_branch: "main"
			remotes: origin: "https://github.com/natsukium/dotfiles.git"
		}, {
			path:           "neovim"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/neovim.git"
				upstream: "https://github.com/neovim/neovim.git"
			}
		}, {
			path:           "nilla"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nilla.git"
				upstream: "https://github.com/nilla-nix/nilla.git"
			}
		}, {
			path:           "nix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nix.git"
				upstream: "https://github.com/NixOS/nix.git"
			}
		}, {
			path:           "nix-build-debug"
			default_branch: "main"
			remotes: origin: "https://github.com/milahu/nix-build-debug.git"
		}, {
			path:           "nix-cargo-crane"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nix-cargo-crane.git"
				upstream: "https://github.com/ipetkov/crane.git"
			}
		}, {
			path:           "nix-config"
			default_branch: "main"
			remotes: origin: "https://github.com/cameronraysmith/nix-config.git"
		}, {
			path:           "nix-darwin"
			default_branch: "master"
			remotes: origin: "https://github.com/nix-darwin/nix-darwin.git"
		}, {
			path:           "nix-quick-install-action"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nix-quick-install-action.git"
				upstream: "https://github.com/nixbuild/nix-quick-install-action.git"
			}
		}, {
			path:           "nix-rosetta-builder"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nix-rosetta-builder.git"
				upstream: "https://github.com/cpick/nix-rosetta-builder.git"
			}
		}, {
			path:           "nix-secrets"
			default_branch: "main"
			remotes: {
				origin: "https://github.com/cameronraysmith/nix-secrets"
				rad:    "rad://z2qTVkuBMHn82UyKbfT2NyyC5EaEH"
			}
		}, {
			path:           "nix-secrets-backup"
			default_branch: "main"
			remotes: origin: "https://github.com/cameronraysmith/nix-secrets.git"
		}, {
			path:           "nix-unit"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nix-unit.git"
				upstream: "https://github.com/nix-community/nix-unit.git"
			}
		}, {
			path:           "nix.dev"
			default_branch: "master"
			remotes: origin: "https://github.com/NixOS/nix.dev.git"
		}, {
			path:           "nixos-unified"
			default_branch: "master"
			remotes: origin: "https://github.com/srid/nixos-unified.git"
		}, {
			path:           "nixpkgs-review"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nixpkgs-review.git"
				upstream: "https://github.com/Mic92/nixpkgs-review.git"
			}
		}, {
			path:           "nixpkgs-review-gha"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nixpkgs-review-gha.git"
				upstream: "https://github.com/Defelo/nixpkgs-review-gha.git"
			}
		}, {
			path:           "nixpod-home"
			default_branch: "main"
			remotes: origin: "https://github.com/cameronraysmith/nixpod.git"
		}, {
			path:           "nothing-but-nix"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nothing-but-nix.git"
				upstream: "https://github.com/wimpysworld/nothing-but-nix.git"
			}
		}, {
			path:           "nuenv"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nuenv.git"
				upstream: "https://github.com/hallettj/nuenv.git"
			}
		}, {
			path:           "nushell-docs"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/nushell.github.io.git"
				upstream: "https://github.com/nushell/nushell.github.io.git"
			}
		}, {
			path:           "omerxx-tmux-dotfiles"
			default_branch: "master"
			remotes: origin: "https://github.com/omerxx/dotfiles.git"
		}, {
			path:           "omnix"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/omnix.git"
				upstream: "https://github.com/juspay/omnix.git"
			}
		}, {
			path:           "phucisstupid-dotfiles-lazyvim"
			default_branch: "main"
			remotes: origin: "https://github.com/phucisstupid/dotfiles.git"
		}, {
			path:           "pyproject.nix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/pyproject.nix.git"
				upstream: "https://github.com/pyproject-nix/pyproject.nix.git"
			}
		}, {
			path:           "python-flake"
			default_branch: "main"
			remotes: origin: "https://github.com/sciexp/python-flake.git"
		}, {
			path:           "python-nix-template"
			default_branch: "main"
			remotes: origin: "https://github.com/sciexp/python-nix-template"
		}, {
			path:           "python-nix-template-planning"
			default_branch: "main"
			remotes: origin: "https://github.com/cameronraysmith/python-nix-template-planning.git"
		}, {
			path:           "python-project-generator"
			default_branch: "main"
			remotes: origin: "https://github.com/sanders41/python-project-generator.git"
		}, {
			path:           "radicle-desktop"
			default_branch: "main"
			remotes: origin: "https://seed.radicle.xyz/z4D5UCArafTzTQpDZNQRuqswh3ury.git"
		}, {
			path:           "radicle-docs"
			default_branch: "master"
			remotes: origin: "https://github.com/radicle-dev/radicle.xyz.git"
		}, {
			path:           "rbw"
			default_branch: "main"
			remotes: origin: "https://github.com/doy/rbw.git"
		}, {
			path:           "rust-flake"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/rust-flake.git"
				upstream: "https://github.com/juspay/rust-flake.git"
			}
		}, {
			path:           "rust-nix-template"
			default_branch: "master"
			remotes: origin: "https://github.com/srid/rust-nix-template.git"
		}, {
			path:           "sops"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/sops.git"
				upstream: "https://github.com/getsops/sops.git"
			}
		}, {
			path:           "sops-emergentmind-nix-config"
			default_branch: "dev"
			remotes: {
				origin:   "https://github.com/cameronraysmith/emergentmind-sops-nix-config.git"
				upstream: "https://github.com/EmergentMind/nix-config.git"
			}
		}, {
			path:           "sops-nix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/sops-nix.git"
				upstream: "https://github.com/Mic92/sops-nix.git"
			}
		}, {
			path:           "srid-nixos-config"
			default_branch: "master"
			remotes: origin: "https://github.com/srid/nixos-config.git"
		}, {
			path:           "STAR"
			default_branch: "master"
			remotes: origin: "https://github.com/alexdobin/STAR.git"
		}, {
			path:           "stormi"
			default_branch: "main"
			remotes: origin: "https://github.com/pinellolab/stormi.git"
		}, {
			path:           "test-secrets"
			default_branch: "main"
			remotes: origin: "https://github.com/cameronraysmith/test-secrets.git"
		}, {
			path:           "test-starlight-cloudflare"
			default_branch: "main"
			remotes: {}
		}, {
			path:           "tmux-kubectx"
			default_branch: "master"
			remotes: origin: "https://github.com/tony-sol/tmux-kubectx.git"
		}, {
			path:           "tmux-sessionx"
			default_branch: "main"
			remotes: origin: "https://github.com/omerxx/tmux-sessionx.git"
		}, {
			path:           "typescript-nix-template"
			default_branch: "main"
			remotes: origin: "https://github.com/sciexp/typescript-nix-template.git"
		}, {
			path:           "uv2nix"
			default_branch: "master"
			remotes: {
				origin:   "https://github.com/cameronraysmith/uv2nix.git"
				upstream: "https://github.com/pyproject-nix/uv2nix.git"
			}
		}, {
			path:           "uv2nix_hammer_overrides"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/uv2nix_hammer_overrides.git"
				upstream: "https://github.com/TyberiusPrime/uv2nix_hammer_overrides.git"
			}
		}, {
			path:           "venv-selector.nvim"
			default_branch: "main"
			remotes: origin: "https://github.com/linux-cultist/venv-selector.nvim.git"
		}, {
			path:           "virby-example-nix-config"
			default_branch: "main"
			remotes: origin: "https://github.com/quinneden/nix-config.git"
		}, {
			path:           "virby-nix-darwin"
			default_branch: "main"
			remotes: {
				origin:   "https://github.com/cameronraysmith/virby-nix-darwin.git"
				upstream: "https://github.com/quinneden/virby-nix-darwin.git"
			}
		}]
	}
}
