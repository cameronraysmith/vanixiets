{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # compute
        argo-workflows
        argocd
        argocd-autopilot
        crane
        crossplane-cli
        ctlptl
        cue
        dive
        (google-cloud-sdk.withExtraComponents [
          google-cloud-sdk.components.gke-gcloud-auth-plugin
        ])
        hcloud
        holos # from nixpkgs (custom version available at .#debug.holos)
        # kcl
        kind
        krew
        kubectl
        kubectx
        kubernetes-helm
        kustomize
        lazydocker
        lima
        ngrok
        # skopeo: replaced by skopeo-nix2container in development-packages.nix
        step-cli
        tenv
        timoni
        vcluster
        # https://github.com/NixOS/nixpkgs/issues/381980
        # ❯ yarn dlx wrangler ...
        # wrangler
      ];
    };
}
