# Gitea Actions runner for magnetite
#
# Provides Podman-based Gitea Actions runners with nix support.
# Uses a custom container image with /nix store mounted from the host.
# Tokens are auto-generated at runtime via gitea CLI.
# Runner instances are parametrized via numInstances using genAttrs.
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.gitea-actions-runner =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Store dependencies available inside the runner container
      # Symlinked into a single bin directory for bind-mounting
      storeDeps = pkgs.runCommand "gitea-runner-store-deps" { } ''
        mkdir -p $out/bin
        for dir in ${
          toString [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gawk
            pkgs.git
            pkgs.nix
            pkgs.jq
            pkgs.nodejs
          ]
        }; do
          for bin in "$dir"/bin/*; do
            ln -s "$bin" "$out/bin/$(basename "$bin")"
          done
        done

        # SSL CA certificates for HTTPS access inside the container
        mkdir -p $out/etc/ssl/certs
        cp -a "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" $out/etc/ssl/certs/ca-bundle.crt
      '';

      numInstances = 2;
    in
    lib.mkMerge [
      {
        # Unprivileged user for nix CI jobs inside the container
        users.users.nixuser = {
          group = "nixuser";
          description = "Used for running nix ci jobs";
          home = "/var/empty";
          isSystemUser = true;
        };
        users.groups.nixuser = { };

        # Build custom container image with nix support
        systemd.services.gitea-runner-nix-image = {
          wantedBy = [ "multi-user.target" ];
          after = [ "podman.service" ];
          requires = [ "podman.service" ];
          path = [
            config.virtualisation.podman.package
            pkgs.gnutar
            pkgs.shadow
            pkgs.getent
          ];
          script = ''
            set -eux -o pipefail
            mkdir -p etc/nix

            # Create an unprivileged user for nix operations
            touch etc/passwd etc/group
            groupid=$(cut -d: -f3 < <(getent group nixuser))
            userid=$(cut -d: -f3 < <(getent passwd nixuser))
            groupadd --prefix $(pwd) --gid "$groupid" nixuser
            emptypassword='$6$1ero.LwbisiU.h3D$GGmnmECbPotJoPQ5eoSTD6tTjKnSWZcjHoVTkxFLZP17W9hRi/XkmCiAMOfWruUwy8gMjINrBMNODc7cYEo4K.'
            useradd --prefix $(pwd) -p "$emptypassword" -m -d /tmp -u "$userid" -g "$groupid" -G nixuser nixuser

            cat <<NIX_CONFIG > etc/nix/nix.conf
            accept-flake-config = true
            experimental-features = nix-command flakes
            NIX_CONFIG

            cat <<NSSWITCH > etc/nsswitch.conf
            passwd:    files mymachines systemd
            group:     files mymachines systemd
            shadow:    files

            hosts:     files mymachines dns myhostname
            networks:  files

            ethers:    files
            services:  files
            protocols: files
            rpc:       files
            NSSWITCH

            tar -cv . | podman import - gitea-runner-nix
          '';
          serviceConfig = {
            RuntimeDirectory = "gitea-runner-nix-image";
            WorkingDirectory = "/run/gitea-runner-nix-image";
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      }
      {
        # N token generation services via genAttrs
        systemd.services =
          lib.genAttrs (builtins.genList (n: "gitea-runner-nix${builtins.toString n}-token") numInstances)
            (name: {
              wantedBy = [ "multi-user.target" ];
              after = [ "gitea.service" ];
              environment = {
                GITEA_CUSTOM = "/var/lib/gitea/custom";
                GITEA_WORK_DIR = "/var/lib/gitea";
              };
              script = ''
                set -euo pipefail
                token=$(${lib.getExe config.services.gitea.package} actions generate-runner-token)
                echo "TOKEN=$token" > /var/lib/gitea-registration/${name}
              '';
              unitConfig.ConditionPathExists = [ "!/var/lib/gitea-registration/${name}" ];
              serviceConfig = {
                User = config.services.gitea.user;
                Group = config.services.gitea.group;
                StateDirectory = "gitea-registration";
                Type = "oneshot";
                RemainAfterExit = true;
              };
            });

        # Podman container runtime
        virtualisation.podman = {
          enable = true;
          extraPackages = [ pkgs.zfs ];
        };

        # ZFS-backed container storage
        virtualisation.containers.storage.settings = {
          storage.driver = "zfs";
          storage.graphroot = "/var/lib/containers/storage";
          storage.runroot = "/run/containers/storage";
          storage.options.zfs.fsname = "zroot/root/podman";
        };

        # DNS configuration for podman (systemd-resolved compatibility)
        virtualisation.containers.containersConf.settings = {
          containers.dns_servers = [
            "8.8.8.8"
            "8.8.4.4"
          ];
        };
      }
      {
        # N systemd service overrides via genAttrs
        systemd.services =
          lib.genAttrs (builtins.genList (n: "gitea-runner-nix${builtins.toString n}") numInstances)
            (name: {
              after = [
                "${name}-token.service"
                "gitea-runner-nix-image.service"
              ];
              requires = [
                "${name}-token.service"
                "gitea-runner-nix-image.service"
              ];
            });

        # N runner instances via genAttrs
        services.gitea-actions-runner.instances =
          lib.genAttrs (builtins.genList (n: "nix${builtins.toString n}") numInstances)
            (name: {
              enable = true;
              name = "magnetite";
              url = config.services.gitea.settings.server.ROOT_URL;
              tokenFile = "/var/lib/gitea-registration/gitea-runner-${name}-token";
              labels = [ "nix:docker://gitea-runner-nix" ];
              settings = {
                container.options = "-e NIX_BUILD_SHELL=/bin/bash -e PAGER=cat -e PATH=/bin -e SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt -v /nix:/nix -v ${storeDeps}/bin:/bin -v ${storeDeps}/etc/ssl:/etc/ssl --user nixuser";
                container.network = "host";
                container.valid_volumes = [
                  "/nix"
                  "${storeDeps}/bin"
                  "${storeDeps}/etc/ssl"
                ];
              };
            });
      }
    ];
}
