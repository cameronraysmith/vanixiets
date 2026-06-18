# Derived cognee endpoint record, the single source of truth read by the cognee
# server bind, the plugin env, the cognee-cli wrapper, the public-UI FQDN, and
# the terranix DNS record. Consolidated into this single file because flake.lib
# is lazyAttrsOf raw. Carries no MCP URL because the cognee MCP is dropped.
{ config, ... }:
let
  inherit (config.flake.lib.hosts) magnetite;
  apiPort = 9270;
in
{
  flake.lib.cognee = {
    inherit apiPort;
    meshApiUrl = "http://[${magnetite.zt}]:${toString apiPort}";
    publicFqdn = "kb.scientistexperience.net";
    userEmail = "cameron@scientistexperience.net";
  };
}
