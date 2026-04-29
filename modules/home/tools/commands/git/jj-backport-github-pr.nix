{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "jj-backport-github-pr";
          runtimeInputs = with pkgs; [
            gh
            jujutsu
          ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Backport a GitHub PR by cherry-picking its merge commit

            Usage: jj-backport-github-pr PR

            Resolves the merge commit SHA from a GitHub PR and cherry-picks
            the merged changes into the current jujutsu working copy using
            the cherry-pick alias (which adds provenance trailers).

            Arguments:
              PR    GitHub PR number, URL, or owner/repo#N format

            Requirements:
              - GitHub CLI (gh) must be authenticated
              - jj cherry-pick alias must be configured
              - Repository must have the PR's commits fetched

            Examples:
              jj-backport-github-pr 123
              jj-backport-github-pr https://github.com/org/repo/pull/123
            HELP
                exit 0
                ;;
              "")
                echo "Error: PR identifier required" >&2
                echo "Usage: jj-backport-github-pr PR" >&2
                echo "Try 'jj-backport-github-pr --help' for more information." >&2
                exit 1
                ;;
            esac

            sha=$(gh pr view "$1" --json mergeCommit --jq .mergeCommit.oid)

            if [ -z "$sha" ]; then
              echo "Error: Could not resolve merge commit for PR: $1" >&2
              echo "The PR may not be merged yet." >&2
              exit 1
            fi

            echo "Backporting merge commit: $sha"
            jj cherry-pick -r "merged($sha)"
          '';
          meta.description = "Backport a GitHub PR by cherry-picking its merge commit";
        })
      ];
    };
}
