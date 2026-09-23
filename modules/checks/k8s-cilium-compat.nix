# Cilium compatibility regulator: fails at evaluation time when the pinned
# cilium, gateway-api, k3s, and Argo CD versions, or the cilium helm values
# we set, form a combination the locked upstream sources declare broken.
#
# The rendered-manifest checks cannot see these failures. Every one of them
# renders cleanly and only breaks on a live cluster, where the cheapest
# signal so far was a phase 6 timeout in k3d-integration-ci. Each fact is read
# from the locked source, not restated here, so a bump re-derives the
# constraint instead of silently outgrowing it. A fact that can no longer be
# read throws, because a regulator that stops finding its input must not
# pass vacuously.
#
# Rules:
# - Gateway API needs kube-proxy replacement from the cilium release whose
#   operator says so (operator/pkg/gateway-api/cell.go); v1.18 still
#   accepted enable-node-port instead.
# - gateway-api-src must meet the minimum stated in cilium's
#   Documentation/operations/upgrade-current.inc, when one is stated.
# - The k3d cluster's k3s minor must be listed in cilium's
#   Documentation/network/kubernetes/compatibility.rst and, while Argo CD is
#   enabled there, in Argo CD's
#   docs/operator-manual/tested-kubernetes-versions.md.
{ self, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      k8sClusters,
      ...
    }:
    let
      inherit (self.inputs) cilium-src gateway-api-src argocd-src;

      fileLines = file: lib.splitString "\n" (builtins.readFile file);
      firstMatch =
        regex: file: lib.findFirst (m: m != null) null (map (builtins.match regex) (fileLines file));
      require =
        what: value:
        if value == null then
          throw "k8s-cilium-compat: cannot read ${what} from the locked source; the upstream layout changed, so re-derive this regulator"
        else
          value;
      readOne =
        what: regex: file:
        lib.head (require what (firstMatch regex file));

      ciliumVersion =
        readOne "the cilium chart version" "version: ([0-9.]+)"
          "${cilium-src}/install/kubernetes/cilium/Chart.yaml";

      gatewayCell = builtins.readFile "${cilium-src}/operator/pkg/gateway-api/cell.go";
      gatewayRequiresKpr =
        if lib.hasInfix "Gateway API support requires kube-proxy-replacement enabled" gatewayCell then
          true
        else if
          lib.hasInfix "Gateway API support requires either kube-proxy-replacement or enable-node-port enabled" gatewayCell
        then
          false
        else
          require "the Gateway API kube-proxy-replacement precondition in operator/pkg/gateway-api/cell.go" null;

      upgradeNotes = "${cilium-src}/Documentation/operations/upgrade-current.inc";
      gatewayApiMinimum =
        let
          m =
            if builtins.pathExists upgradeNotes then
              firstMatch ".*requires Gateway API v([0-9.]+) at a minimum.*" upgradeNotes
            else
              null;
        in
        if m == null then null else lib.head m;

      gatewayApiVersion =
        readOne "the gateway-api bundle version" " *gateway.networking.k8s.io/bundle-version: v([0-9.]+)"
          "${gateway-api-src}/config/crd/standard/gateway.networking.k8s.io_gateways.yaml";

      ciliumKubernetes = lib.splitString ", " (
        readOne "cilium's tested Kubernetes versions" "\\| ([0-9]+\\.[0-9]+(, [0-9]+\\.[0-9]+)*) +\\|.*"
          "${cilium-src}/Documentation/network/kubernetes/compatibility.rst"
      );

      argocdMinor = lib.versions.majorMinor (lib.trim (builtins.readFile "${argocd-src}/VERSION"));
      argocdKubernetes = map (lib.removePrefix "v") (
        lib.splitString ", " (
          readOne "Argo CD ${argocdMinor}'s tested Kubernetes versions"
            "\\| ${lib.escapeRegex argocdMinor} \\| (v[0-9.]+(, v[0-9.]+)*) \\|.*"
            "${argocd-src}/docs/operator-manual/tested-kubernetes-versions.md"
        )
      );

      k3sMinor =
        readOne "the k3s image in kubernetes/clusters/local-k3d/cluster.yaml"
          " *image: rancher/k3s:v([0-9]+\\.[0-9]+)\\.[0-9]+.*"
          ../../kubernetes/clusters/local-k3d/cluster.yaml;

      isTrue = value: value == true || value == "true";
      valuesViolations =
        values:
        let
          gatewayApi = isTrue (values.gatewayAPI.enabled or false);
          kpr = values.kubeProxyReplacement or false;
        in
        lib.optional (gatewayApi && gatewayRequiresKpr && !isTrue kpr) (
          "gatewayAPI.enabled with kubeProxyReplacement=${builtins.toJSON kpr}: cilium ${ciliumVersion} "
          + "runs its Gateway API controller only with kube-proxy replacement (operator/pkg/gateway-api/cell.go)"
        )
        ++
          lib.optional
            (gatewayApi && gatewayApiMinimum != null && lib.versionOlder gatewayApiVersion gatewayApiMinimum)
            "gateway-api-src v${gatewayApiVersion} is below cilium ${ciliumVersion}'s minimum v${gatewayApiMinimum} (Documentation/operations/upgrade-current.inc)";

      easykubenixValues =
        cluster:
        let
          config = k8sClusters.${cluster}.eval.config;
        in
        if config.cilium.enable then config.helm.releases.cilium.values else { };

      k3d = k8sClusters.local-k3d.eval.config;
      k3dKubernetesViolations =
        lib.optional (!builtins.elem k3sMinor ciliumKubernetes)
          "k3s ${k3sMinor} is outside cilium ${ciliumVersion}'s tested Kubernetes versions ${lib.concatStringsSep ", " ciliumKubernetes}"
        ++
          lib.optional (k3d.argocd.enable && !builtins.elem k3sMinor argocdKubernetes)
            "k3s ${k3sMinor} is outside Argo CD ${argocdMinor}'s tested Kubernetes versions ${lib.concatStringsSep ", " argocdKubernetes}";

      actual = {
        cilium-values = {
          local = valuesViolations (easykubenixValues "local");
          local-k3d = valuesViolations (easykubenixValues "local-k3d");
          nixidy-local-k3d =
            valuesViolations
              self.nixidyEnvs.${system}.local-k3d.config.applications.cilium.helm.releases.cilium.values;
        };
        kubernetes-version.local-k3d = k3dKubernetesViolations;
      };
    in
    {
      checks.k8s-cilium-compat = self.lib.mkStructuralCheck pkgs {
        name = "k8s-cilium-compat";
        inherit actual;
        expected = lib.mapAttrsRecursive (_: _: [ ]) actual;
      };
    };
}
