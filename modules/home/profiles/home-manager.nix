# Typed home-manager profile bundles.
#
# Each entry under `flake.lib.profiles.homeManager` names a composition
# of registered home-manager modules. Profiles are referenced by users
# via `flake.users.<u>.profiles = with config.flake.lib.profiles.homeManager; [ core ... ];`.
#
# All bundles are declared in a single module because `flake.lib` is a
# `lazyAttrsOf raw` namespace that does not recurse into nested option
# declarations and does not merge values written at the same path from
# multiple modules. Authoring each bundle in its own file would collide
# at `flake.lib.profiles`. The single-module shape preserves the
# `flake.lib.profiles.homeManager.<name>` consumer namespace without
# introducing per-bundle merge plumbing.
#
# `flake.lib.profileType` is the submodule type used by the consumer
# option `flake.users.<u>.profiles` to enforce schema. Its records are
# raw values here; type discipline lives at the consumer site.
{ config, lib, ... }:
{
  flake.lib.profileType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "One-line summary of what this profile composes.";
      };
      includes = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        description = "List of home-manager deferred modules this profile bundles.";
      };
    };
  };

  flake.lib.profiles.homeManager = {
    core = {
      description = "Core home environment shared by all users (bitwarden, catppuccin, fonts, session-variables, ssh, xdg).";
      includes = [ config.flake.modules.homeManager.core ];
    };

    development = {
      description = "Development tooling profile (ghostty, gui-apps, helix, incus, radicle).";
      includes = [ config.flake.modules.homeManager.development ];
    };

    shell = {
      description = "Shell environment profile (atuin, bash, fish, nushell, tmux, yazi, zellij).";
      includes = [ config.flake.modules.homeManager.shell ];
    };

    ai = {
      description = "AI agent tooling profile (codex, opencode, skills).";
      includes = [ config.flake.modules.homeManager.ai ];
    };
  };
}
