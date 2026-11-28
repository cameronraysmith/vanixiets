# flake.lib.compositionRoutes reads a configuration's composition from the
# import tree the module system records as its `graph`: every named module
# (a `flake.modules.<class>.<name>` definition) with the route by which it
# arrives. The route is the kind of its nearest named or host ancestor; a
# named module reached by none of them is `unknown`, which the
# compositionRoutes fleet obligation fails on every checked host.
# `just composition <host-or-home>` prints flake.lib.renderComposition.
{
  self,
  config,
  lib,
  ...
}:
let
  # A named module's definitions are loaded with the file
  # "<defining file>, via option flake.modules.<class>.<name>"; a name that
  # is not a plain identifier is written as a quoted string.
  namedModule =
    class: file:
    let
      m = builtins.match "(.*), via option flake\\.modules\\.${class}\\.(.*)" file;
      written = builtins.elemAt m 1;
    in
    if m == null then
      null
    else
      {
        defFile = builtins.elemAt m 0;
        name = if lib.hasPrefix "\"" written then builtins.fromJSON written else written;
      };

  # flake-parts loads each named module through a wrapper whose file is
  # "<flake>#modules.<class>.<name>"; it names no importing file.
  isWrapper = file: builtins.match ".*#modules\\..*" file != null;

  sourceFile =
    file:
    let
      own = builtins.head (lib.splitString ", via option " file);
      inStore = builtins.match "/nix/store/[^/]+/(.*)" own;
    in
    if inStore == null then own else builtins.head inStore;

  isClanService = file: builtins.match "Via (instances\\.|[^ ]+\\.perMachine ).*" file != null;

  isHostModule = class: name: builtins.match "machines/${class}/[^/]+" name != null;

  # The route a named module gives the named modules below it. A host
  # module defined outside modules/machines/ (mesh-dns.nix's per-resolver
  # definition) is generated, as is each `mesh-dns/<host>` module.
  routeBelow =
    class: named:
    if named.name == "base" then
      "base"
    else if isHostModule class named.name then
      if lib.hasInfix "/modules/machines/" named.defFile then "host" else "generated"
    else if lib.hasPrefix "mesh-dns/" named.name then
      "generated"
    else
      "include";

  # A named module with no named ancestor is the host's own module, a
  # standalone home's direct list (`home`), or one a clan service brings:
  # clan-core loads a role's per-instance module with the file
  # "Via instances.<instance>.roles.<role>.machines.<machine>" and a
  # service's per-machine module with "Via <service>.perMachine - machine=…".
  rootRoute =
    class: name:
    if class == "homeManager" then
      "home"
    else if isHostModule class name then
      "host"
    else
      "unknown";

  compositionRoutes =
    class: graph:
    let
      walk =
        {
          route,
          importer,
          above,
        }:
        node:
        let
          named = namedModule class node.file;
          entry = named != null && node.file != above;
          here = {
            inherit (named) name;
            route = if route == null then rootRoute class named.name else route;
            parentFile = if importer == null then "(configuration root)" else sourceFile importer;
            parentLabel = if importer == null then "(configuration root)" else importer;
          };
          below = {
            route =
              if entry then
                routeBelow class named
              else if isClanService node.file then
                "clan"
              else
                route;
            importer = if isWrapper node.file then importer else node.file;
            above = node.file;
          };
        in
        lib.optionals (!node.disabled) (lib.optional entry here ++ lib.concatMap (walk below) node.imports);
    in
    lib.concatMap (walk {
      route = null;
      importer = null;
      above = null;
    }) graph;

  # Every configuration holds its own host module, so a graph in which it is
  # not found means namedModule no longer matches the module system's labels
  # and the judge would otherwise pass with nothing to judge.
  routeFailures =
    class: host: graph:
    let
      routes = compositionRoutes class graph;
      hostModule = "machines/${class}/${host}";
    in
    lib.optional (!lib.any (r: r.name == hostModule) routes)
      "${hostModule} is not among ${host}'s named modules; namedModule in modules/lib/composition.nix no longer matches the module system's labels"
    ++ map (
      r:
      "${r.name} reaches ${host} from ${r.parentFile} by no known route; its nearest unnamed importer is labelled \"${r.parentLabel}\", and if that is a clan service, isClanService in modules/lib/composition.nix no longer matches clan-core's labels"
    ) (lib.filter (r: r.route == "unknown") routes);

  render =
    class: graph:
    let
      routes = compositionRoutes class graph;
      byName = lib.groupBy (r: r.name) routes;
      line =
        name:
        let
          rs = byName.${name};
        in
        "${name}\t${lib.concatStringsSep "," (lib.unique (map (r: r.route) rs))}\t${
          lib.concatStringsSep ", " (lib.unique (map (r: r.parentFile) rs))
        }";
    in
    lib.concatMapStrings (name: line name + "\n") (lib.attrNames byName);

  renderComposition =
    name:
    let
      host = config.flake.lib.hosts.${name};
      homes = lib.filter (n: lib.hasPrefix "${name}@" n) (lib.attrNames self.homeConfigurations);
      home = builtins.head homes;
    in
    if config.flake.lib.hosts ? ${name} then
      if host.class == "nixos" then
        "${name}: nixos host\n" + render "nixos" self.nixosConfigurations.${name}.graph
      else if host.class == "darwin" then
        "${name}: darwin host\n" + render "darwin" self.darwinConfigurations.${name}.graph
      else
        throw "${name} is a ${host.class} host and has no configuration"
    else if homes != [ ] then
      "${name}: home built for ${
        lib.concatMapStringsSep ", " (n: lib.removePrefix "${name}@" n) homes
      }\ncomposition of ${home}:\n"
      + render "homeManager" self.homeConfigurations.${home}.graph
    else
      throw "${name} is neither a host in flake.lib.hosts nor a home in homeConfigurations";
in
{
  flake.lib = {
    inherit compositionRoutes routeFailures renderComposition;
  };

  fleetObligations.compositionRoutes = {
    classes = [
      "nixos"
      "darwin"
    ];
    failures = _: _: [ ];
    graphFailures =
      class: name: _:
      routeFailures class name;
  };
}
