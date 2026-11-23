# Evaluation-time guard for the apm-deps fixed-output derivation (design D2, D3).
# Pure over manifest texts; callers read the committed files with readDir and
# readFile, so evaluating it needs no import-from-derivation.
{ lib }:
{ manifests, apmVersion }:
let
  fail = plugin: msg: throw "apm-deps guard: ${plugin}/apm.yml: ${msg}";

  # Lines of the top-level `dependencies:` -> `apm:` block, without blank or
  # comment-only lines.
  depLines =
    text:
    let
      meaningful = builtins.filter (l: builtins.match " *(#.*)?" l == null) (lib.splitString "\n" text);
      go =
        s: l:
        if builtins.match "[^ ].*" l != null then
          s
          // {
            inDeps = l == "dependencies:";
            inApm = false;
          }
        else if s.inDeps && builtins.match "  [^ ].*" l != null then
          s // { inApm = l == "  apm:"; }
        else if s.inDeps && s.inApm then
          s // { acc = s.acc ++ [ l ]; }
        else
          s;
    in
    (lib.foldl' go {
      inDeps = false;
      inApm = false;
      acc = [ ];
    } meaningful).acc;

  # YAML needs whitespace before a comment's `#`, so `owner/repo#sha` is kept.
  uncomment =
    l:
    let
      m = builtins.match "(.*[^ ])[ ]+#.*" l;
    in
    if m == null then l else lib.head m;

  # Groups `    - item` and `      key: value` lines into entries. Every other
  # shape (flow mappings, quoted scalars, anchors) fails closed.
  entries =
    plugin:
    lib.foldl' (
      acc: raw:
      let
        l = uncomment raw;
        item = builtins.match "    - (.*)" l;
        kv = builtins.match "      ([a-z_]+): (.*)" l;
        firstKv = if item == null then null else builtins.match "([a-z_]+): (.*)" (lib.head item);
      in
      if item != null && firstKv != null then
        acc ++ [ { ${lib.elemAt firstKv 0} = lib.elemAt firstKv 1; } ]
      else if item != null && builtins.match "[{\\[\"'&*!|>].*" (lib.head item) != null then
        fail plugin "unrecognised dependencies.apm line: '${raw}'"
      else if item != null then
        acc ++ [ { spec = lib.head item; } ]
      else if kv != null && acc != [ ] then
        lib.init acc ++ [ (lib.last acc // { ${lib.elemAt kv 0} = lib.elemAt kv 1; }) ]
      else
        fail plugin "unrecognised dependencies.apm line: '${raw}'"
    ) [ ];

  isLocal = e: e ? spec && builtins.match "\\.{1,2}/.*" e.spec != null;

  # "owner/name[/path]" -> { repo = "owner/name"; path = "path" or null; }
  splitRepo =
    s:
    let
      p = builtins.match "([^/]+/[^/]+)(/(.+))?" s;
    in
    {
      repo = lib.elemAt p 0;
      path = lib.elemAt p 2;
    };

  normalise =
    plugin: e:
    let
      shorthand = if e ? spec then builtins.match "([^#]+)#(.+)" e.spec else null;
      n =
        if e ? spec then
          (
            if shorthand == null then
              fail plugin "remote dep '${e.spec}' has no #ref"
            else
              splitRepo (lib.elemAt shorthand 0) // { ref = lib.elemAt shorthand 1; }
          )
        else if e ? git then
          removeAttrs e [ "git" ]
          // splitRepo e.git
          // {
            path = e.path or null;
            ref = e.ref or (fail plugin "remote dep '${e.git}' has no ref:");
          }
        else
          fail plugin "unrecognised remote dep entry ${builtins.toJSON e}";
    in
    if builtins.match "[0-9a-f]{40}" n.ref == null then
      fail plugin "remote dep '${n.repo}' ref '${n.ref}' is not a full 40-char commit SHA"
    else
      n // { inherit plugin; };

  remoteDeps = lib.concatLists (
    lib.mapAttrsToList (
      plugin: text:
      map (normalise plugin) (builtins.filter (e: !isLocal e) (entries plugin (depLines text)))
    ) manifests
  );

  refsByRepo = lib.mapAttrs (_: ds: lib.unique (lib.sort lib.lessThan (map (d: d.ref) ds))) (
    lib.groupBy (d: d.repo) remoteDeps
  );

  # Design D3 rules 1-4 for the repositories consumed one skill directory at a time.
  perSkill = {
    "obra/superpowers" = "skills/[a-z0-9-]+";
    "dfinity/icskills" = "skills/[a-z0-9-]+";
    "srid/agency" = "\\.apm/skills/[a-z0-9-]+";
  };
  sameRef = lib.all (
    d:
    if !(perSkill ? ${d.repo}) then
      true
    else if d.path == null then
      fail d.plugin "'${d.repo}' must be declared per skill-directory path"
    else if builtins.match perSkill.${d.repo} d.path == null then
      fail d.plugin "'${d.repo}/${d.path}' is not exactly one skill directory"
    else if builtins.length refsByRepo.${d.repo} > 1 then
      fail d.plugin "'${d.repo}' has more than one ref: ${toString refsByRepo.${d.repo}}"
    else
      true
  ) remoteDeps;

  key = {
    apm = apmVersion;
    deps = lib.sort (a: b: builtins.toJSON a < builtins.toJSON b) remoteDeps;
  };
in
assert sameRef;
{
  inherit remoteDeps refsByRepo;
  digest = builtins.substring 0 32 (builtins.hashString "sha256" (builtins.toJSON key));
}
