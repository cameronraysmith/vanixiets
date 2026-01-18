{ ... }:
{
  flake.modules.darwin.colima =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.colima;

      # Submodule type for port forward configuration per cluster
      portForwardSubmodule = lib.types.submodule {
        options = {
          ip = lib.mkOption {
            type = lib.types.str;
            description = "Target VM IP address (e.g., '192.100.0.10')";
            example = "192.100.0.10";
          };

          apiPort = lib.mkOption {
            type = lib.types.port;
            default = 6443;
            description = "Kubernetes API server port on macOS localhost";
          };

          httpPort = lib.mkOption {
            type = lib.types.port;
            default = 8080;
            description = "Ingress HTTP port on macOS localhost";
          };

          httpsPort = lib.mkOption {
            type = lib.types.port;
            default = 8443;
            description = "Ingress HTTPS port on macOS localhost";
          };

          sshPort = lib.mkOption {
            type = lib.types.port;
            default = 2210;
            description = "SSH port on macOS localhost";
          };
        };
      };

      # Generate a systemd user service unit for socat port forwarding
      mkSocatService = name: localPort: remoteIp: remotePort: ''
        [Unit]
        Description=Port forward ${name} (localhost:${toString localPort} -> ${remoteIp}:${toString remotePort})
        After=network.target

        [Service]
        Type=simple
        ExecStart=/usr/bin/socat TCP-LISTEN:${toString localPort},fork,reuseaddr,bind=0.0.0.0 TCP:${remoteIp}:${toString remotePort}
        Restart=always
        RestartSec=5

        [Install]
        WantedBy=default.target
      '';

      # Generate all socat services for a cluster
      mkClusterServices = clusterName: clusterCfg:
        let
          sanitizedName = builtins.replaceStrings [ "-" ] [ "_" ] clusterName;
        in
        {
          "${sanitizedName}_api" = mkSocatService "${clusterName}-api" clusterCfg.apiPort clusterCfg.ip 6443;
          "${sanitizedName}_http" = mkSocatService "${clusterName}-http" clusterCfg.httpPort clusterCfg.ip 80;
          "${sanitizedName}_https" = mkSocatService "${clusterName}-https" clusterCfg.httpsPort clusterCfg.ip 443;
          "${sanitizedName}_ssh" = mkSocatService "${clusterName}-ssh" clusterCfg.sshPort clusterCfg.ip 22;
        };

      # Merge all cluster services
      allServices = lib.foldlAttrs (acc: name: value: acc // mkClusterServices name value) { } cfg.portForwards;

      # Generate Lima provision script for socat services
      provisionScript =
        let
          serviceFiles = lib.mapAttrsToList (
            name: content: ''
              cat > ~/.config/systemd/user/socat-${name}.service << 'SERVICEEOF'
              ${content}
              SERVICEEOF
              systemctl --user enable socat-${name}.service
            ''
          ) allServices;
          serviceNames = lib.mapAttrsToList (name: _: "socat-${name}.service") allServices;
        in
        ''
          #!/bin/bash
          set -euo pipefail

          # Create systemd user directory
          mkdir -p ~/.config/systemd/user

          # Write service files
          ${lib.concatStringsSep "\n" serviceFiles}

          # Reload and start all services
          systemctl --user daemon-reload
          ${lib.concatMapStringsSep "\n" (svc: "systemctl --user start ${svc} || true") serviceNames}

          echo "Port forwarding services configured:"
          systemctl --user list-units 'socat-*.service' --no-pager || true
        '';

      # Generate Lima port forwards (macOS -> Colima VM)
      limaPortForwards = lib.concatLists (
        lib.mapAttrsToList (
          _: clusterCfg: [
            {
              guestPort = clusterCfg.apiPort;
              hostIP = "127.0.0.1";
            }
            {
              guestPort = clusterCfg.httpPort;
              hostIP = "127.0.0.1";
            }
            {
              guestPort = clusterCfg.httpsPort;
              hostIP = "127.0.0.1";
            }
            {
              guestPort = clusterCfg.sshPort;
              hostIP = "127.0.0.1";
            }
          ]
        ) cfg.portForwards
      );

      # Generate colima.yaml content with port forwards and provision scripts
      colimaYamlContent = lib.generators.toYAML { } (
        {
          cpu = cfg.cpu;
          memory = cfg.memory;
          disk = cfg.disk;
          arch = cfg.arch;
          runtime = cfg.runtime;
          vmType = cfg.vmType;
          mountType = cfg.mountType;
          rosetta = cfg.rosetta && cfg.arch == "aarch64";
          nestedVirtualization = cfg.nestedVirtualization;
        }
        // lib.optionalAttrs (cfg.portForwards != { }) {
          portForwards = limaPortForwards;
          provision = [
            {
              mode = "system";
              script = ''
                #!/bin/bash
                # Install socat if not present
                if ! command -v socat &> /dev/null; then
                  apt-get update && apt-get install -y socat
                fi
              '';
            }
            {
              mode = "user";
              script = provisionScript;
            }
          ];
        }
      );

      # Helper script to initialize Colima with configured settings
      colima-init = pkgs.writeShellApplication {
        name = "colima-init";
        runtimeInputs = [ pkgs.colima ];
        text = ''
          PROFILE="${cfg.profile}"
          COLIMA_DIR="$HOME/.colima/$PROFILE"

          echo "Initializing Colima profile: $PROFILE"
          echo "Runtime: ${cfg.runtime}"
          echo "CPU: ${toString cfg.cpu} cores"
          echo "Memory: ${toString cfg.memory} GiB"
          echo "Disk: ${toString cfg.disk} GiB"
          echo "Architecture: ${cfg.arch}"
          echo "VM Type: ${cfg.vmType}"
          echo "Mount Type: ${cfg.mountType}"
          ${lib.optionalString (cfg.portForwards != { }) ''
            echo "Port forwards: ${lib.concatStringsSep ", " (lib.attrNames cfg.portForwards)}"
          ''}
          echo ""

          # Create profile directory and write colima.yaml
          mkdir -p "$COLIMA_DIR"
          cat > "$COLIMA_DIR/colima.yaml" << 'COLIMAYAMLEOF'
          ${colimaYamlContent}
          COLIMAYAMLEOF

          echo "Wrote configuration to $COLIMA_DIR/colima.yaml"
          echo ""

          colima start \
            --profile "$PROFILE" \
            --runtime ${cfg.runtime} \
            --cpus ${toString cfg.cpu} \
            --memory ${toString cfg.memory} \
            --disk ${toString cfg.disk} \
            --arch ${cfg.arch} \
            --vm-type ${cfg.vmType} \
            --mount-type ${cfg.mountType} \
            ${lib.optionalString (cfg.rosetta && cfg.arch == "aarch64") "--vz-rosetta"}

          echo ""
          echo "Colima initialized successfully!"
          echo "Profile: $PROFILE"
          echo "Status:"
          colima status --profile "$PROFILE"
        '';
      };

      # Helper script to stop Colima
      colima-stop = pkgs.writeShellApplication {
        name = "colima-stop";
        runtimeInputs = [ pkgs.colima ];
        text = ''
          colima stop --profile "${cfg.profile}"
        '';
      };

      # Helper script to restart Colima
      colima-restart = pkgs.writeShellApplication {
        name = "colima-restart";
        runtimeInputs = [ pkgs.colima ];
        text = ''
          echo "Restarting Colima profile: ${cfg.profile}"
          colima restart --profile "${cfg.profile}"
        '';
      };

    in
    {
      options.services.colima = {
        enable = lib.mkEnableOption "Colima container runtime";

        runtime = lib.mkOption {
          type = lib.types.enum [
            "docker"
            "containerd"
            "incus"
          ];
          default = "incus";
          description = "Container runtime to use";
        };

        profile = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Colima profile name";
        };

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Automatically start Colima on system boot via launchd";
        };

        cpu = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Number of CPU cores";
        };

        memory = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Memory in GiB";
        };

        disk = lib.mkOption {
          type = lib.types.int;
          default = 60;
          description = "Disk size in GiB";
        };

        arch = lib.mkOption {
          type = lib.types.enum [
            "aarch64"
            "x86_64"
          ];
          default = pkgs.stdenv.hostPlatform.parsed.cpu.name;
          defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.parsed.cpu.name";
          description = "VM architecture";
        };

        vmType = lib.mkOption {
          type = lib.types.enum [
            "qemu"
            "vz"
          ];
          default = "vz";
          description = "VM type (vz uses macOS Virtualization.framework)";
        };

        rosetta = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Rosetta 2 for x86_64 emulation (macOS 13+, aarch64 only)";
        };

        nestedVirtualization = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable nested virtualization for running VMs inside the Colima VM.
            Requires macOS 15+ (Sequoia) and Apple M3/M4 chip.
            Required for incus VMs (KVM support).
          '';
        };

        mountType = lib.mkOption {
          type = lib.types.enum [
            "9p"
            "sshfs"
            "virtiofs"
          ];
          default = "virtiofs";
          description = "Volume mount driver";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = lib.literalExpression "[ pkgs.kubectl pkgs.docker-compose ]";
          description = "Additional packages to install (e.g., runtime CLIs)";
        };

        portForwards = lib.mkOption {
          type = lib.types.attrsOf portForwardSubmodule;
          default = { };
          example = lib.literalExpression ''
            {
              k3s-dev = {
                ip = "192.100.0.10";
                apiPort = 6443;
                httpPort = 8080;
                httpsPort = 8443;
                sshPort = 2210;
              };
              k3s-capi = {
                ip = "192.100.0.11";
                apiPort = 6444;
                httpPort = 8081;
                httpsPort = 8444;
                sshPort = 2211;
              };
            }
          '';
          description = ''
            Port forwards from macOS localhost to incus VM IPs inside the Colima VM.
            Each entry creates Lima port forwards (macOS -> Colima VM) and socat
            systemd services (Colima VM -> incus VM) for the specified ports.

            The complete forwarding path is:
            macOS localhost:port -> Lima -> Colima VM:port -> socat -> incus VM IP:target

            Target ports inside incus VMs are fixed:
            - Kubernetes API: 6443
            - HTTP ingress: 80
            - HTTPS ingress: 443
            - SSH: 22
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Validate configuration
        assertions = [
          {
            assertion = cfg.rosetta -> (cfg.arch == "aarch64");
            message = "services.colima.rosetta requires services.colima.arch = \"aarch64\"";
          }
          {
            assertion = (cfg.vmType == "vz") -> pkgs.stdenv.hostPlatform.isAarch64;
            message = "services.colima.vmType = \"vz\" requires Apple Silicon (aarch64-darwin)";
          }
        ];

        # Install Colima and runtime packages
        environment.systemPackages =
          with pkgs;
          [
            colima
            colima-init
            colima-stop
            colima-restart
          ]
          ++ lib.optional (cfg.runtime == "docker" || cfg.runtime == "containerd") docker
          # Note: incus package is Linux-only; incus CLI is available inside the VM
          ++ cfg.extraPackages;

        # Activation script to inform user about Colima state
        system.activationScripts.colima.text = ''
          COLIMA_PROFILE="${cfg.profile}"
          COLIMA_BIN="${pkgs.colima}/bin/colima"

          # Check if profile exists and is running
          if $COLIMA_BIN list 2>/dev/null | grep -q "^$COLIMA_PROFILE"; then
            echo "Colima profile '$COLIMA_PROFILE' exists"

            # Note: We don't automatically restart to apply config changes
            # User must run: colima restart --profile ${cfg.profile}
            # This prevents unexpected VM restarts during system activation
            echo "Note: If you've changed Colima configuration, run 'colima-restart' to apply changes"
          else
            echo "Colima profile '$COLIMA_PROFILE' will be created on first start"
            echo "Run: colima-init"
          fi
        '';

        # Optional: launchd service for auto-start
        launchd.user.agents.colima = lib.mkIf cfg.autoStart {
          serviceConfig = {
            ProgramArguments = [
              "${pkgs.colima}/bin/colima"
              "start"
              "--profile"
              cfg.profile
              "--runtime"
              cfg.runtime
              "--cpus"
              (toString cfg.cpu)
              "--memory"
              (toString cfg.memory)
              "--disk"
              (toString cfg.disk)
              "--arch"
              cfg.arch
              "--vm-type"
              cfg.vmType
              "--mount-type"
              cfg.mountType
            ]
            ++ lib.optional (cfg.rosetta && cfg.arch == "aarch64") "--vz-rosetta";

            RunAtLoad = true;
            KeepAlive = false; # Don't restart if Colima stops
            StandardErrorPath = "/tmp/colima-${cfg.profile}.err.log";
            StandardOutPath = "/tmp/colima-${cfg.profile}.out.log";
          };
        };

        # Environment setup for Docker runtime
        environment.variables = lib.mkIf (cfg.runtime == "docker" || cfg.runtime == "containerd") {
          DOCKER_HOST = "unix:///Users/${config.system.primaryUser}/.colima/${cfg.profile}/docker.sock";
        };
      };
    };
}
