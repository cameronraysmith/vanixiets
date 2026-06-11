{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "Q00";
  repo = "ouroboros";
  # rev is the v0.41.0 tag peel and must be bumped together with
  # pkgs/by-name/ouroboros (version 0.41.0). The obvious coupling
  # rev = "v${ouroboros.version}" cannot be expressed here: the agent-plugins/
  # sub-scope of packagesFromDirectoryRecursive shadows the top-level
  # ouroboros attr with this package itself (infinite recursion).
  rev = "91486ab5f4caa5a7d73a2864ccc8d1b10f7f95b7";
  hash = "sha256-HEZDOO+lPdIt6H+d73XL/yIslWDPfP120/aq1mhFOTM=";
}
