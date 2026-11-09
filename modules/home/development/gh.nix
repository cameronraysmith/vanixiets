{ ... }:
let
  content =
    personal:
    { pkgs, ... }:
    {
      programs.gh = {
        enable = true;
        extensions = [ pkgs.gh-stack ];
        gitCredentialHelper.enable = !personal;
        # `gh pr list` has no state column; `gh prs --state all` renders one.
        settings.aliases.prs = ''pr list --json number,title,headRefName,state,createdAt --template '{{tablerow "ID" "STATE" "TITLE" "BRANCH" "CREATED AT"}}{{range .}}{{tablerow (printf "#%v" .number | autocolor "green") (.state | autocolor "cyan") .title (.headRefName | autocolor "cyan") (timeago .createdAt)}}{{end}}{{tablerender}}' '';
      };
    };
in
{
  flake.modules.homeManager.development = content true;
  flake.modules.homeManager.gh = content false;
}
