{
  lib,
  writeShellApplication,
  uv,
}:

let
  version = "0.55.3";
in
writeShellApplication {
  name = "ouroboros";
  runtimeInputs = [ uv ];

  derivationArgs.version = version;

  # uvx fetches the exact-pinned extras (mcp, tui) into the uv cache on first
  # run. A hermetic python build is impossible here: upstream pins extras
  # absent from nixpkgs. Since 0.55 the [claude] extra (Agent SDK, MCP 1.x)
  # conflicts with [mcp] (MCP 2.x); upstream's recommended profile is
  # [mcp,tui] with the dependency-free claude-cli runtime.
  text = ''
    exec uvx --isolated --python '>=3.12' --from "ouroboros-ai[mcp,claude-cli,tui]==${version}" ouroboros "$@"
  '';

  meta = {
    description = "Specification-first agentic loop with MCP, Claude, and TUI integration";
    homepage = "https://github.com/Q00/ouroboros";
    license = lib.licenses.mit;
    mainProgram = "ouroboros";
  };
}
