# Per-host declaration of the shared ghq reference tree: whether this host shares
# one, which accounts read it, and the writer account that alone may change it.
# The NixOS and darwin adapters (modules/{nixos,darwin}/shared-reference-tree.nix)
# consume these options.
{ lib, ... }:
let
  options =
    isDarwin:
    { ... }:
    {
      options.services.shared-reference-tree = {
        enable = lib.mkEnableOption "one ghq reference tree shared by this host's participating accounts";
        participants = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Accounts that read the shared tree through the writer's group; none of them can write it.";
        };
        writer = lib.mkOption {
          type = lib.types.str;
          default = if isDarwin then "_ghq" else "ghq";
          description = "System account, and same-named group, that alone owns and writes the shared tree.";
        };
        root = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/ghq";
          description = "Shared ghq root.";
        };
        rootForms = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          readOnly = true;
          description = "Every path git may resolve the root to, canonical form first; each adapter defines it.";
        };
        writerId = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = "Darwin only: the operator-approved UID, also used as GID, of the writer account; NixOS allocates its own.";
        };
        allowedProtocols = lib.mkOption {
          type = lib.types.listOf (lib.types.strMatching "[a-z][a-z0-9+.-]*");
          default = [ "https" ];
          description = "Git protocols the writer may fetch over; every other protocol is refused.";
        };
      };
    };
  # A safe.directory entry trusts the shared tree's repositories, written by
  # another account, whenever it is `*` or a `<dir>/*` whose `<dir>` encloses the
  # root. `roots` lists every path form git may resolve the root to, canonical
  # form first; a participant must carry exactly the canonical root wildcard.
  safeDirectoriesConform =
    {
      roots,
      participant,
    }:
    entries:
    let
      encloses =
        entry:
        entry == "*"
        ||
          lib.hasSuffix "/*" entry
          && lib.any (
            root:
            let
              dir = lib.removeSuffix "*" entry;
            in
            dir != "${root}/" && lib.hasPrefix dir "${root}/"
          ) roots;
    in
    if participant then entries == [ "${lib.head roots}/*" ] else !(lib.any encloses entries);
  # The shared tree holds LFS pointer files exactly as committed: no account's git
  # runs an LFS filter there. The writer's request handler sets the same keys
  # (pkgs/by-name/ghq-shared/ghq-writer-handler.py, LFS_POLICY), and each
  # participant's git configuration sets them for every root form.
  lfsPolicy = {
    process = "";
    clean = "";
    smudge = "";
    required = false;
  };
  # Readers' git refuses every transport beneath the shared root: a read needing
  # content a copy lacks then fails at once with git's missing-object message
  # rather than starting an on-demand fetch into a tree it cannot write. The
  # writer's git reads no global or system configuration, so this never reaches it.
  transportPolicy.allow = "never";
  # lazygit reads .lazygit.yml in every ancestor of a repository; at the shared
  # root this turns off its start-up fetch for every copy.
  lazygitConfig = "git:\n  autoFetch: false\n";
  # Whether an include's condition can hold for a repository beneath one of
  # roots. Only a gitdir: or gitdir/i: pattern that is a literal absolute path is
  # judged, matching when it encloses a root or lies beneath one; any other
  # condition (a glob, a relative or ~/ pattern, onbranch:, hasconfig:) may hold
  # beneath the root and counts as matching.
  includeReachesRoot =
    roots: include:
    let
      condition = include.condition or null;
      parsed = builtins.match "gitdir(/i)?:(.*)" condition;
      fold = if lib.elemAt parsed 0 == null then lib.id else lib.toLower;
      pattern = fold (lib.elemAt parsed 1);
      literal = lib.hasPrefix "/" pattern && builtins.match ".*[*?[].*" pattern == null;
    in
    condition == null
    || parsed == null
    || !literal
    || lib.any (
      root: lib.hasPrefix pattern (fold "${root}/") || lib.hasPrefix (fold "${root}/") pattern
    ) roots;
  # Why a participant's Home Manager git configuration may let git use a
  # transport beneath the root, one line each; empty when it refuses every one.
  # It must have an include under gitdir:<form>/ setting protocol.allow to never
  # for each form git may resolve the root to, and no protocol.<name>.allow in
  # its settings, which outranks protocol.allow wherever it is set. An include
  # with inline contents whose condition can hold beneath the root must set
  # neither a protocol.<name>.allow nor a protocol.allow other than never, as
  # Home Manager writes the includes after the settings. An include given only
  # as a path is read by git, not by evaluation, and is not seen here.
  transportGaps =
    roots: git:
    let
      named = protocol: lib.attrNames (removeAttrs protocol [ "allow" ]);
      fromInclude =
        index: include:
        let
          protocol = include.contents.protocol or { };
          name = "include ${toString index} (${
            if (include.condition or null) == null then "unconditional" else include.condition
          })";
        in
        lib.optionals (includeReachesRoot roots include) (
          map (key: "${name} sets protocol.${key}.allow") (named protocol)
          ++ lib.optional (
            (protocol.allow or "never") != "never"
          ) "${name} sets protocol.allow to ${toString protocol.allow}"
        );
    in
    map (form: "no include under gitdir:${form}/ sets protocol.allow to never") (
      lib.filter (
        form:
        !lib.any (
          include:
          (include.condition or null) == "gitdir:${form}/"
          && (include.contents.protocol or null) == transportPolicy
        ) (git.includes or [ ])
      ) roots
    )
    ++ map (key: "its settings set protocol.${key}.allow") (named (git.settings.protocol or { }))
    ++ lib.concatLists (lib.imap1 fromInclude (git.includes or [ ]));
  refusesTransport = roots: git: transportGaps roots git == [ ];
in
{
  flake.modules.nixos.shared-reference-tree-options = options false;
  flake.modules.darwin.shared-reference-tree-options = options true;
  flake.lib.sharedReferenceTreeSafeDirectoriesConform = safeDirectoriesConform;
  flake.lib.sharedReferenceTreeLfsPolicy = lfsPolicy;
  flake.lib.sharedReferenceTreeTransportPolicy = transportPolicy;
  flake.lib.sharedReferenceTreeTransportGaps = transportGaps;
  flake.lib.sharedReferenceTreeRefusesTransport = refusesTransport;
  flake.lib.sharedReferenceTreeLazygitConfig = lazygitConfig;
}
