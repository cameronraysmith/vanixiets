{
  lib,
  writeShellApplication,
  uv,
}:

let
  version = "0.41.0";
in
writeShellApplication {
  name = "ouroboros";
  runtimeInputs = [ uv ];

  derivationArgs.version = version;

  # uvx fetches the exact-pinned extras (mcp, claude, tui) into the uv cache on
  # first run. A hermetic python build is impossible here: upstream pins extras
  # absent from nixpkgs.
  text = ''
    exec uvx --from "ouroboros-ai[mcp,claude,tui]==${version}" ouroboros "$@"
  '';

  meta = {
    description = "Specification-first agentic loop with MCP, Claude, and TUI integration";
    homepage = "https://github.com/Q00/ouroboros";
    license = lib.licenses.mit;
    mainProgram = "ouroboros";
  };
}
