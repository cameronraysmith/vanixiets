# nix2container-native multi-arch manifest builder
#
# Creates and pushes multi-architecture Docker manifests using:
# - skopeo with nix: transport (from nix2container) to push individual arch images
# - podman to create and push the multi-arch manifest list
#
# This replaces flocken's ~400 line implementation with ~110-130 lines by:
# - Using nix2container's JSON manifests directly via skopeo nix: transport
# - Eliminating docker-archive tarball streaming (flocken's approach)
# - Pushing images to registry first, then creating manifest from digests
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

  # System to arch mapping for container platforms
  systemToArch = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  };

  # Generate per-arch image URIs for registry
  archImages = lib.mapAttrs' (
    system: image:
    let
      arch = systemToArch.${system};
    in
    lib.nameValuePair arch {
      inherit system image;
      tag = "${version}-${arch}";
      uri = "${registry.name}/${registry.repo}:${version}-${arch}";
    }
  ) images;

  manifestName = "${registry.name}/${registry.repo}:${lib.head parsedTags}";

  skopeoExe = lib.getExe skopeo;
  podmanExe = lib.getExe podman;

in
assert lib.assertMsg (images != { }) "At least one image must be provided";
assert lib.assertMsg (parsedTags != [ ]) "At least one tag must be set";

writeShellApplication {
  name = "multi-arch-manifest-${name}";
  runtimeInputs = [
    skopeo
    podman
    coreutils
    git
  ];

  text = ''
    function cleanup {
      set -x

      ${podmanExe} manifest rm "${manifestName}" || true
      ${podmanExe} logout "${registry.name}" || true
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
    set +x
    echo "Logging in to ${registry.name}"
    ${podmanExe} login \
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

    # Tag additional tags if present (skip the first tag which was already pushed)
    ${lib.concatMapStringsSep "\n" (tag: ''
      # Retag manifest list by copying from primary tag
      ${skopeoExe} copy \
        --dest-creds "${registry.username}:${registry.password}" \
        "docker://${registry.name}/${registry.repo}:${lib.head parsedTags}" \
        "docker://${registry.name}/${registry.repo}:${tag}"
    '') (lib.tail parsedTags)}

    set +x
    echo "Successfully pushed multi-arch manifest for ${name}"
    echo "Available at: ${registry.name}/${registry.repo}:${lib.head parsedTags}"
    ${lib.concatMapStringsSep "\n" (tag: ''
      echo "  Also tagged: ${registry.name}/${registry.repo}:${tag}"
    '') (lib.tail parsedTags)}
  '';
}
