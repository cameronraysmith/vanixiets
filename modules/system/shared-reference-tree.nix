# Per-host declaration of the shared ghq reference tree: which accounts read it,
# and the writer account that alone may change it. A host shares one by
# importing the NixOS or darwin adapter (modules/{nixos,darwin}/shared-reference-tree.nix),
# which consume these options.
{ lib, ... }:
let
  # The shared root as readers' gitdir: includes and the evaluation check use
  # it, each appending `/` to the path: git applies an include only when the
  # pattern spells the path a repository is reached by, so a root with a
  # trailing slash, an empty, `.` or `..` component, or a relative one never
  # matches, and an empty root makes the pattern `gitdir:/`, which matches every
  # repository. git reads `*`, `?`, `[` and `\` in the pattern as glob syntax,
  # so a root holding one is matched as a pattern, not as its own path: `[`
  # and `\` miss the root, `*` and `?` also reach paths beside it; and a
  # subsection name, the include's condition, cannot hold a newline. A
  # component holds none of them.
  rootType =
    let
      rest = "[^/*?[\\\n]";
      first = "[^/.*?[\\\n]";
    in
    lib.types.strMatching "(/(${first}${rest}*|\\.${first}${rest}*|\\.\\.${rest}+))+"
    // {
      description = "absolute path with no trailing slash, no empty, `.` or `..` component, and no `*`, `?`, `[`, `\\` or newline";
    };
  options =
    isDarwin:
    { ... }:
    {
      options.services.shared-reference-tree = {
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
          type = rootType;
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
  # Whether an include's condition can hold for a repository reached by one of
  # paths: every form of the root and every link into it. git matches a gitdir:
  # pattern against the path a repository is reached by as well as its resolved
  # path, so a pattern enclosing a link, the link's own directory and its
  # ancestors included, holds there. Only a gitdir: or gitdir/i: pattern that is
  # a literal absolute path, or one under ~/ expanded with home, is judged,
  # matching when it encloses one of paths or lies beneath one; any other
  # condition (a glob, a relative pattern, onbranch:, hasconfig:) may hold there.
  # Both sides are compared with ASCII letter case folded, gitdir: as gitdir/i:,
  # on every platform: darwin's file system ignores case, so a repository is
  # reached by every spelling of its path. On Linux a pattern differing from one
  # of paths only in case therefore counts as reaching though it cannot apply.
  includeReachesRoot =
    { paths, home }:
    include:
    let
      condition = include.condition or null;
      parsed = builtins.match "gitdir(/i)?:(.*)" condition;
      written = lib.elemAt parsed 1;
      expanded =
        if lib.hasPrefix "~/" written && home != null then
          "${home}/${lib.removePrefix "~/" written}"
        else
          written;
      pattern = lib.toLower expanded;
      literal = lib.hasPrefix "/" pattern && builtins.match ".*[*?[\\].*" pattern == null;
    in
    condition == null
    || parsed == null
    || !literal
    || lib.any (
      path:
      let
        under = lib.toLower "${path}/";
      in
      lib.hasPrefix pattern under || lib.hasPrefix under pattern
    ) paths;
  # The settings git reads from one Home Manager git attribute set, as
  # lib.generators.toGitINI writes it: each leaf at path a.b.….key is the
  # variable key of the section named by the rest, `[a "b.…"]`, or of a section
  # written whole as `a "b"`. Section and variable names are compared in lower
  # case, as git compares them; the subsection keeps its case. A leaf outside
  # any section, or a section name this cannot split, is unreadable.
  gitEntries =
    attrs:
    let
      leaves =
        path: value:
        if lib.isAttrs value && !lib.isDerivation value then
          lib.concatLists (lib.mapAttrsToList (name: leaves (path ++ [ name ])) value)
        else
          [ { inherit path value; } ];
      entry =
        { path, value }:
        let
          sectionName = lib.concatStringsSep "." (lib.init path);
          quoted = builtins.match ''([^ "]+) "([^"]*)"'' sectionName;
          dotted = builtins.match "([^.\"]+)\\.([^\"]*)" sectionName;
          split = if quoted != null then quoted else dotted;
          values = lib.toList value;
        in
        if
          builtins.length path < 2
          || (split == null && lib.hasInfix ''"'' sectionName)
          || lib.any (v: lib.isAttrs v || lib.isList v) values
        then
          { unreadable = lib.concatStringsSep "." path; }
        else
          {
            section = lib.toLower (if split == null then sectionName else lib.head split);
            subsection = if split == null then null else lib.elemAt split 1;
            key = lib.toLower (lib.last path);
            inherit values;
          };
    in
    map entry (leaves [ ] attrs);
  # What in one attribute set of git settings may let git use a transport, each
  # finding prefixed by where: any protocol.<name>.allow, anything unreadable,
  # and, unless admitAllow, a protocol.allow other than never.
  protocolFindings =
    { where, admitAllow }:
    attrs:
    if !lib.isAttrs attrs then
      [ "${where} has a shape this check cannot read" ]
    else
      lib.concatMap (
        entry:
        if entry ? unreadable then
          [ "${where} sets ${entry.unreadable}, which this check cannot read as a git setting" ]
        else if entry.section != "protocol" || entry.key != "allow" then
          [ ]
        else if entry.subsection != null then
          [ "${where} sets protocol.${entry.subsection}.allow" ]
        else
          map (value: "${where} sets protocol.allow to ${toString value}") (
            lib.filter (value: !admitAllow && toString value != "never") entry.values
          )
      ) (gitEntries attrs);
  # Why a participant's git, as its Home Manager configuration home declares it,
  # may use a transport beneath the shared root, one line each; empty when it
  # refuses every one. roots are the forms git may resolve the root to. It must
  # have an include under gitdir:<form>/ setting protocol.allow to never for each
  # of them, and no protocol.<name>.allow in its settings (programs.git.iniContent,
  # and programs.git.settings in either shape Home Manager accepts, one attribute
  # set or a list of them), which outranks protocol.allow wherever it is set. An
  # include with inline contents whose condition can hold for a repository
  # reached by a root form, a form the account's own module declares, or its
  # ~/ghq link, must set neither a protocol.<name>.allow nor a protocol.allow
  # other than never, as Home Manager writes the includes after the settings.
  # An include given only as a path, as an include entry or through include.path
  # or includeIf in the settings, is read by git, not by evaluation, and is not
  # seen here.
  transportGaps =
    roots: home:
    let
      git = home.programs.git or { };
      shared = home.programs.ghq-shared or { };
      reach = {
        paths = lib.unique (
          roots ++ shared.forms or [ ] ++ lib.optional ((shared.link or null) != null) shared.link
        );
        home = home.home.homeDirectory or null;
      };
      settings = git.settings or { };
      fragments = if builtins.isList settings then settings else [ settings ];
      fromInclude =
        index: include:
        lib.optionals (includeReachesRoot reach include) (
          protocolFindings {
            where = "include ${toString index} (${
              if (include.condition or null) == null then "unconditional" else include.condition
            })";
            admitAllow = false;
          } (include.contents or { })
        );
    in
    lib.unique (
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
      # protocol.allow in the settings is admitted whatever its value: the
      # includes, written after the settings, set it to never.
      ++ lib.concatMap (protocolFindings {
        where = "a settings entry";
        admitAllow = true;
      }) ([ (git.iniContent or { }) ] ++ fragments)
      ++ lib.concatLists (lib.imap1 fromInclude (git.includes or [ ]))
    );
  refusesTransport = roots: home: transportGaps roots home == [ ];
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
