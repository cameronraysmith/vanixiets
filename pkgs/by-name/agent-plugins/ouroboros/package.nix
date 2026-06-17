{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "Q00";
  repo = "ouroboros";
  # rev is the v0.42.0 tag peel and must be bumped together with
  # pkgs/by-name/ouroboros (version 0.42.0). The obvious coupling
  # rev = "v${ouroboros.version}" cannot be expressed here: the agent-plugins/
  # sub-scope of packagesFromDirectoryRecursive shadows the top-level
  # ouroboros attr with this package itself (infinite recursion).
  rev = "8e2219f433594a3a8101af37b55cdeafddc41c4d";
  hash = "sha256-VTUraTcZPj4ddxx9TRGy1FI398H+ZivWEARSe3wL9Po=";
}
