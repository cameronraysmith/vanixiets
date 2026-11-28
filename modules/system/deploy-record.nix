# Deploy record (S2, design D9, D12). Every activation appends one JSON line
#
#   {"host":"<hostName>","closure":"<$systemConfig>","previous_closure":"<readlink -f /run/current-system>","ts":"<UTC>"}
#
# to /var/log/deploy-record.jsonl, created mode 0644, so a deploy can be
# attributed to the commits that built its closure. NixOS runs its activation
# snippets before it relinks /run/current-system (nixpkgs
# activation-script.nix), so the snippet reads the link itself. On darwin the
# link can move earlier (F86): nix-darwin's activate-system daemon links
# /run/current-system to the system profile when launchd loads it
# (RunAtLoad), and the activation's launchd step reloads it whenever its
# plist changes, as it does when the set of /etc files changes; the profile
# already names the new system then. So the darwin activation reads the link
# at its very start, in preActivation, and hands it to the record, which
# postActivation writes last, after every other postActivation snippet (see
# activationOrder), so a snippet that fails under set -e leaves no record of
# a deploy that did not finish. previous_closure is absent when the link does not
# exist, as on the first activation of a NixOS boot. Store paths need no JSON
# escaping, so printf writes the line and no machine needs jq at activation.
# The host name is a literal fixed at evaluation.
#
# Both modules define the read-only option vanixiets.deployRecord.script.
# flake.lib.deployRecordObligations, asserted by modules/checks/machines.nix
# on every NixOS and darwin machine check, fails unless the machine's
# activation runs it and reads the previous system before anything in the
# rendered activation relinks /run/current-system, and on darwin unless no
# command runs between the record and the relink;
# checks.x86_64-linux.deploy-record-order runs that judge over fixtures.
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
          # A second argument is the previous system read earlier by the
          # caller, empty when there was none (darwin, F86).
          if [ "$#" -ge 2 ]; then
            previous=$2
          elif [ -e "$current" ]; then
            previous=$(readlink -f "$current")
          else
            previous=
          fi
          if [ -n "$previous" ]; then
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

  # On darwin the previous system is read at the top of activation into this
  # variable and passed to the record (F86, see the darwin module).
  previousVar = "deployRecordPrevious";
  capture = "${previousVar}=$(readlink -f /run/current-system)";
  darwinInvocation = script: "${invocation script} \"\$${previousVar}\"";

  # What relinks /run/current-system during an activation: the activation's
  # own last step on both platforms, and on darwin also the reload of
  # nix-darwin's activate-system daemon, which runs at load and links
  # /run/current-system to the system profile, already set to the new system
  # (nix-darwin modules/services/activate-system, RunAtLoad).
  relink = "ln -sfn \"$(readlink -f \"$systemConfig\")\" /run/current-system";
  activateSystemReload = "org.nixos.activate-system.plist";

  # Problems with the order of `text`, the rendered activation script: the
  # previous system must be read before anything relinks /run/current-system,
  # and on darwin, where nix-darwin splices postActivation immediately before
  # the relink (its modules/system/activation-scripts.nix), no command may run
  # between the record and the relink.
  orderProblems =
    {
      name,
      isDarwin,
      script,
      text,
    }:
    let
      plain = builtins.unsafeDiscardStringContext text;
      parts = needle: lib.splitString (builtins.unsafeDiscardStringContext needle) plain;
      # Characters before the first occurrence of `needle`, or null.
      offset =
        needle:
        let
          p = parts needle;
        in
        if lib.length p < 2 then null else lib.stringLength (lib.head p);
      # The non-blank, non-comment lines between the darwin record and the
      # relink; none when either is missing or the relink comes first.
      afterRecord =
        let
          record = builtins.unsafeDiscardStringContext (darwinInvocation script);
          p = parts record;
          untilRelink =
            if lib.length p < 2 then [ ] else lib.splitString relink (lib.concatStringsSep record (lib.tail p));
        in
        if lib.length untilRelink < 2 then
          [ ]
        else
          lib.filter (line: line != "" && !lib.hasPrefix "#" line) (
            map lib.trim (lib.splitString "\n" (lib.head untilRelink))
          );
      before =
        what: first: second:
        let
          a = offset first;
          b = offset second;
        in
        lib.optional (a != null && b != null && a > b) "${name}: ${what}";
      read = if isDarwin then capture else invocation script;
    in
    if offset read == null then
      [
        (
          if isDarwin then
            "${name}'s activation does not read the previous system into ${previousVar}"
          else
            "${name}'s activation does not run ${script}"
        )
      ]
    else
      before "the previous system is read after the activation relinks /run/current-system" read relink
      ++ lib.optionals isDarwin (
        before
          "the previous system is read after launchd reloads activate-system, which relinks /run/current-system"
          read
          activateSystemReload
        ++ lib.optional (
          offset (darwinInvocation script) == null
        ) "${name}'s activation does not run ${script} with ${previousVar}"
        ++
          lib.optional (afterRecord != [ ])
            "${name}: postActivation runs `${lib.head afterRecord}` after the deploy record, before the relink"
      );

  deployRecordObligations = {
    inherit orderProblems;
    failures =
      name: hostConfig:
      let
        isDarwin = config.flake.lib.hosts.${name}.class == "darwin";
        script = hostConfig.vanixiets.deployRecord.script or null;
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
        orderProblems {
          inherit
            name
            isDarwin
            script
            text
            ;
        };
  };

  # The mkOrder priority of each first-party darwin activation snippet, by
  # script (types.lines joins definitions by ascending priority, equal ones in
  # import order). A new snippet takes its priority here. The values keep the
  # sequence import order would give among nix-darwin's, home-manager's and
  # sops-nix's own snippets (500, 1000, 1500); the deploy record comes last in
  # postActivation, and deployRecordObligations fails a Mac on which anything
  # follows it. `launchd` orders the snippets that run after users are created
  # and before nix-darwin's own launchd text loads the jobs.
  activationOrder = {
    resolverReload = 500;
    localDevelopmentCa = 999;
    casks = 1502;
    dnscryptProxy = 1503;
    fleetServicesTrust = 1504;
    deployRecord = 1900;
    launchd = {
      omnigentHost = 400;
      otelAgentSession = 401;
      otelCollector = 402;
      sharedReferenceTree = 403;
    };
  };
in
{
  flake.lib = {
    inherit activationOrder deployRecordScript deployRecordObligations;
  };

  fleetObligations.deployRecordObligations.failures = deployRecordObligations.failures;

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

  # preActivation runs first, before checks, /etc and launchd; mkBefore puts
  # the read ahead of every other preActivation addition. postActivation runs
  # under set -e before the relink; activationOrder.deployRecord places the
  # record after every other postActivation addition.
  flake.modules.darwin.deploy-record =
    { config, pkgs, ... }:
    {
      options.vanixiets.deployRecord.script = scriptOption;
      config = {
        vanixiets.deployRecord.script = deployRecordScript {
          inherit pkgs;
          inherit (config.networking) hostName;
        };
        system.activationScripts.preActivation.text = lib.mkBefore ''
          ${previousVar}=
          if [ -e /run/current-system ]; then
            ${capture}
          fi
        '';
        system.activationScripts.postActivation.text = lib.mkOrder activationOrder.deployRecord (
          darwinInvocation config.vanixiets.deployRecord.script
        );
      };
    };
}
