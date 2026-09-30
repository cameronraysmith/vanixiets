{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "Q00";
  repo = "ouroboros";
  # rev is the v0.55.3 tag peel and must be bumped together with
  # pkgs/by-name/ouroboros (version 0.55.3). The obvious coupling
  # rev = "v${ouroboros.version}" cannot be expressed here: the agent-plugins/
  # sub-scope of packagesFromDirectoryRecursive shadows the top-level
  # ouroboros attr with this package itself (infinite recursion).
  rev = "b08ab59da1e063a6e1bb1ca3120ea0219af53fda";
  hash = "sha256-bv5VNL02IBemsArje3smSj4VIYbfkCHZa9+r8Pr7r+0=";
}
