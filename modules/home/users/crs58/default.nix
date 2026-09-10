{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      # from home-manager's NixOS and nix-darwin modules; absent standalone
      osConfig ? null,
      ...
    }:
    let
      # Alias set from the dev-graph cookbook's omnigraph-config.example.yaml,
      # retargeted from its `local` server to our magnetite deployment.
      devGraphAlias =
        query: args:
        {
          server = "magnetite";
          graph = "dev";
          inherit query;
        }
        // lib.optionalAttrs (args != [ ]) { inherit args; };
    in
    {
      home.stateVersion = "23.11";

      home.packages = [
        flake.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
      ]
      ++ [
        # On PATH for per-repository opt-in ergonomics: gpg.x509.program is
        # written by hand in a repo-local config, and the alternative is
        # pasting a store path that goes stale on the next update. Nothing
        # invokes it until someone opts in. The credential helper needs no
        # such entry — generated config references it by absolute store path.
        pkgs.buzz-git-sign-nostr
      ];

      aiSkills.extraSkillDirs = flake.lib.linearSkillDirs pkgs;

      # User-level OpenSpec install (skills, schema bundle, and the global
      # config.json) is provided by the opt-in programs.openspec module in
      # modules/home/ai/openspec/default.nix.
      programs.openspec.enable = true;

      # The interactive CLI on PATH, with its config rendered from
      # modules/home/ai/devin/default.nix. Unconditional and independent of
      # services.devin-worker below: the worker runs the CLI from its own
      # store path and needs nothing on a user's PATH, while a person driving
      # `devin` wants it wherever this home lands. It carries no credential --
      # the rendered config.json is a world-readable store symlink and no
      # option feeds a secret into it.
      programs.devin.enable = true;

      programs.omnigraph = {
        enable = true;
        settings = {
          servers.magnetite.url = "http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:8090";

          defaults = {
            server = "magnetite";
            default_graph = "dev";
          };

          aliases = {
            issue = devGraphAlias "issue_lookup" [ "slug" ];
            epic = devGraphAlias "epic_lookup" [ "slug" ];
            pr = devGraphAlias "pr_lookup" [ "slug" ];

            ready = devGraphAlias "ready" [ ];
            blocked = devGraphAlias "blocked" [ ];
            blocked-parent = devGraphAlias "blocked_by_parent" [ ];
            blocked-epic = devGraphAlias "blocked_by_epic" [ ];
            blocked-gate = devGraphAlias "blocked_by_gate" [ ];
            blocked-wait = devGraphAlias "blocked_by_wait" [ ];
            blocked-upstream = devGraphAlias "blocked_on_upstream" [ ];
            stale = devGraphAlias "stale_candidates" [ ];

            epic-issues = devGraphAlias "epic_issues" [ "epic" ];
            epic-open = devGraphAlias "epic_open_issues" [ "epic" ];

            release-prs = devGraphAlias "release_prs" [ "release" ];
            issue-prs = devGraphAlias "issue_implementations" [ "issue" ];
            prs-comp = devGraphAlias "prs_for_component" [ "component" ];
            issues-comp = devGraphAlias "issues_for_component" [ "component" ];

            incident-cause = devGraphAlias "incident_root_cause" [ "incident" ];
            incident-blast = devGraphAlias "incident_components" [ "incident" ];
            learnings-incident = devGraphAlias "learnings_for_incident" [ "incident" ];

            unheld-invariants = devGraphAlias "unheld_invariants" [ ];
            gaps = devGraphAlias "gaps_undermining_invariants" [ ];
            assumptions = devGraphAlias "assumptions" [ ];
            caps-tier = devGraphAlias "capabilities_by_tier" [ "tier" ];
            decisions-comp = devGraphAlias "decisions_for_component" [ "component" ];
            no-spec = devGraphAlias "components_without_spec" [ ];
            no-cap-impl = devGraphAlias "capabilities_without_component" [ ];

            open-epics = devGraphAlias "open_epics" [ ];
            epic-counts = devGraphAlias "epic_issue_counts" [ "epic" ];
            issue-detail = devGraphAlias "issue_detail" [ "issue" ];
            issue-blockers = devGraphAlias "issue_blockers" [ "issue" ];
            issue-parents = devGraphAlias "issue_parents" [ "issue" ];
            issue-epic-parent = devGraphAlias "issue_parent_epic" [ "issue" ];
            issue-gates = devGraphAlias "issue_gates" [ "issue" ];
            issue-waits-on = devGraphAlias "issue_waits_on" [ "issue" ];
            issue-comments = devGraphAlias "issue_comments" [ "issue" ];

            sem-issue = devGraphAlias "search_issues" [ "q" ];
            sem-epic = devGraphAlias "search_epics" [ "q" ];
            sem-spec = devGraphAlias "search_specs" [ "q" ];
            sem-decision = devGraphAlias "search_decisions" [ "q" ];
            sem-learning = devGraphAlias "search_learnings" [ "q" ];
            sem-invariant = devGraphAlias "search_invariants" [ "q" ];
            sem-principle = devGraphAlias "search_principles" [ "q" ];
            sem-gap = devGraphAlias "search_gaps" [ "q" ];
            sem-cap = devGraphAlias "search_capabilities" [ "q" ];
            sem-pr = devGraphAlias "search_prs" [ "q" ];
            sem-incident = devGraphAlias "search_incidents" [ "q" ];
          };
        };
      };

      # sops-nix configuration for crs58/cameron user
      # 23 secrets: development + ai + shell aggregates
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # For allowed_signers generation
          glm-api-key = { };
          tm-source-drive-data-root = { };
          firecrawl-api-key = { };
          huggingface-token = { };
          cerebras-api-key = { };
          linear-api-key-personal = { };
          linear-api-key-work = { };
          linear-workspace-personal = { };
          linear-workspace-work = { };
          context7-api-key = { };
          # Hindsight cloud token for the standalone hindsight CLI, rendered to
          # ~/.hindsight/config by the template below. omp no longer reads it:
          # its memory backend is mnemopi, which is local and unauthenticated.
          hindsight-api-token = { };
          # Per-host scoped cognee X-Api-Key for the always-on cognee-memory
          # plugin and the cognee-cli wrapper. Declared here; its ciphertext is
          # added to secrets.yaml after the one-time owner-authenticated mint
          # against the live magnetite server (a user-run bootstrap gate), so
          # home-manager activation requires the minted value to be present.
          cognee-api-key = { };
          # Moshi pairing token, copied from the app's Settings -> Hooks screen
          # and consumed once per host by the moshi-hook launcher in
          # modules/home/ai/moshi. Seeded blank in secrets.yaml because
          # sops-nix validates every declared key when the generation is built:
          # the key has to exist before the token does. A blank value leaves
          # the daemon serving its local socket unpaired.
          moshi-pairing-token = {
            mode = "0400";
          };
          bitwarden-email = { };
          atuin-key = { };
          mcp-agent-mail-bearer-token = { };
          buzz-nsec = { };
          git-credentials = {
            mode = "0400"; # Read-only: prevent git credential-store from modifying
            path = "${config.home.homeDirectory}/.git-credentials";
          };
          aws-credentials = {
            mode = "0600"; # AWS SDK requires 600 for credentials file
            path = "${config.home.homeDirectory}/.aws/credentials";
          };
          niks3-auth-token = {
            path = "${config.xdg.configHome}/niks3/auth-token";
          };
        };

        # Generate allowed_signers file using sops.templates
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.crs58.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };

        templates."linear-credentials.toml" = flake.lib.mkLinearCredentialsTemplate config;

        # hindsight CLI credentials, rendered immutably from sops so the CLI
        # works without a `hindsight configure` step.
        #
        # This is now the only consumer of hindsight-api-token: omp's memory
        # backend moved to the local mnemopi store, and with it went the
        # ~/.omp/.env template that carried the same secret under omp's own
        # spelling. The CLI reads HINDSIGHT_API_KEY and HINDSIGHT_API_URL
        # (src/config.rs), never HINDSIGHT_API_TOKEN. Its resolution order is
        # environment, then named profile, then this file, then a localhost
        # default, so writing it here leaves the environment free to override
        # per invocation.
        #
        # Read-only (0400): change the URL with --api-url or the environment,
        # never via `hindsight configure`, which would clobber this file.
        templates."hindsight-cli-config" = {
          mode = "0400";
          path = "${config.home.homeDirectory}/.hindsight/config";
          content = ''
            api_url = "https://api.hindsight.vectorize.io"
            api_key = "${config.sops.placeholder."hindsight-api-token"}"
          '';
        };

        # Note: Radicle keys deployed via home.file below (not sops.templates due to pure eval path issues)
      };

      # The token is a bearer credential for registering this host with Moshi,
      # so the daemon is handed the decrypted path rather than the value; see
      # modules/home/ai/moshi for how the launcher consumes it.
      services.moshi-hook.pairingTokenFile = config.sops.secrets.moshi-pairing-token.path;

      # Devin Outposts worker tokens, one file per outpost queue so each can be
      # rotated on its own. Not a containment boundary: a token issued for one
      # outpost lists every outpost through the account-level endpoint, so both
      # are account-scoped for reads. See modules/home/ai/devin/worker.nix for
      # the rotation procedure and for why the launcher reads the path rather
      # than receiving the value.
      #
      # sops rather than clan vars: clan vars is effectively NixOS-shaped in
      # this fleet -- magnetite carries 41 generators against stibnite's one,
      # this repository already records a related clan feature as NixOS-only,
      # and sops-nix through home-manager already delivers secrets to the
      # darwin host for four existing tools.
      #
      # Declaration and wiring are gated on the service, not because either is
      # conditional in spirit but because sops-nix validates every declared key
      # against the sops file when the manifest is built (check-mode=sopsfile):
      # declaring a key whose ciphertext is not yet in secrets.yaml would fail
      # home-manager activation for a service that is off. The operator's
      # actions -- add a ciphertext, enable the worker on that host -- land
      # together, and enabling without it fails at build time naming the
      # missing key.
      #
      # They are gated again on the queue the host actually serves, so a host
      # declares exactly one key and exactly one tokenFile, and a host serving
      # no queue declares neither. Declaring every key everywhere would couple
      # the machines through that same validation: none could be enabled, nor
      # its token rotated, until every other ciphertext existed and validated
      # on it too, and each machine would decrypt credentials it never uses.
      #
      # The second gate sits on the leaf rather than on the attribute set: the
      # outpost names are literals either way, so `outposts` contributes the
      # same attribute names whatever the condition, and only the tokenFile
      # value is conditional. Nothing consults a tokenFile to learn the names
      # or the platforms, so there is no cycle here.
      #
      # Which queue each host serves is a deployment fact, so it is keyed on
      # the machine, not on its platform: six NixOS machines share this user,
      # and a platform-keyed rule would put every one of them on magnetite's
      # queue. A machine absent from this table serves no queue, and enabling
      # the worker there fails evaluation naming it.
      #
      # Carried as an inline module because `sops.secrets` is already defined
      # in the attribute set above, and a conditional slice of it cannot be a
      # second definition of the same attribute path in one literal.
      imports = [
        (
          let
            # Queue label per host. The labels coincide with the machine
            # names because the operator named the queues after the machines,
            # not because either is derived from the other: a host absent
            # from this table serves no queue, which is the property that
            # keeps the fleet's other linux machines off magnetite's queue.
            outpostByHost = {
              stibnite = "stibnite";
              magnetite = "magnetite";
            };

            # Hosts that actually run workers, named separately from the
            # assignment above. Which queue a host would serve is a
            # deployment fact recorded whenever it is decided; running a
            # worker there additionally needs that queue's token present in
            # secrets.yaml, so the two are not the same statement and do not
            # necessarily land together.
            workerHosts = [
              "stibnite"
              "magnetite"
            ];

            hostName = if osConfig == null then null else osConfig.networking.hostName;
            hostOutpost = if hostName == null then null else outpostByHost.${hostName} or null;

            # Both conjuncts matter. The host's own entry in the table is what
            # makes a machine with no queue declare nothing, even if someone
            # names another machine's queue on it -- that host then has no
            # credential and the module's tokenFile assertion fails the build
            # by name, rather than the host quietly serving sessions from a
            # queue that is not its own on a credential that is not its own.
            # The second conjunct keeps a key from being declared on a host
            # whose assignment has been pointed elsewhere.
            serves =
              name:
              config.services.devin-worker.enable
              && hostOutpost == name
              && config.services.devin-worker.outpost == name;
          in
          {
            services.devin-worker.enable = lib.mkIf (lib.elem hostName workerHosts) true;

            services.devin-worker.outpost = lib.mkIf (hostOutpost != null) (lib.mkDefault hostOutpost);

            sops.secrets = lib.mkMerge [
              (lib.mkIf (serves "stibnite") {
                devin-outposts-token-stibnite = {
                  mode = "0400";
                };
              })
              (lib.mkIf (serves "magnetite") {
                devin-outposts-token-magnetite = {
                  mode = "0400";
                };
              })
            ];

            services.devin-worker.outposts = {
              "stibnite".tokenFile =
                lib.mkIf (serves "stibnite") config.sops.secrets.devin-outposts-token-stibnite.path;
              "magnetite".tokenFile =
                lib.mkIf (serves "magnetite") config.sops.secrets.devin-outposts-token-magnetite.path;
            };
          }
        )
      ];

      # Deploy radicle public key (not secret - can be plaintext, but identity-bound)
      # This is the SSH public key used for Radicle node identity
      home.file.".radicle/keys/radicle.pub".text = ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+ ${flake.users.crs58.meta.email}
      '';

      # Note: Radicle signing key linked via activation script in radicle.nix
      # Cannot use home.file.source with sops.secrets.path due to pure eval mode restrictions
      # TODO: Investigate sops-nix symlink option or activation script approach

      programs.git.settings = {
        user.name = flake.users.crs58.meta.fullname;
        user.email = flake.users.crs58.meta.email;

        # buzz-nsec keeps the default sops path while git-credentials and
        # aws-credentials at :77-84 set explicit ones. That asymmetry is two
        # different requirements, not an inconsistency: those two consumers need
        # a fixed location, whereas an explicit `path` materializes a per-secret
        # symlink and git-sign-nostr's open_keyfile
        # (crates/git-sign-nostr/src/lib.rs) opens with O_NOFOLLOW. The default
        # materializes a regular file inside a symlinked generation directory,
        # and O_NOFOLLOW constrains only the trailing component, so it is
        # accepted. Nothing invokes git-sign-nostr today, so this constrains no
        # active path; it applies the moment anyone opts in per-repository.
        nostr.keyfile = config.sops.secrets.buzz-nsec.path;

        # `*` matches exactly one label, so this covers every community on
        # communities.buzz.xyz. The leading "" clears the inherited generic
        # helper chain from development/git.nix, whose `store --file` helper is
        # fatal against the read-only sops-rendered ~/.git-credentials.
        credential."https://*.communities.buzz.xyz/git" = {
          helper = [
            ""
            (lib.getExe' pkgs.buzz-git-credential-nostr "git-credential-nostr")
          ];
          useHttpPath = true;
        };
      };

      programs.jujutsu.settings.user = {
        name = flake.users.crs58.meta.fullname;
        email = flake.users.crs58.meta.email;
      };
    };
in
{
  flake.users.crs58.contentPrivate = content;
}
