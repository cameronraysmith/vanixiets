# Package pins (openspec change automate-package-version-bumps, design D2, D3).
#
# `load ./pin.json { name = "<p>"; }` parses a package's pin, checks it against
# the pin type and the cross-field rules below, and returns `{ pin, pinPlan }`.
# `pinPlan <version>` is the fetch plan for that version, and it is the only
# place URL templates are expanded: the package builds its fetches from
# `pinPlan pin.version`, and the realizer reads every URL it fetches from
# `pinPlan <new version>`.
{ lib }:
let
  inherit (lib) mkOption types;

  option = type: mkOption { inherit type; };
  str = types.nonEmptyStr;
  sri = types.strMatching "sha256-[A-Za-z0-9+/]{43}=";
  commit = types.strMatching "[0-9a-f]{40}";

  # One `lib.types.attrTag` union whose tags each carry a submodule of `fields`.
  union =
    tags: types.attrTag (lib.mapAttrs (_: fields: option (types.submodule { options = fields; })) tags);

  # Applies the handler for the single tag of an attrTag value. A tag with no
  # handler is an evaluation error, so every union is handled in full.
  match =
    value: handlers:
    let
      tag = lib.head (lib.attrNames value);
    in
    handlers.${tag} value.${tag};

  repo = {
    owner = option str;
    repo = option str;
  };

  # How a release asset's hash is obtained, shared by `platformBinaries` and
  # `file`.
  checksum = union {
    upstreamFile = {
      urlTemplate = option str;
      format = option (union {
        sha256sum = { };
        jsonPointer.pointerTemplate = option str;
      });
    };
    prefetch = { };
  };

  pinModule = {
    options = {
      name = option str;
      version = option str;
      # The version realize-pin last completed, written as its final step. It
      # is accepted untyped and never checked here: checks.<system>.pin-realized
      # compares it with `version` at build time, because an evaluation error
      # drops the package from nixbot's evaluation instead of failing it
      # (design D4).
      realizedVersion = mkOption {
        type = types.anything;
        default = null;
      };
      source = option (union {
        githubRelease = repo // {
          tagTemplate = option str;
        };
        npm.package = option str;
        pypi.package = option str;
        vendorJson = {
          url = option str;
          pointer = option str;
        };
        vendorText = {
          url = option str;
          regex = option str;
        };
        gitCommit = repo // {
          branch = option str;
        };
      });
      artifacts = option (
        types.attrsOf (union {
          platformBinaries = {
            urlTemplate = option str;
            platforms = option (types.attrsOf str);
            checksum = option checksum;
            hashes = option (types.attrsOf sri);
          };
          sourceBuild = {
            fetcher = option (union {
              fetchFromGitHub = repo;
            });
            hash = option sri;
            depsHash = option (union {
              npm.hash = option sri;
              cargo.hash = option sri;
              go.hash = option sri;
              none = { };
            });
          };
          fileValue = {
            urlTemplate = option str;
            regex = option str;
            value = option str;
          };
          runtimeFetch.probeUrlTemplate = option str;
          # One release asset that is the same on every platform, such as a
          # JavaScript bundle or a source archive: its URL takes no
          # `{platform}`, and it has one hash.
          file = {
            urlTemplate = option str;
            checksum = option checksum;
            hash = option sri;
          };
        })
      );
      rev = mkOption {
        type = types.nullOr commit;
        default = null;
      };
      companions = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              path = option str;
              kind = option (union {
                apmRef.git = option str;
                fixedOutputHash = {
                  package = option str;
                  attr = option str;
                  # The attribute on `package` of the fixed-output derivation
                  # whose hash `attr` holds: one name, since nix-update reads
                  # `<package>.<name>.outputHash`. Defaults to empty so a
                  # missing value is reported with the pin's name below.
                  fodAttr = mkOption {
                    type = types.str;
                    default = "";
                  };
                };
                # The `nix hash path` of each of `skills`, the skills the
                # apm.yml entry `git: <git>` selects, as the compose installs
                # them, under `remote.<skill>` of a JSON skill index.
                remoteSkillHashes = {
                  git = option str;
                  skills = option (types.nonEmptyListOf str);
                };
              });
            };
          }
        );
        default = [ ];
      };
    };
  };

  # The module system's config carries `_module` at every submodule; the pin
  # is plain data, so it is dropped.
  plain =
    value:
    if lib.isAttrs value then
      lib.mapAttrs (_: plain) (removeAttrs value [ "_module" ])
    else if lib.isList value then
      map plain value
    else
      value;

  # Cross-field rules the option types cannot state, each as
  # "<option path>: <message>".
  problems =
    name: pin:
    let
      packageDir = "pkgs/by-name/${name}/";
      needsRev = lib.any (c: c.kind ? apmRef) pin.companions;
      apmGits = map (c: c.kind.apmRef.git) (lib.filter (c: c.kind ? apmRef) pin.companions);

      artifactProblems = lib.concatLists (
        lib.mapAttrsToList (
          artifact: entry:
          match entry {
            platformBinaries =
              pb:
              let
                platforms = lib.attrNames pb.platforms;
                hashed = lib.attrNames pb.hashes;
                missing = lib.subtractLists hashed platforms;
                extra = lib.subtractLists platforms hashed;
                at = "artifacts.${artifact}.platformBinaries";
              in
              lib.optional (platforms == [ ]) "${at}.platforms: declares no platform"
              ++ lib.optional (
                missing != [ ]
              ) "${at}.hashes: no hash for platform ${lib.concatStringsSep ", " missing}"
              ++ lib.optional (
                extra != [ ]
              ) "${at}.hashes: hash for undeclared platform ${lib.concatStringsSep ", " extra}";
            sourceBuild = _: [ ];
            fileValue = _: [ ];
            runtimeFetch = _: [ ];
            file = _: [ ];
          }
        ) pin.artifacts
      );

      companionProblems = lib.concatLists (
        lib.imap0 (
          i: c:
          let
            at = "companions.${toString i}.path";
            components = lib.splitString "/" c.path;
            tag = lib.head (lib.attrNames c.kind);
          in
          lib.optional (lib.hasPrefix "/" c.path) "${at}: ${c.path} is not repository-relative"
          ++ lib.optional (lib.elem ".." components) "${at}: ${c.path} has a `..` component"
          ++ lib.optional (
            !lib.hasPrefix "/" c.path && lib.any (p: p == "" || p == ".") components
          ) "${at}: ${c.path} has an empty or `.` component"
          ++ lib.optional (lib.hasPrefix packageDir c.path) "${at}: ${c.path} lies inside ${packageDir}"
          ++ lib.optional (
            lib.elem tag [
              "fixedOutputHash"
              "remoteSkillHashes"
            ]
            && !lib.hasSuffix ".json" c.path
          ) "${at}: ${c.path} is a ${tag} companion, which must name a JSON file"
          ++
            lib.optional
              (
                c.kind ? fixedOutputHash
                && builtins.match "[A-Za-z_][A-Za-z0-9_'-]*" c.kind.fixedOutputHash.fodAttr == null
              )
              "companions.${toString i}.kind.fixedOutputHash.fodAttr: `${c.kind.fixedOutputHash.fodAttr}' is not an attribute name"
          ++
            lib.optional (c.kind ? remoteSkillHashes && !lib.elem c.kind.remoteSkillHashes.git apmGits)
              "companions.${toString i}.kind.remoteSkillHashes.git: no apmRef companion of this pin has git ${c.kind.remoteSkillHashes.git}"
        ) pin.companions
      );
    in
    lib.optional (pin.name != name) "name: the pin names ${pin.name}, but package ${name} reads it"
    ++ lib.optional (pin.artifacts == { }) "artifacts: holds no artifact entry"
    ++ artifactProblems
    ++ companionProblems
    ++ lib.optional (
      pin.source ? gitCommit && builtins.match "[0-9a-f]{40}" pin.version == null
    ) "version: ${pin.version} is not a 40-character commit, which a gitCommit source pins"
    ++ lib.optional (needsRev && pin.rev == null) "rev: required by an apmRef companion, and absent"
    ++ lib.optional (!needsRev && pin.rev != null) "rev: present, but no apmRef companion needs it";

  # Replaces each `{var}` of `vars` in `template`, and fails on any `{word}`
  # left over, which names a variable this pin does not define.
  expand =
    context: vars: template:
    let
      names = lib.attrNames vars;
      expanded = builtins.replaceStrings (map (n: "{${n}}") names) (map (n: vars.${n}) names) template;
    in
    if builtins.match ".*\\{[A-Za-z]+}.*" expanded != null then
      throw "${context}: template ${template} uses a variable other than ${
        lib.concatMapStringsSep ", " (n: "{${n}}") names
      }"
    else
      expanded;

  plan =
    pin: version:
    let
      context = "pinPlan of ${pin.name}";
      tag = match pin.source {
        githubRelease = s: expand context { inherit version; } s.tagTemplate;
        npm = _: null;
        pypi = _: null;
        vendorJson = _: null;
        vendorText = _: null;
        gitCommit = _: null;
      };
      releaseVars = {
        inherit version;
      }
      // lib.optionalAttrs (tag != null) { inherit tag; };

      # One asset's `{ url; checksum; }` plan, with `vars` naming the template
      # variables its URL, checksum URL and pointer may use.
      asset =
        vars: urlTemplate: checksum:
        let
          url = expand context vars urlTemplate;
        in
        {
          inherit url;
          checksum = match checksum {
            upstreamFile = file: {
              upstreamFile = {
                url = expand context (vars // { inherit url; }) file.urlTemplate;
                format = match file.format {
                  sha256sum = _: { sha256sum.asset = baseNameOf url; };
                  jsonPointer = p: { jsonPointer.pointer = expand context vars p.pointerTemplate; };
                };
              };
            };
            prefetch = _: { prefetch = { }; };
          };
        };

      platformBinaries =
        pb:
        lib.mapAttrs (
          _system: platform: asset (releaseVars // { inherit platform; }) pb.urlTemplate pb.checksum
        ) pb.platforms;

      # A githubRelease pin fetches its release tag; a gitCommit pin's version
      # is the commit itself.
      gitRef = match pin.source {
        githubRelease = _: { inherit tag; };
        gitCommit = _: { rev = version; };
        npm = noGitRef;
        pypi = noGitRef;
        vendorJson = noGitRef;
        vendorText = noGitRef;
      };
      noGitRef =
        _:
        throw "${context}: fetchFromGitHub needs a release tag or a commit, which only a githubRelease or gitCommit source has";

      sourceBuild =
        sb:
        match sb.fetcher {
          fetchFromGitHub = f: {
            fetchFromGitHub = {
              inherit (f) owner repo;
            }
            // gitRef;
          };
        };
    in
    {
      inherit version tag;
      artifacts = lib.mapAttrs (
        _: entry:
        match entry {
          platformBinaries = pb: { platformBinaries = platformBinaries pb; };
          sourceBuild = sb: { sourceBuild = sourceBuild sb; };
          fileValue = fv: {
            fileValue = {
              url = expand context releaseVars fv.urlTemplate;
              inherit (fv) regex;
            };
          };
          runtimeFetch = rf: {
            runtimeFetch.probeUrl = expand context releaseVars rf.probeUrlTemplate;
          };
          file = f: { file = asset releaseVars f.urlTemplate f.checksum; };
        }
      ) pin.artifacts;
    };
in
{
  load =
    path:
    { name }:
    let
      file = "${toString path} (pin of package ${name})";
      evaluated = lib.evalModules {
        modules = [
          pinModule
          {
            _file = file;
            config = lib.importJSON path;
          }
        ];
      };
      checked = plain evaluated.config;
      errors = problems name checked;
      pin = builtins.deepSeq checked (
        if errors == [ ] then
          checked
        else
          throw "${file} is malformed:\n${lib.concatMapStrings (e: "  - ${e}\n") errors}"
      );
    in
    {
      inherit pin;
      pinPlan = plan pin;
    };

  # The rule a pin cannot check alone: each remoteSkillHashes companion's
  # `skills` equals the `skills:` of the apm.yml entries of its `git`, as the
  # apm-deps guard parses them (`apm-skills-compose.deps.guard.remoteDeps`), so
  # the realizer rewrites the hashes of exactly the skills that `ref:` moves.
  # Each problem is "<package>: <option path>: <message>"; pin-contract applies
  # it to every package pin.
  remoteSkillProblems =
    { pin, remoteDeps }:
    lib.concatLists (
      lib.imap0 (
        i: c:
        let
          inherit (c.kind.remoteSkillHashes) git skills;
          at = "${pin.name}: companions.${toString i}.kind.remoteSkillHashes.skills";
          entries = lib.filter (d: d.repo == git) remoteDeps;
          # `skills: [a, b]`; any other form is kept whole, so it never matches.
          selection =
            d:
            let
              flow = builtins.match "\\[(.*)]" (d.skills or "[]");
            in
            if flow == null then
              [ d.skills ]
            else
              lib.filter (s: s != "") (map lib.trim (lib.splitString "," (lib.head flow)));
          declared = lib.sort lib.lessThan (lib.concatMap selection entries);
          show = l: "[${lib.concatStringsSep ", " l}]";
        in
        if !(c.kind ? remoteSkillHashes) then
          [ ]
        else if entries == [ ] then
          [ "${at}: no apm.yml entry has git ${git}" ]
        else
          lib.optional (lib.sort lib.lessThan skills != declared)
            "${at}: ${show skills} differs from ${show declared}, the skills: of the apm.yml entries with git ${git}"
      ) pin.companions
    );
}
