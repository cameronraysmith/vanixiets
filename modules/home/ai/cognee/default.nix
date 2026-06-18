# Cognee plugin client wiring: declarative endpoint/identity env plus the
# per-host X-Api-Key delivery for the always-on cognee-memory plugin.
#
# The cognee MCP client is dropped (see modules/home/ai/claude-code/mcp-servers.nix);
# the plugin talks REST directly to central magnetite over the ZeroTier mesh,
# reading its endpoint and identity from this module and its credential from a
# sops-nix home-manager secret.
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      {
        config,
        lib,
        flake, # extraSpecialArgs: config.flake // { inherit inputs; }; exposes flake.lib.cognee
        # osConfig is the embedding system config in the nix-darwin-embedded home
        # path; it is absent in the standalone homeConfigurations path, so it MUST
        # be defaulted (a bare required formal throws in the standalone eval).
        osConfig ? null,
        ...
      }:
      let
        inherit (flake.lib.cognee) meshApiUrl userEmail;
        keyPath = config.sops.secrets."cognee-api-key".path;
        # Per-host dataset/agent names are derived statically from
        # osConfig.networking.hostName in the nix-darwin-embedded path; osConfig is
        # null-guarded so the standalone homeConfigurations path (and the
        # home-manager-crs58 check) evaluates without it and simply omits the
        # per-host vars.
        hostName = if osConfig != null then osConfig.networking.hostName else null;
      in
      {
        # Endpoint, owner-identity, per-host dataset/agent, and the plugin
        # credential are ALL delivered through .zshenv exports (programs.zsh.envExtra)
        # rather than home.sessionVariables. The cognee-memory plugin reads these
        # from os.environ inside a hook subprocess that Claude Code launches itself,
        # and that subprocess does NOT inherit home.sessionVariables: those ride
        # hm-session-vars.sh, which .zshenv sources only in login shells and only
        # once (the __HM_SESS_VARS_SOURCED guard), so under Claude Code the guard is
        # set-but-valueless and the vars arrive EMPTY. With COGNEE_SERVICE_URL empty
        # the plugin silently falls back to LOCAL mode. The unconditional .zshenv
        # export channel (already proven for COGNEE_API_KEY) is the only one that
        # reaches the launching shell, so the non-secret vars ride it too.
        #
        # COGNEE_SERVICE_URL is non-local, which puts the plugin in HTTP mode
        # (connect to remote magnetite, never boot a local server). COGNEE_USER_EMAIL
        # must be the real cognee default/owner account; the plugin's built-in
        # default (default_user@example.com) does not exist on this server.
        # COGNEE_PLUGIN_DATASET / COGNEE_AGENT_NAME are derived statically from
        # osConfig.networking.hostName in the deploying nix-darwin-embedded path and
        # omitted in the standalone homeConfigurations path (osConfig null).
        #
        # COGNEE_API_KEY is the only secret value: it is the contents of a sops-nix
        # home-manager secret read at shell-init, never a literal in the store. The
        # plugin reads it as a plaintext env VALUE with no _FILE variant, so a
        # wrapper-cat or _FILE indirection cannot reach it and it cannot ride
        # home.sessionVariables (world-readable).
        programs.zsh.envExtra = ''
          export COGNEE_SERVICE_URL=${lib.escapeShellArg meshApiUrl}
          export COGNEE_USER_EMAIL=${lib.escapeShellArg userEmail}
        ''
        + lib.optionalString (hostName != null) ''
          export COGNEE_PLUGIN_DATASET=${lib.escapeShellArg "claude_sessions_${hostName}"}
          export COGNEE_AGENT_NAME=${lib.escapeShellArg "claude_${hostName}"}
        ''
        + ''
          if [ -r ${lib.escapeShellArg keyPath} ]; then
            COGNEE_API_KEY="$(cat ${lib.escapeShellArg keyPath})"
            export COGNEE_API_KEY
          fi
        '';
      };
  };
}
