{ ... }:
{
  nixpkgsOverlays = [
    # Go 1.27 removed runtime internals that cockroachdb/swiss links to, so
    # otelcol-contrib 0.155.0 fails to compile once nixpkgs' default Go is 1.27.
    # The override applies only to 0.155.0: while nixpkgs' default Go is still
    # 1.26 it yields nixpkgs' own derivation (a cache hit), and once nixpkgs
    # moves past 0.155.0 (NixOS/nixpkgs#581121 bumps it) the package is left
    # untouched, so it is substituted from cache.nixos.org again rather than
    # built locally. Delete this file once nixpkgs carries a newer release.
    (final: prev: {
      opentelemetry-collector-releases =
        if prev.opentelemetry-collector-releases.otelcol-contrib.version == "0.155.0" then
          prev.opentelemetry-collector-releases.override {
            buildGoModule = final.buildGo126Module;
            go = final.go_1_26;
          }
        else
          prev.opentelemetry-collector-releases;
    })
  ];
}
