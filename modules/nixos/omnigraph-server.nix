# How this fleet serves omnigraph (flake.modules.nixos.omnigraph, which stays
# free of clan vars so the runtime tests can import it with their own
# credentials): magnetite's cookbook cluster, its four generators (the R2
# credentials, the admin, seeder and monitor bearer tokens), the server's
# settings and vanixiets.omnigraphRootStore, the option that says which store
# the root lives on. The policies name magnetite as the cluster operator
# (machines/nixos/magnetite/omnigraph/), and the cluster's actor is magnetite.
{ config, ... }:
let
  inherit (config.flake.lib) fleet;
  omnigraphRoots = config.flake.lib.omnigraphClusterRoots;
in
{
  flake.modules.nixos.omnigraph-server =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # The cookbooks of the pinned omnigraph-cookbooks (the top-level
      # directories holding a schema.pg and a seed.jsonl), each served as the
      # example graph `cookbook-<directory>`. Listed here rather than read
      # from the package, which evaluation could only do by building the
      # fetch first; checks.x86_64-linux.omnigraph-cookbook-seeds fails when
      # the pinned package holds a cookbook this list lacks, or lacks one it
      # names.
      cookbooks = [
        "agent-ops"
        "beads"
        "company-brain"
        "dev-graph"
        "hardware-program"
        "health-record"
        "industry-intel"
        "pharma-intel"
        "second-brain"
        "vc-os"
      ];
      cookbookGraph = cookbook: "cookbook-${cookbook}";

      # Where magnetite's omnigraph root lives (vanixiets.omnigraphRootStore,
      # declared below): "local" or "r2".
      omnigraphRootStore = config.vanixiets.omnigraphRootStore;
      omnigraphOnR2 = omnigraphRootStore == "r2";
      # The account's R2 endpoint.
      r2Endpoint = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
    in
    {
      # An option rather than a `let` value, so that an extendModules
      # override can evaluate magnetite on the other store
      # (checks.x86_64-linux.omnigraph-retired-roots).
      options.vanixiets.omnigraphRootStore = lib.mkOption {
        type = lib.types.enum [
          "local"
          "r2"
        ];
        internal = true;
        description = ''
          Where magnetite's omnigraph root lives, under the same root
          name either way (flake.lib.omnigraphClusterRoots.uriIn):
          "local" serves it from /var/lib/omnigraph/clusters on this
          host's disk, "r2" from the `sciexp` bucket with the R2
          endpoint, region, credentials and cluster lease set. Its
          value is flake.lib.omnigraphClusterRoots.stores.magnetite,
          which magnetite's notified units follow too, so that setting
          is the one to change. The `omnigraph-r2` generator, the
          retired and rollback roots and their lifecycle rules stay
          defined under both values, so switching back to "r2" serves
          the bucket's root as it was left.
        '';
      };

      config = {
        vanixiets.omnigraphRootStore = omnigraphRoots.stores.magnetite;

        # Cloudflare R2 S3 credentials scoped to the sciexp bucket, delivered as an
        # EnvironmentFile. object_store has no shared-credentials-file provider, so
        # process environment variables are the only source omnigraph resolves.
        vanixiets.secrets.omnigraph-r2 = {
          prompts.access-key = {
            description = ''
              Cloudflare R2 S3 access key ID with read and write scope on bucket
              sciexp. Minted in the Cloudflare dashboard; distinct from the
              niks3-s3 token, which is scoped to sciexp-nix-cache.
            '';
            type = "hidden";
            persist = true;
            display = {
              group = "omnigraph";
              label = "AWS_ACCESS_KEY_ID";
            };
          };

          prompts.secret-key = {
            description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
            type = "hidden";
            persist = true;
            display = {
              group = "omnigraph";
              label = "AWS_SECRET_ACCESS_KEY";
            };
          };

          files.access-key.deploy = false;
          files.secret-key.deploy = false;

          files."env" = {
            restartUnits = [ "omnigraph-server.service" ];
          };

          script = ''
            {
              printf 'AWS_ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
              printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
            } > "$out/env"
          '';
        };

        vanixiets.secrets.omnigraph-bearer-tokens = {
          files."tokens.json" = {
            restartUnits = [ "omnigraph-server.service" ];
          };
          runtimeInputs = [
            pkgs.openssl
            pkgs.jq
          ];
          script = ''
            jq -n --arg token "$(openssl rand -hex 32)" '{admin: $token}' > "$out/tokens.json"
          '';
        };

        # The seed actor's token, in a generator of its own: generating it
        # leaves omnigraph-bearer-tokens, and so admin's token, as it is. The
        # server adds it to the tokens file at start
        # (services.omnigraph.cluster.graphs.<graph>.seed.tokenFile).
        vanixiets.secrets.omnigraph-seeder-token = {
          files."token" = {
            restartUnits = [ "omnigraph-server.service" ];
          };
          runtimeInputs = [ pkgs.openssl ];
          script = ''
            printf '%s' "$(openssl rand -hex 32)" > "$out/token"
          '';
        };

        # The read-only `monitor` actor's token, in a generator of its own like
        # the seeder's. omnigraph-probe reads each graph's snapshot as this
        # actor, which the policies let list the graphs and read them, nothing
        # more (services.omnigraph.extraBearerTokenFiles).
        vanixiets.secrets.omnigraph-monitor-token = {
          files."token" = {
            restartUnits = [ "omnigraph-server.service" ];
          };
          runtimeInputs = [ pkgs.openssl ];
          script = ''
            printf '%s' "$(openssl rand -hex 32)" > "$out/token"
          '';
        };

        services.omnigraph = {
          enable = true;

          # Every cookbook of the pinned omnigraph-cookbooks as an example
          # graph, on a root created by omnigraph 0.16 and initialized by the
          # bootstrap unit. Its name records the storage format its graphs are
          # created at (flake.lib.omnigraphClusterRoots.name), so it follows
          # createdAtFormat; a fresh copy at the same format to replay the seeds
          # takes a revision (`revision = 2;` names cookbooks-f17-r2). The
          # previous root, dev-graph-v10, created by 0.15 at format 16 with one
          # empty graph `dev`, stays intact as the way back
          # (flake.lib.omnigraphClusterRoots.rollback). The root lives where
          # vanixiets.omnigraphRootStore says, under the same name.
          storageUri = omnigraphRoots.uriIn omnigraphRootStore (
            omnigraphRoots.name {
              family = "cookbooks";
              inherit (config.services.omnigraph.cluster) createdAtFormat;
            }
          );
          # omnigraph 0.16.0 writes storage format 17 (`omnigraph version
          # --json`, internal_schema.writes). servesFloor is the lowest format
          # the packaged omnigraph reads, and checks.omnigraph-format-window
          # holds it to the binary.
          cluster.createdAtFormat = 17;
          cluster.servesFloor = 14;

          s3 = lib.mkIf omnigraphOnR2 {
            endpointUrl = r2Endpoint;
            region = "auto";
          };

          # omnigraph-server takes one --bind, and cinnabar's TLS fronts reach
          # it on both magnetite's ZeroTier and tincr addresses, so it binds the
          # wildcard; 8090 is opened only on the mesh interfaces (the host's
          # firewall) and is absent from the global allowedTCPPorts, so the
          # firewall keeps it off the public interface.
          bindAddress = "::";
          port = 8090;
          requireAllGraphs = true;
          # Clients reach /mcp through cinnabar's omnigraph TLS fronts, and the
          # server refuses an MCP request whose Host it does not list.
          extraFlags = [
            "--mcp-allowed-host"
            "omnigraph.zt"
            "--mcp-allowed-host"
            "omnigraph.${fleet.domain}"
          ];

          # omnigraph-server stops itself when two thirds of its cluster lock's
          # lease pass without an acknowledged heartbeat to R2, and requests to
          # the bucket stall for 8 to 20 s without an error. A 120 s lease
          # tolerates about 39 s, where the default 30 s tolerates about 9 s; a
          # successor then waits 180 s instead of 45 s to take over a crashed
          # server's lock (OMNIGRAPH_CLUSTER_LEASE_SECONDS, omnigraph
          # docs/user/operations/storage-failures.md).
          extraEnvironment.OMNIGRAPH_CLUSTER_LEASE_SECONDS = lib.mkIf omnigraphOnR2 "120";

          environmentFile = lib.mkIf omnigraphOnR2 config.vanixiets.secrets.omnigraph-r2.files."env".path;
          bearerTokensFile = config.vanixiets.secrets.omnigraph-bearer-tokens.files."tokens.json".path;
          extraBearerTokenFiles.monitor = config.vanixiets.secrets.omnigraph-monitor-token.files."token".path;

          cluster = {
            # One example graph per cookbook, seeded once when the bootstrap
            # creates a new root, never on an existing one.
            graphs = lib.listToAttrs (
              map (
                cookbook:
                lib.nameValuePair (cookbookGraph cookbook) {
                  exampleDataOnly = true;
                  seed = {
                    file = "${pkgs.omnigraph-cookbooks}/${cookbook}/seed.jsonl";
                    actor = "seeder";
                    tokenFile = config.vanixiets.secrets.omnigraph-seeder-token.files."token".path;
                  };
                }
              ) cookbooks
            );

            settings = {
              metadata.name = "cookbooks";
              graphs = lib.listToAttrs (
                map (
                  cookbook:
                  lib.nameValuePair (cookbookGraph cookbook) {
                    schema = "cookbooks/${cookbook}/schema.pg";
                    queries = "cookbooks/${cookbook}/queries/";
                  }
                ) cookbooks
              );
              policies = {
                examples = {
                  file = "policies/examples.policy.yaml";
                  applies_to = map cookbookGraph cookbooks;
                };
                server = {
                  file = "policies/server.policy.yaml";
                  applies_to = [ "cluster" ];
                };
              };
            };

            # Each graph's schema and stored queries come from the cookbooks
            # commit pinned in pkgs/by-name/omnigraph-cookbooks/pin.json. A new
            # commit changes the rendered configuration only; the cluster takes
            # it when omnigraph-cluster-apply is run by hand.
            extraFiles =
              lib.listToAttrs (
                lib.concatMap (cookbook: [
                  (lib.nameValuePair "cookbooks/${cookbook}/schema.pg" "${pkgs.omnigraph-cookbooks}/${cookbook}/schema.pg")
                  (lib.nameValuePair "cookbooks/${cookbook}/queries" "${pkgs.omnigraph-cookbooks}/${cookbook}/queries")
                ]) cookbooks
              )
              // {
                "policies/examples.policy.yaml" = ../machines/nixos/magnetite/omnigraph/examples.policy.yaml;
                "policies/server.policy.yaml" = ../machines/nixos/magnetite/omnigraph/server.policy.yaml;
              };

            actor = "magnetite";
          };
        };
      };
    };
}
