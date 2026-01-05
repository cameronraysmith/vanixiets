# nix2container-native multi-arch manifest builder
#
# Creates and pushes multi-architecture Docker manifests using:
# - skopeo with nix: transport to push individual arch images directly from JSON manifests
# - crane to create manifest lists and perform registry-side tagging
#
# Single-arch builds auto-detected and use simplified direct push (no manifest list).
#
# Note: We use skopeo for image push because it has the nix: transport that reads
# nix2container's JSON manifests. We use crane for manifest list creation because
# it's lightweight (pure Go, no container runtime) and works on GitHub Actions
# without storage driver workarounds that podman requires.
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
#     inherit skopeo;
#   }
{
  lib,
  writeShellApplication,
  coreutils,
  git,
  crane,
  jq,
}:
{
  images,
  name,
  registry,
  version,
  tags ? [ ],
  branch ? "main",
  skopeo,
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
  repoBase = "${registry.name}/${registry.repo}";

  skopeoExe = lib.getExe skopeo;
  craneExe = lib.getExe crane;
  jqExe = lib.getExe jq;

in
assert lib.assertMsg (images != { }) "At least one image must be provided";
assert lib.assertMsg (parsedTags != [ ]) "At least one tag must be set";

writeShellApplication {
  name = "multi-arch-manifest-${name}";
  runtimeInputs = [
    skopeo
    crane
    jq
    coreutils
    git
  ];

  text = ''
    function cleanup {
      set -x
      ${skopeoExe} logout "${registry.name}" || true
      ${craneExe} auth logout "${registry.name}" || true
    }
    trap cleanup EXIT

    set -x

    # skopeo requires a policy.json file for container operations
    if [[ ! -f "/etc/containers/policy.json" && ! -f "$HOME/.config/containers/policy.json" ]]; then
      echo "No policy found, using skopeo's default instead."
      mkdir -p "$HOME/.config/containers"
      install -Dm444 "${skopeo.policy}/default-policy.json" "$HOME/.config/containers/policy.json"
    fi

    # Login to registries
    # skopeo for image push, crane for manifest list and tagging
    set +x
    echo "Logging in to ${registry.name}"
    ${skopeoExe} login \
      --username "${registry.username}" \
      --password "${registry.password}" \
      "${registry.name}"
    ${craneExe} auth login "${registry.name}" \
      --username "${registry.username}" \
      --password "${registry.password}"
    set -x

    # Push each architecture image using skopeo nix: transport
    # This reads nix2container's JSON manifest and pushes layers directly
    # Capture digest from each push to ensure manifest list references exact images pushed
    declare -A PUSHED_DIGESTS
    ${lib.concatMapStringsSep "\n" (archImage: ''
      echo "Pushing ${archImage.arch} image to ${archImage.uri}"
      # skopeo copy outputs "Copying blob..." lines then "Writing manifest to image destination"
      # Use --digestfile to reliably capture the pushed manifest digest
      DIGESTFILE=$(mktemp)
      ${skopeoExe} copy \
        --digestfile "$DIGESTFILE" \
        --dest-creds "${registry.username}:${registry.password}" \
        "nix:${archImage.image}" \
        "docker://${archImage.uri}"
      PUSHED_DIGESTS["${archImage.arch}"]=$(cat "$DIGESTFILE")
      rm "$DIGESTFILE"
      echo "Pushed ${archImage.arch} with digest: ''${PUSHED_DIGESTS["${archImage.arch}"]}"
    '') (lib.attrValues archImages)}

    ${lib.optionalString (!isSingleArch) ''
      # Create and push multi-arch manifest list using crane
      # crane index append creates a fresh index with the specified manifests
      # and pushes it in a single operation - no local storage needed
      echo "Creating multi-arch manifest list: ${manifestName}"
      ${craneExe} index append \
        ${
          lib.concatMapStringsSep " \\\n            " (
            archImage: ''-m "${repoBase}@''${PUSHED_DIGESTS["${archImage.arch}"]}"''
          ) (lib.attrValues archImages)
        } \
        --annotation "org.opencontainers.image.created=$(${lib.getExe' coreutils "date"} --iso-8601=seconds)" \
        --annotation "org.opencontainers.image.revision=$(${lib.getExe git} rev-parse HEAD)" \
        --annotation "org.opencontainers.image.version=${version}" \
        --annotation "org.opencontainers.image.source=https://github.com/cameronraysmith/vanixiets" \
        -t "${manifestName}"

      set +x
      echo "Manifest: ${manifestName}"
      ${craneExe} manifest "${manifestName}" | ${jqExe} .
      echo "Tags: ${toString parsedTags}"
      set -x
    ''}

    # Tag additional tags if present (skip the first tag which was already pushed)
    # crane tag is a registry-side metadata operation - no data transfer needed
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
