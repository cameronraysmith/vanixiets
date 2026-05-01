# Identity-fold module for `flake.users.<u>.identityOverride`.
#
# Design note (nix-0pd.17 A2*): the originally-intended implementation
# would `lib.mapAttrs` over `config.flake.users` to synthesize a default
# `identityOverride` for every record. That approach induces a fixed-point
# infinite recursion — definitions of `config.flake.users` cannot read
# `config.flake.users` to enumerate (unlike `aliases-fold.nix`, which
# iterates the independent `config.flake.userAliases` source).
#
# Resolution: canonical users carry their own
# `home.username = lib.mkDefault flake.users.<self>.meta.username` and
# corresponding `home.homeDirectory` setters inside each
# `users/<u>/default.nix` content module. Those setters serve as the
# canonical-default synthesis. The `identityOverride` option default of
# `{ }` is a no-op deferredModule, harmless when appended to the modules
# list in `mk-home.nix`.
#
# `aliases-fold.nix` extends each alias record with `lib.mkForce` setters
# on `home.username` and `home.homeDirectory`, breaking the otherwise-tied
# `lib.mkDefault` merge between the (target user's) content module and
# the alias record's identity-bound expectations.
#
# This file is retained as a placeholder for the design discussion and as
# an extension point if a non-recursive enumeration source for canonical
# users emerges later (e.g. an explicit `config.flake.userNames` list).
{ ... }: { }
