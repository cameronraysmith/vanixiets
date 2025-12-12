# Tools aggregate directory marker
# Individual modules in tools/ are auto-discovered by import-tree
# and merged into homeManager.tools aggregate namespace
{ ... }:
{
  # Namespace stub for import-tree aggregate discovery
  # All configuration in tools/*.nix files:
  # - awscli.nix (AWS CLI)
  # - k9s.nix (Kubernetes UI)
  # - pandoc.nix (document conversion)
  # - nix.nix (Nix configuration)
  # - nixpkgs.nix (nixpkgs config)
  # - gpg.nix (GPG tools)
  # - macchina.nix (system info)
  # - tealdeer.nix (tldr pages)
  # - bottom.nix (system monitor)
  # - bat.nix (better cat)
  # - agents-md.nix (agent documentation)
  # - texlive.nix (TeX/LaTeX distribution)
  # - typst.nix (Typst typesetting with CeTZ/Fletcher)
  # - claude-code-wrappers.nix (GLM wrapper)
  # - commands/ (custom shell commands)
  flake.modules.homeManager.tools = { ... }: { };
}
