# nix2container-native multi-arch manifest builder
#
# Creates and pushes multi-architecture Docker manifests using:
# - skopeo with nix: transport to push individual arch images directly from JSON manifests
# - podman to create and push the multi-arch manifest list
# - crane for efficient registry-side tagging
#
# Single-arch builds auto-detected and use simplified direct push (no manifest list).
#
# Usage:
#   mkMultiArchManifest {
#     name = "fd";
#     images = {
#       "x86_64-linux" = inputs.self.packages.x86_64-linux.fdContainer;
#       "aarch64-linux" = inputs.self.packages.aarch64-linux.fdContainer;
#     };
#     registry = {
#       name = "ghcr.io";
#       repo = "cameronraysmith/vanixiets/fd";
#       username = "cameronraysmith";
#       password = "$GITHUB_TOKEN";
#     };
#     version = "1.0.0";
#     branch = "main";
#     inherit skopeo podman;
#   }
{
  lib,
  writeShellApplication,
  coreutils,
  git,
  crane,
}:
{
  images,
  name,
  registry,
  version,
  tags ? [ ],
  branch ? "main",
  skopeo,
  podman,
}:
let
  # Compute final tags: always include version, add "latest" if on main branch
  parsedTags = [
    version
  ]
  ++ (if tags != [ ] then tags else (if branch == "main" then [ "latest" ] else [ ]));

  # Detect single-arch vs multi-arch scenario
  isSingleArch = lib.length (lib.attrNames images) == 1;

  # System to arch mapping for container platforms
  systemToArch = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  };

  # Generate per-arch image URIs for registry
  # Single-arch: push directly to primary tag (no arch suffix)
  # Multi-arch: push with arch suffix, then create manifest list
  archImages = lib.mapAttrs' (
    system: image:
    let
      arch = systemToArch.${system};
      primaryTag = lib.head parsedTags;
    in
    lib.nameValuePair arch {
      inherit system image arch;
      tag = if isSingleArch then primaryTag else "${version}-${arch}";
      uri = "${registry.name}/${registry.repo}:${
        if isSingleArch then primaryTag else "${version}-${arch}"
      }";
    }
  ) images;

  manifestName = "${registry.name}/${registry.repo}:${lib.head parsedTags}";

  skopeoExe = lib.getExe skopeo;
  podmanExe = lib.getExe podman;
  craneExe = lib.getExe crane;

in
assert lib.assertMsg (images != { }) "At least one image must be provided";
assert lib.assertMsg (parsedTags != [ ]) "At least one tag must be set";

writeShellApplication {
  name = "multi-arch-manifest-${name}";
  runtimeInputs = [
    skopeo
    podman
    crane
    coreutils
    git
  ];

  text = ''
        # Configure podman to use VFS storage driver (no user namespace requirement)
        # Required for GitHub Actions runners which restrict unprivileged user namespaces
        mkdir -p "$HOME/.config/containers"
        if [[ ! -f "$HOME/.config/containers/storage.conf" ]]; then
          cat > "$HOME/.config/containers/storage.conf" << 'STORAGECONF'
    [storage]
    driver = "vfs"
    runroot = "/tmp/containers-run"
    graphroot = "/tmp/containers-storage"
    STORAGECONF
        fi

        function cleanup {
          set -x

          ${podmanExe} manifest rm "${manifestName}" || true
          ${skopeoExe} logout "${registry.name}" || true
          ${craneExe} auth logout "${registry.name}" || true
        }
        trap cleanup EXIT

        set -x

        # Starting with Podman 5.x, a policy.json file is required.
        # If none exists, use skopeo's default permissive policy.
        if [[ ! -f "/etc/containers/policy.json" && ! -f "$HOME/.config/containers/policy.json" ]]; then
          echo "No policy found, using skopeo's default instead."
          install -Dm444 "${skopeo.policy}/default-policy.json" "$HOME/.config/containers/policy.json"
        fi

        # Login to registry once for all operations
        # Use skopeo for login to avoid podman rootless namespace issues on GitHub Actions
        set +x
        echo "Logging in to ${registry.name}"
        ${skopeoExe} login \
          --username "${registry.username}" \
          --password "${registry.password}" \
          "${registry.name}"
        set -x

        # Push each architecture image using skopeo nix: transport
        # This reads nix2container's JSON manifest and pushes layers directly
        ${lib.concatMapStringsSep "\n" (archImage: ''
          echo "Pushing ${archImage.arch} image to ${archImage.uri}"
          ${skopeoExe} copy \
            --dest-creds "${registry.username}:${registry.password}" \
            "nix:${archImage.image}" \
            "docker://${archImage.uri}"
        '') (lib.attrValues archImages)}

        ${lib.optionalString (!isSingleArch) ''
          # Remove existing manifest if present
          if ${podmanExe} manifest exists "${manifestName}"; then
            ${podmanExe} manifest rm "${manifestName}"
          fi

          # Create multi-arch manifest with OCI annotations
          ${podmanExe} manifest create \
            --annotation "org.opencontainers.image.created=$(${lib.getExe' coreutils "date"} --iso-8601=seconds)" \
            --annotation "org.opencontainers.image.revision=$(${lib.getExe git} rev-parse HEAD)" \
            --annotation "org.opencontainers.image.version=${version}" \
            --annotation "org.opencontainers.image.source=https://github.com/cameronraysmith/vanixiets" \
            "${manifestName}"

          # Add each arch-specific image to the manifest by digest
          # Podman fetches the digest from registry and adds to manifest list
          ${lib.concatMapStringsSep "\n" (archImage: ''
            ${podmanExe} manifest add "${manifestName}" "docker://${archImage.uri}"
          '') (lib.attrValues archImages)}

          set +x
          echo "Manifest: ${manifestName}"
          ${podmanExe} manifest inspect "${manifestName}"
          echo "Tags: ${toString parsedTags}"
          set -x

          # Push manifest to registry with primary tag
          ${podmanExe} manifest push \
            --all \
            --format v2s2 \
            "${manifestName}"
        ''}

        # Tag additional tags if present (skip the first tag which was already pushed)
        # crane tag is a registry-side metadata operation - no data transfer needed
        ${lib.optionalString (lib.length parsedTags > 1) ''
          # Login to crane for tagging operations
          set +x
          echo "crane login ${registry.name}"
          ${craneExe} auth login "${registry.name}" \
            --username "${registry.username}" \
            --password "${registry.password}"
          set -x
        ''}
        ${lib.concatMapStringsSep "\n" (tag: ''
          ${craneExe} tag \
            "${registry.name}/${registry.repo}:${lib.head parsedTags}" \
            "${tag}"
        '') (lib.tail parsedTags)}

        set +x
        ${
          if isSingleArch then
            ''
              echo "Successfully pushed single-arch image for ${name}"
            ''
          else
            ''
              echo "Successfully pushed multi-arch manifest for ${name}"
            ''
        }
        echo "Available at: ${registry.name}/${registry.repo}:${lib.head parsedTags}"
        ${lib.concatMapStringsSep "\n" (tag: ''
          echo "  Also tagged: ${registry.name}/${registry.repo}:${tag}"
        '') (lib.tail parsedTags)}
  '';
}
