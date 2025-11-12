# Epic 2: VPS Infrastructure Foundation (Phase 1 - cinnabar)

**Goal:** Deploy always-on Hetzner Cloud VPS infrastructure using validated patterns from Phase 0, establishing foundation for darwin host coordination

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on NixOS before darwin, provides stable zerotier controller independent of workstation power state, proves patterns on clan's native platform

**Timeline:** 1-2 weeks deployment + 1-2 weeks stability validation

**Success Criteria:**
- Hetzner Cloud VPS deployed and operational
- Complete infrastructure stack validated (terraform, disko, LUKS, zerotier, NixOS)
- Zerotier controller functional and reachable
- SSH access working with certificate-based authentication
- Clan vars deployed correctly to /run/secrets/
- Stable for 1-2 weeks minimum before Phase 2

**Note:** This phase transitions from test-clan (experimental) to production nix-config repository on clan branch.

---

## Story 2.1: Apply Phase 0 patterns to nix-config and setup terraform/terranix

As a system administrator,
I want to apply validated patterns from test-clan to production nix-config repository,
So that I can begin deploying real infrastructure with proven architectural patterns.

**Acceptance Criteria:**
1. nix-config repository on clan branch has flake inputs added: clan-core, import-tree, terranix, disko, srvos (following clan-core, flake-parts, nixpkgs)
2. modules/ directory created with dendritic structure: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
3. modules/flake-parts/clan.nix created with clan.meta.name = "nix-config"
4. Terranix flake module imported in flake.nix
5. modules/terranix/base.nix created with Hetzner Cloud provider configuration
6. Hetzner API token secret prepared for terraform authentication
7. Flake evaluates successfully: `nix flake check`

**Prerequisites:** Story 1.6 (Phase 0 GO/CONDITIONAL GO decision)

---

## Story 2.2: Create cinnabar host configuration with disko and LUKS

As a system administrator,
I want to create cinnabar NixOS configuration with declarative disk partitioning and encryption,
So that the VPS has secure storage and reproducible disk layout.

**Acceptance Criteria:**
1. modules/hosts/cinnabar/default.nix created using validated dendritic patterns from Phase 0
2. modules/hosts/cinnabar/disko.nix created with LUKS encryption configuration for root partition
3. Cinnabar added to clan inventory: tags = ["nixos" "vps" "cloud"], machineClass = "nixos"
4. Base system configuration applied: networking.hostName = "cinnabar", nix settings, state version
5. srvos hardening modules imported for server security baseline
6. Configuration builds successfully: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
7. Disko configuration validates: able to generate partitioning commands

**Prerequisites:** Story 2.1 (nix-config setup with terraform)

---

## Story 2.3: Configure zerotier controller and essential clan services for cinnabar

As a system administrator,
I want to configure zerotier controller role and essential services on cinnabar,
So that the VPS provides always-on network coordination and core infrastructure services.

**Acceptance Criteria:**
1. Clan service instance zerotier-local configured with controller role on cinnabar machine
2. Clan service instance sshd-clan configured with server role on cinnabar, client role on all machines
3. Clan service instance emergency-access configured with default role (not on VPS, workstations only)
4. Clan service instance users-root configured for cinnabar root user access
5. Zerotier network ID prepared/documented for use across all machines
6. SSH CA certificate configuration included in sshd-clan instance
7. Service instance configuration validates in clan inventory: `nix eval .#clan.inventory.instances --json | jq .`

**Prerequisites:** Story 2.2 (cinnabar host configuration)

---

## Story 2.4: Initialize clan secrets and generate vars for cinnabar

As a system administrator,
I want to initialize clan secrets infrastructure and generate vars for cinnabar,
So that the VPS has properly encrypted secrets deployed via clan vars system.

**Acceptance Criteria:**
1. Clan secrets initialized in nix-config: age keys generated for admins group
2. User age key added to admins group: `clan secrets groups add-user admins <username>`
3. Hetzner API token added as clan secret for terraform authentication
4. Clan vars generated for cinnabar: `nix run nixpkgs#clan-cli -- vars generate cinnabar`
5. SSH host keys generated in sops/machines/cinnabar/secrets/sshd.* (encrypted)
6. Zerotier identity generated if needed
7. All vars generation succeeds without errors
8. Vars structure validated: sops/machines/cinnabar/{secrets,facts}/ populated

**Prerequisites:** Story 2.3 (clan services configured)

---

## Story 2.5: Deploy cinnabar VPS via terraform and clan machines install

As a system administrator,
I want to provision cinnabar on Hetzner Cloud and install NixOS,
So that the VPS infrastructure is operational and ready for validation.

**Acceptance Criteria:**
1. Terraform configuration generated: `nix run .#terraform.terraform -- init`
2. Terraform plan reviewed: `nix run .#terraform.terraform -- plan`
3. VPS provisioned on Hetzner Cloud CX53: `nix run .#terraform.terraform -- apply`
4. SSH access confirmed to fresh VPS with terraform-provided credentials
5. NixOS installed via clan: `clan machines install cinnabar` (automated installation with disko partitioning)
6. System boots successfully with LUKS encryption
7. Able to SSH into cinnabar post-installation with clan-managed SSH keys
8. Initial system activation successful

**Prerequisites:** Story 2.4 (secrets and vars initialized)

---

## Story 2.6: Validate cinnabar infrastructure and zerotier controller

As a system administrator,
I want to validate all cinnabar infrastructure components are operational,
So that I can confirm the VPS foundation is stable before darwin host migration.

**Acceptance Criteria:**
1. SSH access functional: `ssh root@<cinnabar-zerotier-ip>` works with certificate-based auth
2. Zerotier controller operational: `ssh root@<cinnabar-ip> "zerotier-cli info"` shows controller status
3. Zerotier network created and accessible: `zerotier-cli listnetworks` shows network ID
4. Clan vars deployed correctly: `ssh root@<cinnabar-ip> "ls -la /run/secrets/"` shows sshd keys, proper permissions
5. Emergency access working if needed: root access recovery mechanism validated
6. System stable: no critical errors in journalctl logs
7. Terraform state preserved: able to run `terraform plan` and see no changes
8. Complete infrastructure stack validated: dendritic + clan + terraform + hetzner + disko + LUKS + zerotier + NixOS all operational

**Stability gate:** Monitor cinnabar for 1-2 weeks. No critical issues → proceed to Phase 2 (blackphos migration)

**Prerequisites:** Story 2.5 (cinnabar deployed)

---
