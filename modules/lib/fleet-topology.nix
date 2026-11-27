# The fleet map (openspec change diagram-fleet-topology): a pure function of
# the declared clan inventory, the member registry (flake.lib.hosts) and the
# declared facts (flake.lib.topologyFacts), returning the model and the four
# files committed under packages/docs/diagrams/topology/.
#
# It reads only the inventory fields named in the interface spec and never a
# NixOS or nix-darwin configuration, clanInternals or a package set, so
# evaluating it costs about as much as evaluating the inventory.
# `just topology-generate` writes `files`; checks.x86_64-linux.
# fleet-topology-fresh fails when the committed copies differ, and
# checks.x86_64-linux.eval-fleet-topology (fleet-topology.test.nix) tests the
# function over literal fixtures.
#
# Fleet networks are the instances whose module is tincr or zerotier. The
# zerotier branch (allowedIps matched to registry addresses, label
# `external`) is removed when ZeroTier is retired (migrate-mesh-to-tincr,
# group 12).
{ config, lib, ... }:
let
  inherit (builtins)
    attrNames
    concatLists
    concatMap
    elem
    filter
    isList
    listToAttrs
    sort
    toJSON
    ;
  inherit (lib)
    concatMapStrings
    concatStringsSep
    mapAttrs
    mapAttrsToList
    stringToCharacters
    unique
    ;

  overlayModules = [
    "tincr"
    "zerotier"
  ];

  sorted = sort builtins.lessThan;
  namesOf = x: if isList x then x else attrNames x;

  # D2 identifiers: every character outside [A-Za-z0-9_] becomes `_`.
  ident =
    s:
    concatMapStrings (c: if builtins.match "[A-Za-z0-9_]" c != null then c else "_") (
      stringToCharacters s
    );
  quote = s: "\"" + lib.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] s + "\"";

  # A role's `settings` in the declared inventory is a deferred module: the
  # declared attribute set sits inside `imports`, possibly nested and tagged
  # with `_file`. Collect every attribute-set layer; function modules carry
  # no declared literals and are skipped.
  settingLayers =
    s:
    if builtins.isAttrs s then
      [
        (removeAttrs s [
          "imports"
          "_file"
        ])
      ]
      ++ concatMap settingLayers (s.imports or [ ])
    else
      [ ];
  settingValues = name: s: concatMap (l: lib.optional (l ? ${name}) l.${name}) (settingLayers s);
  list = xs: if xs == [ ] then "—" else concatStringsSep ", " xs;

  mkFleetTopology =
    {
      inventory,
      hosts,
      facts,
    }:
    let
      machines = mapAttrs (_: m: {
        class = m.machineClass;
        tags = sorted (namesOf (m.tags or [ ]));
        description = m.description or null;
      }) inventory.machines;
      machineNames = sorted (attrNames machines);

      # Role membership is flake.lib.inventoryMembersIn, clan's rule, over this
      # inventory; a named machine outside the inventory is left out.
      membersOf =
        instance: role:
        filter (n: machines ? ${n}) (config.flake.lib.inventoryMembersIn inventory.machines instance role);

      instances = mapAttrs (_: i: {
        module = i.module.name;
        roles = mapAttrs (role: _: membersOf i role) (i.roles or { });
      }) inventory.instances;

      everyHost = sorted (
        concatMap (
          i:
          concatMap (r: if instances.${i}.roles.${r} == machineNames then [ "${i}/${r}" ] else [ ]) (
            attrNames instances.${i}.roles
          )
        ) (attrNames instances)
      );

      addressOwner = listToAttrs (
        concatMap (
          n:
          if (hosts.${n}.zerotier.address or null) != null then
            [
              {
                name = hosts.${n}.zerotier.address;
                value = n;
              }
            ]
          else
            [ ]
        ) (attrNames hosts)
      );

      networkMembers =
        name:
        let
          inst = inventory.instances.${name};
          roles = instances.${name}.roles;
          fromRoles = concatMap (
            r:
            map (m: {
              inherit m;
              label = r;
            }) roles.${r}
          ) (attrNames roles);
          devices =
            if inst.module.name == "tincr" then
              map (m: {
                inherit m;
                label = "device";
              }) (unique (concatMap attrNames (settingValues "devices" (inst.roles.peer.settings or { }))))
            else
              [ ];
          external =
            if inst.module.name == "zerotier" then
              map
                (addr: {
                  m =
                    addressOwner.${addr}
                      or (throw "fleet-topology: zerotier allowedIps entry ${addr} matches no flake.lib.hosts member");
                  label = "external";
                })
                (
                  concatMap (c: concatLists (settingValues "allowedIps" (c.settings or { }))) (
                    lib.attrValues (inst.roles.controller.machines or { })
                  )
                )
            else
              [ ];
          all = fromRoles ++ devices ++ external;
        in
        listToAttrs (
          map (m: {
            name = m;
            value = concatStringsSep "," (sorted (unique (map (e: e.label) (filter (e: e.m == m) all))));
          }) (unique (map (e: e.m) all))
        );

      networks = listToAttrs (
        map (name: {
          inherit name;
          value = {
            module = instances.${name}.module;
            members = networkMembers name;
          };
        }) (filter (i: elem instances.${i}.module overlayModules) (attrNames instances))
      );

      unknownFacts = filter (k: !(hosts ? ${k})) (attrNames facts);
      checkedFacts =
        if unknownFacts == [ ] then
          mapAttrs (_: f: {
            services = map (s: {
              inherit (s) name;
              hostnames = s.hostnames or [ ];
              ports = s.ports or [ ];
            }) (f.services or [ ]);
          }) facts
        else
          throw "fleet-topology: topologyFacts key ${builtins.head unknownFacts} is not a flake.lib.hosts member";

      publicNames = sort (a: b: a.hostname < b.hostname) (
        concatMap (
          h:
          map (hostname: {
            inherit hostname;
            host = h;
            service = null;
            ports = [ ];
          }) (hosts.${h}.endpoints or [ ])
        ) (attrNames hosts)
        ++ concatMap (
          h:
          concatMap (
            s:
            map (hostname: {
              inherit hostname;
              host = h;
              service = s.name;
              inherit (s) ports;
            }) s.hostnames
          ) checkedFacts.${h}.services
        ) (attrNames checkedFacts)
      );

      model = {
        inherit
          machines
          instances
          networks
          everyHost
          publicNames
          ;
        facts = checkedFacts;
      };

      # Role memberships of one machine, fleet-wide ones excluded.
      rolesOf =
        n:
        concatMap (
          i:
          concatMap (
            r:
            let
              key = "${i}/${r}";
            in
            if elem n instances.${i}.roles.${r} && !(elem key everyHost) then [ key ] else [ ]
          ) (sorted (attrNames instances.${i}.roles))
        ) (sorted (attrNames instances));
      servicesOf = n: (checkedFacts.${n} or { services = [ ]; }).services;
      serviceLabel =
        s:
        concatStringsSep "\\n" (
          [ s.name ]
          ++ s.hostnames
          ++ lib.optional (s.ports != [ ]) ("port " + concatStringsSep ", " (map toString s.ports))
        );
      networksOf =
        n:
        concatMap (
          net: if networks.${net}.members ? ${n} then [ "${net} (${networks.${net}.members.${n}})" ] else [ ]
        ) (sorted (attrNames networks));

      header = "generated by flake.lib.fleetTopology from the clan inventory, flake.lib.hosts and flake.lib.topologyFacts; run `just topology-generate`, never edit";

      fleetJson =
        let
          entries =
            mapAttrsToList (n: v: {
              name = "machine/${n}";
              value = v;
            }) machines
            ++ mapAttrsToList (n: v: {
              name = "instance/${n}";
              value = v;
            }) instances
            ++ mapAttrsToList (n: v: {
              name = "network/${n}";
              value = v;
            }) networks
            ++ mapAttrsToList (n: v: {
              name = "facts/${n}";
              value = v;
            }) checkedFacts;
          ordered = sort (a: b: a.name < b.name) entries;
        in
        "{\n" + concatStringsSep ",\n" (map (e: "  ${toJSON e.name}: ${toJSON e.value}") ordered) + "\n}\n";

      classTitle =
        c:
        if c == "nixos" then
          "NixOS hosts"
        else if c == "darwin" then
          "darwin hosts"
        else
          "${c} hosts";
      classes = sorted (unique (map (n: machines.${n}.class) machineNames));

      title = text: ''
        title: ${quote text} {
          shape: text
          near: top-center
          style.font-size: 28
        }
      '';

      fleetD2 =
        "# ${header}\n"
        + title "Fleet placement"
        + "direction: down\n"
        + concatMapStrings (
          c:
          "${ident c}: ${quote (classTitle c)} {\n  grid-columns: 3\n"
          + concatMapStrings (
            n:
            "  ${ident n}: ${quote n} {\n    grid-columns: 2\n"
            + concatMapStrings (k: "    r_${ident k}: ${quote k}\n") (rolesOf n)
            + concatMapStrings (
              s: "    s_${ident s.name}: ${quote (serviceLabel s)} {\n      style.fill: \"#FFF4D6\"\n    }\n"
            ) (servicesOf n)
            + "  }\n"
          ) (filter (n: machines.${n}.class == c) machineNames)
          + "}\n"
        ) classes
        + "every_host: \"on every host\" {\n"
        + concatMapStrings (k: "  r_${ident k}: ${quote k}\n") everyHost
        + "}\n"
        + ''
          key: "Key" {
            host: "host: a box holding its service roles and declared services"
            role: "service role: instance/role, from the clan inventory"
            declared: "declared service: name, public hostnames, ports (flake.lib.topologyFacts)" {
              style.fill: "#FFF4D6"
            }
          }
        '';

      netNodes = sorted (
        unique (
          concatMap (net: attrNames networks.${net}.members) (attrNames networks)
          ++ map (p: p.host) publicNames
        )
      );
      networkD2 =
        "# ${header}\n"
        + title "Fleet networks and public edge"
        + "direction: right\n"
        + concatMapStrings (net: "net_${ident net}: ${quote net} {\n  shape: cloud\n}\n") (
          sorted (attrNames networks)
        )
        + concatMapStrings (m: "m_${ident m}: ${quote m}\n") netNodes
        + concatMapStrings (
          net:
          concatMapStrings (
            m:
            "m_${ident m} -> net_${ident net}: ${
              quote networks.${net}.members.${m}
            } {\n  style.stroke-dash: 3\n}\n"
          ) (sorted (attrNames networks.${net}.members))
        ) (sorted (attrNames networks))
        + "internet: \"internet\" {\n  shape: cloud\n}\n"
        + concatMapStrings (p: "internet -> m_${ident p.host}: ${quote p.hostname}\n") publicNames
        + "key: \"Key\" {\n"
        + concatMapStrings (
          net: "  k_${ident net}: ${quote "${net}: ${networks.${net}.module} network"}\n"
        ) (sorted (attrNames networks))
        + "  member: \"dashed edge: membership, labelled with the member's role\"\n"
        + "  public: \"solid edge from internet: a public hostname and the host answering it\"\n"
        + "}\n";

      fleetTable =
        "<!-- ${header} -->\n\n"
        + "| Host | Platform | Service roles | Declared services | Fleet networks |\n"
        + "|---|---|---|---|---|\n"
        + concatMapStrings (
          n:
          "| ${n} | ${machines.${n}.class} | ${list (rolesOf n)} | ${
            list (map (s: s.name) (servicesOf n))
          } | ${list (networksOf n)} |\n"
        ) machineNames
        + "\nService roles held by every host: ${list everyHost}.\n\n"
        + "| Fleet network | Module | Members |\n"
        + "|---|---|---|\n"
        + concatMapStrings (
          net:
          "| ${net} | ${networks.${net}.module} | ${
            list (
              map (m: "${m} (${networks.${net}.members.${m}})") (sorted (attrNames networks.${net}.members))
            )
          } |\n"
        ) (sorted (attrNames networks))
        + "\n| Public hostname | Host | Service | Ports |\n"
        + "|---|---|---|---|\n"
        + concatMapStrings (
          p:
          "| ${p.hostname} | ${p.host} | ${
            if p.service == null then "—" else p.service
          } | ${list (map toString p.ports)} |\n"
        ) publicNames;
    in
    {
      inherit model;
      files = {
        "fleet.json" = fleetJson;
        "fleet.d2" = fleetD2;
        "network.d2" = networkD2;
        "fleet-table.md" = fleetTable;
      };
    };
in
{
  flake.lib.mkFleetTopology = mkFleetTopology;
  flake.lib.fleetTopology = mkFleetTopology {
    inherit (config.flake.clan) inventory;
    inherit (config.flake.lib) hosts;
    facts = config.flake.lib.topologyFacts;
  };
}
