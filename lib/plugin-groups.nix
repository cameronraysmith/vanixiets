# Plugin groups under modules/home/ai/plugins, discovered from the source tree
# (readDir over a source path, so no import-from-derivation). `all` holds every
# group directory; `skills` the groups that carry `.apm/skills`.
let
  root = ../modules/home/ai/plugins;
  entries = builtins.readDir root;
  all = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
in
{
  inherit root all;
  skills = builtins.filter (n: builtins.pathExists (root + "/${n}/.apm/skills")) all;
}
