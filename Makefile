# infra bootstrap makefile
#
# tl;dr:
#
# 1. Run 'make bootstrap' to install nix and direnv
# 2. Run 'make verify' to check your installation
# 3. Derive your sops age key from your Bitwarden SSH key (first time only; see
#    "Workstation age key" in packages/docs/src/content/docs/guides/secrets-management.md)
# 4. Run 'nix develop' to enter the development environment
# 5. Use 'just ...' to run configuration tasks
#
# This Makefile helps bootstrap a development environment with nix and direnv.
# After bootstrap is complete, see the justfile for managing configurations.

.DEFAULT_GOAL := help

#-------
##@ help
#-------

# based on "https://gist.github.com/prwhite/8168133?permalink_comment_id=4260260#gistcomment-4260260"
.PHONY: help
help: ## Display this help. (Default)
	@grep -hE '^(##@|[A-Za-z0-9_ \-]*?:.*##).*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; /^##@/ {print "\n" substr($$0, 5)} /^[A-Za-z0-9_ \-]*?:.*##/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

help-sort: ## Display alphabetized version of help (no section headings).
	@grep -hE '^[A-Za-z0-9_ \-]*?:.*##.*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; /^[A-Za-z0-9_ \-]*?:.*##/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

HELP_TARGETS_PATTERN ?= test
help-targets: ## Print commands for all targets matching a given pattern. Copy this example into your shell:
help-targets: ## Copy this example into your shell:
help-targets: ## eval "$(make help-targets HELP_TARGETS_PATTERN=bootstrap | sed 's/\x1b\[[0-9;]*m//g')"
	@make help-sort | awk '{print $$1}' | grep '$(HELP_TARGETS_PATTERN)' | xargs -I {} printf "printf '___\n\n{}:\n\n'\nmake -n {}\nprintf '\n'\n"

# catch-all pattern rule
#
# This rule matches any targets that are not explicitly defined in this
# Makefile. It prevents 'make' from failing due to unrecognized targets, which
# is particularly useful when passing arguments or targets to sub-Makefiles. The
# '@:' command is a no-op, indicating that nothing should be done for these
# targets within this Makefile.
#
%:
	@:

#-------
##@ bootstrap
#-------

.PHONY: bootstrap-prep-darwin
bootstrap-prep-darwin: ## Install darwin prerequisites (Xcode CLI tools + Homebrew) before 'make bootstrap'
	@printf "Installing darwin prerequisites...\n\n"
	@printf "Step 1: Xcode Command Line Tools\n"
	@if xcode-select -p &>/dev/null; then \
		printf "  ● Xcode CLI tools already installed\n"; \
	else \
		printf "  Installing Xcode CLI tools (this will open a dialog)...\n"; \
		xcode-select --install; \
		printf "  ⏳ Wait for installation to complete, then re-run this target\n"; \
		exit 1; \
	fi
	@printf "\nStep 2: Homebrew\n"
	@if command -v brew &>/dev/null; then \
		printf "  ● Homebrew already installed\n"; \
	else \
		printf "  Installing Homebrew...\n"; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
	fi
	@printf "\n● Darwin prerequisites complete!\n"
	@printf "Next: Run 'make bootstrap' to install Nix\n"

.PHONY: bootstrap
bootstrap: ## Main bootstrap target that runs all necessary setup steps
bootstrap: install-nix install-direnv
	@printf "\n● Bootstrap of nix and direnv complete!\n\n"
	@printf "Next steps:\n"
	@echo "1. Start a new shell session (to load nix in PATH)"
	@echo "2. Run 'make verify' to check your installation"
	@echo "3. Derive your sops age key from your Bitwarden SSH key (first time only):"
	@echo "   see 'Workstation age key' in packages/docs/src/content/docs/guides/secrets-management.md"
	@echo "4. Run 'nix develop' to enter the development environment"
	@echo ""
	@printf "Optional: Auto-activate development environment with direnv\n"
	@echo "  - See https://direnv.net/docs/hook.html to add direnv to your shell"
	@echo "  - Start a new shell session"
	@echo "  - cd out and back into the project directory"
	@echo "  - Run 'direnv allow' to activate"
	@echo ""
	@printf "For detailed documentation, see docs/new-user-host.md\n"

.PHONY: install-nix
# Download platform-specific binary directly from GitHub Releases.
# This bypasses both the Fastly CDN (HTTP 618 errors) and the shell wrapper
# (which has template placeholders that aren't filled in for raw source files).
# To update version, change NIX_INSTALLER_VERSION below.
# Note: versioning jumped from 0.27.0 to 3.11.3, then back to the 2.x line when
# NixOS/nix-installer removed the 3.x tags (repo renamed from experimental-nix-installer).
# The installer tag tracks the Nix it embeds (flake.nix: nix.url = github:NixOS/nix/<tag>),
# so this pin is also the nix version bootstrap lands.
# https://github.com/NixOS/nix-installer/releases
#
# nix-installer 2.35.1 writes /etc/nix/nix.conf in setup_standard_config
# (src/action/common/place_nix_configuration.rs:98-154). Its defaults are
# extra-experimental-features = nix-command, auto-optimise-store = true (Linux
# only), always-allow-substitutes = true, max-jobs = auto, and
# bash-prompt-prefix. flakes is not among them: place_nix_configuration.rs:105-112
# appends flakes, and :126-131 adds extra-nix-path, only when --enable-flakes is
# passed (src/settings.rs:193-204, present since tag 2.34.4). The only other way
# to get flakes is an interactive prompt that --no-confirm suppresses
# (src/cli/subcommand/install/mod.rs:119-137), so a non-interactive install
# without the flag lands nix-command alone. Releases through 2.33.0 wrote
# nix-command flakes unconditionally, which is why the flag is needed at any
# 2.34.4-or-later pin and was not needed before that.
#
# flakes is not optional here: install-direnv resolves nixpkgs#direnv and
# 'make verify' runs 'nix flake --help'.
#
# nix-command and flakes is also the set every host declares
# (modules/system/nix-settings.nix:9-12 for NixOS, modules/darwin/base.nix:17-20
# for darwin), so bootstrap and the fleet agree. auto-allocate-uids, which
# modules/darwin/nix-settings.nix:55-59 merges into the darwin set, is
# deliberately omitted. The experimental feature only makes Nix accept the
# setting of the same name, and the setting is true nowhere in this repo except
# magnetite and pyrite (modules/machines/nixos/{magnetite,pyrite}/default.nix),
# which pair it with extra-system-features = uid-range for systemd-nspawn tests. That pairing is
# belt-and-braces: nix's own getDefaultSystemFeatures
# (nix src/libstore/globals.cc:217-239) already inserts uid-range
# unconditionally on linux. Enabling the feature alone
# changes no build behaviour, and the daemonless mode below has no daemon to
# allocate UIDs at all. Bootstrap's nix.conf is transient regardless:
# the first 'just activate' regenerates it from the host's own modules.
#
# trusted-users lets nix accept flake-specified substituters and public keys
# without prompts or warnings. Nix's own default is `root` alone, so without
# this the person who ran bootstrap cannot use the flake's caches and rebuilds
# everything from source. The three admin groups are one per platform
# convention - @admin on darwin, @wheel on nixos/fedora/arch, @sudo on
# debian/ubuntu - because none of the three exists everywhere and nix ignores
# the ones that do not resolve. Groups rather than $(USER) so the value is
# static and stays right for a second admin on the same host; trusting them is
# no escalation, since a sudoer is already root-equivalent.
NIX_INSTALLER_VERSION := 2.35.1

# A usable systemd runtime is detected by the single existence test that
# /run/systemd/system is present if and only if the machine booted under systemd
# (sd_booted(3)). nix-installer makes the same one test in check_systemd_active
# (src/planner/linux.rs:244-254) and names --init none in its own failure text.
# Overridable so both branches of the check can be expanded on a host that does
# not match.
#
# The resulting $$PLANNER_ARGS is expanded unquoted on purpose: it must become
# either three words or no word at all, and quoting it would pass an empty
# argument to the installer on every systemd host.
SYSTEMD_RUNTIME_DIR ?= /run/systemd/system
install-nix: ## Install Nix using the NixOS community installer
	@echo "Installing Nix..."
	@if command -v nix >/dev/null 2>&1; then \
		echo "Nix is already installed."; \
	else \
		case "$$(uname -s)-$$(uname -m)" in \
			Linux-x86_64)  PLATFORM="x86_64-linux" ;; \
			Linux-aarch64) PLATFORM="aarch64-linux" ;; \
			Darwin-arm64)  PLATFORM="aarch64-darwin" ;; \
			*) echo "Unsupported platform: $$(uname -s)-$$(uname -m)"; exit 1 ;; \
		esac; \
		PLANNER_ARGS=""; \
		case "$$PLATFORM" in \
			*-linux) \
				if [ ! -d "$(SYSTEMD_RUNTIME_DIR)" ]; then \
					if [ "$$(id -u)" -ne 0 ]; then \
						echo "Cannot install Nix: no systemd runtime at $(SYSTEMD_RUNTIME_DIR), and this process is uid $$(id -u) rather than root."; \
						echo ""; \
						echo "Without systemd the only mode this installer supports is 'install linux --init none', which creates a system-wide /nix and the build users but no daemon, leaving the store writable only by root. Running it as a non-root user does not fail early: nix-installer re-executes itself under sudo, and the Nix it leaves behind is unusable by uid $$(id -u)."; \
						echo ""; \
						echo "A true single-user installation - /nix owned by the invoking user, no build users, no daemon - is not implemented by this Makefile. Re-run as root, or install Nix manually:"; \
						echo "  https://nix.dev/manual/nix/stable/installation/installing-binary"; \
						exit 1; \
					fi; \
					echo "No systemd runtime at $(SYSTEMD_RUNTIME_DIR); installing root-only Nix with no daemon."; \
					PLANNER_ARGS="linux --init none"; \
				fi ;; \
		esac; \
		INSTALLER_URL="https://github.com/NixOS/nix-installer/releases/download/$(NIX_INSTALLER_VERSION)/nix-installer-$$PLATFORM"; \
		echo "Platform: $$PLATFORM"; \
		echo "Downloading from: $$INSTALLER_URL"; \
		max_attempts=3; \
		attempt=1; \
		while [ $$attempt -le $$max_attempts ]; do \
			echo "Attempt $$attempt of $$max_attempts..."; \
			if curl --proto '=https' --tlsv1.2 -sSf -L --retry 3 --retry-delay 5 \
				"$$INSTALLER_URL" -o /tmp/nix-installer && chmod +x /tmp/nix-installer; then \
				/tmp/nix-installer install $$PLANNER_ARGS --no-confirm \
					--enable-flakes \
					--extra-conf "trusted-users = root @admin @wheel @sudo" && break; \
			fi; \
			attempt=$$((attempt + 1)); \
			if [ $$attempt -le $$max_attempts ]; then \
				echo "Download or install failed, waiting 10 seconds before retry..."; \
				sleep 10; \
			fi; \
		done; \
		if [ $$attempt -gt $$max_attempts ]; then \
			echo "Failed to install nix after $$max_attempts attempts"; \
			exit 1; \
		fi; \
	fi

.PHONY: uninstall-nix
# The inverse of install-nix, and the only supported one: nix-installer records
# its plan in /nix/receipt.json and reverses exactly that plan
# (src/cli/subcommand/uninstall.rs), so hand-removing /nix leaves the build
# users, the daemon unit and the shell profile snippets behind.
#
# The uninstaller must be the copy the install left at /nix/nix-installer, not
# NIX_INSTALLER_VERSION: the receipt is version-checked, and a binary older than
# the plan refuses to parse it and prints that same path as the fix
# (uninstall.rs:110-149). The pinned release is only a fallback for a host whose
# copy is gone, where it works when the receipt is not newer than the pin.
#
# No sudo: ensure_root re-execs the process under sudo --set-home itself
# (src/cli/mod.rs:133-141), matching install-nix.
#
# Deliberately not wired into any aggregate target - bootstrap is the composition
# worth having - but the pair does compose to the identity map, which is how a
# pin bump gets verified on a real host rather than only in a container:
#
#   make uninstall-nix CONFIRM=1 && make bootstrap && make verify
uninstall-nix: ## Uninstall Nix by reverting /nix/receipt.json (CONFIRM=1 to skip the prompt)
	@echo "Uninstalling Nix..."
	@if [ ! -e /nix/receipt.json ]; then \
		if [ -e /nix ]; then \
			echo "No install receipt at /nix/receipt.json, but /nix exists: this Nix was not installed by nix-installer, so refusing to guess at how to remove it."; \
			exit 1; \
		fi; \
		echo "Nix is not installed."; \
	else \
		UNINSTALLER=/nix/nix-installer; \
		if [ ! -x "$$UNINSTALLER" ]; then \
			case "$$(uname -s)-$$(uname -m)" in \
				Linux-x86_64)  PLATFORM="x86_64-linux" ;; \
				Linux-aarch64) PLATFORM="aarch64-linux" ;; \
				Darwin-arm64)  PLATFORM="aarch64-darwin" ;; \
				*) echo "Unsupported platform: $$(uname -s)-$$(uname -m)"; exit 1 ;; \
			esac; \
			echo "No installer at /nix/nix-installer; falling back to the pinned $(NIX_INSTALLER_VERSION) release."; \
			curl --proto '=https' --tlsv1.2 -sSf -L --retry 3 --retry-delay 5 \
				"https://github.com/NixOS/nix-installer/releases/download/$(NIX_INSTALLER_VERSION)/nix-installer-$$PLATFORM" \
				-o /tmp/nix-installer && chmod +x /tmp/nix-installer; \
			UNINSTALLER=/tmp/nix-installer; \
		fi; \
		if [ "$(CONFIRM)" = "1" ]; then \
			"$$UNINSTALLER" uninstall --no-confirm; \
		else \
			"$$UNINSTALLER" uninstall; \
		fi; \
	fi

.PHONY: install-direnv
install-direnv: ## Install direnv (requires nix to be installed first)
	@echo "Installing direnv..."
	@if command -v direnv >/dev/null 2>&1; then \
		echo "direnv is already installed."; \
	else \
		. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix profile install nixpkgs#direnv; \
	fi
	@echo ""
	@echo "See https://direnv.net/docs/hook.html if you would like to add direnv to your shell"

#-------
##@ verify
#-------

.PHONY: verify
verify: ## Verify nix installation and environment setup
	@printf "\nVerifying installation...\n\n"
	@printf "Checking nix installation: "
	@if command -v nix >/dev/null 2>&1; then \
		printf "● nix found at %s\n" "$$(command -v nix)"; \
		nix --version; \
	else \
		printf "⊘ nix not found\n"; \
		printf "Run 'make install-nix' to install nix\n"; \
		exit 1; \
	fi
	@printf "\nChecking nix flakes support: "
	@if nix flake --help >/dev/null 2>&1; then \
		printf "● flakes enabled\n"; \
	else \
		printf "⊘ flakes not enabled\n"; \
		exit 1; \
	fi
	@printf "\nChecking direnv installation: "
	@if command -v direnv >/dev/null 2>&1; then \
		printf "● direnv found\n"; \
	else \
		printf "⚠️  direnv not found (optional but recommended)\n"; \
		printf "Run 'make install-direnv' to install\n"; \
	fi
	@printf "\nChecking flake validity: "
	@if nix flake metadata . >/dev/null 2>&1; then \
		printf "● flake is valid\n"; \
	else \
		printf "⊘ flake has errors\n"; \
		exit 1; \
	fi
	@printf "\nChecking devShell: "
	@if [ -n "$$CI" ]; then \
		if nix eval --accept-flake-config .#devShells.$$(nix eval --raw --impure --expr builtins.currentSystem).default --apply 'x: "ok"' >/dev/null 2>&1; then \
			printf "● devShell evaluates (build verified by checks-devshells job)\n"; \
		else \
			printf "⊘ devShell evaluation failed\n"; \
			exit 1; \
		fi; \
	else \
		if nix develop --accept-flake-config --command bash -c 'command -v age-keygen && command -v ssh-to-age && command -v sops && command -v just' >/dev/null 2>&1; then \
			printf "● age-keygen, ssh-to-age, sops, just available\n"; \
		else \
			printf "⊘ some tools missing from devShell\n"; \
			exit 1; \
		fi; \
	fi
	@printf "\n/etc/nix/nix.conf:\n"
	@printf "==================\n"
	@cat /etc/nix/nix.conf 2>/dev/null || printf "(file not found)\n"
	@printf "==================\n"
	@if [ -f /etc/nix/nix.custom.conf ]; then \
		printf "\n/etc/nix/nix.custom.conf:\n"; \
		printf "==================\n"; \
		cat /etc/nix/nix.custom.conf; \
		printf "==================\n"; \
	fi
	@printf "\n● All verification checks passed!\n\n"

#-------
##@ setup
#-------

.PHONY: check-secrets
check-secrets: ## Check if you can decrypt shared secrets (requires age key and admin setup)
	@printf "\nChecking secrets access...\n\n"
	@if [ ! -f ~/.config/sops/age/keys.txt ]; then \
		printf "⊘ No age key found. Derive it from your Bitwarden SSH key:\n"; \
		printf "  see 'Workstation age key' in packages/docs/src/content/docs/guides/secrets-management.md\n"; \
		exit 1; \
	fi
	@if nix develop --accept-flake-config --command sops -d secrets/shared.yaml >/dev/null 2>&1; then \
		printf "● Successfully decrypted shared secrets!\n"; \
		printf "You have proper access to the secrets system\n"; \
	else \
		printf "⊘ Cannot decrypt shared secrets\n"; \
		printf "Possible reasons:\n"; \
		printf "1. Admin hasn't added your key to .sops.yaml yet\n"; \
		printf "2. Admin hasn't run 'sops updatekeys' after adding you\n"; \
		printf "3. Your age key is incorrect\n"; \
		printf "\nSend your public key to admin:\n"; \
		age-keygen -y ~/.config/sops/age/keys.txt; \
		exit 1; \
	fi

#-------
##@ clean
#-------

.PHONY: clean
clean: ## Clean any temporary files or build artifacts
	@echo "Cleaning up..."
	@rm -rf result result-*
