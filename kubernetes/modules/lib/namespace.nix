# Namespace enforcement helpers for easykubenix modules.
#
# Some upstream Helm charts (e.g. niks3, buildbot-nix-adjacent) render
# namespaced resources without templating `metadata.namespace`. When those
# charts are consumed through `helm.releases.<name>`, easykubenix cannot
# route the resulting objects into a target namespace and the manifest
# emitter rejects them. `enforceNamespace` patches such objects at render
# time, leaving cluster-scoped kinds untouched.
#
# The scope table is sourced from easykubenix's bundled API resource
# snapshot (`apiResources/v1.33.json`), exposed via
# `config.kubernetes.apiMappingFile`. Unknown kinds fail closed with an
# explicit throw rather than silently defaulting, so missing CRD harvesting
# is surfaced during evaluation instead of producing broken manifests.
#
# Usage from another easykubenix module:
#
#   helm.releases.my-chart.overrides = [
#     (config.lib.kubernetes.enforceNamespace cfg.namespace)
#   ];
{
  config,
  lib,
  ...
}:
let
  # Build `kind -> bool` table from the static API resource snapshot that
  # easykubenix already imports for `kubernetes.apiMappings`.
  scopeTable =
    let
      data = lib.importJSON config.kubernetes.apiMappingFile;
    in
    lib.listToAttrs (
      map (resource: {
        name = resource.kind;
        value = resource.namespaced;
      }) data.resources
    );

  isNamespacedKind =
    kind:
    if scopeTable ? ${kind} then
      scopeTable.${kind}
    else
      throw (
        "enforceNamespace: unknown kind '${kind}' (not present in "
        + "config.kubernetes.apiMappingFile). Extend the API resource "
        + "snapshot or register the kind explicitly before applying "
        + "namespace enforcement."
      );

  enforceNamespace =
    namespace: object:
    if (object.metadata.namespace or null) == null && isNamespacedKind object.kind then
      lib.recursiveUpdate object { metadata.namespace = namespace; }
    else
      object;
in
{
  options.lib.kubernetes = {
    isNamespacedKind = lib.mkOption {
      type = lib.types.functionTo lib.types.bool;
      readOnly = true;
      description = ''
        Predicate that returns `true` when the given Kubernetes `kind`
        represents a namespaced resource. Throws on unknown kinds.
      '';
    };

    enforceNamespace = lib.mkOption {
      type = lib.types.functionTo (lib.types.functionTo lib.types.attrs);
      readOnly = true;
      description = ''
        Curried helper `namespace -> object -> object`. When `object` is a
        namespaced resource lacking `metadata.namespace`, returns a copy
        with the namespace set; otherwise returns the object unchanged.
      '';
    };
  };

  config.lib.kubernetes = {
    inherit isNamespacedKind enforceNamespace;
  };
}
