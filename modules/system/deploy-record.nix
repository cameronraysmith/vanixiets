# Deploy record (S2, design D9, D12). Every activation appends one JSON line
#
#   {"host":"<hostName>","closure":"<$systemConfig>","previous_closure":"<readlink -f /run/current-system>","ts":"<UTC>"}
#
# to /var/log/deploy-record.jsonl, created mode 0644, so a deploy can be
# attributed to the commits that built its closure. NixOS and nix-darwin both
# run their activation snippets before they relink /run/current-system
# (nixpkgs activation-script.nix, nix-darwin activation-scripts.nix), so the
# link still names the system being replaced; previous_closure is absent when
# the link does not exist, as on the first activation of a NixOS boot. Store
# paths need no JSON escaping, so printf writes the line and no machine needs
# jq at activation. The host name is a literal fixed at evaluation.
#
# Both modules define the read-only option vanixiets.deployRecord.script.
# flake.lib.deployRecordObligations, asserted by modules/checks/machines.nix on
# the five x86_64-linux NixOS machine checks, fails unless the machine's activation runs it.
{ config, lib, ... }:
let
  deployRecordScript =
    {
      pkgs,
      hostName,
      file ? "/var/log/deploy-record.jsonl",
      currentSystem ? "/run/current-system",
    }:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "deploy-record-${hostName}";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          closure=$1
          host=${lib.escapeShellArg hostName}
          file=${lib.escapeShellArg file}
          current=${lib.escapeShellArg currentSystem}
          ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          if [ ! -e "$file" ]; then
            mkdir -p "$(dirname "$file")"
            touch "$file"
            chmod 0644 "$file"
          fi
          if [ -e "$current" ]; then
            previous=$(readlink -f "$current")
            printf '{"host":"%s","closure":"%s","previous_closure":"%s","ts":"%s"}\n' \
              "$host" "$closure" "$previous" "$ts" >>"$file"
          else
            printf '{"host":"%s","closure":"%s","ts":"%s"}\n' \
              "$host" "$closure" "$ts" >>"$file"
          fi
        '';
      }
    );

  scriptOption = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      The deploy-record script rendered for this host's networking.hostName;
      the activation runs it with the activated $systemConfig.
    '';
  };

  invocation = script: "${script} \"$systemConfig\"";

  deployRecordObligations = {
    failures =
      name: hostConfig:
      let
        isDarwin = lib.hasSuffix "-darwin" config.flake.lib.machineSystems.${name};
        script = hostConfig.vanixiets.deployRecord.script or null;
        optionPath =
          if isDarwin then "system.activationScripts.script.text" else "system.activationScripts.script";
        # The activation script the platform assembles from every snippet:
        # nixpkgs' activation-script.nix adds `script` in the option's apply,
        # nix-darwin's activation-scripts.nix defines `script.text`.
        text =
          if isDarwin then
            hostConfig.system.activationScripts.script.text
          else
            hostConfig.system.activationScripts.script;
      in
      if script == null then
        [ "${name} does not import deploy-record, so vanixiets.deployRecord.script is undefined" ]
      else
        # lib.hasInfix turns the script path into a regular expression, which
        # builtins.match refuses while it carries the script's string context.
        lib.optional (
          !lib.hasInfix (builtins.unsafeDiscardStringContext script) (
            builtins.unsafeDiscardStringContext text
          )
        ) "${name}'s ${optionPath} does not run ${script}";
  };
in
{
  flake.lib = {
    inherit deployRecordScript deployRecordObligations;
  };

  flake.modules.nixos.deploy-record =
    { config, pkgs, ... }:
    {
      options.vanixiets.deployRecord.script = scriptOption;
      config = {
        vanixiets.deployRecord.script = deployRecordScript {
          inherit pkgs;
          inherit (config.networking) hostName;
        };
        # No supportsDryActivation: a dry activation replaces the snippet
        # with a comment, so it appends nothing.
        system.activationScripts.deploy-record.text = invocation config.vanixiets.deployRecord.script;
      };
    };

  # postActivation runs under set -e as the last snippet before the relink;
  # mkAfter places the record after every other postActivation addition.
  flake.modules.darwin.deploy-record =
    { config, pkgs, ... }:
    {
      options.vanixiets.deployRecord.script = scriptOption;
      config = {
        vanixiets.deployRecord.script = deployRecordScript {
          inherit pkgs;
          inherit (config.networking) hostName;
        };
        system.activationScripts.postActivation.text = lib.mkAfter (
          invocation config.vanixiets.deployRecord.script
        );
      };
    };
}
