# tincapp's network directory files for one phone, rendered from the host
# registry; the operator places them in tincapp's network directory after
# joining by invitation. tincapp runs no hook scripts and configures its
# interface only from network.conf (https://tincapp.euxane.eu/doc.html).
# The other phones' packages override `phone`.
#
# An invitation carries only the inviter's host file, and StrictSubnets uses
# only the Subnets of local host files, so hosts/ holds every other member's
# host file from flake.lib.meshHostFiles, the same files every peer carries;
# the phone's own hosts/<phone>, written by the join with its key and port,
# is left out so copying hosts/ never replaces it. Re-copy hosts/ whenever a
# member is added or rekeyed.
{
  lib,
  runCommand,
  inputs,
  phone ? "pixel11",
}:
let
  inherit (inputs.self.lib)
    fleet
    mesh
    hosts
    meshHostFiles
    ;
  host = hosts.${phone};
  lines = lib.concatMapStrings (line: line + "\n");
  dialable = lib.attrNames (lib.filterAttrs (name: h: name != phone && h.endpoints != [ ]) hosts);
in
assert lib.assertMsg (host.class == "android") "tincapp-network: ${phone} is not an android member";
runCommand "tincapp-network-${phone}"
  {
    __structuredAttrs = true;
    networkConf = lines (
      [
        "Address = ${host.address}/128"
        "Route = ${mesh.prefixOf mesh.instance}"
      ]
      ++ map (resolver: "DNSServer = ${hosts.${resolver}.address}") mesh.resolvers
      ++ [
        "SearchDomain = ${fleet.domain}"
        # Android blocks every address family the VPN configures nothing for;
        # the mesh is IPv6 only, so let IPv4 (AF_INET) fall through to the
        # underlying network. IPv6 outside the mesh prefix matches no VPN
        # route and leaves through the underlying network as well.
        "AllowFamily = 2"
      ]
    );
    # tincapp is a C tinc 1.1 client, which defaults LocalDiscovery to no;
    # Broadcast = no matches every peer's tinc.conf.
    tincConf = lines (
      [
        "Name = ${phone}"
        "Mode = router"
        "ExperimentalProtocol = yes"
        "StrictSubnets = yes"
        "AutoConnect = yes"
        "Broadcast = no"
        "LocalDiscovery = yes"
      ]
      ++ map (name: "ConnectTo = ${name}") dialable
    );
    hostFiles = removeAttrs meshHostFiles [ phone ];
    meta.description = "tincapp network.conf, tinc.conf and hosts/ for ${phone} on the ${mesh.instance} mesh";
  }
  ''
    mkdir -p "$out/hosts"
    printf '%s' "$networkConf" > "$out/network.conf"
    printf '%s' "$tincConf" > "$out/tinc.conf"
    for name in "''${!hostFiles[@]}"; do
      printf '%s' "''${hostFiles[$name]}" > "$out/hosts/$name"
    done
  ''
