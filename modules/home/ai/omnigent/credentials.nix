{ config, lib, ... }:
let
  linearFiles = [
    "key"
    "workspace"
    "workspace-id"
    "viewer-email"
  ];
  sourceSelection =
    credentials:
    lib.filterAttrs (_: source: source.enable) (
      {
        inherit (credentials) signingKey claudeSetupToken;
      }
      // lib.mapAttrs' (
        owner: source: lib.nameValuePair "github-${owner}" source
      ) credentials.githubTokens
      // lib.concatMapAttrs (
        label: source:
        lib.genAttrs (map (file: "linear-${label}-${file}") linearFiles) (name: {
          inherit (source) enable generator;
          file = lib.removePrefix "linear-${label}-" name;
        })
      ) credentials.linearApiKeys
    );
  # The adapter's decisions over a vars-shaped view, `vars.<generator>.<file> = { path; placeholder; }`:
  # the host supplies Clan generator paths and SOPS placeholders, checks supply synthetic ones.
  credentialPolicy =
    {
      pkgs,
      credentials,
      vars,
      linearRendered,
      home,
      serverUrl,
    }:
    let
      selected = sourceSelection credentials;
      output = source: vars.${source.generator}.${source.file};
      path = source: (output source).path;
      placeholder = source: file: (output (source // { inherit file; })).placeholder;
      enabledPath = source: if source.enable then path source else null;
      linear = lib.filterAttrs (_: source: source.enable) credentials.linearApiKeys;
      github = lib.filterAttrs (_: source: source.enable) credentials.githubTokens;
      linearPath = source: file: path (source // { inherit file; });
    in
    {
      policy = {
        inherit home serverUrl;
        inherit (credentials) expected defaultOwner;
        signingKey = enabledPath credentials.signingKey;
        githubTokens = lib.mapAttrs (_: source: {
          path = path source;
          inherit (source) expectedLogin;
        }) github;
        claudeSetupToken = enabledPath credentials.claudeSetupToken;
        linearCredentials = if linear == { } then null else "${home}/.config/linear/credentials.toml";
        linearRendered = if linear == { } then null else linearRendered;
        linearApiKeys = lib.mapAttrs (_: source: {
          path = linearPath source "key";
          workspace = linearPath source "workspace";
          workspaceId = linearPath source "workspace-id";
          viewerEmail = linearPath source "viewer-email";
        }) linear;
        requiredFiles = map path (lib.attrValues selected) ++ lib.optional (linear != { }) linearRendered;
        sources = lib.mapAttrs (_: source: {
          inherit (source) generator file;
          path = path source;
        }) selected;
        executables = {
          gh = lib.getExe pkgs.gh;
          git = lib.getExe pkgs.git;
          linear = lib.getExe pkgs.linear-cli;
          claude = lib.getExe config.flake.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
          ssh-keygen = "${pkgs.openssh}/bin/ssh-keygen";
        };
      };
      linearTemplate =
        if linear == { } then
          null
        else
          config.flake.lib.mkLinearCredentialsTemplate {
            workspaces = lib.mapAttrs' (
              _: source: lib.nameValuePair (placeholder source "workspace") (placeholder source "key")
            ) linear;
            defaultWorkspace = placeholder linear.${lib.head (lib.attrNames linear)} "workspace";
          };
    };
  mkDelivery =
    {
      pkgs,
      osConfig,
      worker,
      home,
      group,
      serverUrl,
    }:
    let
      selected = sourceSelection worker.credentials;
      output = source: osConfig.clan.core.vars.generators.${source.generator}.files.${source.file};
      linear = lib.filterAttrs (_: source: source.enable) worker.credentials.linearApiKeys;
      github = lib.filterAttrs (_: source: source.enable) worker.credentials.githubTokens;
      templateName = "omnigent-${worker.user}-linear";
      secretName = source: "vars/${(output source).rel_dir}/${source.file}";
      sourceFile =
        source:
        let
          file = output source;
        in
        builtins.path {
          name = lib.strings.sanitizeDerivationName "${file.rel_dir}_${file.name}";
          path = osConfig.clan.core.settings.directory + "/vars/${file.rel_dir}/${file.name}/secret";
        };
      linearSelected = lib.filterAttrs (name: _: lib.hasPrefix "linear-" name) selected;
      linearPresent = lib.all (
        source: builtins.hasAttr (secretName source) (osConfig.sops.secrets or { })
      ) (lib.attrValues linearSelected);
      derived = credentialPolicy {
        inherit pkgs home serverUrl;
        credentials = worker.credentials;
        vars = lib.mapAttrs (
          _: generator:
          lib.mapAttrs (name: file: {
            inherit (file) path;
            placeholder = osConfig.sops.placeholder."vars/${file.rel_dir}/${name}";
          }) generator.files
        ) osConfig.clan.core.vars.generators;
        linearRendered = osConfig.sops.templates.${templateName}.path;
      };
      policy = derived.policy;
      policyFile = pkgs.writeText "omnigent-${worker.user}-credential-policy.json" (
        builtins.toJSON policy
      );
      command = mode: "${lib.getExe pkgs.python3} ${./credentials.py} ${policyFile} ${mode}";
      expected = worker.credentials.expected;
    in
    {
      enabled = selected != { };
      inherit policy policyFile;
      readiness = command "ready";
      homeModule = lib.mkIf (selected != { }) {
        _module.args.omnigentCredentialPolicy = policy;
      };
      assertions = [
        {
          assertion = lib.all (source: source.generator != null && source.file != null) (
            lib.attrValues selected
          );
          message = "Omnigent worker ${worker.user}: enabled credentials require explicit Clan generator/file sources.";
        }
        {
          assertion = lib.all (
            source:
            let
              file = output source;
            in
            file.secret
            && file.neededFor == "services"
            && file.owner == worker.user
            && file.mode == "0400"
            && osConfig.clan.core.vars.generators.${source.generator}.share
            && (osConfig.sops.secrets.${secretName source}.owner or null) == worker.user
            && (osConfig.sops.secrets.${secretName source}.mode or null) == "0400"
          ) (lib.attrValues selected);
          message = "Omnigent worker ${worker.user}: credentials require private shared services files owned by the worker with mode 0400.";
        }
        {
          assertion = lib.all (
            source:
            let
              file = output source;
              secret = osConfig.sops.secrets.${secretName source} or null;
            in
            secret != null
            && file.rel_dir == "shared/${source.generator}"
            && secret.path == file.path
            && toString secret.sopsFile == toString (sourceFile source)
          ) (lib.attrValues selected);
          message = "Omnigent worker ${worker.user}: only the declared Clan vars ciphertext and delivered paths are allowed.";
        }
        {
          assertion =
            !worker.credentials.signingKey.enable
            || (expected.gitEmail != null && expected.signingPublicKey != null);
          message = "Omnigent worker ${worker.user}: signing requires the canonical Git email and declared public key.";
        }
        {
          assertion =
            lib.all (source: source.expectedLogin != null) (lib.attrValues github)
            && lib.length (lib.unique (map (source: source.expectedLogin) (lib.attrValues github))) <= 1;
          message = "Omnigent worker ${worker.user}: GitHub owner tokens require the same explicit expected person login.";
        }
        {
          assertion =
            worker.credentials.defaultOwner == null || builtins.hasAttr worker.credentials.defaultOwner github;
          message = "Omnigent worker ${worker.user}: defaultOwner must select an enabled GitHub token.";
        }
        {
          assertion = lib.all (owner: github.${owner}.generator == "${worker.user}-github-token-${owner}") (
            lib.attrNames github
          );
          message = "Omnigent worker ${worker.user}: GitHub generators must use the worker user and resource owner.";
        }
        {
          assertion = selected == { } || expected.omnigentEmail != null;
          message = "Omnigent worker ${worker.user}: credential verification requires an explicit expected Omnigent email.";
        }
        {
          assertion = lib.all (label: linear.${label}.generator == "${worker.user}-linear-${label}") (
            lib.attrNames linear
          );
          message = "Omnigent worker ${worker.user}: Linear generators must use the worker user and masked label.";
        }
      ];
      generators = lib.mapAttrs (
        generator: sources:
        let
          files = map (source: source.file) sources;
        in
        {
          share = true;
          files = lib.genAttrs files (_: {
            secret = true;
            neededFor = "services";
            owner = worker.user;
            inherit group;
            mode = "0400";
          });
          prompts = lib.genAttrs files (file: {
            type = "hidden";
            persist = lib.hasPrefix "${worker.user}-linear-" generator;
            description = "Approved ${worker.user} credential for ${generator}/${file}";
          });
          runtimeInputs = [ pkgs.coreutils ];
          script = lib.concatMapStringsSep "\n" (file: ''
            test -s "$prompts/${file}"
            cp "$prompts/${file}" "$out/${file}"
          '') files;
        }
      ) (lib.groupBy (source: source.generator) (lib.attrValues selected));
      templates = lib.optionalAttrs (linear != { } && linearPresent) {
        ${templateName} = derived.linearTemplate // {
          owner = worker.user;
          inherit group;
        };
      };
    };
in
{
  flake.lib.omnigentCredentialSelection = sourceSelection;
  flake.lib.omnigentCredentialPolicy = credentialPolicy;
  flake.lib.mkOmnigentWorkerCredentials = mkDelivery;
  flake.modules.homeManager.omnigent-worker-credentials =
    { config, pkgs, ... }:
    let
      policy = config.programs.omnigent.workerCredentials;
      policyFile = pkgs.writeText "omnigent-worker-credential-policy.json" (builtins.toJSON policy);
      wrapper =
        name: mode:
        pkgs.writeShellScriptBin name ''
          exec ${lib.getExe pkgs.python3} ${./credentials.py} ${policyFile} ${mode} "$@"
        '';
      signers = pkgs.writeText "omnigent-allowed-signers" ''
        ${policy.expected.gitEmail} namespaces="git" ${policy.expected.signingPublicKey}
      '';
    in
    {
      options.programs.omnigent.workerCredentials = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = config._module.args.omnigentCredentialPolicy or null;
        readOnly = true;
        internal = true;
        description = "Host adapter's selected credential paths and non-secret verification policy.";
      };
      config = lib.mkIf (policy != null) {
        home.packages = [
          (wrapper "omnigent-worker-verify" "verify")
        ]
        ++ lib.optional (policy.linearApiKeys != { }) (lib.hiPrio (wrapper "linear" "linear"));
        xdg.configFile."linear/credentials.toml" = lib.mkIf (policy.linearApiKeys != { }) {
          source = config.lib.file.mkOutOfStoreSymlink policy.linearRendered;
        };
        programs.gh.package = lib.mkIf (policy.githubTokens != { }) (wrapper "gh" "gh");
        programs.claude-code.package = lib.mkIf (policy.claudeSetupToken != null) (
          wrapper "claude" "claude"
        );
        programs.git = lib.mkMerge [
          (lib.mkIf (policy.githubTokens != { }) {
            settings.credential."https://github.com".useHttpPath = true;
          })
          (lib.mkIf (policy.signingKey != null) {
            signing = {
              key = policy.signingKey;
              format = "ssh";
              signByDefault = true;
            };
            settings = {
              user.email = policy.expected.gitEmail;
              gpg.ssh.allowedSignersFile = toString signers;
            };
          })
        ];
        programs.jujutsu.settings = lib.mkIf (policy.signingKey != null) {
          user.email = policy.expected.gitEmail;
          signing = {
            key = policy.signingKey;
            behavior = lib.mkForce "own";
            backend = "ssh";
            backends.ssh.allowed-signers = toString signers;
          };
        };
      };
    };
}
