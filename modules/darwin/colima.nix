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

      # Helper script to initialize Colima with configured settings
      colima-init = pkgs.writeShellApplication {
        name = "colima-init";
        runtimeInputs = [ pkgs.colima ];
        text = ''
          PROFILE="${cfg.profile}"

          echo "Initializing Colima profile: $PROFILE"
          echo "Runtime: ${cfg.runtime}"
          echo "CPU: ${toString cfg.cpu} cores"
          echo "Memory: ${toString cfg.memory} GiB"
          echo "Disk: ${toString cfg.disk} GiB"
          echo "Architecture: ${cfg.arch}"
          echo "VM Type: ${cfg.vmType}"
          echo "Mount Type: ${cfg.mountType}"
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
