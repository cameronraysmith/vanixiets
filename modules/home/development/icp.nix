{ config, ... }:
{
  flake.modules.homeManager.development.imports = [ config.flake.modules.homeManager.icp ];
  flake.modules.homeManager.icp =
    { pkgs, ... }:
    {
      # The Internet Computer toolchain the dfinity/icskills skills drive, pinned
      # here in place of the withheld autoupgrade-icp-cli skill. moc and
      # pocket-ic are absent on purpose: mops downloads the versions a project's
      # mops.toml [toolchain] pins.
      home.packages = [
        pkgs.icp-cli-bin
        pkgs.ic-wasm-bin
        pkgs.mops-bin
      ];
    };
}
