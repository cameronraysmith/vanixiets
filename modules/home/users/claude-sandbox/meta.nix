{ config, ... }:
{
  flake.users.claude-sandbox = {
    meta = {
      # A Claude Code cloud session runs its setup step and its agent as root.
      username = "root";
      fullname = "Cameron Smith";
      email = "cameron.ray.smith@gmail.com";
      githubUser = "cameronraysmith";
      # Never under NixOS: a cloud session receives its age key from the cloud
      # environment's SOPS_AGE_KEY variable.
      sopsAgeKeyId = null;
      sshKeys = [ ];
      # Cloud sessions are granted no signing key.
      signingKey = null;
    };

    # The account exists only inside a Claude Code cloud container, which is
    # x86_64-linux.
    systems = [ "x86_64-linux" ];

    # The user context, the skill corpus and the tools the skills call, from the
    # same modules the other profiles use. `ai` is not imported: it assumes macOS
    # paths, installs Claude Code, and declares sops secrets for MCP servers and
    # wrappers. The cloud harness owns the claude binary.
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      sandbox
      agents-md
      agent-context
      ai-capabilities
      claude-code-hooks
      engineering-tools
      fd
      gh
      ghq
      git
      jq
      jujutsu
      linear
      mergify
      openspec
      pandoc
      ripgrep
      terminal
      typst
      vcs-author
      worktrunk
    ];
  };
}
